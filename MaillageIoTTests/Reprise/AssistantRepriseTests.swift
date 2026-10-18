import Foundation
import MaillageCoeur
import os
import ServiceManagement
import Testing
import UserNotifications
@testable import MaillageIoT

/// Phase 4, tache 7 : l'assistant de reprise. Les textes du resume et de « A refaire » selon les cas, la detection de
/// l'ancienne app par son identifiant, et aucun import sans validation. Le modele de l'assistant tourne ici avec de vrais
/// `ApplicationImport` sur des dossiers temporaires et les exports d'exemple (valeurs inventees), et des coutures factices
/// pour tout le reste (apps lancees, modules, relance, etat du systeme) : jamais le vrai dossier de l'app, ni le trousseau,
/// ni NSWorkspace.
@Suite("Assistant de reprise")
struct AssistantRepriseTests {
    typealias C = ContratExport
    typealias App = ContratExport.AppSource
    typealias G = GenerateurExportsExemple
    typealias D = ConversionThreadTests.Donnees
    typealias Reglages = ApplicationImportTests.ReglagesEssai
    typealias Copie = ValidationExportTests.Copie

    static let fr = Locale(identifier: "fr")
    static let en = Locale(identifier: "en")

    // MARK: Detection de l'ancienne app

    @Test func lAncienneAppEstReconnueParSonIdentifiantDeBundleExact() {
        // Le prefixe ne suffit pas : l'identifiant de Maillage IoT (`fr.djoko.maillage.iot`) et celui de Zigbee
        // commencent comme celui de Thread.
        let tournent: [String?] = ["fr.djoko.maillage.iot", "fr.djoko.maillage.zigbee", nil, "com.apple.finder"]
        #expect(ApplicationsLanceesSysteme.compter(App.maillageThread.identifiantBundle, parmi: tournent) == 0)
        #expect(ApplicationsLanceesSysteme.compter(App.maillageZigbee.identifiantBundle, parmi: tournent) == 1)
        #expect(ApplicationsLanceesSysteme.compter("fr.djoko.maillage", parmi: ["fr.djoko.maillage", "fr.djoko.maillage"]) == 2)
        #expect(App.maillageThread.identifiantBundle == "fr.djoko.maillage")
        #expect(App.maillageZigbee.identifiantBundle == "fr.djoko.maillage.zigbee")
    }

    // MARK: Etat des cles du trousseau

    @Test func lEtatDUneCleSeDeduitDesTroisInventaires() {
        typealias E = EtatCleReprise
        // L'ancienne app n'a jamais eu de cle : rien a reprendre, rien a refaire.
        #expect(E.deduire(nouvelles: [], anciennes: [], tentees: []) == .aucune)
        #expect(E.deduire(nouvelles: ["a"], anciennes: [], tentees: []) == .aucune)
        // Reprise faite : la cle de l'ancienne app est dans le service de l'app.
        #expect(E.deduire(nouvelles: ["a"], anciennes: ["a"], tentees: ["a"]) == .reprise)
        #expect(E.deduire(nouvelles: ["a", "b"], anciennes: ["a"], tentees: []) == .reprise)
        // Pas encore demandee : elle l'est a la connexion.
        #expect(E.deduire(nouvelles: [], anciennes: ["a"], tentees: []) == .aReprendre)
        // Demandee, refusee ou absente : a refaire.
        #expect(E.deduire(nouvelles: [], anciennes: ["a"], tentees: ["a"]) == .nonAboutie)
        // Deux sondes : l'une reprise, l'autre refusee -> a refaire ; l'une reprise, l'autre pas encore demandee -> a reprendre.
        #expect(E.deduire(nouvelles: ["a"], anciennes: ["a", "b"], tentees: ["a", "b"]) == .nonAboutie)
        #expect(E.deduire(nouvelles: ["a"], anciennes: ["a", "b"], tentees: ["a"]) == .aReprendre)
    }

    // MARK: A refaire

    static let enOrdre = EtatSystemeReprise(sondeThread: .reprise, sondeZigbee: .reprise, pontHue: .reprise,
                                            notifications: .autorisees, ouverture: .active, reseauLocalRefuse: false)

    @Test(arguments: [App.maillageThread, .maillageZigbee])
    func rienNEstAffichePourCeQuiEstDejaEnOrdre(app: App) {
        #expect(ListeARefaire.pour(app, etat: Self.enOrdre) == [])
        // Les cles que l'ancienne app n'avait pas ne sont pas a refaire non plus.
        var aucune = Self.enOrdre
        (aucune.sondeThread, aucune.sondeZigbee, aucune.pontHue) = (.aucune, .aucune, .aucune)
        #expect(ListeARefaire.pour(app, etat: aucune) == [])
    }

