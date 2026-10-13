import Foundation
import Testing
@testable import MaillageCoeur

/// Versions Thread des fixtures neutres du coeur (`MaisonInventee`, `FixturesScene.graphe(sonde:)`) :
/// le code d'origine, qui passe par `Banc`, `Instantane`, `ConstructionMaillage` et `MaillageAffiche`.
/// Les tests d'equivalence prouvent que les versions ecrites a la main donnent exactement le meme graphe.
enum MaisonInventeeThread {
    static let partition = "0000000A"

    static func routeur(_ k: Int) -> String { String(format: "Routeur %02d", k) }
    static func appareil(_ j: Int) -> String { String(format: "E2%014X", j) }
    static func extMacRouteur(_ k: Int) -> String { String(format: "E1%014X", k) }

    static func graphe(pieces: Int, routeurs: Int, appareils: Int) -> GrapheReseau {
        var b = Banc()
        let omr = "fd00:5555:6666::/64"
        for k in 0..<routeurs {
            b.routeur(routeur(k), partition: partition, role: k == 0 ? .chef : .routeur, primaire: k == 0,
                      lien: "fe80::\(k + 1)", omr: omr, xa: extMacRouteur(k))
        }
        for j in 0..<appareils {
            b.appareil(appareil(j), noeud: j + 1, adresses: [String(format: "fd00:5555:6666:0:b00::%x", j + 1)])
        }
        let i = Instantane(annonces: b.annonces)
        let r = i.reseaux[0]
        let apps = i.appareils.map { AppareilAffiche(id: $0.id, nom: $0.id, partition: $0.partition, etat: .joignable) }
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: partition)
        c.routeurs(Route64(sequence: 0, routes: (1...routeurs).map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 1)
        for k in 0..<routeurs {
            c.identite(extMacRouteur(k), routeur: k + 1)
            c.marquer(k + 1, bordure: true, bbrPrincipal: k == 0)
            if k > 0 { c.lien(k, k + 1, sortante: 3, entrante: 2) }
        }
        var enfants = [Int](repeating: 0, count: routeurs + 1)
        for j in 0..<appareils {
            let parent = (j % pieces) % routeurs + 1
            enfants[parent] += 1
            c.enfant(EnfantMaillage(rloc16: UInt16(parent) << 10 | UInt16(enfants[parent]), extMac: appareil(j), qualite: 2,
                                    source: .tableEnfants))
        }
        let m = MaillageAffiche(maillage: c.maillage(), reseau: r, appareils: i.appareils)
        return GrapheReseau(reseau: r, appareils: apps, maillage: m)
    }
}

enum ScenePiecesThread {
    static let partition = "46CBEBCD"

    static func grapheThread(sonde: Bool) throws -> GrapheReseau {
        var b = Banc()
        let omr = "fd00:5555:6666::/64"
        b.routeur("Apple TV", partition: partition, role: .chef, primaire: true, lien: "fe80::1", omr: omr,
                  xa: "E0000000000000A1")
        b.routeur("HomePod", partition: partition, lien: "fe80::2", omr: omr, xa: "E0000000000000A2")
        for k in 2...5 {
            b.appareil(String(format: "E00000000000000%d", k), noeud: k, adresses: ["fd00:5555:6666:0:b00::\(k)"])
        }
        let i = Instantane(annonces: b.annonces)
        let r = try #require(i.reseaux.first)
        let apps = i.appareils.map { AppareilAffiche(id: $0.id, nom: $0.id, partition: $0.partition, etat: .joignable) }
        guard sonde else { return GrapheReseau(reseau: r, appareils: apps) }
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: partition)
        c.routeurs(Route64(sequence: 0, routes: (1...3).map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 1)
        c.identite("E0000000000000A1", routeur: 1)
        c.identite("E0000000000000A2", routeur: 2)
        c.identite("E000000000000004", routeur: 3)
        c.marquer(1, bordure: true, bbrPrincipal: true)
        c.marquer(2, bordure: true)
        c.lien(1, 2, sortante: 3, entrante: 2)
        c.lien(1, 3, sortante: 2, entrante: 2)
        c.enfant(EnfantMaillage(rloc16: 0x0401, extMac: "E000000000000002", qualite: 3, source: .tableEnfants))
        c.enfant(EnfantMaillage(rloc16: 0x0801, extMac: "E000000000000003", qualite: 2, source: .tableEnfants))
        let m = MaillageAffiche(maillage: c.maillage(), reseau: r, appareils: i.appareils)
        return GrapheReseau(reseau: r, appareils: apps, maillage: m)
    }
}

@Suite("Fixtures du coeur : a la main == construites par Thread")
struct FixturesThreadTests {
    @Test(arguments: [false, true])
    func grapheDeLaScene(sonde: Bool) throws {
        let manuel = try FixturesScene.graphe(sonde: sonde)
        let thread = try ScenePiecesThread.grapheThread(sonde: sonde)
        #expect(manuel == thread)
        #expect(manuel.noeuds.count == 6)
    }

    /// Les maisons des tests de disposition, plus un seul routeur et moins de pieces que de routeurs.
    @Test(arguments: [(3, 2, 5), (6, 3, 20), (8, 4, 30), (12, 4, 50), (20, 6, 100), (4, 1, 6), (2, 3, 7)])
    func maisonInventee(_ maison: (pieces: Int, routeurs: Int, appareils: Int)) {
        let manuel = MaisonInventee.graphe(pieces: maison.pieces, routeurs: maison.routeurs, appareils: maison.appareils)
        let thread = MaisonInventeeThread.graphe(pieces: maison.pieces, routeurs: maison.routeurs,
                                                 appareils: maison.appareils)
        #expect(manuel == thread)
        #expect(manuel.noeuds.count == maison.routeurs + maison.appareils)
    }
}
