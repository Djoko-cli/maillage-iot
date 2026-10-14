import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Noms : Maison, surnoms, batteries (coeur)")
struct NomsTests {
    @Test func noeudMatter() {
        #expect(AccessoireMaison.noeud(nil) == nil)
        #expect(AccessoireMaison.noeud(0) == nil, "accessoire non Matter")
        #expect(AccessoireMaison.noeud(0x4F63C86C) == "000000004F63C86C")
        #expect(AccessoireMaison.noeud(0xFEDCBA9876543210) == "FEDCBA9876543210")
    }

    /// Maison de demo : les zones et les pieces de la maquette de la vue par pieces, puis le jardin et les combles de
    /// la maquette des etages (polissage C). Son choix de niveau, en memoire : le jardin a cote du rez-de-chaussee, hors
    /// de la maison.
    @Test func zonesEtNiveauxDeDemo() {
        #expect(NomsDemo.zones == [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
                                   ZoneMaison(nom: "Jardin", pieces: ["Terrasse", "Abri"]),
                                   ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
                                   ZoneMaison(nom: "Combles", pieces: ["Grenier", "Salle de jeux"])])
        #expect(NomsDemo.places().rangement(NomsDemo.domicile)
                == Rangement(ordre: ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage", "zone:Combles"],
                             aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)]))
        #expect(NomsDemo.places(dehors: false).rangement(NomsDemo.domicile).aCote["zone:Jardin"]?.dehors == false)
    }

    /// `pont` est facultatif : un fichier sans ce champ se lit.
    @Test func contratSansPont() throws {
        let json = #"{"accessoires":[{"nom":"Halo","noeudMatter":"00000000000002E9"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        let n = try NomsMaison.lire(Data(json.utf8))
        #expect(n.accessoires.first?.pont == nil)
        #expect(n.accessoires.first?.noeudMatter == "00000000000002E9")
    }

    /// `firmware` est facultatif : un fichier ancien, sans ce champ, se lit ;
    /// un fichier qui l'a le garde.
    @Test func contratFirmware() throws {
        let ancien = #"{"accessoires":[{"nom":"Halo","noeudMatter":"00000000000002E9"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(ancien.utf8)).accessoires.first?.firmware == nil)
        let avec = #"{"accessoires":[{"firmware":"1.4.2","nom":"Halo","noeudMatter":"00000000000002E9"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(avec.utf8)).accessoires.first?.firmware == "1.4.2")
        let n = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000),
                           accessoires: [AccessoireMaison(nom: "Halo", modele: "Halo", firmware: "1.4.2")])
        #expect(try NomsMaison.lire(try n.donnees()) == n)
    }

    /// `batterie` est facultatif : un fichier ancien, sans ce champ, se lit ;
    /// un fichier qui l'a le garde.
    @Test func contratBatterie() throws {
        let ancien = #"{"accessoires":[{"nom":"Halo"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(ancien.utf8)).accessoires.first?.batterie == nil)
        let avec = #"{"accessoires":[{"batterie":{"alerte":false,"charge":"enCharge","niveau":81},"nom":"Store"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(avec.utf8)).accessoires.first?.batterie
                == BatterieMaison(niveau: 81, charge: .enCharge, alerte: false))
        let n = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Serrure", batterie: BatterieMaison(niveau: 52, charge: .horsCharge, alerte: false)),
            AccessoireMaison(nom: "Interrupteur", batterie: BatterieMaison(alerte: true)),
        ])
        #expect(try NomsMaison.lire(try n.donnees()) == n)
    }

    /// Un etat de charge inconnu (passeur plus recent que l'app) ne rend pas le
    /// fichier illisible : seule la charge est perdue.
    @Test func chargeInconnue() throws {
        let json = #"{"accessoires":[{"batterie":{"charge":"sansFil","niveau":40},"nom":"Store"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(json.utf8)).accessoires.first?.batterie == BatterieMaison(niveau: 40))
    }

    /// `zones` est facultatif : un fichier d'avant les zones se lit, sans zones ; un fichier qui
    /// les a les garde dans l'ordre de Maison, pieces comprises. Une maison sans zones donne une
    /// liste vide. Le champ est additif : la version ne change pas, et sans zones il n'est pas ecrit.
    @Test func contratZones() throws {
        let ancien = #"{"accessoires":[{"nom":"Halo","piece":"Bureau"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(ancien.utf8)).zones == nil)
        let avec = #"{"accessoires":[],"date":"2026-09-30T12:00:00.000Z","statut":"ok","version":1,"zones":[{"nom":"Étage","pieces":["Chambre","Bureau"]},{"nom":"Rez-de-chaussée","pieces":["Salon","Cuisine","Entrée"]}]}"#
        #expect(try NomsMaison.lire(Data(avec.utf8)).zones == [
            ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"]),
            ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée"]),
        ])
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(try NomsMaison.lire(try NomsMaison(date: date, zones: []).donnees()).zones == [])
        let n = NomsMaison(date: date, accessoires: [AccessoireMaison(nom: "Halo", piece: "Bureau")],
                           zones: [ZoneMaison(nom: "Étage", pieces: ["Bureau"])])
        #expect(try NomsMaison.lire(try n.donnees()) == n)
        #expect(NomsMaison.versionActuelle == 2)
        #expect(!String(decoding: try NomsMaison(date: date).donnees(), as: UTF8.self).contains("zones"))
    }

    /// Version 2 : l'identifiant HomeKit de chaque accessoire, que vise « Identifier ». Un releve de version 1 (sans
    /// `id`) se lit toujours ; `enVersion1` rend le format qu'attendent les anciennes apps (sans `id`).
    @Test func contratIdentifiant() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let id = "8D3C2A10-0000-4000-8000-000000000001"
        let n = NomsMaison(date: date, accessoires: [AccessoireMaison(nom: "Halo", id: id)])
        #expect(n.version == 2)
        #expect(String(decoding: try n.donnees(), as: UTF8.self).contains(#""id" : "\#(id)""#))
        #expect(try NomsMaison.lire(try n.donnees()) == n)
        let ancien = #"{"accessoires":[{"nom":"Halo"}],"date":"2026-09-28T12:00:00.000Z","statut":"ok","version":1}"#
        #expect(try NomsMaison.lire(Data(ancien.utf8)).accessoires.first?.id == nil)
        let v1 = n.enVersion1()
        #expect(v1.version == 1)
        #expect(v1.accessoires == [AccessoireMaison(nom: "Halo")])
        #expect(!String(decoding: try v1.donnees(), as: UTF8.self).contains(#""id""#))
        #expect(v1.date == n.date && v1.statut == n.statut)
    }

    /// Faible : l'accessoire le signale, ou son niveau est a 20 % ou moins.
    @Test func batterieFaible() {
        #expect(BatterieMaison(niveau: 20).faible)
        #expect(!BatterieMaison(niveau: 21).faible)
        #expect(BatterieMaison(niveau: 90, alerte: true).faible, "l'accessoire le signale")
        #expect(BatterieMaison(alerte: true).faible, "alerte sans niveau")
        #expect(!BatterieMaison(alerte: false).faible)
        #expect(!BatterieMaison().faible)
    }

    /// Valeurs de HomeKit (NSNumber) : niveau de 0 a 100 ; charge 0 (hors
    /// charge), 1 (en charge) ou 2 (non rechargeable) ; alerte 0 ou 1. Une
    /// valeur hors de ces bornes est ignoree ; rien de lisible : pas de batterie.
    @Test func batterieDepuisHomeKit() {
        #expect(BatterieMaison.depuisHomeKit(niveau: NSNumber(value: 99), charge: NSNumber(value: 0),
                                             alerte: NSNumber(value: 0))
                == BatterieMaison(niveau: 99, charge: .horsCharge, alerte: false))
        #expect(BatterieMaison.depuisHomeKit(niveau: nil, charge: NSNumber(value: 1), alerte: NSNumber(value: 1))
                == BatterieMaison(charge: .enCharge, alerte: true))
        #expect(BatterieMaison.depuisHomeKit(niveau: NSNumber(value: 100), charge: NSNumber(value: 2), alerte: nil)
                == BatterieMaison(niveau: 100, charge: .nonRechargeable))
        #expect(BatterieMaison.depuisHomeKit(niveau: NSNumber(value: 250), charge: NSNumber(value: 7),
                                             alerte: NSNumber(value: 1))
                == BatterieMaison(alerte: true), "hors bornes")
        #expect(BatterieMaison.depuisHomeKit(niveau: "99", charge: nil, alerte: nil) == nil, "pas un nombre")
        #expect(BatterieMaison.depuisHomeKit(niveau: nil, charge: nil, alerte: nil) == nil)
    }

    @Test func fichierSurnoms() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let url = dossier.appendingPathComponent("sous/surnoms.json")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [:], "absent")
        try Surnoms.ecrire([idt("56B1E064401F74EF"): "Halo"], dans: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [idt("56B1E064401F74EF"): "Halo"])
        try Data("pas du json".utf8).write(to: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [:], "illisible")
    }
}
