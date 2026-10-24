import AppKit
import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// La cadence de l'horloge de la vue par pieces (performance, piste 1 du 25/10) : la rotation lente seule ne demande que
/// 30 images par seconde (un tour en 120 s, 0,1 degre par image) ; des qu'un geste commence, ou qu'un vol, un envol, un
/// fondu, un glissement de disposition, une transition, l'elan d'un geste ou un survol qui change l'affichage est en
/// cours, la vue reprend la pleine cadence de l'ecran, jusqu'a la fin de ce mouvement. La rotation reste continue : son
/// angle suit le temps, pas le nombre d'images.
@MainActor
@Suite("Vue par pieces : 30 images par seconde pendant la seule rotation lente")
struct CadenceHorlogeTests {
    /// La decision, pure : rien ne bouge (ou la fenetre n'est pas vue) -> pause ; la rotation lente seule -> 30 images par
    /// seconde ; tout autre mouvement -> pleine cadence.
    @Test func decision() {
        #expect(CadenceHorloge.decider(enMarche: false, rotationSeule: false) == .pause, "rien ne bouge")
        #expect(CadenceHorloge.decider(enMarche: false, rotationSeule: true) == .pause, "fenetre pas vue : en pause")
        #expect(CadenceHorloge.decider(enMarche: true, rotationSeule: true) == .plafonnee)
        #expect(CadenceHorloge.decider(enMarche: true, rotationSeule: false) == .pleine)
        #expect(CadenceHorloge.plafonnee.intervalle == 1.0 / 30)
        #expect(CadenceHorloge.pleine.intervalle == nil, "pleine cadence : celle de l'ecran")
        #expect(CadenceHorloge.pause.intervalle == nil)
    }

    /// Un moteur en 3D sur la demo, rotation lente, au calme : plus rien d'autre ne bouge a l'heure rendue (au-dela des
    /// 0,6 s d'activite qui suivent toute scene posee).
    static func calme() throws -> (MoteurPieces, Double) {
        let (m, _) = try GlissementTests.moteur(troisD: true)
        m.fige = false
        #expect(m.rotation && m.troisD && m.t == 1)
        return (m, MoteurPieces.maintenant() + 10)
    }

    /// Rotation lente seule : 30 images par seconde.
    @Test func rotationSeule() throws {
        let (m, heure) = try Self.calme()
        #expect(m.cadenceVoulue(heure) == .plafonnee)
        m.rotation = false
        #expect(m.cadenceVoulue(heure) != .plafonnee, "sans rotation lente, la cadence n'est jamais plafonnee")
    }

    /// Chaque mouvement qui part, en plus de la rotation lente, donne la pleine cadence. Chacun est pose par le vrai
    /// chemin du moteur quand il y en a un (glisser, survol, isoler, bascule, scene qui glisse).
    @Test(arguments: ["glisser", "option-glisser", "vol", "envol", "fondu", "glissement des plateaux", "transition",
                      "elan de rotation", "zoom amorti", "pincement", "survol qui change", "activite recente",
                      "scene qui attend", "focus qui s'estompe", "marges qui glissent"])
    func pleineCadence(_ nom: String) throws {
        let (m, heure) = try Self.calme()
        #expect(m.cadenceVoulue(heure) == .plafonnee, "avant : la rotation seule")
        let p = CGPoint(x: 600, y: 450)
        switch nom {
        case "glisser": m.glisser(p, depart: p)
        case "option-glisser": m.glisser(p, depart: p, option: true)
        case "vol": m.isoler(0)
        case "envol": m.basculer(troisD: false)
        case "fondu":
            m.fondu = MoteurPieces.Fondu(debut: MoteurPieces.maintenant(), arrivee: 0)
        case "glissement des plateaux":
            m.glissementPlateaux = MoteurPieces.GlissementPlateaux(depart: m.geometrie, debut: MoteurPieces.maintenant(),
                                                                   duree2D: 1, duree3D: 1)
        case "transition":
            m.installerMaintenant(try GlissementTests.demo("Prise salon", dans: "Chambre"))
        case "elan de rotation": m.rotationEnAttente = SIMD2(0.2, 0)
        case "zoom amorti": m.zoomEnAttente = 0.2
        case "pincement": m.dernierPincement = 0.8
        case "survol qui change":
            let d = try #require(m.projetee?.disques.first)
            m.survoler(d.centre)
            #expect(m.survol != nil, "le survol a change l'affichage")
        case "activite recente": m.reveiller()
        case "scene qui attend":
            m.attente = try GlissementTests.demo("Prise salon", dans: "Cuisine")
        case "focus qui s'estompe":
            m.selection = m.scene?.noeuds.first?.id
        case "marges qui glissent":
            m.marges = (140, 50)
            _ = m.margesDuCadre(MoteurPieces.maintenant())
        default: Issue.record("cas inconnu : \(nom)")
        }
        let maintenant = MoteurPieces.maintenant()
        // Juste apres le depart du mouvement (et, pour l'activite, dans les 0,6 s qui la suivent) : pleine cadence.
        #expect(m.cadenceVoulue(maintenant + 0.05) == .pleine, "\(nom) : pleine cadence")
        #expect(m.cadenceVoulue(maintenant + 0.05) != .plafonnee)
    }

