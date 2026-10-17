import AppKit
import MaillageCoeur

// Phase 4, tache 7 : l'ancienne app qui tourne encore. Une sonde USB ne peut avoir qu'un seul maitre : tant que l'ancienne app de
// l'export tourne, l'import ne demarre pas (spec 4.3). Elle est reconnue par son identifiant de bundle EXACT (`fr.djoko.maillage`
// est le debut de celui de Zigbee et de Maillage IoT : un prefixe ne suffit pas), et quittee par `terminate()`, jamais par
// `forceTerminate()`.

/// Les apps qui tournent. Une couture : les tests donnent des apps factices, l'app celles de NSWorkspace.
@MainActor
protocol ApplicationsLancees {
    /// Combien d'instances de l'app d'identifiant de bundle `identifiantBundle` tournent.
    func instances(de identifiantBundle: String) -> Int
    /// Demande a l'app de quitter (`terminate()`) ; vrai si le systeme a accepte la demande pour chaque instance. Le bac a sable
    /// peut la refuser : la reverification dit si l'app est partie.
    func demanderDeQuitter(_ identifiantBundle: String) -> Bool
}

struct ApplicationsLanceesSysteme: ApplicationsLancees {
    /// Les identifiants qui sont exactement `identifiantBundle`.
    nonisolated static func compter(_ identifiantBundle: String, parmi identifiants: [String?]) -> Int {
        identifiants.filter { $0 == identifiantBundle }.count
    }

    private func lancees(_ identifiantBundle: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == identifiantBundle && !$0.isTerminated }
    }

    func instances(de identifiantBundle: String) -> Int {
        Self.compter(identifiantBundle, parmi: lancees(identifiantBundle).map(\.bundleIdentifier))
    }

    func demanderDeQuitter(_ identifiantBundle: String) -> Bool {
        let apps = lancees(identifiantBundle)
        guard !apps.isEmpty else { return true }
        // `terminate()` et jamais `forceTerminate()` : l'ancienne app se ferme proprement.
        return apps.map { $0.terminate() }.allSatisfy { $0 }
    }
}
