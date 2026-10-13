import Foundation

/// Categories de notifications (cases des reglages).
public enum CategorieAlerte: String, Codable, Hashable, Sendable, CaseIterable {
    /// Reseau scinde (par defaut : oui).
    case scission
    /// Routeur de bordure disparu (par defaut : oui).
    case routeurDisparu
    /// Au moins 3 appareils perdus en 10 min, une notification groupee (par defaut : oui).
    case pertes
    /// Le reste (par defaut : non).
    case informations

    public var parDefaut: Bool { self != .informations }
}

/// Notification a presenter ; un meme identifiant remplace la precedente.
public struct AlerteAEnvoyer: Hashable, Sendable {
    public var categorie: CategorieAlerte
    public var identifiant: String
    public var evenements: [Evenement]

    public init(categorie: CategorieAlerte, identifiant: String, evenements: [Evenement]) {
        self.categorie = categorie
        self.identifiant = identifiant
        self.evenements = evenements
    }
}

/// Decide des notifications a partir des nouveaux evenements.
///
/// Une scission n'est notifiee qu'une fois : l'app s'ouvre a chaque ouverture
/// de session, et un reseau qui reste scinde ne doit pas le redire a chaque
/// lancement. Une scission constatee deja notifiee (meme signature) ne notifie
/// pas ; une scission observee notifie toujours ; les deux sont retenues. Une
/// reunion oublie les signatures de son reseau.
public struct Alertes: Sendable {
    public static let seuilPertes = 3

    /// Signatures des scissions deja notifiees (voir `signature`), gardees d'un
    /// lancement a l'autre par l'app.
    public var scissionsNotifiees: Set<String> = []

    private var debutFenetre: Date?
    /// Identifiant de la notification groupee, fixe a l'ouverture de la fenetre
    /// (d'apres sa premiere perte) : une perte datee plus tot ne le change pas.
    private var identifiantPertes: String?
    private var pertes: [Evenement] = []

    public init() {}

    public mutating func traiter(_ evenements: [Evenement]) -> [AlerteAEnvoyer] {
        var sortie: [AlerteAEnvoyer] = []
        var pertesModifiees = false
        for e in evenements {
            if Regroupement.estPerte(e) {
                if let d = debutFenetre, abs(e.date.timeIntervalSince(d)) < Regroupement.fenetre {
                    pertes.append(e)
                    debutFenetre = min(d, e.date)
                } else {
                    debutFenetre = e.date
                    identifiantPertes = "pertes-\(Int(e.date.timeIntervalSince1970))"
                    pertes = [e]
                }
                pertesModifiees = true
            } else {
                switch e.type {
                case .reseauScinde:
                    let s = Self.signature(e)
                    if !(e.constate && scissionsNotifiees.contains(s)) {
                        sortie.append(AlerteAEnvoyer(categorie: .scission, identifiant: e.id, evenements: [e]))
                    }
                    scissionsNotifiees.insert(s)
                case .reseauReuni:
                    let reseau = (e.reseau ?? "") + "|"
                    scissionsNotifiees = scissionsNotifiees.filter { !$0.hasPrefix(reseau) }
                    sortie.append(AlerteAEnvoyer(categorie: .informations, identifiant: e.id, evenements: [e]))
                case .routeurDisparu:
                    sortie.append(AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: e.id, evenements: [e]))
                case .surveillanceDemarree, .veille:
                    break
                default:
                    sortie.append(AlerteAEnvoyer(categorie: .informations, identifiant: e.id, evenements: [e]))
                }
            }
        }
        if pertesModifiees, let identifiant = identifiantPertes, pertes.count >= Self.seuilPertes {
            sortie.append(AlerteAEnvoyer(categorie: .pertes, identifiant: identifiant,
                                         evenements: pertes.sorted { $0.date < $1.date }))
        }
        return sortie
    }

    /// Signature d'une scission : "<reseau>|<partitions triees>", les partitions
    /// etant les cles de ses `details` (`Suivi.detailsPartitions`), jointes par ",".
    static func signature(_ e: Evenement) -> String {
        "\(e.reseau ?? "")|\(e.details.keys.sorted().joined(separator: ","))"
    }
}
