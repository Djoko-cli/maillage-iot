import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Les identifiants de noeud de Thread (etape 3a, conception B) : le graphe emballe ses cles en `IdNoeud` Thread en
/// sortant du module, et les crochets de fiche et de focus ne regardent que les noeuds Thread, par leur cle.
@Suite("Thread : identifiants de noeud types")
struct IdNoeudThreadTests {
    /// Tout noeud et tout bout de lien du graphe Thread est un `IdNoeud` Thread, avec ou sans la sonde, et sur le releve
    /// reel (noeuds avec et sans partition, routeurs, appareils, inconnus de la sonde `rloc:...`).
    @Test(arguments: [false, true])
    func toutEstThread(sonde: Bool) throws {
        let g = try ScenePiecesThread.grapheThread(sonde: sonde)
        #expect(g.noeuds.allSatisfy { $0.id.protocole == .thread })
        #expect(g.liens.allSatisfy { $0.de.protocole == .thread && $0.vers.protocole == .thread })
        // Les cles ne changent pas : le module ne perd ni ne prefixe rien.
        #expect(g.noeuds.map(\.id.cle).contains("Apple TV") && g.noeuds.map(\.id.cle).contains("E000000000000004"))
        let releve = try #require(GrapheReseauTests.instantane.reseaux.first)
        let r = GrapheReseau(reseau: releve, appareils: GrapheReseauTests.affiches(GrapheReseauTests.instantane))
        #expect(r.noeuds.allSatisfy { $0.id.protocole == .thread && !$0.id.cle.hasPrefix("thread:") })
        #expect(r.liens.allSatisfy { $0.de.protocole == .thread && $0.vers.protocole == .thread })
        #expect(r.noeuds.contains { $0.partition.isEmpty }, "un noeud sans partition garde la partition vide, jamais prefixee")
    }

    /// Un graphe qui porte un noeud Zigbee de meme cle qu'un noeud Thread (un appareil a deux radios) : le focus de
    /// Thread ne voit que le noeud Thread, le noeud Zigbee n'a pas de focus Thread, et un chef d'un autre protocole
    /// ne couronne rien.
    @Test func focusIgnoreUnAutreProtocole() throws {
        let thread = try ScenePiecesThread.grapheThread(sonde: true)
        let cle = "E000000000000003"
        let z = GrapheReseau.Noeud(id: idz(cle), genre: .appareil, partition: "zigbee", routeur: false, bordure: false,
                                   inconnu: false)
        let g = GrapheReseau(noeuds: thread.noeuds + [z], liens: thread.liens)
        #expect(g.noeuds.count == thread.noeuds.count + 1, "deux noeuds de meme cle, un par protocole")
        // E...03 est l'enfant du HomePod ; le chef (Apple TV) s'ajoute par le lien radio direct vers le HomePod.
        let chef: Set<IdNoeud> = [idt("Apple TV")]
        let m = try #require(FocusThread.miseEnAvant(de: idt(cle), graphe: g, chefs: chef))
        #expect(m.noeuds == [idt(cle), idt("HomePod"), idt("Apple TV")], "le noeud Zigbee n'est pas mis en avant")
        #expect(FocusThread.miseEnAvant(de: idz(cle), graphe: g, chefs: chef) == nil)
        let faux = try #require(FocusThread.miseEnAvant(de: idt(cle), graphe: g, chefs: [idz("Apple TV")]))
        #expect(faux.noeuds == [idt(cle), idt("HomePod")], "un chef Zigbee ne couronne rien dans une partition de Thread")
    }

    /// La fiche : les voisins et les enfants d'un noeud Thread sortent en `IdNoeud` Thread ; un noeud d'un autre protocole,
    /// meme de meme cle, n'en a pas.
    @Test func ficheLitLaCleEtLeProtocole() async throws {
        let i = RapprochementTests.instantane()
        let r = try #require(i.reseaux.first)
        let m = MaillageAffiche(maillage: try await RapprochementTests.maillage(), reseau: r, appareils: i.appareils)
        let voisins = FicheThread.voisins(de: idt("E000000000000002"), maillage: m)
        #expect(voisins.map(\.id).contains(idt("E000000000000003")) && voisins.allSatisfy { $0.id.protocole == .thread })
        #expect(FicheThread.voisins(de: idz("E000000000000002"), maillage: m).isEmpty)
        let enfants = FicheThread.enfants(de: idt("E000000000000002"), maillage: m)
        #expect(enfants.map(\.id).contains(idt("E000000000000004")) && enfants.allSatisfy { $0.id.protocole == .thread })
        #expect(FicheThread.enfants(de: idz("E000000000000002"), maillage: m).isEmpty)
    }
}
