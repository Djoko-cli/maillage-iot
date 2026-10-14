import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Les alertes qu'une coque a envoyees aux notifications.
@MainActor
final class RecueilAlertes {
    var alertes: [AlerteAEnvoyer] = []
}

/// Une coque en mode direct (sans dossier, sans fichier) dont les preferences sont en memoire et l'ecoute Bonjour de Thread
/// factice : aucun reseau, aucune preference de l'app. `thread` et `zigbee` : l'etat garde au depart sous `thread.actif` /
/// `zigbee.actif` (nil : rien de garde, donc actif).
final class BancActivation {
    let s: Surveillance
    let recenseur: Recenseur
    let bonjour: FabriqueBonjour
    let preferences: UserDefaults
    let domaine: String
    let alertes: RecueilAlertes

    @MainActor
    init(thread: Bool? = nil, zigbee: Bool? = nil, preferences existantes: (UserDefaults, String)? = nil) throws {
        let (p, d) = try existantes ?? SondeMaillageTests.preferences()
        if let thread { p.set(thread, forKey: SurveillanceThread.cleActif) }
        if let zigbee { p.set(zigbee, forKey: SurveillanceZigbee.cleActif) }
        let fab = FabriqueBonjour()
        // Le premier releve du recenseur est du des qu'il demarre (l'avance tient lieu des 10 s de mise en route).
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100))
        let coque = Surveillance(mode: .direct, dossier: nil, preferences: p, recenseur: r)
        let recueil = RecueilAlertes()
        coque.surAlertes = { recueil.alertes.append(contentsOf: $0) }
        s = coque
        recenseur = r
        bonjour = fab
        preferences = p
        domaine = d
        alertes = recueil
    }

    @MainActor func nettoyer() { preferences.removePersistentDomain(forName: domaine) }

    /// Ce que Thread recoit de sa sonde et de Bonjour : les releves de la panne du 27/09 et le maillage de la sonde.
    @MainActor func nourrirThread() {
        let t = s.thread
        for a in ScenarioPanne.releves { t.integrer(a) }
        if let m = t.instantane.flatMap({ MaillageDemo.maillage($0, date: ScenarioPanne.fin) }) {
            t.recevoir(m, a: ScenarioPanne.fin)
        }
    }

    /// Ce que Zigbee recoit de sa sonde et du pont : le reseau de la demo, avant et apres la panne.
    @MainActor func nourrirZigbee() {
        let z = s.zigbee
        z.nomsPont = NomsDemo.maisonPont
        z.recevoirReleveMaison(NomsDemo.releveMaison)
        z.recevoir(MaillageDemoZigbee.maillageAvant, a: MaillageDemoZigbee.debut)
        z.recevoir(MaillageDemoZigbee.maillage, a: MaillageDemoZigbee.fin)
    }
}

/// « Activer ce protocole » (spec 3.3, decision 11) : un protocole eteint est vraiment arrete (Bonjour, sonde, pont,
/// tournees), ne montre rien, n'ecrit rien et n'alerte pas ; allume, il repart comme au lancement. Tout est factice : aucun
/// port, aucun reseau, aucun trousseau.
@MainActor
@Suite("Activer ce protocole : coque, modeles, scene, preferences", .timeLimit(.minutes(1)))
struct ActivationTests {
    // MARK: Preferences

