import Foundation
import MaillageCoeur

/// L'echelle du signal de la sonde Thread : des dBm.
public extension EchelleSignal {
    /// « −67 dBm » : graduations toutes les dizaines, 5 dB de marge autour des valeurs, aucune borne ; sans valeur,
    /// de -100 a -40 dBm. Bandes : la marge sur un bruit de fond de -100 dBm (comme les tables de diagnostic) ; plus de
    /// 20 dB, a -80 dBm et au-dessus, bonne ; plus de 10 dB, a -90 dBm et au-dessus, moyenne ; au-dessous, faible.
    static let dbm = EchelleSignal(unite: "dBm", uniteAvant: false, pas: 10, marge: 5, bornes: nil,
                                   domaineParDefaut: -100 ... -40, bandes: SeuilsBandes(bonne: -80, moyenne: -90))
}
