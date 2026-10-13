import AppKit
import ImageIO
import MaillageCoeur
import SwiftUI
import UniformTypeIdentifiers

/// Images de la vue par pieces rendues par l'app elle-meme, en mode demo (`--args -demo -captures
/// <dossier>`), pour la relecture (spec de la vue par pieces, section 10) : 2D, envol, 3D, zooms,
/// pieces isolees, survol, la fiche du chef, la legende repliee ; puis les etages (polissage C, section 7) :
/// la grille 2 x 2 dans une fenetre carree, la meme fenetre en rangee, le jardin dans la maison, un etage isole en 2D
/// et en 3D, une piece isolee depuis son etage. La maison de demo a son jardin au niveau du rez-de-chaussee, hors de
/// la maison (`NomsDemo.places()`) ; dans la fenetre des images, la legende ouverte ou repliee, sa grille est la
/// rangee (la zone visible, section 3.3). Puis un appareil a mi-chemin de son glissement vers une autre piece
/// (polissage D, section 6). Sans fenetre ni capture d'ecran ;
/// l'app quitte ensuite. `ImageRenderer` ne rend ni la fenetre ni le verre : le haut de la fenetre et la
/// fiche y sont dessines comme dans les maquettes (`capturePieces`), avec les trois boutons de la
/// fenetre a leur place (`FeuxDeCapture`).
@MainActor
enum CapturesPieces {
    /// Contenu d'une fenetre de 1440 x 900, en 2x.
    nonisolated static let taille = CGSize(width: 1440, height: 900)
    /// Une fenetre carree, ou la grille de la demo est 2 x 2, la legende ouverte (polissage C, sections 3.3 et 7).
    nonisolated static let carree = CGSize(width: 1000, height: 1000)

    /// Une image : son nom, l'etat a poser sur le moteur, et la legende repliee ; la taille de la fenetre, les etages
    /// en grille ou en rangee, et les places gardees, dont le choix de niveau du jardin ; `deplacer` : apres la scene
    /// de la demo, celle des pieces choisies (« Placer dans une piece… »), posee a mi-chemin de son glissement.
    struct Cas {
        var nom: String
        var poser: (MoteurPieces, ScenePieces) -> Void
        var legendeRepliee = false
        var taille = CapturesPieces.taille
        var grille = true
        var places = NomsDemo.places()
        var deplacer: PiecesRouteurs?
    }

    /// L'appareil inconnu de la demo, que seule la sonde connait (« Non identifie · 041F », sans piece), place dans la
    /// cuisine.
    static var appareilDansLaCuisine: PiecesRouteurs {
        var p = PiecesRouteurs()
        p.choisir("Cuisine", appareil: "E0000000000000FF", domicile: NomsDemo.maison.domicile ?? "")
        return p
    }

    /// Indice d'une piece de Maison de la scene (la premiere, sans elle).
    static func piece(_ scene: ScenePieces, _ nom: String) -> Int {
        scene.pieces.firstIndex { $0.nom == .maison(nom) } ?? 0
    }

    /// Indice d'un etage, une zone de Maison, de la scene (le premier, sans elle).
    static func etage(_ scene: ScenePieces, _ nom: String) -> Int {
        scene.etages.firstIndex { $0.nom == .zone(nom) } ?? 0
    }

