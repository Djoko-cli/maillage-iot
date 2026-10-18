import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Revue finale de la phase 4, m3 : apres `ModulesApp.arreterTout` (donc `Surveillance.arreter`), aucun ecrivain ne recrit un
/// fichier commun depuis sa memoire. Le fichier que l'import vient de mettre en place reste intact. Valeurs inventees,
/// dossiers jetables.
@MainActor
@Suite("Apres l'arret des modules, plus d'ecriture depuis la memoire")
struct EcrituresApresArretTests {
    static func dossier() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("arret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Ce que l'import met en place : un contenu reconnaissable, ecrit hors des modules.
    static func mettreEnPlace(_ url: URL) throws -> Data {
        let d = Data(#"{"mis en place par l'import":true}"#.utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try d.write(to: url)
        return d
    }

    @Test func unSurnomNEcritPlusApresLArret() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = Surveillance(mode: .direct, dossier: d)
        let url = d.appendingPathComponent("surnoms.json")
        s.renommer(IdNoeud(.thread, "AAAA000000000001"), en: "Lampe 1")
        s.arreter()
        let place = try Self.mettreEnPlace(url)
        s.renommer(IdNoeud(.thread, "AAAA000000000002"), en: "Lampe 2")
        s.renommer(IdNoeud(.thread, "AAAA000000000001"), en: "")
        #expect(try Data(contentsOf: url) == place, "le fichier mis en place par l'import est intact")
    }

    @Test func uneAssociationNEcritPlusApresLArret() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = AssociationMaisonTests.surveillance(dossier: d)
        let url = Surveillance.dossierThread(d).appendingPathComponent("associations.json")
        s.arreter()
        let place = try Self.mettreEnPlace(url)
        s.thread.associer(AssociationMaisonTests.muet, a: AssociationMaisonTests.maison().accessoires[1])
        s.thread.dissocier(AssociationMaisonTests.muet)
        #expect(try Data(contentsOf: url) == place)
    }

    @Test func unMaillageEnVolNEcritPlusApresLArret() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = Surveillance(mode: .direct, dossier: d)
        let url = Surveillance.dossierThread(d).appendingPathComponent("dernier-maillage.json")
        s.arreter()
        let place = try Self.mettreEnPlace(url)
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        s.thread.recevoir(try SurveillanceTests.maillageGarde(recu.addingTimeInterval(-60)), a: recu)
        #expect(try Data(contentsOf: url) == place)
        let zigbee = Surveillance.dossierZigbee(d).appendingPathComponent("dernier-maillage.json")
        let placeZ = try Self.mettreEnPlace(zigbee)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: recu)
        #expect(try Data(contentsOf: zigbee) == placeZ)
    }

    @Test func unChoixDePieceNEcritPlusApresLArret() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let s = Surveillance(mode: .direct, dossier: d)
        let choisies = PiecesChoisies(fichier: url)
        choisies.coque = s
        choisies.choisir("Salon", .appareil(IdNoeud(.thread, "AAAA000000000001")), domicile: "Maison")
        s.arreter()
        let place = try Self.mettreEnPlace(url)
        choisies.choisir("Bureau", .appareil(IdNoeud(.thread, "AAAA000000000002")), domicile: "Maison")
        #expect(try Data(contentsOf: url) == place)
    }

    @Test func uneDispositionDePiecesNEcritPlusApresLArret() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("positions-pieces.json")
        let (m, _) = try MoteurPiecesTests.moteur(fichier: url)
        let s = Surveillance(mode: .direct, dossier: d)
        m.coque = s
        s.arreter()
        let place = try Self.mettreEnPlace(url)
        m.replacerPieces()
        #expect(try Data(contentsOf: url) == place)
    }

    /// Le garde ne coupe pas les ecritures d'une app qui tourne (et `demarrer()` les rend).
    @Test func avantL_ArretEtApresUnDemarrageOnEcritToujours() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = Surveillance(mode: .direct, dossier: d)
        let url = d.appendingPathComponent("surnoms.json")
        s.arreter()
        s.demarrer()
        s.renommer(IdNoeud(.thread, "AAAA000000000001"), en: "Lampe 1")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [IdNoeud(.thread, "AAAA000000000001"): "Lampe 1"])
    }
}
