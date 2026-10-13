import Foundation
import Testing
@testable import MaillageCoeur

/// Le signal vu par la sonde, dans la fiche (polissage D, section 4.3) : le domaine et ses graduations, le releve sous
/// le pointeur, son etiquette, sans dependre de la langue ni du fuseau de la machine.
@Suite("Courbes : echelle et survol du signal")
struct EchelleSignalTests {
    /// Le domaine : un seul point (−67 donne −80 ... −60) ; des valeurs egales ; des valeurs etalees ; des valeurs deja
    /// sur une dizaine (−70 donne −80 ... −60, pas −70 ... −70). Toujours 10 dB au moins, et deux graduations au moins,
    /// sur les dizaines.
    @Test func domaine() throws {
        #expect(EchelleSignal.domaine([-67]) == -80 ... -60)
        #expect(EchelleSignal.domaine([-67, -67, -67]) == -80 ... -60)
        #expect(EchelleSignal.domaine([-91, -58]) == -100 ... -50)
        #expect(EchelleSignal.domaine([-70]) == -80 ... -60)
        #expect(EchelleSignal.domaine([-75]) == -80 ... -70, "a 5 dB d'une dizaine : elle-meme")
        #expect(EchelleSignal.domaine([-74.9]) == -80 ... -60)
        #expect(EchelleSignal.domaine([-65.1]) == -80 ... -60 && EchelleSignal.domaine([-64.9]) == -70 ... -50)
        #expect(EchelleSignal.domaine([]) == nil)
        #expect(EchelleSignal.graduations(-80 ... -60) == [-80, -70, -60])
        #expect(EchelleSignal.graduations(-100 ... -50) == [-100, -90, -80, -70, -60, -50])
        #expect(EchelleSignal.graduations(-80 ... -70) == [-80, -70])
        #expect(EchelleSignal.graduations(-75 ... -52) == [-70, -60], "la premiere : la dizaine au-dessus du bas")
        #expect(EchelleSignal.graduations(-74 ... -60) == [-70, -60])
        for v in stride(from: -100.0, through: -30, by: 0.7) {
            let d = try #require(EchelleSignal.domaine([v]))
            #expect(d.upperBound - d.lowerBound >= 10 && EchelleSignal.graduations(d).count >= 2 && d.contains(v), "\(v)")
        }
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func point(_ s: TimeInterval, _ v: Double = -67) -> PointCourbe {
        PointCourbe(date: t0.addingTimeInterval(s), valeur: v, troncon: 0)
    }

    /// Le seuil du survol : le plus petit de 2 % de la periode et de l'ecart qui coupe la courbe en troncons, repris du
    /// coeur (`ecartTroncon`) ; 20 min, 90 min et 6 h, car 2 % (28,8 min, 3 h 22, 14 h 24) est toujours plus large.
    @Test func seuil() {
        #expect(EchelleSignal.seuil(periode: .jour) == 1200)
        #expect(EchelleSignal.seuil(periode: .semaine) == 5400)
        #expect(EchelleSignal.seuil(periode: .mois) == 21_600)
        #expect(EchelleSignal.seuil(duree: 1000, ecart: 1200) == 20, "2 % de la periode, quand il est plus petit")
        #expect(EchelleSignal.seuil(duree: 86_400, ecart: 1200) == 1200, "l'ecart, quand il est plus petit")
    }

    /// L'ecart du seuil est celui qui coupe la courbe : un ecart de plus ouvre un troncon, un ecart egal non.
    @Test func ecartDuSeuilEstCeluiDesTroncons() {
        let base = Date(timeIntervalSince1970: 1_789_999_200) // un multiple de 30 min et de 2 h
        for periode in PeriodeCourbes.allCases {
            let ecart = periode.ecartTroncon
            let pas = periode.pas ?? 1
            let egal = CourbesNoeud.reduire([(base, -60), (base.addingTimeInterval(ecart), -60)], pas: periode.pas)
            let apres = base.addingTimeInterval(ecart + pas)
            let plus = CourbesNoeud.reduire([(base, -60), (apres, -60)], pas: periode.pas)
            #expect(egal.map(\.troncon) == [0, 0], "\(periode)")
            #expect(plus.map(\.troncon) == [0, 1], "\(periode)")
        }
    }

    /// Le releve sous le pointeur : le plus proche dans le temps ; a moins du seuil strictement, des deux cotes (sur
    /// 24 h, 1 200 s) ; au-dela, dans un trou, aucun ; sur 7 j, 5 400 s ; sur 30 j, 21 600 s. A egale distance, le plus
    /// ancien.
    @Test func plusProche() {
        let points = [Self.point(0, -60), Self.point(600, -61), Self.point(9000, -62)]
        func proche(_ s: TimeInterval, _ p: PeriodeCourbes) -> PointCourbe? {
            EchelleSignal.plusProche(points, de: Self.t0.addingTimeInterval(s), periode: p)
        }
        #expect(EchelleSignal.portee == 0.02)
        #expect(proche(200, .jour) == points[0])
        #expect(proche(400, .jour) == points[1])
        #expect(proche(300, .jour) == points[0], "a egale distance de deux releves, le plus ancien")
        #expect(proche(-1199, .jour) == points[0])
        #expect(proche(-1200, .jour) == nil, "a l'egalite du seuil : aucun")
        #expect(proche(-1201, .jour) == nil)
        #expect(proche(600 + 1199, .jour) == points[1])
        #expect(proche(600 + 1200, .jour) == nil)
        #expect(proche(600 + 1201, .jour) == nil, "un trou")
        #expect(proche(4800, .jour) == nil, "au milieu du trou")
        #expect(proche(9000 - 1199, .jour) == points[2])
        #expect(proche(9000 - 1200, .jour) == nil)
        #expect(proche(600 + 1201, .semaine) == points[1], "sur 7 j, le seuil est de 90 min")
        #expect(proche(-5399, .semaine) == points[0])
        #expect(proche(-5400, .semaine) == nil, "a l'egalite du seuil : aucun")
        #expect(proche(9000 + 5399, .semaine) == points[2])
        #expect(proche(9000 + 5401, .semaine) == nil, "2 % de 7 j (3 h 22) n'y change rien")
        #expect(proche(9000 + 21_599, .mois) == points[2])
        #expect(proche(9000 + 21_601, .mois) == nil)
        #expect(EchelleSignal.plusProche([], de: Self.t0, periode: .mois) == nil)
    }

    /// L'etiquette, en francais et en anglais, a Paris : la valeur arrondie avec le vrai signe moins, puis l'heure ; en
    /// 7 j et 30 j, le jour aussi. Et sa place : a gauche du trait dans la moitie droite du graphe.
    @Test func etiquette() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let p = Self.point(0, -66.6)
        let fr = Locale(identifier: "fr_FR"), en = Locale(identifier: "en_US")
        #expect(EchelleSignal.etiquette(p, periode: .jour, locale: fr, fuseau: paris) == "\u{2212}67 dBm · 16:13")
        #expect(EchelleSignal.etiquette(p, periode: .jour, locale: en, fuseau: paris) == "\u{2212}67 dBm · 4:13\u{202F}PM")
        #expect(EchelleSignal.etiquette(p, periode: .semaine, locale: fr, fuseau: paris) == "\u{2212}67 dBm · 21 sept. à 16:13")
        #expect(EchelleSignal.etiquette(p, periode: .mois, locale: en, fuseau: paris) == "\u{2212}67 dBm · Sep 21 at 4:13\u{202F}PM")
        #expect(EchelleSignal.etiquette(Self.point(0, 3), periode: .jour, locale: fr, fuseau: paris) == "3 dBm · 16:13")
        let fin = Self.t0.addingTimeInterval(100)
        #expect(EchelleSignal.aGauche(Self.t0.addingTimeInterval(51), debut: Self.t0, fin: fin))
        #expect(!EchelleSignal.aGauche(Self.t0.addingTimeInterval(50), debut: Self.t0, fin: fin))
        #expect(!EchelleSignal.aGauche(Self.t0, debut: Self.t0, fin: Self.t0))
    }

    /// L'arrondi de l'etiquette, des deux cotes de .5 : au plus proche, un demi vers l'exterieur de zero ; le signe
    /// moins d'apres l'entier arrondi (un « −0 » n'existe pas).
    @Test func arrondiDeLEtiquette() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        func valeur(_ v: Double) -> String {
            let fr = Locale(identifier: "fr_FR")
            let e = EchelleSignal.etiquette(Self.point(0, v), periode: .jour, locale: fr, fuseau: paris)
            return String(e.prefix { $0 != "·" }).trimmingCharacters(in: .whitespaces)
        }
        #expect(valeur(-66.4) == "\u{2212}66 dBm")
        #expect(valeur(-66.5) == "\u{2212}67 dBm")
        #expect(valeur(-66.6) == "\u{2212}67 dBm")
        #expect(valeur(-0.4) == "0 dBm", "pas de « −0 »")
        #expect(valeur(0.4) == "0 dBm")
        #expect(valeur(-0.5) == "\u{2212}1 dBm")
        #expect(valeur(3.4) == "3 dBm")
        #expect(valeur(3.5) == "4 dBm")
    }
}
