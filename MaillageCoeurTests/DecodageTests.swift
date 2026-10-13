import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Decodage des annonces")
struct DecodageTests {
    /// TXT d'un routeur de bordure comme le 28/09 (octets bas de `sb` reconstitues).
    static func txtRouteur(tv: String, sb: [UInt8], pt: [UInt8], omr: [UInt8]? = nil) -> ChampsTXT {
        var v: [String: Data] = [
            "vn": Data("Apple".utf8), "mn": Data("BorderRouter".utf8), "tv": Data(tv.utf8),
            "nn": Data("MyHome1482620090".utf8),
            "xp": Data([0x4B, 0x36, 0xA2, 0xB7, 0xFE, 0xFB, 0x20, 0x0B]),
            "xa": Data([0x2A, 0, 0, 0, 0, 0, 0, 0x01]),
            "sb": Data(sb), "pt": Data(pt),
            "at": Data([0x00, 0x00, 0x66, 0xCE, 0xC7, 0x00, 0x00, 0x00]),
        ]
        if let omr { v["omr"] = Data(omr) }
        return ChampsTXT(v)
    }

    @Test func chef() throws {
        let annonce = AnnonceService(instance: "Apple TV 4K", hote: "Apple-TV-4K.local", port: 49153,
                                     txt: Self.txtRouteur(tv: "1.4.0", sb: [0, 0, 0x0F, 0xB1], pt: [0x73, 0x58, 0x6B, 0x68]))
        let r = RouteurBordure(annonce: annonce, adresses: ["fe80::5a:d5f3:dc72:e7d6", "192.0.2.25",
                                                            "fd4b:36a2:b7fe:200b:3:fd31:8a5a:34f5"])
        #expect(r.id == "Apple TV 4K")
        #expect(r.nomReseau == "MyHome1482620090")
        #expect(r.idReseau == "4B36A2B7FEFB200B")
        #expect(r.adresseEtendue == "2A00000000000001")
        #expect(r.partition == "73586B68")
        #expect(r.jeuActif == Date(timeIntervalSince1970: 1_724_827_392), "2024-08-28T06:43:12Z")
        #expect(r.role == .chef)
        #expect(r.etat?.interface == .active)
        #expect(r.etat?.bbrActif == true)
        #expect(r.etat?.bbrPrimaire == true)
        #expect(r.prefixeOMR == nil)
        #expect(r.prefixeReseauLocal?.description == "fd4b:36a2:b7fe:200b::/64")
        #expect(r.adresses.count == 2, "l'IPv4 n'est pas une adresse IPv6")
        #expect(r.adressesLien.map(\.description) == ["fe80::5a:d5f3:dc72:e7d6"])
    }

    @Test func routeurEtThread13() {
        let homepod = RouteurBordure(annonce: AnnonceService(instance: "HomePod Palier",
            txt: Self.txtRouteur(tv: "1.4.0", sb: [0, 0, 0x0C, 0xB1], pt: [0x73, 0x58, 0x6B, 0x68])), adresses: [])
        #expect(homepod.role == .routeur)
        #expect(homepod.etat?.bbrActif == true)
        #expect(homepod.etat?.bbrPrimaire == false)

        // Aqara HubM100 : Thread 1.3.0, bits de role a 0 : role inconnu, pas "detache".
        let aqara = RouteurBordure(annonce: AnnonceService(instance: "Aqara HubM100 #DFEB",
            txt: Self.txtRouteur(tv: "1.3.0", sb: [0, 0, 0x01, 0xB1], pt: [0xE2, 0xE7, 0x9F, 0xFC],
                                 omr: [0x40, 0xFD, 0x03, 0x54, 0xF0, 0x05, 0xDE, 0x00, 0x01])), adresses: [])
        #expect(aqara.role == nil)
        #expect(aqara.etat?.bbrPrimaire == true)
        #expect(aqara.partition == "E2E79FFC")
        #expect(aqara.prefixeOMR?.description == "fd03:54f0:5de:1::/64")

        let sansRien = RouteurBordure(annonce: AnnonceService(instance: "X"), adresses: [])
        #expect(sansRien.role == nil && sansRien.idReseau == nil && sansRien.partition == nil && sansRien.jeuActif == nil)
    }

    @Test func versions() {
        #expect(RouteurBordure.versionAuMoins("1.4.0", 1, 4))
        #expect(RouteurBordure.versionAuMoins("1.10", 1, 4))
        #expect(RouteurBordure.versionAuMoins("2.0", 1, 4))
        #expect(!RouteurBordure.versionAuMoins("1.3.0", 1, 4))
        #expect(!RouteurBordure.versionAuMoins("1", 1, 4))
        #expect(!RouteurBordure.versionAuMoins(nil, 1, 4))
    }

    @Test func instancesMatter() throws {
        let i = try #require(InstanceMatter(instance: "30fc8f95e0e1a385-00000000F89487F7"))
        #expect(i.fabrique == "30FC8F95E0E1A385")
        #expect(i.noeud == "00000000F89487F7")
        #expect(i.nom == "30FC8F95E0E1A385-00000000F89487F7")
        #expect(InstanceMatter(instance: "30FC8F95E0E1A385") == nil)
        #expect(InstanceMatter(instance: "30FC8F95E0E1A385-XYZ") == nil)
        #expect(InstanceMatter(instance: "30FC8F95E0E1A38Z-00000000F89487F7") == nil)
        #expect(InstanceMatter(instance: "A-B-C") == nil)
    }

    @Test func proprietesMatter() {
        #expect(ProprietesMatter(txt: ChampsTXT(["SII": Data("6000".utf8)])).endormi, "1E5019DAC2638F92, 28/09")
        #expect(ProprietesMatter(txt: ChampsTXT(["SII": Data("3500".utf8)])).endormi, "Nuki, sur pile, 28/09")
        #expect(ProprietesMatter(txt: ChampsTXT(["SII": Data("2800".utf8)])).endormi, "Zemismart, sur pile, 28/09")
        #expect(!ProprietesMatter(txt: ChampsTXT(["SII": Data("2000".utf8), "SAI": Data("2000".utf8)])).endormi,
                "pont Halo, alimente")
        #expect(!ProprietesMatter(txt: ChampsTXT(["SII": Data("300".utf8)])).endormi)
        #expect(ProprietesMatter(txt: ChampsTXT(["ICD": Data("0".utf8)])).endormi)
        #expect(!ProprietesMatter(txt: ChampsTXT()).endormi)
        #expect(ProprietesMatter(txt: ChampsTXT(["SAI": Data("800".utf8)])).sai == 800)
    }

    @Test func accessoireHAP() {
        let a = AccessoireHAP(annonce: AnnonceService(instance: "Eve Door 4A3B", hote: "Eve-Door-4A3B.local",
            txt: ChampsTXT(["md": Data("Eve Door".utf8), "ci": Data("10".utf8),
                            "id": Data("AA:BB:CC:DD:EE:FF".utf8), "sf": Data("0".utf8)])))
        #expect(a.nom == "Eve Door 4A3B")
        #expect(a.modele == "Eve Door")
        #expect(a.categorie == 10)
        #expect(a.identifiant == "AA:BB:CC:DD:EE:FF")
        #expect(a.appaire == true)
        #expect(AccessoireHAP(annonce: AnnonceService(instance: "Neuf", txt: ChampsTXT(["sf": Data("1".utf8)]))).appaire == false)
    }
}
