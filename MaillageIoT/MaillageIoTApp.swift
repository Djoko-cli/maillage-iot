import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

/// App de la barre des menus : ecoute le reseau local en permanence, tient
/// le journal, notifie ; graphe et journal dans leurs fenetres.
/// `--args -demo` : la demo combinee (la panne du 27/09 de Thread et le faux reseau Hue de Zigbee, ensemble) ;
/// `--args -demo-thread` et `--args -demo-zigbee` : chacune seule, l'autre protocole eteint ; sans rien ecrire ni notifier.
@main
struct MaillageIoTApp: App {
    @State private var surveillance: Surveillance
    @State private var ouverture: OuvertureSession
    @State private var nomsMaison: NomsPasseur
    @State private var nomsPont: NomsPont
    @State private var sonde: SondeMaillageThread
    @State private var sondeZigbee: SondeMaillageZigbee
    @State private var reglages: ControleurReglages
    @State private var misesAJour: MisesAJour
    /// L'assistant de reprise (fenetre AppKit, ouvert par Reglages > General, par le premier lancement, par le resume qui suit
    /// une reprise).
    @State private var reprise: ControleurReprise
    private let notifications = Notifications()
    /// Bonjour `_hue._tcp` (le pont de Zigbee), demarre hors demo et hors tests : le seul de l'app.
    private let decouverte: DecouvertePont
    /// La demo rejouee (`-demo`, `-demo-thread`, `-demo-zigbee`) ; nil hors demo.
    private static let demoLancee = DemoLancee.depuis(arguments: CommandLine.arguments)
    private static let demo = demoLancee != nil
    /// Le graphe s'ouvre au lancement en mode demo et au tout premier lancement
    /// (jamais a l'ouverture de session ensuite).
    private let ouvrirGraphe: Bool
    static let clePremierGraphe = "grapheDejaOuvert"

    init() {
        // Une reprise interrompue (l'app arretee en pleine application) est defaite AVANT tout le reste : les modules lisent le
        // dossier de donnees des leur initialisation (`ModulesApp`), il doit etre dans un etat sain. Ni en demo ni sous les tests.
        // Un seul `ApplicationImport` pour toute l'app : deux reprises ne se chevauchent jamais.
        let importeur = ApplicationImport(dossierDonnees: Surveillance.dossierParDefaut)
        let recuperation: Result<IssueRecuperation, ErreurApplication>? =
            LancementReprise.disponible(demo: Self.demo) && !Surveillance.sousTests ? importeur.recupererAuLancement() : nil
        // `-demo` rejoue les deux demos ensemble, `-demo-thread` et `-demo-zigbee` chacune seule (l'autre protocole eteint).
        let m = ModulesApp(demo: Self.demoLancee)
        let s = m.surveillance
        let o = m.ouverture
        _surveillance = State(initialValue: s)
        _ouverture = State(initialValue: o)
        _nomsMaison = State(initialValue: m.nomsMaison)
        _nomsPont = State(initialValue: m.nomsPont)
        decouverte = m.decouverte
        _sonde = State(initialValue: m.sondeThread)
        _sondeZigbee = State(initialValue: m.sondeZigbee)
        // Les mises a jour : ni en demo, ni sous les tests (aucune recherche, aucun reseau), ni dans une
        // compilation de travail.
        let mj = MisesAJour.pourLApp(demo: Self.demo)
        _misesAJour = State(initialValue: mj)
        // L'assistant de reprise : les modules sont arretes avant l'application, l'etat reel du Mac est lu au moment du resume
        // (le refus du reseau local vient de Bonjour, au pont).
        let pont = m.nomsPont
        let assistant = AssistantReprise(
            importeur: importeur, dossierDonnees: Surveillance.dossierParDefaut,
            lecteur: LecteurEtatSystemeReel(reseauLocalRefuse: { await MainActor.run { pont.reseauLocalRefuse } }),
            arreterModules: { m.arreterTout() })
        let controleurReprise = ControleurReprise(assistant: assistant)
        _reprise = State(initialValue: controleurReprise)
        _reglages = State(initialValue: ControleurReglages(surveillance: s, ouverture: o, nomsMaison: m.nomsMaison,
                                                           nomsPont: m.nomsPont, sonde: m.sondeThread,
                                                           sondeZigbee: m.sondeZigbee, misesAJour: mj,
                                                           // En demo, aucune reprise : la demo ne lit ni n'ecrit rien sur le disque.
                                                           reprise: LancementReprise.disponible(demo: Self.demo) ? controleurReprise : nil))
        let premier = !UserDefaults.standard.bool(forKey: Self.clePremierGraphe)
        ouvrirGraphe = !Surveillance.sousTests && (Self.demo || premier)
        guard !Surveillance.sousTests else { return }
        // Les interrupteurs de notification de 3a (une cle par categorie) passent aux cles par protocole, avant que les
        // Reglages les lisent.
        Notifications.reprendreClesCommunes()
        if !Self.demo {
            UserDefaults.standard.set(true, forKey: Self.clePremierGraphe)
            let n = notifications
            s.surAlertes = { n.presenter($0) }
            n.demanderAutorisation()
            o.proposerAuPremierLancement()
            m.brancher()
            // Ce que la recuperation du lancement a defait (jamais en silence), le resume d'une reprise qui vient d'avoir lieu, la
            // proposition du premier lancement : la fenetre s'ouvre seulement s'il y a quelque chose a dire.
            if let recuperation {
                Task { @MainActor in
                    if await assistant.preparerLancement(recuperation: recuperation) {
                        try? await Task.sleep(for: .seconds(1))
                        controleurReprise.montrer()
                    }
                }
            }
        }
        s.demarrer()
        // `--args -demo -captures <dossier>` : images de la vue par pieces, puis l'app quitte.
        if let demo = Self.demoLancee, let dossier = UserDefaults.standard.string(forKey: "captures") {
            CapturesPieces.ecrire(dans: dossier, surveillance: s, demo: demo, sonde: m.sondeThread,
                                  sondeZigbee: m.sondeZigbee, nomsMaison: m.nomsMaison, nomsPont: m.nomsPont)
            exit(0)
        }
    }

