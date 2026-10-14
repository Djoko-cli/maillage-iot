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

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Un point de courbe garde le LQI d'origine de la qualite d'un lien ; sans mesure, `nil` par defaut.
    @Test func pointAvecLqi() {
        let sans = PointCourbe(date: Self.t0, valeur: 2, troncon: 0)
        #expect(sans.lqi == nil)
        let avec = PointCourbe(date: Self.t0, valeur: 2, troncon: 0, lqi: 180)
        #expect(avec.lqi == 180)
        #expect(sans != avec)
    }

    /// `reduire` avec une valeur d'origine : sans pas, chaque releve garde la sienne ; avec un pas, la moyenne des
    /// valeurs connues du pas (les releves sans valeur d'origine ne comptent pas) ; sans aucune, `nil`. Le calcul de la
    /// valeur et des troncons est celui de la version sans valeur d'origine.
    @Test func reduireGardeLaValeurDOrigine() {
        let bruts: [(Date, Double, Double?)] = [(Self.t0, 3, 200), (Self.t0.addingTimeInterval(300), 2, nil)]
        let chaque = CourbesNoeud.reduire(bruts, pas: nil)
        #expect(chaque.map(\.lqi) == [200, nil])
        #expect(chaque.map(\.valeur) == [3, 2])

        let pas = 1800.0
        let debut = Date(timeIntervalSince1970: (Self.t0.timeIntervalSince1970 / pas).rounded(.down) * pas)
        let moyenne = CourbesNoeud.reduire([(debut, 3, 200), (debut.addingTimeInterval(60), 2, nil),
                                            (debut.addingTimeInterval(120), 1, 100),
                                            (debut.addingTimeInterval(pas), 1, nil)], pas: pas)
        #expect(moyenne.count == 2)
        #expect(moyenne[0].lqi == 150 && moyenne[0].valeur == 2, "LQI moyen des valeurs connues, valeur moyenne de toutes")
        #expect(moyenne[1].lqi == nil)

        let ancienne = CourbesNoeud.reduire([(Self.t0, -60), (Self.t0.addingTimeInterval(300), -62)], pas: nil)
        #expect(ancienne.allSatisfy { $0.lqi == nil }, "la version sans valeur d'origine n'en pose aucune")
        let troncons = CourbesNoeud.reduire([(Self.t0, 1, 10), (Self.t0.addingTimeInterval(3600), 1, 10)], pas: nil)
        #expect(troncons.map(\.troncon) == [0, 1], "un trou de plus de 20 min ouvre un troncon")
    }

    /// L'init public garde `chemins` vide par defaut ; il le porte quand on le donne.
    @Test func cheminsDeLaCourbe() {
        let c = CourbesNoeud(debut: Self.t0, fin: Self.t0, liens: [], parents: [], signal: [], parentsSonde: [],
                             prioritaires: [])
        #expect(c.chemins.isEmpty && c.estVide)
        let ch = ChangementParent(date: Self.t0, parent: "k")
        let d = CourbesNoeud(debut: Self.t0, fin: Self.t0, liens: [], parents: [], chemins: [ch], signal: [],
                             parentsSonde: [], prioritaires: [])
        #expect(d.chemins == [ch])
    }

    /// Autres cas du choix generique (repris de Maillage Zigbee, `FocusEtFicheTests`) : au plus six prioritaires, dans
    /// leur ordre, celles qui ont une courbe ; sans prioritaire, les six premieres ; « tous » : toutes, les prioritaires
    /// d'abord ; le nombre que la case ajoute ; la pastille qui met une courbe en avant, puis la rend.
    @Test func choixDesCourbesAutresCas() {
        let cles = (1...9).map { "k\($0)" }
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: ["k9", "zz", "k2"], tous: false) == ["k9", "k2"])
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: [], tous: false) == Array(cles.prefix(6)))
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: cles.reversed(), tous: false) == ["k9", "k8", "k7", "k6", "k5", "k4"])
        #expect(ChoixCourbes.montrees(cles: cles, prioritaires: ["k9", "k2"], tous: true)
                == ["k9", "k2", "k1", "k3", "k4", "k5", "k6", "k7", "k8"])
        #expect(ChoixCourbes.cachees(cles: cles, prioritaires: ["k9"]) == 8)
        #expect(ChoixCourbes.cachees(cles: ["a"], prioritaires: ["a"]) == 0)
        #expect(ChoixCourbes.basculer(nil, "a") == "a" && ChoixCourbes.basculer("a", "a") == nil)
        #expect(ChoixCourbes.basculer("a", "b") == "b")
        // Une courbe en avant mais plus montree n'estompe pas les autres.
        #expect(ChoixCourbes.enAvant("g", parmi: ["a", "b"]) == nil)
        #expect(ChoixCourbes.enAvant("b", parmi: ["a", "b"]) == "b" && ChoixCourbes.enAvant(nil, parmi: ["a"]) == nil)
    }
}
