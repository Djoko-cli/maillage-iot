import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// La batterie faible (`BatterieMaison.faible`) et le fichier des surnoms (`Surnoms`) sont testes au coeur
/// (`NomsTests.batterieFaible`, `NomsTests.fichierSurnoms`) : ils ne sont pas repris ici.
@Suite("Noms Zigbee : surnoms, noms du pont, adresse longue")
struct NomsZigbeeTests {
    typealias I = NomsDemo.Ieee

    /// Maison de demo : un faux reseau Hue ; chaque appareil a une adresse longue inventee (`A0000000000000xx`), une
    /// piece, et une pile s'il n'est pas sur secteur. Sans zones (le pont n'a pas d'etages) ; la maison etagee des
    /// essais de la vue range les memes pieces sur quatre etages, et son choix de niveau, en memoire, met le jardin a
    /// cote du rez-de-chaussee, hors de la maison.
    @Test func maisonDeDemo() {
        let m = NomsDemo.maisonPont
        #expect(m.accessoires.count == 21, "le pont, 13 lampes et prises, 7 appareils finaux")
        #expect(m.zones == nil && NomsDemo.maisonEtagee.zones == NomsDemo.zones)
        #expect(m.domicile == NomsDemo.domicile)
        #expect(m.accessoires.allSatisfy { ($0.ieee ?? "").hasPrefix("A0000000000000") && $0.ieee?.count == 16 })
        #expect(Set(m.accessoires.compactMap(\.ieee)).count == m.accessoires.count, "une adresse par appareil")
        #expect(Set(m.accessoires.compactMap(\.piece)) == Set(NomsDemo.zones.flatMap(\.pieces)))
        #expect(NomsDemo.placesEtagees().rangement(NomsDemo.domicile) == Rangement(ordre: [], aCote: [:]), "aucune place")
        #expect(NomsDemo.placesEtagees(etagee: true).rangement(NomsDemo.domicile)
                == Rangement(ordre: ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage", "zone:Combles"],
                             aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)]))
        #expect(NomsDemo.placesEtagees(etagee: true, dehors: false).rangement(NomsDemo.domicile).aCote["zone:Jardin"]?.dehors
                == false)
        // Sur secteur : ni lampe, ni prise, ni pont ne porte une pile.
        let surSecteur: Set<String> = ["Lampe", "Prise", "Pont"]
        let piles = m.accessoires.filter { surSecteur.contains($0.categorie ?? "") && $0.batterie != nil }.map(\.nom)
        #expect(piles.isEmpty, "sur secteur, sans pile : \(piles)")
        #expect(m.accessoires.filter { $0.batterie?.faible == true }.map(\.nom).sorted()
                == ["Capteur grenier", "Télécommande chambre"])
    }

    /// Le pont par l'adresse longue, sans egard a la casse.
    @Test func accessoireParAdresseLongue() {
        let m = NomsDemo.maisonPont
        #expect(m.accessoire(ieee: I.lampeBureau)?.nom == "Lampe bureau")
        #expect(m.accessoire(ieee: I.lampeArcade.lowercased())?.nom == "Lampe arcade")
        #expect(m.accessoire(ieee: I.sonde) == nil, "la sonde n'est pas un appareil du pont")
    }

    /// Priorite des noms : le surnom, puis le nom sur le pont, puis l'adresse longue ; un surnom vide est ignore.
    @Test func priorite() {
        #expect(ResolveurNomsZigbee().nom(ieee: I.lampeBureau) == I.lampeBureau, "l'adresse longue a defaut")
        #expect(ResolveurNomsZigbee().nomConnu(ieee: I.lampeBureau) == nil)
        let pont = ResolveurNomsZigbee(maison: NomsDemo.maisonPont)
        #expect(pont.nom(ieee: I.lampeBureau) == "Lampe bureau")
        #expect(pont.accessoire(ieee: I.lampeBureau)?.piece == "Bureau")
        let surnom = ResolveurNomsZigbee(surnoms: [I.lampeBureau: "Lampe de travail"], maison: NomsDemo.maisonPont)
        #expect(surnom.nom(ieee: I.lampeBureau) == "Lampe de travail")
        #expect(ResolveurNomsZigbee(surnoms: [I.lampeBureau: ""], maison: NomsDemo.maisonPont).nom(ieee: I.lampeBureau)
                == "Lampe bureau", "surnom vide ignore")
    }

    /// Le releve garde : il se relit tel quel ; une version plus recente est refusee.
    @Test func fichierNomsJSON() throws {
        let d = try NomsDemo.maisonPont.donnees()
        #expect(try NomsZigbee.lire(d) == NomsDemo.maisonPont)
        var futur = NomsDemo.maisonPont
        futur.version = 2
        #expect(throws: NomsZigbee.Erreur.versionTropRecente(2)) { try NomsZigbee.lire(try futur.donnees()) }
    }

    /// Les champs facultatifs (firmware, adresse longue, batterie, zones) : absents, ils se lisent nil ; presents, ils
    /// sont gardes. Sans zones, le champ n'est pas ecrit.
    @Test func contratChampsFacultatifs() throws {
        let nu = #"{"accessoires":[{"nom":"Lampe"}],"date":"2026-10-08T12:00:00.000Z","version":1}"#
        let a = try #require(try NomsZigbee.lire(Data(nu.utf8)).accessoires.first)
        #expect(a.firmware == nil && a.ieee == nil && a.batterie == nil)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let n = NomsZigbee(date: date, domicile: "Pont inventé", accessoires: [
            AppareilPont(nom: "Lampe", piece: "Salon", modele: "Hue", firmware: "1.4.2", ieee: "A0000000000000B1"),
            AppareilPont(nom: "Interrupteur", ieee: "A0000000000000B2", batterie: BatterieMaison(alerte: true)),
        ], zones: [ZoneMaison(nom: "Étage", pieces: ["Salon"])])
        #expect(try NomsZigbee.lire(try n.donnees()) == n)
        #expect(try NomsZigbee.lire(try NomsZigbee(date: date, zones: []).donnees()).zones == [])
        #expect(!String(decoding: try NomsZigbee(date: date).donnees(), as: UTF8.self).contains("zones"))
        #expect(NomsZigbee.versionActuelle == 1)
    }

    /// Un etat de charge inconnu (version plus recente) ne rend pas le releve illisible : seule la charge est perdue.
    @Test func chargeInconnue() throws {
        let json = #"{"accessoires":[{"batterie":{"charge":"sansFil","niveau":40},"nom":"Store"}],"date":"2026-09-28T12:00:00.000Z","version":1}"#
        #expect(try NomsZigbee.lire(Data(json.utf8)).accessoires.first?.batterie == BatterieMaison(niveau: 40))
    }
}
