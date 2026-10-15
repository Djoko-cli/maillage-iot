import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Le signal vu par la sonde Thread, en dBm : l'instance `EchelleSignal.dbm` du protocole (le coeur teste ses reglages
/// avec une echelle d'essai de memes valeurs, `EchelleSignalTests`).
@Suite("Courbes Thread : echelle dBm et bandes")
struct EchelleSignalThreadTests {
    /// Les reglages de Thread : « dBm » apres la valeur, un pas de 10, une marge de 5, aucune borne.
    @Test func reglagesDeThread() {
        let e = EchelleSignal.dbm
        #expect(e.unite == "dBm" && !e.uniteAvant && e.pas == 10 && e.marge == 5 && e.bornes == nil)
    }

    /// La bande d'un signal en dBm : la marge sur un bruit de fond de -100 dBm (celle des tables de diagnostic) decide :
    /// plus de 20 dB (a -80 dBm et au-dessus) bonne, plus de 10 dB (a -90 dBm et au-dessus) moyenne, au-dessous faible.
    @Test func bandeDUnSignal() {
        let e = EchelleSignal.dbm
        #expect(e.bande(-55) == .bonne && e.bande(-80) == .bonne)
        #expect(e.bande(-81) == .moyenne && e.bande(-90) == .moyenne)
        #expect(e.bande(-91) == .faible && e.bande(-100) == .faible)
        #expect(e.bandes == SeuilsBandes(bonne: -80, moyenne: -90))
    }
}
