import AppKit
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Observation
import os

/// La coque de l'app : ce que tous les protocoles partagent. Le journal (evenements gardes sur 90 jours, ceux de la
/// session), les alertes et notifications, les surnoms de `surnoms.json` (sous l'identifiant de noeud, de tous les
/// protocoles), la veille du Mac, la purge du mois, la reference de temps (`maintenant`) et la capture JSON. Chaque
/// protocole a son modele (`ModeleProtocole`) : releves -> suivi -> evenements, maillages de la sonde -> historique,
/// noms, fraicheur ; il verse ses evenements au journal de la coque (`ajouter(_:de:)`), qui les marque de son protocole.
/// Les vues lisent l'etat de chaque protocole par son modele : `thread` (`SurveillanceThread`) et `zigbee`
/// (`SurveillanceZigbee`).
@MainActor
@Observable
final class Surveillance {
    enum Mode: Equatable {
        /// Ecoute du reseau local, journal sur disque, notifications.
        case direct
        /// Panne du 27/09 rejouee, rien sur disque, pas de notification.
        case demo
    }

    /// Age du maillage de la sonde d'un protocole, depuis sa reception : frais, ancien (la sonde ne repond plus), puis
    /// perime (retour aux pointilles). Les seuils sont ceux du modele de chaque protocole (Thread : 6 et 15 min, et tant
    /// qu'une tournee est en cours, frais).
    enum Fraicheur: Equatable {
        case frais, ancien, perime
    }

    let mode: Mode
    /// Journal : evenements gardes (90 jours) puis ceux de la session, du plus ancien au plus recent.
    private(set) var evenements: [Evenement] = []
    private(set) var erreurJournal: String?
    /// Le modele de Thread : Bonjour, instantane, sonde, suivi, historique, noms, fichiers sous `Thread/`.
    let thread: SurveillanceThread
    /// Le modele de Zigbee : pont, sonde, suivi des connexions, historique, noms, fichiers sous `Zigbee/`.
    let zigbee: SurveillanceZigbee

    /// La coque a ete arretee (`arreter()`), par exemple pour une reprise de donnees : tant qu'elle l'est, aucun reglage ne
    /// relance un module (`ModulesApp`), et les pages des protocoles sont grisees. Remise a faux par `demarrer()`.
    private(set) var arretee = false

    /// Les modeles de protocole de l'app.
    var modeles: [any ModeleProtocole] { [thread, zigbee] }

    /// Les modeles dont l'app parle (menu, ecran d'attente) : les protocoles actifs ; en demo, ceux dont la demo est rejouee
    /// (l'autre, muet, n'a rien a dire).
    var modelesMontres: [any ModeleProtocole] {
        modeles.filter { $0.actif && (mode != .demo || $0.rejoueLaDemo) }
    }

    /// Les protocoles actifs (« Activer ce protocole ») : ceux dont l'interrupteur de vue peut s'allumer, et dont la scene a des
    /// noeuds. Un protocole eteint est masque quelle que soit la preference de la vue.
    var protocolesActifs: Set<Protocole> { Set(modeles.filter(\.actif).map(\.protocole)) }

    /// Le modele d'un protocole ; nil si l'app n'en porte pas.
    func modele(pour protocole: Protocole) -> (any ModeleProtocole)? {
        modeles.first { $0.protocole == protocole }
    }

    /// Branche sur les notifications (mode direct seulement).
    @ObservationIgnored var surAlertes: (([AlerteAEnvoyer]) -> Void)?
    @ObservationIgnored private let journal: JournalFichiers?
    @ObservationIgnored private let fichierSurnoms: URL?
    /// Les surnoms de `surnoms.json`, de tous les protocoles : ceux de chaque protocole sont aussi dans le resolveur de
    /// noms de son modele (cles brutes, `ModeleProtocole.appliquerSurnom`) ; les autres sont gardes tels quels dans le
    /// fichier.
    @ObservationIgnored private var surnomsCommuns: [IdNoeud: String] = [:]
    @ObservationIgnored private var alertes = Alertes(politique: Surveillance.politiqueJournal)
    /// Mois (annee, mois) de la derniere purge des fichiers ; nil : pas encore purges.
    @ObservationIgnored private var moisDernierePurge: DateComponents?
    @ObservationIgnored private var debutVeille: Date?
    @ObservationIgnored private var observateurs: [NSObjectProtocol] = []

