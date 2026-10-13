import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Diagnostic Thread : TLV des reponses")
struct DiagnosticThreadTests {
    /// Une TLV en octets : type, longueur sur un octet ; a partir de 255 octets, la longueur etendue
    /// d'OpenThread (0xFF, puis la vraie longueur sur 2 octets, grand-boutiste).
    static func tlv(_ type: UInt8, _ valeur: [UInt8]) -> [UInt8] {
        valeur.count < 0xFF ? [type, UInt8(valeur.count)] + valeur
                            : [type, 0xFF, UInt8(valeur.count >> 8), UInt8(valeur.count & 0xFF)] + valeur
    }

    /// Des TLV mises bout a bout, en hexa comme la sonde les transmet.
    static func hexa(_ tlv: [UInt8]...) -> String { Data(tlv.flatMap { $0 }).hexa }

    /// Valeur d'une TLV Route64 : sequence, masque des routeurs actifs (64 bits, le routeur 0 en tete), puis
    /// un octet par routeur, par identifiant croissant : qualite sortante (2 bits), entrante (2 bits), cout (4 bits).
    static func route64(sequence: UInt8 = 0, _ routes: [(id: Int, sortante: Int, entrante: Int, cout: Int)]) -> [UInt8] {
        let tries = routes.sorted { $0.id < $1.id }
        let masque = tries.reduce(UInt64(0)) { $0 | UInt64(1) << (63 - $1.id) }
        let octetsMasque = (0..<8).map { UInt8(truncatingIfNeeded: masque >> (56 - 8 * $0)) }
        return [sequence] + octetsMasque + tries.map { UInt8($0.sortante << 6 | $0.entrante << 4 | $0.cout) }
    }

    /// Une entree de Child Table, sur 3 octets : delai (5 bits), qualite (2 bits), numero (9 bits), mode.
    static func entreeEnfant(delai: Int, qualite: Int, id: Int, mode: UInt8) -> [UInt8] {
        let x = delai << 11 | qualite << 9 | id
        return [UInt8(x >> 8), UInt8(x & 0xFF), mode]
    }

