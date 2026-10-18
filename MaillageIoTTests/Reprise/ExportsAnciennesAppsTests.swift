import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Phase 4, tache 9 : les exports d'exemple que les ANCIENNES APPS ecrivent elles-memes (Maillage Thread 1.4.0, Maillage
/// Zigbee 1.2.0), copies a l'octet de leurs depots (`MaillageIoTTests/Ressources/exports/thread-1.4.0-export` et
/// `zigbee-1.2.0-export`, voir `ORIGINE.md`), passent par toute la chaine de l'import : contrat, validation, conversion,
/// application, reimport. Ils s'ajoutent aux exports provisoires de la tache 2 (`ExportsExempleTests`), qui restent la
/// reference des autres suites : un ecart entre ce que l'ancienne app ecrit et ce que l'import lit se voit ici. Valeurs
/// inventees seulement. La date de reference est celle des exemples (2026-10-17 12:00 UTC).
@Suite("Exports des anciennes apps : de l'ecriture a la lecture")
struct ExportsAnciennesAppsTests {
    typealias C = ContratExport
    typealias G = GenerateurExportsExemple
    typealias D = ConversionThreadTests.Donnees
    typealias App = ContratExport.AppSource
    typealias Nature = ElementNonPris.Nature
    typealias Raison = ElementNonPris.Raison

    // MARK: Outils

    static func nomDossier(_ app: App) -> String {
        switch app {
        case .maillageThread: "thread-1.4.0-export"
        case .maillageZigbee: "zigbee-1.2.0-export"
        }
    }

    static func version(_ app: App) -> String {
        switch app {
        case .maillageThread: "1.4.0"
        case .maillageZigbee: "1.2.0"
        }
    }

    /// Le dossier de l'export ecrit par l'ancienne app.
    static func export(_ app: App) throws -> URL {
        try ExportsExempleTests.racine().appendingPathComponent(nomDossier(app), isDirectory: true)
    }

    static func etat(_ d: D, presents: Set<String> = []) -> EtatActuel { EtatActuel(dossier: d.racine, reglagesPresents: presents) }

    static func convertir(_ app: App, _ dossier: URL? = nil, donnees d: D, presents: Set<String> = []) throws -> PlanReprise {
        let source = try dossier ?? export(app)
        switch app {
        case .maillageThread:
            return try ConversionThread.convertir(dossier: source, etat: etat(d, presents: presents),
                                                  maintenant: G.dateReference, calendrier: ConversionThreadTests.calendrier)
        case .maillageZigbee:
            return try ConversionZigbee.convertir(dossier: source, etat: etat(d, presents: presents),
                                                  maintenant: G.dateReference, calendrier: ConversionThreadTests.calendrier)
        }
    }

    static func appliquer(_ plan: PlanReprise, dans d: D) throws {
        for f in plan.fichiers { try d.ecrire(f.chemin, f.contenu.octets()) }
    }

    /// Les lignes (non vides) d'un fichier de l'export.
    static func lignes(_ app: App, _ chemin: String) throws -> [String] {
        ConversionThreadTests.lignes(try Data(contentsOf: export(app).appendingPathComponent(chemin)))
    }

    /// Les fichiers mensuels de l'export, gardes ou ecartes par la coupe a 90 jours a la date de reference.
    static func mensuels(_ app: App) throws -> (gardes: [String], ecartes: [String]) {
        let (manifeste, _) = try C.verifierDossier(export(app))
        let tous = manifeste.fichiers.compactMap { f in C.mois(de: f.chemin).map { (f.chemin, $0) } }
        return (tous.filter { !ExportsExempleTests.estEcarte($0.1, maintenant: G.dateReference) }.map(\.0),
                tous.filter { ExportsExempleTests.estEcarte($0.1, maintenant: G.dateReference) }.map(\.0))
    }

