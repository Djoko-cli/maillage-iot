import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// La memoire des appariements suit la regle de `FichiersGardes` : un fichier d'une version inconnue n'est jamais
/// ecrase, un fichier illisible est mis de cote avant la premiere ecriture.
@Suite("Memoire des appariements : fichier garde")
struct MemoireAppariementsTests {
    /// Un dossier neuf et le fichier de la memoire qu'il recevra.
    private static func fichier() -> (dossier: URL, fichier: URL) {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("appariements-\(UUID().uuidString)")
        return (dossier, MemoireAppariements.fichier(dossier: dossier))
    }

    /// Un fichier d'une version plus recente (autre schema peut-etre) reste tel quel : `ecrire` ne fait rien, sans
    /// erreur, et la lecture le donne comme vide.
    @Test func formatInconnuJamaisEcrase() throws {
        let (dossier, fichier) = Self.fichier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let inconnu = Data(#"{"version":99,"ids":{"A0000000000000B1":"ID-1"},"autre":true}"#.utf8)
        try inconnu.write(to: fichier)
        try MemoireAppariements(ids: ["A0000000000000B2": "ID-2"]).ecrire(dans: fichier)
        #expect(try Data(contentsOf: fichier) == inconnu, "le fichier d'une version inconnue n'est pas reecrit")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dossier.path) == ["appariements-maison.json"])
        #expect(MemoireAppariements.lire(fichier).ids.isEmpty, "lu comme vide")
    }

    /// Un fichier illisible est mis de cote (jamais efface) avant que la memoire ne s'ecrive a sa place.
    @Test func illisibleMisDeCoteAvantEcriture() throws {
        let (dossier, fichier) = Self.fichier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let abime = Data("pas du json".utf8)
        try abime.write(to: fichier)
        let m = MemoireAppariements(ids: ["A0000000000000B1": "ID-1"])
        try m.ecrire(dans: fichier)
        #expect(MemoireAppariements.lire(fichier) == m)
        let autres = try FileManager.default.contentsOfDirectory(atPath: dossier.path)
            .filter { $0.hasPrefix("appariements-maison.illisible-") }
        #expect(autres.count == 1)
        let misDeCote = try #require(autres.first)
        #expect(try Data(contentsOf: dossier.appendingPathComponent(misDeCote)) == abime)
    }
}
