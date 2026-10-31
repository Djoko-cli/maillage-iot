import Foundation
import Network
import Synchronization

/// Connexion TCP des faux clients des tests vers 127.0.0.1. Sur la boucle locale, le systeme peut donner a une connexion un
/// couple d'adresses encore pris par une ancienne connexion (TIME_WAIT) : elle echoue avec EADDRINUSE avant d'atteindre
/// l'ecoute, et une `NWConnection` reste alors en attente sans jamais finir un envoi (constat du 01/11 : un test bloque
/// jusqu'a sa limite de 60 s, et la porte avorte). On en ouvre une nouvelle, qui part d'un autre port.
enum ConnexionLocale {
    /// Issue d'un essai de connexion.
    enum Issue: Sendable, Equatable {
        case prete
        /// Couple d'adresses deja pris : un nouvel essai peut reussir.
        case adresseOccupee
        /// Personne n'ecoute, ou delai depasse.
        case echec
    }

    /// Une connexion prete vers 127.0.0.1:`port`, au plus `essais` essais de `delai` chacun ; nil si personne n'ecoute.
    /// `essai` : `essayer`, sauf dans les tests de cette aide.
    static func ouvrir(port: UInt16, essais: Int = 5, delai: Duration = .seconds(5),
                       essai: (NWConnection, Duration) async -> Issue = essayer) async -> NWConnection? {
        guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
        for _ in 0..<essais {
            let c = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
            let i = await essai(c, delai)
            if i == .prete { return c }
            c.cancel()
            guard i == .adresseOccupee else { return nil }
        }
        return nil
    }

    /// L'issue d'un etat de la connexion ; nil tant qu'elle se prepare.
    static func issue(_ etat: NWConnection.State) -> Issue? {
        switch etat {
        case .ready: .prete
        case .waiting(.posix(.EADDRINUSE)), .failed(.posix(.EADDRINUSE)): .adresseOccupee
        case .waiting, .failed, .cancelled: .echec
        default: nil
        }
    }

    /// Demarre la connexion et attend son issue, au plus `delai`.
    static func essayer(_ c: NWConnection, delai: Duration) async -> Issue {
        await withCheckedContinuation { (suite: CheckedContinuation<Issue, Never>) in
            let reprise = Reprise(suite)
            let finir: @Sendable (Issue) -> Void = { reprise.finir($0) }
            c.stateUpdateHandler = { etat in
                if let i = issue(etat) { finir(i) }
            }
            let secondes = Double(delai.components.seconds) + Double(delai.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + secondes) { finir(.echec) }
            c.start(queue: .global())
        }
    }

    /// Reprend la continuation une seule fois, depuis n'importe quel fil.
    private final class Reprise: Sendable {
        private let suite: Mutex<CheckedContinuation<Issue, Never>?>

        init(_ suite: CheckedContinuation<Issue, Never>) {
            self.suite = Mutex(suite)
        }

        func finir(_ i: Issue) {
            suite.withLock { $0.take() }?.resume(returning: i)
        }
    }
}
