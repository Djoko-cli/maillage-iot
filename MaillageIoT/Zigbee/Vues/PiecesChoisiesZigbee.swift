import Foundation
import MaillageCoeur
import ProtocoleZigbee

extension PiecesRouteurs {
    /// Les pieces des appareils du pont et de ses zones, sans doublon ni vide, triees : le calcul de `pieces(de:)` du
    /// coeur, qui lit le releve de Maison (`NomsMaison`), sur les noms du pont (`NomsZigbee`).
    static func pieces(de maison: NomsZigbee?) -> [String] {
        guard let maison else { return [] }
        var toutes = Set(maison.accessoires.compactMap(\.piece))
        for z in maison.zones ?? [] { toutes.formUnion(z.pieces) }
        return toutes.filter { !$0.isEmpty }.sorted()
    }
}

extension PiecesChoisies {
    /// « Placer dans une piece… » pour un noeud Zigbee, dans une maison qui a des pieces : un noeud sans piece sur le pont
    /// dont l'adresse longue est connue. Nil pour un noeud que le pont place. `entree` : la scene du meme rendu, dont le
    /// graphe et les appareils servent tels quels.
    static func placementZigbee(_ id: IdNoeud, dans surveillance: Surveillance, entree: EntreeScene) -> Placement? {
        let pieces = PiecesRouteurs.pieces(de: surveillance.zigbee.noms.maison)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !pieces.isEmpty else { return nil }
        if let p = entree.appareils[id]?.piece, !p.isEmpty { return nil }
        guard let n = entree.graphe.noeud(id), let cle = PiecesRouteurs.cle(n) else { return nil }
        return Placement(cle: .appareil(cle), pieces: pieces)
    }
}
