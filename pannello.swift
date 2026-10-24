// Rowline: the PANEL. Graphite blue like Dark Matte and the light tones of White Matte, following the system appearance.
// SF interface, light blue as the only accent, data rows for the shortcuts, icons instead of words where possible.
// Opens from the menu bar icon, with ⌃⌥⌘F, or by reopening Rowline from Launchpad or Spotlight.
// Tabs: Row (map and commands), Workspaces, Shortcuts, Settings, How it works.

import AppKit
import SwiftUI

// MARK: - Theme (follows the system appearance)

final class Tinta: ObservableObject {
    static let shared = Tinta()
    @Published var chiaro = false

    init() {
        leggi()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.leggi() }
        }
    }

    func leggi() {
        chiaro = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != "Dark"
    }

    private func c(_ h: UInt32) -> Color { Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
    var alto: Color { chiaro ? c(0xF6F7F9) : c(0x2B2E3C) }
    var basso: Color { chiaro ? c(0xEEF0F3) : c(0x22252F) }
    var testo: Color { chiaro ? c(0x1E2028) : .white }
    var t2: Color { testo.opacity(0.56) }
    var t3: Color { testo.opacity(chiaro ? 0.42 : 0.34) }
    var linea: Color { testo.opacity(chiaro ? 0.10 : 0.08) }
    var velo: Color { Color.black.opacity(chiaro ? 0.05 : 0.16) }
    var sel: Color { Color.black.opacity(chiaro ? 0.10 : 0.28) }
    var azzurro: Color { chiaro ? c(0x3B82D0) : c(0x8FC7FF) }
    var schema: ColorScheme { chiaro ? .light : .dark }
}

// MARK: - The window

final class PannelloFinestra: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Pannello: NSObject, NSWindowDelegate {
    static let shared = Pannello()
    private var finestra: PannelloFinestra?
    private var controllore: NSHostingController<AnyView>?
    weak var bottone: NSStatusBarButton?
    let stato = StatoPannello()

    func alterna() { (finestra?.isVisible ?? false) ? chiudi() : apri() }

    func apri() {
        if finestra == nil {
            let p = PannelloFinestra(contentRect: NSRect(x: 0, y: 0, width: 392, height: 520),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false               // the system shadow also draws a dark outline: the view draws the shadow instead
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.delegate = self
            let hc = NSHostingController(rootView: AnyView(VistaPannello().environmentObject(Motore.shared).environmentObject(Tasti.shared)
                                        .environmentObject(Tinta.shared).environmentObject(stato)))
            hc.sizingOptions = []            // size is decided by posiziona(), also when the tab changes
            controllore = hc
            p.contentView = hc.view
            finestra = p
        }
        guard let p = finestra else { return }
        Tinta.shared.leggi()
        Motore.shared.aggiornaMappa()
        p.layoutIfNeeded()
        posiziona(p)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.22; p.animator().alphaValue = 1 }
    }

    /// The panel is rebuilt on demand (texts are read when drawn).
    func ricostruisci() {
        let aperto = finestra?.isVisible ?? false
        finestra?.orderOut(nil); finestra = nil; controllore = nil
        if aperto { apri() }
    }

    /// Tab change: the window takes the new size, staying attached under the icon.
    func ridimensiona() { if let p = finestra, p.isVisible { posiziona(p) } }

