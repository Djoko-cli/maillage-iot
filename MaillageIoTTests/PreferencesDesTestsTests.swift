import Foundation
import Testing

/// Les tests tournent dans l'app reelle : une fenetre construite sans preferences lit `UserDefaults.standard`, c'est-a-dire les
/// reglages de la machine (« Voisins » coupe a la main, mode 3D, liens...), et un test change d'un poste a l'autre (le 19/10 :
/// 328 pt au lieu de 345 pour la legende). Toute `FenetrePieces(...)` des tests recoit donc ses preferences.
@Suite("Tests : jamais les preferences de la machine")
struct PreferencesDesTestsTests {
    static let dossier = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    @Test func chaqueFenetreDesPiecesDesTestsRecoitSesPreferences() throws {
        let fichiers = try #require(FileManager.default.enumerator(at: Self.dossier, includingPropertiesForKeys: nil))
        var sans: [String] = []
        var lues = 0
        for case let url as URL in fichiers where url.pathExtension == "swift" && url.lastPathComponent != "PreferencesDesTestsTests.swift" {
            let texte = try String(contentsOf: url, encoding: .utf8)
            lues += 1
            for (i, ligne) in texte.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where ligne.contains("FenetrePieces(fichierPlaces:") && !ligne.contains("preferences:") {
                sans.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        #expect(lues > 50, "les sources des tests sont lisibles")
        #expect(sans.isEmpty, "FenetrePieces(...) sans preferences: \(sans.joined(separator: ", "))")
    }
}