    /// Les images, dans l'ordre : 2D, envol, 3D, zooms, pieces isolees, survol ; puis la fiche du chef de
    /// la demo, avec sa pastille, la vue relevee au-dessus d'elle ; et la legende repliee.
    static let cas: [Cas] = [
        Cas(nom: "01-2d") { _, _ in },
        Cas(nom: "02-envol-30") { m, _ in m.poserBascule(0.3) },
        Cas(nom: "03-envol-55") { m, _ in m.poserBascule(0.55) },
        Cas(nom: "04-envol-80") { m, _ in m.poserBascule(0.8) },
        Cas(nom: "05-3d") { m, _ in m.poserBascule(1) },
        Cas(nom: "06-3d-tournee") { m, _ in
            m.poserBascule(1)
            m.poserAzimut(-1.9)
        },
        Cas(nom: "07-2d-zoom-salon") { m, sc in m.poserZoom(echelle: 2.2, vers: m.centrePiece(piece(sc, "Salon"))) },
        Cas(nom: "08-2d-mi-distance") { m, _ in m.poserZoom(echelle: 0.5, vers: nil) },
        Cas(nom: "09-2d-loin") { m, _ in m.poserZoom(echelle: 0.36, vers: nil) },
        Cas(nom: "10-3d-isolee-salon") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Salon"))
        },
        Cas(nom: "11-2d-isolee-chambre") { m, sc in m.poserIsolement(piece(sc, "Chambre")) },
        Cas(nom: "12-2d-survol") { m, _ in m.poserSurvol("9A28601B74FF90A7") },
        Cas(nom: "13-2d-fiche-du-chef") { m, _ in m.selection = "Apple TV 4K" },
        Cas(nom: "14-2d-legende-repliee", poser: { _, _ in }, legendeRepliee: true),
        Cas(nom: "15-2d-carree-2x2", poser: { _, _ in }, taille: CapturesPieces.carree),
        Cas(nom: "16-2d-carree-en-rangee", poser: { _, _ in }, taille: CapturesPieces.carree, grille: false),
        Cas(nom: "17-3d-jardin-dedans", poser: { m, _ in m.poserBascule(1) }, places: NomsDemo.places(dehors: false)),
        Cas(nom: "18-2d-etage-isole") { m, sc in m.poserEtageIsole(etage(sc, "Étage")) },
        Cas(nom: "19-3d-etage-isole") { m, sc in
            m.poserBascule(1)
            m.poserEtageIsole(etage(sc, "Étage"))
        },
        Cas(nom: "20-3d-terrasse-depuis-le-jardin") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Terrasse"), depuisEtage: true)
        },
        Cas(nom: "21-2d-appareil-en-route", poser: { m, sc in
            m.poserTransition(0.5)
            let sansPiece = sc.pieces.firstIndex { $0.nom == .sansPiece } ?? 0
            m.poserZoom(echelle: 1, vers: m.centrePiece(sansPiece))
        }, deplacer: appareilDansLaCuisine),
    ]

    /// Le moteur d'un cas, prepare comme dans la boucle des images : la taille, la scene de la demo (`e`), puis, pour
    /// `deplacer`, celle des pieces choisies, avec sa transition, enfin l'etat du cas, pose sur la scene que porte le
    /// moteur. Un cas `deplacer` sans transition (la scene choisie ne change rien) est une erreur : l'image sortirait
    /// sans appareil en route.
    static func preparer(_ c: Cas, surveillance s: Surveillance, reseau r: Reseau,
                         marges: (haut: CGFloat, bas: CGFloat)) -> (m: MoteurPieces, e: EntreeScene) {
        let m = MoteurPieces(places: c.places)
        m.fige = true
        m.reglerGrille(c.grille)
        let e = EntreeScene(surveillance: s, reseau: r, places: m.places)
        m.marges = marges
        m.basGrille = marges.bas
        m.poserTaille(c.taille)
        m.installerMaintenant(e)
        m.poserTaille(c.taille)
        if let choix = c.deplacer {
            m.installerMaintenant(EntreeScene(surveillance: s, reseau: r, places: m.places, choix: choix))
        }
        precondition(c.deplacer == nil || m.transition != nil,
                     "\(c.nom) : la scene des pieces choisies ne change aucune disposition")
        guard let scene = m.scene else { preconditionFailure("\(c.nom) : le moteur n'a pas de scene") }
        c.poser(m, scene)
        return (m, e)
    }

    /// Ecrit les images dans `dossier` ; rend leurs noms.
    @discardableResult
    static func ecrire(dans dossier: String, surveillance s: Surveillance, sonde: SondeMaillage,
                       nomsMaison: NomsInternes) -> [String] {
        try? FileManager.default.createDirectory(atPath: dossier, withIntermediateDirectories: true)
        guard let r = s.reseau else { return [] }
        let palette = Palette(sombre: true)
        // Hauteur d'une vue de la fenetre, rendue pour une capture, a la largeur `largeur` (sinon la sienne).
        func hauteur(_ vue: some View, largeur: CGFloat? = nil) -> CGFloat {
            NSHostingView(rootView: vue.frame(width: largeur).pourCapture(s, sonde, nomsMaison)).fittingSize.height
        }
        // Marge du haut : la hauteur du haut de la fenetre, mesuree comme dans la fenetre.
        let haut = hauteur(HautPieces(moteur: MoteurPieces(), troisD: .constant(false)))
        let marges = (FenetrePieces.margeHaut(bas: haut), FenetrePieces.margeBas(pile: nil))
        var noms: [String] = []
        for c in cas {
            let taille = c.taille
            // La vue d'ensemble se cadre au-dessus de la legende ouverte : la hauteur mesuree de la rangee du bas,
            // comme dans la fenetre ; repliee, la marge d'avant. La grille se choisit sur cette zone visible, sans la
            // fiche (polissage C, section 3.3). La mesure se fait sur la scene de la demo, celle du cas sans son
            // deplacement.
            let mesure = EntreeScene(surveillance: s, reseau: r, places: c.places)
            let ouverte = hauteur(LigneDuBas(moteur: MoteurPieces(), entree: mesure, legendeForcee: false))
            let (m, e) = preparer(c, surveillance: s, reseau: r,
                                  marges: (marges.0, c.legendeRepliee ? marges.1 : FenetrePieces.margeBas(pile: ouverte)))
            // La fiche : la legende reste au-dessus d'elle (repliee si la place manque, comme dans la fenetre), et la
            // vue se cadre au-dessus de la pile mesuree.
            var repliee = c.legendeRepliee
            if let id = m.selection {
                let largeur = taille.width - 2 * FenetrePieces.bord
                let fiche = hauteur(FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil)) {},
                                    largeur: largeur)
                repliee = repliee || FenetrePieces.repliDePlace(hauteur: taille.height, margeHaut: m.marges.haut,
                                                                legende: ouverte, fiche: fiche)
                let pile = hauteur(VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                    LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee)
                    FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil)) {}
                }, largeur: largeur)
                m.marges.bas = FenetrePieces.margeBas(pile: pile)
                m.poserTaille(taille)
            }
            // Deux passages : le premier pose les noms, le second les dessine a leur place.
            var image: CGImage?
            for _ in 0..<2 {
                let rendu = ImageRenderer(content: VueCapture(moteur: m, palette: palette, legendeRepliee: repliee)
                    .frame(width: taille.width, height: taille.height)
                    .pourCapture(s, sonde, nomsMaison))
                rendu.scale = 2
                image = rendu.cgImage
            }
            guard let image else { continue }
            ecrire(image, vers: (dossier as NSString).appendingPathComponent(c.nom + ".png"))
            noms.append(c.nom)
        }
        return noms
    }

    static func ecrire(_ image: CGImage, vers chemin: String) {
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: chemin) as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

