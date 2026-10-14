import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

@Suite("Types d'evenements Zigbee : memes noms, memes gravites que le journal de Zigbee 1.1.1")
struct EvenementsZigbeeTests {
    /// Les cas de l'ancienne enumeration fermee de `Evenement.swift` a be6fadf (`TypeEvenement`, dans son ordre) : nom,
    /// constante d'aujourd'hui, gravite par defaut.
    static let table: [(String, TypeEvenement, Gravite)] = [
        ("surveillanceDemarree", .surveillanceDemarree, .info),
        ("veille", .veille, .info),
        ("routeurApparu", .routeurApparu, .info),
        ("routeurDisparu", .routeurDisparu, .alerte),
        ("appareilNouveau", .appareilNouveau, .info),
        ("appareilDisparu", .appareilDisparu, .attention),
        ("appareilRevenu", .appareilRevenu, .info),
        ("parentChange", .parentChange, .info),
        ("sansParent", .sansParent, .attention),
        ("cheminChange", .cheminChange, .info),
    ]

    /// Chaque type de la politique Zigbee se relit avec sa gravite : le nom, la gravite du type et celle d'un
    /// evenement neuf ne bougent pas.
    @Test(arguments: table) func nomEtGraviteInchanges(_ ligne: (String, TypeEvenement, Gravite)) {
        let (nom, type, gravite) = ligne
        #expect(type.rawValue == nom)
        #expect(type.gravite == gravite)
        #expect(Evenement(date: Date(timeIntervalSince1970: 0), type: type).gravite == gravite)
    }

    /// La politique liste les dix types de l'ancienne enumeration, dans son ordre, sans en ajouter ni en perdre.
    @Test func laPolitiqueZigbeeListeLesDixTypesDansLOrdreHistorique() {
        let types = PolitiqueJournalZigbee().types
        #expect(types.map(\.rawValue) == Self.table.map(\.0))
        #expect(types.map(\.gravite) == Self.table.map(\.2))
        #expect(TypeEvenement.zigbee.count == 8, "les types de Zigbee, sans les deux neutres")
        #expect(Set(types.map(\.rawValue)).count == types.count, "aucun nom en double")
    }

    /// Toutes les gravites d'un journal, relues par la politique, sont celles du type.
    @Test func chaqueTypeDeLaPolitiqueSeRelitAvecSaGravite() throws {
        let politique = PolitiqueJournalZigbee()
        for type in politique.types {
            let sans = #"{"date":"2026-09-21T14:13:20.000Z","type":"\#(type.rawValue)"}"#
            let decodeur = CodageJSON.decodeur()
            decodeur.userInfo[.typesEvenement] = politique.typesParNom
            let lu = try decodeur.decode(Evenement.self, from: Data(sans.utf8))
            #expect(lu.type == type && lu.gravite == type.gravite, "\(type.rawValue)")
        }
    }

    /// Lignes ecrites par Zigbee 1.1.1, telles que l'encodage de be6fadf (`Evenement`, `TypeEvenement` ferme encode en
    /// simple chaine, `CodageJSON.encodeur()` : cles triees, date ISO 8601 UTC a la milliseconde) les produit,
    /// recopiees en litteral. Le fichier d'origine n'est pas dans ce depot : les dix premieres sont un evenement nu de
    /// chaque type, les cinq suivantes portent un sujet, des avant/apres, une periode, un constat, un detail `ieee`.
    static let lignes: [(String, Evenement)] = {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let nus: [(String, TypeEvenement)] = [
            ("surveillanceDemarree", .surveillanceDemarree), ("veille", .veille), ("routeurApparu", .routeurApparu),
            ("routeurDisparu", .routeurDisparu), ("appareilNouveau", .appareilNouveau),
            ("appareilDisparu", .appareilDisparu), ("appareilRevenu", .appareilRevenu),
            ("parentChange", .parentChange), ("sansParent", .sansParent), ("cheminChange", .cheminChange),
        ]
        let gravites = ["info", "info", "info", "alerte", "info", "attention", "info", "info", "attention", "info"]
        var tout: [(String, Evenement)] = zip(nus, gravites).map { nu, gravite in
            (#"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{},"gravite":"\#(gravite)","type":"\#(nu.0)"}"#,
             Evenement(date: t0, type: nu.1))
        }
        tout += [
            (#"{"constate":true,"date":"2026-09-21T14:13:20.000Z","details":{"ieee":"0000000000000001"},"gravite":"alerte","sujet":{"id":"0000000000000001","nom":"Routeur 1"},"type":"routeurDisparu"}"#,
             Evenement(date: t0, type: .routeurDisparu, sujet: Sujet(id: "0000000000000001", nom: "Routeur 1"),
                       constate: true, details: ["ieee": "0000000000000001"])),
            (#"{"apres":"Routeur 3","avant":"Routeur 2","constate":false,"date":"2026-09-21T14:13:20.000Z","details":{"ieee":"0000000000000001"},"gravite":"info","sujet":{"id":"0000000000000001","nom":"Routeur 1"},"type":"cheminChange"}"#,
             Evenement(date: t0, type: .cheminChange, sujet: Sujet(id: "0000000000000001", nom: "Routeur 1"),
                       avant: "Routeur 2", apres: "Routeur 3", details: ["ieee": "0000000000000001"])),
            (#"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{"ieee":"0000000000000002"},"gravite":"attention","periode":{"duration":60,"start":"2026-09-21T14:12:20.000Z"},"sujet":{"id":"0000000000000002","nom":"Prise 1"},"type":"appareilDisparu"}"#,
             Evenement(date: t0, type: .appareilDisparu, sujet: Sujet(id: "0000000000000002", nom: "Prise 1"),
                       periode: DateInterval(start: t0 - 60, end: t0), details: ["ieee": "0000000000000002"])),
            (#"{"avant":"Routeur 2","constate":false,"date":"2026-09-21T14:13:20.000Z","details":{"ieee":"0000000000000003"},"gravite":"attention","sujet":{"id":"0000000000000003","nom":"Capteur 1"},"type":"sansParent"}"#,
             Evenement(date: t0, type: .sansParent, sujet: Sujet(id: "0000000000000003", nom: "Capteur 1"),
                       avant: "Routeur 2", details: ["ieee": "0000000000000003"])),
            (#"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{},"gravite":"info","periode":{"duration":3600,"start":"2026-09-21T13:13:20.000Z"},"type":"veille"}"#,
             Evenement(date: t0, type: .veille, periode: DateInterval(start: t0 - 3600, end: t0))),
        ]
        return tout
    }()

