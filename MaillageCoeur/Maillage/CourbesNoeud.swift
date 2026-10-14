import Foundation

/// Periode des courbes de la fiche (spec de la sonde, section 6) : 24 h, 7 j ou 30 j.
public enum PeriodeCourbes: String, CaseIterable, Hashable, Sendable, Identifiable {
    case jour, semaine, mois

    public var id: String { rawValue }

    public var duree: TimeInterval {
        switch self {
        case .jour: 24 * 3600
        case .semaine: 7 * 24 * 3600
        case .mois: 30 * 24 * 3600
        }
    }

    /// Pas des points, moyenne des releves du pas : chaque releve sur 24 h (288 points), 30 min
    /// sur 7 j (336), 2 h sur 30 j (360) ; sans pas, 30 j de releves feraient 8 640 points.
    public var pas: TimeInterval? {
        switch self {
        case .jour: nil
        case .semaine: 1800
        case .mois: 7200
        }
    }

    /// Ecart de plus de ce temps entre deux releves d'une meme courbe : elle se coupe en troncons, c'est un trou
    /// (20 min sur 24 h, 90 min sur 7 j, 6 h sur 30 j).
    public var ecartTroncon: TimeInterval { CourbesNoeud.ecartTroncon(pas: pas) }
}

/// Point d'une courbe. `troncon` : numero du morceau de courbe ; un trou (plus de 20 min entre
/// deux releves, ou de trois pas) en commence un autre, pour ne pas relier par-dessus le trou. `lqi` : pour la courbe
/// d'un lien, la valeur d'origine d'ou vient sa qualite (le LQI, le moins bon des deux sens), lue au survol ; nil pour
/// une courbe sans valeur d'origine (le signal en dBm) ou sans mesure.
public struct PointCourbe: Hashable, Sendable {
    public let date: Date
    public let valeur: Double
    public let troncon: Int
    public let lqi: Double?

    public init(date: Date, valeur: Double, troncon: Int, lqi: Double? = nil) {
        self.date = date
        self.valeur = valeur
        self.troncon = troncon
        self.lqi = lqi
    }
}

/// Qualite d'un lien au fil du temps (0 a 3) : l'autre bout, par sa cle (ExtMac, "rloc:XXXX"),
/// ou `CourbesNoeud.cleParent` pour le lien d'un enfant vers son parent, quel qu'il soit.
public struct CourbeLien: Hashable, Sendable, Identifiable {
    public let id: String
    public let points: [PointCourbe]

    public init(id: String, points: [PointCourbe]) {
        self.id = id
        self.points = points
    }
}

/// Changement de parent : sa date (le premier releve sous le nouveau parent) et la cle du nouveau
/// parent.
public struct ChangementParent: Hashable, Sendable {
    public let date: Date
    public let parent: String

    public init(date: Date, parent: String) {
        self.date = date
        self.parent = parent
    }
}

/// Courbes d'un noeud tirees de l'historique (spec de la sonde, section 6), sur une periode :
/// - routeur : la qualite de chaque lien avec un routeur voisin, celle du lien de chacun de ses enfants vers lui
///   (reprise de Maillage Zigbee, 09/10), et le signal que la sonde en recoit (dBm), avec les changements de parent de
///   la sonde, car ce signal depend d'abord de l'endroit ou elle est posee ;
/// - enfant : la qualite du lien vers son parent (inconnue sous un routeur muet), avec ses
///   changements de parent.
/// Un noeud se reconnait d'un releve a l'autre par sa cle : son ExtMac, ou "rloc:XXXX" pour un
/// routeur sans ExtMac. Les cles des routeurs (le noeud, l'autre bout d'un lien, le parent d'un enfant
/// ou de la sonde) viennent de `ClesHistorique`, sur toute la liste des releves : un routeur dont la
/// sonde n'avait pas encore l'ExtMac garde une seule courbe, et sa fiche montre ses releves d'avant.
public struct CourbesNoeud: Hashable, Sendable {
    /// Cle de la courbe d'un enfant vers son parent.
    public static let cleParent = "parent"
    /// Trou le plus long entre deux releves d'une meme courbe (sans pas) : la tournee part 5 min
    /// apres la fin de la precedente ; au-dela de 20 min, il en manque.
    public static let ecartMax: TimeInterval = 20 * 60

