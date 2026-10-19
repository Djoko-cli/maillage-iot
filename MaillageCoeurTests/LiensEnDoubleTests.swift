import CoreGraphics
import Foundation
import simd
import Testing
@testable import MaillageCoeur

/// Une meme paire de noeuds n'est dessinee qu'une fois (point 10 de la vue des liens) : le trait qui porte le plus
/// d'information reste, l'autre est omis ; la lecture de la scene (la legende) ne compte pas un trait qu'aucun trace ne
/// montre. Valeurs inventees.
@Suite("Liens : une seule trace par paire de noeuds")
struct LiensEnDoubleTests {
    static let cadre = SceneProjeteeTests.cadre

    /// La cle d'une paire de points, sans tenir compte du sens : deux traces de meme cle se superposent.
    static func cle(_ a: CGPoint, _ b: CGPoint) -> String {
        [a, b].map { String(format: "%.1f,%.1f", Double($0.x), Double($0.y)) }.sorted().joined(separator: "|")
    }

    /// Le nombre de traces de chaque paire de points (liens enfant, liens entre routeurs, voisins compris).
    static func traces(_ p: SceneProjetee) -> [String: Int] {
        Dictionary(grouping: p.liensEnfants + p.liensRouteurs) { Self.cle($0.a, $0.b) }.mapValues(\.count)
    }

    static func proche(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5 }

    // MARK: Un repere « ailleurs » et le lien vers son parent

    /// Le bureau isole : ses deux enfants ont leur parent dans une autre piece. Le fil du repere et le lien gris vers le
    /// parent partaient du meme enfant, vers le meme parent : deux traces.
    static func bureauIsole(ailleursEstompes: [IdNoeud: Double] = [:]) throws -> (SceneProjetee, [Ailleurs]) {
        let (s0, _) = try SceneProjeteeTests.projeter(t: 0)
        let bureau = try SceneProjeteeTests.indice(s0, "Bureau")
        let (s, p) = try SceneProjeteeTests.projeter(t: 0) { e in
            e.s = 1
            e.focus = bureau
            e.fk[bureau] = 1
            e.ailleursEstompes = ailleursEstompes
        }
        return (p, SceneProjetee.reperes(s, focus: bureau).sorted { $0.enfant < $1.enfant })
    }

