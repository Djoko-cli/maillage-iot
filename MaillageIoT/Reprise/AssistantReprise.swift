import AppKit
import MaillageCoeur
import Observation

// Phase 4, tache 7 : le modele de l'assistant de reprise (la fenetre de `Vues/Reprise` n'a pas de logique).
//
// Le parcours : choisir le dossier d'export -> validation (`preparer`, lecture seule) -> confirmation (l'ancienne app de cet
// export ne doit plus tourner) -> reprise (modules arretes, `appliquer`, hors du fil principal) -> relance de l'app, qui montre le
// resume et la liste « A refaire » avec l'etat reel du Mac a ce moment-la (spec 4.3, 4.4, 6.8).
//
// Garde-fous :
// - aucun import sans validation reussie : `lancer` n'agit que sur une confirmation, avec la preparation qui l'a produite ;
// - un seul import a la fois : `occupe` est pose avant le premier `await` (deux appels ne se chevauchent pas, le bouton est
//   desactive), et l'app ne cree qu'un seul `ApplicationImport` ;
// - les modules sont arretes avant `appliquer` et jamais relances a la main : apres un import (reussi ou en echec), l'app se
//   relance ; fermer la fenetre d'un assistant dont les modules sont arretes la relance aussi.

/// Ce que l'assistant demande a `ApplicationImport` (une couture : les tests y observent l'ordre des appels).
protocol ImporteurExport: Sendable {
    func preparer(export: URL) async throws -> IssuePreparation
    func appliquer(_ p: PreparationImport) async throws -> ResultatApplication
}

extension ApplicationImport: ImporteurExport {}

/// L'ancienne app de l'export, vue par l'assistant.
enum SuiviAncienneApp: Equatable, Sendable {
    case absente
    /// Elle tourne : l'import ne demarre pas (une sonde USB ne peut avoir qu'un seul maitre).
    case tourne
    /// `terminate()` envoye, l'app n'est pas encore partie.
    case demandeEnvoyee
    /// Le bac a sable a refuse `terminate()`, ou l'app tourne encore apres l'attente : l'utilisateur la quitte lui-meme.
    case aQuitterSoiMeme
}

@MainActor
@Observable
final class AssistantReprise {
    enum Etape: Equatable {
        /// Le point de depart : choisir le dossier d'export (avec la proposition du premier lancement, si `proposition`).
        case accueil
        case validation
        /// L'export est refuse (rien n'est importe) : la cause.
        case refuse(CauseRefus)
        /// La validation n'a pas pu se faire (erreur du systeme, etc.) : rien n'a ete modifie.
        case impossible(ErreurApplication)
        /// L'export est valide : le resume de son contenu, en attente du feu vert.
        case confirmation(ResumeExport)
        /// L'export est intact mais deja repris.
        case dejaRepris(ImportRepris, ResumeExport)
        case enCours
        /// La reprise a echoue (les modules sont arretes : l'app se relance).
        case echec(ErreurApplication)
        /// La reprise est faite : l'app se relance.
        case relance
        /// Le resume final et ce qui reste a faire.
        case termine(ResumeFinal, [TacheARefaire])
    }

    private(set) var etape: Etape = .accueil
    private(set) var ancienneApp: SuiviAncienneApp = .absente
    /// Ce que la recuperation du lancement a a dire (une reprise interrompue defaite, ou impossible a defaire).
    private(set) var avis: AvisLancement?
    /// La proposition du premier lancement est affichee (« Plus tard » existe).
    private(set) var proposition = false
    /// Les modules ont ete arretes pour l'import : l'app doit se relancer.
    private(set) var modulesArretes = false
    /// La relance n'a pas abouti : l'utilisateur quitte et rouvre l'app lui-meme.
    private(set) var relanceEchouee = false
    /// Une validation ou un import est en cours : rien d'autre ne demarre.
    private(set) var occupe = false

    @ObservationIgnored private let importeur: any ImporteurExport
    @ObservationIgnored private let dossierDonnees: URL
    @ObservationIgnored private let applications: any ApplicationsLancees
    @ObservationIgnored private let lecteur: any LecteurEtatSysteme
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let arreterModules: @MainActor () -> Void
    @ObservationIgnored private let relancer: @MainActor () async throws -> Void
    @ObservationIgnored private let selecteur: @MainActor () -> URL?
    @ObservationIgnored private let attendre: @Sendable (Duration) async -> Void
    @ObservationIgnored private let quitter: @MainActor () -> Void
    /// Le dossier d'export choisi, et sa preparation (le contenu converti : jusqu'a 100 Mo, lache des que possible).
    @ObservationIgnored private var dossierChoisi: URL?
    @ObservationIgnored private var preparation: PreparationImport?

