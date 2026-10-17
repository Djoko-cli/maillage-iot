import Foundation
#if canImport(MaillageCoeur)
import MaillageCoeur
#endif

/// Generateur des exports d'exemple PROVISOIRES de Maillage Thread 1.3.0 et de Maillage Zigbee 1.1.1 (phase 4, tache 2).
/// Il ecrit, pour chaque app, un dossier d'export au contrat v1 (`ContratExport`) : les fichiers de
/// `Application Support/<app>/` aux formats que les anciennes apps ecrivent (memes cles, memes encodeurs : cles triees,
/// dates ISO 8601 UTC avec millisecondes), des valeurs INVENTEES seulement, `reglages.json` et `manifeste.json`.
/// Le manifeste, les empreintes et les reglages sont calcules par les fonctions du contrat, jamais a la main.
///
/// Deux usages, un seul code :
/// - `outils/generer-exports-exemple.sh` (compile ce fichier avec le contrat et `main.swift`) ecrit les dossiers sous
///   `MaillageIoTTests/Ressources/exports/` ;
/// - `ExportsExempleTests` (cible MaillageIoTTests) ecrit les memes dossiers dans un dossier temporaire et les compare
///   octet par octet aux dossiers commites : un ecart d'un seul octet fait echouer le test.
/// Ces exports restent (tache 9) ; ceux que produisent les anciennes apps s'ajoutent a cote (outils/recopier-exports-anciennes-apps.sh).
enum GenerateurExportsExemple {
    typealias C = ContratExport

    /// Date de reference FIXE des essais (2026-10-17 12:00:00 UTC) : celle du manifeste, et le "maintenant" de la coupe a
    /// 90 jours. Un fichier mensuel dont le mois est fini depuis plus de 90 jours a cette date est ecarte a l'import.
    static let dateReference = Date(timeIntervalSince1970: 1_792_238_400)

    enum Erreur: Error, CustomStringConvertible {
        case classement(String)
        case reglages(String)
        case verification(String)

        var description: String {
            switch self {
            case .classement(let s): "classement des fichiers : " + s
            case .reglages(let s): "reglages : " + s
            case .verification(let s): "verification : " + s
            }
        }
    }

    /// Nom du dossier d'export d'une app.
    static func nomDossier(_ app: C.AppSource) -> String {
        switch app {
        case .maillageThread: "thread-1.3.0"
        case .maillageZigbee: "zigbee-1.1.1"
        }
    }

    static func versionApp(_ app: C.AppSource) -> String {
        switch app {
        case .maillageThread: "1.3.0"
        case .maillageZigbee: "1.1.1"
        }
    }

    /// Identifiant (invente) du manifeste de chaque export : fixe, pour que le dossier soit reproductible.
    static func identifiant(_ app: C.AppSource) -> UUID {
        switch app {
        case .maillageThread: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        case .maillageZigbee: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
        }
    }

    /// Ecrit les deux exports sous `racine` (`thread-1.3.0`, `zigbee-1.1.1`) : un dossier deja la est efface d'abord ;
    /// rien d'autre n'est touche.
    static func ecrireTout(dans racine: URL) throws {
        for app in C.AppSource.allCases {
            let dossier = racine.appendingPathComponent(nomDossier(app), isDirectory: true)
            if FileManager.default.fileExists(atPath: dossier.path) { try FileManager.default.removeItem(at: dossier) }
            try ecrire(app, dans: dossier)
        }
    }

