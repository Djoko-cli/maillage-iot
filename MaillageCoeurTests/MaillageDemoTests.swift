import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Maillage de demo")
struct MaillageDemoTests {
    /// Sur le releve du 28/09 : les routeurs de bordure de la principale, dont un
    /// muet, deux appareils qui routent, les autres en enfants, un enfant inconnu.
    @Test func surLeReleve() throws {
        let i = Instantane(annonces: Releve20260928.annonces)
        let r = try #require(i.reseaux.first)
        let p = try #require(r.principale)
        let m = try #require(MaillageDemo.maillage(i, date: Releve20260928.annonces.date))
        #expect(m.partition == p.id)
        #expect(m.routeurs.count == p.routeurs.count + 2)
        #expect(m.routeurs.filter(\.muet).count == 1)
        #expect(m.routeurs.filter(\.bordure).count == p.routeurs.count)
        #expect(m.chef?.id == 1)
        #expect(!m.liens.isEmpty)
        let affiche = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils)
        #expect(affiche.inconnus.map(\.id) == ["rloc:041F"], "tous les routeurs reconnus ; un enfant inconnu")
        #expect(affiche.routeurs.values.filter { $0.bordure }.allSatisfy { $0.reconnu })
        // La sonde : le premier enfant, un appareil reconnu.
        let sonde = try #require(m.enfants.first { $0.source == .sonde })
        #expect(m.enfants.filter { $0.source == .sonde }.count == 1)
        #expect(affiche.sonde == affiche.enfants[sonde.rloc16]?.id && affiche.enfants[sonde.rloc16]?.reconnu == true)
        let muet = try #require(m.routeurs.first { $0.muet })
        #expect(m.enfants(de: muet.id).allSatisfy { $0.qualite == nil && $0.source == .resolution })
    }

    /// Routeurs de bordure laisses sans identite : non identifies, chacun avec les deux annonces
    /// pour candidates ; le reste du maillage ne change pas.
    @Test func sansIdentite() throws {
        let i = Instantane(annonces: Releve20260928.annonces)
        let r = try #require(i.reseaux.first)
        let date = Releve20260928.annonces.date
        let m = try #require(MaillageDemo.maillage(i, date: date, sansIdentite: ["HomePod Avant", "HomePod Palier"]))
        let affiche = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils)
        let inconnus = affiche.inconnus.filter { $0.genre == .routeur }
        #expect(inconnus.map(\.rloc16) == [0x1400, 0x2400])
        #expect(inconnus.allSatisfy { $0.bordure && $0.candidats == ["HomePod Avant", "HomePod Palier"] })
        #expect(affiche.annoncesCandidates == ["HomePod Avant", "HomePod Palier"])
        let complet = try #require(MaillageDemo.maillage(i, date: date))
        #expect(m.liens == complet.liens && m.enfants == complet.enfants)
    }
}