    /// Delai avant la relance, pour que l'ecran « Relance… » se voie.
    nonisolated static let delaiAvantRelance: Duration = .seconds(2)
    /// Combien de fois (et a quel rythme) on regarde si l'ancienne app est partie apres `terminate()`.
    nonisolated static let verificationsApresQuitter = 10
    nonisolated static let pasVerification: Duration = .milliseconds(500)
    /// Rythme de `surveillerAncienneApp`.
    nonisolated static let pasSurveillance: Duration = .seconds(1)
    /// Rythme de la relecture de « A refaire » pendant que le resume est montre.
    @ObservationIgnored private let pasRelecture: Duration

    init(importeur: any ImporteurExport, dossierDonnees: URL,
         applications: any ApplicationsLancees = ApplicationsLanceesSysteme(), lecteur: any LecteurEtatSysteme,
         preferences: UserDefaults = .standard, arreterModules: @escaping @MainActor () -> Void,
         relancer: @escaping @MainActor () async throws -> Void = { try await LangueApp.relancer() },
         choisirDossier: @escaping @MainActor () -> URL? = { PanneauExport.choisir() },
         attendre: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         quitter: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
         pasRelecture: Duration = .seconds(2)) {
        self.pasRelecture = pasRelecture
        self.importeur = importeur
        self.dossierDonnees = dossierDonnees
        self.applications = applications
        self.lecteur = lecteur
        self.preferences = preferences
        self.arreterModules = arreterModules
        self.relancer = relancer
        selecteur = choisirDossier
        self.attendre = attendre
        self.quitter = quitter
    }

    // MARK: Etat derive

    /// L'app de l'export en cours de confirmation.
    private var appDeLExport: ContratExport.AppSource? {
        if case .confirmation(let resume) = etape { return resume.app }
        return nil
    }

    /// « Reprendre » est possible : un export valide, l'ancienne app arretee, rien d'autre en cours.
    var peutLancer: Bool {
        if case .confirmation = etape, preparation != nil, ancienneApp == .absente, !occupe { return true }
        return false
    }

    /// Le journal des imports est abime : « Repartir d'un journal vide » le met de cote (jamais supprime).
    var peutRepartirDUnJournalVide: Bool {
        if case .refuse(.journalDesImportsIllisible) = etape, dossierChoisi != nil, !occupe { return true }
        return false
    }

    /// La preparation de l'export (jusqu'a 100 Mo) est gardee en memoire.
    var preparationGardee: Bool { preparation != nil }

    /// La croix de la fenetre ne ferme rien tant que les modules sont arretes : l'app ne tourne jamais sans eux, en silence.
    /// Apres un echec, la croix relance l'app ; si la relance n'aboutit pas, la fenetre reste avec « Quitter Maillage IoT » et le
    /// resume (qui reste aussi garde pour le lancement suivant).
    var fermetureRefusee: Bool { modulesArretes }

    // MARK: Parcours

    /// Le panneau d'ouverture, puis la validation du dossier choisi. Annule : rien ne change.
    func choisirDossier() async {
        guard !occupe, let url = selecteur() else { return }
        await valider(url)
    }

    /// Valide l'export du dossier (lecture seule). Aucun import ne part d'ailleurs que d'ici : `lancer` ne reprend que la
    /// preparation qu'une validation reussie a produite.
    func valider(_ dossier: URL) async {
        guard !occupe else { return }
        occupe = true
        defer { occupe = false }
        etape = .validation
        preparation = nil
        ancienneApp = .absente
        dossierChoisi = dossier
        do {
            switch try await importeur.preparer(export: dossier) {
            case .aReprendre(let p):
                preparation = p
                etape = .confirmation(p.resume)
                verifierAncienneApp()
            case .dejaRepris(let reprise, let resume):
                etape = .dejaRepris(reprise, resume)
            }
        } catch let e as ErreurApplication {
            if case .refuse(let cause) = e { etape = .refuse(cause) } else { etape = .impossible(e) }
        } catch {
            etape = .impossible(.echec(.preparation, retablie: true, code: Self.code(error)))
        }
    }

