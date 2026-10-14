import Foundation
import MaillageCoeur

/// Les appariements deja trouves entre les appareils du pont Hue et les accessoires de Maison : adresse longue de
/// l'appareil (16 hexa majuscules) -> identifiant HomeKit de l'accessoire (`AccessoireMaison.id`). `FusionNoms` la
/// reapplique en premier : l'identifiant HomeKit ne change pas quand l'utilisateur renomme une tuile ou la change de
/// piece, alors que le nom et la piece qui servaient a retrouver l'accessoire, eux, changent. Elle se garde dans le
/// dossier de l'app (`appariements-maison.json`), a cote du releve de Maison.
public struct MemoireAppariements: Codable, Hashable, Sendable {
    public static let versionActuelle = 1
    public static let fichier = "appariements-maison.json"

    public var version: Int
    public var ids: [String: String]

    public init(ids: [String: String] = [:]) {
        version = Self.versionActuelle
        self.ids = ids
    }

    /// Fichier de la memoire dans le dossier de l'app.
    public static func fichier(dossier: URL) -> URL {
        dossier.appendingPathComponent(fichier)
    }

    /// La memoire gardee (`FichiersGardes`) ; vide si le fichier manque, est illisible ou d'une version plus recente
    /// (elle se refait au releve suivant : ce n'est qu'un cache).
    public static func lire(_ url: URL) -> MemoireAppariements {
        FichiersGardes.lire(MemoireAppariements.self, url, version: versionActuelle) ?? MemoireAppariements()
    }

    /// Ecrit la memoire d'un bloc, en creant le dossier au besoin (`FichiersGardes`) : un fichier d'une version plus
    /// recente n'est jamais ecrase (rien n'est ecrit, sans erreur), un fichier illisible est mis de cote d'abord.
    public func ecrire(dans url: URL) throws {
        try FichiersGardes.ecrire(self, dans: url, version: Self.versionActuelle)
    }
}
