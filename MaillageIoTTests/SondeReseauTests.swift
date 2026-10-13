import AppKit
import Foundation
import MaillageCoeur
import Synchronization
import SwiftUI
import Testing
@testable import MaillageIoT

/// Canal dont chaque reponse n'arrive qu'apres `delai` : par le reseau, celle qui repond au
/// renvoi de 4 s du canal reseau.
final class CanalLent: CanalSonde {
    let delai: Duration
    private let repondre: @Sendable (String) -> [String]
    private let suite = Mutex<AsyncStream<Data>.Continuation?>(nil)

    init(delai: Duration, repondre: @escaping @Sendable (String) -> [String]) {
        self.delai = delai
        self.repondre = repondre
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (flux, s) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        suite.withLock { $0 = s }
        return flux
    }

    func envoyer(_ ligne: String) {
        let lignes = repondre(ligne), delai = delai
        Task { [self] in
            try? await Task.sleep(for: delai)
            suite.withLock { s in
                for l in lignes { s?.yield(Data(l.utf8)) }
            }
        }
    }

    func fermer() {
        suite.withLock { s in
            s?.finish()
            s = nil
        }
    }
}

/// Trousseau en memoire qui peut refuser d'effacer ou de ranger (trousseau verrouille, acces
/// refuse).
final class TrousseauRetif: TrousseauCles {
    static let refus = ErreurTrousseau.systeme(-25308)  // errSecInteractionNotAllowed
    let memoire = TrousseauMemoire()
    let refuserOubli = Mutex(true)
    let refuserRangement = Mutex(false)

    func lister() -> [SondeConnue] { memoire.lister() }
    func lire(nom: String) throws -> Data { try memoire.lire(nom: nom) }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        if refuserRangement.withLock({ $0 }) { throw Self.refus }
        try memoire.ranger(nom: nom, cle: cle, empreinte: empreinte)
    }

    func oublier(nom: String) throws {
        if refuserOubli.withLock({ $0 }) { throw Self.refus }
        try memoire.oublier(nom: nom)
    }
}

/// Trousseau en memoire qui note chaque lecture de cle et chaque ecriture, dans l'ordre, et si
/// elle s'est faite sur le fil principal : macOS peut d'abord y afficher une autorisation
/// modale (signature ad hoc), qui figerait le menu.
final class TrousseauTemoin: TrousseauCles {
    let memoire = TrousseauMemoire()
    /// « lire NOM », « ranger NOM » ou « oublier NOM », et le fil de l'operation.
    let operations = Mutex<[(nom: String, filPrincipal: Bool)]>([])

    func lister() -> [SondeConnue] { memoire.lister() }

    func lire(nom: String) throws -> Data {
        noter("lire \(nom)")
        return try memoire.lire(nom: nom)
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        noter("ranger \(nom)")
        try memoire.ranger(nom: nom, cle: cle, empreinte: empreinte)
    }

    func oublier(nom: String) throws {
        noter("oublier \(nom)")
        try memoire.oublier(nom: nom)
    }

    private func noter(_ operation: String) {
        let principal = Thread.isMainThread
        operations.withLock { $0.append((operation, principal)) }
    }
}

/// Trousseau en memoire dont chaque effacement attend que le test le libere, comme derriere une
/// autorisation modale du trousseau.
final class TrousseauLent: TrousseauCles {
    let memoire = TrousseauMemoire()
    /// Un effacement a commence.
    let effacementCommence = Mutex(false)
    private let feu = DispatchSemaphore(value: 0)

    func lister() -> [SondeConnue] { memoire.lister() }
    func lire(nom: String) throws -> Data { try memoire.lire(nom: nom) }
    func ranger(nom: String, cle: Data, empreinte: String) throws { try memoire.ranger(nom: nom, cle: cle, empreinte: empreinte) }

    func oublier(nom: String) throws {
        effacementCommence.withLock { $0 = true }
        feu.wait()
        try memoire.oublier(nom: nom)
    }

    /// Laisse passer un effacement (en cours, ou le prochain).
    func liberer() { feu.signal() }
}

/// Ouvertures de la liaison reseau demandees par `SondeMaillage` : nom d'hote et cle, et le
/// canal rendu (ou l'erreur) a chaque essai. Aucun trafic reseau.
@MainActor
final class ReseauFactice {
    private(set) var appels: [(hote: String, cle: Data)] = []
    /// Reponse de chaque essai, dans l'ordre ; au-dela, la derniere.
    var reponses: [Result<any CanalSonde, any Error>]

    init(_ reponses: [Result<any CanalSonde, any Error>]) {
        self.reponses = reponses
    }

    func ouvrir(_ hote: String, _ cle: Data) throws -> any CanalSonde {
        appels.append((hote, cle))
        let r = reponses.count > 1 ? reponses.removeFirst() : reponses[0]
        return try r.get()
    }
}

