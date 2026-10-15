import AppKit
import Foundation
import MaillageCoeur
@testable import ProtocoleThread
import Synchronization
import Testing
@testable import MaillageIoT

// Liaison « Automatique » de la sonde Thread (etape 3b, tache 12, spec 6.7) : le reglage (Automatique, USB, Reseau Thread) est
// separe du chemin en service, comme `ReglageChemin` / `Acces` de Zigbee. Ports, canaux, reseau, trousseau et Bonjour sont
// factices : aucun port reel, aucun reseau, aucun trousseau du Mac, des identifiants inventes. Ouvrir un port fait basculer
// DTR/RTS : la carte de Zigbee et une carte inconnue ne doivent jamais l'etre.

/// Les ports branches d'un banc, lus par la sonde (`listerPorts` est `@Sendable`).
private final class PortsBranches: Sendable {
    private let liste = Mutex<[PortUSB]>([])
    var valeur: [PortUSB] { liste.withLock { $0 } }
    func poser(_ p: [PortUSB]) { liste.withLock { $0 = p } }
}

/// Un canal dont l'ouverture echoue (port occupe par un autre programme) : la connexion USB automatique est en erreur.
private struct CanalQuiRefuse: CanalSonde {
    struct Refus: Error {}
    func ouvrir() throws -> AsyncStream<Data> { throw Refus() }
    func envoyer(_ ligne: String) {}
    func fermer() {}
}

/// Les instants des ouvertures du reseau, notes par le banc (les essais d'une liaison reseau qui echoue).
@MainActor
private final class InstantsReseau {
    private(set) var instants: [ContinuousClock.Instant] = []
    func noter() { instants.append(.now) }
}

/// Une sonde Thread et tout ce qu'elle touche, factice : suivi des ports, canaux USB comptes, reseau factice, trousseau en
/// memoire, preferences en memoire.
@MainActor
private final class Banc {
    static let hote = SondeReseauTests.hote
    /// La carte retenue par cette sonde (numero de serie inventee, A0:00:00:00:00:01).
    static let retenue = SondeMaillageTests.port
    /// La carte de Zigbee, et un C6 inconnu (le pont d'un autre projet).
    static let zigbee = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:02",
                                produit: nil)
    static let inconnue = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: "FACTICE-03",
                                  produit: nil)

    let sonde: SondeMaillageThread
    let ports = FabriquePorts()
    let usb = RegistrePorts()
    let reseau: ReseauFactice
    let cartes: CartesRetenues
    let preferences: UserDefaults
    private let domaine: String
    private let branches = PortsBranches()

    /// `reglage` : la preference de liaison deja ecrite (nil : absente, une nouvelle installation) ; `retenue` : la sonde est
    /// deja retenue (numero de serie, nom, hote) ; `cle` : la cle de l'acces reseau est dans le trousseau ; `branches` : les
    /// cartes vues au demarrage. Delais courts : reprise 30 puis 60 ms, retour a l'USB 150 ms, nouvel essai USB 40 ms.
    init(reglage: String? = nil, retenue: Bool = true, cle: Bool = true, branches: [PortUSB] = [],
         cartes: CartesRetenues = CartesRetenues(),
         reseau: [Result<any CanalSonde, any Error>] = [.success(SondeReseauTests.sonde())],
         ouvrirReseau: (@MainActor (String, Data) async throws -> any CanalSonde)? = nil,
         canalUSB: @escaping (String) -> any CanalSonde = { _ in SondeReseauTests.sonde() },
         delaisReprise: [Duration] = [.milliseconds(30), .milliseconds(60)],
         delaiRetourUSB: Duration = .milliseconds(150)) throws {
        let (p, d) = try SondeMaillageTests.preferences()
        preferences = p
        domaine = d
        if retenue {
            p.set(Self.retenue.serie, forKey: SondeMaillageThread.cleSerie)
            p.set("SONDE-01", forKey: SondeMaillageThread.cleNom)
            p.set(Self.hote, forKey: SondeMaillageThread.cleHote)
        }
        if let reglage { p.set(reglage, forKey: SondeMaillageThread.cleLiaison) }
        let trousseau = TrousseauMemoireThread()
        if cle { try trousseau.ranger(nom: Self.hote, cle: VecteursH1.psk, empreinte: "630DCD29") }
        let factice = ReseauFactice(reseau)
        self.reseau = factice
        self.cartes = cartes
        self.branches.poser(branches)
        let usb = self.usb, liste = self.branches
        sonde = SondeMaillageThread(
            preferences: p, actif: true, ouvrirCanal: { usb.canal($0, canalUSB($0)) }, trousseau: trousseau,
            ouvrirReseau: ouvrirReseau ?? { h, c in try factice.ouvrir(h, c) },
            delaisReprise: delaisReprise, delaiNouvelEssai: .milliseconds(40), delaiRetourUSB: delaiRetourUSB,
            surveillerPorts: ports.fabriquer, listerPorts: { liste.valeur }, cartes: cartes)
    }

    /// Un evenement USB : la liste des ports branches, vue par le suivi des ports de la sonde.
    func brancher(_ liste: [PortUSB]) {
        branches.poser(liste)
        ports.brancher(liste)
    }

    /// La sonde est annoncee (ou plus) par Bonjour, d'apres l'instantane de Thread.
    func annoncer(_ annoncee: Bool) {
        sonde.annoncesChangees(annoncee ? [Self.hote] : [])
    }

    var connectee: Bool { SondeMaillageTests.connectee(sonde) }
    /// Connectee par ce chemin.
    func connectee(par l: SondeMaillageThread.Liaison) -> Bool { connectee && sonde.liaison == l }

    func nettoyer() {
        sonde.arreter()
        preferences.removePersistentDomain(forName: domaine)
    }
}

