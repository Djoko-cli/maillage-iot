import Foundation
import MaillageCoeur
import Testing

/// Phase 4, tache 2 : les exports d'exemple provisoires de Maillage Thread 1.3.0 et de Maillage Zigbee 1.1.1
/// (`MaillageIoTTests/Ressources/exports/`), leur generateur (`outils/exports-exemple/Generateur.swift`) et leur
/// couverture de l'inventaire. Valeurs inventees seulement. La date de reference des essais est
/// `GenerateurExportsExemple.dateReference` (2026-10-17 12:00 UTC).
@Suite("Exports d'exemple provisoires : contrat, generateur, inventaire")
struct ExportsExempleTests {
    typealias C = ContratExport
    typealias G = GenerateurExportsExemple

    private final class Ancre {}

    /// Le dossier `exports` du paquet de test.
    static func racine() throws -> URL {
        try #require(Bundle(for: Ancre.self).url(forResource: "exports", withExtension: nil), "dossier exports absent du paquet")
    }

    static func dossier(_ app: C.AppSource) throws -> URL {
        try racine().appendingPathComponent(G.nomDossier(app), isDirectory: true)
    }

    /// Les fichiers (chemins relatifs) d'un dossier, triés.
    static func fichiers(de dossier: URL) throws -> [String] {
        let base = dossier.resolvingSymlinksInPath().path + "/"
        let liste = FileManager.default.enumerator(at: dossier.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])
        var chemins: [String] = []
        while let url = liste?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            chemins.append(String(url.resolvingSymlinksInPath().path.dropFirst(base.count)))
        }
        return chemins.sorted()
    }

    static func lignes(_ chemin: String, dans dossier: URL) throws -> [Data] {
        let texte = try String(contentsOf: dossier.appendingPathComponent(chemin), encoding: .utf8)
        return texte.split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
    }

    @Test(arguments: C.AppSource.allCases)
    func leContratAccepteLExport(app: C.AppSource) throws {
        let (manifeste, reglages) = try C.verifierDossier(Self.dossier(app))
        #expect(manifeste.app == app)
        #expect(reglages.app == app)
        #expect(manifeste.versionApp == G.versionApp(app))
        #expect(manifeste.date == G.dateReference)
        #expect(manifeste.identifiant == G.identifiant(app))
        #expect(manifeste.fichiers.contains { $0.chemin == C.nomReglages })
    }

    @Test(arguments: C.AppSource.allCases)
    func leGenerateurReproduitLesOctetsCommites(app: C.AppSource) throws {
        let sortie = FileManager.default.temporaryDirectory.appendingPathComponent("exports-exemple-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sortie) }
        let neuf = sortie.appendingPathComponent(G.nomDossier(app))
        try G.ecrire(app, dans: neuf)
        let commite = try Self.dossier(app)
        let chemins = try Self.fichiers(de: commite)
        #expect(chemins == (try Self.fichiers(de: neuf)))
        for chemin in chemins {
            let a = try Data(contentsOf: commite.appendingPathComponent(chemin))
            let b = try Data(contentsOf: neuf.appendingPathComponent(chemin))
            #expect(a == b, "\(chemin) differe du generateur : relancer outils/generer-exports-exemple.sh")
        }
    }

    @Test(arguments: C.AppSource.allCases)
    func chaqueFichierDeLInventaireEstPresent(app: C.AppSource) throws {
        let (manifeste, _) = try C.verifierDossier(Self.dossier(app))
        for connu in C.fichiersConnus(de: app) {
            #expect(manifeste.fichiers.contains { connu.correspond($0.chemin) }, "\(connu.modele) absent de l'export")
        }
        // Rien d'autre que les fichiers connus et reglages.json.
        for f in manifeste.fichiers where f.chemin != C.nomReglages {
            #expect(C.estConnu(f.chemin, de: app), "\(f.chemin) inconnu du contrat")
        }
    }

    @Test(arguments: C.AppSource.allCases)
    func chaqueReglageDeLInventaireEstPresent(app: C.AppSource) throws {
        let (_, reglages) = try C.verifierDossier(Self.dossier(app))
        for connu in C.reglagesConnus(de: app) {
            #expect(reglages.valeurs[connu.cle]?.type == connu.type, "reglage \(connu.cle) absent ou d'un autre type")
        }
        #expect(reglages.valeurs.count == C.reglagesConnus(de: app).count)
        // Ce que l'app laisse sans le reprendre est cite, sans valeur.
        for cle in ["SUHasLaunchedBefore", "SULastCheckTime", "SUUpdateGroupIdentifier", "NSWindow Frame graphe",
                    "NSWindow Frame journal", "NSWindow Frame SUUpdateAlert2",
                    "NSWindow Frame com_apple_SwiftUI_Settings_window", "reglages.onglet"] {
            #expect(reglages.nonRepris[cle] == .horsContrat, "\(cle) non cite")
        }
        if app == .maillageThread { #expect(reglages.nonRepris["dossierNoms"] == .horsContrat) }
    }

    @Test(arguments: C.AppSource.allCases)
    func lesFichiersVusMaisNonCopiesSontCites(app: C.AppSource) throws {
        let (manifeste, _) = try C.verifierDossier(Self.dossier(app))
        let raisons = Dictionary(uniqueKeysWithValues: manifeste.fichiersNonRepris.map { ($0.chemin, $0.raison) })
        #expect(raisons[".DS_Store"] == .exclu)
        #expect(raisons.contains { $0.key.contains(".illisible-") && $0.value == .exclu })
        #expect(raisons.values.contains(.horsContrat))
        // Un fichier non repris n'est jamais copie.
        let presents = Set(try Self.fichiers(de: Self.dossier(app)))
        for chemin in raisons.keys { #expect(!presents.contains(chemin)) }
    }

    /// Mois fini depuis plus de 90 jours a `maintenant` (`FichiersMensuels.purger` : fin du mois + 90 jours < maintenant).
    static func estEcarte(_ mois: C.Mois, maintenant: Date) -> Bool {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC")!
        let debutSuivant = calendrier.date(from: DateComponents(year: mois.mois == 12 ? mois.annee + 1 : mois.annee,
                                                                month: mois.mois == 12 ? 1 : mois.mois + 1, day: 1))!
        return debutSuivant.addingTimeInterval(90 * 86_400) < maintenant
    }

    @Test(arguments: C.AppSource.allCases)
    func unHistoriqueEtUnJournalDePlusDe90JoursSontLa(app: C.AppSource) throws {
        let (manifeste, _) = try C.verifierDossier(Self.dossier(app))
        let mensuels = manifeste.fichiers.compactMap { f in C.mois(de: f.chemin).map { (f.chemin, $0) } }
        let ecartes = mensuels.filter { Self.estEcarte($0.1, maintenant: G.dateReference) }.map(\.0)
        let gardes = mensuels.filter { !Self.estEcarte($0.1, maintenant: G.dateReference) }.map(\.0)
        #expect(ecartes.contains("maillage-2026-04.jsonl"))
        #expect(ecartes.contains("Journal/journal-2026-04.jsonl"))
        #expect(gardes.contains("maillage-2026-10.jsonl"))
        #expect(gardes.contains("Journal/journal-2026-10.jsonl"))
        if app == .maillageThread { #expect(gardes.contains("maillage-2026-07.jsonl")) }
    }

    @Test(arguments: C.AppSource.allCases)
    func lesLignesDuJournalNOntPasDeProtocole(app: C.AppSource) throws {
        let dossier = try Self.dossier(app)
        let (manifeste, _) = try C.verifierDossier(dossier)
        var types = Set<String>()
        for f in manifeste.fichiers where f.chemin.hasPrefix("Journal/") {
            let lignes = try Self.lignes(f.chemin, dans: dossier)
            #expect(!lignes.isEmpty)
            for l in lignes {
                let objet = try #require(JSONSerialization.jsonObject(with: l) as? [String: Any])
                #expect(objet["protocole"] == nil, "ligne avec protocole dans \(f.chemin)")
                #expect(objet["date"] is String)
                types.insert(try #require(objet["type"] as? String))
            }
        }
        if app == .maillageZigbee {
            #expect(types.isSuperset(of: ["cheminChange", "parentChange", "surveillanceDemarree", "veille"]))
        }
    }

    @Test(arguments: C.AppSource.allCases)
    func tousLesFichiersSontDuJSONValide(app: C.AppSource) throws {
        let dossier = try Self.dossier(app)
        for chemin in try Self.fichiers(de: dossier) {
            if chemin.hasSuffix(".json") {
                _ = try JSONSerialization.jsonObject(with: Data(contentsOf: dossier.appendingPathComponent(chemin)))
            } else if chemin.hasSuffix(".jsonl") {
                let donnees = try Data(contentsOf: dossier.appendingPathComponent(chemin))
                #expect(donnees.last == 0x0A, "\(chemin) ne finit pas par un saut de ligne")
                for l in try Self.lignes(chemin, dans: dossier) { _ = try JSONSerialization.jsonObject(with: l) }
            }
        }
    }

    @Test func lesFormatsPropresACadaAppSontReproduits() throws {
        let thread = try Self.dossier(.maillageThread), zigbee = try Self.dossier(.maillageZigbee)
        func objet(_ chemin: String, _ dossier: URL) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(contentsOf: dossier.appendingPathComponent(chemin))) as? [String: Any])
        }
        // Surnoms de Thread : cles brutes de trois formes (hote d'appareil, instance:, rloc:) ; plats, sans version.
        let surnomsThread = try objet("surnoms.json", thread)
        #expect(surnomsThread["version"] == nil)
        #expect(surnomsThread.keys.contains { $0.hasPrefix("instance:") } && surnomsThread.keys.contains { $0.hasPrefix("rloc:") })
        #expect(!surnomsThread.keys.contains { $0.hasPrefix("thread:") || $0.hasPrefix("zigbee:") })
        // Pieces de Thread : routeurs (maisons) et autres noeuds (appareils) ; de Zigbee : appareils seulement.
        let piecesThread = try objet("pieces-routeurs.json", thread), piecesZigbee = try objet("pieces-routeurs.json", zigbee)
        #expect(piecesThread["maisons"] != nil && piecesThread["appareils"] != nil)
        #expect(piecesZigbee["maisons"] == nil && piecesZigbee["appareils"] != nil)
        // Zigbee : un domicile est l'identifiant du pont (16 hexa), l'autre un nom de maison.
        let domicilesZigbee = try #require(piecesZigbee["appareils"] as? [String: Any]).keys
        #expect(domicilesZigbee.contains { $0.count == 16 && $0.allSatisfy(\.isHexDigit) })
        #expect(domicilesZigbee.contains { !$0.allSatisfy(\.isHexDigit) })
        // Deux releves de Maison (v2) : noms.json de Thread, releve-maison.json de Zigbee, et le cache du pont (v1).
        #expect(try objet("noms.json", thread)["version"] as? Int == 2)
        #expect(try objet("releve-maison.json", zigbee)["version"] as? Int == 2)
        #expect(try objet("noms-pont.json", zigbee)["version"] as? Int == 1)
        // Zigbee : le dernier maillage porte `incomplet` ; Thread n'a pas ce champ.
        #expect(try objet("dernier-maillage.json", zigbee)["incomplet"] is Bool)
        #expect(try objet("dernier-maillage.json", thread)["incomplet"] == nil)
        // La premiere ligne de l'historique de Zigbee n'a pas de chemins (releve d'avant les chemins).
        let avril = try #require(try Self.lignes("maillage-2026-04.jsonl", dans: zigbee).first)
        #expect(try #require(JSONSerialization.jsonObject(with: avril) as? [String: Any])["chemins"] == nil)
    }

    @Test(arguments: C.AppSource.allCases)
    func aucuneValeurReelleNiChemin(app: C.AppSource) throws {
        let dossier = try Self.dossier(app)
        for chemin in try Self.fichiers(de: dossier) {
            let texte = try String(contentsOf: dossier.appendingPathComponent(chemin), encoding: .utf8)
            #expect(!texte.contains("/Users/"), "\(chemin) contient un chemin de dossier personnel")
            #expect(!texte.contains("@"), "\(chemin) contient un arobase (adresse electronique ?)")
        }
    }
}
