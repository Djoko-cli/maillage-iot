import AppKit
import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// L'arrivee a la vue d'ensemble 3D (banc 5, phase 6) : la bulle de la maison doit remplir l'espace libre de la
/// fenetre (entre le haut mesure et la ligne du bas), comme la maison remplit la fenetre en 2D, jardin hors de la
/// maison compris. Avant le correctif, la camera cadrait un rayon de 2,4 fois `rayonCadre` en hauteur : le jardin,
/// compte comme s'il etait aussi haut que large, ramenait la bulle a 40 % de la hauteur libre.
@MainActor
@Suite("Vue par pieces : la vue d'ensemble 3D remplit l'espace libre")
struct VueEnsemble3DTests {
    /// La fraction de la plus petite dimension libre que la bulle doit occuper au moins : 80 %. En 2D, la maison tient dans
    /// 1 / 1,1 = 91 % de la hauteur libre ; la vue d'ensemble 3D cadre la bulle a 87 % (2,4 rayons de hauteur de vue). Le
    /// jardin hors de la maison, lui, doit rester entier dans le cadre a l'arrivee : dans une fenetre etroite et haute
    /// (700 x 1000), sa largeur limite la bulle a 74 % de la largeur libre, d'ou 70 % pour ces fenetres. Avant le
    /// correctif : 39 a 41 % partout, un tiers de la hauteur libre, avec un jardin.
    static let fraction = 0.8
    static let fractionEtroite = 0.7

    /// Une fenetre : sa taille, et la marge du bas, celle de la legende repliee (50) ou ouverte (230, la pile mesuree).
    struct Fenetre: CustomTestStringConvertible, Sendable {
        var taille: CGSize
        var bas: CGFloat
        /// Fenetre plus haute que large : la largeur libre limite la bulle, le jardin y tenant.
        var etroite: Bool { taille.width < taille.height }
        var testDescription: String { "\(Int(taille.width))x\(Int(taille.height)), marge du bas \(Int(bas))" }
    }

    nonisolated static let fenetres: [Fenetre] = [
        Fenetre(taille: CGSize(width: 1440, height: 900), bas: 50),
        Fenetre(taille: CGSize(width: 1440, height: 900), bas: 230),
        Fenetre(taille: CGSize(width: 820, height: 680), bas: 50),
        Fenetre(taille: CGSize(width: 820, height: 680), bas: 230),
        Fenetre(taille: CGSize(width: 700, height: 1000), bas: 50),
        Fenetre(taille: CGSize(width: 700, height: 1000), bas: 230),
    ]

    /// Le moteur de la demo sur quatre plateaux, le jardin hors de la maison (`jardin: true`) ou chacun sur son niveau,
    /// dispose, une premiere image dessinee ; en 3D des l'ouverture ou en 2D.
    static func moteur(_ f: Fenetre, jardin: Bool, troisD: Bool, fichier: URL) throws -> MoteurPieces {
        let base = try MoteurPiecesTests.quatrePlateaux()
        var places = PlacesGardees()
        if jardin {
            places.ranger(Rangement(ordre: [IsolementTests.rdc, IsolementTests.jardin, IsolementTests.etage, IsolementTests.combles],
                                    aCote: [IsolementTests.jardin: PlacesGardees.ACote(etage: IsolementTests.rdc, dehors: true)]),
                          domicile: base.domicile)
        }
        try places.ecrire(dans: fichier)
        let e = try MoteurPiecesTests.quatrePlateaux(places)
        let m = MoteurPieces(troisD: troisD, fichierPlaces: fichier)
        m.marges = (84, f.bas)
        m.poserTaille(f.taille)
        m.installerMaintenant(e)
        for _ in 0..<2 { MoteurPiecesTests.dessiner(m, taille: f.taille) }
        return m
    }

    /// Le diametre projete de la bulle de la maison : la plus petite des deux etendues de son contour a l'ecran.
    static func diametreDeLaBulle(_ m: MoteurPieces) throws -> Double {
        let p = ProjectionScene(m.orbite, cadre: m.cadre)
        let a = try #require(p.contourSphere(m.geometrie.centreSphere, m.geometrie.rayonSphere))
        return 2 * min(hypot(a.a, a.c), hypot(a.b, a.d))
    }