    private func posiziona(_ p: NSPanel) {
        // measure after layout: before that the window was born 0 x 0 and invisible
        var size = controllore?.sizeThatFits(in: NSSize(width: 448, height: 2000)) ?? .zero
        if size.width < 50 || size.height < 50 { size = NSSize(width: 448, height: 616) }
        if let b = bottone, let w = b.window {
            let r = w.convertToScreen(b.convert(b.bounds, to: nil))
            let sc = w.screen ?? NSScreen.main!
            let x = min(max(sc.visibleFrame.minX + 8, r.midX - size.width / 2), sc.visibleFrame.maxX - size.width - 8)
            p.setFrame(NSRect(x: x, y: r.minY + 20 - size.height, width: size.width, height: size.height), display: true)
        } else if let sc = NSScreen.main {
            p.setFrame(NSRect(x: sc.visibleFrame.maxX - size.width - 12, y: sc.visibleFrame.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        }
    }

    func chiudi() {
        stato.fermaRegistrazione()
        guard let p = finestra else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    func windowDidResignKey(_ notification: Notification) {
        if stato.registra == nil { chiudi() }
    }
}

/// Panel state: the open tab and the shortcut being recorded.
final class StatoPannello: ObservableObject {
    enum Scheda: String, CaseIterable { case fila, postazioni, tasti, regole, guida
        var simbolo: String { ["fila": "rectangle.split.3x1", "postazioni": "square.stack", "tasti": "command", "regole": "slider.horizontal.3", "guida": "questionmark"][rawValue]! }
        var titolo: String { ["fila": "Row", "postazioni": "Workspaces", "tasti": "Shortcuts", "regole": "Settings", "guida": "How it works"][rawValue]! }
    }
    @Published var scheda: Scheda = UserDefaults.standard.bool(forKey: "guidaVista") ? .fila : .guida {
        didSet { DispatchQueue.main.async { Pannello.shared.ridimensiona() } }
    }
    init() { UserDefaults.standard.set(true, forKey: "guidaVista") }
    @Published var registra: Azione?
    private var monitor: Any?

    func registra(_ a: Azione) {
        fermaRegistrazione()
        registra = a
        Tasti.shared.sospendi()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let a = self.registra else { return e }
            if e.keyCode == 53 { self.fermaRegistrazione(); return nil }                 // Esc: leave as it was
            let c = Combo.da(e)
            // at least one of ⌘, ⌥ and ⌃ is needed, otherwise the shortcut would steal a letter from every app
            guard c.mod & UInt32(0x0100 | 0x0800 | 0x1000) != 0 else { NSSound.beep(); return nil }
            Tasti.shared.cambia(a, c)
            self.fermaRegistrazione()
            return nil
        }
    }

    func fermaRegistrazione() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if registra != nil { registra = nil; Tasti.shared.registra() }
    }
}

// MARK: - App icons (cached)

enum Icone {
    private static var cache: [String: NSImage] = [:]
    static func di(_ bundle: String) -> NSImage {
        if let i = cache[bundle] { return i }
        let i = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        cache[bundle] = i
        return i
    }
    static func nome(_ b: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: b).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? b
    }
}

// MARK: - Views

