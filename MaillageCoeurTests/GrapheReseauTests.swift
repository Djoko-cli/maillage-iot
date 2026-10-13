import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : noeuds et liens d'un reseau")
struct GrapheReseauTests {
    static let instantane = Instantane(annonces: Releve20260928.annonces)

    static func affiches(_ i: Instantane) -> [AppareilAffiche] {
        i.appareils.map {
            AppareilAffiche(id: $0.id, nom: $0.id, partition: $0.partition,
                            etat: $0.etat == .sansAdresse ? .sansAdresse : .joignable, endormi: $0.endormi)
        }
    }

    /// Releve du 28/09 sans sonde : le centre (Apple TV), les 4 HomePod, 22 appareils rattaches au
    /// centre ; la partition de l'Aqara, son centre seul ; deux appareils sans partition connue.
    @Test func releveReel() throws {
        let r = try #require(Self.instantane.reseaux.first)
        let g = GrapheReseau(reseau: r, appareils: Self.affiches(Self.instantane))
        let atv = try #require(g.noeud("Apple TV 4K"))
        #expect(atv.genre == .centre && atv.routeur && atv.bordure && atv.partition == "73586B68")
        let homepods = g.noeuds.filter { $0.genre == .routeur }
        #expect(homepods.map(\.id) == ["HomePod Avant", "HomePod Palier", "HomePod mini bureau", "HomePod mini chambre"])
        #expect(homepods.allSatisfy { $0.bordure && !$0.inconnu })
        #expect(g.noeuds.filter { $0.genre == .appareil && $0.partition == "73586B68" }.count == 22)
        #expect(g.noeud("Aqara HubM100 #DFEB")?.genre == .centre)
        #expect(g.noeuds.filter { $0.partition.isEmpty }.map(\.id) == ["1E5019DAC2638F92", "724CC16B32D8F820"])
        #expect(g.liens.count == 26, "4 routeurs et 22 appareils vers l'Apple TV")
        #expect(g.liens.allSatisfy { $0.vers == "Apple TV 4K" && $0.genre == .rattachement })
        #expect(g.parent(de: "56B1E064401F74EF") == nil, "sans sonde : pas de parent connu")
    }

    /// L'ordre d'arrivee des appareils ne compte pas ; un appareil disparu reste un noeud.
    @Test func stable() throws {
        let r = try #require(Self.instantane.reseaux.first)
        let apps = Self.affiches(Self.instantane)
        let g = GrapheReseau(reseau: r, appareils: apps)
        #expect(GrapheReseau(reseau: r, appareils: apps.reversed()) == g)
        var avecDisparu = apps
        let i = try #require(avecDisparu.firstIndex { $0.id == "56B1E064401F74EF" })
        avecDisparu[i].etat = .disparu
        #expect(GrapheReseau(reseau: r, appareils: avecDisparu) == g)
    }