    /// Les places de la maison de la demo, en memoire : le jardin au niveau du rez-de-chaussee, hors de la maison (celles de
    /// Thread, que la demo combinee garde : les deux demos ont les memes pieces et les memes etages) ; celles de la demo de
    /// Zigbee seule sont sur ses etages ; nil hors demo.
    private static var placesDeLaDemo: PlacesGardees? {
        switch demoLancee {
        case .thread?, .combinee?: NomsDemo.places()
        case .zigbee?: NomsDemo.placesEtagees()
        case nil: nil
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarre()
                .environment(surveillance)
                .environment(ouverture)
                .environment(nomsMaison)
                .environment(nomsPont)
                .environment(sonde)
                .environment(sondeZigbee)
                .environment(reglages)
                .environment(misesAJour)
        } label: {
            IconeBarre(ouvrirGraphe: ouvrirGraphe)
                .environment(surveillance)
        }
        .menuBarExtraStyle(.window)
        // Les Reglages sont une fenetre AppKit (`ControleurReglages`) : Cmd-virgule l'ouvre.
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") { misesAJour.rechercher() }
                    .disabled(!misesAJour.peutRechercher)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { reglages.montrer() }
                    .keyboardShortcut(",")
            }
        }

        // Sans barre de titre (polissage B, section 1) : SwiftUI pose la barre de titre transparente et le titre
        // masque, et les garde a chaque mise a jour de la fenetre ; les trois boutons restent, et le titre reste
        // celui de la fenetre (Mission Control, menu Fenetre).
        Window("Maillage IoT", id: "graphe") {
            // En demo, le jardin au niveau du rez-de-chaussee, hors de la maison (polissage C, section 7), en memoire.
            FenetrePieces(fichierPlaces: FenetrePieces.fichierPlaces(demo: Self.demo, sousTests: Surveillance.sousTests),
                          fichierPieces: PiecesChoisies.fichier(demo: Self.demo, sousTests: Surveillance.sousTests),
                          places: Self.placesDeLaDemo)
                .environment(surveillance)
                .environment(nomsMaison)
                .environment(nomsPont)
                .environment(sonde)
                .environment(sondeZigbee)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .defaultLaunchBehavior(.suppressed)

        Window("Journal", id: "journal") {
            FenetreJournal()
                .environment(surveillance)
        }
        .defaultSize(width: 720, height: 560)
        .defaultLaunchBehavior(.suppressed)
    }
}