struct VistaPannello: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var s: StatoPannello

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            testa
            if !m.fidato { permesso.padding(.top, 16) }
            Group {
                switch s.scheda {
                case .fila: VistaFila()
                case .postazioni: VistaPostazioni()
                case .tasti: VistaTasti()
                case .regole: VistaRegole()
                case .guida: VistaGuida()
                }
            }
            .padding(.top, 18)
            piede.padding(.top, 18)
        }
        .padding(20)
        .frame(width: 392)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [t.alto, t.basso], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(t.chiaro ? 0.12 : 0.35), radius: 22, y: 10)
        )
        .padding(28)                          // room for the soft shadow
        .foregroundStyle(t.testo)
        .environment(\.colorScheme, t.schema)
        .animation(.easeOut(duration: 0.25), value: s.scheda)
    }

    private var testa: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rowline").font(.system(size: 22, weight: .semibold))
                    Text(m.acceso ? (m.quante == 1 ? "1 window in the row" : "\(m.quante) windows in the row")
                                  : "Off, windows are free")
                        .font(.system(size: 12)).foregroundStyle(t.t2)
                }
                Spacer()
                Toggle("", isOn: $m.acceso).toggleStyle(.switch).labelsHidden().tint(t.azzurro).controlSize(.small)
                    .help("Turn Rowline on or off (⌃⌥⌘P)")
            }
            HStack(spacing: 2) {
                ForEach(StatoPannello.Scheda.allCases, id: \.self) { k in
                    Bottone(simbolo: k.simbolo, acceso: s.scheda == k, aiuto: k.titolo) { s.scheda = k }
                }
            }
            .padding(3)
            .background(Capsule().fill(t.velo))
        }
    }

    private var permesso: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: 15)).foregroundStyle(t.azzurro)
            VStack(alignment: .leading, spacing: 2) {
                Text("One permission needed").font(.system(size: 13))
                Text("Accessibility, to arrange windows").font(.system(size: 11)).foregroundStyle(t.t2)
            }
            Spacer()
            Button("Open") {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(Pillola(principale: true))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.velo))
    }

    private var piede: some View {
        HStack {
            Button { m.adotta() } label: { Label("Tidy up", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(Pillola()).help("Puts the visible windows back in a row, left to right")
            Spacer()
            Button { NSApp.terminate(nil) } label: { Text("Quit") }.buttonStyle(Pillola())
        }
    }
}

/// The map: each screen is a row of tiles as wide as the real windows; the light frame is what you see.
struct VistaFila: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if m.mappa.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.3x1").font(.system(size: 22, weight: .light)).foregroundStyle(t.t3)
                    Text(m.acceso ? "No windows in the row" : "Rowline is off")
                        .font(.system(size: 13)).foregroundStyle(t.t2)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.velo))
            }
            ForEach(m.mappa) { st in RigaStriscia(st: st) }
            comandi
        }
    }

    private var comandi: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([Azione.precedente, .successiva, .spostaSx, .spostaDx, .centra, .galleggia]) { a in Comando(a: a) }
            }
            HStack(spacing: 6) {
                ForEach([Azione.stringi, .meta, .dueTerzi, .intera, .allarga, .impila]) { a in
                    Comando(a: a, testo: a == .meta ? "½" : a == .dueTerzi ? "⅔" : a == .intera ? "1" : nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The map: no frame over the tiles. Like the bottom bar:
/// tiles separated by a gap, filled for those on screen, dimmed for those out of view.
struct RigaStriscia: View {
    let st: StrisciaVista
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    private let alt: CGFloat = 92

    var body: some View {
        let k = alt / max(st.alta, 1)       // from screen points to map points
        let totale = (st.colonne.last.map { $0.x + $0.w } ?? 0) * k
        VStack(alignment: .leading, spacing: 8) {
            if !st.nome.isEmpty { Text(st.nome).font(.system(size: 11)).foregroundStyle(t.t3) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        ForEach(st.colonne) { c in
                            let dentro = c.x + c.w > st.scorrimento + 8 && c.x < st.scorrimento + st.vista - 8
                            VStack(spacing: 4) {
                                ForEach(Array(c.finestre.enumerated()), id: \.element.id) { j, f in
                                    Tessera(f: f, fuoco: c.fuoco && j == c.attiva)
                                }
                            }
                            .frame(width: max(c.w * k - 6, 18), height: alt)
                            .opacity(dentro ? 1 : 0.4)
                            .offset(x: c.x * k + 3)
                            .id(c.id)
                        }
                    }
                    .frame(width: max(totale, st.vista * k) + 6, height: alt, alignment: .topLeading)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.scorrimento)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.colonne.map(\.w))
                }
                .onAppear { if let f = st.colonne.first(where: \.fuoco) { proxy.scrollTo(f.id, anchor: .center) } }
            }
        }
    }
}

struct Tessera: View {
    let f: TesseraVista
    let fuoco: Bool
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @State private var sopra = false

    var body: some View {
        Button { m.scegli(f.id) } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fuoco ? t.azzurro.opacity(t.chiaro ? 0.18 : 0.16) : (sopra ? t.sel : t.velo))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(fuoco ? t.azzurro : t.linea, lineWidth: fuoco ? 1.2 : 1))
                .overlay(Image(nsImage: Icone.di(f.bundle)).resizable().interpolation(.high).frame(width: 22, height: 22))
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(f.app)
    }
}

