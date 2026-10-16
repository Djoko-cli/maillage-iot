import AppKit
import SwiftUI

/// Fenetre Reglages, faite en AppKit comme les reglages classiques de macOS (demande de Djoko,
/// 30/09, sur le modele de Screens Connect) :
/// - les onglets sont dans la barre d'outils ;
/// - le titre de la fenetre est celui de l'onglet ;
/// - la hauteur s'ajuste d'un onglet a l'autre.
///
/// Les onglets sont ceux de `NSTabViewController` en style barre d'outils. La hauteur, elle, est
/// animee ici (`OngletsReglages.ajuster`) : le redimensionnement natif, par `preferredContentSize`,
/// saute d'une hauteur a l'autre (essai et retour de Djoko, 30/09). La scene `Settings` de SwiftUI,
/// que cette fenetre remplace, faisait scintiller la barre des onglets a chaque changement.
@MainActor
@Observable
final class ControleurReglages {
    @ObservationIgnored private let surveillance: Surveillance
    @ObservationIgnored private let ouverture: OuvertureSession
    /// Le seul client du demon Passeur Noms : sa page Maison sert les deux protocoles.
    @ObservationIgnored private let nomsMaison: NomsPasseur
    /// Le client du pont Hue (page Zigbee).
    @ObservationIgnored private let nomsPont: NomsPont
    /// La sonde de Thread (page Thread) et celle de Zigbee (page Zigbee).
    @ObservationIgnored private let sonde: SondeMaillageThread
    @ObservationIgnored private let sondeZigbee: SondeMaillageZigbee
    @ObservationIgnored private let misesAJour: MisesAJour
    /// Les preferences qui gardent l'onglet retenu (celles de l'app ; en memoire dans les tests).
    @ObservationIgnored private let preferences: UserDefaults
    /// Creee a la premiere ouverture, puis gardee : elle rouvre sur le meme onglet.
    @ObservationIgnored private var fenetre: NSWindow?
    /// L'etat de Thread Route, cree avec la fenetre : il vit aussi longtemps qu'elle et ecoute le retour de l'app
    /// au premier plan, que la fenetre soit ouverte ou non (`SuiviThreadRoute`).
    @ObservationIgnored private var suiviThreadRoute: SuiviThreadRoute?

    init(surveillance: Surveillance, ouverture: OuvertureSession, nomsMaison: NomsPasseur, nomsPont: NomsPont,
         sonde: SondeMaillageThread, sondeZigbee: SondeMaillageZigbee, misesAJour: MisesAJour,
         preferences: UserDefaults = .standard) {
        self.surveillance = surveillance
        self.ouverture = ouverture
        self.nomsMaison = nomsMaison
        self.nomsPont = nomsPont
        self.sonde = sonde
        self.sondeZigbee = sondeZigbee
        self.misesAJour = misesAJour
        self.preferences = preferences
    }

    /// Montre la fenetre au premier plan. Elle devient la fenetre active : le menu de la barre
    /// se ferme, comme apres le graphe ou le journal.
    func montrer() {
        let f = fenetre ?? creerFenetre()
        fenetre = f
        f.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Thread Route installe ou approuve pendant que la fenetre etait fermee, sur l'onglet Thread retenu.
        suiviThreadRoute?.relireSiAffiche()
    }

    func creerFenetre() -> NSWindow {
        let onglets = OngletsReglages()
        onglets.preferences = preferences
        onglets.tabStyle = .toolbar
        let suivi = SuiviThreadRoute(affiche: { [weak onglets] in onglets?.ongletCourant == .thread })
        suiviThreadRoute = suivi
        for o in OngletReglages.allCases {
            // Contenu change (sonde branchee, erreur affichee…) : la fenetre suit, si la page est visible.
            let page = FenetreReglages(onglet: o, surHauteur: { [weak onglets] _ in onglets?.contenuChange(de: o) })
                .environment(surveillance)
                .environment(ouverture)
                .environment(nomsMaison)
                .environment(nomsPont)
                .environment(sonde)
                .environment(sondeZigbee)
                .environment(suivi)
                .environment(misesAJour)
            // Sans `sizingOptions` : la page n'annonce pas de taille preferee, sinon le redimensionnement
            // natif, sans animation, prendrait le pas sur `ajuster`.
            let hote = NSHostingController(rootView: page)
            hote.title = o.titre
            let item = NSTabViewItem(viewController: hote)
            item.label = o.titre
            item.image = o.image
            item.identifier = o.rawValue
            onglets.addTabViewItem(item)
        }
        let garde = preferences.string(forKey: OngletReglages.cle).flatMap(OngletReglages.init(rawValue:))
        onglets.selectedTabViewItemIndex = OngletReglages.allCases.firstIndex(of: garde ?? .general) ?? 0
        let f = NSWindow(contentViewController: onglets)
        f.styleMask = [.titled, .closable, .miniaturizable]
        f.toolbarStyle = .preference
        f.isReleasedWhenClosed = false
        onglets.ajuster(animer: false)
        f.center()
        return f
    }
}

