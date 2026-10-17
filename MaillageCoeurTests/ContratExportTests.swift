import Foundation
import Testing
@testable import MaillageCoeur

/// Contrat d'export commun aux trois depots (`ContratExport.swift`, identique a l'octet dans Maillage Thread, Maillage
/// Zigbee et Maillage IoT) : manifeste version 1, `reglages.json`, noms de fichiers connus, chemins, empreintes. Ce
/// fichier se recopie dans les anciennes apps avec le contrat. Valeurs inventees seulement.
@Suite("Contrat d'export : manifeste, reglages, chemins, empreintes")
struct ContratExportTests {
    typealias C = ContratExport

    static let identifiant = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    /// 2026-10-17 12:00:00 UTC.
    static let date = Date(timeIntervalSince1970: 1_792_238_400)
    static let sha = String(repeating: "ab", count: 32)

    static func manifeste(app: C.AppSource = .maillageThread, fichiers: [C.Fichier]? = nil) -> C.Manifeste {
        C.Manifeste(identifiant: identifiant, app: app, versionApp: "9.9.9", date: date,
                    fichiers: fichiers ?? [
                        C.Fichier(chemin: "surnoms.json", taille: 12, sha256: sha),
                        C.Fichier(chemin: "Journal/journal-2026-10.jsonl", taille: 0, sha256: String(repeating: "0", count: 64)),
                        C.Fichier(chemin: "reglages.json", taille: 345, sha256: sha),
                    ])
    }

