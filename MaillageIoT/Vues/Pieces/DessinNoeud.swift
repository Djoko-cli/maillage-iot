import MaillageCoeur
import SwiftUI

/// Dessin d'un noeud, le meme que celui du graphe d'avant (spec de la vue par pieces, section 5) :
/// routeur en sphere brillante (degrade du blanc vers sa couleur, decale en haut a gauche) avec un
/// halo, appareil en pastille pleine de la couleur de son etat avec un halo, appareil disparu en
/// anneau ; cercle bleu autour d'un routeur Thread qui n'est pas de bordure ; ondes de part et d'autre de la sonde ;
/// anneau blanc de la selection ; pastille orange d'une batterie faible. Le protocole se lit au contour (spec 3.1 et 6.7) :
/// Thread est rond, Zigbee un hexagone, pointe en haut, dont les sommets sont sur le rayon du noeud (le cercle
/// circonscrit) ; les ornements (cercle, anneau pointille, ondes, anneau de selection) restent ronds, au-dela du rayon :
/// ils ne touchent aucun sommet.
enum DessinNoeud {
    /// Couleur d'un noeud, resolue par la palette au dessin.
    enum Couleur: Hashable {
        case routeur(principale: Bool)
        /// Routeur de Zigbee, pont Hue compris : violet, une teinte que ni les etats ni le bleu des routeurs de bordure de
        /// Thread n'emploient.
        case routeurZigbee
        /// Routeur que seule la sonde connait.
        case routeurInconnu
        case appareil(EtatAffiche)
    }

    enum Forme: Hashable {
        /// Sphere brillante et son halo (rayon de l'ombre, en points).
        case sphere(halo: CGFloat)
        case pastille
        /// Appareil disparu.
        case anneau
    }

    /// Le contour d'un noeud : le rond de Thread, l'hexagone de Zigbee.
    enum Contour: Hashable {
        case rond
        case hexagone
    }

    struct Apparence: Hashable {
        var forme: Forme
        var couleur: Couleur
        /// Le cercle bleu d'un routeur qui n'est pas de bordure (demande de Djoko du 08/10).
        var cercle = false
        /// Les ondes de la sonde elle-meme (demande de Djoko du 08/10).
        var sonde = false
        /// L'anneau pointille jaune d'un appareil joignable que la sonde a trouve, alors qu'il n'annonce plus
        /// d'adresse (variante B, choisie par Djoko le 12/10).
        var verifie = false
        /// Le rond (Thread) ou l'hexagone (Zigbee) de la forme ; les ornements restent ronds.
        var contour: Contour = .rond
    }

    /// Apparence d'un noeud : sphere pour un routeur de bordure (Thread), un routeur ou le coordinateur (Zigbee) ou un
    /// routeur que seule la sonde connait, pastille pour un appareil, anneau pour un appareil disparu, avec un cercle
    /// s'il route (Thread). `etat` : celui de l'appareil ; `principale` : la partition du noeud est la principale
    /// (Zigbee n'a qu'une partition : ses routeurs sont toujours de la couleur de la principale, et n'ont ni cercle ni
    /// anneau). Sans valeur par defaut : un oubli ferait d'un routeur Thread d'une autre partition un routeur de la principale. La legende reprend les memes (`apparenceRouteur`, `apparenceAppareil`).
    /// `sonde` : le noeud est la sonde elle-meme (ses ondes) ; `verifie` : l'appareil est joignable parce que la
    /// sonde l'a trouve (son anneau).
    static func apparence(_ n: ScenePieces.Noeud, etat: EtatAffiche?, principale: Bool, sonde: Bool = false,
                          verifie: Bool = false) -> Apparence {
        let zigbee = n.id.protocole == .zigbee
        var a = switch n.genre {
        case .centre, .routeur:
            apparenceRouteur(centre: n.genre == .centre, inconnu: n.inconnu, principale: principale, protocole: n.id.protocole)
        case .appareil:
            zigbee ? apparenceAppareil(n.inconnu ? .inconnu : etat, protocole: .zigbee)
                : apparenceAppareil(etat, routeur: n.routeur, verifie: verifie)
        }
        a.sonde = sonde
        return a
    }

    /// La sonde : un appareil joignable et ses ondes, tel que la legende le montre.
    static var apparenceSonde: Apparence {
        var a = apparenceAppareil(.joignable)
        a.sonde = true
        return a
    }

    /// Un routeur : sphere brillante, au halo de 10 pour le centre de sa partition, de 5 sinon ; grise s'il n'est
    /// connu que de la sonde, sinon de la couleur de sa partition, principale ou non. `protocole` : celui du noeud ; un
    /// routeur de Zigbee (le pont compris) est un hexagone violet, sans partition (`principale` n'y compte pas).
    static func apparenceRouteur(centre: Bool = false, inconnu: Bool, principale: Bool = true,
                                 protocole: Protocole = .thread) -> Apparence {
        let forme = Forme.sphere(halo: centre ? 10 : 5)
        switch protocole {
        case .thread:
            return Apparence(forme: forme, couleur: inconnu ? .routeurInconnu : .routeur(principale: principale))
        case .zigbee:
            return Apparence(forme: forme, couleur: inconnu ? .routeurInconnu : .routeurZigbee, contour: .hexagone)
        }
    }

