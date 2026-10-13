import Foundation

/// Le nom d'un accessoire tel que le releve le donne. Maison nomme une vignette unique d'apres son service, et
/// renommer cette vignette change le nom du service, pas celui de l'accessoire (banc du 13/10). Quand l'accessoire
/// a plusieurs vignettes, Maillage garde le nom de l'accessoire : un seul nom par noeud.
enum NomAccessoire {
    static func affiche(accessoire: String, tuiles: [String]) -> String {
        guard tuiles.count == 1, let tuile = tuiles.first,
              !tuile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return accessoire }
        return tuile
    }
}