struct Comando: View {
    let a: Azione
    var testo: String? = nil
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @State private var sopra = false

    var body: some View {
        Button { a.esegui() } label: {
            Group {
                if let testo { Text(testo).font(.system(size: 15, weight: .light)) }
                else { Image(systemName: a.simbolo).font(.system(size: 13, weight: .regular)) }
            }
            .frame(width: 50, height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sopra ? t.sel : t.velo))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help("\(a.titolo)  \(k.combo[a]?.testo ?? "")")
    }
}

/// Workspaces: a saved row (apps, order, widths) restored with a click or with ⌃⌥⌘4, 5, 6.
struct VistaPostazioni: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @State private var nome = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if m.postazioni.isEmpty {
                Text("Arrange your windows the way you like, name it and save. One click brings it back, opening any missing apps.")
                    .font(.system(size: 12)).foregroundStyle(t.t2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }
            ForEach(Array(m.postazioni.enumerated()), id: \.element.id) { i, p in riga(p, i) }
            HStack(spacing: 8) {
                TextField("Name, for example Study", text: $nome)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(t.velo))
                    .onSubmit(salva)
                Button("Save the row", action: salva).buttonStyle(Pillola(principale: true)).disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 14)
        }
    }

    private func salva() {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        m.salvaPostazione(n); nome = ""
    }

    private func riga(_ p: Postazione, _ i: Int) -> some View {
        let a: Azione? = i == 0 ? .postazione1 : i == 1 ? .postazione2 : i == 2 ? .postazione3 : nil
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.nome).font(.system(size: 14))
                    HStack(spacing: 4) {
                        ForEach(Array(p.posti.enumerated()), id: \.offset) { _, x in
                            Image(nsImage: Icone.di(x.bundle)).resizable().frame(width: 16, height: 16).help(x.app)
                        }
                    }
                }
                Spacer()
                if let a, let c = k.combo[a], c.mod != 0 { Text(c.testo).font(.system(size: 12)).foregroundStyle(t.t3) }
                Bottone(simbolo: "play.fill", acceso: false, aiuto: "Bring this row back") { m.applica(p) }
                Bottone(simbolo: "xmark", acceso: false, aiuto: "Delete") { m.postazioni.removeAll { $0.id == p.id } }
            }
            .frame(height: 56)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}

