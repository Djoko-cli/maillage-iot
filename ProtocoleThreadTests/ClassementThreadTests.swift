import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

@Suite("Classement des noeuds Thread dans la vue par pieces")
struct ClassementThreadTests {
    private func noeud(_ genre: GrapheReseau.Genre, routeur: Bool, bordure: Bool) -> GrapheReseau.Noeud {
        GrapheReseau.Noeud(id: "N", genre: genre, partition: "P1", routeur: routeur, bordure: bordure, inconnu: false)
    }

    /// Routeur de bordure : rang 1, rayon 13 (15 pour le centre) ; autre routeur : rang 2, rayon 8 ; autre noeud :
    /// rang 3, rayon 7.
    @Test func rangsEtRayons() {
        let centre = classementThread(noeud(.centre, routeur: true, bordure: true))
        #expect(centre.rang == 1 && centre.rayon == 15)
        let bordure = classementThread(noeud(.routeur, routeur: true, bordure: true))
        #expect(bordure.rang == 1 && bordure.rayon == 13)
        let routeur = classementThread(noeud(.appareil, routeur: true, bordure: false))
        #expect(routeur.rang == 2 && routeur.rayon == 8)
        let appareil = classementThread(noeud(.appareil, routeur: false, bordure: false))
        #expect(appareil.rang == 3 && appareil.rayon == 7)
    }
}
