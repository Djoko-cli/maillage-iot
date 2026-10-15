import Foundation
import Testing
@testable import MaillageCoeur

/// Un type de la politique A, qui n'est qu'a elle (gravite par defaut : alerte) et un type present chez les deux, avec
/// deux gravites.
extension TypeEvenement {
    static let compoPartage = TypeEvenement("compoPartage", gravite: .alerte)
    static let compoPartageDouce = TypeEvenement("compoPartage", gravite: .info)
    static let compoSeulA = TypeEvenement("compoSeulA", gravite: .attention)
    static let compoSeulB = TypeEvenement("compoSeulB")
}

@Suite("Politique du journal composee par protocole")
struct PolitiqueJournalComposeeTests {
    static let calendrier = JournalTests.calendrier
    static let date = JournalTests.date("2026-09-27T00:14:00Z")

    /// Thread : `compoPartage` est une alerte et une perte, `compoSeulA` existe. Zigbee : `compoPartage` est une simple
    /// info, ni perte ni notification, `compoSeulB` existe.
    struct PolitiqueCompoA: PolitiqueJournal {
        var types: [TypeEvenement] { [.surveillanceDemarree, .veille, .compoPartage, .compoSeulA] }
        func estPerte(_ e: Evenement) -> Bool { e.type == .compoPartage }
        func estScission(_ e: Evenement) -> Bool { false }
        func estReunion(_ e: Evenement) -> Bool { false }
        func categorie(_ e: Evenement) -> CategorieAlerte? { e.type == .compoPartage ? .routeurDisparu : nil }
        func cleParent(_ e: Evenement) -> String? { nil }
    }

    struct PolitiqueCompoB: PolitiqueJournal {
        var types: [TypeEvenement] { [.surveillanceDemarree, .veille, .compoPartageDouce, .compoSeulB] }
        func estPerte(_ e: Evenement) -> Bool { false }
        func estScission(_ e: Evenement) -> Bool { false }
        func estReunion(_ e: Evenement) -> Bool { false }
        func categorie(_ e: Evenement) -> CategorieAlerte? { nil }
        func cleParent(_ e: Evenement) -> String? { nil }
    }

    static let compose = PolitiqueJournalComposee([.thread: PolitiqueCompoA(), .zigbee: PolitiqueCompoB()])

    /// Les decisions viennent de la politique du protocole de l'evenement ; sans protocole, celle de Thread.
    @Test func delegueSelonLeProtocole() {
        let thread = Evenement(date: Self.date, type: .compoPartage, protocole: .thread)
        let zigbee = Evenement(date: Self.date, type: .compoPartageDouce, protocole: .zigbee)
        let sans = Evenement(date: Self.date, type: .compoPartage)
        #expect(Self.compose.estPerte(thread) && Self.compose.estPerte(sans) && !Self.compose.estPerte(zigbee))
        #expect(Self.compose.categorie(thread) == .routeurDisparu && Self.compose.categorie(sans) == .routeurDisparu)
        #expect(Self.compose.categorie(zigbee) == nil)
        // Un protocole sans politique : ni perte, ni categorie, ni parent.
        let seul = PolitiqueJournalComposee([.thread: PolitiqueCompoA()])
        #expect(!seul.estPerte(zigbee) && seul.categorie(zigbee) == nil && seul.cleParent(zigbee) == nil)
        let types = Self.compose.types.map(\.rawValue)
        #expect(types == ["surveillanceDemarree", "veille", "compoPartage", "compoSeulA", "compoSeulB"],
                "l'union des types, sans doublon, Thread d'abord : \(types)")
    }

    /// Un meme type, ecrit avec `protocole: zigbee` puis `thread`, prend la gravite de la politique de son protocole : a la
    /// creation (`type.gravite` du protocole) comme a la relecture d'une ligne sans `gravite`. La relecture des journaux
    /// de Zigbee 1.1.1 (sans `protocole`) se regle a l'import, etape 4.
    @Test func memeTypeDeuxGravites() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("compo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        let j = JournalFichiers(dossier: d, calendrier: Self.calendrier, politique: Self.compose)
        let z = Evenement(date: Self.date, type: .compoPartageDouce, protocole: .zigbee)
        let t = Evenement(date: Self.date.addingTimeInterval(60), type: .compoPartage, protocole: .thread)
        try j.ajouter([z, t])
        let relus = try j.lire()
        #expect(relus.map(\.gravite) == [.info, .alerte])
        #expect(relus.map(\.protocole) == [.zigbee, .thread])

        // Des lignes sans `gravite` : la gravite par defaut est celle du type de leur protocole.
        let nu = { (protocole: String?, date: String) in
            #"{"date":"\#(date)","type":"compoPartage"\#(protocole.map { #","protocole":"\#($0)""# } ?? "")}"#
        }
        let lignes = [nu("zigbee", "2026-09-27T01:00:00.000Z"), nu("thread", "2026-09-27T02:00:00.000Z"),
                      nu(nil, "2026-09-27T03:00:00.000Z")]
        let d2 = d.appendingPathComponent("nues")
        try FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        try Data((lignes.joined(separator: "\n") + "\n").utf8).write(to: d2.appendingPathComponent("journal-2026-09.jsonl"))
        let nues = try JournalFichiers(dossier: d2, calendrier: Self.calendrier, politique: Self.compose).lire()
        #expect(nues.map(\.gravite) == [.info, .alerte, .alerte], "zigbee : info ; thread et sans protocole : alerte")
    }

    /// Une politique composee d'un seul protocole lit les types de son protocole pour une ligne qui n'en porte pas :
    /// l'app Zigbee du plan 3a relit ses journaux d'avant (sans `protocole`), gravite par defaut comprise.
    @Test func ligneSansProtocoleChezUnSeulProtocole() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("compo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let ligne = #"{"date":"2026-09-27T01:00:00.000Z","type":"compoSeulB"}"#
        try Data((ligne + "\n").utf8).write(to: d.appendingPathComponent("journal-2026-09.jsonl"))
        let seul = PolitiqueJournalComposee([.zigbee: PolitiqueCompoB()])
        let relus = try JournalFichiers(dossier: d, calendrier: Self.calendrier, politique: seul).lire()
        #expect(relus.map(\.type.rawValue) == ["compoSeulB"] && relus.first?.protocole == nil)
    }
}
