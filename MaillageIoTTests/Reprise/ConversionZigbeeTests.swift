import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Phase 4, tache 5 : la conversion d'un export de Maillage Zigbee 1.1.1 (`ConversionZigbee`). Comme pour Thread : une
/// regle, un test ; chaque fichier et chaque reglage de l'inventaire (Zigbee) a le sien, et la conversion ne perd rien en
/// silence. L'export d'exemple est `MaillageIoTTests/Ressources/exports/zigbee-1.1.1` (date de reference 2026-10-17
/// 12:00 UTC) ; le dossier de donnees de Maillage IoT est un dossier temporaire. Valeurs inventees seulement.
@Suite("Conversion de Zigbee 1.1.1 vers Maillage IoT")
struct ConversionZigbeeTests {
    typealias C = ContratExport
    typealias T = ConversionThreadTests
    typealias Donnees = ConversionThreadTests.Donnees
    typealias Copie = ValidationExportTests.Copie
    typealias Echec = ValidationExportTests.Echec
    typealias Nature = ElementNonPris.Nature
    typealias Raison = ElementNonPris.Raison

    static let maintenant = T.maintenant
    static var calendrier: Calendar { T.calendrier }

    // MARK: Outils

    static func exemple() throws -> URL { try ExportsExempleTests.dossier(.maillageZigbee) }

    static func etat(_ d: Donnees, presents: Set<String> = []) -> EtatActuel {
        EtatActuel(dossier: d.racine, reglagesPresents: presents)
    }

    static func convertir(_ dossier: URL? = nil, donnees d: Donnees, presents: Set<String> = []) throws -> PlanReprise {
        try ConversionZigbee.convertir(dossier: dossier ?? exemple(), etat: etat(d, presents: presents),
                                       maintenant: maintenant, calendrier: calendrier)
    }

    static func octets(_ plan: PlanReprise, _ chemin: String) throws -> Data { try T.octets(plan, chemin) }
    static func objet(_ d: Data) throws -> [String: Any] { try T.objet(d) }
    static func lignes(_ d: Data) -> [String] { T.lignes(d) }
    static func lignesExport(_ chemin: String) throws -> [String] {
        T.lignes(try Data(contentsOf: exemple().appendingPathComponent(chemin)))
    }

    static func cite(_ plan: PlanReprise, _ nature: Nature, _ raison: Raison) -> Bool { T.cite(plan, nature, raison) }

    static func source(_ chemin: String) throws -> Data { try Data(contentsOf: exemple().appendingPathComponent(chemin)) }

    /// Retire un fichier de la copie d'un export (fichier et ligne du manifeste).
    static func retirer(_ chemin: String, de copie: Copie) throws {
        try copie.modifierManifeste { objet in
            objet["fichiers"] = try #require(objet["fichiers"] as? [[String: Any]]).filter { $0["chemin"] as? String != chemin }
        }
        try FileManager.default.removeItem(at: copie.url(chemin))
    }

    /// Depose les fichiers d'un plan dans un dossier de donnees (ce que fera l'application de la tache 6).
    static func appliquer(_ plan: PlanReprise, dans d: Donnees) throws {
        for f in plan.fichiers { try d.ecrire(f.chemin, f.contenu.octets()) }
    }

    // MARK: L'export

