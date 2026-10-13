import Foundation

/// Noms de Maison du mode demo : inventes (ce ne sont pas les vrais noms de la
/// maison), attaches aux vrais noeuds du releve du 28/09 sur la fabrique
/// 30FC8F95E0E1A385, qui joue la fabrique d'Apple. Les pieces et les etages sont
/// ceux de la maquette de la vue par pieces, et, depuis le polissage C, les combles et
/// le jardin de sa maquette, remplis avec des noeuds de la demo (aucune donnee radio
/// nouvelle) ; les routeurs de bordure y sont des accessoires du nom de leur annonce,
/// qui leur donnent leur piece.
public enum NomsDemo {
    public static let fabrique = "30FC8F95E0E1A385"

    /// Hote -> (nom, piece, fabricant, modele, categorie).
    static let table: [String: (String, String, String, String, String)] = [
        "56B1E064401F74EF": ("Halo", "Bureau", "Djoko-CLI", "Pont ScreenBar Halo", "Ampoule"),
        "86E7BD1A75F28E6D": ("Nuki Ultra", "Entrée", "Nuki", "Smart Lock Ultra", "Serrure"),
        // Polissage C : un routeur dans la salle de jeux ; ses enfants : la lampe arcade (meme piece) et le capteur de
        // la salle de bain (un autre niveau).
        "02A8C3C5600F136B": ("Prise console", "Salle de jeux", "Eve Systems", "Eve Energy", "Prise"),
        "3A5DFAFCAB581AAF": ("Eve Motion", "Grenier", "Eve Systems", "Eve Motion", "Capteur"),
        // Polissage C : a l'abri, avec la vanne d'arrosage, les deux enfants du routeur de la terrasse.
        "C656F369B620027F": ("Capteur porte de l'abri", "Abri", "Aqara", "Door and Window Sensor P2", "Capteur"),
        "D661EE20B3E97C66": ("Thermo chambre", "Chambre", "Eve Systems", "Eve Thermo", "Thermostat"),
        "DAEF22ACB58F651C": ("Météo terrasse", "Terrasse", "Eve Systems", "Eve Weather", "Capteur"),
        // Polissage C : un routeur sur la terrasse.
        "0A84D1254BD246AD": ("Prise terrasse", "Terrasse", "Eve Systems", "Eve Energy Outdoor", "Prise"),
        // Polissage C : le grenier.
        "327DF9C45C82BBD6": ("Capteur d'humidité", "Grenier", "Aqara", "Climate Sensor W100", "Capteur"),
        "462DA5B311AFFCC7": ("Fenêtre chambre", "Chambre", "Aqara", "Door and Window Sensor P2", "Capteur"),
        "7A3D0C7512F8E0A5": ("Capteur salle de bain", "Salle de bain", "Aqara", "Climate Sensor W100", "Capteur"),
        "8A7E6F2665F737C6": ("Porte-fenêtre", "Salon", "Aqara", "Door and Window Sensor P2", "Capteur"),
        "9A5C1F9FDFAB242D": ("Détecteur de chaleur allée", "Grenier", "Aqara", "Smoke Detector", "Capteur"),
        "AA3D322B8A4500C4": ("Lampe arcade", "Salle de jeux", "Nanoleaf", "Essentials A19", "Ampoule"),
        "C663573E49A1EC90": ("Capteur de lucarne", "Salle de jeux", "Aqara", "Door and Window Sensor P2", "Capteur"),
        "46F77B36E071F8D0": ("Prise bureau", "Bureau", "Eve Systems", "Eve Energy", "Prise"),
        "7AF0B6D5006CF95F": ("Prise salon", "Salon", "Eve Systems", "Eve Energy", "Prise"),
        "82570DF21CF3784B": ("Vanne d'arrosage", "Abri", "Eve Systems", "Eve Aqua", "Vanne"),
        "724CC16B32D8F820": ("Volet salon", "Salon", "Nanoleaf", "Blinds", "Store"),
        "9A28601B74FF90A7": ("Lampe chambre d'amis", "Chambre d'amis", "Nanoleaf", "Essentials A19", "Ampoule"),
        "D6ECDD6EF9C0CB0C": ("Interrupteur cuisine", "Cuisine", "Eve Systems", "Eve Light Switch", "Interrupteur"),
        "FA15027BC681BB16": ("Ampoule entrée", "Entrée", "Nanoleaf", "Essentials A19", "Ampoule"),
        "C4299622387B": ("Passerelle salon", "Salon", "Eve Systems", "Eve Play", "Pont"),
        "C4E7AE91A29B": ("Prise Wi-Fi bureau", "Bureau", "Meross", "Smart Plug", "Prise"),
    ]

