import Darwin

/// Adresse IPv6 : 16 octets. Lue depuis le texte (avec ou sans zone "%en0"),
/// ecrite sous la forme courte de inet_ntop ("fd19:961f:2db3:0:2c97:...").
public struct AdresseIPv6: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public let octets: [UInt8]

    public init?(octets: [UInt8]) {
        guard octets.count == 16 else { return nil }
        self.octets = octets
    }

    public init?(_ texte: String) {
        let sansZone = String(texte.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        var brut = in6_addr()
        guard inet_pton(AF_INET6, sansZone, &brut) == 1 else { return nil }
        octets = withUnsafeBytes(of: brut) { Array($0) }
    }

    public var description: String {
        var brut = in6_addr()
        withUnsafeMutableBytes(of: &brut) { $0.copyBytes(from: octets) }
        var tampon = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let taille = socklen_t(tampon.count)
        guard inet_ntop(AF_INET6, &brut, &tampon, taille) != nil else { return "::" }
        return tampon.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// fe80::/10 : adresse de lien, jamais routee.
    public var estLienLocal: Bool { octets[0] == 0xFE && (octets[1] & 0xC0) == 0x80 }

    /// Prefixe /64 de l'adresse.
    public var prefixe: PrefixeIPv6 { PrefixeIPv6(huitOctets: Array(octets[0..<8])) }

    /// En JSON, le texte de l'adresse (comme `PrefixeIPv6`) : un texte invalide est refuse au decodage, jamais une
    /// adresse qui n'aurait pas 16 octets.
    public init(from decoder: Decoder) throws {
        let texte = try decoder.singleValueContainer().decode(String.self)
        guard let a = AdresseIPv6(texte) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "adresse IPv6 invalide : \(texte)"))
        }
        self = a
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: AdresseIPv6, b: AdresseIPv6) -> Bool {
        a.octets.lexicographicallyPrecedes(b.octets)
    }

    /// Texte d'une adresse IPv4 valide ("192.0.2.25").
    public static func estIPv4(_ texte: String) -> Bool {
        var brut = in_addr()
        return inet_pton(AF_INET, texte, &brut) == 1
    }
}
