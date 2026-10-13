import Foundation

/// Noeuds d'un maillage tels que le journal les nomme (id du noeud dans le graphe et nom
/// affiche), donnes par l'app a chaque tournee : les routeurs par identifiant, les enfants par
/// RLOC16.
public struct SujetsMaillage: Sendable {
    public var routeurs: [Int: Sujet]
    public var enfants: [UInt16: Sujet]

    public init(routeurs: [Int: Sujet] = [:], enfants: [UInt16: Sujet] = [:]) {
        self.routeurs = routeurs
        self.enfants = enfants
    }
}

/// Suit le maillage de la sonde de tournee en tournee et en tire les evenements du journal (spec
/// de la sonde, section 6), tous de la categorie « Autres changements » (pas de notification par
/// defaut) :
/// - un enfant identifie (ExtMac) vu sous un autre parent : « X a change de parent : A → B ». Un
///   enfant sans ExtMac n'est pas suivi : son RLOC16 change avec son parent. L'ExtMac de l'enfant
///   est dans `details["extMac"]` de ses evenements : son id de sujet, lui, peut changer avec son
///   parent (« rloc:XXXX » pour un enfant que le graphe ne rapproche d'aucun appareil) ;
/// - un enfant identifie absent de deux observations ou son absence est sure : « X n'a plus de
///   parent ». Elle l'est si son dernier parent a repondu (sa table des enfants est fraiche) ou
///   s'il a quitte la liste des routeurs : une absence par tournee. Elle l'est aussi si l'enfant
///   venait d'une resolution et que son parent est toujours muet (un routeur muet garde ses enfants
///   resolus jusqu'a la resolution suivante) : la resolution est reutilisee par toutes les tournees
///   jusqu'a la suivante, donc l'absence doit etre vue par deux resolutions distinctes, et non par
///   deux tournees (choix de Djoko, 30/09, pour le balayage qu'elle remplace : une resolution qui
///   rate un appareil ne suffit pas ; l'alerte vient apres 30 a 60 min). Sous un parent qui s'est tu
///   sans resolution, on ne sait pas. La sonde n'est jamais « sans parent » (detachee, elle ne rend
///   pas de maillage), ni un enfant devenu routeur ;
/// - un routeur hors routeurs de bordure qui entre dans la liste des routeurs, ou en sort.
/// Le premier maillage, et le premier d'une autre partition (les identifiants de routeur y sont
/// redistribues), sont un point de depart : aucun evenement.
public struct SuiviMaillage: Sendable {
    /// Absences sures avant « n'a plus de parent ».
    public static let absencesAvantPerte = 2

    private struct EtatEnfant: Sendable {
        var parent: Int
        var nomParent: String
        var sujet: Sujet
        var source: SourceEnfant
        var absences = 0
        var perdu = false
        /// Date de la resolution de la derniere absence comptee sous un parent muet.
        var resolutionComptee: Date?
    }

    private struct EtatRouteur: Sendable {
        var bordure: Bool
        var sujet: Sujet
    }

    private var partition: String?
    /// Enfants identifies, par ExtMac.
    private var enfants: [String: EtatEnfant] = [:]
    /// Routeurs de la derniere tournee, par identifiant.
    private var routeurs: [Int: EtatRouteur] = [:]

    public init() {}

    /// Evenements du maillage d'une tournee, dates du debut de la tournee (`Maillage.date`).
    public mutating func integrer(_ m: Maillage, sujets: SujetsMaillage) -> [Evenement] {
        func sujet(routeur id: Int) -> Sujet {
            let rloc = String(format: "%04X", UInt16(id) << 10)
            return sujets.routeurs[id] ?? Sujet(id: "rloc:" + rloc, nom: rloc)
        }
        var ev: [Evenement] = []
        if partition == m.partition {
            let ids = Set(m.routeurs.map(\.id))
            for r in m.routeurs where routeurs[r.id] == nil && !r.bordure {
                ev.append(Evenement(date: m.date, type: .routeurThreadApparu, sujet: sujet(routeur: r.id)))
            }
            for (id, r) in routeurs.sorted(by: { $0.key < $1.key }) where !ids.contains(id) && !r.bordure {
                ev.append(Evenement(date: m.date, type: .routeurThreadDisparu, sujet: r.sujet))
            }
        } else {
            partition = m.partition
            enfants = [:]
        }
        let presents = m.enfantsIdentifies
        for (ext, e) in presents.sorted(by: { $0.key < $1.key }) {
            let parent = sujet(routeur: e.parent)
            let s = sujets.enfants[e.rloc16] ?? Sujet(id: String(format: "rloc:%04X", e.rloc16), nom: ext)
            if let avant = enfants[ext], avant.parent != e.parent {
                ev.append(Evenement(date: m.date, type: .parentChange, sujet: s, avant: avant.nomParent, apres: parent.nom,
                                    details: ["extMac": ext]))
            }
            enfants[ext] = EtatEnfant(parent: e.parent, nomParent: parent.nom, sujet: s, source: e.source)
        }
        let parId = Dictionary(m.routeurs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let routeursExt = Set(m.routeurs.compactMap(\.extMac))
        for (ext, var e) in enfants.sorted(by: { $0.key < $1.key }) where presents[ext] == nil && !e.perdu {
            if routeursExt.contains(ext) {
                // Devenu routeur : son entree est dans la liste des routeurs.
                enfants[ext] = nil
                continue
            }
            let parent = parId[e.parent]
            guard e.source != .sonde, parent == nil || parent?.muet == false || e.source == .resolution else { continue }
            if parent?.muet == true {
                // Parent toujours dans la liste et muet : l'absence ne vient que de la resolution, reutilisee
                // par chaque tournee jusqu'a la suivante ; elle ne compte qu'une fois par resolution.
                guard let resolution = m.resolution, resolution != e.resolutionComptee else { continue }
                e.resolutionComptee = resolution
            }
            e.absences += 1
            if e.absences >= Self.absencesAvantPerte {
                e.perdu = true
                ev.append(Evenement(date: m.date, type: .sansParent, sujet: e.sujet, avant: e.nomParent,
                                    details: ["extMac": ext]))
            }
            enfants[ext] = e
        }
        routeurs = Dictionary(m.routeurs.map { ($0.id, EtatRouteur(bordure: $0.bordure, sujet: sujet(routeur: $0.id))) },
                              uniquingKeysWith: { a, _ in a })
        return ev
    }
}
