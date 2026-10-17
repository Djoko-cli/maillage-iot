import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Phase 4, tache 3 : la validation d'un export par l'app (`ValidationExport`). Le contrat fait le controle complet du
/// dossier (`ContratExport.verifierDossier`) ; ici on verifie que chaque erreur du contrat devient une cause lisible,
/// que la version de l'app source est controlee, que l'export deja repris est reconnu (`imports.json`) et que le
/// resume pour l'assistant est juste. Les cas alteres sont batis dans des copies temporaires des deux exemples
/// (`MaillageIoTTests/Ressources/exports`). Valeurs inventees seulement.
@Suite("Validation d'un export de reprise")
struct ValidationExportTests {
    typealias C = ContratExport
    typealias Cause = CauseRefus

    // MARK: Outils

    /// Une copie temporaire d'un export d'exemple, effacee a la fin du test.
    final class Copie {
        let racine: URL
        let dossier: URL
        let app: C.AppSource

        init(_ app: C.AppSource) throws {
            self.app = app
            racine = FileManager.default.temporaryDirectory.appendingPathComponent("validation-\(UUID().uuidString)")
            dossier = racine.appendingPathComponent("export", isDirectory: true)
            try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: try ExportsExempleTests.dossier(app), to: dossier)
        }

        deinit { try? FileManager.default.removeItem(at: racine) }

        func url(_ chemin: String) -> URL { dossier.appendingPathComponent(chemin) }

