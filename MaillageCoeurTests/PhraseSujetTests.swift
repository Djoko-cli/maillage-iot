import Foundation
import Testing
@testable import MaillageCoeur

/// La phrase du sujet d'une ligne du journal : le nom du noeud avec sa piece, en francais naturel. Noms inventes.
@Suite("Phrase du sujet : le nom avec la piece")
struct PhraseSujetTests {
    static let verbe = "a perdu son parent"

    /// Le sujet suivi du verbe, en francais, en debut de phrase.
    static func fr(_ nom: String, _ piece: String?) -> String {
        PhraseSujet.de(nom: nom, piece: piece, langue: .francais).suivi(de: verbe)
    }

    // MARK: Nom qui contient la piece, mots connus

    @Test func nomQuiContientLaPiece() {
        #expect(Self.fr("Lampe bureau", "Bureau") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Capteur cuisine", "Cuisine") == "Le capteur de la cuisine a perdu son parent")
        #expect(Self.fr("Interrupteur entrée", "Entrée") == "L'interrupteur de l'entrée a perdu son parent")
        #expect(Self.fr("Volets chambre", "Chambre") == "Les volets de la chambre a perdu son parent")
    }

    @Test func contractionsEtElisions() {
        // de + le = du ; de + la ; de + l' ; de + les = des.
        #expect(Self.fr("Lampe salon", "Salon") == "La lampe du salon a perdu son parent")
        #expect(Self.fr("Lampe cuisine", "Cuisine") == "La lampe de la cuisine a perdu son parent")
        #expect(Self.fr("Lampe atelier", "Atelier") == "La lampe de l'atelier a perdu son parent")
        #expect(Self.fr("Volets combles", "Combles") == "Les volets des combles a perdu son parent")
        #expect(Self.fr("Prise toilettes", "Toilettes") == "La prise des toilettes a perdu son parent")
        // Elision de l'appareil (voyelle, h muet) et h aspire.
        #expect(Self.fr("Ampoule salon", "Salon") == "L'ampoule du salon a perdu son parent")
        #expect(Self.fr("Horloge cuisine", "Cuisine") == "L'horloge de la cuisine a perdu son parent")
        #expect(Self.fr("Hub salon", "Salon") == "Le hub du salon a perdu son parent")
        #expect(Self.fr("Lampe hall", "Hall") == "La lampe du hall a perdu son parent", "h aspire : du hall")
    }

    @Test func pluriels() {
        #expect(Self.fr("Volets chambre", "Chambre") == "Les volets de la chambre a perdu son parent")
        #expect(Self.fr("Volet chambre", "Chambre") == "Le volet de la chambre a perdu son parent")
        #expect(Self.fr("Spots bureau", "Bureau") == "Les spots du bureau a perdu son parent")
        #expect(Self.fr("Rideaux salon", "Salon") == "Les rideaux du salon a perdu son parent")
        #expect(Self.fr("Lampe bureaux", "Bureaux") == "La lampe des bureaux a perdu son parent")
    }

    /// Le mot de la piece peut venir avant, avec « de », « du », « dans la »... ou entre parentheses.
    @Test func formesDuNom() {
        #expect(Self.fr("Lampe du bureau", "Bureau") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Lampe de la cuisine", "Cuisine") == "La lampe de la cuisine a perdu son parent")
        #expect(Self.fr("Lampe dans l'entrée", "Entrée") == "La lampe de l'entrée a perdu son parent")
        #expect(Self.fr("La lampe du bureau", "Bureau") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Lampe (Bureau)", "Bureau") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Bureau - lampe", "Bureau") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Salon lampe", "Salon") == "La lampe du salon a perdu son parent")
    }

    @Test func sansCasseNiAccents() {
        #expect(Self.fr("LAMPE ENTREE", "Entrée") == "La lampe de l'entrée a perdu son parent")
        #expect(Self.fr("lampe entrée", "ENTREE") == "La lampe de l'entrée a perdu son parent")
        #expect(Self.fr("Lampe sejour", "Séjour") == "La lampe du séjour a perdu son parent")
    }

