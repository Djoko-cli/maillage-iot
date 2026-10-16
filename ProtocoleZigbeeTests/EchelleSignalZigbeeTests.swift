import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Le signal vu par la sonde Zigbee, en LQI : l'instance `EchelleSignal.lqi` du protocole (le coeur teste ses reglages
/// avec une echelle d'essai de memes valeurs, `EchelleSignalTests`). Le domaine et ses graduations, l'etiquette du
/// releve sous le pointeur, sans dependre de la langue ni du fuseau de la machine.
@Suite("Courbes Zigbee : echelle LQI et etiquette du signal")
struct EchelleSignalZigbeeTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func point(_ s: TimeInterval, _ v: Double = 182) -> PointCourbe {
        PointCourbe(date: t0.addingTimeInterval(s), valeur: v, troncon: 0)
    }

    /// Les reglages de Zigbee : « LQI » devant la valeur, un pas de 50, une marge de 10, des bornes de 0 a 255.
    @Test func reglagesDeZigbee() {
        let e = EchelleSignal.lqi
        #expect(e.unite == "LQI" && e.uniteAvant && e.pas == 50 && e.marge == 10)
        #expect(e.bornes == 0 ... 255 && e.domaineParDefaut == 0 ... 255)
    }

    /// Le domaine, en LQI : un seul point (182 donne 150 ... 200) ; des valeurs egales ; des valeurs etalees ; des
    /// valeurs deja sur un multiple de 50 ; toujours dans 0 ... 255. Toujours 50 de haut au moins, et deux graduations
    /// au moins, sur les multiples de 50.
    @Test func domaine() throws {
        let lqi = EchelleSignal.lqi, bornes = try #require(lqi.bornes)
        #expect(lqi.domaine([182]) == 150 ... 200)
        #expect(lqi.domaine([182, 182, 182]) == 150 ... 200)
        #expect(lqi.domaine([61, 230]) == 50 ... 250)
        #expect(lqi.domaine([150]) == 2 * lqi.pas ... 200, "a 10 d'un multiple : au-dela")
        #expect(lqi.domaine([5]) == 0 ... 50, "jamais sous 0")
        #expect(lqi.domaine([250]) == 200 ... 255, "jamais au-dessus de 255")
        #expect(lqi.domaine([]) == nil)
        #expect(lqi.graduations(150 ... 200) == [150, 200])
        #expect(lqi.graduations(50 ... 250) == [50, 100, 150, 200, 250])
        #expect(lqi.graduations(0 ... 255) == [0, 50, 100, 150, 200, 250])
        #expect(lqi.graduations(120 ... 210) == [150, 200], "la premiere : le multiple au-dessus du bas")
        for v in stride(from: 0.0, through: 255, by: 3.7) {
            let d = try #require(lqi.domaine([v]))
            #expect(d.upperBound - d.lowerBound >= 50 && lqi.graduations(d).count >= 2 && d.contains(v)
                    && bornes.contains(d.lowerBound) && bornes.contains(d.upperBound), "\(v)")
        }
    }

    /// L'etiquette, en francais et en anglais, a Paris : « LQI », la valeur arrondie, puis l'heure ; en 7 j et 30 j,
    /// le jour aussi.
    @Test func etiquette() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let p = Self.point(0, 181.6)
        let fr = Locale(identifier: "fr_FR"), en = Locale(identifier: "en_US")
        let e = EchelleSignal.lqi
        #expect(e.etiquette(p, periode: .jour, locale: fr, fuseau: paris) == "LQI 182 · 16:13")
        #expect(e.etiquette(p, periode: .jour, locale: en, fuseau: paris) == "LQI 182 · 4:13\u{202F}PM")
        #expect(e.etiquette(p, periode: .semaine, locale: fr, fuseau: paris) == "LQI 182 · 21 sept. à 16:13")
        #expect(e.etiquette(p, periode: .mois, locale: en, fuseau: paris) == "LQI 182 · Sep 21 at 4:13\u{202F}PM")
    }

    /// L'arrondi de l'etiquette, des deux cotes de .5 : au plus proche, un demi vers le haut (une moyenne de LQI).
    @Test func arrondiDeLEtiquette() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        func valeur(_ v: Double) -> String {
            let fr = Locale(identifier: "fr_FR")
            let e = EchelleSignal.lqi.etiquette(Self.point(0, v), periode: .jour, locale: fr, fuseau: paris)
            return String(e.prefix { $0 != "·" }).trimmingCharacters(in: .whitespaces)
        }
        #expect(valeur(66.4) == "LQI 66")
        #expect(valeur(66.5) == "LQI 67")
        #expect(valeur(0.4) == "LQI 0")
        #expect(valeur(254.6) == "LQI 255")
    }

    /// La bande d'un LQI : celle de la qualite 0 a 3 que `QualiteLien` en tire, pour les 256 valeurs ; la qualite 0
    /// (sous 50) est un lien faible. Les seuils de l'echelle sont ceux de `QualiteLien` (une seule source).
    @Test func bandeDUnLQI() {
        let e = EchelleSignal.lqi
        for lqi in 0 ... 255 {
            #expect(e.bande(Double(lqi)) == BandeQualite(QualiteLien.depuis(lqi: lqi) as Int), "LQI \(lqi)")
        }
        #expect(e.bande(182) == .bonne && e.bande(130) == .moyenne && e.bande(60) == .faible && e.bande(10) == .faible)
        #expect(e.bandes == SeuilsBandes(bonne: Double(QualiteLien.seuilBonne), moyenne: Double(QualiteLien.seuilMoyenne)))
    }
}
