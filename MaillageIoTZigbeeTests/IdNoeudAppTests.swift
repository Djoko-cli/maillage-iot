import Foundation
@testable import MaillageCoeur
import Testing
@testable import MaillageIoTZigbee

/// Les identifiants de noeud dans l'app de transition Zigbee (etape 3a, conception B) : la scene, ses libelles et ses
/// apparences sont indexes par `IdNoeud` Zigbee ; l'argument de lancement `-selection` prend la forme texte ; un noeud
/// d'un autre protocole n'a ni menu de piece, ni couronne.
@MainActor
@Suite("App Zigbee : identifiants de noeud types")
struct IdNoeudAppTests {
    typealias I = NomsDemo.Ieee

    /// La forme texte (`zigbee:<cle>`) se relit ; une adresse longue brute, que les scripts de capture donnaient avant, est
    /// une cle de Zigbee, comme une cle provisoire `~XXXX`.
    @Test func argumentDeSelection() {
        #expect(FenetrePieces.selection(argument: nil) == nil && FenetrePieces.selection(argument: "") == nil)
        #expect(FenetrePieces.selection(argument: "zigbee:\(I.pont)") == idz(I.pont))
        #expect(FenetrePieces.selection(argument: I.pont) == idz(I.pont))
        #expect(FenetrePieces.selection(argument: "~4F2A") == idz("~4F2A"))
        #expect(FenetrePieces.selection(argument: "thread:A1") == idt("A1"), "la forme texte nomme son protocole")
    }

    /// Tout ce que la scene d'un rendu indexe par noeud est un noeud Zigbee ; chaque noeud a son libelle, son apparence
    /// et son appareil (quand le pont en a un) par le meme `IdNoeud`, et le libelle de repli est la cle.
    @Test func laSceneEstIndexeeParIdNoeud() throws {
        let (_, e) = try NomsSceneTests.demo()
        #expect(!e.scene.noeuds.isEmpty && e.scene.noeuds.allSatisfy { $0.id.protocole == .zigbee })
        #expect(e.scene.noeuds.allSatisfy { e.libelles[$0.id] != nil && e.apparences[$0.id] != nil })
        #expect(e.libelles.keys.allSatisfy { $0.protocole == .zigbee } && e.apparences.keys.allSatisfy { $0.protocole == .zigbee })
        #expect(e.appareils.keys.allSatisfy { $0.protocole == .zigbee } && e.chefs == [idz(I.pont)])
        #expect(e.scene.noeuds.allSatisfy { !$0.libelle.hasPrefix("zigbee:") })
    }

    /// « Placer dans une piece… » et la couronne ne regardent que les noeuds Zigbee : le meme texte sous Thread n'a ni l'un
    /// ni l'autre.
    @Test func placementEtCouronneIgnorentUnAutreProtocole() throws {
        let (s, e) = try NomsSceneTests.demo()
        #expect(!FicheNoeud.couronne(idt(I.pont), entree: e) && FicheNoeud.couronne(idz(I.pont), entree: e))
        #expect(!FicheNoeud.renommable(idt(I.pont), entree: e) && FicheNoeud.renommable(idz(I.pont), entree: e))
        #expect(PiecesChoisies.placement(idt(I.sonde), dans: s, entree: e) == nil)
    }
}
