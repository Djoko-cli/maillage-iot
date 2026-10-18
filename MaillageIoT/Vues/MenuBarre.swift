import AppKit
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

/// Icone de la barre des menus : le symbole du maillage seul ; orange quand il y a une alerte. Ouvre le graphe au
/// lancement quand on le lui demande (mode demo, premier lancement).
struct IconeBarre: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.openWindow) private var openWindow
    let ouvrirGraphe: Bool
    private static var grapheOuvert = false

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: Self.image(alerte: surveillance.alerte))
            // L'app de repetition (a cote de la vraie, dans la meme barre) se reconnait a son « R ».
            if IdentiteApp.courante.estRepetition { Text(verbatim: "R").font(.system(size: 11, weight: .bold)) }
        }
            .task {
                guard ouvrirGraphe, !Self.grapheOuvert else { return }
                Self.grapheOuvert = true
                openWindow(id: "graphe")
                NSApp.activate()
            }
    }

    /// Le maillage, le seul symbole (celui du systeme), sans badge (demande de Djoko du 15/10). Image modele, sauf en
    /// alerte : orange.
    static func image(alerte: Bool) -> NSImage {
        let symbole = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                              accessibilityDescription: nil) ?? NSImage()
        let couleur: NSColor = alerte ? .systemOrange : .black
        let image = symbole.withSymbolConfiguration(.init(paletteColors: [couleur])) ?? symbole
        image.accessibilityDescription = "Maillage IoT"
        image.isTemplate = !alerte
        return image
    }
}

