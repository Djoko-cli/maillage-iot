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
        // Les appareils d'un autre protocole ne sont pas des noeuds de Zigbee : leur cle y serait prise pour une adresse longue.
        let appareils = appareils.filter { $0.id.protocole == .zigbee }
        var noeuds: [Noeud] = []
        var liens: [Lien] = []
        let connus = Set(appareils.map { $0.id.cle.uppercased() })
        func rang(_ t: TypeNoeud) -> Int {
            switch t {
            case .coordinateur: 0
            case .routeur: 1
            case .final: 2
            case .inconnu: 3
            }
        }
        var presents = Set<IdNoeud>()
        for n in (m?.noeuds ?? []).sorted(by: { (rang($0.type), $0.ieee) < (rang($1.type), $1.ieee) })
        where presents.insert(IdNoeud(.zigbee, n.ieee)).inserted {
            let genre: Genre = switch n.type {
            case .coordinateur: .centre
            case .routeur: .routeur
            case .final, .inconnu: .appareil
            }
            // Une cle provisoire (sans adresse longue) n'est pas une adresse longue : ni choix de piece, ni menu.
            noeuds.append(Noeud(zigbee: n.ieee, genre: genre, routeur: n.route,
                                inconnu: !connus.contains(n.ieee.uppercased()) && n.ieee != m?.sonde,
                                extMac: n.ieeeConnue ? n.ieee : nil))
        }
        for a in appareils.sorted(by: { $0.id.cle < $1.id.cle }) where presents.insert(IdNoeud(.zigbee, a.id.cle)).inserted {
            noeuds.append(Noeud(zigbee: a.id.cle, genre: .appareil, routeur: false, inconnu: false,
                                extMac: a.id.cle.uppercased()))
        }
        if let m {
            func id(_ cle: String) -> IdNoeud { IdNoeud(.zigbee, cle) }
            for l in MaillageZigbee.reunir(m.liens) where presents.contains(id(l.a)) && presents.contains(id(l.b)) {
                liens.append(Lien(de: id(l.a), vers: id(l.b), genre: .radio, qualite: l.qualite))
            }
            for p in m.parents.sorted(by: { $0.enfant < $1.enfant })
            where presents.contains(id(p.enfant)) && presents.contains(id(p.parent)) {
                liens.append(Lien(de: id(p.enfant), vers: id(p.parent), genre: .parent, qualite: p.qualite, suppose: p.dAvant))
            }
            for c in m.chemins where presents.contains(id(c.routeur)) && presents.contains(id(c.prochain)) {
                liens.append(Lien(de: id(c.routeur), vers: id(c.prochain), genre: .chemin,
                                  qualite: m.lien(entre: c.routeur, et: c.prochain)?.qualite, suppose: c.suppose))
            }
        }
        self.init(noeuds: noeuds, liens: liens)
    }
}

public extension GrapheReseau.Noeud {
    /// Un noeud Zigbee : de la partition unique (`GrapheReseau.partitionUnique`), jamais routeur de bordure.
    init(zigbee cle: String, genre: GrapheReseau.Genre, routeur: Bool, inconnu: Bool, extMac: String? = nil) {
        self.init(id: IdNoeud(.zigbee, cle), genre: genre, partition: GrapheReseau.partitionUnique, routeur: routeur, bordure: false,
                  inconnu: inconnu, extMac: extMac)
    }
}
