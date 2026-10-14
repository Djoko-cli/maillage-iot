import Foundation

/// Ce que le demon sait de Maison : HomeKit dans l'app (`MaisonHomeKit`), une fausse maison dans les tests.
@MainActor
protocol SourceMaison: AnyObject {
    /// Acces a Maison.
    var acces: EtatPasseur.Acces { get }
    /// Appele a chaque changement : autorisation, maisons, accessoires, noms, pieces, zones, services.
    var surChangement: (@MainActor () -> Void)? { get set }
    /// Le releve de Maison ; `batteries` : relit d'abord les batteries (au plus quelques secondes), sinon leurs
    /// dernieres valeurs connues. nil tant que Maison n'a ni donne ses domiciles ni refuse l'acces.
    func releve(batteries: Bool) async -> NomsMaison?
    /// `identify()` sur l'accessoire de cet identifiant (`HMAccessory.uniqueIdentifier`).
    func identifier(_ accessoire: UUID) async -> IssueIdentifier
}

/// Issue d'une identification, avant d'etre mise dans `ReponseIdentifier`.
enum IssueIdentifier: Equatable, Sendable {
    case ok
    case inconnu
    case nonIdentifiable
    /// Le texte de l'erreur de HomeKit.
    case erreur(String)

    func reponse(_ demande: Int) -> ReponseIdentifier {
        switch self {
        case .ok: ReponseIdentifier(demande: demande, ok: true)
        case .inconnu: ReponseIdentifier(demande: demande, ok: false, erreur: ReponseIdentifier.inconnu)
        case .nonIdentifiable: ReponseIdentifier(demande: demande, ok: false, erreur: ReponseIdentifier.nonIdentifiable)
        case .erreur(let texte): ReponseIdentifier(demande: demande, ok: false, erreur: texte)
        }
    }
}

/// Une connexion d'abonnement vers une app (`ConnexionApp` ; un faux dans les tests). Le jeton part a sa creation.
@MainActor
protocol LienApp: AnyObject {
    /// Message recu de l'app.
    var surMessage: (@MainActor (MessagePasseur) -> Void)? { get set }
    /// Connexion finie (fermee par l'app, coupee, trame mal formee, ou `fermer()`) : une seule fois.
    var surFin: (@MainActor () -> Void)? { get set }
    func envoyer(_ m: MessagePasseur)
    func fermer()
}

/// L'ouverture a la session du demon (`SMAppService.mainApp` dans l'app, `OuvertureSMAppService` ; une fausse dans
/// les tests).
@MainActor
protocol OuvertureSessionDemon: AnyObject {
    var statut: EtatPasseur.Ouverture { get }
    /// Inscrit ou desinscrit le demon ; nil si c'est fait, sinon le texte de l'erreur.
    func regler(actif: Bool) -> String?
}

/// Une action planifiee, annulable.
@MainActor
protocol Annulable: AnyObject {
    func annuler()
}

/// Planifie une action apres un delai : `Task.sleep` dans l'app (`HorlogeReelle`), une horloge avancee a la main dans
/// les tests.
@MainActor
protocol Horloge: AnyObject {
    func apres(_ delai: Duration, _ action: @escaping @MainActor () async -> Void) -> any Annulable
}

@MainActor
final class HorlogeReelle: Horloge {
    private final class Tache: Annulable {
        var tache: Task<Void, Never>?

        func annuler() {
            tache?.cancel()
        }
    }

    func apres(_ delai: Duration, _ action: @escaping @MainActor () async -> Void) -> any Annulable {
        let t = Tache()
        t.tache = Task { @MainActor in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            await action()
        }
        return t
    }
}

/// Une action appelee une seule fois, au premier `appeler()`.
@MainActor
final class UneFois {
    private var action: (@MainActor () -> Void)?

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Vrai une fois l'action appelee.
    var fait: Bool { action == nil }

    func appeler() {
        let a = action
        action = nil
        a?()
    }
}
