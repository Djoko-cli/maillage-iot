import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Noms : surnoms, Maison, HomeKit, hote")
struct NomsTests {
    let instantane = Instantane(annonces: Releve20260928.annonces)

    @Test func fabriqueDApple() {
        let n = ResolveurNoms(maison: NomsDemo.maison)
        #expect(NomsDemo.maison.accessoires.count == 30, "24 appareils et 6 routeurs de bordure")
        #expect(n.fabriqueApple(appareils: instantane.appareils + instantane.appareilsIP) == "30FC8F95E0E1A385")
        #expect(ResolveurNoms().fabriqueApple(appareils: instantane.appareils) == nil, "sans Maison")
    }

    /// Maison de demo : les zones et les pieces de la maquette de la vue par pieces, puis le jardin et les combles de
    /// la maquette des etages (polissage C) ; chaque piece a un accessoire ; les routeurs de bordure y sont des
    /// accessoires du nom de leur annonce, sans noeud Matter. Son choix de niveau, en memoire : le jardin a cote du
    /// rez-de-chaussee, hors de la maison. Sur secteur (prise, ampoule, concentrateur, pont), pas de pile : les noms
    /// de la demo ont change avec ses pieces, sa table des piles doit les suivre.
    @Test func maisonDeDemo() {
        let m = NomsDemo.maison
        #expect(m.zones == [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
                            ZoneMaison(nom: "Jardin", pieces: ["Terrasse", "Abri"]),
                            ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
                            ZoneMaison(nom: "Combles", pieces: ["Grenier", "Salle de jeux"])])
        #expect(m.domicile == NomsDemo.domicile)
        #expect(NomsDemo.places().rangement(NomsDemo.domicile)
                == Rangement(ordre: ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage", "zone:Combles"],
                             aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)]))
        #expect(NomsDemo.places(dehors: false).rangement(NomsDemo.domicile).aCote["zone:Jardin"]?.dehors == false)
        let pieces = Set(m.accessoires.compactMap(\.piece))
        #expect(pieces == Set((m.zones ?? []).flatMap(\.pieces)))
        // Sur secteur : ni prise, ni ampoule, ni concentrateur, ni pont ne porte une pile.
        let surSecteur: Set<String> = ["Prise", "Ampoule", "Concentrateur", "Pont"]
        let piles = m.accessoires.filter { surSecteur.contains($0.categorie ?? "") && $0.batterie != nil }.map(\.nom)
        #expect(piles.isEmpty, "sur secteur, sans pile : \(piles)")
        // La fiche montre chaque etat de pile en demo : un volet en charge, rechargeable.
        let enCharge = m.accessoires.filter { $0.batterie?.charge == .enCharge }.map(\.nom)
        #expect(enCharge == ["Volet salon"], "en charge : \(enCharge)")
        let routeurs = Set(instantane.routeurs.map(\.instance))
        let accessoiresRouteurs = m.accessoires.filter { routeurs.contains($0.nom) }
        #expect(accessoiresRouteurs.count == 6 && accessoiresRouteurs.allSatisfy { $0.noeudMatter == nil && $0.piece != nil })
    }

    @Test func noeudMatter() {
        #expect(AccessoireMaison.noeud(nil) == nil)
        #expect(AccessoireMaison.noeud(0) == nil, "accessoire non Matter")
        #expect(AccessoireMaison.noeud(0x4F63C86C) == "000000004F63C86C")
        #expect(AccessoireMaison.noeud(0xFEDCBA9876543210) == "FEDCBA9876543210")
    }

    /// Un pont porte plusieurs accessoires sur un seul noeud : le noeud prend
    /// le nom du pont, sinon du premier par nom.
    @Test func pont() throws {
        let halo = try #require(instantane.appareil("56B1E064401F74EF"))
        let f = "30FC8F95E0E1A385"
        let noeud = try #require(halo.instances.first { $0.fabrique == f }?.noeud)
        var maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Lampe 2", noeudMatter: noeud),
            AccessoireMaison(nom: "Pont Hue", categorie: "Bridge", noeudMatter: noeud, pont: true),
            AccessoireMaison(nom: "Lampe 1", noeudMatter: noeud),
        ])
        #expect(ResolveurNoms(maison: maison).nom(appareil: halo, fabriqueApple: f) == "Pont Hue")
        maison.accessoires[1].pont = nil
        #expect(ResolveurNoms(maison: maison).nom(appareil: halo, fabriqueApple: f) == "Lampe 1")
    }

    /// Plusieurs ponts sur un meme noeud : le premier par nom, quel que soit
    /// l'ordre du fichier.
    @Test func plusieursPonts() throws {
        let halo = try #require(instantane.appareil("56B1E064401F74EF"))
        let f = "30FC8F95E0E1A385"
        let noeud = try #require(halo.instances.first { $0.fabrique == f }?.noeud)
        let maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Pont B", noeudMatter: noeud, pont: true),
            AccessoireMaison(nom: "Lampe", noeudMatter: noeud),
            AccessoireMaison(nom: "Pont A", noeudMatter: noeud, pont: true),
        ])
        #expect(ResolveurNoms(maison: maison).nom(appareil: halo, fabriqueApple: f) == "Pont A")
    }

    /// Un `matterNodeID` a 0 (accessoire non Matter) n'identifie personne.
    @Test func noeudNul() throws {
        var b = Banc()
        b.appareil("AAAA000000000001", noeud: 0, adresses: ["fd19:961f:2db3::11"])
        let a = try #require(Instantane(annonces: b.annonces).appareil("AAAA000000000001"))
        let n = ResolveurNoms(maison: NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Camera IP", noeudMatter: "0000000000000000"),
        ]))
        #expect(n.fabriqueApple(appareils: [a]) == nil)
        #expect(n.accessoire(de: a, fabriqueApple: "30FC8F95E0E1A385") == nil)
        #expect(n.nom(appareil: a, fabriqueApple: "30FC8F95E0E1A385") == "AAAA000000000001")
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

    @Test func priorite() throws {
        let halo = try #require(instantane.appareil("56B1E064401F74EF"))
        let f = "30FC8F95E0E1A385"
        #expect(ResolveurNoms().nom(appareil: halo, fabriqueApple: f) == "56B1E064401F74EF", "l'hote a defaut")
        let maison = ResolveurNoms(maison: NomsDemo.maison)
        #expect(maison.nom(appareil: halo, fabriqueApple: f) == "Halo")
        #expect(maison.accessoire(de: halo, fabriqueApple: f)?.piece == "Bureau")
        #expect(maison.nom(appareil: halo, fabriqueApple: "20D00941B54CEF76") == "56B1E064401F74EF",
                "autre fabrique : autres numeros de noeud")
        let surnom = ResolveurNoms(surnoms: ["56B1E064401F74EF": "Pont du bureau"], maison: NomsDemo.maison)
        #expect(surnom.nom(appareil: halo, fabriqueApple: f) == "Pont du bureau")
        #expect(ResolveurNoms(surnoms: ["56B1E064401F74EF": ""]).nom(appareil: halo, fabriqueApple: nil)
                == "56B1E064401F74EF", "surnom vide ignore")

        var b = Banc()
        b.hap.append(AnnonceService(instance: "Eve Door 4A3B", hote: "Eve-Door-4A3B.local"))
        b.adresses["Eve-Door-4A3B.local"] = ["fd19:961f:2db3::44"]
        let eve = try #require(Instantane(annonces: b.annonces).appareil("Eve-Door-4A3B"))
        #expect(ResolveurNoms().nom(appareil: eve, fabriqueApple: nil) == "Eve Door 4A3B", "nom HomeKit")

        let atv = try #require(instantane.routeur("Apple TV 4K"))
        #expect(ResolveurNoms().nom(routeur: atv) == "Apple TV 4K")
        #expect(ResolveurNoms(surnoms: ["Apple TV 4K": "Salon"]).nom(routeur: atv) == "Salon")
    }

    @Test func fichierNomsJSON() throws {
        let d = try NomsDemo.maison.donnees()
        #expect(try NomsMaison.lire(d) == NomsDemo.maison)
        var futur = NomsDemo.maison
        futur.version = NomsMaison.versionActuelle + 1
        #expect(throws: NomsMaison.Erreur.versionTropRecente(NomsMaison.versionActuelle + 1)) { try NomsMaison.lire(try futur.donnees()) }
        let refus = NomsMaison(date: Date(timeIntervalSince1970: 0), statut: .refuse, message: "acces refuse")
        #expect(try NomsMaison.lire(try refus.donnees()).statut == .refuse)
    }

    @Test func fichierSurnoms() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let url = dossier.appendingPathComponent("sous/surnoms.json")
        #expect(Surnoms.lire(url) == [:], "absent")
        try Surnoms.ecrire(["56B1E064401F74EF": "Halo"], dans: url)
        #expect(Surnoms.lire(url) == ["56B1E064401F74EF": "Halo"])
        try Data("pas du json".utf8).write(to: url)
        #expect(Surnoms.lire(url) == [:], "illisible")
    }
}
