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

    var etat: Etat = .sansSonde
    /// Ports Espressif branches, tels que le dernier evenement USB les a listes (`ports` en retire ceux de l'autre module).
    var portsVus: [PortUSB] = []
    /// Ports Espressif que cette sonde propose et peut ouvrir : les C6 branches, sauf ceux que Zigbee retient (spec 3.4).
    /// Un autre C6 (le pont Halo) y figure : il n'est ouvert que si on le choisit.
    var ports: [PortUSB] { cartes.choix(portsVus, pour: .thread) }
    /// Numero de serie USB de la sonde retenue ; seule `retenirSerie` l'ecrit, car elle le publie aux cartes retenues.
    var serie: String?
    /// Le choix d'un port refuse parce que la carte est la sonde de l'autre module ; nil sinon. Efface par un autre choix,
    /// un evenement USB ou « Oublier la sonde ».
    var choixRefuse: String?
    /// Nom de la sonde (« SONDE-T1 »), mis a jour a chaque `bonjour` ; nil si le firmware
    /// n'en donne pas (1.0.0) ou sans sonde retenue.
    var nom: String?
    /// Numero de serie USB du port que l'etat concerne (connexion, connexion etablie, refus,
    /// erreur) ; nil sans sonde ou la sonde retenue absente.
    var serieEtat: String?
    var etatSonde: EtatSonde?
    /// Reception du dernier maillage (fin de sa tournee).
    var derniereTournee: Date?
    var tourneeEnCours = false
    /// Avancement de la tournee en cours ; nil hors tournee.
    var avancement: AvancementTournee?
    /// Debut de la tournee en cours ; nil hors tournee.
    var debutTournee: Date?
    /// Derniere erreur d'une tournee (la liaison reste ouverte).
    var erreurTournee: String?
    /// Couverture de l'ecoute au dernier maillage (firmware 1.1.0, spec de la sonde tout-en-un, section 2.4) : les
    /// routeurs que la sonde entend, sur ceux de la partition ; nil sans (firmware plus ancien, sans releve).
    var couverture: CouvertureEcoute?
    /// Reglage de liaison (`thread.sondeLiaison`) : seul Automatique decide du chemin (`reevaluer`) ; USB et Reseau Thread le
    /// fixent, comme avant.
    var reglage: ReglageLiaison = .automatique
    /// Le chemin en service, ou vise : le reseau pendant une session ou ses reprises, l'USB sinon (aussi au repos, sans rien
    /// de connecte). Fixe par le reglage, ou, en Automatique, par `reevaluer`.
    var liaison: Liaison = .usb
    /// Les hotes SRP que Bonjour montre avec une adresse (instantane de Thread, `annoncesChangees`), en majuscules : le signal
    /// « annoncee ». Vide a l'arret de la sonde, comme l'instantane qu'il reflete.
    var annonces: Set<String> = []
    /// La sonde retenue est annoncee : son hote SRP est parmi `annonces`. Sans nom d'hote (jamais appris), jamais.
    var annoncee: Bool { CheminLiaison.annoncee(hote: hote, parmi: annonces) }
    /// Nom d'hote SRP de la sonde retenue (sans `.local`) : l'acces reseau vise `<hote>.local`.
    var hote: String?
    /// Empreinte de la cle de ce Mac pour la sonde retenue (trousseau) ; nil sans cle.
    var empreinteAcces: String?
    /// « Autoriser l'acces reseau » en cours (cle demandee par l'USB).
    var autorisationEnCours = false
    /// Echec de la derniere operation sur l'acces reseau (autorisation, oubli de la cle) ; nil
    /// apres une reussite.
    var erreurAcces: String?
    /// Derniere session reseau perdue, gardee jusqu'a la connexion suivante reussie (l'etat ne
    /// montre sa cause qu'un instant, avant la reprise) ; effacee par un changement de liaison
    /// ou l'oubli de la sonde.
    var dernierePerte: Perte?
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

    @ObservationIgnored let preferences: UserDefaults
    /// Les cartes retenues par chaque module : la serie de cette sonde y est publiee, celle de Zigbee en est retiree des choix.
    @ObservationIgnored let cartes: CartesRetenues
    /// Attente du premier releve Bonjour et pas de sa relecture (`attendreReseau`) ; courts dans les tests.
    @ObservationIgnored let attenteReseau: Duration
    @ObservationIgnored let pasAttenteReseau: Duration
    /// Faux (demo, tests) : la sonde ne touche ni port, ni preferences, ni trousseau (lu par `DemarrageTests`). Faux aussi
    /// entre `arreter()` (Thread eteint) et `demarrer()` : aucun port n'est suivi, ouvert ni rouvert (les entrees
    /// publiques gardent `actif`).
    var actif: Bool
    /// Construite pour agir (`actif` vrai au depart) : seule une telle sonde s'arrete et repart ; celle de la demo et des
    /// tests reste inerte, quoi qu'on lui demande.
    @ObservationIgnored let vivante: Bool
    /// Ou les ports sont suivis, et comment on les liste (factices dans les tests : aucun IOKit).
    @ObservationIgnored let surveillerPorts: @MainActor () -> any SurveillantPorts
    @ObservationIgnored let listerPorts: @Sendable () -> [PortUSB]
    @ObservationIgnored let ouvrirCanal: (String) -> any CanalSonde
    /// Cles de l'acces reseau : en memoire par defaut, celui du Mac au lancement de l'app.
    @ObservationIgnored let trousseau: any TrousseauClesThread
    /// Session reseau vers `<hote>.local` avec la cle : le canal pret, ou l'erreur.
    @ObservationIgnored let ouvrirReseau: @MainActor (String, Data) async throws -> any CanalSonde
    @ObservationIgnored let delaisReprise: [Duration]
    @ObservationIgnored let delaiNouvelEssai: Duration
    @ObservationIgnored let delaiRetourUSB: Duration
    /// Retour a l'USB attendu (Automatique, session reseau en cours, carte branchee) : sa tache dort `delaiRetourUSB`.
    @ObservationIgnored var retourUSB: Task<Void, Never>?
    /// Le premier evenement USB est arrive (`portsChanges`) : les cartes branchees sont connues. Avant, Automatique ne choisit
    /// pas (une annonce Bonjour ne doit pas passer sur le reseau avant d'avoir regarde l'USB).
    @ObservationIgnored var portsConnus = false
    /// Echecs de la liaison reseau depuis la derniere connexion reussie.
    @ObservationIgnored var essaisReprise = 0
    @ObservationIgnored var reprise: Task<Void, Never>?
    /// Nouvel essai planifie d'une connexion automatique (USB) en echec.
    @ObservationIgnored var nouvelEssai: Task<Void, Never>?
    /// Canal de la session reseau en place : sa cause de fermeture est montree a la perte.
    @ObservationIgnored var canalReseau: (any CanalSonde)?
    /// Activite tenue pendant une session reseau, comme la session serie de Halo : sans elle,
    /// App Nap retarderait la veille du canal (la carte oublie une session muette) et les tournees.
    @ObservationIgnored var activite: (any NSObjectProtocol)?
    /// Heure du debut de la tournee et de la reception du maillage (injectee par les tests).
    @ObservationIgnored let horloge: () -> Date
    @ObservationIgnored var sonde: SondeUSB?
    /// Chemin du port de `sonde` (nil sans sonde connectee).
    @ObservationIgnored var cheminConnecte: String?
    /// Liaison d'une connexion en cours, avant sa verification : `deconnecter`
    /// la ferme aussi.
    @ObservationIgnored var enConnexion: SondeUSB?
    /// Numero d'essai, incremente par `deconnecter` : une connexion dont le
    /// numero a change est perimee et ne touche plus a rien.
    @ObservationIgnored private(set) var essai = 0
    /// Fermetures lancees par `deconnecter`, chainees : une connexion attend
    /// qu'elles soient finies (ports vraiment fermes) avant d'ouvrir un port.
    @ObservationIgnored private(set) var fermetures: Task<Void, Never>?
    @ObservationIgnored var memoire = MemoireTournee()
    /// Fichier des identites des routeurs (`fichierIdentites(demo:sousTests:)`) : lu au lancement,
    /// ecrit quand elles changent ; nil : ni lu ni ecrit.
    @ObservationIgnored let fichierIdentites: URL?
    /// Identites telles que le fichier les a (lues ou ecrites en dernier).
    @ObservationIgnored var identitesDuFichier: IdentitesGardees?
    /// Boucle des tournees (lue par les tests).
    @ObservationIgnored private(set) var boucle: Task<Void, Never>?
    @ObservationIgnored var surveillantPorts: (any SurveillantPorts)?
    /// La lecture de la cle en vol, avec son numero : une seule a la fois (voir `lireCle`).
    @ObservationIgnored var lectureCle: (numero: Int, hote: String, tache: Task<Data, any Error>)?
    @ObservationIgnored var numeroLecture = 0

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

    /// Ferme sans attendre la liaison connectee et celle d'une connexion en
    /// cours, qui devient perimee ; `connecter` attend ces fermetures. `port` :
    /// celui que le nouvel etat concerne (connexion).
    func deconnecter(_ nouveau: Etat, port: PortUSB? = nil) {
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
    func lancerBoucle(attendre: Bool = true) {
        boucle?.cancel()
        boucle = Task { [weak self] in
            if attendre { await self?.attendreReseau() }
            while !Task.isCancelled {
                await self?.uneTournee()
                try? await Task.sleep(for: Self.periode)
            }
        }
    }
}
