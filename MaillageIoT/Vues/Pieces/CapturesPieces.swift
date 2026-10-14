import AppKit
import ImageIO
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI
import UniformTypeIdentifiers

/// Images de la vue par pieces rendues par l'app elle-meme, en mode demo (`--args -demo -captures
/// <dossier>` pour la demo de Thread, `--args -demo-zigbee -captures <dossier>` pour celle de Zigbee, chacune seule),
/// pour la relecture (spec de la vue par pieces, section 10) : 2D, envol, 3D, zooms,
/// pieces isolees, survol, la fiche du chef (du pont pour Zigbee), la legende repliee ; puis les etages (polissage C, section 7) :
/// la grille 2 x 2 dans une fenetre carree, la meme fenetre en rangee, le jardin dans la maison, un etage isole en 2D
/// et en 3D, une piece isolee depuis son etage. La maison de demo a son jardin au niveau du rez-de-chaussee, hors de
/// la maison (`NomsDemo.places()`) ; dans la fenetre des images, la legende ouverte ou repliee, sa grille est la
/// rangee (la zone visible, section 3.3). Puis un appareil a mi-chemin de son glissement vers une autre piece
/// (polissage D, section 6). Zigbee y ajoute la fiche d'un appareil final qui garde son parent d'avant, le mode focus en
/// 2D et en 3D, et la fiche d'un routeur, ses voisins deplies (etape 5 : l'historique invente de la demo,
/// `MaillageDemoZigbee.historique`), puis la page Reglages › Pont Hue, liee a un pont invente. Sans fenetre ni capture
/// d'ecran ; l'app quitte ensuite. `ImageRenderer` ne rend ni la fenetre ni le verre : le haut de la fenetre et la
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
    /// de la demo, celle des pieces choisies (« Placer dans une piece… »), posee a mi-chemin de son glissement ;
    /// `listeVoisins`, `changementsDeplies`, `periode` : ce que la fiche de Zigbee montre (liste des voisins entendus
    /// depliee, lignes de changements regroupes du journal depliees, periode des courbes ; nil, 24 h).
    struct Cas {
        var nom: String
        var poser: (MoteurPieces, ScenePieces) -> Void
        var legendeRepliee = false
        var taille = CapturesPieces.taille
        var grille = true
        var places = NomsDemo.places()
        var deplacer: PiecesRouteurs?
        var listeVoisins = false
        var changementsDeplies = false
        var periode: PeriodeCourbes?

        /// Un cas de la demo de Zigbee : sa maison, nommee par Maison, sur quatre etages, son jardin hors de la maison.
        static func zigbee(_ nom: String, legendeRepliee: Bool = false, taille: CGSize = CapturesPieces.taille,
                           grille: Bool = true, places: PlacesGardees = NomsDemo.placesEtagees(etagee: true),
                           deplacer: PiecesRouteurs? = nil, listeVoisins: Bool = false, changementsDeplies: Bool = false,
                           periode: PeriodeCourbes? = nil, poser: @escaping (MoteurPieces, ScenePieces) -> Void) -> Cas {
            Cas(nom: nom, poser: poser, legendeRepliee: legendeRepliee, taille: taille, grille: grille, places: places,
                deplacer: deplacer, listeVoisins: listeVoisins, changementsDeplies: changementsDeplies, periode: periode)
        }
    }

    /// L'appareil inconnu de la demo, que seule la sonde connait (« Non identifie · 041F », sans piece), place dans la
    /// cuisine.
    static var appareilDansLaCuisine: PiecesRouteurs {
        var p = PiecesRouteurs()
        p.choisir("Cuisine", appareil: IdNoeud(.thread, "E0000000000000FF"), domicile: NomsDemo.maison.domicile ?? "")
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
        Cas(nom: "12-2d-survol") { m, _ in m.poserSurvol(IdNoeud(.thread, "9A28601B74FF90A7")) },
        Cas(nom: "13-2d-fiche-du-chef") { m, _ in m.selection = IdNoeud(.thread, "Apple TV 4K") },
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

    /// Le routeur inconnu de la demo de Zigbee, que le pont ne connait pas (sans piece), place dans la cuisine.
    static var appareilZigbeeDansLaCuisine: PiecesRouteurs {
        var p = PiecesRouteurs()
        p.choisir("Cuisine", appareil: IdNoeud(.zigbee, NomsDemo.Ieee.inconnu), domicile: NomsDemo.domicile)
        return p
    }

    /// Les images de la demo de Zigbee, dans l'ordre : les memes vues que celles de Thread sur sa maison, puis la fiche du
    /// pont, celle d'un appareil final endormi, le mode focus, la fiche d'un routeur (voisins deplies, sur 7 j, journal
    /// regroupe replie puis deplie).
    static let casZigbee: [Cas] = [
        .zigbee("01-2d") { _, _ in },
        .zigbee("02-envol-30") { m, _ in m.poserBascule(0.3) },
        .zigbee("03-envol-55") { m, _ in m.poserBascule(0.55) },
        .zigbee("04-envol-80") { m, _ in m.poserBascule(0.8) },
        .zigbee("05-3d") { m, _ in m.poserBascule(1) },
        .zigbee("06-3d-tournee") { m, _ in
            m.poserBascule(1)
            m.poserAzimut(-1.9)
        },
        .zigbee("07-2d-zoom-salon") { m, sc in m.poserZoom(echelle: 2.2, vers: m.centrePiece(piece(sc, "Salon"))) },
        .zigbee("08-2d-mi-distance") { m, _ in m.poserZoom(echelle: 0.5, vers: nil) },
        .zigbee("09-2d-loin") { m, _ in m.poserZoom(echelle: 0.36, vers: nil) },
        .zigbee("10-3d-isolee-salon") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Salon"))
        },
        .zigbee("11-2d-isolee-chambre") { m, sc in m.poserIsolement(piece(sc, "Chambre")) },
        .zigbee("12-2d-survol") { m, _ in m.poserSurvol(IdNoeud(.zigbee, NomsDemo.Ieee.lampeChambreAmis)) },
        .zigbee("13-2d-fiche-du-pont") { m, _ in m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.pont) },
        .zigbee("14-2d-legende-repliee", legendeRepliee: true) { _, _ in },
        .zigbee("15-2d-carree-2x2", taille: CapturesPieces.carree) { _, _ in },
        .zigbee("16-2d-carree-en-rangee", taille: CapturesPieces.carree, grille: false) { _, _ in },
        .zigbee("17-3d-jardin-dedans", places: NomsDemo.placesEtagees(etagee: true, dehors: false)) { m, _ in m.poserBascule(1) },
        .zigbee("18-2d-etage-isole") { m, sc in m.poserEtageIsole(etage(sc, "Étage")) },
        .zigbee("19-3d-etage-isole") { m, sc in
            m.poserBascule(1)
            m.poserEtageIsole(etage(sc, "Étage"))
        },
        .zigbee("20-3d-terrasse-depuis-le-jardin") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Terrasse"), depuisEtage: true)
        },
        .zigbee("21-2d-appareil-en-route", deplacer: appareilZigbeeDansLaCuisine) { m, sc in
            m.poserTransition(0.5)
            let sansPiece = sc.pieces.firstIndex { $0.nom == .sansPiece } ?? 0
            m.poserZoom(echelle: 1, vers: m.centrePiece(sansPiece))
        },
        // La fiche d'un appareil final endormi, avec son parent d'avant (pointille).
        .zigbee("22-2d-fiche-telecommande") { m, _ in m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.telecommandeChambre) },
        // Le mode focus (etape 5) : la lampe de la chambre, son chemin jusqu'au pont, ses dependants et ses voisins
        // restent nets, le reste s'estompe ; en 2D puis en 3D.
        .zigbee("25-2d-focus-lampe-chambre") { m, _ in m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeChambre) },
        .zigbee("26-3d-focus-lampe-chambre") { m, _ in
            m.poserBascule(1)
            m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeChambre)
        },
        // La fiche d'un routeur, la liste de ses voisins depliee, et son historique : le changement de chemin marque.
        .zigbee("27-2d-fiche-lampe-bureau", listeVoisins: true) { m, _ in
            m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeBureau)
        },
        // La meme fiche sur 7 j : les changements de chemin proches se fondent en un repere marque de leur nombre.
        .zigbee("28-2d-fiche-lampe-bureau-7j", periode: .semaine) { m, _ in
            m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeBureau)
        },
        // Le journal de la fiche, ses changements de chemin d'une meme heure en une ligne : repliee, puis depliee ; et
        // l'alternance de deux relais, celle du detecteur de l'abri (journal regroupe).
        .zigbee("5c-fiche-lampe-bureau-journal-replie") { m, _ in m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeBureau) },
        .zigbee("5c-fiche-lampe-bureau-journal-deplie", changementsDeplies: true) { m, _ in
            m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.lampeBureau)
        },
        .zigbee("5c-fiche-detecteur-abri-journal-deplie", changementsDeplies: true) { m, _ in
            m.selection = IdNoeud(.zigbee, NomsDemo.Ieee.detecteurAbri)
        },
    ]

    /// Evenements inventes des captures du journal regroupe de Zigbee : la lampe du bureau hesite entre plusieurs relais,
    /// le detecteur de l'abri entre deux parents, dans l'heure qui precede la fin de la demo (le changement de la demo
    /// s'y ajoute).
    static var evenementsHesitants: [Evenement] {
        func changement(_ type: TypeEvenement, _ ieee: String, _ nom: String, _ minutes: Double, _ avant: String,
                        _ apres: String) -> Evenement {
            Evenement(date: MaillageDemoZigbee.fin.addingTimeInterval(-minutes * 60), type: type, sujet: Sujet(id: ieee, nom: nom),
                      avant: avant, apres: apres, details: ["ieee": ieee])
        }
        let b = NomsDemo.Ieee.lampeBureau, d = NomsDemo.Ieee.detecteurAbri
        return [changement(.cheminChange, b, "Lampe bureau", 48, "Lampadaire salon", "Lampe chambre"),
                changement(.cheminChange, b, "Lampe bureau", 31, "Lampe chambre", "Plafonnier salon"),
                changement(.cheminChange, b, "Lampe bureau", 14, "Plafonnier salon", "Pont Hue"),
                changement(.parentChange, d, "Détecteur abri", 44, "Prise terrasse", "Ruban cuisine"),
                changement(.parentChange, d, "Détecteur abri", 29, "Ruban cuisine", "Prise terrasse"),
                changement(.parentChange, d, "Détecteur abri", 12, "Prise terrasse", "Ruban cuisine")]
    }

    /// Le pont invente de l'image des Reglages : adresse de documentation, identifiant et modele inventes.
    static let pontDeCapture = PontRetenu(adresse: "192.0.2.10", identifiant: "C0FFEEFFFE012345", modele: "Hue Bridge",
                                          manuel: false)

    /// L'image de Reglages › Pont Hue, lie au pont invente, avec les noms de la demo (`23-reglages-pont`). Rend son nom,
    /// ou nil si le rendu a echoue. (L'image de Reglages › Maison, avec le bilan de la fusion des noms, vient avec
    /// l'onglet Maison de la tache 10.)
    static func ecrireReglagesPont(dans dossier: String, noms: NomsZigbee) -> String? {
        let pont = NomsPont(capture: pontDeCapture, noms: noms)
        return ecrireReglages(ReglagesPont().environment(pont), nom: "23-reglages-pont", dans: dossier)
    }

    /// Une page des Reglages rendue hors ecran par AppKit (`cacheDisplay`, dans une fenetre jamais montree), en sombre, a
    /// la largeur des Reglages, ecrite sous `nom`.png ; rend son nom, ou nil si le rendu a echoue.
    static func ecrireReglages(_ page: some View, nom: String, dans dossier: String) -> String? {
        let vue = Form { Section { page } }
            .formStyle(.grouped)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
        return ecrireHote(vue, nom: nom, dans: dossier)
    }

    /// Une vue rendue hors ecran par AppKit (`cacheDisplay`, dans une fenetre jamais montree), en sombre, a la taille que
    /// la vue demande, ecrite sous `nom`.png en 2x ; rend son nom, ou nil si le rendu a echoue.
    static func ecrireHote(_ vue: some View, nom: String, dans dossier: String) -> String? {
        let hote = NSHostingView(rootView: vue)
        hote.appearance = NSAppearance(named: .darkAqua)
        hote.frame = CGRect(origin: .zero, size: hote.fittingSize)
        let fenetre = NSWindow(contentRect: hote.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        fenetre.appearance = NSAppearance(named: .darkAqua)
        fenetre.isReleasedWhenClosed = false
        fenetre.contentView = hote
        hote.layoutSubtreeIfNeeded()
        defer { fenetre.contentView = nil }
        // En 2x, comme les autres images, quel que soit l'ecran.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(hote.bounds.width * 2),
                                         pixelsHigh: Int(hote.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = hote.bounds.size
        hote.cacheDisplay(in: hote.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        ecrire(image, vers: (dossier as NSString).appendingPathComponent(nom + ".png"))
        return nom
    }

    /// Le moteur d'un cas, prepare comme dans la boucle des images : la taille, la scene de la demo (`e`), puis, pour
    /// `deplacer`, celle des pieces choisies, avec sa transition, enfin l'etat du cas, pose sur la scene que porte le
    /// moteur. Un cas `deplacer` sans transition (la scene choisie ne change rien) est une erreur : l'image sortirait
    /// sans appareil en route.
    static func preparer(_ c: Cas, surveillance s: Surveillance, reseau r: Reseau?,
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

    /// Ecrit les images de la demo de `protocole` dans `dossier` (la demo de Zigbee : sa maison nommee par Maison, sur quatre
    /// etages, l'historique et les evenements inventes des captures) ; rend leurs noms.
    @discardableResult
    static func ecrire(dans dossier: String, surveillance s: Surveillance, protocole: Protocole,
                       sonde: SondeMaillageThread, sondeZigbee: SondeMaillageZigbee, nomsMaison: NomsPasseur,
                       nomsPont: NomsPont) -> [String] {
        try? FileManager.default.createDirectory(atPath: dossier, withIntermediateDirectories: true)
        let r: Reseau?
        let liste: [Cas]
        switch protocole {
        case .thread:
            guard let reseau = s.thread.reseau else { return [] }
            r = reseau
            liste = cas
        case .zigbee:
            s.zigbee.noms.maison = NomsDemo.maisonFusionnee
            s.zigbee.historiqueDeCapture(MaillageDemoZigbee.historique)
            s.evenementsDeCapture(evenementsHesitants, de: .zigbee)
            guard s.zigbee.aUnReseau else { return [] }
            r = nil
            liste = casZigbee
        }
        let palette = Palette(sombre: true)
        // Hauteur d'une vue de la fenetre, rendue pour une capture, a la largeur `largeur` (sinon la sienne).
        func hauteur(_ vue: some View, largeur: CGFloat? = nil) -> CGFloat {
            NSHostingView(rootView: vue.frame(width: largeur).pourCapture(s, sonde, nomsMaison, sondeZigbee: sondeZigbee,
                                                                         nomsPont: nomsPont)).fittingSize.height
        }
        // Marge du haut : la hauteur du haut de la fenetre, mesuree comme dans la fenetre.
        let haut = hauteur(HautPieces(moteur: MoteurPieces(), troisD: .constant(false), zigbeeSeul: protocole == .zigbee))
        let marges = (FenetrePieces.margeHaut(bas: haut), FenetrePieces.margeBas(pile: nil))
        var noms: [String] = []
        for c in liste {
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
                let fiche = hauteur(FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil),
                                               listeDepliee: c.listeVoisins, changementsDeplies: c.changementsDeplies) {},
                                    largeur: largeur)
                repliee = repliee || FenetrePieces.repliDePlace(hauteur: taille.height, margeHaut: m.marges.haut,
                                                                legende: ouverte, fiche: fiche)
                let pile = hauteur(VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                    LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee)
                    FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil),
                               listeDepliee: c.listeVoisins, changementsDeplies: c.changementsDeplies) {}
                }, largeur: largeur)
                m.marges.bas = FenetrePieces.margeBas(pile: pile)
                m.poserTaille(taille)
            }
            // Deux passages : le premier pose les noms, le second les dessine a leur place.
            var image: CGImage?
            for _ in 0..<2 {
                let rendu = ImageRenderer(content: VueCapture(moteur: m, palette: palette, legendeRepliee: repliee,
                                                              listeVoisins: c.listeVoisins,
                                                              changementsDeplies: c.changementsDeplies)
                    .environment(\.periodeCapture, c.periode)
                    .frame(width: taille.width, height: taille.height)
                    .pourCapture(s, sonde, nomsMaison, sondeZigbee: sondeZigbee, nomsPont: nomsPont))
                rendu.scale = 2
                image = rendu.cgImage
            }
            guard let image else { continue }
            ecrire(image, vers: (dossier as NSString).appendingPathComponent(c.nom + ".png"))
            noms.append(c.nom)
        }
        // Zigbee : la page Reglages › Pont Hue, liee a un pont invente. (Le journal de la demo de Zigbee attend les textes
        // d'evenements des deux protocoles, tache 13.)
        if protocole == .zigbee, let nom = ecrireReglagesPont(dans: dossier, noms: NomsDemo.maisonPont) { noms.append(nom) }
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
    var listeVoisins = false
    var changementsDeplies = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(gradient: palette.fond, center: UnitPoint(x: 0.3, y: 0.35), startRadius: 0, endRadius: 900)
            Canvas { ctx, taille in moteur.image(&ctx, taille: taille, echelle: 2, palette: palette) }
            HautPieces(moteur: moteur, troisD: .constant(moteur.troisD), zigbeeSeul: moteur.entree?.protocoles == [.zigbee])
            FeuxDeCapture()
            VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                Spacer()
                LigneDuBas(moteur: moteur, entree: moteur.entree, legendeForcee: legendeRepliee)
                if let id = moteur.selection {
                    FicheNoeud(id: id, entree: moteur.entree, instant: surveillance.maintenant,
                               aRenommer: .constant(nil), listeDepliee: listeVoisins,
                               changementsDeplies: changementsDeplies) {}
                }
            }
            .padding(FenetrePieces.bord)
        }
        .coordinateSpace(.named(VuePieces.espace))
    }
}

extension View {
    /// Ce qu'une vue de la fenetre lit dans une capture : la surveillance, les sondes et les noms de la
    /// demo (Maison, pont), l'apparence sombre, et le rendu de capture.
    func pourCapture(_ s: Surveillance, _ sonde: SondeMaillageThread, _ noms: NomsPasseur,
                     sondeZigbee: SondeMaillageZigbee, nomsPont: NomsPont) -> some View {
        environment(\.capturePieces, true)
            .environment(\.colorScheme, .dark)
            .environment(s)
            .environment(sonde)
            .environment(sondeZigbee)
            .environment(noms)
            .environment(nomsPont)
    }
}
