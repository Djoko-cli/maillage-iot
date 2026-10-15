import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Journal : changements de parent regroupes")
struct RegroupementParentsTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func parent(_ minutes: Double, _ noeud: String) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .essaiParent, sujet: Sujet(id: noeud, nom: noeud),
                  avant: "A", apres: "B")
    }

    /// Changements de parent d'un meme noeud dans une fenetre de 1 h, comptee depuis le premier :
    /// une ligne ; seul dans sa fenetre, il reste une ligne a lui ; un autre noeud a les siennes.
    @Test func uneLigneParNoeudEtParHeure() throws {
        let lignes = Regroupement.lignes([Self.parent(0, "x"), Self.parent(10, "x"), Self.parent(20, "y"),
                                          Self.parent(50, "x"), Self.parent(59, "x"), Self.parent(70, "x")], politique: PolitiqueEssai())
        try #require(lignes.map(\.evenements.count) == [1, 4, 1], "la plus recente d'abord : x a 70 min, x, y")
        guard case .parents(let groupe) = lignes[1] else {
            Issue.record("les 4 changements de x dans l'heure regroupes")
            return
        }
        #expect(groupe.map(\.date) == [0.0, 10, 50, 59].map { Self.t0.addingTimeInterval($0 * 60) })
        #expect(lignes[1].date == Self.t0.addingTimeInterval(59 * 60), "date du plus recent")
        #expect(lignes[1].id.hasPrefix("parents-"))
        #expect(lignes[0].evenements.first?.date == Self.t0.addingTimeInterval(70 * 60), "70 min : une autre fenetre")
        #expect(lignes[2].evenements.first?.sujet?.id == "y")
    }

    /// Evenement d'un noeud identifie : `details["cle"]` le designe, meme quand son id de sujet change.
    static func parent(_ minutes: Double, sujet: String, cle: String?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .essaiParent, sujet: Sujet(id: sujet, nom: sujet),
                  avant: "A", apres: "B", details: cle.map { ["cle": $0] } ?? [:])
    }

    /// Avec une cle de politique, elle fait le noeud : le meme noeud sous deux ids de sujet est une ligne, deux
    /// noeuds sous un meme id de sujet sont deux lignes. Sans cle, l'id du sujet reste le noeud.
    @Test func cleDeLaPolitique() {
        let memeNoeud = Regroupement.lignes([Self.parent(0, sujet: "s1", cle: "K1"),
                                             Self.parent(5, sujet: "s2", cle: "K1")], politique: PolitiqueEssai())
        #expect(memeNoeud.map(\.evenements.count) == [2])
        let deuxNoeuds = Regroupement.lignes([Self.parent(0, sujet: "s1", cle: "K1"),
                                              Self.parent(5, sujet: "s1", cle: "K2")], politique: PolitiqueEssai())
        #expect(deuxNoeuds.map(\.evenements.count) == [1, 1])
        let sansCle = Regroupement.lignes([Self.parent(0, sujet: "s1", cle: nil),
                                           Self.parent(5, sujet: "s1", cle: nil),
                                           Self.parent(6, sujet: "s2", cle: nil)], politique: PolitiqueEssai())
        #expect(sansCle.map(\.evenements.count) == [1, 2], "regroupement par id de sujet")
    }

    /// La fenetre est de 1 h pleine : un changement a 59 min 59 s du premier est dans sa ligne, a
    /// 60 min pile il ouvre la suivante (comme les pertes a 10 min).
    @Test func borneExacteDeLHeure() {
        let dedans = Regroupement.lignes([Self.parent(0, "x"), Self.parent(59.98, "x")], politique: PolitiqueEssai())
        #expect(dedans.map(\.evenements.count) == [2], "59 min 59 s : meme ligne")
        let pile = Regroupement.lignes([Self.parent(0, "x"), Self.parent(60, "x")], politique: PolitiqueEssai())
        #expect(pile.map(\.evenements.count) == [1, 1], "60 min : une autre fenetre")
    }

    /// Les pertes restent regroupees a part, et les autres evenements passent tels quels.
    @Test func pertesInchangees() {
        let perte = { (minutes: Double, id: String) in
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .essaiPerte, sujet: Sujet(id: id, nom: id))
        }
        let lignes = Regroupement.lignes([perte(0, "a"), Self.parent(1, "x"), perte(2, "b"), Self.parent(3, "x"),
                                          Evenement(date: Self.t0.addingTimeInterval(240), type: .essaiSansParent)], politique: PolitiqueEssai())
        #expect(lignes.count == 3)
        #expect(lignes.contains { if case .pertes(let p) = $0 { p.count == 2 } else { false } })
        #expect(lignes.contains { if case .parents(let p) = $0 { p.count == 2 } else { false } })
    }

    /// Sans politique (`PolitiqueJournalNeutre`), rien ne se regroupe.
    @Test func politiqueNeutreNeRegroupeRien() {
        let lignes = Regroupement.lignes([Self.parent(0, "x"), Self.parent(1, "x")], politique: PolitiqueJournalNeutre())
        #expect(lignes.map(\.evenements.count) == [1, 1])
    }

    static func chemin(_ minutes: Double, _ noeud: String) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .essaiChemin, sujet: Sujet(id: noeud, nom: noeud),
                  avant: "A", apres: "B")
    }

    /// Les changements de chemin d'un meme routeur dans l'heure forment une ligne `.chemins`, a part de ceux de
    /// parent du meme noeud (clef « chemin| » / « parent| ») ; seul dans sa fenetre, un changement reste une ligne.
    @Test func cheminsRegroupes() throws {
        let lignes = Regroupement.lignes([Self.chemin(0, "x"), Self.parent(5, "x"), Self.chemin(10, "x"),
                                          Self.parent(15, "x"), Self.chemin(20, "y"), Self.chemin(70, "x")],
                                         politique: PolitiqueEssai())
        try #require(lignes.map(\.evenements.count) == [1, 1, 2, 2], "la plus recente d'abord : x a 70 min, y, parents de x, chemins de x")
        guard case .chemins(let chemins) = lignes[3], case .parents(let parents) = lignes[2] else {
            Issue.record("deux lignes distinctes : chemins de x et parents de x")
            return
        }
        #expect(chemins.map(\.date) == [0.0, 10].map { Self.t0.addingTimeInterval($0 * 60) })
        #expect(chemins.allSatisfy { $0.type == .essaiChemin } && parents.allSatisfy { $0.type == .essaiParent })
        #expect(lignes[3].id.hasPrefix("chemins-") && lignes[3].id == "chemins-" + (chemins.first?.id ?? ""))
        #expect(lignes[3].date == Self.t0.addingTimeInterval(10 * 60), "date du plus recent")
        #expect(lignes[3].gravite == .info)
        guard case .evenement = lignes[1], case .evenement = lignes[0] else {
            Issue.record("y seul, et x a 70 min dans une autre fenetre : evenements simples")
            return
        }
    }

    /// Politique qui ne definit pas `estChemin` (implementation par defaut) : tout se regroupe comme avant, en `.parents`.
    struct PolitiqueSansChemin: PolitiqueJournal {
        var types: [TypeEvenement] { [.essaiParent, .essaiChemin] }
        func estPerte(_ e: Evenement) -> Bool { false }
        func estScission(_ e: Evenement) -> Bool { false }
        func estReunion(_ e: Evenement) -> Bool { false }
        func categorie(_ e: Evenement) -> CategorieAlerte? { nil }
        func cleParent(_ e: Evenement) -> String? { e.sujet?.id }
    }

    @Test func politiqueSansCheminInchangee() {
        let politique = PolitiqueSansChemin()
        #expect(politique.estChemin(Self.chemin(0, "x")) == false, "implementation par defaut")
        let lignes = Regroupement.lignes([Self.chemin(0, "x"), Self.parent(5, "x"), Self.chemin(10, "x")], politique: politique)
        #expect(lignes.map(\.evenements.count) == [3], "une seule cle « parent| » par noeud, comme avant")
        guard case .parents(let g) = lignes[0] else {
            Issue.record("regroupes en .parents, jamais .chemins")
            return
        }
        #expect(g.count == 3)
    }

    static func parent(_ minutes: Double, _ noeud: String, _ protocole: Protocole?) -> Evenement {
        var e = parent(minutes, noeud)
        e.protocole = protocole
        return e
    }

    /// Deux appareils de deux protocoles qui ont la meme cle de parent ne se regroupent jamais : la cle du groupe est
    /// `<protocole>|parent|<cle>` (`<protocole>|chemin|<cle>`). Sans protocole, un evenement est de Thread.
    @Test func regroupementSepareLesProtocoles() throws {
        let compose = PolitiqueJournalComposee([.thread: PolitiqueEssai(), .zigbee: PolitiqueEssai()])
        let melange = Regroupement.lignes([Self.parent(0, "x", .thread), Self.parent(5, "x", .zigbee),
                                           Self.parent(10, "x", .thread), Self.parent(15, "x", .zigbee),
                                           Self.parent(20, "x", nil)], politique: compose)
        try #require(melange.count == 2, "un groupe par protocole : \(melange.map(\.evenements.count))")
        let parProtocole = melange.map { Set($0.evenements.map { $0.protocole ?? .thread }) }
        #expect(parProtocole.allSatisfy { $0.count == 1 }, "aucun groupe ne melange les protocoles")
        let thread = try #require(melange.first { $0.evenements.first?.protocole != .zigbee })
        let zigbee = try #require(melange.first { $0.evenements.first?.protocole == .zigbee })
        #expect(thread.evenements.count == 3, "Thread : deux evenements marques et un sans protocole")
        #expect(zigbee.evenements.count == 2)
        // Seul dans son protocole, un evenement reste une ligne a lui, meme avec la cle d'un autre.
        let seuls = Regroupement.lignes([Self.parent(0, "x", .thread), Self.parent(5, "x", .zigbee)], politique: compose)
        #expect(seuls.map(\.evenements.count) == [1, 1])
        // Les changements de chemin se separent de meme.
        var c1 = Self.chemin(0, "x")
        c1.protocole = .thread
        var c2 = Self.chemin(5, "x")
        c2.protocole = .zigbee
        #expect(Regroupement.lignes([c1, c2], politique: compose).map(\.evenements.count) == [1, 1])
        // Thread seul : le regroupement est celui d'avant.
        let avant = Regroupement.lignes([Self.parent(0, "x"), Self.parent(10, "x"), Self.parent(20, "y")],
                                        politique: PolitiqueEssai())
        let apres = Regroupement.lignes([Self.parent(0, "x", .thread), Self.parent(10, "x", .thread),
                                         Self.parent(20, "y", .thread)], politique: compose)
        #expect(avant.map(\.evenements.count) == apres.map(\.evenements.count) && apres.map(\.evenements.count) == [1, 2])
    }

    /// Les pertes se regroupent par protocole, comme les changements de parent : deux pertes de deux protocoles, dans la
    /// meme fenetre de 10 min, ne forment pas une ligne ; deux d'un meme protocole oui, meme entrelacees avec l'autre.
    @Test func pertesParProtocole() {
        func perte(_ secondes: Double, _ protocole: Protocole?, _ id: String) -> Evenement {
            Evenement(date: Self.t0.addingTimeInterval(secondes), type: .essaiPerte, sujet: Sujet(id: id, nom: id),
                      protocole: protocole)
        }
        let melangees = [perte(0, .thread, "t1"), perte(10, .zigbee, "z1"), perte(20, .thread, "t2"),
                         perte(30, .zigbee, "z2"), perte(40, .zigbee, "z3")]
        let lignes = Regroupement.lignes(melangees, politique: PolitiqueEssai())
        let groupes = lignes.compactMap { l -> [String]? in
            if case .pertes(let g) = l { return g.compactMap(\.sujet?.id) }
            return nil
        }.sorted { $0.joined() < $1.joined() }
        #expect(groupes == [["t1", "t2"], ["z1", "z2", "z3"]], "une ligne de pertes par protocole")
        #expect(lignes.count == 2)
        // Un seul de chaque protocole : deux evenements, pas un groupe.
        let seuls = Regroupement.lignes([perte(0, .thread, "t1"), perte(10, .zigbee, "z1")], politique: PolitiqueEssai())
        #expect(seuls.count == 2 && seuls.allSatisfy { if case .evenement = $0 { true } else { false } })
        // Sans protocole : Thread, regroupe avec ceux de Thread.
        let anciennes = Regroupement.lignes([perte(0, nil, "t1"), perte(10, .thread, "t2")], politique: PolitiqueEssai())
        #expect(anciennes.map(\.evenements.count) == [2])
        // La fenetre de 10 min se compte par protocole : la premiere perte de chacun l'ouvre.
        let fenetres = Regroupement.lignes([perte(0, .thread, "t1"), perte(500, .zigbee, "z1"), perte(700, .zigbee, "z2"),
                                            perte(650, .thread, "t2")], politique: PolitiqueEssai())
        #expect(Set(fenetres.map(\.evenements.count)) == [1, 2], "t1 | t2 ; z1, z2 (a 200 s l'un de l'autre)")
    }
}
