import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Aides des tests Thread (copies de `PiecesRouteursTests.fichier()` et de `JournalTests.calendrier`) :
/// les tests Thread ne dependent plus des suites du coeur pour ces deux aides.
enum AidesThread {
    static func fichierPieces() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-routeurs.json")
    }

    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 4 * 3600)!
        return c
    }

    /// Dossier temporaire neuf pour un test de fichiers gardes (copie de `FichiersGardesTests.dossier()`).
    static func dossierGarde() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fichiers-\(UUID().uuidString)")
    }

    /// Les noms des fichiers du dossier, tries (copie de `FichiersGardesTests.noms(_:)`).
    static func nomsDuDossier(_ d: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
    }

    /// Une sorte de fichier garde : son nom, et un aller-retour (lire, changer une valeur inventee, ecrire, relire)
    /// qui rend vrai si la valeur ecrite se relit (copie de `FichiersGardesTests.Sorte`).
    struct SorteGardee: Sendable, CustomTestStringConvertible {
        var nom: String
        var allerRetour: @Sendable (URL) throws -> Bool
        var testDescription: String { nom }
    }
}
