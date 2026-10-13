import Foundation

/// Courbes d'un noeud tirees des releves de la sonde Thread.
public extension CourbesNoeud {
    /// Courbes du noeud de cle `cle` dans `releves` (du plus ancien au plus recent), sur la
    /// periode qui finit a `fin`.
    init(cle: String, releves: [ReleveMaillage], periode: PeriodeCourbes, fin: Date) {
        self.init(cle: cle, releves: releves, cles: ClesHistorique(releves: releves), periode: periode, fin: fin)
    }

    /// De meme, avec la resolution des cles deja faite (`cles`, construite sur ces memes `releves`) : la
    /// surveillance la garde d'un calcul de la fiche a l'autre, tant que l'historique ne change pas.
    /// `trel` : ExtMac des routeurs qui annoncent TREL ; le lien entre deux d'entre eux n'a pas de courbe, comme il n'est
    /// pas dessine (carte radio seulement, `MaillageAffiche`).
    init(cle: String, releves: [ReleveMaillage], cles: ClesHistorique, periode: PeriodeCourbes, fin: Date,
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
        self.init(debut: debut, fin: fin,
                  liens: liens.keys.sorted().map { CourbeLien(id: $0, points: Self.reduire(liens[$0] ?? [], pas: periode.pas)) },
                  parents: parents, signal: Self.reduire(signal, pas: periode.pas), parentsSonde: parentsSonde,
                  prioritaires: parent + faiblesDabord(radio) + faiblesDabord(enfants.subtracting(radio)))
    }
}
