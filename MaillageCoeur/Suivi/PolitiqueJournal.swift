import Foundation

/// Ce qu'un protocole decide du journal : les types d'evenements qu'il ecrit, ce qui compte comme une perte, ce
/// qui se notifie et sous quelle categorie, ce qui se regroupe par noeud. Le coeur n'en nomme aucun : `Alertes`,
/// `Regroupement` et `JournalFichiers` recoivent la politique du protocole en cours.
public protocol PolitiqueJournal: Sendable {
    /// Tous les types que le protocole ecrit (le journal les retrouve par leur nom, gravite comprise).
    var types: [TypeEvenement] { get }
    /// Perte d'un appareil : comptee dans la notification groupee et dans la ligne de pertes du journal.
    func estPerte(_ e: Evenement) -> Bool
    /// Scission d'un reseau : notifiee une fois par signature (voir `Alertes`).
    func estScission(_ e: Evenement) -> Bool
    /// Fin de scission d'un reseau : fait oublier les scissions notifiees de ce reseau.
    func estReunion(_ e: Evenement) -> Bool
    /// Categorie de la notification d'un evenement hors perte ; nil si l'evenement ne se notifie pas.
    func categorie(_ e: Evenement) -> CategorieAlerte?
    /// Noeud dont l'evenement est un changement de parent (regroupe par noeud sur une heure) ; nil sinon.
    func cleParent(_ e: Evenement) -> String?
}

public extension PolitiqueJournal {
    /// Les types par nom, tels que `CodingUserInfoKey.typesEvenement` les attend.
    var typesParNom: [String: TypeEvenement] {
        Dictionary(types.map { ($0.rawValue, $0) }, uniquingKeysWith: { premier, _ in premier })
    }
}

/// Politique du coeur : seuls les types neutres, ni perte, ni categorie, ni parent.
public struct PolitiqueJournalNeutre: PolitiqueJournal {
    public init() {}

    public var types: [TypeEvenement] { [.surveillanceDemarree, .veille] }
    public func estPerte(_ e: Evenement) -> Bool { false }
    public func estScission(_ e: Evenement) -> Bool { false }
    public func estReunion(_ e: Evenement) -> Bool { false }
    public func categorie(_ e: Evenement) -> CategorieAlerte? { nil }
    public func cleParent(_ e: Evenement) -> String? { nil }
}
