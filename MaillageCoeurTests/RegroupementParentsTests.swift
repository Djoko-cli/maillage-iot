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
}
