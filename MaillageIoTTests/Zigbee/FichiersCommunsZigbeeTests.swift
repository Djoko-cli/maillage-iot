import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

/// Etape 3a, tache 4 : les fichiers communs et le journal par protocole, cote Zigbee. Valeurs inventees.
@MainActor
@Suite("Fichiers communs et journal par protocole (app Zigbee)")
struct FichiersCommunsZigbeeTests {
    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("communs-\(UUID().uuidString)")
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let ieee = "A0000000000000D1"

    static func parent(_ minutes: Double, protocole: Protocole?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange,
                  sujet: Sujet(id: ieee, nom: "Lampe 1"), avant: "A", apres: "B", protocole: protocole)
    }

    /// Site 9 : un surnom de Zigbee se garde sous `zigbee:<IEEE>` dans `surnoms.json` (version 1) et le resolveur de Zigbee
    /// le lit sous sa cle brute ; un noeud Thread de meme cle est un autre noeud, et ses surnoms restent dans le fichier.
    /// (Le `surnoms.json` plat de Maillage Zigbee 1.1.1 ne se lit plus `zigbee:` : un fichier plat est celui de Thread 1.3,
    /// `FichiersCommunsTests.surnomsDeLAncienFormatPlat` ; celui de Zigbee 1.1.1 se relira a l'import, etape 4.)
    @Test func surnomsSousLIdentifiantDeNoeudZigbee() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("surnoms.json")
        try Data("{\"surnoms\":{\"zigbee:\(Self.ieee)\":\"Lampe 1\"},\"version\":1}".utf8).write(to: url)
        let s = Surveillance(mode: .direct, dossier: d)
        #expect(s.zigbee.noms.surnoms == [Self.ieee: "Lampe 1"] && s.surnom(de: idz(Self.ieee)) == "Lampe 1")
        #expect(s.surnom(de: idt(Self.ieee)) == nil, "un noeud Thread de meme cle est un autre noeud")
        s.renommer(idz("A0000000000000D2"), en: " Lampe 2 ")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread)
                == [idz(Self.ieee): "Lampe 1", idz("A0000000000000D2"): "Lampe 2"])
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains(#""version" : 1"#) && texte.contains("\"zigbee:\(Self.ieee)\" : \"Lampe 1\""), "\(texte)")
        // Un surnom de Thread lu dans le fichier reste dans le fichier.
        s.renommer(idt("AAAA000000000001"), en: "Lampe T")
        #expect(s.zigbee.noms.surnoms[ "AAAA000000000001"] == nil, "le resolveur de Zigbee ne voit que ses cles")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread)[idt("AAAA000000000001")] == "Lampe T")
    }

    /// Site 6 : le journal d'un noeud compare l'id du sujet (ou `details["ieee"]`) a la cle du noeud ET le protocole de
    /// l'evenement (sans protocole : Thread, donc pas Zigbee).
    @Test func journalDUnNoeudSelonLeProtocole() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let journal = JournalFichiers(dossier: d.appendingPathComponent("Journal"), politique: Surveillance.politiqueJournal)
        let zigbee = Self.parent(0, protocole: .zigbee)
        let thread = Self.parent(1, protocole: .thread)
        let sans = Self.parent(2, protocole: nil)
        try journal.ajouter([zigbee, thread, sans])
        let s = Surveillance(mode: .direct, dossier: d)
        s.chargerJournal()
        #expect(s.evenements.count == 3)
        #expect(s.evenements(de: idz(Self.ieee)) == [zigbee], "seul l'evenement de Zigbee")
        #expect(s.evenements(de: idt(Self.ieee)) == [sans, thread], "Thread et sans protocole : pas ceux d'un noeud Zigbee")
        #expect(s.lignesJournal(de: idz(Self.ieee)).map(\.evenements.count) == [1])
        // Un evenement qui porte l'adresse longue dans ses details compte aussi, pour son protocole.
        var ieee = Self.parent(3, protocole: .zigbee)
        ieee.sujet = Sujet(id: "~1A2B", nom: "Lampe 1")
        ieee.details = ["ieee": Self.ieee]
        try journal.ajouter([ieee])
        let s2 = Surveillance(mode: .direct, dossier: d)
        s2.chargerJournal()
        #expect(s2.evenements(de: idz(Self.ieee)) == [ieee, zigbee])
    }

    /// Les evenements de Zigbee entrent au journal avec `protocole = zigbee`, sur disque aussi.
    @Test func evenementsEcritsAvecLeProtocole() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let s = Surveillance(mode: .direct, dossier: d)
        s.noterVeille(debut: Self.t0, fin: Self.t0.addingTimeInterval(60))
        // Chaque modele note la veille du Mac dans son journal : celui de Zigbee a son evenement, avec son protocole.
        #expect(s.evenements.map(\.protocole) == [.thread, .zigbee])
        let relus = try JournalFichiers(dossier: d.appendingPathComponent("Journal"),
                                        politique: Surveillance.politiqueJournal).lire()
        #expect(relus == s.evenements)
        let fichier = try #require(try FileManager.default.contentsOfDirectory(at: d.appendingPathComponent("Journal"),
                                                                              includingPropertiesForKeys: nil).first)
        #expect(try String(contentsOf: fichier, encoding: .utf8).contains(#""protocole":"zigbee""#))
    }

    /// Les pieces choisies : `pieces-noeuds.json` (version 2) ; tant qu'il est absent, le `pieces-routeurs.json` d'avant
    /// (version 1, cles brutes) est relu comme celui de Thread, et jamais reecrit (celui de Zigbee 1.1.1 se relira a
    /// l'import, etape 4). Le choix d'un noeud Zigbee s'ecrit sous `zigbee:<IEEE>`, a cote des anciens choix.
    @Test func piecesChoisiesRelisentLAncienFichier() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let v1 = "{\"appareils\":{\"Maison\":{\"\(Self.ieee)\":\"Salon\"}},\"version\":1}"
        try Data(v1.utf8).write(to: d.appendingPathComponent("pieces-routeurs.json"))
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let choisies = PiecesChoisies(fichier: url)
        #expect(choisies.pieceChoisie(.appareil(idt(Self.ieee)), domicile: "Maison") == "Salon", "un fichier d'avant est celui de Thread")
        #expect(choisies.pieceChoisie(.appareil(idz(Self.ieee)), domicile: "Maison") == nil, "pas un noeud Zigbee")
        choisies.choisir("Bureau", .appareil(idz("A0000000000000D2")), domicile: "Maison")
        let relu = PiecesChoisies(fichier: url)
        #expect(relu.pieceChoisie(.appareil(idt(Self.ieee)), domicile: "Maison") == "Salon")
        #expect(relu.pieceChoisie(.appareil(idz("A0000000000000D2")), domicile: "Maison") == "Bureau")
        #expect(try Data(contentsOf: d.appendingPathComponent("pieces-routeurs.json")) == Data(v1.utf8))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("\"zigbee:A0000000000000D2\" : \"Bureau\""))
    }
}
