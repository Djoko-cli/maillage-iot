import AppKit
import Foundation
import MaillageCoeur
import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Fiche a l'heure de la fenetre du graphe")
struct FicheHeureTests {
    /// Un appareil des premiers releves de la panne rejouee.
    static let appareil = "56B1E064401F74EF"

    /// L'heure de la fenetre (celle de sa TimelineView), ou la fin de la panne rejouee en demo.
    @Test func maintenantALHeureDeLaFenetre() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let direct = Surveillance(mode: .direct, dossier: nil)
        #expect(direct.maintenant(a: t) == t)
        let demo = Surveillance(mode: .demo, dossier: nil)
        demo.demarrer()
        #expect(demo.maintenant(a: t) == demo.maintenant, "la fin de la panne, quelle que soit l'heure")
        #expect(demo.maintenant(a: t) != t)
    }

    /// La fiche d'un appareil lit l'heure qu'on lui donne, pas l'horloge du Mac : « vu il y a … » change
    /// avec elle (rendu de la fiche a deux heures), et deux rendus a la meme heure sont identiques.
    @Test func ficheSuitSonHeure() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        for a in ScenarioPanne.releves.prefix(12) { s.integrer(a) }
        let vu = try #require(s.instantane?.date)
        func rendu(_ instant: Date) -> Data? {
            let fiche = FicheNoeud(id: Self.appareil, entree: nil, instant: instant, aRenommer: .constant(nil), fermer: {})
                .environment(s)
                .frame(width: 1000)
            return ImageRenderer(content: fiche).nsImage?.tiffRepresentation
        }
        let uneMinute = try #require(rendu(vu.addingTimeInterval(60)))
        #expect(rendu(vu.addingTimeInterval(60)) == uneMinute)
        #expect(rendu(vu.addingTimeInterval(3 * 3600)) != uneMinute)
    }

    /// L'heure de la fiche est un debut de minute : une date plus recente se lit « maintenant »,
    /// jamais dans le futur ; une date passee reste relative. Independant de la langue.
    @Test func jamaisDansLeFutur() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(FicheNoeud.relatif(t.addingTimeInterval(20), t) == FicheNoeud.relatif(t, t))
        #expect(FicheNoeud.relatif(t.addingTimeInterval(-120), t) != FicheNoeud.relatif(t, t))
    }
}