    /// L'envie d'un nom de changer de place est un delai, pas un mouvement : la rotation lente en fait naitre sans cesse, et
    /// elle ne rend pas la pleine cadence ; elle tient seulement l'horloge (`doitContinuer`).
    @Test func envieDeNom() throws {
        let (m, heure) = try Self.calme()
        let i = try #require(m.etiquettes.indices.first)
        m.etiquettes[i].envie = 0.4
        #expect(m.cadenceVoulue(heure) == .plafonnee)
        m.rotation = false
        #expect(m.doitContinuer(heure), "un nom qui attend sa place tient l'horloge")
    }

    /// Un survol qui ne change rien a l'affichage (le pointeur bouge sur le fond) laisse la rotation seule a 30 images par
    /// seconde.
    @Test func survolSansEffet() throws {
        let (m, heure) = try Self.calme()
        m.survoler(CGPoint(x: 3, y: 3))
        m.survoler(CGPoint(x: 5, y: 9))
        #expect(m.survol == nil)
        #expect(m.cadenceVoulue(heure) == .plafonnee)
    }

    /// Quand le mouvement finit, la cadence revient a 30 images par seconde : la fin d'un vol (la piece isolee tourne
    /// toujours), celle d'un glisser, celle de l'activite (0,6 s).
    @Test func retourAuxTrenteImages() throws {
        let (m, heure) = try Self.calme()
        m.isoler(0)
        #expect(m.cadenceVoulue(MoteurPieces.maintenant() + 0.05) == .pleine)
        // Le vol et l'isolement vont a leur terme, par l'horloge du moteur.
        var now = m.debutVol + 0.1
        for _ in 0..<80 {
            m.avancer(now)
            now += 0.1
        }
        #expect(m.vol == nil && m.s == m.sCible)
        #expect(m.cadenceVoulue(now + 1) == .plafonnee, "le vol fini : de nouveau 30 images par seconde")

        let (g, h2) = try Self.calme()
        let p = CGPoint(x: 600, y: 450)
        g.glisser(p, depart: p)
        #expect(g.cadenceVoulue(h2) == .pleine, "un geste tenu : pleine cadence, meme immobile")
        g.abandonnerGeste()
        #expect(g.cadenceVoulue(MoteurPieces.maintenant() + 0.2) == .pleine, "0,6 s d'activite apres le geste")
        #expect(g.cadenceVoulue(h2 + 1) == .plafonnee, "le geste fini : 30 images par seconde")
        _ = heure
    }

    /// La rotation reste continue : son angle suit le temps, pas le nombre d'images. 1 s a 60 images par seconde et 1 s a
    /// 30 donnent le meme azimut.
    @Test func rotationContinue() throws {
        let (a, _) = try Self.calme()
        let (b, _) = try Self.calme()
        a.instant = nil
        b.instant = nil
        let depart = a.orbite.azimut
        #expect(b.orbite.azimut == depart)
        let t0 = MoteurPieces.maintenant() + 10
        for k in 0...60 { a.avancer(t0 + Double(k) / 60) }
        for k in 0...30 { b.avancer(t0 + Double(k) / 30) }
        #expect(a.orbite.azimut < depart, "la rotation tourne")
        #expect(abs(a.orbite.azimut - b.orbite.azimut) < 1e-9, "meme angle a 60 et a 30 images par seconde")
        // Un tour en CameraScene.dureeTour : 1 s tourne de 2 pi / dureeTour.
        #expect(abs((depart - a.orbite.azimut) - 2 * .pi / CameraScene.dureeTour) < 1e-9)
    }

    /// Le moteur garde la cadence a jour pour la vue (`cadence`, lue par la `TimelineView`) : plafonnee au calme, pleine des
    /// l'appui d'un glisser, sans attendre l'image suivante, en pause quand rien ne bouge ou que la fenetre n'est pas vue.
    @Test func cadenceDeLaVue() throws {
        let (m, heure) = try Self.calme()
        m.majCadence(heure)
        #expect(m.anime && m.cadence == .plafonnee && m.rotationSeule)
        let p = CGPoint(x: 600, y: 450)
        m.glisser(p, depart: p)
        #expect(m.cadence == .pleine, "l'appui : pleine cadence tout de suite")
        m.abandonnerGeste()
        m.majCadence(heure + 5)
        #expect(m.cadence == .plafonnee, "le geste fini : de nouveau plafonnee")
        m.reveiller()
        #expect(m.cadence == .pleine, "un reveil (survol, bouton) : pleine cadence tout de suite")
        m.majCadence(heure + 20)
        #expect(m.cadence == .plafonnee)
        m.regler(visibilite: VisibiliteFenetre(cachee: true))
        #expect(m.cadence == .pause, "fenetre cachee : aucune image")
        m.regler(visibilite: VisibiliteFenetre())
        m.anime = false
        #expect(m.cadence == .pause, "rien ne bouge : en pause")
    }

