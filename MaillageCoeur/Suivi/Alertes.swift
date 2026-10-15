import Foundation

/// Categories de notifications (cases des reglages ; restent celles de Thread tant que les notifications ne
/// sont pas decidees par protocole).
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

    /// La fenetre de regroupement des pertes d'un protocole.
    private struct FenetrePertes {
        var debut: Date
        /// Identifiant de la notification groupee, fixe a l'ouverture de la fenetre (d'apres sa premiere perte) : une
        /// perte datee plus tot ne le change pas.
        var identifiant: String
        var pertes: [Evenement]
    }

    /// Les pertes se comptent par protocole (sans protocole : Thread) : trois pertes de deux protocoles ne font pas une
    /// notification groupee, et celle d'un protocole n'embarque que les siennes.
    private var fenetres: [Protocole: FenetrePertes] = [:]
    private let politique: any PolitiqueJournal

    /// Avec la politique neutre (`PolitiqueJournalNeutre`), rien ne se notifie : c'est le protocole qui dit quoi.
    public init(politique: any PolitiqueJournal) {
        self.politique = politique
    }

    /// Retire de la fenetre des pertes celles que `oubli` designe (un protocole eteint : aucune notification ne doit
    /// embarquer ses evenements, ni atteindre le seuil grace a eux). La fenetre repart de la plus ancienne perte gardee ;
    /// vide, elle se referme.
    public mutating func oublierPertes(ou oubli: (Evenement) -> Bool) {
        for (protocole, var f) in fenetres {
            f.pertes.removeAll(where: oubli)
            if let debut = f.pertes.map(\.date).min() {
                f.debut = debut
                fenetres[protocole] = f
            } else {
                fenetres[protocole] = nil
            }
        }
    }

    /// Identifiant de la notification groupee d'un protocole : celui de Thread est reste « pertes-<date> ».
    private static func identifiantPertes(_ protocole: Protocole, _ date: Date) -> String {
        let t = Int(date.timeIntervalSince1970)
        return protocole == .thread ? "pertes-\(t)" : "pertes-\(protocole.rawValue)-\(t)"
    }

    public mutating func traiter(_ evenements: [Evenement]) -> [AlerteAEnvoyer] {
        var sortie: [AlerteAEnvoyer] = []
        var pertesModifiees: Set<Protocole> = []
        for e in evenements {
            if politique.estPerte(e) {
                let protocole = e.protocole ?? .thread
                if var f = fenetres[protocole], abs(e.date.timeIntervalSince(f.debut)) < Regroupement.fenetre {
                    f.pertes.append(e)
                    f.debut = min(f.debut, e.date)
                    fenetres[protocole] = f
                } else {
                    fenetres[protocole] = FenetrePertes(debut: e.date, identifiant: Self.identifiantPertes(protocole, e.date),
                                                        pertes: [e])
                }
                pertesModifiees.insert(protocole)
            } else if politique.estScission(e) {
                let s = Self.signature(e)
                if !(e.constate && scissionsNotifiees.contains(s)), let c = politique.categorie(e) {
                    sortie.append(AlerteAEnvoyer(categorie: c, identifiant: e.id, evenements: [e]))
                }
                scissionsNotifiees.insert(s)
            } else {
                if politique.estReunion(e) {
                    let reseau = (e.reseau ?? "") + "|"
                    scissionsNotifiees = scissionsNotifiees.filter { !$0.hasPrefix(reseau) }
                }
                if let c = politique.categorie(e) {
                    sortie.append(AlerteAEnvoyer(categorie: c, identifiant: e.id, evenements: [e]))
                }
            }
        }
        for protocole in Protocole.allCases where pertesModifiees.contains(protocole) {
            if let f = fenetres[protocole], f.pertes.count >= Self.seuilPertes {
                sortie.append(AlerteAEnvoyer(categorie: .pertes, identifiant: f.identifiant,
                                             evenements: f.pertes.sorted { $0.date < $1.date }))
            }
        }
        return sortie
    }

    /// Signature d'une scission : "<reseau>|<partitions triees>", les partitions
    /// etant les cles de ses `details` (`Suivi.detailsPartitions`), jointes par ",".
    static func signature(_ e: Evenement) -> String {
        "\(e.reseau ?? "")|\(e.details.keys.sorted().joined(separator: ","))"
    }
}
