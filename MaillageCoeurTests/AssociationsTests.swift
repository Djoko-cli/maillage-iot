import Foundation
import Testing
@testable import MaillageCoeur

/// Le fichier des associations a la main entre un appareil et un accessoire de Maison (12/10). Valeurs inventees.
@Suite("Associations a un accessoire de Maison : fichier")
struct AssociationsTests {
    static let nomme = "AAAA000000000001"
    static let muet = "AAAA000000000002"

    /// Le fichier `associations.json` : ecrit puis relu ; absent ou illisible, ignore (comme les surnoms).
    @Test func fichier() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let url = dossier.appendingPathComponent("sous/associations.json")
        #expect(Associations.lire(url) == [:], "absent")
        try Associations.ecrire([Self.muet: "00000000000000AA"], dans: url)
        #expect(Associations.lire(url) == [Self.muet: "00000000000000AA"])
        try Data("pas du json".utf8).write(to: url)
        #expect(Associations.lire(url) == [:], "illisible")
        // Une ecriture ensuite met le fichier illisible de cote, sans le perdre.
        try Associations.ecrire([Self.nomme: "00000000000000BB"], dans: url)
        #expect(Associations.lire(url) == [Self.nomme: "00000000000000BB"])
        let voisins = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(voisins.contains { $0.hasPrefix("associations.illisible-") })
    }
}