/// Shortcuts as data rows: action on the left, keys on the right. Click a row to record new keys.
struct VistaTasti: View {
    @EnvironmentObject var k: Tasti
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var s: StatoPannello

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Azione.allCases) { a in riga(a) }
                }
            }
            .frame(height: 330)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            HStack {
                Text("Click a row, then press the new keys. Esc cancels.").font(.system(size: 11)).foregroundStyle(t.t3)
                Spacer()
                Button("Defaults") { k.ripristina() }.buttonStyle(Pillola())
            }
            .padding(.top, 10)
            Text("Hold ⌃⌥⌘ for a second to see every shortcut.")
                .font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 8)
        }
    }

    private func riga(_ a: Azione) -> some View {
        let reg = s.registra == a
        return Button { reg ? s.fermaRegistrazione() : s.registra(a) } label: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: a.simbolo).font(.system(size: 12)).foregroundStyle(t.t3).frame(width: 22)
                    Text(a.titolo).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(reg ? "Press the keys" : (k.combo[a].map { $0.mod == 0 ? "None" : $0.testo } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(reg ? t.azzurro : t.t2)
                }
                .frame(height: 40)
                Rectangle().fill(t.linea).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct VistaRegole: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @ObservedObject private var barra = Barra.shared
    @ObservedObject private var gesto = Gesto.shared
    @ObservedObject private var ant = Anteprime.shared
    @State private var tasti = TastiVisti.shared.acceso

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                riga("hand.draw", "Trackpad swipe", Picker("", selection: $gesto.modo) {
                    ForEach(ModoGesto.allCases, id: \.self) { Text($0.titolo).tag($0) }
                }.pickerStyle(.menu).frame(width: 150))
                if gesto.modo.dita > 0 && ModoGesto.usateDalSistema(gesto.modo.dita) {
                    Text("macOS already uses \(gesto.modo.dita) fingers to switch desktops: pick the other number, or change it in Settings → Trackpad → More Gestures.")
                        .font(.system(size: 11)).foregroundStyle(t.t2).padding(.vertical, 8)
                }
                riga("arrow.left.arrow.right", "Reverse direction", Toggle("", isOn: $gesto.inverti))
                riga("wind", "Animations", Toggle("", isOn: $m.animazioni))
                riga("slider.horizontal.below.rectangle", "Bottom slider", Picker("", selection: $barra.modo) {
                    ForEach(ModoBarra.allCases, id: \.self) { Text($0.titolo).tag($0) }
                }.pickerStyle(.menu).frame(width: 150))
                riga("photo", "Previews in the slider", Toggle("", isOn: $ant.accese))
                if ant.accese && !ant.permesso {
                    Text("Needs Settings → Privacy → Screen Recording → Rowline.")
                        .font(.system(size: 11)).foregroundStyle(t.t2).padding(.vertical, 8)
                }
                riga("square.split.2x1", "Gap between windows", cursore($m.spazio, 0...24, 2))
                riga("rectangle.lefthalf.inset.filled.arrow.left", "Neighbours peeking in", cursore($m.sbirciata, 0...64, 8))
                riga("keyboard", "Show keys on screen", Toggle("", isOn: $tasti).onChange(of: tasti) { _, v in TastiVisti.shared.acceso = v })

                Text("Width per app").font(.system(size: 15, weight: .semibold)).padding(.top, 22)
                Text("Right-click a line in the slider to set one").font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 2)
                Pillole(voci: m.regoleApp.keys.sorted(), etichetta: { b in
                    let v = m.regoleApp[b] ?? 0.5
                    return abs(v - 1.0 / 3) < 0.01 ? "⅓" : abs(v - 0.5) < 0.01 ? "½" : abs(v - 2.0 / 3) < 0.01 ? "⅔" : "full"
                }, togli: { m.regoleApp[$0] = nil }).padding(.top, 12)

                Text("Always free").font(.system(size: 15, weight: .semibold)).padding(.top, 22)
                Text("These apps never join the row").font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 2)
                Pillole(voci: m.escluse, etichetta: { _ in nil }, togli: { b in m.escluse.removeAll { $0 == b } }).padding(.top, 12)
                if let a = m.appInFuoco, !m.escluse.contains(a.bundle) {
                    Button { m.liberaApp(a.bundle) } label: { Label("Leave \(a.nome) free", systemImage: "plus") }
                        .buttonStyle(Pillola()).padding(.top, 12)
                }
            }
        }
        .frame(maxHeight: 440)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private func cursore(_ v: Binding<Double>, _ r: ClosedRange<Double>, _ passo: Double) -> some View {
        HStack(spacing: 8) {
            Slider(value: v, in: r, step: passo).frame(width: 110).tint(t.azzurro)
            Text("\(Int(v.wrappedValue))").font(.system(size: 12)).foregroundStyle(t.t2).frame(width: 20, alignment: .trailing)
        }
    }

    private func riga<V: View>(_ simbolo: String, _ testo: String, _ v: V) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: simbolo).font(.system(size: 12)).foregroundStyle(t.t3).frame(width: 22)
                Text(testo).font(.system(size: 13)).lineLimit(1)
                Spacer()
                v.toggleStyle(.switch).labelsHidden().tint(t.azzurro).controlSize(.small)
            }
            .frame(height: 44)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}

/// App pills (icon, name, optional value, x to remove).
struct Pillole: View {
    let voci: [String]
    let etichetta: (String) -> String?
    let togli: (String) -> Void
    @EnvironmentObject var t: Tinta

