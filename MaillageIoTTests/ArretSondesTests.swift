import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

// « Activer ce protocole » (tache 11), cote des deux sondes : `arreter()` ferme le port, annule la boucle des tournees, les
// reprises et les relances ; `demarrer()` repart, avec la seule sonde retenue. Port serie, suivi des ports, Bonjour et
// reseau sont factices (`ActivationFactices`) : aucun port, aucun reseau, aucun trousseau reels. Une tache annulee ne
// s'observe pas par son effet (un numero d'essai perime la rend deja sans effet) mais par `tachesPlanifiees`.

/// Un C6 qui n'est pas la sonde retenue (le pont Halo, ou l'autre sonde) : branche, jamais ouvert.
private let autreCarte = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                                produit: nil)

@MainActor
@Suite("Arret de la sonde Thread (Activer ce protocole)", .timeLimit(.minutes(1)))
struct ArretSondeThreadTests {
    static let retenu = SondeMaillageTests.port

    struct Banc {
        let sonde: SondeMaillageThread
        let registre: RegistrePorts
        let ports: FabriquePorts
        let nettoyage: () -> Void

        func nettoyer() { nettoyage() }
    }

    /// Une sonde retenue (ou non : `serie` faux), deux C6 branches, un canal par port.
    static func banc(serie: Bool = true, delaiNouvelEssai: Duration = .seconds(3600),
                     canal: @escaping @Sendable (String, RegistrePorts) -> any CanalSonde = { chemin, registre in
                         registre.canal(chemin, CanalRejoue { CanalRejoue.reseauMinimal($0) })
                     }) throws -> Banc {
        let (p, domaine) = try SondeMaillageTests.preferences()
        if serie { p.set(retenu.serie, forKey: SondeMaillageThread.cleSerie) }
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let branches = [retenu, autreCarte]
        let s = SondeMaillageThread(preferences: p, actif: true, ouvrirCanal: { canal($0, registre) },
                                    delaiNouvelEssai: delaiNouvelEssai,
                                    surveillerPorts: ports.fabriquer, listerPorts: { branches })
        return Banc(sonde: s, registre: registre, ports: ports, nettoyage: { p.removePersistentDomain(forName: domaine) })
    }

