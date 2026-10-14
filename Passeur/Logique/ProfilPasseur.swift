import Foundation

/// Le profil de developpement du demon (`embedded.provisionprofile` de son paquet) : un message CMS signe, dont le
/// contenu est une liste de proprietes XML en clair. Sa date d'expiration (`ExpirationDate`) y est lue sans verifier
/// la signature (macOS l'a verifiee au lancement), pour que les apps previennent 30 jours avant (spec, section 3.6).
enum ProfilPasseur {
    /// Le profil dans le paquet d'une app Mac.
    static func fichier(paquet: URL) -> URL {
        paquet.appendingPathComponent("Contents/embedded.provisionprofile")
    }

    /// La date d'expiration ; nil si le profil est illisible.
    static func expiration(_ donnees: Data) -> Date? {
        guard let debut = donnees.range(of: Data("<?xml".utf8)),
              let fin = donnees.range(of: Data("</plist>".utf8), in: debut.lowerBound..<donnees.endIndex) else { return nil }
        let xml = Data(donnees[debut.lowerBound..<fin.upperBound])
        let liste = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        return liste?["ExpirationDate"] as? Date
    }

    static func expiration(paquet: URL) -> Date? {
        (try? Data(contentsOf: fichier(paquet: paquet))).flatMap(expiration)
    }
}
