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
}