    /// Avec la sonde (capture anonymisee) : routeurs reconnus ou inconnus, appareil qui route, enfant
    /// inconnu ; liens de la sonde, et le rattachement au centre des noeuds qu'elle ne relie pas.
    /// L'annonce du HomePod du salon, candidate des routeurs de bordure non identifies, n'est pas un
    /// noeud a part.
    @Test func avecLaSonde() async throws {
        let i = RapprochementTests.instantane()
        let r = try #require(i.reseaux.first)
        let m = MaillageAffiche(maillage: try await RapprochementTests.maillage(), reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(g.noeud("Apple TV")?.genre == .centre)
        #expect(g.noeud("HomePod salon") == nil, "candidate : portee par les routeurs non identifies")
        #expect(g.noeud("HomePod bureau")?.genre == .routeur)
        let routeurAppareil = try #require(g.noeud("E000000000000002"))
        #expect(routeurAppareil.genre == .appareil && routeurAppareil.routeur && !routeurAppareil.bordure)
        let inconnu = try #require(g.noeud("rloc:0400"))
        #expect(inconnu.genre == .routeur && inconnu.inconnu && inconnu.bordure)
        #expect(g.noeud("rloc:6002")?.genre == .appareil && g.noeud("rloc:6002")?.inconnu == true)
        #expect(g.liens.filter { $0.genre == .radio }.count == 7)
        #expect(g.liens.contains(GrapheReseau.Lien(de: "E000000000000004", vers: "E000000000000002", genre: .parent,
                                                   qualite: 2)))
        #expect(g.parent(de: "E000000000000004") == "E000000000000002")
        #expect(g.liens.contains(GrapheReseau.Lien(de: "rloc:E400", vers: "Apple TV")), "sans lien connu : rattachement")
        #expect(g.liens.contains(GrapheReseau.Lien(de: "Absent", vers: "Apple TV")))
        #expect(!g.liens.contains { $0.de == "E000000000000004" && $0.genre == .rattachement })
    }

    /// Un enfant vu deux fois (il a change de parent ; l'ancienne entree de la resolution sous un routeur muet
    /// peut rester 30 minutes) n'est qu'un noeud, pas un « rloc:XXXX » inconnu de plus : il est
    /// rattache par l'entree que retient `Maillage.enfantsIdentifies` (la sonde, puis la table d'un
    /// routeur qui repond, puis la resolution), quel que soit l'ordre des RLOC16.
    @Test(arguments: [
        // (source de l'entree sous le routeur 0 ; source de l'entree sous le routeur 1 ; parent attendu)
        (SourceEnfant.resolution, SourceEnfant.tableEnfants, "rloc:0400"),
        (.tableEnfants, .resolution, "rloc:0000"),
        (.tableEnfants, .sonde, "rloc:0400"),
    ])
    func enfantVuDeuxFois(premiere: SourceEnfant, seconde: SourceEnfant, attendu: String) throws {
        let i = RapprochementTests.instantane()
        let r = try #require(i.reseaux.first)
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.routeurs(Route64(sequence: 1, routes: [RouteRouteur(idRouteur: 0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1),
                                                 RouteRouteur(idRouteur: 1, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)]),
                   chef: 0)
        c.enfant(EnfantMaillage(rloc16: 0x0002, extMac: "E000000000000004", qualite: 3, source: premiere))
        c.enfant(EnfantMaillage(rloc16: 0x0405, extMac: "E000000000000004", qualite: 2, source: seconde))
        let m = MaillageAffiche(maillage: c.maillage(), reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(!g.noeuds.contains { $0.inconnu && $0.genre == .appareil }, "pas de noeud en double")
        #expect(g.noeud("rloc:0002") == nil && g.noeud("rloc:0405") == nil)
        #expect(g.liens.filter { $0.de == "E000000000000004" }.count == 1)
        #expect(g.parent(de: "E000000000000004") == attendu)
    }

    /// Un enfant devenu routeur garde jusqu'a 30 minutes son entree de la resolution sous un routeur muet, sous
    /// son ancien RLOC16 : elle est ecartee, son ExtMac etant celle d'un routeur du maillage. Pas de
    /// noeud « Non identifie » en double, ni de lien, ni d'ExtMac a son nom (la cle d'un choix de piece).
    @Test func enfantDevenuRouteur() throws {
        let i = RapprochementTests.instantane()
        let r = try #require(i.reseaux.first)
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: "46CBEBCD")
        c.routeurs(Route64(sequence: 1, routes: [0, 1, 2].map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 0)
        c.identite("E000000000000004", routeur: 1)
        c.muet(2)
        c.enfant(EnfantMaillage(rloc16: 0x0802, extMac: "E000000000000004", source: .resolution))
        let m = MaillageAffiche(maillage: c.maillage(), reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(g.noeud("rloc:0802") == nil, "pas de noeud en double")
        #expect(!g.noeuds.contains { $0.inconnu && $0.genre == .appareil })
        #expect(g.noeud("E000000000000004")?.routeur == true, "l'appareil est le routeur 1")
        #expect(!g.liens.contains { $0.de == "rloc:0802" })
        #expect(m.extMacs["rloc:0802"] == nil)
    }

    /// Elimination : le HomePod palier, reconnu par elimination, est un seul noeud.
    @Test func elimination() async throws {
        let i = RapprochementTests.instantane(autres: [("HomePod bureau", "E000000000000007"),
                                                       ("HomePod chambre", "E0000000000000E4"),
                                                       ("HomePod palier", "E0000000000000D2"),
                                                       ("HomePod salon", "E0000000000000CC")])
        let r = try #require(i.reseaux.first)
        let maillage = try await RapprochementTests.maillage(entendus: [0xE400: "E0000000000000E4",
                                                                        0xCC00: "E0000000000000CC"])
        let m = MaillageAffiche(maillage: maillage, reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(g.noeuds.filter { $0.id == "HomePod palier" }.count == 1)
        #expect(!g.noeuds.contains { $0.inconnu && $0.genre == .routeur })
    }

    /// Deux routeurs de bordure non identifies, deux annonces candidates : elles ne sont pas des
    /// noeuds ; sans sonde, rien ne change, les annonces sont des noeuds.
    @Test func candidats() async throws {
        let i = RapprochementTests.instantane(autres: [("HomePod bureau", "E000000000000007"),
                                                       ("HomePod chambre", "E0000000000000E4"),
                                                       ("HomePod avant", "E0000000000000D1"),
                                                       ("HomePod palier", "E0000000000000D2")])
        let r = try #require(i.reseaux.first)
        let m = MaillageAffiche(maillage: try await RapprochementTests.maillage(entendus: [0xE400: "E0000000000000E4"]),
                                reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(g.noeud("HomePod avant") == nil && g.noeud("HomePod palier") == nil)
        #expect(g.noeud("rloc:0400") != nil && g.noeud("rloc:CC00") != nil)
        let sans = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i))
        #expect(sans.noeud("HomePod avant") != nil && sans.noeud("HomePod palier") != nil)
    }

    /// Reseau scinde : seules les annonces candidates de la partition de la sonde ne sont pas des
    /// noeuds ; l'autre partition garde les siennes.
    @Test func autrePartition() async throws {
        let i = RapprochementTests.instantane(ailleurs: [("Aqara", "E0000000000000AA"), ("HomePod isole", "E0000000000000A9")])
        let r = try #require(i.reseaux.first)
        let m = MaillageAffiche(maillage: try await RapprochementTests.maillage(), reseau: r, appareils: i.appareils)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: m)
        #expect(g.noeud("HomePod salon") == nil)
        #expect(g.noeud("Aqara")?.partition == "73586B68" && g.noeud("HomePod isole")?.partition == "73586B68")
        #expect(g.noeud("Aqara")?.genre == .centre)
    }

    /// Le centre peut etre candidat : il reste un noeud, au centre ; l'autre annonce candidate, non.
    @Test func centreCandidat() throws {
        var b = Banc()
        b.routeur("Alpha", partition: "46CBEBCD", role: nil, lien: "fe80::1", xa: "E0000000000000C1")
        b.routeur("HomePod avant", partition: "46CBEBCD", role: nil, lien: "fe80::2", xa: "E0000000000000D1")
        let i = Instantane(annonces: b.annonces)
        let r = try #require(i.reseaux.first)
        let m = try RapprochementTests.deuxRouteurs(i)
        let g = GrapheReseau(reseau: r, appareils: [], maillage: m)
        #expect(g.noeud("Alpha")?.genre == .centre)
        #expect(g.noeud("HomePod avant") == nil)
        #expect(g.noeuds.map(\.id) == ["Alpha", "rloc:0400", "rloc:0800"])
    }
}
