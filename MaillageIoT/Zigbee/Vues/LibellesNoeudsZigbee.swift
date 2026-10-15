import Foundation
import MaillageCoeur
import ProtocoleZigbee

/// La part de Zigbee des textes de la vue par pieces (la coque commune est `LibellesNoeuds`) : le coordinateur couronne,
/// le libelle de chaque noeud d'apres les noms du pont, et la piece de chaque noeud d'apres le pont et les choix de
/// l'utilisateur. Chaque fonction a la forme de celle de Thread (`LibellesNoeuds.chefs(reseau:maillage:affiche:)`,
/// `libelles(graphe:appareils:nomsRouteurs:maillage:chefs:)`, `pieces(reseau:appareils:maison:...)`), a ses etiquettes
/// pres : la scene reunie (tache 8) appelle celle du protocole de chaque noeud.
extension LibellesNoeuds {
    /// Noeuds couronnes : le coordinateur (le pont).
    static func chefs(_ graphe: GrapheReseau) -> Set<IdNoeud> {
        Set(graphe.noeuds.filter { $0.genre == .centre && $0.id.protocole == .zigbee }.map(\.id))
    }

    /// Libelle de chaque noeud : son nom (`nom`, par adresse longue ; coupe a 40 caracteres), la couronne du
    /// coordinateur, ☾ endormi (pas pour un noeud qui route), ⚠︎ injoignable ou disparu ; la pastille d'une batterie
    /// faible.
    static func libelles(graphe: GrapheReseau, appareils: [IdNoeud: AppareilAffiche], nom: (String) -> String,
                         chefs: Set<IdNoeud>) -> [IdNoeud: Libelle] {
        var libelles: [IdNoeud: Libelle] = [:]
        for n in graphe.noeuds {
            let a = appareils[n.id]
            // `nom` lit le pont par adresse longue (la cle) ; sans nom, le repli est la cle, jamais le texte.
            // Un noeud d'un autre protocole de meme cle n'est pas lu sur le pont.
            let coupe = CartesPieces.couper(a?.nom ?? (n.id.protocole == .zigbee ? nom(n.id.cle) : n.id.cle))
            let texte = CartesPieces.texte(coupe, chef: chefs.contains(n.id), endormi: endormi(a, routeur: n.routeur),
                                           alerte: a?.etat == .injoignable || a?.etat == .disparu)
            libelles[n.id] = Libelle(texte: texte, pastille: pastilleBatterie(a?.batterie), nom: coupe)
        }
        return libelles
    }

    /// Piece de chaque noeud : celle que le pont donne a son appareil ; pour un noeud que le pont ne place pas, la piece
    /// choisie pour son adresse longue (`PiecesRouteurs`).
    static func pieces(appareils: [AppareilAffiche], maison: NomsZigbee?, choix: PiecesRouteurs = PiecesRouteurs(),
                       graphe: GrapheReseau) -> [IdNoeud: String] {
        var pieces: [IdNoeud: String] = [:]
        for a in appareils {
            if let p = a.piece, !p.isEmpty { pieces[a.id] = p }
        }
        return choix.piecesNoeuds(graphe, deMaison: pieces, parmi: PiecesRouteurs.pieces(de: maison),
                                  domicile: maison?.domicile ?? "")
    }
}
