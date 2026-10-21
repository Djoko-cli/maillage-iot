import Foundation
import MaillageCoeur

/// Les phrases du journal dont le sujet ouvre la phrase, accordees avec lui : « La lampe du bureau est apparue », « Les volets
/// de la chambre ont perdu leur parent ». Le sujet est celui de `PhraseSujet` (le nom du noeud et sa piece) ; son genre et son
/// nombre (`PhraseSujet.accord`) choisissent la forme, une cle du catalogue chacune. Un sujet sans article (mot inconnu,
/// sans piece, anglais) est au masculin singulier : la cle d'avant, mot pour mot. Les deux modules de textes
/// (`TexteEvenementThread`, `TexteEvenementZigbee`) partagent ces phrases, qui sont les memes pour les deux protocoles.
enum PhrasesEvenement {
    /// Ce qui ouvre la phrase : le sujet, et ce qui le separe du verbe (« , » ou « : » quand la piece est une incise).
    private static func debut(_ s: PhraseSujet) -> String { s.texte + s.suite }

    static func apparu(_ s: PhraseSujet) -> String {
        let d = debut(s)
        switch (s.accord.feminin, s.accord.pluriel) {
        case (false, false): return String(localized: "\(d) est apparu")
        case (true, false): return String(localized: "\(d) est apparue")
        case (false, true): return String(localized: "\(d) sont apparus")
        case (true, true): return String(localized: "\(d) sont apparues")
        }
    }

    static func revenu(_ s: PhraseSujet) -> String {
        let d = debut(s)
        switch (s.accord.feminin, s.accord.pluriel) {
        case (false, false): return String(localized: "\(d) est revenu")
        case (true, false): return String(localized: "\(d) est revenue")
        case (false, true): return String(localized: "\(d) sont revenus")
        case (true, true): return String(localized: "\(d) sont revenues")
        }
    }

    static func disparu(_ s: PhraseSujet) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont disparu") : String(localized: "\(d) a disparu")
    }

    static func sansAdresse(_ s: PhraseSujet) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) n'annoncent plus d'adresse")
                                : String(localized: "\(d) n'annonce plus d'adresse")
    }

    /// Isole dans une partition coupee.
    static func isole(_ s: PhraseSujet, partition: String) -> String {
        let d = debut(s)
        switch (s.accord.feminin, s.accord.pluriel) {
        case (false, false): return String(localized: "\(d) est isolé dans la partition \(partition)")
        case (true, false): return String(localized: "\(d) est isolée dans la partition \(partition)")
        case (false, true): return String(localized: "\(d) sont isolés dans la partition \(partition)")
        case (true, true): return String(localized: "\(d) sont isolées dans la partition \(partition)")
        }
    }

    static func rejoint(_ s: PhraseSujet, partition: String) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont rejoint la partition \(partition)")
                                : String(localized: "\(d) a rejoint la partition \(partition)")
    }

    static func parentChange(_ s: PhraseSujet, avant: String, apres: String) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont changé de parent : \(avant) → \(apres)")
                                : String(localized: "\(d) a changé de parent : \(avant) → \(apres)")
    }

    static func sansParent(_ s: PhraseSujet) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) n'ont plus de parent") : String(localized: "\(d) n'a plus de parent")
    }

    static func cheminChange(_ s: PhraseSujet, avant: String, apres: String) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont changé de chemin vers le pont : \(avant) → \(apres)")
                                : String(localized: "\(d) a changé de chemin vers le pont : \(avant) → \(apres)")
    }

    /// Une ligne de changements de parent regroupes : « a changé N fois de parent en 1 h ».
    static func parentsRegroupes(_ s: PhraseSujet, fois: Int) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont changé \(fois) fois de parent en 1 h")
                                : String(localized: "\(d) a changé \(fois) fois de parent en 1 h")
    }

    static func cheminsRegroupes(_ s: PhraseSujet, fois: Int) -> String {
        let d = debut(s)
        return s.accord.pluriel ? String(localized: "\(d) ont changé \(fois) fois de chemin vers le pont en 1 h")
                                : String(localized: "\(d) a changé \(fois) fois de chemin vers le pont en 1 h")
    }

    /// Les noeuds d'une liste (les pertes d'une notification), chacun avec sa piece, en minuscules a l'article : separes par
    /// des virgules, ou par des points-virgules quand une piece est une incise (sa virgule ferait lire deux noeuds).
    static func liste(_ evenements: [Evenement], pieces: PiecesJournal) -> String {
        let sujets = evenements.filter { $0.sujet != nil }.map { pieces.sujet(de: $0, debutDePhrase: false) }
        return sujets.map(\.texte).joined(separator: sujets.contains { !$0.suite.isEmpty } ? " ; " : ", ")
    }
}