@Suite("Liaison de la sonde Thread : le chemin choisi")
struct CheminLiaisonTests {
    /// Automatique : l'USB si la carte retenue est branchee, sinon le reseau si la cle est connue ET la sonde annoncee.
    @Test func automatique() {
        #expect(CheminLiaison.choisir(.automatique, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminLiaison.choisir(.automatique, branchee: true, cleConnue: false, annoncee: false) == .usb)
        #expect(CheminLiaison.choisir(.automatique, branchee: false, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminLiaison.choisir(.automatique, branchee: false, cleConnue: true, annoncee: false) == nil)
        #expect(CheminLiaison.choisir(.automatique, branchee: false, cleConnue: false, annoncee: true) == nil)
        #expect(CheminLiaison.choisir(.automatique, branchee: false, cleConnue: false, annoncee: false) == nil)
    }

    @Test func usbSeulement() {
        #expect(CheminLiaison.choisir(.usb, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminLiaison.choisir(.usb, branchee: false, cleConnue: true, annoncee: true) == nil)
    }

    /// « Reseau Thread » exige la cle, pas l'annonce : le choix manuel de Thread 1.3.0 n'a jamais attendu Bonjour (il se
    /// reessaie seul, 1 a 30 s). Different de Zigbee, ou le Wi-Fi exige aussi l'annonce.
    @Test func reseauSeulement() {
        #expect(CheminLiaison.choisir(.reseau, branchee: true, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminLiaison.choisir(.reseau, branchee: false, cleConnue: true, annoncee: false) == .reseau)
        #expect(CheminLiaison.choisir(.reseau, branchee: true, cleConnue: false, annoncee: true) == nil)
    }

    /// Les valeurs ecrites par Thread 1.3.0 (`usb`, `reseau`) restent des reglages valides ; une valeur inconnue n'en est pas un.
    @Test func reglageLu() {
        #expect(ReglageLiaison(rawValue: "automatique") == .automatique)
        #expect(ReglageLiaison(rawValue: "usb") == .usb && ReglageLiaison(rawValue: "reseau") == .reseau)
        #expect(ReglageLiaison(rawValue: "inconnu") == nil)
        #expect(ReglageLiaison.allCases == [.automatique, .usb, .reseau])
        #expect(SondeMaillageThread.Liaison(rawValue: "usb") == .usb && SondeMaillageThread.Liaison(rawValue: "reseau") == .reseau)
    }

    /// « Annoncee » : l'hote SRP de la sonde (sans `.local`) est parmi ceux de l'instantane, sans tenir compte de la casse.
    @Test func annonceeParSonHote() {
        let annonces: Set<String> = ["0123456789ABCDEF", "FEDCBA9876543210"]
        #expect(CheminLiaison.annoncee(hote: "0123456789ABCDEF", parmi: annonces))
        #expect(CheminLiaison.annoncee(hote: "0123456789abcdef", parmi: annonces))
        #expect(!CheminLiaison.annoncee(hote: "1111111111111111", parmi: annonces))
        #expect(!CheminLiaison.annoncee(hote: nil, parmi: annonces))
        #expect(!CheminLiaison.annoncee(hote: "0123456789ABCDEF", parmi: []))
    }

