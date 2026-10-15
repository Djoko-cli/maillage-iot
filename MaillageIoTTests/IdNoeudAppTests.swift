import Foundation
@testable import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Les identifiants de noeud dans l'app Thread (etape 3a, conception B) : la scene, ses libelles et ses apparences sont
/// indexes par `IdNoeud` Thread ; l'argument de lancement `-selection` prend la forme texte ; un noeud d'un autre
/// protocole n'a ni fiche de Thread ni menu de piece de Thread.
@MainActor
@Suite("App Thread : identifiants de noeud types")
struct IdNoeudAppTests {
    /// La forme texte (`thread:<cle>`) se relit ; une cle brute, que les scripts de capture donnaient avant, est une cle de
    /// Thread ; les cles de Thread qui contiennent des `:` (`rloc:...`, `instance:...`) ne sont pas prises pour un protocole.
    @Test func argumentDeSelection() {
        #expect(FenetrePieces.selection(argument: nil) == nil && FenetrePieces.selection(argument: "") == nil)
        #expect(FenetrePieces.selection(argument: "thread:Apple TV 4K") == idt("Apple TV 4K"))
        #expect(FenetrePieces.selection(argument: "Apple TV 4K") == idt("Apple TV 4K"))
        #expect(FenetrePieces.selection(argument: "thread:rloc:B400") == idt("rloc:B400"))
        #expect(FenetrePieces.selection(argument: "rloc:B400") == idt("rloc:B400"))
        #expect(FenetrePieces.selection(argument: "instance:Salon") == idt("instance:Salon"))
        #expect(FenetrePieces.selection(argument: "zigbee:A1") == idz("A1"), "la forme texte nomme son protocole")
    }

    /// Tout ce que la scene d'un rendu indexe par noeud est un noeud Thread, et chaque noeud a son libelle, son
    /// apparence et son appareil par le meme `IdNoeud`.
    @Test func laSceneEstIndexeeParIdNoeud() throws {
        let (_, _, e) = try NomsSceneTests.demo()
        #expect(!e.scene.noeuds.isEmpty && e.scene.noeuds.allSatisfy { $0.id.protocole == .thread })
        #expect(e.scene.noeuds.allSatisfy { e.libelles[$0.id] != nil && e.apparences[$0.id] != nil })
        #expect(e.libelles.keys.allSatisfy { $0.protocole == .thread } && e.apparences.keys.allSatisfy { $0.protocole == .thread })
        #expect(e.appareils.keys.allSatisfy { $0.protocole == .thread } && e.chefs.allSatisfy { $0.protocole == .thread })
        #expect(Set(e.graphe.noeuds.map(\.id)) == Set(e.scene.noeuds.map(\.id)))
        // Le libelle de repli est la cle, jamais la forme texte.
        #expect(e.scene.noeuds.allSatisfy { !$0.libelle.hasPrefix("thread:") })
    }

    /// « Placer dans une piece… » ne regarde que les noeuds Thread : le meme texte sous un autre protocole n'a pas de
    /// menu, ni pour un routeur de bordure de l'instantane (sa cle est une instance Thread), ni pour un autre noeud.
    @Test func placementIgnoreUnAutreProtocole() throws {
        let (s, _) = try NomsSceneTests.demoAvecInconnus()
        let e = try #require(FenetrePiecesTests.entree(s))
        s.thread.oublierMaillage()
        for cle in ["rloc:041F", "HomePod Palier"] {
            #expect(PiecesChoisies.placement(idt(cle), dans: s, entree: e) != nil, "\(cle)")
            #expect(PiecesChoisies.placement(idt(cle, .zigbee), dans: s, entree: e) == nil, "\(cle) sous un autre protocole")
        }
    }

    /// La fiche couronne les noeuds couronnes de la scene, par `IdNoeud` : une cle de chef sous un autre protocole n'est
    /// pas couronnee.
    @Test func couronneParIdNoeud() throws {
        let (_, _, e) = try NomsSceneTests.demo()
        let chef = try #require(e.chefs.first)
        #expect(FicheNoeud.couronne(chef, entree: e))
        #expect(!FicheNoeud.couronne(IdNoeud(.zigbee, chef.cle), entree: e))
        #expect(!FicheNoeud.couronne(chef, entree: nil))
    }
}
