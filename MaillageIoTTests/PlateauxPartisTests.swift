import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// Quand une piece passe d'un plateau a un autre, un seul mouvement (phase 11, tache 2) : le plateau qui part reste dessine
/// a sa place pendant la transition et s'efface, son nom avec lui ; la piece glisse depuis lui ; le plateau qui arrive
/// apparait. Le plateau parti n'est garde que par le moteur, hors de la geometrie : il ne se clique pas, ne se survole pas,
/// n'entre ni dans le menu ni dans le cadrage. En 2D, les plateaux et les pieces glissent sur la meme duree.
///
/// La scene est celle de la tache 1 (`PlateauxInchangesTests`) : l'Abri, seul dans la Zone 2 (a cote de la Zone 1, hors de
/// la maison), est range dans la Zone 1 (l'aller : la Zone 2 part), puis « Automatiquement » (le retour : elle arrive).
@MainActor
@Suite("Vue par pieces : le plateau qui part s'efface, la piece glisse")
struct PlateauxPartisTests {
    static let z1 = PlateauxInchangesTests.z1, z2 = PlateauxInchangesTests.z2, z3 = PlateauxInchangesTests.z3
    static let abri = "piece:Abri"

    /// Le moteur de la tache 1, fige (les transitions se posent a la main), en 2D ou en 3D, une image dessinee.
    static func moteur(_ fichier: URL, troisD: Bool, reduire: Bool = false) throws -> MoteurPieces {
        let (m, _) = try PlateauxInchangesTests.moteur(fichier)
        m.fige = true
        if troisD { m.poserBascule(1) }
        m.reduire = reduire
        MoteurPiecesTests.dessiner(m)
        return m
    }

    /// L'aller : l'Abri est range dans la Zone 1, la scene suivante est posee.
    static func aller(_ m: MoteurPieces) throws {
        m.rangerPiece(abri, dans: "Zone 1")
        m.installerMaintenant(try PlateauxInchangesTests.scene(m.places))
    }

    /// Le retour : « Automatiquement », l'Abri revient dans la Zone 2.
    static func retour(_ m: MoteurPieces) throws {
        m.rangerPiece(abri, dans: nil)
        m.installerMaintenant(try PlateauxInchangesTests.scene(m.places))
    }

    /// Finit la transition en cours par l'horloge (le moteur reste fige ensuite).
    static func finir(_ m: MoteurPieces) {
        m.fige = false
        m.reculerTransition(de: 5)
        MoteurPiecesTests.dessiner(m)
        m.fige = true
        MoteurPiecesTests.dessiner(m)
    }

    static func indice(_ m: MoteurPieces, piece cle: String) throws -> Int {
        try #require(m.entree?.scene.pieces.firstIndex { $0.id == cle })
    }

    static func indice(_ m: MoteurPieces, plateau cle: String) throws -> Int {
        try #require(m.entree?.scene.etages.firstIndex { $0.id == cle })
    }

    /// Le centre de l'Abri dans le monde, a l'image.
    static func centreAbri(_ m: MoteurPieces) throws -> SIMD3<Double> {
        try #require(m.centrePiece(try indice(m, piece: abri)))
    }

    /// Le nom d'etage d'indice `i` est pose a l'image.
    static func nomVu(_ m: MoteurPieces, _ i: Int) -> Bool {
        m.etiquettes.contains { $0.genre == .etage(i) && $0.vu }
    }

