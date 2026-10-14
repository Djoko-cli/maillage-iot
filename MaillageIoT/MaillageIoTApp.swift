import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

/// App de la barre des menus : ecoute le reseau local en permanence, tient
/// le journal, notifie ; graphe et journal dans leurs fenetres.
/// `--args -demo` : rejoue la panne du 27/09 de Thread ; `--args -demo-zigbee` : le faux reseau Hue de Zigbee ; chaque demo
/// tourne seule, l'autre protocole eteint (la demo combinee est a l'etape 3b) ; sans rien ecrire ni notifier.
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
    private let notifications = Notifications()
    /// Bonjour `_hue._tcp` (le pont de Zigbee), demarre hors demo et hors tests : le seul de l'app.
    private let decouverte: DecouvertePont
    /// Le protocole dont la demo est rejouee (`-demo`, `-demo-zigbee`) ; nil hors demo.
    private static let protocoleDemo = ModulesApp.protocoleDeLaDemo(arguments: CommandLine.arguments)
    private static let demo = protocoleDemo != nil
    /// Le graphe s'ouvre au lancement en mode demo et au tout premier lancement
    /// (jamais a l'ouverture de session ensuite).
    private let ouvrirGraphe: Bool
    static let clePremierGraphe = "grapheDejaOuvert"

    init() {
        // `-demo` rejoue la panne de Thread, `-demo-zigbee` le reseau Hue de Zigbee : une demo a la fois, l'autre protocole
        // eteint (la demo combinee est a l'etape 3b).
        let m = ModulesApp(demo: Self.protocoleDemo)
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
        let mj = MisesAJour(demarrer: MisesAJour.demarrerAuLancement(demo: Self.demo))
        _misesAJour = State(initialValue: mj)
        _reglages = State(initialValue: ControleurReglages(surveillance: s, ouverture: o, nomsMaison: m.nomsMaison,
                                                           nomsPont: m.nomsPont, sonde: m.sondeThread,
                                                           sondeZigbee: m.sondeZigbee, misesAJour: mj))
        let premier = !UserDefaults.standard.bool(forKey: Self.clePremierGraphe)
        ouvrirGraphe = !Surveillance.sousTests && (Self.demo || premier)
        guard !Surveillance.sousTests else { return }
        if !Self.demo {
            UserDefaults.standard.set(true, forKey: Self.clePremierGraphe)
            let n = notifications
            s.surAlertes = { n.presenter($0) }
            n.demanderAutorisation()
            o.proposerAuPremierLancement()
            m.brancher()
        }
        s.demarrer()
        // `--args -demo -captures <dossier>` : images de la vue par pieces, puis l'app quitte.
        if let protocole = Self.protocoleDemo, let dossier = UserDefaults.standard.string(forKey: "captures") {
            CapturesPieces.ecrire(dans: dossier, surveillance: s, protocole: protocole, sonde: m.sondeThread,
                                  sondeZigbee: m.sondeZigbee, nomsMaison: m.nomsMaison, nomsPont: m.nomsPont)
            exit(0)
        }
    }

    /// Les places de la maison de la demo, en memoire : le jardin au niveau du rez-de-chaussee, hors de la maison ; celles de
    /// la demo de Zigbee sont sur ses etages ; nil hors demo.
    private static var placesDeLaDemo: PlacesGardees? {
        switch protocoleDemo {
        case .thread?: NomsDemo.places()
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
