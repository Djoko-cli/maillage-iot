import Foundation
import MaillageCoeur
import ProtocoleThread
import Observation
import os

/// La sonde vue par l'app : port retenu (par son numero de serie USB),
/// connexion, tournee toutes les 5 minutes, dernier maillage. L'app n'ouvre
/// jamais un port qu'on ne lui a pas designe (spec de la sonde, section 3).
/// Liaison par l'USB, ou par le reseau Thread (contrat 1.0.2, comme le pont Halo) :
/// la cle se cree par l'USB et reste dans le trousseau ; par le reseau, la sonde
/// peut etre debranchee du Mac et alimentee ailleurs.
@MainActor
@Observable
final class SondeMaillageThread {
    enum Etat: Equatable {
        /// Aucune sonde choisie dans les Reglages.
        case sansSonde
        /// La sonde retenue n'est pas branchee.
        case absente
        case connexion
        case connectee(Bonjour)
        /// Le port choisi n'est pas une sonde, ou ne repond pas.
        case refusee(String)
        case erreur(String)
    }

    /// Le chemin en service avec la sonde retenue : son port USB, ou le reseau Thread. Le reglage de l'utilisateur
    /// (Automatique, USB, Reseau Thread) est `ReglageLiaison` ; seul Automatique change de chemin de lui-meme.
    enum Liaison: String, Sendable {
        case usb
        case reseau
    }

    /// Session reseau perdue : sa cause, telle que l'etat l'a montree, et son heure.
    struct Perte: Equatable, Sendable {
        let cause: String
        let date: Date
    }