    /// Un appareil : pastille de la couleur de son etat (inconnu sans etat), anneau s'il a disparu ; entoure du cercle
    /// bleu s'il route, sauf disparu (il ne route plus) ; entoure de l'anneau pointille jaune s'il est joignable
    /// grace a la sonde (`verifie`, sans effet sur un autre etat).
    static func apparenceAppareil(_ etat: EtatAffiche?, routeur: Bool = false, verifie: Bool = false,
                                  protocole: Protocole = .thread) -> Apparence {
        let e = etat ?? .inconnu
        return Apparence(forme: e == .disparu ? .anneau : .pastille, couleur: .appareil(e),
                         cercle: routeur && e != .disparu, verifie: verifie && e == .joignable,
                         contour: protocole == .zigbee ? .hexagone : .rond)
    }

    /// L'anneau d'un appareil verifie : jaune, de 2 points, en tirets de 3 pour 3. Son rayon est celui du point plus
    /// 4 pt pour un point de 8 (maquette : un point de 8, un anneau de 12), proportionnel si le point change de taille.
    static let epaisseurAnneauVerifie: CGFloat = 2
    static let tiretsAnneauVerifie: [CGFloat] = [3, 3]
    static func rayonAnneauVerifie(_ r: CGFloat) -> CGFloat { r + 4 * r / 8 }

    /// Le cercle d'un routeur : 1,5 point, a 2 points de sa pastille ; il s'etend de `ecartCercle` au-dela d'elle.
    static let epaisseurCercle: CGFloat = 1.5
    static let ecartCercle: CGFloat = 2 + epaisseurCercle
    /// Les ondes de la sonde : de chaque cote, deux arcs de 70 degres, a 3 et 6 points de sa pastille, de 1,2 point, de
    /// la couleur de son etat (le second plus pale) ; elles s'etendent de `ecartOndes` au-dela d'elle.
    static let epaisseurOndes: CGFloat = 1.2
    static let ecartOndes: CGFloat = 6 + epaisseurOndes / 2

    static func couleur(_ c: Couleur, palette: Palette) -> Color {
        switch c {
        case .routeur(let p): palette.routeur(principale: p)
        case .routeurZigbee: palette.routeurZigbee
        case .routeurInconnu: palette.routeurInconnu
        case .appareil(let e): palette.appareil(e)
        }
    }

    /// Les six sommets de l'hexagone de rayon circonscrit `r`, centre en `c` : le premier pointe en haut, les autres de
    /// 60 degres en 60 degres, dans le sens des aiguilles d'une montre.
    static func sommetsHexagone(centre c: CGPoint, rayon r: CGFloat) -> [CGPoint] {
        (0..<6).map { k in
            let angle = Double(k) * .pi / 3 - .pi / 2
            return CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
        }
    }

    /// Le contour du noeud : un cercle de rayon `r`, ou l'hexagone de rayon circonscrit `r` (`sommetsHexagone`).
    static func trace(centre c: CGPoint, rayon r: CGFloat, _ contour: Contour) -> Path {
        switch contour {
        case .rond:
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .hexagone:
            var chemin = Path()
            chemin.addLines(sommetsHexagone(centre: c, rayon: r))
            chemin.closeSubpath()
            return chemin
        }
    }

    /// Les six facettes de la sphere hexagonale : un triangle du centre a chaque cote, eclairci du cote de la lumiere (en
    /// haut a gauche, d'ou vient le reflet du degrade) et assombri du cote oppose. Elles tiennent dans l'hexagone.
    private static func dessinerFacettes(_ ctx: inout GraphicsContext, centre c: CGPoint, rayon r: CGFloat) {
        let s = sommetsHexagone(centre: c, rayon: r)
        for k in 0..<6 {
            var facette = Path()
            facette.addLines([c, s[k], s[(k + 1) % 6]])
            facette.closeSubpath()
            // La normale de la facette est au milieu de son cote : de -60 degres, de 60 en 60 ; la lumiere vient de -135.
            let eclairage = cos((Double(k) * 60 - 60 + 135) * .pi / 180)
            ctx.fill(facette, with: .color(eclairage > 0 ? Color.white.opacity(0.22 * eclairage)
                                                          : Color.black.opacity(0.16 * -eclairage)))
        }
    }