    /// Aucun plateau parti ne reste : ni dans le moteur, ni a l'image, ni son nom.
    static func aucunParti(_ m: MoteurPieces, _ cas: String) {
        let n = m.entree?.scene.etages.count ?? 0
        #expect(m.transition == nil, "\(cas) : la transition est finie")
        #expect(m.posesAffichees.plateauxPartis.isEmpty && m.posesAffichees.opacitesPlateaux.isEmpty, "\(cas)")
        #expect(m.projetee?.partis.isEmpty == true, "\(cas) : aucun plateau parti dessine")
        #expect(m.projetee?.opacitesEtages.isEmpty == true, "\(cas) : tous les noms d'etage sont nets")
        #expect(m.nomsEtagesPartis.isEmpty, "\(cas)")
        #expect(!m.etiquettes.contains { if case .etage(let i) = $0.genre { i >= n } else { false } },
                "\(cas) : aucun nom de plateau parti")
    }

    // MARK: L'aller : la Zone 2 part

    /// A t = 0 de la transition, l'Abri est a sa place d'avant, sur le plateau parti, dessine plein avec son nom ; a
    /// mi-chemin, l'Abri est entre ses deux places, le plateau et son nom a demi effaces ; a la fin, l'Abri est a sa place
    /// d'arrivee, le plateau et son nom ne sont plus dessines.
    @Test(arguments: [false, true]) func allerLaPieceGlisseDepuisLePlateauQuiPart(troisD: Bool) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: troisD)
        let avant = try Self.centreAbri(m)
        let zone2 = try Self.indice(m, plateau: Self.z2)
        let place2D = m.geometrie.centres2D[zone2], rayon = m.geometrie.rayons[zone2]
        try Self.aller(m)
        let tr = try #require(m.transition, "la piece change de plateau : une transition")
        #expect(tr.plateauxPartis.map(\.cle) == [Self.z2] && tr.plateauxArrivants.isEmpty)
        let parti = try #require(tr.plateauxPartis.first)
        #expect(parti.centre2D == place2D && parti.rayon == rayon && parti.opacite == 1, "a sa place et a son rayon d'avant")
        #expect(m.nomsEtagesPartis[Self.z2] == "Zone 2", "son nom est garde")
        let n = try #require(m.entree?.scene.etages.count)
        #expect(!(m.entree?.scene.etages.contains { $0.id == Self.z2 } ?? true) && m.geometrie.rayons.count == n,
                "hors de la geometrie")

        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        #expect(simd_distance(try Self.centreAbri(m), avant) < 1e-9, "t = 0 : l'Abri a sa place d'avant, sans saut")
        var p = try #require(m.projetee)
        #expect(p.partis.count == 1 && abs((p.partis.first?.opacite ?? 0) - 1) < 1e-9, "t = 0 : le plateau parti, plein")
        #expect(p.opacitesEtages[n] == 1 && p.ancresEtages[n] != nil && Self.nomVu(m, n), "t = 0 : son nom, plein")

        m.poserTransition(1)
        MoteurPiecesTests.dessiner(m)
        let i = try Self.indice(m, piece: Self.abri)
        let e1 = try #require(m.entree?.scene.pieces[i].etage)
        let c = m.geometrie.centrePlateau(e1, m.t)
        let fin = try Self.centreAbri(m)
        #expect(abs(fin.x - (c.x + m.positions[i].x)) < 1e-9 && abs(fin.z - (c.z + m.positions[i].y)) < 1e-9,
                "a la fin : sa place d'arrivee, sur la Zone 1")
        p = try #require(m.projetee)
        #expect(p.partis.isEmpty && p.ancresEtages[n] == nil && !Self.nomVu(m, n), "a la fin : ni le plateau, ni son nom")

        m.poserTransition(0.5)
        MoteurPiecesTests.dessiner(m)
        let mi = try Self.centreAbri(m), d = simd_distance(avant, fin)
        #expect(d > 1 && simd_distance(mi, avant) > 0.2 * d && simd_distance(mi, fin) > 0.2 * d, "a mi-chemin, en route")
        p = try #require(m.projetee)
        let o = try #require(p.partis.first?.opacite)
        #expect(o > 0.05 && o < 0.95, "a mi-chemin : le plateau s'efface (\(o))")
        #expect(p.opacitesEtages[n] == o && Self.nomVu(m, n), "son nom avec lui")
    }

    /// La fin de la transition, par l'horloge : plus rien du plateau parti.
    @Test(arguments: [false, true]) func finDeLaTransition(troisD: Bool) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: troisD)
        try Self.aller(m)
        m.poserTransition(0.3)
        MoteurPiecesTests.dessiner(m)
        #expect(m.projetee?.partis.count == 1)
        Self.finir(m)
        Self.aucunParti(m, "fin")
    }

    // MARK: Le retour : la Zone 2 arrive

    /// Le plateau qui arrive est transparent a t = 0, son nom aussi, et plein a la fin ; l'Abri part de sa place sur la
    /// Zone 1, sans saut.
    @Test(arguments: [false, true]) func retourLePlateauQuiArriveApparait(troisD: Bool) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: troisD)
        try Self.aller(m)
        Self.finir(m)
        let avant = try Self.centreAbri(m)
        try Self.retour(m)
        let tr = try #require(m.transition)
        #expect(tr.plateauxPartis.isEmpty && tr.plateauxArrivants == [Self.z2: 0])
        let zone2 = try Self.indice(m, plateau: Self.z2)
        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        #expect(simd_distance(try Self.centreAbri(m), avant) < 1e-9, "l'Abri part de sa place, sans saut")
        var p = try #require(m.projetee)
        let pl = try #require(p.plateaux.first { $0.etage == zone2 })
        #expect(pl.opacite < 1e-9 && p.opacitesEtages[zone2] == 0, "t = 0 : le plateau qui arrive et son nom, transparents")
        #expect(p.partis.isEmpty)
        m.poserTransition(0.5)
        MoteurPiecesTests.dessiner(m)
        p = try #require(m.projetee)
        let o = try #require(p.plateaux.first { $0.etage == zone2 }?.opacite)
        #expect(o > 0.05 && o < 0.95 && p.opacitesEtages[zone2] == o, "a mi-chemin : il apparait (\(o))")
        m.poserTransition(1)
        MoteurPiecesTests.dessiner(m)
        p = try #require(m.projetee)
        #expect(abs((p.plateaux.first { $0.etage == zone2 }?.opacite ?? 0) - 1) < 1e-9, "a la fin : plein")
        Self.finir(m)
        Self.aucunParti(m, "retour")
        #expect(abs((m.projetee?.plateaux.first { $0.etage == zone2 }?.opacite ?? 0) - 1) < 1e-9)
    }

    // MARK: Hors de tout ce qui se clique

    /// Le plateau parti ne se clique pas, ne se survole pas, n'est pas la cible du menu du clic droit, et son nom non plus ;
    /// il n'entre pas dans la geometrie, donc ni dans le cadrage, ni dans la sphere, ni dans la boite. Le temoin : avant
    /// l'aller, le meme point vise le disque de la Zone 2.
    @Test func lePlateauPartiNeSeCliquePas() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        let zone2 = try Self.indice(m, plateau: Self.z2)
        let proj = ProjectionScene(m.orbite, cadre: m.cadre)
        let c = m.geometrie.centrePlateau(zone2, 0), r = m.geometrie.rayons[zone2]
        // Un point du disque de la Zone 2, hors de l'Abri et de ses pastilles.
        let points = (0..<24).compactMap { k -> CGPoint? in
            let a = Double(k) * .pi / 12
            return proj.ecran(c + SIMD3(0.9 * r * cos(a), 0, 0.9 * r * sin(a)))
        }
        let point = try #require(points.first { m.cibleClic(en: $0) == .disque(zone2) }, "temoin : le disque de la Zone 2")
        let nom = try #require(m.etiquettes.first { $0.genre == .etage(zone2) && $0.vu }?.rect)
        #expect(m.cibleClic(en: CGPoint(x: nom.midX, y: nom.midY)) == .nomEtage(zone2), "temoin : son nom")
        #expect(m.cible(en: point) == .etage(Self.z2), "temoin : son menu")

        try Self.aller(m)
        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        let n = try #require(m.entree?.scene.etages.count)
        let p = try #require(m.projetee)
        let parti = try #require(p.partis.first)
        #expect(SceneProjetee.contient(parti.polygone, point), "le point est sur le plateau parti, dessine")
        #expect(m.disqueSous(point) == nil && m.cibleClic(en: point) == .fond, "son disque ne se clique pas")
        let rect = try #require(m.etiquettes.first { $0.genre == .etage(n) && $0.vu }?.rect)
        let surNom = CGPoint(x: rect.midX, y: rect.midY)
        #expect(m.nomEtageSous(surNom) == nil && m.nomEtageSous(surNom, marge: 2) == nil, "son nom ne se clique pas")
        for q in [point, surNom] {
            m.survoler(q)
            #expect(m.survolEtage == nil && m.survolNomEtage == nil && m.curseurForme == .fleche, "ne se survole pas")
            #expect(m.cible(en: q) != .etage(Self.z2) && m.cibleMenu != .etage(Self.z2), "pas de menu")
        }
        #expect(m.menuEtage(Self.z2) == nil)
        // Hors de la geometrie : la vue d'ensemble se cadre sans lui.
        #expect(m.geometrie.rayons.count == n && m.geometrieVisee.rayons.count == n)
        #expect(m.orbite == CameraScene.canonique(m.geometrie, aspect: m.aspect, u: 0))
    }

    // MARK: Interruptions

    /// Un aller-retour rapide : le retour arrive a mi-chemin de l'aller. L'Abri ne saute pas ; la Zone 2, qui s'effacait,
    /// revient depuis son opacite affichee, a sa place, et n'est plus un plateau parti.
    @Test(arguments: [false, true]) func allerRetourRapide(troisD: Bool) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: troisD)
        try Self.aller(m)
        m.poserTransition(0.5)
        MoteurPiecesTests.dessiner(m)
        let mi = try Self.centreAbri(m)
        let o = try #require(m.projetee?.partis.first?.opacite)
        let zone2Avant = try #require(m.posesAffichees.plateauxPartis.first)
        try Self.retour(m)
        let tr = try #require(m.transition)
        #expect(tr.plateauxPartis.isEmpty && abs((tr.plateauxArrivants[Self.z2] ?? -1) - o) < 1e-9,
                "la Zone 2 revient depuis son opacite affichee")
        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        #expect(simd_distance(try Self.centreAbri(m), mi) < 1e-9, "l'Abri ne saute pas")
        let zone2 = try Self.indice(m, plateau: Self.z2)
        let p = try #require(m.projetee)
        #expect(p.partis.isEmpty && abs((p.plateaux.first { $0.etage == zone2 }?.opacite ?? -1) - o) < 1e-9)
        let c = m.geometrie.centrePlateau(zone2, m.t), c0 = zone2Avant.centre(m.t)
        #expect(simd_distance(c, c0) < 1e-9, "la Zone 2 repart de la ou elle etait dessinee")
        Self.finir(m)
        Self.aucunParti(m, "aller-retour")
    }

    /// Une autre scene pendant l'aller, ou la Zone 2 reste partie : elle continue de s'effacer, depuis son opacite
    /// affichee, puis plus rien.
    @Test func autreScenePendantLAller() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        try Self.aller(m)
        m.poserTransition(0.5)
        MoteurPiecesTests.dessiner(m)
        let o = try #require(m.projetee?.partis.first?.opacite)
        let mi = try Self.centreAbri(m)
        // L'Abri est aussi garde a la main ailleurs dans la Zone 1 : une autre disposition, sans la Zone 2.
        let i = try Self.indice(m, piece: Self.abri)
        var places = m.places
        let e = try #require(m.entree)
        places.garder(m.positions[i] + SIMD2(0.5, 0.5), piece: Self.abri, etage: Self.z1, domicile: e.domicile)
        m.places = places
        m.installerMaintenant(try PlateauxInchangesTests.scene(places))
        let tr = try #require(m.transition)
        #expect(tr.plateauxPartis.map(\.cle) == [Self.z2] && abs((tr.plateauxPartis.first?.opacite ?? -1) - o) < 1e-9,
                "elle continue de s'effacer, depuis son opacite affichee")
        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        #expect(simd_distance(try Self.centreAbri(m), mi) < 1e-9, "sans saut")
        Self.finir(m)
        Self.aucunParti(m, "autre scene")
    }

    /// Un vol (une piece isolee), un envol (la bascule 2D / 3D) ou un glisser (l'Abri pris en route) pendant la transition :
    /// a la fin, aucun plateau parti ne reste.
    @Test(arguments: ["vol", "envol", "glisser"]) func mouvementPendantLaTransition(cas: String) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        m.fige = false
        try Self.aller(m)
        m.reculerTransition(de: 0.3)
        MoteurPiecesTests.dessiner(m)
        #expect(m.projetee?.partis.count == 1)
        switch cas {
        case "vol":
            m.isoler(try MoteurPiecesTests.indice(try #require(m.entree), "Salon"))
            #expect(m.vol != nil)
        case "envol":
            m.basculer(troisD: true)
            #expect(m.envol != nil)
        default:
            let i = try Self.indice(m, piece: Self.abri)
            let p = try MoteurPiecesTests.pointDePiece(m, i)
            m.glisser(p, depart: p)
            m.glisser(CGPoint(x: p.x + 20, y: p.y), depart: p)
            #expect(m.posesAffichees.pieces[Self.abri] == nil, "l'Abri est pris, pose")
            m.relacher(CGPoint(x: p.x + 20, y: p.y))
        }
        MoteurPiecesTests.dessiner(m)
        #expect(m.transition != nil && m.projetee?.partis.count == 1, "\(cas) : le plateau parti s'efface encore")
        m.debutVol -= 5
        m.debutEnvol -= 5
        m.reculerTransition(de: 5)
        MoteurPiecesTests.dessiner(m)
        MoteurPiecesTests.dessiner(m)
        #expect(!m.enMouvement)
        Self.aucunParti(m, cas)
    }

    // MARK: Reduire les animations

    /// « Reduire les animations » : tout est pose d'un coup, a l'aller comme au retour ; ni plateau parti, ni fondu.
    @Test(arguments: [false, true]) func reduirePoseToutDUnCoup(troisD: Bool) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: troisD, reduire: true)
        try Self.aller(m)
        #expect(m.transition == nil && m.glissementPlateaux == nil && m.posesAffichees == PosesScene())
        MoteurPiecesTests.dessiner(m)
        Self.aucunParti(m, "reduire, aller")
        let i = try Self.indice(m, piece: Self.abri)
        let e1 = try #require(m.entree?.scene.pieces[i].etage)
        let c = m.geometrie.centrePlateau(e1, m.t), fin = try Self.centreAbri(m)
        #expect(abs(fin.x - (c.x + m.positions[i].x)) < 1e-9 && abs(fin.z - (c.z + m.positions[i].y)) < 1e-9)
        try Self.retour(m)
        #expect(m.transition == nil && m.posesAffichees == PosesScene())
        MoteurPiecesTests.dessiner(m)
        Self.aucunParti(m, "reduire, retour")
        let zone2 = try Self.indice(m, plateau: Self.z2)
        #expect(abs((m.projetee?.plateaux.first { $0.etage == zone2 }?.opacite ?? 0) - 1) < 1e-9, "pose plein")
    }

    // MARK: Isolement

    /// Une piece isolee (le Salon, de la Zone 1) ou un etage isole (la Zone 1) pendant le choix : l'Abri ne saute pas, et le
    /// plateau parti reste sous le voile de l'isolement, comme les autres plateaux, a l'opacite qu'il avait avant le choix.
    @Test(arguments: ["piece", "etage"]) func isolementPendantLeChoix(cas: String) throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        if cas == "piece" {
            m.poserIsolement(try MoteurPiecesTests.indice(try #require(m.entree), "Salon"))
        } else {
            m.poserEtageIsole(try Self.indice(m, plateau: Self.z1))
        }
        MoteurPiecesTests.dessiner(m)
        let avant = try Self.centreAbri(m)
        let zone2 = try Self.indice(m, plateau: Self.z2)
        let voile = try #require(m.projetee?.plateaux.first { $0.etage == zone2 }?.opacite)
        #expect(abs(voile - 0.15) < 1e-9, "\(cas) : la Zone 2 est sous le voile")
        try Self.aller(m)
        m.poserTransition(0)
        MoteurPiecesTests.dessiner(m)
        #expect(simd_distance(try Self.centreAbri(m), avant) < 1e-9, "\(cas) : sans saut")
        let p = try #require(m.projetee)
        let zone3 = try Self.indice(m, plateau: Self.z3)
        let autre = try #require(p.plateaux.first { $0.etage == zone3 }?.opacite)
        #expect(abs(autre - 0.15) < 1e-9 && abs((p.partis.first?.opacite ?? 0) - voile) < 1e-9,
                "\(cas) : le plateau parti, sous le voile, comme avant le choix")
    }

    // MARK: Une seule duree en 2D

    /// En 2D, des niveaux changes accompagnes d'une transition de disposition : les plateaux glissent sur la duree du
    /// glissement des pieces, et non sur les 0,4 s des cases ; a 0,5 s, les uns et les autres sont encore en route.
    @Test func memeDureeEnDeuxD() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        m.fige = false
        try Self.aller(m)
        let tr = try #require(m.transition)
        let gl = try #require(m.glissementPlateaux, "les plateaux glissent vers la nouvelle grille")
        #expect(gl.duree2D == tr.plan.glissement.duree && gl.duree3D == tr.plan.glissement.duree)
        #expect(abs(gl.debut - tr.debut) < 0.05, "ensemble")
        m.reculerTransition(de: 0.5)
        MoteurPiecesTests.dessiner(m)
        #expect(m.glissementPlateaux != nil && m.transition != nil, "a 0,5 s, plateaux et pieces glissent encore")
        m.reculerTransition(de: 1)
        MoteurPiecesTests.dessiner(m)
        #expect(m.glissementPlateaux == nil && m.transition == nil)
    }

    /// Des niveaux changes sans transition de disposition (« Hors de la maison » decoche pour la Zone 2 : aucune piece ne
    /// bouge, tache 1) : les plateaux glissent seuls, en 0,4 s en 2D, comme avant.
    @Test func niveauxSeulsEnDeuxD() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let m = try Self.moteur(url, troisD: false)
        m.basculerDehors(Self.z2)
        m.installerMaintenant(try PlateauxInchangesTests.scene(m.places))
        #expect(m.entree?.scene.niveaux.dehors(Self.z2) == false)
        #expect(m.transition == nil, "aucune piece ne bouge")
        let gl = try #require(m.glissementPlateaux)
        #expect(gl.duree2D == CameraScene.dureeCases && gl.duree3D == CameraScene.dureeNiveaux)
        #expect(m.posesAffichees.plateauxPartis.isEmpty)
    }
}