    /// Ce que le nom ajoute au mot de l'appareil est garde tel quel, avec sa casse.
    @Test func complementsGardes() {
        #expect(Self.fr("Lampe de chevet bureau", "Bureau") == "La lampe de chevet du bureau a perdu son parent")
        #expect(Self.fr("Lampe 2 bureau", "Bureau") == "La lampe 2 du bureau a perdu son parent")
        #expect(Self.fr("Lampe (droite) bureau", "Bureau") == "La lampe (droite) du bureau a perdu son parent")
        #expect(Self.fr("Lampe Zeta bureau", "Bureau") == "La lampe Zeta du bureau a perdu son parent")
        #expect(Self.fr("Détecteur de gaz cuisine", "Cuisine") == "Le détecteur de gaz de la cuisine a perdu son parent")
    }

    @Test func piecesAPlusieursMots() {
        #expect(Self.fr("Lampe salle de bain", "Salle de bain") == "La lampe de la salle de bain a perdu son parent")
        #expect(Self.fr("Lampe salle d'eau", "Salle d'eau") == "La lampe de la salle d'eau a perdu son parent")
        #expect(Self.fr("Prise salle à manger", "Salle à manger") == "La prise de la salle à manger a perdu son parent")
        #expect(Self.fr("Lampe sous-sol", "Sous-sol") == "La lampe du sous-sol a perdu son parent")
        #expect(Self.fr("Lampe chambre 2", "Chambre 2") == "La lampe de la chambre 2 a perdu son parent")
    }

    // MARK: Pieces et mots entiers

    /// « Salon de the » est une autre piece que « Salon » : jamais retire a tort.
    @Test func salonDeThe() {
        // La piece « Salon » n'est pas retiree de « Lampe Salon de thé » : le nom ne contient la piece qu'en partie.
        #expect(Self.fr("Lampe Salon de thé", "Salon") == "La lampe Salon de thé, dans le salon, a perdu son parent")
        // La piece « Salon de thé » complete est retiree.
        #expect(Self.fr("Applique salon de thé", "Salon de thé") == "L'applique du salon de thé a perdu son parent")
        // Un appareil nomme « Salon de the » dans la piece « Salon » : aucun mot d'appareil connu.
        #expect(Self.fr("Salon de thé", "Salon") == "Salon de thé, dans le salon, a perdu son parent")
    }

    @Test func motsEntiersSeulement() {
        // « salonique » ne contient pas le mot « salon » ; « bureautique » non plus.
        #expect(Self.fr("Lampe salonique", "Salon") == "La lampe salonique, dans le salon, a perdu son parent")
        #expect(Self.fr("Lampe bureautique", "Bureau") == "La lampe bureautique, dans le bureau, a perdu son parent")
    }

    // MARK: Nom sans la piece, piece connue

    @Test func nomSansLaPiece() {
        #expect(Self.fr("HomePod Avant", "Salon") == "HomePod Avant, dans le salon, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Cuisine") == "HomePod Avant, dans la cuisine, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Entrée") == "HomePod Avant, dans l'entrée, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Combles") == "HomePod Avant, dans les combles, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Salle de jeux") == "HomePod Avant, dans la salle de jeux, a perdu son parent")
    }

    /// Un mot d'appareil connu recoit son article, meme sans la piece dans le nom.
    @Test func appareilConnuSansLaPiece() {
        #expect(Self.fr("Lampe chevet", "Bureau") == "La lampe chevet, dans le bureau, a perdu son parent")
        #expect(Self.fr("Prise 3", "Cuisine") == "La prise 3, dans la cuisine, a perdu son parent")
    }

    /// « dans » ne va pas partout : sur la terrasse, sur le balcon, a l'etage.
    @Test func locatifsPropres() {
        #expect(Self.fr("HomePod Avant", "Terrasse") == "HomePod Avant, sur la terrasse, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Balcon") == "HomePod Avant, sur le balcon, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Étage") == "HomePod Avant, à l'étage, a perdu son parent")
        #expect(Self.fr("HomePod Avant", "Jardin") == "HomePod Avant, dans le jardin, a perdu son parent")
    }

    // MARK: Mot inconnu : aucun article invente

