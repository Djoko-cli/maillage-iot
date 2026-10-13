import Foundation

/// Identites des routeurs d'une partition (RLOC16 -> ExtMac), gardees d'un lancement a l'autre
/// dans un fichier du dossier de l'app (spec de la sonde, section 4) : ce que la tournee a
/// retenu (`MemoireTournee.identites`). Relues au lancement, elles sont effacees a la premiere
/// tournee dans une autre partition, comme le reste de la memoire.
public struct IdentitesGardees: Hashable, Sendable {
    public var partition: String
    public var identites: [UInt16: String]

    public init(partition: String, identites: [UInt16: String]) {
        self.partition = partition
        self.identites = identites
    }

    /// Contenu du fichier : la partition, et chaque ExtMac sous son RLOC16 en 4 hexa.
    private struct Fichier: Codable {
        var partition: String
        var routeurs: [String: String]
    }

    /// nil si le fichier manque ou est illisible (`FichiersGardes`) ; un RLOC16 illisible est ignore.
    public static func lire(_ url: URL) -> IdentitesGardees? {
        guard let f = FichiersGardes.lire(Fichier.self, url) else { return nil }
        var identites: [UInt16: String] = [:]
        for (r, ext) in f.routeurs {
            if let rloc = UInt16(r, radix: 16) { identites[rloc] = ext }
        }
        return IdentitesGardees(partition: f.partition, identites: identites)
    }

    /// Un fichier illisible est d'abord mis de cote (`FichiersGardes`).
    public func ecrire(dans url: URL) throws {
        let routeurs = Dictionary(uniqueKeysWithValues: identites.map { (String(format: "%04X", $0.key), $0.value) })
        try FichiersGardes.ecrire(Fichier(partition: partition, routeurs: routeurs), dans: url)
    }
}

extension MemoireTournee {
    /// Memoire d'un lancement : les identites gardees, dans leur partition ; le reste est neuf.
    public init(identites g: IdentitesGardees) {
        self.init()
        partition = g.partition
        identites = g.identites
    }

    /// Ce qui se garde d'un lancement a l'autre ; nil avant la premiere tournee (pas de partition).
    public var identitesGardees: IdentitesGardees? {
        partition.map { IdentitesGardees(partition: $0, identites: identites) }
    }
}
