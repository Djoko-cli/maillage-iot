import Foundation
import MaillageCoeur
import Observation
import Testing
@testable import MaillageIoT

// Les cartes retenues (tache 12, spec 3.4) : le registre, puis les deux sondes ensemble. Ports, canaux, suivi des ports et
// Bonjour sont factices (`ActivationFactices`) : aucun port reel, aucune carte reelle, des numeros de serie inventes.
// Ouvrir un port fait basculer DTR/RTS : une carte de l'autre module, ou inconnue, ne doit jamais l'etre.

/// Les cartes branchees des tests : la sonde Thread, la sonde Zigbee, un C6 inconnu (le pont d'un autre projet).
private let carteThread = PortUSB(chemin: "/dev/cu.usbmodemFACTICE01", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                                  produit: nil)
private let carteZigbee = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:02",
                                  produit: nil)
private let carteInconnue = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: "FACTICE-03",
                                    produit: nil)

@MainActor
@Suite("Registre des cartes retenues", .timeLimit(.minutes(1)))
struct CartesRetenuesTests {
    @Test func uneCarteRetenueSeLitParSonModule() {
        let c = CartesRetenues()
        #expect(c.serie(de: .thread) == nil && c.serie(de: .zigbee) == nil)
        c.retenir("A0:00:00:00:00:01", par: .thread)
        #expect(c.serie(de: .thread) == "A0:00:00:00:00:01" && c.serie(de: .zigbee) == nil)
        c.retenir("A0:00:00:00:00:02", par: .zigbee)
        #expect(c.serie(de: .zigbee) == "A0:00:00:00:00:02")
        #expect(c.retenuePar("A0:00:00:00:00:01") == .thread && c.retenuePar("A0:00:00:00:00:02") == .zigbee)
        #expect(c.retenuePar("A0:00:00:00:00:09") == nil && c.retenuePar(nil) == nil)
    }

    /// Retenir nil ou une serie vide rend la carte ; une carte inconnue (sans serie) n'est jamais retenue par personne.
    @Test func rendreUneCarte() {
        let c = CartesRetenues()
        c.retenir("A0:00:00:00:00:01", par: .thread)
        c.retenir(nil, par: .thread)
        #expect(c.serie(de: .thread) == nil && c.retenuePar("A0:00:00:00:00:01") == nil)
        c.retenir("", par: .zigbee)
        #expect(c.serie(de: .zigbee) == nil && c.retenuePar("") == nil)
    }

