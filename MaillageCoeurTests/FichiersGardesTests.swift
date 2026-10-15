import Foundation
import Testing
@testable import MaillageCoeur

/// Fichiers gardes dans le conteneur de l'app : places des pieces, pieces choisies (`pieces-noeuds.json`, version 2),
/// surnoms (`surnoms.json`, version 1). Un fichier d'une version plus recente, ou qui porte un protocole inconnu, n'est
/// jamais reecrit ; un fichier illisible est mis de cote avant d'etre remplace ; le cas ordinaire ne change pas. Dans un dossier temporaire, avec
/// des donnees inventees.
@Suite("Fichiers gardes : version plus recente, fichier illisible")
struct FichiersGardesTests {
    static let domicile = "Maison inventée"

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fichiers-\(UUID().uuidString)")
    }

    /// Les noms des fichiers du dossier, tries.
    static func noms(_ d: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
    }

    /// Une sorte de fichier garde : son nom, et un aller-retour (lire, changer une valeur inventee,
    /// ecrire, relire) qui rend vrai si la valeur ecrite se relit.
    struct Sorte: Sendable, CustomTestStringConvertible {
        var nom: String
        var allerRetour: @Sendable (URL) throws -> Bool
        var testDescription: String { nom }
    }

    static let sortes = [
        Sorte(nom: "positions-pieces.json") { url in
            var p = PlacesGardees.lire(url)
            p.garder(SIMD2(1.5, -2.25), piece: "piece:Salon", etage: "zone:Étage", domicile: domicile)
            try p.ecrire(dans: url)
            return PlacesGardees.lire(url) == p
        },
        Sorte(nom: "pieces-noeuds.json") { url in
            var p = PiecesRouteurs.lire(url)
            p.choisir("Salon", routeur: idt("HomePod Palier"), domicile: domicile)
            try p.ecrire(dans: url)
            return PiecesRouteurs.lire(url) == p
        },
        Sorte(nom: "surnoms.json") { url in
            var s = Surnoms.lire(url, protocoleParDefaut: .thread)
            s[idt("DEADBEEF00000001")] = "Lampe inventée"
            try Surnoms.ecrire(s, dans: url)
            return Surnoms.lire(url, protocoleParDefaut: .thread) == s
        },
    ]

    /// Un fichier illisible, mais present, est lu comme vide ; a la premiere ecriture, il est mis de
    /// cote (renomme `<nom>.illisible-AAAAMMJJ-HHMMSS.json` dans le meme dossier, son contenu intact),
    /// puis remplace par le fichier ecrit. La suivante ne met plus rien de cote.
    @Test(arguments: sortes)
    func illisibleMisDeCote(_ sorte: Sorte) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent(sorte.nom)
        let abime = Data("{pas du json".utf8)
        try abime.write(to: url)
        #expect(try sorte.allerRetour(url))
        let noms = try Self.noms(d)
        let base = url.deletingPathExtension().lastPathComponent
        let mis = noms.filter { $0 != sorte.nom }
        #expect(noms.contains(sorte.nom) && mis.count == 1, "\(noms)")
        let deCote = try #require(mis.first)
        #expect(deCote.wholeMatch(of: /(.+)\.illisible-\d{8}-\d{6}\.json/)?.output.1 == Substring(base), "\(deCote)")
        #expect(try Data(contentsOf: d.appendingPathComponent(deCote)) == abime, "son contenu intact")
        #expect(try sorte.allerRetour(url))
        #expect(try Self.noms(d) == noms, "rien de plus mis de cote")
    }

    /// Un fichier d'une version plus recente (ecrit par une app plus recente, peut-etre d'un autre
    /// schema) est lu comme vide, et jamais reecrit : l'app travaille en memoire, sans erreur.
    @Test(arguments: [#"{"maisons":{"Maison inventée":{"thread:HomePod Palier":"Salon"}},"nouveau":true,"version":3}"#,
                      #"{"maisons":["un autre schéma"],"version":3}"#])
    func plusRecentJamaisReecrit(_ json: String) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let routeurs = d.appendingPathComponent("pieces-noeuds.json")
        let places = d.appendingPathComponent("positions-pieces.json")
        let recent = Data(json.utf8)
        try recent.write(to: routeurs)
        try recent.write(to: places)
        var p = PiecesRouteurs.lire(routeurs)
        #expect(p == PiecesRouteurs(), "lu comme vide")
        p.choisir("Bureau", routeur: idt("Apple TV"), domicile: Self.domicile)
        try p.ecrire(dans: routeurs)
        var g = PlacesGardees.lire(places)
        #expect(g == PlacesGardees(), "lu comme vide")
        g.ordonner(["zone:Étage"], domicile: Self.domicile)
        try g.ecrire(dans: places)
        #expect(try Data(contentsOf: routeurs) == recent && Data(contentsOf: places) == recent, "jamais reecrit")
        #expect(try Self.noms(d) == ["pieces-noeuds.json", "positions-pieces.json"], "rien de mis de cote")
    }

    /// Le cas ordinaire ne change pas : absent, le fichier est ecrit ; lisible et d'une version connue,
    /// il est relu et reecrit a sa place, sans rien mettre de cote.
    @Test(arguments: sortes)
    func casOrdinaire(_ sorte: Sorte) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent(sorte.nom)
        #expect(try sorte.allerRetour(url), "absent")
        #expect(try sorte.allerRetour(url), "lisible")
        #expect(try Self.noms(d) == [sorte.nom])
    }

    /// Un fichier valide d'une app d'avant (`pieces-routeurs.json` version 1, les routeurs seuls) garde ses trois choix de
    /// routeurs, sous le protocole de l'app, quand l'app y ajoute le choix d'un appareil : l'ancien fichier n'est ni mis de
    /// cote ni touche, le nouveau (`pieces-noeuds.json`, version 2) porte les quatre choix.
    @Test func troisChoixDesRouteurs() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let ancienUrl = d.appendingPathComponent("pieces-routeurs.json")
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let ancien = """
            {
              "maisons" : {
                "" : {
                  "HomePod" : "Cuisine"
                },
                "Maison inventée" : {
                  "Apple TV" : "Salon",
                  "HomePod Palier" : "Bureau"
                }
              },
              "version" : 1
            }
            """
        try Data(ancien.utf8).write(to: ancienUrl)
        let routeurs = ["": [idt("HomePod"): "Cuisine"],
                        Self.domicile: [idt("Apple TV"): "Salon", idt("HomePod Palier"): "Bureau"]]
        var p = PiecesRouteurs.lire(url, ancien: ancienUrl, protocoleParDefaut: .thread)
        #expect(p.maisons == routeurs)
        p.choisir("Salon", appareil: idt("DEADBEEF00000001"), domicile: Self.domicile)
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url).maisons == routeurs)
        #expect(PiecesRouteurs.lire(url).choix(appareil: idt("DEADBEEF00000001"), domicile: Self.domicile) == "Salon")
        // Le nouveau fichier existe : l'ancien n'est plus lu.
        #expect(PiecesRouteurs.lire(url, ancien: ancienUrl, protocoleParDefaut: .zigbee) == PiecesRouteurs.lire(url))
        #expect(try Self.noms(d) == ["pieces-noeuds.json", "pieces-routeurs.json"])
        #expect(try Data(contentsOf: ancienUrl) == Data(ancien.utf8), "l'ancien fichier reste tel quel")
    }

    /// Un format inconnu n'est jamais ecrase : un fichier d'une version plus recente, ou dont une cle porte un protocole que
    /// cette app ne connait pas (une app plus recente l'a ecrit), est lu comme vide, jamais reecrit, jamais mis de cote.
    /// Valable pour les surnoms comme pour les pieces des noeuds.
    struct Inconnu: Sendable, CustomTestStringConvertible {
        var nom: String
        var fichier: String
        var json: String
        var essai: @Sendable (URL) throws -> Bool
        var testDescription: String { nom }
    }

    static let surnomsInconnus: @Sendable (URL) throws -> Bool = { url in
        let lu = Surnoms.lire(url, protocoleParDefaut: .thread)
        var s = lu
        s[idt("DEADBEEF00000001")] = "Lampe inventée"
        try Surnoms.ecrire(s, dans: url)
        return lu.isEmpty
    }

    static let piecesInconnues: @Sendable (URL) throws -> Bool = { url in
        let lu = PiecesRouteurs.lire(url)
        var p = lu
        p.choisir("Bureau", appareil: idt("DEADBEEF00000001"), domicile: domicile)
        try p.ecrire(dans: url)
        return lu == PiecesRouteurs()
    }

    @Test(arguments: [
        Inconnu(nom: "surnoms version 2", fichier: "surnoms.json",
                json: #"{"surnoms":{"thread:A1":"Lampe 1"},"nouveau":true,"version":2}"#, essai: surnomsInconnus),
        Inconnu(nom: "surnoms, protocole inconnu", fichier: "surnoms.json",
                json: #"{"surnoms":{"thread:A1":"Lampe 1","matter:B2":"Lampe 2"},"version":1}"#, essai: surnomsInconnus),
        Inconnu(nom: "pieces version 3", fichier: "pieces-noeuds.json",
                json: #"{"appareils":{"":{"thread:A1":"Salon"}},"version":3}"#, essai: piecesInconnues),
        Inconnu(nom: "pieces, protocole inconnu (appareils)", fichier: "pieces-noeuds.json",
                json: #"{"appareils":{"":{"thread:A1":"Salon","matter:B2":"Bureau"}},"version":2}"#, essai: piecesInconnues),
        Inconnu(nom: "pieces, protocole inconnu (maisons)", fichier: "pieces-noeuds.json",
                json: #"{"maisons":{"":{"matter:B2":"Bureau"}},"version":2}"#, essai: piecesInconnues),
    ])
    func formatInconnuJamaisEcrase(_ cas: Inconnu) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent(cas.fichier)
        let recent = Data(cas.json.utf8)
        try recent.write(to: url)
        #expect(try cas.essai(url), "lu comme vide")
        #expect(try Data(contentsOf: url) == recent, "jamais reecrit")
        #expect(try Self.noms(d) == [cas.fichier], "rien de mis de cote")
    }

    /// Un champ `appareils` mal forme est ignore : le fichier se lit sans choix, il n'est pas mis de cote, et la
    /// premiere ecriture le remplace (repris de Maillage Zigbee, be6fadf).
    @Test func appareilsMalFormes() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("pieces-noeuds.json")
        try Data(#"{"version": 2, "appareils": ["pas", "un", "dictionnaire"]}"#.utf8).write(to: url)
        var p = PiecesRouteurs.lire(url)
        #expect(p == PiecesRouteurs())
        p.choisir("Salon", appareil: idt("deadbeef00000002"), domicile: Self.domicile)
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url).choix(appareil: idt("DEADBEEF00000002"), domicile: Self.domicile) == "Salon",
                "cle en majuscules")
        #expect(try Self.noms(d) == ["pieces-noeuds.json"])
    }
}
