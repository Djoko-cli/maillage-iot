import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

@Suite("Maillage : construction depuis les reponses d'une tournee")
struct MaillageTests {
    static func reponse(_ id: Int) throws -> ReponseDiagnostic {
        try #require(ReponseDiagnostic(hexa: try CaptureSonde.tlv(id)))
    }

    /// Tournee de la capture : Route64 du chef (6000), 5000 et 6000 qui repondent,
    /// les 5 routeurs de bordure muets, Network Data, enfants resolus sous AC00, la sonde.
    static func tournee() throws -> Maillage {
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.routeurs(try #require(try reponse(204).route64), chef: 24)
        c.reponse(try reponse(104), routeur: 20)
        c.pile(try reponse(105).pile, routeur: 20)
        c.reponse(try reponse(106), routeur: 24)
        c.pile(try reponse(107).pile, routeur: 24)
        for id in [1, 43, 45, 51, 57] { c.muet(id) }
        let brutes = try #require(try reponse(206).donneesReseau)
        c.reseau(try #require(DonneesReseau(brutes)))
        for id in 503...508 {
            let r = try reponse(id)
            c.enfant(EnfantMaillage(rloc16: try #require(r.rloc16), extMac: r.extMac, endormi: r.mode?.endormi,
                                    source: .resolution))
        }
        c.enfant(EnfantMaillage(rloc16: 0xAC09, qualite: 3, source: .sonde))
        c.identite("E000000000000007", routeur: 43)
        c.identite("FFFFFFFFFFFFFFFF", routeur: 20)
        return c.maillage()
    }

    /// Routeurs : chef, bordures (Network Data), BBR principal, muets, identite de ceux qui repondent.
    @Test func routeurs() throws {
        let m = try Self.tournee()
        #expect(m.routeurs.map(\.id) == [1, 20, 24, 43, 45, 51, 57])
        #expect(m.chef?.id == 24)
        #expect(m.routeurs.filter(\.bordure).map(\.id) == [1, 43, 45, 51, 57])
        #expect(m.routeurs.filter(\.bbrPrincipal).map(\.id) == [45])
        #expect(m.routeurs.filter(\.muet).map(\.id) == [1, 43, 45, 51, 57])
        let r = try #require(m.routeur(20))
        #expect(r.extMac == "E000000000000002", "sa propre reponse passe avant une identite apprise")
        #expect(r.version == 5)
        #expect(r.pile?.hasPrefix("SL-OPENTHREAD/2.5.1.0") == true)
        #expect(m.routeur(24)?.extMac == "E000000000000003")
        #expect(m.routeur(43)?.extMac == "E000000000000007", "muet : ExtMac apprise (parent de la sonde)")
        #expect(r.rloc16 == 0x5000)
    }

    /// Liens entre voisins seulement, vus par 5000 et 6000, qualite dans chaque sens.
    @Test func liens() throws {
        let m = try Self.tournee()
        #expect(m.liens.map { [$0.a, $0.b] } == [[1, 20], [1, 24], [20, 24], [20, 45], [20, 51], [24, 45], [24, 51]])
        let l = try #require(m.liens.first { $0.a == 20 && $0.b == 51 })
        #expect(l.qualiteAB == 1, "de 20 vers 51")
        #expect(l.qualiteBA == 2, "de 51 vers 20")
        #expect(l.qualite == 1)
        #expect(m.liens.first { $0.a == 20 && $0.b == 24 }?.qualite == 3)
        #expect(m.liens(de: 45).count == 2, "muet : ses liens viennent des autres")
    }

    /// Reponse d'un routeur qui ne donne que sa Route64 : pour chaque voisin, la qualite sortante (du routeur
    /// qui repond vers lui) et la qualite entrante.
    static func reponseVoisins(_ voisins: (id: Int, sortante: Int, entrante: Int)...) throws -> ReponseDiagnostic {
        let routes = voisins.map { (id: $0.id, sortante: $0.sortante, entrante: $0.entrante, cout: 1) }
        let tlv = DiagnosticThreadTests.tlv(TypeTLV.route64, DiagnosticThreadTests.route64(routes))
        return try #require(ReponseDiagnostic(hexa: DiagnosticThreadTests.hexa(tlv)))
    }

    /// Lien lu aux deux bouts. La regle : chaque bout donne les deux sens, et le dernier rapport remplace les
    /// deux sens du precedent (ni moyenne, ni meilleure, ni pire valeur). La tournee applique les reponses par
    /// identifiant croissant : quand les deux bouts repondent, celui de plus grand identifiant decide. Lu par un
    /// seul bout, le lien garde ses deux sens, ranges de `a` vers `b` : par le plus petit identifiant tel quel,
    /// par le plus grand a l'envers (les deux branches de `lien`).
    @Test func lienLuAuxDeuxBouts() throws {
        func lu(_ reponses: [(ReponseDiagnostic, Int)]) throws -> LienRadio {
            var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
            for (r, id) in reponses { c.reponse(r, routeur: id) }
            let liens = c.maillage().liens
            try #require(liens.count == 1)
            return liens[0]
        }
        // 2 voit 5 : de 2 vers 5 en 3, de 5 vers 2 en 1. 5 voit 2 : de 5 vers 2 en 3, de 2 vers 5 en 2.
        let de2 = try Self.reponseVoisins((id: 5, sortante: 3, entrante: 1))
        let de5 = try Self.reponseVoisins((id: 2, sortante: 3, entrante: 2))

        let parLePlusPetit = try lu([(de2, 2)])
        #expect((parLePlusPetit.a, parLePlusPetit.b) == (2, 5))
        #expect(parLePlusPetit.qualiteAB == 3 && parLePlusPetit.qualiteBA == 1, "sortante de 2 : de a vers b")
        let parLePlusGrand = try lu([(de5, 5)])
        #expect((parLePlusGrand.a, parLePlusGrand.b) == (2, 5))
        #expect(parLePlusGrand.qualiteAB == 2 && parLePlusGrand.qualiteBA == 3, "sortante de 5 : de b vers a, donc a l'envers")

        let plusGrandEnDernier = try lu([(de2, 2), (de5, 5)])
        #expect(plusGrandEnDernier.qualiteAB == 2 && plusGrandEnDernier.qualiteBA == 3, "5 remplace les deux sens de 2")
        #expect(plusGrandEnDernier.qualite == 2)
        let plusPetitEnDernier = try lu([(de5, 5), (de2, 2)])
        #expect(plusPetitEnDernier.qualiteAB == 3 && plusPetitEnDernier.qualiteBA == 1, "2 remplace les deux sens de 5")
        #expect(plusPetitEnDernier.qualite == 1)
    }

    /// Enfants : tables de 5000 et 6000, enfants resolus sous AC00, la sonde.
    @Test func enfants() throws {
        let m = try Self.tournee()
        #expect(m.enfants.count == 13)
        let de20 = m.enfants(de: 20)
        #expect(de20.map(\.rloc16) == [0x5001, 0x5004])
        #expect(de20.allSatisfy { $0.source == .tableEnfants && $0.qualite != nil && $0.endormi == true })
        let de43 = m.enfants(de: 43)
        #expect(de43.map(\.rloc16) == [0xAC03, 0xAC04, 0xAC05, 0xAC06, 0xAC07, 0xAC08, 0xAC09])
        let ac04 = try #require(de43.first { $0.rloc16 == 0xAC04 })
        #expect(ac04.extMac == "E00000000000000A")
        #expect(ac04.qualite == nil, "sous un routeur muet")
        #expect(ac04.source == .resolution)
        #expect(de43.last?.source == .sonde)
        #expect(m.enfants(de: 24).count == 4)
    }

    /// Un enfant vu dans une table puis interroge : l'identite complete l'entree.
    @Test func fusion() throws {
        var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        c.reponse(try Self.reponse(104), routeur: 20)
        #expect(c.enfantsSansIdentite == [0x5001, 0x5004])
        let adresse = try #require(AdresseIPv6("fd00:5555:6666:0:a00::7"))
        c.enfant(EnfantMaillage(rloc16: 0x5004, extMac: "E000000000000004", endormi: true, adresses: [adresse],
                                source: .resolution))
        #expect(c.enfantsSansIdentite == [0x5001])
        let e = try #require(c.maillage().enfants.first { $0.rloc16 == 0x5004 })
        #expect(e.extMac == "E000000000000004")
        #expect(e.adresses == [adresse])
        #expect(e.qualite == 2, "qualite de la table gardee")
        #expect(e.source == .tableEnfants)
    }

    /// Enfant vu par deux sources aux valeurs en conflit : champ par champ, la premiere valeur connue est
    /// gardee, et la seconde ne sert qu'a combler ce qui manque (adresses : les premieres, si elles ne sont pas
    /// vides). La source reste celle de la premiere.
    @Test func fusionEnConflit() throws {
        let a1 = try #require(AdresseIPv6("fd00:5555:6666:0:a00::1"))
        let a2 = try #require(AdresseIPv6("fd00:5555:6666:0:a00::2"))
        let table = EnfantMaillage(rloc16: 0x5004, qualite: 2, delai: 256, endormi: true, source: .tableEnfants)
        let resolu = EnfantMaillage(rloc16: 0x5004, extMac: "E0000000000000AA", qualite: 1, delai: 30, endormi: false,
                                    adresses: [a1], source: .resolution)
        let autre = EnfantMaillage(rloc16: 0x5004, extMac: "E0000000000000BB", qualite: 3, delai: 60, endormi: true,
                                   adresses: [a2], source: .resolution)
        func fusion(_ premier: EnfantMaillage, _ second: EnfantMaillage) throws -> EnfantMaillage {
            var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
            c.enfant(premier)
            c.enfant(second)
            let enfants = c.maillage().enfants
            try #require(enfants.count == 1, "un seul RLOC16, une seule entree")
            return enfants[0]
        }
        // Table d'abord, incomplete : ses valeurs restent, la resolution comble l'ExtMac et les adresses.
        #expect(try fusion(table, resolu) == EnfantMaillage(rloc16: 0x5004, extMac: "E0000000000000AA", qualite: 2,
                                                              delai: 256, endormi: true, adresses: [a1],
                                                              source: .tableEnfants))
        // Resolution d'abord, complete : rien n'est remplace, ni par la table, ni par sa source.
        #expect(try fusion(resolu, table) == resolu)
        // Deux entrees completes : la premiere gagne partout.
        #expect(try fusion(resolu, autre) == resolu)
        #expect(try fusion(autre, resolu) == autre)
    }

