import Foundation

/// Ligne du journal affiche : un evenement, des pertes regroupees, les changements de parent
/// repetes d'un meme noeud, ou les changements de chemin repetes d'un meme routeur.
public enum LigneJournal: Hashable, Sendable, Identifiable {
    case evenement(Evenement)
    /// Au moins 2 pertes dans une meme fenetre de 10 min, de la plus ancienne a la plus recente.
    case pertes([Evenement])
    /// Au moins 2 changements de parent d'un meme noeud dans une fenetre de 1 h, du plus ancien
    /// au plus recent.
    case parents([Evenement])
    /// Au moins 2 changements de chemin d'un meme routeur dans une fenetre de 1 h, du plus ancien au plus recent.
    case chemins([Evenement])

    public var id: String {
        switch self {
        case .evenement(let e): e.id
        case .pertes(let l): "pertes-" + (l.first?.id ?? "")
        case .parents(let l): "parents-" + (l.first?.id ?? "")
        case .chemins(let l): "chemins-" + (l.first?.id ?? "")
        }
    }

    /// Date de l'evenement, ou du plus recent du groupe.
    public var date: Date {
        switch self {
        case .evenement(let e): e.date
        case .pertes(let l), .parents(let l), .chemins(let l): l.last?.date ?? .distantPast
        }
    }

    public var evenements: [Evenement] {
        switch self {
        case .evenement(let e): [e]
        case .pertes(let l), .parents(let l), .chemins(let l): l
        }
    }

    public var gravite: Gravite { evenements.map(\.gravite).max() ?? .info }
}

/// Regroupement des pertes, des changements de parent et des changements de chemin pour l'affichage (le journal
/// garde chaque evenement).
public enum Regroupement {
    /// Fenetre de regroupement, comptee depuis la premiere perte.
    public static let fenetre: TimeInterval = 600
    /// Fenetre des changements de parent d'un meme noeud, comptee depuis le premier (spec de la
    /// sonde, section 6 : « X a change 4 fois de parent en 1 h »).
    public static let fenetreParents: TimeInterval = 3600

    /// Le genre (« parent » ou « chemin ») d'une cle de regroupement `<protocole>|<genre>|<cle>`.
    private static func genre(_ cle: String) -> Substring {
        cle.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)[1]
    }

    /// Lignes du journal, les plus recentes d'abord : les pertes survenues dans
    /// une meme fenetre de 10 min forment une seule ligne ; les changements de parent d'un meme
    /// noeud dans une fenetre de 1 h aussi, comme les changements de chemin d'un meme routeur.
    public static func lignes(_ evenements: [Evenement],
                              politique: any PolitiqueJournal) -> [LigneJournal] {
        let tries = evenements.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        var lignes: [LigneJournal] = []
        var groupe: [Evenement] = []
        // Changements de parent (ou de chemin) en cours de regroupement, par protocole, genre et noeud :
        // « <protocole>|parent|<cle> » ou « <protocole>|chemin|<cle> », la cle etant `politique.cleParent`. Deux
        // noeuds de deux protocoles qui ont la meme cle ne se regroupent jamais (sans protocole : Thread).
        var parents: [String: [Evenement]] = [:]
        func fermer() {
            if groupe.count >= 2 {
                lignes.append(.pertes(groupe))
            } else if let e = groupe.first {
                lignes.append(.evenement(e))
            }
            groupe = []
        }
        func fermerParents(_ noeud: String) {
            guard let g = parents.removeValue(forKey: noeud) else { return }
            if g.count >= 2 {
                lignes.append(genre(noeud) == "chemin" ? .chemins(g) : .parents(g))
            } else if let e = g.first {
                lignes.append(.evenement(e))
            }
        }
        for e in tries {
            if politique.estPerte(e) {
                if let premiere = groupe.first, e.date.timeIntervalSince(premiere.date) >= fenetre { fermer() }
                groupe.append(e)
            } else if let cle = politique.cleParent(e) {
                let noeud = "\((e.protocole ?? .thread).rawValue)|\(politique.estChemin(e) ? "chemin" : "parent")|\(cle)"
                if let premier = parents[noeud]?.first, e.date.timeIntervalSince(premier.date) >= fenetreParents {
                    fermerParents(noeud)
                }
                parents[noeud, default: []].append(e)
            } else {
                lignes.append(.evenement(e))
            }
        }
        fermer()
        for noeud in parents.keys.sorted() { fermerParents(noeud) }
        return lignes.enumerated().sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }.map(\.element)
    }
}