/// Acces a la sonde par le reseau Thread dans l'app : cle par l'USB, choix de la liaison,
/// connexion et reprise. Trousseau en memoire, reseau factice. Chaque test borne a une minute.
@MainActor
@Suite("Sonde par le reseau Thread : cle, liaison, reprise", .timeLimit(.minutes(1)))
struct SondeReseauTests {
    static let hote = "0123456789ABCDEF"
    static let port = SondeMaillageTests.port

    /// bonjour du firmware 1.0.2 (valeurs inventees), avec ou sans nom d'hote.
    static func bonjour(hote: String? = SondeReseauTests.hote) -> String {
        let h = hote.map { "\"\($0)\"" } ?? "null"
        return #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.2","nom":"SONDE-01","mac":"A00000000001","appairee":true,"code":"12345678901","qr":"MT:ABCDEFGHIJ0123456789","hote":\#(h)}"#
    }

    /// Reponses d'une sonde 1.0.2 : bonjour, etat (detachee : tournee sans requete), cle nouvelle.
    static func reponses(bonjour: String = SondeReseauTests.bonjour(), cle: @escaping @Sendable (Int) -> [String]
                         = { [CleReseauTests.reponse($0)] }) -> @Sendable (String) -> [String] {
        { l in
            if l == "bonjour\n" { return [bonjour] }
            if l == "etat\n" { return [CanalRejoue.etatDetache] }
            if l.hasPrefix("cle nouvelle ") {
                return cle(Int(l.trimmingCharacters(in: .newlines).split(separator: " ").last ?? "") ?? 0)
            }
            return []
        }
    }

    static func sonde(bonjour: String = SondeReseauTests.bonjour(), cle: @escaping @Sendable (Int) -> [String]
                      = { [CleReseauTests.reponse($0)] }) -> CanalRejoue {
        CanalRejoue(repondre: reponses(bonjour: bonjour, cle: cle))
    }

    static func sondeMaillage(_ p: UserDefaults, usb: @escaping (String) -> any CanalSonde = { _ in sonde() },
                              trousseau: any TrousseauCles, reseau: ReseauFactice? = nil,
                              delais: [Duration] = [.milliseconds(20)]) -> SondeMaillage {
        SondeMaillage(preferences: p, actif: true, ouvrirCanal: usb, trousseau: trousseau,
                      ouvrirReseau: { h, c in
                          guard let reseau else { throw ErreurReseau.autre("pas de reseau dans ce test") }
                          return try reseau.ouvrir(h, c)
                      },
                      delaisReprise: delais)
    }

    /// Sonde retenue avec sa cle, prete pour le reseau (comme apres « Autoriser l'acces reseau »).
    static func prete(_ p: UserDefaults, liaison: SondeMaillage.Liaison) throws -> TrousseauMemoire {
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        p.set(hote, forKey: SondeMaillage.cleHote)
        p.set(liaison.rawValue, forKey: SondeMaillage.cleLiaison)
        let t = TrousseauMemoire()
        try t.ranger(nom: hote, cle: VecteursH1.psk, empreinte: "630DCD29")
        return t
    }

    /// Connectee par l'USB, la sonde retenue donne son nom d'hote ; « Autoriser » cree la cle,
    /// la verifie et la range dans le trousseau sous ce nom. Rien de la cle dans les preferences.
    @Test func autoriser() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauMemoire()
        let s = Self.sondeMaillage(p, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        #expect(s.hote == Self.hote)
        #expect(p.string(forKey: SondeMaillage.cleHote) == Self.hote)
        #expect(s.empreinteAcces == nil && !s.reseauDisponible)
        #expect(s.peutAutoriser)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == nil)
        #expect(try t.lire(nom: Self.hote) == VecteursH1.psk)
        #expect(s.empreinteAcces == "630DCD29")
        #expect(s.reseauDisponible)
        #expect(!s.autorisationEnCours)
        let valeurs = (p.persistentDomain(forName: domaine) ?? [:]).values.map { "\($0)" }
        #expect(!valeurs.contains { $0.contains(CleReseauTests.hexaCle) }, "cle hors des preferences")
        await s.oublier()
    }

