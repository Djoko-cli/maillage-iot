import Foundation

/// Ce que la fiche d'un noeud Thread range dans ses colonnes generiques (`ContenuFiche`) : ses voisins radio et ses
/// enfants, tires du maillage rapproche (la carte radio seulement : les liens entre deux routeurs TREL n'y sont pas).
public enum FicheThread {
    /// Les voisins radio du noeud `id` : l'autre bout de chacun de ses liens radio, avec sa qualite (la moins bonne des
    /// deux sens). Thread ne donne pas de LQI : le meme voisin n'apparait qu'une fois.
    public static func voisins(de id: String, maillage m: MaillageAffiche) -> [VoisinFiche] {
        var vus: Set<String> = []
        return m.liens.filter { $0.genre == .radio && ($0.de == id || $0.vers == id) }.compactMap { l in
            let autre = l.de == id ? l.vers : l.de
            return vus.insert(autre).inserted ? VoisinFiche(id: autre, qualite: l.qualite) : nil
        }
    }

    /// Les enfants du noeud `id` : ceux dont il est le parent, avec la qualite de leur lien vers lui.
    public static func enfants(de id: String, maillage m: MaillageAffiche) -> [DependantFiche] {
        m.liens.filter { $0.genre == .parent && $0.vers == id }.map {
            DependantFiche(id: $0.de, qualite: $0.qualite, routeur: false)
        }
    }
}