    /// Promotion `.sonde` : une entree connue devient celle de la sonde quand la sonde la donne, dans les deux
    /// ordres, et `.sonde` n'est jamais repris par une autre source. Les valeurs restent celles du premier
    /// arrive. La sonde n'est pas a identifier (`enfantsSansIdentite`), meme sans ExtMac.
    @Test func promotionSonde() throws {
        let table = EnfantMaillage(rloc16: 0x5004, qualite: 2, delai: 256, endormi: true, source: .tableEnfants)
        let sonde = EnfantMaillage(rloc16: 0x5004, extMac: "E000000000000004", qualite: 3, source: .sonde)
        var apres = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        apres.enfant(table)
        apres.enfant(sonde)
        let promue = try #require(apres.maillage().enfants.first)
        #expect(promue == EnfantMaillage(rloc16: 0x5004, extMac: "E000000000000004", qualite: 2, delai: 256, endormi: true,
                                         source: .sonde), "table d'abord : promue, valeurs de la table, ExtMac de la sonde")
        var avant = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        avant.enfant(sonde)
        avant.enfant(table)
        let gardee = try #require(avant.maillage().enfants.first)
        #expect(gardee == EnfantMaillage(rloc16: 0x5004, extMac: "E000000000000004", qualite: 3, delai: 256, endormi: true,
                                         source: .sonde), "sonde d'abord : reste la sonde, completee par la table")
        // Sans ExtMac, la sonde n'est pas a identifier ; une entree de table, si.
        var sansExtMac = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        sansExtMac.enfant(EnfantMaillage(rloc16: 0x5004, source: .sonde))
        sansExtMac.enfant(EnfantMaillage(rloc16: 0x5001, source: .tableEnfants))
        #expect(sansExtMac.enfantsSansIdentite == [0x5001])
    }

    /// Sonde posee avant la ligne de sa table, comme la tournee le fait (l'enfant de la sonde est pose avec
    /// `etat`, avant toute reponse) : la ligne de la table de son parent, qui arrive ensuite, complete l'entree
    /// sans la reprendre.
    @Test func sondeAvantSaLigneDeTable() throws {
        var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        c.enfant(EnfantMaillage(rloc16: 0x5004, qualite: 3, source: .sonde))
        c.reponse(try Self.reponse(104), routeur: 20)
        let enfants = c.maillage().enfants
        #expect(enfants.map(\.rloc16) == [0x5001, 0x5004], "la table de 5000 donne 5004 et 5001")
        let sonde = try #require(enfants.first { $0.rloc16 == 0x5004 })
        #expect(sonde.source == .sonde)
        #expect(sonde.qualite == 3, "la sienne, posee la premiere")
        #expect(sonde.delai == 256 && sonde.endormi == true, "completee par sa ligne de table")
        #expect(try #require(enfants.first { $0.rloc16 == 0x5001 }).source == .tableEnfants)
        #expect(c.enfantsSansIdentite == [0x5001], "la sonde n'est pas a identifier")
    }

    /// Reponse et identite : l'ExtMac que le routeur donne lui-meme passe avant une identite apprise ailleurs, que
    /// celle-ci vienne avant ou apres ; une reponse sans ExtMac garde l'identite apprise.
    @Test func reponseAvantIdentite() throws {
        var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        c.identite("E0000000000000AA", routeur: 20)
        #expect(c.maillage().routeur(20)?.extMac == "E0000000000000AA", "sans reponse : l'identite apprise")
        c.reponse(try Self.reponse(104), routeur: 20)
        #expect(c.maillage().routeur(20)?.extMac == "E000000000000002", "sa reponse, arrivee apres l'identite")
        c.identite("E0000000000000BB", routeur: 20)
        #expect(c.maillage().routeur(20)?.extMac == "E000000000000002", "une identite apprise ensuite ne la remplace pas")
        // La reponse du chef n'a pas d'ExtMac : l'identite apprise reste.
        #expect(try Self.reponse(101).extMac == nil)
        c.identite("E0000000000000CC", routeur: 24)
        c.reponse(try Self.reponse(101), routeur: 24)
        #expect(c.maillage().routeur(24)?.extMac == "E0000000000000CC")
    }

    /// Un routeur marque muet qui repond ensuite n'est plus muet ; marque muet apres sa reponse, il l'est.
    @Test func muetRemisAFaux() throws {
        var c = ConstructionMaillage(date: .now, partition: "46CBEBCD")
        c.muet(20)
        #expect(c.maillage().routeur(20)?.muet == true)
        c.reponse(try Self.reponse(104), routeur: 20)
        #expect(c.maillage().routeur(20)?.muet == false, "il a repondu")
        c.muet(20)
        #expect(c.maillage().routeur(20)?.muet == true, "muet apres sa reponse")
        #expect(c.maillage().routeur(24)?.muet == false, "cite par la Route64 de 20, sans avoir ete marque")
    }

    // BBR principal, comme OpenThread : le chef s'il est parmi les serveurs BBR, meme avec une sequence
    // plus basse ; sinon le premier de `bbr`. Network Data construites a la main : un Service BBR et
    // deux Server (stable) de 9 octets = RLOC16 (2), sequence (1), reenregistrement 5 s, delai MLR 3600 s.

    /// B400 (sequence 0x57) puis 6000, le chef (sequence 0x10), dans l'ordre du document.
    static let bbrB400Puis6000: [UInt8] = [
        0x0B, 25,                                  // Service (stable), 25 octets
        0x80,                                      // T = 1 (numero d'entreprise Thread omis), identifiant 0
        1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
        0x0D, 9, 0xB4, 0x00,                       // Server (stable), 9 octets : RLOC16 B400
        0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x57, delais
        0x0D, 9, 0x60, 0x00,                       // Server (stable), 9 octets : RLOC16 6000
        0x10, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x10, memes delais
    ]

    /// E400 (sequence 0x10) puis B400 (sequence 0x57), dans l'ordre du document.
    static let bbrE400PuisB400: [UInt8] = [
        0x0B, 25,                                  // Service (stable), 25 octets
        0x80,                                      // T = 1 (numero d'entreprise Thread omis), identifiant 0
        1, 0x01,                                   // donnees de service : 1 octet, 01 (BBR)
        0x0D, 9, 0xE4, 0x00,                       // Server (stable), 9 octets : RLOC16 E400
        0x10, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x10, delais
        0x0D, 9, 0xB4, 0x00,                       // Server (stable), 9 octets : RLOC16 B400
        0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,  //   sequence 0x57, memes delais
    ]

    /// Le chef (6000, routeur 24) est BBR avec une sequence plus basse que B400 (routeur 45) : c'est lui le principal.
    @Test func bbrPrincipalChef() throws {
        let d = try #require(DonneesReseau(Self.bbrB400Puis6000))
        #expect(d.bbr == [0xB400, 0x6000], "le chef n'est pas en tete de `bbr`")
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.routeurs(try #require(try Self.reponse(204).route64), chef: 24)
        c.reseau(d)
        let m = c.maillage()
        #expect(m.routeurs.filter(\.bbrPrincipal).map(\.id) == [24])
        #expect(m.routeur(45)?.bbrPrincipal == false)
    }

    /// Le chef (6000) n'est pas parmi les serveurs BBR : le principal est le premier de `bbr`, B400.
    @Test func bbrPrincipalSansLeChef() throws {
        let d = try #require(DonneesReseau(Self.bbrE400PuisB400))
        #expect(d.bbr == [0xB400, 0xE400])
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.routeurs(try #require(try Self.reponse(204).route64), chef: 24)
        c.reseau(d)
        let m = c.maillage()
        #expect(m.routeurs.filter(\.bbrPrincipal).map(\.id) == [45])
        #expect(m.routeur(57)?.bbrPrincipal == false)
    }

    /// Network Data d'une tournee precedente (`seulementConnus`) : pour les seuls routeurs de la
    /// liste ; un routeur qui n'y est plus n'est pas rajoute, et un serveur BBR qui n'y est plus ne
    /// compte pas (le principal est alors le premier des autres). Lues a la tournee, elles
    /// rajoutent le routeur, comme avant.
    @Test func reseauPrecedent() throws {
        // Prefix ::/0 : Has Route 5C00 (routeur 23, absent de la Route64) ; service BBR : 5C00
        // (sequence 0x60) puis B400 (sequence 0x57).
        let route: [UInt8] = [0x03, 7, 0x00, 0, 0x00, 3, 0x5C, 0x00, 0x00]
        let bbr: [UInt8] = [0x0B, 25, 0x80, 1, 0x01,
                            0x0D, 9, 0x5C, 0x00, 0x60, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10,
                            0x0D, 9, 0xB4, 0x00, 0x57, 0x00, 0x05, 0x00, 0x00, 0x0E, 0x10]
        let d = try #require(DonneesReseau(route + bbr))
        #expect(d.routeursDeBordure == [0x5C00] && d.bbr == [0x5C00, 0xB400])
        let route64 = try #require(try Self.reponse(204).route64)
        var precedent = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        precedent.routeurs(route64, chef: 24)
        precedent.reseau(d, seulementConnus: true)
        let m = precedent.maillage()
        #expect(m.routeur(23) == nil)
        #expect(m.routeurs.filter(\.bbrPrincipal).map(\.id) == [45])
        var lues = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        lues.routeurs(route64, chef: 24)
        lues.reseau(d)
        #expect(lues.maillage().routeur(23)?.bordure == true)
        #expect(lues.maillage().routeurs.filter(\.bbrPrincipal).map(\.id) == [23])
    }

    /// Chef pas encore connu (`routeurs(_:chef:)` pas encore appele) : le premier de `bbr`.
    @Test func bbrPrincipalChefInconnu() throws {
        let d = try #require(DonneesReseau(Self.bbrE400PuisB400))
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.reseau(d)
        #expect(c.maillage().routeurs.filter(\.bbrPrincipal).map(\.id) == [45])
    }

    // MARK: Sonde tout-en-un (spec du 07/10, sections 2.1 a 2.3)

    static let debut = Date(timeIntervalSince1970: 1_790_000_000)

    /// Route64 d'une annonce entendue : pour chaque voisin, les qualites sortante et entrante (valeurs inventees).
    static func route64(_ voisins: (id: Int, sortante: Int, entrante: Int)...) -> Route64 {
        Route64(sequence: 1, routes: voisins.map {
            RouteRouteur(idRouteur: $0.id, qualiteSortante: $0.sortante, qualiteEntrante: $0.entrante, cout: 1)
        })
    }

    /// Construction aux routeurs 1, 2, 3 et 5 (le chef : 1).
    static func quatreRouteurs() -> ConstructionMaillage {
        var c = ConstructionMaillage(date: Self.debut, partition: "1234ABCD")
        c.routeurs(Self.route64((1, 0, 0), (2, 0, 0), (3, 0, 0), (5, 0, 0)), chef: 1)
        return c
    }

    /// Fusion du diagnostic et de l'ecoute : chaque sens prend la mesure la plus recente. Le diagnostic est date du
    /// debut de la tournee, l'ecoute de l'age de l'annonce : a date egale, le diagnostic l'emporte. Un lien connu
    /// d'un seul cote (la Route64 d'une annonce) a ses deux sens.
    @Test func fusionDiagnosticEtEcoute() throws {
        var c = Self.quatreRouteurs()
        // 2 repond au diagnostic : 2 -> 3 en 3, 3 -> 2 en 2.
        c.reponse(try Self.reponseVoisins((id: 3, sortante: 3, entrante: 2)), routeur: 2)
        // 3 entendu il y a 2 min : 3 -> 2 en 1, 2 -> 3 en 1 ; et 3 -> 5 en 2, 5 -> 3 en 3 (5 ne repond pas).
        c.ecoute(Self.route64((2, 1, 1), (3, 0, 0), (5, 2, 3)), routeur: 3, date: Self.debut - 120)
        // 2 repond aussi pour le lien 1-2.
        c.reponse(try Self.reponseVoisins((id: 1, sortante: 3, entrante: 3), (id: 3, sortante: 3, entrante: 2)), routeur: 2)
        // 1 entendu a l'instant (age 0) : 1 -> 2 en 2, 2 -> 1 en 1 ; la reponse du diagnostic (3,3) est plus recente (meme date, mais diagnostic).
        c.ecoute(Self.route64((2, 2, 1)), routeur: 1, date: Self.debut)
        let m = c.maillage()
        let l23 = try #require(m.liens.first { $0.a == 2 && $0.b == 3 })
        #expect(l23.qualiteAB == 3 && l23.qualiteBA == 2, "le diagnostic, plus recent, dans les deux sens")
        #expect(l23.sourceAB == .diagnostic && l23.sourceBA == .diagnostic)
        #expect(l23.dateAB == Self.debut && l23.dateBA == Self.debut)
        let l35 = try #require(m.liens.first { $0.a == 3 && $0.b == 5 })
        #expect(l35.qualiteAB == 2 && l35.qualiteBA == 3, "connu de 3 seul : les deux sens, de l'annonce")
        #expect(l35.sourceAB == .ecoute && l35.sourceBA == .ecoute && l35.dateAB == Self.debut - 120)
        let l12 = try #require(m.liens.first { $0.a == 1 && $0.b == 2 })
        #expect(l12.qualiteAB == 3 && l12.qualiteBA == 3 && l12.sourceAB == .diagnostic, "a date egale, le diagnostic")
        #expect(m.routeur(3)?.entendu == Self.debut - 120 && m.routeur(1)?.entendu == Self.debut)
        #expect(m.routeur(2)?.entendu == nil && m.routeur(5)?.entendu == nil)
        #expect(l35.sansDates.dateAB == nil && l35.sansDates.sourceAB == .ecoute, "l'historique garde la source, pas la date")
    }

    /// Deux annonces pour la meme paire : chaque sens prend la plus recente ; une annonce plus ancienne arrivee
    /// ensuite ne change rien. Une entree sans qualite (pas voisins) ne remplace rien.
    @Test func ecouteLaPlusRecente() throws {
        var c = Self.quatreRouteurs()
        c.ecoute(Self.route64((5, 3, 2)), routeur: 3, date: Self.debut - 60)
        c.ecoute(Self.route64((3, 1, 1)), routeur: 5, date: Self.debut - 30)
        c.ecoute(Self.route64((5, 2, 2)), routeur: 3, date: Self.debut - 600)
        c.ecoute(Self.route64((5, 0, 0)), routeur: 2, date: Self.debut)
        let m = c.maillage()
        #expect(m.liens.count == 1)
        let l = try #require(m.liens.first)
        #expect((l.a, l.b) == (3, 5) && l.qualiteAB == 1 && l.qualiteBA == 1, "celle de 5, il y a 30 s")
        #expect(l.dateAB == Self.debut - 30 && l.dateBA == Self.debut - 30)
        #expect(m.routeur(3)?.entendu == Self.debut - 60, "l'annonce la plus recente de 3")
        #expect(m.routeur(2)?.entendu == Self.debut, "entendu, meme sans lien")
    }

    /// L'ecoute ne cree ni routeur ni lien hors de la liste des routeurs : une annonce d'un routeur absent est
    /// ecartee, un voisin absent aussi. Une annonce sans Route64 rend le routeur entendu, sans lien.
    @Test func ecouteDansLaListeSeulement() throws {
        var c = Self.quatreRouteurs()
        c.ecoute(Self.route64((1, 3, 3)), routeur: 9, date: Self.debut)
        c.ecoute(Self.route64((9, 3, 3), (1, 2, 2)), routeur: 2, date: Self.debut)
        c.ecoute(nil, routeur: 5, date: Self.debut - 5)
        let m = c.maillage()
        #expect(m.routeurs.map(\.id) == [1, 2, 3, 5])
        #expect(m.liens.map { [$0.a, $0.b] } == [[1, 2]])
        #expect(m.routeur(5)?.entendu == Self.debut - 5)
    }

    /// Couverture de l'ecoute (Reglages › Sonde) : routeurs entendus sur les routeurs de la partition, si la sonde
    /// a rendu ses annonces ; sinon (firmware 1.0.3, sonde muette) inconnue.
    @Test func couverture() {
        var c = Self.quatreRouteurs()
        c.ecoute(nil, routeur: 2, date: Self.debut)
        c.ecoute(Self.route64((1, 3, 3)), routeur: 3, date: Self.debut)
        #expect(c.maillage().couverture == nil, "annonces non lues")
        c.annoncesRecues()
        #expect(c.maillage().couverture == CouvertureEcoute(entendus: 2, routeurs: 4))
        #expect(c.maillage().annoncesLues)
        var vide = Self.quatreRouteurs()
        vide.annoncesRecues()
        #expect(vide.maillage().couverture == CouvertureEcoute(entendus: 0, routeurs: 4))
    }

    /// Enfant resolu sous un routeur qui repond par son propre RLOC16 (Apple) : un numero invente, bit 9 a 1, jamais
    /// un vrai RLOC16 ; son parent reste juste. Une entree resolue dont l'ExtMac est
    /// celle d'un routeur est ecartee des enfants identifies, et passe apres la sonde et une table.
    @Test func enfantResolu() {
        let e = EnfantMaillage(rloc16: 0xAC00 | EnfantMaillage.bitInvente | 2, extMac: "E0000000000000C1",
                               adresses: [], source: .resolution, resolu: Self.debut, echecs: 0.007)
        #expect(!e.rloc16Connu && e.parent == 43)
        #expect(EnfantMaillage(rloc16: 0xAC05, source: .tableEnfants).rloc16Connu)
        var c = Self.quatreRouteurs()
        c.identite("E0000000000000C2", routeur: 5)
        c.enfant(e)
        c.enfant(EnfantMaillage(rloc16: 0x1600, extMac: "E0000000000000C2", source: .resolution))
        c.enfant(EnfantMaillage(rloc16: 0x0805, extMac: "E0000000000000C1", qualite: 2, source: .tableEnfants))
        let m = c.maillage()
        #expect(m.enfantsIdentifies["E0000000000000C2"] == nil, "devenu routeur")
        #expect(m.enfantsIdentifies["E0000000000000C1"]?.source == .tableEnfants, "la table passe avant")
        let resolu = m.enfants.first { $0.rloc16 == e.rloc16 }
        #expect(resolu?.resolu == Self.debut && resolu?.echecs == 0.007)
    }
}

@Suite("Acces au canal refuses d'un enfant, par ses compteurs MAC")
struct AccesCanalTests {
    static func releve(envois: UInt32, echecs: UInt32) -> CompteursMac {
        CompteursMac(protocolesInconnus: 0, erreursRecues: 0, erreursEmises: echecs, unicastRecus: 10, diffusionsRecues: 0,
                     rejetsRecus: 0, unicastEmis: envois, diffusionsEmises: 0, rejetsEmis: 0)
    }

    /// Taux entre deux releves : Δ `ifOutErrors` (acces au canal refuses) / Δ `ifOutUcastPkts` (trames unicast).
    @Test func taux() throws {
        let avant = Self.releve(envois: 5000, echecs: 40)
        let t = try #require(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 6000, echecs: 47)))
        #expect(abs(t - 0.007) < 1e-12)
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 6000, echecs: 91)).map { abs($0 - 0.051) < 1e-12 } == true)
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 6000, echecs: 40)) == 0)
    }

    /// Moins de 50 trames envoyees entre les deux releves : pas de taux ; 50 suffisent.
    @Test func seuilDe50Trames() {
        let avant = Self.releve(envois: 100, echecs: 0)
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 149, echecs: 0)) == nil)
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 150, echecs: 0)) == 0)
        #expect(AccesCanal.tramesMin == 50)
    }

    /// Un compteur qui baisse (l'appareil a redemarre) : pas de taux ; le releve repart de zero.
    @Test func compteurQuiBaisse() {
        let avant = Self.releve(envois: 9000, echecs: 30)
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 200, echecs: 31)) == nil, "envois")
        #expect(AccesCanal.taux(avant: avant, apres: Self.releve(envois: 9900, echecs: 2)) == nil, "echecs")
    }
}

