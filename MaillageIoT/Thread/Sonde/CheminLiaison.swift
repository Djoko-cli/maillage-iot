import Foundation
import ProtocoleThread

/// Reglage « Liaison » de la sonde Thread (spec 6.7), garde dans les preferences sous `thread.sondeLiaison`. Separe du chemin en
/// service (`SondeMaillageThread.Liaison`), comme `ReglageChemin` et `Acces` pour Zigbee. Les valeurs `usb` et `reseau` sont
/// celles que Maillage Thread 1.3.0 ecrivait : un choix existant se relit tel quel. Sans preference (nouvelle installation) :
/// Automatique.
enum ReglageLiaison: String, CaseIterable, Sendable {
    case automatique, usb, reseau

    var libelle: String {
        switch self {
        case .automatique: String(localized: "Automatique")
        case .usb: String(localized: "USB")
        case .reseau: String(localized: "Réseau Thread")
        }
    }
}

extension SondeMaillageThread.Liaison {
    /// Le chemin en service, dit a l'utilisateur.
    var libelle: String {
        switch self {
        case .usb: String(localized: "USB")
        case .reseau: String(localized: "Réseau Thread")
        }
    }
}

/// Le chemin de la sonde Thread selon le reglage, la carte retenue, la cle de l'acces reseau et l'annonce de la sonde.
enum CheminLiaison {
    /// Le chemin a prendre, ou nil (aucun possible). Automatique : l'USB si la carte retenue est branchee, sinon le reseau si la
    /// cle est connue et la sonde annoncee (`annoncee`). USB : la carte retenue branchee, sinon rien. Reseau Thread : la cle
    /// suffit, sans attendre l'annonce, comme le choix manuel de Thread 1.3.0 (il se reessaie seul, 1 a 30 s) ; Zigbee, lui,
    /// exige l'annonce aussi pour son Wi-Fi.
    nonisolated static func choisir(_ r: ReglageLiaison, branchee: Bool, cleConnue: Bool,
                                    annoncee: Bool) -> SondeMaillageThread.Liaison? {
        switch r {
        case .automatique: branchee ? .usb : (cleConnue && annoncee) ? .reseau : nil
        case .usb: branchee ? .usb : nil
        case .reseau: cleConnue ? .reseau : nil
        }
    }

    /// Les hotes SRP (sans `.local`, en majuscules) que Bonjour montre avec au moins une adresse resolue, dans l'instantane du
    /// reseau Thread : la sonde est un appareil Matter, son hote en fait partie tant qu'elle est sur le reseau. Rien de plus
    /// que ce que l'ecoute Bonjour de Thread voit deja : aucun navigateur, aucun paquet de plus.
    nonisolated static func hotesAnnonces(_ i: Instantane?) -> Set<String> {
        Set((i?.appareils ?? []).filter { $0.genre != .sansAdresse }.map { $0.id.uppercased() })
    }

    /// La sonde (son hote SRP, donne par la carte) est annoncee : son hote est parmi `annonces` (majuscules).
    nonisolated static func annoncee(hote: String?, parmi annonces: Set<String>) -> Bool {
        hote.map { annonces.contains($0.uppercased()) } ?? false
    }
}
