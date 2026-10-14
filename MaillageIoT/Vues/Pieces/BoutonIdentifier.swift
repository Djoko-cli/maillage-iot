import MaillageCoeur
import SwiftUI

/// « Identifier », dans la fiche d'un appareil relie a un accessoire de Maison (par son noeud ou par une association a
/// la main) : le demon Passeur Noms appelle `identify()` sur l'accessoire, qui clignote ou emet un son. Grise sans
/// demon connecte, ou pour un accessoire sans `id` (releve d'avant le demon). Le resultat s'affiche quelques secondes
/// dessous. Les noms de Maison sont facultatifs dans l'environnement : les mesures de la fiche (`CapturesPieces`) et
/// plusieurs tests la rendent sans eux ; le bouton est alors grise.
struct BoutonIdentifier: View {
    @Environment(NomsPasseur.self) private var nomsMaison: NomsPasseur?
    let accessoire: AccessoireMaison

    nonisolated static func actif(connecte: Bool, accessoire: AccessoireMaison) -> Bool {
        connecte && accessoire.id != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("Identifier") {
                if let id = accessoire.id { nomsMaison?.identifier(accessoire: id) }
            }
            .boutonDeFiche()
            .disabled(!Self.actif(connecte: nomsMaison?.connecte == true, accessoire: accessoire))
            if let i = nomsMaison?.identification, i.accessoire == accessoire.id {
                Text(i.texte).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
