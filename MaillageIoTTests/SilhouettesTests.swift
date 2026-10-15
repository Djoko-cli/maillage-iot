import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

/// Etape 3b, tache 3 : les silhouettes. Zigbee est un hexagone, pointe en haut, dont les sommets sont sur le rayon du
/// noeud (le cercle circonscrit) ; ses routeurs et le pont Hue sont violets, un violet que ni les etats ni le bleu des
/// routeurs de bordure de Thread n'emploient. Thread garde le rond. Les ondes, le cercle, l'anneau pointille et
/// l'anneau de selection restent ronds, au-dela du rayon : l'hexagone n'y touche pas. La legende dit les deux
/// protocoles par une ligne « Thread / Zigbee », seulement quand la scene les a tous les deux.
@MainActor
@Suite("Silhouettes : l'hexagone violet de Zigbee")
struct SilhouettesTests {
    typealias Apparence = DessinNoeud.Apparence
    typealias Entree = LegendePieces.Entree
    typealias Lecture = LegendePieces.Lecture

    /// Une couleur en sRGB, composantes de 0 a 1.
    static func rvb(_ c: Color) throws -> (r: Double, v: Double, b: Double) {
        let n = try #require(NSColor(c).usingColorSpace(.sRGB))
        return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
    }

    /// Les pixels d'un dessin de noeud, rendu a l'echelle 2 : `largeur` et `hauteur` en points, RVBA de 8 bits.
    static func pixels(largeur: CGFloat, hauteur: CGFloat, _ dessin: @escaping (inout GraphicsContext) -> Void) throws
        -> (largeur: Int, octets: [UInt8]) {
        let p = try LegendePiecesZigbeeTests.pixels(Canvas { ctx, _ in dessin(&ctx) }.frame(width: largeur, height: hauteur))
        return (p.largeur, p.octets)
    }

    // MARK: La forme

    /// Les six sommets de l'hexagone : sur le rayon `r`, le premier pointe en haut, a 60 degres l'un de l'autre.
    @Test func sommetsDeLHexagone() {
        let c = CGPoint(x: 30, y: 20)
        let s = DessinNoeud.sommetsHexagone(centre: c, rayon: 16)
        #expect(s.count == 6)
        for (k, p) in s.enumerated() {
            #expect(abs(hypot(p.x - c.x, p.y - c.y) - 16) < 1e-9, "sommet \(k) sur le rayon circonscrit")
            let angle = atan2(p.y - c.y, p.x - c.x) * 180 / .pi
            let attendu = -90.0 + 60 * Double(k)
            #expect(abs((angle - attendu).remainder(dividingBy: 360)) < 1e-9, "sommet \(k) a \(angle) degres")
        }
        #expect(abs(s[0].x - c.x) < 1e-9 && s[0].y < c.y, "pointe en haut")
        #expect(abs(s[3].x - c.x) < 1e-9 && s[3].y > c.y, "pointe en bas")
        // Un cote vertical, et non une pointe, a droite et a gauche : le rond fait les rayons, l'hexagone moins.
        #expect(abs(s[1].x - s[2].x) < 1e-9 && abs(s[1].x - (c.x + 16 * cos(.pi / 6))) < 1e-9)
    }

