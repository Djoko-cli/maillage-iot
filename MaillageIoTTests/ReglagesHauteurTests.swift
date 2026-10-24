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
                        surveillance: Surveillance = Surveillance(mode: .direct, dossier: nil),
                        reprise: ControleurReprise? = nil) async throws -> (NSWindow, OngletsReglages) {
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
                                            reprise: reprise, preferences: p)
        await thread.connecter(SondeMaillageTests.port, choisi: true)
        await zigbee.connecter(SondeMaillageZigbeeTests.port, choisi: true)
        p.set(onglet.rawValue, forKey: OngletReglages.cle)
        let fenetre = controleur.creerFenetre()
        // Sans animation d'ouverture ni de fermeture : une animation de fenetre qui ne finit jamais (ecran verrouille, fenetre
        // cachee) bloque un fil du pool de Dispatch, et le pool epuise fait taire tout test qui attend le reseau.
        fenetre.animationBehavior = .none
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

    /// A quelle distance du haut de la page (en points, vers le bas) commence son contenu : le haut de la vue de
    /// defilement du formulaire, mesure dans le repere de la vue hote. Positif : du vide au-dessus ; negatif : le haut est
    /// hors de la page, donc coupe.
    static func distanceDuHaut(_ page: NSView) -> CGFloat? {
        guard let defilement = defilements(page).first else { return nil }
        let r = page.convert(defilement.bounds, from: defilement)
        return page.isFlipped ? r.minY - page.bounds.minY : page.bounds.maxY - r.maxY
    }

    /// Donne a la page choisie la hauteur `ideale + ecart` en changeant la taille de la fenetre (le bord du haut ne bouge pas),
    /// comme le fait l'animation de hauteur : la page est tantot plus petite, tantot plus grande que sa taille ideale.
    static func hauteurDePage(_ ecart: CGFloat, fenetre: NSWindow, page: NSView) {
        var cadre = fenetre.frame
        let d = page.fittingSize.height + ecart - page.frame.height
        cadre.size.height += d
        cadre.origin.y -= d
        fenetre.setFrame(cadre, display: true)
        page.layoutSubtreeIfNeeded()
    }

    /// Le fondu enchaine natif de `NSTabViewController`, pose explicitement : il se joue en meme temps que l'animation de
    /// hauteur, et l'utilisateur peut cliquer un autre onglet sans attendre la fin.
    @Test func lesOngletsSeFondentEnchaines() async throws {
        let (fenetre, onglets) = try await Self.fenetre(onglet: .general)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        #expect(onglets.transitionOptions.contains(.crossfade))
        #expect(onglets.transitionOptions.contains(.allowUserInteraction))
    }

    /// Le haut de la page ne bouge pas, quelle que soit la hauteur que lui donne la fenetre pendant l'animation : plus petite
    /// que sa taille ideale (la fenetre grandit vers une page plus haute, ou se reduit depuis une page plus haute) comme
    /// plus grande. Cause du haut coupe : une vue SwiftUI plus grande que sa vue hote y est centree, donc decalee vers le
    /// haut de la moitie du manque.
    @Test(arguments: OngletReglages.allCases) func laPageResteColleeEnHaut(_ onglet: OngletReglages) async throws {
        let (fenetre, onglets) = try await Self.fenetre(onglet: onglet)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        _ = try await Self.attendreAjustement(fenetre, onglets)
        let page = try #require(onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController?.view)
        let repos = try #require(Self.distanceDuHaut(page))
        for ecart: CGFloat in [-300, -100, 100, 300, 0] {
            Self.hauteurDePage(ecart, fenetre: fenetre, page: page)
            #expect(abs(page.frame.height - (page.fittingSize.height + ecart)) < 0.5, "onglet \(onglet.titre) : la page n'a pas la hauteur voulue")
            let haut = try #require(Self.distanceDuHaut(page))
            #expect(abs(haut - repos) < 0.5, "onglet \(onglet.titre), page \(ecart) pt de plus que sa taille ideale : le haut est a \(haut) pt, il etait a \(repos) pt au repos")
        }
    }

    /// Un vrai changement d'onglet, echantillonne pendant le fondu et l'animation de hauteur, dans les deux sens (page plus
    /// haute, puis plus courte) : les deux pages, l'ancienne qui s'efface et la nouvelle, gardent leur haut ou il est au repos.
    @Test(arguments: [(OngletReglages.general, OngletReglages.zigbee), (.zigbee, .general)])
    func lePendantLeChangementDOnglet(_ de: OngletReglages, vers: OngletReglages) async throws {
        let (fenetre, onglets) = try await Self.fenetre(onglet: de)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        _ = try await Self.attendreAjustement(fenetre, onglets)
        // Le haut au repos de chaque page : on la montre une fois (le fondu et l'animation finissent), puis on revient.
        var repos: [OngletReglages: CGFloat] = [:]
        for o in [vers, de] {
            onglets.selectedTabViewItemIndex = OngletReglages.allCases.firstIndex(of: o)!
            _ = try await Self.attendreAjustement(fenetre, onglets)
            try await Task.sleep(for: .milliseconds(600))
            let haut = try #require(Self.distanceDuHaut(onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view))
            repos[o] = haut
        }
        onglets.selectedTabViewItemIndex = OngletReglages.allCases.firstIndex(of: vers)!
        var echantillons = 0
        var ecarts: [String] = []
        var vues = Set<OngletReglages>()
        for _ in 0..<40 {
            for o in OngletReglages.allCases {
                let vue = onglets.tabViewItems[OngletReglages.allCases.firstIndex(of: o)!].viewController!.view
                guard vue.window != nil, vue.superview != nil, let haut = Self.distanceDuHaut(vue) else { continue }
                vues.insert(o)
                echantillons += 1
                if abs(haut - repos[o]!) > 0.5 { ecarts.append("\(o.titre) a \(haut) au lieu de \(repos[o]!), page \(vue.frame.height)") }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("ECHANTILLONS \(de)->\(vers) : \(echantillons), pages vues \(vues.map(\.rawValue).sorted())")
        #expect(echantillons > 0)
        #expect(ecarts.isEmpty, "pendant le changement d'onglet : \(ecarts.prefix(3))")
    }
}
