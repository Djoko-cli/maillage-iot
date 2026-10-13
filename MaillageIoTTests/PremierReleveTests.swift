import Foundation
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Recenseur : moment du premier releve")
struct PremierReleveTests {
    /// `calme` : secondes depuis le dernier changement des navigateurs (2 : juste assez).
    private func du(_ secondes: Int, _ etat: Recenseur.Etat, routeur: Bool, calme: Int = 2) -> Bool {
        Recenseur.premierReleveDu(depuis: .seconds(secondes), etat: etat, routeurVu: routeur,
                                  calmeDepuis: .seconds(calme))
    }

    /// Premier releve : jamais avant 10 s ; des que l'ecoute est prete et qu'un
    /// routeur de bordure est liste ; au plus tard 60 s apres le demarrage.
    @Test func momentDuPremierReleve() {
        #expect(!du(5, .actif, routeur: true), "jamais avant la mise en route")
        #expect(du(10, .actif, routeur: true), "ecoute prete et routeur vu")
        #expect(!du(10, .actif, routeur: false), "aucun routeur vu : on attend")
        #expect(!du(10, .demarrage, routeur: true), "un navigateur n'est pas encore pret")
        #expect(!du(30, .reseauLocalRefuse, routeur: false), "invite ou refus : on attend")
        #expect(!du(59, .erreur("reseau coupe"), routeur: true))
        #expect(du(60, .demarrage, routeur: false), "au plus tard 60 s apres le demarrage")
        #expect(du(60, .reseauLocalRefuse, routeur: false))
        #expect(Recenseur.miseEnRoute == .seconds(10))
        #expect(Recenseur.attenteMax == .seconds(60))
    }

    /// Et seulement quand les annonces se sont calmees : aucun changement des
    /// navigateurs depuis 2 s (le 28/09, le premier releve est parti avec les
    /// 6 routeurs, pendant que les 57 resultats Matter arrivaient encore).
    @Test func calmeDesAnnonces() {
        #expect(!du(10, .actif, routeur: true, calme: 0), "une annonce vient d'arriver : on attend")
        #expect(!du(20, .actif, routeur: true, calme: 1), "les resultats arrivent encore")
        #expect(du(12, .actif, routeur: true, calme: 2), "2 s sans changement")
        #expect(!du(5, .actif, routeur: true, calme: 5), "calme, mais avant la mise en route")
        #expect(!du(30, .demarrage, routeur: true, calme: 20), "calme, mais un navigateur n'est pas pret")
        #expect(!du(30, .actif, routeur: false, calme: 20), "calme, mais aucun routeur vu")
        #expect(du(60, .actif, routeur: true, calme: 0), "au plus tard 60 s, meme sans calme")
        #expect(Recenseur.calme == .seconds(2))
    }
}
