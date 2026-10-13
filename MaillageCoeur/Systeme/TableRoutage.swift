import Darwin

/// Routes IPv6 du Mac (sysctl NET_RT_DUMP) : les prefixes /64 routes par un
/// routeur lien-local, c'est-a-dire les prefixes OMR annonces par les routeurs
/// de bordure (et ceux que pose Thread Route, l'assistant systeme, anciennement halo-routes).
public enum TableRoutage {
    /// Lit la table ; nil si le systeme refuse (bac a sable) ou echoue.
    public static func lire() -> [RouteIPv6]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET6, NET_RT_DUMP, 0]
        let n = UInt32(mib.count)
        var taille = 0
        guard sysctl(&mib, n, nil, &taille, nil, 0) == 0, taille > 0 else { return nil }
        var tampon = [UInt8](repeating: 0, count: taille)
        guard sysctl(&mib, n, &tampon, &taille, nil, 0) == 0 else { return nil }
        return analyser(Array(tampon.prefix(taille)), nomInterface: nomInterface)
    }

    static func nomInterface(_ index: UInt16) -> String? {
        var nom = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &nom) != nil else { return nil }
        return nom.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Analyse le tampon de NET_RT_DUMP : des messages `rt_msghdr`, chacun suivi
    /// de ses adresses (sockaddr arrondis a 4 octets, dans l'ordre des bits de
    /// `rtm_addrs`). Garde les routes par passerelle, de longueur 64, dont la
    /// passerelle est lien-local ; retire la zone que le noyau glisse dans les
    /// octets 2-3 des adresses lien-local.
    static func analyser(_ o: [UInt8], nomInterface: (UInt16) -> String?) -> [RouteIPv6] {
        var routes: [RouteIPv6] = []
        let tailleEntete = MemoryLayout<rt_msghdr>.size
        var i = 0
        while i + tailleEntete <= o.count {
            let entete = o.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i, as: rt_msghdr.self) }
            let longueur = Int(entete.rtm_msglen)
            guard longueur >= tailleEntete, i + longueur <= o.count else { break }
            let debut = i
            let fin = i + longueur
            i = fin
            guard entete.rtm_flags & RTF_GATEWAY != 0, entete.rtm_flags & RTF_HOST == 0 else { continue }
            var j = debut + tailleEntete
            var destination: [UInt8]?
            var passerelle: [UInt8]?
            var masque = 128
            for bit in 0..<8 where entete.rtm_addrs & (1 << bit) != 0 {
                guard j + 1 < fin else { break }
                let longueurSa = Int(o[j])
                let famille = Int32(o[j + 1])
                switch Int32(1 << bit) {
                case RTA_DST where famille == AF_INET6 && longueurSa >= 24 && j + 24 <= fin:
                    destination = Array(o[(j + 8)..<(j + 24)])
                case RTA_GATEWAY where famille == AF_INET6 && longueurSa >= 24 && j + 24 <= fin:
                    passerelle = Array(o[(j + 8)..<(j + 24)])
                case RTA_NETMASK:
                    masque = longueurMasque(o, debut: j + 8, fin: min(j + longueurSa, j + 24, fin))
                default:
                    break
                }
                j += longueurSa == 0 ? 4 : (longueurSa + 3) & ~3
            }
            guard masque == 64, let d = destination, var g = passerelle,
                  let prefixe = PrefixeIPv6(octets: Array(d[0..<8])) else { continue }
            g[2] = 0
            g[3] = 0
            guard let adresse = AdresseIPv6(octets: g), adresse.estLienLocal else { continue }
            routes.append(RouteIPv6(prefixe: prefixe.description, passerelle: adresse.description,
                                    interface: nomInterface(entete.rtm_index)))
        }
        return routes
    }

    /// Nombre de bits a 1 en tete du masque (octets absents = 0).
    static func longueurMasque(_ o: [UInt8], debut: Int, fin: Int) -> Int {
        var n = 0
        var k = debut
        while k < fin {
            let b = o[k]
            if b == 0xFF {
                n += 8
                k += 1
                continue
            }
            n += (~b).leadingZeroBitCount
            break
        }
        return n
    }
}
