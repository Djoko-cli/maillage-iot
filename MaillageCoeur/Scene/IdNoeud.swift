/// Protocole d'un noeud (spec 1.2). L'ordre des cas est l'ordre de tri.
public enum Protocole: String, Codable, Sendable, CaseIterable, Comparable {
    case thread, zigbee

    public static func < (a: Protocole, b: Protocole) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Identifiant d'un noeud au-dessus des modules : le protocole et la cle du module, inchangee (spec 2.1).
/// Forme texte "<protocole>:<cle>", coupee au premier ":" seulement ("thread:instance:Salon" -> cle "instance:Salon").
/// Volontairement sans `CustomStringConvertible` : un identifiant ne s'affiche jamais ; le libelle de repli est `cle`.
public struct IdNoeud: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public let protocole: Protocole
    public let cle: String

    public init(_ protocole: Protocole, _ cle: String) {
        self.protocole = protocole
        self.cle = cle
    }

    /// nil si le protocole est inconnu ou la cle vide.
    public init?(texte: String) {
        guard let i = texte.firstIndex(of: ":"), let p = Protocole(rawValue: String(texte[..<i])) else { return nil }
        let cle = String(texte[texte.index(after: i)...])
        guard !cle.isEmpty else { return nil }
        self.init(p, cle)
    }

    public var texte: String { "\(protocole.rawValue):\(cle)" }

    public static func < (a: IdNoeud, b: IdNoeud) -> Bool {
        (a.protocole, a.cle) < (b.protocole, b.cle)
    }

    public init(from decoder: Decoder) throws {
        let t = try decoder.singleValueContainer().decode(String.self)
        guard let id = IdNoeud(texte: t) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Identifiant de noeud illisible"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(texte)
    }

    public var codingKey: CodingKey { CleTexte(stringValue: texte) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(texte: codingKey.stringValue)
    }

    private struct CleTexte: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
