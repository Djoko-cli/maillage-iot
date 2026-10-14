import Testing
@testable import MaillageCoeur

@Suite("Graphe construit a la main, sans protocole")
struct GrapheManuelTests {
    @Test func noeudsEtParent() {
        let g = GrapheReseau(
            noeuds: [.init(id: "c", genre: .centre, partition: "p", routeur: true, bordure: true, inconnu: false),
                     .init(id: "a", genre: .appareil, partition: "p", routeur: false, bordure: false, inconnu: false)],
            liens: [.init(de: "a", vers: "c", genre: .parent, qualite: 3)])
        #expect(g.noeuds.map(\.id) == ["c", "a"])
        #expect(g.noeud("a")?.genre == .appareil)
        #expect(g.parent(de: "a") == "c")
    }

    /// Des noeuds et des liens deja faits : un lien dont un bout manque est ignore, la liste de liens est facultative.
    @Test func noeudsDejaFaits() {
        let n = [GrapheReseau.Noeud(id: "a", genre: .centre, partition: "p", routeur: true, bordure: false, inconnu: false),
                 GrapheReseau.Noeud(id: "b", genre: .appareil, partition: "p", routeur: false, bordure: false,
                                    inconnu: false)]
        let g = GrapheReseau(noeuds: n, liens: [GrapheReseau.Lien(de: "b", vers: "a", genre: .parent, qualite: 2),
                                                 GrapheReseau.Lien(de: "c", vers: "a", genre: .parent),
                                                 GrapheReseau.Lien(de: "a", vers: "d", genre: .radio)])
        #expect(g.liens.count == 1 && g.parent(de: "b") == "a" && g.parent(de: "a") == nil)
        #expect(GrapheReseau(noeuds: n).liens.isEmpty)
    }

    /// Le chemin d'un noeud : le premier lien `chemin` qui part de lui (son prochain saut) ; nil sans chemin, et les
    /// autres genres de lien ne comptent pas.
    @Test func cheminDUnNoeud() throws {
        func n(_ id: String) -> GrapheReseau.Noeud {
            .init(id: id, genre: .routeur, partition: "p", routeur: true, bordure: false, inconnu: false)
        }
        let g = GrapheReseau(noeuds: [n("a"), n("b"), n("c")], liens: [
            .init(de: "a", vers: "c", genre: .radio, qualite: 3),
            .init(de: "a", vers: "b", genre: .chemin, qualite: 2),
            .init(de: "a", vers: "c", genre: .chemin, qualite: 1),
            .init(de: "b", vers: "c", genre: .parent)])
        let c = try #require(g.chemin(de: "a"))
        #expect(c.vers == "b" && c.genre == .chemin && c.qualite == 2)
        #expect(g.chemin(de: "b") == nil && g.chemin(de: "c") == nil && g.chemin(de: "z") == nil)
    }

    /// Un lien suppose (chemin faute de route active, parent d'avant) : faux par defaut, porte par le lien.
    @Test func lienSuppose() {
        #expect(GrapheReseau.Lien(de: "a", vers: "b").suppose == false)
        let l = GrapheReseau.Lien(de: "a", vers: "b", genre: .chemin, qualite: 1, suppose: true)
        #expect(l.suppose && l != GrapheReseau.Lien(de: "a", vers: "b", genre: .chemin, qualite: 1))
    }

    /// Le nouvel etat d'un appareil s'ajoute sans changer les valeurs ecrites des autres.
    @Test func etatInjoignable() {
        #expect(EtatAffiche.injoignable.rawValue == "injoignable")
        #expect(EtatAffiche(rawValue: "partitionCoupee") == .partitionCoupee)
        #expect(AppareilAffiche(id: "x", nom: "X", etat: .injoignable).partition == nil)
    }
}
