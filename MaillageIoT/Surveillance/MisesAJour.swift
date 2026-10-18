#if !REPETITION
import Combine
import Foundation
import Observation
import Sparkle

/// Les mises a jour de l'app, par Sparkle 2 : recherche au demarrage puis toutes les 24 h, telechargement et
/// installation automatiques, a la fermeture de l'app ou tout de suite par « Installer et relancer ». Le flux
/// (`SUFeedURL`), la cle publique (`SUPublicEDKey`) et ces choix par defaut sont dans l'Info.plist (project.yml).
/// L'app reste dans le bac a sable : Sparkle installe par son service (`SUEnableInstallerLauncherService`) ; les
/// textes de sa fenetre viennent de ses propres traductions.
///
/// Ni en demo, ni sous les tests, le moteur n'est demarre : aucune recherche, aucun acces au reseau, et les
/// reglages ne sont pas ecrits (les preferences sont celles de l'app de Djoko). Ni dans une compilation de
/// travail (numero de compilation 1, jamais publie) : elle ne se remplace jamais par la version publiee.
@MainActor
@Observable
final class MisesAJour {
    /// Celle de l'app, creee a son lancement par `pourLApp` ; aucune autre instance (une fenetre des Reglages d'un
    /// test, par exemple) ne la remplace.
    static private(set) weak var deLApp: MisesAJour?

    /// Le moteur de mises a jour est-il dans cette app ? (Non dans l'app de repetition.)
    nonisolated static let moteurPresent = true
    /// Le moteur est-il demarre ?
    let demarre: Bool
    /// « Rechercher les mises a jour… » est possible : le moteur tourne, et aucune recherche n'est en cours.
    private(set) var peutRechercher = false
    /// Reglage : rechercher automatiquement (au demarrage, puis toutes les 24 h).
    var rechercheAuto: Bool {
        didSet { if demarre { controleur.updater.automaticallyChecksForUpdates = rechercheAuto } }
    }
    /// Reglage : telecharger et installer automatiquement.
    var installationAuto: Bool {
        didSet { if demarre { controleur.updater.automaticallyDownloadsUpdates = installationAuto } }
    }

    @ObservationIgnored private let controleur: SPUStandardUpdaterController
    @ObservationIgnored private var abonnement: AnyCancellable?

    init(demarrer: Bool) {
        controleur = SPUStandardUpdaterController(startingUpdater: demarrer, updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        demarre = demarrer
        rechercheAuto = controleur.updater.automaticallyChecksForUpdates
        installationAuto = controleur.updater.automaticallyDownloadsUpdates
        abonnement = controleur.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] peut in
            MainActor.assumeIsolated { self?.peutRechercher = peut }
        }
    }

    /// L'instance de l'app, creee a son lancement : le moteur ne demarre ni en demo, ni sous les tests, ni dans une
    /// compilation de travail.
    static func pourLApp(demo: Bool) -> MisesAJour {
        let m = MisesAJour(demarrer: demarrerAuLancement(demo: demo))
        deLApp = m
        return m
    }

    /// Le moteur demarre au lancement de l'app, sauf en demo, sous les tests et dans une compilation de travail.
    static func demarrerAuLancement(demo: Bool) -> Bool {
        doitDemarrer(demo: demo, numero: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                     environnement: ProcessInfo.processInfo.environment)
    }

    /// La decision, pure : oui, sauf en demo, si l'environnement porte celui des tests (Xcode pose
    /// `XCTestConfigurationFilePath`, comme le lit `Surveillance.sousTests`), et si le numero de compilation
    /// (`CFBundleVersion`) est celui d'une compilation de travail, 1 (project.yml ; publier.sh donne le nombre de
    /// commits de main) ou absent.
    nonisolated static func doitDemarrer(demo: Bool, numero: String?, environnement: [String: String]) -> Bool {
        !demo && numero != nil && numero != "1" && environnement["XCTestConfigurationFilePath"] == nil
    }

    /// « Rechercher les mises a jour… » : la fenetre de Sparkle dit ce qu'elle trouve.
    func rechercher() {
        controleur.checkForUpdates(nil)
    }
}
#else
import Foundation
import Observation

/// Dans l'app de repetition (cible `MaillageIoTRepetition`, condition de compilation `REPETITION`), il n'y a pas de mises a jour :
/// aucun cadre Sparkle n'y est lie, aucun flux ni aucune cle dans son Info.plist, et la repetition n'est jamais publiee.
/// Meme interface que celle de l'app, mais inerte : le moteur n'est jamais demarre, les reglages et les boutons de mise a jour
/// n'apparaissent pas (`moteurPresent`).
@MainActor
@Observable
final class MisesAJour {
    static private(set) weak var deLApp: MisesAJour?

    nonisolated static let moteurPresent = false
    let demarre = false
    private(set) var peutRechercher = false
    var rechercheAuto = false
    var installationAuto = false

    init(demarrer: Bool) {}

    static func pourLApp(demo: Bool) -> MisesAJour {
        let m = MisesAJour(demarrer: false)
        deLApp = m
        return m
    }

    static func demarrerAuLancement(demo: Bool) -> Bool { false }

    nonisolated static func doitDemarrer(demo: Bool, numero: String?, environnement: [String: String]) -> Bool { false }

    func rechercher() {}
}
#endif
