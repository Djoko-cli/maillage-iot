// Dessine l'icone de Maillage IoT et les logos des onglets Thread et Zigbee des Reglages.
//
//   swift outils/icone/generer.swift            (depuis la racine du depot ; rien d'autre a installer)
//
// Ecrit, toujours les memes octets pour le meme programme :
//   - MaillageIoT/Ressources/AppIcon.icon/Assets/constellation.png : le calque de l'icone (1024 x 1024, opaque, plein
//     cadre : le systeme y applique son masque) ;
//   - outils/icone/tailles/icone_<n>.png : des APERCUS de l'icone, 16 a 1024 pixels (16, 32, 64, 128, 256, 512, 1024),
//     chacun dessine a sa taille (pas reduit : aux petites tailles la composition est simplifiee, moins de noeuds et plus
//     gros). L'app ne les utilise pas : elle n'embarque que le calque 1024 d'AppIcon.icon (format Icon Composer), et
//     macOS le reduit lui-meme pour le Dock, le Finder et le selecteur d'apps. Ils servent a juger le dessin a petite
//     taille, et `LogosEtIconeTests` n'en verifie que les dimensions ;
//   - MaillageIoT/Ressources/Logos.xcassets : les logos de Thread et de Zigbee, redessines en glyphes simplifies,
//     vectoriels et monochromes (PDF), declares « images modeles » pour que la barre d'outils des Reglages les teinte
//     comme les symboles SF voisins.
// Ni texte ni donnee reelle : des formes et des couleurs. Thread et Zigbee sont des marques de leurs titulaires (Thread
// Group, Connectivity Standards Alliance) ; les glyphes ne sont que des redessins simplifies, pour reconnaitre.
//
// Les noeuds ronds sont ceux de Thread (bleu, comme les routeurs de la scene), les noeuds hexagonaux, pointe en haut,
// ceux de Zigbee (violet 0,70 / 0,45 / 0,98, comme les routeurs Zigbee de la scene) ; les appareils terminaux sont
// verts (ronds) ou violet clair (hexagonaux). Le fond est celui de l'icone d'avant : un bleu profond, plus clair en
// haut a gauche.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func couleur(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [r, g, b, a].map { CGFloat($0) })!
}

