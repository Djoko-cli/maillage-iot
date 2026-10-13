import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Identites des routeurs gardees d'un lancement a l'autre")
struct IdentitesGardeesTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Fichier jetable, dans un dossier temporaire qui n'existe pas encore.
    static func fichierTemporaire() -> (dossier: URL, fichier: URL) {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        return (dossier, dossier.appendingPathComponent("identites-routeurs.json"))
    }

    /// Le fichier : la partition, et chaque ExtMac sous son RLOC16 en 4 hexa ; absent ou
    /// illisible, rien ; un RLOC16 illisible est ignore (ExtMac inventees).
    @Test func fichier() throws {
        let (dossier, url) = Self.fichierTemporaire()
        defer { try? FileManager.default.removeItem(at: dossier) }
        #expect(IdentitesGardees.lire(url) == nil, "absent")
        let g = IdentitesGardees(partition: "46CBEBCD", identites: [0xAC00: "E000000000000007", 0x0400: "E0000000000000D1"])
        try g.ecrire(dans: url)
        #expect(IdentitesGardees.lire(url) == g)
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains("\"AC00\"") && texte.contains("\"0400\"") && texte.contains("46CBEBCD"))
        try Data(#"{"partition":"46CBEBCD","routeurs":{"AC00":"E000000000000007","XYZ!":"E0000000000000FF"}}"#.utf8)
            .write(to: url)
        #expect(IdentitesGardees.lire(url) == IdentitesGardees(partition: "46CBEBCD", identites: [0xAC00: "E000000000000007"]))
        try Data("pas du json".utf8).write(to: url)
        #expect(IdentitesGardees.lire(url) == nil, "illisible")
    }

    /// Memoire au lancement : les identites gardees servent des la premiere tournee dans leur
    /// partition (le routeur 57, muet et que la sonde n'entend plus, garde son ExtMac) ; ce qui
    /// se garde ensuite les reprend avec celles de la tournee.
    @Test func memePartition() async throws {
        let g = IdentitesGardees(partition: "46CBEBCD", identites: [0xE400: "E0000000000000E4"])
        let mem = MemoireTournee(identites: g)
        #expect(mem.partition == "46CBEBCD" && mem.identites == g.identites)
        let sonde = try SondeRejouee.capture()
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(m.routeur(57)?.extMac == "E0000000000000E4")
        let gardees = try #require(mem2.identitesGardees)
        #expect(gardees.partition == "46CBEBCD")
        #expect(gardees.identites[0xE400] == "E0000000000000E4")
        #expect(gardees.identites[0xAC00] == "E000000000000007", "le parent de la sonde")
        #expect(MemoireTournee().identitesGardees == nil, "avant la premiere tournee : rien a garder")
    }

    /// Identites gardees d'une autre partition : effacees a la premiere tournee, comme la memoire.
    @Test func autrePartition() async throws {
        let g = IdentitesGardees(partition: "73586B68", identites: [0xE400: "E0000000000000E4"])
        let sonde = try SondeRejouee.capture()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(identites: g),
                                                              maintenant: Self.t0))
        #expect(m.routeur(57)?.extMac == nil)
        #expect(mem.identitesGardees?.partition == "46CBEBCD")
        #expect(mem.identitesGardees?.identites[0xE400] == nil)
    }
}
