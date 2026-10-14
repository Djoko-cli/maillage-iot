import Foundation
import MaillageCoeur

/// Le rang et le rayon d'un noeud Thread dans la vue par pieces : rang dans sa carte (1 routeur de bordure, 2 autre
/// routeur, 3 autre noeud) et rayon naturel de sa pastille (15 px pour le centre, 13 pour un routeur de bordure, 8
/// pour un routeur, 7 sinon). Le coeur n'en connait aucune : chaque protocole passe la sienne a `ScenePieces`
/// (`classement:`).
public func classementThread(_ n: GrapheReseau.Noeud) -> (rang: Int, rayon: Double) {
    (n.bordure ? 1 : n.routeur ? 2 : 3, n.genre == .centre ? 15 : n.bordure ? 13 : n.routeur ? 8 : 7)
}
