import Foundation

/// Noms de Maison du mode demo : inventes (ce ne sont pas les vrais noms de la
/// maison), attaches aux vrais noeuds du releve du 28/09 sur la fabrique
/// 30FC8F95E0E1A385, qui joue la fabrique d'Apple. Les pieces et les etages sont
/// ceux de la maquette de la vue par pieces, et, depuis le polissage C, les combles et
/// le jardin de sa maquette, remplis avec des noeuds de la demo (aucune donnee radio
/// nouvelle) ; les routeurs de bordure y sont des accessoires du nom de leur annonce,
/// qui leur donnent leur piece.
public enum NomsDemo {
    /// Zones des maquettes, dans l'ordre de Maison : le rez-de-chaussee, le jardin, l'etage, les combles.
    public static let zones = [
        ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
        ZoneMaison(nom: "Jardin", pieces: ["Terrasse", "Abri"]),
        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
        ZoneMaison(nom: "Combles", pieces: ["Grenier", "Salle de jeux"]),
    ]

    public static let domicile = "Maison (démo)"

    /// Le choix de niveau de la demo (polissage C, section 7) : le jardin au niveau du rez-de-chaussee, hors de la
    /// maison ; en memoire, la demo n'ecrivant rien. `dehors` : faux, dans la maison.
    public static func places(dehors: Bool = true) -> PlacesGardees {
        var p = PlacesGardees()
        p.ranger(Rangement(ordre: zones.map { "zone:" + $0.nom },
                           aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: dehors)]),
                 domicile: domicile)
        return p
    }
}
