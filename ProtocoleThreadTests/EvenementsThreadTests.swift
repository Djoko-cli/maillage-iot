import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

@Suite("Types d'evenements Thread : memes noms, memes gravites que le journal de Thread 1.3.0")
struct EvenementsThreadTests {
    /// Table de `Evenement.swift` a 15a499a (ordre de l'ancienne enumeration) : nom, constante, gravite par defaut.
    static let table: [(String, TypeEvenement, Gravite)] = [
        ("surveillanceDemarree", .surveillanceDemarree, .info),
        ("veille", .veille, .info),
        ("reseauScinde", .reseauScinde, .alerte),
        ("reseauReuni", .reseauReuni, .info),
        ("chefChange", .chefChange, .attention),
        ("bbrPrimaireChange", .bbrPrimaireChange, .info),
        ("jeuActifChange", .jeuActifChange, .attention),
        ("routeurApparu", .routeurApparu, .info),
        ("routeurDisparu", .routeurDisparu, .alerte),
        ("routeurRoleChange", .routeurRoleChange, .info),
        ("routeurNouvelleAdresseLien", .routeurNouvelleAdresseLien, .attention),
        ("prefixeNouveau", .prefixeNouveau, .info),
        ("prefixeRetire", .prefixeRetire, .attention),
        ("appareilNouveau", .appareilNouveau, .info),
        ("appareilDisparu", .appareilDisparu, .attention),
        ("appareilRevenu", .appareilRevenu, .info),
        ("appareilSansAdresse", .appareilSansAdresse, .attention),
        ("appareilChangePartition", .appareilChangePartition, .attention),
        ("parentChange", .parentChange, .info),
        ("sansParent", .sansParent, .attention),
        ("routeurThreadApparu", .routeurThreadApparu, .info),
        ("routeurThreadDisparu", .routeurThreadDisparu, .attention),
    ]

    @Test(arguments: table) func nomEtGraviteInchanges(_ ligne: (String, TypeEvenement, Gravite)) {
        let (nom, type, gravite) = ligne
        #expect(type.rawValue == nom)
        #expect(type.gravite == gravite)
        #expect(Evenement(date: Date(timeIntervalSince1970: 0), type: type).gravite == gravite)
    }

    @Test func laPolitiqueThreadListeLesVingtDeuxTypesDansLOrdreHistorique() {
        #expect(PolitiqueJournalThread().types.map(\.rawValue) == Self.table.map(\.0))
        #expect(TypeEvenement.thread.count == 20)
    }

    /// Lignes ecrites par Thread 1.3.0 (code de 15a499a, `CodageJSON.encodeur()`), recopiees telles quelles.
    static let lignes: [(String, Evenement)] = {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        return [
            (#"{"apres":"2","avant":"1","constate":true,"date":"2026-09-21T14:13:20.000Z","details":{"P1":"Appareil 1"},"gravite":"alerte","periode":{"duration":60,"start":"2026-09-21T14:12:20.000Z"},"reseau":"0000000000000001","sujet":{"id":"0000000000000001","nom":"Reseau 1"},"type":"reseauScinde"}"#,
             Evenement(date: t0, type: .reseauScinde, reseau: "0000000000000001",
                       sujet: Sujet(id: "0000000000000001", nom: "Reseau 1"), avant: "1", apres: "2",
                       periode: DateInterval(start: t0 - 60, end: t0), constate: true,
                       details: ["P1": "Appareil 1"])),
            (#"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{"coupee":"oui"},"gravite":"info","sujet":{"id":"A1","nom":"Prise 1"},"type":"appareilChangePartition"}"#,
             Evenement(date: t0, type: .appareilChangePartition, gravite: .info,
                       sujet: Sujet(id: "A1", nom: "Prise 1"), details: ["coupee": "oui"])),
            (#"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{},"gravite":"alerte","type":"routeurDisparu"}"#,
             Evenement(date: t0, type: .routeurDisparu)),
        ]
    }()

    @Test(arguments: lignes) func ligneDeThread130SeRelitEnUnEvenementEgal(_ ligne: (String, Evenement)) throws {
        let (json, attendu) = ligne
        let decodeur = CodageJSON.decodeur()
        decodeur.userInfo[.typesEvenement] = PolitiqueJournalThread().typesParNom
        let lu = try decodeur.decode(Evenement.self, from: Data(json.utf8))
        #expect(lu == attendu)
        #expect(lu.gravite == attendu.gravite)
        // Et le code d'aujourd'hui ecrit la meme ligne, a l'octet pres.
        #expect(String(decoding: try CodageJSON.encodeur().encode(attendu), as: UTF8.self) == json)
    }

    /// Une ligne sans `gravite` prend celle que la politique Thread donne au type (appareilDisparu : attention).
    @Test func ligneSansGraviteRelueParLaPolitiqueThread() throws {
        let json = #"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{},"sujet":{"id":"A1","nom":"Prise 1"},"type":"appareilDisparu"}"#
        let decodeur = CodageJSON.decodeur()
        decodeur.userInfo[.typesEvenement] = PolitiqueJournalThread().typesParNom
        let lu = try decodeur.decode(Evenement.self, from: Data(json.utf8))
        #expect(lu.type == .appareilDisparu)
        #expect(lu.gravite == .attention)
    }

    @Test func journalSurDisqueRelitUneLigneDeThread130() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(secondsFromGMT: 0)!
        let j = JournalFichiers(dossier: dossier, calendrier: calendrier, politique: PolitiqueJournalThread())
        let (json, attendu) = Self.lignes[0]
        try Data((json + "\n").utf8).write(to: dossier.appendingPathComponent(j.nomFichier(attendu.date)))
        #expect(try j.lire() == [attendu])
    }
}
