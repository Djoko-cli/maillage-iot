import Foundation
@testable import MaillageCoeur

/// Fixtures de scene partagees, sans test ni suite : le coeur et les tests Thread les compilent tous deux.
enum FixturesScene {
    static let partition = "46CBEBCD"

    /// Petit reseau : l'Apple TV (chef, BBR primaire) et le HomePod, routeurs de bordure ; quatre
    /// appareils. Avec la sonde : le routeur 3 est l'appareil E...04 (un appareil qui route), E...02
    /// est l'enfant de l'Apple TV, E...03 celui du HomePod ; E...05 n'a pas de parent connu.
    static func graphe(sonde: Bool) throws -> GrapheReseau {
        let ext = ["Apple TV": "E0000000000000A1", "HomePod": "E0000000000000A2", "E000000000000002": "E000000000000002",
                   "E000000000000003": "E000000000000003", "E000000000000004": "E000000000000004",
                   "E000000000000005": "E000000000000005"]
        func noeud(_ id: String, _ genre: GrapheReseau.Genre, routeur: Bool = false, bordure: Bool = false) -> GrapheReseau.Noeud {
            .init(id: id, genre: genre, partition: partition, routeur: routeur, bordure: bordure, inconnu: false,
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
            return GrapheReseau(noeuds: noeuds, liens: tous.map { .init(de: $0, vers: "Apple TV") })
        }
        return GrapheReseau(noeuds: noeuds, liens: [
            .init(de: "Apple TV", vers: "HomePod", genre: .radio, qualite: 2),
            .init(de: "Apple TV", vers: "E000000000000004", genre: .radio, qualite: 2),
            .init(de: "E000000000000002", vers: "Apple TV", genre: .parent, qualite: 3),
            .init(de: "E000000000000003", vers: "HomePod", genre: .parent, qualite: 2),
            .init(de: "E000000000000005", vers: "Apple TV")])
    }
}
