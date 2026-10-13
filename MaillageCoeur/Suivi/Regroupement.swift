import Foundation

/// Ligne du journal affiche : un evenement, des pertes regroupees, ou les changements de parent
/// repetes d'un meme noeud.
public enum LigneJournal: Hashable, Sendable, Identifiable {
    case evenement(Evenement)
    /// Au moins 2 pertes dans une meme fenetre de 10 min, de la plus ancienne a la plus recente.
    case pertes([Evenement])
    /// Au moins 2 changements de parent d'un meme noeud dans une fenetre de 1 h, du plus ancien
    /// au plus recent.
    case parents([Evenement])

    public var id: String {
        switch self {
        case .evenement(let e): e.id
        case .pertes(let l): "pertes-" + (l.first?.id ?? "")
        case .parents(let l): "parents-" + (l.first?.id ?? "")
        }
    }

    /// Date de l'evenement, ou du plus recent du groupe.
    public var date: Date {
        switch self {
        case .evenement(let e): e.date
        case .pertes(let l), .parents(let l): l.last?.date ?? .distantPast
        }
    }

    public var evenements: [Evenement] {
        switch self {
        case .evenement(let e): [e]
        case .pertes(let l), .parents(let l): l
        }
    }

    public var gravite: Gravite { evenements.map(\.gravite).max() ?? .info }
}

/// Regroupement des pertes et des changements de parent pour l'affichage (le journal garde
/// chaque evenement).
public enum Regroupement {
    /// Fenetre de regroupement, comptee depuis la premiere perte.
    public static let fenetre: TimeInterval = 600
    /// Fenetre des changements de parent d'un meme noeud, comptee depuis le premier (spec de la
    /// sonde, section 6 : « X a change 4 fois de parent en 1 h »).
    public static let fenetreParents: TimeInterval = 3600

    /// Perte : un appareil joignable devient sans adresse, disparait, ou passe
    /// dans une partition coupee.
    public static func estPerte(_ e: Evenement) -> Bool {
        switch e.type {
        case .appareilDisparu, .appareilSansAdresse: true
        case .appareilChangePartition: e.details["coupee"] == "oui"
        default: false
        }
    }

    /// Lignes du journal, les plus recentes d'abord : les pertes survenues dans
    /// une meme fenetre de 10 min forment une seule ligne ; les changements de parent d'un meme
    /// noeud dans une fenetre de 1 h aussi.
    public static func lignes(_ evenements: [Evenement]) -> [LigneJournal] {
        let tries = evenements.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        var lignes: [LigneJournal] = []
        var groupe: [Evenement] = []
        // Changements de parent en cours de regroupement, par noeud : son ExtMac si l'evenement la
        // donne (l'id du sujet d'un enfant sans appareil change avec son parent), sinon l'id du sujet.
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
                lignes.append(.parents(g))
            } else if let e = g.first {
                lignes.append(.evenement(e))
            }
        }
        for e in tries {
            if estPerte(e) {
                if let premiere = groupe.first, e.date.timeIntervalSince(premiere.date) >= fenetre { fermer() }
                groupe.append(e)
            } else if e.type == .parentChange, let noeud = e.details["extMac"] ?? e.sujet?.id {
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