    /// Vrai par defaut ; garde sous `thread.actif` et `zigbee.actif`, chacun le sien ; relu par un modele recree.
    @Test func preferenceParProtocoleQuiSurvit() throws {
        #expect(SurveillanceThread.cleActif == "thread.actif" && SurveillanceZigbee.cleActif == "zigbee.actif")
        let b = try BancActivation()
        defer { b.nettoyer() }
        #expect(b.s.thread.actif && b.s.zigbee.actif, "actifs par defaut")
        #expect(b.preferences.object(forKey: "thread.actif") == nil, "rien d'ecrit tant qu'on n'y touche pas")
        b.s.thread.actif = false
        #expect(b.preferences.object(forKey: "thread.actif") as? Bool == false)
        #expect(b.preferences.object(forKey: "zigbee.actif") == nil, "l'autre protocole n'est pas touche")

        let relu = try BancActivation(preferences: (b.preferences, b.domaine))
        #expect(!relu.s.thread.actif && relu.s.zigbee.actif, "la preference survit au modele recree")
        relu.s.zigbee.actif = false
        relu.s.thread.actif = true
        let encore = try BancActivation(preferences: (b.preferences, b.domaine))
        #expect(encore.s.thread.actif && !encore.s.zigbee.actif)
        #expect(b.preferences.object(forKey: "thread.actif") as? Bool == true)
        #expect(b.preferences.object(forKey: "zigbee.actif") as? Bool == false)
        // Un modele neuf avec des preferences vides est actif de nouveau.
        let (p, d) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: d) }
        #expect(SurveillanceZigbee(mode: .direct, dossier: nil, surnoms: [:], preferences: p).actif)
    }

    /// Les preferences de l'app ne servent pas aux tests (celles de l'app hote sont les vraies : un protocole eteint pour de
    /// bon ne doit pas les faire echouer, et un test ne doit pas eteindre l'app) ; la demo ne les lit ni ne les ecrit.
    @Test func preferencesDeLAppIgnoreesSousLesTests() throws {
        #expect(Surveillance.sousTests)
        #expect(!Surveillance.activationPersistee(.standard))
        let (p, d) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: d) }
        #expect(Surveillance.activationPersistee(p))
        p.set(false, forKey: SurveillanceThread.cleActif)
        let demo = Surveillance(mode: .demo, dossier: nil, preferences: p)
        #expect(demo.thread.actif, "la demo ne lit pas la preference")
        demo.thread.actif = false
        demo.thread.actif = true
        #expect(p.object(forKey: SurveillanceThread.cleActif) as? Bool == false, "ni ne l'ecrit")
    }

    // MARK: Thread : Bonjour

    /// Eteint au lancement, Thread ne lance rien ; l'allumer lance l'ecoute Bonjour.
    @Test func threadEteintAuLancementNeLanceRien() throws {
        let b = try BancActivation(thread: false)
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        b.s.zigbee.demarrer()
        #expect(b.bonjour.crees.isEmpty && b.recenseur.tachesPlanifiees == 0, "aucun navigateur Bonjour")
        #expect(b.s.thread.etatEcoute == .eteint)
        b.s.thread.actif = true
        #expect(b.bonjour.types == Recenseur.types && b.bonjour.enMarche == 4)
        #expect(b.s.thread.etatEcoute == .demarrage)
        #expect(b.preferences.object(forKey: "thread.actif") as? Bool == true)
        b.s.thread.arreter()
        #expect(b.bonjour.enMarche == 0, "la coque arrete le modele : l'ecoute s'arrete, la preference reste")
        #expect(b.s.thread.actif)
    }

    /// Eteindre Thread arrete l'ecoute Bonjour : plus de navigateur, plus de releve ; ni le reveil du Mac ni un rafraichissement
    /// n'y changent rien ; le rallumage fait quatre navigateurs neufs.
    @Test func eteindreThreadArreteBonjour() async throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        #expect(b.bonjour.enMarche == 4 && b.recenseur.tachesPlanifiees >= 1)
        b.s.thread.actif = false
        #expect(b.bonjour.enMarche == 0 && b.bonjour.arrets == 4)
        #expect(b.recenseur.tachesPlanifiees == 0, "aucune tache de releve")
        #expect(b.s.thread.etatEcoute == .eteint)
        b.s.thread.auReveil()
        b.s.thread.rafraichir()
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.bonjour.enMarche == 0 && b.bonjour.crees.count == 4 && b.s.thread.dernierReleve == nil)

        b.s.thread.actif = true
        #expect(b.bonjour.crees.count == 8 && b.bonjour.enMarche == 4)
        b.s.thread.actif = false
        #expect(b.bonjour.enMarche == 0 && b.recenseur.tachesPlanifiees == 0)
    }

    /// Basculer vite (arret, rallumage, arret) ne laisse rien de vivant.
    @Test func threadBasculesRapides() async throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        b.s.thread.actif = false
        b.s.thread.actif = true
        b.s.thread.actif = false
        #expect(b.bonjour.enMarche == 0 && b.bonjour.demarrages == b.bonjour.arrets && b.bonjour.crees.count == 8)
        #expect(b.recenseur.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(b.bonjour.enMarche == 0 && b.recenseur.tachesPlanifiees == 0 && b.s.thread.dernierReleve == nil)
        #expect(b.preferences.object(forKey: "thread.actif") as? Bool == false)
    }

    // MARK: Un protocole eteint ne montre rien, n'ecrit rien

    /// Allume, Thread montre son reseau et ecrit ses evenements ; eteint, ses noeuds, son resume et son alerte disparaissent,
    /// il ignore ce que sa sonde et Bonjour lui envoient encore, et n'ecrit ni n'alerte rien.
    @Test func threadEteintNeMontreRienNEcritRien() throws {
        let allume = try BancActivation()
        defer { allume.nettoyer() }
        allume.s.thread.demarrer()
        allume.nourrirThread()
        #expect(!allume.s.thread.graphe.noeuds.isEmpty && allume.s.thread.resumeMenu != nil && !allume.s.thread.appareils.isEmpty)
        #expect(!allume.s.evenements.isEmpty && allume.s.evenements.allSatisfy { $0.protocole == .thread })
        #expect(!allume.alertes.alertes.isEmpty, "le controle : la panne alerte")

        // Eteint apres coup : tout part.
        allume.s.thread.actif = false
        #expect(allume.s.thread.graphe.noeuds.isEmpty && allume.s.thread.appareils.isEmpty)
        #expect(allume.s.thread.resumeMenu == nil && allume.s.thread.resume == nil && !allume.s.thread.alerteReseau)
        #expect(allume.s.thread.instantane == nil && allume.s.thread.maillage == nil && allume.s.thread.dernierReleve == nil)
        #expect(!allume.s.thread.rienTrouve)

        // Eteint d'emblee : les memes entrees ne produisent rien.
        let eteint = try BancActivation(thread: false)
        defer { eteint.nettoyer() }
        eteint.s.thread.demarrer()
        eteint.nourrirThread()
        #expect(eteint.s.evenements.isEmpty && eteint.alertes.alertes.isEmpty, "aucun evenement, aucune alerte")
        #expect(eteint.s.thread.instantane == nil && eteint.s.thread.maillage == nil && eteint.s.thread.dernierReleve == nil)
        #expect(eteint.s.thread.graphe.noeuds.isEmpty && eteint.s.thread.resumeMenu == nil)
        #expect(eteint.s.thread.noterVeille(DateInterval(start: .now, duration: 60)).isEmpty)
    }

    @Test func zigbeeEteintNeMontreRienNEcritRien() throws {
        let allume = try BancActivation()
        defer { allume.nettoyer() }
        allume.s.zigbee.demarrer()
        allume.nourrirZigbee()
        #expect(!allume.s.zigbee.graphe.noeuds.isEmpty && allume.s.zigbee.aUnReseau && allume.s.zigbee.resumeMenu != nil)
        #expect(!allume.s.evenements.isEmpty && allume.s.evenements.allSatisfy { $0.protocole == .zigbee })
        #expect(allume.alertes.alertes.contains { $0.categorie == .routeurDisparu }, "le controle : la panne alerte")

        allume.s.zigbee.actif = false
        #expect(allume.s.zigbee.graphe.noeuds.isEmpty && allume.s.zigbee.appareils.isEmpty && !allume.s.zigbee.aUnReseau)
        #expect(allume.s.zigbee.resumeMenu == nil && allume.s.zigbee.resume == nil)
        #expect(allume.s.zigbee.maillage == nil && !allume.s.zigbee.tourneeEnCours)
        #expect(!allume.s.zigbee.rienTrouve)

        let eteint = try BancActivation(zigbee: false)
        defer { eteint.nettoyer() }
        eteint.s.zigbee.demarrer()
        eteint.nourrirZigbee()
        #expect(eteint.s.evenements.isEmpty && eteint.alertes.alertes.isEmpty, "aucun evenement, aucune alerte")
        #expect(eteint.s.zigbee.maillage == nil && eteint.s.zigbee.graphe.noeuds.isEmpty && eteint.s.zigbee.resumeMenu == nil)
        // Une lecture du pont tardive (apres l'arret) n'ecrit rien non plus.
        eteint.s.zigbee.lecturePont(NomsDemo.maisonPont)
        #expect(eteint.s.evenements.isEmpty)
        #expect(eteint.s.zigbee.noterVeille(DateInterval(start: .now, duration: 60)).isEmpty)
    }

    /// Un evenement grave d'un protocole eteint n'entre pas au journal, ne fait pas l'alerte de l'icone et ne notifie rien ;
    /// celui d'un protocole allume si, meme quand l'autre est eteint.
    @Test(arguments: Protocole.allCases) func uneAlerteSeulementDUnProtocoleAllume(protocole: Protocole) throws {
        let autre = Protocole.allCases.first { $0 != protocole }!
        let b = try BancActivation()
        defer { b.nettoyer() }
        let maintenant = b.s.maintenant
        let grave = Evenement(date: maintenant, type: .routeurDisparu, sujet: Sujet(id: "R1", nom: "Routeur 1"))
        func eteindre(_ p: Protocole) { b.s.modele(pour: p)?.actif = false }

        eteindre(protocole)
        b.s.ajouter([grave], de: protocole)
        #expect(b.s.evenements.isEmpty && b.alertes.alertes.isEmpty && !b.s.alerte, "eteint : rien")
        b.s.ajouter([grave], de: autre)
        #expect(b.s.evenements.count == 1 && b.alertes.alertes.map(\.categorie) == [.routeurDisparu] && b.s.alerte,
                "l'autre protocole, allume, ecrit et alerte")
        // L'evenement d'un protocole eteint ensuite ne compte plus pour l'icone.
        eteindre(autre)
        #expect(!b.s.alerte, "un protocole eteint ne fait plus l'alerte de l'icone")
        b.s.modele(pour: protocole)?.actif = true
        b.s.ajouter([grave], de: protocole)
        #expect(b.s.evenements.count == 2 && b.s.alerte, "rallume : il ecrit et alerte de nouveau")
    }

    /// La fenetre des pertes (3 en 10 min, une notification groupee) ne garde rien d'un protocole eteint : deux pertes
    /// Zigbee, Zigbee eteint, une perte Thread ne font pas trois ; la notification, quand elle part, ne compte que Thread.
    @Test func pertesDUnProtocoleEteintNeCompentPlus() throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        let t = b.s.maintenant
        func perte(_ id: String, _ decalage: TimeInterval) -> Evenement {
            Evenement(date: t.addingTimeInterval(decalage), type: .appareilDisparu, sujet: Sujet(id: id, nom: "Appareil \(id)"))
        }
        func groupees() -> [AlerteAEnvoyer] { b.alertes.alertes.filter { $0.categorie == .pertes } }

        b.s.ajouter([perte("Z1", 0), perte("Z2", 1)], de: .zigbee)
        b.s.modele(pour: .zigbee)?.actif = false
        b.s.ajouter([perte("T1", 300)], de: .thread)
        #expect(groupees().isEmpty, "deux pertes Zigbee, Zigbee eteint, une perte Thread : pas trois")

        b.s.ajouter([perte("T2", 301), perte("T3", 302)], de: .thread)
        let envoyee = try #require(groupees().last, "trois pertes Thread : la notification part")
        #expect(envoyee.evenements.count == 3 && envoyee.evenements.allSatisfy { $0.protocole == .thread },
                "rien d'un protocole eteint dans la notification")
    }

    /// Chaque Mac qui se reveille ecrit une ligne « veille » par protocole allume ; un protocole eteint n'ecrit rien.
    @Test func veilleSeulementPourLesProtocolesAllumes() throws {
        let debut = Date(timeIntervalSince1970: 1_800_000_000)
        func protocoles(thread: Bool?, zigbee: Bool?) throws -> [Protocole?] {
            let b = try BancActivation(thread: thread, zigbee: zigbee)
            defer { b.nettoyer() }
            b.s.noterVeille(debut: debut, fin: debut.addingTimeInterval(600))
            return b.s.evenements.map { e in
                #expect(e.type == .veille)
                return e.protocole
            }
        }
        #expect(try protocoles(thread: nil, zigbee: nil) == [.thread, .zigbee])
        #expect(try protocoles(thread: false, zigbee: nil) == [.zigbee])
        #expect(try protocoles(thread: nil, zigbee: false) == [.thread])
        #expect(try protocoles(thread: false, zigbee: false).isEmpty)
    }

    /// Le releve de Maison, un seul pour les deux protocoles (le client du demon Passeur Noms reste abonne), arrive meme aux
    /// modeles eteints : rallumes, ils ont deja leurs noms.
    @Test func releveDeMaisonArriveAuxModelesEteints() throws {
        let b = try BancActivation(thread: false, zigbee: false)
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        b.s.zigbee.demarrer()
        let releve = NomsMaison(date: Date(timeIntervalSince1970: 1_000_000), domicile: "Domicile 1")
        b.s.recevoirReleveMaison(releve)
        #expect(b.s.thread.noms.maison?.domicile == "Domicile 1" && b.s.zigbee.releveMaison?.domicile == "Domicile 1")
        b.s.recevoirReleveMaison(nil)
        #expect(b.s.thread.noms.maison == nil && b.s.zigbee.releveMaison == nil)
    }

    // MARK: Rallumage

    /// Rallumer Thread le fait repartir comme au lancement : il ne garde rien de ce qu'il savait avant l'arret, et le premier
    /// releve est un point de depart, sans evenement rejoue.
    @Test func threadRallumeRepartDeZero() throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        b.nourrirThread()
        let avant = b.s.evenements.count
        b.s.thread.actif = false
        b.s.thread.actif = true
        #expect(b.s.thread.instantane == nil && b.s.thread.maillage == nil && b.s.thread.dernierReleve == nil)
        #expect(b.bonjour.enMarche == 4)
        b.s.thread.integrer(ScenarioPanne.releves[0])
        #expect(b.s.thread.instantane != nil)
        #expect(b.s.evenements.dropFirst(avant).map(\.type) == [.surveillanceDemarree], "point de depart : aucun evenement rejoue")
    }

    @Test func zigbeeRallumeRepartDeZero() throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        b.s.zigbee.demarrer()
        b.nourrirZigbee()
        let avant = b.s.evenements.count
        b.s.zigbee.actif = false
        b.s.zigbee.actif = true
        #expect(b.s.zigbee.maillage == nil && b.s.zigbee.maillageRecu == nil)
        b.s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: MaillageDemoZigbee.fin)
        #expect(b.s.zigbee.maillage != nil)
        #expect(b.s.evenements.dropFirst(avant).map(\.type) == [.surveillanceDemarree], "point de depart : aucun evenement rejoue")
    }

    // MARK: Scene

    /// La scene ne joint que les protocoles allumes : eteint, un protocole n'a plus aucun noeud ni lien dans la scene, et
    /// l'autre reste tel qu'il etait seul ; rallume, il revient.
    @Test func sceneSansLeProtocoleEteint() {
        let s = EntreeSceneTests.deuxReseaux()
        let reunie = EntreeScene(surveillance: s, places: PlacesGardees())
        let seulThread = EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees())
        let seulZigbee = EntreeScene(surveillance: SurveillanceZigbeeTests.demoZigbee(), places: PlacesGardees())
        #expect(reunie.protocoles == [.thread, .zigbee])

        s.thread.actif = false
        let sansThread = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(sansThread.protocoles == [.zigbee])
        #expect(Set(sansThread.scene.noeuds.map(\.id)) == Set(seulZigbee.scene.noeuds.map(\.id)))
        #expect(Set(sansThread.scene.liens) == Set(seulZigbee.scene.liens))
        #expect(Set(sansThread.graphe.noeuds.map(\.id)) == Set(seulZigbee.graphe.noeuds.map(\.id)))
        #expect(sansThread.libelles.keys.allSatisfy { $0.protocole == .zigbee } && sansThread.maillageThread == nil)
        #expect(sansThread.apparences.keys.allSatisfy { $0.protocole == .zigbee })

        s.thread.actif = true
        s.zigbee.actif = false
        let sansZigbee = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(sansZigbee.protocoles == [.thread])
        #expect(Set(sansZigbee.scene.noeuds.map(\.id)) == Set(seulThread.scene.noeuds.map(\.id)))
        #expect(Set(sansZigbee.scene.liens) == Set(seulThread.scene.liens))
        #expect(sansZigbee.maillageZigbee == nil && sansZigbee.libelles.keys.allSatisfy { $0.protocole == .thread })

        s.zigbee.actif = true
        let rallumee = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(rallumee.protocoles == [.thread, .zigbee] && rallumee == reunie, "tout revient, a l'identique")

        s.thread.actif = false
        s.zigbee.actif = false
        let vide = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(vide.protocoles.isEmpty && vide.scene.noeuds.isEmpty && vide.scene.liens.isEmpty)
    }

    // MARK: Onglets

    /// Un protocole actif qui ne trouve rien le dit dans son onglet, simplement : ni alerte, ni notification, ni evenement.
    @Test func unProtocoleActifQuiNeTrouveRienLeDit() throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        b.s.thread.demarrer()
        b.s.zigbee.demarrer()
        #expect(!b.s.thread.rienTrouve, "avant le premier releve, rien n'est encore dit")
        #expect(b.s.zigbee.rienTrouve, "Zigbee n'a ni maillage ni appareil du pont")
        #expect(ActivationProtocole.texteRienTrouve(.zigbee, rienTrouve: b.s.zigbee.rienTrouve)
                == "Aucun réseau Zigbee à montrer : ni maillage de la sonde, ni appareil du pont Hue.")
        b.s.thread.integrer(Annonces(date: ScenarioPanne.debut))
        #expect(b.s.thread.rienTrouve, "le Mac a releve le reseau local sans y voir de Thread")
        #expect(ActivationProtocole.texteRienTrouve(.thread, rienTrouve: b.s.thread.rienTrouve)
                == "Aucun réseau Thread visible sur ce réseau local")
        #expect(ActivationProtocole.texteRienTrouve(.thread, rienTrouve: false) == nil)
        #expect(b.s.evenements.isEmpty && b.alertes.alertes.isEmpty && !b.s.alerte, "sans alerte ni notification")

        // Un reseau a montrer : plus rien a dire.
        b.nourrirThread()
        b.nourrirZigbee()
        #expect(!b.s.thread.rienTrouve && !b.s.zigbee.rienTrouve)
        // Eteints : l'onglet ne dit rien d'autre que son interrupteur.
        b.s.thread.actif = false
        b.s.zigbee.actif = false
        #expect(!b.s.thread.rienTrouve && !b.s.zigbee.rienTrouve)
    }

    // MARK: Cablage de l'app (ModulesApp)

    /// Le branchement de l'app pour Thread : la sonde suit le modele. Eteint, elle ferme son port et annule ses tournees, et
    /// l'ecoute Bonjour s'arrete ; allume, tout repart (la sonde retenue seule) ; eteint au lancement, rien ne demarre.
    @Test func cablageThread() async throws {
        let (pp, dp) = try SondeMaillageTests.preferences()
        defer { pp.removePersistentDomain(forName: dp) }
        pp.set(SondeMaillageTests.port.serie, forKey: SondeMaillageThread.cleSerie)
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let b = try BancActivation()
        defer { b.nettoyer() }
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let branches = [SondeMaillageTests.port, autre]
        let sonde = SondeMaillageThread(preferences: pp, actif: true,
                                        ouvrirCanal: { registre.canal($0, CanalRejoue { CanalRejoue.reseauMinimal($0) }) },
                                        surveillerPorts: ports.fabriquer, listerPorts: { branches })
        ModulesApp.relierThread(b.s, sonde: sonde)
        b.s.thread.demarrer()
        #expect(await attendreActivation { SondeMaillageTests.connectee(sonde) })
        #expect(b.bonjour.enMarche == 4 && sonde.tachesPlanifiees == 1 && registre.ouverts == 1)

        b.s.thread.actif = false
        #expect(!sonde.actif && sonde.tachesPlanifiees == 0 && ports.enMarche == 0 && b.bonjour.enMarche == 0)
        #expect(await attendreActivation { registre.ouverts == 0 }, "le port est ferme")
        sonde.portsChanges(branches)
        b.s.thread.rafraichir()
        try await Task.sleep(for: .milliseconds(100))
        #expect(registre.ouvertures == 1)

        b.s.thread.actif = true
        #expect(await attendreActivation { SondeMaillageTests.connectee(sonde) })
        #expect(registre.ouvertures == 2 && Set(registre.chemins) == [SondeMaillageTests.port.chemin],
                "rouvert, et seule la sonde retenue : \(registre.chemins)")
        #expect(b.bonjour.enMarche == 4)

        // Bascules rapides : rien ne reste.
        b.s.thread.actif = false
        b.s.thread.actif = true
        b.s.thread.actif = false
        #expect(await attendreActivation { registre.ouverts == 0 })
        #expect(sonde.tachesPlanifiees == 0 && ports.enMarche == 0 && b.bonjour.enMarche == 0)
        #expect(ports.demarrages == ports.arrets && b.bonjour.demarrages == b.bonjour.arrets)
    }

    @Test func cablageThreadEteintAuLancement() async throws {
        let (pp, dp) = try SondeMaillageTests.preferences()
        defer { pp.removePersistentDomain(forName: dp) }
        pp.set(SondeMaillageTests.port.serie, forKey: SondeMaillageThread.cleSerie)
        let registre = RegistrePorts()
        let ports = FabriquePorts()
        let b = try BancActivation(thread: false)
        defer { b.nettoyer() }
        let port = SondeMaillageTests.port
        let sonde = SondeMaillageThread(preferences: pp, actif: true,
                                        ouvrirCanal: { registre.canal($0, CanalRejoue { CanalRejoue.reseauMinimal($0) }) },
                                        surveillerPorts: ports.fabriquer, listerPorts: { [port] })
        ModulesApp.relierThread(b.s, sonde: sonde)
        b.s.thread.demarrer()
        try await Task.sleep(for: .milliseconds(100))
        #expect(ports.crees.isEmpty && registre.chemins.isEmpty && b.bonjour.crees.isEmpty, "rien ne demarre")
        b.s.thread.actif = true
        #expect(await attendreActivation { SondeMaillageTests.connectee(sonde) })
        #expect(b.bonjour.enMarche == 4)
        b.s.thread.actif = false
        #expect(await attendreActivation { registre.ouverts == 0 })
    }

    /// Le branchement de l'app pour Zigbee : la sonde, l'ecoute Bonjour de la decouverte du pont et le client du pont suivent le
    /// modele. Eteint, le port se ferme, les tournees, l'entretien et la relecture du pont s'arretent, les deux ecoutes Bonjour
    /// aussi ; allume, tout repart.
    @Test func cablageZigbee() async throws {
        let b = try BancActivation()
        defer { b.nettoyer() }
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        let pont = ArretNomsPontTests.banc()
        let ecoutePont = BonjourFactice(type: DecouvertePont.type)
        let decouverte = DecouvertePont(navigateur: ecoutePont)
        ModulesApp.relierZigbee(b.s, sonde: z.sonde, nomsPont: pont.pont, decouverte: decouverte)
        b.s.zigbee.demarrer()
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(z.sonde) })
        #expect(await attendreActivation { z.sonde.tachesPlanifiees == 1 && pont.simule.appels.count > 20 })
        #expect(decouverte.demarree && ecoutePont.enMarche && z.bonjour.enMarche == 1 && z.ports.enMarche == 1)

        b.s.zigbee.actif = false
        #expect(!z.sonde.actif && z.sonde.tachesPlanifiees == 0 && z.ports.enMarche == 0 && z.bonjour.enMarche == 0)
        #expect(!decouverte.demarree && !ecoutePont.enMarche, "plus de Bonjour du pont")
        #expect(pont.pont.suspendu)
        #expect(await attendreActivation { z.registre.ouverts == 0 && pont.pont.tachesPlanifiees == 0 }, "port ferme, pont arrete")
        let lectures = pont.simule.appels.count
        try await Task.sleep(for: .milliseconds(250))
        #expect(pont.simule.appels.count == lectures, "le pont n'est plus lu")
        #expect(z.registre.ouvertures == 1)

        b.s.zigbee.actif = true
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(z.sonde) })
        #expect(await attendreActivation { pont.simule.appels.count > lectures + 20 }, "le pont est relu")
        #expect(decouverte.demarree && ecoutePont.enMarche && !pont.pont.suspendu)
        #expect(Set(z.registre.chemins) == [ArretSondeZigbeeTests.retenu.chemin], "seule la sonde retenue : \(z.registre.chemins)")

        b.s.zigbee.actif = false
        b.s.zigbee.actif = true
        b.s.zigbee.actif = false
        #expect(await attendreActivation { z.registre.ouverts == 0 && !pont.pont.lectureEnCours })
        #expect(z.sonde.tachesPlanifiees == 0 && pont.pont.tachesPlanifiees == 0 && !decouverte.demarree)
        #expect(z.ports.demarrages == z.ports.arrets && z.bonjour.demarrages == z.bonjour.arrets)
        #expect(ecoutePont.demarrages == ecoutePont.arrets)
    }

    @Test func cablageZigbeeEteintAuLancement() async throws {
        let b = try BancActivation(zigbee: false)
        defer { b.nettoyer() }
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        let pont = ArretNomsPontTests.banc()
        let ecoutePont = BonjourFactice(type: DecouvertePont.type)
        let decouverte = DecouvertePont(navigateur: ecoutePont)
        ModulesApp.relierZigbee(b.s, sonde: z.sonde, nomsPont: pont.pont, decouverte: decouverte)
        b.s.zigbee.demarrer()
        try await Task.sleep(for: .milliseconds(100))
        #expect(z.ports.crees.isEmpty && z.bonjour.crees.isEmpty && z.registre.chemins.isEmpty)
        #expect(ecoutePont.demarrages == 0 && pont.simule.appels.isEmpty, "ni Bonjour, ni pont")
        b.s.zigbee.actif = true
        #expect(await attendreActivation { SondeMaillageZigbeeTests.connectee(z.sonde) })
        #expect(decouverte.demarree && ecoutePont.enMarche)
        #expect(await attendreActivation { !pont.simule.appels.isEmpty }, "le pont est lu")
        b.s.zigbee.actif = false
        #expect(await attendreActivation { z.registre.ouverts == 0 && !pont.pont.lectureEnCours })
    }
}
