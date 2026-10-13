import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Journal : changements de parent regroupes")
struct RegroupementParentsTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func parent(_ minutes: Double, _ noeud: String) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: noeud, nom: noeud),
                  avant: "A", apres: "B")
    }

    /// Changements de parent d'un meme noeud dans une fenetre de 1 h, comptee depuis le premier :
    /// une ligne ; seul dans sa fenetre, il reste une ligne a lui ; un autre noeud a les siennes.
    @Test func uneLigneParNoeudEtParHeure() throws {
        let lignes = Regroupement.lignes([Self.parent(0, "x"), Self.parent(10, "x"), Self.parent(20, "y"),
                                          Self.parent(50, "x"), Self.parent(59, "x"), Self.parent(70, "x")])
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

    /// Evenement d'un enfant identifie : `details["extMac"]` le designe, meme quand son id de sujet
    /// (« rloc:XXXX ») change avec son parent.
    static func parent(_ minutes: Double, sujet: String, extMac: String?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: sujet, nom: sujet),
                  avant: "A", apres: "B", details: extMac.map { ["extMac": $0] } ?? [:])
    }

    /// Avec une ExtMac, elle fait la cle : le meme enfant sous deux ids de sujet est une ligne, deux
    /// enfants sous un meme id de sujet sont deux lignes. Sans ExtMac (evenements deja ecrits), l'id
    /// du sujet reste la cle.
    @Test func cleParExtMac() {
        let b1 = "E0000000000000B1", b2 = "E0000000000000B2"
        let memeEnfant = Regroupement.lignes([Self.parent(0, sujet: "rloc:0401", extMac: b1),
                                              Self.parent(5, sujet: "rloc:0801", extMac: b1)])
        #expect(memeEnfant.map(\.evenements.count) == [2])
        let deuxEnfants = Regroupement.lignes([Self.parent(0, sujet: "rloc:0401", extMac: b1),
                                               Self.parent(5, sujet: "rloc:0401", extMac: b2)])
        #expect(deuxEnfants.map(\.evenements.count) == [1, 1])
        let anciens = Regroupement.lignes([Self.parent(0, sujet: "rloc:0401", extMac: nil),
                                           Self.parent(5, sujet: "rloc:0401", extMac: nil),
                                           Self.parent(6, sujet: "rloc:0801", extMac: nil)])
        #expect(anciens.map(\.evenements.count) == [1, 2], "l'ancien regroupement, par id de sujet")
    }

    /// La fenetre est de 1 h pleine : un changement a 59 min 59 s du premier est dans sa ligne, a
    /// 60 min pile il ouvre la suivante (comme les pertes a 10 min).
    @Test func borneExacteDeLHeure() {
        let dedans = Regroupement.lignes([Self.parent(0, "x"), Self.parent(59.98, "x")])
        #expect(dedans.map(\.evenements.count) == [2], "59 min 59 s : meme ligne")
        let pile = Regroupement.lignes([Self.parent(0, "x"), Self.parent(60, "x")])
        #expect(pile.map(\.evenements.count) == [1, 1], "60 min : une autre fenetre")
    }

    /// Les pertes restent regroupees a part, et les autres evenements passent tels quels.
    @Test func pertesInchangees() {
        let perte = { (minutes: Double, id: String) in
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .appareilDisparu, sujet: Sujet(id: id, nom: id))
        }
        let lignes = Regroupement.lignes([perte(0, "a"), Self.parent(1, "x"), perte(2, "b"), Self.parent(3, "x"),
                                          Evenement(date: Self.t0.addingTimeInterval(240), type: .sansParent)])
        #expect(lignes.count == 3)
        #expect(lignes.contains { if case .pertes(let p) = $0 { p.count == 2 } else { false } })
        #expect(lignes.contains { if case .parents(let p) = $0 { p.count == 2 } else { false } })
    }
}
