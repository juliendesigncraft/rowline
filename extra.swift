// Rowline: extras. Shortcuts sheet, on-screen keys, demo, window previews in the bar.

import AppKit
import SwiftUI
import ScreenCaptureKit

// MARK: - Shortcuts sheet: hold ⌃⌥⌘ for almost a second, let go and it disappears

final class Foglio {
    static let shared = Foglio()
    private var pannello: NSPanel?
    private var attesa: DispatchWorkItem?
    private var monitor: [Any] = []

    func avvia() {
        guard monitor.isEmpty else { return }
        let f: (NSEvent) -> Void = { [weak self] e in self?.modificatori(e.modifierFlags) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: f) { monitor.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { f($0); return $0 }) { monitor.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in self?.annulla() }) { monitor.append(m) }
    }

    private func modificatori(_ fl: NSEvent.ModifierFlags) {
        let m = fl.intersection([.control, .option, .command, .shift])
        if m == [.control, .option, .command] {
            attesa?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.mostra() }
            attesa = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: w)
        } else {
            annulla()
        }
    }

    /// A real key was pressed: it was a shortcut, no need for the sheet.
    func annulla() {
        attesa?.cancel(); attesa = nil
        guard let p = pannello, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    func mostraOra() { attesa?.cancel(); mostra() }

    private func mostra() {
        let p = pannello ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false   // no dark outline: the view draws the shadow
            p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.ignoresMouseEvents = true
            return p
        }()
        pannello = p
        let host = NSHostingView(rootView: VistaFoglio().environmentObject(Tasti.shared).environmentObject(Tinta.shared))
        p.contentView = host
        let size = host.fittingSize
        let m = NSEvent.mouseLocation
        let sc = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main!
        p.setFrame(NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
    }
}

struct VistaFoglio: View {
    @EnvironmentObject var k: Tasti
    @EnvironmentObject var t: Tinta

    private let gruppi: [[Azione]] = [
        [.precedente, .successiva, .su, .giu, .spostaSx, .spostaDx, .centra, .galleggia, .altroSchermo],
        [.meta, .dueTerzi, .intera, .cicla, .allarga, .stringi, .impila, .impilaDx, .staccaSx, .stacca],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rowline").font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("Let go to close").font(.system(size: 11)).foregroundStyle(t.t3)
            }
            HStack(alignment: .top, spacing: 28) {
                ForEach(0..<gruppi.count, id: \.self) { i in
                    VStack(spacing: 0) { ForEach(gruppi[i]) { a in riga(a) } }.frame(width: 270)
                }
            }
        }
        .padding(26)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LinearGradient(colors: [t.alto, t.basso], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(t.chiaro ? 0.12 : 0.35), radius: 22, y: 10))
        .padding(28)
        .foregroundStyle(t.testo)
        .environment(\.colorScheme, t.schema)
    }

    private func riga(_ a: Azione) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: a.simbolo).font(.system(size: 11)).foregroundStyle(t.t3).frame(width: 20)
                Text(a.titolo).font(.system(size: 12.5))
                Spacer()
                Text(k.combo[a].map { $0.mod == 0 ? "" : $0.testo } ?? "").font(.system(size: 12)).foregroundStyle(t.t2)
            }
            .frame(height: 34)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}

// MARK: - On-screen keys: pills for the pressed keys, bottom left (for videos and the demo)

final class TastiVisti {
    static let shared = TastiVisti()
    var acceso: Bool {
        get { UserDefaults.standard.bool(forKey: "tastiVisti") }
        set { UserDefaults.standard.set(newValue, forKey: "tastiVisti") }
    }
    var forzato = false               // always visible during the demo
    private var pannello: NSPanel?
    private var spegni: DispatchWorkItem?

    func mostra(_ a: Azione) {
        guard acceso || forzato, a != .pannello, let c = Tasti.shared.combo[a], c.mod != 0 else { return }
        presenta(AnyView(VistaTastiVisti(combo: c, titolo: a.titolo).environmentObject(Tinta.shared)))
    }

    /// A trackpad gesture, drawn like the keys (icon + name).
    func mostraTesto(_ simbolo: String, _ titolo: String) {
        guard acceso || forzato else { return }
        presenta(AnyView(VistaGestoVisto(simbolo: simbolo, titolo: titolo).environmentObject(Tinta.shared)))
    }

