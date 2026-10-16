import AppKit
import Foundation
import MaillageCoeur
import ProtocoleThread
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// Mesures de la vue par pieces, hors ecran (critere 6.1 de la spec de la fusion : l'ouverture de la vue et la fluidite du
/// zoom, pour la demo de Thread seule, a comparer a l'etape 1, et pour la demo combinee). Jamais une assertion de duree :
/// les machines different ; le test ne verifie que
/// ce qui rend la mesure valable (la scene est dessinee, la camera a bien bouge) et ecrit ses medianes sur une ligne
/// `mesure vue json : {...}` que `outils/mesurer.sh vue` lit (le test est dans le bac a sable de l'app : il n'ecrit pas
/// lui-meme dans un fichier du depot).
///
/// Saute dans la porte (`outils/tester.sh`) : il ne tourne que si `MESURES_VUE=1` (donne par `outils/mesurer.sh vue`, qui le
/// transmet au test par `TEST_RUNNER_MESURES_VUE`), et de preference en Release (`optimisee`).
///
/// Methode (la meme a chaque etape, pour que les chiffres se comparent) :
/// - ouverture : du premier appel a `Surveillance(mode: .demo)` jusqu'a la premiere image complete, hors ecran
///   (`ImageRenderer`) : la surveillance de demo, `EntreeScene`, un `MoteurPieces`, la disposition (`installerMaintenant`),
///   puis une image. Une premiere mesure « froide » (le premier passage du processus : caches, polices) et la mediane des
///   suivantes.
/// - zoom : une suite fixe de pas de zoom (x5 vers le point fixe d'un quart de la vue, puis retour, en echelle
///   geometrique), une image dessinee a chaque pas (`ImageRenderer`). La suite, l'image mediane, le 95e centile et la pire.
@MainActor
@Suite("Mesures de la vue (hors porte)")
struct MesuresVueTests {
    nonisolated static let actives = ProcessInfo.processInfo.environment["MESURES_VUE"] == "1"

    /// Compilation optimisee (Release) : les temps ne se comparent qu'entre compilations de meme nature.
    static var optimisee: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    static let taille = CGSize(width: 1200, height: 800)
    /// Passages mesures de l'ouverture (le premier, « froid », s'y ajoute) et de la suite de zoom.
    static let passages = 9
    /// Pas de la suite de zoom : la moitie vers l'avant, la moitie de retour.
    static let pasDeZoom = 60
    /// Rapport de l'echelle au bout de l'aller.
    static let rapportDeZoom = 5.0

    /// Les scenes mesurees : la demo de Thread seule (`-demo-thread`, celle de l'etape 1, a garder identique pour que les
    /// chiffres se comparent) et la demo combinee (`-demo`, les deux protocoles, construite comme l'app).
    enum Cas: String, CaseIterable {
        case threadSeule = "thread_seule"
        case combinee
    }

    /// La scene d'un cas : la ligne qui differe d'une etape a l'autre de l'app pour Thread seule (le reseau Thread se lit
    /// `surveillance.thread.reseau` depuis l'etape 3a, `surveillance.reseau` a l'etape 1).
    static func sceneDeDemo(_ cas: Cas) throws -> EntreeScene {
        switch cas {
        case .threadSeule:
            let s = Surveillance(mode: .demo, dossier: nil, demo: .thread)
            s.demarrer()
            let r = try #require(s.thread.reseau)
            return EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        case .combinee:
            // Comme `FenetrePieces` : la scene de la surveillance (reseau de Thread et maillage de Zigbee), places vides.
            let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
            s.demarrer()
            return EntreeScene(surveillance: s, places: PlacesGardees())
        }
    }

