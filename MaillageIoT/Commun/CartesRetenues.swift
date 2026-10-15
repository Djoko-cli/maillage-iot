import Foundation
import MaillageCoeur
import Observation

/// Les cartes que chaque module de protocole a retenues, par leur numero de serie USB (lu par IOKit sans ouvrir le port,
/// `PortUSB.serie`). Une carte retenue par un module n'est jamais proposee ni ouverte par l'autre (spec 3.4) : ouvrir un
/// port fait basculer DTR/RTS et peut redemarrer un autre ESP32-C6, et un redemarrage USB apres de l'802.15.4 laisse le
/// Wi-Fi de la carte mort.
///
/// Un registre par app, partage par les deux sondes (`ModulesApp`) : chaque sonde y publie sa serie retenue quand elle la
/// lit au lancement, la retient par un choix, ou l'oublie (« Oublier la sonde »). Il est observable : une liste de ports
/// des Reglages qui le lit se met a jour quand l'autre module retient ou oublie une carte, sans evenement USB.
///
/// Un protocole eteint (« Activer ce protocole ») garde sa carte : sa sonde reste construite avec sa serie, et la carte
/// reste reservee. La rendre a l'autre module le laisserait l'ouvrir, puis le rallumage rouvrirait la meme carte.
@MainActor
@Observable
final class CartesRetenues {
    private var series: [Protocole: String] = [:]

    /// `serie` est la carte retenue par `protocole` ; nil (ou vide) la rend. Une serie deja retenue par l'autre module est
    /// gardee quand meme : deux modules qui revendiquent la meme carte (preferences anciennes) la perdent tous les deux,
    /// ce qui est sans danger (aucun n'ouvre une carte que l'autre retient).
    func retenir(_ serie: String?, par protocole: Protocole) {
        if let serie, !serie.isEmpty {
            if series[protocole] != serie { series[protocole] = serie }
        } else if series[protocole] != nil {
            series[protocole] = nil
        }
    }

    /// La carte retenue par `protocole`.
    func serie(de protocole: Protocole) -> String? { series[protocole] }

    /// Un module qui retient `serie`, hors `protocole` s'il est donne.
    func retenuePar(_ serie: String?, hors protocole: Protocole? = nil) -> Protocole? {
        guard let serie, !serie.isEmpty else { return nil }
        return Protocole.allCases.first { $0 != protocole && series[$0] == serie }
    }

    /// `serie` est retenue par un autre module que `protocole`.
    func retenueParUnAutre(_ serie: String?, que protocole: Protocole) -> Bool {
        retenuePar(serie, hors: protocole) != nil
    }

    /// Les ports que `protocole` peut proposer et ouvrir : sans ceux que les autres modules retiennent.
    func choix(_ ports: [PortUSB], pour protocole: Protocole) -> [PortUSB] {
        ports.filter { !retenueParUnAutre($0.serie, que: protocole) }
    }

    /// Le texte d'un choix refuse : la carte demandee est la sonde de l'autre module (`autre`).
    static func texteRefus(retenuePar autre: Protocole) -> String {
        switch autre {
        case .thread: String(localized: "Cette carte est la sonde Thread : elle ne peut pas servir de sonde Zigbee.")
        case .zigbee: String(localized: "Cette carte est la sonde Zigbee : elle ne peut pas servir de sonde Thread.")
        }
    }
}
