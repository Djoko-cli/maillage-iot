import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Noms : surnoms, Maison, HomeKit, hote (Thread)")
struct NomsThreadTests {
    let instantane = Instantane(annonces: Releve20260928.annonces)

    @Test func fabriqueDApple() {
        let n = ResolveurNoms(maison: NomsDemo.maison)
        #expect(NomsDemo.maison.accessoires.count == 30, "24 appareils et 6 routeurs de bordure")
        #expect(n.fabriqueApple(appareils: instantane.appareils + instantane.appareilsIP) == "30FC8F95E0E1A385")
        #expect(ResolveurNoms().fabriqueApple(appareils: instantane.appareils) == nil, "sans Maison")
    }

    /// Maison de demo Thread : chaque piece des zones de la demo (`NomsTests.zonesEtNiveauxDeDemo`) a un accessoire ;
    /// les routeurs de bordure y sont des accessoires du nom de leur annonce, sans noeud Matter. Sur secteur (prise,
    /// ampoule, concentrateur, pont), pas de pile : les noms de la demo ont change avec ses pieces, sa table des piles
    /// doit les suivre.
    @Test func maisonDeDemo() {
        let m = NomsDemo.maison
        #expect(m.zones == NomsDemo.zones)
        #expect(m.domicile == NomsDemo.domicile)
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
}