    @Test func motInconnu() {
        // Piece inconnue : le nom, un tiret, la piece, deux-points.
        #expect(Self.fr("Hue Go (droite)", "Zone Z7") == "Hue Go (droite) — Zone Z7 : a perdu son parent")
        // Appareil et piece inconnus, la piece dans le nom : le nom seul, sans article.
        #expect(Self.fr("Hue Go Zone Z7", "Zone Z7") == "Hue Go Zone Z7 a perdu son parent")
        // Piece inconnue, appareil connu : l'article de l'appareil, jamais celui de la piece.
        #expect(Self.fr("Lampe chevet", "Zone Z7") == "La lampe chevet — Zone Z7 : a perdu son parent")
        // Appareil inconnu, piece connue contenue dans le nom : le nom seul (il dit deja la piece).
        #expect(Self.fr("Hue Go bureau", "Bureau") == "Hue Go bureau a perdu son parent")
        // Appareil inconnu dans le nom avec la piece : pas d'article invente.
        #expect(Self.fr("Zeta bureau", "Bureau") == "Zeta bureau a perdu son parent")
    }

    @Test func sansPiece() {
        #expect(Self.fr("Lampe bureau", nil) == "Lampe bureau a perdu son parent")
        #expect(Self.fr("Lampe bureau", "") == "Lampe bureau a perdu son parent")
        #expect(Self.fr("Lampe bureau", "  ") == "Lampe bureau a perdu son parent")
        #expect(Self.fr("HomePod Avant", nil) == "HomePod Avant a perdu son parent")
    }

    // MARK: Majuscule, milieu de phrase

    @Test func majusculeEnDebutDePhrase() {
        #expect(PhraseSujet.de(nom: "lampe bureau", piece: "Bureau", langue: .francais).texte == "La lampe du bureau")
        #expect(PhraseSujet.de(nom: "interrupteur entrée", piece: "Entrée", langue: .francais).texte == "L'interrupteur de l'entrée")
        // Un nom propre (mot hors lexique) garde sa casse, aussi en tete.
        #expect(PhraseSujet.de(nom: "iPhone Zeta", piece: "Salon", langue: .francais).texte == "iPhone Zeta, dans le salon")
    }

    @Test func milieuDePhrase() {
        let m = PhraseSujet.de(nom: "Lampe bureau", piece: "Bureau", langue: .francais, debutDePhrase: false)
        #expect(m.texte == "la lampe du bureau")
        let n = PhraseSujet.de(nom: "HomePod Avant", piece: "Salon", langue: .francais, debutDePhrase: false)
        #expect(n.texte == "HomePod Avant, dans le salon", "le nom propre garde sa casse")
        #expect(n.suite == ",")
    }

    @Test func ponctuationDeLaSuite() {
        #expect(PhraseSujet.de(nom: "Lampe bureau", piece: "Bureau", langue: .francais).suite == "")
        #expect(PhraseSujet.de(nom: "HomePod Avant", piece: "Salon", langue: .francais).suite == ",")
        #expect(PhraseSujet.de(nom: "Hue Go", piece: "Zone Z7", langue: .francais).suite == " :")
        #expect(PhraseSujet.de(nom: "Lampe bureau", piece: nil, langue: .francais).suite == "")
    }

    @Test func casLimites() {
        #expect(Self.fr("Bureau", "Bureau") == "Bureau a perdu son parent", "le nom est la piece")
        #expect(Self.fr("", "Bureau") == " a perdu son parent", "nom vide : rien d'invente")
        #expect(Self.fr("  Lampe   bureau  ", "  Bureau ") == "La lampe du bureau a perdu son parent")
        #expect(Self.fr("Lampe bureau", "Bureau 2") == "La lampe bureau, dans le bureau 2, a perdu son parent")
    }

