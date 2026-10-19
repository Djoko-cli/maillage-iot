import CoreGraphics
import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Une meme paire de noeuds n'est dessinee qu'une fois, sur la demo combinee (point 10 de la vue des liens ; valeurs
/// inventees) : sous un repere « ailleurs », un seul trait part de l'enfant vers son parent, pour Zigbee comme pour Thread ;
/// et, partout ailleurs, aucune paire n'a deux traces, dans les deux modes et a la selection. Le coeur le montre sur de
/// petites scenes (`LiensEnDoubleTests`).
@MainActor
@Suite("Liens en double sur la demo")
struct LiensEnDoubleDemoTests {
    /// La cle d'une paire de points, sans tenir compte du sens : deux traces de meme cle se superposent.
    static func cle(_ a: CGPoint, _ b: CGPoint) -> String {
        [a, b].map { String(format: "%.1f,%.1f", Double($0.x), Double($0.y)) }.sorted().joined(separator: "|")
    }

    /// Le nombre de traces de chaque paire de points de l'image (liens enfant et entre routeurs, voisins compris).
    static func traces(_ p: SceneProjetee) -> [String: Int] {
        Dictionary(grouping: p.liensEnfants + p.liensRouteurs) { Self.cle($0.a, $0.b) }.mapValues(\.count)
    }

    static func proche(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5 }

    /// Les traces qui partent du centre de la pastille de `enfant` vers son parent : son fil « ailleurs » et son lien parent.
    static func versLeParent(_ p: SceneProjetee, _ enfant: IdNoeud) throws -> (fils: Int, liens: Int) {
        let r = try #require(p.ancresNoeuds[enfant])
        let centre = CGPoint(x: r.midX, y: r.midY)
        return (p.fils.filter { Self.proche($0.a, centre) }.count,
                p.liensEnfants.filter { $0.genre == .parent && Self.proche($0.a, centre) }.count)
    }

    /// Sous chaque repere d'une piece isolee de la demo, un seul trait part de l'enfant vers son parent : son fil ; et ses
    /// autres liens vers un parent (un enfant sans repere) restent. Une piece pour chaque protocole, plus une qui a les deux.
    @Test func unSeulTraceSousLesReperes() throws {
        let e = EntreeScene(surveillance: DemoCombineeTests.combinee(), places: PlacesGardees())
        let avecReperes = e.scene.pieces.indices.map { ($0, SceneProjetee.reperes(e.scene, focus: $0)) }.filter { !$0.1.isEmpty }
        let zigbee = try #require(avecReperes.first { $0.1.contains { $0.enfant.protocole == .zigbee } })
        let thread = try #require(avecReperes.first { $0.1.contains { $0.enfant.protocole == .thread } })
        var vus = Set<Protocole>()
        for (piece, reperes) in [zigbee, thread] {
            let m = MoteurPiecesTests.moteur(e)
            m.poserZoom(echelle: 1, vers: nil)
            ReperesAilleursTests.isoler(m, piece)
            let p = try #require(m.projetee)
            #expect(p.fils.count == reperes.count)
            for a in reperes {
                let (fils, liens) = try Self.versLeParent(p, a.enfant)
                #expect(fils == 1 && liens == 0, "\(a.enfant.protocole) : \(fils) fil et \(liens) lien vers son parent")
                vus.insert(a.enfant.protocole)
            }
            let sansRepere = Set(e.scene.liens.filter { $0.genre == .parent }.map(\.de)).subtracting(reperes.map(\.enfant))
            #expect(p.liensEnfants.filter { $0.genre == .parent }.count == sansRepere.count, "les liens sans repere restent")
            #expect(Self.traces(p).values.allSatisfy { $0 == 1 })
        }
        #expect(vus == [.zigbee, .thread], "les deux protocoles ont ete vus")
    }

    /// Toute la scene, en 3D, sans piece isolee : aucune paire n'a deux traces, dans les deux modes, sans selection et a la
    /// selection d'un routeur de Zigbee (ses voisins) ou d'un noeud de Thread.
    @Test func aucunePaireEnDouble() throws {
        let e = EntreeScene(surveillance: DemoCombineeTests.combinee(), places: PlacesGardees())
        let routeur = try #require(e.scene.liens.first { $0.genre == .chemin }?.de, "un routeur de Zigbee avec un chemin")
        let thread = try #require(e.scene.liens.first { $0.de.protocole == .thread && $0.genre == .parent }?.vers)
        let m = MoteurPiecesTests.moteur(e)
        m.poserZoom(echelle: 1, vers: nil)
        for mode in ModeLiens.allCases {
            for selection in [nil, routeur, thread] {
                m.liens = mode
                m.selection = selection
                MoteurPiecesTests.dessiner(m)
                let p = try #require(m.projetee)
                let t = Self.traces(p)
                #expect(!t.isEmpty && t.values.allSatisfy { $0 == 1 }, "\(mode) \(selection?.cle ?? "-") : \(t.filter { $0.value > 1 })")
            }
        }
    }

    /// La legende ne compte pas un voisin que la scene ne dessine pas : la paire d'un chemin n'a pas de voisin ; une paire
    /// radio seule en a un, et ses qualites.
    @Test func legendeDesVoisins() {
        let (a, b, c) = (idz("A1"), idz("A2"), idz("A3"))
        let radio = ScenePieces.Lien(de: a, vers: b, genre: .radio, qualite: 3)
        let chemin = ScenePieces.Lien(de: b, vers: a, genre: .chemin, qualite: 3)
        let seul = ScenePieces.Lien(de: b, vers: c, genre: .radio, qualite: 1)
        typealias Lecture = LegendePieces.Lecture
        #expect(LegendePieces.entrees(Lecture(liens: [radio, chemin], mode: .chemins)) == [.chemin, .bonne], "pas de voisin")
        #expect(LegendePieces.entrees(Lecture(liens: [radio, chemin, seul], mode: .chemins)) == [.chemin, .bonne, .voisinEntendu, .faible])
        #expect(LegendePieces.entrees(Lecture(liens: [radio, chemin], mode: .tous)) == [.bonne], "en mode tous : le lien radio")
    }
}
