import Foundation

/// La cadence de l'horloge de la vue par pieces (performance, piste 1 du 25/10) : combien d'images la `TimelineView` en
/// demande. La rotation lente seule ne bouge la scene que de 0,1 degre par image a 30 images par seconde (un tour en
/// 120 s) : le cout de chaque image (dessin, rendu RenderBox, graphe de SwiftUI) est divise par deux sans que l'oeil le
/// voie. Des qu'autre chose bouge (un geste, un vol, un envol, un fondu, un glissement de disposition, une transition,
/// l'elan d'un geste, un survol qui change l'affichage), la vue a la pleine cadence de l'ecran, jusqu'a la fin de ce
/// mouvement. La rotation reste continue : son angle suit le temps (`MoteurPieces.avancer`), pas le nombre d'images.
enum CadenceHorloge: Equatable, Sendable {
    /// Aucune image : rien ne bouge, ou la fenetre n'est pas vue.
    case pause
    /// La rotation lente seule : 30 images par seconde.
    case plafonnee
    /// La cadence de l'ecran.
    case pleine

    /// Images par seconde de la cadence plafonnee.
    static let imagesParSecondePlafonnees = 30.0

    /// L'intervalle minimal entre deux images, pour la `TimelineView` (nil : celui de l'ecran).
    var intervalle: TimeInterval? {
        switch self {
        case .plafonnee: 1 / Self.imagesParSecondePlafonnees
        case .pause, .pleine: nil
        }
    }

    /// La cadence voulue : `enMarche`, l'horloge tourne (un mouvement en cours, dans une fenetre vue :
    /// `MoteurPieces.horlogeEnMarche`) ; `rotationSeule`, la rotation lente est le seul mouvement.
    static func decider(enMarche: Bool, rotationSeule: Bool) -> CadenceHorloge {
        guard enMarche else { return .pause }
        return rotationSeule ? .plafonnee : .pleine
    }
}
