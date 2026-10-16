import Foundation
import MaillageCoeur
import Observation
import ProtocoleZigbee

// Sonde Zigbee, plan des fichiers et index de la machine d'etats (spec 3.4) : regle -> fichier, fonction.
//  - principal : etats, constantes, `init`, `deconnecter` (`essai` ; annule `boucle`, `entretien`, `reessaiReseau`, `nouvelEssai`) ;
//  - +Chemin   : Automatique, USB d'abord (`reevaluer`, `portsChanges`, `annoncesChangees`) ;
//  - +USB      : `ouvrable`, `connecter`, seul `ouvrirCanal` ; `liaisonFermee` ; nouvel essai 5 a 60 s (`planifierNouvelEssai`) ;
//  - +Reseau   : `injoignable` retentee (`connecterReseau`, `planifierReessaiReseau`) ; liaison muette fermee apres 6 s
//                (`delaiCommandeReseau`) ou 128 s (`delaiTable`) ; pas de mise en service en tournee (`miseEnServicePossible`) ;
//                constante d'entretien 180 s (`periodeEntretien`) ;
//  - +Tournees : tournee 30 s apres `occupee` (`planifierSuite`) ; tournee retenue pendant une mise en service
//                (`planifierTournee`) ; entretien (`entretenir`) ; budget de pages (`attendreBudget`) ;
//  - +Affichage, +Cycle : textes montres, demarrage et arret reel.

/// La sonde vue par l'app : port retenu (par son numero de serie USB), connexion, verification (`bonjour` doit dire
/// `"produit":"sonde-zigbee"`), reprise quand elle est rebranchee, et la boucle des tournees (spec de l'app,
/// section 6) : la premiere ~10 s apres la connexion, puis toutes les 15 minutes, et au bouton Rafraichir. Chaque
/// tournee (`TourneeZigbee`) rend un `MaillageZigbee` a la surveillance (`surMaillage`). Quand une tournee a reporte des
/// routes faute de budget de pages, la passe complementaire (les routes reportees seulement) est lancee des que le
/// budget le permet (`MemoireTourneeZigbee.instantPasseComplementaire`), sans attendre la tournee suivante ; le rythme de
/// 15 minutes reprend a sa fin.
/// Budget de pages : le journal des pages envoyees (10 dernieres minutes) est garde dans les preferences, donc d'un
/// lancement de l'app a l'autre ; une tournee dont les tables de voisins et les routes du pont ne tiennent pas dans la
/// marge restante (550 pages par 10 minutes, `MemoireTourneeZigbee.instantProchaineTournee`) attend l'instant ou elles
/// tiennent (`tourneeDifferee`). Rafraichir n'outrepasse pas cette attente.
/// Securite des ports : l'app n'ouvre jamais un port qu'on ne lui a pas designe (spec de la sonde, section 2) ; sur un
/// port ouvert, `bonjour` d'abord, et rien d'autre tant qu'il ne dit pas `"produit":"sonde-zigbee"`. Elle n'envoie
/// jamais `oubli`, `suspendre`, `reprendre`, `nom` ni `echecs`.
@MainActor
@Observable
final class SondeMaillageZigbee {
    enum Etat: Equatable {
        /// Aucune sonde choisie dans les Reglages.
        case sansSonde
        /// La sonde retenue n'est pas branchee.
        case absente
        /// Le reseau est le chemin choisi, mais la sonde ne repond pas (Wi-Fi coupe, cle refusee).
        case injoignable
        case connexion
        case connectee(BonjourZigbee)
        /// Le port choisi n'est pas une sonde, ou ne repond pas.
        case refusee(String)
        case erreur(String)

        /// La sonde est connectee (par l'USB ou par le reseau).
        var estConnectee: Bool {
            if case .connectee = self { return true }
            return false
        }
    }

