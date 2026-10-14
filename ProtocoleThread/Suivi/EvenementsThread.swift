import Foundation
import MaillageCoeur

/// Types d'evenements du protocole Thread, avec leur gravite par defaut. Sept types sont communs a tous les protocoles
/// et declares au coeur (`TypeEvenement+Reseau.swift`) : routeurApparu, routeurDisparu, appareilNouveau,
/// appareilDisparu, appareilRevenu, parentChange, sansParent.
public extension TypeEvenement {
    // Reseau
    static let reseauScinde = TypeEvenement("reseauScinde", gravite: .alerte)
    static let reseauReuni = TypeEvenement("reseauReuni")
    static let chefChange = TypeEvenement("chefChange", gravite: .attention)
    static let bbrPrimaireChange = TypeEvenement("bbrPrimaireChange")
    static let jeuActifChange = TypeEvenement("jeuActifChange", gravite: .attention)
    // Routeurs de bordure
    static let routeurRoleChange = TypeEvenement("routeurRoleChange")
    static let routeurNouvelleAdresseLien = TypeEvenement("routeurNouvelleAdresseLien", gravite: .attention)
    // Prefixes OMR
    static let prefixeNouveau = TypeEvenement("prefixeNouveau")
    static let prefixeRetire = TypeEvenement("prefixeRetire", gravite: .attention)
    // Appareils
    static let appareilSansAdresse = TypeEvenement("appareilSansAdresse", gravite: .attention)
    static let appareilChangePartition = TypeEvenement("appareilChangePartition", gravite: .attention)
    // Maillage de la sonde : un routeur Thread (hors routeurs de bordure) entre dans la liste des routeurs ou en sort
    static let routeurThreadApparu = TypeEvenement("routeurThreadApparu")
    static let routeurThreadDisparu = TypeEvenement("routeurThreadDisparu", gravite: .attention)

    /// Les types Thread, dans l'ordre de l'ancienne enumeration.
    static let thread: [TypeEvenement] = [
        .reseauScinde, .reseauReuni, .chefChange, .bbrPrimaireChange, .jeuActifChange,
        .routeurApparu, .routeurDisparu, .routeurRoleChange, .routeurNouvelleAdresseLien,
        .prefixeNouveau, .prefixeRetire,
        .appareilNouveau, .appareilDisparu, .appareilRevenu, .appareilSansAdresse, .appareilChangePartition,
        .parentChange, .sansParent, .routeurThreadApparu, .routeurThreadDisparu,
    ]
}

/// Politique du journal pour Thread : ce que `Alertes` et `Regroupement` decidaient quand ils nommaient ces types.
public struct PolitiqueJournalThread: PolitiqueJournal {
    public init() {}

    public var types: [TypeEvenement] { [.surveillanceDemarree, .veille] + TypeEvenement.thread }

    /// Un appareil joignable devient sans adresse, disparait, ou passe dans une partition coupee.
    public func estPerte(_ e: Evenement) -> Bool {
        switch e.type {
        case .appareilDisparu, .appareilSansAdresse: true
        case .appareilChangePartition: e.details["coupee"] == "oui"
        default: false
        }
    }

    public func estScission(_ e: Evenement) -> Bool { e.type == .reseauScinde }
    public func estReunion(_ e: Evenement) -> Bool { e.type == .reseauReuni }

    public func categorie(_ e: Evenement) -> CategorieAlerte? {
        switch e.type {
        case .reseauScinde: .scission
        case .routeurDisparu: .routeurDisparu
        case .surveillanceDemarree, .veille: nil
        default: .informations
        }
    }

    /// ExtMac du noeud si l'evenement la donne (l'id du sujet d'un enfant sans appareil change avec son parent),
    /// sinon l'id du sujet.
    public func cleParent(_ e: Evenement) -> String? {
        e.type == .parentChange ? (e.details["extMac"] ?? e.sujet?.id) : nil
    }
}
