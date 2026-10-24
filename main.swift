// Rowline: every window in one horizontal row, side by side.
// Menu bar app: Swift/AppKit, no dependencies, no network.
// Click the icon to open the panel; ⌃⌥⌘F opens it from anywhere; reopening Rowline (Spotlight, Launchpad) does the same.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = item.button {
            b.target = self
            b.action = #selector(clic)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])   // right click (or ⌃click): the menu
            Pannello.shared.bottone = b
        }
        aggiornaIcona()
        let motore = Motore.shared
        motore.avvia()
        Tasti.shared.registra()
        Gesto.shared.avvia()
        Barra.shared.avvia()
        Foglio.shared.avvia()
        // the icon turns off with Rowline, and the gesture starts as soon as the Accessibility permission arrives
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.aggiornaIcona()
            if Gesto.shared.modo == .opzione { Gesto.shared.avvia() }
        }
        // first launch without permission: ask right away and open the panel that explains it
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Pannello.shared.apri() }
        }
    }

    private var ultimaIcona: Bool?
    private func aggiornaIcona() {
        let on = Motore.shared.acceso && AXIsProcessTrusted()
        guard on != ultimaIcona, let b = item.button else { return }
        ultimaIcona = on
        let img = NSImage(systemSymbolName: on ? "rectangle.split.3x1.fill" : "rectangle.split.3x1", accessibilityDescription: "Rowline")
        img?.isTemplate = true
        b.image = img
        b.appearsDisabled = !on
    }

    @objc private func clic() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { mostraMenu() } else { Pannello.shared.alterna() }
    }

    /// The right-click menu: everyday things without opening the panel.
    private func mostraMenu() {
        let m = Motore.shared, k = Tasti.shared
        let menu = NSMenu()
        func voce(_ t: String, _ simbolo: String? = nil, _ a: Azione? = nil, _ f: @escaping () -> Void) {
            let i = NSMenuItem(title: t, action: #selector(Voce.scatta(_:)), keyEquivalent: "")
            let v = Voce(f); i.target = v; i.representedObject = v
            if let simbolo { i.image = NSImage(systemSymbolName: simbolo, accessibilityDescription: nil) }
            if let a, let c = k.combo[a], c.mod != 0, let (tasto, mod) = c.equivalente { i.keyEquivalent = tasto; i.keyEquivalentModifierMask = mod }
            menu.addItem(i)
        }
        voce("Open Rowline", "rectangle.split.3x1", .pannello) { Pannello.shared.apri() }
        menu.addItem(.separator())
        voce(m.acceso ? "Turn off" : "Turn on", "power", .pausa) { m.acceso.toggle() }
        voce("Tidy up windows", "arrow.triangle.2.circlepath") { m.adotta() }
        if let a = m.appInFuoco, !m.escluse.contains(a.bundle) {
            voce("Leave \(a.nome) free", "pin.slash") { m.liberaApp(a.bundle) }
        }
        menu.addItem(.separator())
        if !m.postazioni.isEmpty {
            menu.addItem(.separator())
            for (i, p) in m.postazioni.enumerated() {
                voce(p.nome, "square.stack", i == 0 ? .postazione1 : i == 1 ? .postazione2 : i == 2 ? .postazione3 : nil) { m.applica(p) }
            }
        }
        menu.addItem(.separator())
        voce(Dimostrazione.shared.inCorso ? "Stop the demo" : "Demo", "play.rectangle") {
            Dimostrazione.shared.inCorso ? Dimostrazione.shared.ferma() : Dimostrazione.shared.avvia()
        }
        voce("Shortcut sheet", "keyboard") { Pannello.shared.stato.scheda = .tasti; Pannello.shared.apri() }
        voce("How it works", "questionmark.circle") { Pannello.shared.stato.scheda = .guida; Pannello.shared.apri() }
        if !AXIsProcessTrusted() {
            voce("Grant permission", "hand.raised") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        menu.addItem(.separator())
        voce("Quit Rowline", "xmark.circle") { NSApp.terminate(nil) }
        item.menu = menu
        item.button?.performClick(nil)      // opens the menu under the icon
        item.menu = nil                     // and left click goes back to the panel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Pannello.shared.apri()
        return false
    }

    // When Rowline quits, no window may stay parked in the corner
    func applicationWillTerminate(_ n: Notification) { Motore.shared.libera() }
}

final class Voce: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func scatta(_ s: Any?) { f() }
}

// Quit from outside (pkill, build.sh, logout): before exiting, put the parked windows back in view.
signal(SIGTERM, SIG_IGN)
let segnale = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
segnale.setEventHandler { NSApp.terminate(nil) }
segnale.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
