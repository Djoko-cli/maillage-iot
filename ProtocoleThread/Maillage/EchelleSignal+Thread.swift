import Foundation
import MaillageCoeur

/// L'echelle du signal de la sonde Thread : des dBm.
public extension EchelleSignal {
    /// « −67 dBm » : graduations toutes les dizaines, 5 dB de marge autour des valeurs, aucune borne ; sans valeur,
    /// de -100 a -40 dBm.
    static let dbm = EchelleSignal(unite: "dBm", uniteAvant: false, pas: 10, marge: 5, bornes: nil,
                                   domaineParDefaut: -100 ... -40)
}
