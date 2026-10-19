import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// La piece qu'AirPlay propose pour un routeur de bordure que Maison ne place pas (phase 7, spec « Piece proposee aux HomePod
/// et a l'Apple TV »), dans sa fiche : une ligne « Piece proposee : <piece> (d'apres AirPlay) », « Placer ici » et « Ignorer ».
/// Le calcul de la proposition est celui de `PieceAirPlay` ; ici, ce que la fiche en fait. Rien n'est jamais place d'office :
/// « Placer ici » fait exactement ce que fait « Placer dans une piece… » pour cette piece (`PiecesChoisies.choisir`, donc le meme
/// fichier, la meme persistance), et « Ignorer » se retient a cote des pieces choisies, sous le nom AirPlay dont elle venait :
/// elle revient quand ce nom change.
@MainActor
enum PropositionPiece {
    /// La proposition de la fiche du noeud `id`, nil sans : il n'est pas un routeur de bordure que Maison ne place pas (le menu
    /// « Placer dans une piece… » n'existe pas pour lui, ou sa piece est deja connue : Maison, un choix, la regle du nom), AirPlay
    /// n'en dit rien de sur (`PieceAirPlay.propositions`), ou « Ignorer » a ete choisi pour ce nom AirPlay.
    /// `entree` : la scene du meme rendu (ses pieces, choix de Djoko compris) ; `choisies` : les pieces choisies et les
    /// propositions ignorees.
    static func pour(_ id: IdNoeud, dans surveillance: Surveillance, entree: EntreeScene,
                     choisies: PiecesChoisies) -> Proposition? {
        guard id.protocole == .thread, let releve = surveillance.thread.dernierReleve,
              let placement = PiecesChoisies.placement(id, dans: surveillance, entree: entree),
              case .routeur = placement.cle else { return nil }
        let propositions = PieceAirPlay.propositions(
            airplay: PieceAirPlay.services(de: releve), bordures: PieceAirPlay.bordures(de: releve),
            piecesMaison: placement.pieces, piecesConnues: entree.piecesNoeuds)
        guard let p = propositions[id], placement.pieces.contains(p.piece),
              choisies.airPlayIgnore(id, domicile: domicile(surveillance)) != p.nomAirPlay else { return nil }
        return p
    }

    /// Le domicile de la maison, sous lequel les pieces choisies et les propositions ignorees sont gardees.
    static func domicile(_ surveillance: Surveillance) -> String {
        surveillance.thread.noms.maison?.domicile ?? ""
    }

    /// « Placer ici » : le choix du menu « Placer dans une piece… », pour la piece proposee.
    static func placer(_ p: Proposition, pour id: IdNoeud, domicile: String, choisies: PiecesChoisies) {
        choisies.choisir(p.piece, .routeur(id), domicile: domicile)
    }

    /// « Ignorer » : la proposition ne revient pas tant que le nom AirPlay est le meme.
    static func ignorer(_ p: Proposition, pour id: IdNoeud, domicile: String, choisies: PiecesChoisies) {
        choisies.ignorerAirPlay(p.nomAirPlay, id, domicile: domicile)
    }

    /// La ligne de la fiche.
    static func texte(_ p: Proposition) -> String {
        String(localized: "Pièce proposée : \(p.piece) (d'après AirPlay)")
    }
}

/// La ligne de la proposition et ses deux boutons, dans la colonne d'identite de la fiche d'un routeur de bordure.
struct LignePropositionPiece: View {
    let proposition: Proposition
    let placer: () -> Void
    let ignorer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: PropositionPiece.texte(proposition))
                .fixedSize(horizontal: false, vertical: true)
            RangeesFluides(espacement: 8, interligne: 6) {
                Button("Placer ici", action: placer)
                    .boutonDeFiche()
                Button("Ignorer", action: ignorer)
                    .boutonDeFiche()
            }
        }
    }
}
