// Rowline: the BAR. A thin line per window, as wide as the window. Lines on screen are brighter,
// lines out of view are almost off, the active one is light blue. On hover the lines get thicker (easier to
// click). When you change window, the app name and its position ("Chrome  2 of 5") appear for a moment above.
// Click a line: go to that window. Drag: the bright part slides and, on release, the row follows.

import AppKit
import SwiftUI
import Combine

enum ModoBarra: String, CaseIterable { case sempre, quandoCambi, mai
    var titolo: String { self == .sempre ? "Always" : self == .quandoCambi ? "When it changes" : "Never" }
}

final class Barra: ObservableObject {
    static let shared = Barra()
    static var alta: CGFloat { Anteprime.shared.accese ? 230 : 44 }
    static let margine: CGFloat = 4, larghezzaVista: CGFloat = 64, massima: CGFloat = 300

    @Published var modo: ModoBarra = ModoBarra(rawValue: UserDefaults.standard.string(forKey: "barra") ?? "") ?? .sempre {
        didSet { UserDefaults.standard.set(modo.rawValue, forKey: "barra"); aggiorna(); Motore.shared.disponiTutto() }
    }
    /// How much room the windows leave free at the bottom: just the strip of lines.
    static var riserva: CGFloat { shared.modo == .sempre ? 16 : 0 }

    private var pannelli: [CGDirectDisplayID: NSPanel] = [:]
    private var sub: AnyCancellable?
    private var spegni: DispatchWorkItem?

    func avvia() {
        sub = Motore.shared.$mappa.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.aggiorna(mostra: true) }
        }
        aggiorna()
    }

    /// Common scale: the screen becomes `larghezzaVista` wide, the whole row at most `massima`.
    static func scala(_ st: StrisciaVista) -> CGFloat {
        let totale = max(st.colonne.last.map { $0.x + $0.w } ?? 1, st.vista)
        return min(larghezzaVista / max(st.vista, 1), massima / totale)
    }
    static func larghezza(_ st: StrisciaVista) -> CGFloat {
        (st.colonne.last.map { $0.x + $0.w } ?? 1) * scala(st)
    }

    func aggiorna(mostra: Bool = false) {
        let m = Motore.shared
        let attivi = Set(modo == .mai || !m.acceso ? [] : m.mappa.map(\.id))
        for (id, p) in pannelli where !attivi.contains(id) { p.orderOut(nil); pannelli[id] = nil }
        for st in m.mappa where attivi.contains(st.id) {
            guard let sc = NSScreen.screens.first(where: { $0.numero == st.id }) else { continue }
            let p = pannelli[st.id] ?? crea(st.id)
            pannelli[st.id] = p
            let w = max(Barra.larghezza(st) + 40, Anteprime.shared.accese ? 300 : 220)       // wide enough for the app name
            let v = sc.visibleFrame
            p.setFrame(NSRect(x: v.midX - w / 2, y: v.minY + Barra.margine, width: w, height: Barra.alta), display: true)
            if modo == .sempre || mostra { p.alphaValue = 1; p.orderFrontRegardless() }
        }
        if modo == .quandoCambi && mostra {
            spegni?.cancel()
            let w = DispatchWorkItem { [weak self] in
                self?.pannelli.values.forEach { p in NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) }) }
            }
            spegni = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w)
        }
    }

    private func crea(_ id: CGDirectDisplayID) -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovable = false
        let host = NSHostingView(rootView: VistaBarra(schermo: id).environmentObject(Motore.shared).environmentObject(Tinta.shared).environmentObject(Anteprime.shared))
        host.layer?.backgroundColor = .clear
        p.contentView = host
        return p
    }
}

struct VistaBarra: View {
    let schermo: CGDirectDisplayID
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var ant: Anteprime
    @State private var trascina: CGFloat?
    @State private var sopraID: CGWindowID?
    @State private var sopra = false
    @State private var sopraApp: String?
    @State private var etichetta = false
    @State private var nascondi: DispatchWorkItem?

