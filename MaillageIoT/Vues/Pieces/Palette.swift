import MaillageCoeur
import SwiftUI

/// Couleurs de la vue par pieces, en mode sombre (fond profond) et clair (fond pale).
struct Palette {
    let sombre: Bool

    var fond: Gradient {
        sombre ? Gradient(colors: [Color(red: 0.12, green: 0.23, blue: 0.54), Color(red: 0.06, green: 0.09, blue: 0.16),
                                   Color(red: 0.01, green: 0.02, blue: 0.09)])
               : Gradient(colors: [Color(red: 0.86, green: 0.91, blue: 1.0), Color(red: 0.95, green: 0.96, blue: 0.99),
                                   Color.white])
    }

    var selection: Color { sombre ? .white : .black }
    /// Pastille d'une batterie faible : orange vif en halo, texte brun fonce.
    var batterieFaible: Color { Color(red: 1.0, green: 0.62, blue: 0.1) }
    var texteBatterieFaible: Color { Color(red: 0.25, green: 0.12, blue: 0.0) }

    /// La qualite que la vue lit d'un lien de `protocole` : celle du module, sauf le 0 de Zigbee, un LQI sous 50, lien
    /// tres faible mais reel, qui se lit comme un lien faible (1) ; le 0 de Thread vaut « pas de lien » et reste gris.
    static func qualiteAffichee(_ qualite: Int?, protocole: Protocole) -> Int? {
        protocole == .zigbee && qualite == 0 ? 1 : qualite
    }

    /// La bande que la scene et la legende lisent d'un lien de `protocole` (`qualiteAffichee`) : celle de la fiche
    /// (`BandeQualite.init`), sauf le 0 de Thread, « pas de lien », qui reste inconnu (gris) ; la fiche le lit « faible ».
    static func bande(_ qualite: Int?, protocole: Protocole) -> BandeQualite {
        let q = qualiteAffichee(qualite, protocole: protocole)
        return q == 0 ? .inconnue : BandeQualite(q)
    }

    /// Lien de la sonde : vert, jaune, orange ; gris si la qualite est inconnue (parent muet). `protocole` : celui du lien
    /// (`qualiteAffichee`) ; Thread par defaut.
    func lienSonde(_ qualite: Int?, protocole: Protocole = .thread) -> Color {
        switch Self.bande(qualite, protocole: protocole) {
        case .bonne: Color(red: 0.29, green: 0.87, blue: 0.5)
        case .moyenne: Color(red: 0.98, green: 0.8, blue: 0.2)
        case .faible: .orange
        case .inconnue: sombre ? Color(white: 0.6) : Color(white: 0.5)
        }
    }

    /// Routeur que l'instantane ne connait pas (routeur de bordure muet sans identite).
    var routeurInconnu: Color { Color(white: 0.62) }

    func routeur(principale: Bool) -> Color {
        principale ? Color(red: 0.38, green: 0.65, blue: 0.98) : Color(red: 0.98, green: 0.75, blue: 0.14)
    }

    func appareil(_ e: EtatAffiche) -> Color {
        switch e {
        case .joignable: Color(red: 0.29, green: 0.87, blue: 0.5)
        case .partitionCoupee: .orange
        // `injoignable` (le pont le dit tel) : le rouge de Zigbee, celui du disparu ; Thread ne l'emet pas.
        case .sansAdresse, .injoignable, .disparu: Color(red: 0.97, green: 0.44, blue: 0.44)
        case .inconnu: .gray
        }
    }

    /// Anneau pointille d'un appareil joignable dont l'adresse n'est plus annoncee (variante B, choisie le 12/10) :
    /// rgb(232, 240, 90).
    var anneauVerifie: Color { Color(red: 232 / 255, green: 240 / 255, blue: 90 / 255) }

    // MARK: Vue par pieces (spec de la vue par pieces, sections 5 et 6)

    /// Couleur de zone de l'app (celle de la partition principale) : plateaux et noms d'etage.
    var zone: Color { Color(red: 0.23, green: 0.51, blue: 0.96) }
    /// Encre des liens enfant-parent et des rattachements (leur opacite vient de la scene).
    var encre: Color { sombre ? .white : .black }

