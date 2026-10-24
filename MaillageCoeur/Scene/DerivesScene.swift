import Foundation

/// Ce que la projection tire de la seule scene (`ScenePieces`), sans camera ni etat de l'image : les voisins entendus que
/// le chemin de leur paire rend inutiles, l'indice de chaque plateau par sa cle, les cles des pieces. Rien de cela ne
/// change d'une image a l'autre : le moteur le calcule une fois par scene (`MoteurPieces.derivesDeLaScene`) et le passe a
/// chaque `SceneProjetee`, au lieu de le refaire a chaque image (performance, piste 3 du 25/10 : `voisinsMasques` pesait
/// 10 % d'une image sur la maison reelle).
public struct DerivesScene: Equatable, Sendable {
    /// Les liens radio dont la paire a aussi un chemin (`SceneProjetee.voisinsMasques`).
    public let voisinsMasques: Set<GrapheReseau.Lien>
    /// L'indice de chaque plateau de la scene, par sa cle.
    public let indicesEtages: [String: Int]
    /// Les cles des pieces de la scene.
    public let clesPieces: Set<String>

    public init(_ scene: ScenePieces) {
        voisinsMasques = SceneProjetee.voisinsMasques(scene.liens)
        indicesEtages = Dictionary(scene.etages.indices.map { (scene.etages[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        clesPieces = Set(scene.pieces.map(\.id))
    }
}
