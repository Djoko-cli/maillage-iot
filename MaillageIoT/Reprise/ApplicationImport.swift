import Foundation
import MaillageCoeur

// Phase 4, tache 6 : l'application d'un import, tout ou rien.
//
// Entree : un dossier d'export. `ApplicationImport` le valide (`ValidationExport`), le convertit en plan (`ConversionThread`
// / `ConversionZigbee`, qui fusionnent avec ce que Maillage IoT a deja : l'existant l'emporte), puis applique le plan d'un
// coup, ou pas du tout. Rien n'est ecrit tant que l'utilisateur n'a pas confirme : `preparer` ne fait que lire, `appliquer`
// ecrit.
//
// Isolation : `ApplicationImport` est un `actor` (jamais le fil principal). La conversion et l'application lisent et
// ecrivent des dizaines de Mo (l'historique de Zigbee peut peser 80 a 100 Mo a 90 jours) : l'interface les appelle avec
// `await`, ses types (`PreparationImport`, `ResultatApplication`...) sont `Sendable`. Les deux appels sont serialises par
// l'acteur : deux applications ne se melangent jamais dans un meme processus.
//
// L'ALGORITHME D'APPLICATION (`appliquerPlan`), dans l'ordre. Tout ce qui ecrit passe par `OperationsFichiers` (une
// couture : les tests y font echouer chaque operation). Le dossier de travail `.reprise-en-cours` est DANS le dossier de
// donnees de l'app (meme volume : un deplacement est un simple renommage, atomique) :
//   0. verifications sans ecriture : l'export est intact et identique a celui du plan (manifeste et reglages a l'identique,
//      empreintes relues) ; son identifiant n'est pas deja dans `imports.json` ; le dossier de donnees et les cles de
//      preferences sont ceux que le plan a lus (empreinte de chaque fichier). Sinon le plan est recalcule (jusqu'a 3 fois).
//   1. le dossier de travail est cree (avec la racine, en un seul appel : jamais une racine vide sans dossier de travail) ;
//      `journal.json` y est ecrit (atomiquement) AVANT tout deplacement : il dit quels fichiers sont remplaces, lesquels sont
//      crees, quels dossiers sont crees, et l'empreinte SHA-256 de chaque fichier que l'import va mettre en place.
//   2. dossier d'attente (`attente/`) : chaque fichier du plan y est ecrit (contenu converti) ou copie (fichier de l'export),
//      puis son empreinte est verifiee ; le nouvel `imports.json` (l'ancien plus une ligne) y est ecrit aussi.
//   3. remplacement : pour chaque fichier, l'original est DEPLACE dans `sauvegarde/` (empreinte comparee a celle du plan : un
//      fichier modifie entretemps arrete tout), puis le fichier d'attente est deplace a sa place.
//   4. preferences : les cles du plan sont ecrites (toutes etaient absentes ; sinon le plan est recalcule). Seulement ici,
//      une fois les fichiers en place. Le journal, passe a la phase `reglages`, dit d'abord pour chaque cle la valeur qui va
//      etre ecrite et l'etat d'avant.
//   5. VALIDATION : `imports.json` est remplace de la meme facon (original en sauvegarde, nouveau fichier deplace d'attente :
//      un renommage, jamais une ecriture en place). C'est l'instant ou la reprise existe.
//   6. nettoyage du dossier de travail (sans effet sur le resultat : une erreur ici ne defait rien).
//
// RETOUR EN ARRIERE. Toute erreur avant l'instant 5 defait ce qui a ete fait : les reglages ecrits sont retires (ou remis),
// les fichiers de `sauvegarde/` retournent a leur place, les fichiers crees sont retires, les dossiers crees aussi s'ils sont
// vides. Le dossier de l'app est alors octet pour octet ce qu'il etait.
//
// Il ne defait que ce que l'import a ECRIT, et seulement tant que cela n'a pas bouge : un fichier n'est retire (ou remplace
// par son original) que si son contenu a encore l'empreinte que l'import a mise en place ; un reglage n'est retire (ou remis)
// que s'il a encore la valeur que l'import a ecrite ; un reglage que l'import n'a pas ecrit n'est jamais touche. Si l'app a
// ecrit depuis (apres un arret, puis un usage normal), son travail est LAISSE en place et cite (`ElementsLaisses`) ; l'original
// d'un fichier laisse est garde a part (`conserve`), jamais efface avec le dossier de travail. Si le retour en arriere echoue
// lui-meme (ou
// si l'app s'arrete en plein milieu), `recuperer()` le refait au lancement suivant, d'apres `journal.json` : decision
// ANNULER, sauf si `imports.json` contient deja l'identifiant de cet import (la validation a eu lieu : on termine le
// nettoyage). On n'acheve jamais une reprise a moitie : annuler est toujours possible (les originaux sont en sauvegarde),
// et l'utilisateur relance l'import, qui est idempotent.
//
// Jamais d'ecrasement d'un format inconnu ou plus recent (`FichiersGardes`) : la conversion ne fusionne que ce qu'elle sait
// lire et laisse le reste intact ; l'application ne remplace un fichier que s'il est dans l'etat que le plan a lu.

