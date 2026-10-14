import Foundation
import MaillageCoeur

/// Le rang et le rayon d'un noeud Zigbee dans la vue par pieces : le coordinateur (le pont) au premier rang, les
/// routeurs au deuxieme, les appareils finaux au troisieme. Zigbee n'a pas de routeur de bordure (`bordure` toujours
/// faux) : la regle de Thread donnerait le rang 2 au coordinateur.
public extension ScenePieces {
    /// Rang : centre 1, routeur 2, sinon 3 ; rayon : centre 15, routeur 8, sinon 7.
    static let classementZigbee: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) = { n in
        let rang = n.genre == .centre ? 1 : n.routeur ? 2 : 3
        let rayon: Double = n.genre == .centre ? 15 : n.routeur ? 8 : 7
        return (rang, rayon)
    }
}
