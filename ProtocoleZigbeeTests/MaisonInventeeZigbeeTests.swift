import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Versions Zigbee des fixtures neutres du coeur (`MaisonInventee`, `FixturesScene.graphe(sonde:)`) : le code d'origine,
/// qui passe par `MaillageZigbee` et `GrapheReseau(maillage:appareils:)`. Les tests d'equivalence prouvent que les
/// versions ecrites a la main donnent le meme graphe, aux champs propres a un protocole pres : `partition` (celle de
/// Zigbee est unique), `bordure` (Zigbee n'en a pas, les fixtures du coeur en ont) et `extMac` des routeurs.
enum MaisonInventeeZigbee {
    static func routeur(_ k: Int) -> String { String(format: "Routeur %02d", k) }
    static func appareil(_ j: Int) -> String { String(format: "E2%014X", j) }

    static func graphe(pieces: Int, routeurs: Int, appareils: Int) -> GrapheReseau {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var noeuds = (0..<routeurs).map { k in
            NoeudZigbee(ieee: routeur(k), court: UInt16(k), type: k == 0 ? .coordinateur : .routeur)
        }
        noeuds += (0..<appareils).map { NoeudZigbee(ieee: appareil($0), court: UInt16(0x1000 + $0), type: .final) }
        // Chaque lien : qualite 3 d'un cote, 2 de l'autre (la moins bonne, 2, est affichee).
        let liens = (1..<max(routeurs, 1)).map { k in
            LienRadioZigbee(mesurePar: routeur(k - 1), de: routeur(k), lqi: 200, date: date)
                .fusionner(LienRadioZigbee(mesurePar: routeur(k), de: routeur(k - 1), lqi: 120, date: date))
        }
        let parents = (0..<appareils).map { j in
            LienParent(enfant: appareil(j), parent: routeur((j % pieces) % routeurs), lqi: 120, date: date)
        }
        let m = MaillageZigbee(date: date, noeuds: noeuds, liens: liens, parents: parents)
        let apps = (0..<routeurs).map { AppareilAffiche(id: routeur($0), nom: routeur($0), etat: .joignable) }
            + (0..<appareils).map { AppareilAffiche(id: appareil($0), nom: appareil($0), etat: .joignable) }
        return GrapheReseau(maillage: m, appareils: apps)
    }
}

enum ScenePiecesZigbee {
    /// Petit reseau : l'Apple TV (le coordinateur, couronne) et le HomePod, routeurs ; quatre appareils. Sans la
    /// sonde, aucun lien, et E...04 est un appareil final. Avec la sonde : E...04 route, E...02 est l'enfant de l'Apple
    /// TV, E...03 celui du HomePod ; E...05 n'a pas de parent connu : il porte un rattachement suppose a l'Apple TV, que
    /// le graphe Zigbee ne trace pas, mais que la scene et sa projection savent encore dessiner.
    static func grapheZigbee(sonde: Bool) throws -> GrapheReseau {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var noeuds = [NoeudZigbee(ieee: "Apple TV", court: 0, type: .coordinateur),
                      NoeudZigbee(ieee: "HomePod", court: 0x1000, type: .routeur)]
        noeuds += (2...5).map { k in
            NoeudZigbee(ieee: String(format: "E00000000000000%d", k), court: UInt16(0x2000 + k),
                        type: sonde && k == 4 ? .routeur : .final)
        }
        let apps = noeuds.map { AppareilAffiche(id: $0.ieee, nom: $0.ieee, etat: .joignable) }
        guard sonde else { return GrapheReseau(maillage: MaillageZigbee(date: date, noeuds: noeuds), appareils: apps) }
        let liens = [LienRadioZigbee(a: "Apple TV", b: "HomePod", lqiA: 200, lqiB: 120),
                     LienRadioZigbee(a: "Apple TV", b: "E000000000000004", lqiA: 120, lqiB: 120)]
        let parents = [LienParent(enfant: "E000000000000002", parent: "Apple TV", lqi: 200),
                       LienParent(enfant: "E000000000000003", parent: "HomePod", lqi: 120)]
        let m = MaillageZigbee(date: date, noeuds: noeuds, liens: liens, parents: parents)
        let g = GrapheReseau(maillage: m, appareils: apps)
        return GrapheReseau(noeuds: g.noeuds, liens: g.liens + [GrapheReseau.Lien(de: "E000000000000005", vers: "Apple TV")])
    }
}

