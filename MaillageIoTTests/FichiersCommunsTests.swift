import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 4 : les fichiers communs et le journal par protocole, dans l'app Thread. Valeurs inventees.
@MainActor
@Suite("Fichiers communs et journal par protocole (app Thread)")
struct FichiersCommunsTests {
    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("communs-\(UUID().uuidString)")
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func parent(_ minutes: Double, sujet: String, protocole: Protocole?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: sujet, nom: sujet),
                  avant: "A", apres: "B", protocole: protocole)
    }

    /// Site 9 : un surnom se garde sous l'identifiant de noeud (`thread:<cle>`) ; les surnoms d'un autre protocole lus dans le
    /// fichier sont gardes tels quels a l'ecriture et ne touchent pas le resolveur de Thread.
    @Test func surnomsSousLIdentifiantDeNoeud() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("surnoms.json")
        try Data(#"{"surnoms":{"zigbee:ZZ01":"Lampe Zigbee"},"version":1}"#.utf8).write(to: url)
        let s = Surveillance(mode: .direct, dossier: d)
        #expect(s.noms.surnoms.isEmpty, "le resolveur de Thread ne voit que ses cles")
        #expect(s.surnom(de: idz("ZZ01")) == "Lampe Zigbee")
        s.renommer(idt("AAAA000000000001"), en: "  Lampe 1 ")
        #expect(s.noms.surnoms == ["AAAA000000000001": "Lampe 1"] && s.surnom(de: idt("AAAA000000000001")) == "Lampe 1")
        #expect(s.surnom(de: idz("AAAA000000000001")) == nil, "la meme cle sous un autre protocole est un autre noeud")
        let relu = Surnoms.lire(url, protocoleParDefaut: .thread)
        #expect(relu == [idt("AAAA000000000001"): "Lampe 1", idz("ZZ01"): "Lampe Zigbee"])
        s.renommer(idt("AAAA000000000001"), en: "")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [idz("ZZ01"): "Lampe Zigbee"])
    }

    /// Le `surnoms.json` plat de Maillage Thread 1.3 se relit (cles brutes = Thread) ; un surnom donne ensuite le passe au
    /// nouveau schema.
    @Test func surnomsDeLAncienFormatPlat() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("surnoms.json")
        try Data(#"{"AAAA000000000001":"Lampe 1"}"#.utf8).write(to: url)
        let s = Surveillance(mode: .direct, dossier: d)
        #expect(s.noms.surnoms == ["AAAA000000000001": "Lampe 1"] && s.surnom(de: idt("AAAA000000000001")) == "Lampe 1")
        s.renommer(idt("AAAA000000000002"), en: "Lampe 2")
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains(#""version" : 1"#) && texte.contains(#""thread:AAAA000000000001" : "Lampe 1""#)
                && texte.contains(#""thread:AAAA000000000002" : "Lampe 2""#), "\(texte)")
    }

    /// Un `surnoms.json` plus recent n'est jamais reecrit : les surnoms restent en memoire.
    @Test func surnomsPlusRecentsJamaisEcrases() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("surnoms.json")
        let recent = Data(#"{"surnoms":{"matter:X":"Lampe M"},"version":1}"#.utf8)
        try recent.write(to: url)
        let s = Surveillance(mode: .direct, dossier: d)
        s.renommer(idt("AAAA000000000001"), en: "Lampe 1")
        #expect(s.noms.surnoms == ["AAAA000000000001": "Lampe 1"], "en memoire")
        #expect(try Data(contentsOf: url) == recent, "jamais reecrit")
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path) == ["surnoms.json"])
    }

    /// Site 6 : le journal d'un noeud compare l'id du sujet a la cle du noeud ET le protocole de l'evenement (sans
    /// protocole : Thread). Un evenement de Zigbee qui aurait la meme cle n'est pas celui du noeud Thread.
    @Test func journalDUnNoeudSelonLeProtocole() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let journal = JournalFichiers(dossier: d.appendingPathComponent("Journal"), politique: Surveillance.politiqueJournal)
        let thread = Self.parent(0, sujet: "AAAA000000000001", protocole: .thread)
        let sans = Self.parent(1, sujet: "AAAA000000000001", protocole: nil)
        let zigbee = Self.parent(2, sujet: "AAAA000000000001", protocole: .zigbee)
        try journal.ajouter([thread, sans, zigbee])
        let s = Surveillance(mode: .direct, dossier: d)
        s.chargerJournal()
        #expect(s.evenements.count == 3)
        #expect(s.evenements(de: idt("AAAA000000000001")) == [sans, thread], "Thread et sans protocole, le plus recent d'abord")
        #expect(s.evenements(de: idz("AAAA000000000001")).isEmpty, "Thread n'est pas Zigbee")
        #expect(s.lignesJournal(de: idt("AAAA000000000001")).map(\.evenements.count) == [2], "regroupes : le parent change deux fois")
        #expect(s.lignesJournal(de: idz("AAAA000000000001")).isEmpty)
    }

    /// Les evenements de l'app entrent au journal avec `protocole = thread` ; les lignes d'avant, sans protocole, se
    /// relisent telles quelles.
    @Test func evenementsEcritsAvecLeProtocole() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = Surveillance(mode: .direct, dossier: d)
        s.noterVeille(debut: Self.t0, fin: Self.t0.addingTimeInterval(60))
        #expect(s.evenements.map(\.protocole) == [.thread])
        let relus = try JournalFichiers(dossier: d.appendingPathComponent("Journal"),
                                        politique: Surveillance.politiqueJournal).lire()
        #expect(relus == s.evenements && relus.first?.protocole == .thread)
        let fichier = try #require(try FileManager.default.contentsOfDirectory(at: d.appendingPathComponent("Journal"),
                                                                              includingPropertiesForKeys: nil).first)
        #expect(try String(contentsOf: fichier, encoding: .utf8).contains(#""protocole":"thread""#))
    }

    /// Les pieces choisies : `pieces-noeuds.json` (version 2) ; tant qu'il est absent, le `pieces-routeurs.json` d'avant
    /// (version 1, cles brutes de Thread) est relu ; il n'est jamais reecrit.
    @Test func piecesChoisiesRelisentLAncienFichier() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let v1 = #"{"appareils":{"Maison":{"AAAA000000000001":"Salon"}},"maisons":{"Maison":{"HomePod 1":"Cuisine"}},"version":1}"#
        try Data(v1.utf8).write(to: d.appendingPathComponent("pieces-routeurs.json"))
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let choisies = PiecesChoisies(fichier: url)
        #expect(choisies.pieceChoisie(.routeur(idt("HomePod 1")), domicile: "Maison") == "Cuisine")
        #expect(choisies.pieceChoisie(.appareil(idt("AAAA000000000001")), domicile: "Maison") == "Salon")
        choisies.choisir("Bureau", .appareil(idt("AAAA000000000002")), domicile: "Maison")
        let relu = PiecesChoisies(fichier: url)
        #expect(relu.pieceChoisie(.routeur(idt("HomePod 1")), domicile: "Maison") == "Cuisine", "les anciens choix suivent")
        #expect(relu.pieceChoisie(.appareil(idt("AAAA000000000002")), domicile: "Maison") == "Bureau")
        #expect(try Data(contentsOf: d.appendingPathComponent("pieces-routeurs.json")) == Data(v1.utf8))
        #expect(try String(contentsOf: url, encoding: .utf8).contains(#""thread:HomePod 1" : "Cuisine""#))
    }
}
