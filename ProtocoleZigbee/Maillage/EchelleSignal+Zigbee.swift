import Foundation
import MaillageCoeur

/// L'echelle du signal de la sonde Zigbee : un LQI, de 0 a 255.
public extension EchelleSignal {
    /// « LQI 182 » : graduations tous les 50, 10 de marge autour des valeurs, dans 0 a 255 ; sans valeur, de 0 a 255.
    /// Bandes : les seuils de `QualiteLien` (170 et plus bonne, 100 et plus moyenne, au-dessous faible), une seule source.
    static let lqi = EchelleSignal(unite: "LQI", uniteAvant: true, pas: 50, marge: 10, bornes: 0...255,
                                   domaineParDefaut: 0...255,
                                   bandes: SeuilsBandes(bonne: Double(QualiteLien.seuilBonne),
                                                        moyenne: Double(QualiteLien.seuilMoyenne)))
}