    /// Journal du Mac (Console, sous-systeme fr.djoko.maillage.iot) : jamais de donnees du reseau.
    nonisolated static let journal = Logger(subsystem: "fr.djoko.maillage.iot", category: "sonde")
    /// Numero de serie USB de la sonde retenue (l'adresse MAC du C6).
    static let cleSerie = "thread.sondeSerieUSB"
    /// Nom de la sonde retenue, donne par la carte (`bonjour`).
    static let cleNom = "thread.sondeNom"
    /// Nom d'hote SRP de la sonde retenue (sans `.local`), donne par la carte (`bonjour`, `cle`).
    static let cleHote = "thread.sondeHote"
    /// Reglage de liaison choisi dans les Reglages (`ReglageLiaison`) : absent, Automatique (nouvelle installation) ; un
    /// choix existant (`usb`, `reseau`) est garde tel quel, jamais remplace par Automatique.
    static let cleLiaison = "thread.sondeLiaison"
    /// Toutes les cles de preferences de la sonde, prefixees `thread.` (identite de Maillage IoT).
    static let cles = [cleSerie, cleNom, cleHote, cleLiaison]
    static let periode: Duration = .seconds(300)
    /// Attente la plus longue du premier releve Bonjour avant la premiere tournee (`attendreReseau`).
    static let attenteReseau: Duration = .seconds(30)
    /// Reprises de la liaison reseau apres un echec : 1, 2, 5, 10 s, puis toutes les 30 s.
    static let delaisReprise: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30)]
    /// Nouvel essai d'une connexion automatique (USB) en echec : une sonde qui demarre en plus
    /// de 3 s (bonjour sans reponse) n'attend pas l'evenement USB suivant.
    static let delaiNouvelEssai: Duration = .seconds(5)
    /// Automatique, en session reseau : la carte retenue doit rester branchee ce temps-la, sans interruption, avant que la sonde
    /// ne revienne a l'USB. Un branchement qui clignote (cable, hub, enumeration) ne coupe donc pas la session, ni n'ouvre le
    /// port a chaque evenement. Sans session reseau a proteger, le retour est immediat.
    static let delaiRetourUSB: Duration = .seconds(5)

    private(set) var etat: Etat = .sansSonde
    /// Ports Espressif branches, tels que le dernier evenement USB les a listes (`ports` en retire ceux de l'autre module).
    private var portsVus: [PortUSB] = []
    /// Ports Espressif que cette sonde propose et peut ouvrir : les C6 branches, sauf ceux que Zigbee retient (spec 3.4).
    /// Un autre C6 (le pont Halo) y figure : il n'est ouvert que si on le choisit.
    var ports: [PortUSB] { cartes.choix(portsVus, pour: .thread) }
    /// Numero de serie USB de la sonde retenue ; seule `retenirSerie` l'ecrit, car elle le publie aux cartes retenues.
    private(set) var serie: String?
    /// Le choix d'un port refuse parce que la carte est la sonde de l'autre module ; nil sinon. Efface par un autre choix,
    /// un evenement USB ou « Oublier la sonde ».
    private(set) var choixRefuse: String?
    /// Nom de la sonde (« SONDE-T1 »), mis a jour a chaque `bonjour` ; nil si le firmware
    /// n'en donne pas (1.0.0) ou sans sonde retenue.
    private(set) var nom: String?
    /// Numero de serie USB du port que l'etat concerne (connexion, connexion etablie, refus,
    /// erreur) ; nil sans sonde ou la sonde retenue absente.
    private(set) var serieEtat: String?
    private(set) var etatSonde: EtatSonde?
    /// Reception du dernier maillage (fin de sa tournee).
    private(set) var derniereTournee: Date?
    private(set) var tourneeEnCours = false
    /// Avancement de la tournee en cours ; nil hors tournee.
    private(set) var avancement: AvancementTournee?
    /// Debut de la tournee en cours ; nil hors tournee.
    private(set) var debutTournee: Date?
    /// Derniere erreur d'une tournee (la liaison reste ouverte).
    private(set) var erreurTournee: String?
    /// Couverture de l'ecoute au dernier maillage (firmware 1.1.0, spec de la sonde tout-en-un, section 2.4) : les
    /// routeurs que la sonde entend, sur ceux de la partition ; nil sans (firmware plus ancien, sans releve).
    private(set) var couverture: CouvertureEcoute?
    /// Reglage de liaison (`thread.sondeLiaison`) : seul Automatique decide du chemin (`reevaluer`) ; USB et Reseau Thread le
    /// fixent, comme avant.
    private(set) var reglage: ReglageLiaison = .automatique
    /// Le chemin en service, ou vise : le reseau pendant une session ou ses reprises, l'USB sinon (aussi au repos, sans rien
    /// de connecte). Fixe par le reglage, ou, en Automatique, par `reevaluer`.
    private(set) var liaison: Liaison = .usb
    /// Les hotes SRP que Bonjour montre avec une adresse (instantane de Thread, `annoncesChangees`), en majuscules : le signal
    /// « annoncee ». Vide a l'arret de la sonde, comme l'instantane qu'il reflete.
    private(set) var annonces: Set<String> = []
    /// La sonde retenue est annoncee : son hote SRP est parmi `annonces`. Sans nom d'hote (jamais appris), jamais.
    var annoncee: Bool { CheminLiaison.annoncee(hote: hote, parmi: annonces) }
    /// Nom d'hote SRP de la sonde retenue (sans `.local`) : l'acces reseau vise `<hote>.local`.
    private(set) var hote: String?
    /// Empreinte de la cle de ce Mac pour la sonde retenue (trousseau) ; nil sans cle.
    private(set) var empreinteAcces: String?
    /// « Autoriser l'acces reseau » en cours (cle demandee par l'USB).
    private(set) var autorisationEnCours = false
    /// Echec de la derniere operation sur l'acces reseau (autorisation, oubli de la cle) ; nil
    /// apres une reussite.
    private(set) var erreurAcces: String?
    /// Derniere session reseau perdue, gardee jusqu'a la connexion suivante reussie (l'etat ne
    /// montre sa cause qu'un instant, avant la reprise) ; effacee par un changement de liaison
    /// ou l'oubli de la sonde.
    private(set) var dernierePerte: Perte?
    /// Appele a chaque nouveau maillage, avec l'heure de sa reception (fin de la
    /// tournee) : la fraicheur affichee se compte depuis.
    @ObservationIgnored var surMaillage: ((Maillage, Date) -> Void)?
    /// Appele au debut (vrai) et a la fin (faux) de chaque tournee : pendant une
    /// tournee, le maillage affiche n'est pas « ancien ».
    @ObservationIgnored var surTournee: ((Bool) -> Void)?
    /// Appele quand la sonde est oubliee : son maillage part du graphe.
    @ObservationIgnored var surOubli: (() -> Void)?
    /// Appareils de l'app a resoudre (l'instantane : spec de la sonde tout-en-un, section 2.2), demandes au debut de
    /// chaque tournee ; nil : aucun.
    @ObservationIgnored var appareilsAResoudre: (@MainActor () -> [AppareilAResoudre])?
    /// L'app a recu son premier releve Bonjour : la liste des appareils a resoudre est connue (`attendreReseau`) ;
    /// nil : rien a attendre.
    @ObservationIgnored var reseauConnu: (@MainActor () -> Bool)?

    @ObservationIgnored private let preferences: UserDefaults
    /// Les cartes retenues par chaque module : la serie de cette sonde y est publiee, celle de Zigbee en est retiree des choix.
    @ObservationIgnored private let cartes: CartesRetenues
    /// Attente du premier releve Bonjour et pas de sa relecture (`attendreReseau`) ; courts dans les tests.
    @ObservationIgnored private let attenteReseau: Duration
    @ObservationIgnored private let pasAttenteReseau: Duration
    /// Faux (demo, tests) : la sonde ne touche ni port, ni preferences, ni trousseau (lu par `DemarrageTests`). Faux aussi
    /// entre `arreter()` (Thread eteint) et `demarrer()` : aucun port n'est suivi, ouvert ni rouvert (les entrees
    /// publiques gardent `actif`).
    private(set) var actif: Bool
    /// Construite pour agir (`actif` vrai au depart) : seule une telle sonde s'arrete et repart ; celle de la demo et des
    /// tests reste inerte, quoi qu'on lui demande.
    @ObservationIgnored private let vivante: Bool
    /// Ou les ports sont suivis, et comment on les liste (factices dans les tests : aucun IOKit).
    @ObservationIgnored private let surveillerPorts: @MainActor () -> any SurveillantPorts
    @ObservationIgnored private let listerPorts: @Sendable () -> [PortUSB]
    @ObservationIgnored private let ouvrirCanal: (String) -> any CanalSonde
    /// Cles de l'acces reseau : en memoire par defaut, celui du Mac au lancement de l'app.
    @ObservationIgnored let trousseau: any TrousseauClesThread
    /// Session reseau vers `<hote>.local` avec la cle : le canal pret, ou l'erreur.
    @ObservationIgnored private let ouvrirReseau: @MainActor (String, Data) async throws -> any CanalSonde
    @ObservationIgnored private let delaisReprise: [Duration]
    @ObservationIgnored private let delaiNouvelEssai: Duration
    @ObservationIgnored private let delaiRetourUSB: Duration
    /// Retour a l'USB attendu (Automatique, session reseau en cours, carte branchee) : sa tache dort `delaiRetourUSB`.
    @ObservationIgnored private var retourUSB: Task<Void, Never>?
    /// Le premier evenement USB est arrive (`portsChanges`) : les cartes branchees sont connues. Avant, Automatique ne choisit
    /// pas (une annonce Bonjour ne doit pas passer sur le reseau avant d'avoir regarde l'USB).
    @ObservationIgnored private var portsConnus = false
    /// Echecs de la liaison reseau depuis la derniere connexion reussie.
    @ObservationIgnored private var essaisReprise = 0
    @ObservationIgnored private var reprise: Task<Void, Never>?
    /// Nouvel essai planifie d'une connexion automatique (USB) en echec.
    @ObservationIgnored private var nouvelEssai: Task<Void, Never>?
    /// Canal de la session reseau en place : sa cause de fermeture est montree a la perte.
    @ObservationIgnored private var canalReseau: (any CanalSonde)?
    /// Activite tenue pendant une session reseau, comme la session serie de Halo : sans elle,
    /// App Nap retarderait la veille du canal (la carte oublie une session muette) et les tournees.
    @ObservationIgnored private var activite: (any NSObjectProtocol)?
    /// Heure du debut de la tournee et de la reception du maillage (injectee par les tests).
    @ObservationIgnored private let horloge: () -> Date
    @ObservationIgnored private var sonde: SondeUSB?
    /// Chemin du port de `sonde` (nil sans sonde connectee).
    @ObservationIgnored private var cheminConnecte: String?
    /// Liaison d'une connexion en cours, avant sa verification : `deconnecter`
    /// la ferme aussi.
    @ObservationIgnored private var enConnexion: SondeUSB?
    /// Numero d'essai, incremente par `deconnecter` : une connexion dont le
    /// numero a change est perimee et ne touche plus a rien.
    @ObservationIgnored private var essai = 0
    /// Fermetures lancees par `deconnecter`, chainees : une connexion attend
    /// qu'elles soient finies (ports vraiment fermes) avant d'ouvrir un port.
    @ObservationIgnored private var fermetures: Task<Void, Never>?
    @ObservationIgnored private var memoire = MemoireTournee()
    /// Fichier des identites des routeurs (`fichierIdentites(demo:sousTests:)`) : lu au lancement,
    /// ecrit quand elles changent ; nil : ni lu ni ecrit.
    @ObservationIgnored private let fichierIdentites: URL?
    /// Identites telles que le fichier les a (lues ou ecrites en dernier).
    @ObservationIgnored private var identitesDuFichier: IdentitesGardees?
    /// Boucle des tournees (lue par les tests).
    @ObservationIgnored private(set) var boucle: Task<Void, Never>?
    @ObservationIgnored private var surveillantPorts: (any SurveillantPorts)?

    /// `actif` faux (mode demo, tests) : ni port, ni preferences lues, ni trousseau.
    /// `trousseau` : en memoire par defaut (tests) ; l'app lui passe celui du Mac.
    /// `fichierIdentites` : ou garder les identites des routeurs d'un lancement a l'autre (nil :
    /// nulle part).
    init(preferences: UserDefaults = .standard, actif: Bool,
         ouvrirCanal: @escaping (String) -> any CanalSonde
             = { CanalSerie(liaison: LiaisonSerie(chemin: $0, etiquette: "fr.djoko.maillage.iot.sonde-thread"),
                                  decoupeur: { DecoupeurLignes() }) },
         trousseau: any TrousseauClesThread = TrousseauMemoireThread(),
         ouvrirReseau: @escaping @MainActor (String, Data) async throws -> any CanalSonde
             = { try await CanalReseauUDP.connecter(hote: $0, cle: $1) },
         delaisReprise: [Duration] = SondeMaillageThread.delaisReprise,
         delaiNouvelEssai: Duration = SondeMaillageThread.delaiNouvelEssai,
         delaiRetourUSB: Duration = SondeMaillageThread.delaiRetourUSB,
         attenteReseau: Duration = SondeMaillageThread.attenteReseau, pasAttenteReseau: Duration = .seconds(1),
         horloge: @escaping () -> Date = { Date() }, fichierIdentites: URL? = nil,
         surveillerPorts: @escaping @MainActor () -> any SurveillantPorts = { PortsUSB() },
         listerPorts: @escaping @Sendable () -> [PortUSB] = { PortsUSB.lister() },
         cartes: CartesRetenues = CartesRetenues()) {
        self.preferences = preferences
        self.cartes = cartes
        self.actif = actif
        self.vivante = actif
        self.surveillerPorts = surveillerPorts
        self.listerPorts = listerPorts
        self.ouvrirCanal = ouvrirCanal
        self.trousseau = trousseau
        self.ouvrirReseau = ouvrirReseau
        self.delaisReprise = delaisReprise
        self.delaiNouvelEssai = delaiNouvelEssai
        self.delaiRetourUSB = delaiRetourUSB
        self.attenteReseau = attenteReseau
        self.pasAttenteReseau = pasAttenteReseau
        self.horloge = horloge
        self.fichierIdentites = fichierIdentites
        serie = actif ? preferences.string(forKey: Self.cleSerie) : nil
        cartes.retenir(serie, par: .thread)
        nom = actif ? preferences.string(forKey: Self.cleNom) : nil
        // Lu quel que soit `actif` : l'app ne passe aucun fichier en demo ni sous les tests.
        if let g = fichierIdentites.flatMap(IdentitesGardees.lire) {
            memoire = MemoireTournee(identites: g)
            identitesDuFichier = g
        }
        guard actif else { return }
        // Un choix existant est relu tel quel ; sans preference (nouvelle installation), Automatique.
        reglage = preferences.string(forKey: Self.cleLiaison).flatMap(ReglageLiaison.init(rawValue:)) ?? .automatique
        liaison = reglage == .reseau ? .reseau : .usb
        hote = preferences.string(forKey: Self.cleHote)
        empreinteAcces = hote.flatMap(empreinte(pour:))
    }

    /// Fichier des identites des routeurs : sous `Thread/`, dans le dossier de l'app ; nil en demo et sous les
    /// tests (qui passent le leur, temporaire).
    static func fichierIdentites(demo: Bool, sousTests: Bool) -> URL? {
        demo || sousTests
            ? nil
            : Surveillance.dossierThread(Surveillance.dossierParDefaut).appendingPathComponent("identites-routeurs.json")
    }

    /// Une activite est tenue (session reseau en place).
    var activiteTenue: Bool { activite != nil }

    /// Le reseau se choisit : nom d'hote connu, et cle de ce Mac pour lui.
    var reseauDisponible: Bool { hote != nil && empreinteAcces != nil }

    /// « Autoriser l'acces reseau » possible : la sonde retenue connectee par son port USB, hors
    /// tournee (une ligne `erreur`, sans id, serait attribuee a la demande de cle).
    var peutAutoriser: Bool {
        guard liaison == .usb, !autorisationEnCours, !tourneeEnCours, case .connectee = etat else { return false }
        return serie != nil && serieEtat == serie
    }

    /// Nom de la sonde retenue pour l'etat qui la concerne : absente, ou connexion, connexion
    /// etablie, refus ou erreur de son port ; nil pour un autre port choisi, ou sans sonde.
    var nomEtat: String? {
        switch etat {
        case .sansSonde: nil
        case .absente: nom
        case .connexion, .connectee, .refusee, .erreur: serie != nil && serieEtat == serie ? nom : nil
        }
    }

    /// `rafraichir` lancerait une tournee : sonde connectee, pas de tournee en cours.
    var tourneeAuRafraichir: Bool {
        if case .connectee = etat { !tourneeEnCours } else { false }
    }

    /// Nom montre pour la sonde : le sien, sinon « Sonde ».
    static func nomAffiche(_ nom: String?) -> String {
        nom ?? String(localized: "Sonde")
    }

    /// Suit les ports ; reprend la sonde retenue des qu'elle est branchee. Apres `arreter()`, repart : la sonde retenue
    /// (et elle seule : jamais un port inconnu) est rouverte si elle est branchee, ou rejointe par le reseau.
    func demarrer() {
        guard vivante else { return }
        actif = true
        guard surveillantPorts == nil else { return }
        let p = surveillerPorts()
        p.changement = { [weak self] l in self?.portsChanges(l) }
        p.demarrer()
        surveillantPorts = p
        portsChanges(listerPorts())
        // Reseau Thread choisi : la session part sans attendre l'annonce (comme avant). En Automatique, `portsChanges` a deja
        // choisi le chemin.
        if reglage == .reseau { lancerConnexionReseau() }
    }

    /// Arret reel (Thread eteint) : le suivi des ports s'arrete, la liaison (le port serie ou la session reseau) se ferme,
    /// la tournee, la boucle des tournees, les reprises de la liaison reseau et le nouvel essai planifie sont annules, et
    /// l'activite de la session reseau est rendue. Plus rien ne se connecte (`portsChanges`, `choisir`, `choisirLiaison`,
    /// `annoncesChangees`, `reevaluer` et `connecterReseau` gardent `actif`) tant que `demarrer()` n'a pas repris ; le retour a
    /// l'USB attendu est annule, et l'annonce oubliee (l'instantane de Thread repart de zero, la sonde ne le sait pas avant son
    /// premier releve) ; en Automatique le chemin est a refaire (`portsConnus`). La sonde retenue, son nom, sa cle et son
    /// reglage restent. Sans effet sur une sonde inerte (demo, tests).
    func arreter() {
        guard vivante, actif else { return }
        actif = false
        surveillantPorts?.arreter()
        surveillantPorts = nil
        reprise?.cancel()
        reprise = nil
        nouvelEssai?.cancel()
        nouvelEssai = nil
        annulerRetourUSB()
        essaisReprise = 0
        annonces = []
        portsConnus = false
        if reglage == .automatique { liaison = .usb }
        deconnecter(serie == nil ? .sansSonde : .absente)
    }

    /// Des taches de fond sont encore planifiees ou en cours : la boucle des tournees, une reprise de la liaison reseau, un
    /// nouvel essai de connexion, un retour a l'USB attendu (lu par les tests de l'arret).
    var tachesPlanifiees: Int {
        [boucle, reprise, nouvelEssai, retourUSB].filter { $0 != nil && $0?.isCancelled == false }.count
    }

    /// Choix d'un port dans les Reglages : retenu seulement s'il repond en sonde.
    /// Le port de la sonde deja connectee n'est pas rouvert.
    /// Une carte que Zigbee retient est refusee (`choixRefuse`), sans que rien ne soit ouvert (spec 3.4).
    /// Reseau Thread choisi : pas de port (comme avant). Automatique : le choix prend la place d'une session reseau en cours.
    func choisir(_ port: PortUSB) {
        guard actif, reglage != .reseau, port.chemin != cheminConnecte else { return }
        if let autre = cartes.retenuePar(port.serie, hors: .thread) {
            choixRefuse = CartesRetenues.texteRefus(retenuePar: autre)
            return
        }
        choixRefuse = nil
        annulerRetourUSB()
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        essaisReprise = 0
        dernierePerte = nil
        lancerConnexion(port, choisi: true)
    }

    /// Retient (ou rend, avec nil) le numero de serie de la sonde, et le publie aux cartes retenues : Zigbee ne propose
    /// plus cette carte et ne l'ouvre plus.
    private func retenirSerie(_ s: String?) {
        serie = s
        cartes.retenir(s, par: .thread)
    }

    /// Ce port peut etre ouvert : aucun autre module ne retient sa carte, et ou bien l'utilisateur l'a choisi, ou bien c'est
    /// la carte retenue par cette sonde (un C6 inconnu n'est jamais ouvert de lui-meme : ouvrir un port fait basculer
    /// DTR/RTS et peut redemarrer la carte).
    private func ouvrable(_ port: PortUSB, choisi: Bool) -> Bool {
        guard !cartes.retenueParUnAutre(port.serie, que: .thread) else { return false }
        return choisi || (port.serie != nil && port.serie == serie)
    }

    /// Reglage de liaison choisi dans les Reglages, garde dans les preferences. « Reseau Thread » exige une cle de ce Mac pour la
    /// sonde retenue : la liaison USB est fermee (le port libere), la session reseau ouverte. « USB » ferme la session reseau et
    /// reprend la sonde retenue si elle est branchee (une liaison USB en place n'est pas rouverte). « Automatique » garde ce qui
    /// tient et change de chemin sans delai si l'autre est celui qu'il choisit (le choix est explicite : pas de stabilite a
    /// attendre).
    func choisirLiaison(_ r: ReglageLiaison) {
        guard actif, r != reglage, r != .reseau || reseauDisponible else { return }
        reglage = r
        preferences.set(r.rawValue, forKey: Self.cleLiaison)
        reprise?.cancel()
        reprise = nil
        annulerRetourUSB()
        essaisReprise = 0
        dernierePerte = nil
        switch r {
        case .reseau:
            // Une session reseau ouverte (Automatique) est gardee ; sinon elle part.
            guard liaison != .reseau || sonde == nil else { return }
            liaison = .reseau
            lancerConnexionReseau()
        case .usb:
            if liaison == .reseau {
                liaison = .usb
                deconnecter(serie == nil ? .sansSonde : .absente)
            }
            portsChanges(portsVus)
        case .automatique:
            reevaluer(immediat: true)
        }
    }

    /// Automatique : applique le chemin choisi (`CheminLiaison.choisir`) apres un changement de ports, d'annonce ou de reglage.
    /// Aucun effet pour USB et Reseau Thread, qui fixent le chemin (leurs regles sont celles de Thread 1.3.0). Ne touche pas
    /// une connexion que l'utilisateur a choisie vers un autre port (`versUnAutrePort`), ni rien avant que les cartes branchees
    /// soient connues (`portsConnus` : USB d'abord).
    /// - L'USB est le chemin et la sonde est sur le reseau : retour a l'USB, apres `delaiRetourUSB` de branchement continu si
    ///   une session reseau tient (`immediat` : sans delai), tout de suite sinon.
    /// - Le reseau est le chemin et la sonde est sur l'USB (ou nulle part) : le reseau.
    /// - Aucun chemin : une session reseau ouverte reste (elle prouve que la sonde est joignable, meme si Bonjour la perd de vue
    ///   un instant) ; les essais d'une session qui n'aboutit pas s'arretent.
    /// Idempotente : un chemin deja pris n'est pas relance (les annonces et evenements sans effet ne relancent rien).
    private func reevaluer(immediat: Bool = false) {
        guard actif, reglage == .automatique, portsConnus, !versUnAutrePort else { return }
        let port = ports.first { $0.serie != nil && $0.serie == serie }
        let voulu = CheminLiaison.choisir(.automatique, branchee: port != nil, cleConnue: reseauDisponible,
                                          annoncee: annoncee)
        if voulu != .usb { annulerRetourUSB() }
        switch (voulu, liaison) {
        case (.usb?, .reseau):
            guard let port else { return }
            if sonde == nil || immediat {
                versUSB(port)
            } else {
                planifierRetourUSB()
            }
        case (.reseau?, .usb):
            versReseau()
        case (nil, .reseau):
            guard sonde == nil else { return }
            arreterReseau()
        default:
            break
        }
    }

    /// Automatique : de la session reseau (ou de ses reprises) vers l'USB, la carte retenue ouverte comme au demarrage (la
    /// session reseau se ferme, le port s'ouvre une fois).
    private func versUSB(_ port: PortUSB) {
        annulerRetourUSB()
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        dernierePerte = nil
        lancerConnexion(port, choisi: false)
    }

    /// Automatique : vers le reseau. Les echecs d'avant, sans connexion reussie depuis (`essaisReprise`), gardent l'espacement
    /// de la reprise : une annonce qui clignote ou une carte qui se debranche ne relancent pas une session a chaque fois.
    private func versReseau() {
        annulerRetourUSB()
        liaison = .reseau
        dernierePerte = nil
        reprise?.cancel()
        reprise = nil
        if essaisReprise == 0 {
            lancerConnexionReseau()
        } else {
            deconnecter(.connexion)
            serieEtat = serie
            planifierReprise()
        }
    }

    /// Automatique : plus de chemin (sonde plus annoncee, cle perdue) et aucune session ouverte : les essais s'arretent, la
    /// sonde est « absente ». `essaisReprise` reste, pour l'espacement du retour.
    private func arreterReseau() {
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        dernierePerte = nil
        deconnecter(serie == nil ? .sansSonde : .absente)
    }

    /// Retour a l'USB attendu : la carte doit rester branchee `delaiRetourUSB` ; `reevaluer` decide ensuite, d'apres l'etat de
    /// ce moment-la (une carte repartie dans l'intervalle annule le retour, `annulerRetourUSB`).
    private func planifierRetourUSB() {
        guard retourUSB == nil else { return }
        let delai = delaiRetourUSB
        retourUSB = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self else { return }
            self.retourUSB = nil
            self.reevaluer(immediat: true)
        }
    }

    private func annulerRetourUSB() {
        retourUSB?.cancel()
        retourUSB = nil
    }

    /// Les hotes que Bonjour montre avec une adresse (l'instantane de Thread, a chaque releve). La sonde est « annoncee » quand
    /// son hote en fait partie. Seul un changement de cette annonce fait choisir le chemin de nouveau : un releve sans effet
    /// ne relance rien. Rien eteint.
    func annoncesChangees(_ hotes: Set<String>) {
        guard actif else { return }
        let avant = annoncee
        let nouvelles = Set(hotes.map { $0.uppercased() })
        if nouvelles != annonces { annonces = nouvelles }
        guard annoncee != avant else { return }
        reevaluer()
    }

    /// Oublie la sonde retenue (numero de serie, nom, nom d'hote, cle de ce Mac pour elle :
    /// la sonde garde la sienne), son releve (etat, dernier releve, erreur de tournee) et son
    /// maillage dans le graphe (`surOubli`), et ferme la liaison ; retour a l'USB. L'etat change
    /// tout de suite, avant toute attente ; la cle s'efface ensuite hors de l'acteur principal, et
    /// le nom d'hote part avec elle. Si le trousseau refuse d'effacer la cle, l'echec est montre
    /// et le nom d'hote reste (comme la cle) : « Oublier » peut etre relance.
    func oublier() async {
        preferences.removeObject(forKey: Self.cleSerie)
        retenirSerie(nil)
        choixRefuse = nil
        retenirNom(nil)
        erreurAcces = nil
        // Plus de sonde, plus de reglage : retour a Automatique, comme une nouvelle installation.
        reglage = .automatique
        liaison = .usb
        preferences.removeObject(forKey: Self.cleLiaison)
        reprise?.cancel()
        annulerRetourUSB()
        essaisReprise = 0
        dernierePerte = nil
        etatSonde = nil
        derniereTournee = nil
        erreurTournee = nil
        couverture = nil
        surOubli?()
        deconnecter(.sansSonde)
        guard let h = hote else { return }
        let t = trousseau
        do {
            try await Self.horsActeurPrincipal { try t.oublier(nom: h) }
            // Pendant l'effacement, la sonde choisie de nouveau a pu donner un autre nom d'hote : il reste.
            if hote == h { retenirHote(nil) }
        } catch {
            erreurAcces = String(localized: "Clé de \(h).local non retirée du trousseau : \(error.localizedDescription)")
        }
    }

    /// Nom d'hote de la sonde retenue, garde a cote de son numero de serie ; l'empreinte de la
    /// cle de ce Mac pour lui est relue du trousseau.
    private func retenirHote(_ h: String?) {
        if let h {
            preferences.set(h, forKey: Self.cleHote)
        } else {
            preferences.removeObject(forKey: Self.cleHote)
        }
        hote = h
        empreinteAcces = h.flatMap(empreinte(pour:))
    }

    private func empreinte(pour nom: String) -> String? {
        trousseau.lister().first { $0.nom == nom }?.empreinte
    }

    /// Nom donne par le dernier `bonjour` : retenu a cote du numero de serie, efface si le
    /// firmware n'en donne pas.
    private func retenirNom(_ n: String?) {
        if let n {
            preferences.set(n, forKey: Self.cleNom)
        } else {
            preferences.removeObject(forKey: Self.cleNom)
        }
        nom = n
    }

    /// Tournee tout de suite (bouton rafraichir) ; rien pendant une tournee : relancer la
    /// boucle ne ferait que repousser la suivante de 5 min apres ce clic.
    func rafraichir() {
        guard tourneeAuRafraichir else { return }
        lancerBoucle(attendre: false)
    }

    /// Ports branches : la sonde retenue revient, ou s'en va.
    /// Avec « Reseau Thread » choisi, la sonde n'est jamais ouverte en USB, meme branchee. En Automatique, le chemin change
    /// avec la carte : elle part, le reseau (si la cle est connue et la sonde annoncee) ; elle revient, l'USB.
    func portsChanges(_ liste: [PortUSB]) {
        portsVus = liste.filter(\.estEspressif)
        portsConnus = true
        choixRefuse = nil
        guard actif, reglage != .reseau else { return }
        if reglage == .automatique { reevaluer() }
        guard liaison == .usb, let serie else { return }
        if let p = ports.first(where: { $0.serie == serie }) {
            // `lancerConnexion` passe tout de suite a `.connexion` : un second appel n'en lance pas d'autre.
            if sonde == nil && etat != .connexion { lancerConnexion(p, choisi: false) }
        } else if (sonde != nil || etat != .absente) && !versUnAutrePort {
            deconnecter(.absente)
        }
    }

    /// Une connexion, en cours ou etablie, vise un autre port que celui de la sonde retenue (un
    /// choix des Reglages) : l'absence de la sonde retenue ne l'annule pas.
    private var versUnAutrePort: Bool {
        (etat == .connexion || sonde != nil) && serieEtat != serie
    }

    /// Connexion au port : ferme la liaison en place et attend qu'elle le soit
    /// vraiment, ouvre le port, le garde s'il repond en sonde. Perimee par un
    /// `deconnecter` pendant une attente, elle ferme sa liaison (en l'attendant)
    /// et sort sans toucher a l'etat, a la sonde, ni au numero de serie retenu.
    /// Automatique (`choisi` faux) et en echec, elle est refaite une fois apres
    /// `delaiNouvelEssai` ; `dernierEssai` : c'est ce nouvel essai.
    func connecter(_ port: PortUSB, choisi: Bool, dernierEssai: Bool = false) async {
        guard ouvrable(port, choisi: choisi) else {
            refuserConnexionEnCours(port)
            return
        }
        deconnecter(.connexion, port: port)
        let n = essai
        // Tant que l'ancienne liaison tient le port, TIOCEXCL refuse de le rouvrir.
        await fermetures?.value
        guard n == essai else { return }
        // L'autre module a pu retenir la carte pendant l'attente : rien n'est ouvert, la sonde ne reste pas en « connexion ».
        guard ouvrable(port, choisi: choisi) else {
            refuserConnexionEnCours(port)
            return
        }
        let s = SondeUSB(canal: ouvrirCanal(port.chemin))
        enConnexion = s
        do {
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            guard n == essai else {
                await s.fermer()
                return
            }
            let b = try await s.bonjour()
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "\(port.libelle) n'est pas une sonde (« \(b.produit) »)"))
                return
            }
            // Zigbee a retenu cette carte pendant la connexion (deux choix en meme temps) : elle n'est pas a nous.
            if let autre = cartes.retenuePar(port.serie, hors: .thread) {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
                return
            }
            enConnexion = nil
            sonde = s
            cheminConnecte = port.chemin
            etat = .connectee(b)
            // Une liaison etablie par l'USB : les echecs du reseau d'avant ne comptent plus.
            essaisReprise = 0
            if choisi, let serieUSB = port.serie {
                let autre = serieUSB != serie
                preferences.set(serieUSB, forKey: Self.cleSerie)
                retenirSerie(serieUSB)
                // Le nom d'hote retenu etait celui d'une autre sonde, comme le releve.
                if autre {
                    retenirHote(nil)
                    etatSonde = nil
                    derniereTournee = nil
                    erreurTournee = nil
                    couverture = nil
                }
            }
            // Le nom va avec la sonde retenue (un port sans numero de serie ne l'est pas).
            let retenue = port.serie != nil && port.serie == serie
            retenirNom(retenue ? b.nom : nil)
            // Son nom d'hote aussi, s'il est connu (nil tant que Matter ne l'a pas enregistre).
            if retenue, let h = b.hote, h != hote { retenirHote(h) }
            lancerBoucle()
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = choisi ? .refusee(error.localizedDescription) : .erreur(error.localizedDescription)
            if !choisi && !dernierEssai { planifierNouvelEssai(port) }
        }
    }

    /// `connecter` refuse ce port (l'autre module retient sa carte) alors que `lancerConnexion` a deja passe la sonde en
    /// `.connexion` pour lui : elle passe en `.refusee` au lieu de rester bloquee (`portsChanges` ne relance pas une sonde en
    /// connexion). Sans effet si la sonde n'attend pas ce port (appel direct, autre connexion en cours).
    private func refuserConnexionEnCours(_ port: PortUSB) {
        guard case .connexion = etat, enConnexion == nil, sonde == nil, serieEtat == port.serie,
              let autre = cartes.retenuePar(port.serie, hors: .thread) else { return }
        etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
    }

    /// Connexion lancee sans l'attendre (Reglages, ports) : la liaison en place
    /// est fermee et `etat` passe a `.connexion` tout de suite ; un `deconnecter`
    /// d'ici au depart de la tache (oublier, autre choix, port retire) l'annule.
    private func lancerConnexion(_ port: PortUSB, choisi: Bool) {
        guard ouvrable(port, choisi: choisi) else { return }
        deconnecter(.connexion, port: port)
        let n = essai
        Task {
            guard n == essai else { return }
            await connecter(port, choisi: choisi)
        }
    }

    /// Nouvel essai d'une connexion automatique en echec, apres `delaiNouvelEssai`, si rien n'a
    /// change depuis (aucun `deconnecter` : ni evenement USB, ni choix, ni oubli). C'est le seul :
    /// en echec a son tour, la sonde attend l'evenement USB suivant.
    private func planifierNouvelEssai(_ port: PortUSB) {
        let n = essai
        let delai = delaiNouvelEssai
        nouvelEssai?.cancel()
        nouvelEssai = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.liaison == .usb else { return }
            await self.connecter(port, choisi: false, dernierEssai: true)
        }
    }

    private func liaisonFermee(_ s: SondeUSB) {
        guard sonde === s else { return }
        guard liaison == .reseau else {
            deconnecter(.absente)
            return
        }
        // Veille sans reponse (sonde debranchee, redemarree), session perdue : cause montree, et
        // gardee jusqu'a la connexion suivante reussie, puis reconnexion.
        let cause = (canalReseau as? any CauseFermeture)?.raisonFermeture ?? String(localized: "liaison réseau perdue")
        dernierePerte = Perte(cause: cause, date: horloge())
        deconnecter(.erreur(cause))
        serieEtat = serie
        // Automatique : la carte est peut-etre revenue, ou la sonde n'est plus annoncee ; sinon, la reprise.
        reevaluer(immediat: true)
        guard liaison == .reseau else { return }
        planifierReprise()
    }

    // MARK: - Reseau

    /// Connexion par le reseau lancee sans l'attendre (Reglages, lancement) : la liaison en
    /// place est fermee et `etat` passe a `.connexion` tout de suite.
    private func lancerConnexionReseau() {
        deconnecter(.connexion)
        serieEtat = serie
        let n = essai
        Task {
            guard n == essai else { return }
            await connecterReseau()
        }
    }

    /// Connexion a la sonde retenue par le reseau Thread : cle du trousseau, session vers
    /// `<hote>.local:5480` (poignee de main H1), `bonjour`, puis tournees. Un echec est montre et
    /// la connexion reprise seule (1, 2, 5, 10 s, puis toutes les 30 s), sauf sans cle (il faut
    /// l'USB). Perimee par un `deconnecter`, elle ferme sa liaison et sort sans rien toucher.
    func connecterReseau() async {
        // Liaison USB : rien a fermer ni a changer.
        guard actif, liaison == .reseau else { return }
        deconnecter(.connexion)
        serieEtat = serie
        let n = essai
        // La liaison USB en place est vraiment fermee : le port est libre.
        await fermetures?.value
        guard n == essai, liaison == .reseau else { return }
        var canal: (any CanalSonde)?
        do {
            guard let hote else { throw CleReseau.Erreur.sansNomDHote }
            let cle = try await lireCle(hote)
            // Arretee (ou autre liaison choisie) pendant la lecture de la cle : aucune session n'est ouverte.
            guard n == essai else { return }
            let c = try await ouvrirReseau(hote, cle)
            canal = c
            guard n == essai else {
                c.fermer()
                return
            }
            // Par le reseau, une commande attend au-dela du renvoi de 4 s du canal.
            let s = SondeUSB(canal: c, delaiCommande: SondeUSB.delaiCommandeReseau)
            enConnexion = s
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            let b = try await s.bonjour()
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "\(hote).local n'est pas une sonde (« \(b.produit) »)"))
                return
            }
            enConnexion = nil
            sonde = s
            canalReseau = c
            tenirActivite()
            etat = .connectee(b)
            dernierePerte = nil
            essaisReprise = 0
            retenirNom(b.nom)
            lancerBoucle()
        } catch {
            // Session ouverte puis abandonnee (bonjour sans reponse...) : fermee ici.
            canal?.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = .erreur(error.localizedDescription)
            // Sans cle ou sans nom d'hote (trousseau, ou jamais appris) : il faut l'USB ; le reste
            // se reprend seul. Cle refusee ou absente : l'etat d'acces est relu (la reprise etant
            // notee, la liste ne montre plus l'ancienne cle : « non autorise », pas de selecteur).
            if error is ErreurTrousseauThread { empreinteAcces = hote.flatMap(empreinte(pour:)) }
            if error is ErreurTrousseauThread || error is CleReseau.Erreur { return }
            if let e = error as? ErreurReseau, !e.repriseAutomatique { return }
            planifierReprise()
        }
    }

    /// La lecture de la cle en vol, avec son numero : une seule a la fois (voir `lireCle`).
    @ObservationIgnored private var lectureCle: (numero: Int, hote: String, tache: Task<Data, any Error>)?
    @ObservationIgnored private var numeroLecture = 0

    /// Lit la cle de l'hote, une seule lecture en vol : une seconde tentative (carte rebranchee puis retiree, annonce qui
    /// tombe puis revient, pendant que macOS attend l'accord de l'utilisateur) rejoint la lecture en cours au lieu d'en lancer
    /// une autre. Sinon la seconde echouerait en `absente` (la reprise est deja notee) et l'acces reseau serait indisponible
    /// jusqu'au relancement, alors que l'accord donne a la premiere recopie la cle. Le resultat est le meme pour toutes ; la
    /// liste du trousseau est relue a la fin, la recopie ayant change ce qu'elle montre.
    private func lireCle(_ hote: String) async throws -> Data {
        if let l = lectureCle, l.hote == hote { return try await l.tache.value }
        let t = trousseau
        let tache = Task { try await Self.horsActeurPrincipal { try t.lire(nom: hote) } }
        numeroLecture += 1
        let numero = numeroLecture
        lectureCle = (numero, hote, tache)
        defer {
            if lectureCle?.numero == numero { lectureCle = nil }
            if self.hote == hote { empreinteAcces = empreinte(pour: hote) }
        }
        return try await tache.value
    }

    /// Operation du trousseau hors de l'acteur principal : macOS peut d'abord demander
    /// l'autorisation d'acceder au trousseau (fenetre modale, signature ad hoc), sans figer le
    /// menu. Pour la lecture de la cle comme pour les ecritures (ranger, oublier) ; la liste des
    /// cles (attributs seulement, sans la cle) reste lue sur place.
    private nonisolated static func horsActeurPrincipal<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try operation() }.value
    }

    private func tenirActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session reseau de la sonde : veille et tournees")
    }

    private func relacherActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    /// Nouvel essai de la liaison reseau apres un delai croissant.
    private func planifierReprise() {
        let delai = delaisReprise[min(essaisReprise, delaisReprise.count - 1)]
        essaisReprise += 1
        let n = essai
        reprise?.cancel()
        reprise = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.liaison == .reseau else { return }
            await self.connecterReseau()
        }
    }

    // MARK: - Cle

    /// « Autoriser l'acces reseau » (Reglages, sonde retenue branchee en USB) : `bonjour` pour un
    /// nom d'hote a jour (sans lui, aucune cle n'est demandee), `cle nouvelle` par l'USB, cle
    /// verifiee puis rangee dans le trousseau sous ce nom. La carte remplace sa cle : une session
    /// reseau en cours (autre Mac) tombe.
    func autoriserAccesReseau() async {
        guard peutAutoriser, let s = sonde else { return }
        autorisationEnCours = true
        erreurAcces = nil
        defer { autorisationEnCours = false }
        do {
            let b = try await s.bonjour()
            if sonde === s {
                etat = .connectee(b)
                retenirNom(b.nom)
            }
            guard let nomHote = b.hote, !nomHote.isEmpty else { throw CleReseau.Erreur.sansNomDHote }
            let reponse = try await s.cleNouvelle(alea: CleReseau.alea())
            let c = try CleReseau.verifier(reponse).get()
            // La carte a adopte la cle : elle se range meme si la liaison s'est fermee depuis, sous
            // le nom d'hote de la reponse, sinon (nul ou vide) sous celui du `bonjour`.
            let nom = c.hote.flatMap { $0.isEmpty ? nil : $0 } ?? nomHote
            // Ecritures hors de l'acteur principal, comme la lecture de la cle.
            let t = trousseau
            try await Self.horsActeurPrincipal { try t.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte) }
            retenirHote(nom)
            // Une seule sonde retenue : les cles d'autres noms d'hote (mise en service anterieure)
            // ne servent plus ; un echec est montre, la nouvelle cle reste rangee.
            for ancien in trousseau.lister() where ancien.nom != nom {
                do {
                    try await Self.horsActeurPrincipal { try t.oublier(nom: ancien.nom) }
                } catch {
                    erreurAcces = String(localized: "Clé rangée ; l'ancienne clé de \(ancien.nom).local n'a pas pu être retirée du trousseau : \(error.localizedDescription)")
                }
            }
        } catch {
            erreurAcces = error.localizedDescription
        }
    }

    /// Ferme sans attendre la liaison connectee et celle d'une connexion en
    /// cours, qui devient perimee ; `connecter` attend ces fermetures. `port` :
    /// celui que le nouvel etat concerne (connexion).
    private func deconnecter(_ nouveau: Etat, port: PortUSB? = nil) {
        essai += 1
        boucle?.cancel()
        boucle = nil
        for s in [sonde, enConnexion].compactMap({ $0 }) {
            let precedentes = fermetures
            fermetures = Task {
                await s.fermer()
                await precedentes?.value
            }
        }
        sonde = nil
        enConnexion = nil
        canalReseau = nil
        relacherActivite()
        cheminConnecte = nil
        serieEtat = port?.serie
        etat = nouveau
    }

    /// `attendre` : la premiere tournee attend le premier releve Bonjour (`attendreReseau`), a chaque nouvelle
    /// liaison ; pas un clic sur rafraichir, un ordre explicite.
    private func lancerBoucle(attendre: Bool = true) {
        boucle?.cancel()
        boucle = Task { [weak self] in
            if attendre { await self?.attendreReseau() }
            while !Task.isCancelled {
                await self?.uneTournee()
                try? await Task.sleep(for: Self.periode)
            }
        }
    }

    /// Avant la premiere tournee d'une liaison, attend que l'app ait recu son premier releve Bonjour (`reseauConnu`),
    /// quelques secondes apres le lancement, au plus `attenteReseau`. Sans lui, la liste des appareils a resoudre est
    /// vide : la sonde ne rattache aucun enfant sous les routeurs muets, et la premiere carte (ou le dernier maillage
    /// garde, relu au lancement) laisserait place a une carte appauvrie jusqu'a la tournee suivante, 5 min plus tard
    /// (banc du 12/10 : 2 enfants au lieu de 24). Ensuite (reconnexion), le releve est la : pas d'attente.
    private func attendreReseau() async {
        guard let connu = reseauConnu else { return }
        let fin = ContinuousClock.now + attenteReseau
        while !Task.isCancelled, !connu(), ContinuousClock.now < fin {
            try? await Task.sleep(for: pasAttenteReseau)
        }
    }

    /// Etat de la sonde, puis une tournee ; le maillage part a la surveillance,
    /// avec l'heure de sa reception (la fin de la tournee), entre les signaux de
    /// debut et de fin de la tournee. L'avancement et l'heure du debut sont exposes
    /// pendant la tournee, remis a nil a sa fin (erreur et liaison fermee comprises).
    func uneTournee() async {
        guard let sonde, !tourneeEnCours else { return }
        tourneeEnCours = true
        debutTournee = horloge()
        surTournee?(true)
        // L'avancement vient de la tache de la tournee : il passe sur le MainActor dans
        // l'ordre, et tout est lu avant la remise a nil.
        let (flux, suite) = AsyncStream.makeStream(of: AvancementTournee.self)
        let lecture = Task { @MainActor [weak self] in
            for await a in flux { self?.avancement = a }
        }
        await executerTournee(sonde) { suite.yield($0) }
        suite.finish()
        await lecture.value
        avancement = nil
        debutTournee = nil
        tourneeEnCours = false
        surTournee?(false)
    }

    /// Corps de `uneTournee` : ses erreurs sont retenues ici, sauf la liaison fermee (`liaisonFermee`).
    /// Rien n'est retenu d'une tournee dont la liaison n'est plus celle de la sonde (oubliee,
    /// debranchee, reconnectee) : une reponse arrivee apres l'oubli ne remet ni releve ni maillage.
    private func executerTournee(_ sonde: SondeUSB, suivi: @escaping @Sendable (AvancementTournee) -> Void) async {
        do {
            let e = try await sonde.etat()
            guard sonde === self.sonde else { return }
            etatSonde = e
            let appareils = appareilsAResoudre?() ?? []
            let r = try await Tournee.executer(sonde, memoire: memoire, maintenant: horloge(), appareils: appareils,
                                               avancement: suivi)
            guard sonde === self.sonde else { return }
            // Meme sans maillage (pas de liste des routeurs), les identites apprises sont gardees.
            memoire = r.memoire
            garderIdentites()
            if let m = r.maillage {
                let recu = horloge()
                derniereTournee = recu
                couverture = m.couverture
                surMaillage?(m, recu)
            }
            erreurTournee = nil
        } catch SondeUSB.Erreur.fermee {
            // La liaison est fermee : `liaisonFermee` s'en occupe.
        } catch {
            guard sonde === self.sonde else { return }
            erreurTournee = error.localizedDescription
        }
    }

    /// Ecrit les identites des routeurs si elles ont change depuis le fichier. Un echec est
    /// consigne dans le journal du Mac ; les identites restent en memoire et l'ecriture est
    /// retentee a la tournee suivante.
    private func garderIdentites() {
        guard let f = fichierIdentites, let g = memoire.identitesGardees, g != identitesDuFichier else { return }
        do {
            try g.ecrire(dans: f)
            identitesDuFichier = g
        } catch {
            Self.journal.error("identites des routeurs non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }
}