/// La vue d'une capture : le fond, la scene, le haut de la fenetre (avec ses trois boutons, et la ligne de niveau
/// sous le fil), la legende (ouverte, ou repliee), puis, dessous, la fiche du noeud choisi ; sans horloge ni geste.
struct VueCapture: View {
    @Environment(Surveillance.self) private var surveillance
    let moteur: MoteurPieces
    let palette: Palette
    var legendeRepliee = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(gradient: palette.fond, center: UnitPoint(x: 0.3, y: 0.35), startRadius: 0, endRadius: 900)
            Canvas { ctx, taille in moteur.image(&ctx, taille: taille, echelle: 2, palette: palette) }
            HautPieces(moteur: moteur, troisD: .constant(moteur.troisD))
            FeuxDeCapture()
            VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                Spacer()
                LigneDuBas(moteur: moteur, entree: moteur.entree, legendeForcee: legendeRepliee)
                if let id = moteur.selection {
                    FicheNoeud(id: id, entree: moteur.entree, instant: surveillance.maintenant,
                               aRenommer: .constant(nil)) {}
                }
            }
            .padding(FenetrePieces.bord)
        }
        .coordinateSpace(.named(VuePieces.espace))
    }
}

extension View {
    /// Ce qu'une vue de la fenetre lit dans une capture : la surveillance, la sonde et les noms de la
    /// demo, l'apparence sombre, et le rendu de capture.
    func pourCapture(_ s: Surveillance, _ sonde: SondeMaillage, _ noms: NomsInternes) -> some View {
        environment(\.capturePieces, true)
            .environment(\.colorScheme, .dark)
            .environment(s)
            .environment(sonde)
            .environment(noms)
    }
}