    /// Arret : le port serie se ferme, la boucle des tournees est annulee, le suivi des ports s'arrete ; un evenement USB,
    /// un choix des Reglages ou un rafraichissement n'ouvrent plus rien.
    @Test func arretFermeLePortEtAnnuleLesTaches() async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.sonde) })
        #expect(b.registre.ouverts == 1 && b.registre.chemins == [Self.retenu.chemin], "seule la sonde retenue est ouverte")
        #expect(b.sonde.tachesPlanifiees == 1, "la boucle des tournees")
        #expect(b.ports.enMarche == 1)

        b.sonde.arreter()
        #expect(!b.sonde.actif)
        #expect(b.sonde.etat == .absente)
        #expect(b.sonde.tachesPlanifiees == 0, "boucle annulee, pas seulement rendue sans effet")
        #expect(b.ports.enMarche == 0, "le suivi des ports est arrete")
        #expect(await attendreActivation { b.registre.ouverts == 0 }, "le port serie est ferme")

        b.ports.brancher([Self.retenu, autreCarte])
        b.sonde.portsChanges([Self.retenu, autreCarte])
        b.sonde.choisir(Self.retenu)
        b.sonde.rafraichir()
        await b.sonde.connecterReseau()
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.registre.ouvertures == 1 && b.registre.ouverts == 0, "rien ne rouvre le port")
        #expect(b.sonde.etat == .absente && b.sonde.tachesPlanifiees == 0)
        #expect(b.sonde.ports.count == 2, "les ports restent listes (les Reglages)")
    }

    /// Rallumage : le suivi des ports repart et la sonde retenue, seule, est rouverte ; l'autre C6 branche n'est jamais ouvert.
    @Test func rallumageRepartAvecLaSerieRetenueSeule() async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.sonde) })
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })

        b.sonde.demarrer()
        #expect(b.sonde.actif)
        #expect(await attendreActivation { SondeMaillageTests.connectee(b.sonde) }, "etat \(b.sonde.etat)")
        #expect(b.registre.ouvertures == 2 && b.registre.ouverts == 1)
        #expect(Set(b.registre.chemins) == [Self.retenu.chemin], "jamais l'autre carte : \(b.registre.chemins)")
        #expect(b.ports.demarrages == 2 && b.ports.enMarche == 1)
        #expect(b.sonde.tachesPlanifiees == 1)
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })
    }

    /// Sans sonde retenue, ni au lancement ni apres un arret et un rallumage, aucun port n'est ouvert.
    @Test func sansSerieRetenueRienNeSOuvre() async throws {
        let b = try Self.banc(serie: false)
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(b.sonde.etat == .sansSonde && b.registre.chemins.isEmpty)
        b.sonde.arreter()
        #expect(b.sonde.etat == .sansSonde && b.sonde.tachesPlanifiees == 0)
        b.sonde.demarrer()
        b.ports.brancher([Self.retenu, autreCarte])
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.registre.chemins.isEmpty && b.sonde.ports.count == 2)
        b.sonde.arreter()
    }

    /// Le nouvel essai d'une connexion automatique en echec est annule par l'arret, pas seulement perime.
    @Test func nouvelEssaiPlanifieEstAnnule() async throws {
        let b = try Self.banc(delaiNouvelEssai: .milliseconds(300), canal: { chemin, registre in
            registre.canal(chemin, CanalEnPanne())
        })
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { if case .erreur = b.sonde.etat { true } else { false } })
        #expect(b.registre.chemins.count == 1 && b.sonde.tachesPlanifiees == 1, "le nouvel essai attend")
        b.sonde.arreter()
        #expect(b.sonde.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(700))
        #expect(b.registre.chemins.count == 1, "le nouvel essai n'a pas eu lieu")
    }

    /// Par le reseau Thread : la reprise planifiee apres un echec est annulee, aucune session n'est rouverte, et l'activite
    /// tenue pendant la session est rendue.
    @Test func repriseDeLaLiaisonReseauEstAnnulee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t = try SondeReseauTests.prete(p, liaison: .reseau)
        let reseau = ReseauFactice([.failure(ErreurReseau.nomIntrouvable(SondeReseauTests.hote))])
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let retenu = Self.retenu
        let s = SondeMaillageThread(preferences: p, actif: true,
                                    ouvrirCanal: { registre.canal($0, CanalRejoue { CanalRejoue.reseauMinimal($0) }) },
                                    trousseau: t, ouvrirReseau: { try reseau.ouvrir($0, $1) },
                                    delaisReprise: [.milliseconds(300)],
                                    surveillerPorts: ports.fabriquer, listerPorts: { [retenu] })
        s.demarrer()
        #expect(await attendreActivation { !reseau.appels.isEmpty })
        #expect(await attendreActivation { s.tachesPlanifiees == 1 }, "la reprise attend")
        s.arreter()
        #expect(s.tachesPlanifiees == 0)
        let essais = reseau.appels.count
        try await Task.sleep(for: .milliseconds(700))
        #expect(reseau.appels.count == essais, "aucune session rouverte")
        #expect(registre.chemins.isEmpty, "la liaison reseau n'ouvre aucun port USB, meme branche")
        s.demarrer()
        #expect(await attendreActivation { reseau.appels.count > essais }, "le rallumage reessaie")
        s.arreter()
    }

    /// Basculer vite (arret, rallumage, arret ; avec ou sans connexion etablie) ne laisse rien de vivant : aucun port ouvert,
    /// aucune tache, aucun suivi des ports.
    @Test(arguments: [false, true]) func basculesRapides(connectee: Bool) async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        if connectee { #expect(await attendreActivation { SondeMaillageTests.connectee(b.sonde) }) }
        b.sonde.arreter()
        b.sonde.demarrer()
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })
        #expect(b.sonde.tachesPlanifiees == 0 && !b.sonde.actif)
        #expect(b.ports.enMarche == 0 && b.ports.demarrages == b.ports.arrets)
        let ouvertures = b.registre.ouvertures
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.registre.ouvertures == ouvertures && b.registre.ouverts == 0, "plus rien ne s'ouvre apres coup")
        #expect(b.sonde.tachesPlanifiees == 0)
    }

    /// Une tournee en vol a l'arret est abandonnee : elle ne rapporte aucun maillage, et le modele est prevenu de sa fin.
    @Test func tourneeEnVolAbandonnee() async throws {
        let journal = JournalCanaux()
        let canal = SondeMaillageTests.canalRetenu(journal)
        let b = try Self.banc(canal: { chemin, registre in registre.canal(chemin, canal) })
        defer { b.nettoyer() }
        var maillages = 0
        var enCours: [Bool] = []
        b.sonde.surMaillage = { _, _ in maillages += 1 }
        b.sonde.surTournee = { enCours.append($0) }
        b.sonde.demarrer()
        #expect(await attendreActivation { b.sonde.tourneeEnCours })
        b.sonde.arreter()
        #expect(await attendreActivation { !b.sonde.tourneeEnCours && enCours.last == false }, "\(enCours)")
        canal.emettre(CanalRejoue.reseauMinimal(SondeMaillageTests.listeRetenue + "\n"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(maillages == 0 && b.sonde.derniereTournee == nil)
        #expect(b.sonde.tachesPlanifiees == 0)
    }

    /// La sonde de la demo et des tests est inerte : `arreter` et `demarrer` ne la reveillent pas.
    @Test func sondeInerteResteInerte() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let ports = FabriquePorts()
        let retenu = Self.retenu
        let s = SondeMaillageThread(preferences: p, actif: false, surveillerPorts: ports.fabriquer,
                                    listerPorts: { [retenu] })
        s.demarrer()
        s.arreter()
        s.demarrer()
        #expect(!s.actif && ports.crees.isEmpty && s.ports.isEmpty && s.tachesPlanifiees == 0)
    }
}