    /// Le rendu rapporte la cadence : passee la fenetre d'activite, une image qui trouve la rotation seule la plafonne ;
    /// un mouvement la rend a la pleine cadence.
    @Test(.timeLimit(.minutes(1))) func lImageMetLaCadenceAJour() async throws {
        let (m, _) = try Self.calme()
        m.fige = false
        m.reveiller()
        try await Task.sleep(for: .milliseconds(750))
        MoteurPiecesTests.dessiner(m)
        try await MoteurPiecesTests.attendre { m.rotationSeule }
        #expect(m.cadence == .plafonnee, "la rotation seule, vue par l'image")
        m.rotationEnAttente = SIMD2(0.3, 0)
        MoteurPiecesTests.dessiner(m)
        try await MoteurPiecesTests.attendre { !m.rotationSeule }
        #expect(m.cadence == .pleine, "un elan, vu par l'image")
    }

    /// Les images dessinees pendant `duree`.
    static func images(_ moteur: MoteurPieces, pendant duree: Duration = .seconds(1)) async throws -> Int {
        let avant = moteur.imagesDessinees
        try await Task.sleep(for: duree)
        return moteur.imagesDessinees - avant
    }

    /// Attend (10 s au plus) que la cadence du moteur soit `cadence`.
    static func attendre(_ cadence: CadenceHorloge, _ moteur: MoteurPieces) async throws {
        var n = 0
        while moteur.cadence != cadence && n < 1000 {
            try await Task.sleep(for: .milliseconds(10))
            n += 1
        }
    }

    /// Attend (5 s au plus) que la fenetre de la vue soit vue (`VisibiliteFenetre.vue`).
    static func attendreFenetreVue(_ moteur: MoteurPieces) async throws {
        var n = 0
        while !moteur.visibilite.vue && n < 500 {
            try await Task.sleep(for: .milliseconds(10))
            n += 1
        }
    }

    /// Les images dessinees pendant une seconde de rotation lente seule, une fois la cadence plafonnee. Les suites de
    /// fenetre se partagent le centre de notifications de `NSWorkspace` (`ecransEteints` y envoie les ecrans eteints, puis
    /// rallumes) et la machine : une seconde troublee est mesuree de nouveau (4 essais).
    static func imagesDeLaRotationSeule(_ moteur: MoteurPieces) async throws -> Int {
        var images = 0
        for _ in 0..<4 {
            try await attendre(.plafonnee, moteur)
            try await Task.sleep(for: .milliseconds(300))
            images = try await Self.images(moteur)
            if moteur.cadence == .plafonnee && images >= 8 && images <= 36 { break }
        }
        return images
    }
}

/// Les fenetres reelles de ces essais se partagent le centre de notifications de `NSWorkspace` (`ecransEteints` y envoie
/// les ecrans eteints, puis rallumes) : la suite de l'horloge est serialisee, et cet essai en est.
extension HorlogeFenetreTests {
    /// La vraie fenetre, hors ecran, en 3D : la rotation lente seule dessine au plus 30 images par seconde (plus une
    /// marge de mesure) ; un glisser en mouvement, la cadence de l'ecran ; le glisser fini, de nouveau 30 images par
    /// seconde.
    @Test(.timeLimit(.minutes(2))) func laTimelineSuitLaCadence() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (fenetre, moteur) = try await HorlogeFenetreTests.fenetre3D(p)
        defer { FenetrePiecesTests.fermer(fenetre) }
        // AppKit juge cachee (`occlusionState`) une fenetre hors ecran quand les ecrans du Mac sont en veille ou le Mac
        // verrouille : elle ne dessine alors rien, par construction (`HorlogeFenetreTests`). La cadence est verifiee, plus
        // haut, sur le moteur ; cet essai-ci n'a rien a mesurer.
        try await CadenceHorlogeTests.attendreFenetreVue(moteur)
        guard moteur.visibilite.vue else { return }
        let seule = try await CadenceHorlogeTests.imagesDeLaRotationSeule(moteur)
        #expect(moteur.cadence == .plafonnee)
        #expect(seule >= 8 && seule <= 36, "rotation lente seule : au plus 30 images par seconde (\(seule))")

        // Un glisser du fond, le pointeur en mouvement pendant une seconde.
        let p0 = CGPoint(x: 600, y: 450)
        moteur.glisser(p0, depart: p0)
        #expect(moteur.cadence != .plafonnee, "l'appui : pleine cadence tout de suite")
        let avant = moteur.imagesDessinees
        for k in 1...60 {
            moteur.glisser(CGPoint(x: 600 + Double(k) * 3, y: 450), depart: p0)
            try await Task.sleep(for: .milliseconds(16))
        }
        let pleine = moteur.imagesDessinees - avant
        #expect(pleine > seule + 8, "geste en mouvement : la cadence de l'ecran (\(pleine) contre \(seule))")

        moteur.abandonnerGeste()
        // L'elan du geste (la rotation amortie) tient la pleine cadence jusqu'a son terme, quelques secondes.
        let retour = try await CadenceHorlogeTests.imagesDeLaRotationSeule(moteur)
        #expect(moteur.cadence == .plafonnee && retour >= 8 && retour <= 36, "retour a 30 images par seconde (\(retour))")
    }
}
