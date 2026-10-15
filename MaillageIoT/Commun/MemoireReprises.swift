import Foundation
import Synchronization

// Commune aux reprises de cles de Zigbee (`TrousseauRepris`) et de Thread (`TrousseauReprisThread`).

/// Les identifiants dont la reprise a deja ete tentee.
struct MemoireReprises: Sendable {
    let tentee: @Sendable (String) -> Bool
    let noter: @Sendable (String) -> Void

    /// Dans les preferences de l'app, sous `cle` (une liste d'identifiants).
    static func preferences(cle: String) -> MemoireReprises {
        MemoireReprises(tentee: { UserDefaults.standard.stringArray(forKey: cle)?.contains($0) == true },
                        noter: { id in
                            var ids = UserDefaults.standard.stringArray(forKey: cle) ?? []
                            if !ids.contains(id) { ids.append(id) }
                            UserDefaults.standard.set(ids, forKey: cle)
                        })
    }

    /// En memoire : celle des tests.
    static func memoire() -> MemoireReprises {
        let partage = Partage()
        return MemoireReprises(tentee: { id in partage.ids.withLock { $0.contains(id) } },
                               noter: { id in _ = partage.ids.withLock { $0.insert(id) } })
    }

    private final class Partage: Sendable {
        let ids = Mutex<Set<String>>([])
    }
}