    /// Numero de serie USB de la sonde retenue (l'adresse MAC du C6).
    static let cleSerie = "zigbee.sondeSerieUSB"
    /// Nom de la sonde retenue, donne par la carte (`bonjour`).
    static let cleNom = "zigbee.sondeNom"
    /// Adresse longue de la sonde retenue (compte de sa cle dans le trousseau), donnee par `bonjour` en USB.
    static let cleIeee = "zigbee.sondeIeee"
    /// Nom du Wi-Fi donne a la sonde a sa derniere mise en service reussie (jamais le mot de passe) : la page Sonde le
    /// remontre, la carte ne le rendant pas dans `etat`.
    static let cleNomWifi = "zigbee.sondeNomWifi"
    /// Journal des pages envoyees a la sonde dans les 10 dernieres minutes : `[instant, pages, instant, pages...]`
    /// (`BudgetPages.enregistrable`).
    static let cleJournalPages = "zigbee.sondeJournalPages"
    /// Pages de la derniere lecture complete des tables de voisins (estime la suivante apres un relancement).
    static let clePagesTables = "zigbee.sondePagesTables"
    /// Une tournee refusee parce que la sonde n'a pas encore sa pile Zigbee (`occupee`, attente du Wi-Fi au demarrage)
    /// est retentee bientot, au lieu d'attendre le rythme de 15 minutes.
    static let delaiReessaiOccupee: Duration = .seconds(30)
    /// Premiere tournee apres la connexion : le temps que la sonde se rattache si elle vient de demarrer.
    static let delaiPremiereTournee: Duration = .seconds(10)
    /// Une tournee toutes les 15 minutes (spec de l'app, section 6).
    static let periodeTournees: Duration = .seconds(15 * 60)

    var etat: Etat = .sansSonde
    /// Ports Espressif branches, tels que le dernier evenement USB les a listes (`ports` en retire ceux de l'autre module).
    var portsVus: [PortUSB] = []
    /// Numero de serie USB de la sonde retenue ; seule `retenirSerie` l'ecrit, car elle le publie aux cartes retenues.
    var serie: String?
    /// Le choix d'un port refuse parce que la carte est la sonde de l'autre module ; nil sinon. Efface par un autre choix,
    /// un evenement USB ou « Oublier la sonde ».
    var choixRefuse: String?
    /// Nom de la sonde (« SONDE-Z1 »), mis a jour a chaque `bonjour` ; nil sans sonde retenue.
    var nom: String?
    /// Numero de serie USB du port que l'etat concerne (connexion, connexion etablie, refus, erreur) ; nil sans sonde
    /// ou la sonde retenue absente.
    var serieEtat: String?
    /// Dernier `etat` de la sonde, lu a la connexion et a chaque tournee.
    var etatSonde: EtatSondeZigbee?
    /// Reception du dernier maillage (fin de sa tournee).
    var derniereTournee: Date?
    var tourneeEnCours = false
    /// Avancement de la tournee en cours ; nil hors tournee.
    var avancement: AvancementTourneeZigbee?
    /// Debut de la tournee en cours ; nil hors tournee.
    var debutTournee: Date?
    /// Bilan et duree de la derniere tournee faite (Reglages › Sonde) ; nil avant la premiere.
    var bilan: BilanTournee?
    /// Heure de la passe complementaire programmee ; nil sans passe programmee (une seule a la fois).
    var passeComplementaire: Date?
    /// Par ou passe la sonde connectee ; nil sans sonde connectee.
    var acces: Acces?
    /// Adresse longue de la sonde retenue (compte de sa cle dans le trousseau) ; nil avant sa premiere connexion USB.
    var ieee: String?
    /// Nom du Wi-Fi de la derniere mise en service reussie (`cleNomWifi`).
    var nomWifi: String?
    /// La sonde retenue est annoncee par Bonjour sur le reseau local.
    var annoncee = false
    /// macOS refuse `_maillage-zigbee._tcp` a l'app : type absent de la liste NSBonjourServices qu'il connait (NoAuth). La sonde
    /// reste joignable par l'USB.
    var bonjourNonDeclare = false
    /// Le nom de son instance Bonjour, celui que vise la connexion par le reseau : le nom de la sonde, ou ce nom renomme
    /// apres un conflit (`CheminSonde.instance`).
    @ObservationIgnored var instanceAnnoncee: String?
    var reglageChemin: ReglageChemin = .automatique {
        didSet {
            guard reglageChemin != oldValue else { return }
            // Un reglage change sonde eteinte est garde aussi (`vivante`) : seule la sonde inerte (demo, tests) n'ecrit rien.
            if vivante { preferences.set(reglageChemin.rawValue, forKey: CheminSonde.cleReglage) }
            reevaluer()
        }
    }
    /// Empreinte (`H1.kid`, 8 hexa) de la cle de l'acces par le reseau rangee dans le trousseau pour la sonde retenue ;
    /// nil sans cle. Etat observable, relu du trousseau par `relireCleReseau` chaque fois que la cle ou l'adresse
    /// longue peut changer.
    var empreinteAcces: String?