    var body: some View {
        if let st = m.mappa.first(where: { $0.id == schermo }) {
            let k = Barra.scala(st)
            let totale = st.colonne.last.map { $0.x + $0.w } ?? 1
            let s = trascina ?? st.scorrimento
            let alto: CGFloat = sopra || trascina != nil ? 8 : 4
            VStack(spacing: 7) {
                Spacer(minLength: 0)
                // the window preview under the cursor (if enabled and permitted)
                if let id = sopraID, let img = ant.immagini[id] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 260, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
                // the name: appears when you change window or hover a line, with a halo and no box
                Text(testo(st))
                    .font(.system(size: 11))
                    .foregroundStyle(t.testo.opacity(0.9))
                    .shadow(color: (t.chiaro ? Color.white : Color.black).opacity(0.7), radius: 4)
                    .opacity(etichetta || sopraApp != nil || trascina != nil ? 1 : 0)
                    .allowsHitTesting(false)
                // One single line as long as the row:
                // brighter where the screen is, light blue on the focused window. Click and hover read the column under the point.
                let colonna: (CGFloat) -> ColonnaVista? = { x in
                    st.colonne.min { abs(($0.x + $0.w / 2) * k - x) < abs(($1.x + $1.w / 2) * k - x) }
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(t.testo.opacity(t.chiaro ? 0.16 : 0.2))
                        .frame(width: max(totale * k, 6), height: alto)
                    Capsule().fill(t.testo.opacity(t.chiaro ? 0.5 : 0.6))
                        .frame(width: max(min(st.vista, totale) * k, 6), height: alto)
                        .offset(x: s * k)
                    if trascina == nil, let c = st.colonne.first(where: \.fuoco) {
                        Capsule().fill(t.azzurro)
                            .frame(width: max(c.w * k - 2, 6), height: alto)
                            .offset(x: c.x * k + 1)
                    }
                }
                .contentShape(Rectangle().inset(by: -6))
                .onContinuousHover { fase in
                    switch fase {
                    case .active(let p):
                        if let c = colonna(p.x), let f = c.finestre[safe: c.attiva] { sopraApp = f.app; sopraID = f.id; ant.chiedi(f.id) }
                    case .ended: sopraApp = nil; sopraID = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { p in
                    if let c = colonna(p.x), let f = c.finestre[safe: c.attiva] { m.scegli(f.id) }
                }
                .contextMenu {
                    if let id = sopraID, let f = st.colonne.flatMap(\.finestre).first(where: { $0.id == id }) { menu(f) }
                }
                .frame(width: totale * k, height: 8, alignment: .leading)
                .shadow(color: .black.opacity(t.chiaro ? 0.08 : 0.35), radius: 2, y: 0.5)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onHover { sopra = $0 }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        let max0 = max(0, totale - st.vista)
                        trascina = min(max0, max(0, st.scorrimento + v.translation.width / k))
                    }
                    .onEnded { _ in
                        if let x = trascina { m.scorriA(schermo, x) }
                        trascina = nil
                    })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 2)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.scorrimento)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.colonne.map(\.w))
            .animation(.easeOut(duration: 0.2), value: alto)
            .animation(.easeOut(duration: 0.25), value: etichetta)
            .animation(.easeOut(duration: 0.2), value: sopraApp)
            .animation(.easeOut(duration: 0.2), value: sopraID)
            .onChange(of: st.fuoco?.posto) { _, _ in mostraEtichetta() }
            .onChange(of: st.fuoco?.app) { _, _ in mostraEtichetta() }
            .environment(\.colorScheme, t.schema)
        }
    }

    /// Right click on a line: fixed width for that app, leave it free, or float it.
    @ViewBuilder private func menu(_ f: TesseraVista) -> some View {
        let r = m.regoleApp[f.bundle]
        Text("\(f.app): when it opens")
        ForEach([(1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (1.0, "Full")], id: \.0) { v, n in
            Button((r.map { abs($0 - v) < 0.01 } ?? false ? "✓ " : "") + "Always " + n) { m.regoleApp[f.bundle] = v }
        }
        if r != nil { Button("No rule") { m.regoleApp[f.bundle] = nil } }
        Divider()
        Button("Leave \(f.app) free") { m.liberaApp(f.bundle) }
    }

    private func testo(_ st: StrisciaVista) -> String {
        if let a = sopraApp { return a }
        guard let f = st.fuoco else { return "" }
        return "\(f.app)   \(f.posto) " + "of" + " \(f.totale)"
    }

    private func mostraEtichetta() {
        etichetta = true
        nascondi?.cancel()
        let w = DispatchWorkItem { etichetta = false }
        nascondi = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }
}