    /// L'autre module : un module ne se compte pas lui-meme, et sa propre carte lui reste proposee.
    @Test func lAutreModuleSeulCompte() {
        let c = CartesRetenues()
        c.retenir("A0:00:00:00:00:01", par: .thread)
        #expect(c.retenueParUnAutre("A0:00:00:00:00:01", que: .zigbee))
        #expect(!c.retenueParUnAutre("A0:00:00:00:00:01", que: .thread))
        #expect(!c.retenueParUnAutre("A0:00:00:00:00:02", que: .zigbee))
        #expect(!c.retenueParUnAutre(nil, que: .zigbee), "un port sans serie n'est a personne")
        #expect(c.choix([carteThread, carteZigbee, carteInconnue], pour: .zigbee).map(\.chemin)
            == [carteZigbee.chemin, carteInconnue.chemin])
        #expect(c.choix([carteThread, carteZigbee, carteInconnue], pour: .thread).count == 3)
    }

    /// Deux modules qui revendiquent la meme carte (preferences anciennes) : aucun des deux ne l'ouvre ni ne la propose.
    @Test func revendicationDouble() {
        let c = CartesRetenues()
        c.retenir("A0:00:00:00:00:01", par: .thread)
        c.retenir("A0:00:00:00:00:01", par: .zigbee)
        #expect(c.retenueParUnAutre("A0:00:00:00:00:01", que: .thread) && c.retenueParUnAutre("A0:00:00:00:00:01", que: .zigbee))
        #expect(c.choix([carteThread], pour: .thread).isEmpty && c.choix([carteThread], pour: .zigbee).isEmpty)
    }

    /// Observable : une liste qui lit le registre est relue quand l'autre module retient ou rend une carte.
    @Test func leRegistreEstObservable() {
        let c = CartesRetenues()
        let vu = CompteurAppels()
        withObservationTracking { _ = c.choix([carteThread], pour: .zigbee) } onChange: { vu.incrementer() }
        c.retenir("A0:00:00:00:00:01", par: .thread)
        #expect(vu.valeur == 1)
        withObservationTracking { _ = c.choix([carteThread], pour: .zigbee) } onChange: { vu.incrementer() }
        c.retenir("A0:00:00:00:00:01", par: .thread)
        #expect(vu.valeur == 1, "retenir la meme serie ne change rien")
        c.retenir(nil, par: .thread)
        #expect(vu.valeur == 2)
    }

    @Test func leTexteDeRefusNommeLaSondeDeLAutre() {
        #expect(CartesRetenues.texteRefus(retenuePar: .thread).contains("Thread"))
        #expect(CartesRetenues.texteRefus(retenuePar: .zigbee).contains("Zigbee"))
        #expect(CartesRetenues.texteRefus(retenuePar: .thread) != CartesRetenues.texteRefus(retenuePar: .zigbee))
    }

    /// `ModulesApp` donne le meme registre aux deux sondes : une carte retenue par Thread disparait des choix de Zigbee.
    @Test func lAppPartageUnSeulRegistre() {
        let m = ModulesApp(demo: nil, sousTests: true)
        m.cartes.retenir(carteThread.serie, par: .thread)
        m.sondeZigbee.portsChanges([carteThread, carteInconnue])
        m.sondeThread.portsChanges([carteThread, carteInconnue])
        #expect(m.sondeZigbee.ports.map(\.chemin) == [carteInconnue.chemin])
        #expect(m.sondeThread.ports.count == 2)
        m.cartes.retenir(carteInconnue.serie, par: .zigbee)
        #expect(m.sondeThread.ports.map(\.chemin) == [carteThread.chemin])
    }
}

@MainActor
@Suite("Deux sondes en meme temps : une carte n'est ouverte que par son module", .timeLimit(.minutes(1)))
struct DeuxSondesTests {
    @MainActor struct Banc {
        let cartes: CartesRetenues
        let thread: SondeMaillageThread
        let zigbee: SondeMaillageZigbee
        /// Les ports que chaque sonde a demande a ouvrir.
        let ouvertsThread: RegistrePorts
        let ouvertsZigbee: RegistrePorts
        let portsThread: FabriquePorts
        let portsZigbee: FabriquePorts
        let nettoyage: () -> Void

        func nettoyer() {
            thread.arreter()
            zigbee.arreter()
            nettoyage()
        }

        /// Un evenement USB : les deux sondes voient la meme liste.
        func brancher(_ liste: [PortUSB]) {
            portsThread.brancher(liste)
            portsZigbee.brancher(liste)
        }

        var chemins: Set<String> { Set(ouvertsThread.chemins + ouvertsZigbee.chemins) }
    }

