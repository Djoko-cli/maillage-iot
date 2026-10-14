import Foundation

/// Surnoms donnes dans l'app ("Renommer..."), gardes dans `surnoms.json`, communs aux protocoles : une cle par noeud,
/// sous sa forme texte d'`IdNoeud` ("thread:<cle>", "zigbee:<cle>").
///
/// Schema (version 1) : `{"version": 1, "surnoms": {"thread:<cle>": "...", "zigbee:<cle>": "..."}}`. Le fichier d'avant
/// (Maillage Thread 1.3, Maillage Zigbee 1.1.1) etait un dictionnaire plat de cles brutes, sans version : il se relit
/// encore, ses cles prenant le protocole de l'app qui le lit (`protocoleParDefaut`), puis la premiere ecriture le passe
/// au nouveau schema. Une cle d'un protocole inconnu, ou une version plus recente, rend le fichier « plus recent »
/// (`FichiersGardes`) : lu comme vide, jamais reecrit.
public enum Surnoms {
    public static let versionActuelle = 1

    /// Le fichier tel qu'il est sur disque : cles en forme texte (ou brutes, pour l'ancien dictionnaire plat).
    struct Fichier: Codable {
        var version = Surnoms.versionActuelle
        var surnoms: [String: String]
        /// Lu de l'ancien dictionnaire plat (jamais ecrit) : les cles sont alors brutes.
        var plat = false

        init(surnoms: [String: String]) { self.surnoms = surnoms }

        private enum CodingKeys: String, CodingKey { case version, surnoms }

        init(from decoder: any Decoder) throws {
            if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.version) {
                version = try c.decode(Int.self, forKey: .version)
                surnoms = try c.decode([String: String].self, forKey: .surnoms)
                // Une cle d'un protocole inconnu : fichier d'une app plus recente.
                for cle in surnoms.keys { _ = try FichiersGardes.idNoeud(cle) }
            } else {
                surnoms = try decoder.singleValueContainer().decode([String: String].self)
                plat = true
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encode(surnoms, forKey: .surnoms)
        }
    }

    /// Vide si le fichier manque, est illisible ou d'une version plus recente (`FichiersGardes`). `protocoleParDefaut` : le
    /// protocole de l'app, pour les cles brutes de l'ancien dictionnaire plat.
    public static func lire(_ url: URL, protocoleParDefaut: Protocole) -> [IdNoeud: String] {
        guard let f = FichiersGardes.lire(Fichier.self, url, version: versionActuelle, versionFacultative: true) else {
            return [:]
        }
        var surnoms: [IdNoeud: String] = [:]
        for (cle, surnom) in f.surnoms {
            if f.plat {
                surnoms[IdNoeud(protocoleParDefaut, cle)] = surnom
            } else if let id = IdNoeud(texte: cle) {
                surnoms[id] = surnom
            }
        }
        return surnoms
    }

    /// Un fichier illisible est d'abord mis de cote ; un fichier d'une version plus recente n'est pas ecrit
    /// (`FichiersGardes`).
    public static func ecrire(_ surnoms: [IdNoeud: String], dans url: URL) throws {
        let f = Fichier(surnoms: Dictionary(uniqueKeysWithValues: surnoms.map { ($0.key.texte, $0.value) }))
        try FichiersGardes.ecrire(f, dans: url, version: versionActuelle, versionFacultative: true)
    }

    /// Les surnoms d'un protocole, sous les cles brutes de son module (les resolveurs de noms des modules gardent leurs
    /// cles en texte brut).
    public static func cles(de surnoms: [IdNoeud: String], protocole: Protocole) -> [String: String] {
        Dictionary(uniqueKeysWithValues: surnoms.compactMap { id, surnom in
            id.protocole == protocole ? (id.cle, surnom) : nil
        })
    }
}
