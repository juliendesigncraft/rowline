// Rowline: the ENGINE.
// Open windows sit in a horizontal row, side by side, instead of piling up. Each screen has its own row;
// each place in the row is a column that can hold a single window or several stacked windows. The row scrolls:
// the focused window is always fully visible; windows out of view are parked in the bottom right corner
// of the screen (one pixel stays visible, as AeroSpace does).
//
// Everything goes through the macOS Accessibility API (the only permission needed). No network, no account.
// Windows move only when something happens (new or closed window, focus change, a command):
// if you move them by hand Rowline does not pull them back, it puts them in the row at the next event.

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Accessibility, in short

enum AX {
    static func valore(_ el: AXUIElement, _ nome: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, nome as CFString, &v) == .success ? v : nil
    }
    static func stringa(_ el: AXUIElement, _ nome: String) -> String? { valore(el, nome) as? String }
    static func vero(_ el: AXUIElement, _ nome: String) -> Bool { (valore(el, nome) as? Bool) ?? false }
    static func id(_ el: AXUIElement) -> CGWindowID? {
        var i: CGWindowID = 0
        return _AXUIElementGetWindow(el, &i) == .success && i != 0 ? i : nil
    }
    static func finestre(_ app: AXUIElement) -> [AXUIElement] {
        (valore(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    static func modificabile(_ el: AXUIElement, _ nome: String) -> Bool {
        var b: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, nome as CFString, &b) == .success && b.boolValue
    }
    static func cornice(_ el: AXUIElement) -> CGRect? {
        guard let p = valore(el, kAXPositionAttribute), let s = valore(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
    static func posa(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
    }
    static func misura(_ el: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) }
    }
}

// MARK: - Screens in Accessibility coordinates (origin at the top left of the main screen)

extension NSScreen {
    var numero: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0 }
    private static var altezzaPrincipale: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    private func ax(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: NSScreen.altezzaPrincipale - r.maxY, width: r.width, height: r.height) }
    var areaAX: CGRect { ax(visibleFrame) }     // without menu bar and Dock
    var corniceAX: CGRect { ax(frame) }
}

// MARK: - The model

final class Finestra {
    let id: CGWindowID, el: AXUIElement, pid: pid_t, app: String, bundle: String
    init(id: CGWindowID, el: AXUIElement, pid: pid_t, app: String, bundle: String) {
        self.id = id; self.el = el; self.pid = pid; self.app = app; self.bundle = bundle
    }
}

final class Colonna {
    var finestre: [Finestra]
    var frazione: CGFloat          // share of the screen width: 1/2, 2/3, 1
    var attiva = 0                 // which window of the stack has focus
    init(_ f: [Finestra], frazione: CGFloat) { finestre = f; self.frazione = frazione }
}

final class Striscia {
    let schermo: CGDirectDisplayID
    var colonne: [Colonna] = []
    var fuoco = 0
    var scorrimento: CGFloat = 0
    var centrata = false           // ⌃⌥⌘C: the focused column stays centred even at the edges of the row
    // the last layout, to draw the map in the panel
    var xs: [CGFloat] = [], larghezze: [CGFloat] = [], vista: CGFloat = 1, alta: CGFloat = 1
    init(_ s: CGDirectDisplayID) { schermo = s }
}

// What the panel draws (plain copies, never AX references)
struct TesseraVista: Identifiable { let id: CGWindowID; let app: String; let bundle: String }
struct ColonnaVista: Identifiable { let id: Int; let x: CGFloat; let w: CGFloat; let finestre: [TesseraVista]; let attiva: Int; let fuoco: Bool }
struct StrisciaVista: Identifiable { let id: CGDirectDisplayID; let nome: String; let colonne: [ColonnaVista]; let scorrimento: CGFloat; let vista: CGFloat; let alta: CGFloat
    var fuoco: (app: String, posto: Int, totale: Int)? {
        guard let i = colonne.firstIndex(where: \.fuoco) else { return nil }
        let c = colonne[i]
        return (c.finestre[safe: c.attiva]?.app ?? "", i + 1, colonne.count)
    }
}

// MARK: - The engine

final class Motore: ObservableObject {
    static let shared = Motore()

