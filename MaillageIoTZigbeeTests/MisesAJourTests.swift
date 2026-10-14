import Foundation
import Security
import Testing
@testable import MaillageIoTZigbee
import ProtocoleZigbee

/// Les mises a jour de l'app de transition : inertes, sans Sparkle (ni flux, ni cle, ni exceptions mach-lookup), et le
/// moteur jamais demarre sous les tests.
@MainActor
@Suite("Mises a jour : inertes, sans Sparkle")
struct MisesAJourTests {
    /// L'Info.plist : la version, et aucun reglage de Sparkle (ni flux des versions, ni cle publique).
    @Test func infoPlist() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect((info["CFBundleShortVersionString"] as? String)?.split(separator: ".").count == 3)
        #expect(Int(info["CFBundleVersion"] as? String ?? "") != nil, "un nombre")
        for cle in ["SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks", "SUScheduledCheckInterval",
                    "SUAutomaticallyUpdate", "SUEnableInstallerLauncherService"] {
            #expect(info[cle] == nil, "pas de Sparkle : \(cle)")
        }
    }

    /// Les droits du bac a sable : aucun service de Sparkle (aucune exception mach-lookup), le reseau de l'app.
    @Test func droitsMachLookup() throws {
        let tache = try #require(SecTaskCreateFromSelf(nil))
        let cle = "com.apple.security.temporary-exception.mach-lookup.global-name" as CFString
        let valeur = SecTaskCopyValueForEntitlement(tache, cle, nil) as? [String] ?? []
        // Sous les tests, Xcode ajoute ceux de ses outils (com.apple…) a la compilation Debug.
        #expect(valeur.filter { !$0.hasPrefix("com.apple.") } == [])
        let bac = SecTaskCopyValueForEntitlement(tache, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
        #expect(bac == true)
        let reseau = SecTaskCopyValueForEntitlement(tache, "com.apple.security.network.client" as CFString, nil) as? Bool
        #expect(reseau == true)
    }

    /// La decision de demarrer le moteur : oui dans l'app publiee ordinaire, non en demo, non sous les tests (Xcode
    /// pose `XCTestConfigurationFilePath`), non dans une compilation de travail (numero 1, ou absent). Sans le cas
    /// « oui », une app qui ne cherche jamais passerait.
    @Test func decisionDeDemarrer() {
        #expect(MisesAJour.doitDemarrer(demo: false, numero: "435", environnement: [:]))
        #expect(MisesAJour.doitDemarrer(demo: false, numero: "435", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "1", environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "1", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: nil, environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435", environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "435",
                                         environnement: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "435",
                                         environnement: ["HOME": "/tmp", "XCTestConfigurationFilePath": ""]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435",
                                         environnement: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
    }

    /// Celle de l'app, creee a son lancement, n'est pas demarree sous les tests : aucune recherche, aucun reseau.
    @Test func moteurArreteSousLesTests() throws {
        #expect(!MisesAJour.demarrerAuLancement(demo: false))
        let m = try #require(MisesAJour.deLApp, "creee au lancement de l'app")
        #expect(!m.demarre)
        #expect(!m.peutRechercher, "un moteur arrete ne recherche pas")
    }
}
