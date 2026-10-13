import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Courbes d'un noeud : choix des courbes montrees")
struct CourbesNoeudTests {
    /// Les courbes montrees (generique) : au plus six, les prioritaires d'abord ; sans prioritaire, les six premieres ;
    /// « tous les liens » : toutes, les prioritaires en tete ; la case n'ajoute que ce qui est cache ; la mise en avant
    /// d'une pastille se bascule.
    @Test func choixDesCourbes() {
        let cles = (1...8).map { "k\($0)" }
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: ["k8", "k3", "absente"], tous: false) == ["k8", "k3"])
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: [], tous: false) == Array(cles.prefix(6)))
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: ["k8"], tous: true) == ["k8"] + cles.dropLast())
        #expect(ChoixCourbes.cachees(cles: cles, prioritaires: []) == 2)
        #expect(ChoixCourbes.cachees(cles: ["k1"], prioritaires: ["k1"]) == 0)
        #expect(ChoixCourbes.basculer(nil, "k1") == "k1" && ChoixCourbes.basculer("k1", "k1") == nil)
        #expect(ChoixCourbes.basculer("k1", "k2") == "k2")
        // Une courbe en avant mais plus montree (case « tous » decochee, autre periode) n'estompe pas les autres.
        #expect(ChoixCourbes.enAvant("g", parmi: ["a", "b"]) == nil)
        #expect(ChoixCourbes.enAvant("b", parmi: ["a", "b"]) == "b" && ChoixCourbes.enAvant(nil, parmi: ["a"]) == nil)
    }
}