    /// La bulle remplit la fraction voulue de la plus petite dimension libre du cadre.
    static func verifierBulle(_ m: MoteurPieces, _ f: Fenetre, jardin: Bool, _ contexte: String) throws {
        let libre = min(m.cadre.width, m.cadre.height)
        #expect(abs(m.cadre.height - (f.taille.height - 84 - f.bas)) < 1e-6, "le cadre est l'espace libre : \(contexte)")
        let d = try Self.diametreDeLaBulle(m)
        #expect(d >= (f.etroite && jardin ? Self.fractionEtroite : Self.fraction) * libre, "\(contexte) : bulle \(Int(d)) px, espace libre \(Int(libre)) px (\(Int(100 * d / libre)) %)")
        #expect(d <= libre, "\(contexte) : la bulle reste dans l'espace libre")
    }

    /// Le jardin (les zones hors de la maison) est entier dans le cadre a l'arrivee, a l'azimut de la pose canonique. (Sur
    /// un tour de rotation lente, il en sortirait par moments : le cadrage de tout un tour ramenait la bulle a 40 %, voir
    /// `CameraScene.vue3D`.)
    static func verifierJardin(_ m: MoteurPieces, _ contexte: String) throws {
        let scene = try #require(m.scene)
        let dehors = scene.etages.indices.filter { scene.etages[$0].dehors }
        #expect(!dehors.isEmpty, "la scene a un jardin hors de la maison")
        let proj = ProjectionScene(m.orbite, cadre: m.cadre)
        for e in dehors {
            let c = m.geometrie.centres3D[e], r = m.geometrie.rayons[e]
            for a in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
                for h in [0.0, GeometrieMaison.hauteurBloc3D] {
                    let p = c + SIMD3(r * cos(a), h, r * sin(a))
                    let q = try #require(proj.ecran(p))
                    #expect(m.cadre.contains(q), "\(contexte) : jardin, point \(Int(q.x)),\(Int(q.y))")
                }
            }
        }
    }

    /// A l'ouverture de la vue en 3D, avec un jardin hors de la maison : la bulle remplit l'espace libre, le jardin reste
    /// dans le cadre.
    @Test(arguments: fenetres) func ouvertureEn3DAvecJardin(_ f: Fenetre) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(f, jardin: true, troisD: true, fichier: url)
        #expect(m.t == 1 && m.geometrie.rayonCadre > m.geometrie.rayonSphere, "un jardin hors de la bulle")
        try Self.verifierBulle(m, f, jardin: true, "ouverture, \(f.testDescription)")
        try Self.verifierJardin(m, "ouverture, \(f.testDescription)")
    }

    /// Sans jardin hors de la maison : la meme exigence (elle tenait deja).
    @Test(arguments: fenetres) func ouvertureEn3DSansJardin(_ f: Fenetre) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(f, jardin: false, troisD: true, fichier: url)
        #expect(m.t == 1 && m.geometrie.rayonCadre == m.geometrie.rayonSphere, "pas de jardin hors de la bulle")
        try Self.verifierBulle(m, f, jardin: false, "sans jardin, \(f.testDescription)")
    }

    /// Le passage 2D -> 3D (double-clic sur la bascule) : a l'arrivee de l'envol, meme cadrage.
    @Test(.timeLimit(.minutes(1)), arguments: fenetres) func arriveeDeLEnvol(_ f: Fenetre) async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(f, jardin: true, troisD: false, fichier: url)
        m.basculer(troisD: true)
        #expect(m.enMouvement)
        try await MoteurPiecesTests.attendre {
            MoteurPiecesTests.dessiner(m, taille: f.taille)
            return !m.enMouvement
        }
        #expect(!m.enMouvement && m.t == 1)
        try Self.verifierBulle(m, f, jardin: true, "envol, \(f.testDescription)")
        try Self.verifierJardin(m, "envol, \(f.testDescription)")
    }

    /// Le retour a la vue d'ensemble 3D (Echap depuis une piece isolee) : meme cadrage.
    @Test(.timeLimit(.minutes(1)), arguments: fenetres) func retourALaVueDEnsemble(_ f: Fenetre) async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(f, jardin: true, troisD: true, fichier: url)
        let salon = try MoteurPiecesTests.indice(try #require(m.entree), "Salon")
        m.poserIsolement(salon)
        MoteurPiecesTests.dessiner(m, taille: f.taille)
        #expect(m.sortir() && m.enMouvement, "Echap remonte a la maison par un vol")
        try await MoteurPiecesTests.attendre {
            MoteurPiecesTests.dessiner(m, taille: f.taille)
            return !m.enMouvement
        }
        #expect(!m.enMouvement)
        try Self.verifierBulle(m, f, jardin: true, "retour, \(f.testDescription)")
        try Self.verifierJardin(m, "retour, \(f.testDescription)")
    }
}
