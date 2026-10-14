import Foundation
import Observation

/// Les mises a jour de l'app, inertes : l'app de transition de l'etape 2 (« Maillage IoT Zigbee », spec 6.5) n'est
/// jamais publiee et n'embarque pas Sparkle (ni paquet, ni cles `SU*`, ni exceptions mach-lookup). Le type garde
/// l'API de Maillage Zigbee, que lisent le menu et les Reglages : aucun moteur, aucune recherche, aucun acces au
/// reseau ; « Rechercher les mises a jour… » reste grise et les deux reglages restent eteints, sans rien ecrire.
/// Il disparait avec l'app de transition, a l'etape 3.
@MainActor
@Observable
final class MisesAJour {
    /// Celle de l'app, creee a son lancement.
    static private(set) weak var deLApp: MisesAJour?

    /// Le moteur est-il demarre ? Jamais : il n'y a pas de moteur.
    let demarre = false
    /// « Rechercher les mises a jour… » est possible : jamais.
    private(set) var peutRechercher = false
    /// Reglage : rechercher automatiquement. Sans effet.
    var rechercheAuto = false
    /// Reglage : telecharger et installer automatiquement. Sans effet.
    var installationAuto = false

    /// `demarrer` est ignore : rien a demarrer.
    init(demarrer: Bool) {
        Self.deLApp = self
    }

    /// Le moteur demarrerait-il au lancement ? La decision de Maillage Zigbee, gardee telle quelle ; ici toujours
    /// non, le numero de compilation etant 1 (project.yml).
    static func demarrerAuLancement(demo: Bool) -> Bool {
        doitDemarrer(demo: demo, numero: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                     environnement: ProcessInfo.processInfo.environment)
    }

    /// La decision, pure : oui, sauf en demo, si l'environnement porte celui des tests (Xcode pose
    /// `XCTestConfigurationFilePath`, comme le lit `Surveillance.sousTests`), et si le numero de compilation
    /// (`CFBundleVersion`) est celui d'une compilation de travail, 1 (project.yml) ou absent.
    nonisolated static func doitDemarrer(demo: Bool, numero: String?, environnement: [String: String]) -> Bool {
        !demo && numero != nil && numero != "1" && environnement["XCTestConfigurationFilePath"] == nil
    }

    /// « Rechercher les mises a jour… » : rien, l'app de transition n'en recoit pas.
    func rechercher() {}
}
