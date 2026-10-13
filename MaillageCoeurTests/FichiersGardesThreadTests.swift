import Foundation
import Testing
@testable import MaillageCoeur

/// Le fichier garde propre a Thread (`identites-routeurs.json`) suit la meme regle que les autres fichiers gardes
/// (voir `FichiersGardesTests` du coeur) : illisible, il est mis de cote avant d'etre remplace ; le cas ordinaire ne change pas.
@Suite("Fichiers gardes Thread : identites des routeurs")
struct FichiersGardesThreadTests {
    static let sortes = [
        AidesThread.SorteGardee(nom: "identites-routeurs.json") { url in
            var g = IdentitesGardees.lire(url) ?? IdentitesGardees(partition: "0000000A", identites: [:])
            g.identites[0x0400] = "E0000000000000A1"
            try g.ecrire(dans: url)
            return IdentitesGardees.lire(url) == g
        },
    ]

    /// Un fichier illisible, mais present, est lu comme vide ; a la premiere ecriture, il est mis de
    /// cote (renomme `<nom>.illisible-AAAAMMJJ-HHMMSS.json` dans le meme dossier, son contenu intact),
    /// puis remplace par le fichier ecrit. La suivante ne met plus rien de cote.
    @Test(arguments: sortes)
    func illisibleMisDeCote(_ sorte: AidesThread.SorteGardee) throws {
        let d = AidesThread.dossierGarde()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent(sorte.nom)
        let abime = Data("{pas du json".utf8)
        try abime.write(to: url)
        #expect(try sorte.allerRetour(url))
        let noms = try AidesThread.nomsDuDossier(d)
        let base = url.deletingPathExtension().lastPathComponent
        let mis = noms.filter { $0 != sorte.nom }
        #expect(noms.contains(sorte.nom) && mis.count == 1, "\(noms)")
        let deCote = try #require(mis.first)
        #expect(deCote.wholeMatch(of: /(.+)\.illisible-\d{8}-\d{6}\.json/)?.output.1 == Substring(base), "\(deCote)")
        #expect(try Data(contentsOf: d.appendingPathComponent(deCote)) == abime, "son contenu intact")
        #expect(try sorte.allerRetour(url))
        #expect(try AidesThread.nomsDuDossier(d) == noms, "rien de plus mis de cote")
    }

    /// Le cas ordinaire ne change pas : absent, le fichier est ecrit ; lisible et d'une version connue,
    /// il est relu et reecrit a sa place, sans rien mettre de cote.
    @Test(arguments: sortes)
    func casOrdinaire(_ sorte: AidesThread.SorteGardee) throws {
        let d = AidesThread.dossierGarde()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent(sorte.nom)
        #expect(try sorte.allerRetour(url), "absent")
        #expect(try sorte.allerRetour(url), "lisible")
        #expect(try AidesThread.nomsDuDossier(d) == [sorte.nom])
    }
}
