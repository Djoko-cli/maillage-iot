import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Courbes d'un noeud tirees de l'historique")
struct CourbesNoeudTests {
    /// Debut d'un pas de 30 min et de 2 h.
    static let t0 = Date(timeIntervalSince1970: 1_790_006_400)
    static let a0 = "E0000000000000A0"
    static let a1 = "E0000000000000A1"
    static let b1 = "E0000000000000B1"

    /// Releve a `minutes` de t0 (valeurs inventees), de la partition `partition` : les routeurs 0 (sans ExtMac si
    /// `sansExt0`, sinon a0) et 1 (sans ExtMac si `sansExt1`, sinon a1) et leur lien, de qualite `q` de 0 vers 1 et 3
    /// de 1 vers 0 ; l'enfant b1 sous `parent` ; la sonde sous `parentSonde`, qui entend le routeur 0 a `rssi`.
    static func releve(_ minutes: Double, q: Int = 3, parent: Int = 0, qualiteEnfant: Int? = 3, parentSonde: Int = 0,
                       rssi: Int = -60, sansExt0: Bool = false, sansExt1: Bool = false,
                       partition: String = "0000000A") -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(minutes * 60), partition: partition,
                       routeurs: [.init(id: 0, extMac: sansExt0 ? nil : a0), .init(id: 1, extMac: sansExt1 ? nil : a1)],
                       liens: [LienRadio(a: 0, b: 1, qualiteAB: q, qualiteBA: 3)],
                       enfants: [.init(extMac: b1, parent: parent, qualite: qualiteEnfant)],
                       signaux: [SignalSonde(routeur: 0, rssi: rssi)], parentSonde: parentSonde)
    }

    static func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// Routeur : la qualite de son lien avec chaque voisin (la moins bonne des deux sens), celle du lien de chacun de ses
    /// enfants vers lui, et le signal que la sonde en recoit, a chaque releve de la periode ; ses liens radio passent
    /// avant ses enfants dans les prioritaires.
    @Test func routeur() {
        let releves = [Self.releve(0, q: 3, rssi: -60), Self.releve(5, q: 2, rssi: -65), Self.releve(10, q: 1, rssi: -70)]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(15))
        #expect(c.courbe(Self.a1) == CourbeLien(id: Self.a1, points: [
            PointCourbe(date: Self.minutes(0), valeur: 3, troncon: 0), PointCourbe(date: Self.minutes(5), valeur: 2, troncon: 0),
            PointCourbe(date: Self.minutes(10), valeur: 1, troncon: 0)]))
        #expect(c.courbe(Self.b1)?.points.map(\.valeur) == [3, 3, 3], "son enfant b1")
        #expect(c.liens.map(\.id).sorted() == [Self.a1, Self.b1].sorted() && c.courbe("absent") == nil)
        #expect(c.prioritaires == [Self.a1, Self.b1], "ses liens radio, puis ses enfants")
        #expect(c.signal.map(\.valeur) == [-60, -65, -70])
        #expect(c.parents.isEmpty)
        #expect(c.debut == Self.minutes(15).addingTimeInterval(-24 * 3600))
        #expect(CourbesNoeud(cle: Self.a1, releves: releves, periode: .jour, fin: Self.minutes(15)).signal.isEmpty,
                "la sonde n'entend pas le routeur 1")
    }

    /// Carte radio seulement : le lien entre deux routeurs qui annoncent TREL n'a pas de courbe ; un seul ne suffit pas.
    @Test func liensTrelSansCourbe() {
        let releves = [Self.releve(0), Self.releve(5)]
        #expect(CourbesNoeud(cle: Self.a0, releves: releves, cles: ClesHistorique(releves: releves), periode: .jour,
                             fin: Self.minutes(15), trel: [Self.a0, Self.a1]).courbe(Self.a1) == nil)
        #expect(CourbesNoeud(cle: Self.a0, releves: releves, cles: ClesHistorique(releves: releves), periode: .jour,
                             fin: Self.minutes(15), trel: [Self.a0]).courbe(Self.a1) != nil)
    }

    /// Enfant : la qualite du lien vers son parent, quel qu'il soit (inconnue sous un routeur muet :
    /// pas de point), et ses changements de parent, a la date du premier releve sous le nouveau.
    @Test func enfant() {
        let releves = [Self.releve(0), Self.releve(5), Self.releve(10, parent: 1, qualiteEnfant: 2),
                       Self.releve(15, parent: 1, qualiteEnfant: nil)]
        let c = CourbesNoeud(cle: Self.b1, releves: releves, periode: .jour, fin: Self.minutes(20))
        #expect(c.liens.map(\.id) == [CourbesNoeud.cleParent] && c.prioritaires == [CourbesNoeud.cleParent])
        #expect(c.liens.first?.points.map(\.valeur) == [3, 3, 2])
        #expect(c.parents == [ChangementParent(date: Self.minutes(10), parent: Self.a1)])
        #expect(c.signal.isEmpty)
        #expect(!c.estVide)
        #expect(CourbesNoeud(cle: "E0000000000000FF", releves: releves, periode: .jour, fin: Self.minutes(20)).estVide)
    }

    /// Changements de parent de la sonde (sur la courbe du signal d'un routeur) ; un routeur sans
    /// ExtMac se suit par son RLOC16.
    @Test func sondeEtRouteurSansExtMac() {
        let releves = [Self.releve(0, parentSonde: 0, sansExt1: true), Self.releve(5, parentSonde: 0, sansExt1: true),
                       Self.releve(10, parentSonde: 1, sansExt1: true)]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(15))
        #expect(c.parentsSonde == [ChangementParent(date: Self.minutes(10), parent: "rloc:0400")])
        #expect(c.liens.map(\.id) == [Self.b1, "rloc:0400"], "son enfant b1, puis le routeur 1 par son RLOC16")
        let r1 = CourbesNoeud(cle: "rloc:0400", releves: releves, periode: .jour, fin: Self.minutes(15))
        #expect(r1.liens.map(\.id) == [Self.a0])
    }

    /// Un routeur identifie plus tard (verification du 05/10) : ses releves sans ExtMac prennent celle du suivant le plus
    /// proche (`ClesHistorique`), sur toute la liste et non la seule periode : ses liens d'avant rejoignent sa courbe, sans
    /// doublon « rloc », et sa fiche montre ses points d'avant son identification. Le meme identifiant dans une autre
    /// partition reste a part.
    @Test func routeurIdentifiePlusTard() {
        let releves = [Self.releve(0, q: 1, rssi: -70, sansExt0: true, sansExt1: true),
                       Self.releve(5, q: 2, rssi: -65, sansExt0: true, sansExt1: true),
                       Self.releve(10, q: 3, rssi: -60),
                       Self.releve(15, q: 2, sansExt1: true, partition: "0000000B")]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(10))
        #expect(c.liens.map(\.id) == [Self.a1, Self.b1], "son voisin, puis son enfant b1")
        #expect(c.liens.first?.points.map(\.valeur) == [1, 2, 3])
        #expect(c.signal.map(\.valeur) == [-70, -65, -60], "les points d'avant son identification")
        let avant = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(7))
        #expect(avant.liens.map(\.id) == [Self.a1, Self.b1] && avant.signal.map(\.valeur) == [-70, -65],
                "identifie apres la fin de la periode")
        #expect(CourbesNoeud(cle: Self.a1, releves: releves, periode: .jour, fin: Self.minutes(10)).liens.map(\.id) == [Self.a0])
        #expect(CourbesNoeud(cle: "rloc:0000", releves: releves, periode: .jour, fin: Self.minutes(10)).estVide)
        let b = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(15))
        #expect(b.liens.map(\.id) == [Self.a1, Self.b1, "rloc:0400"], "l'identifiant 1 de l'autre partition")
    }

    /// Un routeur identifie seulement avant : ses releves suivants, sans ExtMac, prennent celle du precedent le plus
    /// proche.
    @Test func routeurIdentifieSeulementAvant() {
        let releves = [Self.releve(0, q: 3), Self.releve(5, q: 2, sansExt1: true), Self.releve(10, q: 1, sansExt1: true)]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(10))
        #expect(c.liens.map(\.id) == [Self.a1, Self.b1])
        #expect(c.liens.first?.points.map(\.valeur) == [3, 2, 1])
    }

    /// Les parents, de la sonde et d'un enfant, se nomment par la meme cle : un parent identifie en cours de route n'est
    /// pas un changement de parent ; un vrai changement, si.
    @Test func parentsIdentifiesEnCoursDeRoute() {
        let releves = [Self.releve(0, parent: 1, parentSonde: 1, sansExt1: true),
                       Self.releve(5, parent: 1, parentSonde: 1, sansExt1: true),
                       Self.releve(10, parent: 1, parentSonde: 1),
                       Self.releve(15, parent: 0, parentSonde: 0)]
        let enfant = CourbesNoeud(cle: Self.b1, releves: releves, periode: .jour, fin: Self.minutes(10))
        #expect(enfant.parents.isEmpty)
        #expect(CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(10)).parentsSonde.isEmpty)
        let tout = CourbesNoeud(cle: Self.b1, releves: releves, periode: .jour, fin: Self.minutes(15))
        #expect(tout.parents == [ChangementParent(date: Self.minutes(15), parent: Self.a0)])
        #expect(CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(15)).parentsSonde
                == [ChangementParent(date: Self.minutes(15), parent: Self.a0)])
        let avant = CourbesNoeud(cle: Self.b1, releves: Array(releves.prefix(2)) + [Self.releve(10, parent: 0, parentSonde: 0)],
                                 periode: .jour, fin: Self.minutes(10))
        #expect(avant.parents == [ChangementParent(date: Self.minutes(10), parent: Self.a0)],
                "le routeur 1, jamais identifie, reste rloc : le passage au routeur 0 est un changement")
    }

    /// 7 j : la moyenne de chaque pas de 30 min ; un trou de plus de trois pas ouvre un troncon.
    /// 24 h : chaque releve ; un trou de plus de 20 min ouvre un troncon. Hors periode : rien.
    @Test func pasEtTroncons() {
        let semaine = [0.0, 5, 10, 15, 20, 25].enumerated().map { Self.releve($1, q: $0 < 3 ? 3 : 2) }
            + [Self.releve(210, q: 3)]
        let c = CourbesNoeud(cle: Self.a0, releves: semaine, periode: .semaine, fin: Self.minutes(240))
        #expect(c.liens.first?.points == [PointCourbe(date: Self.minutes(0), valeur: 2.5, troncon: 0),
                                          PointCourbe(date: Self.minutes(210), valeur: 3, troncon: 1)])
        let jour = [Self.releve(0), Self.releve(5), Self.releve(30), Self.releve(35)]
        let d = CourbesNoeud(cle: Self.a0, releves: jour, periode: .jour, fin: Self.minutes(40))
        #expect(d.signal.map(\.troncon) == [0, 0, 1, 1])
        let tard = CourbesNoeud(cle: Self.a0, releves: jour, periode: .jour, fin: Self.minutes(20 + 24 * 60))
        #expect(tard.signal.map(\.date) == [Self.minutes(30), Self.minutes(35)], "24 h avant la fin")
    }

    /// Bornes de la periode (les deux comprises : un releve plus recent que la fiche, qui est a la
    /// minute, n'en fait pas partie), seuils des troncons (20 min pile ne coupent pas, 20 min et 1 s
    /// coupent ; trois pas ne coupent pas, quatre oui ; chaque trou ouvre un troncon de plus), 30 j.
    @Test func bornesSeuilsEtMois() {
        let r = [Self.releve(0), Self.releve(10), Self.releve(11)]
        #expect(CourbesNoeud(cle: Self.a0, releves: r, periode: .jour, fin: Self.minutes(10)).signal.map(\.date)
                == [Self.minutes(0), Self.minutes(10)], "fin comprise, plus recent exclu")
        #expect(CourbesNoeud(cle: Self.a0, releves: r, periode: .jour, fin: Self.minutes(24 * 60)).signal.map(\.date)
                == [Self.minutes(0), Self.minutes(10), Self.minutes(11)], "debut compris")
        let trous = [Self.releve(0), Self.releve(20), Self.releve(40 + 1.0 / 60), Self.releve(70)]
        #expect(CourbesNoeud(cle: Self.a0, releves: trous, periode: .jour, fin: Self.minutes(80)).signal.map(\.troncon)
                == [0, 0, 1, 2], "seuil de 20 min")
        let pas = [Self.releve(0), Self.releve(90), Self.releve(210)]
        #expect(CourbesNoeud(cle: Self.a0, releves: pas, periode: .semaine, fin: Self.minutes(240)).signal.map(\.troncon)
                == [0, 0, 1], "seuil de trois pas")
        let mois = [Self.releve(0, rssi: -60), Self.releve(119, rssi: -70), Self.releve(120, rssi: -80)]
        let m = CourbesNoeud(cle: Self.a0, releves: mois, periode: .mois, fin: Self.minutes(240))
        #expect(m.signal == [PointCourbe(date: Self.minutes(0), valeur: -65, troncon: 0),
                             PointCourbe(date: Self.minutes(120), valeur: -80, troncon: 0)], "pas de 2 h")
        #expect(m.debut == Self.minutes(240).addingTimeInterval(-30 * 24 * 3600), "30 j")
        #expect(CourbesNoeud(cle: Self.a0, releves: mois, periode: .semaine, fin: Self.minutes(240)).debut
                == Self.minutes(240).addingTimeInterval(-7 * 24 * 3600), "7 j")
    }

    /// Un lien sans qualite des deux cotes n'a pas de point (le signal suffit a une fiche) ; un enfant
    /// sous un routeur muet n'a pas de courbe, et ses changements de parent suffisent a sa fiche.
    @Test func sansQualite() {
        let muet = ReleveMaillage(date: Self.t0, partition: "0000000A",
                                  routeurs: [.init(id: 0, extMac: Self.a0), .init(id: 1, extMac: Self.a1)],
                                  liens: [LienRadio(a: 0, b: 1, qualiteAB: nil, qualiteBA: nil)],
                                  enfants: [], signaux: [SignalSonde(routeur: 0, rssi: -60)], parentSonde: nil)
        let c = CourbesNoeud(cle: Self.a0, releves: [muet], periode: .jour, fin: Self.minutes(5))
        #expect(c.liens.isEmpty, "pas de point sans qualite")
        #expect(!c.estVide, "le signal suffit")
        let e = CourbesNoeud(cle: Self.b1, releves: [Self.releve(0, parent: 0, qualiteEnfant: nil),
                                                     Self.releve(5, parent: 1, qualiteEnfant: nil)],
                             periode: .jour, fin: Self.minutes(10))
        #expect(e.liens.isEmpty, "qualite inconnue : pas de courbe")
        #expect(!e.estVide, "le changement de parent suffit")
    }

    /// Les prioritaires d'un routeur, chacun du plus faible au meilleur en moyenne : deux voisins, puis deux enfants.
    @Test func prioritairesDuPlusFaible() {
        let r = ReleveMaillage(date: Self.t0, partition: "0000000A",
                               routeurs: [.init(id: 0, extMac: Self.a0), .init(id: 1, extMac: Self.a1),
                                          .init(id: 2, extMac: "E0000000000000A2")],
                               liens: [LienRadio(a: 0, b: 1, qualiteAB: 3, qualiteBA: 3),
                                       LienRadio(a: 0, b: 2, qualiteAB: 1, qualiteBA: 1)],
                               enfants: [.init(extMac: Self.b1, parent: 0, qualite: 3),
                                         .init(extMac: "E0000000000000B2", parent: 0, qualite: 2)],
                               signaux: [], parentSonde: nil)
        let c = CourbesNoeud(cle: Self.a0, releves: [r], periode: .jour, fin: Self.minutes(5))
        #expect(c.prioritaires == ["E0000000000000A2", Self.a1, "E0000000000000B2", Self.b1])
    }

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