    /// Hote -> batterie : une faible par son niveau, une par l'alerte seule, deux non rechargeables (le detecteur de
    /// fumee, la vanne), un volet en charge ; ni prise, ni ampoule, ni concentrateur n'en a, sur secteur
    /// (`NomsTests.maisonDeDemo`).
    static let batteries: [String: BatterieMaison] = [
        "86E7BD1A75F28E6D": BatterieMaison(niveau: 52, charge: .horsCharge, alerte: false),
        "3A5DFAFCAB581AAF": BatterieMaison(niveau: 12, alerte: false),
        "C656F369B620027F": BatterieMaison(niveau: 45, alerte: false),
        "D661EE20B3E97C66": BatterieMaison(niveau: 40, alerte: false),
        "327DF9C45C82BBD6": BatterieMaison(niveau: 100, alerte: false),
        "462DA5B311AFFCC7": BatterieMaison(alerte: true),
        "9A5C1F9FDFAB242D": BatterieMaison(niveau: 97, charge: .nonRechargeable, alerte: false),
        "82570DF21CF3784B": BatterieMaison(niveau: 81, charge: .nonRechargeable, alerte: false),
        "724CC16B32D8F820": BatterieMaison(niveau: 64, charge: .enCharge, alerte: false),
    ]

    /// Routeurs de bordure (instance de l'annonce) -> (piece, fabricant, modele).
    static let routeurs: [String: (String, String, String)] = [
        "Apple TV 4K": ("Salon", "Apple", "Apple TV 4K"),
        "HomePod Palier": ("Salon", "Apple", "HomePod"),
        "HomePod Avant": ("Salon", "Apple", "HomePod"),
        "HomePod mini bureau": ("Bureau", "Apple", "HomePod mini"),
        "HomePod mini chambre": ("Chambre", "Apple", "HomePod mini"),
        "Aqara HubM100 #DFEB": ("Buanderie", "Aqara", "Hub M100"),
    ]

    /// Zones des maquettes, dans l'ordre de Maison : le rez-de-chaussee, le jardin, l'etage, les combles.
    public static let zones = [
        ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
        ZoneMaison(nom: "Jardin", pieces: ["Terrasse", "Abri"]),
        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
        ZoneMaison(nom: "Combles", pieces: ["Grenier", "Salle de jeux"]),
    ]

    public static let maison: NomsMaison = {
        var accessoires: [AccessoireMaison] = []
        for s in Releve20260928.annonces.matter {
            guard let i = InstanceMatter(instance: s.instance), i.fabrique == fabrique, let hote = s.hote else { continue }
            let id = Instantane.idAppareil(hote: hote, instance: s.instance)
            guard let e = table[id] else { continue }
            accessoires.append(AccessoireMaison(nom: e.0, piece: e.1, fabricant: e.2, modele: e.3,
                                                categorie: e.4, noeudMatter: i.noeud, batterie: batteries[id]))
        }
        for (nom, r) in routeurs {
            accessoires.append(AccessoireMaison(nom: nom, piece: r.0, fabricant: r.1, modele: r.2, categorie: "Concentrateur"))
        }
        // Dans le temps de la demo (la fin de la panne rejouee) : « releve il y a 5 minutes ».
        return NomsMaison(date: ScenarioPanne.fin.addingTimeInterval(-5 * 60), domicile: domicile,
                          accessoires: accessoires.sorted { $0.nom < $1.nom }, zones: zones)
    }()

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