    @Test func uneAppDifferenteEstRefusee() throws {
        let d = try Donnees()
        #expect(throws: ErreurConversion.self) {
            try ConversionZigbee.convertir(dossier: ExportsExempleTests.dossier(.maillageThread), etat: Self.etat(d),
                                           maintenant: Self.maintenant, calendrier: Self.calendrier)
        }
    }

    @Test func unExportAltereEstRefuse() throws {
        let copie = try Copie(.maillageZigbee)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = String(repeating: "0", count: 64) }
        #expect(throws: C.Erreur.empreinteFausse("surnoms.json")) {
            try Self.convertir(copie.dossier, donnees: Donnees())
        }
    }

    // MARK: surnoms.json

    @Test func lesSurnomsPrennentLePrefixeZigbee() throws {
        let d = try Donnees()
        let plan = try Self.convertir(donnees: d)
        let f = try #require(plan.fichier("surnoms.json"))
        #expect(f.sources == ["surnoms.json"])
        let brut = try Self.objet(f.contenu.octets())
        #expect(brut["version"] as? Int == 1)
        #expect(brut["surnoms"] as? [String: String] == [
            "zigbee:00000000000000C1": "Routeur 1", "zigbee:00000000000000F1": "Capteur 1", "zigbee:00000000000000F2": "Ampoule 1",
        ])
        // Le fichier est ecrit en v1 prefixe : le lecteur de l'app, meme avec Thread pour defaut, ne le prend pas pour du Thread.
        let relu = d.url("relu-surnoms.json")
        try f.contenu.octets().write(to: relu)
        let lus = Surnoms.lire(relu, protocoleParDefaut: .thread)
        #expect(lus.count == 3)
        #expect(lus[IdNoeud(.zigbee, "00000000000000C1")] == "Routeur 1")
        #expect(!lus.keys.contains { $0.protocole == .thread }, "aucun surnom de Zigbee range sous thread:")
    }

    @Test func unSurnomDejaDonneDansMaillageIoTEstGarde() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"zigbee:00000000000000C1":"Mon choix","thread:0000000000000001":"Prise Thread"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        let surnoms = try #require(Self.objet(Self.octets(plan, "surnoms.json"))["surnoms"] as? [String: String])
        #expect(surnoms["zigbee:00000000000000C1"] == "Mon choix", "le choix de Djoko l'emporte")
        #expect(surnoms["thread:0000000000000001"] == "Prise Thread", "un surnom de Thread reste")
        #expect(surnoms["zigbee:00000000000000F1"] == "Capteur 1", "ce qui manquait est ajoute")
        #expect(surnoms.count == 4)
        #expect(Self.cite(plan, .entrees(fichier: "surnoms.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func tousLesSurnomsDejaLaNeSontPasReecrits() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"zigbee:00000000000000C1":"Routeur 1","zigbee:00000000000000F1":"Capteur 1","zigbee:00000000000000F2":"Ampoule 1"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(Self.cite(plan, .fichier("surnoms.json"), .dejaDansMaillageIoT))
    }

    @Test func unSurnomsVideOuIllisibleNEstPasPrisEtEstCite() throws {
        for (contenu, raison) in [("{}", Raison.vide), ("[1, 2]", Raison.fichierIllisible)] {
            let copie = try Copie(.maillageZigbee)
            try copie.remplacer("surnoms.json", par: Data(contenu.utf8))
            let plan = try Self.convertir(copie.dossier, donnees: Donnees())
            #expect(plan.fichier("surnoms.json") == nil, "\(contenu)")
            #expect(Self.cite(plan, .fichier("surnoms.json"), raison), "\(contenu)")
        }
    }

    @Test func unSurnomsAbsentDeLExportNeFaitRien() throws {
        // Le vrai export de Zigbee 1.1.1 n'a pas de `surnoms.json` quand aucun surnom n'a ete donne.
        let copie = try Copie(.maillageZigbee)
        try Self.retirer("surnoms.json", de: copie)
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("surnoms.json") == nil)
        #expect(!plan.nonPris.contains { $0.nature == .fichier("surnoms.json") }, "rien a citer : il n'existait pas")
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

    @Test func lesPiecesDeZigbeeDeviennentPiecesNoeudsVersion2() throws {
        let d = try Donnees()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("pieces-routeurs.json") == nil, "l'ancien nom n'est jamais depose : il serait relu comme Thread")
        let f = try #require(plan.fichier("pieces-noeuds.json"))
        #expect(f.sources == ["pieces-routeurs.json"])
        let u = d.url("relu-pieces.json")
        try f.contenu.octets().write(to: u)
        let p = PiecesRouteurs.lire(u)
        #expect(p.version == 2)
        #expect(p.maisons.isEmpty, "Zigbee n'a que des appareils")
        // Le domicile « 0000000000000B01 » est l'identifiant du pont, pas un nom de maison : garde tel quel.
        #expect(p.appareils == [
            "0000000000000B01": [IdNoeud(.zigbee, "00000000000000C2"): "Pièce 2"],
            "Maison 1": [IdNoeud(.zigbee, "00000000000000C1"): "Pièce 1", IdNoeud(.zigbee, "00000000000000E1"): "Pièce 3"],
        ])
        let texte = String(decoding: try f.contenu.octets(), as: UTF8.self)
        #expect(texte.contains(#""zigbee:00000000000000C1""#) && !texte.contains("thread:"))
    }

    @Test func lesAdressesLonguesDesPiecesDeZigbeeSontEnMajuscules() throws {
        let copie = try Copie(.maillageZigbee)
        try copie.remplacer("pieces-routeurs.json", par: Data(#"{"appareils":{"Maison 1":{"00000000abcdef01":"Pièce 2"}},"version":1}"#.utf8))
        let d = try Donnees()
        let plan = try Self.convertir(copie.dossier, donnees: d)
        let u = d.url("relu-pieces.json")
        try Self.octets(plan, "pieces-noeuds.json").write(to: u)
        #expect(PiecesRouteurs.lire(u).appareils == ["Maison 1": [IdNoeud(.zigbee, "00000000ABCDEF01"): "Pièce 2"]])
    }

    @Test func leChoixExistantDUnAppareilGagneEtCeuxDeThreadRestent() throws {
        let d = try Donnees()
        var existant = PiecesRouteurs()
        existant.choisir("Salon", appareil: IdNoeud(.zigbee, "00000000000000C1"), domicile: "Maison 1")
        existant.choisir("Bureau", routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1")
        try d.ecrire("pieces-noeuds.json", T.encodeur().encode(existant))
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-pieces.json")
        try Self.octets(plan, "pieces-noeuds.json").write(to: u)
        let p = PiecesRouteurs.lire(u)
        #expect(p.choix(appareil: IdNoeud(.zigbee, "00000000000000C1"), domicile: "Maison 1") == "Salon", "le choix existant l'emporte")
        #expect(p.choix(appareil: IdNoeud(.zigbee, "00000000000000E1"), domicile: "Maison 1") == "Pièce 3", "le manquant est ajoute")
        #expect(p.choix(routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1") == "Bureau", "un choix de Thread reste")
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
        let copie = try Copie(.maillageZigbee)
        try copie.remplacer("pieces-routeurs.json", par: Data(#"{"version":2,"appareils":{}}"#.utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("pieces-noeuds.json") == nil)
        #expect(Self.cite(plan, .fichier("pieces-routeurs.json"), .fichierIllisible))
    }

    // MARK: positions-pieces.json

    @Test func lesPositionsSansFichierExistantSontCopieesTellesQuelles() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("positions-pieces.json"))
        #expect(try f.contenu.octets() == Self.source("positions-pieces.json"))
        guard case .copie(_, let sha) = f.contenu else { throw Echec("copie attendue") }
        #expect(sha == C.sha256(try Self.source("positions-pieces.json")))
    }

    @Test func lesPositionsSeFusionnentEnProfondeur() throws {
        var existant = PlacesGardees()
        existant.maisons["Maison 1"] = PlacesGardees.Maison(
            ordreEtages: ["zone:Étage 1"], etages: ["zone:Étage 1": ["piece:Pièce 1": .init(x: 9, z: 9)]], aCote: [:])
        let d = try Donnees()
        try d.ecrire("positions-pieces.json", T.encodeur().encode(existant))
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-positions.json")
        try Self.octets(plan, "positions-pieces.json").write(to: u)
        let p = PlacesGardees.lire(u)
        let m1 = try #require(p.maisons["Maison 1"])
        #expect(m1.etages["zone:Étage 1"]?["piece:Pièce 1"] == .init(x: 9, z: 9), "la place existante l'emporte")
        #expect(m1.etages["zone:Étage 1"]?["piece:Pièce 2"] == .init(x: -3.25, z: 0.5), "la place manquante est ajoutee")
        #expect(m1.etages["zone:Étage 2"]?["piece:Pièce 3"] == .init(x: 0, z: 4))
        #expect(m1.aCote["zone:Jardin"] == .init(etage: "zone:Étage 1", dehors: true))
        #expect(p.maisons["0000000000000B01"]?.etages["zone:Zone 1"]?["routeur:00000000000000C2"] == .init(x: 2, z: 2),
                "le domicile en identifiant du pont est garde tel quel")
        #expect(Self.cite(plan, .entrees(fichier: "positions-pieces.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func desPositionsExistantesNonLisiblesOuDejaToutesLaRestentIntouchees() throws {
        let d1 = try Donnees()
        try d1.ecrire("positions-pieces.json", #"{"version":9,"maisons":{}}"#)
        let p1 = try Self.convertir(donnees: d1)
        #expect(p1.fichier("positions-pieces.json") == nil)
        #expect(Self.cite(p1, .fichier("positions-pieces.json"), .fichierExistantNonLisible))
        let d2 = try Donnees()
        try d2.ecrire("positions-pieces.json", Self.source("positions-pieces.json"))
        let p2 = try Self.convertir(donnees: d2)
        #expect(p2.fichier("positions-pieces.json") == nil)
        #expect(Self.cite(p2, .fichier("positions-pieces.json"), .dejaDansMaillageIoT))
    }

    // MARK: Fichiers propres a Zigbee

    static let fichiersZigbee = ["noms-pont.json", "appariements-maison.json", "dernier-maillage.json"]

    @Test(arguments: fichiersZigbee)
    func unFichierDuModuleSansExistantEstCopieSousZigbee(chemin: String) throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("Zigbee/\(chemin)"))
        #expect(f.sources == [chemin])
        #expect(try f.contenu.octets() == Self.source(chemin), "memes octets, memes cles")
        guard case .copie(let url, let sha) = f.contenu else { throw Echec("copie attendue") }
        #expect(url.lastPathComponent == chemin)
        #expect(sha == C.sha256(try Self.source(chemin)))
        #expect(plan.fichier(chemin) == nil, "rien n'est depose a la racine")
        #expect(plan.fichier("Thread/\(chemin)") == nil)
    }

    @Test func lesAppariementsSeFusionnentEtLeChoixExistantGagne() throws {
        let d = try Donnees()
        try d.ecrire("Zigbee/appariements-maison.json", #"{"ids":{"00000000000000C1":"id-existant","00000000000000AA":"id-aa"},"version":1}"#)
        let plan = try Self.convertir(donnees: d)
        let u = d.url("relu-appariements.json")
        try Self.octets(plan, "Zigbee/appariements-maison.json").write(to: u)
        #expect(MemoireAppariements.lire(u).ids == [
            "00000000000000C1": "id-existant", "00000000000000AA": "id-aa",
            "00000000000000F1": "00000000-0000-4000-8000-0000000000B2",
        ])
        #expect(Self.cite(plan, .entrees(fichier: "appariements-maison.json", nombre: 1), .dejaDansMaillageIoT))
    }

    @Test func desAppariementsDejaToutLaNeSontPasReecrits() throws {
        let d = try Donnees()
        try d.ecrire("Zigbee/appariements-maison.json", Self.source("appariements-maison.json"))
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Zigbee/appariements-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("appariements-maison.json"), .dejaDansMaillageIoT))
    }

    static func nomsPont(date: String) throws -> Data {
        let texte = try String(decoding: source("noms-pont.json"), as: UTF8.self)
        return Data(texte.replacingOccurrences(of: "2026-10-14T09:00:00.000Z", with: date).utf8)
    }

    @Test func leCacheDuPontLePlusRecentGagne() throws {
        // L'export date du 2026-10-14T09:00:00.000Z.
        let d1 = try Donnees()
        try d1.ecrire("Zigbee/noms-pont.json", Self.nomsPont(date: "2026-10-10T09:00:00.000Z"))
        #expect(try Self.octets(Self.convertir(donnees: d1), "Zigbee/noms-pont.json") == Self.source("noms-pont.json"),
                "un cache plus ancien est remplace")
        for date in ["2026-10-16T09:00:00.000Z", "2026-10-14T09:00:00.000Z"] {
            let d = try Donnees()
            try d.ecrire("Zigbee/noms-pont.json", Self.nomsPont(date: date))
            let avant = try d.instantane()
            let plan = try Self.convertir(donnees: d)
            #expect(plan.fichier("Zigbee/noms-pont.json") == nil, "\(date)")
            #expect(Self.cite(plan, .fichier("noms-pont.json"), .dejaDansMaillageIoT), "\(date)")
            #expect(try d.instantane() == avant)
        }
    }

    @Test func leDernierMaillageLePlusRecentGagne() throws {
        // L'export a recu le 2026-10-14T09:43:00.000Z.
        let recent = #"{"incomplet":false,"maillage":{},"recu":"2026-10-16T08:00:00.000Z"}"#
        let ancien = #"{"incomplet":true,"maillage":{},"recu":"2026-10-10T08:00:00.000Z"}"#
        let d1 = try Donnees()
        try d1.ecrire("Zigbee/dernier-maillage.json", recent)
        let p1 = try Self.convertir(donnees: d1)
        #expect(p1.fichier("Zigbee/dernier-maillage.json") == nil)
        #expect(Self.cite(p1, .fichier("dernier-maillage.json"), .dejaDansMaillageIoT))
        let d2 = try Donnees()
        try d2.ecrire("Zigbee/dernier-maillage.json", ancien)
        let p2 = try Self.convertir(donnees: d2)
        #expect(try Self.octets(p2, "Zigbee/dernier-maillage.json") == Self.source("dernier-maillage.json"))
    }

    @Test func unFichierDuModuleIllisibleDansLExportNEstPasPrisEtEstCite() throws {
        let copie = try Copie(.maillageZigbee)
        for chemin in Self.fichiersZigbee { try copie.remplacer(chemin, par: Data("[]".utf8)) }
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        for chemin in Self.fichiersZigbee {
            #expect(plan.fichier("Zigbee/\(chemin)") == nil, "\(chemin)")
            #expect(Self.cite(plan, .fichier(chemin), .fichierIllisible), "\(chemin)")
        }
    }

    @Test(arguments: fichiersZigbee)
    func unFichierDuModuleExistantNonLisibleResteIntouche(chemin: String) throws {
        let d = try Donnees()
        try d.ecrire("Zigbee/\(chemin)", "pas du json")
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Zigbee/\(chemin)") == nil)
        #expect(Self.cite(plan, .fichier(chemin), .fichierExistantNonLisible))
        #expect(try d.instantane() == avant)
    }

    // MARK: Historique mensuel

    @Test func lHistoriqueDeMoinsDe90JoursVaSousZigbeeSansChangement() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("Zigbee/maillage-2026-10.jsonl"))
        #expect(f.sources == ["maillage-2026-10.jsonl"])
        #expect(try f.contenu.octets() == Self.source("maillage-2026-10.jsonl"))
        #expect(plan.fichier("maillage-2026-10.jsonl") == nil, "rien a la racine")
        #expect(plan.fichier("Thread/maillage-2026-10.jsonl") == nil)
    }

    @Test func lHistoriqueEtLeJournalDePlusDe90JoursSontEcartesEtCites() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.fichier("Zigbee/maillage-2026-04.jsonl") == nil)
        #expect(plan.fichier("Journal/journal-2026-04.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("maillage-2026-04.jsonl"), .plusDe90Jours))
        #expect(Self.cite(plan, .fichier("Journal/journal-2026-04.jsonl"), .plusDe90Jours))
    }

    @Test func lHistoriqueSeFusionneAvecLExistantSansDoublon() throws {
        let importees = try Self.lignesExport("maillage-2026-10.jsonl")
        let propre = #"{"date":"2026-10-16T08:00:00.000Z","liens":[],"noeuds":[],"parents":[],"signaux":[],"sonde":null}"#
        let d = try Donnees()
        try d.ecrire("Zigbee/maillage-2026-10.jsonl", ([importees[0], importees[1], propre]).joined(separator: "\n") + "\n")
        let plan = try Self.convertir(donnees: d)
        let f = try #require(plan.fichier("Zigbee/maillage-2026-10.jsonl"))
        #expect(Self.lignes(try f.contenu.octets()) == [importees[0], importees[1], propre] + Array(importees[2...]),
                "l'existant d'abord, tel quel, puis les lignes de l'export qui n'y sont pas")
        #expect(Self.cite(plan, .entrees(fichier: "maillage-2026-10.jsonl", nombre: 2), .dejaDansMaillageIoT))
    }

    @Test func unMoisDeZigbeeDejaToutEntierLaEstCite() throws {
        let d = try Donnees()
        try d.ecrire("Zigbee/maillage-2026-10.jsonl", Self.source("maillage-2026-10.jsonl"))
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Zigbee/maillage-2026-10.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("maillage-2026-10.jsonl"), .dejaDansMaillageIoT))
    }

    @Test func unHistoriqueSansFinDeLigneRecoitUneFinDeLigne() throws {
        let copie = try Copie(.maillageZigbee)
        let ligne = #"{"date":"2026-10-12T08:25:00.000Z","liens":[],"noeuds":[],"parents":[],"signaux":[],"sonde":null}"#
        try copie.remplacer("maillage-2026-10.jsonl", par: Data(ligne.utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(try Self.octets(plan, "Zigbee/maillage-2026-10.jsonl") == Data((ligne + "\n").utf8))
    }

    // MARK: Journal : le protocole de chaque ligne

    /// Une ligne decodee comme le journal de l'app la lit.
    static func evenement(_ ligne: String) throws -> Evenement {
        try CodageJSON.decodeur().decode(Evenement.self, from: Data(ligne.utf8))
    }

    @Test func chaqueLigneDuJournalRecoitLeProtocoleZigbee() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("Journal/journal-2026-10.jsonl"))
        #expect(f.sources == ["Journal/journal-2026-10.jsonl"])
        let sources = try Self.lignesExport("Journal/journal-2026-10.jsonl")
        let converties = Self.lignes(try f.contenu.octets())
        #expect(sources.count == 10 && converties.count == 10, "aucune ligne perdue")
        for (avant, apres) in zip(sources, converties) {
            #expect((try Self.evenement(avant)).protocole == nil, "la ligne d'origine se lirait Thread")
            var e = try Self.evenement(apres)
            #expect(e.protocole == .zigbee, "\(apres)")
            // Rien d'autre ne change : la ligne est celle que l'app ecrirait pour le meme evenement.
            #expect(String(decoding: try CodageJSON.encodeur().encode(e), as: UTF8.self) == apres)
            e.protocole = nil
            #expect(String(decoding: try CodageJSON.encodeur().encode(e), as: UTF8.self) == avant, "sinon, la ligne d'origine n'est pas retrouvee")
        }
        #expect(try f.contenu.octets().last == 0x0A)
    }

    @Test func leProtocoleSAjouteAuBonEndroitDeLaLigneEtSeulementAuPremierNiveau() {
        let p = Protocole.zigbee
        func ajoute(_ s: String) -> String { String(decoding: FusionReprise.avecProtocole(Data(s.utf8), p), as: UTF8.self) }
        #expect(ajoute(#"{"date":"d","type":"t"}"#) == #"{"date":"d","protocole":"zigbee","type":"t"}"#)
        #expect(ajoute(#"{"date":"d","sujet":{"id":"1"},"type":"t"}"#) == #"{"date":"d","protocole":"zigbee","sujet":{"id":"1"},"type":"t"}"#)
        #expect(ajoute(#"{"avant":"a","date":"d"}"#) == #"{"avant":"a","date":"d","protocole":"zigbee"}"#, "tout en dernier")
        #expect(ajoute("{}") == #"{"protocole":"zigbee"}"#)
        // Un « protocole » imbrique, ou dans un texte, n'est pas celui de la ligne ; les accolades et guillemets d'un texte non plus.
        #expect(ajoute(#"{"details":{"protocole":"thread"},"type":"t"}"#) == #"{"details":{"protocole":"thread"},"protocole":"zigbee","type":"t"}"#)
        #expect(ajoute(#"{"apres":"a \"protocole\": }","type":"t"}"#) == #"{"apres":"a \"protocole\": }","protocole":"zigbee","type":"t"}"#)
        // Une ligne qui a deja un protocole est laissee telle quelle ; une ligne qui n'est pas un objet aussi.
        let deja = #"{"date":"d","protocole":"thread","type":"t"}"#
        #expect(ajoute(deja) == deja)
        #expect(ajoute("pas du json") == "pas du json")
        #expect(ajoute("[1,2]") == "[1,2]")
        // Deterministe et idempotente.
        let une = ajoute(#"{"date":"d","type":"t"}"#)
        #expect(ajoute(une) == une)
    }

    @Test func uneLigneQuiADejaUnProtocoleLeGarde() throws {
        let copie = try Copie(.maillageZigbee)
        let thread = #"{"constate":true,"date":"2026-10-02T06:00:00.000Z","details":{},"gravite":"info","protocole":"thread","type":"surveillanceDemarree"}"#
        let sans = #"{"constate":true,"date":"2026-10-03T06:00:00.000Z","details":{},"gravite":"info","type":"surveillanceDemarree"}"#
        try copie.remplacer("Journal/journal-2026-10.jsonl", par: Data((thread + "\n" + sans + "\n").utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        let lignes = Self.lignes(try Self.octets(plan, "Journal/journal-2026-10.jsonl"))
        #expect(lignes[0] == thread)
        #expect(try Self.evenement(lignes[1]).protocole == .zigbee)
    }

    @Test func unJournalVideNeFaitRienEtEstCite() throws {
        let copie = try Copie(.maillageZigbee)
        try copie.remplacer("Journal/journal-2026-10.jsonl", par: Data())
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("Journal/journal-2026-10.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("Journal/journal-2026-10.jsonl"), .vide))
    }

    @Test func unJournalExistantNonLisibleResteIntouche() throws {
        let d = try Donnees()
        try FileManager.default.createDirectory(at: d.url("Journal/journal-2026-10.jsonl"), withIntermediateDirectories: true)
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("Journal/journal-2026-10.jsonl") == nil)
        #expect(Self.cite(plan, .fichier("Journal/journal-2026-10.jsonl"), .fichierExistantNonLisible))
    }

    @Test func leJournalSAjouteALExistantSansDupliquerLesLignesDejaLa() throws {
        let sources = try Self.lignesExport("Journal/journal-2026-10.jsonl")
        let convertie = try Self.lignes(Self.octets(Self.convertir(donnees: Donnees()), "Journal/journal-2026-10.jsonl"))
        let thread = #"{"constate":true,"date":"2026-10-16T06:00:00.000Z","details":{},"gravite":"info","protocole":"thread","type":"surveillanceDemarree"}"#
        let d = try Donnees()
        // L'existant a une ligne de Thread et deux lignes de Zigbee deja converties (un import precedent, ou l'app elle-meme).
        try d.ecrire("Journal/journal-2026-10.jsonl", [thread, convertie[2], convertie[0]].joined(separator: "\n") + "\n")
        let plan = try Self.convertir(donnees: d)
        let lignes = Self.lignes(try Self.octets(plan, "Journal/journal-2026-10.jsonl"))
        #expect(lignes == [thread, convertie[2], convertie[0]] + [convertie[1]] + Array(convertie[3...]),
                "l'existant tel quel, puis les lignes absentes, converties, dans l'ordre de l'export")
        #expect(!lignes.contains(sources[0]), "aucune ligne sans protocole ne passe")
        #expect(Self.cite(plan, .entrees(fichier: "Journal/journal-2026-10.jsonl", nombre: 2), .dejaDansMaillageIoT))
    }

    @Test func reimporterLeMemeJournalNeChangeRienALOctetPres() throws {
        let d = try Donnees()
        let existant = #"{"constate":true,"date":"2026-10-16T06:00:00.000Z","details":{},"gravite":"info","protocole":"thread","type":"surveillanceDemarree"}"# + "\n"
        try d.ecrire("Journal/journal-2026-10.jsonl", existant)
        let premier = try Self.convertir(donnees: d)
        try Self.appliquer(premier, dans: d)
        let apres1 = try d.instantane()
        let second = try Self.convertir(donnees: d)
        #expect(second.fichier("Journal/journal-2026-10.jsonl") == nil, "plus rien a ajouter")
        #expect(Self.cite(second, .fichier("Journal/journal-2026-10.jsonl"), .dejaDansMaillageIoT))
        try Self.appliquer(second, dans: d)
        #expect(try d.instantane() == apres1)
        let journal = try #require(apres1["Journal/journal-2026-10.jsonl"])
        #expect(Self.lignes(journal).count == 11)
    }

    @Test func leJournalVuParLApp() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let sortie = try Donnees()
        for f in plan.fichiers { try sortie.ecrire(f.chemin, f.contenu.octets()) }
        let journal = JournalFichiers(dossier: sortie.url("Journal"), politique: Surveillance.politiqueJournal)
        let evenements = try journal.lire()
        #expect(evenements.count == 10)
        #expect(evenements.allSatisfy { $0.protocole == .zigbee }, "aucun evenement de Zigbee lu comme Thread")
        let sujets = Set(evenements.compactMap { $0.sujet?.id })
        #expect(sujets.isSubset(of: ["00000000000000C1", "00000000000000C2", "00000000000000F1", "00000000000000F2"]),
                "les identifiants du journal restent bruts, sans prefixe")
    }

    // MARK: releve-maison.json

    static func releve(date: String) throws -> Data {
        let texte = try String(decoding: source("releve-maison.json"), as: UTF8.self)
        return Data(texte.replacingOccurrences(of: "2026-10-14T09:30:00.000Z", with: date).utf8)
    }

    @Test func leReleveDeMaisonSansExistantEstPris() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let f = try #require(plan.fichier("releve-maison.json"))
        #expect(f.sources == ["releve-maison.json"])
        #expect(try f.contenu.octets() == Self.source("releve-maison.json"))
        #expect(try NomsMaison.lire(f.contenu.octets()).accessoires.count > 0)
    }

    @Test func unReleveExistantPlusAncienEstRemplace() throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", Self.releve(date: "2026-10-10T08:00:00.000Z"))
        let plan = try Self.convertir(donnees: d)
        #expect(try Self.octets(plan, "releve-maison.json") == Self.source("releve-maison.json"))
    }

    @Test(arguments: ["2026-10-16T08:00:00.000Z", "2026-10-14T09:30:00.000Z"])
    func unReleveExistantPlusRecentOuDeLaMemeDateGagne(date: String) throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", Self.releve(date: date))
        let avant = try d.instantane()
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("releve-maison.json"), .releveMaisonNonPlusRecent))
        #expect(try d.instantane() == avant)
    }

    @Test func unReleveExistantNonLisibleResteIntouche() throws {
        let d = try Donnees()
        try d.ecrire("releve-maison.json", "pas du json")
        let plan = try Self.convertir(donnees: d)
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("releve-maison.json"), .fichierExistantNonLisible))
    }

    @Test func unReleveDeLExportIllisibleOuTropRecentNEstPasPris() throws {
        let copie = try Copie(.maillageZigbee)
        let texte = try String(contentsOf: copie.url("releve-maison.json"), encoding: .utf8)
        try copie.remplacer("releve-maison.json", par: Data(texte.replacingOccurrences(of: #""version" : 2"#, with: #""version" : 3"#).utf8))
        let plan = try Self.convertir(copie.dossier, donnees: Donnees())
        #expect(plan.fichier("releve-maison.json") == nil)
        #expect(Self.cite(plan, .fichier("releve-maison.json"), .fichierIllisible))
    }

    // MARK: Reglages

    static let pontHue = Data(base64Encoded: "eyJhZHJlc3NlIjoiMTkyLjAuMi4xMCIsImlkZW50aWZpYW50IjoiMDAwMDAwMDAwMDAwMEIwMSIsIm1hbnVlbCI6ZmFsc2UsIm1vZGVsZSI6IkJTQjAwMiJ9")!

    static let reglagesAttendus: [String: C.Valeur] = [
        "zigbee.sondeSerieUSB": .texte("SERIE-Z1"), "zigbee.sondeNom": .texte("SONDE-Z1"), "zigbee.sondeIeee": .texte("00000000000000E1"),
        "zigbee.sondeNomWifi": .texte("Wifi 1"), "zigbee.sondePagesTables": .entier(4), "zigbee.sondeChemin": .texte("automatique"),
        "zigbee.pont.hue": .donnees(pontHue),
        "zigbee.liensMontres": .texte("chemins"), "zigbee.voisinsALaSelection": .bool(true),
        "notification.zigbee.routeurDisparu": .bool(true), "notification.zigbee.pertes": .bool(true),
        "notification.zigbee.informations": .bool(false),
        "vuePieces3D": .bool(true), "etagesEnGrille": .bool(false), "legendeRepliee": .bool(true),
        "grapheDejaOuvert": .bool(true), "ouvertureSessionProposee": .bool(true), "AppleLanguages": .listeTextes(["fr", "en"]),
    ]

    @Test func lesReglagesPrennentLesCleDeMaillageIoT() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.reglages == Self.reglagesAttendus)
        #expect(plan.reglages.count == 18)
        #expect(plan.reglages["sondeNom"] == nil && plan.reglages["notification.pertes"] == nil, "aucune cle ancienne ni commune")
    }

    @Test func lePontRetenuEstRepris() throws {
        // `pont.hue` donne l'identifiant du pont a la reprise de sa cle du trousseau (`zigbee.repriseTrousseauPont`).
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.reglages["zigbee.pont.hue"] == .donnees(Self.pontHue))
        let json = try #require(JSONSerialization.jsonObject(with: Self.pontHue) as? [String: Any])
        #expect(json["identifiant"] as? String == "0000000000000B01", "l'identifiant du pont est dans la valeur reprise")
        #expect(plan.reglages["zigbee.repriseTrousseauPont"] == nil, "la memoire des reprises n'est jamais ecrite")
    }

    @Test func leBudgetDeTourneeEstRepris() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(plan.reglages["zigbee.sondePagesTables"] == .entier(4))
    }

    @Test func leJournalDesPagesEstTransitoireEtCite() throws {
        let plan = try Self.convertir(donnees: Donnees())
        #expect(!plan.reglages.keys.contains { $0.contains("JournalPages") }, "jamais repris")
        #expect(Self.cite(plan, .reglage("sondeJournalPages"), .laisseParLAncienneApp(.transitoire)))
    }

    static func reglagesSans(_ cles: Set<String>) throws -> (C.Manifeste, C.Reglages) {
        let (manifeste, reglages) = try C.verifierDossier(exemple())
        let valeurs = reglages.valeurs.filter { !cles.contains($0.key) }
        return (manifeste, C.Reglages(app: .maillageZigbee, valeurs: valeurs, nonRepris: reglages.nonRepris))
    }

    static func convertir(_ manifeste: C.Manifeste, _ reglages: C.Reglages, presents: Set<String> = []) throws -> PlanReprise {
        try ConversionZigbee.convertir(dossier: exemple(), manifeste: manifeste, reglages: reglages,
                                       etat: etat(Donnees(), presents: presents), maintenant: maintenant, calendrier: calendrier)
    }

    @Test func uneCleAbsenteResteAbsenteEtNEstPasCitee() throws {
        for (ancienne, cible) in [("sondeChemin", "zigbee.sondeChemin"), ("pont.hue", "zigbee.pont.hue"),
                                  ("sondePagesTables", "zigbee.sondePagesTables"), ("liensMontres", "zigbee.liensMontres"),
                                  ("voisinsALaSelection", "zigbee.voisinsALaSelection"), ("sondeIeee", "zigbee.sondeIeee")] {
            let (m, r) = try Self.reglagesSans([ancienne])
            let plan = try Self.convertir(m, r)
            #expect(plan.reglages[cible] == nil && plan.reglages[ancienne] == nil, "\(ancienne)")
            #expect(plan.reglages.count == 17, "\(ancienne)")
            #expect(!plan.nonPris.contains { $0.nature == .reglage(ancienne) || $0.nature == .reglage(cible) }, "\(ancienne) : rien a citer")
        }
    }

    @Test func lesNotificationsAbsentesNeSontPasEcrites() throws {
        let cles: Set<String> = ["notification.routeurDisparu", "notification.pertes", "notification.informations"]
        let (m, r) = try Self.reglagesSans(cles)
        let plan = try Self.convertir(m, r)
        #expect(!plan.reglages.keys.contains { $0.hasPrefix("notification.") }, "une notification jamais changee garde son defaut")
        #expect(plan.reglages.count == 15)
    }

    @Test func uneNotificationSeulementEstEcriteSousSonProtocole() throws {
        let (m, r) = try Self.reglagesSans(["notification.routeurDisparu", "notification.informations"])
        let plan = try Self.convertir(m, r)
        #expect(plan.reglages.filter { $0.key.hasPrefix("notification.") } == ["notification.zigbee.pertes": .bool(true)])
    }

    @Test func lesReglagesLaissesParLAncienneAppSontCites() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let (_, reglages) = try C.verifierDossier(Self.exemple())
        #expect(reglages.nonRepris.count == 14)
        for (cle, raison) in reglages.nonRepris {
            #expect(Self.cite(plan, .reglage(cle), .laisseParLAncienneApp(raison)), "\(cle)")
        }
        for cle in ["SUHasLaunchedBefore", "NSWindow Frame graphe", "reglages.onglet"] {
            #expect(Self.cite(plan, .reglage(cle), .laisseParLAncienneApp(.horsContrat)), "\(cle)")
        }
    }

    @Test func unReglageDejaPoseDansMaillageIoTNEstJamaisEcrase() throws {
        // cle de Maillage IoT deja posee -> cle de l'export, citee au resume
        let presents = ["zigbee.sondeNom": "sondeNom", "zigbee.pont.hue": "pont.hue", "zigbee.sondePagesTables": "sondePagesTables",
                        "zigbee.liensMontres": "liensMontres", "notification.zigbee.pertes": "notification.pertes",
                        "vuePieces3D": "vuePieces3D", "AppleLanguages": "AppleLanguages"]
        let plan = try Self.convertir(donnees: Donnees(), presents: Set(presents.keys))
        for (cible, ancienne) in presents {
            #expect(plan.reglages[cible] == nil, "\(cible) ecrase")
            #expect(Self.cite(plan, .reglage(ancienne), .dejaDansMaillageIoT), "\(ancienne)")
        }
        #expect(plan.reglages.count == Self.reglagesAttendus.count - presents.count)
        #expect(plan.reglages["zigbee.sondeIeee"] == .texte("00000000000000E1"), "les autres sont ecrits")
    }

    @Test func laCleCommuneDeNotificationDejaPoseeProtegeLaCleDuProtocole() throws {
        let plan = try Self.convertir(donnees: Donnees(), presents: ["notification.pertes"])
        #expect(plan.reglages["notification.zigbee.pertes"] == nil)
        #expect(Self.cite(plan, .reglage("notification.pertes"), .dejaDansMaillageIoT))
        #expect(plan.reglages["notification.zigbee.routeurDisparu"] == .bool(true))
    }

    @MainActor @Test func lesCleCiblesSontCellesDeLApp() throws {
        #expect(SondeMaillageZigbee.cleSerie == "zigbee.sondeSerieUSB" && SondeMaillageZigbee.cleNom == "zigbee.sondeNom")
        #expect(SondeMaillageZigbee.cleIeee == "zigbee.sondeIeee" && SondeMaillageZigbee.cleNomWifi == "zigbee.sondeNomWifi")
        #expect(SondeMaillageZigbee.clePagesTables == "zigbee.sondePagesTables")
        #expect(CheminSonde.cleReglage == "zigbee.sondeChemin")
        #expect(MemoirePreferences.cle == "zigbee.pont.hue")
        #expect(FenetrePieces.cleLiens == "zigbee.liensMontres" && FenetrePieces.cleVoisins == "zigbee.voisinsALaSelection")
        for cle in [SondeMaillageZigbee.cleSerie, SondeMaillageZigbee.cleNom, SondeMaillageZigbee.cleIeee, SondeMaillageZigbee.cleNomWifi,
                    SondeMaillageZigbee.clePagesTables, CheminSonde.cleReglage, MemoirePreferences.cle, FenetrePieces.cleLiens, FenetrePieces.cleVoisins] {
            #expect(Self.reglagesAttendus[cle] != nil, "\(cle)")
        }
        #expect(Self.reglagesAttendus[SondeMaillageZigbee.cleJournalPages] == nil, "le journal des pages n'est pas repris")
        for c in Notifications.categories(de: .zigbee) {
            #expect(Self.reglagesAttendus[Notifications.cle(c, de: .zigbee)] != nil, "\(c)")
            #expect(FusionReprise.cibleReglage("notification.\(c.rawValue)", de: .maillageZigbee) == Notifications.cle(c, de: .zigbee))
            #expect(FusionReprise.cleCommuneDeNotification("notification.\(c.rawValue)", de: .maillageZigbee) == Notifications.cleCommune(c))
        }
        #expect(FusionReprise.cibleReglage(LangueApp.cle, de: .maillageZigbee) == LangueApp.cle)
    }

    @Test func unReglageDeLExportSansCibleEstCite() throws {
        let (m, r) = try C.verifierDossier(Self.exemple())
        var valeurs = r.valeurs
        valeurs["cleInconnue"] = .bool(true)
        valeurs["sondeJournalPages"] = .listeEntiers([1, 2])
        let plan = try Self.convertir(m, C.Reglages(app: .maillageZigbee, valeurs: valeurs, nonRepris: r.nonRepris))
        #expect(plan.reglages["cleInconnue"] == nil && plan.reglages["zigbee.sondeJournalPages"] == nil)
        #expect(Self.cite(plan, .reglage("cleInconnue"), .sansEquivalent))
        #expect(Self.cite(plan, .reglage("sondeJournalPages"), .sansEquivalent), "meme dans les valeurs d'un export inattendu")
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
        #expect(plan.fichiers.count == 9)
        #expect(plan.fichiers.map(\.chemin) == [
            "Journal/journal-2026-10.jsonl", "Zigbee/appariements-maison.json", "Zigbee/dernier-maillage.json",
            "Zigbee/maillage-2026-10.jsonl", "Zigbee/noms-pont.json", "pieces-noeuds.json", "positions-pieces.json",
            "releve-maison.json", "surnoms.json",
        ])
        #expect(plan.nonPris.filter { if case .fichier = $0.nature { true } else { false } }.count == 2 + 3)
    }

    @Test func lePlanEstTrieEtDeterministe() throws {
        let d = try Donnees()
        let a = try Self.convertir(donnees: d)
        let b = try Self.convertir(donnees: d)
        #expect(a == b)
        #expect(a.fichiers.map(\.chemin) == a.fichiers.map(\.chemin).sorted())
        #expect(a.app == .maillageZigbee)
    }

    @Test func laConversionNEcritNiDansLApp() throws {
        let d = try Donnees()
        try d.ecrire("surnoms.json", #"{"surnoms":{"zigbee:00000000000000C1":"Mon choix"},"version":1}"#)
        try d.ecrire("Journal/journal-2026-10.jsonl", "{\"a\":1}\n")
        try d.ecrire("releve-maison.json", Self.releve(date: "2026-10-10T08:00:00.000Z"))
        try d.ecrire("Zigbee/appariements-maison.json", #"{"ids":{"00000000000000AA":"x"},"version":1}"#)
        let avant = try d.instantane()
        let export = try Self.exemple()
        let avantExport = try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) }
        _ = try Self.convertir(donnees: d)
        #expect(try d.instantane() == avant, "le dossier de Maillage IoT est lu, jamais ecrit")
        #expect(try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) } == avantExport)
    }

    @MainActor @Test func lePlanAppliqueEstRelisibleParLesLecteursDeLApp() throws {
        let plan = try Self.convertir(donnees: Donnees())
        let sortie = try Donnees()
        try Self.appliquer(plan, dans: sortie)
        // Le fichier d'avant n'a pas ete depose : un lecteur de secours le lirait comme Thread.
        #expect(!FileManager.default.fileExists(atPath: sortie.url("pieces-routeurs.json").path))
        #expect(Surnoms.lire(sortie.url("surnoms.json"), protocoleParDefaut: .thread).count == 3)
        #expect(PiecesRouteurs.lire(sortie.url("pieces-noeuds.json")).appareils.count == 2)
        #expect(PlacesGardees.lire(sortie.url("positions-pieces.json")).maisons.count == 2)
        #expect(MemoireAppariements.lire(sortie.url("Zigbee/appariements-maison.json")).ids.count == 2)
        #expect(try NomsZigbee.lire(Data(contentsOf: sortie.url("Zigbee/noms-pont.json"))).accessoires.count > 0)
        #expect(try NomsMaison.lire(Data(contentsOf: sortie.url("releve-maison.json"))).version == 2)
        let historique = HistoriqueFichiersZigbee(dossier: sortie.url("Zigbee"), calendrier: Self.calendrier)
        #expect(try historique.lire(depuis: .distantPast).count == 5)
    }

    @Test func reimporterLeMemeExportNeChangeRien() throws {
        let d = try Donnees()
        let premier = try Self.convertir(donnees: d)
        try Self.appliquer(premier, dans: d)
        let apres = try d.instantane()
        let second = try Self.convertir(donnees: d, presents: Set(premier.reglages.keys))
        #expect(second.fichiers.isEmpty, "\(second.fichiers.map(\.chemin))")
        #expect(second.reglages.isEmpty)
        try Self.appliquer(second, dans: d)
        #expect(try d.instantane() == apres)
    }

    // MARK: Thread puis Zigbee, ou Zigbee puis Thread

    @Test func lOrdreDesDeuxImportsNeChangeLesFichiersCommunsQueParLOrdreDesLignes() throws {
        func importer(_ ordre: [C.AppSource]) throws -> ([String: Data], [String: C.Valeur]) {
            let d = try Donnees()
            var reglages: [String: C.Valeur] = [:]
            for app in ordre {
                let presents = Set(reglages.keys)
                let plan: PlanReprise
                switch app {
                case .maillageThread:
                    plan = try ConversionThread.convertir(dossier: ExportsExempleTests.dossier(.maillageThread), etat: Self.etat(d, presents: presents),
                                                         maintenant: Self.maintenant, calendrier: Self.calendrier)
                case .maillageZigbee:
                    plan = try Self.convertir(donnees: d, presents: presents)
                }
                try Self.appliquer(plan, dans: d)
                reglages.merge(plan.reglages) { a, _ in a }
            }
            return (try d.instantane(), reglages)
        }
        let (tz, rtz) = try importer([.maillageThread, .maillageZigbee])
        let (zt, rzt) = try importer([.maillageZigbee, .maillageThread])
        #expect(Set(tz.keys) == Set(zt.keys), "memes fichiers")
        // Les fichiers a cles prefixees ou ecrits en entier sont les memes a l'octet pres, quel que soit l'ordre.
        for chemin in ["surnoms.json", "pieces-noeuds.json", "releve-maison.json"] {
            #expect(tz[chemin] == zt[chemin], "\(chemin)")
        }
        // Les deux protocoles sont dans le meme fichier, sans collision.
        let surnomsBruts = try #require(tz["surnoms.json"])
        let surnoms = try #require(Self.objet(surnomsBruts)["surnoms"] as? [String: String])
        #expect(surnoms.count == 5 + 3)
        #expect(surnoms.keys.filter { $0.hasPrefix("thread:") }.count == 5 && surnoms.keys.filter { $0.hasPrefix("zigbee:") }.count == 3)
        // Le journal : les memes lignes, dans l'ordre des imports.
        let jtz = Self.lignes(try #require(tz["Journal/journal-2026-10.jsonl"]))
        let jzt = Self.lignes(try #require(zt["Journal/journal-2026-10.jsonl"]))
        #expect(jtz.count == 7 + 10 && Set(jtz) == Set(jzt), "memes lignes, sans doublon ni perte")
        #expect(try jtz.filter { try Self.evenement($0).protocole == .zigbee }.count == 10)
        #expect(try jtz.filter { try (Self.evenement($0).protocole ?? .thread) == .thread }.count == 7)
        // Les positions : les memes maisons, etages et pieces (l'ordre des etages peut suivre l'ordre des imports).
        func places(_ d: Data?) throws -> PlacesGardees {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("positions-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: u) }
            try #require(d).write(to: u)
            return PlacesGardees.lire(u)
        }
        let ptz = try places(tz["positions-pieces.json"]), pzt = try places(zt["positions-pieces.json"])
        #expect(ptz.maisons.keys == pzt.maisons.keys)
        for (domicile, m) in ptz.maisons {
            let autre = try #require(pzt.maisons[domicile])
            #expect(m.etages == autre.etages && m.aCote == autre.aCote && Set(m.ordreEtages) == Set(autre.ordreEtages), "\(domicile)")
        }
        // Les reglages : les cles de chaque protocole sont celles de son export, quel que soit l'ordre.
        #expect(rtz.filter { $0.key.hasPrefix("thread.") || $0.key.hasPrefix("zigbee.") || $0.key.hasPrefix("notification.") }
                == rzt.filter { $0.key.hasPrefix("thread.") || $0.key.hasPrefix("zigbee.") || $0.key.hasPrefix("notification.") })
        #expect(rtz["zigbee.sondeNom"] == .texte("SONDE-Z1") && rtz["thread.sondeNom"] == .texte("SONDE-T1"))
        // Les fichiers de chaque module sont a leur place.
        for chemin in ["Thread/associations.json", "Thread/dernier-maillage.json", "Zigbee/dernier-maillage.json", "Zigbee/noms-pont.json"] {
            #expect(tz[chemin] != nil && tz[chemin] == zt[chemin], "\(chemin)")
        }
    }
}
