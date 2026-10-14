import MaillageCoeur
import SwiftUI

extension LegendePieces {
    /// Le signe d'une entree de la legende, tel que la scene le dessine (verification du polissage B, 02/10) : un
    /// noeud par `DessinNoeud` (la sphere brillante d'un routeur, avec son halo et son reflet ; la pastille d'un
    /// appareil ; l'anneau d'un disparu) ; un lien, un nom de noeud (des candidats), le glyphe d'un nom (la couronne du
    /// chef, la lune d'un endormi) et un repere « ailleurs » par `RenduCanvas` ; la pastille d'une pile par
    /// `DessinNoeud`.
    enum Signe: Equatable {
        /// Un noeud, de cette apparence, de ce rayon.
        case noeud(DessinNoeud.Apparence, rayon: CGFloat)
        /// Un lien radio entre routeurs, de la couleur de sa qualite.
        case lienRadio(qualite: Int?)
        /// Un lien vers un parent, d'un pixel ; un rattachement suppose, en pointilles.
        case lienEnfant(rattachement: Bool)
        /// Un nom de noeud, d'un routeur (12 pt) ou d'un appareil (11 pt).
        case nom(String, routeur: Bool)
        /// Le glyphe d'un nom de noeud, dans son texte, sans la pastille sombre du nom (reverification du 02/10).
        case glyphe(String, routeur: Bool)
        /// La pastille d'une batterie faible.
        case pastille(String)
        /// Un repere « ailleurs ».
        case ailleurs(String)
    }

    /// Hauteur d'une ligne de la legende : un texte de 11 pt, mesure.
    static let hauteurLigne: CGFloat = 14
    /// Zoom de la vue d'ensemble de reference (k : points par unite a la cible, divises par 24) : celui de la demo de
    /// deux etages de B a la taille des images (1440 x 900, en 2D), mesure le 02/10. La demo de C, a quatre plateaux, a
    /// une vue d'ensemble plus petite (0,47, en rangee) : la legende garde cette taille, decision de Djoko du 03/10
    /// (`LegendePiecesTests.tailleDesSignes`).
    static let zoomVueDEnsemble: CGFloat = 0.53
    /// Un noeud de la legende a la taille d'un noeud de la scene a ce zoom : son rayon naturel (`ScenePieces` : 13 pt
    /// pour un routeur de bordure, 7 pour un appareil) fois le zoom, et au plus la demi-hauteur d'une ligne de la
    /// legende : 6,9 et 3,7 pt.
    static let rayonRouteur = min(13 * zoomVueDEnsemble, hauteurLigne / 2)
    static let rayonAppareil = min(7 * zoomVueDEnsemble, hauteurLigne / 2)
    /// Opacite d'un lien au repos dans la scene (`SceneProjetee`) : 0,95 pour un lien radio, 0,28 pour un lien vers un
    /// parent ou un rattachement.
    static let opaciteLienRadio = 0.95
    static let opaciteLienEnfant = 0.28

    /// Le signe de chaque entree : un noeud de la meme apparence que dans la scene (`DessinNoeud.apparenceRouteur`,
    /// `apparenceAppareil`) ; la couronne et la lune des noms de la scene (`LibellesNoeuds`), seules : sans la pastille
    /// sombre de leur nom, « une ombre disgracieuse et inutile » dans la legende (reverification du 02/10) ; un lien de
    /// la scene.
    static func signe(_ e: Entree) -> Signe {
        switch e {
        case .routeur: .noeud(DessinNoeud.apparenceRouteur(inconnu: false, principale: true), rayon: rayonRouteur)
        case .routeurSimple: .noeud(DessinNoeud.apparenceAppareil(.joignable, routeur: true), rayon: rayonAppareil)
        case .nonIdentifie: .noeud(DessinNoeud.apparenceRouteur(inconnu: true, principale: true), rayon: rayonRouteur)
        case .autrePartition: .noeud(DessinNoeud.apparenceRouteur(inconnu: false, principale: false), rayon: rayonRouteur)
        case .chef: .glyphe(LibellesNoeuds.couronne, routeur: true)
        case .joignable: .noeud(DessinNoeud.apparenceAppareil(.joignable), rayon: rayonAppareil)
        case .verifiee: .noeud(DessinNoeud.apparenceAppareil(.joignable, verifie: true), rayon: rayonAppareil)
        case .sonde: .noeud(DessinNoeud.apparenceSonde, rayon: rayonAppareil)
        case .partitionCoupee: .noeud(DessinNoeud.apparenceAppareil(.partitionCoupee), rayon: rayonAppareil)
        case .sansAdresse: .noeud(DessinNoeud.apparenceAppareil(.sansAdresse), rayon: rayonAppareil)
        case .disparu: .noeud(DessinNoeud.apparenceAppareil(.disparu), rayon: rayonAppareil)
        case .endormi: .glyphe(LibellesNoeuds.lune, routeur: false)
        case .pile: .pastille(exemplePile)
        case .bonne: .lienRadio(qualite: 3)
        case .moyenne: .lienRadio(qualite: 2)
        case .faible: .lienRadio(qualite: 1)
        case .inconnue: .lienRadio(qualite: nil)
        case .versParent: .lienEnfant(rattachement: false)
        case .rattachement: .lienEnfant(rattachement: true)
        case .ailleurs: .ailleurs(exempleAilleurs)
        case .candidats: .nom(exempleCandidats, routeur: true)
        }
    }
}