    /// Met `imports.json` de cote (renomme, jamais supprime) puis valide de nouveau le meme dossier.
    func repartirDUnJournalVide() async {
        guard peutRepartirDUnJournalVide, let dossier = dossierChoisi else { return }
        do {
            try JournalImports.mettreDeCoteImportsAbime(dans: dossierDonnees)
        } catch {
            etape = .impossible(.echec(.preparation, retablie: true, code: Self.code(error)))
            return
        }
        await valider(dossier)
    }

    /// La fenetre se rouvre : un assistant au repos (refus, erreur, export en attente de confirmation) repart du choix du dossier ;
    /// une reprise en cours, un echec (l'app doit se relancer) ou le resume restent comme ils sont.
    func rouvrir() {
        switch etape {
        case .refuse, .impossible, .dejaRepris, .confirmation: recommencer()
        default: break
        }
    }

    /// Revient au choix du dossier.
    func recommencer() {
        guard !occupe else { return }
        preparation = nil
        dossierChoisi = nil
        ancienneApp = .absente
        etape = .accueil
    }

    // MARK: L'ancienne app

    /// Regarde si l'ancienne app de cet export tourne (par son identifiant de bundle).
    func verifierAncienneApp() {
        guard let app = appDeLExport else { return }
        if applications.instances(de: app.identifiantBundle) == 0 {
            ancienneApp = .absente
        } else if ancienneApp != .aQuitterSoiMeme {
            ancienneApp = ancienneApp == .demandeEnvoyee ? .demandeEnvoyee : .tourne
        }
    }

    /// « Quitter Maillage Thread » : `terminate()`, jamais `forceTerminate()`. Refuse par le bac a sable, ou l'app tourne encore
    /// apres quelques secondes : on demande a l'utilisateur de la quitter lui-meme, et `verifierAncienneApp` reverifie.
    func quitterAncienneApp() async {
        guard let app = appDeLExport, !occupe else { return }
        guard applications.demanderDeQuitter(app.identifiantBundle) else {
            ancienneApp = .aQuitterSoiMeme
            return
        }
        ancienneApp = .demandeEnvoyee
        for _ in 0..<Self.verificationsApresQuitter {
            await attendre(Self.pasVerification)
            if applications.instances(de: app.identifiantBundle) == 0 {
                ancienneApp = .absente
                return
            }
        }
        ancienneApp = .aQuitterSoiMeme
    }

    /// Reverifie tant que l'ancienne app tourne (l'utilisateur peut la quitter lui-meme) ; s'arrete avec la tache (la vue la
    /// lance). Une vraie attente, pas `attendre` : un `attendre` instantane (tests) en ferait une boucle qui monopolise le fil.
    func surveillerAncienneApp() async {
        while !Task.isCancelled, case .confirmation = etape, ancienneApp != .absente {
            try? await Task.sleep(for: Self.pasSurveillance)
            verifierAncienneApp()
        }
    }

    // MARK: La reprise

    /// Lance la reprise : modules arretes, `appliquer`, puis la relance de l'app. Rien si l'export n'est pas valide, si l'ancienne
    /// app tourne, ou si un import est deja en cours.
    func lancer() async {
        guard case .confirmation(let resume) = etape, let prep = preparation, !occupe else { return }
        verifierAncienneApp()
        guard ancienneApp == .absente else { return }
        occupe = true
        etape = .enCours
        arreterModules()
        modulesArretes = true
        do {
            let resultat = try await importeur.appliquer(prep)
            preparation = nil
            let final = ResumeFinal(resultat: resultat, resume: resume)
            DepotResume(preferences: preferences).ecrire(final)
            etape = .relance
            occupe = false
            await relancerApp(apres: final)
        } catch let e as ErreurApplication {
            preparation = nil
            etape = .echec(e)
            occupe = false
        } catch {
            preparation = nil
            etape = .echec(.echec(.remplacement, retablie: false, code: Self.code(error)))
            occupe = false
        }
    }

    /// L'app se relance d'elle-meme (ses modules lisent leurs fichiers au lancement). Si la relance n'aboutit pas, le resume est
    /// montre ici, avec « Quitter Maillage IoT » ; il reste aussi garde pour le lancement suivant.
    private func relancerApp(apres final: ResumeFinal) async {
        await attendre(Self.delaiAvantRelance)
        do {
            try await relancer()
        } catch {
            relanceEchouee = true
            etape = .termine(final, ListeARefaire.pour(final.app, etat: await lecteur.lire()))
        }
    }

