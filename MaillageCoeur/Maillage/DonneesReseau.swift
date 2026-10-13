import Foundation

/// Network Data d'une partition (TLV 7) : ce qui sert a la sonde, par RLOC16.
/// Chaque TLV : type (7 bits) et bit stable, longueur, valeur.
public struct DonneesReseau: Hashable, Sendable {
    /// Routeurs de bordure : ceux qui publient un prefixe (Border Router), une
    /// route (Has Route) ou le service SRP.
    public private(set) var routeursDeBordure: Set<UInt16> = []
    /// Serveurs du service BBR (donnees 01), du plus au moins prefere, hors chef, dans l'ordre
    /// d'OpenThread (`Manager::IsBackboneRouterPreferredTo`, network_data_service.cpp) : sequence la
    /// plus haute (comparaison simple), puis RLOC16 le plus haut ; un serveur dont les donnees font
    /// moins de 7 octets est ignore. Le chef, que cette regle place avant tous, n'est donc pas
    /// forcement en tete : `ConstructionMaillage.reseau(_:)`, qui seul le connait, le prefere s'il
    /// est parmi les serveurs.
    public private(set) var bbr: [UInt16] = []

    static let prefixe: UInt8 = 1, service: UInt8 = 5
    static let aUneRoute: UInt8 = 0, routeurDeBordure: UInt8 = 2, serveur: UInt8 = 6
    /// Donnees de service : BBR (Thread 1.2), SRP en anycast et en unicast.
    static let serviceBBR: UInt8 = 0x01, serviceSRPAnycast: UInt8 = 0x5C, serviceSRPUnicast: UInt8 = 0x5D
    /// Donnees de serveur d'un BBR : sequence (1 octet), delai de reenregistrement (2), delai MLR (4).
    static let octetsDonneesBBR = 7
    /// Numero d'entreprise de Thread (44970, 0xAFAA) : celui des services ou T vaut 1, ou il est omis.
    static let entrepriseThread: UInt32 = 44970

    /// nil si une TLV depasse la fin des donnees.
    public init?(_ o: [UInt8]) {
        guard let tlv = Self.tlv(o) else { return nil }
        var serveursBBR: [(rloc: UInt16, sequence: UInt8)] = []
        for (t, v) in tlv {
            switch t {
            case Self.prefixe: prefixe(v)
            case Self.service: service(v, serveursBBR: &serveursBBR)
            default: break
            }
        }
        // Tous les services BBR lus, puis le tri : sequence la plus haute, a egalite RLOC16 le plus haut.
        bbr = serveursBBR.sorted { ($0.sequence, $0.rloc) > ($1.sequence, $1.rloc) }.map(\.rloc)
    }

    /// Prefix : domaine, longueur en bits, prefixe, puis ses sous-TLV.
    private mutating func prefixe(_ v: [UInt8]) {
        guard v.count >= 2 else { return }
        let bits = Int(v[1]), debut = 2 + (bits + 7) / 8
        guard debut <= v.count, let sous = Self.tlv(Array(v[debut...])) else { return }
        for (t, s) in sous {
            switch t {
            case Self.routeurDeBordure:
                routeursDeBordure.formUnion(stride(from: 0, to: s.count - 3, by: 4).map { UInt16(s[$0]) << 8 | UInt16(s[$0 + 1]) })
            case Self.aUneRoute:
                routeursDeBordure.formUnion(stride(from: 0, to: s.count - 2, by: 3).map { UInt16(s[$0]) << 8 | UInt16(s[$0 + 1]) })
            default: break
            }
        }
    }

    /// Service : T et identifiant, numero d'entreprise (si T vaut 0), donnees, puis ses serveurs.
    /// T vaut 1 : le numero est celui de Thread, omis. T vaut 0 : il suit sur 4 octets, et seul celui
    /// de Thread (44970) compte ; le service d'un autre fabricant est ignore, car ses donnees n'ont
    /// pas le sens de 01, 5C ou 5D.
    /// Chaque serveur : RLOC16, puis ses donnees ; celles d'un BBR commencent par la sequence.
    private mutating func service(_ v: [UInt8], serveursBBR: inout [(rloc: UInt16, sequence: UInt8)]) {
        guard let premier = v.first else { return }
        var j = 1
        if premier & 0x80 == 0 {
            guard v.count >= 5, v[1...4].reduce(UInt32(0), { $0 << 8 | UInt32($1) }) == Self.entrepriseThread else { return }
            j = 5
        }
        guard j < v.count else { return }
        let longueur = Int(v[j])
        guard j + 1 + longueur <= v.count else { return }
        let donnees = Array(v[(j + 1)..<(j + 1 + longueur)])
        j += 1 + longueur
        guard let sous = Self.tlv(Array(v[j...])) else { return }
        let serveurs = sous.filter { $0.type == Self.serveur && $0.valeur.count >= 2 }
            .map { (rloc: UInt16($0.valeur[0]) << 8 | UInt16($0.valeur[1]), donnees: Array($0.valeur.dropFirst(2))) }
        switch donnees.first {
        case Self.serviceBBR?:
            serveursBBR += serveurs.filter { $0.donnees.count >= Self.octetsDonneesBBR }
                .map { (rloc: $0.rloc, sequence: $0.donnees[0]) }
        case Self.serviceSRPAnycast?, Self.serviceSRPUnicast?: routeursDeBordure.formUnion(serveurs.map(\.rloc))
        default: break
        }
    }

    /// Suite de TLV (type sans le bit stable, valeur) ; nil si l'une deborde.
    static func tlv(_ o: [UInt8]) -> [(type: UInt8, valeur: [UInt8])]? {
        var res: [(type: UInt8, valeur: [UInt8])] = []
        var i = 0
        while i < o.count {
            guard i + 2 <= o.count, i + 2 + Int(o[i + 1]) <= o.count else { return nil }
            res.append((o[i] >> 1, Array(o[(i + 2)..<(i + 2 + Int(o[i + 1]))])))
            i += 2 + Int(o[i + 1])
        }
        return res
    }
}