    /// Routeur 5000 (EFR32) : identite, liens avec qualite et cout, enfants, adresses, version.
    @Test func routeurQuiRepond() throws {
        let r = try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(104)))
        #expect(r.extMac == "E000000000000002")
        #expect(r.rloc16 == 0x5000)
        let route = try #require(r.route64)
        #expect(route.sequence == 186)
        #expect(route.routeurs == [1, 20, 24, 43, 45, 51, 57])
        #expect(route.route(vers: 24) == RouteRouteur(idRouteur: 24, qualiteSortante: 3, qualiteEntrante: 3, cout: 1))
        #expect(route.route(vers: 51) == RouteRouteur(idRouteur: 51, qualiteSortante: 1, qualiteEntrante: 2, cout: 3))
        #expect(route.route(vers: 43)?.estVoisin == false, "pas voisin : joint par une route de cout 3")
        let enfants = try #require(r.enfants)
        try #require(enfants.map(\.idEnfant) == [4, 1])
        let premier = try #require(enfants.first)
        #expect(premier.qualite == 2)
        #expect(premier.delai == 256)
        #expect(premier.mode.endormi)
        #expect(premier.rloc16(parent: 0x5000) == 0x5004)
        #expect(r.adresses.map(\.description).contains("fd00:1111:2222:c87:0:ff:fe00:5000"), "son RLOC")
        #expect(r.version == 5, "Thread 1.4")
        #expect(r.chef == nil)
        #expect(r.mode == nil)
    }

    /// TLV fabricant : 25 a 27 presentes mais vides (nil), 28 remplie.
    @Test func fabricantVide() throws {
        let r = try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(105)))
        #expect(r.fabricant == nil)
        #expect(r.modele == nil)
        #expect(r.versionLogicielle == nil)
        #expect(r.pile == "SL-OPENTHREAD/2.5.1.0_GitHub-1fceb225b; EFR32; Sep 18 2024 19:39")
    }

    /// Chef (routeur 24) : Route64 et Leader Data.
    @Test func chef() throws {
        let r = try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(101)))
        #expect(r.chef == DonneesChef(partition: "46CBEBCD", poids: 64, version: 108, versionStable: 186, idChef: 24))
        #expect(r.route64?.routeurs.count == 7)
        #expect(r.extMac == nil)
    }

    /// Enfant endormi interroge a son RLOC (5004) : ExtMac, adresses, mode.
    @Test func enfant() throws {
        let r = try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(116)))
        #expect(r.extMac == "E000000000000004")
        let mode = try #require(r.mode)
        #expect(mode.endormi)
        #expect(!mode.appareilComplet)
        #expect(r.adresses.count == 4)
    }

    /// Reponse vide, hexa invalide, TLV tronquee ; chaine vide.
    @Test func casLimites() throws {
        let vide = try #require(ReponseDiagnostic(hexa: ""))
        #expect(vide.extMac == nil)
        #expect(vide.adresses.isEmpty)
        #expect(ReponseDiagnostic(hexa: "0G") == nil)
        #expect(ReponseDiagnostic(hexa: "0008AABB") == nil, "longueur annoncee 8, 2 octets presents")
        let fabricantVide = try #require(ReponseDiagnostic(hexa: "1900"), "TLV vide : la reponse existe")
        #expect(fabricantVide.fabricant == nil)
        #expect(ReponseDiagnostic(hexa: "1A03457665")?.modele == "Eve")
    }

    /// Queue trop courte pour etre une TLV : un octet seul apres la derniere TLV (ou seul), ou un
    /// en-tete sans sa valeur.
    @Test func queueDUnOctet() throws {
        #expect(ReponseDiagnostic(hexa: "00") == nil, "un octet seul : pas meme un en-tete")
        #expect(ReponseDiagnostic(hexa: "190000") == nil, "un octet apres une TLV entiere")
        #expect(ReponseDiagnostic(hexa: "0008") == nil, "en-tete entier, valeur de 8 octets absente")
        let entiere = try #require(ReponseDiagnostic(hexa: "1A03457665"), "sans queue : lue")
        #expect(entiere.modele == "Eve")
        #expect(ReponseDiagnostic(hexa: "1A0345766500") == nil, "la meme, avec un octet de trop")
    }

    /// Masques du mode : R (0x08) recepteur actif, D (0x02) appareil complet, N (0x01) donnees completes.
    /// Le bit 0x04 est reserve et les bits hauts ne comptent pas. Endormi : pas de R.
    @Test func masquesDuMode() throws {
        let cas: [(brut: UInt8, actif: Bool, complet: Bool, donnees: Bool)] = [
            (0x00, false, false, false), (0x01, false, false, true), (0x02, false, true, false),
            (0x04, false, false, false), (0x08, true, false, false), (0x0A, true, true, false),
            (0x0B, true, true, true), (0x0F, true, true, true), (0xF0, false, false, false), (0xF4, false, false, false),
        ]
        for c in cas {
            let m = ModeThread(brut: c.brut)
            #expect(m.recepteurActif == c.actif, "R de \(c.brut)")
            #expect(m.endormi == !c.actif, "endormi de \(c.brut)")
            #expect(m.appareilComplet == c.complet, "D de \(c.brut)")
            #expect(m.donneesCompletes == c.donnees, "N de \(c.brut)")
            // Par la TLV Mode (2) : un octet, sinon ignoree.
            let r = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.mode, [c.brut]))))
            #expect(r.mode == m, "TLV Mode de \(c.brut)")
        }
        let deux = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.mode, [0x08, 0x08]))))
        #expect(deux.mode == nil, "deux octets : ce n'est pas un mode")
    }

    /// Route64 trop courte : moins de 9 octets (sequence, puis masque de 8), ou moins d'octets de routes que
    /// le masque n'annonce de routeurs. La TLV est ignoree, sans perdre celles qui suivent.
    @Test func route64Courte() throws {
        let extMac = Self.tlv(TypeTLV.extMac, [0xE0, 0, 0, 0, 0, 0, 0, 0x02])
        func lire(_ valeur: [UInt8]) throws -> ReponseDiagnostic {
            try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.route64, valeur), extMac)))
        }
        let sansMasque = try lire([0x07, 0, 0, 0, 0, 0, 0, 0])
        #expect(sansMasque.route64 == nil, "8 octets : le masque est coupe")
        #expect(sansMasque.extMac == "E000000000000002", "la TLV suivante est lue")
        let vide = try lire([0x07, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(vide.route64 == Route64(sequence: 7, routes: []), "9 octets : aucun routeur, c'est valable")

        let trois = Self.route64([(1, 3, 3, 1), (20, 2, 1, 3), (24, 1, 2, 2)])
        let entiere = try #require(try lire(trois).route64)
        #expect(entiere.routeurs == [1, 20, 24])
        #expect(entiere.route(vers: 20) == RouteRouteur(idRouteur: 20, qualiteSortante: 2, qualiteEntrante: 1, cout: 3))
        #expect(try lire(Array(trois.dropLast())).route64 == nil, "le masque annonce 3 routeurs, 2 octets de routes")
        #expect(try lire(Array(trois.dropLast())).extMac == "E000000000000002")
    }

    /// Child Table dont la longueur n'est pas un multiple de 3 : les entrees entieres sont lues, le reste
    /// est ignore ; vide ou plus courte qu'une entree, la liste est vide (et non absente).
    @Test func tableEnfantsIncomplete() throws {
        let a = Self.entreeEnfant(delai: 8, qualite: 2, id: 4, mode: 0x08)
        let b = Self.entreeEnfant(delai: 10, qualite: 1, id: 7, mode: 0x0B)
        let cas: [(octets: [UInt8], ids: [Int])] = [
            ([], []), ([0x40], []), ([0x40, 0x04], []), (a, [4]), (a + [0x40], [4]), (a + [0x40, 0x07], [4]),
            (a + b, [4, 7]), (a + b + [0x99], [4, 7]),
        ]
        for c in cas {
            let r = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.tableEnfants, c.octets))))
            #expect(r.enfants?.map(\.idEnfant) == c.ids, "\(c.octets.count) octets")
        }
        let r = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.tableEnfants, a + b + [0x99]))))
        #expect(r.enfants?.last == EntreeEnfant(idEnfant: 7, qualite: 1, delai: 64, mode: ModeThread(brut: 0x0B)))
    }

    /// Delai d'un enfant : 2^(t - 4) secondes, t sur 5 bits. Sous t = 4, moins d'une seconde : 0. Les champs
    /// voisins (qualite sur 2 bits, numero sur 9) ne debordent pas.
    @Test func delaiDUnEnfant() throws {
        for (t, delai) in [(0, 0), (3, 0), (4, 1), (5, 2), (8, 16), (31, 1 << 27)] {
            let octets = Self.tlv(TypeTLV.tableEnfants, Self.entreeEnfant(delai: t, qualite: 3, id: 0x1FF, mode: 0x08))
            let r = try #require(ReponseDiagnostic(hexa: Self.hexa(octets)))
            let e = try #require(r.enfants?.first, "t = \(t)")
            #expect(e == EntreeEnfant(idEnfant: 0x1FF, qualite: 3, delai: delai, mode: ModeThread(brut: 0x08)), "t = \(t)")
        }
    }

    // TLV a longueur etendue : OpenThread ecrit 0xFF a la place de la longueur quand la valeur depasse
    // 254 octets (une liste de 16 adresses ou plus, par exemple), puis la vraie longueur sur 2 octets.

    /// Seize adresses et plus : la TLV etendue est lue en entier, et les TLV qui la suivent aussi.
    @Test func longueurEtendue() throws {
        let adresses = (0..<17).flatMap { k -> [UInt8] in
            [0xFD, 0x00, 0x11, 0x11, 0x22, 0x22, 0x0C, 0x87, 0x00, 0x00, 0x00, 0xFF, 0xFE, 0x00, 0x00, UInt8(k)]
        }
        #expect(adresses.count == 272, "17 adresses de 16 octets : plus de 254")
        let hexa = Self.hexa(Self.tlv(TypeTLV.extMac, [0xE0, 0, 0, 0, 0, 0, 0, 0x02]),
                             Self.tlv(TypeTLV.adresses, adresses),
                             Self.tlv(TypeTLV.address16, [0x50, 0x00]))
        let r = try #require(ReponseDiagnostic(hexa: hexa))
        #expect(r.adresses.count == 17)
        #expect(r.adresses.first?.description == "fd00:1111:2222:c87:0:ff:fe00:0")
        #expect(r.adresses.last?.description == "fd00:1111:2222:c87:0:ff:fe00:10")
        #expect(r.extMac == "E000000000000002", "la TLV d'avant")
        #expect(r.rloc16 == 0x5000, "la TLV d'apres")
    }

    /// Frontiere : 254 octets tiennent sur un octet de longueur ; 255 et plus passent en longueur etendue.
    @Test func frontiereDeLaLongueurEtendue() throws {
        for n in [253, 254, 255, 256, 1000] {
            let texte = String(repeating: "x", count: n)
            let octets = Self.tlv(TypeTLV.pile, Array(texte.utf8))
            #expect((octets[1] == 0xFF) == (n >= 255), "\(n) octets")
            let r = try #require(ReponseDiagnostic(hexa: Self.hexa(octets)), "\(n) octets")
            #expect(r.pile == texte, "\(n) octets")
        }
    }

    /// En-tete etendu ou valeur etendue coupes : nil, comme une TLV ordinaire tronquee.
    @Test func longueurEtendueTronquee() {
        #expect(ReponseDiagnostic(hexa: "08FF") == nil, "longueur etendue absente")
        #expect(ReponseDiagnostic(hexa: "08FF01") == nil, "un seul des deux octets de longueur")
        #expect(ReponseDiagnostic(hexa: "08FF0110") == nil, "272 octets annonces, aucun present")
        let complete = Self.tlv(TypeTLV.adresses, [UInt8](repeating: 0x01, count: 272))
        #expect(ReponseDiagnostic(hexa: Self.hexa(complete)) != nil)
        #expect(ReponseDiagnostic(hexa: Self.hexa(Array(complete.dropLast()))) == nil, "un octet de moins")
        #expect(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.extMac, [0xE0, 0, 0, 0, 0, 0, 0, 0x02]),
                                                  Array(complete.dropLast()))) == nil, "coupee apres une TLV entiere")
    }

    /// TLV 9, compteurs MAC (spec de la sonde tout-en-un, section 2.3) : neuf compteurs de 32 bits,
    /// gros-boutistes, dans l'ordre de la spec Thread. Un appareil endormi la rend (pas la TLV 4). Une autre
    /// longueur : ignoree (valeurs inventees).
    @Test func compteursMac() throws {
        let valeurs: [UInt32] = [1, 2, 37, 0x01020304, 5, 6, 4321, 8, 0xFFFFFFFF]
        let octets = valeurs.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)) } }
        let r = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.compteursMac, octets))))
        let c = try #require(r.compteursMac)
        #expect(c == CompteursMac(protocolesInconnus: 1, erreursRecues: 2, erreursEmises: 37,
                                  unicastRecus: 0x01020304, diffusionsRecues: 5, rejetsRecus: 6, unicastEmis: 4321,
                                  diffusionsEmises: 8, rejetsEmis: 0xFFFFFFFF))
        let courte = try #require(ReponseDiagnostic(hexa: Self.hexa(Self.tlv(TypeTLV.compteursMac, Array(octets.dropLast())))))
        #expect(courte.compteursMac == nil, "35 octets")
        #expect(TypeTLV.compteursMac == 9)
    }
}
