import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// App de la barre des menus : ecoute le reseau local en permanence, tient
/// le journal, notifie ; graphe et journal dans leurs fenetres.
/// `--args -demo` : rejoue la panne du 27/09, sans rien ecrire ni notifier.
@main
struct MaillageIoTApp: App {
    @State private var surveillance: Surveillance
    @State private var ouverture: OuvertureSession
    @State private var nomsMaison: NomsPasseur
    @State private var sonde: SondeMaillage
    @State private var reglages: ControleurReglages
    @State private var misesAJour: MisesAJour
    private let notifications = Notifications()
    private static let demo = CommandLine.arguments.contains("-demo")
    /// Le graphe s'ouvre au lancement en mode demo et au tout premier lancement
    /// (jamais a l'ouverture de session ensuite).
    private let ouvrirGraphe: Bool
    static let clePremierGraphe = "grapheDejaOuvert"

    init() {
        let s = Surveillance(mode: Self.demo ? .demo : .direct, dossier: Self.demo ? nil : Surveillance.dossierParDefaut)
        let o = OuvertureSession()
        // Les noms de Maison : inerte en demo et sous tests (aucun releve lu, ecrit ni demande au demon Passeur Noms) ;
        // sinon le demon, son dernier releve garde dans `releve-maison.json`, a la racine du dossier de l'app.
        let d = Self.demo || Surveillance.sousTests
            ? NomsPasseur()
            : NomsPasseur(cache: NomsPasseur.fichierCache(dossier: Surveillance.dossierParDefaut),
                          lanceur: NomsPasseur.lancerPasseurDuMac)
        _surveillance = State(initialValue: s)
        _ouverture = State(initialValue: o)
        _nomsMaison = State(initialValue: d)
        // Inerte en demo et sous tests : aucun port ouvert, ni trousseau lu, aucune identite de
        // routeur lue ni ecrite. La cle de l'acces reseau vit dans le trousseau du Mac (les tests
        // gardent le leur en memoire).
        let sm = SondeMaillage(actif: !Self.demo && !Surveillance.sousTests, trousseau: TrousseauSysteme(),
                               fichierIdentites: SondeMaillage.fichierIdentites(demo: Self.demo,
                                                                                sousTests: Surveillance.sousTests))
        _sonde = State(initialValue: sm)
        // Les mises a jour : ni en demo, ni sous les tests (aucune recherche, aucun reseau), ni dans une
        // compilation de travail.
        let m = MisesAJour(demarrer: MisesAJour.demarrerAuLancement(demo: Self.demo))
        _misesAJour = State(initialValue: m)
        _reglages = State(initialValue: ControleurReglages(surveillance: s, ouverture: o, nomsMaison: d, sonde: sm,
                                                           misesAJour: m))
        let premier = !UserDefaults.standard.bool(forKey: Self.clePremierGraphe)
        ouvrirGraphe = !Surveillance.sousTests && (Self.demo || premier)
        guard !Surveillance.sousTests else { return }
        if !Self.demo {
            UserDefaults.standard.set(true, forKey: Self.clePremierGraphe)
            let n = notifications
            s.surAlertes = { n.presenter($0) }
            n.demanderAutorisation()
            o.proposerAuPremierLancement()
            d.surReleve = { [weak s] m in s?.noms.maison = m }
            d.demarrer()
            sm.surMaillage = { [weak s] m, recu in s?.recevoir(m, a: recu) }
            sm.surTournee = { [weak s] enCours in s?.tourneeEnCours = enCours }
            sm.surOubli = { [weak s] in s?.oublierMaillage() }
            sm.appareilsAResoudre = { [weak s] in s?.appareilsAResoudre() ?? [] }
            sm.reseauConnu = { [weak s] in s?.instantane != nil }
            sm.demarrer()
        }
        s.demarrer()
        // `--args -demo -captures <dossier>` : images de la vue par pieces, puis l'app quitte.
        if Self.demo, let dossier = UserDefaults.standard.string(forKey: "captures") {
            CapturesPieces.ecrire(dans: dossier, surveillance: s, sonde: sm, nomsMaison: d)
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarre()
                .environment(surveillance)
                .environment(ouverture)
                .environment(nomsMaison)
                .environment(sonde)
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
                          places: Self.demo ? NomsDemo.places() : nil)
                .environment(surveillance)
                .environment(nomsMaison)
                .environment(sonde)
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
