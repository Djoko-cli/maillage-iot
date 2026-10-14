import Foundation
import Testing
@testable import MaillageCoeur

/// Le contenu generique de la fiche d'un noeud (repris de Maillage Zigbee, `FocusEtFicheTests`).
@Suite("Fiche : niveau de qualite d'un lien")
struct ContenuFicheTests {
    /// Le niveau d'une qualite de lien (0 a 3), une seule source pour la fiche et la legende : 3 bonne, 2 moyenne, 1 et 0
    /// faible (un LQI sous 50 est un lien reel, tres faible) ; inconnue sans mesure ou hors echelle.
    @Test func niveauDeQualite() {
        #expect(NiveauQualite(3) == .bonne && NiveauQualite(2) == .moyenne)
        #expect(NiveauQualite(1) == .faible && NiveauQualite(0) == .faible)
        #expect(NiveauQualite(nil) == .inconnue && NiveauQualite(4) == .inconnue && NiveauQualite(-1) == .inconnue)
    }
}
