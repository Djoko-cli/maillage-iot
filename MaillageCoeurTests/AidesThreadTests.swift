import Foundation

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
}
