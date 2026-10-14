import AppKit
import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// Icone de la barre des menus : le maillage et, en bas a droite, le symbole de Thread ; orange quand il y a une
/// alerte. Ouvre le graphe au lancement quand on le lui demande (mode demo, premier lancement).
struct IconeBarre: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.openWindow) private var openWindow
    let ouvrirGraphe: Bool
    private static var grapheOuvert = false

    var body: some View {
        Image(nsImage: Self.image(alerte: surveillance.alerte))
            .task {
                guard ouvrirGraphe, !Self.grapheOuvert else { return }
                Self.grapheOuvert = true
                openWindow(id: "graphe")
                NSApp.activate()
            }
    }

    /// Le maillage (symbole du systeme), et le symbole de Thread en badge dans son coin vide, en bas a droite : 11 pt
    /// pour un maillage de 15 pt de haut, le canevas agrandi d'un quart du badge vers le bas et de pres de la moitie de
    /// sa largeur vers la droite, sa silhouette detouree de 1,5 pt (essais du 08/10, choix de Djoko). Image modele,
    /// sauf en alerte : orange.
    static func image(alerte: Bool) -> NSImage {
        let symbole = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                              accessibilityDescription: nil) ?? NSImage()
        let couleur: NSColor = alerte ? .systemOrange : .black
        let base = symbole.withSymbolConfiguration(.init(paletteColors: [couleur])) ?? symbole
        let b = base.size
        let badge = CGSize(width: 11 * b.height / 15 * MarqueThread.proportion, height: 11 * b.height / 15)
        let taille = NSSize(width: b.width + badge.width * 0.45, height: b.height + badge.height * 0.25)
        let image = NSImage(size: taille, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: NSRect(x: 0, y: taille.height - b.height, width: b.width, height: b.height))
            MarqueThread.dessiner(ctx, dans: CGRect(x: taille.width - badge.width, y: 0, width: badge.width,
                                                    height: badge.height),
                                  couleur: couleur, detourage: 1.5)
            return true
        }
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
    @Environment(\.openWindow) private var openWindow
    @Environment(ControleurReglages.self) private var reglages
    @Environment(MisesAJour.self) private var misesAJour
    /// Fenetre du menu, pour le fermer apres « Ouvrir le graphe », « Journal… » et « Reglages… ».
    @State private var fenetreMenu = RefFenetre()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            if surveillance.thread.etatEcoute == .reseauLocalRefuse {
                Label("Accès au réseau local refusé", systemImage: "network.slash")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Divider()
            ForEach(surveillance.lignesJournal.prefix(3)) { l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(TexteEvenementThread.titre(l)).font(.callout).lineLimit(2)
                    Text(l.evenements.first.map(TexteEvenementThread.quand) ?? "").font(.caption).foregroundStyle(.secondary)
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
                Button("Rechercher les mises à jour…") { rechercherMisesAJour() }
                    .disabled(!misesAJour.peutRechercher)
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

    @ViewBuilder
    private var entete: some View {
        let alerte = surveillance.alerte
        HStack(spacing: 8) {
            if muet != nil {
                Image(systemName: "wifi.slash").foregroundStyle(.secondary)
            } else {
                Image(systemName: alerte ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(alerte ? .orange : .green)
            }
            Text(titre).font(.headline)
        }
        if let r = surveillance.thread.resume {
            Text("\(r.nom) · partitions : \(r.partitions)").font(.caption).foregroundStyle(.secondary)
            Text("Routeurs : \(r.routeurs) · appareils : \(r.appareils) · injoignables : \(r.injoignables)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if surveillance.mode == .demo {
            Text("Mode démo : panne du 27/09 rejouée").font(.caption).foregroundStyle(.secondary)
        } else if let t = Self.ligneSonde(sonde.etat, nom: sonde.nomEtat, derniere: sonde.derniereTournee,
                                          avancement: sonde.avancement, maintenant: Date()) {
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
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

    /// Le Mac n'entend plus rien depuis cette date ; le resume montre le dernier etat connu.
    private var muet: Date? {
        surveillance.thread.instantane == nil ? nil : surveillance.thread.rienVuDepuis
    }

    private var titre: String {
        if surveillance.thread.instantane == nil { return String(localized: "Écoute du réseau local…") }
        if let d = muet { return String(localized: "Rien de visible sur le réseau local depuis \(TexteEvenementThread.heure(d))") }
        guard let r = surveillance.thread.reseau else { return String(localized: "Aucun réseau Thread visible") }
        if r.estScinde { return String(localized: "Réseau scindé") }
        return surveillance.alerte ? String(localized: "Alerte dans l'heure") : String(localized: "Réseau Thread normal")
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
