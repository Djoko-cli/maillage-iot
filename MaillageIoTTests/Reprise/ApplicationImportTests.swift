import Foundation
import MaillageCoeur
import os
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Phase 4, tache 6 : l'application d'un import, tout ou rien (`ApplicationImport`). Chaque test a son dossier de donnees
/// temporaire et ses preferences dans une suite nommee, effacees a la fin : jamais le vrai dossier de l'app ni les vraies
/// preferences. Les exports sont les exemples de `MaillageIoTTests/Ressources/exports` (valeurs inventees), la date de
/// reference est celle des exemples (2026-10-17 12:00 UTC). La couture `OperationsFichiers` fait echouer, a tour de role,
/// chacune des operations d'une application : le dossier doit alors etre octet pour octet ce qu'il etait.
@Suite("Application de l'import, tout ou rien")
struct ApplicationImportTests {
    typealias C = ContratExport
    typealias G = GenerateurExportsExemple
    typealias D = ConversionThreadTests.Donnees
    typealias Copie = ValidationExportTests.Copie
    typealias Echec = ValidationExportTests.Echec
    typealias App = ContratExport.AppSource

    // MARK: Outils

    /// Des preferences d'essai : une suite nommee, effacee a la fin du test.
    final class ReglagesEssai: Sendable {
        let nom = "fr.djoko.maillage.iot.essai-\(UUID().uuidString)"
        var preferences: PreferencesUserDefaults { PreferencesUserDefaults(suite: nom, domaine: nom) }

        func poser(_ cle: String, _ valeur: Any) { UserDefaults(suiteName: nom)?.set(valeur, forKey: cle) }

        func domaine() -> NSDictionary {
            NSDictionary(dictionary: UserDefaults(suiteName: nom)?.persistentDomain(forName: nom) ?? [:])
        }

        func objet(_ cle: String) -> Any? { UserDefaults(suiteName: nom)?.object(forKey: cle) }

        deinit { UserDefaults(suiteName: nom)?.removePersistentDomain(forName: nom) }
    }

    struct ErreurInjectee: Error {}

    /// Les operations reelles, comptees et journalisees (chemins relatifs au dossier de donnees), avec un echec injecte a la
    /// n-ieme operation (`unique` : celle-la seulement ; `depuis` : celle-la et toutes les suivantes, comme un arret net de
    /// l'app, retablissement compris) et un crochet qui s'execute juste avant l'operation (un changement "entretemps").
    final class OperationsEssai: OperationsFichiers, Sendable {
        enum Mode: Sendable {
            case normal
            case unique(Int)
            case depuis(Int)
        }

        struct Etat: Sendable {
            var compte = 0
            var journal: [String] = []
            var surLeFilPrincipal: [Bool] = []
        }

        private let etat = OSAllocatedUnfairLock(initialState: Etat())
        private let reelles = OperationsFichiersReelles()
        private let racine: String
        private let mode: Mode
        private let crochet: (@Sendable (Int, String) -> Void)?

        init(racine: URL, mode: Mode = .normal, crochet: (@Sendable (Int, String) -> Void)? = nil) {
            self.racine = racine.path + "/"
            self.mode = mode
            self.crochet = crochet
        }

        var journal: [String] { etat.withLock { $0.journal } }
        var compte: Int { etat.withLock { $0.compte } }
        var surLeFilPrincipal: [Bool] { etat.withLock { $0.surLeFilPrincipal } }

        private func relatif(_ url: URL) -> String {
            url.path.hasPrefix(racine) ? String(url.path.dropFirst(racine.count)) : url.path
        }

        /// Le nom d'une operation : son verbe puis ses chemins, sans le dossier de travail (`attente/x` devient `x`).
        private func nom(_ verbe: String, _ urls: URL...) -> String {
            verbe + " " + urls.map { u in
                let r = relatif(u)
                for dossier in ["\(ApplicationImport.nomTravail)/attente/", "\(ApplicationImport.nomTravail)/sauvegarde/"] where r.hasPrefix(dossier) {
                    return (dossier.contains("attente") ? "A:" : "S:") + String(r.dropFirst(dossier.count))
                }
                return r
            }.joined(separator: " -> ")
        }

        private func passer(_ nom: String, _ action: () throws -> Void) throws {
            let (n, echoue) = etat.withLock { e -> (Int, Bool) in
                e.compte += 1
                e.journal.append(nom)
                e.surLeFilPrincipal.append(Thread.isMainThread)
                switch mode {
                case .normal: return (e.compte, false)
                case .unique(let k): return (e.compte, e.compte == k)
                case .depuis(let k): return (e.compte, e.compte >= k)
                }
            }
            crochet?(n, nom)
            if echoue { throw ErreurInjectee() }
            try action()
        }

        func creerDossier(_ url: URL) throws { try passer(nom("creerDossier", url)) { try reelles.creerDossier(url) } }

        func ecrire(_ donnees: Data, vers url: URL, atomique: Bool) throws {
            try passer(nom(atomique ? "ecrireAtomique" : "ecrire", url)) { try reelles.ecrire(donnees, vers: url, atomique: atomique) }
        }

        func copier(de source: URL, vers cible: URL) throws {
            try passer(nom("copier", cible)) { try reelles.copier(de: source, vers: cible) }
        }

        func deplacer(de source: URL, vers cible: URL) throws {
            try passer(nom("deplacer", source, cible)) { try reelles.deplacer(de: source, vers: cible) }
        }

        func supprimer(_ url: URL) throws { try passer(nom("supprimer", url)) { try reelles.supprimer(url) } }
    }

    /// Des preferences qui echouent, ou qui regardent le dossier au moment d'ecrire.
    struct PreferencesEssai: PreferencesReprise {
        enum Mode: Sendable {
            case normales
            /// Echoue avant d'ecrire quoi que ce soit.
            case echecAvant
            /// Ecrit la moitie des cles puis echoue.
            case echecEnMilieu
        }

        let base: PreferencesUserDefaults
        var mode: Mode = .normales
        var avantEcriture: (@Sendable () -> Void)?
        /// Vrai quand l'app est "arretee" : plus rien ne s'ecrit, reglages compris (ni ecriture ni retrait).
        var arret: OSAllocatedUnfairLock<Bool>?

        private var arretee: Bool { arret?.withLock { $0 } ?? false }

        func clesPresentes() -> Set<String> { base.clesPresentes() }

        func valeurs(pour cles: [String]) -> [String: ContratExport.Valeur] { base.valeurs(pour: cles) }

        func ecrire(_ valeurs: [String: ContratExport.Valeur]) throws {
            guard !arretee else { return }
            avantEcriture?()
            switch mode {
            case .normales: try base.ecrire(valeurs)
            case .echecAvant: throw ErreurInjectee()
            case .echecEnMilieu:
                let cles = valeurs.keys.sorted()
                try base.ecrire(valeurs.filter { cles.prefix(max(1, cles.count / 2)).contains($0.key) })
                throw ErreurInjectee()
            }
        }

        func retirer(_ cles: [String]) { if !arretee { base.retirer(cles) } }
    }

    /// Lance l'import et l'arrete net a l'operation `n` (comme un arret de l'app) : plus rien ne s'ecrit apres, ni fichier,
    /// ni reglage, et le retour en arriere de l'import ne tourne pas.
    static func importArreteA(_ n: Int, _ app: App, _ d: D, _ r: ReglagesEssai) async {
        let arret = OSAllocatedUnfairLock(initialState: false)
        let ops = OperationsEssai(racine: d.racine, mode: .depuis(n)) { k, _ in if k >= n { arret.withLock { $0 = true } } }
        var preferences = PreferencesEssai(base: r.preferences)
        preferences.arret = arret
        do { _ = try await appli(d, r, operations: ops, preferences: preferences).reprendre(export: exemple(app)) } catch {}
    }

    static func exemple(_ app: App) throws -> URL { try ExportsExempleTests.dossier(app) }