    static func texte(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    static func dossier() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("contrat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Manifeste

    /// Aller-retour, et texte exact : cles triees, dates ISO 8601, ordre des fichiers garde, deux ecritures identiques.
    @Test func manifesteAllerRetour() throws {
        let m = Self.manifeste()
        let json = try C.ecrire(m)
        #expect(try C.lireManifeste(json) == m)
        #expect(try C.ecrire(m) == json, "ecriture deterministe")
        let attendu = """
        {
          "app" : "thread",
          "date" : "2026-10-17T12:00:00Z",
          "fichiers" : [
            {
              "chemin" : "surnoms.json",
              "sha256" : "\(Self.sha)",
              "taille" : 12
            },
            {
              "chemin" : "Journal/journal-2026-10.jsonl",
              "sha256" : "\(String(repeating: "0", count: 64))",
              "taille" : 0
            },
            {
              "chemin" : "reglages.json",
              "sha256" : "\(Self.sha)",
              "taille" : 345
            }
          ],
          "format" : 1,
          "identifiant" : "00000000-0000-4000-8000-000000000001",
          "versionApp" : "9.9.9"
        }
        """
        #expect(Self.texte(json) == attendu)
    }

    /// Les valeurs brutes de l'app source sont stables : elles sont ecrites dans les exports.
    @Test func appsSource() {
        #expect(C.AppSource.maillageThread.rawValue == "thread")
        #expect(C.AppSource.maillageZigbee.rawValue == "zigbee")
        #expect(C.AppSource.allCases.count == 2)
        #expect(C.AppSource(rawValue: "zigbee") == .maillageZigbee)
    }

    /// Une date avec des fractions est ramenee a la seconde a la construction : ce qui s'ecrit se relit egal.
    @Test func dateALaSeconde() throws {
        let m = C.Manifeste(identifiant: Self.identifiant, app: .maillageZigbee, versionApp: "1", date: Self.date + 0.789,
                            fichiers: [])
        #expect(m.date == Self.date)
        #expect(try C.lireManifeste(C.ecrire(m)) == m)
    }

    /// Un format autre que 1 est refuse avec une erreur typee, meme si le reste du manifeste a une autre forme.
    @Test func formatInconnuRefuse() throws {
        for format in [0, 2, 99, -1] {
            let json = Data(#"{"format": \#(format), "inconnu": true}"#.utf8)
            #expect(throws: C.Erreur.formatInconnu(format)) { try C.lireManifeste(json) }
        }
        let bon = try C.ecrire(Self.manifeste())
        let v2 = Data(Self.texte(bon).replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2").utf8)
        #expect(throws: C.Erreur.formatInconnu(2)) { try C.lireManifeste(v2) }
        #expect(throws: C.Erreur.formatInconnu(2)) { try JSONDecoder().decode(C.Manifeste.self, from: v2) }
    }

    /// Une app source inconnue est refusee avec son nom ; l'ancien nom de cas n'est pas une valeur brute.
    @Test func appInconnueRefusee() throws {
        let bon = Self.texte(try C.ecrire(Self.manifeste()))
        for nom in ["matter", "", "maillageThread", "THREAD"] {
            let json = Data(bon.replacingOccurrences(of: "\"app\" : \"thread\"", with: "\"app\" : \"\(nom)\"").utf8)
            #expect(throws: C.Erreur.appInconnue(nom)) { try C.lireManifeste(json) }
        }
    }

    /// Un manifeste mal forme est « illisible », sans plantage : JSON invalide, champ manquant, mauvais type.
    @Test func manifesteIllisible() throws {
        let bon = Self.texte(try C.ecrire(Self.manifeste()))
        let casses = [
            "pas du JSON",
            "[]",
            "{}",
            bon.replacingOccurrences(of: "\"versionApp\"", with: "\"autreCle\""),
            bon.replacingOccurrences(of: "\"taille\" : 12", with: "\"taille\" : \"12\""),
            bon.replacingOccurrences(of: "2026-10-17T12:00:00Z", with: "hier"),
            bon.replacingOccurrences(of: "00000000-0000-4000-8000-000000000001", with: "pas-un-uuid"),
        ]
        for c in casses {
            #expect(throws: C.Erreur.illisible, "\(c.prefix(40))") { try C.lireManifeste(Data(c.utf8)) }
        }
    }

    /// Un manifeste altere est refuse a la lecture : chemin qui sort, empreinte mal formee, taille negative, doublon
    /// (casse comprise), nom reserve.
    @Test func manifesteAltereRefuse() throws {
        func avec(_ f: C.Fichier...) -> Data { (try? C.encodeur().encode(Self.manifeste(fichiers: f))) ?? Data() }
        let ok = C.Fichier(chemin: "surnoms.json", taille: 1, sha256: Self.sha)
        #expect(throws: C.Erreur.cheminInvalide("../x")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "../x", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminInvalide("/etc/passwd")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "/etc/passwd", taille: 1, sha256: Self.sha)))
        }
        for mauvaise in ["", "abc", String(repeating: "AB", count: 32), String(repeating: "g", count: 64),
                         String(repeating: "a", count: 63), String(repeating: "a", count: 65)] {
            #expect(throws: C.Erreur.empreinteInvalide("surnoms.json"), "\(mauvaise.count)") {
                try C.lireManifeste(avec(C.Fichier(chemin: "surnoms.json", taille: 1, sha256: mauvaise)))
            }
        }
        #expect(throws: C.Erreur.tailleInvalide("surnoms.json")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "surnoms.json", taille: -1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminEnDouble("SURNOMS.json")) {
            try C.lireManifeste(avec(ok, C.Fichier(chemin: "SURNOMS.json", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminEnDouble("surnoms.json")) { try C.lireManifeste(avec(ok, ok)) }
        #expect(throws: C.Erreur.nomReserve("manifeste.json")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "manifeste.json", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.nomReserve("Manifeste.JSON")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "Manifeste.JSON", taille: 1, sha256: Self.sha)))
        }
    }

    /// L'ecriture refuse elle aussi ce que la lecture refuserait : on ne produit pas un export illisible.
    @Test func ecritureRefuseLesMemesCas() {
        #expect(throws: C.Erreur.cheminInvalide("a/../../x")) {
            try C.ecrire(Self.manifeste(fichiers: [C.Fichier(chemin: "a/../../x", taille: 1, sha256: Self.sha)]))
        }
    }

    // MARK: Chemins

    @Test(arguments: [
        "surnoms.json", "Journal/journal-2026-10.jsonl", "Thread/x.json", "a/b/c.txt", "maillage-2026-09.jsonl",
        "nom avec espaces.json", "accentué.json", "..x", "x..", "a/..b/c", ".cache", "a/.b",
    ])
    func cheminsValides(_ chemin: String) throws {
        #expect(C.cheminEstValide(chemin))
        try C.verifierChemin(chemin)
    }

    @Test(arguments: [
        "", "/", "/etc/passwd", "/surnoms.json", "..", "../x", "a/../../x", "a/..", "a/../b", "./x", "a/./b", "a//b",
        "a/", "x/", "//x", "a\\b", "a\u{0}b", "a\nb", "a\tb", "a\u{7F}b", ".", "a/.", "~/../x",
        String(repeating: "a", count: 300), Array(repeating: "d", count: 600).joined(separator: "/"),
    ])
    func cheminsRefuses(_ chemin: String) {
        #expect(!C.cheminEstValide(chemin))
        #expect(throws: C.Erreur.cheminInvalide(chemin)) { try C.verifierChemin(chemin) }
    }

    /// Resolution dans un dossier : un chemin normal, y compris vers un fichier pas encore ecrit, reste dedans.
    @Test func resoudreDansLeDossier() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = try C.resoudre("Journal/journal-2026-10.jsonl", dans: d)
        #expect(url.standardizedFileURL.path == d.standardizedFileURL.appendingPathComponent("Journal/journal-2026-10.jsonl").path)
        #expect(throws: C.Erreur.cheminInvalide("../x")) { try C.resoudre("../x", dans: d) }
        #expect(throws: C.Erreur.cheminInvalide("/tmp/x")) { try C.resoudre("/tmp/x", dans: d) }
    }

    /// Un lien symbolique du dossier vers l'exterieur, sur le fichier ou sur un dossier du chemin, est refuse.
    @Test func lienSymboliqueRefuse() throws {
        let d = try Self.dossier(), dehors = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d); try? FileManager.default.removeItem(at: dehors) }
        try Data("dehors".utf8).write(to: dehors.appendingPathComponent("secret.json"))
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("lien.json"),
                                                   withDestinationURL: dehors.appendingPathComponent("secret.json"))
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("Journal"), withDestinationURL: dehors)
        #expect(throws: C.Erreur.lienSymbolique("lien.json")) { try C.resoudre("lien.json", dans: d) }
        #expect(throws: C.Erreur.lienSymbolique("Journal/secret.json")) { try C.resoudre("Journal/secret.json", dans: d) }
        #expect(throws: C.Erreur.lienSymbolique("lien.json")) { try C.Fichier.decrire(chemin: "lien.json", dans: d) }
    }

    /// Le dossier lui-meme peut etre derriere un lien (`/var` -> `/private/var`) sans que ses fichiers soient refuses.
    @Test func dossierDerriereUnLien() throws {
        let vrai = try Self.dossier()
        let lien = FileManager.default.temporaryDirectory.appendingPathComponent("contrat-lien-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vrai); try? FileManager.default.removeItem(at: lien) }
        try FileManager.default.createSymbolicLink(at: lien, withDestinationURL: vrai)
        try Data("x".utf8).write(to: vrai.appendingPathComponent("surnoms.json"))
        let f = try C.Fichier.decrire(chemin: "surnoms.json", dans: lien)
        #expect(f.taille == 1)
    }

    // MARK: Empreintes

    /// SHA-256 de contenus connus (FIPS 180-2), en hexadecimal minuscule.
    @Test func empreinteConnue() throws {
        #expect(C.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(C.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: f)
        #expect(try C.sha256(fichier: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let vide = d.appendingPathComponent("vide")
        try Data().write(to: vide)
        #expect(try C.sha256(fichier: vide) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// Un fichier de plusieurs tailles de tampon donne la meme empreinte que son contenu d'un bloc.
    @Test func empreinteParBlocs() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        var contenu = Data()
        for i in 0..<(3 * 1024 * 1024 + 17) { contenu.append(UInt8(truncatingIfNeeded: i &* 31 &+ 7)) }
        let f = d.appendingPathComponent("gros.bin")
        try contenu.write(to: f)
        #expect(try C.sha256(fichier: f) == C.sha256(contenu))
    }

    /// Un fichier absent n'a pas d'empreinte : l'erreur passe, rien n'est invente.
    @Test func empreinteFichierAbsent() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(throws: (any Error).self) { try C.sha256(fichier: d.appendingPathComponent("absent")) }
    }

    /// `Fichier.decrire` : taille et empreinte du fichier du dossier, sous son chemin relatif.
    @Test func decrireUnFichier() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d.appendingPathComponent("Journal"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: d.appendingPathComponent("Journal/journal-2026-10.jsonl"))
        let f = try C.Fichier.decrire(chemin: "Journal/journal-2026-10.jsonl", dans: d)
        #expect(f == C.Fichier(chemin: "Journal/journal-2026-10.jsonl", taille: 3,
                               sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        #expect(throws: (any Error).self) { try C.Fichier.decrire(chemin: "Journal", dans: d) }
        #expect(throws: (any Error).self) { try C.Fichier.decrire(chemin: "absent.json", dans: d) }
    }

    @Test func formeDUneEmpreinte() {
        #expect(C.empreinteEstValide(Self.sha))
        #expect(!C.empreinteEstValide(Self.sha.uppercased()))
        #expect(!C.empreinteEstValide(String(Self.sha.dropLast())))
        #expect(!C.empreinteEstValide(""))
    }

    // MARK: Reglages

    /// Un reglage de chaque type, ecrit puis relu egal ; le texte porte le type et la valeur, cles triees.
    @Test func reglagesAllerRetour() throws {
        let r = C.Reglages(app: .maillageZigbee, valeurs: [
            "grapheDejaOuvert": .bool(true),
            "etagesEnGrille": .bool(false),
            "sondePagesTables": .entier(7),
            "negatif": .entier(-3),
            "decimal": .decimal(0.25),
            "sondeNom": .texte("Sonde 1 é"),
            "vide": .texte(""),
            "pont.hue": .donnees(Data([0x00, 0x01, 0xFE, 0xFF])),
            "AppleLanguages": .listeTextes(["fr", "en"]),
            "listeVide": .listeTextes([]),
            "sondeJournalPages": .listeEntiers([1, 2, 300, -4]),
        ])
        let json = try C.ecrire(r)
        #expect(try C.lireReglages(json) == r)
        #expect(try C.ecrire(r) == json)
        let t = Self.texte(json)
        #expect(t.contains("\"pont.hue\" : {\n      \"type\" : \"donnees\",\n      \"valeur\" : \"AAH+/w==\"\n    }"))
        #expect(t.contains("\"sondePagesTables\" : {\n      \"type\" : \"entier\",\n      \"valeur\" : 7\n    }"))
        #expect(t.contains("\"app\" : \"zigbee\""))
        #expect(t.contains("\"format\" : 1"))
        let cles = t.components(separatedBy: "\n").compactMap { l -> String? in
            guard l.hasPrefix("    \""), let f = l.dropFirst(5).firstIndex(of: "\"") else { return nil }
            return String(l.dropFirst(5)[..<f])
        }
        #expect(cles == cles.sorted(), "cles triees")
    }

    /// Un 1 entier et un 1,0 decimal, un booleen et un 1 : le type ecrit est celui qu'on relit.
    @Test func typesNeSeConfondentPas() throws {
        let r = C.Reglages(app: .maillageThread, valeurs: ["a": .entier(1), "b": .decimal(1.0), "c": .bool(true),
                                                          "d": .texte("1"), "e": .listeEntiers([1])])
        let relu = try C.lireReglages(C.ecrire(r))
        #expect(relu.valeurs["a"] == .entier(1))
        #expect(relu.valeurs["b"] == .decimal(1.0))
        #expect(relu.valeurs["c"] == .bool(true))
        #expect(relu.valeurs["d"] == .texte("1"))
        #expect(relu.valeurs["e"] == .listeEntiers([1]))
        #expect(relu.valeurs["a"] != .decimal(1.0))
    }

    @Test func reglagesVides() throws {
        let r = C.Reglages(app: .maillageThread, valeurs: [:])
        #expect(try C.lireReglages(C.ecrire(r)) == r)
    }

    /// Format inconnu, app inconnue, type de valeur inconnu (jamais ignore en silence), cle vide, JSON mal forme.
    @Test func reglagesRefuses() throws {
        let bon = Self.texte(try C.ecrire(C.Reglages(app: .maillageThread, valeurs: ["a": .bool(true)])))
        let v2 = Data(bon.replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2").utf8)
        #expect(throws: C.Erreur.formatInconnu(2)) { try C.lireReglages(v2) }
        let app = Data(bon.replacingOccurrences(of: "\"thread\"", with: "\"autre\"").utf8)
        #expect(throws: C.Erreur.appInconnue("autre")) { try C.lireReglages(app) }
        let type = Data(bon.replacingOccurrences(of: "\"bool\"", with: "\"date\"").utf8)
        #expect(throws: C.Erreur.valeurInconnue(cle: "a", type: "date")) { try C.lireReglages(type) }
        let vide = Data(bon.replacingOccurrences(of: "\"a\"", with: "\"\"").utf8)
        #expect(throws: C.Erreur.cleInvalide) { try C.lireReglages(vide) }
        let mauvais = Data(bon.replacingOccurrences(of: "true", with: "\"oui\"").utf8)
        #expect(throws: C.Erreur.illisible) { try C.lireReglages(mauvais) }
        #expect(throws: C.Erreur.illisible) { try C.lireReglages(Data("{}".utf8)) }
        #expect(throws: C.Erreur.illisible) { try C.lireReglages(Data("pas du json".utf8)) }
    }

    /// Un decimal qui ne s'ecrit pas en JSON (NaN, infini) n'est jamais ecrit tronque : l'ecriture echoue.
    @Test func decimalNonFini() {
        let r = C.Reglages(app: .maillageThread, valeurs: ["x": .decimal(.nan)])
        #expect(throws: (any Error).self) { try C.ecrire(r) }
    }

    // MARK: Fichiers et reglages connus

    @Test func fichiersConnusDeThread() {
        let attendus = ["surnoms.json", "associations.json", "identites-routeurs.json", "dernier-maillage.json",
                        "dernieres-adresses.json", "noms.json", "pieces-routeurs.json", "positions-pieces.json",
                        "maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        #expect(C.fichiersConnus(de: .maillageThread).map(\.modele) == attendus)
    }

    @Test func fichiersConnusDeZigbee() {
        let attendus = ["surnoms.json", "dernier-maillage.json", "appariements-maison.json", "noms-pont.json",
                        "releve-maison.json", "pieces-routeurs.json", "positions-pieces.json",
                        "maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        #expect(C.fichiersConnus(de: .maillageZigbee).map(\.modele) == attendus)
    }

    @Test func correspondanceDesNomsConnus() {
        #expect(C.estConnu("surnoms.json", de: .maillageThread))
        #expect(C.estConnu("maillage-2026-10.jsonl", de: .maillageThread))
        #expect(C.estConnu("Journal/journal-2026-09.jsonl", de: .maillageZigbee))
        #expect(C.estConnu("noms.json", de: .maillageThread))
        #expect(!C.estConnu("noms.json", de: .maillageZigbee), "noms.json est le releve de Thread seulement")
        #expect(C.estConnu("releve-maison.json", de: .maillageZigbee))
        #expect(!C.estConnu("associations.json", de: .maillageZigbee))
        #expect(!C.estConnu("Thread/surnoms.json", de: .maillageThread), "pas de dossier d'un module dans l'export")
        for faux in ["maillage-2026-13.jsonl", "maillage-2026-00.jsonl", "maillage-26-10.jsonl", "maillage-2026-1.jsonl",
                     "maillage-2026-10.json", "Maillage-2026-10.jsonl", "journal-2026-10.jsonl", "Journal/journal-2026-10.json",
                     "maillage-2026-10.jsonl.bak", "maillage-abcd-10.jsonl", "Journal/maillage-2026-10.jsonl",
                     "reglages.json", "manifeste.json", ".DS_Store", ""] {
            #expect(!C.estConnu(faux, de: .maillageThread), "\(faux)")
            #expect(!C.estConnu(faux, de: .maillageZigbee), "\(faux)")
        }
    }

    @Test func moisDesFichiersMensuels() {
        #expect(C.mois(de: "maillage-2026-10.jsonl") == C.Mois(annee: 2026, mois: 10))
        #expect(C.mois(de: "Journal/journal-2025-01.jsonl") == C.Mois(annee: 2025, mois: 1))
        #expect(C.mois(de: "surnoms.json") == nil)
        #expect(C.mois(de: "maillage-2026-13.jsonl") == nil)
        #expect(C.Mois(annee: 2025, mois: 12) < C.Mois(annee: 2026, mois: 1))
        #expect(C.Mois(annee: 2026, mois: 2) < C.Mois(annee: 2026, mois: 10))
    }

    @Test func fichiersExclus() {
        for nom in [".DS_Store", "Journal/.DS_Store", "noms.illisible-20261017-120000.json", "Journal/x.illisible-1.json"] {
            #expect(C.estExcluDeLExport(nom), "\(nom)")
        }
        for nom in ["surnoms.json", "illisible.json", "x.illisible-1.txt", "maillage-2026-10.jsonl"] {
            #expect(!C.estExcluDeLExport(nom), "\(nom)")
        }
    }

    /// Les reglages de l'inventaire (17/10) : chacun a son type, par app ; les cles absentes de la liste restent a
    /// l'import de dire « ignore ».
    @Test func reglagesConnus() {
        func types(_ app: C.AppSource) -> [String: C.TypeValeur] {
            Dictionary(uniqueKeysWithValues: C.reglagesConnus(de: app).map { ($0.cle, $0.type) })
        }
        let communs: [String: C.TypeValeur] = [
            "vuePieces3D": .bool, "etagesEnGrille": .bool, "legendeRepliee": .bool, "grapheDejaOuvert": .bool,
            "ouvertureSessionProposee": .bool, "AppleLanguages": .listeTextes,
        ]
        let thread = communs.merging([
            "sondeSerieUSB": .texte, "sondeNom": .texte, "sondeHote": .texte, "sondeLiaison": .texte,
            "scissionsNotifiees": .listeTextes,
            "notification.scission": .bool, "notification.routeurDisparu": .bool, "notification.pertes": .bool,
            "notification.informations": .bool,
        ]) { a, _ in a }
        let zigbee = communs.merging([
            "sondeSerieUSB": .texte, "sondeNom": .texte, "sondeIeee": .texte, "sondeNomWifi": .texte,
            "sondeJournalPages": .listeEntiers, "sondePagesTables": .entier, "sondeChemin": .texte,
            "pont.hue": .donnees, "liensMontres": .texte, "voisinsALaSelection": .bool,
            "notification.routeurDisparu": .bool, "notification.pertes": .bool, "notification.informations": .bool,
        ]) { a, _ in a }
        #expect(types(.maillageThread) == thread)
        #expect(types(.maillageZigbee) == zigbee)
        #expect(C.reglagesConnus(de: .maillageThread).count == thread.count, "pas de cle en double")
        #expect(C.reglagesConnus(de: .maillageZigbee).count == zigbee.count, "pas de cle en double")
        #expect(types(.maillageZigbee)["notification.scission"] == nil, "Zigbee n'a pas de scission")
    }

    /// Jamais dans les reglages : Sparkle, etats de fenetre, onglet des reglages, signet de l'ancien dossier des noms,
    /// secrets. Ils ne sont dans aucune liste connue.
    @Test func reglagesNonRepris() {
        for cle in ["SUHasLaunchedBefore", "SULastCheckTime", "SUUpdateGroupIdentifier", "NSWindow Frame graphe",
                    "reglages.onglet", "dossierNoms", "motDePasseWifi", "cleSonde"] {
            for app in C.AppSource.allCases {
                #expect(!C.reglagesConnus(de: app).contains { $0.cle == cle }, "\(cle)")
                #expect(C.typeAttendu(cle: cle, de: app) == nil)
            }
        }
        #expect(C.typeAttendu(cle: "sondeLiaison", de: .maillageThread) == .texte)
        #expect(C.typeAttendu(cle: "sondeLiaison", de: .maillageZigbee) == nil)
        #expect(C.Valeur.listeEntiers([]).type == .listeEntiers)
        #expect(C.Valeur.donnees(Data()).type == .donnees)
    }

    /// Les noms que l'export reserve au contrat.
    @Test func nomsReserves() {
        #expect(C.nomManifeste == "manifeste.json")
        #expect(C.nomReglages == "reglages.json")
        #expect(C.formatCourant == 1)
    }
}
