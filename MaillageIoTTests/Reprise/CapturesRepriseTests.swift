import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

/// Phase 4, tache 7 : l'entree des Reglages et les captures de l'assistant. Les captures ne sont ecrites que sur demande
/// (`TEST_RUNNER_CAPTURES_REPRISE=1`, jamais dans la porte) ; elles n'utilisent que les exports d'exemple (valeurs inventees)
/// et des dossiers temporaires, dans le dossier temporaire du conteneur de l'app de test.
@MainActor
@Suite("Assistant de reprise : fenetre", .serialized, .timeLimit(.minutes(2)))
struct CapturesRepriseTests {
    typealias Banc = AssistantRepriseTests.Banc
    typealias App = ContratExport.AppSource

    nonisolated static var demande: Bool { ProcessInfo.processInfo.environment["CAPTURES_REPRISE"] != nil }

    // MARK: Reglages > General

    /// La hauteur ideale de la page General d'une fenetre des Reglages.
    static func hauteurGeneral(_ onglets: OngletsReglages) -> CGFloat {
        onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view.fittingSize.height
    }

    /// L'entree « Reprendre des donnees… » est dans Reglages > General quand l'app a un assistant (une section de plus, que les
    /// tests des vues, sans assistant, n'ont pas) ; sa capture (`16-reglages-general.png`) la montre.
    @Test func lEntreeReprendreDesDonneesEstDansReglagesGeneral() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let (avec, ongletsAvec) = try await ReglagesHauteurTests.fenetre(onglet: .general, reprise: ControleurReprise(assistant: b.assistant))
        defer { avec.close() }
        let (sans, ongletsSans) = try await ReglagesHauteurTests.fenetre(onglet: .general)
        defer { sans.close() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(ongletsAvec.ongletCourant == .general && ongletsSans.ongletCourant == .general)
        let (a, s) = (Self.hauteurGeneral(ongletsAvec), Self.hauteurGeneral(ongletsSans))
        #expect(a > s + 60, "la section Reprise (un bouton et sa note) s'ajoute a la page : \(a) contre \(s)")
    }