    static func decodeur(_ politique: some PolitiqueJournal) -> JSONDecoder {
        let d = CodageJSON.decodeur()
        d.userInfo[.typesEvenement] = politique.typesParNom
        return d
    }

    /// Une ligne de Zigbee 1.1.1 se relit en un evenement egal, avec la gravite qu'elle porte ; et le code d'aujourd'hui
    /// ecrit la meme ligne, a l'octet pres.
    @Test(arguments: lignes) func ligneDeZigbee111SeRelitEnUnEvenementEgal(_ ligne: (String, Evenement)) throws {
        let (json, attendu) = ligne
        let lu = try Self.decodeur(PolitiqueJournalZigbee()).decode(Evenement.self, from: Data(json.utf8))
        #expect(lu == attendu)
        #expect(lu.gravite == attendu.gravite)
        #expect(String(decoding: try CodageJSON.encodeur().encode(attendu), as: UTF8.self) == json)
    }

    /// `journalZigbeeRelu` : les memes lignes, sans leur `gravite` (un journal d'avant que Zigbee l'ecrive), se relisent
    /// avec la politique Zigbee aux gravites d'avant : celle du type, comme l'enumeration fermee la donnait.
    @Test(arguments: lignes) func journalZigbeeRelu(_ ligne: (String, Evenement)) throws {
        let (json, attendu) = ligne
        let sans = json.replacingOccurrences(of: #""gravite":"\#(attendu.gravite.rawValue)","#, with: "")
        try #require(sans != json && !sans.contains("gravite"), "la gravite a bien ete retiree")
        let lu = try Self.decodeur(PolitiqueJournalZigbee()).decode(Evenement.self, from: Data(sans.utf8))
        #expect(lu == attendu)
        #expect(lu.gravite == attendu.type.gravite)
        #expect(lu.gravite == attendu.gravite, "la gravite d'avant")
    }

    /// Sans la politique Zigbee, un type de Zigbee reste lisible mais perd sa gravite par defaut (info) : c'est la
    /// politique qui la rend.
    @Test func sansLaPolitiqueLaGraviteParDefautSePerd() throws {
        let json = #"{"constate":false,"date":"2026-09-21T14:13:20.000Z","details":{},"type":"sansParent"}"#
        let avec = try Self.decodeur(PolitiqueJournalZigbee()).decode(Evenement.self, from: Data(json.utf8))
        let sans = try Self.decodeur(PolitiqueJournalNeutre()).decode(Evenement.self, from: Data(json.utf8))
        #expect(avec.gravite == .attention)
        #expect(sans.type.rawValue == "sansParent" && sans.gravite == .info)
    }

    /// Un journal sur disque, relu par `JournalFichiers` avec la politique Zigbee : toutes les lignes de Zigbee 1.1.1.
    @Test func journalSurDisqueRelitLesLignesDeZigbee111() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let j = JournalFichiers(dossier: dossier, calendrier: AidesZigbee.calendrier, politique: PolitiqueJournalZigbee())
        let texte = Self.lignes.map { $0.0 + "\n" }.joined()
        try Data(texte.utf8).write(to: dossier.appendingPathComponent(j.nomFichier(Self.lignes[0].1.date)))
        let lus = try j.lire()
        #expect(lus.count == Self.lignes.count)
        for attendu in Self.lignes.map(\.1) {
            #expect(lus.contains(attendu), "\(attendu.id)")
        }
        #expect(lus.first { $0.type == .routeurDisparu }?.gravite == .alerte)
    }
}
