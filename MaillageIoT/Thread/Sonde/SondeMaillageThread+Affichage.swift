import Foundation
import MaillageCoeur
import ProtocoleThread

// Sonde Thread, role Affichage : ce que les Reglages et le menu lisent de la sonde (etats derives, noms).
extension SondeMaillageThread {
    /// Une activite est tenue (session reseau en place).
    var activiteTenue: Bool { activite != nil }

    /// Le reseau se choisit : nom d'hote connu, et cle de ce Mac pour lui.
    var reseauDisponible: Bool { hote != nil && empreinteAcces != nil }

    /// « Autoriser l'acces reseau » possible : la sonde retenue connectee par son port USB, hors
    /// tournee (une ligne `erreur`, sans id, serait attribuee a la demande de cle).
    var peutAutoriser: Bool {
        guard liaison == .usb, !autorisationEnCours, !tourneeEnCours, case .connectee = etat else { return false }
        return serie != nil && serieEtat == serie
    }

    /// Nom de la sonde retenue pour l'etat qui la concerne : absente, ou connexion, connexion
    /// etablie, refus ou erreur de son port ; nil pour un autre port choisi, ou sans sonde.
    var nomEtat: String? {
        switch etat {
        case .sansSonde: nil
        case .absente: nom
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
}
