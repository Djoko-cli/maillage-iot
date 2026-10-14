import Foundation

/// Types d'evenements que tous les protocoles ecrivent, declares une seule fois ici (deux declarations du meme nom
/// dans deux modules seraient ambigues dans l'app). Les noms (`rawValue`) sont ceux des journaux deja ecrits, ne pas
/// les changer. Le sens et les details precis d'un type restent ceux du protocole qui l'ecrit : un routeur apparu est
/// un routeur de bordure pour Thread, un routeur Zigbee pour Zigbee.
public extension TypeEvenement {
    // Routeurs
    static let routeurApparu = TypeEvenement("routeurApparu")
    static let routeurDisparu = TypeEvenement("routeurDisparu", gravite: .alerte)
    // Appareils
    static let appareilNouveau = TypeEvenement("appareilNouveau")
    static let appareilDisparu = TypeEvenement("appareilDisparu", gravite: .attention)
    static let appareilRevenu = TypeEvenement("appareilRevenu")
    // Maillage de la sonde : un enfant change de parent ou n'en a plus
    static let parentChange = TypeEvenement("parentChange")
    static let sansParent = TypeEvenement("sansParent", gravite: .attention)
}