    /// Teinte d'une piece (`ScenePieces.teintes`), eclairee ou non.
    static func couleur(_ t: Teinte) -> Color { Color(.sRGB, red: t.r, green: t.g, blue: t.b) }

    static func teintePiece(_ i: Int) -> Color {
        couleur(Teinte(hexa: ScenePieces.teintes[i % ScenePieces.teintes.count]))
    }

    /// Noms des appareils : blanc a 0,9 sur une pastille rgba(6, 10, 26, 0,72).
    var texteNom: Color { Color(white: 1, opacity: 0.9) }
    var fondNom: Color { Color(.sRGB, red: 6 / 255, green: 10 / 255, blue: 26 / 255, opacity: 0.72) }
    /// Noms des pieces : #eef3ff, compte #9fb0d0, sur rgba(14, 22, 48, 0,78).
    var texteNomPiece: Color { Color(.sRGB, red: 0xEE / 255, green: 0xF3 / 255, blue: 1) }
    var comptePiece: Color { Color(.sRGB, red: 0x9F / 255, green: 0xB0 / 255, blue: 0xD0 / 255) }
    var fondNomPiece: Color { Color(.sRGB, red: 14 / 255, green: 22 / 255, blue: 48 / 255, opacity: 0.78) }
    /// Reperes « ailleurs » : #b8c4dc sur rgba(6, 10, 26, 0,78), bordure en tirets a 0,5 ; fil vert.
    var texteAilleurs: Color { Color(.sRGB, red: 0xB8 / 255, green: 0xC4 / 255, blue: 0xDC / 255) }
    var fondAilleurs: Color { Color(.sRGB, red: 6 / 255, green: 10 / 255, blue: 26 / 255, opacity: 0.78) }
    var filAilleurs: Color { appareil(.joignable) }
    /// Traits de rappel des noms : rgba(230, 236, 250, 0,45).
    var trait: Color { Color(.sRGB, red: 230 / 255, green: 236 / 255, blue: 250 / 255, opacity: 0.45) }
    /// « ⌂ Maison » : blanc a 0,9, ombre noire.
    var texteMaison: Color { Color(white: 1, opacity: 0.9) }
    /// Sphere de la maison : lisere (0,55 ; 0,72 ; 1,0) et equateur #dfe6f3.
    var bulle: Color { Color(.sRGB, red: 0.55, green: 0.72, blue: 1.0) }
    var equateur: Color { Color(.sRGB, red: 0xDF / 255, green: 0xE6 / 255, blue: 0xF3 / 255) }

    // MARK: Legende (polissage B, section 2 ; maquette de la legende ; en verre depuis la verification du 02/10)

    /// Texte de la legende : blanc a 0,88 ; titres de ses groupes, gris bleute : rgb(148, 163, 190).
    static let texteLegende = Color(white: 1, opacity: 0.88)
    static let titreLegende = Color(.sRGB, red: 148 / 255, green: 163 / 255, blue: 190 / 255)

    /// Pastille du chef dans la fiche (maquette de la fiche) : capsule jaune a 0,16, filet jaune a 0,5 (le
    /// jaune des liens moyens, rgb(250, 204, 51)), texte rgb(253, 224, 120).
    static let jauneChef = Color(red: 0.98, green: 0.8, blue: 0.2)
    static let texteChef = Color(.sRGB, red: 253 / 255, green: 224 / 255, blue: 120 / 255)

    /// Lisere de la sphere : l'alpha de la maquette, force (0,02 + 0,45 (1 - |n.v|)^2,5), ou |n.v| vaut
    /// racine(1 - rho^2) a la distance rho du centre du disque ; echantillonne plus serre vers le bord.
    func degradeBulle(force: Double) -> Gradient {
        let rhos: [Double] = [0, 0.35, 0.55, 0.68, 0.77, 0.84, 0.89, 0.925, 0.95, 0.968, 0.98, 0.989, 0.995, 1]
        return Gradient(stops: rhos.map { rho in
            let f = pow(1 - (max(0, 1 - rho * rho)).squareRoot(), 2.5)
            return Gradient.Stop(color: bulle.opacity(force * (0.02 + 0.45 * f)), location: rho)
        })
    }
}