    var body: some View {
        if voci.isEmpty {
            Text("None").font(.system(size: 12)).foregroundStyle(t.t2)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(voci, id: \.self) { b in
                    HStack(spacing: 8) {
                        Image(nsImage: Icone.di(b)).resizable().frame(width: 18, height: 18)
                        Text(Icone.nome(b)).font(.system(size: 12)).lineLimit(1)
                        if let e = etichetta(b) { Text(e).font(.system(size: 12)).foregroundStyle(t.azzurro) }
                        Spacer(minLength: 0)
                        Button { togli(b) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                            .buttonStyle(.plain).foregroundStyle(t.t3)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Capsule().fill(t.velo))
                }
            }
        }
    }
}

// MARK: - Small pieces

struct Bottone: View {
    let simbolo: String
    let acceso: Bool
    let aiuto: String
    let azione: () -> Void
    @EnvironmentObject var t: Tinta
    @State private var sopra = false

    var body: some View {
        Button(action: azione) {
            Image(systemName: simbolo).font(.system(size: 12))
                .foregroundStyle(acceso ? t.azzurro : t.t2)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(acceso || sopra ? t.sel : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(aiuto)
    }
}

struct Pillola: ButtonStyle {
    var principale = false
    func makeBody(configuration: Configuration) -> some View {
        PillolaCorpo(configuration: configuration, principale: principale)
    }
    private struct PillolaCorpo: View {
        let configuration: ButtonStyleConfiguration
        let principale: Bool
        @EnvironmentObject var t: Tinta
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .padding(.horizontal, 14).frame(height: 30)
                .foregroundStyle(principale ? (t.chiaro ? Color.white : Color(red: 0.075, green: 0.08, blue: 0.118)) : t.testo)
                .background(Capsule().fill(principale ? AnyShapeStyle(t.chiaro ? Color(white: 0.1) : .white) : AnyShapeStyle(t.velo)))
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// How it works, in five steps with one drawing each. Opens by itself the first time.
struct VistaGuida: View {
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @ObservedObject private var gesto = Gesto.shared

    var body: some View {
        let c: (Azione) -> String = { k.combo[$0]?.testo ?? "" }
        let dita = gesto.modo == .tre ? "three fingers on the trackpad"
            : gesto.modo == .quattro ? "four fingers on the trackpad"
            : gesto.modo == .opzione ? "⌥ and two fingers on the trackpad" : "the bottom slider"
        VStack(alignment: .leading, spacing: 0) {
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: 1, "Your windows sit in a row",
                  "Every window gets its own spot, side by side. New ones land on the right.")
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: 2, "Slide along",
                  "\(c(.precedente)) and \(c(.successiva)), or \(dita). The lines at the bottom show where you are.")
            tappa(disegno: [1.0 / 3, 2.0 / 3, 0.5], fuoco: 1, "Change the width",
                  "\(c(.meta)) half, \(c(.dueTerzi)) two thirds, \(c(.intera)) full, \(c(.allarga)) and \(c(.stringi)) in small steps.")
            tappa(disegno: [0.5, 0.5], fuoco: 0, pila: true, "Stack",
                  "\(c(.impila)) stacks the window onto the one on the left, \(c(.stacca)) pops it out.")
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: -1, "Forgot a shortcut?",
                  "Hold ⌃⌥⌘ for a second and every shortcut appears.")
        }
    }

    private func tappa(disegno: [CGFloat], fuoco: Int, pila: Bool = false, _ titolo: String, _ testo: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(Array(disegno.enumerated()), id: \.offset) { i, w in
                        VStack(spacing: 3) {
                            ForEach(0..<(pila && i == 0 ? 2 : 1), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(i == fuoco ? t.azzurro : t.testo.opacity(0.16))
                            }
                        }
                        .frame(width: w * 30)
                    }
                }
                .frame(width: 62, height: 34, alignment: .leading)
                .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(titolo).font(.system(size: 14))
                    Text(testo).font(.system(size: 12)).foregroundStyle(t.t2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}