    /// Les hotes que l'instantane montre avec une adresse resolue : un appareil sans adresse n'est pas « annonce » (rien
    /// a joindre), un appareil absent non plus.
    @MainActor @Test func hotesDeLInstantane() {
        let a = AdresseVerifieeAppTests.annonces(Date(timeIntervalSince1970: 0), muets: [AdresseVerifieeAppTests.hap])
        var suivi = Suivi()
        _ = suivi.integrer(a, noms: ResolveurNoms())
        let hotes = CheminLiaison.hotesAnnonces(suivi.instantane)
        #expect(hotes.contains(AdresseVerifieeAppTests.matter) && hotes.contains(AdresseVerifieeAppTests.temoin))
        #expect(!hotes.contains(AdresseVerifieeAppTests.hap.uppercased()), "sans adresse")
        #expect(CheminLiaison.hotesAnnonces(nil).isEmpty)
    }
}

@MainActor
@Suite("Sonde Thread : Automatique, USB d'abord puis le reseau Thread", .timeLimit(.minutes(1)))
struct LiaisonAutomatiqueThreadTests {
    // MARK: - Preference

    /// Une nouvelle installation (aucune preference) est en Automatique, et ne l'ecrit pas d'elle-meme.
    @Test func nouvelleInstallationEnAutomatique() async throws {
        let b = try Banc(reglage: nil, retenue: false, cle: false)
        defer { b.nettoyer() }
        #expect(b.sonde.reglage == .automatique && b.sonde.liaison == .usb)
        b.sonde.demarrer()
        b.brancher([Banc.retenue])
        b.annoncer(true)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == nil, "Automatique n'ecrit rien tout seul")
    }

    /// Un choix existant (`thread.sondeLiaison`) est garde tel quel : lu, jamais reecrit ni remplace par Automatique, ni par
    /// un demarrage, un evenement USB ou une annonce.
    @Test(arguments: ["usb", "reseau"]) func choixExistantGarde(_ choix: String) async throws {
        let b = try Banc(reglage: choix, branches: [])
        defer { b.nettoyer() }
        #expect(b.sonde.reglage.rawValue == choix)
        b.sonde.demarrer()
        b.annoncer(true)
        b.brancher([Banc.retenue])
        b.brancher([])
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.sonde.reglage.rawValue == choix)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == choix)
    }

    /// Un ancien choix « USB » ne bascule jamais sur le reseau : carte debranchee, cle connue et sonde annoncee, rien ne part.
    @Test func ancienChoixUSBNeVaPasSurLeReseau() async throws {
        let b = try Banc(reglage: "usb", branches: [])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(b.reseau.appels.isEmpty && b.usb.chemins.isEmpty)
        #expect(b.sonde.etat == .absente && b.sonde.liaison == .usb)
    }

    /// Un ancien choix « Reseau Thread » reste le reseau, sans attendre l'annonce, et ne s'ouvre pas en USB si la carte est
    /// branchee (comme avant).
    @Test func ancienChoixReseauResteLeReseau() async throws {
        let b = try Banc(reglage: "reseau", branches: [Banc.retenue])
        defer { b.nettoyer() }
        #expect(b.sonde.liaison == .reseau)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.brancher([Banc.retenue])
        try await Task.sleep(for: .milliseconds(250))
        #expect(b.usb.chemins.isEmpty, "branchee, la sonde n'est pas ouverte en USB")
        #expect(b.reseau.appels.count == 1 && b.connectee(par: .reseau))
    }

    /// Une valeur inconnue n'est pas un choix : Automatique.
    @Test func preferenceInconnue() throws {
        let b = try Banc(reglage: "wifi", retenue: false, cle: false)
        defer { b.nettoyer() }
        #expect(b.sonde.reglage == .automatique)
    }

    // MARK: - Choix du chemin en Automatique

    /// Carte retenue branchee : l'USB d'abord, meme avec une cle connue et une sonde annoncee ; le reseau n'est pas touche.
    @Test func usbDAbord() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.annoncer(true)
        #expect(b.sonde.liaison == .usb && b.sonde.etat == .sansSonde,
                "avant de connaitre les cartes branchees, une annonce ne passe pas sur le reseau")
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.annoncer(true)
        b.annoncer(false)
        b.annoncer(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.usb.chemins == [Banc.retenue.chemin])
        #expect(b.reseau.appels.isEmpty, "le reseau n'est pas ouvert tant que l'USB est la")
        #expect(b.connectee(par: .usb))
    }

    /// Sans carte branchee, le reseau si la cle est connue et la sonde annoncee : aucun port n'est ouvert.
    @Test func reseauSansCarteBranchee() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(b.sonde.etat == .absente && b.reseau.appels.isEmpty, "pas encore annoncee")
        b.annoncer(true)
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        #expect(b.reseau.appels.map(\.hote) == [Banc.hote] && b.reseau.appels.first?.cle == VecteursH1.psk)
        #expect(b.usb.chemins.isEmpty)
    }

    /// Sans cle, ou sonde non annoncee : rien ne part, ni reseau ni port.
    @Test func sansCleOuSansAnnonceRienNePart() async throws {
        let sansCle = try Banc(cle: false, branches: [])
        defer { sansCle.nettoyer() }
        sansCle.sonde.demarrer()
        sansCle.annoncer(true)
        let sansAnnonce = try Banc(branches: [])
        defer { sansAnnonce.nettoyer() }
        sansAnnonce.sonde.demarrer()
        sansAnnonce.annoncer(false)
        try await Task.sleep(for: .milliseconds(150))
        for b in [sansCle, sansAnnonce] {
            #expect(b.reseau.appels.isEmpty && b.usb.chemins.isEmpty)
            #expect(b.sonde.etat == .absente && b.sonde.liaison == .usb && b.sonde.tachesPlanifiees == 0)
        }
        #expect(!sansCle.sonde.reseauDisponible && sansAnnonce.sonde.reseauDisponible)
    }

    /// L'annonce qui arrive apres le demarrage met la sonde sur le reseau ; celle qui disparait ne coupe pas une session
    /// ouverte (elle prouve que la sonde est joignable), mais arrete les essais d'une session qui n'aboutit pas.
    @Test func annonceTardiveEtPerdue() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer(true)
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.annoncer(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.connectee(par: .reseau) && b.reseau.appels.count == 1, "la session ouverte reste")

        // Une session qui n'aboutit pas : l'annonce perdue arrete les essais.
        let c = try Banc(branches: [], reseau: [.failure(ErreurReseau.aucunDefi)])
        defer { c.nettoyer() }
        c.sonde.demarrer()
        c.annoncer(true)
        #expect(await attendreActivation { c.reseau.appels.count >= 2 }, "il reessaie tant qu'elle est annoncee")
        c.annoncer(false)
        try await Task.sleep(for: .milliseconds(60))
        let vus = c.reseau.appels.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(c.reseau.appels.count == vus, "plus d'essai une fois la sonde plus annoncee")
        #expect(c.sonde.etat == .absente && c.sonde.liaison == .usb && c.sonde.tachesPlanifiees == 0)
    }

    // MARK: - Jamais la mauvaise carte

    /// Ni la carte de Zigbee ni un C6 inconnu ne sont ouverts, a l'arrivee comme au demarrage, la carte retenue absente ou
    /// non ; seule la carte retenue l'est, et elle seule.
    @Test func jamaisLaCarteDeZigbeeNiUneInconnue() async throws {
        let cartes = CartesRetenues()
        cartes.retenir(Banc.zigbee.serie, par: .zigbee)
        let b = try Banc(branches: [Banc.zigbee, Banc.inconnue], cartes: cartes)
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.brancher([Banc.zigbee, Banc.inconnue])
        await b.sonde.connecter(Banc.zigbee, choisi: false)
        await b.sonde.connecter(Banc.inconnue, choisi: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.usb.chemins.isEmpty, "rien d'ouvert : \(b.usb.chemins)")
        #expect(b.sonde.ports.map(\.chemin) == [Banc.inconnue.chemin], "la carte de Zigbee n'est pas proposee")
        // La sienne arrive avec les autres : elle seule est ouverte.
        b.brancher([Banc.zigbee, Banc.inconnue, Banc.retenue])
        #expect(await attendreActivation { b.connectee(par: .usb) })
        #expect(b.usb.chemins == [Banc.retenue.chemin])
        // Elle repart : le reseau prend le relais, les autres cartes restent fermees.
        b.annoncer(true)
        b.brancher([Banc.zigbee, Banc.inconnue])
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        #expect(b.usb.chemins == [Banc.retenue.chemin] && b.usb.ouverts == 0)
    }

    /// Nouvelle installation en Automatique : aucune carte retenue, aucune n'est ouverte d'elle-meme (meme un C6 qui serait la
    /// sonde) ; le choix de l'utilisateur la retient, sans ecrire la preference de liaison.
    @Test func uneCarteNonRetenueNEstOuverteQuePourUnChoix() async throws {
        let b = try Banc(retenue: false, cle: false, branches: [Banc.retenue, Banc.inconnue])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.brancher([Banc.retenue, Banc.inconnue])
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.usb.chemins.isEmpty && b.sonde.etat == .sansSonde)
        b.sonde.choisir(Banc.retenue)
        #expect(await attendreActivation { b.connectee(par: .usb) })
        #expect(b.usb.chemins == [Banc.retenue.chemin] && b.sonde.serie == Banc.retenue.serie)
        #expect(b.cartes.serie(de: .thread) == Banc.retenue.serie)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == nil)
    }

    // MARK: - Bascules, sans bagarre entre l'USB et le reseau

    /// L'USB se debranche : le reseau prend le relais tout de suite (la liaison USB est fermee, le port rendu).
    @Test func debranchementBasculeVersLeReseau() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.brancher([])
        #expect(b.sonde.liaison == .reseau, "le chemin change des l'evenement")
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        #expect(b.usb.ouverts == 0 && b.usb.chemins.count == 1 && b.reseau.appels.count == 1)
    }

    /// Debranchee sans annonce : rien ne part, la sonde est « absente » (et le reseau ne s'ouvre pas a l'aveugle).
    @Test func debranchementSansAnnonce() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.brancher([])
        try await Task.sleep(for: .milliseconds(120))
        #expect(b.sonde.etat == .absente && b.reseau.appels.isEmpty && b.usb.ouverts == 0)
        // L'annonce arrive : le reseau.
        b.annoncer(true)
        #expect(await attendreActivation { b.connectee(par: .reseau) })
    }

    /// L'USB revient pendant une session reseau : retour a l'USB, une fois, apres le delai de stabilite ; la session reseau
    /// est fermee et rien n'est rouvert ensuite.
    @Test func rebranchementRamenerALUSBUneFois() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.brancher([])
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.brancher([Banc.retenue])
        #expect(b.sonde.liaison == .reseau && b.usb.chemins.count == 1, "pas tout de suite : la session reseau tient")
        #expect(await attendreActivation { b.connectee(par: .usb) })
        try await Task.sleep(for: .milliseconds(400))
        #expect(b.usb.chemins == [Banc.retenue.chemin, Banc.retenue.chemin], "ouverte une seule fois de plus")
        #expect(b.reseau.appels.count == 1, "le reseau n'est pas rouvert")
        #expect(b.connectee(par: .usb) && b.sonde.tachesPlanifiees == 1, "seule la boucle des tournees")
    }

    /// Pas d'oscillation : une carte qui se branche et se debranche plus vite que le delai de stabilite ne coupe pas la
    /// session reseau et n'ouvre pas le port ; stable ensuite, elle ramene l'USB, une fois.
    @Test func rebranchementsRapidesSansOscillation() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.brancher([])
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        for _ in 0..<5 {
            b.brancher([Banc.retenue])
            try await Task.sleep(for: .milliseconds(40))
            b.brancher([])
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(b.usb.chemins.count == 1, "le port n'a pas ete rouvert : \(b.usb.chemins)")
        #expect(b.reseau.appels.count == 1 && b.connectee(par: .reseau), "la session reseau n'a pas ete coupee")
        b.brancher([Banc.retenue])
        #expect(await attendreActivation { b.connectee(par: .usb) })
        try await Task.sleep(for: .milliseconds(300))
        #expect(b.usb.chemins.count == 2 && b.reseau.appels.count == 1)
    }

    /// Sans session reseau a protéger (elle n'aboutit pas), l'USB qui revient prend la place tout de suite.
    @Test func rebranchementSansSessionReseauEstImmediat() async throws {
        let b = try Banc(branches: [], reseau: [.failure(ErreurReseau.aucunDefi)],
                         delaisReprise: [.seconds(30)], delaiRetourUSB: .seconds(30))
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer(true)
        #expect(await attendreActivation { b.reseau.appels.count == 1 })
        b.brancher([Banc.retenue])
        #expect(await attendreActivation { b.connectee(par: .usb) }, "sans attendre les 30 s")
        #expect(b.reseau.appels.count == 1)
    }

    /// Un reseau qui echoue ne martele pas : essais espaces (reprise croissante), aucun ne part plus tot que le delai ; un
    /// evenement Bonjour qui ne change rien (annonce repetee) n'en provoque pas.
    @Test func reseauEnEchecNeMartelePas() async throws {
        let instants = InstantsReseau()
        let b = try Banc(branches: [], ouvrirReseau: { _, _ in
            instants.noter()
            throw ErreurReseau.aucunDefi
        }, delaisReprise: [.milliseconds(40), .milliseconds(80), .milliseconds(160)])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer(true)
        try await Task.sleep(for: .milliseconds(100))
        let avant = instants.instants.count
        for _ in 0..<50 { b.annoncer(true) }
        for _ in 0..<20 { b.brancher([]) }
        #expect(instants.instants.count == avant, "ni une annonce repetee ni un evenement USB sans effet ne relancent")
        try await Task.sleep(for: .milliseconds(700))
        let t = instants.instants
        #expect(t.count >= 3 && t.count <= 9, "essais : \(t.count)")
        let ecarts = zip(t, t.dropFirst()).map { $1 - $0 }
        #expect(ecarts.allSatisfy { $0 >= .milliseconds(35) }, "ecarts : \(ecarts)")
        #expect(ecarts.last! >= ecarts.first!, "le delai ne diminue pas : \(ecarts)")
    }

    /// Une annonce qui clignote pendant que le reseau echoue : l'espacement des essais est garde (il ne repart pas de zero
    /// a chaque retour de l'annonce, seule une connexion reussie le remet).
    @Test func annonceQuiClignoteGardeLEspacement() async throws {
        let instants = InstantsReseau()
        let b = try Banc(branches: [], ouvrirReseau: { _, _ in
            instants.noter()
            throw ErreurReseau.aucunDefi
        }, delaisReprise: [.milliseconds(300)])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer(true)
        #expect(await attendreActivation { instants.instants.count == 1 })
        for _ in 0..<6 {
            b.annoncer(false)
            try await Task.sleep(for: .milliseconds(10))
            b.annoncer(true)
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(instants.instants.count <= 2, "des essais a chaque retour de l'annonce : \(instants.instants.count)")
    }

    /// Une connexion USB qui echoue ne bascule pas sur le reseau (carte branchee = USB) : un seul nouvel essai, puis la
    /// sonde attend l'evenement USB suivant, comme avant ; le reseau n'est jamais ouvert.
    @Test func usbEnEchecNeBasculePasVersLeReseau() async throws {
        let b = try Banc(branches: [Banc.retenue], canalUSB: { _ in CanalQuiRefuse() })
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.usb.chemins.count == 2 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(b.usb.chemins.count == 2, "essai + un nouvel essai")
        #expect(b.reseau.appels.isEmpty && b.sonde.liaison == .usb)
        if case .erreur = b.sonde.etat {} else { Issue.record("etat : \(b.sonde.etat)") }
    }

    // MARK: - Changements de reglage

    /// Le reglage change les chemins : Automatique -> USB ferme le reseau, Reseau n'est pas choisissable sans cle ; la
    /// preference est ecrite a chaque choix de l'utilisateur.
    @Test func changerDeReglage() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.sonde.choisirLiaison(.usb)
        #expect(b.sonde.reglage == .usb && b.sonde.liaison == .usb && b.sonde.etat == .absente)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == "usb")
        b.annoncer(false)
        b.annoncer(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.reseau.appels.count == 1, "en USB, l'annonce ne lance rien")
        b.sonde.choisirLiaison(.automatique)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == "automatique")
        #expect(await attendreActivation { b.connectee(par: .reseau) }, "Automatique : la sonde est annoncee, le reseau")
        b.sonde.choisirLiaison(.reseau)
        #expect(b.sonde.reglage == .reseau && b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == "reseau")
    }

    /// Passer a Automatique pendant une session reseau, carte branchee : l'USB tout de suite (le choix est explicite, pas de
    /// delai de stabilite) ; passer a Automatique avec l'USB en place ne la rouvre pas.
    @Test func automatiqueApresLeReseauOuLUSB() async throws {
        let b = try Banc(reglage: "reseau", branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.sonde.choisirLiaison(.automatique)
        #expect(await attendreActivation { b.connectee(par: .usb) })
        #expect(b.usb.chemins.count == 1)
        b.sonde.choisirLiaison(.usb)
        b.sonde.choisirLiaison(.automatique)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.usb.chemins.count == 1 && b.reseau.appels.count == 1 && b.connectee(par: .usb), "la liaison USB n'est pas rouverte")
    }

    /// Sans cle, « Reseau Thread » n'est pas choisissable : rien ne change, rien n'est ecrit.
    @Test func reseauIndisponibleSansCle() async throws {
        let b = try Banc(cle: false, branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.sonde.choisirLiaison(.reseau)
        #expect(b.sonde.reglage == .automatique && b.sonde.liaison == .usb)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == nil)
        #expect(b.reseau.appels.isEmpty && b.connectee(par: .usb))
    }

    /// Un port choisi a la main, pendant une session reseau en Automatique, prend la place de la liaison reseau.
    @Test func choisirUnPortPendantLeReseau() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.brancher([Banc.retenue])
        b.sonde.choisir(Banc.retenue)
        #expect(b.sonde.liaison == .usb)
        #expect(await attendreActivation { b.connectee(par: .usb) })
        try await Task.sleep(for: .milliseconds(300))
        #expect(b.connectee(par: .usb) && b.usb.chemins.count == 1 && b.reseau.appels.count == 1)
    }

    // MARK: - Arret, oubli

    /// Thread eteint : plus rien ne se connecte, ni sur une annonce, ni sur un evenement USB, aucune tache ne reste (le retour
    /// a l'USB attendu non plus) ; rallume, la sonde repart au premier releve.
    @Test func arretEtRedemarrage() async throws {
        let b = try Banc(branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        b.brancher([])
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.brancher([Banc.retenue])  // un retour a l'USB est attendu
        b.sonde.arreter()
        #expect(b.sonde.tachesPlanifiees == 0 && b.sonde.etat == .absente && !b.sonde.actif)
        b.annoncer(true)
        b.brancher([Banc.retenue])
        try await Task.sleep(for: .milliseconds(300))
        #expect(b.usb.chemins.count == 1 && b.reseau.appels.count == 1 && b.usb.ouverts == 0, "rien n'est rouvert, eteint")
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) }, "la carte est la : l'USB")
        #expect(b.usb.chemins.count == 2)
    }

    /// Une sonde arretee en Automatique sur le reseau repart de l'annonce : pas d'annonce gardee d'avant l'arret.
    @Test func lAnnonceNeSurvitPasALArret() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        b.annoncer(true)
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        b.sonde.arreter()
        #expect(!b.sonde.annoncee && b.sonde.liaison == .usb)
        b.sonde.demarrer()
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.reseau.appels.count == 1 && b.sonde.etat == .absente, "pas d'annonce, pas de reseau")
        b.annoncer(true)
        #expect(await attendreActivation { b.connectee(par: .reseau) })
    }

    /// « Oublier la sonde » : la preference de liaison part (comme avant), le reglage revient a Automatique.
    @Test func oublierRevientAAutomatique() async throws {
        let b = try Banc(reglage: "usb", branches: [Banc.retenue])
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { b.connectee(par: .usb) })
        await b.sonde.oublier()
        #expect(b.sonde.reglage == .automatique && b.sonde.liaison == .usb)
        #expect(b.preferences.string(forKey: SondeMaillageThread.cleLiaison) == nil)
    }

    // MARK: - Le signal « annoncee » vient de Bonjour, dans l'app

    /// Le modele de Thread donne a la sonde les hotes de son instantane : branchement de l'app (`ModulesApp.relierThread`).
    @Test func lInstantaneDeThreadAnnonceLaSonde() async throws {
        let b = try Banc(branches: [])
        defer { b.nettoyer() }
        let s = Surveillance(mode: .direct, dossier: nil)
        ModulesApp.relierThread(s, sonde: b.sonde)
        #expect(!b.sonde.annoncee && b.reseau.appels.isEmpty)
        // Un releve ou la sonde (son hote SRP) est annoncee avec une adresse : le reseau.
        let hote = Banc.hote
        var a = AdresseVerifieeAppTests.annonces(Date(timeIntervalSince1970: 0))
        a.matter.append(AnnonceService(instance: "0000000000000F01-00000000000000AA", hote: hote + ".local", port: 5540))
        a.adresses[hote + ".local"] = [AdresseVerifieeAppTests.adresse(9)]
        s.thread.integrer(a)
        #expect(b.sonde.annoncee)
        #expect(await attendreActivation { b.connectee(par: .reseau) })
        // Puis un releve ou elle n'est plus la : plus annoncee (la session ouverte reste).
        // (L'instantane garde un hote disparu au-dela du sursis de 2 min : deux releves plus tard.)
        s.thread.integrer(AdresseVerifieeAppTests.annonces(Date(timeIntervalSince1970: 200)))
        s.thread.integrer(AdresseVerifieeAppTests.annonces(Date(timeIntervalSince1970: 400)))
        #expect(!b.sonde.annoncee && b.connectee(par: .reseau))
    }
}

