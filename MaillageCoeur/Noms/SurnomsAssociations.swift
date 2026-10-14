import Foundation

/// Surnoms donnes dans l'app ("Renommer..."), gardes dans un fichier JSON.
public enum Surnoms {
    /// Vide si le fichier manque ou est illisible (`FichiersGardes`).
    public static func lire(_ url: URL) -> [String: String] {
        FichiersGardes.lire([String: String].self, url) ?? [:]
    }

    /// Un fichier illisible est d'abord mis de cote (`FichiersGardes`).
    public static func ecrire(_ surnoms: [String: String], dans url: URL) throws {
        try FichiersGardes.ecrire(surnoms, dans: url)
    }
}

/// Associations a la main entre un appareil et un accessoire de Maison (identifiant de l'appareil -> `noeudMatter` de
/// l'accessoire), gardees dans `associations.json` comme les surnoms. Une association dont l'appareil retrouve son
/// noeud reste dans le fichier, sans effet : si l'accessoire cesse de nouveau d'etre annonce par lui, le nom revient
/// sans geste.
public enum Associations {
    /// Vide si le fichier manque ou est illisible (`FichiersGardes`).
    public static func lire(_ url: URL) -> [String: String] {
        FichiersGardes.lire([String: String].self, url) ?? [:]
    }

    /// Ecriture atomique ; un fichier illisible est d'abord mis de cote (`FichiersGardes`).
    public static func ecrire(_ associations: [String: String], dans url: URL) throws {
        try FichiersGardes.ecrire(associations, dans: url)
    }
}
