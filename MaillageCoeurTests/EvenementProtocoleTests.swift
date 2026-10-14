import Foundation
import Testing
@testable import MaillageCoeur

/// Le protocole d'un evenement du journal : facultatif, absent des lignes d'avant, lu comme Thread.
@Suite("Evenement : protocole facultatif")
struct EvenementProtocoleTests {
    static let calendrier = JournalTests.calendrier
    static let date = JournalTests.date("2026-09-27T00:14:00Z")

    /// Une ligne d'avant l'etape 3 (sans `protocole`) se relit avec `protocole == nil`, que la politique lit comme
    /// Thread ; relue puis reecrite, elle reste telle quelle, octet pour octet (la cle est absente, pas `null`).
    @Test func ligneSansProtocoleEstThread() throws {
        let ligne = #"{"constate":false,"date":"2026-09-27T00:14:00.000Z","details":{},"gravite":"attention","sujet":{"id":"SUJET-1","nom":"Appareil 1"},"type":"essaiPerte"}"#
        let e = try CodageJSON.decodeur().decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.protocole == nil)
        let compose = PolitiqueJournalComposee([.thread: PolitiqueEssai()])
        #expect(compose.estPerte(e), "une ligne sans protocole est de Thread")
        let ecrite = try CodageJSON.encodeur().encode(e)
        #expect(String(decoding: ecrite, as: UTF8.self) == ligne, "reecrite a l'identique")

        // Dans un fichier du journal : relue, puis ajoutee de nouveau, la ligne est la meme.
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("evt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data((ligne + "\n").utf8).write(to: d.appendingPathComponent("journal-2026-09.jsonl"))
        let j = JournalFichiers(dossier: d, calendrier: Self.calendrier, politique: compose)
        let relus = try j.lire()
        #expect(relus == [e])
        let d2 = d.appendingPathComponent("copie")
        try JournalFichiers(dossier: d2, calendrier: Self.calendrier, politique: compose).ajouter(relus)
        let copie = try String(contentsOf: d2.appendingPathComponent("journal-2026-09.jsonl"), encoding: .utf8)
        #expect(copie == ligne + "\n")
    }

    /// Un evenement qui porte son protocole l'ecrit et le relit ; un protocole inconnu rend la ligne illisible, donc
    /// ignoree (jamais lue comme Thread).
    @Test func protocoleEcritEtRelu() throws {
        var e = Evenement(date: Self.date, type: .essaiRoutine, sujet: Sujet(id: "S", nom: "S"))
        e.protocole = .zigbee
        let json = try CodageJSON.encodeur().encode(e)
        #expect(String(decoding: json, as: UTF8.self).contains(#""protocole":"zigbee""#))
        #expect(try CodageJSON.decodeur().decode(Evenement.self, from: json) == e)
        let inconnu = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "zigbee", with: "matter")
        #expect(throws: DecodingError.self) { try CodageJSON.decodeur().decode(Evenement.self, from: Data(inconnu.utf8)) }
        let neuf = Evenement(date: Self.date, type: .essaiRoutine, protocole: .thread)
        #expect(neuf.protocole == .thread)
    }
}