func degrade(_ arrets: [(Double, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: rgb, colors: arrets.map { $0.1 } as CFArray, locations: arrets.map { CGFloat($0.0) })!
}

// MARK: - Icone

enum Famille { case thread, zigbee, vert, zigbeeTerminal }

struct Noeud {
    let famille: Famille
    let x: Double, y: Double, rayon: Double
    var halo: Double { famille == .vert || famille == .zigbeeTerminal ? 34 : 84 }
    var hexagone: Bool { famille == .zigbee || famille == .zigbeeTerminal }
}

struct Lien {
    let de: Int, a: Int
    var pointille = false
}

struct Composition {
    var noeuds: [Noeud]
    var liens: [Lien]
    /// Largeur du trait des liens pleins, dans le repere de 1024.
    var largeurLien: Double
    var anneauDuCentre: Bool
}

/// La composition complete (128 pixels et plus) : un chef rond au centre, des routeurs ronds (Thread) et hexagonaux
/// (Zigbee) autour, des appareils terminaux ronds verts et hexagonaux violet clair au bout de liens pointilles.
let complete: Composition = {
    let n: [Noeud] = [
        Noeud(famille: .thread, x: 512, y: 548, rayon: 72),    // 0 chef
        Noeud(famille: .thread, x: 300, y: 372, rayon: 40),    // 1 routeur Thread
        Noeud(famille: .thread, x: 736, y: 338, rayon: 40),    // 2
        Noeud(famille: .thread, x: 318, y: 744, rayon: 40),    // 3
        Noeud(famille: .zigbee, x: 800, y: 660, rayon: 58),    // 4 routeur Zigbee
        Noeud(famille: .zigbee, x: 600, y: 868, rayon: 52),    // 5
        Noeud(famille: .vert, x: 214, y: 250, rayon: 19),      // 6 appareils
        Noeud(famille: .vert, x: 500, y: 196, rayon: 19),      // 7
        Noeud(famille: .vert, x: 884, y: 470, rayon: 19),      // 8
        Noeud(famille: .vert, x: 168, y: 548, rayon: 19),      // 9
        Noeud(famille: .vert, x: 640, y: 470, rayon: 19),      // 10
        Noeud(famille: .vert, x: 420, y: 620, rayon: 19),      // 11
        Noeud(famille: .zigbeeTerminal, x: 906, y: 810, rayon: 24),  // 12
        Noeud(famille: .zigbeeTerminal, x: 428, y: 906, rayon: 24),  // 13
        Noeud(famille: .zigbeeTerminal, x: 826, y: 884, rayon: 24),  // 14
    ]
    let l: [Lien] = [
        Lien(de: 1, a: 2), Lien(de: 1, a: 0), Lien(de: 2, a: 0), Lien(de: 0, a: 4), Lien(de: 0, a: 3),
        Lien(de: 1, a: 3), Lien(de: 2, a: 4), Lien(de: 3, a: 5), Lien(de: 4, a: 5), Lien(de: 0, a: 5),
        Lien(de: 6, a: 1, pointille: true), Lien(de: 7, a: 1, pointille: true), Lien(de: 7, a: 2, pointille: true),
        Lien(de: 8, a: 2, pointille: true), Lien(de: 9, a: 3, pointille: true), Lien(de: 10, a: 2, pointille: true),
        Lien(de: 11, a: 3, pointille: true), Lien(de: 12, a: 4, pointille: true),
        Lien(de: 14, a: 4, pointille: true), Lien(de: 13, a: 5, pointille: true), Lien(de: 14, a: 5, pointille: true),
    ]
    return Composition(noeuds: n, liens: l, largeurLien: 8, anneauDuCentre: true)
}()

/// La composition simplifiee (64 pixels et moins) : cinq noeuds gros, deux ronds, deux hexagonaux et le chef.
let simple: Composition = {
    let n: [Noeud] = [
        Noeud(famille: .thread, x: 512, y: 520, rayon: 150),
        Noeud(famille: .thread, x: 250, y: 290, rayon: 105),
        Noeud(famille: .zigbee, x: 790, y: 290, rayon: 120),
        Noeud(famille: .zigbee, x: 780, y: 770, rayon: 120),
        Noeud(famille: .thread, x: 250, y: 760, rayon: 105),
    ]
    let l = (1...4).map { Lien(de: 0, a: $0) }
    return Composition(noeuds: n, liens: l, largeurLien: 64, anneauDuCentre: false)
}()

/// Hexagone pointe en haut, sommets sur le cercle de rayon `r`, angles arrondis.
func hexagone(_ x: Double, _ y: Double, _ r: Double) -> CGPath {
    let sommets = (0..<6).map { k -> CGPoint in
        let a = (-90.0 + 60.0 * Double(k)) * Double.pi / 180
        return CGPoint(x: x + r * cos(a), y: y + r * sin(a))
    }
    let p = CGMutablePath()
    let rond = r * 0.2
    for k in 0..<6 {
        let avant = sommets[(k + 5) % 6], ici = sommets[k], apres = sommets[(k + 1) % 6]
        let milieu = CGPoint(x: (avant.x + ici.x) / 2, y: (avant.y + ici.y) / 2)
        if k == 0 { p.move(to: milieu) } else { p.addLine(to: milieu) }
        p.addArc(tangent1End: ici, tangent2End: apres, radius: rond)
    }
    p.closeSubpath()
    return p
}

func forme(_ n: Noeud) -> CGPath {
    n.hexagone ? hexagone(n.x, n.y, n.rayon)
               : CGPath(ellipseIn: CGRect(x: n.x - n.rayon, y: n.y - n.rayon, width: 2 * n.rayon, height: 2 * n.rayon),
                        transform: nil)
}

func teintes(_ f: Famille) -> (halo: CGColor, corps: CGColor, degrade: CGGradient, bord: CGColor) {
    switch f {
    case .thread:
        return (couleur(0.35, 0.60, 1.0, 0.95), couleur(0.27, 0.52, 0.98),
                degrade([(0, couleur(1, 1, 1)), (0.35, couleur(0.78, 0.87, 1)), (1, couleur(0.26, 0.52, 0.98))]),
                couleur(1, 1, 1, 0.30))
    case .zigbee:
        return (couleur(0.70, 0.45, 0.98, 0.95), couleur(0.70, 0.45, 0.98),
                degrade([(0, couleur(0.98, 0.94, 1)), (0.40, couleur(0.82, 0.66, 1)), (1, couleur(0.62, 0.37, 0.95))]),
                couleur(1, 1, 1, 0.34))
    case .vert:
        return (couleur(0.30, 0.90, 0.50, 0.80), couleur(0.30, 0.88, 0.50),
                degrade([(0, couleur(0.70, 1, 0.80)), (1, couleur(0.22, 0.84, 0.46))]), couleur(1, 1, 1, 0))
    case .zigbeeTerminal:
        return (couleur(0.78, 0.60, 1.0, 0.80), couleur(0.78, 0.62, 1.0),
                degrade([(0, couleur(0.98, 0.95, 1)), (1, couleur(0.72, 0.52, 0.98))]), couleur(1, 1, 1, 0))
    }
}

func dessinerIcone(taille: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: taille, height: taille, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = Double(taille) / 1024
    ctx.interpolationQuality = .high
    // Repere de 1024 x 1024, y vers le bas.
    ctx.translateBy(x: 0, y: CGFloat(taille))
    ctx.scaleBy(x: CGFloat(s), y: CGFloat(-s))
    let c = taille <= 64 ? simple : complete

    // Fond : un bleu profond, plus clair en haut a gauche.
    let fond = degrade([(0, couleur(0.23, 0.43, 0.83)), (0.40, couleur(0.10, 0.19, 0.38)),
                        (0.70, couleur(0.05, 0.10, 0.23)), (1, couleur(0.013, 0.026, 0.11))])
    ctx.drawRadialGradient(fond, startCenter: CGPoint(x: 330, y: 290), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 290), endRadius: 1000,
                           options: [.drawsAfterEndLocation])

    // Liens : pleins (blanc doux, violet quand ils touchent un noeud hexagonal), puis pointilles.
    ctx.setLineCap(.round)
    for l in c.liens {
        let a = c.noeuds[l.de], b = c.noeuds[l.a]
        if l.pointille && taille < 256 { continue }
        let zigbee = a.hexagone || b.hexagone
        ctx.setStrokeColor(zigbee ? couleur(0.78, 0.62, 1.0, l.pointille ? 0.5 : 0.55)
                                  : couleur(0.80, 0.88, 1.0, l.pointille ? 0.5 : 0.45))
        if l.pointille {
            ctx.setLineWidth(CGFloat(max(4, 1.1 / s)))
            ctx.setLineDash(phase: 0, lengths: [0.1, CGFloat(11)])
        } else {
            ctx.setLineWidth(CGFloat(max(c.largeurLien, 1.4 / s)))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.move(to: CGPoint(x: a.x, y: a.y))
        ctx.addLine(to: CGPoint(x: b.x, y: b.y))
        ctx.strokePath()
    }
    ctx.setLineDash(phase: 0, lengths: [])

    // Anneau du chef.
    if c.anneauDuCentre {
        let chef = c.noeuds[0]
        let r = chef.rayon * 1.36
        let cercle = CGRect(x: chef.x - r, y: chef.y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(couleur(1, 1, 1, 0.07))
        ctx.fillEllipse(in: cercle)
        ctx.setStrokeColor(couleur(1, 1, 1, 0.38))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: cercle)
    }

    // Noeuds : halo, corps, relief.
    let ordre = c.noeuds.enumerated().sorted { $0.element.rayon < $1.element.rayon }.map { $0.element }
    for n in ordre {
        let t = teintes(n.famille)
        let chemin = forme(n)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: CGFloat(n.halo * s), color: t.halo)
        ctx.addPath(chemin)
        ctx.setFillColor(t.corps)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(chemin)
        ctx.clip()
        let reflet = CGPoint(x: n.x - 0.30 * n.rayon, y: n.y - 0.36 * n.rayon)
        ctx.drawRadialGradient(t.degrade, startCenter: reflet, startRadius: 0,
                               endCenter: CGPoint(x: n.x, y: n.y), endRadius: CGFloat(n.rayon * 1.08),
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        if n.rayon > 30 {
            ctx.addPath(chemin)
            ctx.setStrokeColor(t.bord)
            ctx.setLineWidth(CGFloat(max(2, n.rayon * 0.04)))
            ctx.strokePath()
        }
    }
    return ctx.makeImage()!
}

func ecrirePNG(_ image: CGImage, vers url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { fatalError("ecriture impossible : \(url.path)") }
}

// MARK: - Logos

/// Un logo : un PDF d'une page de 32 x 32 points, noir sur transparent (la teinte vient du systeme), dont `dessin`
/// remplit la page de `[0, 1]`, y vers le haut.
func ecrirePDF(vers url: URL, dessin: (CGContext) -> Void) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var boite = CGRect(x: 0, y: 0, width: 32, height: 32)
    let infos = [kCGPDFContextTitle: "logo"] as CFDictionary
    let ctx = CGContext(url as CFURL, mediaBox: &boite, infos)!
    ctx.beginPDFPage(nil)
    ctx.scaleBy(x: 32, y: 32)
    ctx.setStrokeColor(couleur(0, 0, 0))
    ctx.setFillColor(couleur(0, 0, 0))
    dessin(ctx)
    ctx.endPDFPage()
    ctx.closePDF()
    // Le meme PDF a chaque lancement : la date et l'identifiant du fichier sont remplaces, par des valeurs de la
    // meme longueur (les decalages de la table des references restent justes) ; en Latin-1, qui garde chaque octet.
    var texte = String(data: try Data(contentsOf: url), encoding: .isoLatin1)!
    texte = texte.replacingOccurrences(of: "D:[0-9]{14}Z00'00'", with: "D:20260101000000Z00'00'",
                                       options: .regularExpression)
    texte = texte.replacingOccurrences(of: "<[0-9a-f]{32}>", with: "<00000000000000000000000000000000>",
                                       options: .regularExpression)
    try texte.data(using: .isoLatin1)!.write(to: url)
}

