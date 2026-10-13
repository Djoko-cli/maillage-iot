import Foundation

/// Ce qui reste net a la selection d'un noeud Thread : la part propre a Thread du mode focus, que le moteur generique
/// recoit (`MiseEnAvant`). Thread n'a ni chemin unique ni centre (le chef est elu, le maillage decentralise) : seuls des
/// liens reels sont mis en avant, jamais un chemin suppose (choix de Djoko du 09/10).
public enum FocusThread {
    /// La mise en avant du noeud `id` du graphe `g` : nil s'il n'y est pas. Restent nets :
    /// - le noeud lui-meme ;
    /// - son parent et son lien vers lui (ou son rattachement suppose) ;
    /// - ses enfants et leurs liens vers lui ;
    /// - si `voisins` est vrai, ses liens radio et ses voisins radio ;
    /// - le chef de sa partition (`chefs`, les noeuds couronnes), et le lien radio direct vers lui s'il existe : depuis
    ///   le noeud s'il route, sinon depuis son parent.
    public static func miseEnAvant(de id: String, graphe g: GrapheReseau, chefs: Set<String>,
                                   voisins: Bool = true) -> MiseEnAvant? {
        guard let n = g.noeud(id) else { return nil }
        var m = MiseEnAvant(noeuds: [id])
        // Ceux dont un lien radio direct vers le chef compte : le noeud s'il route, et son parent.
        var versLeChef: [String] = n.routeur ? [id] : []
        for l in g.liens {
            switch l.genre {
            case .parent, .rattachement:
                if l.de == id {
                    m.ajouter(lien: l.de, l.vers)
                    if l.genre == .parent { versLeChef.append(l.vers) }
                } else if l.vers == id {
                    m.ajouter(lien: l.de, l.vers)
                }
            case .radio where voisins && (l.de == id || l.vers == id):
                m.ajouter(lien: l.de, l.vers)
            default:
                break
            }
        }
        for c in chefs.sorted() where g.noeud(c)?.partition == n.partition {
            m.noeuds.insert(c)
            for r in versLeChef where r != c {
                let direct = g.liens.contains { $0.genre == .radio && Set([$0.de, $0.vers]) == [r, c] }
                if direct { m.ajouter(lien: r, c) }
            }
        }
        return m
    }
}