/// Onglets des Reglages : garde le dernier onglet ouvert (`OngletReglages.cle`), et donne a la
/// fenetre la taille de la page choisie, en l'animant, bord du haut fixe, comme les reglages
/// classiques de macOS.
final class OngletsReglages: NSTabViewController {
    /// Les preferences qui gardent l'onglet retenu (`ControleurReglages` donne les siennes).
    var preferences: UserDefaults = .standard

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            preferences.set(id, forKey: OngletReglages.cle)
        }
        ajuster(animer: fenetreVue)
    }

    /// Vrai si la fenetre est vue pour de bon : visible, et pas cachee ni couverte (`occlusionState`). Une fenetre qui
    /// n'est pas vue (ecran eteint ou verrouille, session sans affichage) n'avance aucune animation, `animator().setFrame`
    /// n'y pose jamais la taille : elle y est posee d'un coup, personne ne la voit changer.
    private var fenetreVue: Bool {
        guard let fenetre = view.window else { return false }
        return fenetre.isVisible && fenetre.occlusionState.contains(.visible)
    }

    /// L'onglet choisi, ou nil si le choix n'en est pas un.
    var ongletCourant: OngletReglages? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(OngletReglages.init(rawValue:))
    }

    /// La page de cet onglet a change de hauteur : la fenetre suit, si c'est la page visible. Le changement est annonce
    /// pendant la mise en page de SwiftUI, quand `fittingSize` rend (0, 0) ou une taille d'avant (mesure du 12/10 : un
    /// aller-retour Wi-Fi / Automatique laissait la fenetre a sa hauteur d'avant, sans autre appel pour la corriger) :
    /// la taille est donc lue au tour suivant de la boucle, une fois la mise en page finie.
    func contenuChange(de onglet: OngletReglages) {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex),
              tabViewItems[selectedTabViewItemIndex].identifier as? String == onglet.rawValue else { return }
        planifierAjustement(essais: Self.essaisAjustement)
    }

    /// Nombre de relectures de la taille de la page, au tour suivant de la boucle, quand elle n'est pas encore connue.
    private static let essaisAjustement = 5
    private var ajustementPlanifie = false

    /// Un seul ajustement attend a la fois : les changements annonces d'ici la le partagent.
    private func planifierAjustement(essais: Int) {
        guard !ajustementPlanifie else { return }
        ajustementPlanifie = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            ajustementPlanifie = false
            let connue = ajuster(animer: fenetreVue)
            if !connue && essais > 1 { planifierAjustement(essais: essais - 1) }
        }
    }

    /// Donne a la fenetre la taille ideale de la page choisie (sa `fittingSize` : la page est
    /// collee en haut et peut s'etirer, mais sa taille ideale est celle de son contenu). Le bord
    /// du haut ne bouge pas ; l'animation prend la duree standard de macOS pour ce changement.
    /// Rend faux si la page n'a pas encore de taille (mise en page pas finie).
    @discardableResult
    func ajuster(animer: Bool) -> Bool {
        guard let fenetre = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              let page = tabViewItems[selectedTabViewItemIndex].viewController else { return true }
        let voulu = page.view.fittingSize
        let actuel = fenetre.contentLayoutRect.size
        guard voulu.height > 0, voulu.width > 0 else { return false }
        guard abs(voulu.height - actuel.height) > 0.5 || abs(voulu.width - actuel.width) > 0.5 else { return true }
        var cadre = fenetre.frame
        cadre.origin.y -= voulu.height - actuel.height
        cadre.size.height += voulu.height - actuel.height
        cadre.size.width += voulu.width - actuel.width
        if animer {
            NSAnimationContext.runAnimationGroup { contexte in
                contexte.duration = fenetre.animationResizeTime(cadre)
                fenetre.animator().setFrame(cadre, display: true)
            }
        } else {
            fenetre.setFrame(cadre, display: true)
        }
        return true
    }
}
