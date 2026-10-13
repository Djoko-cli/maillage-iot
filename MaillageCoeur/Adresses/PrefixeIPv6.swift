import Foundation

/// Prefixe IPv6 de longueur 64 (prefixes OMR, reseau local) : ses 8 premiers
/// octets. En texte et en JSON : "fd19:961f:2db3::/64".
public struct PrefixeIPv6: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public let octets: [UInt8]

    init(huitOctets: [UInt8]) {
        precondition(huitOctets.count == 8)
        octets = huitOctets
    }

    public init?(octets: [UInt8]) {
        guard octets.count == 8 else { return nil }
        self.octets = octets
    }

    /// "fd19:961f:2db3::/64" ou "fd19:961f:2db3::" ; une autre longueur que 64 est refusee.
    public init?(_ texte: String) {
        let morceaux = texte.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        if morceaux.count == 2 && morceaux[1] != "64" { return nil }
        guard let adresse = AdresseIPv6(String(morceaux[0])) else { return nil }
        octets = Array(adresse.octets[0..<8])
    }

    /// Champ TXT `omr` d'un routeur de bordure : longueur en bits (0x40) puis le prefixe.
    public init?(omr: Data) {
        let o = [UInt8](omr)
        guard o.count >= 9, o[0] == 64 else { return nil }
        octets = Array(o[1...8])
    }

    /// Prefixe on-link des routeurs de bordure, tire de l'identifiant etendu du
    /// reseau (`xp`, 8 octets) : fd + 5 premiers octets + 2 derniers.
    public init?(reseauLocalDe xp: [UInt8]) {
        guard xp.count == 8 else { return nil }
        octets = [0xFD] + Array(xp[0..<5]) + Array(xp[6..<8])
    }

    public func contient(_ adresse: AdresseIPv6) -> Bool {
        Array(adresse.octets[0..<8]) == octets
    }

    public var description: String {
        (AdresseIPv6(octets: octets + [UInt8](repeating: 0, count: 8))?.description ?? "::") + "/64"
    }

    public static func < (a: PrefixeIPv6, b: PrefixeIPv6) -> Bool {
        a.octets.lexicographicallyPrecedes(b.octets)
    }

    public init(from decoder: Decoder) throws {
        let texte = try decoder.singleValueContainer().decode(String.self)
        guard let p = PrefixeIPv6(texte) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "prefixe IPv6 invalide : \(texte)"))
        }
        self = p
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