    /// Les deux sondes sur un meme registre. `threadRetient` / `zigbeeRetient` : leur carte est deja retenue (preferences) ;
    /// `branches` : les cartes vues au demarrage ; `canalThread` : le canal ouvert pour Thread (le registre le compte).
    static func banc(threadRetient: Bool = true, zigbeeRetient: Bool = true,
                     branches: [PortUSB] = [carteThread, carteZigbee, carteInconnue],
                     cartes: CartesRetenues = CartesRetenues(),
                     avantOuverture: @escaping @MainActor (String) -> Void = { _ in }) throws -> Banc {
        let (pt, dt) = try SondeMaillageTests.preferences()
        let (pz, dz) = try SondeMaillageZigbeeTests.preferences()
        if threadRetient { pt.set(carteThread.serie, forKey: SondeMaillageThread.cleSerie) }
        if zigbeeRetient {
            pz.set(carteZigbee.serie, forKey: SondeMaillageZigbee.cleSerie)
            pz.set("SONDE-01", forKey: SondeMaillageZigbee.cleNom)
        }
        let ot = RegistrePorts(), oz = RegistrePorts()
        let ft = FabriquePorts(), fz = FabriquePorts()
        let thread = SondeMaillageThread(
            preferences: pt, actif: true,
            ouvrirCanal: { avantOuverture($0); return ot.canal($0, CanalRejoue { CanalRejoue.reseauMinimal($0) }) },
            surveillerPorts: ft.fabriquer, listerPorts: { branches }, cartes: cartes)
        let zigbee = SondeMaillageZigbee(
            preferences: pz, actif: true, trousseau: TrousseauMemoireZigbee(),
            ouvrirCanal: { avantOuverture($0); return oz.canal($0, CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) }) },
            periodeEntretien: .seconds(3600), delaiNouvelEssai: .seconds(3600), delaiPremiereTournee: .seconds(3600),
            surveillerPorts: fz.fabriquer, listerPorts: { branches }, fabriqueBonjour: FabriqueBonjour().fabriquer,
            cartes: cartes)
        return Banc(cartes: cartes, thread: thread, zigbee: zigbee, ouvertsThread: ot, ouvertsZigbee: oz,
                    portsThread: ft, portsZigbee: fz,
                    nettoyage: { pt.removePersistentDomain(forName: dt); pz.removePersistentDomain(forName: dz) })
    }

    private static func chemins(_ ports: [PortUSB]) -> [String] { ports.map(\.chemin) }

    /// Chaque sonde retient sa carte et ne voit pas celle de l'autre ; un C6 inconnu est propose aux deux, ouvert par aucune.
    @Test func chaqueModuleVoitSaCarteEtPasCelleDeLAutre() async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        #expect(b.cartes.serie(de: .thread) == carteThread.serie, "publiee des la lecture des preferences")
        #expect(b.cartes.serie(de: .zigbee) == carteZigbee.serie)
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) && SondeMaillageZigbeeTests.connectee(b.zigbee) })
        #expect(Self.chemins(b.thread.ports) == [carteThread.chemin, carteInconnue.chemin])
        #expect(Self.chemins(b.zigbee.ports) == [carteZigbee.chemin, carteInconnue.chemin])
        #expect(b.ouvertsThread.chemins == [carteThread.chemin], "Thread n'ouvre que sa carte")
        #expect(b.ouvertsZigbee.chemins == [carteZigbee.chemin], "Zigbee n'ouvre que sa carte")
    }

    /// Un choix de Zigbee qui vise la carte de Thread est refuse, avec un message ; rien n'est ouvert, rien n'est retenu.
    @Test func zigbeeNOuvrePasLaCarteDeThread() async throws {
        let b = try Self.banc(zigbeeRetient: false)
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) })
        #expect(!Self.chemins(b.zigbee.ports).contains(carteThread.chemin))

        b.zigbee.choisir(carteThread)
        #expect(b.zigbee.choixRefuse == CartesRetenues.texteRefus(retenuePar: .thread))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.ouvertsZigbee.chemins.isEmpty, "Zigbee n'a rien ouvert")
        #expect(b.zigbee.etat == .sansSonde && b.zigbee.serie == nil && b.cartes.serie(de: .zigbee) == nil)
        #expect(b.cartes.serie(de: .thread) == carteThread.serie, "Thread garde sa carte")
        // Une connexion demandee directement, avec une liste perimee, ne l'ouvre pas non plus.
        await b.zigbee.connecter(carteThread, choisi: true)
        await b.zigbee.connecter(carteThread, choisi: false)
        #expect(b.ouvertsZigbee.chemins.isEmpty && b.zigbee.etat == .sansSonde)
    }

    /// Et l'inverse : Thread ne choisit pas la carte de Zigbee.
    @Test func threadNOuvrePasLaCarteDeZigbee() async throws {
        let b = try Self.banc(threadRetient: false)
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.zigbee) })
        #expect(!Self.chemins(b.thread.ports).contains(carteZigbee.chemin))

        b.thread.choisir(carteZigbee)
        #expect(b.thread.choixRefuse == CartesRetenues.texteRefus(retenuePar: .zigbee))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.ouvertsThread.chemins.isEmpty, "Thread n'a rien ouvert")
        #expect(b.thread.etat == .sansSonde && b.thread.serie == nil && b.cartes.serie(de: .thread) == nil)
        await b.thread.connecter(carteZigbee, choisi: true)
        await b.thread.connecter(carteZigbee, choisi: false)
        #expect(b.ouvertsThread.chemins.isEmpty && b.thread.etat == .sansSonde)
    }

    /// Un C6 inconnu n'est jamais ouvert de lui-meme, ni par Thread ni par Zigbee en Automatique, avec ou sans carte retenue
    /// (absente), a l'arrivee comme au demarrage.
    @Test func uneCarteInconnueNEstJamaisOuverte() async throws {
        for retenues in [false, true] {
            let b = try Self.banc(threadRetient: retenues, zigbeeRetient: retenues, branches: [carteInconnue])
            defer { b.nettoyer() }
            #expect(b.zigbee.reglageChemin == .automatique)
            b.thread.demarrer()
            b.zigbee.demarrer()
            b.brancher([carteInconnue])
            b.thread.portsChanges([carteInconnue])
            b.zigbee.portsChanges([carteInconnue])
            // Meme demandee directement (une connexion automatique), sans choix de l'utilisateur : aucun port.
            await b.thread.connecter(carteInconnue, choisi: false)
            await b.zigbee.connecter(carteInconnue, choisi: false)
            try await Task.sleep(for: .milliseconds(150))
            #expect(b.chemins.isEmpty, "retenues \(retenues) : \(b.chemins)")
            #expect(b.thread.ports.count == 1 && b.zigbee.ports.count == 1, "proposee, jamais ouverte d'elle-meme")
            #expect(b.thread.tachesPlanifiees == 0 && b.zigbee.tachesPlanifiees == 0)
        }
    }

    /// La carte de l'autre, branchee seule alors que la sienne manque : elle n'est pas prise pour la sienne.
    @Test func laCarteDeLAutreNeRemplacePasLaSienne() async throws {
        let b = try Self.banc(branches: [])
        defer { b.nettoyer() }
        // Chacune ne voit que la carte de l'autre.
        b.thread.demarrer()
        b.zigbee.demarrer()
        b.thread.portsChanges([carteZigbee])
        b.zigbee.portsChanges([carteThread])
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.thread.ports.isEmpty && b.zigbee.ports.isEmpty)
        #expect(b.thread.etat == .absente && b.zigbee.etat == .absente)
        #expect(b.chemins.isEmpty, "ni l'une ni l'autre n'est ouverte : \(b.chemins)")
    }

    /// « Oublier la sonde » rend la carte aux choix de l'autre module, sans nouvel evenement USB ; l'autre peut alors la choisir.
    @Test func oublierRendLaCarteALAutre() async throws {
        let b = try Self.banc(zigbeeRetient: false, branches: [carteThread, carteInconnue])
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) })
        #expect(Self.chemins(b.zigbee.ports) == [carteInconnue.chemin])

        await b.thread.oublier()
        #expect(b.cartes.serie(de: .thread) == nil && b.thread.serie == nil)
        #expect(Self.chemins(b.zigbee.ports) == [carteThread.chemin, carteInconnue.chemin], "rendue, sans evenement USB")
        b.zigbee.choisir(carteThread)
        #expect(b.zigbee.choixRefuse == nil)
        #expect(await attendreActivation { b.ouvertsZigbee.chemins == [carteThread.chemin] })
        // Le choix retient la carte pour Zigbee : Thread ne la voit plus.
        #expect(await attendreActivation { b.cartes.serie(de: .zigbee) == carteThread.serie })
        #expect(!Self.chemins(b.thread.ports).contains(carteThread.chemin))
    }

    /// Le meme aller-retour, de Zigbee vers Thread.
    @Test func zigbeeOublieEtThreadPeutChoisir() async throws {
        let b = try Self.banc(threadRetient: false, branches: [carteZigbee])
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.zigbee) })
        #expect(b.thread.ports.isEmpty)
        await b.zigbee.oublier()
        #expect(b.cartes.serie(de: .zigbee) == nil)
        #expect(Self.chemins(b.thread.ports) == [carteZigbee.chemin])
        b.thread.choisir(carteZigbee)
        #expect(b.thread.choixRefuse == nil)
        #expect(await attendreActivation { b.ouvertsThread.chemins == [carteZigbee.chemin] })
    }

    /// Un choix reussi publie la serie : l'autre module ne voit plus la carte, et la retient meme sans preference lue.
    @Test func unChoixRetientEtPublie() async throws {
        let b = try Self.banc(threadRetient: false, zigbeeRetient: false, branches: [carteThread, carteInconnue])
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(Self.chemins(b.zigbee.ports) == [carteThread.chemin, carteInconnue.chemin])
        b.thread.choisir(carteThread)
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) })
        #expect(b.cartes.serie(de: .thread) == carteThread.serie)
        #expect(Self.chemins(b.zigbee.ports) == [carteInconnue.chemin])
        #expect(b.ouvertsZigbee.chemins.isEmpty)
    }

    /// Protocole eteint : sa carte reste reservee (jamais proposee ni ouverte par l'autre), eteint comme rallume. Rendre
    /// la carte l'offrirait a l'autre module, puis le rallumage rouvrirait la meme carte.
    @Test func unProtocoleEteintGardeSaCarte() async throws {
        let b = try Self.banc(branches: [carteThread, carteZigbee, carteInconnue])
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) && SondeMaillageZigbeeTests.connectee(b.zigbee) })

        b.thread.arreter()
        #expect(!b.thread.actif)
        #expect(b.cartes.serie(de: .thread) == carteThread.serie, "la carte reste reservee")
        #expect(!Self.chemins(b.zigbee.ports).contains(carteThread.chemin))
        b.brancher([carteThread, carteZigbee, carteInconnue])
        b.zigbee.choisir(carteThread)
        #expect(b.zigbee.choixRefuse == CartesRetenues.texteRefus(retenuePar: .thread))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.ouvertsZigbee.chemins == [carteZigbee.chemin], "Zigbee n'a ouvert que la sienne")

        b.thread.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) })
        #expect(b.ouvertsThread.chemins == [carteThread.chemin, carteThread.chemin], "la meme carte, rouverte par Thread")
        #expect(!Self.chemins(b.zigbee.ports).contains(carteThread.chemin))
    }

    /// Un protocole eteint des le lancement garde aussi sa carte : sa sonde lit ses preferences meme sans demarrer.
    @Test func unProtocoleEteintAuLancementGardeSaCarte() throws {
        let b = try Self.banc(zigbeeRetient: false)
        defer { b.nettoyer() }
        // Thread n'est jamais demarre (eteint au lancement) ; Zigbee tourne.
        b.zigbee.demarrer()
        b.portsZigbee.brancher([carteThread, carteInconnue])
        #expect(Self.chemins(b.zigbee.ports) == [carteInconnue.chemin])
        #expect(b.ouvertsThread.chemins.isEmpty && b.ouvertsZigbee.chemins.isEmpty)
    }

    /// Les deux modules choisissent la meme carte en meme temps : la seconde connexion, qui voit la carte retenue par l'autre
    /// a la fin, se referme et ne se retient pas.
    @Test func laMemeCarteDemandeeParLesDeuxModules() async throws {
        let cartes = CartesRetenues()
        let faits = CompteurAppels()
        let b = try Self.banc(threadRetient: false, zigbeeRetient: false, branches: [carteInconnue], cartes: cartes,
                              avantOuverture: { _ in
            // Zigbee retient la carte juste apres que Thread a passe sa garde, avant la fin de sa connexion.
            if faits.valeur == 0 { cartes.retenir(carteInconnue.serie, par: .zigbee) }
            faits.incrementer()
        })
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.thread.choisir(carteInconnue)
        #expect(await attendreActivation { if case .refusee = b.thread.etat { true } else { false } })
        guard case .refusee(let m) = b.thread.etat else { return }
        #expect(m == CartesRetenues.texteRefus(retenuePar: .zigbee))
        #expect(b.thread.serie == nil && cartes.serie(de: .thread) == nil, "Thread ne retient pas la carte de Zigbee")
        #expect(cartes.serie(de: .zigbee) == carteInconnue.serie)
        #expect(await attendreActivation { b.ouvertsThread.ouverts == 0 }, "sa liaison est refermee")
    }

    // MARK: Une sonde n'est jamais bloquee en « connexion » (relecture finale, m1)

    /// Thread : l'autre module retient la carte entre `choisir` (qui passe en `.connexion`) et le depart de la tache : la sonde
    /// passe en `.refusee`, au lieu de rester en « connexion… » jusqu'au prochain evenement ; rien n'est ouvert.
    @Test func threadRefuseeSiLaCarteEstRetenueEntreLeChoixEtLeDepart() async throws {
        let b = try Self.banc(threadRetient: false, zigbeeRetient: false, branches: [carteInconnue])
        defer { b.nettoyer() }
        b.thread.demarrer()
        b.thread.choisir(carteInconnue)
        #expect(b.thread.etat == .connexion)
        b.cartes.retenir(carteInconnue.serie, par: .zigbee)
        #expect(await attendreActivation { b.thread.etat != .connexion }, "jamais bloquee en connexion")
        #expect(b.thread.etat == .refusee(CartesRetenues.texteRefus(retenuePar: .zigbee)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.ouvertsThread.chemins.isEmpty && b.thread.serie == nil, "rien d'ouvert, rien de retenu")
        #expect(b.thread.tachesPlanifiees == 0)
    }

    /// Zigbee : le meme cas.
    @Test func zigbeeRefuseeSiLaCarteEstRetenueEntreLeChoixEtLeDepart() async throws {
        let b = try Self.banc(threadRetient: false, zigbeeRetient: false, branches: [carteInconnue])
        defer { b.nettoyer() }
        b.zigbee.demarrer()
        b.zigbee.choisir(carteInconnue)
        #expect(b.zigbee.etat == .connexion)
        b.cartes.retenir(carteInconnue.serie, par: .thread)
        #expect(await attendreActivation { b.zigbee.etat != .connexion }, "jamais bloquee en connexion")
        #expect(b.zigbee.etat == .refusee(CartesRetenues.texteRefus(retenuePar: .thread)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.ouvertsZigbee.chemins.isEmpty && b.zigbee.serie == nil, "rien d'ouvert, rien de retenu")
    }

    /// Thread : la carte est retenue par l'autre module pendant l'attente de la fermeture de la liaison en place (apres la
    /// premiere garde de `connecter`) : `ouvrable` est reverifiee juste avant d'ouvrir le canal. Rien n'est ouvert.
    @Test func threadReverifieAvantOuvrir() async throws {
        let b = try Self.banc(branches: [carteThread, carteInconnue])
        defer { b.nettoyer() }
        b.thread.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.thread) })
        let ouvertures = b.ouvertsThread.chemins.count
        // `connecter` ferme la liaison en place (une tache) et l'attend : l'autre module retient la carte pendant ce temps.
        let t = Task { await b.thread.connecter(carteInconnue, choisi: true) }
        await Task.yield()
        b.cartes.retenir(carteInconnue.serie, par: .zigbee)
        await t.value
        #expect(b.ouvertsThread.chemins.count == ouvertures, "la carte de l'autre n'est pas ouverte : \(b.ouvertsThread.chemins)")
        #expect(b.thread.etat == .refusee(CartesRetenues.texteRefus(retenuePar: .zigbee)))
    }

    /// Zigbee : le meme cas.
    @Test func zigbeeReverifieAvantOuvrir() async throws {
        let b = try Self.banc(branches: [carteZigbee, carteInconnue])
        defer { b.nettoyer() }
        b.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.zigbee) })
        let ouvertures = b.ouvertsZigbee.chemins.count
        let t = Task { await b.zigbee.connecter(carteInconnue, choisi: true) }
        await Task.yield()
        b.cartes.retenir(carteInconnue.serie, par: .thread)
        await t.value
        #expect(b.ouvertsZigbee.chemins.count == ouvertures, "la carte de l'autre n'est pas ouverte : \(b.ouvertsZigbee.chemins)")
        #expect(b.zigbee.etat == .refusee(CartesRetenues.texteRefus(retenuePar: .thread)))
    }
}