    /// `hexagoneZigbee` : un routeur (sphere facettee), un appareil (pastille) et un disparu (anneau) de Zigbee dessinent
    /// un hexagone pointe en haut dont les sommets sont sur le rayon ; les memes de Thread, un cercle. Un rayon de
    /// 16 pt, pour que le sommet haut (a 16 pt) et le milieu du cote droit (a 13,9 pt) se distinguent du cercle (16 pt).
    @Test func hexagoneZigbee() throws {
        let p = Palette(sombre: true)
        let r: CGFloat = 16
        let centre = CGPoint(x: 30, y: 25)
        func alpha(_ a: Apparence, dx: Double, dy: Double) throws -> Int {
            let image = try Self.pixels(largeur: 60, hauteur: 50) { ctx in
                DessinNoeud.dessiner(&ctx, centre: centre, rayon: r, apparence: a, palette: p)
            }
            return Int(image.octets[(Int((centre.y + dy) * 2) * image.largeur + Int((centre.x + dx) * 2)) * 4 + 3])
        }
        let formes: [(String, Apparence, Apparence)] = [
            ("routeur", DessinNoeud.apparenceRouteur(inconnu: false, protocole: .zigbee), DessinNoeud.apparenceRouteur(inconnu: false)),
            ("appareil", DessinNoeud.apparenceAppareil(.joignable, protocole: .zigbee), DessinNoeud.apparenceAppareil(.joignable)),
            ("disparu", DessinNoeud.apparenceAppareil(.disparu, protocole: .zigbee), DessinNoeud.apparenceAppareil(.disparu)),
        ]
        for (nom, hex, rond) in formes {
            #expect(hex.contour == .hexagone && rond.contour == .rond, Comment(rawValue: nom))
            // Un anneau n'est que son trait (2 pt, centre sur le contour) : on le sonde sur le sommet meme ; la sphere et la
            // pastille, pleines, un peu en dedans.
            let anneau = hex.forme == .anneau
            // La pointe en haut est sur le rayon : le haut du noeud est plein (sa pointe), a 1 pt dessous.
            let haut = try alpha(hex, dx: 0, dy: -Double(r) + (anneau ? 0.3 : 1))
            #expect(haut > 200, "\(nom) : la pointe en haut (\(haut))")
            // Le milieu du cote droit est a 0,87 r : a 0,99 r, le cercle est rempli (ou son trait), l'hexagone non (hors
            // le halo de la sphere et de la pastille).
            let droite = try alpha(hex, dx: Double(r) * 0.99, dy: 0)
            let cercle = try alpha(rond, dx: Double(r) * 0.99, dy: 0)
            #expect(cercle > 200 && cercle - droite > 100, "\(nom) : un cote a droite, non un arc (\(droite) contre \(cercle))")
            // Les sommets lateraux sont sur le rayon : a 30 degres, le noeud est plein (a 0,9 r).
            let f = anneau ? 0.98 : 0.9
            let oblique = try alpha(hex, dx: Double(r) * f * cos(.pi / 6), dy: -Double(r) * f * sin(.pi / 6))
            #expect(oblique > 200, "\(nom) : le sommet a 30 degres (\(oblique))")
        }
    }

