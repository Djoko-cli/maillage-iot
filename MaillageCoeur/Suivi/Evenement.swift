import Foundation

/// Nature d'un evenement du journal.
public enum TypeEvenement: String, Codable, Hashable, Sendable, CaseIterable {
    // Surveillance
    case surveillanceDemarree, veille
    // Reseau
    case reseauScinde, reseauReuni, chefChange, bbrPrimaireChange, jeuActifChange
    // Routeurs de bordure
    case routeurApparu, routeurDisparu, routeurRoleChange, routeurNouvelleAdresseLien
    // Prefixes OMR
    case prefixeNouveau, prefixeRetire
    // Appareils
    case appareilNouveau, appareilDisparu, appareilRevenu, appareilSansAdresse, appareilChangePartition
    // Maillage de la sonde : un enfant change de parent ou n'en a plus ; un routeur Thread (hors
    // routeurs de bordure) entre dans la liste des routeurs ou en sort
    case parentChange, sansParent, routeurThreadApparu, routeurThreadDisparu

    /// Gravite par defaut.
    public var gravite: Gravite {
        switch self {
        case .reseauScinde, .routeurDisparu:
            .alerte
        case .chefChange, .jeuActifChange, .routeurNouvelleAdresseLien, .prefixeRetire,
             .appareilDisparu, .appareilSansAdresse, .appareilChangePartition, .sansParent, .routeurThreadDisparu:
            .attention
        default:
            .info
        }
    }
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

    public init(date: Date, type: TypeEvenement, gravite: Gravite? = nil, reseau: String? = nil,
                sujet: Sujet? = nil, avant: String? = nil, apres: String? = nil, periode: DateInterval? = nil,
                constate: Bool = false, details: [String: String] = [:]) {
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
    }

    public var id: String {
        "\(Int64((date.timeIntervalSince1970 * 1000).rounded()))-\(type.rawValue)-\(sujet?.id ?? reseau ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case date, type, gravite, reseau, sujet, avant, apres, periode, constate, details
    }

    /// Lecture tolerante : `gravite`, `constate` et `details` peuvent manquer.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        type = try c.decode(TypeEvenement.self, forKey: .type)
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