    static func centre(_ p: SceneProjetee, _ enfant: IdNoeud) throws -> CGPoint {
        let r = try #require(p.ancresNoeuds[enfant])
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Le lien vers le parent qui part de `enfant`.
    static func lien(_ p: SceneProjetee, _ enfant: IdNoeud) throws -> SceneProjetee.Lien {
        let c = try Self.centre(p, enfant)
        return try #require(p.liensEnfants.first { $0.genre == .parent && Self.proche($0.a, c) })
    }

    /// Les traces qui partent du centre de la pastille de `enfant` vers son parent : son fil « ailleurs » et son lien parent.
    static func versLeParent(_ p: SceneProjetee, _ enfant: IdNoeud) throws -> (fils: Int, liens: Int) {
        let centre = try Self.centre(p, enfant)
        return (p.fils.filter { Self.proche($0.a, centre) }.count,
                p.liensEnfants.filter { $0.genre == .parent && Self.proche($0.a, centre) }.count)
    }

    /// Sous un repere « ailleurs », un seul trait part de l'enfant vers son parent : le fil du repere, qui garde le lien.
    @Test func unSeulTraceSousUnRepere() throws {
        let (p, reperes) = try Self.bureauIsole()
        #expect(reperes.count == 2 && p.fils.count == 2)
        for a in reperes {
            let (fils, liens) = try Self.versLeParent(p, a.enfant)
            #expect(fils == 1 && liens == 0, "\(a.enfant) : \(fils) fil et \(liens) lien parent vers le meme parent")
        }
        #expect(p.liensEnfants.filter { $0.genre == .rattachement }.count == 1, "les autres liens enfant sont intacts")
    }

    /// Un repere efface sous une selection (point 9) n'a plus de fil : le lien vers le parent, seule trace restante, revient.
    /// Le fil et le lien se passent le relais a mesure que le repere s'estompe : a moitie estompe, le fil est a moitie et le
    /// lien a moitie (jamais plus d'un trait entier : leurs parts font un).
    @Test func lienRendu() throws {
        let (_, reperes) = try Self.bureauIsole()
        let (a, b) = (reperes[0], reperes[1])
        let (efface, _) = try Self.bureauIsole(ailleursEstompes: [b.enfant: 1])
        let (fa, la) = try Self.versLeParent(efface, a.enfant)
        let (fb, lb) = try Self.versLeParent(efface, b.enfant)
        #expect((fa, la) == (1, 0), "le repere net garde son fil seul")
        #expect((fb, lb) == (0, 1), "le repere efface rend le lien vers son parent")
        let (moitie, _) = try Self.bureauIsole(ailleursEstompes: [b.enfant: 0.5])
        let (fm, lm) = try Self.versLeParent(moitie, b.enfant)
        #expect((fm, lm) == (1, 1), "a moitie estompe : le relais")
        let lienRendu = try Self.lien(efface, b.enfant), lienMoitie = try Self.lien(moitie, b.enfant)
        #expect(abs(lienMoitie.opacite - 0.5 * lienRendu.opacite) < 1e-12, "le lien cede la moitie de son trait au fil")
        let filMoitie = try #require(moitie.fils.first { Self.proche($0.a, (try? Self.centre(moitie, b.enfant)) ?? .zero) })
        #expect(abs(filMoitie.opacite - 0.4) < 1e-12, "et le fil a moitie de ses 0,8")
    }

    /// Hors de la piece isolee, aucun repere : tous les liens vers un parent sont la, comme avant.
    @Test func sansRepereLesLiensRestent() throws {
        let (_, p) = try SceneProjeteeTests.projeter(t: 0)
        #expect(p.fils.isEmpty && p.liensEnfants.filter { $0.genre == .parent }.count == 2)
    }

    /// Un parent d'avant (lien suppose) qui part vers ailleurs : son fil en garde le style (pointilles fins), faute de quoi
    /// la nuance serait perdue avec le lien.
    @Test func filDuParentDAvant() throws {
        let sup = ScenePieces(graphe: try Self.grapheAvecParentDAvant(), libelles: ScenePiecesTests.libelles,
                              piecesNoeuds: Self.piecesBureau, zones: Self.zones, chefs: [idt("Apple TV")], piecesMaison: true,
                              classement: FixturesScene.classement)
        let cartes = CartesPieces.cartes(sup, largeurs: [:])
        let disp = DispositionPieces(scene: sup, cartes: cartes)
        let geo = GeometrieMaison(rayons: disp.rayons)
        let bureau = try SceneProjeteeTests.indice(sup, "Bureau")
        var e = EtatAnime(t: 0, s: 1, fk: Array(repeating: 0, count: sup.pieces.count), focus: bureau)
        e.fk[bureau] = 1
        let p = SceneProjetee(scene: sup, cartes: cartes, positions: disp.positions, geometrie: geo, etat: e,
                              orbite: CameraScene.canonique(geo, aspect: 1.5, u: 0), cadre: Self.cadre)
        #expect(p.fils.count == 2)
        #expect(p.fils.filter(\.suppose).count == 1, "le fil du parent d'avant est suppose, l'autre non")
        #expect(p.liensEnfants.filter { $0.genre == .parent }.isEmpty)
    }

    static let piecesBureau = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre", idt("E000000000000002"): "Bureau",
                               idt("E000000000000003"): "Bureau", idt("E000000000000004"): "Salon",
                               idt("E000000000000005"): "Salon"]
    static let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"])]

    /// Le graphe de la fixture, dont le lien de E...02 vers son parent est un parent d'avant.
    static func grapheAvecParentDAvant() throws -> GrapheReseau {
        let g = try FixturesScene.graphe(sonde: true)
        let liens = g.liens.map { l in
            l.genre == .parent && l.de == idt("E000000000000002")
                ? GrapheReseau.Lien(de: l.de, vers: l.vers, genre: .parent, qualite: l.qualite, suppose: true) : l
        }
        return GrapheReseau(noeuds: g.noeuds, liens: liens)
    }

    // MARK: Un voisin entendu et le chemin de la meme paire

