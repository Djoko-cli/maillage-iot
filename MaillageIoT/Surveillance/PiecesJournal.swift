import Foundation
import MaillageCoeur

extension LangueSujet {
    /// La langue des textes de l'app : celle que `String(localized:)` lit (le Mac, ou le choix des Reglages). Le sujet d'une
    /// ligne du journal s'accorde en francais, jamais en anglais.
    static var courante: LangueSujet { LangueSujet(code: Bundle.main.preferredLocalizations.first) }
}

/// Les pieces des noeuds, telles que la scene les place (celle de Maison, le choix de Djoko, ou la regle du nom), lues a
/// l'affichage : la meme regle dans la fenetre du journal, les notifications et le menu de la barre. Un noeud que la scene
/// range « Sans piece » (ou qu'elle ne connait pas) n'a pas de piece : son nom seul, comme avant.
struct PiecesJournal: Equatable {
    var pieces: [IdNoeud: String] = [:]
    var langue: LangueSujet = .courante

    /// Aucune piece : les textes d'avant (le nom du noeud seul).
    static let aucune = PiecesJournal()

    /// Les pieces de la scene de la surveillance, a cet instant.
    /// C'est la scene de la vue par pieces, celle de tous les protocoles actifs, construite avec les pieces choisies de la
    /// coque (`Surveillance.piecesChoisies`) : la piece d'un noeud est celle dont elle le range (Maison, le choix de Djoko,
    /// ou la regle du nom), jamais une copie.
    @MainActor
    static func de(_ surveillance: Surveillance, langue: LangueSujet = .courante) -> PiecesJournal {
        guard surveillance.thread.reseau != nil || surveillance.zigbee.aUnReseau else {
            return PiecesJournal(pieces: [:], langue: langue)
        }
        let entree = EntreeScene(surveillance: surveillance, places: PlacesGardees(),
                                 choix: surveillance.piecesChoisies.choix)
        return PiecesJournal(pieces: pieces(de: entree.scene), langue: langue)
    }

    /// La piece de Maison dont la scene range chaque noeud ; ceux qu'elle range « Sans piece » (ou sur la carte d'un routeur,
    /// quand Maison n'a aucune piece) n'en ont pas.
    static func pieces(de scene: ScenePieces) -> [IdNoeud: String] {
        var pieces: [IdNoeud: String] = [:]
        for n in scene.noeuds {
            if case .maison(let nom) = scene.pieces[n.piece].nom { pieces[n.id] = nom }
        }
        return pieces
    }

    /// La piece d'un sujet d'evenement du protocole `protocole` ; nil sans piece.
    func piece(de sujet: Sujet?, protocole: Protocole) -> String? {
        sujet.flatMap { pieces[IdNoeud(protocole, $0.id)] }
    }

    /// Le sujet d'un evenement, avec sa piece : voir `PhraseSujet`. Sans sujet : un nom vide.
    func sujet(de e: Evenement, debutDePhrase: Bool = true) -> PhraseSujet {
        sujet(e.sujet, protocole: e.protocole ?? .thread, debutDePhrase: debutDePhrase)
    }

    func sujet(_ sujet: Sujet?, protocole: Protocole, debutDePhrase: Bool = true) -> PhraseSujet {
        PhraseSujet.de(nom: sujet?.nom ?? "", piece: piece(de: sujet, protocole: protocole), langue: langue,
                       debutDePhrase: debutDePhrase)
    }
}