/// Contenu de la barre des menus : etat d'un coup d'oeil, 3 derniers
/// evenements, et les actions.
struct MenuBarre: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(NomsPasseur.self) private var nomsMaison
    @Environment(SondeMaillageThread.self) private var sonde
    @Environment(SondeMaillageZigbee.self) private var sondeZigbee
    @Environment(NomsPont.self) private var pont
    @Environment(\.openWindow) private var openWindow
    @Environment(ControleurReglages.self) private var reglages
    @Environment(MisesAJour.self) private var misesAJour
    /// Fenetre du menu, pour le fermer apres « Ouvrir le graphe », « Journal… » et « Reglages… ».
    @State private var fenetreMenu = RefFenetre()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            Divider()
            ForEach(surveillance.lignesJournal.prefix(3)) { l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(TexteEvenement.titre(l)).font(.callout).lineLimit(2)
                    Text(l.evenements.first.map(TexteEvenement.quand) ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            // Actions : comme les articles d'un menu natif (texte en couleur primaire, taille standard,
            // surlignees au survol) ; la marge negative aligne leur texte sur le reste du menu.
            VStack(alignment: .leading, spacing: 0) {
                Button("Ouvrir le graphe") { ouvrir("graphe") }
                Button("Journal…") { ouvrir("journal") }
                if surveillance.mode == .direct {
                    // Grise pendant une relecture : le demon y repond, sinon la garde la libere apres 2 minutes.
                    Button("Rafraîchir depuis Maison") { nomsMaison.relire() }
                        .disabled(nomsMaison.releveEnCours)
                    if let p = nomsMaison.probleme {
                        Text(p).font(.caption).foregroundStyle(.red).padding(.horizontal, 8)
                    }
                }
                if MisesAJour.moteurPresent {
                    Button("Rechercher les mises à jour…") { rechercherMisesAJour() }
                        .disabled(!misesAJour.peutRechercher)
                }
                Button("Réglages…") { ouvrirReglages() }
                Button("Quitter Maillage IoT") { NSApp.terminate(nil) }
            }
            .buttonStyle(ActionMenu())
            .padding(.horizontal, -8)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(FenetreHote { fenetreMenu.fenetre = $0 })
    }

    /// Un bloc par protocole actif, l'un sous l'autre (Thread, puis Zigbee) ; un protocole eteint n'a rien. Aucun protocole
    /// actif : une ligne le dit.
    @ViewBuilder
    private var entete: some View {
        let blocs = Self.blocs(surveillance)
        if blocs.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
                Text(Self.titreSansProtocole).font(.headline)
            }
        }
        ForEach(blocs) { b in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: b.etat.symbole).foregroundStyle(b.etat.couleur)
                    Text(verbatim: b.titre).font(.headline)
                }
                if b.protocole == .thread && surveillance.thread.etatEcoute == .reseauLocalRefuse {
                    Label("Accès au réseau local refusé", systemImage: "network.slash")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                ForEach(b.lignes, id: \.self) { l in
                    Text(verbatim: l).font(.caption).foregroundStyle(.secondary)
                }
                lignesSonde(b.protocole)
            }
        }
    }

    /// Ce que la sonde (et le pont) du protocole disent sous son resume : le mode demo, ou l'etat de la sonde.
    @ViewBuilder
    private func lignesSonde(_ protocole: Protocole) -> some View {
        switch protocole {
        case .thread:
            if surveillance.mode == .demo {
                Text("Mode démo : panne du 27/09 rejouée").font(.caption).foregroundStyle(.secondary)
            } else if let t = Self.ligneSonde(sonde.etat, nom: sonde.nomEtat, derniere: sonde.derniereTournee,
                                              avancement: sonde.avancement, maintenant: Date()) {
                Text(verbatim: t).font(.caption).foregroundStyle(.secondary)
            }
        case .zigbee:
            if surveillance.mode == .demo {
                Text("Mode démo : faux réseau Hue").font(.caption).foregroundStyle(.secondary)
            } else {
                if let t = Self.ligneSondeZigbee(sondeZigbee.etat, nom: sondeZigbee.nomEtat, derniere: sondeZigbee.derniereTournee,
                                                 avancement: sondeZigbee.avancement, maintenant: Date(),
                                                 passe: sondeZigbee.passeComplementaire, differee: sondeZigbee.tourneeDifferee) {
                    Text(verbatim: t).font(.caption).foregroundStyle(.secondary)
                }
                if let t = Self.lignePont(pont.etat, lie: pont.lie) {
                    Text(verbatim: t).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// L'etat d'un protocole dans le menu : son icone et sa couleur.
    enum EtatBloc: Equatable {
        /// Rien a montrer encore (Thread n'a pas ecoute le reseau local, Zigbee attend le maillage de la sonde).
        case attente
        /// Thread : le Mac n'entend plus rien depuis un moment, le resume montre le dernier etat connu.
        case muet
        case alerte
        case normal

        var symbole: String {
            switch self {
            case .attente: "ellipsis.circle"
            case .muet: "wifi.slash"
            case .alerte: "exclamationmark.triangle.fill"
            case .normal: "checkmark.circle.fill"
            }
        }

        var couleur: Color {
            switch self {
            case .attente, .muet: .secondary
            case .alerte: .orange
            case .normal: .green
            }
        }
    }

    /// Ce que le menu dit d'un protocole actif : l'etat de son reseau (titre, icone) et ses chiffres.
    struct BlocMenu: Equatable, Identifiable {
        var protocole: Protocole
        var titre: String
        var etat: EtatBloc
        /// Le resume du reseau, une ligne par information (Thread : son nom et ses partitions, puis les chiffres) ; vide sans
        /// reseau a resumer. La ligne de la sonde (et du pont) vient en dessous, de la vue.
        var lignes: [String]

        var id: Protocole { protocole }
    }

    /// Un bloc par protocole actif, Thread d'abord ; aucun pour un protocole eteint (en demo, seul le protocole rejoue en a un).
    /// L'alerte de chaque bloc est celle de son protocole. Le `switch` n'a pas de defaut : un troisieme protocole ne compile
    /// pas sans son bloc.
    static func blocs(_ s: Surveillance) -> [BlocMenu] {
        s.modelesMontres.map { m in
            switch m.protocole {
            case .thread: blocThread(s)
            case .zigbee: blocZigbee(s)
            }
        }
    }

    private static func blocThread(_ s: Surveillance) -> BlocMenu {
        let t = s.thread
        let alerte = s.alerte(de: .thread)
        var lignes: [String] = []
        if let r = t.resume {
            lignes = [String(localized: "\(r.nom) · partitions : \(r.partitions)"),
                      String(localized: "Routeurs : \(r.routeurs) · appareils : \(r.appareils) · injoignables : \(r.injoignables)")]
        }
        // Un reseau scinde est une alerte (`alerteReseau`) : `alerte` le dit deja.
        let etat: EtatBloc
        if t.instantane == nil {
            etat = .attente
        } else if t.rienVuDepuis != nil {
            etat = .muet
        } else {
            etat = alerte ? .alerte : .normal
        }
        return BlocMenu(protocole: .thread, titre: titreThread(t, alerte: alerte), etat: etat, lignes: lignes)
    }

    private static func blocZigbee(_ s: Surveillance) -> BlocMenu {
        let z = s.zigbee
        let alerte = s.alerte(de: .zigbee)
        let r = z.resume
        let lignes = r.map { [String(localized: "Routeurs : \($0.routeurs) · appareils : \($0.appareils) · injoignables : \($0.injoignables)")] } ?? []
        return BlocMenu(protocole: .zigbee, titre: titreZigbee(resume: r, alerte: alerte),
                        etat: r == nil ? .attente : alerte ? .alerte : .normal, lignes: lignes)
    }

    /// Le menu quand aucun protocole n'est actif.
    static var titreSansProtocole: String { String(localized: "Aucun protocole actif") }

    /// Titre d'un bloc en alerte dans l'heure : il nomme son protocole, car deux blocs s'empilent dans le menu.
    static func titreAlerte(_ protocole: Protocole) -> String {
        switch protocole {
        case .thread: String(localized: "Alerte Thread dans l'heure")
        case .zigbee: String(localized: "Alerte Zigbee dans l'heure")
        }
    }

    /// Titre du bloc de Thread : l'ecoute du reseau local tant qu'il n'a rien releve, le silence du Mac, puis l'etat du
    /// reseau (l'alerte de l'heure nomme son protocole : deux blocs s'empilent). `alerte` : celle de Thread.
    static func titreThread(_ t: SurveillanceThread, alerte: Bool) -> String {
        if t.instantane == nil { return String(localized: "Écoute du réseau local…") }
        if let d = t.rienVuDepuis { return String(localized: "Rien de visible sur le réseau local depuis \(TexteEvenement.heure(d))") }
        guard let r = t.reseau else { return String(localized: "Aucun réseau Thread visible") }
        if r.estScinde { return String(localized: "Réseau scindé") }
        return alerte ? titreAlerte(.thread) : String(localized: "Réseau Thread normal")
    }

    /// Titre du bloc de Zigbee : en attente tant qu'il n'y a rien a montrer, sinon l'alerte de l'heure, ou le reseau normal.
    /// `alerte` : celle de Zigbee.
    static func titreZigbee(resume: ResumeReseauZigbee?, alerte: Bool) -> String {
        guard resume != nil else { return String(localized: "En attente du maillage de la sonde…") }
        return alerte ? titreAlerte(.zigbee) : String(localized: "Réseau Zigbee normal")
    }

    /// Ligne de la sonde, sous le nom donne (celui de la sonde retenue quand l'etat la concerne,
    /// `SondeMaillageThread.nomEtat`), sinon « Sonde » ; pendant une tournee, son etape et son
    /// compteur. Rien tant qu'aucune sonde n'est choisie.
    static func ligneSonde(_ e: SondeMaillageThread.Etat, nom: String?, derniere: Date?, avancement: AvancementTournee?,
                           maintenant: Date) -> String? {
        let n = SondeMaillageThread.nomAffiche(nom)
        switch e {
        case .sansSonde: return nil
        case .absente: return String(localized: "\(n) : absente")
        case .connexion: return String(localized: "\(n) : connexion…")
        case .connectee:
            if let avancement { return TexteTourneeThread.menu(avancement, nom: n) }
            guard let d = derniere else { return String(localized: "\(n) : connectée") }
            return String(localized: "\(n) : connectée · relevé \(FicheNoeud.relatif(d, maintenant))")
        case .refusee, .erreur: return String(localized: "\(n) : erreur (voir les Réglages)")
        }
    }

    /// Ligne de la sonde de Zigbee, sous le nom donne (celui de la sonde retenue quand l'etat la concerne,
    /// `SondeMaillageZigbee.nomEtat`), sinon « Sonde » ; pendant une tournee, son etape et son compteur, hors tournee la
    /// passe complementaire programmee (`passe`) ou la tournee differee faute de budget (`differee`). Rien tant qu'aucune
    /// sonde n'est choisie.
    static func ligneSondeZigbee(_ e: SondeMaillageZigbee.Etat, nom: String?, derniere: Date?,
                                 avancement: AvancementTourneeZigbee?, maintenant: Date, passe: Date? = nil,
                                 differee: SondeMaillageZigbee.TourneeDifferee? = nil) -> String? {
        let n = SondeMaillageZigbee.nomAffiche(nom)
        switch e {
        case .sansSonde: return nil
        case .absente: return String(localized: "\(n) : absente")
        case .injoignable: return String(localized: "\(n) : injoignable")
        case .connexion: return String(localized: "\(n) : connexion…")
        case .connectee:
            if let avancement { return TexteTourneeZigbee.menu(avancement, nom: n) }
            if let passe { return TexteTourneeZigbee.menuPasse(passe, nom: n) }
            if let differee { return TexteTourneeZigbee.menuDifferee(differee, nom: n) }
            guard let d = derniere else { return String(localized: "\(n) : connectée") }
            return String(localized: "\(n) : connectée · relevé \(FicheNoeud.relatif(d, maintenant))")
        case .refusee, .erreur: return String(localized: "\(n) : erreur (voir les Réglages)")
        }
    }

    /// Ligne du pont Hue, quand il n'est pas lie et lu : introuvable, non lie, ou en erreur.
    static func lignePont(_ e: NomsPont.Etat, lie: Bool) -> String? {
        switch e {
        case .lie: nil
        case .introuvable: String(localized: "Pont Hue introuvable")
        case .erreur where lie: String(localized: "Pont Hue : erreur (voir les Réglages)")
        case .trouve, .aLier, .liaisonEnCours, .erreur: String(localized: "Pont Hue non lié")
        }
    }

    private func ouvrir(_ id: String) {
        Self.ouvrir(id, par: { openWindow(id: $0); NSApp.activate() }, menu: fenetreMenu.fenetre)
    }

    /// Ouvre la fenetre `id` de l'app (« graphe », « journal ») par `ouvrirFenetre`, puis ferme le menu `menu`, comme
    /// apres « Reglages… » : la fenetre ouverte ne prend pas toujours la main (l'app inactive, l'activation est
    /// cooperative), et le menu restait ouvert (vu par Djoko le 02/10, apres « Ouvrir le graphe »).
    static func ouvrir(_ id: String, par ouvrirFenetre: (String) -> Void, menu: NSWindow?) {
        ouvrirFenetre(id)
        menu?.close()
    }

    /// Le menu se ferme quand une autre fenetre de l'app prend la main. La fenetre des reglages ne
    /// la prend pas toujours : l'app inactive, le menu la garde (vu par Djoko le 30/09, le menu
    /// restait ouvert). On ferme donc le menu nous-memes, apres avoir montre les reglages.
    private func ouvrirReglages() {
        reglages.montrer()
        fenetreMenu.fenetre?.close()
    }

    /// La fenetre de Sparkle prend la place du menu, comme celle des reglages.
    private func rechercherMisesAJour() {
        misesAJour.rechercher()
        fenetreMenu.fenetre?.close()
    }
}

/// Fenetre du menu de la barre, retenue sans la garder en vie.
@MainActor
final class RefFenetre {
    weak var fenetre: NSWindow?
}

/// Donne la fenetre qui porte la vue, des qu'elle y est posee.
private struct FenetreHote: NSViewRepresentable {
    let surFenetre: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Vue { Vue(surFenetre: surFenetre) }
    func updateNSView(_ nsView: Vue, context: Context) {}

    final class Vue: NSView {
        let surFenetre: (NSWindow?) -> Void

        init(surFenetre: @escaping (NSWindow?) -> Void) {
            self.surFenetre = surFenetre
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            surFenetre(window)
        }
    }
}

/// Action du menu de la barre, a la maniere d'un article de menu natif : texte en couleur
/// primaire et en taille standard, sur toute la largeur, surligne a la couleur d'accent au survol.
private struct ActionMenu: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LigneAction(configuration: configuration)
    }

    private struct LigneAction: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var active
        @State private var survol = false

        var body: some View {
            let surligne = survol && active
            configuration.label
                .font(.body)
                .foregroundStyle(surligne ? AnyShapeStyle(Color.white) : AnyShapeStyle(active ? .primary : .secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(surligne ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onHover { survol = $0 }
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}
