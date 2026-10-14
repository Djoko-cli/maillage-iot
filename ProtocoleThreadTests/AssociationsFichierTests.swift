import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Le fichier des associations a la main entre un appareil et un accessoire de Maison (12/10) : `associations.json`,
/// `{"version": 1, "associations": {...}}`, cles brutes de Thread (jamais prefixees : le fichier est de Thread). Lit encore
/// l'ancien dictionnaire plat. Valeurs inventees.
@Suite("Associations a un accessoire de Maison : fichier")
struct AssociationsFichierTests {
    static let nomme = "AAAA000000000001"
    static let muet = "AAAA000000000002"

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("assoc-\(UUID().uuidString)")
    }

    /// Le fichier `associations.json` : ecrit puis relu ; absent ou illisible, ignore (comme les surnoms).
    @Test func fichier() throws {
        let dossier = Self.dossier()
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

    /// Le schema est `{version, associations}`, cles brutes ; l'ancien dictionnaire plat se relit, et le fichier ecrit ensuite
    /// est au nouveau schema, sans que l'ancien soit mis de cote.
    @Test func versionEtAncienFormatPlat() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("associations.json")
        try Data(#"{"AAAA000000000002":"00000000000000AA"}"#.utf8).write(to: url)
        #expect(Associations.lire(url) == [Self.muet: "00000000000000AA"], "l'ancien format plat")
        try Associations.ecrire([Self.muet: "00000000000000AA", Self.nomme: "00000000000000BB"], dans: url)
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains(#""version" : 1"#) && texte.contains(#""associations" : {"#)
                && texte.contains(#""AAAA000000000001" : "00000000000000BB""#) && !texte.contains("thread:"), "\(texte)")
        #expect(Associations.lire(url).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path) == ["associations.json"], "rien mis de cote")
    }

    /// Une version plus recente n'est jamais reecrite : lue comme vide, intacte.
    @Test func versionPlusRecenteJamaisEcrasee() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("associations.json")
        let recent = Data(#"{"associations":{"AAAA000000000002":"00000000000000AA"},"version":2}"#.utf8)
        try recent.write(to: url)
        #expect(Associations.lire(url) == [:])
        try Associations.ecrire([Self.nomme: "00000000000000BB"], dans: url)
        #expect(try Data(contentsOf: url) == recent)
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path) == ["associations.json"])
    }
}
