import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Phase 4, tache 4 : la conversion d'un export de Maillage Thread 1.3.0 (`ConversionThread`). Une regle, un test : chaque
/// fichier et chaque reglage de l'inventaire a le sien, et la conversion ne perd rien en silence (un fichier ou un
/// reglage de l'export est dans le plan, ou cite parmi ce qui n'est pas pris). L'export d'exemple est
/// `MaillageIoTTests/Ressources/exports/thread-1.3.0` (date de reference 2026-10-17 12:00 UTC) ; le dossier de donnees de
/// Maillage IoT est un dossier temporaire. Valeurs inventees seulement.
@Suite("Conversion de Thread 1.3.0 vers Maillage IoT")
struct ConversionThreadTests {
    typealias C = ContratExport
    typealias G = GenerateurExportsExemple
    typealias Copie = ValidationExportTests.Copie
    typealias Echec = ValidationExportTests.Echec
    typealias Nature = ElementNonPris.Nature
    typealias Raison = ElementNonPris.Raison

    static let maintenant = G.dateReference

    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: Outils

    /// Un dossier de donnees de Maillage IoT temporaire, efface a la fin du test.
    final class Donnees {
        let racine: URL

        init() throws {
            racine = FileManager.default.temporaryDirectory.appendingPathComponent("donnees-iot-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: racine) }

        func url(_ chemin: String) -> URL { racine.appendingPathComponent(chemin) }

        func ecrire(_ chemin: String, _ octets: Data) throws {
            let u = url(chemin)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try octets.write(to: u)
        }

        func ecrire(_ chemin: String, _ texte: String) throws { try ecrire(chemin, Data(texte.utf8)) }

        /// Tout ce que le dossier contient : chemin relatif -> octets.
        func instantane() throws -> [String: Data] {
            var r: [String: Data] = [:]
            let base = racine.resolvingSymlinksInPath().path + "/"
            let liste = FileManager.default.enumerator(at: racine.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])
            while let u = liste?.nextObject() as? URL {
                guard try u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                r[String(u.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: u)
            }
            return r
        }
    }

    static func exemple() throws -> URL { try ExportsExempleTests.dossier(.maillageThread) }

    static func etat(_ d: Donnees, presents: Set<String> = []) -> EtatActuel {
        EtatActuel(dossier: d.racine, reglagesPresents: presents)
    }

    static func convertir(_ dossier: URL? = nil, donnees d: Donnees, presents: Set<String> = []) throws -> PlanReprise {
        try ConversionThread.convertir(dossier: dossier ?? exemple(), etat: etat(d, presents: presents),
                                       maintenant: maintenant, calendrier: calendrier)
    }

    static func octets(_ plan: PlanReprise, _ chemin: String) throws -> Data {
        try #require(plan.fichier(chemin), "\(chemin) absent du plan").contenu.octets()
    }

    static func objet(_ d: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: d) as? [String: Any])
    }

    static func lignes(_ d: Data) -> [String] {
        String(decoding: d, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    static func lignesExport(_ chemin: String) throws -> [String] {
        lignes(try Data(contentsOf: exemple().appendingPathComponent(chemin)))
    }

    static func cite(_ plan: PlanReprise, _ nature: Nature, _ raison: Raison) -> Bool {
        plan.nonPris.contains(ElementNonPris(nature: nature, raison: raison))
    }

    static func encodeur() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }

    // MARK: L'export

    @Test func uneAppDifferenteEstRefusee() throws {
        let d = try Donnees()
        #expect(throws: ErreurConversion.self) {
            try ConversionThread.convertir(dossier: ExportsExempleTests.dossier(.maillageZigbee), etat: Self.etat(d),
                                           maintenant: Self.maintenant, calendrier: Self.calendrier)
        }
    }