    @Test func threadAvecUneCleNonAboutieDitDeMettreLaSondeEnService() {
        var e = Self.enOrdre
        e.sondeThread = .nonAboutie
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.miseEnServiceSonde(.maillageThread)])
        // Une cle de Zigbee en echec ne regarde pas l'export de Thread.
        e.sondeZigbee = .nonAboutie
        e.pontHue = .nonAboutie
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.miseEnServiceSonde(.maillageThread)])
    }

    @Test func zigbeeDitDAppairerLePontPuisDeMettreLaSondeEnService() {
        var e = Self.enOrdre
        e.pontHue = .nonAboutie
        #expect(ListeARefaire.pour(.maillageZigbee, etat: e) == [.relierPontHue])
        e.sondeZigbee = .nonAboutie
        #expect(ListeARefaire.pour(.maillageZigbee, etat: e) == [.relierPontHue, .miseEnServiceSonde(.maillageZigbee)])
        e.sondeThread = .nonAboutie
        #expect(ListeARefaire.pour(.maillageZigbee, etat: e) == [.relierPontHue, .miseEnServiceSonde(.maillageZigbee)])
    }

    @Test func uneCleAReprendreALaConnexionEstAnnoncee() {
        var e = Self.enOrdre
        e.sondeThread = .aReprendre
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.reprendreCle(.sondeThread)])
        e.pontHue = .aReprendre
        e.sondeZigbee = .aReprendre
        #expect(ListeARefaire.pour(.maillageZigbee, etat: e) == [.reprendreCle(.pontHue), .reprendreCle(.sondeZigbee)])
    }

    @Test func lesAutorisationsDeMacOSSeLisentSurLEtatReel() {
        var e = Self.enOrdre
        e.notifications = .nonDemandees
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.accepterNotifications])
        e.notifications = .refusees
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.autoriserNotifications])
        e.notifications = .autorisees
        e.ouverture = .inactive
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.activerOuverture])
        e.ouverture = .aApprouver
        #expect(ListeARefaire.pour(.maillageThread, etat: e) == [.approuverOuverture])
        e.ouverture = .active
        e.reseauLocalRefuse = true
        #expect(ListeARefaire.pour(.maillageZigbee, etat: e) == [.autoriserReseauLocal])
        // Tout ensemble, dans un ordre stable : cles, notifications, reseau local, ouverture.
        let tout = EtatSystemeReprise(sondeThread: .nonAboutie, sondeZigbee: .reprise, pontHue: .reprise,
                                      notifications: .refusees, ouverture: .inactive, reseauLocalRefuse: true)
        #expect(ListeARefaire.pour(.maillageThread, etat: tout)
                == [.miseEnServiceSonde(.maillageThread), .autoriserNotifications, .autoriserReseauLocal, .activerOuverture])
    }

    @Test func lesStatutsDuSystemeSeTraduisent() {
        #expect(StatutNotifications(.authorized) == .autorisees)
        #expect(StatutNotifications(.provisional) == .autorisees)
        #expect(StatutNotifications(.notDetermined) == .nonDemandees)
        #expect(StatutNotifications(.denied) == .refusees)
        #expect(StatutOuverture(.enabled) == .active)
        #expect(StatutOuverture(.requiresApproval) == .aApprouver)
        #expect(StatutOuverture(.notRegistered) == .inactive)
        #expect(StatutOuverture(.notFound) == .inactive)
    }

    @Test func chaqueTacheADesTextesEnFrancaisEtEnAnglais() {
        let taches: [TacheARefaire] = [
            .reprendreCle(.sondeThread), .reprendreCle(.sondeZigbee), .reprendreCle(.pontHue),
            .miseEnServiceSonde(.maillageThread), .miseEnServiceSonde(.maillageZigbee), .relierPontHue,
            .accepterNotifications, .autoriserNotifications, .activerOuverture, .approuverOuverture, .autoriserReseauLocal,
        ]
        for t in taches {
            for locale in [Self.fr, Self.en] {
                #expect(!t.titre(locale: locale).isEmpty && !t.detail(locale: locale).isEmpty)
            }
            #expect(t.titre(locale: Self.fr) != t.titre(locale: Self.en), "\(t) : titre traduit")
            #expect(t.detail(locale: Self.fr) != t.detail(locale: Self.en), "\(t) : detail traduit")
        }
        // La mise en service remplace l'ancienne cle : le texte le dit, pour chaque sonde (spec 4.4).
        for app in [App.maillageThread, .maillageZigbee] {
            let t = TacheARefaire.miseEnServiceSonde(app)
            #expect(t.detail(locale: Self.fr).contains("injoignable"))
            #expect(t.detail(locale: Self.en).contains("unreachable"))
            #expect(t.titre(locale: Self.fr).contains(app == .maillageThread ? "Thread" : "Zigbee"))
        }
        #expect(TacheARefaire.relierPontHue.titre(locale: Self.fr).contains("pont Hue"))
    }

    // MARK: Lecture de l'etat reel

    /// Un inventaire du trousseau fait a la main : service -> comptes. Jamais le vrai trousseau.
    struct InventaireFactice: InventaireTrousseau {
        var parService: [String: Set<String>] = [:]
        func comptes(service: String) -> Set<String> { parService[service] ?? [] }
    }

    static func preferences() -> (UserDefaults, String) {
        let nom = "fr.djoko.maillage.iot.essai-assistant-\(UUID().uuidString)"
        return (UserDefaults(suiteName: nom)!, nom)
    }

    @Test func lEtatReelSeLitDuTrousseauDesReprisesEtDuSysteme() async {
        let (prefs, nom) = Self.preferences()
        defer { prefs.removePersistentDomain(forName: nom) }
        // Thread : la cle de l'ancienne app est la, copiee dans le service de l'app. Zigbee : le pont est refuse, la sonde
        // pas encore demandee.
        prefs.set(["sonde-1"], forKey: MemoireReprises.cleSondeThread)
        prefs.set(["pont-1"], forKey: MemoireReprises.clePontZigbee)
        let inventaire = InventaireFactice(parService: [
            TrousseauSystemeThread.serviceParDefaut: ["sonde-1"], TrousseauReprisThread.serviceAncien: ["sonde-1"],
            TrousseauRepris.servicePontAncien: ["pont-1"], TrousseauRepris.serviceSondeAncien: ["aa:bb"],
        ])
        let lecteur = LecteurEtatSystemeReel(inventaire: inventaire, suite: nom,
                                             notifications: { .nonDemandees }, ouverture: { .aApprouver },
                                             reseauLocalRefuse: { true })
        let etat = await lecteur.lire()
        #expect(etat == EtatSystemeReprise(sondeThread: .reprise, sondeZigbee: .aReprendre, pontHue: .nonAboutie,
                                           notifications: .nonDemandees, ouverture: .aApprouver, reseauLocalRefuse: true))
        #expect(ListeARefaire.pour(.maillageZigbee, etat: etat)
                == [.relierPontHue, .reprendreCle(.sondeZigbee), .accepterNotifications, .autoriserReseauLocal, .approuverOuverture])
        #expect(ListeARefaire.pour(.maillageThread, etat: etat) == [.accepterNotifications, .autoriserReseauLocal, .approuverOuverture])
    }

    // MARK: Resume final

    static func repris(_ app: App, dans d: D, _ r: Reglages) async throws -> (ResultatApplication, ResumeExport) {
        let a = ApplicationImportTests.appli(d, r)
        guard case .aReprendre(let p) = try await a.preparer(export: ApplicationImportTests.exemple(app)) else {
            throw ApplicationImportTests.Echec("deja repris")
        }
        return (try await a.appliquer(p), p.resume)
    }

    @Test(arguments: [App.maillageThread, .maillageZigbee])
    func leResumeDitCeQuiEstReprisEtCeQuiEstIgnore(app: App) async throws {
        let d = try D(), r = Reglages()
        let (resultat, resume) = try await Self.repris(app, dans: d, r)
        let final = ResumeFinal(resultat: resultat, resume: resume)
        #expect(final.app == app && final.versionApp == resume.versionApp)
        #expect(final.fichiersRepris == resultat.fichiersEcrits.count && final.fichiersRepris > 0)
        #expect(final.reglagesRepris == resultat.reglagesEcrits.count)
        // Rien ne se perd en silence : chaque element non pris est compte dans une ligne.
        let total = resultat.nonPris.reduce(0) { somme, e in
            if case .entrees(_, let n) = e.nature { return somme + n }
            return somme + 1
        }
        #expect(final.ignores.reduce(0) { $0 + $1.nombre } == total)
        #expect(final.ignores.map(\.raison) == final.ignores.map(\.raison).sorted { $0.rawValue < $1.rawValue }, "ordre stable")
        for locale in [Self.fr, Self.en] {
            let lignes = final.lignesReprises(locale: locale) + final.lignesIgnorees(locale: locale)
            #expect(lignes.count == 2 + final.ignores.count)
            #expect(lignes.allSatisfy { !$0.isEmpty })
        }
        #expect(final.lignesReprises(locale: Self.fr)[0] == "Fichiers repris : \(resultat.fichiersEcrits.count)")
        #expect(final.lignesReprises(locale: Self.en)[0] == "Files imported: \(resultat.fichiersEcrits.count)")
        #expect(final.lignesReprises(locale: Self.fr)[1] == "Réglages repris : \(resultat.reglagesEcrits.count)")
        #expect(final.origine(locale: Self.fr).contains(app.nomApp) && final.origine(locale: Self.fr).contains(resume.versionApp))
        #expect(final.texteLaisses(locale: Self.fr) == nil)
    }

    @Test func leResumeCiteLesFichiersDeDeuxExportsQueLeHistoriqueDePlusDe90JoursEcarte() async throws {
        let d = try D(), r = Reglages()
        let (resultat, resume) = try await Self.repris(.maillageThread, dans: d, r)
        let final = ResumeFinal(resultat: resultat, resume: resume)
        let ligne = try #require(final.ignores.first { $0.raison == .plusDe90Jours }, "l'exemple de Thread a des mois de plus de 90 jours")
        #expect(ligne.nombre >= 1)
        #expect(final.lignesIgnorees(locale: Self.fr).contains("Historique de plus de 90 jours : \(ligne.nombre)"))
    }

    @Test func leResumeCiteCeQueLAppAEcritEntretemps() {
        let resultat = ResultatApplication(
            repris: ImportRepris(identifiant: UUID(), app: .maillageThread, versionApp: "1.4.0", date: G.dateReference),
            fichiersEcrits: ["a.json"], reglagesEcrits: [], nonPris: [], planRecalcule: true,
            laisses: ElementsLaisses(fichiers: ["Journal/journal-2026-10.jsonl", "surnoms.json"], reglages: ["thread.sondeHote"]))
        let final = ResumeFinal(resultat: resultat, app: .maillageThread, versionApp: "1.4.0", dateExport: G.dateReference)
        let texte = final.texteLaisses(locale: Self.fr)
        #expect(texte?.contains("Journal/journal-2026-10.jsonl") == true && texte?.contains("surnoms.json") == true
                && texte?.contains("thread.sondeHote") == true)
        #expect(final.planRecalcule)
        #expect(final.texteRecalcul(locale: Self.fr) != nil)
        // Il se garde tel quel d'un lancement a l'autre.
        let relu = try? JSONDecoder().decode(ResumeFinal.self, from: JSONEncoder().encode(final))
        #expect(relu == final)
    }

    @Test func chaqueRaisonDIgnorerADesTextesEnFrancaisEtEnAnglais() {
        for raison in RaisonIgnoree.allCases {
            let f = raison.libelle(locale: Self.fr), e = raison.libelle(locale: Self.en)
            #expect(!f.isEmpty && !e.isEmpty && f != e, "\(raison)")
        }
        // Chaque raison du plan se range dans une raison du resume.
        let raisons: [ElementNonPris.Raison] = [
            .plusDe90Jours, .dejaDansMaillageIoT, .vide, .releveMaisonNonPlusRecent, .fichierIllisible, .fichierExistantNonLisible,
            .sansEquivalent,
        ] + C.RaisonNonRepris.allCases.map { .laisseParLAncienneApp($0) }
        #expect(Set(raisons.map(RaisonIgnoree.init)).count == RaisonIgnoree.allCases.count)
    }

    // MARK: Erreurs lisibles

    @Test func chaqueErreurDApplicationADesMotsEtNeDitJamaisUnChemin() {
        let laisses = ElementsLaisses(fichiers: ["surnoms.json"], reglages: ["thread.sondeHote"])
        let erreurs: [ErreurApplication] = [
            .refuse(.manifesteAbsent), .exportModifie,
            .dejaRepris(ImportRepris(identifiant: UUID(), app: .maillageZigbee, versionApp: "1.2.0", date: G.dateReference)),
            .etatInstable,
            .echec(.preparation, retablie: true, code: "NSCocoaErrorDomain 640"),
            .echec(.remplacement, retablie: false, code: "NSCocoaErrorDomain 640"),
            .echec(.reglages, retablie: true, code: "x 1"), .echec(.validation, retablie: true, code: "x 1"),
            .echecAvecReste(.validation, laisses, code: "NSCocoaErrorDomain 640"),
            .recuperationImpossible(code: "NSCocoaErrorDomain 4"),
        ]
        for e in erreurs {
            let f = TexteReprise.erreur(e, locale: Self.fr), a = TexteReprise.erreur(e, locale: Self.en)
            #expect(!f.isEmpty && !a.isEmpty && f != a, "\(e)")
            #expect(!f.contains("/Users") && !a.contains("/Users"))
        }
        let reste = TexteReprise.erreur(.echecAvecReste(.validation, laisses, code: "x 1"), locale: Self.fr)
        #expect(reste.contains("surnoms.json") && reste.contains("thread.sondeHote"))
        #expect(TexteReprise.erreur(.echec(.preparation, retablie: false, code: "x 1"), locale: Self.fr).contains("lancement"),
                "retablie = faux : le prochain lancement remet en etat")
    }

    @Test func lAvisDuLancementCiteCeQueLaRecuperationAMontre() {
        let laisses = ElementsLaisses(fichiers: ["surnoms.json"], reglages: ["thread.sondeHote"])
        #expect(AvisLancement(.success(.rienAFaire)) == nil)
        #expect(AvisLancement(.success(.nettoyee)) == nil)
        #expect(AvisLancement(.success(.terminee)) == nil)
        #expect(AvisLancement(.success(.annulee)) != nil)
        let sauf = AvisLancement(.success(.annuleeSauf(laisses)))
        #expect(sauf?.texte(locale: Self.fr).contains("surnoms.json") == true)
        #expect(sauf?.texte(locale: Self.fr).contains("thread.sondeHote") == true)
        #expect(sauf?.texte(locale: Self.en) != sauf?.texte(locale: Self.fr))
        let impossible = AvisLancement(.failure(.recuperationImpossible(code: "NSCocoaErrorDomain 4")))
        #expect(impossible?.texte(locale: Self.fr).contains("NSCocoaErrorDomain 4") == true)
    }

    // MARK: Le modele de l'assistant

    /// Les apps lancees, a la main : l'ancienne app tourne tant que `tournent` la contient ; `quitte` dit si la demande de
    /// quitter est acceptee (sinon le bac a sable l'a refusee) et si elle suffit (l'app s'arrete).
    @MainActor
    final class AppsFactices: ApplicationsLancees {
        var tournent: [String: Int] = [:]
        var demandes: [String] = []
        var accepte = true
        var quitteVraiment = true

        func instances(de identifiantBundle: String) -> Int { tournent[identifiantBundle] ?? 0 }

        func demanderDeQuitter(_ identifiantBundle: String) async -> Bool {
            demandes.append(identifiantBundle)
            if accepte && quitteVraiment { tournent[identifiantBundle] = nil }
            return accepte
        }
    }

    struct LecteurFactice: LecteurEtatSysteme {
        var etat = AssistantRepriseTests.enOrdre
        func lire() async -> EtatSystemeReprise { etat }
    }

    /// Un lecteur dont l'etat change entre deux lectures (l'issue de Bonjour, des notifications, du dialogue de cle).
    final class LecteurMutable: LecteurEtatSysteme, Sendable {
        private let courant: OSAllocatedUnfairLock<EtatSystemeReprise>
        let lectures = OSAllocatedUnfairLock(initialState: 0)

        init(_ etat: EtatSystemeReprise) { courant = OSAllocatedUnfairLock(initialState: etat) }

        func changer(_ modification: @Sendable (inout EtatSystemeReprise) -> Void) { courant.withLock { modification(&$0) } }

        func lire() async -> EtatSystemeReprise {
            lectures.withLock { $0 += 1 }
            return courant.withLock { $0 }
        }
    }

    /// Un importeur qui compte ses appels et note l'ordre des evenements (avec les modules et la relance).
    final class ImporteurEspion: ImporteurExport, Sendable {
        let reel: ApplicationImport
        let evenements: OSAllocatedUnfairLock<[String]>
        /// Si non nil : `appliquer` attend que ce flux se libere (pour tenir un import en vol).
        let porte: Porte?
        let erreurApplication: OSAllocatedUnfairLock<ErreurApplication?>

        init(_ reel: ApplicationImport, evenements: OSAllocatedUnfairLock<[String]>, porte: Porte? = nil, erreur: ErreurApplication? = nil) {
            self.reel = reel
            self.evenements = evenements
            self.porte = porte
            erreurApplication = OSAllocatedUnfairLock(initialState: erreur)
        }

        func preparer(export: URL) async throws -> IssuePreparation {
            evenements.withLock { $0.append("preparer") }
            return try await reel.preparer(export: export)
        }

        func appliquer(_ p: PreparationImport) async throws -> ResultatApplication {
            evenements.withLock { $0.append("appliquer") }
            await porte?.attendre()
            if let e = erreurApplication.withLock({ $0 }) { throw e }
            return try await reel.appliquer(p)
        }

        func nombre(_ nom: String) -> Int { evenements.withLock { $0.filter { $0 == nom }.count } }
    }

    /// Une porte qui retient un appel jusqu'a `ouvrir()`.
    final class Porte: Sendable {
        private let etat = OSAllocatedUnfairLock<(ouverte: Bool, suites: [CheckedContinuation<Void, Never>])>(initialState: (false, []))
        func attendre() async {
            await withCheckedContinuation { suite in
                let passe = etat.withLock { e -> Bool in
                    if e.ouverte { return true }
                    e.suites.append(suite)
                    return false
                }
                if passe { suite.resume() }
            }
        }

        func ouvrir() {
            let suites = etat.withLock { e -> [CheckedContinuation<Void, Never>] in
                e.ouverte = true
                defer { e.suites = [] }
                return e.suites
            }
            suites.forEach { $0.resume() }
        }
    }

    /// Tout ce qu'il faut pour faire tourner l'assistant sans toucher a rien de reel.
    @MainActor
    struct Banc {
        let donnees: D
        let reglages: Reglages
        let preferences: UserDefaults
        let nomPreferences: String
        let apps: AppsFactices
        let evenements: OSAllocatedUnfairLock<[String]>
        let importeur: ImporteurEspion
        let assistant: AssistantReprise
        let relances: OSAllocatedUnfairLock<Int>

        init(porte: Porte? = nil, erreur: ErreurApplication? = nil, relanceEchoue: Bool = false, etat: EtatSystemeReprise = AssistantRepriseTests.enOrdre,
             choix: URL? = nil, delaiQuitter: Duration = .zero, lecteur: (any LecteurEtatSysteme)? = nil,
             pasRelecture: Duration = .seconds(2)) throws {
            donnees = try D()
            reglages = Reglages()
            (preferences, nomPreferences) = AssistantRepriseTests.preferences()
            apps = AppsFactices()
            evenements = OSAllocatedUnfairLock(initialState: [])
            relances = OSAllocatedUnfairLock(initialState: 0)
            importeur = ImporteurEspion(ApplicationImportTests.appli(donnees, reglages), evenements: evenements, porte: porte, erreur: erreur)
            let ev = evenements, rel = relances
            assistant = AssistantReprise(
                importeur: importeur, dossierDonnees: donnees.racine, applications: apps, lecteur: lecteur ?? LecteurFactice(etat: etat),
                preferences: preferences,
                arreterModules: { ev.withLock { $0.append("arreterModules") } },
                relancer: {
                    ev.withLock { $0.append("relancer") }
                    rel.withLock { $0 += 1 }
                    if relanceEchoue { throw CocoaError(.fileNoSuchFile) }
                },
                choisirDossier: { choix },
                attendre: { _ in }, pasRelecture: pasRelecture)
        }

        func nettoyer() { preferences.removePersistentDomain(forName: nomPreferences) }

        var arbre: [String: String] { (try? ApplicationImportTests.arbre(donnees)) ?? [:] }
    }

    @MainActor
    @Test func aucunImportSansValidation() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        // Au depart, ou apres un refus, ou pendant une validation : lancer ne fait rien.
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0 && b.importeur.nombre("arreterModules") == 0)
        #expect(b.assistant.etape == .accueil)
        let copie = try Copie(.maillageThread)
        try Data("{}".utf8).write(to: copie.url("surnoms.json")) // fichier modifie : taille et empreinte fausses
        await b.assistant.valider(copie.dossier)
        guard case .refuse(.tailleFausse) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0, "un export refuse ne s'importe pas")
        #expect(b.evenements.withLock { $0 } == ["preparer"], "les modules ne sont pas arretes")
        #expect(b.arbre.isEmpty && b.relances.withLock { $0 } == 0, "rien n'est ecrit")
    }

    @MainActor
    @Test func unExportValideSeReprendEtLAppSeRelanceModulesArretesAvant() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        guard case .confirmation(let resume) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(resume.app == .maillageThread && b.arbre.isEmpty, "valider n'ecrit rien")
        #expect(b.assistant.peutLancer)
        await b.assistant.lancer()
        // Les modules sont arretes AVANT l'application, la relance vient apres, une seule fois.
        #expect(b.evenements.withLock { $0 } == ["preparer", "arreterModules", "appliquer", "relancer"])
        #expect(b.arbre["imports.json"] != nil && b.arbre["surnoms.json"] != nil)
        // Le resume est garde pour le lancement suivant, qui le montre avec l'etat reel a ce moment-la.
        #expect(DepotResume(preferences: b.preferences).lire() != nil)
        #expect(b.assistant.etape == .relance)
    }

    @MainActor
    @Test func apresLaRelanceLeResumeEstMontreAvecLEtatReelEtOublieQuandOnTermine() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageZigbee))
        await b.assistant.lancer()
        // Le lancement suivant : un autre modele, les memes preferences, et l'etat du Mac tel qu'il est alors.
        var etat = Self.enOrdre
        etat.pontHue = .nonAboutie
        etat.notifications = .nonDemandees
        let suivant = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                       lecteur: LecteurFactice(etat: etat), preferences: b.preferences, arreterModules: {},
                                       relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        let doitMontrer = await suivant.preparerLancement(recuperation: .success(.rienAFaire))
        #expect(doitMontrer)
        guard case .termine(let final, let taches) = suivant.etape else { throw ApplicationImportTests.Echec("\(suivant.etape)") }
        #expect(final.app == .maillageZigbee)
        #expect(taches == [.relierPontHue, .accepterNotifications])
        #expect(!suivant.relanceEchouee)
        suivant.terminer()
        #expect(DepotResume(preferences: b.preferences).lire() == nil)
        let encore = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                      lecteur: LecteurFactice(), preferences: b.preferences, arreterModules: {}, relancer: {},
                                      choisirDossier: { nil }, attendre: { _ in })
        #expect(await encore.preparerLancement(recuperation: .success(.rienAFaire)) == false, "le resume ne revient pas, ni la proposition (des imports existent)")
    }

    @MainActor
    @Test func siLaRelanceEchoueLeResumeResteEtOnDemandeDeRouvrir() async throws {
        let b = try Banc(relanceEchoue: true)
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        guard case .termine(let final, _) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(final.app == .maillageThread)
        #expect(b.assistant.relanceEchouee, "le bouton « Quitter Maillage IoT » prend la suite")
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "le resume attend le lancement suivant")
        #expect(b.relances.withLock { $0 } == 1)
    }

    @MainActor
    @Test func uneAncienneAppQuiTourneEmpecheLImportJusquAuQuitter() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        b.apps.tournent[App.maillageThread.identifiantBundle] = 1
        // L'autre ancienne app, elle, ne gene pas un export de Thread.
        b.apps.tournent[App.maillageZigbee.identifiantBundle] = 1
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        #expect(b.assistant.ancienneApp == .tourne)
        #expect(!b.assistant.peutLancer)
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0 && b.importeur.nombre("arreterModules") == 0, "l'import ne demarre pas")
        // « Quitter Maillage Thread » : terminate, jamais forceTerminate ; la reverification la voit partie.
        await b.assistant.quitterAncienneApp()
        #expect(b.apps.demandes == [App.maillageThread.identifiantBundle])
        #expect(b.assistant.ancienneApp == .absente && b.assistant.peutLancer)
        #expect(b.apps.tournent[App.maillageZigbee.identifiantBundle] == 1, "on ne quitte que l'app de cet export")
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 1)
    }

    @MainActor
    @Test func siLeBacASableRefuseDeQuitterOnDemandeAQuitterSoiMeme() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        b.apps.tournent[App.maillageZigbee.identifiantBundle] = 1
        b.apps.accepte = false
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageZigbee))
        await b.assistant.quitterAncienneApp()
        #expect(b.assistant.ancienneApp == .aQuitterSoiMeme, "terminate a rendu faux")
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0)
        // Terminate accepte mais l'app tourne encore apres l'attente : meme message.
        b.apps.accepte = true
        b.apps.quitteVraiment = false
        await b.assistant.quitterAncienneApp()
        #expect(b.assistant.ancienneApp == .aQuitterSoiMeme)
        // Djoko la quitte lui-meme : la reverification la voit partie.
        b.apps.tournent[App.maillageZigbee.identifiantBundle] = nil
        b.assistant.verifierAncienneApp()
        #expect(b.assistant.ancienneApp == .absente && b.assistant.peutLancer)
        // Si elle revient entre-temps, `lancer` la voit aussi, juste avant d'agir.
        b.apps.tournent[App.maillageZigbee.identifiantBundle] = 1
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0 && b.assistant.ancienneApp == .tourne)
    }

    @MainActor
    @Test func deuxImportsNeSeChevauchentJamais() async throws {
        let porte = Porte()
        let b = try Banc(porte: porte)
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        let premier = Task { @MainActor in await b.assistant.lancer() }
        // Laisser le premier arriver dans `appliquer` (retenu par la porte).
        while b.importeur.nombre("appliquer") == 0 { await Task.yield() }
        #expect(b.assistant.occupe && !b.assistant.peutLancer, "le bouton est desactive")
        await b.assistant.lancer()
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageZigbee))
        #expect(b.importeur.nombre("appliquer") == 1 && b.importeur.nombre("preparer") == 1, "ni deuxieme import, ni nouvelle validation")
        porte.ouvrir()
        await premier.value
        #expect(b.importeur.nombre("appliquer") == 1)
        #expect(!b.assistant.occupe || b.assistant.etape == .relance)
    }

    @MainActor
    @Test func unImportQuiEchoueRendLesMotsEtOffreDeRelancer() async throws {
        let b = try Banc(erreur: .echec(.remplacement, retablie: true, code: "NSCocoaErrorDomain 640"))
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        guard case .echec(let e) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(e == .echec(.remplacement, retablie: true, code: "NSCocoaErrorDomain 640"))
        // Les modules sont arretes : l'app ne peut rester ainsi. Fermer la fenetre (ou « Relancer ») la relance.
        #expect(b.assistant.modulesArretes && b.relances.withLock { $0 } == 0)
        await b.assistant.relancerApresEchec()
        #expect(b.relances.withLock { $0 } == 1)
        #expect(DepotResume(preferences: b.preferences).lire() == nil, "pas de resume pour un echec")
    }

    @MainActor
    @Test func fermerLaFenetreApresUnEchecRelanceLApp() async throws {
        let b = try Banc(erreur: .etatInstable)
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        await b.assistant.fenetreFermee()
        #expect(b.relances.withLock { $0 } == 1)
        // Fermer la fenetre d'un assistant dont les modules tournent n'a aucun effet.
        let propre = try Banc()
        defer { propre.nettoyer() }
        await propre.assistant.fenetreFermee()
        #expect(propre.relances.withLock { $0 } == 0)
    }

    // MARK: Correctifs du tour 1

    /// I1 : la liste « A refaire » se relit sur l'etat reel tant que le resume est montre : une ligne qui n'est plus vraie
    /// disparait, une ligne vraie apparait (le refus de la cle, l'issue de Bonjour, celle des notifications).
    @MainActor
    @Test func laListeARefaireSeRelitEtSuitLEtatDuMac() async throws {
        var depart = Self.enOrdre
        depart.pontHue = .aReprendre
        depart.notifications = .nonDemandees
        let lecteur = LecteurMutable(depart)
        let b = try Banc(relanceEchoue: true, lecteur: lecteur)
        defer { b.nettoyer() }
        await b.assistant.relireARefaire()
        #expect(b.assistant.etape == .accueil && lecteur.lectures.withLock { $0 } == 0, "hors du resume, rien ne se relit")
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageZigbee))
        await b.assistant.lancer()
        guard case .termine(let final, let avant) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(avant == [.reprendreCle(.pontHue), .accepterNotifications])
        // macOS a refuse la cle du pont, et Djoko a accepte les notifications : « Autoriser » disparait, « Appairer » apparait.
        lecteur.changer { $0.pontHue = .nonAboutie; $0.notifications = .autorisees }
        await b.assistant.relireARefaire()
        guard case .termine(let memeResume, let apres) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(memeResume == final, "le resume ne change pas")
        #expect(apres == [.relierPontHue])
        // Bonjour voit le refus du reseau local.
        lecteur.changer { $0.reseauLocalRefuse = true }
        await b.assistant.relireARefaire()
        guard case .termine(_, let reseau) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(reseau == [.relierPontHue, .autoriserReseauLocal])
        // Tout est en ordre : la liste se vide.
        lecteur.changer { $0 = Self.enOrdre }
        await b.assistant.relireARefaire()
        guard case .termine(_, let vide) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(vide.isEmpty)
    }

    /// I1 : la fenetre qui montre le resume relit toute seule (le dialogue de cle ou de notifications se repond apres coup).
    @MainActor
    @Test func leResumeRelitLaListeToutSeulJusquAuTermine() async throws {
        var depart = Self.enOrdre
        depart.notifications = .nonDemandees
        let lecteur = LecteurMutable(depart)
        let b = try Banc(relanceEchoue: true, lecteur: lecteur, pasRelecture: .milliseconds(10))
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        guard case .termine(_, let avant) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(avant == [.accepterNotifications])
        let suivi = Task { @MainActor in await b.assistant.surveillerARefaire() }
        lecteur.changer { $0.notifications = .autorisees }
        var liste: [TacheARefaire] = avant
        for _ in 0..<300 {
            if case .termine(_, let t) = b.assistant.etape { liste = t }
            if liste.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(liste.isEmpty, "la ligne n'est plus vraie : elle a disparu")
        // « Termine » : la surveillance s'arrete d'elle-meme.
        b.assistant.terminer()
        await suivi.value
        #expect(b.assistant.etape == .accueil)
    }

    /// M2 : tant que les modules sont arretes, la fenetre ne se ferme pas en laissant l'app tourner sans eux, et le resume reste.
    @MainActor
    @Test func fermerLaFenetreNeLaisseJamaisLAppSansSesModules() async throws {
        let b = try Banc(relanceEchoue: true)
        defer { b.nettoyer() }
        #expect(!b.assistant.fermetureRefusee, "modules en marche : la fenetre se ferme")
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        #expect(b.assistant.relanceEchouee && b.assistant.fermetureRefusee)
        await b.assistant.fenetreFermee()
        guard case .termine = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "le resume reste")
        #expect(b.assistant.fermetureRefusee)
        // Un echec dont la relance echoue aussi : meme garde.
        let c = try Banc(erreur: .etatInstable, relanceEchoue: true)
        defer { c.nettoyer() }
        await c.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await c.assistant.lancer()
        #expect(c.assistant.fermetureRefusee, "echec, relance pas encore tentee : la croix relance, elle ne ferme pas")
        await c.assistant.relancerApresEchec()
        #expect(c.assistant.relanceEchouee && c.assistant.fermetureRefusee)
    }

    /// M9 : la preparation (jusqu'a 100 Mo) est lachee quand la fenetre est fermee sur l'etape de confirmation.
    @MainActor
    @Test func fermerLaFenetreSurLaConfirmationLacheLaPreparation() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        #expect(b.assistant.peutLancer && b.assistant.preparationGardee)
        await b.assistant.fenetreFermee()
        #expect(b.assistant.etape == .accueil && !b.assistant.preparationGardee && !b.assistant.peutLancer)
        await b.assistant.lancer()
        #expect(b.importeur.nombre("appliquer") == 0)
    }

    /// M6 : « Rien a refaire » ne dit pas plus que ce que l'app sait (le reseau local ne se lit pas).
    @Test func rienARefaireNeDitPasPlusQueCeQueLAppSait() {
        let fr = ListeARefaire.rienARefaire(locale: Self.fr)
        let en = ListeARefaire.rienARefaire(locale: Self.en)
        #expect(!fr.contains("tout est en ordre") && fr.contains("macOS"))
        #expect(!en.contains("everything is in order") && en.contains("macOS") && en != fr)
        let noteFr = ListeARefaire.noteReseauLocal(locale: Self.fr)
        let noteEn = ListeARefaire.noteReseauLocal(locale: Self.en)
        #expect(noteFr.contains("réseau local") && noteEn.contains("local network") && noteEn != noteFr)
    }

    /// M10 : anglais coherent (« Imported »), « Still to do », dates formatees avec la langue de l'environnement.
    @Test func lAnglaisDeLaRepriseEstCoherentEtLesDatesSuiventLaLangue() throws {
        #expect(ListeARefaire.titreSection(locale: Self.en) == "Still to do")
        #expect(ListeARefaire.titreSection(locale: Self.fr) == "À refaire")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let fr = TexteReprise.date(date, locale: Self.fr)
        let en = TexteReprise.date(date, locale: Self.en)
        #expect(fr != en, "fr : \(fr), en : \(en)")
        #expect(fr.localizedCaseInsensitiveContains("janv") || fr.localizedCaseInsensitiveContains("déc") || fr.localizedCaseInsensitiveContains("janvier"))
    }

    /// M1 : en demo, ni section « Reprise » ni proposition ni recuperation ; hors demo, oui.
    @Test func enDemoAucuneRepriseNEstPossible() {
        #expect(!LancementReprise.disponible(demo: true))
        #expect(LancementReprise.disponible(demo: false))
    }

    @MainActor
    @Test func unExportDejaReprisNeSeReprendPasDeuxFois() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        let avant = b.arbre
        let b2 = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                  lecteur: LecteurFactice(), preferences: b.preferences, arreterModules: {}, relancer: {},
                                  choisirDossier: { nil }, attendre: { _ in })
        await b2.valider(try ApplicationImportTests.exemple(.maillageThread))
        guard case .dejaRepris(let repris, _) = b2.etape else { throw ApplicationImportTests.Echec("\(b2.etape)") }
        #expect(repris.app == .maillageThread)
        await b2.lancer()
        #expect(b.arbre == avant)
    }

    @MainActor
    @Test func unJournalDesImportsAbimePeutEtreMisDeCoteSansRienSupprimer() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        try b.donnees.ecrire("imports.json", "pas du json")
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        guard case .refuse(.journalDesImportsIllisible) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(b.assistant.peutRepartirDUnJournalVide)
        await b.assistant.repartirDUnJournalVide()
        // Mis de cote, jamais supprime ; l'export est valide de nouveau.
        #expect(try Data(contentsOf: b.donnees.url("imports.json.abime")) == Data("pas du json".utf8))
        #expect(!FileManager.default.fileExists(atPath: b.donnees.url("imports.json").path))
        guard case .confirmation = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(!b.assistant.peutRepartirDUnJournalVide)
    }

    @MainActor
    @Test func choisirLeDossierPasseParLePanneauEtValide() async throws {
        let dossier = try ApplicationImportTests.exemple(.maillageZigbee)
        let b = try Banc(choix: dossier)
        defer { b.nettoyer() }
        await b.assistant.choisirDossier()
        guard case .confirmation(let resume) = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(resume.app == .maillageZigbee)
        // Un panneau annule ne change rien.
        let annule = try Banc(choix: nil)
        defer { annule.nettoyer() }
        await annule.assistant.choisirDossier()
        #expect(annule.assistant.etape == .accueil && annule.importeur.nombre("preparer") == 0)
    }

    // MARK: Arret des modules

    /// Passeur Noms (le releve de Maison, ecrit dans `releve-maison.json`) est arrete avant l'import : plus de reabonnement ni
    /// d'ecriture du releve dans le dossier de donnees.
    @MainActor
    @Test func passeurNomsArrete_neSeReabonnePlusEtNEcritPlus() async throws {
        let cache = NomsPasseurTests.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, attentes: [.milliseconds(10)],
                            lanceur: NomsPasseurTests.lanceur(lancements, echec: .introuvable(ancien: false)))
        n.demarrer()
        _ = await NomsPasseurTests.cible(lancements, fois: 3)
        #expect(lancements.tous.count >= 3, "il se reabonne tant qu'il tourne")
        n.arreter()
        let apres = lancements.tous.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(lancements.tous.count == apres, "arrete : plus de reabonnement")
        n.integrer(NomsPasseurTests.releve())
        #expect(!FileManager.default.fileExists(atPath: cache.path), "arrete : le releve n'est plus ecrit")
        // Il peut repartir (le reglage « Activer » ne passe pas par la, mais un demarrage explicite le rend actif).
        n.demarrer()
        _ = await NomsPasseurTests.cible(lancements, fois: apres + 1)
        #expect(lancements.tous.count > apres)
        n.arreter()
    }

    /// `arreterTout` arrete TOUS les modules de l'app : chaque module que `ModulesApp` porte (sonde, pont, decouverte, client du
    /// demon, coque...) est dans la liste de ceux qu'elle arrete. Un module retire de la liste, ou ajoute a l'app sans y etre
    /// inscrit, fait echouer ce test (les arrets eux-memes sont testes module par module).
    @MainActor
    @Test func tousLesModulesDeLAppSArretent() {
        let m = ModulesApp(demo: nil, sousTests: true)
        let arretes = m.modulesArretables.map { ObjectIdentifier($0) }
        let portes = Mirror(reflecting: m).children.compactMap { $0.value as? any ModuleArretable }
        #expect(portes.count == 6, "la coque, deux sondes, le pont, sa decouverte, le client du demon : \(portes.count)")
        for module in portes {
            #expect(arretes.contains(ObjectIdentifier(module)), "\(type(of: module)) n'est pas arrete par arreterTout")
        }
        #expect(Set(arretes).count == arretes.count, "aucun module n'est arrete deux fois")
        m.surveillance.demarrer()
        m.arreterTout() // inertes sous les tests : l'appel ne doit rien ouvrir, rien casser, et se repeter sans danger
        m.arreterTout()
        #expect(m.surveillance.arretee, "la coque se sait arretee")
    }

    /// Apres `arreterTout`, aucun reglage ne relance un module avant la relance de l'app (M4) : « Activer ce protocole » ne
    /// rallume ni la sonde de Thread, ni celle de Zigbee, ni le pont, ni Bonjour ; les pages des protocoles sont grisees.
    @MainActor
    @Test func apresLArretAucunReglageNeRelanceUnModule() async throws {
        let (pp, dp) = try SondeMaillageTests.preferences()
        defer { pp.removePersistentDomain(forName: dp) }
        pp.set(SondeMaillageTests.port.serie, forKey: SondeMaillageThread.cleSerie)
        let b = try BancActivation()
        defer { b.nettoyer() }
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let branche = SondeMaillageTests.port
        let sonde = SondeMaillageThread(preferences: pp, actif: true,
                                        ouvrirCanal: { registre.canal($0, CanalRejoue { CanalRejoue.reseauMinimal($0) }) },
                                        surveillerPorts: ports.fabriquer, listerPorts: { [branche] })
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        let pont = ArretNomsPontTests.banc()
        let ecoutePont = BonjourFactice(type: DecouvertePont.type)
        let decouverte = DecouvertePont(navigateur: ecoutePont)
        ModulesApp.relierThread(b.s, sonde: sonde)
        ModulesApp.relierZigbee(b.s, sonde: z.sonde, nomsPont: pont.pont, decouverte: decouverte)
        b.s.demarrer()
        #expect(b.s.protocoleReglable(.thread) && b.s.protocoleReglable(.zigbee))
        // L'arret de la reprise (ce que fait `ModulesApp.arreterTout`).
        b.s.arreter()
        sonde.arreter()
        z.sonde.arreter()
        pont.pont.arreter()
        decouverte.arreter()
        #expect(!b.s.protocoleReglable(.thread) && !b.s.protocoleReglable(.zigbee), "les pages des protocoles sont grisees")
        // Un interrupteur manie pendant la reprise ne rallume rien.
        b.s.thread.actif = false
        b.s.thread.actif = true
        b.s.zigbee.actif = false
        b.s.zigbee.actif = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(!sonde.actif && sonde.tachesPlanifiees == 0, "la sonde de Thread reste arretee")
        #expect(!z.sonde.actif && z.sonde.tachesPlanifiees == 0, "la sonde de Zigbee reste arretee")
        #expect(!decouverte.demarree && !ecoutePont.enMarche && pont.pont.suspendu, "ni Bonjour du pont, ni le pont")
        #expect(registre.ouverts == 0 && z.registre.ouverts == 0, "aucun port rouvert")
    }

    // MARK: Premier lancement

    @MainActor
    @Test func laRepriseEstProposeeUneSeuleFoisEtSeulementSansImport() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        #expect(await b.assistant.preparerLancement(recuperation: .success(.rienAFaire)), "premier lancement : proposition")
        #expect(b.assistant.etape == .accueil && b.assistant.proposition)
        // « Plus tard » ferme sans rien faire, et la proposition ne revient pas.
        b.assistant.plusTard()
        #expect(!b.assistant.proposition)
        #expect(await b.assistant.preparerLancement(recuperation: .success(.rienAFaire)) == false)
        // Un import existe deja : jamais de proposition, drapeau ou non.
        let c = try Banc()
        defer { c.nettoyer() }
        try c.donnees.ecrire("imports.json", #"{"imports":[{"app":"thread","date":"2026-10-17T12:00:00Z","identifiant":"\#(UUID().uuidString)","versionApp":"1.4.0"}],"version":1}"#)
        #expect(await c.assistant.preparerLancement(recuperation: .success(.rienAFaire)) == false)
        // Un journal abime : pas de proposition non plus (l'entree des Reglages dit quoi faire).
        let d = try Banc()
        defer { d.nettoyer() }
        try d.donnees.ecrire("imports.json", "abime")
        #expect(await d.assistant.preparerLancement(recuperation: .success(.rienAFaire)) == false)
    }

    @MainActor
    @Test func uneRecuperationQuiLaisseDesElementsEstMontreeJamaisEnSilence() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        b.preferences.set(true, forKey: LancementReprise.clePropositionFaite) // pas de proposition : seul l'avis ouvre
        let laisses = ElementsLaisses(fichiers: ["surnoms.json"], reglages: [])
        #expect(await b.assistant.preparerLancement(recuperation: .success(.annuleeSauf(laisses))), "la fenetre s'ouvre")
        #expect(b.assistant.avis?.texte(locale: Self.fr).contains("surnoms.json") == true)
        // Une erreur de recuperation aussi.
        let c = try Banc()
        defer { c.nettoyer() }
        c.preferences.set(true, forKey: LancementReprise.clePropositionFaite)
        #expect(await c.assistant.preparerLancement(recuperation: .failure(.recuperationImpossible(code: "x 1"))))
        #expect(c.assistant.avis != nil)
        // Rien a dire : rien ne s'ouvre.
        let d = try Banc()
        defer { d.nettoyer() }
        d.preferences.set(true, forKey: LancementReprise.clePropositionFaite)
        #expect(await d.assistant.preparerLancement(recuperation: .success(.rienAFaire)) == false)
        #expect(d.assistant.avis == nil)
    }

    // MARK: Le resume deja vu ne revient pas (banc de la repetition)

    /// Apres un import et la relance : un autre modele, les memes preferences, l'etat du Mac d'alors. `lancer` y a ecrit le resume.
    @MainActor
    private func apresLaRelance(_ b: Banc) async throws -> AssistantReprise {
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "l'import a garde le resume pour la relance")
        return AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                lecteur: LecteurFactice(), preferences: b.preferences, arreterModules: {}, relancer: {},
                                choisirDossier: { nil }, attendre: { _ in })
    }

    @MainActor
    @Test func leResumeMontreEstEffaceDesQuilEstALEcranEtNeRevientPasAuLancementSuivant() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "pas encore montre : il reste")
        suivant.resumeMontre()
        guard case .termine = suivant.etape else { throw ApplicationImportTests.Echec("\(suivant.etape)") }
        #expect(DepotResume(preferences: b.preferences).lire() == nil, "montre : il est efface, la fenetre garde le sien")
        // L'app quitte avant que Djoko ait clique : le lancement suivant n'a plus de resume a montrer.
        let encore = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                      lecteur: LecteurFactice(), preferences: b.preferences, arreterModules: {}, relancer: {},
                                      choisirDossier: { nil }, attendre: { _ in })
        #expect(await encore.preparerLancement(recuperation: .success(.rienAFaire)) == false)
        #expect(encore.etape == .accueil)
    }

    @MainActor
    @Test func sansAffichageLeResumeResteEtLeLancementSuivantLeMontre() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        // L'app quitte avant d'avoir ouvert la fenetre : aucun `resumeMontre`.
        let encore = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: b.apps,
                                      lecteur: LecteurFactice(), preferences: b.preferences, arreterModules: {}, relancer: {},
                                      choisirDossier: { nil }, attendre: { _ in })
        #expect(await encore.preparerLancement(recuperation: .success(.rienAFaire)))
        guard case .termine = encore.etape else { throw ApplicationImportTests.Echec("\(encore.etape)") }
    }

    @MainActor
    @Test func apresTermineLaCleEstEffaceeEtLAssistantRouvreSurLAccueil() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        suivant.terminer()
        #expect(DepotResume(preferences: b.preferences).lire() == nil)
        #expect(suivant.etape == .accueil)
        suivant.rouvrir()
        #expect(suivant.etape == .accueil, "le clic sur « Reprendre des donnees… » ouvre l'accueil")
    }

    @MainActor
    @Test func fermerLaFenetreParLaCroixEffaceLeResumeEtRouvreSurLAccueil() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        await suivant.fenetreFermee()
        #expect(DepotResume(preferences: b.preferences).lire() == nil)
        #expect(suivant.etape == .accueil)
        suivant.rouvrir()
        #expect(suivant.etape == .accueil)
    }

    @MainActor
    @Test func siLaRelanceAEchoueLeResumeNEstPasEffaceParLAffichage() async throws {
        let b = try Banc(relanceEchoue: true)
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        #expect(b.assistant.relanceEchouee)
        b.assistant.resumeMontre()
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "l'app ne tourne pas encore sur les donnees reprises : il reste")
    }

    @MainActor
    @Test func ouvrirLaFenetreDuResumeEffaceLaCleEtLaFermerRouvreSurLAccueil() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        let controleur = ControleurReprise(assistant: suivant)
        controleur.montrer()
        defer { controleur.fermer() }
        #expect(DepotResume(preferences: b.preferences).lire() == nil, "la fenetre montre le resume : la cle s'efface")
        controleur.fermer()
        try await Task.sleep(for: .milliseconds(200))
        #expect(suivant.etape == .accueil)
        controleur.montrer()
        #expect(suivant.etape == .accueil, "le second clic ouvre l'accueil")
    }

    @MainActor
    @Test func leResumeDejaVuNeRevientPasMemeSiLaFenetreResteOuverteDerriere() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        let controleur = ControleurReprise(assistant: suivant)
        defer { controleur.fermer() }
        controleur.montrer()
        guard case .termine = suivant.etape else { throw ApplicationImportTests.Echec("\(suivant.etape)") }
        // La fenetre passe derriere, sans Termine ni croix : le clic sur « Reprendre des donnees… » ouvre l'accueil.
        controleur.montrer()
        #expect(suivant.etape == .accueil, "le resume a deja ete vu : le second montrer() ouvre l'accueil")
        #expect(DepotResume(preferences: b.preferences).lire() == nil)
        #expect(!suivant.proposition)
    }

    @MainActor
    @Test func apresUneRelanceEchoueeLeSecondMontrerGardeLeResume() async throws {
        let b = try Banc(relanceEchoue: true)
        defer { b.nettoyer() }
        await b.assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        await b.assistant.lancer()
        #expect(b.assistant.relanceEchouee)
        let controleur = ControleurReprise(assistant: b.assistant)
        defer { controleur.fermer() }
        controleur.montrer()
        controleur.montrer()
        guard case .termine = b.assistant.etape else { throw ApplicationImportTests.Echec("\(b.assistant.etape)") }
        #expect(DepotResume(preferences: b.preferences).lire() != nil, "l'app ne tourne pas encore sur les donnees reprises")
    }

    @MainActor
    @Test func lePremierMontrerDuLancementGardeSonResume() async throws {
        let b = try Banc()
        defer { b.nettoyer() }
        let suivant = try await apresLaRelance(b)
        #expect(await suivant.preparerLancement(recuperation: .success(.rienAFaire)))
        suivant.rouvrir() // avant l'affichage : le resume est encore a montrer
        guard case .termine = suivant.etape else { throw ApplicationImportTests.Echec("\(suivant.etape)") }
    }
}