    /// L'ecart qui coupe une courbe en troncons : trois pas, ou `ecartMax` sans pas.
    public static func ecartTroncon(pas: TimeInterval?) -> TimeInterval { pas.map { 3 * $0 } ?? ecartMax }

    public let debut: Date
    public let fin: Date
    /// Par cle de l'autre bout.
    public let liens: [CourbeLien]
    public let parents: [ChangementParent]
    /// Les changements de chemin d'un routeur (prochain saut vers le pont) ; vide pour un protocole sans chemins.
    public let chemins: [ChangementParent]
    public let signal: [PointCourbe]
    public let parentsSonde: [ChangementParent]
    /// Les courbes montrees d'abord (`ChoixCourbes`) : pour un enfant, celle vers son parent ; pour un routeur, ses liens
    /// radio, puis ses enfants, chacun du plus faible au meilleur en moyenne sur la periode, puis par cle : ce qui merite
    /// d'etre surveille passe dans les six.
    public let prioritaires: [String]

    public init(debut: Date, fin: Date, liens: [CourbeLien], parents: [ChangementParent],
                chemins: [ChangementParent] = [], signal: [PointCourbe],
                parentsSonde: [ChangementParent], prioritaires: [String]) {
        self.debut = debut
        self.fin = fin
        self.liens = liens
        self.parents = parents
        self.chemins = chemins
        self.signal = signal
        self.parentsSonde = parentsSonde
        self.prioritaires = prioritaires
    }

    /// La courbe de cle `cle` ; nil si elle n'existe pas.
    public func courbe(_ cle: String) -> CourbeLien? { liens.first { $0.id == cle } }

    public var estVide: Bool { liens.allSatisfy { $0.points.isEmpty } && parents.isEmpty && signal.isEmpty }

    /// Points d'une courbe de mesures sans valeur d'origine (`reduire(_:pas:)` a trois valeurs).
    public static func reduire(_ bruts: [(Date, Double)], pas: TimeInterval?) -> [PointCourbe] {
        reduire(bruts.map { ($0.0, $0.1, nil as Double?) }, pas: pas)
    }

    /// Points d'une courbe : la moyenne de chaque pas (datee du debut du pas, valeur d'origine comprise, sur ses mesures
    /// connues), ou chaque releve sans pas ; un ecart de plus de trois pas (20 min sans pas) entre deux points ouvre un
    /// nouveau troncon. Troisieme valeur : la valeur d'origine de la mesure (le LQI d'un lien), si on la connait.
    public static func reduire(_ bruts: [(Date, Double, Double?)], pas: TimeInterval?) -> [PointCourbe] {
        var points = bruts
        if let pas {
            var groupes: [(debut: Date, valeurs: [Double], lqis: [Double])] = []
            for (d, v, lqi) in bruts {
                let debut = Date(timeIntervalSince1970: (d.timeIntervalSince1970 / pas).rounded(.down) * pas)
                let lqis = lqi.map { [$0] } ?? []
                if groupes.last?.debut == debut {
                    groupes[groupes.count - 1].valeurs.append(v)
                    groupes[groupes.count - 1].lqis += lqis
                } else {
                    groupes.append((debut, [v], lqis))
                }
            }
            points = groupes.map { g in
                (g.debut, g.valeurs.reduce(0, +) / Double(g.valeurs.count),
                 g.lqis.isEmpty ? nil : g.lqis.reduce(0, +) / Double(g.lqis.count))
            }
        }
        let ecart = ecartTroncon(pas: pas)
        var troncon = 0
        var resultat: [PointCourbe] = []
        for (i, (d, v, lqi)) in points.enumerated() {
            if i > 0, d.timeIntervalSince(points[i - 1].0) > ecart { troncon += 1 }
            resultat.append(PointCourbe(date: d, valeur: v, troncon: troncon, lqi: lqi))
        }
        return resultat
    }
}