    /// La tournee differee faute de budget de pages (la sonde a deja beaucoup servi) ; nil sans attente de ce genre.
    var tourneeDifferee: TourneeDifferee?
    var dureeTournee: TimeInterval?
    /// Derniere erreur de la sonde connectee (la liaison reste ouverte), ou pourquoi la tournee n'a pas eu lieu.
    var erreurTournee: String?
    /// Appele a chaque nouveau maillage, avec l'heure de sa reception (fin de la tournee).
    @ObservationIgnored var surMaillage: ((MaillageZigbee, Date) -> Void)?
    /// Appele au debut (vrai) et a la fin (faux) de chaque tournee.
    @ObservationIgnored var surTournee: ((Bool) -> Void)?
    /// Appele quand la sonde est oubliee : son maillage part du graphe.
    @ObservationIgnored var surOubli: (() -> Void)?

    @ObservationIgnored let preferences: UserDefaults
    /// Faux (demo, tests) : la sonde ne touche ni port, ni preferences, ni trousseau (lu par `DemarrageTests`). Faux aussi
    /// entre `arreter()` (Zigbee eteint) et `demarrer()` : aucun port n'est suivi, ouvert ni rouvert (les entrees
    /// publiques gardent `actif`).
    var actif: Bool
    /// Construite pour agir (`actif` vrai au depart) : seule une telle sonde s'arrete et repart ; celle de la demo et des
    /// tests reste inerte, quoi qu'on lui demande.
    @ObservationIgnored let vivante: Bool
    /// Ou les ports sont suivis, comment on les liste, et l'ecoute Bonjour des sondes du reseau (factices dans les tests :
    /// aucun IOKit, aucun reseau).
    @ObservationIgnored let surveillerPorts: @MainActor () -> any SurveillantPorts
    /// Les cartes retenues par chaque module : la serie de cette sonde y est publiee, celle de Thread en est retiree des choix.
    @ObservationIgnored let cartes: CartesRetenues
    @ObservationIgnored let listerPorts: @Sendable () -> [PortUSB]
    @ObservationIgnored let fabriqueBonjour: @MainActor (String) -> any EcouteBonjour
    @ObservationIgnored let ouvrirCanal: (String) -> any CanalSonde
    @ObservationIgnored let trousseau: any TrousseauClesZigbee
    @ObservationIgnored let ouvrirReseau: (String, Data) -> any CanalSonde
    @ObservationIgnored let delaiReessaiReseau: Duration
    /// Attente d'une commande sans id par le reseau (`delaiCommandeReseau`).
    @ObservationIgnored let delaiCommandeReseau: Duration
    @ObservationIgnored let periodeEntretien: Duration
    /// Nouvel essai planifie d'une connexion par le reseau en echec.
    @ObservationIgnored var reessaiReseau: Task<Void, Never>?
    /// Relecture periodique d'`etat` de la sonde connectee par le reseau.
    @ObservationIgnored var entretien: Task<Void, Never>?
    @ObservationIgnored var navigateur: (any EcouteBonjour)?
    @ObservationIgnored let delaiNouvelEssai: Duration
    @ObservationIgnored let plafondNouvelEssai: Duration
    @ObservationIgnored let delaiReessaiOccupee: Duration
    /// Nombre d'echecs de suite des nouveaux essais USB (espacement progressif) ; remis a zero par un evenement USB
    /// (`lancerConnexion`) et par une connexion reussie.
    @ObservationIgnored var rangNouvelEssai = 0
    /// Nouvel essai planifie d'une connexion automatique en echec.
    @ObservationIgnored var nouvelEssai: Task<Void, Never>?
    /// Heure des releves (injectee par les tests).
    @ObservationIgnored let horloge: @Sendable () -> Date
    /// Pauses de la tournee (attente du retour de la sonde dans le reseau), injectees par les tests.
    @ObservationIgnored let attendre: @Sendable (Duration) async throws -> Void
    /// Attente avant la prochaine tournee ou passe (injectee par les tests, avec `horloge`).
    @ObservationIgnored let dormir: @Sendable (Duration) async throws -> Void
    @ObservationIgnored let delaiPremiereTournee: Duration
    @ObservationIgnored let periodeTournees: Duration
    /// Echeance d'une table ou des routes (125 s ; les tests la raccourcissent).
    @ObservationIgnored let delaiTable: Duration
    /// Ce que la tournee retient d'une fois sur l'autre (routeurs muets, tables, routes lues, budget de pages) ; remise a
    /// zero avec une autre sonde.
    @ObservationIgnored var memoire = MemoireTourneeZigbee()
    /// La prochaine tournee (attente comprise), et la tournee en cours.
    @ObservationIgnored var boucle: Task<Void, Never>?
    /// Une mise en service est en cours (`autoriserReseau`) : aucune tournee ne part, le `wifi` ferait redemarrer la
    /// sonde en pleine tournee (constat 13 de la relecture finale).
    @ObservationIgnored var miseEnServiceEnCours = false
    /// Une tournee est arrivee a son heure pendant la mise en service : elle part a la fin de celle-ci.
    @ObservationIgnored var tourneeRetenue = false
    @ObservationIgnored var sonde: Sonde?
    /// Chemin du port de `sonde` (nil sans sonde connectee).
    @ObservationIgnored var cheminConnecte: String?
    /// Liaison d'une connexion en cours, avant sa verification : `deconnecter` la ferme aussi.
    @ObservationIgnored var enConnexion: Sonde?
    /// La connexion en cours (`.connexion`) passe par le reseau : une sonde branchee en USB l'interrompt (`portsChanges`).
    /// Remis a faux par `deconnecter`.
    @ObservationIgnored var tentativeReseau = false
    /// Numero d'essai, incremente par `deconnecter` : une connexion dont le numero a change est perimee et ne touche
    /// plus a rien.
    @ObservationIgnored private(set) var essai = 0
    /// Fermetures lancees par `deconnecter`, chainees : une connexion attend qu'elles soient finies (ports vraiment
    /// fermes) avant d'ouvrir un port.
    @ObservationIgnored private(set) var fermetures: Task<Void, Never>?
    @ObservationIgnored var surveillantPorts: (any SurveillantPorts)?

