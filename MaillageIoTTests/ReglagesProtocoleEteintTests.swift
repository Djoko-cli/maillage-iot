import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

/// L'onglet d'un protocole eteint (spec 6.7, decision 5) : tout est grise, sauf « Activer ce protocole » qui le rallume.
/// Une seule regle pour Thread et Zigbee ; les controles ajoutes plus tard a ces pages sont couverts sans qu'on y pense
/// (`PageProtocole` grise tout ce qui suit l'interrupteur). On regarde les vrais controles AppKit de la page, hors ecran.
@MainActor
@Suite("Reglages : onglet d'un protocole eteint", .serialized, .timeLimit(.minutes(1)))
struct ReglagesProtocoleEteintTests {
    /// Les controles AppKit de la page, dans l'ordre de l'arbre, sans les barres de defilement du formulaire.
    static func controles(_ v: NSView) -> [NSControl] {
        var ici: [NSControl] = []
        if let c = v as? NSControl, !(c is NSScroller) { ici = [c] }
        return ici + v.subviews.flatMap { controles($0) }
    }

    /// L'interrupteur « Activer ce protocole » (le premier interrupteur de la page : il est en tete) et tous les autres
    /// controles de la page.
    static func lire(_ onglets: OngletsReglages) -> (interrupteur: NSControl?, autres: [NSControl]) {
        let page = onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view
        let tous = controles(page)
        let i = tous.firstIndex { String(describing: type(of: $0)).contains("Switch") }
        return (i.map { tous[$0] }, tous.enumerated().filter { $0.offset != i }.map(\.element))
    }

    /// Laisse SwiftUI appliquer l'etat (le changement de `actif` passe par l'observation, puis une mise en page).
    static func attendre(_ onglets: OngletsReglages, jusqua condition: (NSControl?, [NSControl]) -> Bool) async throws {
        for _ in 0..<60 {
            let (i, a) = lire(onglets)
            if condition(i, a) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Thread avec sa liaison reseau proposee (acces autorise) : le choix de liaison est alors un controle de plus.
    static func sondeThreadAvecReseau() throws -> SondeMaillageThread {
        let (p, _) = try SondeMaillageTests.preferences()
        let t = try SondeReseauTests.prete(p, liaison: .usb)
        return SondeReseauTests.sondeMaillage(p, trousseau: t)
    }

    @Test(arguments: [Protocole.thread, Protocole.zigbee])
    func ongletGriseProtocoleEteint(_ protocole: Protocole) async throws {
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let modele = try #require(surveillance.modele(pour: protocole))
        let (fenetre, onglets) = try await ReglagesHauteurTests.fenetre(
            onglet: protocole == .thread ? .thread : .zigbee,
            sondeThread: protocole == .thread ? try Self.sondeThreadAvecReseau() : nil,
            surveillance: surveillance)
        defer { fenetre.close() }

        // Allume : l'interrupteur et les controles de la page sont actifs.
        try await Self.attendre(onglets) { i, a in i != nil && !a.isEmpty && a.allSatisfy { $0.isEnabled } }
        var (interrupteur, autres) = Self.lire(onglets)
        #expect(interrupteur?.isEnabled == true, "l'interrupteur est actif")
        #expect(!autres.isEmpty, "des controles sous l'interrupteur")
        #expect(autres.allSatisfy { $0.isEnabled }, "allume, rien n'est grise")

        // Eteint : tout est grise sauf l'interrupteur, qui reste la pour rallumer.
        modele.actif = false
        try await Self.attendre(onglets) { _, a in a.allSatisfy { !$0.isEnabled } }
        (interrupteur, autres) = Self.lire(onglets)
        #expect(interrupteur?.isEnabled == true, "eteint, l'interrupteur reste actif")
        #expect(!autres.isEmpty)
        #expect(autres.allSatisfy { !$0.isEnabled }, "eteint, tout le reste est grise : \(autres.filter { $0.isEnabled }.map { type(of: $0) })")

        // Rallume : tout redevient actif.
        modele.actif = true
        try await Self.attendre(onglets) { _, a in a.allSatisfy { $0.isEnabled } }
        (interrupteur, autres) = Self.lire(onglets)
        #expect(interrupteur?.isEnabled == true)
        #expect(autres.allSatisfy { $0.isEnabled }, "rallume, les controles reviennent")
    }

    /// Ce que voit un controle de la page : l'etat « actif » de son environnement, note a chaque changement.
    @MainActor final class Releve { var valeurs: [String: Bool] = [:] }

    struct Sonde: View {
        let nom: String
        let releve: Releve
        @Environment(\.isEnabled) private var actif
        var body: some View {
            Color.clear.frame(width: 1, height: 1).onChange(of: actif, initial: true) { releve.valeurs[nom] = actif }
        }
    }

    /// Les controles ajoutes a une page de protocole sont grises sans rien faire de plus : bouton, choix, saisie, et une
    /// vue sur mesure (Thread « Automatique », ajoute en 3b) ; tous suivent l'interrupteur, y compris ceux que SwiftUI
    /// dessine lui-meme (invisibles parmi les controles AppKit de la page).
    @Test(arguments: [Protocole.thread, Protocole.zigbee])
    func toutCeQuiSuitLInterrupteurEstGrise(_ protocole: Protocole) async throws {
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let modele = try #require(surveillance.modele(pour: protocole))
        let releve = Releve()
        let page = FenetreReglages.page {
            PageProtocole(protocole: protocole) {
                Section("Un") {
                    Button("Bouton") {}
                    Sonde(nom: "bouton", releve: releve)
                    Picker("Choix", selection: .constant(1)) { Text("A").tag(1) }
                    Sonde(nom: "choix", releve: releve)
                }
                Section("Deux") {
                    TextField("Saisie", text: .constant(""))
                    Sonde(nom: "saisie", releve: releve)
                }
            }
        }
        .environment(surveillance)
        let hote = NSHostingView(rootView: page)
        let fenetre = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 560, height: 600), styleMask: [.titled],
                               backing: .buffered, defer: false)
        fenetre.contentView = hote
        fenetre.alphaValue = 0
        fenetre.orderFrontRegardless()
        defer { fenetre.close() }
        let noms = ["bouton", "choix", "saisie"]
        func attendre(_ voulu: Bool) async throws {
            for _ in 0..<60 where !(noms.allSatisfy { releve.valeurs[$0] == voulu }) {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await attendre(true)
        #expect(noms.allSatisfy { releve.valeurs[$0] == true }, "allume : \(releve.valeurs)")
        modele.actif = false
        try await attendre(false)
        #expect(noms.allSatisfy { releve.valeurs[$0] == false }, "eteint : \(releve.valeurs)")
        modele.actif = true
        try await attendre(true)
        #expect(noms.allSatisfy { releve.valeurs[$0] == true }, "rallume : \(releve.valeurs)")
    }
}
