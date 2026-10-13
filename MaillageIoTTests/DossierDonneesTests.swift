import Foundation
import Testing
@testable import MaillageIoT

/// Identite de Maillage IoT (spec, sections 2.2 et 2.3) : rien n'est lu ni ecrit chez Maillage Thread.
@MainActor
@Suite("Identite : dossier de donnees et preferences de Maillage IoT")
struct DossierDonneesTests {
    @Test func dossierDeDonnees() {
        #expect(Surveillance.dossierParDefaut.lastPathComponent == "Maillage IoT")
        #expect(Surveillance.dossierParDefaut.path.contains("Maillage Thread") == false)
    }

    @Test func clesDePreferencesThreadPrefixees() {
        #expect(SondeMaillage.cles.allSatisfy { $0.hasPrefix("thread.") })
        #expect(Surveillance.cleScissionsNotifiees == "thread.scissionsNotifiees")
    }
}
