import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Le mecanisme de regroupement (fenetre de 1 h, borne, ordre) est teste dans le coeur
/// (`MaillageCoeurTests/RegroupementParentsTests.swift`, politique d'essai) ; ici, ce que Thread regroupe.
@Suite("Regroupement Thread : changements de parent par ExtMac")
struct RegroupementParentsThreadTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func parent(_ minutes: Double, _ noeud: String) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: noeud, nom: noeud),
                  avant: "A", apres: "B")
    }

    /// `parentChange` se regroupe par noeud sur une heure.
    @Test func parentChangeRegroupeParNoeud() {
        let lignes = Regroupement.lignes([Self.parent(0, "x"), Self.parent(10, "x"), Self.parent(20, "y")],
                                         politique: PolitiqueJournalThread())
        #expect(lignes.map(\.evenements.count) == [1, 2])
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
                                              Self.parent(5, sujet: "rloc:0801", extMac: b1)], politique: PolitiqueJournalThread())
        #expect(memeEnfant.map(\.evenements.count) == [2])
        let deuxEnfants = Regroupement.lignes([Self.parent(0, sujet: "rloc:0401", extMac: b1),
                                               Self.parent(5, sujet: "rloc:0401", extMac: b2)], politique: PolitiqueJournalThread())
        #expect(deuxEnfants.map(\.evenements.count) == [1, 1])
        let anciens = Regroupement.lignes([Self.parent(0, sujet: "rloc:0401", extMac: nil),
                                           Self.parent(5, sujet: "rloc:0401", extMac: nil),
                                           Self.parent(6, sujet: "rloc:0801", extMac: nil)], politique: PolitiqueJournalThread())
        #expect(anciens.map(\.evenements.count) == [1, 2], "l'ancien regroupement, par id de sujet")
    }

    /// Les pertes Thread (`appareilDisparu`) restent regroupees a part, et `sansParent` passe tel quel.
    @Test func pertesInchangees() {
        let perte = { (minutes: Double, id: String) in
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .appareilDisparu, sujet: Sujet(id: id, nom: id))
        }
        let lignes = Regroupement.lignes([perte(0, "a"), Self.parent(1, "x"), perte(2, "b"), Self.parent(3, "x"),
                                          Evenement(date: Self.t0.addingTimeInterval(240), type: .sansParent)], politique: PolitiqueJournalThread())
        #expect(lignes.count == 3)
        #expect(lignes.contains { if case .pertes(let p) = $0 { p.count == 2 } else { false } })
        #expect(lignes.contains { if case .parents(let p) = $0 { p.count == 2 } else { false } })
    }
}
