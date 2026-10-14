import Foundation
import MaillageCoeur

/// Construction du graphe d'un maillage Zigbee : le coeur ne connait que `init(noeuds:liens:)`. Les noeuds : le
/// coordinateur (le pont), les routeurs, les appareils finaux, les noeuds de type inconnu (chacun par adresse longue),
/// puis les appareils du pont absents du maillage (par id). Les liens : radio entre routeurs, de chaque appareil final
/// vers son parent, de chaque routeur vers son prochain saut vers le pont (son chemin).
public extension GrapheReseau {
    /// La partition de tous les noeuds : Zigbee n'en a pas, la scene garde le champ.
    static let partitionUnique = "zigbee"

    /// Le graphe d'un maillage (nil : pas de maillage, ou perime) et des appareils du pont (`id` : adresse longue).
    init(maillage m: MaillageZigbee?, appareils: [AppareilAffiche]) {
        var noeuds: [Noeud] = []
        var liens: [Lien] = []
        let connus = Set(appareils.map { $0.id.uppercased() })
        func rang(_ t: TypeNoeud) -> Int {
            switch t {
            case .coordinateur: 0
            case .routeur: 1
            case .final: 2
            case .inconnu: 3
            }
        }
        var presents = Set<String>()
        for n in (m?.noeuds ?? []).sorted(by: { (rang($0.type), $0.ieee) < (rang($1.type), $1.ieee) })
        where presents.insert(n.ieee).inserted {
            let genre: Genre = switch n.type {
            case .coordinateur: .centre
            case .routeur: .routeur
            case .final, .inconnu: .appareil
            }
            // Une cle provisoire (sans adresse longue) n'est pas une adresse longue : ni choix de piece, ni menu.
            noeuds.append(Noeud(id: n.ieee, genre: genre, routeur: n.route,
                                inconnu: !connus.contains(n.ieee.uppercased()) && n.ieee != m?.sonde,
                                extMac: n.ieeeConnue ? n.ieee : nil))
        }
        for a in appareils.sorted(by: { $0.id < $1.id }) where presents.insert(a.id).inserted {
            noeuds.append(Noeud(id: a.id, genre: .appareil, routeur: false, inconnu: false,
                                extMac: a.id.uppercased()))
        }
        if let m {
            for l in MaillageZigbee.reunir(m.liens) where presents.contains(l.a) && presents.contains(l.b) {
                liens.append(Lien(de: l.a, vers: l.b, genre: .radio, qualite: l.qualite))
            }
            for p in m.parents.sorted(by: { $0.enfant < $1.enfant })
            where presents.contains(p.enfant) && presents.contains(p.parent) {
                liens.append(Lien(de: p.enfant, vers: p.parent, genre: .parent, qualite: p.qualite, suppose: p.dAvant))
            }
            for c in m.chemins where presents.contains(c.routeur) && presents.contains(c.prochain) {
                liens.append(Lien(de: c.routeur, vers: c.prochain, genre: .chemin,
                                  qualite: m.lien(entre: c.routeur, et: c.prochain)?.qualite, suppose: c.suppose))
            }
        }
        self.init(noeuds: noeuds, liens: liens)
    }
}

public extension GrapheReseau.Noeud {
    /// Un noeud Zigbee : de la partition unique (`GrapheReseau.partitionUnique`), jamais routeur de bordure.
    init(id: String, genre: GrapheReseau.Genre, routeur: Bool, inconnu: Bool, extMac: String? = nil) {
        self.init(id: id, genre: genre, partition: GrapheReseau.partitionUnique, routeur: routeur, bordure: false,
                  inconnu: inconnu, extMac: extMac)
    }
}
