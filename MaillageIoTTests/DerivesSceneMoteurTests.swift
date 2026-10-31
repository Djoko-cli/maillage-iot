import AppKit
import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

/// Ce que la projection tire de la seule scene (`DerivesScene` : `voisinsMasques`, l'indice des plateaux, les cles des
/// pieces), calcule une fois par scene par le moteur et non a chaque image (performance, piste 3 du 25/10) : le meme
/// resultat qu'avant, et refait quand la scene change.
@MainActor
@Suite("Vue par pieces : ce qui ne depend que de la scene est calcule une fois par scene")
struct DerivesSceneMoteurTests {
    /// Les liens de la derniere image, sans leur geometrie : de quoi comparer deux images.
    static func liens(_ m: MoteurPieces) throws -> [String] {
        let p = try #require(m.projetee)
        return (p.liensRouteurs + p.liensEnfants).map { "\($0.genre) \($0.voisin) \($0.suppose) \($0.opacite) \($0.a) \($0.b)" }
    }

    /// Une scene, plusieurs images : un seul calcul, le meme que `DerivesScene(scene)` ; ni la camera, ni le survol, ni la
    /// selection, ni les voisins montres ou masques ne le refont (il ne depend que des liens de la scene).
    @Test func unSeulCalculParScene() throws {
        let (m, _) = try MoteurPiecesZigbeeTests.moteur()
        #expect(m.calculsDerives == 1, "la premiere image le calcule")
        let scene = try #require(m.scene)
        #expect(m.derives == DerivesScene(scene))
        #expect(m.derives?.voisinsMasques == SceneProjetee.voisinsMasques(scene.liens))
        for _ in 0..<5 { MoteurPiecesZigbeeTests.dessiner(m) }
        #expect(m.calculsDerives == 1, "cinq images de plus : toujours un seul calcul")
        m.selection = idz(NomsDemo.Ieee.lampeBureau)
        m.voisins = false
        m.poserAzimut(0.3)
        m.poserSurvol(m.scene?.noeuds.first?.id)
        m.liens = .tous
        MoteurPiecesZigbeeTests.dessiner(m)
        MoteurPiecesZigbeeTests.dessiner(m)
        #expect(m.calculsDerives == 1, "la selection, les voisins, le survol, la camera et le mode ne le refont pas")
    }

    /// Le meme dessin des liens qu'avant : une image avec le calcul garde et une image qui le refait (calcul efface avant
    /// chaque image, comme a chaque image avant) donnent les memes liens, voisins montres ou masques, selection ou non.
    @Test func memeResultatQuAvant() throws {
        let (m, _) = try MoteurPiecesZigbeeTests.moteur()
        let (neuf, _) = try MoteurPiecesZigbeeTests.moteur()
        let masques = try #require(m.derives).voisinsMasques
        #expect(!masques.isEmpty, "la demo a des voisins que le chemin de leur paire rend inutiles")
        for (selection, voisins) in [(nil, true), (idz(NomsDemo.Ieee.lampeBureau), true), (idz(NomsDemo.Ieee.lampeBureau), false)] {
            for moteur in [m, neuf] {
                moteur.selection = selection
                moteur.voisins = voisins
            }
            MoteurPiecesZigbeeTests.dessiner(m)
            neuf.derives = nil
            MoteurPiecesZigbeeTests.dessiner(neuf)
            let gardes = try Self.liens(m), refaits = try Self.liens(neuf)
            #expect(!gardes.isEmpty)
            #expect(gardes.count == refaits.count)
            // Les deux moteurs sont ceux de la meme scene, a la meme camera : meme dessin (a l'opacite pres, que leur
            // survol, leur focus et leur horloge peuvent separer : le nombre et le genre des liens suffisent a prouver
            // que les masques sont les memes).
            #expect(gardes.map { $0.split(separator: " ").prefix(3) } == refaits.map { $0.split(separator: " ").prefix(3) })
        }
        #expect(neuf.calculsDerives == 4, "refait a chaque image dans cet essai, une fois la premiere")
    }

    /// Une nouvelle scene refait le calcul, a sa premiere image, et le calcul vaut celui de cette scene ; la meme scene
    /// reposee (un releve qui ne change rien) le refait aussi, sans que ce soit faux.
    @Test func refaitQuandLaSceneChange() throws {
        let (m, _) = try MoteurPiecesZigbeeTests.moteur()
        #expect(m.calculsDerives == 1)
        let avant = try #require(m.derives)
        let (_, _, autre) = try NomsSceneTests.demo()
        m.installerMaintenant(autre)
        #expect(m.derives == nil, "la scene a change : le calcul est a refaire")
        MoteurPiecesZigbeeTests.dessiner(m)
        #expect(m.calculsDerives == 2)
        let scene = try #require(m.scene)
        #expect(m.derives == DerivesScene(scene), "le calcul vaut celui de la nouvelle scene")
        #expect(m.derives != avant, "la scene de Thread n'a pas les memes plateaux, ni les memes pieces")
        MoteurPiecesZigbeeTests.dessiner(m)
        #expect(m.calculsDerives == 2)
    }

    /// Les protocoles sans mode, lus a chaque image, sont calcules une fois par scene aussi.
    @Test func protocolesSansModeParScene() throws {
        let (m, e) = try MoteurPiecesZigbeeTests.moteur()
        let attendu = Set(e.modeles.filter { !$0.suitModeLiens }.map(\.protocole))
        #expect(m.protocolesSansMode == attendu)
        #expect(m.protocolesSansModeCalcules == attendu, "gardes pour les images qui suivent")
        m.installerMaintenant(e)
        #expect(m.protocolesSansModeCalcules == nil, "une nouvelle scene les refait")
        #expect(m.protocolesSansMode == attendu)
    }
}
