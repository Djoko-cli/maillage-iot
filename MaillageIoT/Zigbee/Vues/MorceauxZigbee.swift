import MaillageCoeur
import ProtocoleZigbee
import SwiftUI

// La part de Zigbee des morceaux de la fenetre de la vue par pieces (la coque commune est `MorceauxFenetre` : la
// barre d'outils, la feuille « Renommer… », la place de la ligne de la tournee, l'indicateur du maillage incomplet). L'ecran d'attente
// (`EtatVide`) et le haut de la fenetre (`ContenuHaut`) choisissent, pour chaque protocole de la scene, le morceau qui lui
// revient.

/// Ligne de la tournee en cours de la sonde de Zigbee, en haut de la colonne de gauche (voir `LigneTournee` pour la
/// place qu'elle prend et garde) : vue a part, seule elle se redessine a chaque pas de la tournee.
struct LigneTourneeZigbee: View {
    @Environment(SondeMaillageZigbee.self) private var sonde

    /// Le premier pas d'une tournee, montre avant le premier avancement recu ; et celui du gabarit.
    static let premierPas = AvancementTourneeZigbee(etape: .etatSonde, fait: 0, total: 1)

    /// La ligne, cachee et sans horloge : sa place, de la taille de la ligne montree, que compte la marge du haut.
    static var gabarit: some View {
        IndicateurTourneeZigbee(avancement: premierPas, debut: nil)
            .hidden()
            .accessibilityHidden(true)
    }

    var body: some View {
        if let debut = sonde.debutTournee {
            IndicateurTourneeZigbee(avancement: sonde.avancement ?? Self.premierPas, debut: debut)
        }
    }
}

/// Tournee de la sonde de Zigbee en cours : un petit indicateur de progression et « Tables des routeurs · 12/26 ·
/// 0:42 », la duree a jour chaque seconde. Sans debut : la place de la ligne, sans horloge.
struct IndicateurTourneeZigbee: View {
    let avancement: AvancementTourneeZigbee
    let debut: Date?

    var body: some View {
        HStack(spacing: 6) {
            if avancement.total > 0 {
                ProgressView(value: Double(avancement.fait), total: Double(avancement.total))
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
            }
            // Largeur de la plus longue etape, compteur et duree compris : la capsule ne change
            // pas de taille d'une etape a l'autre (texte cale a gauche).
            ZStack(alignment: .leading) {
                ForEach(AvancementTourneeZigbee.Etape.allCases, id: \.self) { e in
                    Text(TexteTourneeZigbee.gabaritBarre(e)).hidden()
                }
                if let debut {
                    TimelineView(.periodic(from: debut, by: 1)) { contexte in
                        Text(TexteTourneeZigbee.barre(avancement, debut: debut, maintenant: contexte.date))
                    }
                }
            }
            .monospacedDigit()
        }
        .controlSize(.small)
        .piluleDuHaut()
    }
}

/// Ecran d'attente de Zigbee, quand il n'y a pas de reseau a dessiner : ni maillage, ni appareil du pont.
struct EtatVideZigbee: View {
    var body: some View {
        ContentUnavailableView {
            Label("En attente du maillage de la sonde", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Choisissez la sonde ou liez le pont Hue dans Réglages › Zigbee.")
        }
    }
}

/// Bandeau d'une maison dont le pont n'a encore donne aucune piece (spec de la vue par pieces, section 2.3) : chaque
/// routeur a sa carte, avec ses enfants.
struct BandeauSansPiecesZigbee: View {
    var body: some View {
        Label("Pas encore de pièces : le pont Hue les donnera", systemImage: "house")
            .piluleDuHaut()
    }
}
