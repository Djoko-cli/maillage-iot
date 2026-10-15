import Foundation
import Testing
@testable import MaillageCoeur

/// Les surnoms (`surnoms.json`) : `{"version": 1, "surnoms": {"<protocole>:<cle>": "..."}}`, qui lit encore le
/// dictionnaire plat d'avant (cles brutes d'un seul protocole). Valeurs inventees.
@Suite("Surnoms : fichier commun par identifiant de noeud")
struct SurnomsTests {
    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("surnoms-\(UUID().uuidString)")
    }

    static let plat = #"{"AAAA000000000001":"Lampe 1","Apple TV 4K":"Salon"}"#

    /// Ecrit puis relu, sous la forme `{version, surnoms}` ; chaque cle porte son protocole.
    @Test func formatVersion1() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("sous/surnoms.json")
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [:], "absent")
        let s = [idt("AAAA000000000001"): "Lampe 1", idz("00124B0000000001"): "Lampe 2", idt("instance:Salon"): "Salon"]
        try Surnoms.ecrire(s, dans: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == s)
        #expect(Surnoms.lire(url, protocoleParDefaut: .zigbee) == s, "le protocole par defaut ne sert qu'a l'ancien format")
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains(#""version" : 1"#) && texte.contains(#""thread:AAAA000000000001" : "Lampe 1""#)
                && texte.contains(#""zigbee:00124B0000000001" : "Lampe 2""#) && texte.contains(#""thread:instance:Salon" : "Salon""#),
                "\(texte)")
    }

    /// L'ancien dictionnaire plat (Maillage Thread 1.3, Maillage Zigbee 1.1.1) se relit : ses cles brutes prennent le
    /// protocole de l'app. Une ecriture le passe au nouveau format, sans mettre l'ancien de cote (il etait lisible).
    @Test func ancienFormatPlatRelu() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("surnoms.json")
        try Data(Self.plat.utf8).write(to: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread)
                == [idt("AAAA000000000001"): "Lampe 1", idt("Apple TV 4K"): "Salon"])
        #expect(Surnoms.lire(url, protocoleParDefaut: .zigbee)
                == [idz("AAAA000000000001"): "Lampe 1", idz("Apple TV 4K"): "Salon"], "l'app Zigbee d'avant")
        var s = Surnoms.lire(url, protocoleParDefaut: .thread)
        s[idt("BBBB000000000002")] = "Lampe 3"
        try Surnoms.ecrire(s, dans: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .zigbee) == s, "reecrit au format de la version 1")
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path) == ["surnoms.json"], "rien mis de cote")
        // Un dictionnaire plat vide (tous les surnoms retires) se lit aussi.
        try Data("{}".utf8).write(to: url)
        #expect(Surnoms.lire(url, protocoleParDefaut: .thread) == [:])
    }

    /// Les cles d'un protocole, en cles brutes, pour le module qui les nomme.
    @Test func clesBrutesDUnProtocole() {
        let s = [idt("A1"): "Lampe 1", idz("B2"): "Lampe 2", idt("instance:Salon"): "Salon"]
        #expect(Surnoms.cles(de: s, protocole: .thread) == ["A1": "Lampe 1", "instance:Salon": "Salon"])
        #expect(Surnoms.cles(de: s, protocole: .zigbee) == ["B2": "Lampe 2"])
    }
}
