import Foundation
import Testing

/// Date d'expiration lue dans le profil embarque : la liste de proprietes en clair dans le message CMS.
@Suite("Profil du passeur")
struct ProfilPasseurTests {
    static let expiration = Date(timeIntervalSince1970: 1_823_000_000)

    /// Un faux profil : des octets, la liste XML, des octets.
    static func profil(_ liste: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: liste, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x01, 0x02, 0x06]) + xml + Data([0xA0, 0x82, 0x00])
    }

    @Test func dateLue() throws {
        let d = try Self.profil(["Name": "passeur", "ExpirationDate": Self.expiration])
        #expect(ProfilPasseur.expiration(d) == Self.expiration)
    }

    @Test func illisible() throws {
        #expect(ProfilPasseur.expiration(Data()) == nil)
        #expect(ProfilPasseur.expiration(try Self.profil(["Name": "passeur"])) == nil, "sans date")
        #expect(ProfilPasseur.expiration(try Self.profil(["ExpirationDate": "demain"])) == nil, "pas une date")
        let tronque = try Self.profil(["ExpirationDate": Self.expiration]).prefix(40)
        #expect(ProfilPasseur.expiration(Data(tronque)) == nil, "sans fin de liste")
    }

    @Test func emplacement() {
        let paquet = URL(fileURLWithPath: "/Applications/Passeur Noms.app")
        #expect(ProfilPasseur.fichier(paquet: paquet).path == "/Applications/Passeur Noms.app/Contents/embedded.provisionprofile")
        #expect(ProfilPasseur.expiration(paquet: URL(fileURLWithPath: "/nulle/part.app")) == nil)
    }
}
