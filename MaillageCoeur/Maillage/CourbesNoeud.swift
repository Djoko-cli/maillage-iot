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
/// deux releves, ou de trois pas) en commence un autre, pour ne pas relier par-dessus le trou.
public struct PointCourbe: Hashable, Sendable {
    public let date: Date
    public let valeur: Double
    public let troncon: Int

    public init(date: Date, valeur: Double, troncon: Int) {
        self.date = date
        self.valeur = valeur
        self.troncon = troncon
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
    public let signal: [PointCourbe]
    public let parentsSonde: [ChangementParent]
    /// Les courbes montrees d'abord (`ChoixCourbes`) : pour un enfant, celle vers son parent ; pour un routeur, ses liens
    /// radio, puis ses enfants, chacun du plus faible au meilleur en moyenne sur la periode, puis par cle : ce qui merite
    /// d'etre surveille passe dans les six.
    public let prioritaires: [String]

    /// La courbe de cle `cle` ; nil si elle n'existe pas.
    public func courbe(_ cle: String) -> CourbeLien? { liens.first { $0.id == cle } }

    public var estVide: Bool { liens.allSatisfy { $0.points.isEmpty } && parents.isEmpty && signal.isEmpty }

    /// Courbes du noeud de cle `cle` dans `releves` (du plus ancien au plus recent), sur la
    /// periode qui finit a `fin`.
    public init(cle: String, releves: [ReleveMaillage], periode: PeriodeCourbes, fin: Date) {
        self.init(cle: cle, releves: releves, cles: ClesHistorique(releves: releves), periode: periode, fin: fin)
    }

    /// De meme, avec la resolution des cles deja faite (`cles`, construite sur ces memes `releves`) : la
    /// surveillance la garde d'un calcul de la fiche a l'autre, tant que l'historique ne change pas.
    /// `trel` : ExtMac des routeurs qui annoncent TREL ; le lien entre deux d'entre eux n'a pas de courbe, comme il n'est
    /// pas dessine (carte radio seulement, `MaillageAffiche`).
    public init(cle: String, releves: [ReleveMaillage], cles: ClesHistorique, periode: PeriodeCourbes, fin: Date,
                trel: Set<String> = []) {
        let debut = fin.addingTimeInterval(-periode.duree)
        var liens: [String: [(Date, Double)]] = [:]
        var signal: [(Date, Double)] = []
        var parents: [ChangementParent] = []
        var parentsSonde: [ChangementParent] = []
        var dernierParent: String?
        var dernierParentSonde: String?
        var radio: Set<String> = [], enfants: Set<String> = []
        for (i, r) in releves.enumerated() where r.date >= debut && r.date <= fin {
            if let id = r.routeurs.first(where: { cles.cle(releve: i, routeur: $0.id) == cle })?.id {
                let extMacs = Dictionary(r.routeurs.compactMap { x in x.extMac.map { (x.id, $0.uppercased()) } },
                                         uniquingKeysWith: { a, _ in a })
                for l in r.liens where l.a == id || l.b == id {
                    guard let q = l.qualite else { continue }
                    if let a = extMacs[l.a], let b = extMacs[l.b], trel.contains(a), trel.contains(b) { continue }
                    let autre = cles.cle(releve: i, routeur: l.a == id ? l.b : l.a)
                    liens[autre, default: []].append((r.date, Double(q)))
                    radio.insert(autre)
                }
                // Ses enfants : la qualite de leur lien vers lui (la courbe de leurs dependants).
                for e in r.enfants where e.parent == id {
                    guard let q = e.qualite else { continue }
                    liens[e.extMac, default: []].append((r.date, Double(q)))
                    enfants.insert(e.extMac)
                }
                if let s = r.signaux.first(where: { $0.routeur == id }) { signal.append((r.date, Double(s.rssi))) }
            }
            if let e = r.enfants.first(where: { $0.extMac == cle }) {
                let p = cles.cle(releve: i, routeur: e.parent)
                if let d = dernierParent, d != p { parents.append(ChangementParent(date: r.date, parent: p)) }
                dernierParent = p
                if let q = e.qualite { liens[Self.cleParent, default: []].append((r.date, Double(q))) }
            }
            if let ps = r.parentSonde {
                let p = cles.cle(releve: i, routeur: ps)
                if let d = dernierParentSonde, d != p { parentsSonde.append(ChangementParent(date: r.date, parent: p)) }
                dernierParentSonde = p
            }
        }
        self.debut = debut
        self.fin = fin
        self.liens = liens.keys.sorted().map { CourbeLien(id: $0, points: Self.reduire(liens[$0] ?? [], pas: periode.pas)) }
        self.parents = parents
        self.signal = Self.reduire(signal, pas: periode.pas)
        self.parentsSonde = parentsSonde
        // Les prioritaires : le lien vers son parent (enfant) ; ses liens radio, puis ses enfants (routeur), du plus
        // faible au meilleur en moyenne.
        func faiblesDabord(_ k: Set<String>) -> [String] {
            k.map { c in
                let v = (liens[c] ?? []).map(\.1)
                return (cle: c, moyenne: v.reduce(0, +) / Double(max(1, v.count)))
            }
            .sorted { ($0.moyenne, $0.cle) < ($1.moyenne, $1.cle) }.map(\.cle)
        }
        let parent = liens[Self.cleParent] == nil ? [] : [Self.cleParent]
        prioritaires = parent + faiblesDabord(radio) + faiblesDabord(enfants.subtracting(radio))
    }

    /// Points d'une courbe : la moyenne de chaque pas (datee du debut du pas), ou chaque releve
    /// sans pas ; un ecart de plus de trois pas (20 min sans pas) entre deux points ouvre un
    /// nouveau troncon.
    static func reduire(_ bruts: [(Date, Double)], pas: TimeInterval?) -> [PointCourbe] {
        var points = bruts
        if let pas {
            var groupes: [(debut: Date, valeurs: [Double])] = []
            for (d, v) in bruts {
                let debut = Date(timeIntervalSince1970: (d.timeIntervalSince1970 / pas).rounded(.down) * pas)
                if groupes.last?.debut == debut {
                    groupes[groupes.count - 1].valeurs.append(v)
                } else {
                    groupes.append((debut, [v]))
                }
            }
            points = groupes.map { ($0.debut, $0.valeurs.reduce(0, +) / Double($0.valeurs.count)) }
        }
        let ecart = ecartTroncon(pas: pas)
        var troncon = 0
        var resultat: [PointCourbe] = []
        for (i, (d, v)) in points.enumerated() {
            if i > 0, d.timeIntervalSince(points[i - 1].0) > ecart { troncon += 1 }
            resultat.append(PointCourbe(date: d, valeur: v, troncon: troncon))
        }
        return resultat
    }
}
