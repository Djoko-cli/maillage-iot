import Foundation
@testable import MaillageCoeur

/// Politique de journal d'essai : types inventes, decisions calquees sur la forme de celles d'un vrai protocole
/// (perte, perte conditionnelle, scission, reunion, categories, parent regroupe par noeud). Le coeur se teste
/// ainsi seul, sans aucun protocole.
extension TypeEvenement {
    static let essaiScission = TypeEvenement("essaiScission", gravite: .alerte)
    static let essaiReunion = TypeEvenement("essaiReunion")
    static let essaiPerte = TypeEvenement("essaiPerte", gravite: .attention)
    /// Perte seulement quand `details["coupee"] == "oui"`.
    static let essaiCoupure = TypeEvenement("essaiCoupure", gravite: .attention)
    static let essaiParent = TypeEvenement("essaiParent")
    static let essaiSansParent = TypeEvenement("essaiSansParent", gravite: .attention)
    /// Changement de chemin d'un routeur : regroupe par noeud comme le parent, mais sur sa propre ligne.
    static let essaiChemin = TypeEvenement("essaiChemin")
    static let essaiRelaisPerdu = TypeEvenement("essaiRelaisPerdu", gravite: .alerte)
    static let essaiRoutine = TypeEvenement("essaiRoutine")
}

struct PolitiqueEssai: PolitiqueJournal {
    var types: [TypeEvenement] {
        [.surveillanceDemarree, .veille, .essaiScission, .essaiReunion, .essaiPerte, .essaiCoupure,
         .essaiParent, .essaiSansParent, .essaiChemin, .essaiRelaisPerdu, .essaiRoutine]
    }

    func estPerte(_ e: Evenement) -> Bool {
        switch e.type {
        case .essaiPerte: true
        case .essaiCoupure: e.details["coupee"] == "oui"
        default: false
        }
    }

    func estScission(_ e: Evenement) -> Bool { e.type == .essaiScission }
    func estReunion(_ e: Evenement) -> Bool { e.type == .essaiReunion }

    func categorie(_ e: Evenement) -> CategorieAlerte? {
        switch e.type {
        case .essaiScission: .scission
        case .essaiRelaisPerdu: .routeurDisparu
        case .surveillanceDemarree, .veille: nil
        default: .informations
        }
    }

    /// `details["cle"]` du noeud si l'evenement la donne, sinon l'id du sujet (parent et chemin).
    func cleParent(_ e: Evenement) -> String? {
        e.type == .essaiParent || e.type == .essaiChemin ? (e.details["cle"] ?? e.sujet?.id) : nil
    }

    func estChemin(_ e: Evenement) -> Bool { e.type == .essaiChemin }
}