    /// Ecrit l'export de `app` dans `dossier` (cree), puis le relit avec `verifierDossier` : un export que le contrat
    /// refuserait n'est pas rendu.
    static func ecrire(_ app: C.AppSource, dans dossier: URL) throws {
        let gestionnaire = FileManager.default
        try gestionnaire.createDirectory(at: dossier, withIntermediateDirectories: true)

        // 1. Les fichiers de l'app, a leur chemin relatif.
        let fichiers = try contenu(app)
        for (chemin, donnees) in fichiers {
            let url = try C.resoudre(chemin, dans: dossier)
            try gestionnaire.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try donnees.write(to: url)
        }

        // 2. Le classement du contrat : tout ce qui est copie est connu, le reste est cite (non repris).
        let vus = fichiers.map(\.0) + nonCopies(app)
        let (aCopier, nonRepris) = try C.classerFichiers(vus: vus, de: app)
        guard aCopier == fichiers.map(\.0).sorted() else {
            throw Erreur.classement("les fichiers ecrits ne sont pas ceux que le contrat copie")
        }

        // 3. Les reglages : le domaine simule passe par la lecture du contrat, comme dans l'ancienne app.
        let reglages = C.reglages(depuis: domaineReglages(app), app: app)
        guard reglages.valeurs.count == C.reglagesConnus(de: app).count else {
            throw Erreur.reglages("un reglage de l'inventaire manque ou n'a pas le bon type")
        }
        let attendus = reglages.nonRepris.allSatisfy {
            $0.value == .horsContrat || ($0.key == "sondeJournalPages" && $0.value == .transitoire)
        }
        guard attendus, !reglages.nonRepris.isEmpty else {
            throw Erreur.reglages("les reglages non repris attendus (Sparkle, fenetres) ne sont pas cites")
        }
        try C.ecrire(reglages).write(to: dossier.appendingPathComponent(C.nomReglages))

        // 4. Le manifeste : chaque fichier decrit sur sa COPIE (taille et SHA-256), reglages.json compris.
        let decrits = try (aCopier + [C.nomReglages]).map { try C.Fichier.decrire(chemin: $0, dans: dossier) }
        let manifeste = C.Manifeste(identifiant: identifiant(app), app: app, versionApp: versionApp(app),
                                    date: dateReference, fichiers: decrits, fichiersNonRepris: nonRepris)
        try C.ecrire(manifeste).write(to: dossier.appendingPathComponent(C.nomManifeste))

        // 5. Le contrat relit le dossier.
        do { _ = try C.verifierDossier(dossier) } catch { throw Erreur.verification("\(error)") }
    }

    // MARK: Fichiers vus mais non copies

    /// Ce que l'ancienne app avait en plus dans son dossier : `.DS_Store` et fichiers mis de cote (exclus), un fichier que
    /// le contrat ne connait pas (hors contrat). Ils n'existent pas dans le dossier d'export : le manifeste les cite.
    static func nonCopies(_ app: C.AppSource) -> [String] {
        switch app {
        case .maillageThread:
            [".DS_Store", "Journal/.DS_Store", "surnoms.illisible-20261001-101500.json", "cache-temporaire.json"]
        case .maillageZigbee:
            [".DS_Store", "noms-pont.illisible-20261003-093000.json", "sonde-diagnostic.json"]
        }
    }

    // MARK: Encodages (ceux des anciennes apps)