    /// Sans nom d'hote (Matter ne l'a pas encore enregistre), aucune cle n'est demandee.
    @Test func autoriserSansNomDHote() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauMemoire()
        let canal = Self.sonde(bonjour: Self.bonjour(hote: nil))
        let s = Self.sondeMaillage(p, usb: { _ in canal }, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == CleReseau.Erreur.sansNomDHote.localizedDescription)
        #expect(!canal.envoyes.contains { $0.hasPrefix("cle") })
        #expect(t.lister().isEmpty)
        await s.oublier()
    }

    /// Empreinte fausse, ou refus d'un firmware sans acces reseau : rien n'est range.
    @Test func autoriserEnEchec() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauMemoire()
        var canaux = 0
        let s = Self.sondeMaillage(p, usb: { _ in
            canaux += 1
            return canaux == 1
                ? Self.sonde(cle: { [CleReseauTests.reponse($0, empreinte: "00000000")] })
                : Self.sonde(cle: { _ in [#"{"v":1,"t":"erreur","erreur":"commande inconnue"}"#] })
        }, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == CleReseau.Erreur.empreinteIncoherente.localizedDescription)
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == SondeUSB.Erreur.refusee("commande inconnue").localizedDescription)
        #expect(t.lister().isEmpty)
        #expect(s.empreinteAcces == nil)
        await s.oublier()
    }

    /// Apres une nouvelle mise en service, le nom d'hote a change : la cle se range sous le nouveau
    /// nom, l'entree de l'ancien est retiree du trousseau (une seule sonde retenue).
    @Test func autoriserRetireLAncienneEntree() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauMemoire()
        try t.ranger(nom: "FEDCBA9876543210", cle: Data(repeating: 1, count: 32), empreinte: "11111111")
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("FEDCBA9876543210", forKey: SondeMaillage.cleHote)
        let s = Self.sondeMaillage(p, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        #expect(s.hote == Self.hote, "nom d'hote du bonjour")
        await s.autoriserAccesReseau()
        let noms = t.lister().map { $0.nom }
        #expect(noms == [Self.hote])
        await s.oublier()
    }

    /// L'ancienne entree ne s'efface pas : la nouvelle cle est rangee, l'echec est montre.
    @Test func autoriserAncienneCleNonRetiree() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauRetif()
        try t.ranger(nom: "FEDCBA9876543210", cle: Data(repeating: 1, count: 32), empreinte: "11111111")
        let s = Self.sondeMaillage(p, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.empreinteAcces == "630DCD29" && s.reseauDisponible)
        #expect(s.erreurAcces == String(localized: "Clé rangée ; l'ancienne clé de \("FEDCBA9876543210").local n'a pas pu être retirée du trousseau : \(TrousseauRetif.refus.localizedDescription)"))
        t.refuserOubli.withLock { $0 = false }
        await s.oublier()
    }

    /// « Oublier la sonde » quand le trousseau refuse d'effacer la cle : l'echec est montre, le nom
    /// d'hote reste (la cle aussi) ; relance une fois le trousseau d'accord, tout part.
    @Test func oublierSansEffacerLaCle() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        _ = try Self.prete(p, liaison: .usb)
        let t = TrousseauRetif()
        try t.ranger(nom: Self.hote, cle: VecteursH1.psk, empreinte: "630DCD29")
        let s = Self.sondeMaillage(p, trousseau: t)
        await s.oublier()
        #expect(s.etat == .sansSonde && s.serie == nil && s.liaison == .usb)
        #expect(s.hote == Self.hote && s.empreinteAcces == "630DCD29", "nom d'hote garde : la cle est toujours la")
        #expect(p.string(forKey: SondeMaillage.cleHote) == Self.hote)
        #expect(s.erreurAcces == String(localized: "Clé de \(Self.hote).local non retirée du trousseau : \(TrousseauRetif.refus.localizedDescription)"))
        t.refuserOubli.withLock { $0 = false }
        await s.oublier()
        #expect(s.hote == nil && s.empreinteAcces == nil && s.erreurAcces == nil)
        #expect(t.lister().isEmpty)
    }

    /// Le trousseau refuse de ranger la cle : l'echec est montre, pas d'acces reseau.
    @Test func autoriserCleNonRangee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauRetif()
        t.refuserRangement.withLock { $0 = true }
        let s = Self.sondeMaillage(p, trousseau: t)
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == TrousseauRetif.refus.localizedDescription)
        #expect(t.lister().isEmpty)
        #expect(s.empreinteAcces == nil && !s.reseauDisponible)
        #expect(!s.autorisationEnCours)
        t.refuserOubli.withLock { $0 = false }
        await s.oublier()
    }

    /// Lecture de la cle et ecritures du trousseau (ranger la cle, retirer l'ancienne, oublier
    /// la sonde) hors du fil principal : macOS peut d'abord demander l'autorisation d'acceder au
    /// trousseau (fenetre modale, signature ad hoc), qui figerait le menu.
    @Test(.timeLimit(.minutes(1))) func trousseauHorsDuFilPrincipal() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = TrousseauTemoin()
        try t.memoire.ranger(nom: "FEDCBA9876543210", cle: Data(repeating: 1, count: 32), empreinte: "11111111")
        let s = Self.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([.success(Self.sonde())]))
        await s.connecter(Self.port, choisi: true)
        await s.autoriserAccesReseau()
        #expect(s.erreurAcces == nil && s.reseauDisponible)
        s.choisirLiaison(.reseau)
        await SondeMaillageTests.attendre { SondeMaillageTests.connectee(s) }
        await s.oublier()
        #expect(t.lister().isEmpty && s.hote == nil && s.erreurAcces == nil)
        let operations = t.operations.withLock { $0 }
        #expect(operations.map(\.nom) == ["ranger \(Self.hote)", "oublier FEDCBA9876543210", "lire \(Self.hote)",
                                          "oublier \(Self.hote)"])
        let principal = operations.filter(\.filPrincipal).map(\.nom)
        #expect(principal.isEmpty, "sur le fil principal : \(principal)")
    }

    /// « Oublier la sonde » : l'etat change tout de suite ; pendant l'effacement de la cle
    /// (autorisation modale du trousseau), la sonde choisie de nouveau donne un autre nom d'hote
    /// (nouvelle mise en service) : l'oubli, fini ensuite, ne le retire pas.
    @Test(.timeLimit(.minutes(1))) func nouveauNomDHotePendantLOubli() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        _ = try Self.prete(p, liaison: .usb)
        let t = TrousseauLent()
        try t.memoire.ranger(nom: Self.hote, cle: VecteursH1.psk, empreinte: "630DCD29")
        let nouveau = "FEDCBA9876543210"
        let s = Self.sondeMaillage(p, usb: { _ in Self.sonde(bonjour: Self.bonjour(hote: nouveau)) }, trousseau: t)
        let oubli = Task { await s.oublier() }
        #expect(await Self.sonder { t.effacementCommence.withLock { $0 } })
        #expect(s.etat == .sansSonde && s.serie == nil && s.liaison == .usb)
        await s.connecter(Self.port, choisi: true)
        #expect(s.hote == nouveau)
        t.liberer()
        await oubli.value
        #expect(t.lister().isEmpty, "cle de l'ancien nom d'hote effacee")
        #expect(s.hote == nouveau && p.string(forKey: SondeMaillage.cleHote) == nouveau)
        #expect(s.erreurAcces == nil)
        t.liberer()
        await s.oublier()
    }

    /// Nom d'hote de la reponse `cle` nul ou vide : la cle se range sous celui du `bonjour`.
    @Test func cleSansNomDHote() async throws {
        for h in [nil, ""] as [String?] {
            let (p, domaine) = try SondeMaillageTests.preferences()
            defer { p.removePersistentDomain(forName: domaine) }
            let t = TrousseauMemoire()
            let s = Self.sondeMaillage(p, usb: { _ in Self.sonde(cle: { [CleReseauTests.reponse($0, hote: h)] }) }, trousseau: t)
            await s.connecter(Self.port, choisi: true)
            await s.autoriserAccesReseau()
            let noms = t.lister().map { $0.nom }
            #expect(noms == [Self.hote], "cle.hote \(String(describing: h))")
            #expect(s.hote == Self.hote)
            await s.oublier()
        }
    }

    /// Pendant une tournee, pas de demande de cle : une ligne `erreur` sans id lui serait attribuee.
    @Test(.timeLimit(.minutes(1))) func pasDeCleNouvellePendantUneTournee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let bonjour = Self.bonjour()
        // Sonde attachee dont la liste des routeurs ne revient que quand le test la rend.
        let canal = CanalRejoue { l in
            journal.noter(l.trimmingCharacters(in: .newlines))
            if l == "bonjour\n" { return [bonjour] }
            if l.hasPrefix("diag 0000 5,6 ") { return [] }
            if l.hasPrefix("cle nouvelle ") { return [CleReseauTests.reponse(Int(l.split(separator: " ").last?.dropLast() ?? "") ?? 0)] }
            return CanalRejoue.reseauMinimal(l)
        }
        let s = Self.sondeMaillage(p, usb: { _ in canal }, trousseau: TrousseauMemoire())
        await s.connecter(Self.port, choisi: true)
        await journal.attendre(SondeMaillageTests.listeRetenue)
        #expect(s.tourneeEnCours)
        #expect(!s.peutAutoriser)
        await s.autoriserAccesReseau()
        #expect(!canal.envoyes.contains { $0.hasPrefix("cle") }, "aucune demande de cle")
        canal.emettre(CanalRejoue.reseauMinimal(SondeMaillageTests.listeRetenue + "\n"))
        await SondeMaillageTests.attendre { !s.tourneeEnCours }
        #expect(s.peutAutoriser, "apres la tournee")
        await s.oublier()
    }

    /// Liaison USB : `connecterReseau` ne ferme rien et ne touche pas a l'etat.
    @Test func connecterReseauEnUSBNeFermeRien() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .usb)
        let journal = JournalCanaux()
        let reseau = ReseauFactice([.success(Self.sonde())])
        let s = Self.sondeMaillage(p, usb: { _ in CanalTemoin("usb", journal: journal) }, trousseau: t, reseau: reseau)
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connecteeParUSB(s))
        await s.connecterReseau()
        #expect(Self.connecteeParUSB(s), "rien de ferme : \(s.etat)")
        #expect(journal.cycle == ["ouvrir usb"])
        #expect(reseau.appels.isEmpty)
        await s.oublier()
    }

    /// Sans cle pour la sonde retenue, le reseau ne se choisit pas.
    @Test func reseauSansCle() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let reseau = ReseauFactice([.success(Self.sonde())])
        let s = Self.sondeMaillage(p, trousseau: TrousseauMemoire(), reseau: reseau)
        await s.connecter(Self.port, choisi: true)
        s.choisirLiaison(.reseau)
        #expect(s.liaison == .usb)
        #expect(Self.connecteeParUSB(s))
        await Task.yield()
        #expect(reseau.appels.isEmpty)
        await s.oublier()
    }

    static func connecteeParUSB(_ s: SondeMaillage) -> Bool {
        s.liaison == .usb && SondeMaillageTests.connectee(s)
    }

    /// Attend une condition qui n'est pas observable (canal, reseau factice), au plus `delai` ;
    /// rend la condition.
    static func sonder(delai: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let fin = ContinuousClock.now + delai
        while ContinuousClock.now < fin {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Choisir le reseau : le port USB est ferme, la session part vers le nom d'hote avec la
    /// cle du trousseau, la tournee commence ; la sonde branchee n'est plus ouverte en USB.
    @Test(.timeLimit(.minutes(1))) func choisirLeReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .usb)
        let journal = JournalCanaux()
        var canaux = 0
        let distante = Self.sonde()
        let reseau = ReseauFactice([.success(distante)])
        let s = Self.sondeMaillage(p, usb: { _ in
            canaux += 1
            return CanalTemoin("\(canaux)", journal: journal)
        }, trousseau: t, reseau: reseau)
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connecteeParUSB(s))
        #expect(s.reseauDisponible)
        s.choisirLiaison(.reseau)
        #expect(s.liaison == .reseau)
        #expect(p.string(forKey: SondeMaillage.cleLiaison) == SondeMaillage.Liaison.reseau.rawValue)
        await SondeMaillageTests.attendre { SondeMaillageTests.connectee(s) }
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1"], "port USB ferme")
        let hotes = reseau.appels.map { $0.hote }
        #expect(hotes == [Self.hote])
        #expect(reseau.appels.first?.cle == VecteursH1.psk)
        #expect(await Self.sonder { distante.envoyes.contains("etat\n") }, "tournee par le reseau")
        #expect(s.nomEtat == "SONDE-01")
        s.portsChanges([Self.port])
        await Task.yield()
        #expect(canaux == 1, "branchee, la sonde n'est pas ouverte en USB")
        await s.oublier()
    }

    /// Au lancement, liaison reseau retenue : nom d'hote et empreinte relus ; connexion par le reseau.
    @Test func reseauAuLancement() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let reseau = ReseauFactice([.success(Self.sonde())])
        var canaux = 0
        let s = Self.sondeMaillage(p, usb: { _ in
            canaux += 1
            return Self.sonde()
        }, trousseau: t, reseau: reseau)
        #expect(s.liaison == .reseau && s.hote == Self.hote && s.empreinteAcces == "630DCD29")
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s))
        #expect(canaux == 0, "aucun port ouvert")
        #expect(reseau.appels.count == 1)
        await s.oublier()
    }

    /// Echec de la session (sonde muette, pas de route) : erreur montree, reprise seule.
    @Test(.timeLimit(.minutes(1))) func repriseApresEchec() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let reseau = ReseauFactice([.failure(ErreurReseau.aucunDefi), .failure(ErreurReseau.pasDeRoute), .success(Self.sonde())])
        let s = Self.sondeMaillage(p, trousseau: t, reseau: reseau, delais: [.milliseconds(50)])
        await s.connecterReseau()
        #expect(s.etat == .erreur(ErreurReseau.aucunDefi.localizedDescription))
        #expect(s.nomEtat == "SONDE-01")
        await SondeMaillageTests.attendre { SondeMaillageTests.connectee(s) }
        #expect(reseau.appels.count == 3)
        await s.oublier()
    }

    /// Cle absente du trousseau : erreur, sans reprise (il faut l'USB).
    @Test func cleAbsente() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        _ = try Self.prete(p, liaison: .reseau)
        let reseau = ReseauFactice([.success(Self.sonde())])
        let s = Self.sondeMaillage(p, trousseau: TrousseauMemoire(), reseau: reseau)
        await s.connecterReseau()
        #expect(s.etat == .erreur(ErreurTrousseau.absente(Self.hote).localizedDescription))
        try await Task.sleep(for: .milliseconds(100))
        #expect(reseau.appels.isEmpty)
        await s.oublier()
    }

    /// Liaison reseau perdue (canal ferme : veille sans reponse, session perdue) : reconnexion.
    @Test(.timeLimit(.minutes(1))) func liaisonPerdue() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let premiere = Self.sonde()
        let reseau = ReseauFactice([.success(premiere), .success(Self.sonde())])
        let s = Self.sondeMaillage(p, trousseau: t, reseau: reseau)
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s))
        premiere.fermer()
        #expect(await Self.sonder { reseau.appels.count == 2 && SondeMaillageTests.connectee(s) })
        await s.oublier()
    }

    /// Session perdue (chemin perdu, veille sans reponse) : sa cause est montree, comme dans Halo
    /// (« Connexion reseau perdue : <cause> ») ; ici par le vrai canal, sur la carte simulee.
    @Test(.timeLimit(.minutes(1))) func causeDeLaPerteMontree() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: CanalReseauTests.sonde)
        let connexions = ConnexionsSimulees()
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in Self.sonde() }, trousseau: t,
                              ouvrirReseau: { h, c in
                                  try await CanalReseau.connecter(hote: h, cle: c, reglages: CanalReseauTests.rapides(),
                                                                  reglagesTransport: TransportUDPTests.rapides()) { hh, pp in
                                      let x = ConnexionSimulee(hote: hh, port: pp, carte: carte)
                                      connexions.ajouter(x)
                                      return x
                                  }
                              },
                              delaisReprise: [.seconds(60)])
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s))
        connexions.toutes.last?.echouer(.pasDeRoute)
        await SondeMaillageTests.attendre { if case .erreur = s.etat { true } else { false } }
        #expect(s.etat == .erreur(TransportUDP.raisonPerte(.pasDeRoute)))
        await s.oublier()
    }

    /// La cause de la derniere session perdue reste dans Reglages › Sonde (« Derniere perte »)
    /// pendant la reprise, meme quand un essai echoue a son tour, jusqu'a la connexion suivante
    /// reussie ; l'heure est celle de la perte.
    @Test(.timeLimit(.minutes(1))) func dernierePerteGardeeJusquALaReconnexion() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let horloge = HorlogeFactice(Date(timeIntervalSince1970: 1_790_000_000))
        let premiere = Self.sonde()
        let reseau = ReseauFactice([.success(premiere), .failure(ErreurReseau.aucunDefi), .success(Self.sonde())])
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in Self.sonde() }, trousseau: t,
                              ouvrirReseau: { h, c in try reseau.ouvrir(h, c) },
                              delaisReprise: [.milliseconds(200)], horloge: { horloge.maintenant })
        func hauteur() -> CGFloat { NSHostingView(rootView: DernierePerteSonde().environment(s)).fittingSize.height }
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s))
        #expect(s.dernierePerte == nil)
        #expect(hauteur() == 0)
        horloge.avancer(60)
        premiere.fermer()
        await SondeMaillageTests.attendre { s.dernierePerte != nil }
        let perdue = SondeMaillage.Perte(cause: String(localized: "liaison réseau perdue"), date: horloge.maintenant)
        #expect(s.dernierePerte == perdue)
        #expect(hauteur() > 0, "montree dans les Reglages")
        // Premiere reprise en echec : l'etat change, la perte reste.
        #expect(await Self.sonder { reseau.appels.count == 2 && s.etat == .erreur(ErreurReseau.aucunDefi.localizedDescription) })
        #expect(s.dernierePerte == perdue)
        // Seconde reprise reussie : la perte s'efface.
        #expect(await Self.sonder { reseau.appels.count == 3 && SondeMaillageTests.connectee(s) })
        #expect(s.dernierePerte == nil)
        #expect(hauteur() == 0)
        await s.oublier()
    }

    /// Une activite est tenue pendant une session reseau (App Nap retarderait la veille et les
    /// tournees), relachee a sa fin ; rien de tel en USB.
    @Test(.timeLimit(.minutes(1))) func activitePendantLaSessionReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .usb)
        let premiere = Self.sonde()
        let s = Self.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([.success(premiere), .failure(ErreurReseau.aucunDefi)]),
                                   delais: [.seconds(60)])
        await s.connecter(Self.port, choisi: true)
        #expect(!s.activiteTenue, "pas en USB")
        s.choisirLiaison(.reseau)
        await SondeMaillageTests.attendre { SondeMaillageTests.connectee(s) }
        #expect(s.activiteTenue)
        premiere.fermer()
        await SondeMaillageTests.attendre { if case .erreur = s.etat { true } else { false } }
        #expect(!s.activiteTenue, "session perdue")
        await s.oublier()
        #expect(!s.activiteTenue)
    }

    /// Retour a l'USB : la session reseau est fermee, la sonde branchee reprise par son port.
    @Test(.timeLimit(.minutes(1))) func retourALUSB() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let journal = JournalCanaux()
        let distante = CanalTemoin("reseau", journal: journal)
        let reseau = ReseauFactice([.success(distante)])
        let s = Self.sondeMaillage(p, usb: { _ in CanalTemoin("usb", journal: journal) }, trousseau: t, reseau: reseau)
        s.portsChanges([Self.port])
        await Task.yield()
        #expect(!journal.cycle.contains("ouvrir usb"))
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s))
        s.choisirLiaison(.usb)
        #expect(p.string(forKey: SondeMaillage.cleLiaison) == SondeMaillage.Liaison.usb.rawValue)
        await SondeMaillageTests.attendre { Self.connecteeParUSB(s) }
        #expect(journal.cycle == ["ouvrir reseau", "fermer reseau", "fin reseau", "ouvrir usb"])
        await s.oublier()
    }

    /// Reglages › Sonde : etat de l'acces reseau (les attentes reprennent les cles du code :
    /// elles suivent la langue de l'hote).
    @Test func texteAccesReseau() {
        #expect(FenetreReglages.texteAccesReseau(empreinte: nil) == String(localized: "non autorisé"))
        #expect(FenetreReglages.texteAccesReseau(empreinte: "630DCD29") == String(localized: "autorisé · clé \("630DCD29")"))
        #expect(FenetreReglages.texteHote(Self.hote) == "0123456789ABCDEF.local")
        #expect(FenetreReglages.texteHote(nil) == "—")
    }

    /// Reglages › Sonde : « Dernier releve » donne la date avec l'heure (la sonde peut rester des
    /// jours sans relever).
    @Test func texteDernierReleve() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let texte = FenetreReglages.texteDernierReleve(d)
        #expect(texte.contains(d.formatted(.dateTime.year())), "la date : \(texte)")
        #expect(texte.contains(d.formatted(date: .omitted, time: .standard)), "l'heure : \(texte)")
    }

    /// Reglages › Sonde : partition, suspension, dernier releve et erreur de la tournee seulement
    /// pour la sonde connectee ; debranchee, ces lignes perimees ne restent pas.
    @Test(.timeLimit(.minutes(1))) func releveSeulementConnectee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let s = Self.sondeMaillage(p, usb: { _ in CanalRejoue { CanalRejoue.reseauMinimal($0) } }, trousseau: TrousseauMemoire())
        func hauteur() -> CGFloat { NSHostingView(rootView: ReleveSonde().environment(s)).fittingSize.height }
        await s.connecter(Self.port, choisi: true)
        await SondeMaillageTests.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        #expect(s.etatSonde != nil)
        #expect(hauteur() > 0, "connectee : partition et dernier releve")
        s.portsChanges([])
        #expect(s.etat == .absente)
        #expect(hauteur() == 0, "debranchee")
        await s.oublier()
    }

    /// Reglages › Sonde : le bouton de l'acces reseau dit ce qu'il fera : autoriser sans cle,
    /// regenerer une cle ensuite (demande de Djoko : le bouton reste actif apres l'autorisation).
    @Test func titreBoutonAcces() {
        #expect(FenetreReglages.titreBoutonAcces(empreinte: nil) == String(localized: "Autoriser l'accès réseau"))
        #expect(FenetreReglages.titreBoutonAcces(empreinte: "630DCD29") == String(localized: "Régénérer une clé"))
    }

    /// Reglages › Sonde : par le reseau, le firmware 1.0.2 ne donne ni code ni QR code (le code
    /// d'appairage ne circule pas en clair) ; une note les remplace. En USB, ou quand la sonde
    /// les donne, pas de note (valeurs inventees).
    @Test func noteCodeMatterParLeReseau() throws {
        func lire(_ json: String) -> Bonjour? {
            if case .bonjour(let b)? = MessageSonde.lire(Data(json.utf8)) { b } else { nil }
        }
        let avecCode = try #require(lire(Self.bonjour()))
        let sansCode = try #require(lire(Self.bonjour().replacingOccurrences(
            of: #""code":"12345678901","qr":"MT:ABCDEFGHIJ0123456789""#, with: #""code":null,"qr":null"#)))
        #expect(sansCode.code == nil && sansCode.qr == nil)
        let note = String(localized: "Le code Matter ne passe pas par le réseau : branchez la sonde en USB pour l'afficher.")
        #expect(FenetreReglages.noteCodeMatter(sansCode, liaison: .reseau) == note)
        #expect(FenetreReglages.noteCodeMatter(sansCode, liaison: .usb) == nil)
        #expect(FenetreReglages.noteCodeMatter(avecCode, liaison: .reseau) == nil)
        #expect(FenetreReglages.noteCodeMatter(avecCode, liaison: .usb) == nil)
    }

    /// Reglages › Sonde : le bloc de l'acces reseau se dessine (etat, bouton, explication).
    @Test func vueAccesReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        func hauteur(_ s: SondeMaillage) -> CGFloat {
            NSHostingView(rootView: Form { AccesReseauSonde() }.formStyle(.grouped).environment(s)).fittingSize.height
        }
        // En USB : etat, bouton et explication ; une erreur ajoute sa ligne.
        let usb = Self.sondeMaillage(p, usb: { _ in Self.sonde(bonjour: Self.bonjour(hote: nil)) }, trousseau: TrousseauMemoire())
        await usb.connecter(Self.port, choisi: true)
        let sansErreur = hauteur(usb)
        await usb.autoriserAccesReseau()
        #expect(usb.erreurAcces != nil)
        #expect(hauteur(usb) > sansErreur, "ligne de l'erreur")
        await usb.oublier()
        // Par le reseau : pas de bouton (la cle ne passe que par l'USB).
        let t = try Self.prete(p, liaison: .reseau)
        let reseau = Self.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([.success(Self.sonde())]))
        #expect(hauteur(reseau) < sansErreur, "sans le bouton")
        await reseau.oublier()
    }

    /// Liaison reseau tombee (aucune sonde dans l'app) : un port branche, debranche, rebranche ne
    /// change rien et n'est jamais ouvert.
    @Test(.timeLimit(.minutes(1))) func reseauTombeAucunPortOuvert() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        var canaux = 0
        let premiere = Self.sonde()
        let s = Self.sondeMaillage(p, usb: { _ in
            canaux += 1
            return Self.sonde()
        }, trousseau: t, reseau: ReseauFactice([.success(premiere), .failure(ErreurReseau.aucunDefi)]), delais: [.seconds(60)])
        await s.connecterReseau()
        premiere.fermer()
        await SondeMaillageTests.attendre { if case .erreur = s.etat { true } else { false } }
        let tombee = s.etat
        for liste in [[Self.port], [], [Self.port]] {
            s.portsChanges(liste)
            await Task.yield()
            #expect(s.etat == tombee, "ni connexion, ni absente")
        }
        #expect(canaux == 0)
        #expect(s.ports == [Self.port], "port liste pour les Reglages")
        await s.oublier()
    }

    /// Au lancement, liaison reseau retenue : `demarrer` se connecte par le reseau ; les ports
    /// branches sont seulement listes (IOKit), aucun n'est ouvert.
    @Test(.timeLimit(.minutes(1))) func demarrerEnReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let reseau = ReseauFactice([.success(Self.sonde())])
        var canaux = 0
        let s = Self.sondeMaillage(p, usb: { _ in
            canaux += 1
            return Self.sonde()
        }, trousseau: t, reseau: reseau)
        s.demarrer()
        #expect(await Self.sonder { SondeMaillageTests.connectee(s) }, "connectee par le reseau")
        #expect(reseau.appels.count == 1)
        #expect(canaux == 0)
        await s.oublier()
    }

    /// Par le reseau, `bonjour` et `etat` attendent au-dela du renvoi de 4 s du canal : la
    /// reponse a ce renvoi (ici a 4,2 s) aboutit.
    @Test(.timeLimit(.minutes(1))) func delaiDeCommandeParLeReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let lent = CanalLent(delai: .milliseconds(4200), repondre: Self.reponses())
        let s = Self.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([.success(lent)]), delais: [.seconds(60)])
        await s.connecterReseau()
        #expect(SondeMaillageTests.connectee(s), "bonjour a 4,2 s : \(s.etat)")
        #expect(await Self.sonder(delai: .seconds(10)) { s.etatSonde != nil }, "etat de la tournee a 4,2 s")
        await s.oublier()
    }

    /// En USB, rien ne change : 3 s, puis « ne repond pas ».
    @Test(.timeLimit(.minutes(1))) func delaiDeCommandeEnUSB() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let lent = CanalLent(delai: .milliseconds(4200), repondre: Self.reponses())
        let s = Self.sondeMaillage(p, usb: { _ in lent }, trousseau: TrousseauMemoire())
        let debut = ContinuousClock.now
        await s.connecter(Self.port, choisi: true)
        #expect(s.etat == .refusee(SondeUSB.Erreur.sansReponse("bonjour").localizedDescription))
        #expect(ContinuousClock.now - debut < .seconds(4), "abandon a 3 s")
        await s.oublier()
    }

    /// Oublier la sonde : la cle de ce Mac part avec elle ; retour a l'USB.
    @Test func oublier() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try Self.prete(p, liaison: .reseau)
        let s = Self.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([.success(Self.sonde())]))
        await s.connecterReseau()
        await s.oublier()
        #expect(s.etat == .sansSonde)
        #expect(t.lister().isEmpty)
        #expect(s.hote == nil && s.empreinteAcces == nil && s.liaison == .usb)
        #expect(p.string(forKey: SondeMaillage.cleHote) == nil)
        #expect(p.string(forKey: SondeMaillage.cleLiaison) == nil)
    }
}