    static func appli(_ d: D, _ r: ReglagesEssai, operations: any OperationsFichiers = OperationsFichiersReelles(),
                      preferences: (any PreferencesReprise)? = nil) -> ApplicationImport {
        ApplicationImport(dossierDonnees: d.racine, preferences: preferences ?? r.preferences, operations: operations,
                          maintenant: { G.dateReference }, calendrier: ConversionThreadTests.calendrier)
    }

    /// Tout le dossier : chaque fichier (empreinte) et chaque dossier, dossier de travail compris. Deux dossiers sont
    /// "octet pour octet les memes" quand leurs arbres sont egaux.
    static func arbre(_ d: D) throws -> [String: String] {
        var r: [String: String] = [:]
        func parcourir(_ dossier: URL, _ prefixe: String) throws {
            for nom in try FileManager.default.contentsOfDirectory(atPath: dossier.path).sorted() {
                let u = dossier.appendingPathComponent(nom)
                var estDossier: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: u.path, isDirectory: &estDossier)
                if estDossier.boolValue {
                    r[prefixe + nom + "/"] = "dossier"
                    try parcourir(u, prefixe + nom + "/")
                } else {
                    r[prefixe + nom] = C.sha256(try Data(contentsOf: u))
                }
            }
        }
        if FileManager.default.fileExists(atPath: d.racine.path) { try parcourir(d.racine, "") }
        return r
    }

    /// L'arbre sans le dossier de travail.
    static func arbreSansTravail(_ d: D) throws -> [String: String] {
        try arbre(d).filter { !$0.key.hasPrefix(ApplicationImport.nomTravail) }
    }

    static func octets(_ d: D, _ chemin: String) throws -> Data { try Data(contentsOf: d.url(chemin)) }

    static func objet(_ d: D, _ chemin: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: octets(d, chemin)) as? [String: Any])
    }

    static func lignes(_ d: D, _ chemin: String) throws -> [String] { ConversionThreadTests.lignes(try octets(d, chemin)) }

    static func importes(_ d: D) throws -> [ImportRepris] {
        try ContratExport.decodeur().decode(JournalImports.self, from: octets(d, "imports.json")).imports
    }

    static func repris(_ i: IssueReprise) throws -> ResultatApplication {
        guard case .repris(let r) = i else { throw Echec("deja repris alors qu'il fallait reprendre") }
        return r
    }

    /// Reprend les exports donnes, dans l'ordre, avec les vraies operations.
    @discardableResult
    static func reprendre(_ apps: [App], dans d: D, _ r: ReglagesEssai) async throws -> [ResultatApplication] {
        let a = appli(d, r)
        var resultats: [ResultatApplication] = []
        for app in apps { resultats.append(try repris(await a.reprendre(export: exemple(app)))) }
        return resultats
    }

    /// Le dossier et les preferences de depart d'un test d'echec : vide, ou deja garni par l'import de l'autre app.
    static func depart(_ app: App, avecExistant: Bool) async throws -> (D, ReglagesEssai) {
        let d = try D(), r = ReglagesEssai()
        if avecExistant {
            try await reprendre([app == .maillageThread ? .maillageZigbee : .maillageThread], dans: d, r)
            // Un choix de Djoko par-dessus, dans un fichier que l'import va devoir fusionner.
            let c = try Self.objet(d, "surnoms.json")
            var surnoms = try #require(c["surnoms"] as? [String: String])
            surnoms["\(app.rawValue):0000000000000001"] = "Mon choix"
            try d.ecrire("surnoms.json", JSONSerialization.data(withJSONObject: ["version": 1, "surnoms": surnoms], options: [.sortedKeys]))
        }
        return (d, r)
    }

    // MARK: L'etat final

    @Test func importDeThreadPuisDeZigbee() async throws {
        let d = try D(), r = ReglagesEssai()
        let resultats = try await Self.reprendre([.maillageThread, .maillageZigbee], dans: d, r)
        #expect(resultats.map(\.repris.app) == [.maillageThread, .maillageZigbee])
        #expect(resultats.allSatisfy { !$0.planRecalcule })

        // Surnoms : les deux protocoles, sans collision.
        let surnoms = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(surnoms.keys.filter { $0.hasPrefix("thread:") }.count == 5)
        #expect(surnoms.keys.filter { $0.hasPrefix("zigbee:") }.count == 3)
        #expect(surnoms.count == 8)
        // Fichiers : sous Thread/ et Zigbee/, journaux a la racine, rien a l'ancien nom.
        let fichiers = Set(try Self.arbreSansTravail(d).keys)
        for chemin in ["surnoms.json", "pieces-noeuds.json", "positions-pieces.json", "releve-maison.json", "imports.json",
                       "Thread/associations.json", "Thread/dernier-maillage.json", "Thread/maillage-2026-10.jsonl",
                       "Zigbee/noms-pont.json", "Zigbee/appariements-maison.json", "Zigbee/maillage-2026-10.jsonl",
                       "Journal/journal-2026-10.jsonl"] {
            #expect(fichiers.contains(chemin), "\(chemin) absent")
        }
        #expect(!fichiers.contains("pieces-routeurs.json") && !fichiers.contains("noms.json"))
        #expect(!fichiers.contains { $0.hasPrefix(ApplicationImport.nomTravail) }, "rien ne reste du dossier de travail")
        // Journal : les lignes des deux apps, chacune a son protocole.
        let journal = try Self.lignes(d, "Journal/journal-2026-10.jsonl")
        #expect(journal.count == 17, "7 lignes de Thread + 10 de Zigbee")
        #expect(journal.filter { $0.contains(#""protocole":"zigbee""#) || $0.contains(#""protocole" : "zigbee""#) }.count == 10)
        // Preferences : chaque protocole sous son prefixe.
        #expect(r.objet("thread.sondeNom") as? String == "SONDE-T1")
        #expect(r.objet("zigbee.sondeNom") as? String == "SONDE-Z1")
        #expect(r.objet("zigbee.sondeJournalPages") == nil, "reglage transitoire non repris")
        // imports.json : une ligne par reprise, dans l'ordre.
        let importes = try Self.importes(d)
        #expect(importes.map(\.identifiant) == [G.identifiant(.maillageThread), G.identifiant(.maillageZigbee)])
        #expect(importes.map(\.app) == [.maillageThread, .maillageZigbee])
        #expect(importes.allSatisfy { $0.date == G.dateReference })
    }

    /// L'oracle : les plans de Thread et de Zigbee deposes a la main l'un apres l'autre (sans l'application), dans un
    /// autre dossier. L'application doit donner les memes fichiers et les memes preferences.
    @Test func lApplicationDonneCeQueDonnentLesPlansDeposesALaMain() async throws {
        let attendu = try D(), ra = ReglagesEssai()
        for app in [App.maillageThread, .maillageZigbee] {
            let etat = EtatActuel(dossier: attendu.racine, reglagesPresents: ra.preferences.clesPresentes())
            let plan = app == .maillageThread
                ? try ConversionThread.convertir(dossier: Self.exemple(app), etat: etat, maintenant: G.dateReference,
                                                 calendrier: ConversionThreadTests.calendrier)
                : try ConversionZigbee.convertir(dossier: Self.exemple(app), etat: etat, maintenant: G.dateReference,
                                                 calendrier: ConversionThreadTests.calendrier)
            for f in plan.fichiers { try attendu.ecrire(f.chemin, f.contenu.octets()) }
            try ra.preferences.ecrire(plan.reglages)
        }
        let d = try D(), r = ReglagesEssai()
        try await Self.reprendre([.maillageThread, .maillageZigbee], dans: d, r)
        var obtenu = try Self.arbre(d)
        #expect(obtenu.removeValue(forKey: "imports.json") != nil)
        #expect(obtenu == (try Self.arbre(attendu).filter { $0.value != "dossier" || obtenu[$0.key] != nil }))
        #expect(r.domaine() == ra.domaine())
    }

    @Test func zigbeePuisThreadDonneLeMemeEtatPourLesFichiersCommuns() async throws {
        let (d1, r1) = (try D(), ReglagesEssai())
        let (d2, r2) = (try D(), ReglagesEssai())
        try await Self.reprendre([.maillageThread, .maillageZigbee], dans: d1, r1)
        try await Self.reprendre([.maillageZigbee, .maillageThread], dans: d2, r2)
        let a1 = try Self.arbreSansTravail(d1), a2 = try Self.arbreSansTravail(d2)
        #expect(Set(a1.keys) == Set(a2.keys), "les memes fichiers")
        for chemin in a1.keys.sorted() where a1[chemin] != "dossier" {
            if chemin == "imports.json" { continue }
            if chemin.hasSuffix(".jsonl") && chemin.hasPrefix("Journal/") {
                #expect(Set(try Self.lignes(d1, chemin)) == Set(try Self.lignes(d2, chemin)), "\(chemin) : memes lignes")
                #expect(try Self.lignes(d1, chemin).count == Self.lignes(d2, chemin).count, "\(chemin) : sans doublon")
            } else if chemin == "positions-pieces.json" {
                // L'ordre des etages suit l'ordre des imports ; les maisons, etages et pieces sont les memes.
                let p1 = try Self.positions(d1), p2 = try Self.positions(d2)
                #expect(p1 == p2, "positions-pieces.json")
            } else {
                #expect(a1[chemin] == a2[chemin], "\(chemin) differe selon l'ordre")
            }
        }
        // Les preferences propres a un protocole ne dependent pas de l'ordre ; les communes suivent "le premier l'emporte".
        let communes: Set<String> = ["AppleLanguages", "etagesEnGrille", "grapheDejaOuvert", "legendeRepliee", "ouvertureSessionProposee", "vuePieces3D"]
        let (p1, p2) = (r1.domaine(), r2.domaine())
        let cles = Set((p1.allKeys + p2.allKeys).compactMap { $0 as? String })
        #expect(!cles.isEmpty)
        for cle in cles where !communes.contains(cle) && !cle.hasPrefix("notification.") || cle.hasPrefix("notification.thread.") || cle.hasPrefix("notification.zigbee.") {
            #expect((p1[cle] as AnyObject?)?.isEqual(p2[cle]) == true, "\(cle) differe selon l'ordre")
        }
    }

    private static func positions(_ d: D) throws -> NSDictionary {
        var objet = try Self.objet(d, "positions-pieces.json")
        // Les listes d'etages sont comparees comme des ensembles.
        func normaliser(_ v: Any) -> Any {
            if var o = v as? [String: Any] {
                for (k, x) in o { o[k] = k == "ordreEtages" ? Set((x as? [String]) ?? []) : normaliser(x) }
                return o
            }
            return v
        }
        objet = (normaliser(objet) as? [String: Any]) ?? objet
        return NSDictionary(dictionary: objet)
    }

    // MARK: Idempotence

    @Test func reimporterLeMemeExportNeChangeRien() async throws {
        let d = try D(), r = ReglagesEssai()
        let a = Self.appli(d, r)
        _ = try Self.repris(await a.reprendre(export: Self.exemple(.maillageThread)))
        let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
        guard case .dejaRepris(let reprise, let resume) = try await a.reprendre(export: Self.exemple(.maillageThread)) else {
            throw Echec("le meme export a ete repris une seconde fois")
        }
        #expect(reprise.identifiant == G.identifiant(.maillageThread) && resume.identifiant == reprise.identifiant)
        #expect(try Self.arbre(d) == avant, "le dossier n'a pas change d'un octet")
        #expect(r.domaine() == prefsAvant, "les preferences non plus")
        // Une autre instance (apres un relancement) le sait aussi : c'est imports.json qui s'en souvient.
        guard case .dejaRepris = try await Self.appli(d, r).reprendre(export: Self.exemple(.maillageThread)) else {
            throw Echec("imports.json n'a pas suffi")
        }
        #expect(try Self.arbre(d) == avant)
    }

    @Test func unPlanDejaAppliqueNeSAppliquePasDeuxFois() async throws {
        let d = try D(), r = ReglagesEssai()
        let a = Self.appli(d, r)
        guard case .aReprendre(let p) = try await a.preparer(export: Self.exemple(.maillageZigbee)) else { throw Echec("deja repris") }
        _ = try await a.appliquer(p)
        let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
        await #expect(throws: ErreurApplication.self) { try await a.appliquer(p) }
        #expect(try Self.arbre(d) == avant && r.domaine() == prefsAvant)
    }

    // MARK: Un choix deja fait n'est jamais ecrase

    @Test func unChoixDejaFaitDansMaillageIoTNEstJamaisEcrase() async throws {
        let d = try D(), r = ReglagesEssai()
        // Un surnom, un choix de piece et trois reglages de Djoko.
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Mon choix","zigbee:00AA":"Lampe Zigbee"},"version":1}"#)
        var pieces = PiecesRouteurs()
        pieces.choisir("Salon", routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1")
        try d.ecrire("pieces-noeuds.json", ConversionThreadTests.encodeur().encode(pieces))
        r.poser("thread.sondeLiaison", "usb")
        r.poser("thread.sondeNom", "MON-NOM")
        r.poser("notification.thread.pertes", true)
        let resultat = try Self.repris(await Self.appli(d, r).reprendre(export: Self.exemple(.maillageThread)))

        let surnoms = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(surnoms["thread:0000000000000001"] == "Mon choix", "le surnom de Djoko l'emporte")
        #expect(surnoms["zigbee:00AA"] == "Lampe Zigbee")
        #expect(surnoms["thread:0000000000000002"] == "Capteur 1", "ce qui manquait est ajoute")
        let relu = d.url("relu.json")
        try Self.octets(d, "pieces-noeuds.json").write(to: relu)
        let p = PiecesRouteurs.lire(relu)
        try FileManager.default.removeItem(at: relu)
        #expect(p.choix(routeur: IdNoeud(.thread, "Routeur 1"), domicile: "Maison 1") == "Salon")
        #expect(p.choix(routeur: IdNoeud(.thread, "Routeur 2"), domicile: "Maison 1") == "Pièce 1")
        #expect(r.objet("thread.sondeLiaison") as? String == "usb", "la liaison choisie reste")
        #expect(r.objet("thread.sondeNom") as? String == "MON-NOM")
        #expect(r.objet("notification.thread.pertes") as? Bool == true, "une notification choisie n'est pas remise au defaut")
        #expect(r.objet("thread.sondeHote") as? String == "sonde-t1.local", "un reglage absent est repris")
        #expect(!resultat.reglagesEcrits.contains("thread.sondeLiaison") && !resultat.reglagesEcrits.contains("thread.sondeNom"))
        #expect(resultat.reglagesEcrits.contains("thread.sondeHote"))
    }

    @Test func unFormatInconnuDejaPresentNEstJamaisEcrase() async throws {
        let d = try D(), r = ReglagesEssai()
        let surnoms = Data(#"{"surnoms":{"thread:0000000000000001":"Futur"},"version":99}"#.utf8)
        let pieces = Data(#"{"version":7,"nouveau":true}"#.utf8)
        let positions = Data("pas du json".utf8)
        try d.ecrire("surnoms.json", surnoms)
        try d.ecrire("pieces-noeuds.json", pieces)
        try d.ecrire("positions-pieces.json", positions)
        let resultat = try Self.repris(await Self.appli(d, r).reprendre(export: Self.exemple(.maillageThread)))
        #expect(try Self.octets(d, "surnoms.json") == surnoms, "surnoms.json d'une version plus recente est intact")
        #expect(try Self.octets(d, "pieces-noeuds.json") == pieces)
        #expect(try Self.octets(d, "positions-pieces.json") == positions)
        for chemin in ["pieces-routeurs.json", "positions-pieces.json", "surnoms.json"] {
            #expect(resultat.nonPris.contains { $0.nature == .fichier(chemin) && $0.raison == .fichierExistantNonLisible },
                    "\(chemin) cite parmi ce qui n'est pas repris")
        }
        #expect(!resultat.fichiersEcrits.contains("surnoms.json") && !resultat.fichiersEcrits.contains("pieces-noeuds.json"))
        #expect(try Self.octets(d, "Thread/associations.json").count > 0, "le reste de la reprise a eu lieu")
        #expect(try Self.importes(d).count == 1)
    }

    // MARK: Tout ou rien : un echec a chaque operation

    /// Une application propre, pour compter ses operations et trouver celle qui valide.
    private static func modele(_ app: App, avecExistant: Bool) async throws -> (compte: Int, validation: Int, final: [String: String], prefs: NSDictionary) {
        let (d, r) = try await depart(app, avecExistant: avecExistant)
        let ops = OperationsEssai(racine: d.racine)
        _ = try repris(await appli(d, r, operations: ops).reprendre(export: exemple(app)))
        let validation = try #require(ops.journal.firstIndex { $0 == "deplacer A:imports.json -> imports.json" }) + 1
        return (ops.compte, validation, try arbre(d), r.domaine())
    }

    @Test(arguments: [App.maillageThread, .maillageZigbee], [false, true])
    func unEchecAChaqueOperationLaisseLeDossierIdentique(app: App, avecExistant: Bool) async throws {
        let m = try await Self.modele(app, avecExistant: avecExistant)
        #expect(m.compte > 10 && m.validation < m.compte)
        for n in 1...m.compte {
            let (d, r) = try await Self.depart(app, avecExistant: avecExistant)
            let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
            let ops = OperationsEssai(racine: d.racine, mode: .unique(n))
            do {
                _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(app))
                #expect(n > m.validation, "l'echec de l'operation \(n) (\(ops.journal[n - 1])) aurait du tout defaire")
                // Apres la validation : la reprise est faite, seul le nettoyage a echoue.
                #expect(try Self.arbreSansTravail(d) == m.final.filter { !$0.key.hasPrefix(ApplicationImport.nomTravail) })
                #expect(r.domaine() == m.prefs)
            } catch let e as ErreurApplication {
                guard case .echec(_, let retablie, _) = e else { throw Echec("erreur inattendue \(e) a l'operation \(n)") }
                #expect(retablie, "operation \(n) (\(ops.journal[n - 1])) : retour en arriere")
                #expect(n <= m.validation, "l'echec de l'operation \(n) apres la validation ne doit rien defaire")
                #expect(try Self.arbre(d) == avant, "operation \(n) (\(ops.journal[n - 1])) : le dossier n'est pas identique")
                #expect(r.domaine() == prefsAvant, "operation \(n) : les preferences ne sont pas identiques")
            }
        }
    }

    @Test(arguments: [App.maillageThread, .maillageZigbee], [false, true])
    func uneApplicationInterrompueEstDefaiteAuLancementSuivant(app: App, avecExistant: Bool) async throws {
        let m = try await Self.modele(app, avecExistant: avecExistant)
        for n in 1...m.compte {
            let (d, r) = try await Self.depart(app, avecExistant: avecExistant)
            let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
            // L'app s'arrete net a l'operation n : plus rien ne s'ecrit, le retour en arriere non plus.
            let ops = OperationsEssai(racine: d.racine, mode: .depuis(n))
            do { _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(app)) } catch {}
            // Le lancement suivant.
            let issue = try await Self.appli(d, r).recuperer()
            if n <= m.validation {
                #expect(try Self.arbre(d) == avant, "arret a l'operation \(n) (\(ops.journal[n - 1])) : le dossier n'est pas revenu")
                #expect(r.domaine() == prefsAvant, "arret a l'operation \(n) : preferences")
                #expect([.rienAFaire, .nettoyee, .annulee].contains(issue), "operation \(n) : \(issue)")
            } else {
                #expect(try Self.arbre(d) == m.final, "arret apres la validation (operation \(n)) : la reprise est faite et nettoyee")
                #expect(r.domaine() == m.prefs)
                #expect([.rienAFaire, .nettoyee, .terminee].contains(issue), "operation \(n) : \(issue)")
            }
            // Et l'import peut etre refait, ou ne l'est pas s'il etait fait.
            let suite = try await Self.appli(d, r).reprendre(export: Self.exemple(app))
            if n <= m.validation { _ = try Self.repris(suite) } else if case .repris = suite { throw Echec("repris deux fois") }
            #expect(try Self.arbre(d) == m.final, "apres le retour (operation \(n)) : meme etat final")
        }
    }

    @Test func uneApplicationAbandonneeApresLaValidationSeTermine() async throws {
        let m = try await Self.modele(.maillageThread, avecExistant: false)
        let d = try D(), r = ReglagesEssai()
        // Tout s'ecrit jusqu'a la validation, puis plus rien (le nettoyage ne se fait pas).
        let ops = OperationsEssai(racine: d.racine, mode: .depuis(m.validation + 1))
        _ = try Self.repris(await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)))
        #expect(try Self.arbre(d)[ApplicationImport.nomTravail + "/"] == "dossier", "le dossier de travail est reste")
        #expect(try await Self.appli(d, r).recuperer() == .terminee)
        #expect(try Self.arbre(d) == m.final)
        #expect(try await Self.appli(d, r).recuperer() == .rienAFaire)
    }

    @Test func unDossierDeTravailSansJournalEstSupprime() async throws {
        let d = try D(), r = ReglagesEssai()
        try d.ecrire("surnoms.json", "{}")
        try d.ecrire("\(ApplicationImport.nomTravail)/attente/x.json", "{}")
        let avant = try Self.arbreSansTravail(d)
        #expect(try await Self.appli(d, r).recuperer() == .nettoyee)
        #expect(try Self.arbre(d) == avant)
    }

    @Test func unJournalDeRepriseIllisibleNEstJamaisEfface() async throws {
        let d = try D(), r = ReglagesEssai()
        try d.ecrire("\(ApplicationImport.nomTravail)/journal.json", "pas du json")
        try d.ecrire("\(ApplicationImport.nomTravail)/sauvegarde/surnoms.json", "{}")
        let avant = try Self.arbre(d)
        let a = Self.appli(d, r)
        await #expect(throws: ErreurApplication.self) { try await a.recuperer() }
        await #expect(throws: ErreurApplication.self) { try await a.preparer(export: Self.exemple(.maillageThread)) }
        #expect(try Self.arbre(d) == avant, "rien n'est efface quand le journal ne se lit pas")
    }

    @Test func preparerDefaitUneApplicationInterrompueAvantDeLire() async throws {
        let d = try D(), r = ReglagesEssai()
        let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
        let ops = OperationsEssai(racine: d.racine, mode: .depuis(12))
        do { _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageZigbee)) } catch {}
        #expect(try Self.arbre(d) != avant, "l'application interrompue a laisse des traces")
        guard case .aReprendre = try await Self.appli(d, r).preparer(export: Self.exemple(.maillageZigbee)) else {
            throw Echec("l'export devait pouvoir etre repris")
        }
        #expect(try Self.arbre(d) == avant && r.domaine() == prefsAvant)
    }

    @Test func unEchecDuDossierDeDonneesAbsentLeLaisseAbsent() async throws {
        let m = try await Self.modele(.maillageThread, avecExistant: false)
        for n in 1...m.validation {
            let d = try D(), r = ReglagesEssai()
            try FileManager.default.removeItem(at: d.racine)
            let ops = OperationsEssai(racine: d.racine, mode: .unique(n))
            await #expect(throws: ErreurApplication.self) {
                try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread))
            }
            #expect(!FileManager.default.fileExists(atPath: d.racine.path), "operation \(n) : le dossier cree est retire")
        }
        // Sans echec, il est cree.
        let d = try D(), r = ReglagesEssai()
        try FileManager.default.removeItem(at: d.racine)
        _ = try Self.repris(await Self.appli(d, r).reprendre(export: Self.exemple(.maillageThread)))
        #expect(try Self.importes(d).count == 1)
    }

    // MARK: Preferences : seulement apres les fichiers, et tout ou rien

    @Test(arguments: [PreferencesEssai.Mode.echecAvant, .echecEnMilieu])
    func unEchecDesPreferencesDefaitLesFichiers(mode: PreferencesEssai.Mode) async throws {
        let (d, r) = try await Self.depart(.maillageZigbee, avecExistant: true)
        let (avant, prefsAvant) = (try Self.arbre(d), r.domaine())
        let preferences = PreferencesEssai(base: r.preferences, mode: mode)
        let a = Self.appli(d, r, preferences: preferences)
        do {
            _ = try await a.reprendre(export: Self.exemple(.maillageZigbee))
            throw Echec("l'application aurait du echouer")
        } catch let e as ErreurApplication {
            guard case .echec(.reglages, retablie: true, _) = e else { throw Echec("\(e)") }
        }
        #expect(try Self.arbre(d) == avant, "les fichiers sont revenus")
        #expect(r.domaine() == prefsAvant, "les cles ecrites a moitie sont retirees")
    }

    @Test func lesPreferencesNeSEcriventQuApresLesFichiers() async throws {
        let d = try D(), r = ReglagesEssai()
        let vu = OSAllocatedUnfairLock<[String: String]>(initialState: [:])
        let racine = d.racine
        var preferences = PreferencesEssai(base: r.preferences)
        preferences.avantEcriture = {
            let fichiers = (try? FileManager.default.contentsOfDirectory(atPath: racine.path)) ?? []
            vu.withLock { $0 = Dictionary(uniqueKeysWithValues: fichiers.map { ($0, "") }) }
        }
        _ = try Self.repris(await Self.appli(d, r, preferences: preferences).reprendre(export: Self.exemple(.maillageThread)))
        let moment = vu.withLock { $0 }
        #expect(moment["surnoms.json"] != nil && moment["Thread"] != nil, "les fichiers sont deja en place")
        #expect(moment["imports.json"] == nil, "imports.json ne vient qu'apres")
    }

    @Test func lesPreferencesSEcriventAvecLeurType() async throws {
        let d = try D(), r = ReglagesEssai()
        try await Self.reprendre([.maillageZigbee], dans: d, r)
        #expect(r.objet("zigbee.sondeNom") as? String == "SONDE-Z1")
        #expect((r.objet("zigbee.sondePagesTables") as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.intValue == 4 } == true)
        #expect((r.objet("zigbee.pont.hue") as? Data).map { !$0.isEmpty } == true)
        #expect(r.objet("zigbee.voisinsALaSelection") as? Bool == true)
        #expect(r.objet("AppleLanguages") as? [String] == ["fr", "en"])
        #expect(r.objet("zigbee.sondeJournalPages") == nil)
    }

    // MARK: imports.json

    @Test func importsJsonSEcritPleinementOuPasDuTout() async throws {
        let d = try D(), r = ReglagesEssai()
        // Une reprise plus ancienne est deja dans le journal : elle reste, la nouvelle s'ajoute apres.
        let ancien = ImportRepris(identifiant: UUID(), app: .maillageZigbee, versionApp: "1.1.1", date: G.dateReference.addingTimeInterval(-86_400))
        try d.ecrire("imports.json", JournalImports(imports: [ancien]).donnees())
        let ops = OperationsEssai(racine: d.racine)
        _ = try Self.repris(await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)))
        let importes = try Self.importes(d)
        #expect(importes.count == 2 && importes[0] == ancien && importes[1].identifiant == G.identifiant(.maillageThread))
        #expect(importes[1].versionApp == "1.3.0" || !importes[1].versionApp.isEmpty)
        // Jamais ecrit en place : un fichier d'attente, puis deux renommages (l'ancien en sauvegarde, le nouveau a sa place).
        let journal = ops.journal
        #expect(!journal.contains { $0.hasPrefix("ecrire imports.json") || $0.hasPrefix("ecrireAtomique imports.json") })
        #expect(journal.contains("ecrire A:imports.json"))
        let sauvegarde = try #require(journal.firstIndex(of: "deplacer imports.json -> S:imports.json"))
        let miseEnPlace = try #require(journal.firstIndex(of: "deplacer A:imports.json -> imports.json"))
        #expect(miseEnPlace == sauvegarde + 1, "l'ancien part, le nouveau arrive aussitot")
        // C'est la derniere ecriture avant le nettoyage : tout le reste du dossier est deja en place.
        #expect(journal[(miseEnPlace + 1)...].allSatisfy { $0.hasPrefix("supprimer") })
        // Le journal est lu par la validation, sans changement de schema.
        guard case .dejaRepris = ValidationExport.valider(dossier: try Self.exemple(.maillageThread), dossierDonnees: d.racine) else {
            throw Echec("imports.json n'est pas relu par la validation")
        }
    }

    @Test func unExportRefuseNeToucheRienEtNeCreeRien() async throws {
        let copie = try Copie(.maillageThread)
        try copie.modifierLigne("surnoms.json") { $0["sha256"] = String(repeating: "0", count: 64) }
        let d = try D(), r = ReglagesEssai()
        let ops = OperationsEssai(racine: d.racine)
        do {
            _ = try await Self.appli(d, r, operations: ops).reprendre(export: copie.dossier)
            throw Echec("un export altere a ete accepte")
        } catch let e as ErreurApplication {
            #expect(e == .refuse(.empreinteFausse("surnoms.json")))
        }
        #expect(ops.compte == 0, "aucune ecriture")
        #expect(try Self.arbre(d).isEmpty && r.domaine().count == 0)
    }

    @Test func unImportsJsonAbimeBloqueLaRepriseSansRienChanger() async throws {
        let d = try D(), r = ReglagesEssai()
        try d.ecrire("imports.json", "{abime")
        let avant = try Self.arbre(d)
        let a = Self.appli(d, r)
        do {
            _ = try await a.reprendre(export: Self.exemple(.maillageThread))
            throw Echec("journal abime accepte")
        } catch let e as ErreurApplication {
            guard case .refuse(.journalDesImportsIllisible) = e else { throw Echec("\(e)") }
        }
        #expect(try Self.arbre(d) == avant)
        // Mis de cote (jamais supprime), l'import repart comme au premier jour.
        #expect(try JournalImports.mettreDeCoteImportsAbime(dans: d.racine) != nil)
        _ = try Self.repris(await a.reprendre(export: Self.exemple(.maillageThread)))
        #expect(try Self.importes(d).count == 1)
        #expect(try Self.octets(d, "imports.json.abime") == Data("{abime".utf8))
    }

    // MARK: Un changement entre le plan et l'application

    @Test func unFichierChangeEntreLePlanEtLApplicationFaitRefaireLePlan() async throws {
        let d = try D(), r = ReglagesEssai()
        let a = Self.appli(d, r)
        guard case .aReprendre(let p) = try await a.preparer(export: Self.exemple(.maillageThread)) else { throw Echec("deja repris") }
        #expect(p.plan.fichier("surnoms.json") != nil)
        // Entretemps, Djoko donne un surnom et fait un reglage (l'app tourne).
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Mon choix"},"version":1}"#)
        r.poser("thread.sondeNom", "MON-NOM")
        let resultat = try await a.appliquer(p)
        #expect(resultat.planRecalcule)
        let surnoms = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(surnoms["thread:0000000000000001"] == "Mon choix", "le surnom de Djoko n'est pas ecrase par un plan perime")
        #expect(surnoms["thread:0000000000000002"] == "Capteur 1" && surnoms.count == 5)
        #expect(r.objet("thread.sondeNom") as? String == "MON-NOM")
        #expect(!resultat.reglagesEcrits.contains("thread.sondeNom"))
    }

    @Test func unFichierQuiApparaitEntreLePlanEtLApplicationEstFusionne() async throws {
        let d = try D(), r = ReglagesEssai()
        let a = Self.appli(d, r)
        guard case .aReprendre(let p) = try await a.preparer(export: Self.exemple(.maillageZigbee)) else { throw Echec("deja repris") }
        #expect(p.plan.fichier("Zigbee/noms-pont.json") != nil)
        let existant = Data(#"{"version":1,"inconnu":true}"#.utf8)
        try d.ecrire("Zigbee/noms-pont.json", existant)
        let resultat = try await a.appliquer(p)
        // Le fichier apparu n'est pas ecrase a l'aveugle : le plan refait l'a lu et l'a laisse intact.
        let apres = try Self.octets(d, "Zigbee/noms-pont.json")
        #expect(apres == existant, "le fichier apparu (sans date de releve, donc illisible pour la fusion) est intact, `inconnu` compris")
        #expect(String(decoding: apres, as: UTF8.self).contains(#""inconnu":true"#))
        #expect(resultat.planRecalcule)
        #expect(resultat.nonPris.contains { $0.nature == .fichier("noms-pont.json") && $0.raison == .fichierExistantNonLisible },
                "il est cite parmi ce qui n'est pas repris")
        #expect(!resultat.fichiersEcrits.contains("Zigbee/noms-pont.json"))
    }

    @Test func unFichierModifiePendantLApplicationFaitToutDefaireEtRefaireLePlan() async throws {
        let d = try D(), r = ReglagesEssai()
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Prise 1"},"version":1}"#)
        let tire = OSAllocatedUnfairLock(initialState: false)
        let surnoms = d.url("surnoms.json")
        // L'app ecrit un surnom juste avant que l'application ne deplace surnoms.json.
        let ops = OperationsEssai(racine: d.racine) { _, nom in
            guard nom.hasPrefix("deplacer surnoms.json ->"), !tire.withLock({ let deja = $0; $0 = true; return deja }) else { return }
            try? Data(#"{"surnoms":{"thread:0000000000000001":"Prise 1","thread:rloc:0800":"Mon routeur"},"version":1}"#.utf8).write(to: surnoms)
        }
        let resultat = try Self.repris(await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)))
        #expect(resultat.planRecalcule)
        let obtenu = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(obtenu["thread:rloc:0800"] == "Mon routeur", "le surnom donne pendant l'application n'est pas perdu")
        #expect(obtenu["thread:0000000000000002"] == "Capteur 1")
        #expect(try Self.importes(d).count == 1)
    }

    @Test func unEtatQuiBougeATouteTentativeNeChangeRien() async throws {
        let d = try D(), r = ReglagesEssai()
        try d.ecrire("surnoms.json", #"{"surnoms":{"thread:0000000000000001":"Prise 1"},"version":1}"#)
        let compteur = OSAllocatedUnfairLock(initialState: 0)
        let surnoms = d.url("surnoms.json")
        let ops = OperationsEssai(racine: d.racine) { _, nom in
            guard nom.hasPrefix("deplacer surnoms.json ->") else { return }
            let k = compteur.withLock { $0 += 1; return $0 }
            try? Data(#"{"surnoms":{"thread:0000000000000001":"Prise 1","thread:rloc:0800":"Version \#(k)"},"version":1}"#.utf8).write(to: surnoms)
        }
        do {
            _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread))
            throw Echec("l'application aurait du renoncer")
        } catch let e as ErreurApplication {
            #expect(e == .etatInstable)
        }
        #expect(compteur.withLock { $0 } == ApplicationImport.tentatives)
        #expect(Set(try Self.arbre(d).keys) == ["surnoms.json"], "rien d'autre que le fichier de l'app, ni imports.json ni dossier de travail")
        let obtenu = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(obtenu["thread:rloc:0800"] == "Version 3", "la derniere ecriture de l'app est conservee")
        #expect(r.domaine().count == 0)
    }

    @Test func unExportModifieEntreLaPreparationEtLApplicationEstRefuse() async throws {
        let copie = try Copie(.maillageThread)
        let d = try D(), r = ReglagesEssai()
        let a = Self.appli(d, r)
        guard case .aReprendre(let p) = try await a.preparer(export: copie.dossier) else { throw Echec("deja repris") }
        // Un fichier change sans que le manifeste le sache.
        try Data("{}".utf8).write(to: copie.url("surnoms.json"))
        await #expect(throws: ErreurApplication.exportModifie) { try await a.appliquer(p) }
        // Un export refait avec un autre manifeste (meme identifiant, contenu different).
        try copie.remplacer("surnoms.json", par: Data("{}".utf8))
        await #expect(throws: ErreurApplication.exportModifie) { try await a.appliquer(p) }
        #expect(try Self.arbre(d).isEmpty && r.domaine().count == 0)
    }

    // MARK: Le retour en arriere ne defait que ce que l'import a ecrit

    /// Ce que l'app fait entre un arret et le lancement suivant : un surnom, une ligne de journal, un fichier cree par
    /// l'import qui grandit, un reglage. Rend les octets ecrits, pour verifier qu'ils sont toujours la.
    struct TravailDeLApp {
        let surnoms: Data
        let ligneDeJournal: Data
        let associations: Data
        static let hote = "MON-HOTE"
    }

    private static func travaillerCommeLApp(_ app: App, _ d: D, _ r: ReglagesEssai) throws -> TravailDeLApp {
        let prefixe = app.rawValue
        var o = try objet(d, "surnoms.json")
        var surnoms = try #require(o["surnoms"] as? [String: String])
        surnoms["\(prefixe):rloc:0800"] = "Mon routeur"
        o["surnoms"] = surnoms
        let surnomsOctets = try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
        try d.ecrire("surnoms.json", surnomsOctets)
        let journal = try octets(d, "Journal/journal-2026-10.jsonl") + Data("{\"ligne\":\"de Djoko\"}\n".utf8)
        try d.ecrire("Journal/journal-2026-10.jsonl", journal)
        let associations = try octets(d, "Thread/associations.json") + Data("\n".utf8)
        try d.ecrire("Thread/associations.json", associations)
        r.poser("thread.sondeHote", TravailDeLApp.hote)
        return TravailDeLApp(surnoms: surnomsOctets, ligneDeJournal: journal, associations: associations)
    }

    private static func verifierTravailConserve(_ t: TravailDeLApp, _ d: D, _ r: ReglagesEssai, _ contexte: String) throws {
        #expect(try octets(d, "surnoms.json") == t.surnoms, "\(contexte) : le surnom donne par l'app est perdu")
        #expect(try octets(d, "Journal/journal-2026-10.jsonl") == t.ligneDeJournal, "\(contexte) : la ligne de journal est perdue")
        #expect(try octets(d, "Thread/associations.json") == t.associations, "\(contexte) : le fichier cree puis modifie est perdu")
        #expect(r.objet("thread.sondeHote") as? String == TravailDeLApp.hote, "\(contexte) : le reglage de l'app est perdu")
    }

    /// Une application interrompue juste avant la validation : tous les fichiers du plan et tous les reglages sont en place.
    private static func interrompueAvantLaValidation(avecExistant: Bool) async throws -> (D, ReglagesEssai, avant: [String: String], prefsAvant: NSDictionary) {
        let m = try await modele(.maillageThread, avecExistant: avecExistant)
        let (d, r) = try await depart(.maillageThread, avecExistant: avecExistant)
        let (avant, prefsAvant) = (try arbre(d), r.domaine())
        await importArreteA(m.validation, .maillageThread, d, r)
        #expect(r.objet("thread.sondeHote") != nil, "les reglages sont ecrits")
        return (d, r, avant, prefsAvant)
    }

    @Test(arguments: [false, true])
    func cePuEcritL_AppApresUnArretNEstJamaisPerdu(avecExistant: Bool) async throws {
        let (d, r, avant, _) = try await Self.interrompueAvantLaValidation(avecExistant: avecExistant)
        let t = try Self.travaillerCommeLApp(.maillageThread, d, r)
        let issue = try await Self.appli(d, r).recuperer()
        try Self.verifierTravailConserve(t, d, r, "apres la reprise")
        // Ce que l'app a ecrit est cite, et l'original qu'elle a recouvert est garde a part.
        guard case .annuleeSauf(let laisses) = issue else { throw Echec("retour en arriere complet alors que l'app avait ecrit : \(issue)") }
        #expect(Set(laisses.fichiers) == ["surnoms.json", "Journal/journal-2026-10.jsonl", "Thread/associations.json"])
        #expect(laisses.reglages == ["thread.sondeHote"])
        if avecExistant {
            let conserve = d.url("\(ApplicationImport.nomConserve)/\(G.identifiant(.maillageThread).uuidString)/surnoms.json")
            #expect(try C.sha256(Data(contentsOf: conserve)) == avant["surnoms.json"], "l'original est garde")
        }
        #expect(try Self.arbre(d)["imports.json"] == avant["imports.json"], "imports.json est revenu a l'etat d'avant")
        #expect(try Self.arbre(d).keys.contains { $0.hasPrefix(ApplicationImport.nomTravail) } == false, "le dossier de travail est parti")
    }

    @Test(arguments: [false, true])
    func uneDoubleInterruptionLaisseUnEtatCoherent(avecExistant: Bool) async throws {
        // Combien d'operations compte une reprise complete ?
        let compte: Int
        do {
            let (d, r, _, _) = try await Self.interrompueAvantLaValidation(avecExistant: avecExistant)
            _ = try Self.travaillerCommeLApp(.maillageThread, d, r)
            let ops = OperationsEssai(racine: d.racine)
            _ = try await Self.appli(d, r, operations: ops).recuperer()
            compte = ops.compte
        }
        #expect(compte > 3)
        for k in 1...compte {
            let (d, r, avant, _) = try await Self.interrompueAvantLaValidation(avecExistant: avecExistant)
            let t = try Self.travaillerCommeLApp(.maillageThread, d, r)
            // La reprise s'arrete net a l'operation k...
            let ops = OperationsEssai(racine: d.racine, mode: .depuis(k))
            _ = try? await Self.appli(d, r, operations: ops).recuperer()
            try Self.verifierTravailConserve(t, d, r, "reprise arretee a l'operation \(k)")
            // ...et le lancement suivant l'acheve.
            _ = try await Self.appli(d, r).recuperer()
            try Self.verifierTravailConserve(t, d, r, "apres la reprise de la reprise \(k)")
            if avecExistant {
                let conserve = d.url("\(ApplicationImport.nomConserve)/\(G.identifiant(.maillageThread).uuidString)/surnoms.json")
                #expect(try C.sha256(Data(contentsOf: conserve)) == avant["surnoms.json"], "reprise \(k) : l'original est garde")
            }
            #expect(try Self.arbre(d)["imports.json"] == avant["imports.json"], "reprise \(k) : imports.json")
            #expect(try Self.arbre(d).keys.contains { $0.hasPrefix(ApplicationImport.nomTravail) } == false, "reprise \(k) : dossier de travail")
            #expect(try await Self.appli(d, r).recuperer() == .rienAFaire)
        }
    }

    @Test func unEchecDeLaValidationLaisseCeQueLAppAEcritEntretemps() async throws {
        let m = try await Self.modele(.maillageThread, avecExistant: true)
        let (d, r) = try await Self.depart(.maillageThread, avecExistant: true)
        let avant = try Self.arbre(d)
        let ajout = Data("\n".utf8)
        let ecrit = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let surnoms = d.url("surnoms.json")
        // L'app ajoute une ligne a un fichier deja mis en place, juste avant l'echange d'imports.json qui echoue.
        let validation = m.validation
        let ops = OperationsEssai(racine: d.racine, mode: .unique(validation)) { k, _ in
            guard k == validation, let actuel = try? Data(contentsOf: surnoms) else { return }
            try? (actuel + ajout).write(to: surnoms)
            ecrit.withLock { $0 = actuel + ajout }
        }
        do {
            _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread))
            throw Echec("l'application aurait du echouer")
        } catch let e as ErreurApplication {
            guard case .echecAvecReste(.validation, let laisses, _) = e else { throw Echec("\(e)") }
            #expect(laisses.fichiers == ["surnoms.json"] && laisses.reglages.isEmpty)
        }
        #expect(try Self.octets(d, "surnoms.json") == ecrit.withLock { $0 }, "la ligne de l'app est la")
        #expect(try Self.arbre(d)["imports.json"] == avant["imports.json"], "imports.json est revenu")
        let conserve = d.url("\(ApplicationImport.nomConserve)/\(G.identifiant(.maillageThread).uuidString)/surnoms.json")
        #expect(try C.sha256(Data(contentsOf: conserve)) == avant["surnoms.json"], "l'original est garde")
        #expect(try Self.arbre(d).keys.contains { $0.hasPrefix(ApplicationImport.nomTravail) } == false)
    }

    @Test func lesPreferencesDeLAppSontCellesDeSonIdentite() throws {
        // Un bundle d'essai avec une autre identite (celle de l'app de repetition).
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let info = ["CFBundleIdentifier": "fr.djoko.maillage.iot.repetition"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: dossier.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: dossier))
        #expect(bundle.bundleIdentifier == "fr.djoko.maillage.iot.repetition")
        let repetition = PreferencesUserDefaults.app(bundle: bundle)
        #expect(repetition.domaine == "fr.djoko.maillage.iot.repetition" && repetition.suite == nil)
        #expect(PreferencesUserDefaults.pourApp(identifiant: nil).domaine == "fr.djoko.maillage.iot", "sans identifiant, celui de l'app publiee")
        #expect(PreferencesUserDefaults.app.domaine == PreferencesUserDefaults.app(bundle: .main).domaine)
        #expect(PreferencesUserDefaults.app.domaine == (Bundle.main.bundleIdentifier ?? "fr.djoko.maillage.iot"))
    }

    @Test func unReglageQueLImportNAPasEcritNEstJamaisRetireApresUnEchec() async throws {
        let propre = try D(), rp = ReglagesEssai()
        let ops0 = OperationsEssai(racine: propre.racine)
        _ = try Self.repris(await Self.appli(propre, rp, operations: ops0).reprendre(export: Self.exemple(.maillageThread)))
        let n = try #require(ops0.journal.firstIndex { $0.hasPrefix("deplacer A:") }) + 1

        let d = try D(), r = ReglagesEssai()
        // Djoko pose un reglage que le plan comptait ecrire, au moment ou le premier fichier est deplace (et l'echec tombe).
        let ops = OperationsEssai(racine: d.racine, mode: .unique(n)) { k, _ in if k == n { r.poser("thread.sondeHote", "MON-HOTE") } }
        await #expect(throws: ErreurApplication.self) {
            try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread))
        }
        #expect(r.objet("thread.sondeHote") as? String == "MON-HOTE", "le reglage de Djoko n'a pas ete ecrit par l'import : il reste")
    }

    @Test func unReglageQueLImportNAPasEcritNEstJamaisRetireApresUnArret() async throws {
        let propre = try D(), rp = ReglagesEssai()
        let ops0 = OperationsEssai(racine: propre.racine)
        _ = try Self.repris(await Self.appli(propre, rp, operations: ops0).reprendre(export: Self.exemple(.maillageThread)))
        let n = try #require(ops0.journal.firstIndex { $0.hasPrefix("deplacer A:") }) + 1

        let d = try D(), r = ReglagesEssai()
        await Self.importArreteA(n, .maillageThread, d, r)
        r.poser("thread.sondeHote", "MON-HOTE")
        r.poser("zigbee.autre", 3)
        _ = try await Self.appli(d, r).recuperer()
        #expect(r.objet("thread.sondeHote") as? String == "MON-HOTE")
        #expect(r.objet("zigbee.autre") as? Int == 3)
    }

    @Test func unDossierDeDonneesAbsentNeResteJamaisVideApresUnArret() async throws {
        let m = try await Self.modele(.maillageThread, avecExistant: false)
        for n in 1...m.validation {
            let d = try D(), r = ReglagesEssai()
            try FileManager.default.removeItem(at: d.racine)
            let ops = OperationsEssai(racine: d.racine, mode: .depuis(n))
            do { _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)) } catch {}
            _ = try await Self.appli(d, r).recuperer()
            #expect(!FileManager.default.fileExists(atPath: d.racine.path), "arret a l'operation \(n) : le dossier cree est retire")
        }
    }

    @Test func unJournalAuxCheminsHorsDuDossierNeFaitRienHorsDuDossier() async throws {
        let id = UUID()
        for nom in ["remplaces", "crees", "dossiersCrees"] {
            let d = try D(), r = ReglagesEssai()
            let dehors = d.racine.deletingLastPathComponent().appendingPathComponent("dehors-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dehors) }
            let chemin = "../" + dehors.lastPathComponent
            var j = JournalApplication(identifiant: id, remplaces: [], crees: [], dossiersCrees: [], racineCreee: false, empreintes: [:],
                                       phase: .remplacement)
            switch nom {
            case "remplaces": j.remplaces = [chemin]
            case "crees": j.crees = [chemin]
            default: j.dossiersCrees = [chemin]
            }
            try d.ecrire("\(ApplicationImport.nomTravail)/journal.json", try C.encodeur().encode(j))
            // Une sauvegarde a l'endroit ou le chemin la ferait chercher, et un element hors du dossier a la cible.
            try FileManager.default.createDirectory(at: d.url("\(ApplicationImport.nomTravail)/\(ApplicationImport.nomSauvegarde)"),
                                                    withIntermediateDirectories: true)
            try d.ecrire("\(ApplicationImport.nomTravail)/\(dehors.lastPathComponent)", "sauvegarde")
            if nom == "dossiersCrees" {
                try FileManager.default.createDirectory(at: dehors, withIntermediateDirectories: true)
            } else {
                try Data("a moi".utf8).write(to: dehors)
            }
            let avant = try Self.arbre(d)
            await #expect(throws: ErreurApplication.self, "\(nom)") { try await Self.appli(d, r).recuperer() }
            #expect(FileManager.default.fileExists(atPath: dehors.path), "\(nom) : l'element hors du dossier est intact")
            if nom != "dossiersCrees" { #expect(try Data(contentsOf: dehors) == Data("a moi".utf8), "\(nom)") }
            #expect(try Self.arbre(d) == avant, "\(nom) : rien n'est touche dans le dossier non plus")
        }
    }

    @Test func enPhaseDePreparationLesDossiersDeLAppNeSontPasRetires() async throws {
        let propre = try D(), rp = ReglagesEssai()
        let ops0 = OperationsEssai(racine: propre.racine)
        _ = try Self.repris(await Self.appli(propre, rp, operations: ops0).reprendre(export: Self.exemple(.maillageThread)))
        // Arret au premier fichier d'attente : le journal est ecrit, rien n'est deplace.
        let n = try #require(ops0.journal.firstIndex { $0.hasPrefix("ecrire A:") }) + 1

        let d = try D(), r = ReglagesEssai()
        let ops = OperationsEssai(racine: d.racine, mode: .depuis(n))
        do { _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)) } catch {}
        // L'app tourne et cree ses dossiers (vides) entretemps.
        for dossier in ["Thread", "Journal"] { try FileManager.default.createDirectory(at: d.url(dossier), withIntermediateDirectories: true) }
        _ = try await Self.appli(d, r).recuperer()
        for dossier in ["Thread", "Journal"] {
            #expect(FileManager.default.fileExists(atPath: d.url(dossier).path), "\(dossier) est a l'app, pas a l'import")
        }
    }

    // MARK: Phase 4, tache 7 : reports de la tache 6

    /// Carry 6 : un changement d'etat PENDANT l'application, apres qu'un fichier a ete mis en place et que l'app l'a fait
    /// grandir : le retour en arriere laisse le travail de l'app, le plan est refait, et le resultat le cite (jamais en silence).
    @Test func unEtatQuiBougePendantLApplicationCiteCeQueLAppAEcritEntretemps() async throws {
        let (d, r) = try await Self.depart(.maillageThread, avecExistant: true)
        let journal = d.url("Journal/journal-2026-10.jsonl")
        let surnoms = d.url("surnoms.json")
        let tire = OSAllocatedUnfairLock(initialState: false)
        // Juste avant que surnoms.json ne soit deplace : l'app ajoute une ligne au journal deja mis en place, et change surnoms.json.
        let ops = OperationsEssai(racine: d.racine) { _, nom in
            guard nom.hasPrefix("deplacer surnoms.json ->"), !tire.withLock({ let deja = $0; $0 = true; return deja }) else { return }
            if let actuel = try? Data(contentsOf: journal) { try? (actuel + Data("{\"ligne\":\"de Djoko\"}\n".utf8)).write(to: journal) }
            try? Data(#"{"surnoms":{"thread:rloc:0800":"Mon routeur"},"version":1}"#.utf8).write(to: surnoms)
        }
        let resultat = try Self.repris(await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread)))
        #expect(resultat.planRecalcule)
        #expect(resultat.laisses.fichiers.contains("Journal/journal-2026-10.jsonl"), "ce que l'app a ecrit est cite : \(resultat.laisses)")
        #expect(try String(decoding: Self.octets(d, "Journal/journal-2026-10.jsonl"), as: UTF8.self).contains("de Djoko"), "la ligne de l'app est la")
        let obtenu = try #require(Self.objet(d, "surnoms.json")["surnoms"] as? [String: String])
        #expect(obtenu["thread:rloc:0800"] == "Mon routeur")
        let conserve = d.url("\(ApplicationImport.nomConserve)/\(G.identifiant(.maillageThread).uuidString)/Journal/journal-2026-10.jsonl")
        #expect(FileManager.default.fileExists(atPath: conserve.path), "l'original du journal est garde a part")
    }

    /// Idem quand l'etat bouge a chaque essai : l'erreur finale cite les elements laisses.
    @Test func unEtatInstableCiteCeQueLAppAEcritEntretemps() async throws {
        let (d, r) = try await Self.depart(.maillageThread, avecExistant: true)
        let journal = d.url("Journal/journal-2026-10.jsonl")
        let surnoms = d.url("surnoms.json")
        let compteur = OSAllocatedUnfairLock(initialState: 0)
        let ops = OperationsEssai(racine: d.racine) { _, nom in
            guard nom.hasPrefix("deplacer surnoms.json ->") else { return }
            let k = compteur.withLock { $0 += 1; return $0 }
            if let actuel = try? Data(contentsOf: journal) { try? (actuel + Data("{\"ligne\":\"\(k)\"}\n".utf8)).write(to: journal) }
            try? Data(#"{"surnoms":{"thread:rloc:0800":"Version \#(k)"},"version":1}"#.utf8).write(to: surnoms)
        }
        do {
            _ = try await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageThread))
            throw Echec("l'application aurait du renoncer")
        } catch let e as ErreurApplication {
            guard case .echecAvecReste(_, let laisses, _) = e else { throw Echec("erreur sans les elements laisses : \(e)") }
            #expect(laisses.fichiers.contains("Journal/journal-2026-10.jsonl"))
        }
    }

    /// Carry 1 : la recuperation du lancement est synchrone (elle precede la construction des modules, qui lisent le dossier
    /// des l'init) et fait la meme chose que `recuperer()`.
    @Test func laRecuperationDuLancementEstSynchroneEtDefaitUneApplicationInterrompue() async throws {
        let (d, r, avant, _) = try await Self.interrompueAvantLaValidation(avecExistant: true)
        let a = Self.appli(d, r)
        let issue = a.recupererAuLancement()
        #expect(issue == .success(.annulee))
        #expect(try Self.arbre(d) == avant)
        #expect(a.recupererAuLancement() == .success(.rienAFaire))
        let (d2, r2) = try (D(), ReglagesEssai())
        try FileManager.default.createDirectory(at: d2.url(ApplicationImport.nomTravail), withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: d2.url("\(ApplicationImport.nomTravail)/journal.json"))
        guard case .failure(.recuperationImpossible) = Self.appli(d2, r2).recupererAuLancement() else {
            throw Echec("un journal illisible doit etre rendu, pas efface")
        }
        #expect(FileManager.default.fileExists(atPath: d2.url("\(ApplicationImport.nomTravail)/journal.json").path))
    }

    // MARK: Hors du fil principal

    @MainActor
    @Test func lApplicationNeTourneJamaisSurLeFilPrincipal() async throws {
        let d = try D(), r = ReglagesEssai()
        let ops = OperationsEssai(racine: d.racine)
        _ = try Self.repris(await Self.appli(d, r, operations: ops).reprendre(export: Self.exemple(.maillageZigbee)))
        MainActor.assertIsolated("le test est sur le fil principal")
        #expect(ops.compte > 10)
        #expect(ops.surLeFilPrincipal.allSatisfy { !$0 }, "aucune operation sur le fil principal")
    }
}