/// Le signe d'une entree de la legende, dessine dans un `Canvas` par les fonctions du rendu de la scene (`dessiner`).
/// Sa place est celle du signe : un noeud, son disque (entoure du cercle d'un routeur, la place d'un routeur) ; un lien, 22 pt de long ; un nom, une pastille ou un repere,
/// leur taille dans la scene (`MesureNoms`) ; un glyphe, la largeur d'un noeud de son groupe (`largeurGlyphe`) et la
/// hauteur de son nom. Le halo d'une sphere ou d'une pastille, et un glyphe plus large que sa place, debordent autour,
/// sans prendre de place.
struct SigneLegende: View {
    let signe: LegendePieces.Signe
    @Environment(\.displayScale) private var echelle

    /// Longueur d'un lien.
    static let longueurLien: CGFloat = 22
    /// Place laissee autour du signe pour son halo.
    static let debord: CGFloat = 12
    /// Les noms et les pastilles, mesures comme ceux de la scene.
    private static let mesure = MesureNoms()

    var body: some View {
        let taille = Self.taille(signe)
        Color.clear
            .frame(width: taille.width, height: taille.height)
            .overlay {
                Canvas { ctx, _ in
                    Self.dessiner(signe, &ctx, dans: CGRect(origin: CGPoint(x: Self.debord, y: Self.debord), size: taille),
                                  echelle: echelle, palette: Palette(sombre: true))
                }
                .frame(width: taille.width + 2 * Self.debord, height: taille.height + 2 * Self.debord)
            }
    }

    /// Largeur de la place d'un glyphe (ronde finale du 02/10) : celle d'un noeud de son groupe, un routeur pour la
    /// couronne, un appareil pour la lune. Les textes des lignes 👑 et ☾ s'alignent ainsi sur ceux des autres signes du
    /// groupe ; a la place du glyphe (17 et 11 pt), ils etaient decales d'environ 3,5 pt vers la droite.
    static func largeurGlyphe(routeur: Bool) -> CGFloat {
        2 * (routeur ? LegendePieces.rayonRouteur : LegendePieces.rayonAppareil)
    }

    /// La place du signe ; un noeud entoure du cercle d'un routeur, celle d'un routeur de son groupe (son cercle deborde
    /// d'un tiers de point, comme un halo) ; la sonde, ses ondes en largeur (comme la pile, elle garde sa place).
    /// L'anneau d'un appareil verifie deborde comme un halo, sans prendre de place : les textes du groupe restent
    /// alignes.
    static func taille(_ s: LegendePieces.Signe) -> CGSize {
        switch s {
        case .noeud(let apparence, let rayon):
            apparence.sonde ? CGSize(width: 2 * (rayon + DessinNoeud.ecartOndes), height: 2 * rayon)
            : apparence.cercle ? CGSize(width: largeurGlyphe(routeur: true), height: largeurGlyphe(routeur: true))
            : CGSize(width: 2 * rayon, height: 2 * rayon)
        case .lienRadio, .lienEnfant: CGSize(width: longueurLien, height: 2)
        case .nom(let texte, let routeur): mesure.noeud(LibellesNoeuds.Libelle(texte: texte), routeur: routeur)
        case .glyphe(let texte, let routeur):
            CGSize(width: largeurGlyphe(routeur: routeur), height: mesure.glyphe(texte, routeur: routeur).height)
        case .pastille(let texte): mesure.pastille(texte)
        case .ailleurs(let texte): mesure.ailleurs(texte)
        }
    }

    /// Le signe dans sa place `r`, par les fonctions du rendu de la scene, avec ses parametres : un noeud au centre ;
    /// un lien d'un bord a l'autre, a mi-hauteur (1 pt de marge pour ses bouts ronds), avec l'opacite d'un lien au
    /// repos ; un nom, une pastille ou un repere dans sa place ; un glyphe centre sur elle, comme un noeud, sans fond.
    /// `echelle` : pixels par point (un lien vers un parent fait un pixel, comme dans la scene).
    static func dessiner(_ s: LegendePieces.Signe, _ ctx: inout GraphicsContext, dans r: CGRect, echelle: CGFloat,
                         palette: Palette) {
        let a = CGPoint(x: r.minX + 1, y: r.midY)
        let b = CGPoint(x: r.maxX - 1, y: r.midY)
        switch s {
        case .noeud(let apparence, let rayon):
            DessinNoeud.dessiner(&ctx, centre: CGPoint(x: r.midX, y: r.midY), rayon: rayon, apparence: apparence,
                                 palette: palette)
        case .lienRadio(let qualite):
            RenduCanvas.dessinerLienRadio(&ctx, de: a, a: b, qualite: qualite, opacite: LegendePieces.opaciteLienRadio,
                                          palette: palette)
        case .lienEnfant(let rattachement):
            RenduCanvas.dessinerLienEnfant(&ctx, de: a, a: b, rattachement: rattachement,
                                           opacite: LegendePieces.opaciteLienEnfant, eclaire: false, pixel: 1 / echelle,
                                           palette: palette)
        case .nom(let texte, let routeur):
            let nom = ctx.resolve(RenduCanvas.texteNom(texte, routeur: routeur, fort: false, palette: palette))
            RenduCanvas.dessinerNom(&ctx, nom, dans: r, palette: palette)
        case .glyphe(let texte, let routeur):
            let glyphe = ctx.resolve(RenduCanvas.texteNom(texte, routeur: routeur, fort: false, palette: palette))
            ctx.draw(glyphe, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        case .pastille(let texte):
            DessinNoeud.dessinerPastille(&ctx, texte, gauche: CGPoint(x: r.minX, y: r.midY), palette: palette)
        case .ailleurs(let texte):
            let repere = ctx.resolve(RenduCanvas.texteAilleurs(texte, palette: palette))
            RenduCanvas.dessinerAilleurs(&ctx, repere, dans: r, palette: palette)
        }
    }
}
