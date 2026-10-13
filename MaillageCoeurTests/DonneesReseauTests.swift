import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Network Data : routeurs de bordure et BBR")
struct DonneesReseauTests {
    /// Network Data de la partition d'Apple, lues au routeur 5000 : les 5 routeurs
    /// de bordure (route fc00::/7, service SRP), B400 principal (BBR).
    @Test func partitionApple() throws {
        let r = try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(206)))
        let brutes = try #require(r.donneesReseau)
        let d = try #require(DonneesReseau(brutes))
        #expect(d.routeursDeBordure == [0x0400, 0xAC00, 0xB400, 0xCC00, 0xE400])
        #expect(d.bbr == [0xB400])
    }

    /// Prefixe /64 publie par un routeur de bordure, route seule par un autre.
    @Test func construites() throws {
        // Prefix (stable) fd00:1:2:3::/64 : Border Router 4800 ; Prefix ::/0 : Has Route 5C00.
        let omr: [UInt8] = [0x03, 16, 0x00, 64, 0xFD, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03,
                            0x04, 4, 0x48, 0x00, 0x00, 0x00]
        let route: [UInt8] = [0x03, 7, 0x00, 0, 0x00, 3, 0x5C, 0x00, 0x00]
        let d = try #require(DonneesReseau(omr + route))
        #expect(d.routeursDeBordure == [0x4800, 0x5C00])
        #expect(d.bbr.isEmpty)
    }

    @Test func tronquees() throws {
        #expect(DonneesReseau([0x03, 10, 0x00]) == nil)
        let vide = try #require(DonneesReseau([]))
        let inconnue = try #require(DonneesReseau([0x10, 0]), "une TLV inconnue n'est pas une erreur")
        #expect(vide == inconnue, "vides, ou TLV inconnue : rien")
        #expect(vide.routeursDeBordure.isEmpty && vide.bbr.isEmpty)
    }

    // TLV de Network Data construites a la main : type (7 bits) et bit stable, longueur, valeur.

    static func tlv(_ type: UInt8, _ valeur: [UInt8], stable: Bool = true) -> [UInt8] {
        [type << 1 | (stable ? 1 : 0), UInt8(valeur.count)] + valeur
    }

    /// Prefix (type 1) : domaine 0, longueur en bits, octets du prefixe, puis ses sous-TLV.
    static func prefixe(_ bits: Int, _ octets: [UInt8], _ sousTLV: [UInt8]...) -> [UInt8] {
        tlv(1, [0x00, UInt8(bits)] + octets + sousTLV.flatMap { $0 })
    }

    /// Border Router (type 2) : RLOC16 et 2 octets de drapeaux par routeur.
    static func routeurDeBordure(_ rlocs: UInt16...) -> [UInt8] {
        tlv(2, rlocs.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF), 0x00, 0x00] }, stable: false)
    }

    /// Server (type 6) : RLOC16, puis les donnees du serveur.
    static func serveur(_ rloc: UInt16, _ donnees: [UInt8] = []) -> [UInt8] {
        tlv(6, [UInt8(rloc >> 8), UInt8(rloc & 0xFF)] + donnees)
    }

    /// Service (type 5) : T et identifiant, numero d'entreprise (sur 4 octets, si `entreprise` : T vaut 0 ;
    /// sinon T vaut 1 et celui de Thread est omis), donnees de service, puis les serveurs.
    static func service(entreprise: UInt32? = nil, id: UInt8 = 0, donnees: [UInt8], serveurs: [[UInt8]]) -> [UInt8] {
        var v: [UInt8]
        if let e = entreprise {
            v = [id & 0x0F, UInt8(e >> 24), UInt8((e >> 16) & 0xFF), UInt8((e >> 8) & 0xFF), UInt8(e & 0xFF)]
        } else {
            v = [0x80 | (id & 0x0F)]
        }
        return tlv(5, v + [UInt8(donnees.count)] + donnees + serveurs.flatMap { $0 })
    }

    /// Donnees d'un serveur BBR : sequence 0x57, reenregistrement 5 s, delai MLR 3600 s.
    static let donneesBBR: [UInt8] = [0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10]

    /// Adresse IPv6 et port d'un service SRP en unicast.
    static let adresseEtPort = [UInt8](repeating: 0x20, count: 16) + [0x1F, 0x90]

    /// Service SRP, en anycast (donnees 5C, puis la sequence) et en unicast (5D, l'adresse et le port dans les
    /// donnees du serveur, ou dans celles du service) : ses serveurs sont des routeurs de bordure, sans prefixe
    /// ni route. Pas des BBR.
    @Test func serviceSRP() throws {
        let anycast = Self.service(donnees: [0x5C, 0x02], serveurs: [Self.serveur(0x3800), Self.serveur(0x4400)])
        let unicastServeur = Self.service(id: 1, donnees: [0x5D], serveurs: [Self.serveur(0x7D8B, Self.adresseEtPort)])
        let unicastService = Self.service(id: 2, donnees: [0x5D] + Self.adresseEtPort, serveurs: [Self.serveur(0x8C00)])
        let d = try #require(DonneesReseau(anycast + unicastServeur + unicastService))
        #expect(d.routeursDeBordure == [0x3800, 0x4400, 0x7D8B, 0x8C00])
        #expect(d.bbr.isEmpty)
    }

    /// Service dont T vaut 0 : le numero d'entreprise suit, sur 4 octets. Celui de Thread (44970, 0xAFAA) donne
    /// les memes roles que T = 1.
    @Test func serviceAvecLeNumeroDEntrepriseDeThread() throws {
        let bbr = Self.service(entreprise: 44970, donnees: [0x01], serveurs: [Self.serveur(0xB400, Self.donneesBBR)])
        let srp = Self.service(entreprise: 44970, id: 1, donnees: [0x5C, 0x02], serveurs: [Self.serveur(0x3800)])
        let d = try #require(DonneesReseau(bbr + srp))
        #expect(d.bbr == [0xB400])
        #expect(d.routeursDeBordure == [0x3800])
    }

    /// Service d'un autre fabricant (T vaut 0, un autre numero d'entreprise) : ses donnees n'ont pas le sens de
    /// 01, 5C ou 5D ; il n'est ni BBR ni SRP, meme si ses donnees commencent par ces octets.
    @Test func serviceDUnAutreFabricant() throws {
        for entreprise: UInt32 in [0, 1, 44969, 44971, 0x0001_AFAA, 0xAFAA_0000] {
            let bbr = Self.service(entreprise: entreprise, donnees: [0x01], serveurs: [Self.serveur(0xB400, Self.donneesBBR)])
            let anycast = Self.service(entreprise: entreprise, id: 1, donnees: [0x5C, 0x02], serveurs: [Self.serveur(0x3800)])
            let unicast = Self.service(entreprise: entreprise, id: 2, donnees: [0x5D],
                                       serveurs: [Self.serveur(0x7D8B, Self.adresseEtPort)])
            let d = try #require(DonneesReseau(bbr + anycast + unicast), "entreprise \(entreprise)")
            #expect(d.bbr.isEmpty, "BBR, entreprise \(entreprise)")
            #expect(d.routeursDeBordure.isEmpty, "SRP, entreprise \(entreprise)")
        }
        // Un service de Thread a la suite d'un autre fabricant reste lu.
        let autre = Self.service(entreprise: 7, donnees: [0x01], serveurs: [Self.serveur(0x5000, Self.donneesBBR)])
        let thread = Self.service(id: 1, donnees: [0x01], serveurs: [Self.serveur(0xB400, Self.donneesBBR)])
        #expect(try #require(DonneesReseau(autre + thread)).bbr == [0xB400])
        // Numero d'entreprise coupe : le service est ignore, pas les donnees.
        let coupe = Self.tlv(5, [0x00, 0x00, 0x00])
        let d = try #require(DonneesReseau(coupe + thread))
        #expect(d.bbr == [0xB400])
    }

    /// Un routeur qui publie un prefixe est de bordure, quelle que soit la longueur du prefixe (/48, /64, /128) ;
    /// un Border Router peut en nommer plusieurs.
    @Test func routeurDeBordureQuelleQueSoitLaLongueurDuPrefixe() throws {
        let p48 = Self.prefixe(48, [0xFD, 0x00, 0x00, 0x01, 0x00, 0x02], Self.routeurDeBordure(0x4800, 0x5000))
        let p64 = Self.prefixe(64, [0xFD, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03], Self.routeurDeBordure(0x6400))
        let p128 = Self.prefixe(128, [UInt8](repeating: 0xFD, count: 16), Self.routeurDeBordure(0x8000))
        #expect(try #require(DonneesReseau(p48)).routeursDeBordure == [0x4800, 0x5000])
        #expect(try #require(DonneesReseau(p64)).routeursDeBordure == [0x6400])
        #expect(try #require(DonneesReseau(p128)).routeursDeBordure == [0x8000])
        #expect(try #require(DonneesReseau(p48 + p64 + p128)).routeursDeBordure == [0x4800, 0x5000, 0x6400, 0x8000])
    }

    /// Sous-TLV qui deborde de son Prefix, ou Server qui deborde de son Service : le Prefix ou le Service est
    /// ignore en silence, sans perdre les TLV suivantes ; si le bloc lui-meme deborde, c'est nil.
    @Test func sousTLVTronque() throws {
        let route = Self.prefixe(0, [], Self.tlv(0, [0x5C, 0x00, 0x00], stable: false))
        let thread = Self.service(id: 1, donnees: [0x01], serveurs: [Self.serveur(0xB400, Self.donneesBBR)])
        // Prefix dont le Border Router annonce 9 octets et n'en a que 2 : le bloc est entier, pas ce qu'il contient.
        let prefixeCoupe = Self.tlv(1, [0x00, 64, 0xFD, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x04, 9, 0x48, 0x00])
        let d1 = try #require(DonneesReseau(prefixeCoupe + route + thread))
        #expect(d1.routeursDeBordure == [0x5C00], "le Prefix coupe ne donne rien, le suivant est lu")
        #expect(d1.bbr == [0xB400])
        // Service dont le second Server annonce 9 octets et n'en a que 2 : tout le service est ignore.
        let serviceCoupe = Self.tlv(5, [0x80, 1, 0x01] + Self.serveur(0xAC00, Self.donneesBBR) + [0x0D, 9, 0x50, 0x00])
        let d2 = try #require(DonneesReseau(serviceCoupe + route))
        #expect(d2.bbr.isEmpty)
        #expect(d2.routeursDeBordure == [0x5C00])
        // Donnees de service plus longues que le service : ignore aussi.
        let donneesCoupees = Self.tlv(5, [0x80, 9, 0x01])
        #expect(try #require(DonneesReseau(donneesCoupees + thread)).bbr == [0xB400])
        // Le bloc lui-meme deborde : nil.
        #expect(DonneesReseau(Array(prefixeCoupe.dropLast())) == nil)
        #expect(DonneesReseau(route + Array(thread.dropLast())) == nil)
    }

    // Ordre des serveurs BBR : celui d'OpenThread (Manager::IsBackboneRouterPreferredTo), le chef mis a part.
    // Un Server (stable) de BBR : 0x0D, 9 octets = RLOC16 (2), puis les donnees de serveur (7) :
    // sequence (1), delai de reenregistrement (2), delai MLR (4).

    /// Deux serveurs BBR d'un meme service, E400 (sequence 0x10) puis B400 (sequence 0x57) : la sequence
    /// la plus haute passe avant l'ordre du document.
    @Test func bbrSequenceLaPlusHaute() throws {
        let service: [UInt8] = [
            0x0B, 25,                                  // Service (stable), 25 octets
            0x80,                                      // T = 1 (numero d'entreprise Thread omis), identifiant 0
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 9, 0xE4, 0x00,                       // Server (stable), 9 octets : RLOC16 E400
            0x10, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x10, reenregistrement 5 s, delai MLR 3600 s
            0x0D, 9, 0xB4, 0x00,                       // Server (stable), 9 octets : RLOC16 B400
            0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x57, memes delais
        ]
        let d = try #require(DonneesReseau(service))
        #expect(d.bbr == [0xB400, 0xE400])
    }

    /// Deux serveurs BBR de meme sequence, 5000 puis AC00 : le RLOC16 le plus haut d'abord.
    @Test func bbrMemeSequence() throws {
        let service: [UInt8] = [
            0x0B, 25,                                  // Service (stable), 25 octets
            0x80,                                      // T = 1, identifiant 0
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 9, 0x50, 0x00,                       // Server (stable), 9 octets : RLOC16 5000
            0x22, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x22, reenregistrement 5 s, delai MLR 3600 s
            0x0D, 9, 0xAC, 0x00,                       // Server (stable), 9 octets : RLOC16 AC00
            0x22, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x22 aussi, memes delais
        ]
        let d = try #require(DonneesReseau(service))
        #expect(d.bbr == [0xAC00, 0x5000])
    }

    /// Sequence comparee simplement, sans arithmetique de serie : 0xFF passe avant 0x01.
    @Test func bbrSequenceComparaisonSimple() throws {
        let service: [UInt8] = [
            0x0B, 25,                                  // Service (stable), 25 octets
            0x80,                                      // T = 1, identifiant 0
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 9, 0xAC, 0x00,                       // Server (stable), 9 octets : RLOC16 AC00
            0x01, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x01, reenregistrement 5 s, delai MLR 3600 s
            0x0D, 9, 0x50, 0x00,                       // Server (stable), 9 octets : RLOC16 5000
            0xFF, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0xFF, memes delais
        ]
        let d = try #require(DonneesReseau(service))
        #expect(d.bbr == [0x5000, 0xAC00])
    }

    /// Serveurs BBR aux donnees trop courtes (moins de 7 octets) : ignores, meme avec la sequence la plus haute.
    @Test func bbrDonneesTropCourtes() throws {
        let service: [UInt8] = [
            0x0B, 28,                                  // Service (stable), 28 octets
            0x80,                                      // T = 1, identifiant 0
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 8, 0xE4, 0x00,                       // Server (stable), 8 octets : RLOC16 E400
            0x99, 0x00, 0x05, 0x00, 0x00, 0x0E,        //   6 octets de donnees : sequence 0x99, delai MLR coupe
            0x0D, 2, 0xCC, 0x00,                       // Server (stable), 2 octets : RLOC16 CC00, sans donnees
            0x0D, 9, 0xB4, 0x00,                       // Server (stable), 9 octets : RLOC16 B400
            0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   7 octets de donnees, le minimum : sequence 0x57
        ]
        let d = try #require(DonneesReseau(service))
        #expect(d.bbr == [0xB400])
    }

    /// Deux TLV Service BBR, un serveur chacune : tous les serveurs comptent avant le tri.
    @Test func bbrPlusieursServices() throws {
        let services: [UInt8] = [
            0x0B, 14,                                  // Service (stable), 14 octets
            0x80,                                      // T = 1, identifiant 0
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 9, 0xAC, 0x00,                       // Server (stable), 9 octets : RLOC16 AC00
            0x05, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x05, reenregistrement 5 s, delai MLR 3600 s
            0x0B, 14,                                  // Service (stable), 14 octets
            0x81,                                      // T = 1, identifiant 1
            1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
            0x0D, 9, 0x50, 0x00,                       // Server (stable), 9 octets : RLOC16 5000
            0x09, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x09, memes delais
        ]
        let d = try #require(DonneesReseau(services))
        #expect(d.bbr == [0x5000, 0xAC00])
    }
}