    /// Les noeuds d'une scene de Zigbee : hexagonaux, routeurs violets ; la legende et `apparence` n'ont qu'un moyen.
    @Test func lesNoeudsDeZigbeeSontHexagonaux() throws {
        let (scene, _, _) = try FusionVuesTests.sceneZigbee()
        for n in scene.noeuds {
            let a = DessinNoeud.apparence(n, etat: .joignable, principale: true)
            #expect(a.contour == .hexagone, "\(n.id)")
            if n.genre != .appareil { #expect(a.couleur == .routeurZigbee || a.couleur == .routeurInconnu) }
            // Meme ou principale dit le contraire : un hexagone ne change pas de partition.
            #expect(a == DessinNoeud.apparence(n, etat: .joignable, principale: false))
        }
        #expect(scene.noeuds.contains { $0.genre == .centre })
    }

    // MARK: La couleur

    /// `routeurZigbeeViolet` : les routeurs de Zigbee et le pont Hue ont un seul violet, que la palette donne ; il est
    /// loin de chaque autre couleur de la vue (le bleu d'un routeur de bordure de Thread, le jaune d'une autre
    /// partition, le vert, l'orange, le rouge et le gris des etats, le jaune pale de l'anneau, ceux des liens et du chef).
    @Test func routeurZigbeeViolet() throws {
        let p = Palette(sombre: true)
        let (scene, _, _) = try FusionVuesTests.sceneZigbee()
        let centre = try #require(scene.noeuds.first { $0.genre == .centre })
        let routeur = try #require(scene.noeuds.first { $0.genre == .routeur && !$0.inconnu })
        for n in [centre, routeur] {
            #expect(DessinNoeud.apparence(n, etat: nil, principale: true).couleur == .routeurZigbee, "pont compris : \(n.id)")
        }
        #expect(DessinNoeud.couleur(.routeurZigbee, palette: p) == p.routeurZigbee)
        #expect(DessinNoeud.couleur(.routeurZigbee, palette: Palette(sombre: false)) == p.routeurZigbee, "le meme sur fond clair")
        #expect(LegendePieces.signe(.routeurZigbee) == .noeud(Apparence(forme: .sphere(halo: 5), couleur: .routeurZigbee,
                                                                         contour: .hexagone), rayon: LegendePieces.rayonRouteur))
        // Un violet : la teinte entre 255 et 285 degres, assez saturee et claire pour se voir sur le fond sombre.
        let v = try Self.rvb(p.routeurZigbee)
        let c = NSColor(red: v.r, green: v.v, blue: v.b, alpha: 1)
        #expect(c.hueComponent > 255.0 / 360 && c.hueComponent < 285.0 / 360, "teinte \(c.hueComponent * 360)")
        #expect(c.saturationComponent > 0.4 && c.brightnessComponent > 0.8)
        // Loin des autres : la distance euclidienne en sRGB, et la teinte, de chacune.
        let autres: [(String, Color)] = [
            ("routeur de bordure", p.routeur(principale: true)), ("autre partition", p.routeur(principale: false)),
            ("routeur inconnu", p.routeurInconnu), ("joignable", p.appareil(.joignable)),
            ("partition coupee", p.appareil(.partitionCoupee)), ("disparu", p.appareil(.disparu)),
            ("inconnu", p.appareil(.inconnu)), ("anneau verifie", p.anneauVerifie), ("zone", p.zone),
            ("lien bon", p.lienSonde(3)), ("lien moyen", p.lienSonde(2)), ("lien faible", p.lienSonde(1)),
            ("lien inconnu", p.lienSonde(nil)), ("chef", Palette.jauneChef), ("batterie", p.batterieFaible),
        ]
        for (nom, couleur) in autres {
            let a = try Self.rvb(couleur)
            let distance = ((a.r - v.r) * (a.r - v.r) + (a.v - v.v) * (a.v - v.v) + (a.b - v.b) * (a.b - v.b)).squareRoot()
            #expect(distance > 0.25, "le violet est trop proche de \(nom) : \(distance)")
        }
        // Le bleu d'un routeur de bordure s'en distingue par la teinte : plus de 40 degres.
        let bleu = try Self.rvb(p.routeur(principale: true))
        let hb = NSColor(red: bleu.r, green: bleu.v, blue: bleu.b, alpha: 1).hueComponent
        #expect(abs(hb - c.hueComponent) * 360 > 40, "bleu \(hb * 360), violet \(c.hueComponent * 360)")
    }

    /// `routeurDeBordureBleu` : Thread ne change pas ; ses routeurs de bordure gardent le bleu et le rond, et la legende
    /// de « routeur de bordure » aussi.
    @Test func routeurDeBordureBleu() throws {
        let p = Palette(sombre: true)
        let bleu = try Self.rvb(p.routeur(principale: true))
        #expect(abs(bleu.r - 0.38) < 1e-6 && abs(bleu.v - 0.65) < 1e-6 && abs(bleu.b - 0.98) < 1e-6, "le bleu d'avant")
        let jaune = try Self.rvb(p.routeur(principale: false))
        #expect(abs(jaune.r - 0.98) < 1e-6 && abs(jaune.v - 0.75) < 1e-6 && abs(jaune.b - 0.14) < 1e-6)
        let (_, _, e) = try NomsSceneTests.demo()
        for n in e.scene.noeuds {
            let a = try #require(e.apparences[n.id])
            #expect(a.contour == .rond && a.couleur != .routeurZigbee, "\(n.id) : Thread reste rond")
        }
        let borduriers = e.scene.noeuds.filter { $0.genre != .appareil && !$0.inconnu }
        #expect(!borduriers.isEmpty)
        #expect(borduriers.allSatisfy { e.apparences[$0.id]?.couleur == .routeur(principale: true) || e.apparences[$0.id]?.couleur == .routeur(principale: false) })
        #expect(LegendePieces.signe(.routeur) == .noeud(Apparence(forme: .sphere(halo: 5), couleur: .routeur(principale: true)),
                                                          rayon: LegendePieces.rayonRouteur))
        #expect(LegendePieces.signe(.routeur) != LegendePieces.signe(.routeurZigbee))
    }

    // MARK: Les ornaments restent ronds, au-dela du rayon

    /// Les ondes, le cercle, l'anneau pointille et l'anneau de selection d'un hexagone de rayon 7 (routeur, appareil,
    /// disparu) : aucun pixel de plus que le meme hexagone sans l'ornement ne tombe a moins de 1,5 pt de son rayon, donc
    /// sur aucun de ses sommets ; l'ornement existe (des pixels de plus). La pastille de batterie est a droite du nom, hors
    /// du noeud (`RenduCanvas`) : elle ne touche pas l'hexagone.
    @Test func ornementsHorsDuHexagone() throws {
        let p = Palette(sombre: true)
        let r: CGFloat = 7
        let centre = CGPoint(x: 40, y: 30)
        func rendu(_ a: Apparence, selection: Bool) throws -> (largeur: Int, octets: [UInt8]) {
            try Self.pixels(largeur: 80, hauteur: 60) { ctx in
                DessinNoeud.dessiner(&ctx, centre: centre, rayon: r, apparence: a, palette: p)
                if selection { DessinNoeud.dessinerSelection(&ctx, centre: centre, rayon: r, apparence: a, palette: p) }
            }
        }
        let bases = [("routeur", DessinNoeud.apparenceRouteur(inconnu: false, protocole: .zigbee)),
                     ("appareil", DessinNoeud.apparenceAppareil(.joignable, protocole: .zigbee)),
                     ("disparu", DessinNoeud.apparenceAppareil(.disparu, protocole: .zigbee))]
        var ornements: [(String, (inout Apparence) -> Void, Bool)] = []
        ornements.append(("ondes", { $0.sonde = true }, false))
        ornements.append(("cercle", { $0.cercle = true }, false))
        ornements.append(("anneau pointille", { $0.verifie = true }, false))
        ornements.append(("selection", { _ in }, true))
        ornements.append(("selection autour des ondes", { $0.sonde = true }, true))
        for (nomBase, base) in bases {
            let sans = try rendu(base, selection: false)
            for (nom, poser, selection) in ornements {
                var a = base
                poser(&a)
                let avec = try rendu(a, selection: selection)
                var plusProche = Double.infinity
                var nombre = 0
                for y in 0..<(avec.octets.count / 4 / avec.largeur) {
                    for x in 0..<avec.largeur {
                        let i = (y * avec.largeur + x) * 4
                        // L'encre qu'ajoute l'ornement ; le flou d'un halo varie de quelques octets d'un rendu a l'autre.
                        let ecart = (0..<4).map { abs(Int(avec.octets[i + $0]) - Int(sans.octets[i + $0])) }.max() ?? 0
                        guard ecart > 24 else { continue }
                        nombre += 1
                        let d = hypot((Double(x) + 0.5) / 2 - Double(centre.x), (Double(y) + 0.5) / 2 - Double(centre.y))
                        plusProche = min(plusProche, d)
                    }
                }
                #expect(nombre > 20, "\(nomBase) : \(nom) existe (\(nombre) pixels)")
                #expect(plusProche > Double(r) + 1.5,
                        "\(nomBase) : \(nom) a \(plusProche) pt du centre, dans l'hexagone de rayon \(r)")
            }
        }
    }

    // MARK: La legende

    /// `Lecture.protocoles` : ceux dont la scene a un noeud ; la ligne « Thread / Zigbee » ne se montre qu'avec les deux.
    /// Elle n'ajoute ni ne retire aucune entree.
    @Test func ligneDeProtocolesSeulementAvecLesDeux() {
        let t = idt("T1"), z = idz("Z1")
        let thread = Lecture(couleurs: [t: .routeur(principale: true), idt("T2"): .appareil(.joignable)])
        let zigbee = Lecture(couleurs: [z: .routeurZigbee, idz("Z2"): .appareil(.joignable)])
        let deux = Lecture(couleurs: [t: .routeur(principale: true), z: .routeurZigbee])
        #expect(thread.protocoles == [.thread] && zigbee.protocoles == [.zigbee] && deux.protocoles == [.thread, .zigbee])
        #expect(Lecture().protocoles.isEmpty)
        #expect(!LegendePieces.montreLesProtocoles(thread), "Thread seul : pas de ligne")
        #expect(!LegendePieces.montreLesProtocoles(zigbee), "Zigbee seul : pas de ligne")
        #expect(!LegendePieces.montreLesProtocoles(Lecture()), "rien")
        #expect(LegendePieces.montreLesProtocoles(deux), "les deux : la ligne")
        // Un noeud sans couleur dessinee (inconnu, sonde, chef) compte aussi.
        #expect(LegendePieces.montreLesProtocoles(Lecture(couleurs: [t: .routeur(principale: true)], chefs: [z])))
        #expect(LegendePieces.entrees(deux) == [.routeur, .routeurZigbee])
        #expect(LegendePieces.rubriques(deux).map(\.groupe) == [.routeurs])
    }

    /// Le rond et l'hexagone de la ligne : un noeud de chaque protocole, tel que la scene le dessine (le routeur de bordure
    /// bleu et rond de Thread, le routeur violet et hexagonal de Zigbee), par `DessinNoeud` comme tous les signes.
    @Test func signesDeLaLigneDeProtocoles() {
        #expect(LegendePieces.signeProtocole(.thread)
                == .noeud(DessinNoeud.apparenceRouteur(inconnu: false, principale: true), rayon: LegendePieces.rayonRouteur))
        #expect(LegendePieces.signeProtocole(.zigbee)
                == .noeud(DessinNoeud.apparenceRouteur(inconnu: false, protocole: .zigbee), rayon: LegendePieces.rayonRouteur))
        guard case .noeud(let rond, _) = LegendePieces.signeProtocole(.thread),
              case .noeud(let hexagone, _) = LegendePieces.signeProtocole(.zigbee) else {
            Issue.record("deux signes de noeud")
            return
        }
        #expect(rond.contour == .rond && hexagone.contour == .hexagone)
        #expect(rond.couleur == .routeur(principale: true) && hexagone.couleur == .routeurZigbee)
        #expect(LegendePieces.nomProtocole(.thread) == "Thread" && LegendePieces.nomProtocole(.zigbee) == "Zigbee")
    }

    /// Les entrees communes (joignable, disparu, sonde) restent rondes, quelle que soit la scene ; celles de Zigbee seul
    /// (routeur, inconnu du pont, injoignable) prennent l'hexagone ; celles de Thread restent rondes.
    @Test func entreesCommunesRondesEntreesDeZigbeeHexagonales() {
        func contour(_ e: Entree) -> DessinNoeud.Contour? {
            if case .noeud(let a, _) = LegendePieces.signe(e) { a.contour } else { nil }
        }
        for e in [Entree.joignable, .disparu, .sonde, .verifiee, .partitionCoupee, .sansAdresse, .routeur, .routeurSimple,
                  .nonIdentifie, .autrePartition] {
            #expect(contour(e) == .rond, "\(e)")
        }
        for e in [Entree.routeurZigbee, .nonIdentifieZigbee, .injoignable] {
            #expect(contour(e) == .hexagone, "\(e)")
        }
        // Le coordinateur est la couronne de son nom (`LibellesNoeuds`), comme dans la scene : un glyphe, sans contour.
        #expect(contour(.coordinateur) == nil && LegendePieces.signe(.coordinateur) == .glyphe(LibellesNoeuds.couronne, routeur: true))
    }

    /// La ligne prend une ligne de texte (14 pt) et son ecart (7 pt) de plus dans le panneau ouvert ; replie, rien ne change.
    /// Les marges de la vue (`margeBas`, `repliDePlace`) lisent la hauteur mesuree de la legende ouverte : elles suivent.
    @Test func hauteurDeLaLigneDeProtocoles() {
        let rubriques = LegendePieces.rubriques(Lecture(couleurs: [idt("T1"): .routeur(principale: true), idz("Z1"): .routeurZigbee,
                                                                    idt("T2"): .appareil(.joignable)]))
        func taille(_ avec: Bool, repliee: Bool = false) -> CGSize {
            NSHostingView(rootView: LegendePieces(rubriques: rubriques, ligneProtocoles: avec, repliee: .constant(repliee))).fittingSize
        }
        let ecart = taille(true).height - taille(false).height
        #expect(abs(ecart - (LegendePieces.hauteurLigne + LegendePieces.ecartLigneProtocoles)) < 0.5, "ecart \(ecart)")
        #expect(LegendePieces.hauteurLigne + LegendePieces.ecartLigneProtocoles == 21)
        #expect(taille(true).width == taille(false).width, "la ligne n'elargit pas le panneau")
        #expect(taille(true, repliee: true) == taille(false, repliee: true), "repliee : l'etiquette seule")
        // La legende vide n'est pas montree, avec ou sans la ligne.
        #expect(NSHostingView(rootView: LegendePieces(rubriques: [], ligneProtocoles: true, repliee: .constant(false))).fittingSize
                == NSHostingView(rootView: LegendePieces(rubriques: [], repliee: .constant(false))).fittingSize)
    }
}