    static func ms(_ debut: ContinuousClock.Instant, _ fin: ContinuousClock.Instant) -> Double {
        let d = debut.duration(to: fin)
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    static func mediane(_ x: [Double]) -> Double {
        let t = x.sorted()
        return t.isEmpty ? 0 : (t.count % 2 == 1 ? t[t.count / 2] : (t[t.count / 2 - 1] + t[t.count / 2]) / 2)
    }

    static func centile(_ x: [Double], _ p: Double) -> Double {
        let t = x.sorted()
        return t.isEmpty ? 0 : t[min(t.count - 1, Int((p * Double(t.count - 1)).rounded(.up)))]
    }

    /// Une image hors ecran du moteur (comme `MoteurPiecesTests.dessiner`), l'echelle 1.
    static func dessiner(_ m: MoteurPieces) -> CGImage? {
        let rendu = ImageRenderer(content: Canvas { ctx, t in
            m.image(&ctx, taille: t, echelle: 1, palette: Palette(sombre: true))
        }.frame(width: taille.width, height: taille.height))
        return rendu.cgImage
    }

    struct Ouverture {
        var total = 0.0, scene = 0.0, disposition = 0.0, image = 0.0
    }

    /// Verifiee une fois par cas (hors chronometre) : la premiere image a la taille de la vue et n'est pas unie.
    static var verifie: Set<Cas> = []

    /// L'image porte plus d'une couleur (un echantillon de ses octets).
    static func nonUnie(_ image: CGImage) -> Bool {
        guard let donnees = image.dataProvider?.data as Data? else { return false }
        let pas = max(1, donnees.count / 4096)
        return Set(stride(from: 0, to: donnees.count, by: pas).map { donnees[$0] }).count > 1
    }

    /// Un passage de l'ouverture, chronometre en trois temps.
    static func ouvrir(_ cas: Cas) throws -> (Ouverture, MoteurPieces, EntreeScene) {
        var o = Ouverture()
        let t0 = ContinuousClock.now
        let e = try sceneDeDemo(cas)
        let t1 = ContinuousClock.now
        let m = MoteurPieces(fichierPlaces: nil)
        m.marges = (84, 50)
        m.poserTaille(taille)
        m.installerMaintenant(e)
        let t2 = ContinuousClock.now
        let image = dessiner(m)
        let t3 = ContinuousClock.now
        #expect(image != nil && m.pret && m.projetee != nil, "la premiere image est dessinee")
        if let image, !verifie.contains(cas) {
            verifie.insert(cas)
            #expect(image.width >= Int(taille.width) && image.height >= Int(taille.height), "l'image a la taille de la vue")
            #expect(Self.nonUnie(image), "l'image n'est pas unie : la scene y est dessinee")
        }
        o.scene = ms(t0, t1)
        o.disposition = ms(t1, t2)
        o.image = ms(t2, t3)
        o.total = ms(t0, t3)
        return (o, m, e)
    }

    /// Une suite de zoom sur un moteur deja ouvert : le temps de chaque image.
    static func zoomer(_ m: MoteurPieces) -> [Double] {
        let k0 = ProjectionScene(m.orbite, cadre: m.cadre).pxParUnite(m.orbite.cible) / CartesPieces.px
        let ancre = ProjectionScene(m.orbite, cadre: m.cadre)
            .sol(CGPoint(x: m.cadre.width / 4, y: m.cadre.midY / 2), hauteur: m.orbite.cible.y)
        let demi = pasDeZoom / 2
        let pas = pow(rapportDeZoom, 1 / Double(demi))
        var images: [Double] = []
        for i in 1...pasDeZoom {
            let n = i <= demi ? i : pasDeZoom - i
            m.poserZoom(echelle: k0 * pow(pas, Double(n)), vers: ancre)
            let t0 = ContinuousClock.now
            _ = dessiner(m)
            images.append(ms(t0, ContinuousClock.now))
        }
        return images
    }

    /// Les mesures d'un cas : les memes passages et la meme suite de zoom pour chacun.
    static func mesurer(_ cas: Cas) throws -> [String: Any] {
        // Ouverture : un passage froid, puis `passages` passages.
        let (froid, _, e0) = try ouvrir(cas)
        var ouvertures: [Ouverture] = []
        for _ in 0..<passages { ouvertures.append(try ouvrir(cas).0) }
        // Zoom : sur un moteur ouvert, `passages` suites ; la premiere image de chaque suite part de la vue d'ensemble.
        var suites: [Double] = []
        var images: [Double] = []
        for _ in 0..<passages {
            let (_, m, _) = try ouvrir(cas)
            let depart = m.orbite.distance
            let pasImages = zoomer(m)
            #expect(pasImages.count == pasDeZoom)
            #expect(abs(m.orbite.distance - depart) < 1e-6 * depart, "la suite revient a la vue de depart : la camera a bien suivi")
            suites.append(pasImages.reduce(0, +))
            images += pasImages
        }
        return [
            "ouverture_ms": mediane(ouvertures.map(\.total)),
            "ouverture_froide_ms": froid.total,
            "ouverture_scene_ms": mediane(ouvertures.map(\.scene)),
            "ouverture_disposition_ms": mediane(ouvertures.map(\.disposition)),
            "ouverture_premiere_image_ms": mediane(ouvertures.map(\.image)),
            "zoom_suite_ms": mediane(suites),
            "zoom_image_ms": mediane(images),
            "zoom_image_p95_ms": centile(images, 0.95),
            "zoom_pire_image_ms": images.max() ?? 0,
            "pas_de_zoom": pasDeZoom,
            "passages": passages,
            "noeuds": e0.scene.noeuds.count,
            "pieces": e0.scene.pieces.count,
        ]
    }

    /// Thread seule d'abord (son passage froid est celui du processus, comme a l'etape 1), puis la combinee.
    @Test(.enabled(if: MesuresVueTests.actives, "mesure hors porte (outils/mesurer.sh vue)"))
    func ouvertureEtZoom() throws {
        var resultat: [String: Any] = ["compilation": Self.optimisee ? "Release" : "Debug"]
        for cas in Cas.allCases { resultat[cas.rawValue] = try Self.mesurer(cas) }
        let json = try JSONSerialization.data(withJSONObject: resultat, options: [.sortedKeys])
        print("mesure vue json : \(String(decoding: json, as: UTF8.self))")
    }
}