    private func presenta(_ vista: AnyView) {
        let p = pannello ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .stationary]; p.ignoresMouseEvents = true
            return p
        }()
        pannello = p
        let host = NSHostingView(rootView: vista)
        p.contentView = host
        let size = host.fittingSize
        let m = NSEvent.mouseLocation
        let sc = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main!
        p.setFrame(NSRect(x: sc.visibleFrame.minX + 28, y: sc.visibleFrame.minY + 36, width: size.width, height: size.height), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        spegni?.cancel()
        let w = DispatchWorkItem { NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) }) }
        spegni = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: w)
    }
}

struct VistaTastiVisti: View {
    let combo: Combo
    let titolo: String
    @EnvironmentObject var t: Tinta

    var body: some View {
        let simboli = Array(combo.testo).map(String.init)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(simboli.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 17, weight: .light))
                        .frame(minWidth: 40, minHeight: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
            }
            Text(titolo).font(.system(size: 12)).foregroundStyle(t.testo.opacity(0.85))
                .shadow(color: (t.chiaro ? Color.white : Color.black).opacity(0.7), radius: 4)
        }
        .padding(6)
        .foregroundStyle(t.testo)
        .environment(\.colorScheme, t.schema)
    }
}

struct VistaGestoVisto: View {
    let simbolo: String
    let titolo: String
    @EnvironmentObject var t: Tinta
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: simbolo).font(.system(size: 19, weight: .light))
                .frame(width: 52, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            Text(titolo).font(.system(size: 12)).foregroundStyle(t.testo.opacity(0.85))
                .shadow(color: (t.chiaro ? Color.white : Color.black).opacity(0.7), radius: 4)
        }
        .padding(6).foregroundStyle(t.testo).environment(\.colorScheme, t.schema)
    }
}

// MARK: - Demo: Rowline shows itself (calls the engine, does not simulate keys). Esc stops it.

final class Dimostrazione {
    static let shared = Dimostrazione()
    private var passi: [DispatchWorkItem] = []
    private var monitor: [Any] = []
    private(set) var inCorso = false

    private let copione: [(Azione, Double)] = [
        (.successiva, 1.6), (.successiva, 1.3), (.precedente, 1.3), (.dueTerzi, 1.5), (.meta, 1.3),
        (.centra, 1.5), (.spostaDx, 1.5), (.spostaSx, 1.5), (.impila, 1.7), (.stacca, 1.5),
        (.allarga, 1.3), (.allarga, 1.1), (.meta, 1.3), (.successiva, 1.3), (.precedente, 1.3),
    ]

    func avvia() {
        guard !inCorso else { return }
        inCorso = true
        TastiVisti.shared.forzato = true
        let esc: (NSEvent) -> Void = { [weak self] e in if e.keyCode == 53 { self?.ferma() } }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: esc) { monitor.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { esc($0); return $0 }) { monitor.append(m) }
        var t = 1.5                                     // time to start recording
        for (a, d) in copione {
            let w = DispatchWorkItem { MainActor.assumeIsolated { a.esegui() } }
            passi.append(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
            t += d
        }
        let fine = DispatchWorkItem { [weak self] in self?.ferma() }
        passi.append(fine)
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.5, execute: fine)
    }

    func ferma() {
        passi.forEach { $0.cancel() }; passi = []
        monitor.forEach { NSEvent.removeMonitor($0) }; monitor = []
        TastiVisti.shared.forzato = false
        inCorso = false
    }
}

// MARK: - Previews: hovering a line in the bar shows the window thumbnail (needs the Screen Recording permission)

final class Anteprime: ObservableObject {
    static let shared = Anteprime()
    @Published var accese: Bool = UserDefaults.standard.bool(forKey: "anteprime") {
        didSet {
            UserDefaults.standard.set(accese, forKey: "anteprime")
            if accese && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            Barra.shared.aggiorna()
        }
    }
    @Published var immagini: [CGWindowID: NSImage] = [:]
    private var quando: [CGWindowID: Date] = [:]

    var permesso: Bool { CGPreflightScreenCaptureAccess() }

    func chiedi(_ id: CGWindowID) {
        guard accese, permesso else { return }
        if let q = quando[id], Date().timeIntervalSince(q) < 3 { return }
        quando[id] = Date()
        Task {
            guard let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
                  let w = c.windows.first(where: { $0.windowID == id }) else { return }
            let cfg = SCStreamConfiguration()
            let k = 480 / max(w.frame.width, 1)
            cfg.width = Int(w.frame.width * k); cfg.height = Int(w.frame.height * k)
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) else { return }
            await MainActor.run { self.immagini[id] = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) }
        }
    }
}
