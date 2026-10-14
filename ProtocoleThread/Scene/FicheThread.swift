import Foundation
import MaillageCoeur

/// Ce que la fiche d'un noeud Thread range dans ses colonnes generiques (`ContenuFiche`) : ses voisins radio et ses
/// enfants, tires du maillage rapproche (la carte radio seulement : les liens entre deux routeurs TREL n'y sont pas).
public enum FicheThread {
    /// Les voisins radio du noeud `id` : l'autre bout de chacun de ses liens radio, avec sa qualite (la moins bonne des
    /// deux sens). Thread ne donne pas de LQI : le meme voisin n'apparait qu'une fois. Vide pour un noeud d'un autre
    /// protocole ; le maillage Thread est lu par `id.cle`, ses voisins ressortent en `IdNoeud` Thread.
    public static func voisins(de id: IdNoeud, maillage m: MaillageAffiche) -> [VoisinFiche] {
        guard id.protocole == .thread else { return [] }
        var vus: Set<String> = []
        return m.liens.filter { $0.genre == .radio && ($0.de == id.cle || $0.vers == id.cle) }.compactMap { l in
            let autre = l.de == id.cle ? l.vers : l.de
            return vus.insert(autre).inserted ? VoisinFiche(id: IdNoeud(.thread, autre), qualite: l.qualite) : nil
        }
    }

    /// Les enfants du noeud `id` : ceux dont il est le parent, avec la qualite de leur lien vers lui.
    public static func enfants(de id: IdNoeud, maillage m: MaillageAffiche) -> [DependantFiche] {
        guard id.protocole == .thread else { return [] }
        return m.liens.filter { $0.genre == .parent && $0.vers == id.cle }.map {
            DependantFiche(id: IdNoeud(.thread, $0.de), qualite: $0.qualite, routeur: false)
        }
    }
}
