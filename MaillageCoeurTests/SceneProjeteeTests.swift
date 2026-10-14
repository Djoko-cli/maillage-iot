import CoreGraphics
import Foundation
import simd
import Testing
@testable import MaillageCoeur

@Suite("Scene : projection vers le moteur")
struct SceneProjeteeTests {
    static let cadre = CGRect(x: 0, y: 0, width: 1200, height: 800)

    /// Trois pieces sur deux etages : le salon au rez-de-chaussee (l'Apple TV, E...04, E...05), la
    /// chambre (le HomePod) et le bureau (E...02, enfant de l'Apple TV ; E...03, enfant du HomePod) a
    /// l'etage. Liens de la sonde : Apple TV - HomePod et Apple TV - E...04 (radio), E...02 et E...03
    /// vers leur parent ; E...05, rattache au centre.
    static func scene() throws -> (ScenePieces, [CartesPieces.Carte], DispositionPieces, GeometrieMaison) {
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Bureau",
                      "E000000000000003": "Bureau", "E000000000000004": "Salon", "E000000000000005": "Salon"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"])]
        let s = ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: true), libelles: ScenePiecesTests.libelles,
                            piecesNoeuds: pieces, zones: zones, chefs: ["Apple TV"], piecesMaison: true)
        let c = CartesPieces.cartes(s, largeurs: [:])
        let d = DispositionPieces(scene: s, cartes: c)
        return (s, c, d, GeometrieMaison(rayons: d.rayons))
    }

    static func projeter(t: Double, _ etat: (inout EtatAnime) -> Void = { _ in }) throws
        -> (ScenePieces, SceneProjetee) {
        let (s, c, d, g) = try Self.scene()
        var e = EtatAnime(t: t, fk: Array(repeating: 0, count: s.pieces.count))
        etat(&e)
        let o = CameraScene.canonique(g, aspect: 1.5, u: t)
        return (s, SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o, cadre: Self.cadre))
    }

    static func indice(_ s: ScenePieces, _ nom: String) throws -> Int {
        try #require(s.pieces.firstIndex { $0.nom == .maison(nom) })
    }

    /// En 2D : les plateaux, le dessus de chaque bloc (et au plus deux cotes, vus par la tranche), ni
    /// sphere ni equateur ; les ancres de tous les noms ; les liens entre routeurs a part des autres.
    @Test func vueDeDessus() throws {
        let (s, p) = try Self.projeter(t: 0)
        #expect(p.plateaux.count == 2)
        #expect(p.blocs.count == 3 && p.blocs.allSatisfy { !$0.faces.isEmpty && $0.faces.count <= 3 })
        #expect(p.sphere == nil && p.equateur == nil)
        #expect(p.ancresNoeuds.count == s.noeuds.count && p.ancresPieces.count == 3 && p.ancresEtages.count == 2)
        #expect(p.ancreMaison != nil)
        #expect(p.liensRouteurs.count == 2 && p.liensEnfants.count == 3)
        #expect(p.liensEnfants.filter { $0.genre == .rattachement }.count == 1)
        #expect(p.disques.count == s.noeuds.count)
        #expect(zip(p.disques, p.disques.dropFirst()).allSatisfy { $0.profondeur >= $1.profondeur })
        #expect(p.blocs.allSatisfy { abs($0.opaciteVerre - 0.13) < 1e-12 && abs($0.opaciteAretes - 0.75) < 1e-12 })
    }

    /// En 3D : la sphere et son equateur ; plusieurs faces par bloc ; les blocs du plus loin au plus proche.
    @Test func vueEn3D() throws {
        let (_, p) = try Self.projeter(t: 1)
        #expect(p.sphere != nil && p.equateur != nil)
        #expect(p.blocs.allSatisfy { $0.faces.count >= 2 && $0.faces.count <= 3 })
        #expect(zip(p.blocs, p.blocs.dropFirst()).allSatisfy { $0.profondeur >= $1.profondeur })
        #expect(p.blocs.allSatisfy { abs($0.opaciteVerre - 0.18) < 1e-12 })
    }

    /// Clic et survol : la piece et le noeud sous le curseur ; rien sur le fond.
    @Test func sousLeCurseur() throws {
        let (s, p) = try Self.projeter(t: 0)
        for (i, a) in p.ancresPieces {
            let coin = CGPoint(x: a.minX + 2, y: a.maxY - 2)
            #expect(p.piece(sous: coin) == i, "\(s.pieces[i].id)")
        }
        for d in p.disques { #expect(p.noeud(sous: d.centre) == d.noeud) }
        #expect(p.piece(sous: CGPoint(x: 3, y: 3)) == nil && p.noeud(sous: CGPoint(x: 3, y: 3)) == nil)
    }

    /// Piece isolee (le bureau) : les autres s'estompent a 15 % ; un repere « ailleurs » par enfant dont
    /// le parent est dans une autre piece, avec son sens (meme etage, dessous) et son fil. Les disques des
    /// etages restent a 15 % : on peut cliquer dessus (polissage C, section 5.2).
    @Test func pieceIsolee() throws {
        let (s0, _) = try Self.projeter(t: 0)
        let bureau = try Self.indice(s0, "Bureau")
        let (s, p) = try Self.projeter(t: 0) { e in
            e.s = 1
            e.focus = bureau
            e.fk[bureau] = 1
        }
        let reperes = p.ailleurs.sorted { $0.enfant < $1.enfant }
        let salon = try Self.indice(s, "Salon"), chambre = try Self.indice(s, "Chambre")
        #expect(reperes.map(\.parent) == ["Apple TV", "HomePod"])
        #expect(reperes[0].sens == .dessous && reperes[0].piece == salon)
        #expect(reperes[1].sens == .memeNiveau && reperes[1].piece == chambre)
        #expect(p.fils.count == 2 && p.fils.allSatisfy { abs($0.opacite - 0.8) < 1e-12 })
        #expect(p.ancresAilleurs.count == 2)
        for b in p.blocs {
            let attendue = b.piece == bureau ? 0.13 : 0.15 * 0.13
            #expect(abs(b.opaciteVerre - attendue) < 1e-12)
        }
        #expect(p.plateaux.allSatisfy { abs($0.opacite - 0.15) < 1e-12 })
    }

    /// Etage isole (polissage C, section 5.1), ici l'etage : les autres plateaux descendent a 15 %, avec leurs pieces,
    /// leurs pastilles et leurs liens ; un lien qui touche l'etage isole reste visible, meme vers un autre etage ; la
    /// sphere et l'equateur s'effacent. Le disque survole s'eclaircit.
    @Test func etageIsole() throws {
        let (s0, _) = try Self.projeter(t: 1)
        let etage = try #require(s0.etages.firstIndex { $0.nom == .zone("Étage") })
        let (s, p) = try Self.projeter(t: 1) { e in
            e.se = 1
            e.ek = s0.etages.indices.map { $0 == etage ? 1 : 0 }
            e.survolEtage = etage
        }
        #expect(p.voilesEtages.indices.allSatisfy { abs(p.voilesEtages[$0] - ($0 == etage ? 1 : 0.15)) < 1e-12 })
        for pl in p.plateaux {
            #expect(abs(pl.opacite - (pl.etage == etage ? 1 : 0.15)) < 1e-12 && pl.eclaire == (pl.etage == etage))
        }
        for b in p.blocs {
            let attendue = s.pieces[b.piece].etage == etage ? 0.18 : 0.15 * 0.18
            #expect(abs(b.opaciteVerre - attendue) < 1e-12)
        }
        for d in p.disques {
            let n = try #require(s.noeud(d.noeud))
            #expect(abs(d.opacite - (s.pieces[n.piece].etage == etage ? 1 : 0.15)) < 1e-12)
        }
        // Apple TV (rez-de-chaussee) - HomePod (etage) touche l'etage isole ; Apple TV - E...04 reste au rez-de-chaussee.
        let opacites = p.liensRouteurs.map(\.opacite).sorted()
        #expect(opacites.count == 2 && abs(opacites[0] - 0.95 * 0.15) < 1e-12 && abs(opacites[1] - 0.95) < 1e-12)
        #expect(p.sphere == nil && p.equateur == nil)
    }

    /// Le sens d'un repere « ailleurs » compare les niveaux (polissage C, section 5.2) : un parent dans l'etage
    /// principal d'une zone a cote est au meme niveau (↗) ; un parent a l'etage, au-dessus (↑). La zone mise sur
    /// son propre niveau, au-dessus des deux autres : ses parents sont en dessous.
    @Test func reperesParNiveau() throws {
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Terrasse",
                      "E000000000000003": "Terrasse"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"]),
                     ZoneMaison(nom: "Jardin", pieces: ["Terrasse"])]
        for aCote in [["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)], [:]] {
            let s = ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: true), libelles: ScenePiecesTests.libelles,
                                piecesNoeuds: pieces, zones: zones, chefs: ["Apple TV"], piecesMaison: true, aCote: aCote)
            let terrasse = try Self.indice(s, "Terrasse")
            let sens = SceneProjetee.reperes(s, focus: terrasse).sorted { $0.enfant < $1.enfant }.map(\.sens)
            #expect(sens == (aCote.isEmpty ? [.dessous, .dessous] : [.memeNiveau, .dessus]), "\(aCote)")
        }
    }

    /// Survol d'un appareil : ses liens enfant-parent s'eclairent a 0,85 ; les autres restent a 0,28.
    @Test func survol() throws {
        let (_, p) = try Self.projeter(t: 0) { $0.survol = "E000000000000002" }
        let eclaires = p.liensEnfants.filter(\.eclaire)
        #expect(eclaires.count == 1 && abs(eclaires[0].opacite - 0.85) < 1e-12)
        #expect(p.liensEnfants.filter { !$0.eclaire }.allSatisfy { abs($0.opacite - 0.28) < 1e-12 })
        #expect(p.liensRouteurs.allSatisfy { abs($0.opacite - 0.95) < 1e-12 && !$0.eclaire })
    }

    /// Eclairage des faces : (2,2 + 1,6 n.l) / pi, en lineaire ; un facteur 1 ne change rien.
    @Test func eclairage() {
        let l = simd_normalize(SIMD3<Double>(-10, 30, 14))
        #expect(abs(SceneProjetee.lambert[2] - (2.2 + 1.6 * l.y) / .pi) < 1e-12)
        #expect(abs(SceneProjetee.lambert[0] - 2.2 / .pi) < 1e-12, "+x : la lumiere vient de -x")
        let bleu = Teinte(hexa: 0x3B82F5)
        let meme = bleu.eclairee(1)
        #expect(abs(meme.r - bleu.r) < 1e-9 && abs(meme.g - bleu.g) < 1e-9 && abs(meme.b - bleu.b) < 1e-9)
        #expect(bleu.eclairee(0.5).b < bleu.b)
    }
}
