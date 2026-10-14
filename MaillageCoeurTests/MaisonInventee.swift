import Foundation
@testable import MaillageCoeur

/// Maison inventee pour les tests de la scene : `pieces` pieces reparties sur deux etages (ou sur un seul
/// plateau, `unSeulPlateau`),
/// `routeurs` routeurs de bordure relies en chaine (le premier est le chef), le routeur k dans la
/// piece k ; `appareils` appareils, l'appareil j dans la piece j modulo `pieces`, enfant du routeur
/// de numero (sa piece) modulo `routeurs`. Noms : 7 px par caractere, plus 10 px de marges.
enum MaisonInventee {
    static let partition = "0000000A"

    static func routeur(_ k: Int) -> String { String(format: "Routeur %02d", k) }
    static func appareil(_ j: Int) -> String { String(format: "E2%014X", j) }
    static func extMacRouteur(_ k: Int) -> String { String(format: "E1%014X", k) }

    /// Graphe ecrit a la main, sans aucun type de protocole : le routeur 0 est le centre, les autres sont des
    /// routeurs de bordure relies en chaine par des liens radio de qualite 2 ; chaque appareil est l'enfant
    /// (lien parent, qualite 2) du routeur de sa piece, les liens parent classes par routeur puis par appareil.
    /// `FixturesThreadTests` verifie qu'il est identique au graphe que bati `MaisonInventeeThread`.
    static func graphe(pieces: Int, routeurs: Int, appareils: Int) -> GrapheReseau {
        var noeuds: [GrapheReseau.Noeud] = []
        for k in 0..<routeurs {
            noeuds.append(.init(id: routeur(k), genre: k == 0 ? .centre : .routeur, partition: partition, routeur: true,
                                bordure: true, inconnu: false, extMac: extMacRouteur(k)))
        }
        for j in 0..<appareils {
            noeuds.append(.init(id: appareil(j), genre: .appareil, partition: partition, routeur: false, bordure: false,
                                inconnu: false, extMac: appareil(j)))
        }
        var liens: [GrapheReseau.Lien] = []
        for k in 1..<max(routeurs, 1) {
            liens.append(.init(de: routeur(k - 1), vers: routeur(k), genre: .radio, qualite: 2))
        }
        for k in 0..<routeurs {
            for j in 0..<appareils where (j % pieces) % routeurs == k {
                liens.append(.init(de: appareil(j), vers: routeur(k), genre: .parent, qualite: 2))
            }
        }
        return GrapheReseau(noeuds: noeuds, liens: liens)
    }

    /// La scene et ses cartes.
    static func scene(pieces: Int, appareils: Int, routeurs: Int,
                      unSeulPlateau: Bool = false) -> (scene: ScenePieces, cartes: [CartesPieces.Carte]) {
        let g = graphe(pieces: pieces, routeurs: routeurs, appareils: appareils)
        func nomPiece(_ p: Int) -> String { String(format: "Pièce %02d", p) }
        var piecesNoeuds: [String: String] = [:]
        var libelles: [String: String] = [:]
        for k in 0..<routeurs {
            piecesNoeuds[routeur(k)] = nomPiece(k % pieces)
            libelles[routeur(k)] = routeur(k)
        }
        for j in 0..<appareils {
            piecesNoeuds[appareil(j)] = nomPiece(j % pieces)
            libelles[appareil(j)] = "Appareil \(j)"
        }
        let bas = (0..<pieces / 2).map(nomPiece)
        let haut = (pieces / 2..<pieces).map(nomPiece)
        let s = ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: piecesNoeuds,
                            zones: unSeulPlateau ? nil : [ZoneMaison(nom: "Bas", pieces: bas), ZoneMaison(nom: "Haut", pieces: haut)],
                            chefs: [routeur(0)], piecesMaison: true, classement: FixturesScene.classement)
        let largeurs = libelles.mapValues { Double($0.count) * 7 + 10 }
        return (s, CartesPieces.cartes(s, largeurs: largeurs))
    }
}