    /// Un petit maillage de Zigbee dans une piece : le coordinateur C, deux routeurs R1 et R2. Radio : C-R1, R1-R2, C-R2 ;
    /// chemins : R1 vers C, R2 vers R1. Seule la paire C-R2 n'a pas de chemin.
    static func maillage() -> (GrapheReseau, c: IdNoeud, r1: IdNoeud, r2: IdNoeud) {
        let (c, r1, r2) = (idz("A000000000000001"), idz("A000000000000010"), idz("A000000000000011"))
        func noeud(_ id: IdNoeud, _ genre: GrapheReseau.Genre) -> GrapheReseau.Noeud {
            .init(id: id, genre: genre, partition: "zigbee", routeur: true, bordure: false, inconnu: false)
        }
        let g = GrapheReseau(noeuds: [noeud(c, .centre), noeud(r1, .routeur), noeud(r2, .routeur)], liens: [
            .init(de: c, vers: r1, genre: .radio, qualite: 3),
            .init(de: r1, vers: r2, genre: .radio, qualite: 2),
            .init(de: c, vers: r2, genre: .radio, qualite: 1),
            .init(de: r1, vers: c, genre: .chemin, qualite: 3),
            .init(de: r2, vers: r1, genre: .chemin, qualite: 2),
        ])
        return (g, c, r1, r2)
    }

    static func projeterMaillage(selection: IdNoeud?, mode: ModeLiens) -> (SceneProjetee, ScenePieces) {
        let (g, c, r1, r2) = Self.maillage()
        let s = ScenePieces(graphe: g, libelles: [:], piecesNoeuds: [c: "Salon", r1: "Salon", r2: "Salon"],
                            zones: [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"])], chefs: [c], piecesMaison: true,
                            classement: FixturesScene.classement)
        let cartes = CartesPieces.cartes(s, largeurs: [:])
        let d = DispositionPieces(scene: s, cartes: cartes)
        let geo = GeometrieMaison(rayons: d.rayons)
        var e = EtatAnime(t: 0, fk: Array(repeating: 0, count: s.pieces.count))
        e.selection = selection
        e.liens = mode
        let o = CameraScene.canonique(geo, aspect: 1.5, u: 0)
        return (SceneProjetee(scene: s, cartes: cartes, positions: d.positions, geometrie: geo, etat: e, orbite: o, cadre: Self.cadre), s)
    }

    /// Mode « chemins », R1 choisi : ses deux liens radio (C-R1, R1-R2) sont des voisins, et chacun a deja son chemin. Le
    /// chemin, qui dit la meme qualite et en plus son role, reste seul ; le voisin dessous (un trait fin, estompe, de la meme
    /// couleur) etait une seconde trace de la paire.
    @Test func unVoisinSousSonChemin() {
        let (p, _) = Self.projeterMaillage(selection: Self.maillage().r1, mode: .chemins)
        let t = Self.traces(p)
        #expect(t.values.allSatisfy { $0 == 1 }, "une trace par paire : \(t)")
        #expect(p.liensRouteurs.filter(\.voisin).isEmpty, "aucun voisin : les deux paires de R1 ont leur chemin")
        #expect(p.liensRouteurs.filter { $0.genre == .chemin }.count == 2)
    }

    /// Le voisin d'une paire sans chemin (C-R2, R2 choisi) reste : c'est sa seule trace, et l'autre paire de R2 (R1-R2) ne
    /// montre que son chemin.
    @Test func unVoisinSansCheminReste() {
        let (p, _) = Self.projeterMaillage(selection: Self.maillage().r2, mode: .chemins)
        #expect(Self.traces(p).values.allSatisfy { $0 == 1 })
        #expect(p.liensRouteurs.filter(\.voisin).count == 1 && p.liensRouteurs.filter { $0.genre == .chemin }.count == 2)
    }

    /// Mode « tous » : les chemins sont masques, les trois liens radio se montrent, une trace chacun.
    @Test func modeTous() {
        let (p, _) = Self.projeterMaillage(selection: Self.maillage().r1, mode: .tous)
        #expect(Self.traces(p).count == 3 && Self.traces(p).values.allSatisfy { $0 == 1 })
        #expect(p.liensRouteurs.allSatisfy { $0.genre == .radio && !$0.voisin })
    }

    /// Sans selection, en mode « chemins » : les deux chemins seuls (les voisins ne se montrent qu'a la selection).
    @Test func sansSelection() {
        let (p, _) = Self.projeterMaillage(selection: nil, mode: .chemins)
        #expect(Self.traces(p).count == 2 && Self.traces(p).values.allSatisfy { $0 == 1 })
    }
}
