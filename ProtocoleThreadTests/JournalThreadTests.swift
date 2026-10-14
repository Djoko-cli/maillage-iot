import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Le mecanisme du journal (tri, ajout, lignes illisibles, purge) est teste dans le coeur
/// (`MaillageCoeurTests/JournalTests.swift`, politique d'essai) ; ici, la relecture avec les types Thread.
@Suite("Journal Thread : relecture avec PolitiqueJournalThread")
struct JournalThreadTests {
    static func date(_ texte: String) -> Date {
        try! Date(texte, strategy: .iso8601)
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
    }

    @Test func ajouterEtLire() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let j = JournalFichiers(dossier: d, calendrier: AidesThread.calendrier, politique: PolitiqueJournalThread())
        #expect(try j.lire().isEmpty, "dossier absent")
        let a = Evenement(date: Self.date("2026-09-27T00:14:00Z"), type: .appareilDisparu,
                          sujet: Sujet(id: "46F77B36E071F8D0", nom: "Prise bureau"))
        let b = Evenement(date: Self.date("2026-09-30T21:00:00Z"), type: .veille,
                          periode: DateInterval(start: Self.date("2026-09-30T20:00:00Z"), end: Self.date("2026-09-30T21:00:00Z")))
        let c = Evenement(date: Self.date("2026-09-27T00:10:00Z"), type: .reseauScinde, reseau: "4B36A2B7FEFB200B")
        try j.ajouter([a, b])
        try j.ajouter([c])
        #expect(try j.fichiers().map(\.lastPathComponent) == ["journal-2026-09.jsonl", "journal-2026-10.jsonl"])
        let relus = try j.lire()
        #expect(relus == [c, a, b], "tries par date")
        #expect(relus.map(\.gravite) == [.alerte, .attention, .info], "gravites des types Thread")
    }
}
