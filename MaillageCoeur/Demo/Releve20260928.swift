import Foundation

/// Releve reel du 28/09/2026 a 02:15 (heure du Mac) : reseau MyHome1482620090
/// scinde (Aqara HubM100 seul dans la partition E2E79FFC), 6 routeurs de
/// bordure, 57 instances Matter sur 28 hotes, dont 2 sans adresse. Sert aux
/// tests et au mode demo.
public enum Releve20260928 {
    public static let annonces: Annonces = {
        guard let url = Bundle(for: Ancre.self).url(forResource: "releve-2026-09-28", withExtension: "json"),
              let donnees = try? Data(contentsOf: url),
              let a = try? CodageJSON.decodeur().decode(Annonces.self, from: donnees) else {
            preconditionFailure("releve-2026-09-28.json absent ou illisible du framework MaillageCoeur")
        }
        return a
    }()

    private final class Ancre {}
}