// MARK: Coutures

/// Les operations qui ECRIVENT dans le systeme de fichiers pendant une application. Les lectures (existence, empreintes)
/// ne passent pas par la : elles ne changent rien. Les tests substituent une version qui echoue a l'operation voulue.
protocol OperationsFichiers: Sendable {
    func creerDossier(_ url: URL) throws
    /// Ecrit `donnees` dans `url` ; `atomique` : fichier temporaire puis renommage (jamais un fichier a moitie ecrit).
    func ecrire(_ donnees: Data, vers url: URL, atomique: Bool) throws
    func copier(de source: URL, vers cible: URL) throws
    /// Renomme (meme volume) ; la cible ne doit pas exister.
    func deplacer(de source: URL, vers cible: URL) throws
    func supprimer(_ url: URL) throws
}

struct OperationsFichiersReelles: OperationsFichiers {
    func creerDossier(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func ecrire(_ donnees: Data, vers url: URL, atomique: Bool) throws {
        try donnees.write(to: url, options: atomique ? [.atomic] : [])
    }

    func copier(de source: URL, vers cible: URL) throws {
        try FileManager.default.copyItem(at: source, to: cible)
    }

    func deplacer(de source: URL, vers cible: URL) throws {
        try FileManager.default.moveItem(at: source, to: cible)
    }

    func supprimer(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// Les preferences de Maillage IoT : ce que l'application lit (les cles deja posees) et ecrit (les cles du plan, une fois les
/// fichiers en place). Une couture, pour que les tests n'aient jamais les vraies preferences.
protocol PreferencesReprise: Sendable {
    /// Les cles du domaine persistant de l'app (jamais les valeurs globales du Mac).
    func clesPresentes() -> Set<String>
    /// Les valeurs actuelles de ces cles dans le domaine de l'app (une cle absente, ou d'un type que l'export ne connait pas,
    /// n'est pas dans le resultat).
    func valeurs(pour cles: [String]) -> [String: ContratExport.Valeur]
    func ecrire(_ valeurs: [String: ContratExport.Valeur]) throws
    func retirer(_ cles: [String])
}

/// Les preferences d'un domaine de `UserDefaults` : `suite` nil = les preferences de l'app (`.standard`), `domaine` = le
/// nom du domaine persistant (l'identifiant de l'app ; celui de la suite pour un essai).
struct PreferencesUserDefaults: PreferencesReprise {
    let suite: String?
    let domaine: String

    /// Le domaine de l'app publiee, quand le bundle n'a pas d'identifiant (jamais en pratique).
    static let domaineParDefaut = "fr.djoko.maillage.iot"

    /// Les vraies preferences de l'app qui tourne : son domaine est son identifiant (`Bundle.main`), donc celui de l'app de
    /// repetition dans l'app de repetition, jamais celui de l'app publiee.
    static var app: PreferencesUserDefaults { app(bundle: .main) }

    static func app(bundle: Bundle) -> PreferencesUserDefaults { pourApp(identifiant: bundle.bundleIdentifier) }

    static func pourApp(identifiant: String?) -> PreferencesUserDefaults {
        PreferencesUserDefaults(suite: nil, domaine: identifiant ?? domaineParDefaut)
    }

    private func defauts() -> UserDefaults {
        suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    func clesPresentes() -> Set<String> {
        Set(defauts().persistentDomain(forName: domaine)?.keys.map { $0 } ?? [])
    }

    func valeurs(pour cles: [String]) -> [String: ContratExport.Valeur] {
        let presentes = defauts().persistentDomain(forName: domaine) ?? [:]
        var r: [String: ContratExport.Valeur] = [:]
        for cle in cles { if let objet = presentes[cle], let v = Self.valeur(objet) { r[cle] = v } }
        return r
    }

    /// La valeur typee d'un objet de preferences (un booleen, un entier et un decimal ne se confondent pas).
    private static func valeur(_ objet: Any) -> ContratExport.Valeur? {
        switch objet {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return ["d", "f"].contains(String(cString: n.objCType)) ? .decimal(n.doubleValue) : .entier(n.intValue)
        case let t as String: return .texte(t)
        case let d as Data: return .donnees(d)
        case let l as [String]: return .listeTextes(l)
        case let l as [Int]: return .listeEntiers(l)
        default: return nil
        }
    }

    func ecrire(_ valeurs: [String: ContratExport.Valeur]) throws {
        let d = defauts()
        for (cle, valeur) in valeurs.sorted(by: { $0.key < $1.key }) {
            switch valeur {
            case .bool(let v): d.set(v, forKey: cle)
            case .entier(let v): d.set(v, forKey: cle)
            case .decimal(let v): d.set(v, forKey: cle)
            case .texte(let v): d.set(v, forKey: cle)
            case .donnees(let v): d.set(v, forKey: cle)
            case .listeTextes(let v): d.set(v, forKey: cle)
            case .listeEntiers(let v): d.set(v, forKey: cle)
            }
        }
    }

    func retirer(_ cles: [String]) {
        let d = defauts()
        for cle in cles { d.removeObject(forKey: cle) }
    }
}

// MARK: Etat du dossier de donnees

/// Taille et SHA-256 d'un fichier du dossier de donnees ; un lien symbolique : taille -1 et sa destination.
struct EmpreinteFichier: Equatable, Sendable {
    let taille: Int64
    let sha256: String
}

/// Ce que le plan a lu : chaque fichier du dossier de donnees (hors dossier de travail) et les cles de preferences deja
/// posees. L'application compare cet etat a l'etat du moment ; s'il a bouge, le plan est recalcule (le plan fusionne avec
/// l'existant : un existant qui change change le plan).
struct EtatDonnees: Equatable, Sendable {
    let fichiers: [String: EmpreinteFichier]
    let reglagesPresents: Set<String>

    static func lire(racine: URL, reglagesPresents: Set<String>) throws -> EtatDonnees {
        var fichiers: [String: EmpreinteFichier] = [:]
        if existe(racine) { try parcourir(racine, prefixe: "", dans: &fichiers) }
        return EtatDonnees(fichiers: fichiers, reglagesPresents: reglagesPresents)
    }

    static func empreinte(_ url: URL) throws -> EmpreinteFichier {
        let fm = FileManager.default
        if (try fm.attributesOfItem(atPath: url.path))[.type] as? FileAttributeType == .typeSymbolicLink {
            return EmpreinteFichier(taille: -1, sha256: try fm.destinationOfSymbolicLink(atPath: url.path))
        }
        let e = try ContratExport.empreinte(fichier: url)
        return EmpreinteFichier(taille: e.taille, sha256: e.sha256)
    }

    /// Existe-t-il quelque chose a ce chemin (un lien casse compte) ?
    static func existe(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func parcourir(_ dossier: URL, prefixe: String, dans r: inout [String: EmpreinteFichier]) throws {
        let fm = FileManager.default
        for nom in try fm.contentsOfDirectory(atPath: dossier.path).sorted() {
            if prefixe.isEmpty, nom == ApplicationImport.nomTravail { continue }
            if nom == ".DS_Store" { continue }
            let url = dossier.appendingPathComponent(nom)
            let chemin = prefixe + nom
            switch (try fm.attributesOfItem(atPath: url.path))[.type] as? FileAttributeType {
            case .typeDirectory: try parcourir(url, prefixe: chemin + "/", dans: &r)
            case .typeRegular, .typeSymbolicLink: r[chemin] = try empreinte(url)
            default: continue
            }
        }
    }
}

// MARK: Types de l'API

/// Un import prepare : tout ce que l'ecran de confirmation montre (`resume`, `plan.nonPris`) et ce que l'application
/// applique. Rien n'est encore ecrit.
struct PreparationImport: Sendable {
    let dossierExport: URL
    let manifeste: ContratExport.Manifeste
    let reglagesExport: ContratExport.Reglages
    let resume: ResumeExport
    let plan: PlanReprise
    /// Ce que le plan a lu (dossier de donnees, cles de preferences).
    let etat: EtatDonnees
}

enum IssuePreparation: Sendable {
    case aReprendre(PreparationImport)
    /// L'export est intact mais deja repris (`imports.json`) : rien a faire, rien n'est ecrit.
    case dejaRepris(ImportRepris, ResumeExport)
}

struct ResultatApplication: Equatable, Sendable {
    /// La ligne ajoutee a `imports.json`.
    let repris: ImportRepris
    /// Les chemins ecrits dans le dossier de donnees (sans `imports.json`).
    let fichiersEcrits: [String]
    /// Les cles de preferences ecrites.
    let reglagesEcrits: [String]
    /// Ce qui n'est pas repris, avec la raison (le resume de fin).
    let nonPris: [ElementNonPris]
    /// Vrai si l'etat de l'app a change depuis `preparer` : le plan a ete refait avant d'etre applique.
    let planRecalcule: Bool
}

enum IssueReprise: Sendable {
    case repris(ResultatApplication)
    case dejaRepris(ImportRepris, ResumeExport)
}

/// L'etape ou une application a echoue (pour le message : on ne dit jamais un chemin).
enum EtapeApplication: String, Equatable, Sendable {
    /// Dossier de travail, journal, ecriture ou copie dans l'attente, empreintes.
    case preparation
    /// Deplacement des originaux et des nouveaux fichiers.
    case remplacement
    case reglages
    /// Remplacement d'`imports.json` (l'instant de la validation).
    case validation
}

enum ErreurApplication: Error, Equatable, Sendable {
    /// L'export est refuse (`ValidationExport`) : rien n'est importe.
    case refuse(CauseRefus)
    /// L'export a change depuis `preparer` (ou n'est plus lisible) : le preparer de nouveau.
    case exportModifie
    /// Cet export est deja repris (un autre appel l'a fait entretemps).
    case dejaRepris(ImportRepris)
    /// L'etat de l'app a change a chaque essai (3) : rien n'a ete modifie ; reessayer plus tard.
    case etatInstable
    /// Une operation a echoue. `retablie` : le dossier de l'app est revenu a l'identique ; sinon `recuperer()` le fera au
    /// prochain lancement. `code` : domaine et code de l'erreur du systeme, jamais un chemin.
    case echec(EtapeApplication, retablie: Bool, code: String)
    /// Une operation a echoue et le retour en arriere a tout defait SAUF ce que l'app avait ecrit entretemps : cela reste en
    /// place (voir `ElementsLaisses`).
    case echecAvecReste(EtapeApplication, ElementsLaisses, code: String)
    /// Une application interrompue n'a pas pu etre defaite (ni terminee) : rien n'est efface, a refaire.
    case recuperationImpossible(code: String)
}

/// Ce qu'un retour en arriere a laisse en place parce que l'app l'avait ecrit depuis l'import (un fichier dont le contenu n'a
/// plus l'empreinte que l'import avait mise, un reglage qui n'a plus la valeur ecrite par l'import). Pour un fichier qui
/// remplacait un original, l'original est garde dans `.reprise-conservee/<identifiant de l'import>/<chemin>`.
struct ElementsLaisses: Equatable, Sendable {
    var fichiers: [String] = []
    var reglages: [String] = []

    var estVide: Bool { fichiers.isEmpty && reglages.isEmpty }
}

enum IssueRecuperation: Equatable, Sendable {
    case rienAFaire
    /// Un dossier de travail sans journal (arret avant tout deplacement) : supprime.
    case nettoyee
    /// Une application interrompue avant la validation : defaite, le dossier est comme avant.
    case annulee
    /// Idem, sauf ce que l'app avait ecrit depuis l'arret : laisse en place, cite.
    case annuleeSauf(ElementsLaisses)
    /// Une application interrompue apres la validation : seul le nettoyage restait.
    case terminee
}

/// Un reglage ecrit par l'import : la valeur ecrite (le retour en arriere ne le touche que s'il l'a encore) et l'etat d'avant
/// (nil : absent).
struct ReglageJournal: Codable, Equatable, Sendable {
    var cle: String
    var ecrite: ContratExport.Valeur
    var avant: ContratExport.Valeur?
}

/// Ce que `journal.json` du dossier de travail garde pour retablir l'etat d'avant.
struct JournalApplication: Codable, Equatable, Sendable {
    static let versionCourante = 2
    var version = JournalApplication.versionCourante
    var identifiant: UUID
    /// Les fichiers qui existaient et sont remplaces (l'original va dans `sauvegarde/`), `imports.json` en dernier.
    var remplaces: [String]
    /// Les fichiers qui n'existaient pas.
    var crees: [String]
    /// Les dossiers qui n'existaient pas, du plus haut au plus bas.
    var dossiersCrees: [String]
    var racineCreee: Bool
    /// Pour chaque fichier que l'import met en place (`imports.json` compris), l'empreinte SHA-256 de son contenu : le
    /// retour en arriere ne retire ou ne remplace que ce qui l'a encore.
    var empreintes: [String: String]
    /// Les reglages ecrits, renseignes en passant a la phase `reglages` (avant la premiere ecriture).
    var reglagesEcrits: [ReglageJournal] = []
    var phase: Phase = .preparation

    /// Jusqu'ou l'application est allee : tant que le remplacement n'a pas commence, rien de ce qui est dans le dossier
    /// de donnees n'est le travail de l'application (un fichier "cree" qui s'y trouve n'est pas le sien) ; tant que la phase
    /// `reglages` n'a pas commence, aucun reglage n'est le sien.
    enum Phase: String, Codable, Sendable {
        case preparation
        case remplacement
        case reglages
    }

    /// Tous les chemins que le journal nomme : relus, ils doivent rester dans le dossier de donnees.
    var chemins: [String] { remplaces + crees + dossiersCrees + Array(empreintes.keys) }
}

// MARK: L'application

actor ApplicationImport {
    /// Le dossier de travail, a la racine du dossier de donnees : cache, ignore par l'etat et par l'app.
    static let nomTravail = ".reprise-en-cours"
    static let nomJournal = "journal.json"
    static let nomAttente = "attente"
    static let nomSauvegarde = "sauvegarde"
    /// Le dossier (a la racine du dossier de donnees) ou va l'original d'un fichier que l'app a ecrit depuis l'import.
    static let nomConserve = ".reprise-conservee"
    /// Combien de fois le plan est refait quand l'etat de l'app bouge sous nos pieds.
    static let tentatives = 3

    let racine: URL
    private let preferences: any PreferencesReprise
    private let operations: any OperationsFichiers
    private let maintenant: @Sendable () -> Date
    private let calendrier: Calendar

    /// Un changement du dossier de donnees ou des preferences depuis le plan : interne, jamais montre.
    private struct EtatChange: Error {}
    /// Un fichier de l'export n'a plus l'empreinte du manifeste.
    private struct ExportChange: Error {}

    init(dossierDonnees: URL, preferences: any PreferencesReprise = PreferencesUserDefaults.app,
         operations: any OperationsFichiers = OperationsFichiersReelles(),
         maintenant: @escaping @Sendable () -> Date = { Date() }, calendrier: Calendar = .current) {
        racine = dossierDonnees
        self.preferences = preferences
        self.operations = operations
        self.maintenant = maintenant
        self.calendrier = calendrier
    }

    private var travail: URL { racine.appendingPathComponent(Self.nomTravail, isDirectory: true) }
    private var attente: URL { travail.appendingPathComponent(Self.nomAttente, isDirectory: true) }
    private var sauvegarde: URL { travail.appendingPathComponent(Self.nomSauvegarde, isDirectory: true) }
    private var fichierJournal: URL { travail.appendingPathComponent(Self.nomJournal) }

    // MARK: API

    /// Valide l'export et prepare le plan, sans rien ecrire (sauf, au besoin, le retablissement d'une application
    /// interrompue). A lancer hors du fil principal : `await`.
    func preparer(export dossier: URL) async throws -> IssuePreparation {
        _ = try recupererSync()
        switch ValidationExport.valider(dossier: dossier, dossierDonnees: racine) {
        case .refuse(let cause):
            throw ErreurApplication.refuse(cause)
        case .dejaRepris(let reprise, let resume):
            return .dejaRepris(reprise, resume)
        case .acceptee:
            let (manifeste, reglages) = try verifier(dossier)
            let etat = try lireEtat()
            return .aReprendre(try planifier(dossier, manifeste: manifeste, reglages: reglages, etat: etat))
        }
    }

    /// Applique le plan d'un coup, ou pas du tout. Reverifie l'export et l'etat de l'app ; si l'app a change depuis
    /// `preparer`, le plan est refait (l'existant l'emporte toujours) avant d'etre applique.
    func appliquer(_ preparation: PreparationImport) async throws -> ResultatApplication {
        var courante = preparation
        var recalcule = false
        for _ in 0..<Self.tentatives {
            _ = try recupererSync()
            let (manifeste, reglages) = try verifier(preparation.dossierExport)
            guard manifeste == preparation.manifeste, reglages == preparation.reglagesExport else {
                throw ErreurApplication.exportModifie
            }
            let imports = try lireJournalDesImports()
            if let reprise = imports.entree(pour: manifeste.identifiant) { throw ErreurApplication.dejaRepris(reprise) }
            let etat = try lireEtat()
            if etat != courante.etat {
                courante = try planifier(preparation.dossierExport, manifeste: manifeste, reglages: reglages, etat: etat)
                recalcule = true
            }
            do {
                return try appliquerPlan(courante, imports: imports, planRecalcule: recalcule)
            } catch is EtatChange {
                continue
            }
        }
        throw ErreurApplication.etatInstable
    }

    /// `preparer` puis `appliquer` d'une traite (sans confirmation entre les deux).
    func reprendre(export dossier: URL) async throws -> IssueReprise {
        switch try await preparer(export: dossier) {
        case .dejaRepris(let reprise, let resume): return .dejaRepris(reprise, resume)
        case .aReprendre(let preparation): return .repris(try await appliquer(preparation))
        }
    }

    /// A appeler au lancement de l'app, avant tout autre acces au dossier de donnees : defait (ou termine) une application
    /// interrompue. `preparer` et `appliquer` l'appellent aussi.
    func recuperer() async throws -> IssueRecuperation {
        try recupererSync()
    }

    // MARK: Preparation

    private func verifier(_ dossier: URL) throws -> (ContratExport.Manifeste, ContratExport.Reglages) {
        do { return try ContratExport.verifierDossier(dossier) } catch { throw ErreurApplication.exportModifie }
    }

    private func lireJournalDesImports() throws -> JournalImports {
        do { return try JournalImports.lire(dans: racine) } catch {
            throw ErreurApplication.refuse(.journalDesImportsIllisible(chemin: racine.appendingPathComponent(JournalImports.nomFichier).path))
        }
    }

    private func lireEtat() throws -> EtatDonnees {
        do { return try EtatDonnees.lire(racine: racine, reglagesPresents: preferences.clesPresentes()) } catch {
            throw ErreurApplication.echec(.preparation, retablie: true, code: Self.code(error))
        }
    }

    private func planifier(_ dossier: URL, manifeste: ContratExport.Manifeste, reglages: ContratExport.Reglages,
                           etat: EtatDonnees) throws -> PreparationImport {
        let actuel = EtatActuel(dossier: racine, reglagesPresents: etat.reglagesPresents)
        let plan: PlanReprise
        do {
            switch manifeste.app {
            case .maillageThread:
                plan = try ConversionThread.convertir(dossier: dossier, manifeste: manifeste, reglages: reglages, etat: actuel,
                                                      maintenant: maintenant(), calendrier: calendrier)
            case .maillageZigbee:
                plan = try ConversionZigbee.convertir(dossier: dossier, manifeste: manifeste, reglages: reglages, etat: actuel,
                                                      maintenant: maintenant(), calendrier: calendrier)
            }
        } catch {
            throw ErreurApplication.exportModifie
        }
        return PreparationImport(dossierExport: dossier, manifeste: manifeste, reglagesExport: reglages,
                                 resume: ResumeExport(manifeste: manifeste, reglages: reglages), plan: plan, etat: etat)
    }

    // MARK: Application

    private func appliquerPlan(_ p: PreparationImport, imports: JournalImports, planRecalcule: Bool) throws -> ResultatApplication {
        let plan = p.plan
        let repris = ImportRepris(identifiant: p.manifeste.identifiant, app: p.manifeste.app,
                                  versionApp: p.manifeste.versionApp, date: maintenant())
        let octetsImports: Data
        do { octetsImports = try JournalImports(imports: imports.imports + [repris]).donnees() } catch {
            throw ErreurApplication.echec(.preparation, retablie: true, code: Self.code(error))
        }

        // Les fichiers a placer : ceux du plan, puis imports.json (le dernier : sa mise en place valide tout).
        var aPlacer: [(chemin: String, contenu: ContenuAPlacer)] = []
        for f in plan.fichiers {
            guard ContratExport.cheminEstValide(f.chemin), f.chemin != JournalImports.nomFichier,
                  f.chemin.split(separator: "/").first.map(String.init) != Self.nomTravail else {
                throw ErreurApplication.echec(.preparation, retablie: true, code: "chemin")
            }
            aPlacer.append((f.chemin, f.contenu))
        }
        aPlacer.append((JournalImports.nomFichier, .donnees(octetsImports)))

        var remplaces: [String] = []
        var crees: [String] = []
        for (chemin, _) in aPlacer {
            let present = EtatDonnees.existe(racine.appendingPathComponent(chemin))
            guard present == (p.etat.fichiers[chemin] != nil) else { throw EtatChange() }
            if present { remplaces.append(chemin) } else { crees.append(chemin) }
        }
        var dossiersCrees: [String] = []
        for (chemin, _) in aPlacer {
            var composants = chemin.split(separator: "/").map(String.init)
            composants.removeLast()
            for i in composants.indices {
                let dossier = composants[0...i].joined(separator: "/")
                if !dossiersCrees.contains(dossier), !EtatDonnees.existe(racine.appendingPathComponent(dossier)) {
                    dossiersCrees.append(dossier)
                }
            }
        }
        dossiersCrees.sort { $0.split(separator: "/").count < $1.split(separator: "/").count }
        // L'empreinte de chaque fichier tel que l'import le met en place (verifiee dans l'attente avant le remplacement).
        var empreintes: [String: String] = [:]
        for (chemin, contenu) in aPlacer {
            switch contenu {
            case .donnees(let donnees): empreintes[chemin] = ContratExport.sha256(donnees)
            case .copie(_, let sha256): empreintes[chemin] = sha256
            }
        }
        var journal = JournalApplication(identifiant: p.manifeste.identifiant, remplaces: remplaces, crees: crees,
                                         dossiersCrees: dossiersCrees, racineCreee: !EtatDonnees.existe(racine),
                                         empreintes: empreintes)

        var etape = EtapeApplication.preparation
        do {
            // 1. Dossier de travail et journal, avant tout deplacement.
            // Un seul appel pour la racine (si elle manque) et le dossier de travail : un arret ne laisse jamais une racine
            // vide sans dossier de travail.
            try operations.creerDossier(travail)
            try operations.creerDossier(attente)
            try operations.creerDossier(sauvegarde)
            try operations.ecrire(try ContratExport.encodeur().encode(journal), vers: fichierJournal, atomique: true)

            // 2. Dossier d'attente : chaque fichier, puis son empreinte.
            for (chemin, contenu) in aPlacer { try deposerEnAttente(chemin, contenu) }

            // 3. Remplacement des fichiers du plan, un par un. Le journal le dit d'abord (en memoire avant le disque : le
            // retablissement est ainsi toujours au moins aussi prudent que ce qui est ecrit).
            etape = .remplacement
            journal.phase = .remplacement
            try operations.ecrire(try ContratExport.encodeur().encode(journal), vers: fichierJournal, atomique: true)
            for dossier in dossiersCrees { try operations.creerDossier(racine.appendingPathComponent(dossier)) }
            for (chemin, _) in aPlacer.dropLast() { try mettreEnPlace(chemin, remplaces: remplaces, etat: p.etat) }

            // 4. Preferences, une fois les fichiers en place. Le journal dit d'abord ce qui va etre ecrit (valeur et etat
            // d'avant) : le retour en arriere ne touche que ces cles, et seulement si elles ont encore cette valeur.
            etape = .reglages
            guard preferences.clesPresentes().isDisjoint(with: plan.reglages.keys) else { throw EtatChange() }
            let avant = preferences.valeurs(pour: plan.reglages.keys.sorted())
            journal.reglagesEcrits = plan.reglages.sorted { $0.key < $1.key }.map {
                ReglageJournal(cle: $0.key, ecrite: $0.value, avant: avant[$0.key])
            }
            journal.phase = .reglages
            try operations.ecrire(try ContratExport.encodeur().encode(journal), vers: fichierJournal, atomique: true)
            try preferences.ecrire(plan.reglages)

            // 5. La validation : imports.json prend sa place.
            etape = .validation
            try mettreEnPlace(JournalImports.nomFichier, remplaces: remplaces, etat: p.etat)
        } catch {
            let retour = Result { try retablir(journal) }
            // Defait, ou defait sauf ce que l'app a ecrit entretemps (laisse en place : le plan refait le fusionnera).
            if case .success(let laisses) = retour {
                if error is EtatChange { throw error }
                if error is ExportChange { throw ErreurApplication.exportModifie }
                if !laisses.estVide { throw ErreurApplication.echecAvecReste(etape, laisses, code: Self.code(error)) }
            }
            throw ErreurApplication.echec(etape, retablie: (try? retour.get()) != nil, code: Self.code(error))
        }

        // 6. Nettoyage : sans effet sur le resultat.
        nettoyer()
        return ResultatApplication(repris: repris, fichiersEcrits: plan.fichiers.map(\.chemin), reglagesEcrits: plan.reglages.keys.sorted(),
                                   nonPris: plan.nonPris, planRecalcule: planRecalcule)
    }

    /// Ecrit ou copie le fichier dans l'attente, puis verifie son empreinte.
    private func deposerEnAttente(_ chemin: String, _ contenu: ContenuAPlacer) throws {
        let cible = attente.appendingPathComponent(chemin)
        if chemin.contains("/") { try operations.creerDossier(cible.deletingLastPathComponent()) }
        switch contenu {
        case .donnees(let donnees):
            try operations.ecrire(donnees, vers: cible, atomique: false)
            guard try ContratExport.sha256(fichier: cible) == ContratExport.sha256(donnees) else {
                throw CocoaError(.fileWriteUnknown)
            }
        case .copie(let source, let sha256):
            try operations.copier(de: source, vers: cible)
            guard try ContratExport.sha256(fichier: cible) == sha256 else { throw ExportChange() }
        }
    }

    /// Met un fichier d'attente a sa place : l'original (s'il existe) va d'abord en sauvegarde, verifie contre le plan.
    private func mettreEnPlace(_ chemin: String, remplaces: [String], etat: EtatDonnees) throws {
        let cible = racine.appendingPathComponent(chemin)
        if remplaces.contains(chemin) {
            let sauvegarde = sauvegarde.appendingPathComponent(chemin)
            if chemin.contains("/") { try operations.creerDossier(sauvegarde.deletingLastPathComponent()) }
            try operations.deplacer(de: cible, vers: sauvegarde)
            guard try EtatDonnees.empreinte(sauvegarde) == etat.fichiers[chemin] else { throw EtatChange() }
        } else {
            guard !EtatDonnees.existe(cible) else { throw EtatChange() }
        }
        try operations.deplacer(de: attente.appendingPathComponent(chemin), vers: cible)
    }

    // MARK: Retour en arriere et reprise

    /// Defait ce que le journal dit avoir ete fait, sans rien supposer de ce qui l'a vraiment ete : chaque etape regarde
    /// l'etat des fichiers, donc elle se refait sans danger. Chaque etape est tentee meme si la precedente echoue ; la
    /// premiere erreur est rendue a la fin, et le dossier de travail reste alors pour la reprise suivante.
    ///
    /// Ne defait que ce que l'import a ecrit et qui n'a pas bouge depuis (empreinte, valeur) : le reste est rendu, pas touche.
    private func retablir(_ j: JournalApplication) throws -> ElementsLaisses {
        var premiereErreur: (any Error)?
        var laisses = ElementsLaisses()
        func essayer(_ action: () throws -> Void) {
            do { try action() } catch { if premiereErreur == nil { premiereErreur = error } }
        }
        // Les reglages d'abord (ecrits apres les fichiers, defaits avant eux) : seulement ceux que l'import a ecrits, et
        // seulement s'ils ont encore la valeur qu'il a ecrite.
        if j.phase == .reglages {
            let actuelles = preferences.valeurs(pour: j.reglagesEcrits.map(\.cle))
            let presentes = preferences.clesPresentes()
            for reglage in j.reglagesEcrits.reversed() {
                if actuelles[reglage.cle] == reglage.ecrite {
                    if let avant = reglage.avant {
                        essayer { try preferences.ecrire([reglage.cle: avant]) }
                    } else {
                        preferences.retirer([reglage.cle])
                    }
                } else if presentes.contains(reglage.cle) {
                    laisses.reglages.append(reglage.cle)
                }
            }
        }
        // Les originaux (imports.json le dernier de la liste : le premier defait).
        for chemin in j.remplaces.reversed() {
            let sauv = sauvegarde.appendingPathComponent(chemin)
            let cible = racine.appendingPathComponent(chemin)
            guard EtatDonnees.existe(sauv) else { continue }
            if EtatDonnees.existe(cible), !contientEncore(cible, empreinte: j.empreintes[chemin]) {
                // L'app a ecrit apres l'import : son fichier reste, l'original est garde a part.
                laisses.fichiers.append(chemin)
                essayer { try conserver(sauv, chemin: chemin, identifiant: j.identifiant) }
                continue
            }
            essayer {
                if EtatDonnees.existe(cible) { try operations.supprimer(cible) }
                try operations.deplacer(de: sauv, vers: cible)
            }
        }
        // Les fichiers crees, seulement ceux que l'application a mis en place (le remplacement a commence et leur fichier
        // d'attente est parti), et seulement s'ils ont encore le contenu mis en place.
        for chemin in j.crees.reversed() where j.phase != .preparation {
            let cible = racine.appendingPathComponent(chemin)
            guard !EtatDonnees.existe(attente.appendingPathComponent(chemin)), EtatDonnees.existe(cible) else { continue }
            if contientEncore(cible, empreinte: j.empreintes[chemin]) {
                essayer { try operations.supprimer(cible) }
            } else {
                laisses.fichiers.append(chemin)
            }
        }
        // Les dossiers crees, s'ils sont vides, du plus bas au plus haut : seulement une fois le remplacement commence (avant,
        // l'import n'en a cree aucun, ceux qui existent sont a l'app).
        for dossier in j.dossiersCrees.reversed() where j.phase != .preparation {
            let url = racine.appendingPathComponent(dossier)
            guard let contenu = try? FileManager.default.contentsOfDirectory(atPath: url.path), contenu.isEmpty else { continue }
            essayer { try operations.supprimer(url) }
        }
        if premiereErreur == nil { essayer { try supprimerJournalEtTravail() } }
        // La racine, si l'application l'a creee et qu'elle est de nouveau vide.
        if premiereErreur == nil, j.racineCreee { supprimerRacineSiVide(&premiereErreur) }
        if let erreur = premiereErreur { throw erreur }
        laisses.fichiers.reverse()
        return laisses
    }

    /// Le fichier a-t-il encore le contenu que l'import y a mis ? (Illisible, ou lien, ou dossier : non.)
    private func contientEncore(_ url: URL, empreinte: String?) -> Bool {
        guard let empreinte, let actuelle = try? EtatDonnees.empreinte(url) else { return false }
        return actuelle.taille >= 0 && actuelle.sha256 == empreinte
    }

    /// Garde l'original d'un fichier que l'app a ecrit depuis l'import, hors du dossier de travail (qui va etre efface).
    private func conserver(_ sauv: URL, chemin: String, identifiant: UUID) throws {
        let base = racine.appendingPathComponent(Self.nomConserve, isDirectory: true)
            .appendingPathComponent(identifiant.uuidString, isDirectory: true)
        var destination = base.appendingPathComponent(chemin)
        var i = 1
        while EtatDonnees.existe(destination) {
            destination = base.appendingPathComponent("\(chemin).\(i)")
            i += 1
        }
        try operations.creerDossier(destination.deletingLastPathComponent())
        try operations.deplacer(de: sauv, vers: destination)
    }

    private func supprimerRacineSiVide(_ erreur: inout (any Error)?) {
        guard let contenu = try? FileManager.default.contentsOfDirectory(atPath: racine.path), contenu.isEmpty else { return }
        do { try operations.supprimer(racine) } catch { if erreur == nil { erreur = error } }
    }

    /// Le journal part le premier : sans lui, un dossier de travail restant n'est plus qu'un reste a effacer (jamais un
    /// retablissement a refaire).
    private func supprimerJournalEtTravail() throws {
        if EtatDonnees.existe(fichierJournal) { try operations.supprimer(fichierJournal) }
        try? operations.supprimer(travail)
    }

    /// Apres la validation : le reste du dossier de travail est inutile. Une erreur ici ne change rien au resultat.
    private func nettoyer() {
        try? supprimerJournalEtTravail()
    }

    private func recupererSync() throws -> IssueRecuperation {
        guard EtatDonnees.existe(travail) else { return .rienAFaire }
        guard EtatDonnees.existe(fichierJournal) else {
            // Arret avant le journal (ou entre la suppression du journal et celle du dossier de travail) : rien n'est a
            // defaire. Une racine devenue vide est retiree : si l'import l'a creee, il ne la laisse pas ; sinon elle ne
            // contenait rien, et l'app la recree.
            var erreur: (any Error)?
            do { try operations.supprimer(travail) } catch {
                throw ErreurApplication.recuperationImpossible(code: Self.code(error))
            }
            supprimerRacineSiVide(&erreur)
            if let erreur { throw ErreurApplication.recuperationImpossible(code: Self.code(erreur)) }
            return .nettoyee
        }
        let journal: JournalApplication
        do {
            journal = try ContratExport.decodeur().decode(JournalApplication.self, from: Data(contentsOf: fichierJournal))
            guard journal.version == JournalApplication.versionCourante else { throw CocoaError(.fileReadCorruptFile) }
            // Un journal abime mais lisible ne doit jamais faire agir hors du dossier de donnees (ni dans le dossier de
            // travail lui-meme, ni sur imports.json comme fichier cree).
            guard journal.chemins.allSatisfy({ ContratExport.cheminEstValide($0)
                && $0.split(separator: "/").first.map(String.init) != Self.nomTravail }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            throw ErreurApplication.recuperationImpossible(code: Self.code(error))
        }
        if let imports = try? JournalImports.lire(dans: racine), imports.entree(pour: journal.identifiant) != nil {
            nettoyer()
            return .terminee
        }
        do {
            let laisses = try retablir(journal)
            return laisses.estVide ? .annulee : .annuleeSauf(laisses)
        } catch { throw ErreurApplication.recuperationImpossible(code: Self.code(error)) }
    }

    private static func code(_ erreur: any Error) -> String {
        let e = erreur as NSError
        return "\(e.domain) \(e.code)"
    }
}
