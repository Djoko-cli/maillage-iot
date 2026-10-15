import Foundation
@testable import MaillageCoeur
@testable import ProtocoleThread
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Journal et historique de la sonde dans l'app")
struct JournalMaillageTests {
    /// Un appareil Matter du releve de la demo : son ExtMac est son nom d'hote.
    static let appareil = "56B1E064401F74EF"

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
    }

    /// Mode direct sans ecoute, avec les 12 premiers releves de la panne rejouee (instantane,
    /// appareils) ; journal et historique dans `dossier`.
    static func surveillance(_ mode: Surveillance.Mode = .direct, dossier: URL?) -> Surveillance {
        let s = Surveillance(mode: mode, dossier: dossier)
        for a in ScenarioPanne.releves.prefix(12) { s.thread.integrer(a) }
        return s
    }

    /// Maillage de la partition principale (valeurs inventees) : les routeurs 1 (chef, d'ExtMac `extMac1`) et 5, qui ne
    /// sont pas dans l'instantane ; l'appareil, enfant de `parent`.
    static func maillage(_ s: Surveillance, _ date: Date, parent: Int, extMac1: String? = nil) throws -> Maillage {
        var c = ConstructionMaillage(date: date, partition: try #require(s.thread.reseau?.principale?.id))
        c.routeurs(Route64(sequence: 1, routes: [1, 5].map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: 1)
        if let x = extMac1 { c.identite(x, routeur: 1) }
        c.lien(1, 5, sortante: 3, entrante: 2)
        c.enfant(EnfantMaillage(rloc16: UInt16(parent) << 10 | 2, extMac: Self.appareil, qualite: 3, source: .tableEnfants))
        c.signal(SignalSonde(routeur: 1, rssi: -61))
        return c.maillage()
    }

    /// Changement de parent de l'appareil : au journal (en memoire et sur disque), sous son id et son
    /// nom du graphe, avec le nom des deux routeurs ; chaque tournee a son releve dans
    /// `maillage-AAAA-MM.jsonl`, relu par un nouveau lancement.
    @Test func journalEtHistoriqueSurDisque() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Self.surveillance(dossier: dossier)
        // Des secondes entieres : le fichier garde les dates a la milliseconde.
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        s.thread.recevoir(try Self.maillage(s, t, parent: 1), a: t.addingTimeInterval(1))
        s.thread.recevoir(try Self.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(301))
        let e = try #require(s.evenements.last)
        #expect(e.type == .parentChange)
        let a = try #require(s.thread.appareil(Self.appareil))
        #expect(e.sujet == Sujet(id: Self.appareil, nom: s.thread.nom(a)))
        #expect(e.avant == String(localized: "Routeur · \("0400")") && e.apres == String(localized: "Routeur · \("1400")"))
        #expect(try JournalFichiers(dossier: dossier.appendingPathComponent("Journal"), politique: Surveillance.politiqueJournal).lire().last == e)
        #expect(s.thread.historique.map(\.date) == [t, t.addingTimeInterval(300)])
        let thread = Surveillance.dossierThread(dossier)
        let fichier = thread.appendingPathComponent(HistoriqueFichiers(dossier: thread).nomFichier(t.addingTimeInterval(300)))
        #expect(FileManager.default.fileExists(atPath: fichier.path))
        let relu = Surveillance(mode: .direct, dossier: dossier)
        await relu.thread.chargerHistorique()
        #expect(relu.thread.historique == s.thread.historique)
    }

    /// Relecture de l'historique avec des releves deja en memoire : le releve d'un lancement
    /// precedent est relu ; celui recu depuis (sa date est tronquee a la milliseconde sur le disque)
    /// n'est pas repris en double ; le fichier d'un mois fini depuis plus de 90 jours est supprime.
    @Test func chargementFusionneSansDoublon() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        let a = Self.surveillance(dossier: dossier)
        a.thread.recevoir(try Self.maillage(a, t, parent: 1), a: t.addingTimeInterval(1))
        // Sous la milliseconde : la copie du disque est a t + 300.000, celle de la memoire a t + 300.0004.
        let tard = t.addingTimeInterval(300.0004)
        let b = Self.surveillance(dossier: dossier)
        b.thread.recevoir(try Self.maillage(b, tard, parent: 1), a: t.addingTimeInterval(301))
        let ancien = Surveillance.dossierThread(dossier).appendingPathComponent("maillage-2020-01.jsonl")
        FileManager.default.createFile(atPath: ancien.path, contents: Data())
        await b.thread.chargerHistorique()
        #expect(b.thread.historique.map(\.date) == [t, tard], "relu sans doublon, sans sa copie du disque")
        #expect(!FileManager.default.fileExists(atPath: ancien.path), "mois fini depuis plus de 90 jours")
    }

    /// Appareil vu deux fois (la resolution ancienne sous un routeur muet, et la table de son nouveau
    /// parent) : le journal le nomme comme l'appareil, sous son nouveau parent, meme si le graphe
    /// donne son id a l'entree de la resolution (le premier RLOC16).
    @Test func appareilVuDeuxFois() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        s.thread.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        var c = ConstructionMaillage(date: t.addingTimeInterval(300), partition: try #require(s.thread.reseau?.principale?.id))
        c.routeurs(Route64(sequence: 1, routes: [1, 5].map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: 1)
        c.muet(1)
        c.enfant(EnfantMaillage(rloc16: 0x0405, extMac: Self.appareil, source: .resolution))
        c.enfant(EnfantMaillage(rloc16: 0x1402, extMac: Self.appareil, qualite: 2, source: .tableEnfants))
        s.thread.recevoir(c.maillage(), a: t.addingTimeInterval(300))
        let e = try #require(s.evenements.last)
        #expect(e.type == .parentChange && e.sujet?.id == Self.appareil)
        #expect(e.apres == String(localized: "Routeur · \("1400")"))
    }

    /// Enfant que le graphe ne rapproche d'aucun appareil : son id de sujet est « rloc:XXXX », qui
    /// change avec son parent. Sa fiche montre tous ses changements de parent, pas seulement ceux
    /// de son RLOC16 du moment : l'ExtMac, dans les details, les relie.
    @Test func ficheDUnEnfantSansAppareil() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        let inconnu = "E0000000000000B1"
        let maillage = { (date: Date, parent: Int) throws -> Maillage in
            var c = ConstructionMaillage(date: date, partition: try #require(s.thread.reseau?.principale?.id))
            c.routeurs(Route64(sequence: 1, routes: [1, 5].map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                       chef: 1)
            c.enfant(EnfantMaillage(rloc16: UInt16(parent) << 10 | 2, extMac: inconnu, qualite: 3, source: .tableEnfants))
            return c.maillage()
        }
        // Sous 1, puis sous 5, puis sous 1 : deux changements, sous deux ids de sujet.
        for (minutes, parent) in [(0.0, 1), (5, 5), (10, 1)] {
            s.thread.recevoir(try maillage(t.addingTimeInterval(minutes * 60), parent), a: t.addingTimeInterval(minutes * 60))
        }
        let changements = s.evenements.filter { $0.type == .parentChange }
        #expect(changements.count == 2)
        #expect(changements.allSatisfy { $0.sujet?.id.hasPrefix("rloc:") == true && $0.details["extMac"] == inconnu },
                "aucun appareil : id « rloc: », ExtMac dans les details")
        #expect(Set(changements.compactMap(\.sujet?.id)).count == 2, "l'id du sujet change avec le parent")
        let noeud = String(format: "rloc:%04X", UInt16(1 << 10 | 2))
        #expect(s.evenements(de: idt(noeud)) == changements.reversed(), "tous ses changements, le plus recent d'abord")
        #expect(s.evenements(de: idt("rloc:ABCD")).isEmpty)
    }

    /// Une purge qui echoue (vieux fichier dans un dossier sans droit d'ecriture) n'empeche ni la
    /// lecture du journal ni celle de l'historique.
    @Test func purgeEnEchecNeBloquePasLaLecture() async throws {
        let dossier = Self.dossier()
        let journalDossier = dossier.appendingPathComponent("Journal")
        let thread = Surveillance.dossierThread(dossier)
        defer {
            for d in [journalDossier, thread, dossier] { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path) }
            try? FileManager.default.removeItem(at: dossier)
        }
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        let e = Evenement(date: t, type: .veille)
        try JournalFichiers(dossier: journalDossier, politique: Surveillance.politiqueJournal).ajouter([e])
        let r = ReleveMaillage(try Self.maillage(Self.surveillance(dossier: nil), t, parent: 1))
        try HistoriqueFichiers(dossier: thread).ajouter(r)
        FileManager.default.createFile(atPath: journalDossier.appendingPathComponent("journal-2020-01.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: thread.appendingPathComponent("maillage-2020-01.jsonl").path, contents: Data())
        for d in [journalDossier, thread, dossier] { try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.chargerJournal()
        #expect(s.erreurJournal == nil)
        #expect(s.evenements == [e])
        await s.thread.chargerHistorique()
        #expect(s.thread.historique == [r])
        #expect(FileManager.default.fileExists(atPath: journalDossier.appendingPathComponent("journal-2020-01.jsonl").path),
                "la purge a bien echoue")
    }

    /// Les fichiers sont purges quand le mois change pendant que l'app tourne (elle peut durer des
    /// semaines), pas a chaque tournee : deux tournees du meme mois ne purgent pas ; la premiere d'un
    /// autre mois purge le journal et l'historique. Ni en demo, ni sans dossier.
    @Test func purgeAuChangementDeMois() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Self.surveillance(dossier: dossier)
        s.chargerJournal()
        await s.thread.chargerHistorique()
        let anciens = [dossier.appendingPathComponent("Journal/journal-2020-01.jsonl"),
                       Surveillance.dossierThread(dossier).appendingPathComponent("maillage-2020-01.jsonl")]
        func creer() {
            try? FileManager.default.createDirectory(at: Surveillance.dossierThread(dossier), withIntermediateDirectories: true)
            for u in anciens { FileManager.default.createFile(atPath: u.path, contents: Data()) }
        }
        func presents() -> [Bool] { anciens.map { FileManager.default.fileExists(atPath: $0.path) } }
        let t = Date()
        creer()
        s.thread.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        #expect(presents() == [true, true], "meme mois que la derniere purge (celle du chargement)")
        // Un mois plus tard au moins : 45 jours.
        let plus = t.addingTimeInterval(45 * 24 * 3600)
        s.thread.recevoir(try Self.maillage(s, plus, parent: 1), a: plus)
        #expect(presents() == [false, false], "mois change : journal et historique purges")
        creer()
        s.thread.recevoir(try Self.maillage(s, plus.addingTimeInterval(300), parent: 1), a: plus.addingTimeInterval(300))
        #expect(presents() == [true, true], "une fois par mois")
        // Demo : rien n'est ecrit ni purge.
        let demo = Self.surveillance(.demo, dossier: dossier)
        demo.thread.recevoir(try Self.maillage(demo, plus, parent: 1), a: plus.addingTimeInterval(90 * 24 * 3600))
        #expect(presents() == [true, true])
    }

    /// Demo : ni releve en memoire, ni fichier, meme avec un dossier ; le journal du maillage reste
    /// en memoire. Direct sans dossier : l'historique en memoire seulement.
    @Test func rienSurDisqueEnDemo() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let demo = Self.surveillance(.demo, dossier: dossier)
        let t = Date()
        demo.thread.recevoir(try Self.maillage(demo, t, parent: 1), a: t)
        demo.thread.recevoir(try Self.maillage(demo, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        #expect(demo.thread.historique.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dossier.path))
        #expect(demo.evenements.last?.type == .parentChange)
        let memoire = Self.surveillance(dossier: nil)
        memoire.thread.recevoir(try Self.maillage(memoire, t, parent: 1), a: t)
        #expect(memoire.thread.historique.count == 1)
    }

    /// Sonde oubliee : le maillage suivant est un point de depart (pas de « a change de parent »
    /// calcule par-dessus l'oubli) ; l'historique en memoire reste.
    @Test func oubliRepartDeZero() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        s.thread.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        s.thread.oublierMaillage()
        let avant = s.evenements.count
        s.thread.recevoir(try Self.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        #expect(s.evenements.count == avant, "point de depart")
        #expect(s.thread.historique.count == 2)
    }

    /// L'historique en memoire garde 30 jours, comptes depuis la reception du dernier maillage.
    @Test func trenteJoursEnMemoire() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        let vieux = t.addingTimeInterval(-Surveillance.dureeHistorique - 60)
        s.thread.recevoir(try Self.maillage(s, vieux, parent: 1), a: vieux)
        s.thread.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        #expect(s.thread.historique.map(\.date) == [t])
    }
}