    @Published var mappa: [StrisciaVista] = []
    @Published private(set) var fidato = AXIsProcessTrusted()
    @Published var acceso: Bool = UserDefaults.standard.object(forKey: "acceso") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(acceso, forKey: "acceso")
            if acceso { adotta() } else { libera() }
        }
    }
    @Published var escluse: [String] = UserDefaults.standard.stringArray(forKey: "escluse") ?? [] {
        didSet { UserDefaults.standard.set(escluse, forKey: "escluse"); if acceso { adotta() } }
    }
    @Published var spazio: Double = UserDefaults.standard.object(forKey: "spazio") as? Double ?? 10 {
        didSet { UserDefaults.standard.set(spazio, forKey: "spazio"); disponiTutto() }
    }
    var g: CGFloat { CGFloat(spazio) }
    /// Windows slide into place (0.2 s) instead of jumping.
    @Published var animazioni: Bool = UserDefaults.standard.object(forKey: "animazioni") as? Bool ?? true {
        didSet { UserDefaults.standard.set(animazioni, forKey: "animazioni") }
    }
    /// Fixed width per app (bundle → fraction): a new window of that app enters already at that width.
    @Published var regoleApp: [String: Double] = (UserDefaults.standard.dictionary(forKey: "regoleApp") as? [String: Double]) ?? [:] {
        didSet { UserDefaults.standard.set(regoleApp, forKey: "regoleApp") }
    }
    /// How much the neighbouring windows peek in at the sides (0 = none): shows that the row continues.
    @Published var sbirciata: Double = UserDefaults.standard.object(forKey: "sbirciata") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(sbirciata, forKey: "sbirciata"); disponiTutto() }
    }
    @Published var postazioni: [Postazione] = Postazione.carica() {
        didSet { Postazione.salva(postazioni) }
    }
    /// Windows made to float above the row (⌃⌥⌘T): free until put back.
    private var galleggianti = Set<CGWindowID>()

    private var strisce: [CGDirectDisplayID: Striscia] = [:]
    private var fuocoID: CGWindowID?
    private var timer: Timer?
    /// Apps that are never put in the row: Rowline itself.
    private let sempreLibere: Set<String> = ["com.juliendesigncraft.rowline"]

    func avvia() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                  NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                  NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.giro() }
        }
        // Space change: windows of the other Space leave the row, those of this one enter.
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.adotta() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.adotta() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.giro() }
        if acceso { adotta() }
    }

    // MARK: Finding windows

    private struct Trovata { let f: Finestra; let cornice: CGRect }

    /// Normal windows of normal apps: no dialogs, panels, minimised or full screen windows,
    /// no fixed-size windows (System Settings, calculator): those stay free.
    private func cerca(soloVisibili: Bool) -> [CGWindowID: Trovata] {
        var visibili = Set<CGWindowID>()
        if soloVisibili, let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in info { if let n = w[kCGWindowNumber as String] as? CGWindowID { visibili.insert(n) } }
        }
        var out: [CGWindowID: Trovata] = [:]
        let mio = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != mio {
            let b = app.bundleIdentifier ?? ""
            if sempreLibere.contains(b) || escluse.contains(b) { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            for w in AX.finestre(axApp) {
                guard AX.stringa(w, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      !AX.vero(w, kAXMinimizedAttribute), !AX.vero(w, "AXFullScreen"),
                      AX.modificabile(w, kAXSizeAttribute),
                      let id = AX.id(w), let c = AX.cornice(w) else { continue }
                if soloVisibili && !visibili.contains(id) { continue }
                if galleggianti.contains(id) { continue }
                let nome = app.localizedName ?? b
                out[id] = Trovata(f: Finestra(id: id, el: w, pid: app.processIdentifier, app: nome, bundle: b), cornice: c)
            }
        }
        return out
    }

    private func schermo(per c: CGRect) -> NSScreen? {
        let centro = CGPoint(x: c.midX, y: c.midY)
        return NSScreen.screens.first { $0.corniceAX.contains(centro) }
            ?? NSScreen.screens.max { $0.corniceAX.intersection(c).area < $1.corniceAX.intersection(c).area }
    }

    private func striscia(_ s: NSScreen) -> Striscia {
        if let x = strisce[s.numero] { return x }
        let x = Striscia(s.numero); strisce[s.numero] = x; return x
    }

    /// Start over: the visible windows enter the row in their left to right order.
    func adotta() {
        fidato = AXIsProcessTrusted()
        guard acceso, fidato else { aggiornaMappa(); return }
        let vecchie = strisce
        strisce = [:]
        let trovate = cerca(soloVisibili: true).values.sorted { $0.cornice.minX < $1.cornice.minX }
        for t in trovate {
            guard let s = schermo(per: t.cornice) else { continue }
            // whoever was already in the row keeps its width
            let prima = vecchie.values.flatMap(\.colonne).first { $0.finestre.contains { $0.id == t.f.id } }
            striscia(s).colonne.append(Colonna([t.f], frazione: prima?.frazione ?? regoleApp[t.f.bundle].map { CGFloat($0) } ?? frazioneNuova(t.cornice.width, s)))
        }
        leggiFuoco(forza: true)
        disponiTutto()
    }

    /// The starting width: the closest among 1/2, 2/3 and full to the one the window already has.
    private func frazioneNuova(_ w: CGFloat, _ s: NSScreen) -> CGFloat {
        let r = w / s.areaAX.width
        return [0.5, 2.0 / 3, 1].min { abs($0 - r) < abs($1 - r) }!
    }

    // MARK: The loop (every 0.35 s and on every app event)

    func giro() {
        let ora = AXIsProcessTrusted()
        if ora != fidato { fidato = ora; if ora { adotta() } }
        guard acceso, fidato else { return }
        var cambiate = Set<CGDirectDisplayID>()
        let tutte = cerca(soloVisibili: false)
        // drop closed, minimised or hidden ones
        for st in strisce.values {
            let prima = st.colonne.reduce(0) { $0 + $1.finestre.count }
            for c in st.colonne { c.finestre.removeAll { tutte[$0.id] == nil }; c.attiva = min(c.attiva, max(0, c.finestre.count - 1)) }
            st.colonne.removeAll { $0.finestre.isEmpty }
            if st.colonne.reduce(0, { $0 + $1.finestre.count }) != prima { cambiate.insert(st.schermo); st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1)) }
        }
        // add the new ones (only if visible: those on other Spaces stay out)
        let note = Set(strisce.values.flatMap { $0.colonne.flatMap { $0.finestre.map(\.id) } })
        let nuove = tutte.filter { !note.contains($0.key) }
        if !nuove.isEmpty {
            let visibili = cerca(soloVisibili: true)
            for (id, t) in nuove where visibili[id] != nil {
                guard let s = schermo(per: t.cornice) else { continue }
                let st = striscia(s)
                let posto = st.colonne.isEmpty ? 0 : st.fuoco + 1
                st.colonne.insert(Colonna([t.f], frazione: regoleApp[t.f.bundle].map { CGFloat($0) } ?? 0.5), at: posto)
                st.fuoco = posto
                cambiate.insert(st.schermo)
            }
        }
        if let s = leggiFuoco(forza: false) { cambiate.insert(s) }
        for s in cambiate { if let st = strisce[s] { disponi(st) } }
        if !cambiate.isEmpty { aggiornaMappa() }
    }

    /// Follows the focused window (click, ⌘Tab, Dock): if it is in the row, the row scrolls to it.
    @discardableResult
    private func leggiFuoco(forza: Bool) -> CGDirectDisplayID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let v = AX.valore(axApp, kAXFocusedWindowAttribute), CFGetTypeID(v) == AXUIElementGetTypeID(),
              let id = AX.id(v as! AXUIElement) else { return nil }
        if id == fuocoID && !forza { return nil }
        fuocoID = id
        for st in strisce.values {
            for (i, c) in st.colonne.enumerated() {
                if let j = c.finestre.firstIndex(where: { $0.id == id }) {
                    if st.fuoco != i { st.centrata = false }
                    st.fuoco = i; c.attiva = j
                    return st.schermo
                }
            }
        }
        return nil
    }

    // MARK: Layout

    func disponiTutto() {
        guard acceso, fidato else { return }
        strisce.values.forEach(disponi)
        aggiornaMappa()
    }

    private func disponi(_ st: Striscia) {
        guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { return }
        var area = sc.areaAX.insetBy(dx: g, dy: g)
        area.size.height -= Barra.riserva          // the room taken by the bottom bar: windows do not go over it
        let pieno = area                           // the whole screen: whatever falls inside is visible
        // with peeking, the focused column sits in a narrower view and the neighbours peek in at the sides
        if st.colonne.count > 1 && sbirciata > 0 { area = area.insetBy(dx: CGFloat(sbirciata), dy: 0) }
        guard !st.colonne.isEmpty else { st.xs = []; st.larghezze = []; return }
        st.fuoco = min(st.fuoco, st.colonne.count - 1)

        // 1. sizes (some windows do not shrink below a minimum width: the real one is kept)
        var larghezze: [CGFloat] = []
        for c in st.colonne {
            let w = max(240, (c.frazione * (area.width + g) - g).rounded())
            let n = CGFloat(c.finestre.count)
            let h = ((area.height - g * (n - 1)) / n).rounded()
            var vera = w
            for f in c.finestre {
                AX.misura(f.el, CGSize(width: w, height: h))
                if let r = AX.cornice(f.el) { vera = max(vera, min(r.width, area.width)) }
            }
            larghezze.append(vera)
        }
        // 2. positions in the row and the minimum scroll that shows the whole focused column
        var xs: [CGFloat] = [], x: CGFloat = 0
        for w in larghezze { xs.append(x); x += w + g }
        let totale = x - g
        var s = st.scorrimento
        let fx = xs[st.fuoco], fw = larghezze[st.fuoco]
        if st.centrata {
            s = fx + fw / 2 - area.width / 2
        } else {
            if fx < s { s = fx }
            if fx + fw > s + area.width { s = fx + fw - area.width }
            s = max(0, min(s, max(0, totale - area.width)))
        }
        let prima = st.scorrimento
        st.scorrimento = s; st.xs = xs; st.larghezze = larghezze; st.vista = area.width; st.alta = area.height

        // 3. place everything: what is visible, even in part, at its place, the rest parked in the corner.
        //    Visible windows slide: from where they are, or (if they were parked) from where they would have been before.
        let angolo = CGPoint(x: sc.corniceAX.maxX - 1, y: sc.corniceAX.maxY - 1)
        var mosse: [Mossa] = []
        for (i, c) in st.colonne.enumerated() {
            let sx = area.minX + xs[i] - s
            let siVede = sx + larghezze[i] > pieno.minX + 8 && sx < pieno.maxX - 8
            let n = CGFloat(c.finestre.count)
            let h = ((area.height - g * (n - 1)) / n).rounded()
            for (j, f) in c.finestre.enumerated() {
                if siVede {
                    let p = CGPoint(x: sx, y: area.minY + CGFloat(j) * (h + g))
                    let ora = AX.cornice(f.el)
                    let parcheggiata = ora.map { $0.minX >= sc.corniceAX.maxX - 4 || $0.maxX <= sc.corniceAX.minX + 4 } ?? true
                    let da = parcheggiata ? CGPoint(x: area.minX + xs[i] - prima, y: p.y) : (ora?.origin ?? p)
                    mosse.append(Mossa(el: f.el, da: da, a: p, misura: CGSize(width: larghezze[i], height: h)))
                } else {
                    AX.posa(f.el, angolo)
                }
            }
        }
        anima(mosse)
    }

    // MARK: Animation

    private struct Mossa { let el: AXUIElement; let da: CGPoint; let a: CGPoint; let misura: CGSize }
    private var timerAnim: Timer?
    private var inCorso: [Mossa] = []

    /// 0.2 s with a soft ease-out, at 60 steps per second. A new layout interrupts the running one
    /// (earlier windows go straight to their final place, so nothing is left half way).
    private func anima(_ m: [Mossa]) {
        timerAnim?.invalidate()
        for x in inCorso where !m.contains(where: { CFEqual($0.el, x.el) }) { posaFinale(x) }
        inCorso = m
        let corte = m.filter { hypot($0.a.x - $0.da.x, $0.a.y - $0.da.y) > 2 }
        guard animazioni, !corte.isEmpty else { m.forEach(posaFinale); inCorso = []; return }
        let inizio = CACurrentMediaTime(), durata = 0.2
        timerAnim = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let k = min(1, (CACurrentMediaTime() - inizio) / durata)
            let e = CGFloat(1 - pow(1 - k, 3))
            if k >= 1 {
                t.invalidate()
                self.inCorso.forEach(self.posaFinale)
                self.inCorso = []
                return
            }
            for x in self.inCorso {
                AX.posa(x.el, CGPoint(x: x.da.x + (x.a.x - x.da.x) * e, y: x.da.y + (x.a.y - x.da.y) * e))
            }
        }
    }

    private func posaFinale(_ x: Mossa) {
        AX.posa(x.el, x.a)
        AX.misura(x.el, x.misura)      // after the move: the screen no longer squeezes it
        AX.posa(x.el, x.a)
    }

    /// Rowline off or closed: no window may stay in the corner. All return to the screen, cascaded.
    func libera() {
        for st in strisce.values {
            guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { continue }
            let area = sc.areaAX.insetBy(dx: g, dy: g)
            for (k, f) in st.colonne.flatMap(\.finestre).enumerated() {
                let r = AX.cornice(f.el) ?? .zero
                if r.minX >= area.minX - 1 && r.maxX <= area.maxX + 1 { continue }   // already fully in view: stays where it is
                let off = CGFloat(k % 8) * 28
                let w = min(r.width > 0 ? r.width : area.width / 2, area.width - off)
                AX.posa(f.el, CGPoint(x: area.minX + off, y: area.minY + off))
                AX.misura(f.el, CGSize(width: w, height: min(r.height > 0 ? r.height : area.height, area.height - off)))
            }
        }
        strisce = [:]
        aggiornaMappa()
    }

    // MARK: Commands

    /// The row to act on: that of the focused window, otherwise that of the screen under the mouse.
    private var attiva: Striscia? {
        if let id = fuocoID, let st = strisce.values.first(where: { $0.colonne.contains { $0.finestre.contains { $0.id == id } } }) { return st }
        let m = NSEvent.mouseLocation
        let sc = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
        return sc.flatMap { strisce[$0.numero] }
    }

    private func porta(_ f: Finestra) {
        fuocoID = f.id
        AXUIElementSetAttributeValue(f.el, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(f.el, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: f.pid)?.activate()
    }

    private func dopo(_ st: Striscia) {
        disponi(st)
        let c = st.colonne[st.fuoco]
        porta(c.finestre[min(c.attiva, c.finestre.count - 1)])
        aggiornaMappa()
    }

    func vai(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.centrata = false
        st.fuoco = max(0, min(st.colonne.count - 1, st.fuoco + d))
        dopo(st)
    }

    func suGiu(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        c.attiva = max(0, min(c.finestre.count - 1, c.attiva + d))
        dopo(st)
    }

    func sposta(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let j = st.fuoco + d
        guard j >= 0 && j < st.colonne.count else { return }
        st.colonne.swapAt(st.fuoco, j); st.fuoco = j
        dopo(st)
    }

    func larghezza(_ fr: CGFloat) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.colonne[st.fuoco].frazione = fr
        dopo(st)
    }

    func ciclaLarghezza() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let giri: [CGFloat] = [0.5, 2.0 / 3, 1]
        let c = st.colonne[st.fuoco]
        let i = giri.firstIndex { abs($0 - c.frazione) < 0.01 } ?? -1
        c.frazione = giri[(i + 1) % giri.count]
        dopo(st)
    }

    /// Stack: the focused window enters the column on its left (they sit one above the other).
    func impila() {
        guard let st = attiva, st.fuoco > 0 else { return }
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        let sinistra = st.colonne[st.fuoco - 1]
        sinistra.finestre.append(f); sinistra.attiva = sinistra.finestre.count - 1
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1) }
        st.fuoco -= 1
        dopo(st)
    }

    /// Unstack: the focused window leaves the stack and takes its own place, right after.
    func stacca() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        guard c.finestre.count > 1 else { return }
        let f = c.finestre.remove(at: c.attiva)
        c.attiva = min(c.attiva, c.finestre.count - 1)
        st.colonne.insert(Colonna([f], frazione: c.frazione), at: st.fuoco + 1)
        st.fuoco += 1
        dopo(st)
    }

    /// ⌃⌥⌘C: the focused window slides to the centre of the screen.
    func centra() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.centrata = true
        dopo(st)
    }

    /// ⌃⌥⌘= and ⌃⌥⌘-: a bit wider or narrower (steps of a tenth of the screen).
    func allarga(_ d: CGFloat) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        c.frazione = max(0.2, min(1, (c.frazione + d * 0.1)))
        dopo(st)
    }

    /// ⌃⌥⌘]: the focused window enters the column on its right.
    func impilaDestra() {
        guard let st = attiva, st.fuoco < st.colonne.count - 1 else { return }
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        let destra = st.colonne[st.fuoco + 1]
        destra.finestre.append(f); destra.attiva = destra.finestre.count - 1
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1); st.fuoco += 1 }
        dopo(st)
    }

    /// ⌃⌥⇧⌘[: leaves the stack and takes its own place on the left.
    func staccaSinistra() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        guard c.finestre.count > 1 else { return }
        let f = c.finestre.remove(at: c.attiva)
        c.attiva = min(c.attiva, c.finestre.count - 1)
        st.colonne.insert(Colonna([f], frazione: c.frazione), at: st.fuoco)
        dopo(st)
    }

    /// ⌃⌥⌘T: the window leaves the row and floats in the centre, above the others. ⌃⌥⌘T again and it goes back in the row.
    func galleggia() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let v = AX.valore(axApp, kAXFocusedWindowAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return }
        let el = v as! AXUIElement
        guard let id = AX.id(el) else { return }
        if galleggianti.remove(id) != nil { giro(); return }        // goes back in the row at the next loop, after the focused one
        galleggianti.insert(id)
        for st in strisce.values {
            for c in st.colonne { c.finestre.removeAll { $0.id == id } }
            st.colonne.removeAll { $0.finestre.isEmpty }
            st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1))
        }
        let sc = AX.cornice(el).flatMap(schermo(per:)) ?? NSScreen.main!
        let a = sc.areaAX
        let w = a.width * 0.55, h = a.height * 0.7
        AX.misura(el, CGSize(width: w, height: h))
        AX.posa(el, CGPoint(x: a.midX - w / 2, y: a.midY - h / 2))
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        strisce.values.forEach(disponi)
        aggiornaMappa()
    }

    /// ⌃⌥⌘N: the window moves to the row of the other screen.
    func altroSchermo() {
        guard NSScreen.screens.count > 1, let st = attiva, !st.colonne.isEmpty,
              let i = NSScreen.screens.firstIndex(where: { $0.numero == st.schermo }) else { return }
        let dest = striscia(NSScreen.screens[(i + 1) % NSScreen.screens.count])
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1) }
        st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1))
        let posto = dest.colonne.isEmpty ? 0 : dest.fuoco + 1
        dest.colonne.insert(Colonna([f], frazione: c.frazione), at: posto)
        dest.fuoco = posto
        disponi(st)
        dopo(dest)
    }

    /// From the panel: a click on a map tile.
    func scegli(_ id: CGWindowID) {
        for st in strisce.values {
            st.centrata = false
            for (i, c) in st.colonne.enumerated() {
                if let j = c.finestre.firstIndex(where: { $0.id == id }) { st.fuoco = i; c.attiva = j; dopo(st); return }
            }
        }
    }

    /// From the bar: dragged to `s`, focus goes to the column in the middle of what is visible.
    func scorriA(_ schermo: CGDirectDisplayID, _ s: CGFloat) {
        guard let st = strisce[schermo], !st.colonne.isEmpty, st.xs.count == st.colonne.count else { return }
        let centro = s + st.vista / 2
        let i = st.xs.indices.min { abs(st.xs[$0] + st.larghezze[$0] / 2 - centro) < abs(st.xs[$1] + st.larghezze[$1] / 2 - centro) } ?? st.fuoco
        st.scorrimento = s
        st.centrata = false
        st.fuoco = i
        dopo(st)
    }

    // MARK: Workspaces

    /// Saves the order and widths of the row you are using.
    func salvaPostazione(_ nome: String) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let posti = st.colonne.compactMap { c in c.finestre.first.map { Posto(bundle: $0.bundle, app: $0.app, frazione: Double(c.frazione)) } }
        postazioni.append(Postazione(id: UUID(), nome: nome, posti: posti))
    }

    /// Opens missing apps, waits for their windows (8 s at most) and puts them in the row in the saved order.
    func applica(_ p: Postazione) {
        let aperte = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for b in Set(p.posti.map(\.bundle)) where !aperte.contains(b) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        let inizio = Date()
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.giro()
            let presenti = Set(self.strisce.values.flatMap { $0.colonne.flatMap { $0.finestre.map(\.bundle) } })
            if p.posti.allSatisfy({ presenti.contains($0.bundle) }) || Date().timeIntervalSince(inizio) > 8 {
                t.invalidate()
                self.ordina(p)
            }
        }
    }

    private func ordina(_ p: Postazione) {
        let m = NSEvent.mouseLocation
        guard let sc = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) ?? NSScreen.main else { return }
        let dest = striscia(sc)
        var prese: [Colonna] = []
        for posto in p.posti {
            // the first window of that app not yet taken, from any row
            var trovata: Finestra?
            for st in strisce.values {
                for c in st.colonne {
                    if let j = c.finestre.firstIndex(where: { f in f.bundle == posto.bundle && !prese.contains { $0.finestre.contains { $0 === f } } }) {
                        trovata = c.finestre.remove(at: j); c.attiva = max(0, min(c.attiva, c.finestre.count - 1)); break
                    }
                }
                if trovata != nil { break }
            }
            if let f = trovata { prese.append(Colonna([f], frazione: CGFloat(posto.frazione))) }
        }
        for st in strisce.values { st.colonne.removeAll { $0.finestre.isEmpty }; st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1)) }
        dest.colonne = prese + dest.colonne
        dest.fuoco = 0; dest.scorrimento = 0; dest.centrata = false
        strisce.values.filter { $0 !== dest }.forEach(disponi)
        if !dest.colonne.isEmpty { dopo(dest) } else { aggiornaMappa() }
    }

    /// The app of the focused window, for "leave it free".
    var appInFuoco: (nome: String, bundle: String)? {
        guard let st = attiva, !st.colonne.isEmpty else { return nil }
        let c = st.colonne[st.fuoco]
        guard let f = c.finestre[safe: c.attiva] else { return nil }
        return (f.app, f.bundle)
    }

    func liberaApp(_ bundle: String) {
        guard !bundle.isEmpty, !escluse.contains(bundle) else { return }
        // first put it back on screen, then it leaves the row
        for st in strisce.values {
            for c in st.colonne { for f in c.finestre where f.bundle == bundle { mettiInVista(f, st) } }
        }
        escluse.append(bundle)
    }

    private func mettiInVista(_ f: Finestra, _ st: Striscia) {
        guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { return }
        let a = sc.areaAX.insetBy(dx: 60, dy: 40)
        AX.posa(f.el, CGPoint(x: a.minX, y: a.minY))
        AX.misura(f.el, CGSize(width: a.width * 0.6, height: a.height))
    }

    // MARK: Map for the panel

    func aggiornaMappa() {
        var out: [StrisciaVista] = []
        for (k, sc) in NSScreen.screens.enumerated() {
            guard let st = strisce[sc.numero], !st.colonne.isEmpty, st.xs.count == st.colonne.count else { continue }
            let cols = st.colonne.enumerated().map { i, c in
                ColonnaVista(id: i, x: st.xs[i], w: st.larghezze[i],
                             finestre: c.finestre.map { TesseraVista(id: $0.id, app: $0.app, bundle: $0.bundle) },
                             attiva: c.attiva, fuoco: i == st.fuoco)
            }
            let nome = NSScreen.screens.count > 1 ? (sc.localizedName.isEmpty ? "Display \(k + 1)" : sc.localizedName) : ""
            out.append(StrisciaVista(id: st.schermo, nome: nome, colonne: cols, scorrimento: st.scorrimento, vista: st.vista, alta: st.alta))
        }
        mappa = out
    }

    var quante: Int { mappa.reduce(0) { $0 + $1.colonne.reduce(0) { $0 + $1.finestre.count } } }
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

// MARK: - Workspaces (saved in UserDefaults)

struct Posto: Codable, Hashable { var bundle: String; var app: String; var frazione: Double }
struct Postazione: Codable, Identifiable, Hashable {
    var id: UUID; var nome: String; var posti: [Posto]
    static func carica() -> [Postazione] {
        UserDefaults.standard.data(forKey: "postazioni").flatMap { try? JSONDecoder().decode([Postazione].self, from: $0) } ?? []
    }
    static func salva(_ p: [Postazione]) { UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: "postazioni") }
}