    /// Toutes les combinaisons du lexique : jamais « de le », « de les », « a le », « le a », « la a » ; l'elision et le
    /// pluriel sont ceux du mot.
    @Test func aucuneFauteDAccord() {
        let fautes = [" de le ", " de les ", " dans le les ", " à le ", " à les ", "de la entrée", "le entrée", "la entrée", "ee"]
        for a in LexiqueMaison.appareils {
            for p in LexiqueMaison.pieces where p.singulier != a.singulier {
                for (nom, piece) in [("\(a.singulier) \(p.singulier)", p.singulier), ("\(a.pluriel) \(p.singulier)", p.singulier)] {
                    let t = PhraseSujet.de(nom: nom, piece: piece, langue: .francais).suivi(de: "x")
                    #expect(t.first?.isUppercase == true, "\(t)")
                    #expect(t.contains(" du ") || t.contains(" de la ") || t.contains(" de l'") || t.contains(" des ")
                            || t.contains(" de l’"), "\(t)")
                    for f in fautes { #expect(!t.contains(f), "\(f) dans \(t)") }
                    #expect(!t.contains("l' ") && !t.contains("  "), "\(t)")
                }
            }
        }
    }

    // MARK: Anglais

    @Test func anglais() {
        func en(_ nom: String, _ piece: String?) -> String {
            PhraseSujet.de(nom: nom, piece: piece, langue: .anglais).suivi(de: "lost its parent")
        }
        #expect(en("Desk lamp", "Office") == "Desk lamp (Office) lost its parent")
        #expect(en("Desk lamp", nil) == "Desk lamp lost its parent")
        #expect(en("Desk lamp (Office)", "Office") == "Desk lamp (Office) lost its parent", "la piece deja dans le nom")
        #expect(en("Lampe bureau", "Bureau") == "Lampe bureau lost its parent", "pas d'accord en anglais")
    }

    @Test func codeDeLangue() {
        #expect(LangueSujet(code: "fr") == .francais)
        #expect(LangueSujet(code: "fr-FR") == .francais)
        #expect(LangueSujet(code: "en") == .anglais)
        #expect(LangueSujet(code: "de") == .anglais, "toute langue sans accord")
        #expect(LangueSujet(code: nil) == .anglais)
    }

    // MARK: Accord du verbe (tache 2 : « est apparue », « sont apparus »)

    static func accord(_ nom: String, _ piece: String?, _ langue: LangueSujet = .francais) -> AccordSujet {
        PhraseSujet.de(nom: nom, piece: piece, langue: langue).accord
    }

    /// Le genre et le nombre sont ceux du mot d'appareil, lus dans le lexique, quelle que soit la forme de la phrase.
    @Test func accordDuMotDAppareil() {
        #expect(Self.accord("Lampe bureau", "Bureau") == AccordSujet(feminin: true, pluriel: false))
        #expect(Self.accord("Capteur cuisine", "Cuisine") == AccordSujet(feminin: false, pluriel: false))
        #expect(Self.accord("Volets chambre", "Chambre") == AccordSujet(feminin: false, pluriel: true))
        #expect(Self.accord("Lampes bureau", "Bureau") == AccordSujet(feminin: true, pluriel: true))
        #expect(Self.accord("Prise toilettes", "Toilettes") == AccordSujet(feminin: true, pluriel: false), "le pluriel de la piece n'est pas celui du sujet")
        #expect(Self.accord("Ampoule salon", "Salon") == AccordSujet(feminin: true, pluriel: false))
        // Un mot d'appareil connu qui recoit son article hors de la forme « contient la piece ».
        #expect(Self.accord("Lampe chevet", "Bureau") == AccordSujet(feminin: true, pluriel: false))
        #expect(Self.accord("Volets chevet", "Zeta") == AccordSujet(feminin: false, pluriel: true), "piece inconnue, appareil connu")
    }

    /// Pas d'article, pas d'accord : le masculin singulier, comme le texte d'avant.
    @Test func accordParDefaut() {
        let defaut = AccordSujet()
        #expect(Self.accord("HomePod Avant", "Salon") == defaut, "mot inconnu")
        #expect(Self.accord("Hue Go (droite)", "Zone Z7") == defaut)
        #expect(Self.accord("Lampe bureau", nil) == defaut, "sans piece : le nom seul")
        #expect(Self.accord("Lampes bureau", "") == defaut)
        #expect(Self.accord("Lampe bureau", "Bureau", .anglais) == defaut, "l'anglais n'accorde pas")
        #expect(Self.accord("Petite lampe bureau", "Bureau") == defaut, "adjectif en tete : repli sans article")
    }
}
