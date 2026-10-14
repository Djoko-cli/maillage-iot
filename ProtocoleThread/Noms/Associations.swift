import Foundation
import MaillageCoeur

/// Associations a la main entre un appareil et un accessoire de Maison (identifiant de l'appareil -> `noeudMatter` de
/// l'accessoire), gardees dans `associations.json` comme les surnoms. Une association dont l'appareil retrouve son
/// noeud reste dans le fichier, sans effet : si l'accessoire cesse de nouveau d'etre annonce par lui, le nom revient
/// sans geste.
///
/// Le fichier est propre a Thread : les cles restent brutes (jamais prefixees). Schema (version 1) :
/// `{"version": 1, "associations": {"<appareil>": "<noeudMatter>"}}` ; l'ancien dictionnaire plat, sans version, se
/// relit encore, et la premiere ecriture le passe au nouveau schema. Une version plus recente n'est jamais reecrite
/// (`FichiersGardes`).
public enum Associations {
    public static let versionActuelle = 1

    /// Le fichier tel qu'il est sur disque.
    struct Fichier: Codable {
        var version = Associations.versionActuelle
        var associations: [String: String]

        init(associations: [String: String]) { self.associations = associations }

        private enum CodingKeys: String, CodingKey { case version, associations }

        /// Avec `version` : le schema d'aujourd'hui ; sans : l'ancien dictionnaire plat.
        init(from decoder: any Decoder) throws {
            if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.version) {
                version = try c.decode(Int.self, forKey: .version)
                associations = try c.decode([String: String].self, forKey: .associations)
            } else {
                associations = try decoder.singleValueContainer().decode([String: String].self)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encode(associations, forKey: .associations)
        }
    }

    /// Vide si le fichier manque, est illisible ou d'une version plus recente (`FichiersGardes`).
    public static func lire(_ url: URL) -> [String: String] {
        FichiersGardes.lire(Fichier.self, url, version: versionActuelle, versionFacultative: true)?.associations ?? [:]
    }

    /// Ecriture atomique ; un fichier illisible est d'abord mis de cote (`FichiersGardes`).
    public static func ecrire(_ associations: [String: String], dans url: URL) throws {
        try FichiersGardes.ecrire(Fichier(associations: associations), dans: url, version: versionActuelle,
                                  versionFacultative: true)
    }
}
