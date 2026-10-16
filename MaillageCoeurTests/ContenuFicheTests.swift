import Foundation
import Testing
@testable import MaillageCoeur

/// Le contenu generique de la fiche d'un noeud (repris de Maillage Zigbee, `FocusEtFicheTests`).
@Suite("Fiche : niveau de qualite d'un lien")
struct ContenuFicheTests {
    /// La bande d'une qualite de lien (0 a 3), une seule source pour la fiche et la legende : 3 bonne, 2 moyenne, 1 et 0
    /// faible (un LQI sous 50 est un lien reel, tres faible) ; inconnue sans mesure ou hors echelle.
    @Test func bandeDeQualite() {
        #expect(BandeQualite(3) == .bonne && BandeQualite(2) == .moyenne)
        #expect(BandeQualite(1) == .faible && BandeQualite(0) == .faible)
        #expect(BandeQualite(nil) == .inconnue && BandeQualite(4) == .inconnue && BandeQualite(-1) == .inconnue)
    }
}