/// Glyphe de Thread : une tige qui monte vers une boucle, et un crochet qui s'enroule a gauche (le « T » a la tige
/// enroulee), en traits de 0,125 de la hauteur du glyphe ; 0,79 de large pour 1 de haut, centre dans la page, 22 de 32 points de haut.
func glypheThread(_ ctx: CGContext) {
    let h = 22.0 / 32, l = 0.79 * h
    ctx.translateBy(x: (1 - l) / 2, y: (1 - h) / 2)
    ctx.scaleBy(x: h, y: h)
    // Coordonnees du glyphe : hauteur 1, y vers le haut.
    ctx.setLineWidth(0.125)
    ctx.setLineCap(.butt)
    ctx.setLineJoin(.round)
    let tige = 0.476
    ctx.move(to: CGPoint(x: tige, y: 0))
    ctx.addLine(to: CGPoint(x: tige, y: 0.81))
    ctx.strokePath()
    // Boucle en haut a droite, tangente a la tige.
    ctx.strokeEllipse(in: CGRect(x: tige, y: 0.81 - 0.1257, width: 0.2514, height: 0.2514))
    // Crochet : de la tige vers la gauche, puis demi-tour par le bas.
    ctx.move(to: CGPoint(x: tige, y: 0.6863))
    ctx.addLine(to: CGPoint(x: 0.2261, y: 0.6863))
    ctx.addArc(center: CGPoint(x: 0.2261, y: 0.5227), radius: 0.1636, startAngle: .pi / 2, endAngle: 3 * .pi / 2,
               clockwise: false)
    ctx.strokePath()
}

