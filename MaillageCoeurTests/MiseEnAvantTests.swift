import Foundation
import Testing
@testable import MaillageCoeur

/// Mode focus, partie generique (reprise de Maillage Zigbee, 09/10) : la cle d'un lien sans ordre, le facteur d'opacite,
/// les cibles d'estompement et la transition douce.
@Suite("Mode focus : mise en avant")
struct MiseEnAvantTests {
    @Test func cleEtFacteur() {
        #expect(MiseEnAvant.cle(idt("b"), idt("a")) == MiseEnAvant.cle(idt("a"), idt("b")))
        #expect(MiseEnAvant.cle(GrapheReseau.Lien(de: idt("x"), vers: idt("y"), genre: .radio)) == MiseEnAvant.cle(idt("y"), idt("x")))
        #expect(MiseEnAvant.facteur(0) == 1 && MiseEnAvant.facteur(1) == MiseEnAvant.opaciteEstompee)
        #expect(abs(MiseEnAvant.facteur(0.5) - (1 - (1 - MiseEnAvant.opaciteEstompee) / 2)) < 1e-9)
        var m = MiseEnAvant(noeuds: [idt("a")])
        m.ajouter(lien: idt("b"), idt("a"))
        #expect(m.noeuds == [idt("a"), idt("b")] && m.contient(lien: GrapheReseau.Lien(de: idt("a"), vers: idt("b"), genre: .parent)))
    }

    /// Sans mise en avant, rien n'est estompe ; avec, tout ce qui n'y est pas vise 1 ; la transition y va en douceur, et
    /// une valeur a moins de 0,001 de sa cible la prend.
    @Test func ciblesEtTransition() {
        #expect(MiseEnAvant.cibles(nil, noeuds: [idt("a"), idt("b")], liens: ["a|b"]) == ([:], [:]))
        let m = MiseEnAvant(noeuds: [idt("a")], liens: [])
        let c = MiseEnAvant.cibles(m, noeuds: [idt("a"), idt("b")], liens: ["a|b"])
        #expect(c.noeuds == [idt("b"): 1] && c.liens == ["a|b": 1])
        var e: [IdNoeud: Double] = [:]
        e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.25)
        #expect(e == [idt("b"): 0.25])
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.25) }
        #expect(e == [idt("b"): 1])
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: [:], k: 0.25) }
        #expect(e.isEmpty, "revenue nette : la valeur nulle n'est pas gardee")
    }

    /// Autres cas du mode focus generique (repris de Maillage Zigbee, `FocusEtFicheTests`) : la cle d'un lien ne depend
    /// ni de l'ordre de ses bouts, ni de son genre ; l'estompement va de net (1) a 18 %, borne ; les cibles estompent ce
    /// qui n'est pas mis en avant, rien sans focus ; la transition y va en douceur, et ne garde pas les valeurs nulles.
    @Test func miseEnAvantGenerique() {
        #expect(MiseEnAvant.cle(idt("B"), idt("A")) == MiseEnAvant.cle(idt("A"), idt("B")))
        #expect(MiseEnAvant.cle(GrapheReseau.Lien(de: idt("B"), vers: idt("A"), genre: .chemin)) == "thread:A|thread:B")
        #expect(MiseEnAvant.facteur(0) == 1 && MiseEnAvant.facteur(1) == MiseEnAvant.opaciteEstompee)
        #expect(MiseEnAvant.facteur(2) == MiseEnAvant.opaciteEstompee && MiseEnAvant.facteur(-1) == 1)
        var m = MiseEnAvant(noeuds: [idt("A")])
        m.ajouter(lien: idt("B"), idt("A"))
        #expect(m.noeuds == [idt("A"), idt("B")] && m.contient(lien: GrapheReseau.Lien(de: idt("A"), vers: idt("B"), genre: .radio)))
        let ab = MiseEnAvant.cle(idt("A"), idt("B")), bc = MiseEnAvant.cle(idt("B"), idt("C"))
        let c = MiseEnAvant.cibles(m, noeuds: [idt("A"), idt("B"), idt("C")], liens: [ab, bc])
        #expect(c.noeuds == [idt("C"): 1] && c.liens == [bc: 1])
        #expect(MiseEnAvant.cibles(nil, noeuds: [idt("A")], liens: [MiseEnAvant.cle(idt("A"), idt("B"))]).noeuds.isEmpty)
        // Vers l'estompement, puis le retour.
        var e: [IdNoeud: Double] = [:]
        for _ in 0..<3 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.3) }
        #expect((e[idt("C")] ?? 0) > 0.5 && (e[idt("C")] ?? 0) < 1, "en route : \(e)")
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.3) }
        #expect(e == [idt("C"): 1], "arrive")
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: [:], k: 0.3) }
        #expect(e.isEmpty, "revenu net, sans valeur nulle gardee")
        #expect(MiseEnAvant.tendre([idt("X"): 0.5], vers: [:], k: 1).isEmpty, "d'un coup")
    }
}
