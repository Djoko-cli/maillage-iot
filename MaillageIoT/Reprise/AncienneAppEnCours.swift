import AppKit
import MaillageCoeur

// Phase 4, tache 7 : l'ancienne app qui tourne encore. Une sonde USB ne peut avoir qu'un seul maitre : tant que l'ancienne app de
// l'export tourne, l'import ne demarre pas (spec 4.3). Elle est reconnue par son identifiant de bundle EXACT (`fr.djoko.maillage`
// est le debut de celui de Zigbee et de Maillage IoT : un prefixe ne suffit pas).
//
// Banc de la repetition : `terminate()` est refuse par le bac a sable. La voie native est l'evenement Apple « quit »
// (kCoreEventClass / kAEQuitApplication) envoye a l'ancienne app, cible par son identifiant. Le droit
// `com.apple.security.temporary-exception.apple-events` (Droits.entitlements de l'app et de la repetition) est limite a ces deux
// identifiants ; macOS demande a Djoko l'autorisation d'Automatisation la premiere fois. Refus, app absente ou delai : repli sur
// la demande de quitter soi-meme (`SuiviAncienneApp.aQuitterSoiMeme`), puis reverification. Jamais `forceTerminate()`.

/// Les anciennes apps a qui Maillage IoT peut demander de quitter : celles des exports, rien d'autre.
enum AnciennesApps {
    /// Exactement les identifiants du droit `temporary-exception.apple-events` (un test compare avec les droits du produit).
    static let identifiantsAutorises: Set<String> = Set(ContratExport.AppSource.allCases.map(\.identifiantBundle))
}

/// Ce qui est arrive a la demande de quitter envoyee a une ancienne app.
enum IssueQuitter: Equatable, Sendable {
    /// L'app a repondu a l'evenement.
    case envoyee
    /// Pas de reponse dans le delai : l'evenement est peut-etre parti, la reverification dira si l'app est fermee.
    case delai
    /// macOS refuse (Automatisation non accordee : -1743), app introuvable (-600) ou autre erreur : le code du systeme.
    case refusee(code: Int)
    /// L'identifiant n'est pas celui d'une ancienne app : rien n'a ete envoye.
    case nonAutorisee

    /// L'issue d'un code du systeme : 0 (aucune erreur), -1712 (`errAETimeout` : delai), sinon un refus
    /// (-1743 `errAEEventNotPermitted`, -1744 consentement requis, -600 `procNotFound`...).
    init(codeErreur: Int) {
        switch codeErreur {
        case 0: self = .envoyee
        case -1712: self = .delai
        default: self = .refusee(code: codeErreur)
        }
    }
}

/// L'envoi de l'evenement « quit » : une couture, les tests ne l'exercent jamais en reel.
protocol EnvoyeurQuitter: Sendable {
    func envoyerQuitter(a identifiantBundle: String) async -> IssueQuitter
}

/// Le vrai envoi : l'evenement Apple « quit » (kCoreEventClass / kAEQuitApplication) a l'app d'identifiant `identifiantBundle`,
/// et a elle seule, hors du fil principal (la demande d'autorisation d'Automatisation attend la reponse de Djoko). Jamais
/// exerce par les tests : ils passent par un espion.
struct EnvoyeurQuitterSysteme: EnvoyeurQuitter {
    /// Combien de secondes on attend la reponse de l'ancienne app a l'evenement (une fois l'autorisation donnee).
    nonisolated static let delaiReponse: TimeInterval = 5
    /// La file dediee de l'envoi bloquant : l'invite d'Automatisation attend Djoko aussi longtemps qu'il hesite, puis la reponse
    /// de l'app jusqu'a `delaiReponse`. Aucun fil du pool cooperatif n'est immobilise.
    nonisolated static let etiquetteFile = "fr.djoko.maillage.iot.quitter-ancienne-app"
    nonisolated private static let file = DispatchQueue(label: etiquetteFile, qos: .userInitiated)

    /// L'envoi bloquant, appele sur la file dediee (une couture : les tests y observent la file, sans rien envoyer).
    let envoi: @Sendable (String) -> IssueQuitter

