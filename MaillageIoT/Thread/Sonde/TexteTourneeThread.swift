import Foundation
import MaillageCoeur
import ProtocoleThread

/// Textes de l'avancement d'une tournee : barre du graphe, Reglages › Sonde, menu.
enum TexteTourneeThread {
    /// Libelle court d'une etape.
    static func etape(_ e: AvancementTournee.Etape) -> String {
        switch e {
        case .etatSonde: String(localized: "État de la sonde")
        case .listeRouteurs: String(localized: "Liste des routeurs")
        case .routeurs: String(localized: "Routeurs")
        case .pileEtReseau: String(localized: "Pile et Network Data")
        case .resolution: String(localized: "Résolution des parents")
        case .compteurs: String(localized: "Compteurs des enfants")
        case .identites: String(localized: "Identité des enfants")
        }
    }

    /// « Resolution des parents · 12/26 » ; l'etape seule quand elle n'a rien a faire.
    static func avancement(_ a: AvancementTournee) -> String {
        guard a.total > 0 else { return etape(a.etape) }
        return String(localized: "\(etape(a.etape)) · \(a.fait)/\(a.total)")
    }

    /// Barre du graphe : « Resolution des parents · 12/26 · 0:42 ».
    static func barre(_ a: AvancementTournee, debut: Date, maintenant: Date) -> String {
        String(localized: "\(avancement(a)) · \(TexteTournee.chrono(maintenant.timeIntervalSince(debut)))")
    }

    /// Texte le plus large de la barre pour une etape (compteur a trois chiffres, duree de
    /// 99:59), invisible : il donne sa largeur fixe a la capsule de la tournee.
    static func gabaritBarre(_ e: AvancementTournee.Etape) -> String {
        String(localized: "\(avancement(AvancementTournee(etape: e, fait: 888, total: 888))) · \(TexteTournee.chrono(99 * 60 + 59))")
    }

    /// Reglages › Sonde : « Resolution des parents · 12/26 · depuis 42 s ».
    static func reglages(_ a: AvancementTournee, debut: Date, maintenant: Date) -> String {
        String(localized: "\(avancement(a)) · depuis \(TexteTournee.duree(maintenant.timeIntervalSince(debut)))")
    }

    /// Menu : « SONDE-T1 : Resolution des parents 12/26… ».
    static func menu(_ a: AvancementTournee, nom: String) -> String {
        guard a.total > 0 else { return String(localized: "\(nom) : \(etape(a.etape))…") }
        return String(localized: "\(nom) : \(etape(a.etape)) \(a.fait)/\(a.total)…")
    }
}