    /// La fenetre s'ajuste a son contenu (banc du 18/10 : l'accueil gardait la hauteur du resume, vide en bas), sans depasser
    /// `hauteurMax`, au-dela de laquelle le formulaire defile.
    @Test func laFenetreSAjusteASonContenu() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let hote = NSHostingView(rootView: FenetreReprise(assistant: b.assistant))
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: FenetreReprise.largeur, height: FenetreReprise.hauteurMax),
                               styleMask: [.titled], backing: .buffered, defer: false)
        fenetre.animationBehavior = .none
        fenetre.contentView = hote
        fenetre.alphaValue = 0
        fenetre.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        fenetre.orderFrontRegardless()
        defer { fenetre.close() }
        try await Task.sleep(for: .milliseconds(500))
        hote.layoutSubtreeIfNeeded()
        let h = hote.fittingSize.height
        #expect(h > 150 && h < FenetreReprise.hauteurMax - 200, "l'accueil tient en \(h) points, pas en \(FenetreReprise.hauteurMax)")
    }

    // MARK: Captures

    /// Rend la vue de l'assistant hors ecran (comme les tests des Reglages) et la garde en PNG.
    static func capturer(_ nom: String, _ assistant: AssistantReprise, dans dossier: URL) async throws {
        let hote = NSHostingView(rootView: FenetreReprise(assistant: assistant))
        let taille = NSSize(width: FenetreReprise.largeur, height: FenetreReprise.hauteurMax)
        let fenetre = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.titled], backing: .buffered, defer: false)
        fenetre.animationBehavior = .none
        fenetre.contentView = hote
        fenetre.alphaValue = 0
        fenetre.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        fenetre.orderFrontRegardless()
        defer { fenetre.close() }
        try await Task.sleep(for: .milliseconds(400))
        hote.layoutSubtreeIfNeeded()
        let rep = try #require(hote.bitmapImageRepForCachingDisplay(in: hote.bounds))
        hote.cacheDisplay(in: hote.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: dossier.appendingPathComponent("\(nom).png"))
    }

    static func exemple(_ app: App) throws -> URL { try ApplicationImportTests.exemple(app) }

    @Test(.enabled(if: CapturesRepriseTests.demande))
    func captures() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("captures-reprise", isDirectory: true)
        try? FileManager.default.removeItem(at: dossier)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        // 1. Premier lancement : la proposition.
        let a = try Banc()
        defer { a.nettoyer() }
        _ = await a.assistant.preparerLancement(recuperation: .success(.rienAFaire))
        try await Self.capturer("01-proposition-premier-lancement", a.assistant, dans: dossier)

        // 2. L'entree des Reglages : l'accueil sans proposition.
        let b = try Banc()
        defer { b.nettoyer() }
        try await Self.capturer("02-accueil", b.assistant, dans: dossier)

        // 3. Export refuse.
        let copie = try ValidationExportTests.Copie(.maillageThread)
        try Data("{}".utf8).write(to: copie.url("surnoms.json"))
        let c = try Banc()
        defer { c.nettoyer() }
        await c.assistant.valider(copie.dossier)
        try await Self.capturer("03-export-refuse", c.assistant, dans: dossier)

        // 4. Confirmation (Thread), puis avec l'ancienne app qui tourne, puis quand macOS refuse de la quitter.
        let d = try Banc()
        defer { d.nettoyer() }
        await d.assistant.valider(try Self.exemple(.maillageThread))
        try await Self.capturer("04-confirmation-thread", d.assistant, dans: dossier)
        let e = try Banc()
        defer { e.nettoyer() }
        e.apps.tournent[App.maillageThread.identifiantBundle] = 1
        await e.assistant.valider(try Self.exemple(.maillageThread))
        try await Self.capturer("05-ancienne-app-qui-tourne", e.assistant, dans: dossier)
        e.apps.accepte = false
        await e.assistant.quitterAncienneApp()
        try await Self.capturer("06-ancienne-app-a-quitter-soi-meme", e.assistant, dans: dossier)

        // 7. Confirmation (Zigbee).
        let f = try Banc()
        defer { f.nettoyer() }
        await f.assistant.valider(try Self.exemple(.maillageZigbee))
        try await Self.capturer("07-confirmation-zigbee", f.assistant, dans: dossier)

        // 8. Reprise en cours (retenue par une porte).
        let porte = AssistantRepriseTests.Porte()
        let g = try Banc(porte: porte)
        defer { g.nettoyer() }
        await g.assistant.valider(try Self.exemple(.maillageThread))
        let tache = Task { @MainActor in await g.assistant.lancer() }
        while g.assistant.etape != .enCours { await Task.yield() }
        try await Self.capturer("08-reprise-en-cours", g.assistant, dans: dossier)
        porte.ouvrir()
        await tache.value
        try await Self.capturer("09-relance", g.assistant, dans: dossier)

        // 10. Deja repris.
        let h = AssistantReprise(importeur: g.importeur, dossierDonnees: g.donnees.racine, applications: g.apps,
                                 lecteur: AssistantRepriseTests.LecteurFactice(), preferences: g.preferences, arreterModules: {},
                                 relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        await h.valider(try Self.exemple(.maillageThread))
        try await Self.capturer("10-deja-repris", h, dans: dossier)

        // 11. Echec.
        let i = try Banc(erreur: .echecAvecReste(.validation, ElementsLaisses(fichiers: ["surnoms.json"], reglages: ["thread.sondeHote"]),
                                                 code: "NSCocoaErrorDomain 640"))
        defer { i.nettoyer() }
        await i.assistant.valider(try Self.exemple(.maillageThread))
        await i.assistant.lancer()
        try await Self.capturer("11-echec", i.assistant, dans: dossier)

        // 12. Resume apres la relance : tout en ordre (Thread), puis ce qui reste a faire (Zigbee).
        let ordre = try Banc()
        defer { ordre.nettoyer() }
        await ordre.assistant.valider(try Self.exemple(.maillageThread))
        await ordre.assistant.lancer()
        let suivantOrdre = AssistantReprise(importeur: ordre.importeur, dossierDonnees: ordre.donnees.racine, applications: ordre.apps,
                                            lecteur: AssistantRepriseTests.LecteurFactice(), preferences: ordre.preferences,
                                            arreterModules: {}, relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        _ = await suivantOrdre.preparerLancement(recuperation: .success(.rienAFaire))
        try await Self.capturer("12-resume-thread-tout-en-ordre", suivantOrdre, dans: dossier)

        var etat = AssistantRepriseTests.enOrdre
        etat.pontHue = .nonAboutie
        etat.sondeZigbee = .aReprendre
        etat.notifications = .nonDemandees
        etat.ouverture = .aApprouver
        etat.reseauLocalRefuse = true
        let z = try Banc()
        defer { z.nettoyer() }
        await z.assistant.valider(try Self.exemple(.maillageZigbee))
        await z.assistant.lancer()
        let suivantZ = AssistantReprise(importeur: z.importeur, dossierDonnees: z.donnees.racine, applications: z.apps,
                                        lecteur: AssistantRepriseTests.LecteurFactice(etat: etat), preferences: z.preferences,
                                        arreterModules: {}, relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        _ = await suivantZ.preparerLancement(recuperation: .success(.rienAFaire))
        try await Self.capturer("13-resume-zigbee-a-refaire", suivantZ, dans: dossier)

        // 14. Journal des imports abime : le bouton « Repartir d'un journal vide ».
        let j = try Banc()
        defer { j.nettoyer() }
        try j.donnees.ecrire("imports.json", "pas du json")
        await j.assistant.valider(try Self.exemple(.maillageThread))
        try await Self.capturer("14-journal-abime", j.assistant, dans: dossier)

        // 15. Avis du lancement : une reprise interrompue defaite, sauf ce que l'app avait ecrit.
        let k = try Banc()
        defer { k.nettoyer() }
        k.preferences.set(true, forKey: LancementReprise.clePropositionFaite)
        _ = await k.assistant.preparerLancement(recuperation: .success(.annuleeSauf(ElementsLaisses(fichiers: ["surnoms.json"], reglages: []))))
        try await Self.capturer("15-avis-du-lancement", k.assistant, dans: dossier)

        // 16. Reglages > General avec l'entree.
        let l = try Banc()
        defer { l.nettoyer() }
        let (fenetre, _) = try await ReglagesHauteurTests.fenetre(onglet: .general, reprise: ControleurReprise(assistant: l.assistant))
        defer { fenetre.close() }
        try await Task.sleep(for: .milliseconds(600))
        let vue = try #require(fenetre.contentView)
        let rep = try #require(vue.bitmapImageRepForCachingDisplay(in: vue.bounds))
        vue.cacheDisplay(in: vue.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: dossier.appendingPathComponent("16-reglages-general.png"))

        print("CAPTURES_REPRISE_DOSSIER=\(dossier.path)")
    }
}