    /// Le noeud, centre en `centre`, de rayon `rayon`.
    static func dessiner(_ ctx: inout GraphicsContext, centre c: CGPoint, rayon r: CGFloat, apparence: Apparence,
                         palette: Palette) {
        let contour = trace(centre: c, rayon: r, apparence.contour)
        let couleur = couleur(apparence.couleur, palette: palette)
        switch apparence.forme {
        case .sphere(let halo):
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: couleur.opacity(0.8), radius: halo))
                l.fill(contour, with: .radialGradient(Gradient(colors: [.white.opacity(0.9), couleur]),
                                                      center: CGPoint(x: c.x - r / 3, y: c.y - r / 3),
                                                      startRadius: 0, endRadius: r * 1.3))
            }
            if apparence.contour == .hexagone { dessinerFacettes(&ctx, centre: c, rayon: r) }
        case .pastille:
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: couleur.opacity(0.8), radius: 4))
                l.fill(contour, with: .color(couleur))
            }
        case .anneau:
            ctx.stroke(contour, with: .color(couleur), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        if apparence.cercle {
            let a = r + ecartCercle - epaisseurCercle / 2
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - a, y: c.y - a, width: 2 * a, height: 2 * a)),
                       with: .color(palette.routeur(principale: true)), lineWidth: epaisseurCercle)
        }
        if apparence.verifie {
            let a = rayonAnneauVerifie(r)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - a, y: c.y - a, width: 2 * a, height: 2 * a)),
                       with: .color(palette.anneauVerifie),
                       style: StrokeStyle(lineWidth: epaisseurAnneauVerifie, dash: tiretsAnneauVerifie))
        }
        if apparence.sonde {
            for (ecart, opacite) in [(CGFloat(3), 0.9), (6, 0.55)] {
                var ondes = Path()
                for milieu in [0.0, 180.0] {
                    // Chaque arc a part : sans ce saut, `addArc` relierait la fin du premier au debut du second.
                    let debut = Angle.degrees(milieu - 35).radians
                    ondes.move(to: CGPoint(x: c.x + (r + ecart) * cos(debut), y: c.y + (r + ecart) * sin(debut)))
                    ondes.addArc(center: c, radius: r + ecart, startAngle: .degrees(milieu - 35),
                                 endAngle: .degrees(milieu + 35), clockwise: false)
                }
                ctx.stroke(ondes, with: .color(couleur.opacity(opacite)),
                           style: StrokeStyle(lineWidth: epaisseurOndes, lineCap: .round))
            }
        }
    }

    /// Anneau du noeud selectionne, 4 points autour de sa pastille, de son cercle ou des ondes de la sonde.
    static func dessinerSelection(_ ctx: inout GraphicsContext, centre c: CGPoint, rayon r: CGFloat, apparence: Apparence,
                                  palette: Palette) {
        var a = r + 4 + (apparence.sonde ? ecartOndes : apparence.cercle ? ecartCercle : 0)
        // Celui d'un appareil verifie passe au-dela de son anneau pointille.
        if apparence.verifie { a = max(a, rayonAnneauVerifie(r) + epaisseurAnneauVerifie / 2 + 3) }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - a, y: c.y - a, width: 2 * a, height: 2 * a)),
                   with: .color(palette.selection), lineWidth: 2)
    }

    static let policePastille = Font.caption2.weight(.semibold)

    static var iconePastille: Text {
        Text(Image(systemName: "exclamationmark.triangle.fill")).font(policePastille)
    }

    static func textePastille(_ valeur: String) -> Text {
        Text(verbatim: valeur).font(policePastille)
    }

    /// Capsule de la pastille : 6 pt, l'icone, 3 pt, la valeur, 6 pt ; 2 pt dessus et dessous.
    static func taillePastille(icone: CGSize, valeur: CGSize) -> CGSize {
        CGSize(width: 6 + icone.width + 3 + valeur.width + 6, height: max(icone.height, valeur.height) + 4)
    }

    /// Pastille orange en surbrillance d'une batterie faible : petit triangle et texte, dans une
    /// capsule qui luit ; le milieu de son bord gauche en `gauche`.
    static func dessinerPastille(_ ctx: inout GraphicsContext, _ texte: String, gauche: CGPoint, palette: Palette) {
        let icone = ctx.resolve(iconePastille.foregroundStyle(palette.texteBatterieFaible))
        let valeur = ctx.resolve(textePastille(texte).foregroundStyle(palette.texteBatterieFaible))
        let ti = icone.measure(in: StylesNoms.grand)
        let tv = valeur.measure(in: StylesNoms.grand)
        let taille = taillePastille(icone: ti, valeur: tv)
        let cadre = CGRect(x: gauche.x, y: gauche.y - taille.height / 2, width: taille.width, height: taille.height)
        let capsule = Path(roundedRect: cadre, cornerRadius: cadre.height / 2)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: palette.batterieFaible.opacity(0.9), radius: 6))
            l.fill(capsule, with: .color(palette.batterieFaible))
        }
        ctx.draw(icone, at: CGPoint(x: cadre.minX + 6, y: cadre.midY), anchor: .leading)
        ctx.draw(valeur, at: CGPoint(x: cadre.minX + 6 + ti.width + 3, y: cadre.midY), anchor: .leading)
    }
}