@Suite("Fixtures du coeur : a la main == construites par Zigbee (aux champs du protocole pres)")
struct FixturesZigbeeTests {
    /// Ce qu'un noeud a en commun avec son equivalent ecrit a la main : tout sauf `partition`, `bordure` et `extMac`.
    typealias Commun = [String: [String]]
    static func commun(_ g: GrapheReseau) -> Commun {
        Dictionary(uniqueKeysWithValues: g.noeuds.map {
            ($0.id, ["\($0.genre)", "\($0.routeur)", "\($0.inconnu)"])
        })
    }

    static func cle(_ l: GrapheReseau.Lien) -> String { "\(l.de)>\(l.vers)|\(l.genre)|\(String(describing: l.qualite))|\(l.suppose)" }

    /// Les noeuds sont les memes (a l'ordre pres : Zigbee classe d'abord les routeurs) et les liens de la sonde aussi.
    /// Une difference de sens : E...04, qui route avec la sonde, est pour les fixtures du coeur un appareil qui route
    /// (genre `appareil`, comme sous Thread) et pour Zigbee un routeur (genre `routeur`). Sans sonde, le graphe Zigbee
    /// n'a aucun lien (les fixtures du coeur rattachent chaque noeud au centre). Zigbee est a une seule partition, sans
    /// routeur de bordure.
    @Test(arguments: [false, true])
    func grapheDeLaScene(sonde: Bool) throws {
        let manuel = try FixturesScene.graphe(sonde: sonde)
        let zigbee = try ScenePiecesZigbee.grapheZigbee(sonde: sonde)
        var attendu = Self.commun(manuel)
        if sonde { attendu["E000000000000004"] = ["routeur", "true", "false"] }
        #expect(attendu == Self.commun(zigbee))
        #expect(manuel.noeuds.count == 6 && zigbee.noeuds.count == 6)
        #expect(zigbee.noeuds.allSatisfy { $0.partition == GrapheReseau.partitionUnique && !$0.bordure })
        if sonde {
            #expect(Set(manuel.liens.map(Self.cle)) == Set(zigbee.liens.map(Self.cle)))
            #expect(manuel.liens.count == zigbee.liens.count)
        } else {
            #expect(zigbee.liens.isEmpty)
        }
    }

    /// Les maisons des tests de disposition, plus un seul routeur et moins de pieces que de routeurs.
    @Test(arguments: [(3, 2, 5), (6, 3, 20), (8, 4, 30), (12, 4, 50), (20, 6, 100), (4, 1, 6), (2, 3, 7)])
    func maisonInventee(_ maison: (pieces: Int, routeurs: Int, appareils: Int)) {
        let manuel = MaisonInventee.graphe(pieces: maison.pieces, routeurs: maison.routeurs, appareils: maison.appareils)
        let zigbee = MaisonInventeeZigbee.graphe(pieces: maison.pieces, routeurs: maison.routeurs,
                                                 appareils: maison.appareils)
        #expect(Self.commun(manuel) == Self.commun(zigbee))
        #expect(manuel.noeuds.count == maison.routeurs + maison.appareils && zigbee.noeuds.count == manuel.noeuds.count)
        #expect(manuel.noeuds.map(\.id) == zigbee.noeuds.map(\.id), "meme ordre : routeurs puis appareils")
        #expect(Set(manuel.liens.map(Self.cle)) == Set(zigbee.liens.map(Self.cle)))
        #expect(manuel.liens.count == zigbee.liens.count)
        #expect(zigbee.noeuds.allSatisfy { $0.partition == GrapheReseau.partitionUnique && !$0.bordure })
    }
}