@Suite("Maillage : aller-retour JSON du dernier maillage garde")
struct MaillageJSONTests {
    /// Un maillage complet (sources et dates des liens, ecoute, adresses, resolution, echecs) fait l'aller-retour JSON
    /// du dernier maillage garde (`CodageJSON`) sans rien perdre ; une adresse s'ecrit en texte.
    @Test func allerRetourJSON() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)  // une seconde ronde : le JSON garde les millisecondes
        var chef = RouteurMaillage(id: 3)
        chef.extMac = "0000000000000001"
        chef.bordure = true
        chef.chef = true
        chef.version = 4
        chef.pile = "test"
        chef.entendu = t
        var muet = RouteurMaillage(id: 12)
        muet.muet = true
        let adresse = try #require(AdresseIPv6("fd00::1"))
        var m = Maillage(date: t, partition: "00000001", routeurs: [chef, muet],
                         liens: [LienRadio(a: 3, b: 12, qualiteAB: 3, qualiteBA: nil, sourceAB: .diagnostic,
                                           sourceBA: .ecoute, dateAB: t, dateBA: t.addingTimeInterval(-30))],
                         enfants: [EnfantMaillage(rloc16: 0x0C01, extMac: "0000000000000002", qualite: 2, delai: 240,
                                                  endormi: true, adresses: [adresse], source: .resolution,
                                                  resolu: t, echecs: 0.25),
                                   EnfantMaillage(rloc16: 0x0C02, source: .sonde)],
                         signaux: [SignalSonde(routeur: 3, rssi: -61)])
        m.resolution = t
        m.annoncesLues = true
        let json = try CodageJSON.encodeur().encode(m)
        #expect(String(decoding: json, as: UTF8.self).contains("\"fd00::1\""))
        #expect(try CodageJSON.decodeur().decode(Maillage.self, from: json) == m)
        #expect(m.identifiantsValides)
    }
}