    @Test func unExportAltereEstRefuse() throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = String(repeating: "0", count: 64) }
        let d = try Donnees()
        #expect(throws: C.Erreur.empreinteFausse("surnoms.json")) {
            try Self.convertir(copie.dossier, donnees: d)
        }
    }

    // MARK: surnoms.json

    @Test func lesSurnomsPrennentLePrefixeThread() throws {
        let d = try Donnees()
        let plan = try Self.convertir(donnees: d)
        let f = try #require(plan.fichier("surnoms.json"))
        #expect(f.sources == ["surnoms.json"])
        let brut = try Self.objet(f.contenu.octets())
        #expect(brut["version"] as? Int == 1)
        #expect(brut["surnoms"] as? [String: String] == [
            "thread:0000000000000001": "Prise 1", "thread:0000000000000002": "Capteur 1",
            "thread:instance:Routeur 2": "Routeur du bas", "thread:rloc:0800": "Routeur 3",
            "thread:Routeur 1": "Routeur du haut",
        ])
        // Le vrai lecteur relit le fichier, meme avec un autre protocole par defaut : le prefixe est ecrit, pas suppose.
        let relu = d.url("relu-surnoms.json")
        try f.contenu.octets().write(to: relu)
        #expect(Surnoms.lire(relu, protocoleParDefaut: .zigbee).count == 5)
        #expect(Surnoms.lire(relu, protocoleParDefaut: .zigbee)[IdNoeud(.thread, "instance:Routeur 2")] == "Routeur du bas")
    }

    @Test func unSurnomDejaDonneDansMaillageIoTEstGarde() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Mon choix","zigbee:00AA":"Lampe Zigbee"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        let surnoms = try #require(Self.objet(Self.octets(plan, "surnoms.json"))["surnoms"] as? [String: String])
        #expect(surnoms["thread:0000000000000001"] == "Mon choix", "le choix de Djoko l'emporte")
        #expect(surnoms["zigbee:00AA"] == "Lampe Zigbee", "un surnom d'un autre protocole reste")
        #expect(surnoms["thread:0000000000000002"] == "Capteur 1", "ce qui manquait est ajoute")
        #expect(surnoms.count == 6)
        #expect(Self.cite(plan, .entrees(fichier: "surnoms.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func unSurnomIdentiqueNEstPasUnConflit() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Prise 1"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        #expect(!plan.nonPris.contains { if case .entrees(fichier: "surnoms.json", _) = $0.nature { true } else { false } })
    }

    @Test func tousLesSurnomsDejaLaNeSontPasReecrits() throws {
        let d = try Donnees()
        let texte = #"{"surnoms":{"thread:0000000000000001":"Prise 1","thread:0000000000000002":"Capteur 1","thread:instance:Routeur 2":"Routeur du bas","thread:rloc:0800":"Routeur 3","thread:Routeur 1":"Routeur du haut"},"version":1}"#
        try d.ecrire("surnoms.json", texte)
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(Self.cite(plan, .fichier("surnoms.json"), .dejaDansMaillageIoT))
    }

    @Test func unSurnomsIllisibleNEstPasPrisEtEstCite() throws {
        let copie = try Copie(.maillageThread)
        try copie.remplacer("surnoms.json", par: Data("[1, 2]".utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(Self.cite(plan, .fichier("surnoms.json"), .fichierIllisible))
    }

    @Test func unSurnomsVideNeFaitRienEtEstCite() throws {
        let copie = try Copie(.maillageThread)
        try copie.remplacer("surnoms.json", par: Data("{}".utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(Self.cite(plan, .fichier("surnoms.json"), .vide))
    }

    @Test func uneCleVideNEmpoisonnePasLeFichier() throws {
        // « thread: » (cle vide) rendrait tout le fichier illisible au prochain lancement (`IdNoeud(texte:)` nil) : elle est
        // ecartee et citee.
        let copie = try Copie(.maillageThread)
        try copie.remplacer("surnoms.json", par: Data(#"{"":"Sans cle","0000000000000001":"Prise 1"}"#.utf8))
        let d = try Donnees()
        let plan = try Self.convertir(copie.dossier, donnees: d)
        let surnoms = try #require(Self.objet(Self.octets(plan, "surnoms.json"))["surnoms"] as? [String: String])
        #expect(surnoms == ["thread:0000000000000001": "Prise 1"])
        #expect(Self.cite(plan, .entrees(fichier: "surnoms.json", nombre: 1), .fichierIllisible))
    }

    @Test func unSurnomsExistantNonLisibleResteIntouche() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"matter:X":"Lampe M"},"version":1}"#)
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(Self.cite(plan, .fichier("surnoms.json"), .fichierExistantNonLisible))
        #expect(try d.instantane() == avant)
    }

    // MARK: pieces-routeurs.json -> pieces-noeuds.json

    @Test func lesPiecesDeVersion1DeviennentPiecesNoeudsVersion2() throws {
        let d = try Donnees()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("pieces-routeurs.json") == nil, "l'ancien nom n'est jamais depose : il serait relu sans protocole")
        let f = try #require(plan.fichier("pieces-noeuds.json"))
        #expect(f.sources == ["pieces-routeurs.json"])
        let u = d.url("relu-pieces.json")
        try f.contenu.octets().write(to: u)
        let p = PiecesRouteurs.lire(u)
        #expect(p.version == 2)
        #expect(p.maisons == ["Maison 1": [IdNoeud(.thread, "Routeur 1"): "Pièce 3", IdNoeud(.thread, "Routeur 2"): "Pièce 1"]])
        #expect(p.appareils == ["Maison 1": [IdNoeud(.thread, "0000000000000011"): "Pièce 2",
                                              IdNoeud(.thread, "0000000000000012"): "Pièce 1"]])
        let texte = String(decoding: try f.contenu.octets(), as: UTF8.self)
        #expect(texte.contains(#""thread:Routeur 1""#) && texte.contains(#""thread:0000000000000011""#))
    }

    @Test func lesAdressesLonguesDesPiecesSontEnMajuscules() throws {
        let copie = try Copie(.maillageThread)
        let v1 = #"{"appareils":{"Maison 1":{"abcdef0000000011":"Pièce 2"}},"maisons":{},"version":1}"#
        try copie.remplacer("pieces-routeurs.json", par: Data(v1.utf8))
        let d = try Donnees()
        let plan = try Self.convertir(copie.dossier, donnees: d)
        let u = d.url("relu-pieces.json")
        try Self.octets(plan, "pieces-noeuds.json").write(to: u)
        #expect(PiecesRouteurs.lire(u).appareils == ["Maison 1": [IdNoeud(.thread, "ABCDEF0000000011"): "Pièce 2"]])
    }

    @Test func leChoixManuelExistantDUnApparelAppleTVGagne() throws {
        let d = try Donnees()
        var existant = PiecesRouteurs()
        existant.choisir("Salon", routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1")
        existant.choisir("Bureau", appareil: IdNoeud(.zigbee, "00000000000000AA"), domicile: "Maison 1")
        try d.ecrire("pieces-noeuds.json", Self.encodeur().encode(existant))
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-pieces.json")
        try Self.octets(plan, "pieces-noeuds.json").write(to: u)
        let p = PiecesRouteurs.lire(u)
        #expect(p.choix(routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1") == "Salon", "le choix existant l'emporte")
        #expect(p.choix(routeur: IdNoeud(.thread, "Routeur 2"), domicile: "Maison 1") == "Pièce 1", "le manquant est ajoute")
        #expect(p.choix(appareil: IdNoeud(.zigbee, "00000000000000AA"), domicile: "Maison 1") == "Bureau", "un choix de Zigbee reste")
        #expect(p.choix(appareil: IdNoeud(.thread, "0000000000000011"), domicile: "Maison 1") == "Pièce 2")
        #expect(Self.cite(plan, .entrees(fichier: "pieces-routeurs.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func desPiecesNoeudsExistantsNonLisiblesRestentIntouchees() throws {
        let d = try Donnees()
        try d.ecrire("pieces-noeuds.json", "pas du json")
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("pieces-noeuds.json") == nil)
        #expect(Self.cite(plan, .fichier("pieces-routeurs.json"), .fichierExistantNonLisible))
        #expect(try d.instantane() == avant)
    }

    @Test func desPiecesRouteursIllisiblesNeSontPasPrises() throws {
        let copie = try Copie(.maillageThread)
        try copie.remplacer("pieces-routeurs.json", par: Data(#"{"version":2,"maisons":{}}"#.utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("pieces-noeuds.json") == nil)
        #expect(Self.cite(plan, .fichier("pieces-routeurs.json"), .fichierIllisible))
    }

    // MARK: positions-pieces.json

    @Test func lesPositionsSansFichierExistantSontCopieesTellesQuelles() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("positions-pieces.json"))
        let source = try Self.exemple().appendingPathComponent("positions-pieces.json")
        #expect(try f.contenu.octets() == Data(contentsOf: source))
        guard case .copie(_, let sha) = f.contenu else { throw Echec("copie attendue") }
        #expect(sha == C.sha256(try Data(contentsOf: source)))
    }

    @Test func lesPositionsSeFusionnentEnProfondeur() throws {
        var existant = PlacesGardees()
        existant.maisons["Maison 1"] = PlacesGardees.Maison(
            ordreEtages: ["zone:Étage 1", "zone:Salon bis"],
            etages: ["zone:Étage 1": ["piece:Pièce 1": .init(x: 9, z: 9)], "zone:Salon bis": ["piece:X": .init(x: 1, z: 1)]],
            aCote: ["zone:Jardin": .init(etage: "zone:Étage 2", dehors: false)])
        let d = try Donnees()
        try d.ecrire("positions-pieces.json", Self.encodeur().encode(existant))
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-positions.json")
        try Self.octets(plan, "positions-pieces.json").write(to: u)
        let p = PlacesGardees.lire(u)
        let m1 = try #require(p.maisons["Maison 1"])
        #expect(m1.ordreEtages == ["zone:Étage 1", "zone:Salon bis", "zone:Étage 2", "zone:Jardin"], "l'ordre existant, puis le manquant")
        #expect(m1.etages["zone:Étage 1"]?["piece:Pièce 1"] == .init(x: 9, z: 9), "la place existante l'emporte")
        #expect(m1.etages["zone:Étage 1"]?["piece:Pièce 2"] == .init(x: -3.25, z: 0.5), "la place manquante est ajoutee")
        #expect(m1.etages["zone:Salon bis"]?["piece:X"] == .init(x: 1, z: 1), "l'etage existant reste")
        #expect(m1.etages["zone:Étage 2"]?["piece:Pièce 3"] == .init(x: 0, z: 4), "l'etage manquant est ajoute")
        #expect(m1.aCote["zone:Jardin"] == .init(etage: "zone:Étage 2", dehors: false), "le choix de niveau existant l'emporte")
        #expect(p.maisons["Maison 2"]?.etages["zone:Zone 1"]?["routeur:0000000000000011"] == .init(x: 2, z: 2), "une maison manquante est ajoutee")
        #expect(Self.cite(plan, .entrees(fichier: "positions-pieces.json", nombre: 2), .dejaDansMaillageIoT))
    }

    @Test func desPositionsDejaToutesLaNeSontPasReecrites() throws {
        let d = try Donnees()
        try d.ecrire("positions-pieces.json", Data(contentsOf: Self.exemple().appendingPathComponent("positions-pieces.json")))
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("positions-pieces.json") == nil)
        #expect(Self.cite(plan, .fichier("positions-pieces.json"), .dejaDansMaillageIoT))
    }

    @Test func desPositionsExistantesNonLisiblesRestentIntouchees() throws {
        let d = try Donnees()
        try d.ecrire("positions-pieces.json", #"{"version":9,"maisons":{}}"#)
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("positions-pieces.json") == nil)
        #expect(Self.cite(plan, .fichier("positions-pieces.json"), .fichierExistantNonLisible))
    }

    // MARK: Fichiers propres a Thread

    static let fichiersThread = ["associations.json", "identites-routeurs.json", "dernieres-adresses.json", "dernier-maillage.json"]

    @Test(arguments: fichiersThread)
    func unFichierDuModuleSansExistantEstCopieSousThread(chemin: String) throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("Thread/\(chemin)"))
        #expect(f.sources == [chemin])
        let source = try Self.exemple().appendingPathComponent(chemin)
        #expect(try f.contenu.octets() == Data(contentsOf: source), "memes octets, memes cles")
        guard case .copie(let url, let sha) = f.contenu else { throw Echec("copie attendue") }
        #expect(url.lastPathComponent == chemin)
        #expect(sha == C.sha256(try Data(contentsOf: source)))
        #expect(plan.fichier(chemin) == nil, "rien n'est depose a la racine")
    }

    @Test func lesAssociationsSeFusionnentEtLeChoixExistantGagne() throws {
        let d = try Donnees()
        try d.ecrire("Thread/associations.json", #"{"associations":{"0000000000000001":"00000000000000FF","0000000000000009":"00000000000000A9"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-associations.json")
        try Self.octets(plan, "Thread/associations.json").write(to: u)
        #expect(Associations.lire(u) == ["0000000000000001": "00000000000000FF", "0000000000000002": "00000000000000A2",
                                         "0000000000000009": "00000000000000A9"])
        #expect(Self.cite(plan, .entrees(fichier: "associations.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func lesIdentitesDeRouteursExistantesRestent() throws {
        let d = try Donnees()
        let existant = #"{"partition":"0000B002","routeurs":{"0000":"0000000000000099"}}"#
        try d.ecrire("Thread/identites-routeurs.json", existant)
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Thread/identites-routeurs.json") == nil, "une autre partition : on ne melange pas les identites")
        #expect(Self.cite(plan, .fichier("identites-routeurs.json"), .dejaDansMaillageIoT))
    }

    @Test func leDernierMaillageLePlusRecentGagne() throws {
        // L'export a recu le 2026-10-14T08:07:00.000Z.
        let recent = #"{"maillage":{},"recu":"2026-10-16T08:00:00.000Z"}"#
        let ancien = #"{"maillage":{},"recu":"2026-10-10T08:00:00.000Z"}"#
        let d1 = try Donnees()
        try d1.ecrire("Thread/dernier-maillage.json", recent)
        let p1 = try Self.convertir(donnees: d1)
        #expect(p1.fichier("Thread/dernier-maillage.json") == nil)
        #expect(Self.cite(p1, .fichier("dernier-maillage.json"), .dejaDansMaillageIoT))
        let d2 = try Donnees()
        try d2.ecrire("Thread/dernier-maillage.json", ancien)
        let p2 = try Self.convertir(donnees: d2)
        let source = try Data(contentsOf: Self.exemple().appendingPathComponent("dernier-maillage.json"))
        #expect(try Self.octets(p2, "Thread/dernier-maillage.json") == source, "le cache de l'export, plus recent, remplace")
    }

    @Test func lesDernieresAdressesSeFusionnentEtLExistantGagne() throws {
        let d = try Donnees()
        let existant = #"{"appareils":{"0000000000000001":{"adresse":"fd00::99","annonce":"2026-10-16T08:05:00.000Z","partition":"0000A001"},"0000000000000007":{"adresse":"fd00::7","annonce":"2026-10-16T08:05:00.000Z","partition":"0000A001"}}}"#
        try d.ecrire("Thread/dernieres-adresses.json", existant)
        let plan = try Self.convertir(donnees: d)
        let appareils = try #require(Self.objet(Self.octets(plan, "Thread/dernieres-adresses.json"))["appareils"] as? [String: [String: String]])
        #expect(Set(appareils.keys) == ["0000000000000001", "0000000000000002", "0000000000000007"])
        #expect(appareils["0000000000000001"]?["adresse"] == "fd00::99", "l'adresse existante l'emporte")
        #expect(appareils["0000000000000002"]?["adresse"] == "fd00::2")
        #expect(Self.cite(plan, .entrees(fichier: "dernieres-adresses.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func unFichierDuModuleIllisibleDansLExportNEstPasPrisEtEstCite() throws {
        let copie = try Copie(.maillageThread)
        for chemin in Self.fichiersThread { try copie.remplacer(chemin, par: Data("[]".utf8)) }
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        for chemin in Self.fichiersThread {
            #expect(plan.fichier("Thread/\(chemin)") == nil, "\(chemin)")
            #expect(Self.cite(plan, .fichier(chemin), .fichierIllisible), "\(chemin)")
        }
    }

    @Test(arguments: fichiersThread)
    func unFichierDuModuleExistantNonLisibleResteIntouche(chemin: String) throws {
        let d = try Donnees()
        try d.ecrire("Thread/\(chemin)", "pas du json")
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Thread/\(chemin)") == nil)
        #expect(Self.cite(plan, .fichier(chemin), .fichierExistantNonLisible))
        #expect(try d.instantane() == avant)
    }

    // MARK: Historique mensuel

    @Test func lHistoriqueDeMoinsDe90JoursVaSousThreadSansChangement() throws {
        let plan = try Self.convertir(donnees: Donnees())
        for mois in ["2026-07", "2026-09", "2026-10"] {
            let chemin = "maillage-\(mois).jsonl"
            let f = try #require(plan.fichier("Thread/\(chemin)"), "\(chemin)")
            #expect(f.sources == [chemin])
            #expect(try f.contenu.octets() == Data(contentsOf: Self.exemple().appendingPathComponent(chemin)), "\(chemin)")
        }
        #expect(plan.fichier("maillage-2026-10.jsonl") == nil, "rien a la racine")
    }

    @Test func lHistoriqueDePlusDe90JoursEstEcarteEtCite() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.fichier("Thread/maillage-2026-04.jsonl") == nil)
        #expect(plan.fichier("Journal/journal-2026-04.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("maillage-2026-04.jsonl"), .plusDe90Jours))
        #expect(Self.cite(plan, .fichier("Journal/journal-2026-04.jsonl"), .plusDe90Jours))
    }

    @Test func laCoupeSeFaitParMoisFiniDepuisPlusDe90Jours() throws {
        let c = Self.calendrier
        let finJuillet = try #require(c.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let quatreVingtDixJours: TimeInterval = 90 * 24 * 3600
        func ancien(_ chemin: String, _ t: Date) -> Bool? {
            FusionReprise.moisEstTropAncien(chemin, maintenant: t, calendrier: c)
        }
        #expect(ancien("maillage-2026-07.jsonl", finJuillet.addingTimeInterval(quatreVingtDixJours)) == false, "90 jours pile : gardee")
        #expect(ancien("maillage-2026-07.jsonl", finJuillet.addingTimeInterval(quatreVingtDixJours + 1)) == true)
        #expect(ancien("Journal/journal-2026-06.jsonl", Self.maintenant) == true, "juin : fini depuis 108 jours")
        #expect(ancien("maillage-2026-07.jsonl", Self.maintenant) == false, "juillet : fini depuis 77 jours")
        #expect(ancien("maillage-2026-12.jsonl", Self.maintenant) == false, "le mois en cours ou a venir")
        #expect(ancien("surnoms.json", Self.maintenant) == nil, "pas un fichier mensuel")
    }

    @Test func lHistoriqueSeFusionneAvecLExistantSansDoublon() throws {
        let importees = try Self.lignesExport("maillage-2026-10.jsonl")
        let propre = #"{"date":"2026-10-16T08:00:00.000Z","partition":"0000A001","routeurs":[],"liens":[],"enfants":[],"signaux":[],"parentSonde":null}"#
        let d = try Donnees()
        try d.ecrire("Thread/maillage-2026-10.jsonl", ([importees[0], importees[1], propre]).joined(separator: "\n") + "\n")
        let plan = try Self.convertir(donnees: d)
        let f = try #require(plan.fichier("Thread/maillage-2026-10.jsonl"))
        #expect(f.sources == ["maillage-2026-10.jsonl"])
        #expect(Self.lignes(try f.contenu.octets()) == [importees[0], importees[1], propre] + Array(importees[2...]),
                "l'existant d'abord, tel quel, puis les lignes de l'export qui n'y sont pas")
        #expect(Self.cite(plan, .entrees(fichier: "maillage-2026-10.jsonl", nombre: 2), .dejaDansMaillageIoT))
    }

    @Test func unMoisDejaToutEntierLaEstCite() throws {
        let importees = try Self.lignesExport("maillage-2026-09.jsonl")
        let d = try Donnees()
        try d.ecrire("Thread/maillage-2026-09.jsonl", importees.joined(separator: "\n") + "\n")
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Thread/maillage-2026-09.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("maillage-2026-09.jsonl"), .dejaDansMaillageIoT))
    }

    @Test func unFichierSansFinDeLigneReçoitUneFinDeLigne() throws {
        // L'app ajoute ses lignes a la suite : sans fin de ligne, la premiere se collerait a la derniere.
        let copie = try Copie(.maillageThread)
        let ligne = #"{"date":"2026-07-02T08:00:00.000Z","partition":"0000A001","routeurs":[],"liens":[],"enfants":[],"signaux":[],"parentSonde":null}"#
        try copie.remplacer("maillage-2026-07.jsonl", par: Data(ligne.utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        let octets = try Self.octets(plan, "Thread/maillage-2026-07.jsonl")
        #expect(octets == Data((ligne + "\n").utf8))
    }

    @Test func unExistantSansFinDeLigneRecoitUneFinDeLigneAvantLAjout() throws {
        let importees = try Self.lignesExport("maillage-2026-09.jsonl")
        let d = try Donnees()
        try d.ecrire("Thread/maillage-2026-09.jsonl", "{\"a\":1}")
        let plan = try Self.convertir(donnees: d)
        let lignes = Self.lignes(try Self.octets(plan, "Thread/maillage-2026-09.jsonl"))
        #expect(lignes == ["{\"a\":1}"] + importees)
    }

    // MARK: Journal

    @Test func leJournalVaTelQuelEtSesLignesSansProtocoleSontThread() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("Journal/journal-2026-10.jsonl"))
        #expect(f.sources == ["Journal/journal-2026-10.jsonl"])
        let source = try Data(contentsOf: Self.exemple().appendingPathComponent("Journal/journal-2026-10.jsonl"))
        #expect(try f.contenu.octets() == source, "ajoute tel quel : aucune ligne n'est reecrite")
        let decodeur = CodageJSON.decodeur()
        for l in Self.lignes(source) {
            let e = try decodeur.decode(Evenement.self, from: Data(l.utf8))
            #expect((e.protocole ?? .thread) == .thread, "une ligne de Thread se lit Thread : \(l)")
        }
    }

    @Test func leJournalSAjouteALExistantSansDupliquerLesLignesDejaLa() throws {
        let importees = try Self.lignesExport("Journal/journal-2026-10.jsonl")
        let zigbee = #"{"constate":true,"date":"2026-10-16T06:00:00.000Z","details":{},"gravite":"info","protocole":"zigbee","type":"surveillanceDemarree"}"#
        let d = try Donnees()
        try d.ecrire("Journal/journal-2026-10.jsonl", [zigbee, importees[2], importees[0]].joined(separator: "\n") + "\n")
        let plan = try Self.convertir(donnees: d)
        let lignes = Self.lignes(try Self.octets(plan, "Journal/journal-2026-10.jsonl"))
        #expect(lignes == [zigbee, importees[2], importees[0]] + [importees[1]] + Array(importees[3...]),
                "l'existant tel quel, puis les lignes absentes dans l'ordre de l'export")
        #expect(lignes.filter { $0 == zigbee }.count == 1, "la ligne de Zigbee n'est pas touchee")
        #expect(Self.cite(plan, .entrees(fichier: "Journal/journal-2026-10.jsonl", nombre: 2), .dejaDansMaillageIoT))
    }

    @Test func uneLigneIdentiqueDansLExportMaisAbsenteDeLExistantResteEnDouble() throws {
        // Seul l'existant sert de reference : l'export est pris tel quel.
        let copie = try Copie(.maillageThread)
        let l = #"{"constate":true,"date":"2026-10-02T06:00:00.000Z","details":{},"gravite":"info","type":"surveillanceDemarree"}"#
        try copie.remplacer("Journal/journal-2026-10.jsonl", par: Data((l + "\n" + l + "\n").utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(Self.lignes(try Self.octets(plan, "Journal/journal-2026-10.jsonl")) == [l, l])
    }

    // MARK: noms.json -> releve-maison.json

    static func releve(date: String) throws -> Data {
        let texte = try String(contentsOf: exemple().appendingPathComponent("noms.json"), encoding: .utf8)
        return Data(texte.replacingOccurrences(of: "2026-10-14T08:00:00.000Z", with: date).utf8)
    }

    @Test func leReleveDeMaisonSansExistantPrendLeNomDuReleve() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("releve-maison.json"))
        #expect(f.sources == ["noms.json"])
        #expect(try f.contenu.octets() == Data(contentsOf: Self.exemple().appendingPathComponent("noms.json")),
                "renomme seulement : aucun identifiant n'est prefixe")
        #expect(plan.fichier("noms.json") == nil)
        #expect(try NomsMaison.lire(f.contenu.octets()).accessoires.count > 0)
    }

    @Test func unReleveExistantPlusAncienEstRemplace() throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", Self.releve(date: "2026-10-10T08:00:00.000Z"))
        let plan = try Self.convertir(donnees: d)
        #expect(try Self.octets(plan, "releve-maison.json") == Data(contentsOf: Self.exemple().appendingPathComponent("noms.json")))
    }

    @Test(arguments: ["2026-10-16T08:00:00.000Z", "2026-10-14T08:00:00.000Z"])
    func unReleveExistantPlusRecentOuDeLaMemeDateGagne(date: String) throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", Self.releve(date: date))
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("noms.json"), .releveMaisonNonPlusRecent))
        #expect(try d.instantane() == avant)
    }

    @Test func unReleveExistantNonLisibleResteIntouche() throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", "pas du json")
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("noms.json"), .fichierExistantNonLisible))
    }

    @Test func unReleveDeLExportIllisibleOuTropRecentNEstPasPris() throws {
        let copie = try Copie(.maillageThread)
        let texte = try String(contentsOf: copie.url("noms.json"), encoding: .utf8)
        try copie.remplacer("noms.json", par: Data(texte.replacingOccurrences(of: #""version" : 2"#, with: #""version" : 3"#).utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("noms.json"), .fichierIllisible))
    }

    // MARK: Reglages

    static let reglagesAttendus: [String: C.Valeur] = [
        "thread.sondeSerieUSB": .texte("SERIE-T1"), "thread.sondeNom": .texte("SONDE-T1"),
        "thread.sondeHote": .texte("sonde-t1.local"), "thread.sondeLiaison": .texte("reseau"),
        "thread.scissionsNotifiees": .listeTextes(["0000000000000E01"]),
        "notification.thread.scission": .bool(true), "notification.thread.routeurDisparu": .bool(true),
        "notification.thread.pertes": .bool(false), "notification.thread.informations": .bool(false),
        "vuePieces3D": .bool(true), "etagesEnGrille": .bool(false), "legendeRepliee": .bool(true),
        "grapheDejaOuvert": .bool(true), "ouvertureSessionProposee": .bool(true), "AppleLanguages": .listeTextes(["fr"]),
    ]

    @Test func lesReglagesPrennentLesCleDeMaillageIoT() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.reglages == Self.reglagesAttendus)
        #expect(plan.reglages.count == 15)
        #expect(plan.reglages["sondeNom"] == nil && plan.reglages["notification.pertes"] == nil, "aucune cle ancienne ni commune")
    }

    static func reglagesSans(_ cles: Set<String>) throws -> (C.Manifeste, C.Reglages) {
        let (manifeste, reglages) = try C.verifierDossier(exemple())
        let valeurs = reglages.valeurs.filter { !cles.contains($0.key) }
        return (manifeste, C.Reglages(app: .maillageThread, valeurs: valeurs, nonRepris: reglages.nonRepris))
    }

    static func convertir(_ manifeste: C.Manifeste, _ reglages: C.Reglages, presents: Set<String> = []) throws -> PlanReprise {
        try ConversionThread.convertir(dossier: exemple(), manifeste: manifeste, reglages: reglages,
                                       etat: etat(Donnees(), presents: presents), maintenant: maintenant, calendrier: calendrier)
    }

    @Test func laLiaisonDeLaSondeEstRecopieeTelleQuelle() throws {
        for valeur in ["usb", "reseau", "auto", "une valeur inattendue"] {
            let (m, r) = try Self.reglagesSans(["sondeLiaison"])
            var valeurs = r.valeurs
            valeurs["sondeLiaison"] = .texte(valeur)
            let plan = try Self.convertir(m, C.Reglages(app: .maillageThread, valeurs: valeurs, nonRepris: r.nonRepris))
            #expect(plan.reglages["thread.sondeLiaison"] == .texte(valeur))
        }
    }

    @Test func laLiaisonAbsenteResteAbsente() throws {
        // Absente de l'ancienne app (lue USB par defaut) : on n'ecrit rien, jamais de valeur par defaut.
        let (m, r) = try Self.reglagesSans(["sondeLiaison"])
        let plan = try Self.convertir(m, r)
        #expect(plan.reglages["thread.sondeLiaison"] == nil)
        #expect(plan.reglages["sondeLiaison"] == nil)
        #expect(plan.reglages.count == 14)
        #expect(!plan.nonPris.contains { $0.nature == .reglage("sondeLiaison") || $0.nature == .reglage("thread.sondeLiaison") },
                "rien a citer : la cle n'existait pas")
    }

    @Test func lesNotificationsAbsentesNeSontPasEcrites() throws {
        let cles: Set<String> = ["notification.scission", "notification.routeurDisparu", "notification.pertes", "notification.informations"]
        let (m, r) = try Self.reglagesSans(cles)
        let plan = try Self.convertir(m, r)
        #expect(!plan.reglages.keys.contains { $0.hasPrefix("notification.") }, "une notification jamais changee garde son defaut")
        #expect(plan.reglages.count == 11)
    }

    @Test func uneNotificationSeulementEstEcriteSousSonProtocole() throws {
        let cles: Set<String> = ["notification.scission", "notification.routeurDisparu", "notification.informations"]
        let (m, r) = try Self.reglagesSans(cles)
        let plan = try Self.convertir(m, r)
        #expect(plan.reglages.filter { $0.key.hasPrefix("notification.") } == ["notification.thread.pertes": .bool(false)])
    }

    @Test func lesReglagesLaissesParLAncienneAppSontCites() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let (_, reglages) = try C.verifierDossier(Self.exemple())
        #expect(reglages.nonRepris.count == 14)
        for (cle, raison) in reglages.nonRepris {
            #expect(Self.cite(plan, .reglage(cle), .laisseParLAncienneApp(raison)), "\(cle)")
        }
        for cle in ["SUHasLaunchedBefore", "NSWindow Frame graphe", "reglages.onglet", "dossierNoms"] {
            #expect(Self.cite(plan, .reglage(cle), .laisseParLAncienneApp(.horsContrat)), "\(cle)")
        }
    }

    @Test func unReglageDejaPoseDansMaillageIoTNEstJamaisEcrase() throws {
        // cle de Maillage IoT deja posee -> cle de l'export, citee au resume
        let presents = ["thread.sondeNom": "sondeNom", "thread.sondeLiaison": "sondeLiaison",
                        "notification.thread.pertes": "notification.pertes", "vuePieces3D": "vuePieces3D",
                        "AppleLanguages": "AppleLanguages"]
        let plan = try Self.convertir(donnees: Donnees(), presents: Set(presents.keys))
        for (cible, ancienne) in presents {
            #expect(plan.reglages[cible] == nil, "\(cible) ecrase")
            #expect(Self.cite(plan, .reglage(ancienne), .dejaDansMaillageIoT), "\(ancienne)")
        }
        #expect(plan.reglages.count == Self.reglagesAttendus.count - presents.count)
        #expect(plan.reglages["thread.sondeHote"] == .texte("sonde-t1.local"), "les autres sont ecrits")
    }

    @Test func laCleCommuneDeNotificationDejaPoseeProtegeLaCleDuProtocole() throws {
        // `notification.pertes` (3a) est relue par `Notifications.active` quand la cle du protocole manque : ecrire
        // `notification.thread.pertes` remplacerait ce choix.
        let plan = try Self.convertir(donnees: Donnees(), presents: ["notification.pertes"])
        #expect(plan.reglages["notification.thread.pertes"] == nil)
        #expect(Self.cite(plan, .reglage("notification.pertes"), .dejaDansMaillageIoT))
        #expect(plan.reglages["notification.thread.scission"] == .bool(true))
    }

    @MainActor @Test func lesCleCiblesSontCellesDeLApp() throws {
        #expect(["thread.sondeSerieUSB", "thread.sondeNom", "thread.sondeHote", "thread.sondeLiaison"] == SondeMaillageThread.cles)
        #expect(SurveillanceThread.cleScissionsNotifiees == "thread.scissionsNotifiees")
        for c in Notifications.categories(de: .thread) {
            #expect(Self.reglagesAttendus[Notifications.cle(c, de: .thread)] != nil, "\(c)")
            #expect(FusionReprise.cibleReglage("notification.\(c.rawValue)", de: .maillageThread) == Notifications.cle(c, de: .thread))
            #expect(FusionReprise.cleCommuneDeNotification("notification.\(c.rawValue)", de: .maillageThread) == Notifications.cleCommune(c))
        }
        #expect(FusionReprise.cibleReglage(LangueApp.cle, de: .maillageThread) == LangueApp.cle)
    }

    @Test(arguments: C.AppSource.allCases)
    func chaqueReglageConnuADeCible(app: C.AppSource) throws {
        let cibles = C.reglagesConnus(de: app).map { FusionReprise.cibleReglage($0.cle, de: app) }
        #expect(!cibles.contains { $0 == nil }, "un reglage connu sans cible serait perdu en silence")
        let reelles = cibles.compactMap { $0 }
        #expect(Set(reelles).count == reelles.count, "deux reglages vers la meme cle")
        let reservees: Set<String> = ["thread.actif", "zigbee.actif", "thread.repriseTrousseauSonde", "zigbee.repriseTrousseauSonde",
                                      "zigbee.repriseTrousseauPont", "notification.scission", "notification.routeurDisparu",
                                      "notification.pertes", "notification.informations"]
        #expect(Set(reelles).isDisjoint(with: reservees), "cles neuves d'IoT ou cles communes : jamais ecrites")
        #expect(FusionReprise.cibleReglage("reglages.onglet", de: app) == nil)
        #expect(FusionReprise.cibleReglage("SUHasLaunchedBefore", de: app) == nil)
    }

    @Test func unReglageDeLExportSansCibleEstCite() throws {
        let (m, r) = try C.verifierDossier(Self.exemple())
        var valeurs = r.valeurs
        valeurs["cleInconnue"] = .bool(true)
        let plan = try Self.convertir(m, C.Reglages(app: .maillageThread, valeurs: valeurs, nonRepris: r.nonRepris))
        #expect(plan.reglages["cleInconnue"] == nil)
        #expect(Self.cite(plan, .reglage("cleInconnue"), .sansEquivalent))
    }

    // MARK: Rien ne se perd en silence, rien n'est ecrit

    @Test func chaqueFichierDeLExportEstDansLePlanOuCite() throws {
        let (manifeste, _) = try C.verifierDossier(Self.exemple())
        let plan = try Self.convertir(donnees: Donnees())
        let places = Set(plan.fichiers.flatMap(\.sources))
        for f in manifeste.fichiers where f.chemin != C.nomReglages {
            let cite = plan.nonPris.contains { $0.nature == .fichier(f.chemin) }
            #expect(places.contains(f.chemin) != cite, "\(f.chemin) : exactement un des deux")
        }
        for f in manifeste.fichiersNonRepris {
            #expect(Self.cite(plan, .fichier(f.chemin), .laisseParLAncienneApp(f.raison)), "\(f.chemin)")
        }
        #expect(plan.fichiers.count == 12)
        #expect(plan.nonPris.filter { if case .fichier = $0.nature { true } else { false } }.count == 2 + 4)
    }

    @Test func lePlanEstTrieEtDeterministe() throws {
        let d = try Donnees()
        let a = try Self.convertir(donnees: d)
        let b = try Self.convertir(donnees: d)
        #expect(a == b)
        #expect(a.fichiers.map(\.chemin) == a.fichiers.map(\.chemin).sorted())
        #expect(a.app == .maillageThread)
    }

    @Test func laConversionNEcritNiDansLApp() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Mon choix"},"version":1}"#)
        try d.ecrire("Journal/journal-2026-10.jsonl", "{\"a\":1}\n")
        try d.ecrire("releve-maison.json", Self.releve(date: "2026-10-10T08:00:00.000Z"))
        try d.ecrire("Thread/associations.json", #"{"0000000000000009":"00000000000000A9"}"#)
        let avant = try d.instantane()
        let export = try Self.exemple()
        let avantExport = try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) }
        _ = try Self.convertir(donnees: d)
        #expect(try d.instantane() == avant, "le dossier de Maillage IoT est lu, jamais ecrit")
        #expect(try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) } == avantExport)
    }

    @MainActor @Test func lePlanAppliqueEstRelisibleParLesLecteursDeLApp() throws {
        let d = try Donnees()
        let plan = try Self.convertir(donnees: d)
        let sortie = try Donnees()
        for f in plan.fichiers { try sortie.ecrire(f.chemin, f.contenu.octets()) }
        #expect(Surnoms.lire(sortie.url("surnoms.json"), protocoleParDefaut: .thread).count == 5)
        #expect(PiecesRouteurs.lire(sortie.url("pieces-noeuds.json")).appareils.count == 1)
        #expect(PlacesGardees.lire(sortie.url("positions-pieces.json")).maisons.count == 2)
        #expect(Associations.lire(sortie.url("Thread/associations.json")).count == 2)
        #expect(IdentitesGardees.lire(sortie.url("Thread/identites-routeurs.json"))?.identites.count == 3)
        #expect(try NomsMaison.lire(Data(contentsOf: sortie.url("releve-maison.json"))).version == 2)
        let historique = HistoriqueFichiers(dossier: sortie.url("Thread"), calendrier: Self.calendrier)
        #expect(try historique.lire(depuis: .distantPast).count == 3 + 4 + 5, "les trois mois gardes, toutes leurs lignes")
        let journal = JournalFichiers(dossier: sortie.url("Journal"), politique: Surveillance.politiqueJournal)
        #expect(try journal.lire().count == 7)
    }
}
