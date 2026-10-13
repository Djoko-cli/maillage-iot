import Darwin
import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Systeme : table de routage et prefixes du Mac")
struct SystemeTests {
    /// sockaddr_in6 complet ; `portee` : zone glissee par le noyau dans les octets 2-3.
    static func adresse(_ texte: String, portee: UInt16 = 0) -> [UInt8] {
        var o = [UInt8](repeating: 0, count: 28)
        o[0] = 28
        o[1] = UInt8(AF_INET6)
        o.replaceSubrange(8..<24, with: AdresseIPv6(texte)!.octets)
        if portee != 0 {
            o[10] = UInt8(portee >> 8)
            o[11] = UInt8(portee & 0xFF)
        }
        return o
    }

    /// Masque tronque comme le noyau l'ecrit, complete a 4 octets.
    static func masque(_ bits: Int) -> [UInt8] {
        let n = (bits + 7) / 8
        var o = [UInt8](repeating: 0, count: 8 + n)
        o[0] = UInt8(8 + n)
        for i in 0..<n {
            let reste = bits - 8 * i
            o[8 + i] = reste >= 8 ? 0xFF : UInt8((0xFF << (8 - reste)) & 0xFF)
        }
        return o + [UInt8](repeating: 0, count: (4 - o.count % 4) % 4)
    }

    static func message(drapeaux: Int32, index: UInt16 = 7, adresses: [[UInt8]],
                        bits: Int32 = RTA_DST | RTA_GATEWAY | RTA_NETMASK) -> [UInt8] {
        let corps = adresses.flatMap { $0 }
        var h = rt_msghdr()
        h.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + corps.count)
        h.rtm_version = UInt8(RTM_VERSION)
        h.rtm_type = UInt8(RTM_GET)
        h.rtm_index = index
        h.rtm_flags = drapeaux
        h.rtm_addrs = bits
        return withUnsafeBytes(of: h) { Array($0) } + corps
    }

    @Test func analyse() {
        let passerelle = Self.adresse("fe80::5a:d5f3:dc72:e7d6", portee: 7)
        let tampon = Self.message(drapeaux: RTF_UP | RTF_GATEWAY,
                                  adresses: [Self.adresse("fd19:961f:2db3::"), passerelle, Self.masque(64)])
            + Self.message(drapeaux: RTF_UP | RTF_GATEWAY | RTF_HOST,
                           adresses: [Self.adresse("fd19:961f:2db3::1"), passerelle, Self.masque(128)])
            + Self.message(drapeaux: RTF_UP | RTF_GATEWAY,
                           adresses: [Self.adresse("fd7a:115c:a1e0::"), passerelle, Self.masque(48)])
            + Self.message(drapeaux: RTF_UP,
                           adresses: [Self.adresse("fd4b:36a2:b7fe:200b::"), passerelle, Self.masque(64)])
            + Self.message(drapeaux: RTF_UP | RTF_GATEWAY, index: 9,
                           adresses: [Self.adresse("fd03:54f0:5de:1::"), Self.adresse("fe80::56ef:44ff:fe97:b882", portee: 9),
                                      Self.masque(64)])
        let routes = TableRoutage.analyser(tampon) { "if\($0)" }
        #expect(routes == [
            RouteIPv6(prefixe: "fd19:961f:2db3::/64", passerelle: "fe80::5a:d5f3:dc72:e7d6", interface: "if7"),
            RouteIPv6(prefixe: "fd03:54f0:5de:1::/64", passerelle: "fe80::56ef:44ff:fe97:b882", interface: "if9"),
        ], "hote, /48 et sans passerelle ignores ; zone retiree de l'adresse lien-local")
        #expect(TableRoutage.analyser(Array(tampon.prefix(50))) { _ in nil } == [], "tampon tronque")
        #expect(TableRoutage.longueurMasque([0xFF, 0xFF, 0xF0, 0x00], debut: 0, fin: 4) == 20)
    }

    @Test func tableDuMac() throws {
        // Hors bac a sable (tests du framework) : la table se lit.
        let routes = try #require(TableRoutage.lire())
        for r in routes {
            #expect(PrefixeIPv6(r.prefixe) != nil)
            #expect(r.passerelle.flatMap { AdresseIPv6($0) }?.estLienLocal == true)
        }
        #expect(InterfacesLocales.prefixes().allSatisfy { PrefixeIPv6($0) != nil })
    }
}