    /// `FichiersGardes.ecrire` : cles triees, joli (surnoms, associations, identites, pieces, places, appariements).
    private static func joli(_ objet: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: objet, options: [.prettyPrinted, .sortedKeys])
    }

    /// `CodageJSON.encodeur(lisible: true)` : le releve de Maison, le releve du pont.
    private static func jolieSansEchappement(_ objet: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: objet, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// `CodageJSON.encodeur()` : une ligne, cles triees (derniers maillages, adresses, lignes des fichiers mensuels).
    private static func compact(_ objet: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Un fichier JSON Lines : une ligne par objet, chacune terminee par un saut de ligne (`FichiersMensuels.ajouter`).
    private static func lignes(_ objets: [Any]) throws -> Data {
        var d = Data()
        for o in objets {
            d.append(try compact(o))
            d.append(0x0A)
        }
        return d
    }

    private static let nul = NSNull()

    // MARK: Contenu des fichiers

    private static func contenu(_ app: C.AppSource) throws -> [(String, Data)] {
        switch app {
        case .maillageThread: try contenuThread()
        case .maillageZigbee: try contenuZigbee()
        }
    }

    /// Un accessoire de Maison tel que le demon Passeur Noms le releve (identique dans les deux apps).
    private static func accessoireReleve(nom: String, piece: String?, categorie: String, noeud: String?, id: String,
                                         pont: Bool = false, batterie: [String: Any]? = nil) -> [String: Any] {
        var a: [String: Any] = ["nom": nom, "categorie": categorie, "fabricant": "Fabricant 1", "firmware": "1.0.0",
                                "modele": "Modele \(categorie)", "id": id, "pont": pont]
        if let piece { a["piece"] = piece }
        if let noeud { a["noeudMatter"] = noeud }
        if let batterie { a["batterie"] = batterie }
        return a
    }

    private static var zones: [[String: Any]] {
        [["nom": "Étage 1", "pieces": ["Pièce 1", "Pièce 2"]], ["nom": "Étage 2", "pieces": ["Pièce 3"]]]
    }

    /// Le releve de Maison (v2, `statut` ok) : `noms.json` de Thread, `releve-maison.json` de Zigbee.
    private static func releveMaison(_ accessoires: [[String: Any]], date: String) -> [String: Any] {
        ["version": 2, "date": date, "statut": "ok", "domicile": "Maison 1", "accessoires": accessoires, "zones": zones]
    }

    private static var batterieFaible: [String: Any] { ["alerte": false, "charge": "horsCharge", "niveau": 18] }

    /// `positions-pieces.json` (v1) : une maison avec pieces et zone a cote, une maison sans pieces (routeur).
    private static func positions(domicileSansPieces: String, cleRouteur: String) -> [String: Any] {
        func place(_ x: Double, _ z: Double) -> [String: Any] { ["x": x, "z": z] }
        return [
            "version": 1,
            "maisons": [
                "Maison 1": [
                    "ordreEtages": ["zone:Étage 1", "zone:Étage 2", "zone:Jardin"],
                    "etages": [
                        "zone:Étage 1": ["piece:Pièce 1": place(1.5, -2), "piece:Pièce 2": place(-3.25, 0.5)],
                        "zone:Étage 2": ["piece:Pièce 3": place(0, 4)],
                    ],
                    "aCote": ["zone:Jardin": ["etage": "zone:Étage 1", "dehors": true]],
                ] as [String: Any],
                domicileSansPieces: [
                    "ordreEtages": ["zone:Zone 1"],
                    "etages": ["zone:Zone 1": [cleRouteur: place(2, 2)]],
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    // Thread --------------------------------------------------------------------------------------------------------

    private static let partitionThread = "0000A001"

    /// Un releve de l'historique de Thread (`maillage-AAAA-MM.jsonl`). `ancien` : le format d'avant la sonde tout-en-un
    /// (liens et enfants sans source ni taux).
    private static func releveThread(_ date: String, n: Int, ancien: Bool) -> [String: Any] {
        let q = [3, 3, 2, 3, 1][n % 5]
        var liens: [[Any]] = ancien ? [[0, 1, q, 3], [0, 2, 2, nul]] : [[0, 1, q, 3, "d", "e"], [0, 2, 2, nul, "d", nul]]
        liens.append(ancien ? [1, 2, 1, 2] : [1, 2, 1, 2, "e", "d"])
        let enfants: [[Any]] = ancien
            ? [["0000000000000021", 1, 3], ["0000000000000022", 2, nul]]
            : [["0000000000000021", 1, 3, "t"], ["0000000000000022", 2, nul, "r", 0.0125], ["0000000000000099", 1, 2, "s"]]
        return ["date": date, "partition": partitionThread,
                "routeurs": [[0, "0000000000000011"], [1, "0000000000000012"], [2, nul]],
                "liens": liens, "enfants": enfants, "signaux": [[1, -60 - n], [2, -72]], "parentSonde": 1]
    }

    /// Un evenement du journal (`Evenement`, aucune cle `protocole`, comme Thread 1.3.0 et Zigbee 1.1.1 les ecrivent).
    private static func evenement(_ date: String, _ type: String, _ gravite: String, reseau: String? = nil,
                                  sujet: (id: String, nom: String)? = nil, avant: String? = nil, apres: String? = nil,
                                  periode: (debut: String, duree: Double)? = nil, constate: Bool = false,
                                  details: [String: String] = [:]) -> [String: Any] {
        var e: [String: Any] = ["date": date, "type": type, "gravite": gravite, "constate": constate, "details": details]
        if let reseau { e["reseau"] = reseau }
        if let sujet { e["sujet"] = ["id": sujet.id, "nom": sujet.nom] }
        if let avant { e["avant"] = avant }
        if let apres { e["apres"] = apres }
        if let periode { e["periode"] = ["start": periode.debut, "duration": periode.duree] }
        return e
    }

    private static func contenuThread() throws -> [(String, Data)] {
        let xp = "0000000000000E01"
        let surnoms = ["0000000000000001": "Prise 1", "0000000000000002": "Capteur 1", "Routeur 1": "Routeur du haut",
                       "instance:Routeur 2": "Routeur du bas", "rloc:0800": "Routeur 3"]
        let associations = ["0000000000000001": "00000000000000A1", "0000000000000002": "00000000000000A2"]
        let identites: [String: Any] = ["partition": partitionThread,
                                        "routeurs": ["0000": "0000000000000011", "0400": "0000000000000012",
                                                     "0800": "0000000000000013"]]
        let adresse: (String, String) -> [String: Any] = { a, quand in
            ["adresse": a, "partition": partitionThread, "annonce": quand]
        }
        let adresses: [String: Any] = ["appareils": [
            "0000000000000001": adresse("fd00::1", "2026-10-14T08:05:00.000Z"),
            "0000000000000002": adresse("fd00::2", "2026-10-14T08:05:00.000Z"),
        ]]
        let maillage: [String: Any] = [
            "recu": "2026-10-14T08:07:00.000Z",
            "maillage": [
                "date": "2026-10-14T08:06:30.000Z", "partition": partitionThread, "annoncesLues": true,
                "routeurs": [
                    ["id": 0, "extMac": "0000000000000011", "bordure": true, "bbrPrincipal": true, "chef": true,
                     "muet": false, "version": 4, "pile": "ot-1.4.0", "entendu": "2026-10-14T08:06:00.000Z"],
                    ["id": 1, "extMac": "0000000000000012", "bordure": false, "bbrPrincipal": false, "chef": false,
                     "muet": false, "version": 4, "pile": "ot-1.4.0"],
                    ["id": 2, "bordure": true, "bbrPrincipal": false, "chef": false, "muet": true],
                ],
                "liens": [
                    ["a": 0, "b": 1, "qualiteAB": 3, "qualiteBA": 3, "sourceAB": "diag", "sourceBA": "ecoute",
                     "dateAB": "2026-10-14T08:06:30.000Z", "dateBA": "2026-10-14T08:06:00.000Z"],
                    ["a": 0, "b": 2, "qualiteAB": 2, "qualiteBA": 2, "sourceAB": "diag", "sourceBA": "diag",
                     "dateAB": "2026-10-14T08:06:30.000Z", "dateBA": "2026-10-14T08:06:30.000Z"],
                ],
                "enfants": [
                    ["rloc16": 1025, "extMac": "0000000000000021", "qualite": 3, "delai": 240, "endormi": true,
                     "adresses": ["fd00::21"], "source": "tableEnfants"],
                    ["rloc16": 2049, "extMac": "0000000000000022", "adresses": [String](), "source": "resolution",
                     "resolu": "2026-10-14T08:00:00.000Z", "echecs": 0.0125],
                    ["rloc16": 1026, "extMac": "0000000000000099", "qualite": 2, "adresses": [String](), "source": "sonde"],
                ],
                "signaux": [["routeur": 1, "rssi": -61]],
            ] as [String: Any],
        ]
        let noms = releveMaison([
            accessoireReleve(nom: "Prise 1", piece: "Pièce 1", categorie: "Prise", noeud: "00000000000000A1",
                             id: "00000000-0000-4000-8000-0000000000A1"),
            accessoireReleve(nom: "Capteur 1", piece: "Pièce 2", categorie: "Capteur", noeud: "00000000000000A2",
                             id: "00000000-0000-4000-8000-0000000000A2", batterie: batterieFaible),
            accessoireReleve(nom: "Routeur 1", piece: "Pièce 3", categorie: "Enceinte", noeud: nil,
                             id: "00000000-0000-4000-8000-0000000000A3"),
        ], date: "2026-10-14T08:00:00.000Z")
        let pieces: [String: Any] = [
            "version": 1,
            "maisons": ["Maison 1": ["Routeur 1": "Pièce 3", "Routeur 2": "Pièce 1"]],
            "appareils": ["Maison 1": ["0000000000000011": "Pièce 2", "0000000000000012": "Pièce 1"]],
        ]
        let journalOctobre: [Any] = [
            evenement("2026-10-02T06:00:00.000Z", "surveillanceDemarree", "info", constate: true, details: ["routeurs": "3"]),
            evenement("2026-10-02T06:00:01.000Z", "routeurApparu", "info", reseau: xp,
                      sujet: ("Routeur 1", "Routeur du haut"), constate: true),
            evenement("2026-10-05T09:30:00.000Z", "veille", "info",
                      periode: ("2026-10-05T09:25:00.000Z", 300)),
            evenement("2026-10-08T14:10:00.000Z", "appareilDisparu", "attention", reseau: xp,
                      sujet: ("0000000000000001", "Prise 1"), avant: "présent", apres: "absent"),
            evenement("2026-10-08T14:40:00.000Z", "appareilRevenu", "info", reseau: xp,
                      sujet: ("0000000000000001", "Prise 1")),
            evenement("2026-10-11T18:20:00.000Z", "parentChange", "info",
                      sujet: ("0000000000000021", "Capteur 1"), avant: "Routeur 1", apres: "Routeur 2"),
            evenement("2026-10-14T08:00:00.000Z", "reseauScinde", "alerte", reseau: xp,
                      details: ["partitions": "2"]),
        ]
        let journalAvril: [Any] = [
            evenement("2026-04-10T10:00:00.000Z", "surveillanceDemarree", "info", constate: true),
            evenement("2026-04-10T10:05:00.000Z", "routeurDisparu", "alerte", reseau: xp,
                      sujet: ("Routeur 2", "Routeur du bas")),
        ]
        var histo: [(String, Data)] = []
        let mois: [(String, [String], Bool)] = [
            ("2026-04", ["2026-04-12T08:00:00.000Z", "2026-04-12T14:00:00.000Z", "2026-04-13T08:00:00.000Z",
                         "2026-04-13T14:00:00.000Z"], true),
            ("2026-07", ["2026-07-20T09:00:00.000Z", "2026-07-20T15:00:00.000Z", "2026-07-21T09:00:00.000Z"], false),
            ("2026-09", ["2026-09-15T08:00:00.000Z", "2026-09-15T14:00:00.000Z", "2026-09-16T08:00:00.000Z",
                         "2026-09-16T14:00:00.000Z"], false),
            ("2026-10", ["2026-10-13T08:00:00.000Z", "2026-10-13T14:00:00.000Z", "2026-10-14T08:00:00.000Z",
                         "2026-10-14T08:05:00.000Z", "2026-10-14T08:06:30.000Z"], false),
        ]
        for (m, dates, ancien) in mois {
            histo.append(("maillage-\(m).jsonl",
                          try lignes(dates.enumerated().map { releveThread($1, n: $0, ancien: ancien) })))
        }
        return [
            ("surnoms.json", try joli(surnoms)),
            ("associations.json", try joli(associations)),
            ("identites-routeurs.json", try joli(identites)),
            ("dernier-maillage.json", try compact(maillage)),
            ("dernieres-adresses.json", try compact(adresses)),
            ("noms.json", try jolieSansEchappement(noms)),
            ("pieces-routeurs.json", try joli(pieces)),
            ("positions-pieces.json", try joli(positions(domicileSansPieces: "Maison 2", cleRouteur: "routeur:0000000000000011"))),
            ("Journal/journal-2026-04.jsonl", try lignes(journalAvril)),
            ("Journal/journal-2026-10.jsonl", try lignes(journalOctobre)),
        ] + histo
    }

    // Zigbee --------------------------------------------------------------------------------------------------------

    private static let pontZigbee = "0000000000000B01"
    private static let coordinateur = "00000000000000C0"
    private static let routeur1 = "00000000000000C1"
    private static let routeur2 = "00000000000000C2"
    private static let final1 = "00000000000000F1"
    private static let final2 = "00000000000000F2"
    private static let sondeZigbee = "00000000000000E1"

    /// Un releve de l'historique de Zigbee (`maillage-AAAA-MM.jsonl`). Sans `chemins` : la ligne d'un releve d'avant les
    /// chemins (la cle manque).
    private static func releveZigbee(_ date: String, n: Int, chemins: Bool) -> [String: Any] {
        var r: [String: Any] = [
            "date": date,
            "noeuds": [[coordinateur, "c"], [routeur1, "r"], [routeur2, "r", true], [final1, "f"], [sondeZigbee, "f"]],
            "liens": [[coordinateur, routeur1, 200 - n, 190], [routeur1, routeur2, 120, nul]],
            "parents": [[final1, routeur1, 150 + n], [final2, routeur2, nul], [sondeZigbee, routeur1, 170]],
            "signaux": [[routeur1, 180 - n]],
            "sonde": sondeZigbee,
        ]
        if chemins { r["chemins"] = [[routeur1, coordinateur], [routeur2, routeur1, true]] }
        return r
    }

    private static func contenuZigbee() throws -> [(String, Data)] {
        let surnoms = [routeur1: "Routeur 1", final1: "Capteur 1", final2: "Ampoule 1"]
        func noeud(_ ieee: String, _ court: Int, _ type: String, muet: Bool = false, ecoute: Bool? = nil) -> [String: Any] {
            var n: [String: Any] = ["ieee": ieee, "court": court, "type": type, "muet": muet, "tableNonLue": muet]
            if let ecoute { n["ecoute"] = ecoute }
            return n
        }
        let quand = "2026-10-14T09:40:00.000Z"
        let maillage: [String: Any] = [
            "recu": "2026-10-14T09:43:00.000Z", "incomplet": false,
            "maillage": [
                "date": "2026-10-14T09:41:00.000Z", "dateTables": quand, "complet": true, "sonde": sondeZigbee,
                "noeuds": [
                    noeud(coordinateur, 0, "coordinateur", ecoute: true), noeud(routeur1, 4097, "routeur", ecoute: true),
                    noeud(routeur2, 4098, "routeur", muet: true), noeud(final1, 4099, "final", ecoute: false),
                    noeud(sondeZigbee, 4100, "final", ecoute: true),
                ],
                "liens": [
                    ["a": coordinateur, "b": routeur1, "lqiA": 200, "lqiB": 190, "dateA": quand, "dateB": quand],
                    ["a": routeur1, "b": routeur2, "lqiA": 120, "dateA": quand],
                ],
                "parents": [
                    ["enfant": final1, "parent": routeur1, "lqi": 150, "date": quand],
                    ["enfant": sondeZigbee, "parent": routeur1, "lqi": 170, "date": quand],
                    ["enfant": final2, "parent": routeur2, "date": "2026-10-13T20:00:00.000Z", "dAvant": true],
                ],
                "routesPont": [
                    ["destination": 4097, "prochain": 4097, "etat": "active", "plusieursVersUn": false],
                    ["destination": 4098, "prochain": 4097, "etat": "inactive", "plusieursVersUn": false],
                ],
                "signaux": [["ieee": routeur1, "lqi": 180]],
                "chemins": [
                    ["routeur": routeur1, "prochain": coordinateur, "plusieursVersUn": true, "actif": true, "suppose": false,
                     "date": quand],
                    ["routeur": routeur2, "prochain": routeur1, "plusieursVersUn": false, "actif": false, "suppose": true],
                ],
            ] as [String: Any],
        ]
        func accessoirePont(_ nom: String, piece: String?, ieee: String, categorie: String, origine: String, idHue: String,
                            batterie: [String: Any]? = nil) -> [String: Any] {
            var a: [String: Any] = ["nom": nom, "categorie": categorie, "fabricant": "Fabricant 1", "firmware": "1.0.0",
                                    "modele": "Modele \(categorie)", "ieee": ieee, "connexion": "connected",
                                    "idModele": "MOD-\(categorie)", "origine": origine, "idHue": idHue]
            if let piece { a["piece"] = piece }
            if let batterie { a["batterie"] = batterie }
            return a
        }
        let nomsPont: [String: Any] = [
            "version": 1, "date": "2026-10-14T09:00:00.000Z", "domicile": pontZigbee, "zones": zones,
            "reseau": ["canal": 15, "epid": "0000000000000E02"],
            "accessoires": [
                accessoirePont("Routeur 1", piece: "Pièce 1", ieee: routeur1, categorie: "Prise", origine: "maison",
                               idHue: "00000000-0000-4000-8000-0000000000D1"),
                accessoirePont("Capteur 1", piece: "Pièce 2", ieee: final1, categorie: "Capteur", origine: "pont",
                               idHue: "00000000-0000-4000-8000-0000000000D2", batterie: batterieFaible),
                accessoirePont("Ampoule 1", piece: nil, ieee: final2, categorie: "Ampoule", origine: "pont",
                               idHue: "00000000-0000-4000-8000-0000000000D3"),
            ],
        ]
        let appariements: [String: Any] = [
            "version": 1,
            "ids": [routeur1: "00000000-0000-4000-8000-0000000000B1", final1: "00000000-0000-4000-8000-0000000000B2"],
        ]
        let releve = releveMaison([
            accessoireReleve(nom: "Pont 1", piece: "Pièce 3", categorie: "Pont", noeud: "00000000000000B1",
                             id: "00000000-0000-4000-8000-0000000000B0", pont: true),
            accessoireReleve(nom: "Routeur 1", piece: "Pièce 1", categorie: "Prise", noeud: "00000000000000B1",
                             id: "00000000-0000-4000-8000-0000000000B1"),
            accessoireReleve(nom: "Capteur 1", piece: "Pièce 2", categorie: "Capteur", noeud: "00000000000000B1",
                             id: "00000000-0000-4000-8000-0000000000B2", batterie: batterieFaible),
        ], date: "2026-10-14T09:30:00.000Z")
        let pieces: [String: Any] = [
            "version": 1,
            "appareils": ["Maison 1": [routeur1: "Pièce 1", sondeZigbee: "Pièce 3"], pontZigbee: [routeur2: "Pièce 2"]],
        ]
        let journalOctobre: [Any] = [
            evenement("2026-10-08T08:25:00.000Z", "surveillanceDemarree", "info", constate: true,
                      details: ["routeurs": "2", "appareils": "3"]),
            evenement("2026-10-08T08:25:01.000Z", "routeurApparu", "info", sujet: (routeur1, "Routeur 1"), constate: true,
                      details: ["ieee": routeur1]),
            evenement("2026-10-09T11:00:00.000Z", "appareilNouveau", "info", sujet: (final2, "Ampoule 1"),
                      details: ["ieee": final2]),
            evenement("2026-10-10T07:45:00.000Z", "veille", "info", periode: ("2026-10-10T07:40:00.000Z", 300)),
            evenement("2026-10-11T16:20:00.000Z", "cheminChange", "info", sujet: (routeur2, "Routeur 2"),
                      avant: "Routeur 1", apres: "Pont 1", details: ["ieee": routeur2]),
            evenement("2026-10-12T10:00:00.000Z", "parentChange", "info", sujet: (final1, "Capteur 1"),
                      avant: "Routeur 1", apres: "Routeur 2", details: ["ieee": final1]),
            evenement("2026-10-12T10:30:00.000Z", "sansParent", "attention", sujet: (final1, "Capteur 1"),
                      avant: "Routeur 2", details: ["ieee": final1]),
            evenement("2026-10-13T13:00:00.000Z", "appareilDisparu", "attention", sujet: (final2, "Ampoule 1"),
                      details: ["ieee": final2]),
            evenement("2026-10-13T13:20:00.000Z", "appareilRevenu", "info", sujet: (final2, "Ampoule 1"),
                      details: ["ieee": final2]),
            evenement("2026-10-14T09:00:00.000Z", "routeurDisparu", "alerte", sujet: (routeur2, "Routeur 2"),
                      details: ["ieee": routeur2]),
        ]
        let journalAvril: [Any] = [
            evenement("2026-04-10T10:00:00.000Z", "surveillanceDemarree", "info", constate: true),
            evenement("2026-04-10T10:05:00.000Z", "routeurApparu", "info", sujet: (routeur1, "Routeur 1"),
                      details: ["ieee": routeur1]),
        ]
        let avril = ["2026-04-12T08:00:00.000Z", "2026-04-12T14:00:00.000Z", "2026-04-13T08:00:00.000Z"]
        let octobre = ["2026-10-12T08:25:00.000Z", "2026-10-13T08:25:00.000Z", "2026-10-13T14:25:00.000Z",
                       "2026-10-14T08:25:00.000Z", "2026-10-14T09:41:00.000Z"]
        return [
            ("surnoms.json", try joli(surnoms)),
            ("dernier-maillage.json", try compact(maillage)),
            ("appariements-maison.json", try joli(appariements)),
            ("noms-pont.json", try jolieSansEchappement(nomsPont)),
            ("releve-maison.json", try jolieSansEchappement(releve)),
            ("pieces-routeurs.json", try joli(pieces)),
            ("positions-pieces.json", try joli(positions(domicileSansPieces: pontZigbee, cleRouteur: "routeur:" + routeur2))),
            ("maillage-2026-04.jsonl", try lignes(avril.enumerated().map { releveZigbee($1, n: $0, chemins: false) })),
            ("maillage-2026-10.jsonl", try lignes(octobre.enumerated().map { releveZigbee($1, n: $0, chemins: $0 > 0) })),
            ("Journal/journal-2026-04.jsonl", try lignes(journalAvril)),
            ("Journal/journal-2026-10.jsonl", try lignes(journalOctobre)),
        ]
    }

    // MARK: Reglages (UserDefaults simules)

    private static func nombre(_ b: Bool) -> NSNumber { NSNumber(value: b) }
    private static func nombre(_ n: Int) -> NSNumber { NSNumber(value: n) }

    /// Le domaine persistant simule de l'ancienne app : tous les reglages de l'inventaire, avec des valeurs inventees,
    /// plus ce que l'app y laisse sans le reprendre (Sparkle, etats de fenetre, `reglages.onglet`, `dossierNoms`).
    private static func domaineReglages(_ app: C.AppSource) -> [String: Any] {
        var d: [String: Any] = [
            "vuePieces3D": nombre(true), "etagesEnGrille": nombre(false), "legendeRepliee": nombre(true),
            "grapheDejaOuvert": nombre(true), "ouvertureSessionProposee": nombre(true), "AppleLanguages": ["fr"],
            // Non repris : Sparkle, AppKit, etat de l'app.
            "SUHasLaunchedBefore": nombre(true), "SULastCheckTime": Date(timeIntervalSince1970: 1_792_000_000),
            "SUUpdateGroupIdentifier": nombre(1), "SUSkippedVersion": "9.9.9", "SUEnableAutomaticChecks": nombre(true),
            "SUAutomaticallyUpdate": nombre(true),
            "NSWindow Frame graphe": "100 120 900 640 0 0 1440 900 ",
            "NSWindow Frame journal": "140 160 700 500 0 0 1440 900 ",
            "NSWindow Frame SUUpdateAlert2": "200 200 600 400 0 0 1440 900 ",
            "NSWindow Frame com_apple_SwiftUI_Settings_window": "300 300 500 300 0 0 1440 900 ",
            "NSNavPanelExpandedStateForSaveMode": nombre(true), "NSOSPLastRootDirectory": Data([0x01, 0x02, 0x03]),
            "reglages.onglet": "sonde",
        ]
        switch app {
        case .maillageThread:
            d["sondeSerieUSB"] = "SERIE-T1"
            d["sondeNom"] = "SONDE-T1"
            d["sondeHote"] = "sonde-t1.local"
            d["sondeLiaison"] = "reseau"
            d["scissionsNotifiees"] = ["0000000000000E01"]
            d["notification.scission"] = nombre(true)
            d["notification.routeurDisparu"] = nombre(true)
            d["notification.pertes"] = nombre(false)
            d["notification.informations"] = nombre(false)
            d["dossierNoms"] = Data([0x0A, 0x0B, 0x0C, 0x0D])
        case .maillageZigbee:
            d["sondeSerieUSB"] = "SERIE-Z1"
            d["sondeNom"] = "SONDE-Z1"
            d["sondeIeee"] = sondeZigbee
            d["sondeNomWifi"] = "Wifi 1"
            // Comme l'app Zigbee l'ecrit : des Double (instant, pages, instant, pages...), transitoire pour le contrat.
            d["sondeJournalPages"] = [1_760_000_000.5, 12.0, 1_760_000_060.25, 7.0] as [Double]
            d["sondePagesTables"] = nombre(4)
            d["sondeChemin"] = "automatique"
            d["pont.hue"] = Data(#"{"adresse":"192.0.2.10","identifiant":"\#(pontZigbee)","manuel":false,"modele":"BSB002"}"#.utf8)
            d["liensMontres"] = "chemins"
            d["voisinsALaSelection"] = nombre(true)
            d["notification.routeurDisparu"] = nombre(true)
            d["notification.pertes"] = nombre(true)
            d["notification.informations"] = nombre(false)
            d["AppleLanguages"] = ["fr", "en"]
        }
        return d
    }
}
