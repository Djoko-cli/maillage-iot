import Foundation
import Testing
@testable import MaillageCoeur

/// Mode focus, partie generique (reprise de Maillage Zigbee, 09/10) : la cle d'un lien sans ordre, le facteur d'opacite,
/// les cibles d'estompement et la transition douce.
@Suite("Mode focus : mise en avant")
struct MiseEnAvantTests {
    @Test func cleEtFacteur() {
        #expect(MiseEnAvant.cle("b", "a") == MiseEnAvant.cle("a", "b"))
        #expect(MiseEnAvant.cle(GrapheReseau.Lien(de: "x", vers: "y", genre: .radio)) == MiseEnAvant.cle("y", "x"))
        #expect(MiseEnAvant.facteur(0) == 1 && MiseEnAvant.facteur(1) == MiseEnAvant.opaciteEstompee)
        #expect(abs(MiseEnAvant.facteur(0.5) - (1 - (1 - MiseEnAvant.opaciteEstompee) / 2)) < 1e-9)
        var m = MiseEnAvant(noeuds: ["a"])
        m.ajouter(lien: "b", "a")
        #expect(m.noeuds == ["a", "b"] && m.contient(lien: GrapheReseau.Lien(de: "a", vers: "b", genre: .parent)))
    }

    /// Sans mise en avant, rien n'est estompe ; avec, tout ce qui n'y est pas vise 1 ; la transition y va en douceur, et
    /// une valeur a moins de 0,001 de sa cible la prend.
    @Test func ciblesEtTransition() {
        #expect(MiseEnAvant.cibles(nil, noeuds: ["a", "b"], liens: ["a|b"]) == ([:], [:]))
        let m = MiseEnAvant(noeuds: ["a"], liens: [])
        let c = MiseEnAvant.cibles(m, noeuds: ["a", "b"], liens: ["a|b"])
        #expect(c.noeuds == ["b": 1] && c.liens == ["a|b": 1])
        var e: [String: Double] = [:]
        e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.25)
        #expect(e == ["b": 0.25])
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.25) }
        #expect(e == ["b": 1])
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: [:], k: 0.25) }
        #expect(e.isEmpty, "revenue nette : la valeur nulle n'est pas gardee")
    }

    /// Autres cas du mode focus generique (repris de Maillage Zigbee, `FocusEtFicheTests`) : la cle d'un lien ne depend
    /// ni de l'ordre de ses bouts, ni de son genre ; l'estompement va de net (1) a 18 %, borne ; les cibles estompent ce
    /// qui n'est pas mis en avant, rien sans focus ; la transition y va en douceur, et ne garde pas les valeurs nulles.
    @Test func miseEnAvantGenerique() {
        #expect(MiseEnAvant.cle("B", "A") == MiseEnAvant.cle("A", "B"))
        #expect(MiseEnAvant.cle(GrapheReseau.Lien(de: "B", vers: "A", genre: .chemin)) == "A|B")
        #expect(MiseEnAvant.facteur(0) == 1 && MiseEnAvant.facteur(1) == MiseEnAvant.opaciteEstompee)
        #expect(MiseEnAvant.facteur(2) == MiseEnAvant.opaciteEstompee && MiseEnAvant.facteur(-1) == 1)
        var m = MiseEnAvant(noeuds: ["A"])
        m.ajouter(lien: "B", "A")
        #expect(m.noeuds == ["A", "B"] && m.contient(lien: GrapheReseau.Lien(de: "A", vers: "B", genre: .radio)))
        let c = MiseEnAvant.cibles(m, noeuds: ["A", "B", "C"], liens: ["A|B", "B|C"])
        #expect(c.noeuds == ["C": 1] && c.liens == ["B|C": 1])
        #expect(MiseEnAvant.cibles(nil, noeuds: ["A"], liens: ["A|B"]).noeuds.isEmpty)
        // Vers l'estompement, puis le retour.
        var e: [String: Double] = [:]
        for _ in 0..<3 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.3) }
        #expect((e["C"] ?? 0) > 0.5 && (e["C"] ?? 0) < 1, "en route : \(e)")
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: c.noeuds, k: 0.3) }
        #expect(e == ["C": 1], "arrive")
        for _ in 0..<40 { e = MiseEnAvant.tendre(e, vers: [:], k: 0.3) }
        #expect(e.isEmpty, "revenu net, sans valeur nulle gardee")
        #expect(MiseEnAvant.tendre(["X": 0.5], vers: [:], k: 1).isEmpty, "d'un coup")
    }
}