/// Le selecteur de liaison de la page Thread : toujours la ; grise avec le reste de la page quand Thread est eteint.
@MainActor
@Suite("Reglages Thread : selecteur de liaison", .serialized, .timeLimit(.minutes(1)))
struct SelecteurLiaisonThreadTests {
    /// Le controle segmente de la page (« Automatique », « USB », « Reseau Thread »).
    static func segments(_ onglets: OngletsReglages) -> NSSegmentedControl? {
        let page = onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view
        return ReglagesProtocoleEteintTests.controles(page).compactMap { $0 as? NSSegmentedControl }
            .first { $0.segmentCount == 3 }
    }

    static func sonde(cle: Bool) throws -> (SondeMaillageThread, UserDefaults) {
        let (p, _) = try SondeMaillageTests.preferences()
        p.set("A0:00:00:00:00:01", forKey: SondeMaillageThread.cleSerie)
        p.set(SondeReseauTests.hote, forKey: SondeMaillageThread.cleHote)
        let t = TrousseauMemoireThread()
        if cle { try t.ranger(nom: SondeReseauTests.hote, cle: VecteursH1.psk, empreinte: "630DCD29") }
        return (SondeReseauTests.sondeMaillage(p, trousseau: t), p)
    }

    /// Toujours visible, avec ou sans cle ; sans cle, « Reseau Thread » ne se choisit pas (le choix est refuse, rien n'est
    /// ecrit) ; avec la cle, il se choisit.
    @Test(arguments: [true, false]) func toujoursVisible(_ cle: Bool) async throws {
        let (sonde, p) = try Self.sonde(cle: cle)
        let (fenetre, onglets) = try await ReglagesHauteurTests.fenetre(onglet: .thread, sondeThread: sonde)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        _ = try await ReglagesHauteurTests.attendreAjustement(fenetre, onglets)
        let seg = try #require(Self.segments(onglets), "le selecteur est la, cle \(cle)")
        #expect(seg.label(forSegment: 0) == String(localized: "Automatique"))
        #expect(seg.label(forSegment: 1) == String(localized: "USB"))
        #expect(seg.label(forSegment: 2) == String(localized: "Réseau Thread"))
        #expect(seg.isEnabled)
        #expect(seg.selectedSegment == 0, "Automatique est le reglage d'une nouvelle installation")
        seg.selectedSegment = 2
        seg.performClick(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(sonde.reglage == (cle ? .reseau : .automatique), "« Réseau Thread » indisponible tant que la cle est inconnue")
        if !cle { #expect(p.string(forKey: SondeMaillageThread.cleLiaison) == nil) }
        await sonde.oublier()
    }

    /// L'explication de « Reseau Thread » indisponible : la, tant que la cle est inconnue ; rien une fois la cle connue.
    @Test func explicationDeLIndisponibilite() {
        #expect(FenetreReglages.noteReseauIndisponible(reseauDisponible: false)
            == String(localized: "« Réseau Thread » est disponible une fois l'accès réseau autorisé : sonde branchée en USB, puis « Autoriser l'accès réseau »."))
        #expect(FenetreReglages.noteReseauIndisponible(reseauDisponible: true) == nil)
    }

    /// Thread eteint, le selecteur est grise comme le reste de la page (decision 5 : `PageProtocole`), et revient allume.
    @Test func griseAvecLaPage() async throws {
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let (fenetre, onglets) = try await ReglagesHauteurTests.fenetre(
            onglet: .thread, sondeThread: try Self.sonde(cle: true).0, surveillance: surveillance)
        defer { fenetre.close() }
        try await ReglagesProtocoleEteintTests.attendre(onglets) { _, a in !a.isEmpty && a.allSatisfy { $0.isEnabled } }
        #expect(try #require(Self.segments(onglets)).isEnabled, "allume")
        surveillance.thread.actif = false
        try await ReglagesProtocoleEteintTests.attendre(onglets) { _, a in a.allSatisfy { !$0.isEnabled } }
        #expect(try #require(Self.segments(onglets)).isEnabled == false, "eteint, le selecteur de liaison est grise")
        surveillance.thread.actif = true
        try await ReglagesProtocoleEteintTests.attendre(onglets) { _, a in a.allSatisfy { $0.isEnabled } }
        #expect(try #require(Self.segments(onglets)).isEnabled, "rallume")
    }
}
