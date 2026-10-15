import Foundation

/// Politique du journal d'une app qui porte plusieurs protocoles : chaque decision est celle de la politique du
/// protocole de l'evenement (`Evenement.protocole`) ; une ligne sans protocole est de Thread (journaux d'avant
/// l'etape 3). Un evenement dont le protocole n'a pas de politique ici n'est ni une perte, ni une scission, ni notifie,
/// ni regroupe par noeud.
///
/// Les types sont l'union de ceux des politiques (dans l'ordre des protocoles, sans doublon par nom) ; le journal relit
/// chaque ligne avec les types de son protocole (`typesParProtocole`), si bien qu'un type present dans les deux politiques
/// prend la gravite par defaut de son protocole.
public struct PolitiqueJournalComposee: PolitiqueJournal {
    private let politiques: [Protocole: any PolitiqueJournal]

    public init(_ politiques: [Protocole: any PolitiqueJournal]) {
        self.politiques = politiques
    }

    private func politique(_ e: Evenement) -> (any PolitiqueJournal)? {
        politiques[e.protocole ?? .thread]
    }

    public var types: [TypeEvenement] {
        var vus = Set<String>()
        return Protocole.allCases.compactMap { politiques[$0]?.types }.flatMap { $0 }.filter { vus.insert($0.rawValue).inserted }
    }

    public var typesParProtocole: [Protocole: [String: TypeEvenement]] {
        politiques.mapValues(\.typesParNom)
    }

    public func estPerte(_ e: Evenement) -> Bool { politique(e)?.estPerte(e) ?? false }
    public func estScission(_ e: Evenement) -> Bool { politique(e)?.estScission(e) ?? false }
    public func estReunion(_ e: Evenement) -> Bool { politique(e)?.estReunion(e) ?? false }
    public func categorie(_ e: Evenement) -> CategorieAlerte? { politique(e)?.categorie(e) }
    public func cleParent(_ e: Evenement) -> String? { politique(e)?.cleParent(e) }
    public func estChemin(_ e: Evenement) -> Bool { politique(e)?.estChemin(e) ?? false }
}