    init(envoi: @escaping @Sendable (String) -> IssueQuitter = { EnvoyeurQuitterSysteme.envoyerBloquant($0) }) {
        self.envoi = envoi
    }

    func envoyerQuitter(a identifiantBundle: String) async -> IssueQuitter {
        // Le droit du bac a sable ne couvre que ces deux apps ; on ne vise rien d'autre, meme par erreur.
        guard AnciennesApps.identifiantsAutorises.contains(identifiantBundle) else { return .nonAutorisee }
        let envoi = envoi
        return await withCheckedContinuation { suite in
            Self.file.async { suite.resume(returning: envoi(identifiantBundle)) }
        }
    }

    nonisolated static func envoyerBloquant(_ identifiantBundle: String) -> IssueQuitter {
        let cible = NSAppleEventDescriptor(bundleIdentifier: identifiantBundle)
        let classe = AEEventClass(kCoreEventClass)
        let identifiant = AEEventID(kAEQuitApplication)
        // L'autorisation d'Automatisation : macOS la demande a Djoko la premiere fois (« Maillage IoT veut controler... »).
        let statut = AEDeterminePermissionToAutomateTarget(cible.aeDesc, classe, identifiant, true)
        guard statut == noErr else { return IssueQuitter(codeErreur: Int(statut)) }
        let evenement = NSAppleEventDescriptor(eventClass: classe, eventID: identifiant, targetDescriptor: cible,
                                               returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
        do {
            let reponse = try evenement.sendEvent(options: [.waitForReply], timeout: delaiReponse)
            // Une erreur renvoyee par l'app dans sa reponse (mot-cle `errn`).
            let erreur = reponse.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0
            return IssueQuitter(codeErreur: Int(erreur))
        } catch {
            return IssueQuitter(codeErreur: (error as NSError).code)
        }
    }
}

/// Les apps qui tournent. Une couture : les tests donnent des apps factices, l'app celles de NSWorkspace.
@MainActor
protocol ApplicationsLancees {
    /// Combien d'instances de l'app d'identifiant de bundle `identifiantBundle` tournent.
    func instances(de identifiantBundle: String) -> Int
    /// Envoie a l'app l'evenement Apple « quit », hors du fil principal ; vrai si la demande est partie (reponse ou delai). Le
    /// systeme peut la refuser (Automatisation non accordee) : la reverification dit si l'app est partie.
    func demanderDeQuitter(_ identifiantBundle: String) async -> Bool
}

struct ApplicationsLanceesSysteme: ApplicationsLancees {
    let envoyeur: any EnvoyeurQuitter
    /// Les identifiants de bundle des apps qui tournent (NSWorkspace ; une couture pour les tests).
    let identifiantsLances: @MainActor () -> [String?]

    init(envoyeur: any EnvoyeurQuitter = EnvoyeurQuitterSysteme(),
         identifiantsLances: @escaping @MainActor () -> [String?] = {
             NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(\.bundleIdentifier)
         }) {
        self.envoyeur = envoyeur
        self.identifiantsLances = identifiantsLances
    }

    /// Les identifiants qui sont exactement `identifiantBundle`.
    nonisolated static func compter(_ identifiantBundle: String, parmi identifiants: [String?]) -> Int {
        identifiants.filter { $0 == identifiantBundle }.count
    }

    func instances(de identifiantBundle: String) -> Int {
        Self.compter(identifiantBundle, parmi: identifiantsLances())
    }

    func demanderDeQuitter(_ identifiantBundle: String) async -> Bool {
        // Rien a quitter : elle ne tourne pas, aucun evenement n'est envoye.
        guard instances(de: identifiantBundle) > 0 else { return true }
        // Seulement les anciennes apps des exports : jamais un evenement a une autre app.
        guard AnciennesApps.identifiantsAutorises.contains(identifiantBundle) else { return false }
        switch await envoyeur.envoyerQuitter(a: identifiantBundle) {
        case .envoyee, .delai: return true
        case .refusee, .nonAutorisee: return false
        }
    }
}
