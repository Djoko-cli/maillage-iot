import Foundation
import Testing
@testable import MaillageCoeur

/// Le lexique de la maison : le genre, l'elision et le pluriel se lisent dans la table, jamais devines (l'accord
/// automatique d'Apple ne connait pas le genre des noms courants, essai du 20/10).
@Suite("Lexique de la maison : genre, elision, pluriel")
struct LexiqueMaisonTests {
    static func appareil(_ mot: String) -> MotMaison? { LexiqueMaison.appareils.first { $0.singulier == mot } }
    static func piece(_ mot: String) -> MotMaison? { LexiqueMaison.pieces.first { $0.singulier == mot } }

    @Test func tailleEtUnicite() {
        #expect(LexiqueMaison.appareils.count >= 80, "\(LexiqueMaison.appareils.count) appareils")
        #expect(LexiqueMaison.pieces.count >= 50, "\(LexiqueMaison.pieces.count) pieces")
        for liste in [LexiqueMaison.appareils, LexiqueMaison.pieces] {
            let cles = liste.map(\.singulier)
            #expect(Set(cles).count == cles.count, "mot en double : \(cles.filter { c in cles.filter { $0 == c }.count > 1 })")
            for m in liste {
                #expect(m.singulier == m.singulier.trimmingCharacters(in: .whitespaces) && !m.singulier.contains(" "), "\(m.singulier)")
                #expect(!m.pluriel.isEmpty)
            }
        }
    }

    @Test func genreDesAppareils() {
        let feminins = ["lampe", "ampoule", "prise", "télécommande", "porte", "fenêtre", "serrure", "enceinte", "suspension",
                        "guirlande", "applique", "vanne", "sonnette", "caméra", "veilleuse", "lumière", "sirène", "box"]
        let masculins = ["capteur", "détecteur", "interrupteur", "bouton", "variateur", "volet", "store", "thermostat",
                         "ruban", "plafonnier", "lampadaire", "spot", "radiateur", "routeur", "pont", "relais", "module"]
        for m in feminins { #expect(Self.appareil(m)?.genre == .feminin, "\(m)") }
        for m in masculins { #expect(Self.appareil(m)?.genre == .masculin, "\(m)") }
    }

    @Test func genreDesPieces() {
        let feminins = ["cuisine", "entrée", "chambre", "salle", "buanderie", "cave", "terrasse", "véranda", "toilettes"]
        let masculins = ["bureau", "salon", "séjour", "grenier", "garage", "cellier", "dressing", "couloir", "dégagement",
                         "palier", "sous-sol", "balcon", "jardin", "abri", "étage", "rangement", "atelier", "WC", "combles"]
        for m in feminins { #expect(Self.piece(m)?.genre == .feminin, "\(m)") }
        for m in masculins { #expect(Self.piece(m)?.genre == .masculin, "\(m)") }
    }

    /// Voyelle ou h muet : elision ; h aspire : pas d'elision ; consonne : pas d'elision.
    @Test func elision() {
        for m in ["interrupteur", "ampoule", "applique", "enceinte", "horloge", "humidificateur", "écran", "ordinateur"] {
            #expect(Self.appareil(m)?.elision == true, "\(m)")
        }
        for m in ["lampe", "capteur", "volet", "hub", "hotte", "haut-parleur"] {
            #expect(Self.appareil(m)?.elision == false, "\(m)")
        }
        for m in ["entrée", "atelier", "abri", "étage", "arrière-cuisine", "office"] {
            #expect(Self.piece(m)?.elision == true, "\(m)")
        }
        for m in ["bureau", "cuisine", "hall", "salon"] { #expect(Self.piece(m)?.elision == false, "\(m)") }
    }

    @Test func pluriel() {
        #expect(Self.appareil("volet")?.pluriel == "volets")
        #expect(Self.appareil("rideau")?.pluriel == "rideaux")
        #expect(Self.appareil("relais")?.pluriel == "relais", "invariable")
        #expect(Self.appareil("lave-linge")?.pluriel == "lave-linge")
        #expect(Self.piece("bureau")?.pluriel == "bureaux")
        #expect(Self.piece("combles")?.toujoursPluriel == true)
        #expect(Self.piece("toilettes")?.toujoursPluriel == true)
        #expect(Self.piece("WC")?.toujoursPluriel == true)
        #expect(Self.piece("salon")?.toujoursPluriel == false)
    }

    /// Pluriels irreguliers : « locaux », « rez-de-chaussee » invariable, et les composes de la maison.
    @Test func plurielsIrreguliers() {
        #expect(Self.piece("local")?.pluriel == "locaux")
        #expect(Self.piece("rez-de-chaussée")?.pluriel == "rez-de-chaussée", "invariable")
        #expect(Self.appareil("porte-fenêtre")?.pluriel == "portes-fenêtres")
        #expect(Self.appareil("radio-réveil")?.pluriel == "radios-réveils")
        #expect(Self.appareil("porte-fenêtre")?.genre == .feminin)
        #expect(Self.appareil("radio-réveil")?.genre == .masculin)
        #expect(Self.appareil("porte-serviettes")?.pluriel == "porte-serviettes")
    }

    /// Tout le lexique : un mot en -al, -au ou -eu ne prend pas un simple s (« locals », « rideaus »).
    @Test func aucunPlurielEnSDeTrop() {
        for m in LexiqueMaison.appareils + LexiqueMaison.pieces where !m.toujoursPluriel {
            guard ["al", "au", "eu"].contains(where: { m.singulier.hasSuffix($0) }) else { continue }
            #expect(m.pluriel != m.singulier + "s", "\(m.singulier) -> \(m.pluriel)")
        }
    }

    /// Un locatif propre a la piece quand « dans » serait faux : sur la terrasse, sur le balcon, a l'etage.
    @Test func locatif() {
        #expect(Self.piece("terrasse")?.locatif == .sur)
        #expect(Self.piece("balcon")?.locatif == .sur)
        #expect(Self.piece("palier")?.locatif == .sur)
        #expect(Self.piece("étage")?.locatif == .a)
        #expect(Self.piece("salon")?.locatif == .dans)
    }
}
