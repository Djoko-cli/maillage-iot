import Foundation

/// Les relais d'une ligne de changements regroupes (repris de Maillage Zigbee, 09/10) : les parents par lesquels un
/// noeud est passe, et celui sur lequel il a fini.
public struct ResumeRelais: Hashable, Sendable {
    /// Les relais dans l'ordre ou le noeud y est passe, chacun une seule fois (a sa premiere apparition).
    public var relais: [String]
    /// Le relais du dernier changement : celui sur lequel le noeud finit ; nil sans changement lisible.
    public var dernier: String?

    public init(relais: [String], dernier: String?) {
        self.relais = relais
        self.dernier = dernier
    }

    /// Deux relais seulement, qui se partagent les changements : le noeud alterne de l'un a l'autre (« A ⇄ B »).
    public var alternent: Bool { relais.count == 2 }
}

extension Regroupement {
    /// Resume des changements `avant` → `apres` d'un meme noeud (les evenements d'une ligne `.parents`) :
    /// les relais dans l'ordre ou le noeud y est passe, sans doublon (l'ancien puis le nouveau relais de chaque
    /// changement, a leur premiere apparition), et le nouveau relais du dernier changement, dans l'ordre des dates (a date egale,
    /// celui des evenements donnes). Un nom absent ou vide est ignore.
    public static func resumeRelais(_ evenements: [Evenement]) -> ResumeRelais {
        let tries = evenements.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        var relais: [String] = []
        for nom in tries.flatMap({ [$0.avant, $0.apres] }) {
            if let nom, !nom.isEmpty, !relais.contains(nom) { relais.append(nom) }
        }
        let dernier = tries.last?.apres.flatMap { $0.isEmpty ? nil : $0 }
        return ResumeRelais(relais: relais, dernier: dernier)
    }
}
