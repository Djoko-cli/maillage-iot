import Foundation
import MaillageCoeur

/// Courbes d'un noeud tirees des releves de la sonde Zigbee : la qualite de ses liens (LQI d'origine compris), le LQI
/// que la sonde en recoit, ses changements de parent et de chemin vers le pont.
public extension CourbesNoeud {
    /// Courbes du noeud d'adresse longue `cle` dans `releves` (du plus ancien au plus recent), sur la periode qui finit
    /// a `fin`. Les prioritaires : le lien du chemin (vers le prochain saut, le plus recent d'abord ; pour un appareil
    /// final, vers son parent), puis ceux des dependants de la periode (routeurs dont il etait le prochain saut,
    /// appareils dont il etait le parent), du plus faible au meilleur en moyenne, puis par cle. Seules y sont les cles
    /// qui ont une courbe.
    init(cle: String, releves: [ReleveMaillageZigbee], periode: PeriodeCourbes, fin: Date) {
        let debut = fin.addingTimeInterval(-periode.duree)
        // Une mesure brute : sa date, sa valeur, et pour la qualite d'un lien, son LQI.
        var liens: [String: [(Date, Double, Double?)]] = [:]
        var signal: [(Date, Double, Double?)] = []
        var parents: [ChangementParent] = []
        var chemins: [ChangementParent] = []
        var parentsSonde: [ChangementParent] = []
        var dernierParent: String?
        var dernierProchain: String?
        var dernierParentSonde: String?
        var prochains: [String] = []
        var dependants: Set<String> = []
        func lqi(_ v: Int?) -> Double? { v.map(Double.init) }
        for r in releves where r.date >= debut && r.date <= fin {
            for l in r.liens {
                guard let autre = l.autre(que: cle), let q = l.qualite else { continue }
                liens[autre, default: []].append((r.date, Double(q), lqi([l.lqiA, l.lqiB].compactMap { $0 }.min())))
            }
            if let s = r.signaux.first(where: { $0.ieee == cle }) { signal.append((r.date, Double(s.lqi), nil)) }
            if let e = r.parents.first(where: { $0.enfant == cle }) {
                if let d = dernierParent, d != e.parent { parents.append(ChangementParent(date: r.date, parent: e.parent)) }
                dernierParent = e.parent
                if let q = e.qualite { liens[Self.cleParent, default: []].append((r.date, Double(q), lqi(e.lqi))) }
            }
            for e in r.parents where e.parent == cle && e.enfant != cle {
                dependants.insert(e.enfant)
                if let q = e.qualite { liens[e.enfant, default: []].append((r.date, Double(q), lqi(e.lqi))) }
            }
            if let c = r.chemins.first(where: { $0.routeur == cle }) {
                if let d = dernierProchain, d != c.prochain { chemins.append(ChangementParent(date: r.date, parent: c.prochain)) }
                dernierProchain = c.prochain
                prochains.removeAll { $0 == c.prochain }
                prochains.insert(c.prochain, at: 0)
            }
            for c in r.chemins where c.prochain == cle && c.routeur != cle { dependants.insert(c.routeur) }
            if let p = r.parentSonde {
                if let d = dernierParentSonde, d != p { parentsSonde.append(ChangementParent(date: r.date, parent: p)) }
                dernierParentSonde = p
            }
        }
        let courbes = liens.keys.sorted().map { CourbeLien(id: $0, points: Self.reduire(liens[$0] ?? [], pas: periode.pas)) }
        // Les prioritaires : le chemin, puis les dependants du plus faible au meilleur en moyenne.
        func moyenne(_ k: String) -> Double {
            guard let p = courbes.first(where: { $0.id == k })?.points, !p.isEmpty else { return .infinity }
            return p.map(\.valeur).reduce(0, +) / Double(p.count)
        }
        let avecCourbe = Set(courbes.map(\.id))
        let chemin = (dernierParent != nil ? [Self.cleParent] : prochains).filter { avecCourbe.contains($0) }
        let deps = dependants.subtracting(chemin).filter { avecCourbe.contains($0) }
            .map { (cle: $0, moyenne: moyenne($0)) }
            .sorted { ($0.moyenne, $0.cle) < ($1.moyenne, $1.cle) }
            .map { $0.cle }
        self.init(debut: debut, fin: fin, liens: courbes, parents: parents, chemins: chemins,
                  signal: Self.reduire(signal, pas: periode.pas), parentsSonde: parentsSonde,
                  prioritaires: chemin + deps)
    }
}
