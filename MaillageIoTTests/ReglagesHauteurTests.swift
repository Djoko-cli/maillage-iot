import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

/// La hauteur de la fenetre des Reglages suit celle de la page (`OngletsReglages.ajuster`), hors ecran, sur les six
/// onglets (Thread de l'app Thread n'avait aucun test de hauteur ; celui de Zigbee ne couvrait que sa page Sonde).
@MainActor
@Suite("Reglages : hauteur de la fenetre", .serialized, .timeLimit(.minutes(1)))
struct ReglagesHauteurTests {
    static func defilements(_ v: NSView) -> [NSScrollView] {
        ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap { defilements($0) }
    }

    static func segments(_ v: NSView) -> [NSSegmentedControl] {
        ((v as? NSSegmentedControl).map { [$0] } ?? []) + v.subviews.flatMap { segments($0) }
    }

    /// Une fenetre des Reglages sur `onglet`, montree hors ecran (transparente, loin de tout ecran) : visible pour AppKit,
    /// donc animee comme dans l'app, sans rien montrer. Les deux sondes sont connectees par leur port USB, sans reseau ni
    /// trousseau du Mac ; l'onglet retenu est ecrit dans des preferences en memoire, jamais dans celles de l'app.
    static func fenetre(onglet: OngletReglages, sondeThread: SondeMaillageThread? = nil,
                        sondeZigbee: SondeMaillageZigbee? = nil,
                        surveillance: Surveillance = Surveillance(mode: .direct, dossier: nil)) async throws -> (NSWindow, OngletsReglages) {
        let (p, _) = try SondeMaillageTests.preferences()
        let thread = try sondeThread ?? {
            let (pt, _) = try SondeMaillageTests.preferences()
            return SondeReseauTests.sondeMaillage(pt, trousseau: TrousseauMemoireThread())
        }()
        let zigbee = try sondeZigbee ?? {
            let (pz, _) = try SondeMaillageZigbeeTests.preferences()
            return SondeMaillageZigbee(preferences: pz, actif: true, trousseau: TrousseauMemoireZigbee(),
                                       ouvrirCanal: { _ in CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) } })
        }()
        let controleur = ControleurReglages(surveillance: surveillance,
                                            ouverture: OuvertureSession(), nomsMaison: NomsPasseur(), nomsPont: NomsPont(),
                                            sonde: thread, sondeZigbee: zigbee, misesAJour: MisesAJour(demarrer: false),
                                            preferences: p)
        await thread.connecter(SondeMaillageTests.port, choisi: true)
        await zigbee.connecter(SondeMaillageZigbeeTests.port, choisi: true)
        p.set(onglet.rawValue, forKey: OngletReglages.cle)
        let fenetre = controleur.creerFenetre()
        fenetre.alphaValue = 0
        fenetre.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        fenetre.orderFrontRegardless()
        return (fenetre, try #require(fenetre.contentViewController as? OngletsReglages))
    }

    /// Une fenetre des Reglages sur l'onglet Zigbee, sonde USB connectee.
    static func fenetreSonde(_ sonde: SondeMaillageZigbee) async throws -> (NSWindow, OngletsReglages) {
        try await fenetre(onglet: .zigbee, sondeZigbee: sonde)
    }

    /// Les mesures d'une fenetre des Reglages : la hauteur de sa zone de contenu, la taille ideale de la page choisie, la
    /// hauteur de la page dans la fenetre, et ce que la vue de defilement du formulaire cache (en points).
    struct Mesure: CustomStringConvertible {
        var contenu: CGFloat, ideale: CGFloat, page: CGFloat, cache: CGFloat
        var description: String { "contenu \(contenu), ideale \(ideale), page \(page), cache \(cache)" }
        var juste: Bool { abs(contenu - ideale) < 0.5 && abs(page - contenu) < 0.5 && ideale > 0 && cache < 0.5 }
    }

    static func mesurer(_ fenetre: NSWindow, _ onglets: OngletsReglages) -> Mesure {
        let page = onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view
        let cache = defilements(fenetre.contentView!).map { max(($0.documentView?.frame.height ?? 0) - $0.documentVisibleRect.height, 0) }
        return Mesure(contenu: fenetre.contentLayoutRect.height, ideale: page.fittingSize.height, page: page.frame.height,
                      cache: cache.max() ?? 0)
    }

    /// Attend, 3 s au plus, que la fenetre se soit ajustee a la page ; rend la derniere mesure.
    static func attendreAjustement(_ fenetre: NSWindow, _ onglets: OngletsReglages) async throws -> Mesure {
        var m = mesurer(fenetre, onglets)
        for _ in 0..<60 where !m.juste {
            try await Task.sleep(for: .milliseconds(50))
            m = mesurer(fenetre, onglets)
        }
        return m
    }

    /// Les six onglets, dans l'ordre de la barre d'outils : Zigbee et Thread ont chacun le leur (spec 3.3).
    @Test func lesSixOnglets() {
        #expect(OngletReglages.allCases == [.general, .notifications, .maison, .thread, .zigbee, .diagnostic])
        #expect(OngletReglages.allCases.map(\.rawValue)
                == ["general", "notifications", "maison", "thread", "zigbee", "diagnostic"])
        #expect(OngletReglages.allCases.map(\.titre)
                == [String(localized: "Général"), String(localized: "Notifications"), String(localized: "Maison"),
                    String(localized: "Thread"), String(localized: "Zigbee"), String(localized: "Diagnostic")])
        #expect(Set(OngletReglages.allCases.map(\.symbole)).count == 6, "un symbole par onglet")
        // Les anciens onglets « sonde » et « pont » (gardes dans les preferences) retombent sur General.
        #expect(OngletReglages(rawValue: "sonde") == nil && OngletReglages(rawValue: "pont") == nil)
    }

    /// Chaque onglet, ouvert tel quel : la fenetre prend la hauteur de sa page, la page entiere est visible.
    @Test(arguments: OngletReglages.allCases) func chaqueOngletALaHauteurDeSaPage(_ onglet: OngletReglages) async throws {
        let (fenetre, onglets) = try await Self.fenetre(onglet: onglet)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        #expect(onglets.ongletCourant == onglet)
        #expect(fenetre.title == onglet.titre, "le titre de la fenetre est celui de l'onglet")
        let m = try await Self.attendreAjustement(fenetre, onglets)
        #expect(m.juste, "onglet \(onglet.titre) : \(m)")
    }

    /// D'un onglet a l'autre, dans les deux sens et d'un bout a l'autre de la barre : la fenetre suit la page chaque fois,
    /// bord du haut fixe.
    @Test func laFenetreSuitLeChangementDOnglet() async throws {
        let (fenetre, onglets) = try await Self.fenetre(onglet: .general)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        _ = try await Self.attendreAjustement(fenetre, onglets)
        let haut = fenetre.frame.maxY
        let parcours: [OngletReglages] = OngletReglages.allCases + Array(OngletReglages.allCases.reversed())
            + [.zigbee, .general, .thread, .diagnostic]
        for o in parcours {
            onglets.selectedTabViewItemIndex = OngletReglages.allCases.firstIndex(of: o)!
            try await Task.sleep(for: .milliseconds(120))
            let m = try await Self.attendreAjustement(fenetre, onglets)
            #expect(onglets.ongletCourant == o)
            #expect(m.juste, "apres l'onglet \(o.titre) : \(m)")
            #expect(abs(fenetre.frame.maxY - haut) < 0.5, "apres l'onglet \(o.titre) : le bord du haut a bouge")
        }
    }

    /// Le bug du banc (11/10) : Liaison Automatique, puis Wi-Fi (la page perd des lignes), puis de nouveau Automatique
    /// (elle en retrouve) : la fenetre doit suivre la page chaque fois, la page entiere visible, bord du haut fixe.
    @Test func lAjustementSuitLaPage() async throws {
        let (p, domaine) = try SondeMaillageZigbeeTests.preferences()
        defer { SondeMaillageZigbeeTests.nettoyer(p, domaine) }
        let sonde = SondeMaillageZigbee(preferences: p, actif: true, trousseau: TrousseauMemoireZigbee(),
                                        ouvrirCanal: { _ in CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) } })
        let (fenetre, onglets) = try await Self.fenetreSonde(sonde)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        let segments = try #require(Self.segments(fenetre.contentView!).first)
        let haut = try await { () -> CGFloat in
            _ = try await Self.attendreAjustement(fenetre, onglets)
            return fenetre.frame.maxY
        }()
        for (indice, nom) in [(1, "USB"), (0, "Automatique"), (2, "Wi-Fi"), (0, "Automatique"), (2, "Wi-Fi"), (0, "Automatique"),
                              (1, "USB"), (0, "Automatique")] {
            segments.selectedSegment = indice
            segments.performClick(nil)
            // Une pause courte, avant la fin de l'animation precedente, puis la mesure une fois la fenetre posee.
            try await Task.sleep(for: .milliseconds(120))
            let m = try await Self.attendreAjustement(fenetre, onglets)
            #expect(m.juste, "apres \(nom) : \(m)")
            #expect(abs(fenetre.frame.maxY - haut) < 0.5, "apres \(nom) : le bord du haut a bouge")
        }
        await sonde.oublier()
    }
}