    /// Apres un echec, les modules sont arretes : l'app se relance.
    func relancerApresEchec() async {
        guard case .echec = etape, !relanceEchouee else { return }
        do { try await relancer() } catch { relanceEchouee = true }
    }

    /// « Quitter Maillage IoT » : quand la relance n'a pas abouti.
    func quitterMaillageIoT() { quitter() }

    /// La fenetre se ferme : apres un echec, l'app se relance ; sur le resume, il est acquitte (sauf si la relance n'a pas
    /// abouti : le resume reste, l'app ne tourne pas encore sur les donnees reprises) ; sur la confirmation (ou un refus), la
    /// preparation est lachee.
    func fenetreFermee() async {
        switch etape {
        case .echec: await relancerApresEchec()
        case .termine: if !relanceEchouee { terminer() }
        case .refuse, .impossible, .dejaRepris, .confirmation: recommencer()
        default: break
        }
    }

    /// Le resume est lu : il ne reviendra pas.
    func terminer() {
        DepotResume(preferences: preferences).effacer()
        proposition = false
        if case .termine = etape { etape = .accueil }
    }

    // MARK: Relecture de « A refaire »

    /// Relit l'etat reel du Mac et refait la liste « A refaire » du resume montre : une ligne qui n'est plus vraie disparait, une
    /// ligne vraie apparait (la reponse de macOS aux notifications, a la cle du pont, l'issue de Bonjour viennent apres le
    /// lancement). Sans effet hors du resume. Le resume lui-meme ne change pas.
    func relireARefaire() async {
        guard case .termine(let final, let avant) = etape else { return }
        let taches = ListeARefaire.pour(final.app, etat: await lecteur.lire())
        // L'etat a pu changer pendant la lecture (le resume est acquitte, ou remplace) : on ne l'ecrase pas.
        guard case .termine(let encore, let courantes) = etape, encore == final, courantes == avant, taches != avant else { return }
        etape = .termine(final, taches)
    }

    /// Relit « A refaire » tant que le resume est montre (la fenetre la lance avec sa tache, et la relit aussi au retour de l'app
    /// au premier plan). Une vraie attente, pas `attendre`.
    func surveillerARefaire() async {
        while !Task.isCancelled, case .termine = etape {
            try? await Task.sleep(for: pasRelecture)
            guard !Task.isCancelled else { return }
            await relireARefaire()
        }
    }

    // MARK: Lancement

    /// Au lancement : ce qu'il y a a montrer. Dans l'ordre : le resume d'une reprise qui vient d'avoir lieu (avec l'etat reel du
    /// Mac a ce moment-la), l'avis de la recuperation (jamais en silence), la proposition du premier lancement. Rend vrai si la
    /// fenetre doit s'ouvrir.
    func preparerLancement(recuperation: Result<IssueRecuperation, ErreurApplication>) async -> Bool {
        avis = AvisLancement(recuperation)
        var montrer = avis != nil
        if let final = DepotResume(preferences: preferences).lire() {
            etape = .termine(final, ListeARefaire.pour(final.app, etat: await lecteur.lire()))
            return true
        }
        if LancementReprise.doitProposer(preferences: preferences, dossierDonnees: dossierDonnees) {
            LancementReprise.noterProposition(preferences: preferences)
            proposition = true
            montrer = true
        }
        return montrer
    }

    /// « Plus tard » : la proposition se ferme sans rien faire.
    func plusTard() { proposition = false }

    /// Le texte du systeme pour une erreur inattendue : domaine et code, jamais un chemin.
    private static func code(_ erreur: any Error) -> String {
        let e = erreur as NSError
        return "\(e.domain) \(e.code)"
    }
}

/// Le panneau d'ouverture (NSOpenPanel) qui choisit le dossier d'export. L'acces au dossier est donne par le panneau (droit
/// `user-selected`) pour la duree du processus.
@MainActor
enum PanneauExport {
    static func choisir() -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.canCreateDirectories = false
        p.prompt = String(localized: "Choisir")
        p.message = String(localized: "Choisir le dossier écrit par « Exporter pour Maillage IoT… », dans Maillage Thread ou Maillage Zigbee.")
        return p.runModal() == .OK ? p.url : nil
    }
}