/// Glyphe de Zigbee : un anneau et, dedans, un Z (deux barres et leur diagonale), en traits de 0,09.
func glypheZigbee(_ ctx: CGContext) {
    let echelle = 25.0 / 32
    ctx.translateBy(x: (1 - echelle) / 2, y: (1 - echelle) / 2)
    ctx.scaleBy(x: echelle, y: echelle)
    ctx.setLineWidth(0.075)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokeEllipse(in: CGRect(x: 0.0425, y: 0.0425, width: 0.915, height: 0.915))
    ctx.setLineWidth(0.088)
    ctx.move(to: CGPoint(x: 0.31, y: 0.67))
    ctx.addLine(to: CGPoint(x: 0.69, y: 0.67))
    ctx.addLine(to: CGPoint(x: 0.31, y: 0.33))
    ctx.addLine(to: CGPoint(x: 0.69, y: 0.33))
    ctx.strokePath()
}

func ecrireImageModele(_ nom: String, dans catalogue: URL, dessin: (CGContext) -> Void) throws {
    let dossier = catalogue.appendingPathComponent("\(nom).imageset")
    try ecrirePDF(vers: dossier.appendingPathComponent("\(nom).pdf"), dessin: dessin)
    let contenu = """
    {
      "images" : [
        {
          "filename" : "\(nom).pdf",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "preserves-vector-representation" : true,
        "template-rendering-intent" : "template"
      }
    }

    """
    try contenu.write(to: dossier.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// MARK: - Programme

let racine = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: racine.appendingPathComponent("outils/icone/generer.swift").path) else {
    FileHandle.standardError.write(Data("a lancer depuis la racine du depot : swift outils/icone/generer.swift\n".utf8))
    exit(1)
}

try ecrirePNG(dessinerIcone(taille: 1024),
              vers: racine.appendingPathComponent("MaillageIoT/Ressources/AppIcon.icon/Assets/constellation.png"))
for t in [16, 32, 64, 128, 256, 512, 1024] {
    try ecrirePNG(dessinerIcone(taille: t), vers: racine.appendingPathComponent("outils/icone/tailles/icone_\(t).png"))
}
let logos = racine.appendingPathComponent("MaillageIoT/Ressources/Logos.xcassets")
try FileManager.default.createDirectory(at: logos, withIntermediateDirectories: true)
try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: logos.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try ecrireImageModele("LogoThread", dans: logos, dessin: glypheThread)
try ecrireImageModele("LogoZigbee", dans: logos, dessin: glypheZigbee)
print("icone, tailles et logos ecrits")
