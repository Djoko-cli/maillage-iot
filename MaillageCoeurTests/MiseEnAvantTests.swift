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
}
