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
                            chefs: [routeur(0)], piecesMaison: true)
        let largeurs = libelles.mapValues { Double($0.count) * 7 + 10 }
        return (s, CartesPieces.cartes(s, largeurs: largeurs))
    }
}
