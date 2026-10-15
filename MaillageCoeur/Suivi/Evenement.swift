import Foundation

/// Nature d'un evenement du journal : un nom stable (celui qu'ecrit le journal) et une gravite par defaut. Le coeur
/// ne declare que les types neutres ; chaque protocole declare les siens en extension (EvenementsThread.swift).
/// Deux types sont egaux si leurs noms le sont ; un type inconnu se relit et se garde tel quel.
public struct TypeEvenement: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    /// Gravite par defaut a la creation d'un evenement ; jamais ecrite dans le journal.
    public let gravite: Gravite

    public init(_ rawValue: String, gravite: Gravite = .info) {
        self.rawValue = rawValue
        self.gravite = gravite
    }

    /// Type relu sans le connaitre : gravite par defaut `info`.
    public init(rawValue: String) { self.init(rawValue) }

    public static func == (a: TypeEvenement, b: TypeEvenement) -> Bool { a.rawValue == b.rawValue }
    public func hash(into h: inout Hasher) { h.combine(rawValue) }

    /// Relu du journal : le type connu du decodeur (`CodingUserInfoKey.typesEvenement`), gravite comprise ; sinon
    /// un type inconnu, garde tel quel.
    public init(from decoder: Decoder) throws {
        let nom = try decoder.singleValueContainer().decode(String.self)
        let connus = decoder.userInfo[.typesEvenement] as? [String: TypeEvenement]
        self = connus?[nom] ?? TypeEvenement(rawValue: nom)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    // Surveillance
    public static let surveillanceDemarree = TypeEvenement("surveillanceDemarree")
    public static let veille = TypeEvenement("veille")
}

public extension CodingUserInfoKey {
    /// Types d'evenements connus, par nom (`[String: TypeEvenement]`), pour relire le journal.
    static let typesEvenement = CodingUserInfoKey(rawValue: "typesEvenement")!
    /// Types d'evenements connus de chaque protocole, par nom (`[Protocole: [String: TypeEvenement]]`) : un meme type
    /// peut avoir deux gravites par defaut selon le protocole de l'evenement (`PolitiqueJournalComposee`). Prime sur
    /// `typesEvenement` pour un type que le protocole de la ligne connait.
    static let typesEvenementParProtocole = CodingUserInfoKey(rawValue: "typesEvenementParProtocole")!
}

public enum Gravite: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case info, attention, alerte

    var rang: Int {
        switch self {
        case .info: 0
        case .attention: 1
        case .alerte: 2
        }
    }

    public static func < (a: Gravite, b: Gravite) -> Bool { a.rang < b.rang }
}

/// Ce dont parle un evenement : identifiant et nom affiche a ce moment.
public struct Sujet: Codable, Hashable, Sendable {
    /// Instance d'un routeur, identifiant d'un appareil, `xp` d'un reseau, texte d'un prefixe.
    public var id: String
    public var nom: String

    public init(id: String, nom: String) {
        self.id = id
        self.nom = nom
    }
}

/// Evenement du journal (une ligne JSON par evenement).
public struct Evenement: Codable, Hashable, Sendable, Identifiable {
    /// Moment du changement (premiere absence pour une disparition ; exception : « n'a plus de
    /// parent » est date de la seconde absence, celle qui le declenche).
    public var date: Date
    public var type: TypeEvenement
    public var gravite: Gravite
    /// `xp` du reseau concerne.
    public var reseau: String?
    public var sujet: Sujet?
    public var avant: String?
    public var apres: String?
    /// Date incertaine : le changement a eu lieu pendant cette periode (veille du Mac).
    public var periode: DateInterval?
    /// Etat trouve (au lancement, a la decouverte ou au retour d'un reseau), pas un changement observe.
    public var constate: Bool
    /// Complements ("routeurs": "6", partition -> routeurs, "coupee": "oui"...).
    public var details: [String: String]
    /// Protocole de l'evenement ; nil pour une ligne d'avant l'etape 3 (journaux de Maillage Thread, de Maillage IoT
    /// avant 3a), lue comme Thread par la politique composee (`PolitiqueJournalComposee`). Absent de la ligne quand il
    /// est nil : une ligne d'avant se reecrit a l'identique. `Sujet.id` reste la cle brute du module.
    public var protocole: Protocole?

    public init(date: Date, type: TypeEvenement, gravite: Gravite? = nil, reseau: String? = nil,
                sujet: Sujet? = nil, avant: String? = nil, apres: String? = nil, periode: DateInterval? = nil,
                constate: Bool = false, details: [String: String] = [:], protocole: Protocole? = nil) {
        self.date = date
        self.type = type
        self.gravite = gravite ?? type.gravite
        self.reseau = reseau
        self.sujet = sujet
        self.avant = avant
        self.apres = apres
        self.periode = periode
        self.constate = constate
        self.details = details
        self.protocole = protocole
    }

    /// Identifiant de l'evenement : sa date, son protocole (sans protocole : Thread, comme partout), son type et son sujet.
    /// Deux evenements identiques sauf le protocole ne se confondent pas (ligne du journal, identifiant de notification).
    public var id: String {
        "\(Int64((date.timeIntervalSince1970 * 1000).rounded()))-\((protocole ?? .thread).rawValue)-\(type.rawValue)-\(sujet?.id ?? reseau ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case date, type, gravite, reseau, sujet, avant, apres, periode, constate, details, protocole
    }

    /// Lecture tolerante : `gravite`, `constate`, `details` et `protocole` peuvent manquer. Un protocole inconnu rend la
    /// ligne illisible (elle n'est jamais lue comme une ligne de Thread). Le type se relit avec les types connus du
    /// protocole de la ligne (`typesEvenementParProtocole`, Thread sans protocole), puis avec tous les types connus.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        protocole = try c.decodeIfPresent(Protocole.self, forKey: .protocole)
        let nom = try c.decode(String.self, forKey: .type)
        let duProtocole = (decoder.userInfo[.typesEvenementParProtocole] as? [Protocole: [String: TypeEvenement]])?[protocole ?? .thread]
        let connus = decoder.userInfo[.typesEvenement] as? [String: TypeEvenement]
        type = duProtocole?[nom] ?? connus?[nom] ?? TypeEvenement(rawValue: nom)
        gravite = try c.decodeIfPresent(Gravite.self, forKey: .gravite) ?? type.gravite
        reseau = try c.decodeIfPresent(String.self, forKey: .reseau)
        sujet = try c.decodeIfPresent(Sujet.self, forKey: .sujet)
        avant = try c.decodeIfPresent(String.self, forKey: .avant)
        apres = try c.decodeIfPresent(String.self, forKey: .apres)
        periode = try c.decodeIfPresent(DateInterval.self, forKey: .periode)
        constate = try c.decodeIfPresent(Bool.self, forKey: .constate) ?? false
        details = try c.decodeIfPresent([String: String].self, forKey: .details) ?? [:]
    }
}