@MainActor
@Suite("Arret de la sonde Zigbee (Activer ce protocole)", .timeLimit(.minutes(1)))
struct ArretSondeZigbeeTests {
    static let retenu = SondeMaillageZigbeeTests.port
    static let cle = SondeParReseauTests.cle

    struct Banc {
        let sonde: SondeMaillageZigbee
        let registre: RegistrePorts
        let ports: FabriquePorts
        let bonjour: FabriqueBonjour
        /// Les connexions par le reseau demandees (nom de l'instance).
        let reseau: Compteur
        let nettoyage: () -> Void

        func nettoyer() { nettoyage() }

        /// La sonde est annoncee sur le reseau local (l'ecoute Bonjour en marche la voit).
        @MainActor func annoncer() { bonjour.crees.last { $0.enMarche }?.voir("SONDE-01") }
    }

    /// Une sonde retenue (serie, nom, adresse longue, cle du reseau), deux C6 branches ; `canal` : le canal d'un port USB,
    /// `canalReseau` : celui d'une session par le reseau.
    static func banc(serie: Bool = true, branchee: Bool = true,
                     canal: @escaping @Sendable (String, RegistrePorts) -> any CanalSonde = { chemin, registre in
                         registre.canal(chemin, CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) })
                     },
                     canalReseau: @escaping @Sendable (String, RegistrePorts) -> any CanalSonde = { nom, registre in
                         registre.canal("reseau:\(nom)", CanalRejoueZigbee(repondre: SondeParReseauTests.sondeReseau))
                     }) throws -> Banc {
        let (p, domaine) = try SondeMaillageZigbeeTests.preferences()
        if serie {
            p.set(retenu.serie, forKey: SondeMaillageZigbee.cleSerie)
            p.set("SONDE-01", forKey: SondeMaillageZigbee.cleNom)
            p.set("A000000000000001", forKey: SondeMaillageZigbee.cleIeee)
        }
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let bonjour = FabriqueBonjour()
        let reseau = Compteur()
        let branches = branchee ? [retenu, autreCarte] : [autreCarte]
        let s = SondeMaillageZigbee(
            preferences: p, actif: true, trousseau: TrousseauMemoireZigbee(["A000000000000001": cle]),
            ouvrirCanal: { canal($0, registre) },
            ouvrirReseau: { nom, _ in
                reseau.ajouter(nom)
                return canalReseau(nom, registre)
            },
            delaiReessaiReseau: .milliseconds(300), periodeEntretien: .seconds(3600), delaiNouvelEssai: .milliseconds(300),
            delaiPremiereTournee: .seconds(3600),
            surveillerPorts: ports.fabriquer, listerPorts: { branches }, fabriqueBonjour: bonjour.fabriquer)
        return Banc(sonde: s, registre: registre, ports: ports, bonjour: bonjour, reseau: reseau,
                    nettoyage: { SondeMaillageZigbeeTests.nettoyer(p, domaine) })
    }

    /// Arret par l'USB : le port se ferme, la boucle des tournees est annulee, le suivi des ports et l'ecoute Bonjour
    /// s'arretent ; ni un evenement USB, ni une annonce, ni un choix ne rouvrent rien.
    @Test func arretFermeLePortEtAnnuleLesTaches() async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.sonde) })
        #expect(await attendreActivation { b.sonde.tachesPlanifiees == 1 }, "la boucle des tournees")
        #expect(b.registre.ouverts == 1 && b.registre.chemins == [Self.retenu.chemin])
        #expect(b.ports.enMarche == 1 && b.bonjour.enMarche == 1)
        #expect(b.bonjour.types == ["_maillage-zigbee._tcp"], "l'ecoute des sondes du reseau")

        b.sonde.arreter()
        #expect(!b.sonde.actif && b.sonde.etat == .absente)
        #expect(b.sonde.tachesPlanifiees == 0, "boucle annulee, pas seulement rendue sans effet")
        #expect(b.ports.enMarche == 0 && b.bonjour.enMarche == 0)
        #expect(await attendreActivation { b.registre.ouverts == 0 })

        b.ports.brancher([Self.retenu, autreCarte])
        b.sonde.portsChanges([Self.retenu, autreCarte])
        b.sonde.annoncesChangees(["SONDE-01"])
        b.sonde.choisir(Self.retenu)
        b.sonde.rafraichir()
        await b.sonde.connecterReseau()
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.registre.ouvertures == 1 && b.reseau.noms.isEmpty, "rien ne rouvre le port ni le reseau")
        #expect(b.sonde.etat == .absente && b.sonde.tachesPlanifiees == 0 && !b.sonde.annoncee)
    }

    /// Rallumage : le suivi des ports et l'ecoute Bonjour repartent (neufs), la sonde retenue, seule, est rouverte.
    @Test func rallumageRepartAvecLaSerieRetenueSeule() async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.sonde) })
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })

        b.sonde.demarrer()
        #expect(b.sonde.actif)
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.sonde) }, "etat \(b.sonde.etat)")
        #expect(b.registre.ouvertures == 2 && b.registre.ouverts == 1)
        #expect(Set(b.registre.chemins) == [Self.retenu.chemin], "jamais l'autre carte : \(b.registre.chemins)")
        #expect(b.ports.demarrages == 2 && b.ports.enMarche == 1)
        #expect(b.bonjour.crees.count == 2 && b.bonjour.enMarche == 1)
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })
    }

    /// Par le reseau : l'entretien (relecture d'`etat`), la boucle des tournees et la session sont arretes ; une annonce
    /// tardive ne rouvre pas la session.
    @Test func arretParLeReseau() async throws {
        let b = try Self.banc(branchee: false)
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer()
        #expect(await attendreActivation { b.sonde.acces == .reseau }, "etat \(b.sonde.etat)")
        #expect(await attendreActivation { b.sonde.tachesPlanifiees == 2 }, "tournees et entretien")
        #expect(b.reseau.noms == ["SONDE-01"] && b.registre.ouverts == 1)
        #expect(b.registre.chemins == ["reseau:SONDE-01"], "la session reseau, aucun port USB")

        let ecoute = try #require(b.bonjour.crees.last)
        b.sonde.arreter()
        #expect(b.sonde.tachesPlanifiees == 0 && b.sonde.acces == nil && !b.sonde.annoncee)
        #expect(!ecoute.enMarche && ecoute.surChangement == nil)
        #expect(await attendreActivation { b.registre.ouverts == 0 }, "la session reseau est fermee")
        ecoute.voir("SONDE-01")
        b.sonde.annoncesChangees(["SONDE-01"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.reseau.noms == ["SONDE-01"], "pas de seconde session")
    }

    /// La relance d'une connexion reseau en echec est annulee par l'arret.
    @Test func reessaiDuReseauEstAnnule() async throws {
        let b = try Self.banc(branchee: false, canalReseau: { _, _ in CanalEnPanneZigbee() })
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.annoncer()
        #expect(await attendreActivation { b.sonde.etat == .injoignable })
        #expect(b.sonde.tachesPlanifiees == 1, "le reessai attend")
        b.sonde.arreter()
        #expect(b.sonde.tachesPlanifiees == 0)
        let essais = b.reseau.noms.count
        try await Task.sleep(for: .milliseconds(700))
        #expect(b.reseau.noms.count == essais, "aucun reessai apres l'arret")
    }

    /// Le nouvel essai USB (espacement progressif) est annule par l'arret.
    @Test func nouvelEssaiUSBEstAnnule() async throws {
        let b = try Self.banc(canal: { chemin, registre in registre.canal(chemin, CanalEnPanneZigbee()) })
        defer { b.nettoyer() }
        b.sonde.demarrer()
        #expect(await attendreActivation { if case .erreur = b.sonde.etat { true } else { false } })
        #expect(b.registre.chemins.count == 1 && b.sonde.tachesPlanifiees == 1, "le nouvel essai attend")
        b.sonde.arreter()
        #expect(b.sonde.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(700))
        #expect(b.registre.chemins.count == 1, "le nouvel essai n'a pas eu lieu")
    }

    /// Sans sonde retenue, rien ne s'ouvre, avant comme apres un arret et un rallumage.
    @Test func sansSerieRetenueRienNeSOuvre() async throws {
        let b = try Self.banc(serie: false)
        defer { b.nettoyer() }
        b.sonde.demarrer()
        b.sonde.arreter()
        b.sonde.demarrer()
        b.ports.brancher([Self.retenu, autreCarte])
        b.bonjour.crees.last?.voir("SONDE-01")
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.registre.chemins.isEmpty && b.reseau.noms.isEmpty)
        #expect(b.sonde.etat == .sansSonde && b.sonde.tachesPlanifiees == 0)
        b.sonde.arreter()
    }

    /// Basculer vite ne laisse rien de vivant : aucun port ouvert, aucune tache, aucun suivi, aucune ecoute.
    @Test(arguments: [false, true]) func basculesRapides(connectee: Bool) async throws {
        let b = try Self.banc()
        defer { b.nettoyer() }
        b.sonde.demarrer()
        if connectee { #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(b.sonde) }) }
        b.sonde.arreter()
        b.sonde.demarrer()
        b.sonde.arreter()
        #expect(await attendreActivation { b.registre.ouverts == 0 })
        #expect(b.sonde.tachesPlanifiees == 0 && !b.sonde.actif)
        #expect(b.ports.enMarche == 0 && b.ports.demarrages == b.ports.arrets)
        #expect(b.bonjour.enMarche == 0 && b.bonjour.demarrages == b.bonjour.arrets)
        let ouvertures = b.registre.ouvertures
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.registre.ouvertures == ouvertures && b.registre.ouverts == 0, "plus rien ne s'ouvre apres coup")
        #expect(b.sonde.tachesPlanifiees == 0)
    }

    /// La sonde de la demo et des tests est inerte : `arreter` et `demarrer` ne la reveillent pas.
    @Test func sondeInerteResteInerte() throws {
        let (p, domaine) = try SondeMaillageZigbeeTests.preferences()
        defer { SondeMaillageZigbeeTests.nettoyer(p, domaine) }
        let ports = FabriquePorts()
        let bonjour = FabriqueBonjour()
        let retenu = Self.retenu
        let s = SondeMaillageZigbee(preferences: p, actif: false, trousseau: TrousseauMemoireZigbee(),
                                    surveillerPorts: ports.fabriquer, listerPorts: { [retenu] },
                                    fabriqueBonjour: bonjour.fabriquer)
        s.demarrer()
        s.arreter()
        s.demarrer()
        #expect(!s.actif && ports.crees.isEmpty && bonjour.crees.isEmpty && s.ports.isEmpty && s.tachesPlanifiees == 0)
    }
}
