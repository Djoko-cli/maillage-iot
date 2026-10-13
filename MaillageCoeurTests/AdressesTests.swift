import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Adresses et prefixes IPv6")
struct AdressesTests {
    @Test func lectureEtEcriture() throws {
        let a = try #require(AdresseIPv6("fd19:961f:2db3:0000:34a9:8acf:e48d:c424"))
        #expect(a.description == "fd19:961f:2db3:0:34a9:8acf:e48d:c424", "un seul zero : pas de ::")
        #expect(AdresseIPv6("fe80::5a:d5f3:dc72:e7d6%en0")?.description == "fe80::5a:d5f3:dc72:e7d6", "zone ignoree")
        #expect(AdresseIPv6("192.0.2.25") == nil)
        #expect(AdresseIPv6("") == nil)
        #expect(AdresseIPv6(octets: [1, 2]) == nil)
        #expect(AdresseIPv6("fe80::5a:d5f3:dc72:e7d6")?.estLienLocal == true)
        #expect(!a.estLienLocal)
        #expect(AdresseIPv6.estIPv4("192.0.2.25"))
        #expect(!AdresseIPv6.estIPv4("fe80::1"))
    }

    @Test func prefixes() throws {
        let p = try #require(PrefixeIPv6("fd19:961f:2db3::/64"))
        #expect(p.description == "fd19:961f:2db3::/64")
        #expect(PrefixeIPv6("fd19:961f:2db3::")?.description == "fd19:961f:2db3::/64")
        #expect(PrefixeIPv6("fd19:961f:2db3::/48") == nil)
        let dedans = try #require(AdresseIPv6("fd19:961f:2db3:0:34a9:8acf:e48d:c424"))
        let dehors = try #require(AdresseIPv6("fd03:54f0:5de:1::5"))
        #expect(p.contient(dedans))
        #expect(!p.contient(dehors))
        #expect(dedans.prefixe == p)
        #expect(dehors.prefixe.description == "fd03:54f0:5de:1::/64")
    }

    @Test func champOMR() {
        // Aqara HubM100, releve du 28/09 : omr=40FD0354F005DE0001
        let omr = Data([0x40, 0xFD, 0x03, 0x54, 0xF0, 0x05, 0xDE, 0x00, 0x01])
        #expect(PrefixeIPv6(omr: omr)?.description == "fd03:54f0:5de:1::/64")
        #expect(PrefixeIPv6(omr: Data([0x30] + [UInt8](repeating: 0, count: 8))) == nil, "longueur 48 refusee")
        #expect(PrefixeIPv6(omr: Data([0x40, 0xFD])) == nil)
    }

    @Test func reseauLocalTireDuXP() {
        // xp=4B36A2B7FEFB200B -> fd4b:36a2:b7fe:200b::/64 (table de routage du Mac, 28/09)
        let xp: [UInt8] = [0x4B, 0x36, 0xA2, 0xB7, 0xFE, 0xFB, 0x20, 0x0B]
        #expect(PrefixeIPv6(reseauLocalDe: xp)?.description == "fd4b:36a2:b7fe:200b::/64")
        #expect(PrefixeIPv6(reseauLocalDe: [0x01]) == nil)
    }

    @Test func ordreEtJSON() throws {
        let a = try #require(PrefixeIPv6("fd03:54f0:5de:1::/64"))
        let b = try #require(PrefixeIPv6("fd19:961f:2db3::/64"))
        #expect([b, a].sorted() == [a, b])
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = .withoutEscapingSlashes
        let json = try encodeur.encode([a])
        #expect(String(decoding: json, as: UTF8.self) == "[\"fd03:54f0:5de:1::/64\"]")
        #expect(try JSONDecoder().decode([PrefixeIPv6].self, from: json) == [a])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PrefixeIPv6].self, from: Data("[\"pas un prefixe\"]".utf8))
        }
    }
}
