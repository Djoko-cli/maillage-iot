// Derive l'icone de l'app de repetition (« Maillage IoT Repetition », phase 4, tache 8) de celle de l'app :
//
//   swift outils/icone/generer-repetition.swift          (depuis la racine du depot ; rien d'autre a installer)
//
// Lit le calque de l'icone de l'app (MaillageIoT/Ressources/AppIcon.icon : constellation.png et icon.json) et ecrit
// MaillageIoTRepetition/Ressources/AppIconRepetition.icon (meme format Icon Composer, meme fond, meme constellation) avec, en
// plus, une pastille orange portant un « R » blanc en bas a droite : reconnaissable d'un coup d'oeil a cote de l'icone de l'app
// reelle, dans le Dock comme dans le Finder. Le « R » est un trace (traits arrondis), pas du texte : aucune police en jeu,
// toujours les memes octets pour le meme programme. Ni texte ni donnee reelle.
//
// La pastille tient dans le masque du systeme (le calque est plein cadre : le coin est coupe a ~957 pixels sur la diagonale ;
// la pastille s'arrete a ~890).
//
// Echoue si l'icone de l'app manque : mieux vaut pas d'icone de repetition qu'une icone generique (outils/repetition.sh).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let racine = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = racine.appendingPathComponent("MaillageIoT/Ressources/AppIcon.icon")
let cible = racine.appendingPathComponent("MaillageIoTRepetition/Ressources/AppIconRepetition.icon")

func echouer(_ message: String) -> Never {
    FileHandle.standardError.write(Data("generer-repetition : \(message)\n".utf8))
    exit(1)
}

guard FileManager.default.fileExists(atPath: racine.appendingPathComponent("outils/icone/generer-repetition.swift").path) else {
    echouer("a lancer depuis la racine du depot : swift outils/icone/generer-repetition.swift")
}
let calque = source.appendingPathComponent("Assets/constellation.png")
let reglages = source.appendingPathComponent("icon.json")
guard let fichier = CGImageSourceCreateWithURL(calque as CFURL, nil), let base = CGImageSourceCreateImageAtIndex(fichier, 0, nil),
      FileManager.default.fileExists(atPath: reglages.path) else {
    echouer("l'icone de l'app manque ou est illisible : \(source.path)")
}
guard base.width == 1024, base.height == 1024 else { echouer("le calque de l'app doit faire 1024 x 1024") }

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func couleur(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [r, g, b, a].map { CGFloat($0) })!
}

let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(base, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

// La pastille : centre (740, 284) (y vers le haut), rayon 150, liseré blanc, ombre douce.
let centre = CGPoint(x: 740, y: 284)
let rayon = 150.0
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: couleur(0, 0, 0, 0.45))
ctx.setFillColor(couleur(1, 1, 1))
ctx.fillEllipse(in: CGRect(x: centre.x - rayon - 10, y: centre.y - rayon - 10, width: 2 * rayon + 20, height: 2 * rayon + 20))
ctx.restoreGState()
ctx.setFillColor(couleur(0.98, 0.52, 0.06))
ctx.fillEllipse(in: CGRect(x: centre.x - rayon, y: centre.y - rayon, width: 2 * rayon, height: 2 * rayon))

// Le « R », dessine en traits arrondis dans un carre de 1 x 1 (origine au centre), puis mis a l'echelle.
let echelle = 190.0
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: centre.x + x * echelle, y: centre.y + y * echelle) }
let r = Path.trace()
ctx.setStrokeColor(couleur(1, 1, 1))
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(r)
ctx.strokePath()

enum Path {
    static func trace() -> CGPath {
        let t = CGMutablePath()
        // La haste, puis la panse (demi-cercle de rayon 0,25), puis la jambe.
        t.move(to: p(-0.24, -0.5))
        t.addLine(to: p(-0.24, 0.5))
        t.addLine(to: p(0.0, 0.5))
        t.addArc(center: p(0.0, 0.25), radius: 0.25 * echelle, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        t.addLine(to: p(-0.24, 0.0))
        t.move(to: p(0.04, 0.0))
        t.addLine(to: p(0.30, -0.5))
        return t
    }
}

guard let image = ctx.makeImage() else { echouer("image impossible") }
try FileManager.default.createDirectory(at: cible.appendingPathComponent("Assets"), withIntermediateDirectories: true)
let sortie = cible.appendingPathComponent("Assets/constellation.png")
guard let d = CGImageDestinationCreateWithURL(sortie as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    echouer("ecriture impossible : \(sortie.path)")
}
CGImageDestinationAddImage(d, image, nil)
guard CGImageDestinationFinalize(d) else { echouer("ecriture impossible : \(sortie.path)") }
// Les memes reglages (fond, groupe, plateforme) que l'icone de l'app.
let json = cible.appendingPathComponent("icon.json")
try? FileManager.default.removeItem(at: json)
try FileManager.default.copyItem(at: reglages, to: json)
print("icone de repetition ecrite : \(cible.path)")
