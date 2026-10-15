import Foundation
@testable import MaillageCoeur

/// Fixtures de scene partagees, sans test ni suite : le coeur et les tests Thread les compilent tous deux.
enum FixturesScene {
    static let partition = "46CBEBCD"

    /// La regle de classement des tests du coeur, qui ne depend d'aucun protocole : rang dans sa carte (1 routeur de
    /// bordure, 2 autre routeur, 3 autre noeud) et rayon de pastille (15 le centre, 13 un routeur de bordure, 8 un
    /// routeur, 7 sinon). Meme formule que `classementThread` (ProtocoleThread), copiee ici : les attentes des tests de la
    /// scene sont ecrites avec ces rangs.
    static let classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) = { n in
        (n.bordure ? 1 : n.routeur ? 2 : 3, n.genre == .centre ? 15 : n.bordure ? 13 : n.routeur ? 8 : 7)
    }

    /// Petit reseau : l'Apple TV (chef, BBR primaire) et le HomePod, routeurs de bordure ; quatre
    /// appareils. Avec la sonde : le routeur 3 est l'appareil E...04 (un appareil qui route), E...02
    /// est l'enfant de l'Apple TV, E...03 celui du HomePod ; E...05 n'a pas de parent connu.
    static func graphe(sonde: Bool) throws -> GrapheReseau {
        let ext = ["Apple TV": "E0000000000000A1", "HomePod": "E0000000000000A2", "E000000000000002": "E000000000000002",
                   "E000000000000003": "E000000000000003", "E000000000000004": "E000000000000004",
                   "E000000000000005": "E000000000000005"]
        func noeud(_ id: String, _ genre: GrapheReseau.Genre, routeur: Bool = false, bordure: Bool = false) -> GrapheReseau.Noeud {
            .init(id: idt(id), genre: genre, partition: partition, routeur: routeur, bordure: bordure, inconnu: false,
                  extMac: ext[id])
        }
        let noeuds = [noeud("Apple TV", .centre, routeur: true, bordure: true),
                      noeud("HomePod", .routeur, routeur: true, bordure: true),
                      noeud("E000000000000002", .appareil),
                      noeud("E000000000000003", .appareil),
                      noeud("E000000000000004", .appareil, routeur: sonde),
                      noeud("E000000000000005", .appareil)]
        guard sonde else {
            let tous = ["HomePod", "E000000000000002", "E000000000000003", "E000000000000004", "E000000000000005"]
            return GrapheReseau(noeuds: noeuds, liens: tous.map { .init(de: idt($0), vers: idt("Apple TV")) })
        }
        return GrapheReseau(noeuds: noeuds, liens: [
            .init(de: idt("Apple TV"), vers: idt("HomePod"), genre: .radio, qualite: 2),
            .init(de: idt("Apple TV"), vers: idt("E000000000000004"), genre: .radio, qualite: 2),
            .init(de: idt("E000000000000002"), vers: idt("Apple TV"), genre: .parent, qualite: 3),
            .init(de: idt("E000000000000003"), vers: idt("HomePod"), genre: .parent, qualite: 2),
            .init(de: idt("E000000000000005"), vers: idt("Apple TV"))])
    }
}