    /// Ce que le journal sait de chaque protocole : types d'evenements, pertes, notifications, changements de parent.
    /// Composee par protocole (une ligne sans protocole est de Thread : les journaux de Zigbee 1.1.1 se relisent a l'import,
    /// etape 4).
    nonisolated static let politiqueJournal = PolitiqueJournalComposee([.thread: PolitiqueJournalThread(),
                                                                         .zigbee: PolitiqueJournalZigbee()])
    /// Historique garde en memoire : les courbes de la fiche vont jusqu'a 30 jours.
    static let dureeHistorique: TimeInterval = 30 * 24 * 3600
    /// Journal du Mac (Console, sous-systeme fr.djoko.maillage.iot) : jamais de donnees du reseau.
    nonisolated static let journalMac = Logger(subsystem: "fr.djoko.maillage.iot", category: "historique")

    /// Lance par les tests (heberges dans l'app) : ne rien ecouter ni ecrire.
    static var sousTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// `thread.actif` et `zigbee.actif` sont-ils lus et ecrits dans `preferences` ? Toujours, sauf sous les tests avec les
    /// preferences de l'app (`.standard`, celles de l'app hote, c'est-a-dire les vraies) : un protocole eteint pour de bon
    /// dans l'app ne doit pas faire echouer les tests, et un test ne doit pas eteindre l'app. Un test qui verifie
    /// l'activation donne ses propres preferences.
    static func activationPersistee(_ preferences: UserDefaults) -> Bool {
        !(sousTests && preferences === UserDefaults.standard)
    }

