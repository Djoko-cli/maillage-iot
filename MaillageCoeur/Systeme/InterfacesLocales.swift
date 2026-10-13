import Darwin

/// Prefixes du reseau local, vus depuis les interfaces du Mac.
public enum InterfacesLocales {
    /// Prefixes /64 des adresses IPv6 (hors lien-local) des interfaces actives
    /// du Mac, hors boucle locale, tries.
    public static func prefixes() -> [String] {
        var tete: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&tete) == 0, let premiere = tete else { return [] }
        defer { freeifaddrs(tete) }
        var resultat = Set<PrefixeIPv6>()
        for p in sequence(first: premiere, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard i.ifa_flags & UInt32(IFF_UP) != 0, i.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let sa = i.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET6 else { continue }
            let octets = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s in
                withUnsafeBytes(of: s.pointee.sin6_addr) { Array($0) }
            }
            guard let adresse = AdresseIPv6(octets: octets), !adresse.estLienLocal else { continue }
            resultat.insert(adresse.prefixe)
        }
        return resultat.sorted().map(\.description)
    }
}