    static func objet(_ app: App, _ chemin: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: export(app).appendingPathComponent(chemin))) as? [String: Any])
    }

    // MARK: L'export tel que l'ancienne app l'ecrit

    @Test(arguments: App.allCases)
    func leContratAccepteLExportEcritParLAncienneApp(app: App) throws {
        let (manifeste, reglages) = try C.verifierDossier(Self.export(app))
        #expect(manifeste.app == app)
        #expect(reglages.app == app)
        #expect(manifeste.versionApp == Self.version(app))
        #expect(manifeste.fichiers.contains { $0.chemin == C.nomReglages })
        // Un export de test n'a pas l'identifiant d'un autre : les deux jeux d'exemples peuvent s'importer ensemble.
        #expect(manifeste.identifiant != G.identifiant(app))
    }

    @Test(arguments: App.allCases)
    func lesDossiersDesAnciennesAppsNeSontPasLesExportsProvisoires(app: App) throws {
        #expect(try Self.export(app) != ExportsExempleTests.dossier(app))
        #expect(FileManager.default.fileExists(atPath: try ExportsExempleTests.dossier(app).path), "l'export provisoire reste")
        let origine = try String(contentsOf: ExportsExempleTests.racine().appendingPathComponent("ORIGINE.md"), encoding: .utf8)
        #expect(origine.contains(Self.nomDossier(app)), "ORIGINE.md cite le dossier")
        #expect(!origine.contains("/Users/"))
    }

    @Test(arguments: App.allCases)
    func chaqueFichierEcritEstConnuDuContrat(app: App) throws {
        let (manifeste, _) = try C.verifierDossier(Self.export(app))
        for f in manifeste.fichiers where f.chemin != C.nomReglages {
            #expect(C.estConnu(f.chemin, de: app), "\(f.chemin) : l'ancienne app l'ecrit, le contrat ne le connait pas")
        }
    }

    /// Un fichier attendu absent est un ecart de format (hors fichiers mensuels, dont l'export d'exemple n'a que quelques mois).
    @Test(arguments: App.allCases)
    func chaqueFichierDeLInventaireEstEcritParLAncienneApp(app: App) throws {
        let (manifeste, _) = try C.verifierDossier(Self.export(app))
        for connu in C.fichiersConnus(de: app) {
            #expect(manifeste.fichiers.contains { connu.correspond($0.chemin) }, "\(connu.modele) absent de l'export de l'ancienne app")
        }
    }

    /// Chaque reglage de l'inventaire est ecrit avec son type, ou cite avec sa raison : jamais absent sans rien dire.
    @Test(arguments: App.allCases)
    func chaqueReglageDeLInventaireEstEcritOuCite(app: App) throws {
        let (_, reglages) = try C.verifierDossier(Self.export(app))
        for connu in C.reglagesConnus(de: app) {
            let ecrit = reglages.valeurs[connu.cle]
            let cite = reglages.nonRepris[connu.cle]
            #expect(ecrit != nil || cite != nil, "reglage \(connu.cle) ni ecrit ni cite")
            if let ecrit { #expect(ecrit.type == connu.type, "reglage \(connu.cle) d'un autre type") }
        }
        // Ce qu'une ancienne app ecrit en valeurs est connu du contrat, au meme type.
        for (cle, valeur) in reglages.valeurs {
            #expect(C.typeAttendu(cle: cle, de: app) == valeur.type, "valeur \(cle) inconnue ou d'un autre type")
        }
    }

    @Test func lesFormatsPropresACadaAppSontCeuxQueLImportLit() throws {
        // Thread : surnoms plats avec trois formes de cle, sans version ; pieces avec maisons et appareils.
        let surnoms = try Self.objet(.maillageThread, "surnoms.json")
        #expect(surnoms["version"] == nil)
        #expect(!surnoms.keys.contains { $0.hasPrefix("thread:") || $0.hasPrefix("zigbee:") })
        let piecesThread = try Self.objet(.maillageThread, "pieces-routeurs.json")
        #expect(piecesThread["maisons"] != nil && piecesThread["appareils"] != nil)
        // Zigbee : pieces d'appareils seulement ; le domicile est tantot un nom de maison, tantot l'identifiant du pont.
        let piecesZigbee = try Self.objet(.maillageZigbee, "pieces-routeurs.json")
        #expect(piecesZigbee["maisons"] == nil && piecesZigbee["appareils"] != nil)
        // Releves de Maison (v2) et cache du pont (v1).
        #expect(try Self.objet(.maillageThread, "noms.json")["version"] as? Int == 2)
        #expect(try Self.objet(.maillageZigbee, "releve-maison.json")["version"] as? Int == 2)
        #expect(try Self.objet(.maillageZigbee, "noms-pont.json")["version"] as? Int == 1)
        // Le journal de l'ancienne app : aucune ligne de Zigbee 1.2.0 ni de Thread 1.4.0 n'a `protocole` (l'import l'ajoute a Zigbee).
        for app in App.allCases {
            let (manifeste, _) = try C.verifierDossier(Self.export(app))
            for f in manifeste.fichiers where f.chemin.hasPrefix("Journal/") {
                for l in try Self.lignes(app, f.chemin) {
                    let o = try #require(JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any])
                    #expect(o["protocole"] == nil, "ligne avec protocole dans \(f.chemin)")
                }
            }
        }
    }

    @Test(arguments: App.allCases)
    func aucuneValeurReelleNiChemin(app: App) throws {
        let dossier = try Self.export(app)
        for chemin in try ExportsExempleTests.fichiers(de: dossier) {
            let texte = try String(contentsOf: dossier.appendingPathComponent(chemin), encoding: .utf8)
            #expect(!texte.contains("/Users/"), "\(chemin) contient un chemin de dossier personnel")
            #expect(!texte.contains("@"), "\(chemin) contient un arobase (adresse electronique ?)")
        }
    }

    // MARK: Validation (tache 3)

    @Test(arguments: App.allCases)
    func lAssistantAccepteLExportEcritParLAncienneApp(app: App) throws {
        guard case .acceptee(let resume) = ValidationExport.valider(dossier: try Self.export(app), imports: .vide) else {
            Issue.record("export refuse par la validation")
            return
        }
        #expect(resume.app == app)
        #expect(resume.versionApp == Self.version(app))
        let (manifeste, _) = try C.verifierDossier(Self.export(app))
        #expect(resume.tailleTotale == manifeste.fichiers.reduce(0) { $0 + $1.taille }, "reglages.json compris")
    }

    @Test(arguments: App.allCases)
    func unOctetChangeDansLExportDeLAncienneAppEstRefuse(app: App) throws {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("anciennes-apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }
        let copie = racine.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.export(app), to: copie)
        let surnoms = copie.appendingPathComponent("surnoms.json")
        try (Data(contentsOf: surnoms) + Data(" ".utf8)).write(to: surnoms)
        guard case .refuse = ValidationExport.valider(dossier: copie, imports: .vide) else {
            Issue.record("un fichier altere a ete accepte")
            return
        }
    }

    // MARK: Conversion (taches 4 et 5)

    /// Rien ne se perd en silence : chaque fichier de l'export est place par une regle ou cite ; chaque reglage est ecrit ou cite.
    @Test(arguments: App.allCases)
    func rienNeSePerdEnSilence(app: App) throws {
        let (manifeste, reglages) = try C.verifierDossier(Self.export(app))
        let plan = try Self.convertir(app, donnees: D())
        let places = Set(plan.fichiers.flatMap(\.sources))
        for f in manifeste.fichiers where f.chemin != C.nomReglages {
            let cite = plan.nonPris.contains { $0.nature == .fichier(f.chemin) }
            #expect(places.contains(f.chemin) || cite, "\(f.chemin) ni place ni cite")
        }
        for cle in reglages.valeurs.keys {
            let cible = FusionReprise.cibleReglage(cle, de: app)
            let ecrit = cible.map { plan.reglages[$0] != nil } ?? false
            let cite = plan.nonPris.contains { $0.nature == .reglage(cle) }
            #expect(ecrit || cite, "reglage \(cle) ni ecrit ni cite")
        }
        for (cle, raison) in reglages.nonRepris {
            #expect(plan.nonPris.contains(ElementNonPris(nature: .reglage(cle), raison: .laisseParLAncienneApp(raison))),
                    "reglage \(cle) laisse par l'ancienne app mais non cite")
        }
        for f in manifeste.fichiersNonRepris {
            #expect(plan.nonPris.contains(ElementNonPris(nature: .fichier(f.chemin), raison: .laisseParLAncienneApp(f.raison))),
                    "fichier \(f.chemin) vu par l'ancienne app mais non cite")
        }
        // Sur un dossier vide, chaque fichier mensuel de plus de 90 jours est cite, jamais place.
        for ecarte in try Self.mensuels(app).ecartes {
            #expect(plan.nonPris.contains(ElementNonPris(nature: .fichier(ecarte), raison: .plusDe90Jours)), "\(ecarte) ecarte sans citation")
            #expect(!places.contains(ecarte))
        }
    }

    @Test(arguments: App.allCases)
    func lesReglagesPrennentLaCleDeLeurProtocole(app: App) throws {
        let (_, reglages) = try C.verifierDossier(Self.export(app))
        let plan = try Self.convertir(app, donnees: D())
        let prefixe = app == .maillageThread ? "thread" : "zigbee"
        for (cle, valeur) in reglages.valeurs {
            guard let cible = FusionReprise.cibleReglage(cle, de: app) else { continue }
            #expect(plan.reglages[cible] == valeur, "\(cle) -> \(cible) : valeur changee ou absente")
            if cle.hasPrefix("sonde") || cle.hasPrefix("notification.") {
                #expect(cible.hasPrefix("\(prefixe).") || cible.hasPrefix("notification.\(prefixe)."), "\(cible) sans protocole")
            }
        }
        // La liaison de la sonde de Thread est recopiee telle quelle, jamais remise au defaut.
        if app == .maillageThread { #expect(plan.reglages["thread.sondeLiaison"] == .texte("reseau")) }
        // Aucune cle de l'autre protocole.
        let autre = app == .maillageThread ? "zigbee." : "thread."
        #expect(!plan.reglages.keys.contains { $0.hasPrefix(autre) || $0.hasPrefix("notification.\(autre)") })
    }

    @Test(arguments: App.allCases)
    func chaqueFichierPrendLeProtocoleDeSonApp(app: App) throws {
        let plan = try Self.convertir(app, donnees: D())
        let protocole: Protocole = app == .maillageThread ? .thread : .zigbee
        let autre = app == .maillageThread ? "zigbee" : "thread"
        // Les cles prefixees seulement dans surnoms.json et pieces-noeuds.json : toutes celles de l'app.
        let surnoms = try #require(JSONSerialization.jsonObject(with: Self.octets(plan, "surnoms.json")) as? [String: Any])
        let valeurs = try #require(surnoms["surnoms"] as? [String: String])
        let source = try Self.objet(app, "surnoms.json")
        #expect(valeurs.count == source.count, "un surnom perdu ou ajoute")
        #expect(valeurs.keys.allSatisfy { $0.hasPrefix("\(protocole.rawValue):") }, "un surnom range sous un autre protocole")
        #expect(Set(valeurs.values) == Set(source.values.compactMap { $0 as? String }))
        let pieces = try Self.texte(plan, "pieces-noeuds.json")
        #expect(!pieces.contains("\"\(autre):"), "une piece rangee sous l'autre protocole")
        // Les fichiers propres a l'app sont rangees sous son dossier, sans changement de cle ni de contenu.
        let dossier = app == .maillageThread ? "Thread" : "Zigbee"
        let propres = plan.fichiers.filter { $0.chemin.hasPrefix("\(dossier)/") }
        #expect(!propres.isEmpty)
        for f in plan.fichiers where f.chemin.hasPrefix("\(dossier)/") && f.sources.count == 1 && !f.sources[0].hasSuffix(".jsonl") {
            let origine = try Data(contentsOf: Self.export(app).appendingPathComponent(f.sources[0]))
            #expect(try f.contenu.octets() == origine || f.chemin.hasSuffix("associations.json") || f.chemin.hasSuffix("appariements-maison.json"),
                    "\(f.chemin) change de contenu")
        }
        #expect(!plan.fichiers.contains { $0.chemin.hasPrefix(app == .maillageThread ? "Zigbee/" : "Thread/") })
        // Historique : les lignes du mois gardé vont telles quelles.
        for chemin in try Self.mensuels(app).gardes where chemin.hasPrefix("maillage-") {
            let f = try #require(plan.fichier("\(dossier)/\(chemin)"), "\(chemin) absent du plan")
            #expect(try Data(f.contenu.octets()) == Data(contentsOf: Self.export(app).appendingPathComponent(chemin)))
        }
    }

    static func octets(_ plan: PlanReprise, _ chemin: String) throws -> Data {
        try #require(plan.fichier(chemin), "\(chemin) absent du plan").contenu.octets()
    }

    static func texte(_ plan: PlanReprise, _ chemin: String) throws -> String {
        String(decoding: try octets(plan, chemin), as: UTF8.self)
    }

    @Test(arguments: App.allCases)
    func leJournalPrendLeProtocoleDeLApp(app: App) throws {
        let plan = try Self.convertir(app, donnees: D())
        let decodeur = CodageJSON.decodeur()
        var total = 0
        for chemin in try Self.mensuels(app).gardes where chemin.hasPrefix("Journal/") {
            let lignes = ConversionThreadTests.lignes(try Self.octets(plan, chemin))
            let sources = try Self.lignes(app, chemin)
            #expect(lignes.count == sources.count, "\(chemin) : une ligne perdue ou ajoutee")
            for l in lignes {
                let e = try decodeur.decode(Evenement.self, from: Data(l.utf8))
                switch app {
                case .maillageThread: #expect((e.protocole ?? .thread) == .thread, "ligne de Thread lue autrement : \(l)")
                case .maillageZigbee: #expect(e.protocole == .zigbee, "ligne de Zigbee sans son protocole : \(l)")
                }
            }
            total += lignes.count
        }
        #expect(total > 0)
    }

    @Test(arguments: App.allCases)
    func lHistoriqueDeMoinsDe90JoursEstGardeEtLeResteEcarte(app: App) throws {
        let (gardes, ecartes) = try Self.mensuels(app)
        #expect(!ecartes.isEmpty, "l'export d'exemple a un mois de plus de 90 jours")
        #expect(gardes.contains { $0.hasPrefix("maillage-") } && gardes.contains { $0.hasPrefix("Journal/") })
        let plan = try Self.convertir(app, donnees: D())
        let dossier = app == .maillageThread ? "Thread" : "Zigbee"
        for chemin in gardes {
            let cible = chemin.hasPrefix("Journal/") ? chemin : "\(dossier)/\(chemin)"
            #expect(plan.fichier(cible) != nil, "\(chemin) garde mais absent du plan")
        }
        for chemin in ecartes {
            let cible = chemin.hasPrefix("Journal/") ? chemin : "\(dossier)/\(chemin)"
            #expect(plan.fichier(cible) == nil, "\(chemin) ecarte mais place")
        }
    }

    // MARK: Ce que les lecteurs de l'app lisent

    @MainActor @Test func lePlanDeThreadEstRelisibleParLesLecteursDeLApp() throws {
        let plan = try Self.convertir(.maillageThread, donnees: D())
        let sortie = try D()
        try Self.appliquer(plan, dans: sortie)
        let source = try Self.objet(.maillageThread, "surnoms.json")
        #expect(Surnoms.lire(sortie.url("surnoms.json"), protocoleParDefaut: .zigbee).count == source.count)
        let surnomsLus = Surnoms.lire(sortie.url("surnoms.json"), protocoleParDefaut: .zigbee)
        #expect(Set(surnomsLus.keys.map(\.protocole)) == [.thread])
        let pieces = PiecesRouteurs.lire(sortie.url("pieces-noeuds.json"))
        #expect(pieces.appareils.values.reduce(0) { $0 + $1.count } == 1, "une piece d'appareil de Thread")
        #expect(pieces.maisons.values.reduce(0) { $0 + $1.count } == 1, "une piece de routeur de Thread")
        #expect(PlacesGardees.lire(sortie.url("positions-pieces.json")).maisons.count == 1)
        #expect(Associations.lire(sortie.url("Thread/associations.json")).count == 1)
        #expect(IdentitesGardees.lire(sortie.url("Thread/identites-routeurs.json"))?.identites.count == 2)
        let releve = try NomsMaison.lire(Data(contentsOf: sortie.url("releve-maison.json")))
        #expect(releve.version == 2 && releve.accessoires.count == 3)
        let historique = HistoriqueFichiers(dossier: sortie.url("Thread"), calendrier: ConversionThreadTests.calendrier)
        let attendu = try Self.mensuels(.maillageThread).gardes.filter { $0.hasPrefix("maillage-") }
            .reduce(0) { $0 + (try Self.lignes(.maillageThread, $1)).count }
        #expect(try historique.lire(depuis: .distantPast).count == attendu, "chaque releve de l'historique garde est lu")
        let journal = JournalFichiers(dossier: sortie.url("Journal"), politique: Surveillance.politiqueJournal)
        let attenduJournal = try Self.mensuels(.maillageThread).gardes.filter { $0.hasPrefix("Journal/") }
            .reduce(0) { $0 + (try Self.lignes(.maillageThread, $1)).count }
        #expect(try journal.lire().count == attenduJournal, "chaque ligne du journal gardee est lue")
    }

    @MainActor @Test func lePlanDeZigbeeEstRelisibleParLesLecteursDeLApp() throws {
        let plan = try Self.convertir(.maillageZigbee, donnees: D())
        let sortie = try D()
        try Self.appliquer(plan, dans: sortie)
        let source = try Self.objet(.maillageZigbee, "surnoms.json")
        let surnomsLus = Surnoms.lire(sortie.url("surnoms.json"), protocoleParDefaut: .thread)
        #expect(surnomsLus.count == source.count)
        #expect(Set(surnomsLus.keys.map(\.protocole)) == [.zigbee], "aucun surnom de Zigbee lu comme Thread")
        let pieces = PiecesRouteurs.lire(sortie.url("pieces-noeuds.json"))
        #expect(pieces.appareils.values.reduce(0) { $0 + $1.count } == 2)
        #expect(Set(pieces.appareils.values.flatMap(\.keys).map(\.protocole)) == [.zigbee])
        #expect(PlacesGardees.lire(sortie.url("positions-pieces.json")).maisons.count == 1)
        #expect(MemoireAppariements.lire(sortie.url("Zigbee/appariements-maison.json")).ids.count == 2)
        #expect(try NomsZigbee.lire(Data(contentsOf: sortie.url("Zigbee/noms-pont.json"))).accessoires.count == 2)
        #expect(try NomsMaison.lire(Data(contentsOf: sortie.url("releve-maison.json"))).version == 2)
        let historique = HistoriqueFichiersZigbee(dossier: sortie.url("Zigbee"), calendrier: ConversionThreadTests.calendrier)
        let attendu = try Self.mensuels(.maillageZigbee).gardes.filter { $0.hasPrefix("maillage-") }
            .reduce(0) { $0 + (try Self.lignes(.maillageZigbee, $1)).count }
        #expect(try historique.lire(depuis: .distantPast).count == attendu, "chaque releve de l'historique garde est lu")
        let journal = JournalFichiers(dossier: sortie.url("Journal"), politique: Surveillance.politiqueJournal)
        let evenements = try journal.lire()
        let attenduJournal = try Self.mensuels(.maillageZigbee).gardes.filter { $0.hasPrefix("Journal/") }
            .reduce(0) { $0 + (try Self.lignes(.maillageZigbee, $1)).count }
        #expect(evenements.count == attenduJournal)
        #expect(evenements.allSatisfy { $0.protocole == .zigbee }, "aucun evenement de Zigbee lu comme Thread")
    }

    /// Les fichiers d'etat de la sonde, tels que les modeles de l'app les relisent au lancement (memes formes que les
    /// structures privees de `SurveillanceThread` et `SurveillanceZigbee`) : celui de l'export, puis celui du plan.
    private struct MaillageGardeThread: Codable {
        var maillage: Maillage
        var recu: Date
    }

    private struct AdressesGardeesThread: Codable {
        var appareils: [String: Suivi.AdresseGardee]
    }

    private struct MaillageGardeZigbee: Codable {
        var maillage: MaillageZigbee
        var recu: Date
        var incomplet: Bool
    }

    @Test func lEtatDeLaSondeDeThreadSeRelitParLesModelesDeLApp() throws {
        let decodeur = CodageJSON.decodeur()
        let plan = try Self.convertir(.maillageThread, donnees: D())
        for lire in [{ (chemin: String) throws -> Data in try Data(contentsOf: Self.export(.maillageThread).appendingPathComponent(chemin)) },
                     { (chemin: String) throws -> Data in try Self.octets(plan, "Thread/" + chemin) }] {
            let garde = try decodeur.decode(MaillageGardeThread.self, from: lire("dernier-maillage.json"))
            #expect(garde.maillage.routeurs.count == 4 && garde.maillage.liens.count == 4)
            let adresses = try decodeur.decode(AdressesGardeesThread.self, from: lire("dernieres-adresses.json"))
            #expect(adresses.appareils.count == 1)
        }
    }

    @Test func lEtatDeLaSondeDeZigbeeSeRelitParLesModelesDeLApp() throws {
        let decodeur = CodageJSON.decodeur()
        let plan = try Self.convertir(.maillageZigbee, donnees: D())
        for lire in [{ (chemin: String) throws -> Data in try Data(contentsOf: Self.export(.maillageZigbee).appendingPathComponent(chemin)) },
                     { (chemin: String) throws -> Data in try Self.octets(plan, "Zigbee/" + chemin) }] {
            let garde = try decodeur.decode(MaillageGardeZigbee.self, from: lire("dernier-maillage.json"))
            #expect(garde.maillage.noeuds.count > 0 && !garde.incomplet)
        }
    }

    // MARK: Application et reimport (taches 6)

    @Test(arguments: App.allCases)
    func lApplicationDonneLeMemeEtatQueLePlanDeposeALaMain(app: App) async throws {
        let attendu = try D(), ra = ApplicationImportTests.ReglagesEssai()
        let plan = try Self.convertir(app, donnees: attendu, presents: ra.preferences.clesPresentes())
        try Self.appliquer(plan, dans: attendu)
        try ra.preferences.ecrire(plan.reglages)
        let d = try D(), r = ApplicationImportTests.ReglagesEssai()
        let resultat = try ApplicationImportTests.repris(await Self.appli(d, r).reprendre(export: Self.export(app)))
        #expect(resultat.repris.app == app && !resultat.planRecalcule)
        var obtenu = try ApplicationImportTests.arbre(d)
        #expect(obtenu.removeValue(forKey: "imports.json") != nil)
        #expect(obtenu == (try ApplicationImportTests.arbre(attendu).filter { $0.value != "dossier" || obtenu[$0.key] != nil }))
        #expect(r.domaine() == ra.domaine())
        #expect(Set(resultat.reglagesEcrits) == Set(plan.reglages.keys))
        #expect(!obtenu.keys.contains { $0.hasPrefix(ApplicationImport.nomTravail) })
    }

    static func appli(_ d: D, _ r: ApplicationImportTests.ReglagesEssai,
                      operations: any OperationsFichiers = OperationsFichiersReelles()) -> ApplicationImport {
        ApplicationImportTests.appli(d, r, operations: operations)
    }

    @Test(arguments: App.allCases)
    func reimporterLeMemeExportNeFaitRien(app: App) async throws {
        let d = try D(), r = ApplicationImportTests.ReglagesEssai()
        let a = Self.appli(d, r)
        _ = try ApplicationImportTests.repris(await a.reprendre(export: Self.export(app)))
        let fichiers = try ApplicationImportTests.arbre(d), domaine = r.domaine()
        guard case .dejaRepris(let repris, _) = try await a.reprendre(export: Self.export(app)) else {
            Issue.record("le meme export a ete repris deux fois")
            return
        }
        #expect(repris.app == app)
        #expect(try ApplicationImportTests.arbre(d) == fichiers, "rien n'a bouge")
        #expect(r.domaine() == domaine)
    }

    /// Meme sans le journal des imports (perdu, reinitialise), reprendre le meme export ne change aucun fichier : les
    /// fusions sont idempotentes, aucune ligne n'est doublee.
    @Test(arguments: App.allCases)
    func reprendreSansLeJournalDesImportsNeChangeAucunFichier(app: App) async throws {
        let d = try D(), r = ApplicationImportTests.ReglagesEssai()
        _ = try ApplicationImportTests.repris(await Self.appli(d, r).reprendre(export: Self.export(app)))
        var avant = try ApplicationImportTests.arbre(d)
        let domaine = r.domaine()
        try FileManager.default.removeItem(at: d.url("imports.json"))
        _ = try ApplicationImportTests.repris(await Self.appli(d, r).reprendre(export: Self.export(app)))
        var apres = try ApplicationImportTests.arbre(d)
        #expect(avant.removeValue(forKey: "imports.json") != nil && apres.removeValue(forKey: "imports.json") != nil)
        #expect(apres == avant, "le second import n'ajoute rien")
        #expect(r.domaine() == domaine, "aucun reglage de Djoko remplace")
    }

    @Test func lesDeuxAnciennesAppsSImportentDansLesDeuxOrdres() async throws {
        let (d1, r1) = (try D(), ApplicationImportTests.ReglagesEssai())
        let (d2, r2) = (try D(), ApplicationImportTests.ReglagesEssai())
        for app in [App.maillageThread, .maillageZigbee] { _ = try ApplicationImportTests.repris(await Self.appli(d1, r1).reprendre(export: Self.export(app))) }
        for app in [App.maillageZigbee, .maillageThread] { _ = try ApplicationImportTests.repris(await Self.appli(d2, r2).reprendre(export: Self.export(app))) }
        let a1 = try ApplicationImportTests.arbreSansTravail(d1), a2 = try ApplicationImportTests.arbreSansTravail(d2)
        #expect(Set(a1.keys) == Set(a2.keys))
        let surnoms = try #require(ApplicationImportTests.objet(d1, "surnoms.json")["surnoms"] as? [String: String])
        let attendu = try Self.objet(.maillageThread, "surnoms.json").count + Self.objet(.maillageZigbee, "surnoms.json").count
        #expect(surnoms.count == attendu, "les surnoms des deux protocoles, sans collision")
        #expect(surnoms.keys.filter { $0.hasPrefix("thread:") }.count == (try Self.objet(.maillageThread, "surnoms.json").count))
        #expect(surnoms.keys.filter { $0.hasPrefix("zigbee:") }.count == (try Self.objet(.maillageZigbee, "surnoms.json").count))
        // Le journal : toutes les lignes gardees des deux apps, chacune a son protocole, dans les deux ordres.
        for chemin in a1.keys where chemin.hasPrefix("Journal/") && chemin.hasSuffix(".jsonl") {
            #expect(Set(try ApplicationImportTests.lignes(d1, chemin)) == Set(try ApplicationImportTests.lignes(d2, chemin)), "\(chemin)")
        }
        let journal = try ApplicationImportTests.lignes(d1, "Journal/journal-2026-10.jsonl")
        let t = try Self.lignes(.maillageThread, "Journal/journal-2026-10.jsonl").count
        let z = try Self.lignes(.maillageZigbee, "Journal/journal-2026-10.jsonl").count
        #expect(journal.count == t + z)
        #expect(journal.filter { $0.contains(#""protocole":"zigbee""#) }.count == z)
        // Les fichiers communs et les reglages : chaque protocole sous sa cle, rien d'ecrase.
        #expect(r1.objet("thread.sondeNom") != nil && r1.objet("zigbee.sondeNom") != nil)
        #expect(r1.objet("thread.sondeNom") as? String == r2.objet("thread.sondeNom") as? String)
        #expect(r1.objet("zigbee.sondeNom") as? String == r2.objet("zigbee.sondeNom") as? String)
        #expect(try ApplicationImportTests.importes(d1).count == 2)
    }

    /// Les exports provisoires (taches 2 a 6) et ceux des anciennes apps s'importent ensemble : le second apporte ce qui
    /// manque, rien d'ecrase, aucun doublon.
    @Test(arguments: App.allCases)
    func lExportDeLAncienneAppApresLExportProvisoireNeFaitQueCompleter(app: App) async throws {
        let d = try D(), r = ApplicationImportTests.ReglagesEssai()
        let a = Self.appli(d, r)
        _ = try ApplicationImportTests.repris(await a.reprendre(export: ExportsExempleTests.dossier(app)))
        let avant = try ApplicationImportTests.arbreSansTravail(d)
        let reglagesAvant = r.domaine()
        _ = try ApplicationImportTests.repris(await a.reprendre(export: Self.export(app)))
        let apres = try ApplicationImportTests.arbreSansTravail(d)
        #expect(Set(avant.keys).isSubset(of: Set(apres.keys)), "aucun fichier disparu")
        // Les surnoms deja la ne sont jamais remplaces.
        let s1 = try ApplicationImportTests.octets(d, "surnoms.json")
        let surnoms = try #require(JSONSerialization.jsonObject(with: s1) as? [String: Any])
        #expect(surnoms["surnoms"] is [String: String])
        // Aucune cle de reglage deja posee n'a change de valeur.
        let apresReglages = r.domaine()
        for cle in reglagesAvant.allKeys {
            #expect((reglagesAvant[cle] as? NSObject) == (apresReglages[cle] as? NSObject), "reglage \(cle) ecrase")
        }
        #expect(try ApplicationImportTests.importes(d).map(\.app) == [app, app])
    }

    /// Echec injecte a chaque operation de l'application (avec ou sans un existant d'une autre app) : jusqu'a la validation,
    /// le dossier et les preferences sont alors octet pour octet ce qu'ils etaient.
    @Test(arguments: App.allCases, [false, true])
    func unEchecAChaqueOperationLaisseLeDossierIdentique(app: App, avecExistant: Bool) async throws {
        let (dm, rm) = try await ApplicationImportTests.depart(app, avecExistant: avecExistant)
        let opsM = ApplicationImportTests.OperationsEssai(racine: dm.racine)
        _ = try ApplicationImportTests.repris(await Self.appli(dm, rm, operations: opsM).reprendre(export: Self.export(app)))
        let validation = try #require(opsM.journal.firstIndex { $0 == "deplacer A:imports.json -> imports.json" }) + 1
        let (compte, final, prefs) = (opsM.compte, try ApplicationImportTests.arbreSansTravail(dm), rm.domaine())
        #expect(compte > 10 && validation < compte)
        for n in 1...compte {
            let (d, r) = try await ApplicationImportTests.depart(app, avecExistant: avecExistant)
            let (avant, prefsAvant) = (try ApplicationImportTests.arbre(d), r.domaine())
            let ops = ApplicationImportTests.OperationsEssai(racine: d.racine, mode: .unique(n))
            do {
                _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.export(app))
                #expect(n > validation, "l'echec de l'operation \(n) (\(ops.journal[n - 1])) aurait du tout defaire")
                #expect(try ApplicationImportTests.arbreSansTravail(d) == final)
                #expect(r.domaine() == prefs)
            } catch let e as ErreurApplication {
                guard case .echec(_, let retablie, _) = e else {
                    Issue.record("erreur inattendue \(e) a l'operation \(n)")
                    continue
                }
                #expect(retablie, "operation \(n) (\(ops.journal[n - 1])) : retour en arriere")
                #expect(n <= validation, "l'echec de l'operation \(n) apres la validation ne doit rien defaire")
                #expect(try ApplicationImportTests.arbre(d) == avant, "operation \(n) (\(ops.journal[n - 1])) : le dossier n'est pas identique")
                #expect(r.domaine() == prefsAvant, "operation \(n) : les preferences ne sont pas identiques")
            }
        }
    }

    @Test(arguments: App.allCases)
    func laChaineNeModifiePasLExportDeLAncienneApp(app: App) async throws {
        let export = try Self.export(app)
        let avant = try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) }
        let d = try D(), r = ApplicationImportTests.ReglagesEssai()
        _ = try ApplicationImportTests.repris(await Self.appli(d, r).reprendre(export: export))
        _ = try await Self.appli(d, r).reprendre(export: export)
        #expect(try ExportsExempleTests.fichiers(de: export).map { try Data(contentsOf: export.appendingPathComponent($0)) } == avant)
    }
}