    /// Dossier de l'app : Application Support/Maillage IoT (dans le conteneur du bac a sable).
    static var dossierParDefaut: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Maillage IoT")
    }

    /// Le dossier des fichiers propres a Thread (spec 2.2) : `Thread/`, sous le dossier de l'app. Les fichiers de tous
    /// les protocoles (`surnoms.json`, `Journal/`, pieces, releve de Maison) restent a la racine.
    nonisolated static func dossierThread(_ dossier: URL) -> URL {
        dossier.appendingPathComponent("Thread", isDirectory: true)
    }

    /// Le dossier des fichiers propres a Zigbee : `Zigbee/`, sous le dossier de l'app (noms du pont, appariements de Maison,
    /// dernier maillage et historique de la sonde).
    nonisolated static func dossierZigbee(_ dossier: URL) -> URL {
        dossier.appendingPathComponent("Zigbee", isDirectory: true)
    }

    /// `dossier` : la racine des donnees de l'app, ou garder le journal et les surnoms ; les fichiers de chaque protocole
    /// vont sous son dossier (`Thread/` : associations, dernier maillage, adresses gardees, historique de la sonde ;
    /// `Zigbee/` : dernier maillage, appariements, historique ; nil : nulle part) ; `preferences` : les scissions deja
    /// notifiees (mode direct, une fois demarree) ; `demo` : en mode demo, celle qui est rejouee (Thread seule par defaut :
    /// c'est elle que rejoue la reference de Thread ; Zigbee seule ; ou la combinee, les deux a la fois, l'horloge de Zigbee
    /// recalee sur celle de Thread) ; `demoZigbee` : la demo de Zigbee a la place de celle que `demo` donne (pour les tests,
    /// deux horloges qui different) ; `recenseur` : l'ecoute Bonjour de Thread (mode direct ; les tests en donnent une a
    /// navigateurs factices).
    init(mode: Mode, dossier: URL?, preferences: UserDefaults = .standard, demo: DemoLancee = .thread,
         demoZigbee: DemoZigbee? = nil, recenseur: Recenseur? = nil) {
        self.mode = mode
        var surnoms: [IdNoeud: String] = [:]
        switch mode {
        case .direct:
            journal = dossier.map {
                JournalFichiers(dossier: $0.appendingPathComponent("Journal"), politique: Surveillance.politiqueJournal)
            }
            let fichier = dossier?.appendingPathComponent("surnoms.json")
            fichierSurnoms = fichier
            surnoms = fichier.map { Surnoms.lire($0, protocoleParDefaut: SurveillanceThread.protocole) } ?? [:]
            surnomsCommuns = surnoms
        case .demo:
            journal = nil
            fichierSurnoms = nil
        }
        thread = SurveillanceThread(mode: mode, dossier: dossier, surnoms: surnoms, preferences: preferences,
                                    rejoueLaDemo: demo.rejoue(.thread), recenseur: recenseur)
        zigbee = SurveillanceZigbee(mode: mode, dossier: dossier, surnoms: surnoms, preferences: preferences,
                                    rejoueLaDemo: demo.rejoue(.zigbee), demo: demoZigbee ?? demo.zigbeeRejouee)
        thread.coque = self
        zigbee.coque = self
    }

    func demarrer() {
        arretee = false
        switch mode {
        case .demo:
            modeles.forEach { $0.demarrer() }
            ordonnerLeJournalDeLaDemo()
        case .direct:
            chargerJournal()
            modeles.forEach { $0.demarrer() }
            observerVeille()
        }
    }

    /// Les demos des deux protocoles se jouent l'une apres l'autre : les evenements de la seconde (Zigbee, recalee sur
    /// l'horloge de la panne de Thread dans la demo combinee) peuvent preceder la fin de ceux de la premiere. Le journal les
    /// remet dans l'ordre du temps, a date egale dans celui de leur arrivee ; une demo seule, deja ordonnee, n'y change rien.
    private func ordonnerLeJournalDeLaDemo() {
        evenements = evenements.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// Purge le journal (mois finis depuis plus de 90 jours) puis le lit. Une purge qui echoue
    /// (droits sur un vieux fichier) n'empeche pas la lecture. Sans dossier : rien.
    func chargerJournal() {
        guard let journal else { return }
        let maintenant = Date()
        noterPurge(a: maintenant)
        _ = try? journal.purger(maintenant: maintenant)
        do {
            evenements = try journal.lire()
        } catch {
            erreurJournal = error.localizedDescription
        }
    }

    func arreter() {
        arretee = true
        modeles.forEach { $0.arreter() }
        observateurs.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observateurs = []
    }

    /// Les fichiers ont ete purges au mois de `maintenant` (au lancement : le journal par `chargerJournal`, les
    /// historiques par les modeles) : la purge du mois (`purgerSiNouveauMois`) attend le mois suivant.
    func noterPurge(a maintenant: Date) {
        moisDernierePurge = Calendar.current.dateComponents([.year, .month], from: maintenant)
    }

    /// Purge le journal et l'historique de chaque protocole (mois finis depuis plus de 90 jours, comme au lancement)
    /// quand le mois de `date` n'est pas celui de la derniere purge : l'app de la barre des menus peut tourner des
    /// semaines sans etre relancee. Un echec est ignore : la purge reviendra au lancement suivant. Sans dossier (demo,
    /// tests) : rien.
    func purgerSiNouveauMois(_ date: Date) {
        let mois = Calendar.current.dateComponents([.year, .month], from: date)
        guard mois != moisDernierePurge else { return }
        moisDernierePurge = mois
        _ = try? journal?.purger(maintenant: date)
        modeles.forEach { $0.purgerHistorique(maintenant: date) }
    }

    /// Les scissions deja notifiees, relues par le modele de Thread au demarrage : un reseau qui reste scinde n'est pas
    /// notifie de nouveau a chaque lancement.
    func reprendreScissionsNotifiees(_ signatures: Set<String>) {
        alertes.scissionsNotifiees = signatures
    }

    /// Un modele n'a pas pu ecrire un de ses fichiers : l'erreur est montree dans les Reglages (Diagnostic).
    func noterErreurJournal(_ message: String) {
        erreurJournal = message
    }

    /// Veille du Mac (appele au reveil) : chaque protocole actif la note dans son suivi (la date des changements incertains
    /// en depend), mais le journal n'en recoit qu'une ligne, celle du premier protocole actif (la veille est celle du Mac,
    /// pas d'un protocole) ; un protocole eteint ne note ni n'ecrit rien, et aucun protocole actif, aucune ligne.
    func noterVeille(debut: Date, fin: Date) {
        let intervalle = DateInterval(start: debut, end: max(fin, debut))
        let notees = modeles.filter(\.actif).map { ($0.protocole, $0.noterVeille(intervalle)) }
        if let (protocole, evenements) = notees.first { ajouter(evenements, de: protocole) }
    }

    /// Donne (ou retire, avec nil ou "") un surnom a un noeud. L'identifiant porte son protocole : le fichier garde les
    /// surnoms de tous les protocoles, le resolveur de chaque modele ne voit que les siens.
    func renommer(_ id: IdNoeud, en surnom: String?) {
        let s = surnom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        surnomsCommuns[id] = s.isEmpty ? nil : s
        modele(pour: id.protocole)?.appliquerSurnom(s.isEmpty ? nil : s, cle: id.cle)
        guard let fichierSurnoms else { return }
        do {
            try Surnoms.ecrire(surnomsCommuns, dans: fichierSurnoms)
        } catch {
            erreurJournal = error.localizedDescription
        }
    }

    /// Le surnom d'un noeud ; nil sans surnom.
    func surnom(de id: IdNoeud) -> String? { surnomsCommuns[id] }

    /// Le releve de Maison du demon Passeur Noms, donne a chaque modele de protocole (un seul client du demon, un seul
    /// abonnement : son releve sert les deux).
    func recevoirReleveMaison(_ releve: NomsMaison?) {
        modeles.forEach { $0.recevoirReleveMaison(releve) }
    }

    /// Dernier releve en JSON (option de capture) : celui de Thread, a defaut le dernier maillage de Zigbee.
    func captureJSON() throws -> Data? {
        if let d = try thread.captureJSON() { return d }
        return try zigbee.captureJSON()
    }

    /// Les captures de la demo montrent un noeud qui hesite entre plusieurs relais (changements regroupes du journal) :
    /// ces evenements inventes s'ajoutent a ceux de la demo, sous le protocole `protocole` (celui qui n'en a pas). En
    /// demo seulement, et seulement pour elles ; rien sur disque.
    func evenementsDeCapture(_ nouveaux: [Evenement], de protocole: Protocole) {
        guard mode == .demo else { return }
        let nouveaux = nouveaux.map { e in
            var e = e
            e.protocole = e.protocole ?? protocole
            return e
        }
        let tous = (evenements + nouveaux).enumerated()
        evenements = tous.sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// Verse au journal les evenements d'un modele : ils portent le protocole du modele des qu'ils entrent au journal,
    /// puis vont au disque, aux alertes et aux notifications.
    func ajouter(_ evenementsDuModule: [Evenement], de protocole: Protocole) {
        // Un protocole eteint n'ecrit rien : ni journal, ni alerte, ni notification.
        guard !evenementsDuModule.isEmpty, modele(pour: protocole)?.actif ?? true else { return }
        let nouveaux = evenementsDuModule.map { e in
            var e = e
            e.protocole = protocole
            return e
        }
        evenements.append(contentsOf: nouveaux)
        do {
            try journal?.ajouter(nouveaux)
        } catch {
            erreurJournal = error.localizedDescription
        }
        // Les pertes d'un protocole eteint depuis ne comptent plus dans la fenetre du groupe (ni pour le seuil, ni dans la
        // notification).
        let eteints = Set(modeles.filter { !$0.actif }.map(\.protocole))
        alertes.oublierPertes { eteints.contains($0.protocole ?? SurveillanceThread.protocole) }
        let notifiees = alertes.scissionsNotifiees
        let envoyer = alertes.traiter(nouveaux)
        if alertes.scissionsNotifiees != notifiees { thread.garderScissionsNotifiees(alertes.scissionsNotifiees) }
        if mode == .direct && !envoyer.isEmpty { surAlertes?(envoyer) }
    }

    private func observerVeille() {
        let nc = NSWorkspace.shared.notificationCenter
        observateurs.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.debutVeille = Date() }
        })
        observateurs.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let debut = self.debutVeille else { return }
                self.debutVeille = nil
                self.noterVeille(debut: debut, fin: Date())
                self.modeles.forEach { $0.auReveil() }
            }
        })
    }

    // MARK: - Pour les vues

    /// Reference a l'heure du Mac, pour ce qui n'est pas lie a un noeud : en demo, la plus tardive des fins de demo (le plus
    /// tard des modeles). Un noeud se lit a l'horloge de son modele (`maintenant(de:a:)`), jamais a celle-ci : en demo
    /// combinee, l'horloge de l'autre protocole peut etre en avance et ferait paraitre ce noeud perime.
    var maintenant: Date { maintenant(a: Date()) }

    /// Reference des durees a l'heure `horloge` (celle de la fenetre du graphe, que sa `TimelineView`
    /// avance chaque minute) : cette heure, ou, en demo, la plus tardive des fins de demo (le plus tard des modeles).
    func maintenant(a horloge: Date) -> Date { modeles.map { $0.maintenant(a: horloge) }.max() ?? horloge }

    /// Reference des durees d'un noeud de `protocole`, a l'heure `horloge` : l'horloge de SON modele (la fin de sa demo en
    /// demo). C'est elle que lisent la fiche d'un noeud, la fenetre et l'alerte d'un protocole : ses durees (« vu il y a »,
    /// fraicheur, evenements de l'heure) ne dependent jamais de l'horloge de l'autre protocole.
    func maintenant(de protocole: Protocole, a horloge: Date) -> Date {
        modele(pour: protocole)?.maintenant(a: horloge) ?? horloge
    }

    /// Alerte en cours : celle d'un protocole actif (`alerte(de:)`). Un protocole eteint n'en signale aucune.
    var alerte: Bool { modeles.contains { alerte(de: $0.protocole) } }

    /// Alerte en cours d'un protocole : son reseau est lui-meme une alerte (`ModeleProtocole.alerteReseau` : un reseau
    /// scinde), ou il a un evenement grave dans l'heure (a l'heure de son modele : la fin de sa demo rejouee en demo).
    /// Faux s'il est eteint, et les evenements graves qu'il a ecrits avant ne comptent plus.
    func alerte(de protocole: Protocole) -> Bool {
        guard let m = modele(pour: protocole), m.actif else { return false }
        if m.alerteReseau { return true }
        let recent = m.maintenant.addingTimeInterval(-3600)
        return evenements.reversed().prefix { $0.date >= recent }.contains {
            $0.gravite == .alerte && ($0.protocole ?? SurveillanceThread.protocole) == protocole
        }
    }

    var lignesJournal: [LigneJournal] { Regroupement.lignes(evenements, politique: Self.politiqueJournal) }

    /// 5 derniers evenements d'un noeud, du plus recent au plus ancien : ceux que le modele de son protocole dit siens
    /// (`ModeleProtocole.concernant`).
    func evenements(de id: IdNoeud) -> [Evenement] {
        Array(evenements.reversed().filter(concernant(id)).prefix(5))
    }

    /// Lignes du journal d'un noeud, de la plus recente a la plus ancienne, 5 au plus : ses evenements regroupes comme
    /// ceux de la fenetre du journal (`Regroupement.lignes`), ses changements de parent d'une meme heure en une seule
    /// ligne (reprise de Maillage Zigbee, 09/10).
    func lignesJournal(de id: IdNoeud) -> [LigneJournal] {
        Array(Regroupement.lignes(evenements.filter(concernant(id)), politique: Self.politiqueJournal).prefix(5))
    }

    /// Le critere du modele du protocole du noeud ; aucun evenement si l'app ne porte pas ce protocole.
    func concernant(_ id: IdNoeud) -> (Evenement) -> Bool {
        modele(pour: id.protocole)?.concernant(id) ?? { _ in false }
    }
}
