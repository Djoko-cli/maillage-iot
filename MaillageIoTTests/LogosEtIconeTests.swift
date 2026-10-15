import AppKit
import Foundation
import Testing
@testable import MaillageIoT

/// Les logos des onglets Thread et Zigbee des Reglages (redessines en vectoriel monochrome, images modeles : la barre
/// d'outils les teinte comme les symboles SF voisins) et l'icone de l'app (la constellation sans badge, dessinee par
/// `outils/icone/generer.swift`).
@MainActor
@Suite("Icones et logos", .serialized, .timeLimit(.minutes(1)))
struct LogosEtIconeTests {
    /// Le depot : ce fichier est dans `MaillageIoTTests/`.
    static let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Les pixels d'une image dessinee dans un tampon RGBA de `cote` pixels.
    static func pixels(_ image: NSImage, cote: Int) -> [UInt8] {
        var donnees = [UInt8](repeating: 0, count: cote * cote * 4)
        donnees.withUnsafeMutableBytes { tampon in
            let ctx = CGContext(data: tampon.baseAddress, width: cote, height: cote, bitsPerComponent: 8,
                                bytesPerRow: cote * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            image.draw(in: NSRect(x: 0, y: 0, width: cote, height: cote))
            NSGraphicsContext.restoreGraphicsState()
        }
        return donnees
    }

    @Test(arguments: [OngletReglages.thread, .zigbee])
    func lOngletChargeSonLogoEnImageModele(_ onglet: OngletReglages) throws {
        let logo = try #require(onglet.logo, "le logo de \(onglet.titre) manque aux ressources")
        #expect(logo.isTemplate, "image modele : teintee par le systeme")
        #expect(logo.size.width > 0 && logo.size.height > 0)
        #expect(onglet.image.name() == logo.name(), "l'onglet montre son logo, pas le symbole SF")
        // Il dessine quelque chose, et seulement une forme (tout le noir est en alpha : la teinte est celle du systeme).
        let p = Self.pixels(logo, cote: 64)
        let opaques = stride(from: 3, to: p.count, by: 4).filter { p[$0] > 128 }.count
        #expect(opaques > 150 && opaques < 64 * 64 * 3 / 4, "\(opaques) pixels opaques sur 4096")
    }

    @Test func lesAutresOngletsGardentLeurSymbole() {
        for o in OngletReglages.allCases where o != .thread && o != .zigbee {
            #expect(o.logo == nil, "\(o.titre)")
            #expect(o.image.isTemplate)
        }
    }

    /// Dans la vraie fenetre des Reglages, les onglets Thread et Zigbee portent leurs logos.
    @Test func lesOngletsDeLaFenetreMontrentLesLogos() async throws {
        let (fenetre, onglets) = try await ReglagesHauteurTests.fenetre(onglet: .thread)
        defer { fenetre.orderOut(nil) }
        for o in OngletReglages.allCases {
            let item = try #require(onglets.tabViewItems.first { $0.identifier as? String == o.rawValue })
            let image = try #require(item.image)
            #expect(image.isTemplate, "\(o.titre) : image modele")
            if let logo = o.logo {
                #expect(image.name() == logo.name(), "\(o.titre) : son logo")
            } else {
                #expect(image.name() != OngletReglages.thread.logo?.name() && image.name() != OngletReglages.zigbee.logo?.name(),
                        "\(o.titre) : son symbole")
            }
        }
    }

    /// Aucun badge sur l'icone de l'app : pas d'orange (celui du badge de Thread) dans son coin du bas a droite, la
    /// ou il etait.
    @Test func laConstellationNAPasDeBadge() throws {
        let url = Self.racine.appendingPathComponent("MaillageIoT/Ressources/AppIcon.icon/Assets/constellation.png")
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(rep.pixelsWide == 1024 && rep.pixelsHigh == 1024)
        let coin = try #require(rep.colorAt(x: 0, y: 0))
        #expect(coin.alphaComponent == 1, "plein cadre, opaque")
        var orange = 0
        for y in stride(from: 700, to: 1000, by: 4) {
            for x in stride(from: 700, to: 1000, by: 4) {
                let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if c.redComponent > 0.6 && c.blueComponent < 0.45 { orange += 1 }
            }
        }
        #expect(orange == 0, "\(orange) points oranges dans le coin du badge")
    }

    /// L'icone existe a chaque taille de l'icone d'une app Mac (16 a 1024 points, 1x et 2x), toutes carrees.
    @Test(arguments: [16, 32, 64, 128, 256, 512, 1024])
    func uneIconeParTaille(_ cote: Int) throws {
        let url = Self.racine.appendingPathComponent("outils/icone/tailles/icone_\(cote).png")
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(rep.pixelsWide == cote && rep.pixelsHigh == cote)
    }
}
