import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// « Associer a un accessoire de Maison… », dans la fiche d'un appareil que Maison ne nomme pas : un menu des
/// accessoires de Maison « orphelins » (`Surveillance.accessoiresOrphelins` : leur noeud n'est annonce par personne,
/// et personne ne les a associes), dans le style de « Placer dans une piece… ». Choisir un accessoire donne son nom
/// et sa piece a l'appareil, comme s'il etait trouve par son noeud (`Surveillance.associer`). Sans accessoire a
/// proposer, le menu reste, un seul article grise le dit.
struct MenuAssocier: View {
    @Environment(Surveillance.self) private var surveillance
    let id: String

    /// Le bouton est dans la fiche d'un appareil que Maison ne nomme ni par son noeud ni par une association : un
    /// appareil Thread (ou sans adresse), et une lecture de Maison.
    static func propose(_ a: Appareil, dans s: Surveillance) -> Bool {
        a.genre != .ip && s.noms.maison != nil && s.accessoire(a) == nil
    }

    /// Une ligne du menu : le nom de l'accessoire, sa piece, son modele (sans ce qui manque).
    static func ligne(_ a: AccessoireMaison) -> String {
        [a.nom, a.piece, a.modele].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        let orphelins = surveillance.accessoiresOrphelins
        Menu("Associer à un accessoire de Maison…") {
            if orphelins.isEmpty {
                Button("Aucun accessoire de Maison à associer") {}
                    .disabled(true)
            } else {
                ForEach(orphelins, id: \.self) { a in
                    Button(Self.ligne(a)) { surveillance.associer(id, a: a) }
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }
}
