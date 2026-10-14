import Foundation
import Testing
@testable import MaillageIoT

@Suite("Demarrage de l'app (tests heberges)")
struct DemarrageTests {
    @Test func identite() {
        #expect(Bundle.main.bundleIdentifier == "fr.djoko.maillage.iot")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true, "app de la barre des menus")
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        #expect(services == Recenseur.types, "chaque type ecoute est declare (sinon le reseau local peut etre refuse)")
    }
}
