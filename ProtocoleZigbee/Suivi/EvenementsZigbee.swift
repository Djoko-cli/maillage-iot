import Foundation
import MaillageCoeur

/// Types d'evenements du protocole Zigbee. Sept types sont communs a tous les protocoles et declares au coeur
/// (`TypeEvenement+Reseau.swift`) : routeurApparu, routeurDisparu, appareilNouveau, appareilDisparu, appareilRevenu,
/// parentChange, sansParent ; Zigbee y ajoute le changement de chemin d'un routeur vers le pont.
public extension TypeEvenement {
    // Maillage de la sonde : un routeur passe par un autre prochain saut vers le pont
    static let cheminChange = TypeEvenement("cheminChange")

    /// Les types Zigbee, dans l'ordre de l'ancienne enumeration (sans les deux types neutres).
    static let zigbee: [TypeEvenement] = [
        .routeurApparu, .routeurDisparu,
        .appareilNouveau, .appareilDisparu, .appareilRevenu,
        .parentChange, .sansParent, .cheminChange,
    ]
}

/// Politique du journal pour Zigbee : ce que `Alertes` et `Regroupement` decidaient quand ils nommaient ces types.
public struct PolitiqueJournalZigbee: PolitiqueJournal {
    public init() {}

    public var types: [TypeEvenement] { [.surveillanceDemarree, .veille] + TypeEvenement.zigbee }

    /// Un appareil disparait.
    public func estPerte(_ e: Evenement) -> Bool { e.type == .appareilDisparu }

    /// Zigbee n'a qu'un reseau : ni scission ni reunion.
    public func estScission(_ e: Evenement) -> Bool { false }
    public func estReunion(_ e: Evenement) -> Bool { false }

    public func categorie(_ e: Evenement) -> CategorieAlerte? {
        switch e.type {
        case .routeurDisparu: .routeurDisparu
        case .surveillanceDemarree, .veille: nil
        default: .informations
        }
    }

    /// Changement de parent ou de chemin : l'adresse longue du noeud si l'evenement la donne, sinon l'id du sujet (qui
    /// est aussi son adresse longue).
    public func cleParent(_ e: Evenement) -> String? {
        e.type == .parentChange || e.type == .cheminChange ? (e.details["ieee"] ?? e.sujet?.id) : nil
    }

    /// Un routeur change de prochain saut vers le pont.
    public func estChemin(_ e: Evenement) -> Bool { e.type == .cheminChange }
}
