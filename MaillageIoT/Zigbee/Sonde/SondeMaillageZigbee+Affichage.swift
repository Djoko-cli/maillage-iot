import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role Affichage : textes et etats montres aux Reglages et au menu.
extension SondeMaillageZigbee {
    /// Nom de la sonde retenue pour l'etat qui la concerne : absente, ou connexion, connexion etablie, refus ou erreur
    /// de son port ; nil pour un autre port choisi, ou sans sonde.
    var nomEtat: String? {
        switch etat {
        case .sansSonde: nil
        case .absente, .injoignable: nom
        case .connexion, .connectee, .refusee, .erreur: serie != nil && serieEtat == serie ? nom : nil
        }
    }

    /// `rafraichir` lancerait une tournee : sonde connectee, pas de tournee en cours.
    var tourneeAuRafraichir: Bool {
        if case .connectee = etat { !tourneeEnCours } else { false }
    }

    /// Nom montre pour la sonde : le sien, sinon « Sonde ».
    static func nomAffiche(_ nom: String?) -> String {
        nom ?? String(localized: "Sonde")
    }

    /// Pourquoi une tournee n'a pas eu lieu ; nil si elle a eu lieu.
    static func texteEmpechement(_ e: EmpechementTournee?) -> String? {
        switch e {
        case .horsReseau?: String(localized: "La sonde n'est pas dans le réseau : pas de tournée.")
        case .suspendue?: String(localized: "La sonde est suspendue : pas de tournée.")
        case nil: nil
        }
    }

    /// Tournee incomplete, d'apres la derniere raison de la sonde.
    static func texteLacune(_ raison: String) -> String {
        switch raison {
        case "non_membre": String(localized: "Tournée incomplète : la sonde a quitté le réseau.")
        case "cadence": String(localized: "Tournée incomplète : la sonde a atteint sa limite de requêtes.")
        case "sans_reponse": String(localized: "Tournée incomplète : la sonde n'a pas répondu.")
        case TourneeZigbee.lacuneSansTables: String(localized: "Tournée incomplète : tables de voisins pas encore lues.")
        default: String(localized: "Tournée incomplète : \(raison).")
        }
    }
}
