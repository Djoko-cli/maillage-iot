import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Aides des tests Zigbee (copies de `JournalTests.calendrier` et de `PiecesRouteursTests.fichier()` du coeur) : les
/// tests Zigbee ne dependent d'aucune suite d'une autre cible. Sans test.
enum AidesZigbee {
    /// Un calendrier a +4 h, pour que le mois d'un fichier de journal ne soit pas celui de l'UTC.
    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 4 * 3600)!
        return c
    }

    /// Un fichier `pieces-routeurs.json` dans un dossier temporaire neuf.
    static func fichierPieces() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-noeuds.json")
    }
}
