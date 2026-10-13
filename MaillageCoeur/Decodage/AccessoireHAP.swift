import Foundation

/// Accessoire HomeKit (`_hap._udp`) : son nom est celui de l'instance.
public struct AccessoireHAP: Hashable, Sendable {
    /// Nom de l'instance ("Eve Door 4A3B").
    public let nom: String
    /// `md` : modele.
    public let modele: String?
    /// `ci` : categorie HomeKit (5 ampoule, 6 serrure, 7 prise...).
    public let categorie: Int?
    /// `id` : identifiant de l'accessoire ("AA:BB:CC:DD:EE:FF").
    public let identifiant: String?
    /// `sf` bit 0 : 0 = appaire.
    public let appaire: Bool?

    public init(annonce: AnnonceService) {
        let t = annonce.txt
        nom = annonce.instance
        modele = t.texte("md")
        categorie = t.entier("ci")
        identifiant = t.texte("id")
        appaire = t.entier("sf").map { $0 & 1 == 0 }
    }
}