    /// `actif` faux (mode demo, tests) : ni port, ni preferences lues. `trousseau` sans valeur par defaut : seule l'app
    /// passe le trousseau du systeme, les tests un `TrousseauMemoireZigbee` (un oubli ne compile pas : spec sonde Wi-Fi, 4.3).
    init(preferences: UserDefaults = .standard, actif: Bool, trousseau: any TrousseauClesZigbee,
         ouvrirCanal: @escaping (String) -> any CanalSonde = { CanalSerie(liaison: LiaisonSerie(chemin: $0, etiquette: "fr.djoko.maillage.iot.sonde-zigbee"),
                                  decoupeur: { DecoupeurLignesZigbee() }) },
         ouvrirReseau: @escaping (String, Data) -> any CanalSonde = {
             CanalReseauTCP(transport: TransportTCP(service: $0), cle: $1,
                         delaiPoigneeDeMain: SondeMaillageZigbee.delaiPoigneeDeMain)
         },
         delaiReessaiReseau: Duration = SondeMaillageZigbee.delaiReessaiReseau,
         delaiCommandeReseau: Duration = SondeMaillageZigbee.delaiCommandeReseau,
         periodeEntretien: Duration = SondeMaillageZigbee.periodeEntretien,
         delaiNouvelEssai: Duration = SondeMaillageZigbee.delaiNouvelEssai,
         plafondNouvelEssai: Duration = SondeMaillageZigbee.plafondNouvelEssai,
         delaiReessaiOccupee: Duration = SondeMaillageZigbee.delaiReessaiOccupee,
         delaiPremiereTournee: Duration = SondeMaillageZigbee.delaiPremiereTournee,
         periodeTournees: Duration = SondeMaillageZigbee.periodeTournees,
         delaiTable: Duration = ProtocoleSondeZigbee.echeanceTable,
         horloge: @escaping @Sendable () -> Date = { Date() },
         attendre: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         surveillerPorts: @escaping @MainActor () -> any SurveillantPorts = { PortsUSB() },
         listerPorts: @escaping @Sendable () -> [PortUSB] = { PortsUSB.lister() },
         fabriqueBonjour: @escaping @MainActor (String) -> any EcouteBonjour = { NavigateurBonjour(type: $0) },
         cartes: CartesRetenues = CartesRetenues()) {
        self.preferences = preferences
        self.cartes = cartes
        self.actif = actif
        self.vivante = actif
        self.surveillerPorts = surveillerPorts
        self.listerPorts = listerPorts
        self.fabriqueBonjour = fabriqueBonjour
        self.ouvrirCanal = ouvrirCanal
        self.trousseau = trousseau
        self.ouvrirReseau = ouvrirReseau
        self.delaiReessaiReseau = delaiReessaiReseau
        self.delaiCommandeReseau = delaiCommandeReseau
        self.periodeEntretien = periodeEntretien
        self.delaiNouvelEssai = delaiNouvelEssai
        self.plafondNouvelEssai = plafondNouvelEssai
        self.delaiReessaiOccupee = delaiReessaiOccupee
        self.delaiPremiereTournee = delaiPremiereTournee
        self.periodeTournees = periodeTournees
        self.delaiTable = delaiTable
        self.horloge = horloge
        self.attendre = attendre
        self.dormir = dormir
        serie = actif ? preferences.string(forKey: Self.cleSerie) : nil
        cartes.retenir(serie, par: .zigbee)
        nom = actif ? preferences.string(forKey: Self.cleNom) : nil
        ieee = actif ? preferences.string(forKey: Self.cleIeee) : nil
        nomWifi = actif ? preferences.string(forKey: Self.cleNomWifi) : nil
        reglageChemin = actif
            ? ReglageChemin(rawValue: preferences.string(forKey: CheminSonde.cleReglage) ?? "") ?? .automatique
            : .automatique
        memoire = nouvelleMemoire()
        relireCleReseau()
    }

    /// Ferme sans attendre la liaison connectee et celle d'une connexion en cours, qui devient perimee ; `connecter`
    /// attend ces fermetures. `port` : celui que le nouvel etat concerne (connexion).
    func deconnecter(_ nouveau: Etat, port: PortUSB? = nil) {
        essai += 1
        boucle?.cancel()
        boucle = nil
        passeComplementaire = nil
        tourneeDifferee = nil
        finirTournee(nil)
        for s in [sonde, enConnexion].compactMap({ $0 }) {
            let precedentes = fermetures
            fermetures = Task {
                await s.fermer()
                await precedentes?.value
            }
        }
        entretien?.cancel()
        entretien = nil
        reessaiReseau?.cancel()
        reessaiReseau = nil
        sonde = nil
        enConnexion = nil
        tentativeReseau = false
        acces = nil
        cheminConnecte = nil
        serieEtat = port?.serie
        etat = nouveau
    }
}