        /// Modifie le manifeste (objet JSON) puis le reecrit.
        func modifierManifeste(_ f: (inout [String: Any]) throws -> Void) throws {
            let u = url(C.nomManifeste)
            var objet = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: u)) as? [String: Any])
            try f(&objet)
            try JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys]).write(to: u)
        }

        /// Modifie la ligne `chemin` de la liste des fichiers du manifeste.
        func modifierLigne(_ chemin: String, _ f: (inout [String: Any]) -> Void) throws {
            try modifierManifeste { objet in
                var liste = try #require(objet["fichiers"] as? [[String: Any]])
                let i = try #require(liste.firstIndex { $0["chemin"] as? String == chemin }, "ligne \(chemin) absente")
                f(&liste[i])
                objet["fichiers"] = liste
            }
        }

        /// Reecrit un fichier et met le manifeste d'accord (taille et empreinte), pour que seul le contenu change.
        func remplacer(_ chemin: String, par octets: Data) throws {
            try octets.write(to: url(chemin))
            try modifierLigne(chemin) { ligne in
                ligne["taille"] = octets.count
                ligne["sha256"] = C.sha256(octets)
            }
        }
    }

    static func valider(_ copie: Copie, imports: JournalImports = .vide) -> ResultatValidation {
        ValidationExport.valider(dossier: copie.dossier, imports: imports)
    }

    /// La cause du refus, ou echec du test.
    static func refus(_ copie: Copie, imports: JournalImports = .vide, ligne: UInt = #line) throws -> CauseRefus {
        switch valider(copie, imports: imports) {
        case .refuse(let cause): return cause
        case .acceptee: throw Echec("export accepte alors qu'il devait etre refuse (ligne \(ligne))")
        case .dejaRepris: throw Echec("export 'deja repris' alors qu'il devait etre refuse (ligne \(ligne))")
        }
    }

    struct Echec: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    // MARK: Les deux exemples sont acceptes

    @Test(arguments: C.AppSource.allCases)
    func lesExemplesSontAcceptes(app: C.AppSource) throws {
        let resultat = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(app), imports: .vide)
        guard case .acceptee(let resume) = resultat else { throw Echec("refuse : \(resultat)") }
        #expect(resume.app == app)
        #expect(resume.identifiant == GenerateurExportsExemple.identifiant(app))
        #expect(resume.versionApp == GenerateurExportsExemple.versionApp(app))
        #expect(resume.date == GenerateurExportsExemple.dateReference)
    }

    // MARK: Resume pour l'assistant

    @Test(arguments: [(C.AppSource.maillageThread, [1, 2, 1, 4, 4, 2], 15, 14, 4),
                      (C.AppSource.maillageZigbee, [1, 2, 1, 3, 2, 2], 18, 14, 3)])
    func leResumeCompteChaqueGenre(app: C.AppSource, comptes: [Int], repris: Int, nonRepris: Int, citesFichiers: Int) throws {
        let resultat = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(app), imports: .vide)
        guard case .acceptee(let resume) = resultat else { throw Echec("refuse : \(resultat)") }
        let ordre: [GenreContenu] = [.surnoms, .pieces, .nomsMaison, .etatDesModules, .historiqueSonde, .journal]
        for (genre, attendu) in zip(ordre, comptes) { #expect(resume.nombre(genre) == attendu, "\(genre)") }
        #expect(resume.nombre(.autres) == 0)
        #expect(resume.reglagesRepris == repris)
        #expect(resume.reglagesNonRepris.count == nonRepris)
        #expect(resume.reglagesNonRepris["SUHasLaunchedBefore"] == .horsContrat)
        #expect(resume.fichiersNonRepris.count == citesFichiers)
        #expect(resume.fichiersNonRepris.contains(.init(chemin: ".DS_Store", raison: .exclu)))
    }

    @Test(arguments: C.AppSource.allCases)
    func leResumeCompteTousLesFichiersEtLeurTaille(app: C.AppSource) throws {
        let dossier = try ExportsExempleTests.dossier(app)
        let (manifeste, _) = try C.verifierDossier(dossier)
        guard case .acceptee(let resume) = ValidationExport.valider(dossier: dossier, imports: .vide) else {
            throw Echec("refuse")
        }
        // Tous les fichiers listes, reglages.json compris, sont comptes quelque part : rien ne manque au total.
        let parGenre = GenreContenu.allCases.reduce(0) { $0 + resume.nombre($1) }
        #expect(parGenre + 1 == manifeste.fichiers.count, "les fichiers sans genre, plus reglages.json")
        #expect(resume.tailleTotale == manifeste.fichiers.reduce(0) { $0 + $1.taille })
    }

    @Test(arguments: C.AppSource.allCases)
    func chaqueFichierConnuADeGenre(app: C.AppSource) throws {
        let (manifeste, _) = try C.verifierDossier(ExportsExempleTests.dossier(app))
        for f in manifeste.fichiers where f.chemin != C.nomReglages {
            #expect(GenreContenu.genre(de: f.chemin) != .autres, "\(f.chemin) sans genre")
        }
        #expect(GenreContenu.genre(de: "Journal/journal-2026-10.jsonl") == .journal)
        #expect(GenreContenu.genre(de: "maillage-2026-10.jsonl") == .historiqueSonde)
        #expect(GenreContenu.genre(de: "inconnu.json") == .autres)
    }

    // MARK: Refus : empreinte, taille, fichiers

    @Test(arguments: C.AppSource.allCases)
    func uneEmpreinteFausseEstRefusee(app: C.AppSource) throws {
        let copie = try Copie(app)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = String(repeating: "0", count: 64) }
        #expect(try Self.refus(copie) == .empreinteFausse("surnoms.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unOctetChangeEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        var octets = try Data(contentsOf: copie.url("surnoms.json"))
        octets[octets.startIndex] = octets[octets.startIndex] ^ 0x01
        try octets.write(to: copie.url("surnoms.json"))
        #expect(try Self.refus(copie) == .empreinteFausse("surnoms.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func uneTailleFausseEstRefusee(app: C.AppSource) throws {
        let copie = try Copie(app)
        try copie.modifierLigne("surnoms.json") { $0["taille"] = ($0["taille"] as? Int ?? 0) + 1 }
        #expect(try Self.refus(copie) == .tailleFausse("surnoms.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unFichierTronqueEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        let octets = try Data(contentsOf: copie.url("surnoms.json"))
        try octets.dropLast().write(to: copie.url("surnoms.json"))
        #expect(try Self.refus(copie) == .tailleFausse("surnoms.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unFichierManquantEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        try FileManager.default.removeItem(at: copie.url("Journal/journal-2026-10.jsonl"))
        #expect(try Self.refus(copie) == .fichierManquant("Journal/journal-2026-10.jsonl"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unFichierEnTropEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        try Data("{}".utf8).write(to: copie.url("en-trop.json"))
        #expect(try Self.refus(copie) == .fichierEnTrop("en-trop.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unFichierEnTropDansUnSousDossierEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        try Data("{}".utf8).write(to: copie.url("Journal/journal-2026-11.jsonl"))
        #expect(try Self.refus(copie) == .fichierEnTrop("Journal/journal-2026-11.jsonl"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unFichierListeMaisInconnuEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        let octets = Data("{}".utf8)
        try octets.write(to: copie.url("bidule.json"))
        try copie.modifierManifeste { objet in
            var liste = try #require(objet["fichiers"] as? [[String: Any]])
            liste.append(["chemin": "bidule.json", "taille": octets.count, "sha256": C.sha256(octets)])
            objet["fichiers"] = liste
        }
        #expect(try Self.refus(copie) == .fichierInconnu("bidule.json"))
    }

    @Test(arguments: C.AppSource.allCases)
    func unLienSymboliqueEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        try FileManager.default.removeItem(at: copie.url("surnoms.json"))
        try FileManager.default.createSymbolicLink(at: copie.url("surnoms.json"),
                                                   withDestinationURL: copie.url("pieces-routeurs.json"))
        #expect(try Self.refus(copie) == .lienSymbolique("surnoms.json"))
    }

    // MARK: Refus : chemins qui sortent du dossier

    @Test(arguments: ["../evil.json", "Journal/../../evil.json", "/etc/hosts", "./surnoms.json", "a//b.json", "..",
                      "Journal/..\\x.json"])
    func unCheminQuiSortDuDossierEstRefuse(chemin: String) throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["chemin"] = chemin }
        #expect(try Self.refus(copie) == .cheminInvalide(chemin))
    }

    @Test
    func unCheminQuiSortParUnLienDuDossierEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        let dehors = copie.racine.appendingPathComponent("dehors", isDirectory: true)
        try FileManager.default.createDirectory(at: dehors, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: copie.url("Journal"))
        try FileManager.default.createSymbolicLink(at: copie.url("Journal"), withDestinationURL: dehors)
        #expect(try Self.refus(copie) == .lienSymbolique("Journal"))
    }

    // MARK: Refus : manifeste

    @Test
    func unDossierSansManifesteEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try FileManager.default.removeItem(at: copie.url(C.nomManifeste))
        #expect(try Self.refus(copie) == .manifesteAbsent)
    }

    @Test
    func unDossierQuiNExistePasEstRefuse() {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        #expect(ValidationExport.valider(dossier: absent, imports: .vide) == .refuse(.manifesteAbsent))
    }

    @Test
    func unManifesteIllisibleEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try Data("pas du JSON {".utf8).write(to: copie.url(C.nomManifeste))
        #expect(try Self.refus(copie) == .manifesteIllisible(.jsonInvalide))
    }

    @Test
    func unManifesteVideEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try Data().write(to: copie.url(C.nomManifeste))
        #expect(try Self.refus(copie) == .manifesteIllisible(.jsonInvalide))
    }

    @Test
    func unChampManquantDuManifesteEstDit() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { $0.removeValue(forKey: "versionApp") }
        #expect(try Self.refus(copie) == .manifesteIllisible(.champManquant("versionApp")))
    }

    @Test
    func unChampDuMauvaisTypeDuManifesteEstDit() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { $0["fichiers"] = "aucun" }
        #expect(try Self.refus(copie) == .manifesteIllisible(.typeInattendu("fichiers")))
    }

    @Test
    func unFormatInconnuEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { $0["format"] = 2 }
        #expect(try Self.refus(copie) == .formatInconnu(2))
    }

    @Test
    func uneAppSourceInconnueEstRefusee() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { $0["app"] = "domotique" }
        #expect(try Self.refus(copie) == .appInconnue("domotique"))
    }

    @Test
    func uneEmpreinteMalFormeeEstRefusee() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = "XYZ" }
        #expect(try Self.refus(copie) == .empreinteInvalide("surnoms.json"))
    }

    @Test
    func uneTailleNegativeEstRefusee() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["taille"] = -1 }
        #expect(try Self.refus(copie) == .tailleInvalide("surnoms.json"))
    }

    @Test
    func unCheminEnDoubleEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { objet in
            var liste = try #require(objet["fichiers"] as? [[String: Any]])
            liste.append(try #require(liste.first { $0["chemin"] as? String == "surnoms.json" }))
            objet["fichiers"] = liste
        }
        #expect(try Self.refus(copie) == .cheminEnDouble("surnoms.json"))
    }

    @Test
    func leNomReserveDuManifesteEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["chemin"] = "Manifeste.json" }
        #expect(try Self.refus(copie) == .nomReserve("Manifeste.json"))
    }

    // MARK: Refus : reglages.json

    @Test(arguments: C.AppSource.allCases)
    func unManifesteSansReglagesEstRefuse(app: C.AppSource) throws {
        let copie = try Copie(app)
        try copie.modifierManifeste { objet in
            objet["fichiers"] = try #require(objet["fichiers"] as? [[String: Any]])
                .filter { $0["chemin"] as? String != C.nomReglages }
        }
        #expect(try Self.refus(copie) == .reglagesAbsents)
    }

    @Test
    func unReglagesListeMaisAbsentEstRefuse() throws {
        let copie = try Copie(.maillageZigbee)
        try FileManager.default.removeItem(at: copie.url(C.nomReglages))
        #expect(try Self.refus(copie) == .fichierManquant(C.nomReglages))
    }

    @Test
    func unReglagesIllisibleEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try copie.remplacer(C.nomReglages, par: Data("[1, 2".utf8))
        #expect(try Self.refus(copie) == .reglagesIllisibles(.jsonInvalide))
    }

    @Test
    func unReglagesDUneAutreAppEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        let autre = try Data(contentsOf: ExportsExempleTests.dossier(.maillageZigbee).appendingPathComponent(C.nomReglages))
        try copie.remplacer(C.nomReglages, par: autre)
        #expect(try Self.refus(copie) == .appDifferente)
    }

    @Test
    func unReglagesAuTypeInconnuEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        var objet = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: copie.url(C.nomReglages))) as? [String: Any])
        var valeurs = try #require(objet["valeurs"] as? [String: Any])
        valeurs["vuePieces3D"] = ["type": "date", "valeur": "x"]
        objet["valeurs"] = valeurs
        try copie.remplacer(C.nomReglages, par: JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys]))
        #expect(try Self.refus(copie) == .reglagesIllisibles(.typeInconnu(cle: "vuePieces3D", type: "date")))
    }

    @Test
    func unReglagesAvecUneCleEnDoubleEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        var objet = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: copie.url(C.nomReglages))) as? [String: Any])
        var non = try #require(objet["nonRepris"] as? [String: Any])
        non["vuePieces3D"] = "horsContrat"
        objet["nonRepris"] = non
        try copie.remplacer(C.nomReglages, par: JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys]))
        #expect(try Self.refus(copie) == .reglagesIllisibles(.cleEnDouble("vuePieces3D")))
    }

    // MARK: Version de l'app source

    @Test(arguments: [("1.3.0", true), ("1.3.7", true), ("1.4.0", true), ("1.4.12", true), ("1.3", true), ("1.4", true),
                      ("1.2.9", false), ("1.5.0", false), ("2.0.0", false), ("0.3.0", false), ("1", false),
                      ("", false), ("1.3.0-beta", false), ("1.3.x", false), ("1..3", false), ("1.3.0.", false),
                      ("v1.3.0", false), ("1.03.0", false), ("1.3.-1", false), (" 1.3.0", false), ("1.3.0 ", false),
                      ("1.3.0.0.0", false), ("١.٣.٠", false)])
    func laVersionDeThreadEstControlee(version: String, prise: Bool) {
        #expect(ValidationExport.versionEstPrise(version, de: .maillageThread) == prise, "\(version)")
    }

    @Test(arguments: [("1.1.0", true), ("1.1.1", true), ("1.2.0", true), ("1.2.5", true), ("1.0.9", false),
                      ("1.3.0", false), ("2.1.0", false), ("1.4.0", false)])
    func laVersionDeZigbeeEstControlee(version: String, prise: Bool) {
        #expect(ValidationExport.versionEstPrise(version, de: .maillageZigbee) == prise, "\(version)")
    }

    @Test(arguments: [("1.5.0", C.AppSource.maillageThread), ("2.0.0", .maillageThread), ("1.2.0", .maillageThread),
                      ("1.0.0", .maillageZigbee), ("1.3.0", .maillageZigbee), ("abc", .maillageZigbee)])
    func uneVersionNonPriseDeLAppSourceEstRefusee(version: String, app: C.AppSource) throws {
        let copie = try Copie(app)
        try copie.modifierManifeste { $0["versionApp"] = version }
        #expect(try Self.refus(copie) == .versionNonPrise(app: app, version: version))
    }

    @Test(arguments: [("1.4.0", C.AppSource.maillageThread), ("1.3.9", .maillageThread), ("1.2.0", .maillageZigbee),
                      ("1.1.0", .maillageZigbee)])
    func lesVersionsDesDernieresSeriesSontAcceptees(version: String, app: C.AppSource) throws {
        let copie = try Copie(app)
        try copie.modifierManifeste { $0["versionApp"] = version }
        guard case .acceptee(let resume) = Self.valider(copie) else { throw Echec("refuse") }
        #expect(resume.versionApp == version)
    }

    @Test
    func laVersionNonPriseSeDitAvantLesFichiersInconnus() throws {
        // Un export d'une version plus recente : la cause est la version, pas ses fichiers que l'on ne connait pas.
        let copie = try Copie(.maillageThread)
        try Data("{}".utf8).write(to: copie.url("nouveau-format.json"))
        try copie.modifierManifeste { $0["versionApp"] = "1.5.0" }
        #expect(try Self.refus(copie) == .versionNonPrise(app: .maillageThread, version: "1.5.0"))
    }

    // MARK: Deja repris

    @Test(arguments: C.AppSource.allCases)
    func unExportDejaReprisEstReconnu(app: C.AppSource) throws {
        let dossier = try ExportsExempleTests.dossier(app)
        let id = GenerateurExportsExemple.identifiant(app)
        let le = Date(timeIntervalSince1970: 1_790_000_000)
        let entree = ImportRepris(identifiant: id, app: app, versionApp: "1.4.0", date: le)
        let imports = JournalImports(imports: [ImportRepris(identifiant: UUID(), app: app, versionApp: "1.3.0", date: .distantPast),
                                               entree])
        guard case .dejaRepris(let repris, let resume) = ValidationExport.valider(dossier: dossier, imports: imports) else {
            throw Echec("pas reconnu comme deja repris")
        }
        #expect(repris == entree)
        #expect(resume.identifiant == id)
        #expect(resume.app == app)
    }

    @Test(arguments: C.AppSource.allCases)
    func unAutreIdentifiantNEstPasDejaRepris(app: C.AppSource) throws {
        let imports = JournalImports(imports: [ImportRepris(identifiant: UUID(), app: app, versionApp: "1.3.0", date: .now)])
        guard case .acceptee = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(app), imports: imports) else {
            throw Echec("refuse ou deja repris")
        }
    }

    @Test
    func unExportAltereNEstPasAccepteMemeDejaRepris() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = String(repeating: "f", count: 64) }
        let id = GenerateurExportsExemple.identifiant(.maillageThread)
        let imports = JournalImports(imports: [ImportRepris(identifiant: id, app: .maillageThread, versionApp: "1.3.0", date: .now)])
        #expect(try Self.refus(copie, imports: imports) == .empreinteFausse("surnoms.json"))
    }

    // MARK: imports.json

    @Test
    func sansFichierImportsLeJournalEstVide() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        #expect(try JournalImports.lire(dans: dossier) == .vide)
    }

    @Test
    func leJournalDesImportsSeRelit() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let journal = JournalImports(imports: [
            ImportRepris(identifiant: UUID(), app: .maillageZigbee, versionApp: "1.2.0", date: Date(timeIntervalSince1970: 1_790_000_000)),
            ImportRepris(identifiant: UUID(), app: .maillageThread, versionApp: "1.4.0", date: Date(timeIntervalSince1970: 1_790_000_100)),
        ])
        try journal.donnees().write(to: dossier.appendingPathComponent(JournalImports.nomFichier))
        #expect(try JournalImports.lire(dans: dossier) == journal)
        let texte = try String(contentsOf: dossier.appendingPathComponent("imports.json"), encoding: .utf8)
        #expect(texte.contains("\"version\" : 1"))
        #expect(texte.contains("\"zigbee\"") && texte.contains("\"thread\""))
    }

    @Test(arguments: ["pas du JSON", "{}", "{\"version\": 2, \"imports\": []}", "{\"version\": 1}",
                      "{\"version\": 1, \"imports\": [{\"identifiant\": \"x\"}]}", ""])
    func unJournalDesImportsIllisibleEstRefuse(contenu: String) throws {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        try Data(contenu.utf8).write(to: racine.appendingPathComponent("imports.json"))
        #expect(throws: (any Error).self) { try JournalImports.lire(dans: racine) }
        // Illisible : on ne sait pas si l'export est deja repris, donc on ne le laisse pas passer.
        let dossier = try ExportsExempleTests.dossier(.maillageThread)
        let chemin = racine.appendingPathComponent("imports.json").path
        let resultat = ValidationExport.valider(dossier: dossier, dossierDonnees: racine)
        #expect(resultat == .refuse(.journalDesImportsIllisible(chemin: chemin)))
        // La cause dit ou est le fichier (avec son dossier) et quoi faire.
        guard case .refuse(let cause) = resultat else { return }
        for langue in ["fr", "en"] {
            let texte = cause.texte(locale: Locale(identifier: langue))
            #expect(texte.contains(chemin), "chemin absent (\(langue)) : \(texte)")
            #expect(texte.contains("imports.json.abime"), "mise de cote non dite (\(langue)) : \(texte)")
        }
    }

    // MARK: Journal des imports abime : mise de cote

    static func dossierDonneesAvecJournal(_ contenu: String?) throws -> URL {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        if let contenu { try Data(contenu.utf8).write(to: racine.appendingPathComponent("imports.json")) }
        return racine
    }

    @Test(arguments: C.AppSource.allCases)
    func leJournalAbimeMisDeCotePermetDeReprendreCommeSiRienNAvaitEuLieu(app: C.AppSource) throws {
        let racine = try Self.dossierDonneesAvecJournal("{ pas du JSON")
        defer { try? FileManager.default.removeItem(at: racine) }
        let dossier = try ExportsExempleTests.dossier(app)
        guard case .refuse = ValidationExport.valider(dossier: dossier, dossierDonnees: racine) else { throw Echec("accepte") }
        let mis = try #require(try JournalImports.mettreDeCoteImportsAbime(dans: racine))
        #expect(mis.lastPathComponent == "imports.json.abime")
        #expect(mis.deletingLastPathComponent().path == racine.path)
        // Le fichier est renomme, jamais supprime ni modifie.
        #expect(try Data(contentsOf: mis) == Data("{ pas du JSON".utf8))
        #expect(!FileManager.default.fileExists(atPath: racine.appendingPathComponent("imports.json").path))
        guard case .acceptee(let resume) = ValidationExport.valider(dossier: dossier, dossierDonnees: racine) else {
            throw Echec("toujours refuse")
        }
        #expect(resume.app == app)
    }

    @Test
    func unJournalVideEstMisDeCoteAussi() throws {
        let racine = try Self.dossierDonneesAvecJournal("")
        defer { try? FileManager.default.removeItem(at: racine) }
        let mis = try #require(try JournalImports.mettreDeCoteImportsAbime(dans: racine))
        #expect(FileManager.default.fileExists(atPath: mis.path))
        guard case .acceptee = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(.maillageThread),
                                                        dossierDonnees: racine) else { throw Echec("refuse") }
    }

    @Test
    func uneCopieAbimeDejaPresenteNEstJamaisEcrasee() throws {
        let racine = try Self.dossierDonneesAvecJournal("premier")
        defer { try? FileManager.default.removeItem(at: racine) }
        let instant = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21T14:13:20Z
        let premier = try #require(try JournalImports.mettreDeCoteImportsAbime(dans: racine, date: instant))
        #expect(premier.lastPathComponent == "imports.json.abime")
        // Un second journal abime : le nom existe, la copie porte la date.
        try Data("second".utf8).write(to: racine.appendingPathComponent("imports.json"))
        let second = try #require(try JournalImports.mettreDeCoteImportsAbime(dans: racine, date: instant))
        #expect(second.lastPathComponent == "imports-20260921-141320.json.abime")
        // Un troisieme a la meme seconde : jamais le meme nom.
        try Data("troisieme".utf8).write(to: racine.appendingPathComponent("imports.json"))
        let troisieme = try #require(try JournalImports.mettreDeCoteImportsAbime(dans: racine, date: instant))
        #expect(Set([premier, second, troisieme].map(\.lastPathComponent)).count == 3)
        #expect(try Data(contentsOf: premier) == Data("premier".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
        #expect(try Data(contentsOf: troisieme) == Data("troisieme".utf8))
    }

    @Test
    func unJournalLisibleOuAbsentNEstPasMisDeCote() throws {
        // Seul un journal illisible se met de cote : un journal valide garde la trace des reprises deja faites.
        let valide = try JournalImports(imports: [ImportRepris(identifiant: UUID(), app: .maillageThread, versionApp: "1.4.0",
                                                               date: Date(timeIntervalSince1970: 1_790_000_000))]).donnees()
        let racine = try Self.dossierDonneesAvecJournal(String(decoding: valide, as: UTF8.self))
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect(try JournalImports.mettreDeCoteImportsAbime(dans: racine) == nil)
        #expect(try Data(contentsOf: racine.appendingPathComponent("imports.json")) == valide)
        let sans = try Self.dossierDonneesAvecJournal(nil)
        defer { try? FileManager.default.removeItem(at: sans) }
        #expect(try JournalImports.mettreDeCoteImportsAbime(dans: sans) == nil)
    }

    @Test
    func leDossierDeDonneesSansJournalLaissePasserLExport() throws {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        let resultat = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(.maillageZigbee), dossierDonnees: racine)
        guard case .acceptee = resultat else { throw Echec("refuse : \(resultat)") }
    }

    @Test
    func unExportReprisAvecLeJournalDuDisqueEstReconnu() throws {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        let id = GenerateurExportsExemple.identifiant(.maillageThread)
        let journal = JournalImports(imports: [ImportRepris(identifiant: id, app: .maillageThread, versionApp: "1.3.0",
                                                            date: Date(timeIntervalSince1970: 1_790_000_000))])
        try journal.donnees().write(to: racine.appendingPathComponent(JournalImports.nomFichier))
        let resultat = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(.maillageThread), dossierDonnees: racine)
        guard case .dejaRepris(let repris, _) = resultat else { throw Echec("pas deja repris : \(resultat)") }
        #expect(repris.identifiant == id)
    }

    // MARK: Messages : chaque cause se dit, en francais et en anglais

    /// Une cause de chaque forme.
    static let causes: [CauseRefus] = [
        .dossierIllisible, .manifesteAbsent, .manifesteIllisible(.jsonInvalide), .formatInconnu(2),
        .appInconnue("domotique"), .versionNonPrise(app: .maillageThread, version: "9.9.9"),
        .cheminInvalide("../x"), .lienSymbolique("x"), .empreinteInvalide("x"), .tailleInvalide("x"),
        .cheminEnDouble("x"), .nomReserve("manifeste.json"), .reglagesAbsents, .reglagesIllisibles(.champManquant("format")),
        .fichierManquant("x"), .fichierEnTrop("x"), .fichierInconnu("x"), .tailleFausse("x"), .empreinteFausse("x"),
        .appDifferente, .journalDesImportsIllisible(chemin: "/donnees/imports.json"),
        .versionNonPrise(app: .maillageZigbee, version: "1.0.0"), .versionNonPrise(app: .maillageThread, version: "1.4.0-beta"),
    ]

    @Test(arguments: causes)
    func chaqueCauseSeDitEnClair(cause: CauseRefus) {
        let texte = cause.message
        #expect(!texte.isEmpty)
        #expect(texte.hasSuffix("."), "\(texte)")
        #expect(!texte.contains("Optional"))
        #expect(!texte.contains("%"), "specificateur non rempli : \(texte)")
    }

    @Test
    func lesMessagesNommentLeFichierOuLeChamp() {
        #expect(CauseRefus.empreinteFausse("surnoms.json").message.contains("surnoms.json"))
        #expect(CauseRefus.tailleFausse("Journal/journal-2026-10.jsonl").message.contains("Journal/journal-2026-10.jsonl"))
        #expect(CauseRefus.fichierManquant("pieces-routeurs.json").message.contains("pieces-routeurs.json"))
        #expect(CauseRefus.fichierEnTrop("en-trop.json").message.contains("en-trop.json"))
        #expect(CauseRefus.cheminInvalide("../evil.json").message.contains("../evil.json"))
        #expect(CauseRefus.versionNonPrise(app: .maillageZigbee, version: "3.0.0").message.contains("3.0.0"))
        #expect(CauseRefus.versionNonPrise(app: .maillageZigbee, version: "3.0.0").message.contains("Maillage Zigbee"))
        #expect(CauseRefus.formatInconnu(7).message.contains("7"))
        #expect(CauseRefus.manifesteIllisible(.champManquant("versionApp")).message.contains("versionApp"))
    }

    @Test
    func unNomAffichePeutEtreHostile() {
        let long = String(repeating: "a", count: 500)
        let message = CauseRefus.fichierManquant(long + "\u{0007}\n").message
        #expect(message.count < 200)
        #expect(!message.contains("\u{0007}"))
        #expect(!message.contains("\n"))
    }

    /// Chaque message existe dans le catalogue de l'app, en francais et en anglais (traduit, pas recopie).
    @Test(arguments: causes)
    func chaqueCauseEstTraduite(cause: CauseRefus) {
        let fr = cause.texte(locale: Locale(identifier: "fr"))
        let en = cause.texte(locale: Locale(identifier: "en"))
        #expect(!fr.isEmpty && !en.isEmpty)
        #expect(fr != en, "non traduit : \(fr)")
        #expect(!en.contains("é") && !en.contains("è") && !en.contains("à"), "accent dans l'anglais : \(en)")
    }

    @Test(arguments: [DetailIllisible.jsonInvalide, .champManquant("c"), .typeInattendu("c"), .valeurAbsente("c"),
                      .valeurInvalide("c"), .valeurInvalide(nil), .lectureImpossible, .cleVide, .cleEnDouble("c"),
                      .typeInconnu(cle: "c", type: "t"), .autre("x")])
    func chaqueDetailEstTraduit(detail: DetailIllisible) {
        let fr = detail.texte(locale: Locale(identifier: "fr"))
        let en = detail.texte(locale: Locale(identifier: "en"))
        if case .autre = detail { #expect(fr == en) } else { #expect(fr != en, "non traduit : \(fr)") }
    }

    @Test(arguments: GenreContenu.allCases)
    func chaqueGenreAUnLibelleDansLesDeuxLangues(genre: GenreContenu) {
        let fr = genre.libelle(locale: Locale(identifier: "fr"))
        let en = genre.libelle(locale: Locale(identifier: "en"))
        #expect(!fr.isEmpty && !en.isEmpty)
        #expect(fr != en, "non traduit : \(fr)")
    }

    @Test
    func lesDetailsDuContratSontReconnus() {
        #expect(DetailIllisible(contrat: "JSON invalide") == .jsonInvalide)
        #expect(DetailIllisible(contrat: "champ manquant : fichiers[0].taille") == .champManquant("fichiers[0].taille"))
        #expect(DetailIllisible(contrat: "type inattendu : format") == .typeInattendu("format"))
        #expect(DetailIllisible(contrat: "valeur absente : app") == .valeurAbsente("app"))
        #expect(DetailIllisible(contrat: "valeur invalide : identifiant") == .valeurInvalide("identifiant"))
        #expect(DetailIllisible(contrat: "valeur invalide") == .valeurInvalide(nil))
        #expect(DetailIllisible(contrat: "lecture impossible") == .lectureImpossible)
        #expect(DetailIllisible(contrat: "quelque chose de neuf") == .autre("quelque chose de neuf"))
    }

    // MARK: Version trop recente ou trop ancienne : que faire

    @Test(arguments: [("1.5.0", C.AppSource.maillageThread), ("2.0.0", .maillageThread), ("1.3.0", .maillageZigbee),
                      ("1.3", .maillageZigbee), ("10.0", .maillageZigbee)])
    func uneVersionTropRecenteInviteAMettreAJourMaillageIoT(version: String, app: C.AppSource) {
        let cause = CauseRefus.versionNonPrise(app: app, version: version)
        #expect(ValidationExport.sens(de: version, app: app) == .tropRecente)
        let fr = cause.texte(locale: Locale(identifier: "fr"))
        let en = cause.texte(locale: Locale(identifier: "en"))
        #expect(fr.contains("mettez Maillage IoT à jour"), "\(fr)")
        #expect(en.contains("Update Maillage IoT"), "\(en)")
        #expect(!fr.contains("refaites l'export") && !en.contains("export again"))
        #expect(fr.contains(version) && fr.contains(app.nomApp))
    }

    @Test(arguments: [("1.2.0", C.AppSource.maillageThread), ("1.0.0", .maillageThread), ("0.9", .maillageThread),
                      ("1.0.9", .maillageZigbee), ("0.1.0", .maillageZigbee)])
    func uneVersionTropAncienneInviteAMettreAJourLAncienneApp(version: String, app: C.AppSource) {
        let cause = CauseRefus.versionNonPrise(app: app, version: version)
        #expect(ValidationExport.sens(de: version, app: app) == .tropAncienne)
        let fr = cause.texte(locale: Locale(identifier: "fr"))
        let en = cause.texte(locale: Locale(identifier: "en"))
        #expect(fr.contains("mettez \(app.nomApp) à jour"), "\(fr)")
        #expect(en.contains("Update \(app.nomApp)"), "\(en)")
        #expect(!fr.contains("mettez Maillage IoT"), "\(fr)")
        #expect(fr.contains(version))
    }

    @Test(arguments: ["", "abc", "1.4.0-beta", " 1.4.0", "v1.3.0", "1.03.0", "1"])
    func uneVersionIllisibleOuDansLesSeriesPriseNeDitPasDeMettreAJour(version: String) {
        #expect(ValidationExport.sens(de: version, app: .maillageThread) == .inconnue)
        let fr = CauseRefus.versionNonPrise(app: .maillageThread, version: version).texte(locale: Locale(identifier: "fr"))
        #expect(!fr.contains("à jour"), "\(fr)")
        #expect(fr.contains("1.3") && fr.contains("1.4"))
    }

    @Test
    func laVersionTropRecenteDeBoutEnBout() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierManifeste { $0["versionApp"] = "1.5.0" }
        let cause = try Self.refus(copie)
        #expect(cause == .versionNonPrise(app: .maillageThread, version: "1.5.0"))
        #expect(cause.texte(locale: Locale(identifier: "fr")).contains("mettez Maillage IoT à jour"))
    }

    // MARK: Pluriels du resume

    @Test(arguments: [(0, "0 fichier", "0 files"), (1, "1 fichier", "1 file"), (2, "2 fichiers", "2 files"),
                      (12, "12 fichiers", "12 files")])
    func lesFichiersDuResumeSeDisentAuSingulierOuAuPluriel(n: Int, fr: String, en: String) {
        #expect(ResumeExport.nombreDeFichiers(n, locale: Locale(identifier: "fr")) == fr)
        #expect(ResumeExport.nombreDeFichiers(n, locale: Locale(identifier: "en")) == en)
    }

    @Test(arguments: [(1, "1 réglage repris", "1 setting imported"), (2, "2 réglages repris", "2 settings imported")])
    func lesReglagesReprisSeDisentAuSingulierOuAuPluriel(n: Int, fr: String, en: String) {
        #expect(ResumeExport.nombreDeReglagesRepris(n, locale: Locale(identifier: "fr")) == fr)
        #expect(ResumeExport.nombreDeReglagesRepris(n, locale: Locale(identifier: "en")) == en)
    }

    @Test(arguments: [(1, "1 réglage laissé de côté", "1 setting left out"),
                      (2, "2 réglages laissés de côté", "2 settings left out")])
    func lesReglagesLaissesDeCoteSeDisentAuSingulierOuAuPluriel(n: Int, fr: String, en: String) {
        #expect(ResumeExport.nombreDeReglagesLaissesDeCote(n, locale: Locale(identifier: "fr")) == fr)
        #expect(ResumeExport.nombreDeReglagesLaissesDeCote(n, locale: Locale(identifier: "en")) == en)
    }

    @Test(arguments: [(1, "1 fichier non repris", "1 file not imported"), (3, "3 fichiers non repris", "3 files not imported")])
    func lesFichiersNonReprisSeDisentAuSingulierOuAuPluriel(n: Int, fr: String, en: String) {
        #expect(ResumeExport.nombreDeFichiersNonRepris(n, locale: Locale(identifier: "fr")) == fr)
        #expect(ResumeExport.nombreDeFichiersNonRepris(n, locale: Locale(identifier: "en")) == en)
    }

    @Test(arguments: C.AppSource.allCases)
    func lesLignesDuResumeUtilisentLesComptesDeLExport(app: C.AppSource) throws {
        guard case .acceptee(let resume) = ValidationExport.valider(dossier: try ExportsExempleTests.dossier(app), imports: .vide) else {
            throw Echec("refuse")
        }
        let fr = Locale(identifier: "fr")
        #expect(resume.ligne(.surnoms, locale: fr) == "Surnoms : 1 fichier")
        #expect(resume.ligne(.journal, locale: fr) == "Journal des événements : 2 fichiers")
        #expect(resume.ligne(.journal, locale: Locale(identifier: "en")) == "Event log: 2 files")
        #expect(resume.texteReglagesRepris(locale: fr) == ResumeExport.nombreDeReglagesRepris(resume.reglagesRepris, locale: fr))
        #expect(resume.texteReglagesLaissesDeCote(locale: fr)
                == ResumeExport.nombreDeReglagesLaissesDeCote(resume.reglagesNonRepris.count, locale: fr))
        #expect(resume.texteFichiersNonRepris(locale: fr)
                == ResumeExport.nombreDeFichiersNonRepris(resume.fichiersNonRepris.count, locale: fr))
    }
}
