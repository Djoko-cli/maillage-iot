import Foundation
import Testing
@testable import MaillageCoeur

/// « Ignorer », dans la fiche d'un routeur de bordure a qui AirPlay propose une piece : le nom AirPlay ignore, garde par
/// maison a cote des pieces choisies (`pieces-noeuds.json`, version 2, un champ de plus).
@Suite("Scene : proposition AirPlay ignoree")
struct PiecesRouteursAirPlayTests {
    @Test func gardeParMaisonEtParRouteur() {
        var p = PiecesRouteurs()
        #expect(p.airPlayIgnore(routeur: idt("HomePod 1"), domicile: "Maison") == nil)
        p.ignorerAirPlay("HomePod Salon", routeur: idt("HomePod 1"), domicile: "Maison")
        #expect(p.airPlayIgnore(routeur: idt("HomePod 1"), domicile: "Maison") == "HomePod Salon")
        #expect(p.airPlayIgnore(routeur: idt("HomePod 2"), domicile: "Maison") == nil, "un autre routeur")
        #expect(p.airPlayIgnore(routeur: idt("HomePod 1"), domicile: "Chalet") == nil, "une autre maison")
        p.ignorerAirPlay("HomePod Cuisine", routeur: idt("HomePod 1"), domicile: "Maison")
        #expect(p.airPlayIgnore(routeur: idt("HomePod 1"), domicile: "Maison") == "HomePod Cuisine", "le dernier nom ignore")
        p.ignorerAirPlay(nil, routeur: idt("HomePod 1"), domicile: "Maison")
        #expect(p == PiecesRouteurs(), "rien d'ignore : le fichier redevient vide")
    }

    /// Le fichier ne change pas tant que rien n'est ignore (octets des fichiers d'avant) ; ignore, il se relit tel quel,
    /// a cote des choix.
    @Test func fichier() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ignorees-\(UUID().uuidString)/pieces-noeuds.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PiecesRouteurs()
        p.choisir("Salon", routeur: idt("HomePod 1"), domicile: "Maison")
        try p.ecrire(dans: url)
        let avant = try Data(contentsOf: url)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("ignore") == false)
        #expect(PiecesRouteurs.lire(url) == p)
        p.ignorerAirPlay("HomePod Salon", routeur: idt("HomePod 2"), domicile: "Maison")
        try p.ecrire(dans: url)
        #expect(try Data(contentsOf: url) != avant)
        let relu = PiecesRouteurs.lire(url)
        #expect(relu == p)
        #expect(relu.airPlayIgnore(routeur: idt("HomePod 2"), domicile: "Maison") == "HomePod Salon")
        #expect(relu.choix(routeur: idt("HomePod 1"), domicile: "Maison") == "Salon")
    }

    /// Un champ mal forme est ignore : il ne fait pas perdre les choix de pieces.
    @Test func champMalForme() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ignorees-\(UUID().uuidString)/pieces-noeuds.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"{"ignoreAirPlay":42,"appareils":{},"maisons":{"Maison":{"thread:HomePod 1":"Salon"}},"version":2}"#
        try Data(json.utf8).write(to: url)
        let p = PiecesRouteurs.lire(url)
        #expect(p.choix(routeur: idt("HomePod 1"), domicile: "Maison") == "Salon")
        #expect(p.airPlayIgnore(routeur: idt("HomePod 1"), domicile: "Maison") == nil)
    }
}
