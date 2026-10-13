import Foundation

/// Maillage de la sonde en mode demo : invente, sur les vrais noeuds du releve
/// du 28/09 (partition principale), pour voir les vrais liens sans sonde.
/// Les routeurs de bordure (par leur `xa`), dont le dernier muet ; deux
/// appareils qui routent ; les autres appareils joignables en enfants, repartis
/// entre eux, le premier etant la sonde ; un enfant que l'instantane ne connait pas.
public enum MaillageDemo {
    public static func maillage(_ i: Instantane, date: Date) -> Maillage? {
        maillage(i, date: date, sansIdentite: [])
    }

    /// Pour les tests seulement (hors de l'API publique) : `sansIdentite`, instances des routeurs
    /// de bordure que ce maillage laisse sans ExtMac, comme des routeurs que la sonde n'a jamais
    /// entendus (le BBR principal reste reconnu).
    static func maillage(_ i: Instantane, date: Date, sansIdentite: Set<String>) -> Maillage? {
        guard let p = i.reseaux.first?.principale else { return nil }
        var c = ConstructionMaillage(date: date, partition: p.id)
        let bordures = p.routeurs.filter { $0.adresseEtendue != nil }
        let appareils = i.appareils.filter { $0.partition == p.id && $0.etat == .joignable }.sorted { $0.id < $1.id }
        let qui = Array(appareils.prefix(2))
        let enfants = Array(appareils.dropFirst(2))
        // Identifiants de routeur : 1, 5, 9... ; le premier routeur de bordure est le chef.
        let ids = (0..<(bordures.count + qui.count)).map { 1 + 4 * $0 }
        guard let chef = ids.first else { return nil }
        c.routeurs(Route64(sequence: 1, routes: ids.map { RouteRouteur(idRouteur: $0, qualiteSortante: 0, qualiteEntrante: 0, cout: 1) }),
                   chef: chef)
        for (k, r) in bordures.enumerated() {
            if !sansIdentite.contains(r.instance) { c.identite(r.adresseEtendue!, routeur: ids[k]) }
            c.marquer(ids[k], bordure: true, bbrPrincipal: r.etat?.bbrPrimaire == true)
        }
        for (k, a) in qui.enumerated() { c.identite(a.id, routeur: ids[bordures.count + k]) }
        let muet = bordures.count > 1 ? ids[bordures.count - 1] : nil
        if let muet { c.muet(muet) }
        // Liens : le chef avec chacun ; chaque appareil qui route avec deux routeurs de bordure.
        let qualites = [3, 3, 2, 1]
        for (k, id) in ids.dropFirst().enumerated() where id != muet {
            c.lien(chef, id, sortante: qualites[k % 4], entrante: qualites[(k + 1) % 4])
        }
        for (k, a) in ids.suffix(qui.count).enumerated() where bordures.count > 1 {
            c.lien(a, ids[1 + k % (bordures.count - 1)], sortante: 2, entrante: 1)
        }
        // Enfants, a tour de role ; sous le routeur muet, resolus, sans qualite.
        for (k, a) in enfants.enumerated() {
            let parent = ids[k % ids.count]
            c.enfant(EnfantMaillage(rloc16: UInt16(parent) << 10 | UInt16(1 + k / ids.count), extMac: a.id,
                                    qualite: parent == muet ? nil : qualites[k % 4], endormi: a.endormi,
                                    source: k == 0 ? .sonde : parent == muet ? .resolution : .tableEnfants))
        }
        c.enfant(EnfantMaillage(rloc16: UInt16(chef) << 10 | 0x1F, extMac: "E0000000000000FF", qualite: 1, endormi: true,
                                source: .tableEnfants))
        return c.maillage()
    }
}
