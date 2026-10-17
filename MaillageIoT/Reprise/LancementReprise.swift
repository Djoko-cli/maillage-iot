import Foundation

// Phase 4, tache 7 : la reprise au lancement de l'app. La proposition du premier lancement (spec 4.3 : « Reprendre depuis
// Maillage Thread ou Zigbee… ») est faite une seule fois (drapeau dans les preferences), et seulement si aucun import n'a eu lieu.
// L'entree « Reprendre des donnees… » de Reglages > General reste toujours la.

enum LancementReprise {
    /// Le drapeau « la proposition a ete faite » (preferences de l'app).
    static let clePropositionFaite = "repriseProposee"

    /// Proposer la reprise ? Oui si elle ne l'a jamais ete et que `imports.json` ne contient aucun import. Un journal des imports
    /// illisible : non (on ne sait pas ce qui a ete repris ; l'entree des Reglages dit quoi faire).
    static func doitProposer(preferences: UserDefaults, dossierDonnees: URL) -> Bool {
        guard !preferences.bool(forKey: clePropositionFaite) else { return false }
        guard let journal = try? JournalImports.lire(dans: dossierDonnees) else { return false }
        return journal.imports.isEmpty
    }

    static func noterProposition(preferences: UserDefaults) {
        preferences.set(true, forKey: clePropositionFaite)
    }
}
