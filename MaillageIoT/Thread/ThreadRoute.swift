import AppKit
import Foundation
import ServiceManagement

/// Etat de Thread Route, le demon systeme qui garde la route du Mac vers le reseau Thread, et donc vers la sonde
/// par « Reseau Thread ». Sa source est dans le depot du pont Halo ; ce depot en garde une copie a l'identique
/// (`outils/thread-route`). Il s'installe par son installateur, avec le mot de passe administrateur : une app dans
/// le bac a sable ne peut pas l'inscrire elle-meme (essai du 06/10 : SMAppService y refuse un demon qui n'est pas
/// dans le bac a sable). L'app lit son etat aupres du systeme, ce que permet le bac a sable
/// (`SMAppService.statusForLegacyPlist`).
enum EtatThreadRoute: Equatable, Sendable {
    /// Ni Thread Route, ni halo-routes.
    case absent
    /// Installe, mais desactive dans Reglages Systeme (Ouverture et extensions).
    case aApprouver
    /// Installe et autorise : launchd le garde en marche.
    case actif
    /// halo-routes, son ancien nom, est encore installe : l'installateur le remplace.
    case ancien

    static let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/fr.djoko.thread.route.plist")
    static let plistAncien = URL(fileURLWithPath: "/Library/LaunchDaemons/fr.djoko.halo.routes.plist")

    /// L'etat, a partir de ce que le systeme dit du plist de Thread Route et de celui de halo-routes.
    static func depuis(nouveau: SMAppService.Status, ancien: SMAppService.Status) -> EtatThreadRoute {
        switch nouveau {
        case .enabled: .actif
        case .requiresApproval: .aApprouver
        default: ancien == .enabled || ancien == .requiresApproval ? .ancien : .absent
        }
    }

    /// L'etat du moment, lu aupres du systeme. `statut` repond pour un plist : les tests y mettent une
    /// source simulee, pour ne jamais lire l'etat reel du Mac.
    static func lire(
        statut: (URL) -> SMAppService.Status = { SMAppService.statusForLegacyPlist(at: $0) }
    ) -> EtatThreadRoute {
        depuis(nouveau: statut(plist), ancien: statut(plistAncien))
    }

    /// Libelle de l'etat, dans les Reglages.
    var libelle: String {
        switch self {
        case .absent: String(localized: "Absent")
        case .aApprouver: String(localized: "Désactivé dans Réglages Système")
        case .actif: String(localized: "Actif")
        case .ancien: String(localized: "halo-routes, son ancien nom, est encore installé")
        }
    }

    /// Ce qu'il reste a faire ; rien quand il est actif.
    var consigne: String? {
        switch self {
        case .absent: String(localized: "Pour l'installer : sh outils/thread-route/installer.sh (mot de passe administrateur).")
        case .aApprouver: String(localized: "L'autoriser dans Réglages Système, Général, Ouverture et extensions.")
        case .actif: nil
        case .ancien: String(localized: "Pour le remplacer : sh outils/thread-route/installer.sh (mot de passe administrateur).")
        }
    }
}

/// Suit l'etat de Thread Route pour la page Diagnostic des Reglages. Il le relit :
/// - a la demande (`relire`) : l'onglet qui s'affiche, la fenetre qui se rouvre ;
/// - a chaque retour de l'app au premier plan, tant que cette page est celle de l'onglet retenu : c'est le
///   retour de Reglages Systeme apres l'approbation, ou d'un Terminal ou l'installateur vient de tourner.
///
/// La fenetre Reglages est creee une fois et gardee (`ControleurReglages`) : une vue qui apparait ne peut pas
/// seule voir ce retour, le suivi vit donc avec la fenetre et ecoute lui-meme. Le test de la page affichee
/// (`affiche`) est donne par la fenetre ; le centre et la notification le sont pour les tests.
@MainActor
@Observable
final class SuiviThreadRoute {
    private(set) var etat: EtatThreadRoute
    @ObservationIgnored private let lecture: () -> EtatThreadRoute
    @ObservationIgnored private let affiche: () -> Bool
    @ObservationIgnored private let centre: NotificationCenter
    @ObservationIgnored nonisolated(unsafe) private var observateur: (any NSObjectProtocol)?

    /// `lecture` rend l'etat du moment (par defaut, celui du systeme : les tests y mettent le leur) ; `affiche`
    /// dit si la page de l'etat est celle de l'onglet retenu. L'etat est lu une fois, a la creation.
    init(lecture: @escaping () -> EtatThreadRoute = { EtatThreadRoute.lire() },
         affiche: @escaping () -> Bool,
         centre: NotificationCenter = .default,
         retour: Notification.Name = NSApplication.didBecomeActiveNotification) {
        self.lecture = lecture
        self.affiche = affiche
        self.centre = centre
        etat = lecture()
        observateur = centre.addObserver(forName: retour, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relireSiAffiche() }
        }
    }

    deinit {
        if let observateur { centre.removeObserver(observateur) }
    }

    /// Relit l'etat aupres du systeme.
    func relire() {
        etat = lecture()
    }

    /// Relit l'etat si la page qui le montre est celle de l'onglet retenu ; sinon, ne lit rien.
    func relireSiAffiche() {
        if affiche() { relire() }
    }
}
