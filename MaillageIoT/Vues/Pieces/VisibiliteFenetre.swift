import AppKit
import SwiftUI

/// Ce que Djoko voit de la fenetre de la vue par pieces (performance, constat du 25/10) : l'horloge du moteur ne tourne
/// que dans une fenetre vue (`MoteurPieces.horlogeEnMarche`). La `TimelineView` de SwiftUI, elle, calcule ses images dans
/// une fenetre fermee, reduite dans le Dock ou entierement cachee : avec la rotation lente, la vue en calculait sans fin,
/// environ 45 % d'un coeur. Lue sur la fenetre et sur le Mac par `SondeVisibilite`.
struct VisibiliteFenetre: Equatable, Sendable {
    /// La vue est dans une fenetre posee a l'ecran : ni fermee, ni retiree (`isVisible`).
    var ouverte = true
    /// La fenetre est reduite dans le Dock.
    var reduite = false
    /// La fenetre est entierement cachee, selon AppKit (`occlusionState` sans `.visible`) : sous d'autres fenetres, sur un
    /// autre bureau, l'ecran eteint ou verrouille.
    var cachee = false
    /// Les ecrans sont en veille (`NSWorkspace.screensDidSleepNotification`).
    var ecransEteints = false
    /// L'ecran est verrouille (`com.apple.screenIsLocked`).
    var verrouillee = false
    /// La session n'est plus a l'ecran : un autre utilisateur a la main (`NSWorkspace.sessionDidResignActiveNotification`).
    var sessionAilleurs = false

    /// La fenetre est vue : la vue peut calculer des images.
    var vue: Bool { ouverte && !reduite && !cachee && !ecransEteints && !verrouillee && !sessionAilleurs }

    /// L'horloge tourne : un mouvement en cours (`MoteurPieces.anime`), dans une fenetre vue.
    static func horloge(anime: Bool, visibilite: VisibiliteFenetre) -> Bool { anime && visibilite.vue }
}

extension VisibiliteFenetre {
    /// Celle de la fenetre `fenetre` (nil : la vue n'est dans aucune), le Mac etant dans l'etat `mac` (ecrans, verrou,
    /// session : ce que la fenetre ne dit pas).
    @MainActor
    init(fenetre: NSWindow?, mac: VisibiliteFenetre) {
        self = mac
        ouverte = fenetre?.isVisible ?? false
        reduite = fenetre?.isMiniaturized ?? false
        cachee = !(fenetre?.occlusionState.contains(.visible) ?? false)
    }
}

/// D'ou la sonde tire ce que Djoko voit. Dans l'app : la fenetre et le Mac (`reelle`, les centres de notifications
/// du systeme). Dans les tests (`FenetrePiecesTests.fenetre`) : une valeur fixe, « toujours vue » par defaut, pour que
/// la veille des ecrans ou le verrou du Mac ne change rien aux essais d'animation (AppKit juge cachee la fenetre hors
/// ecran des tests quand les ecrans dorment) ; les essais d'occlusion reelle donnent leurs propres centres, jamais
/// celui du processus (une fausse annonce de veille y atteindrait toutes les fenetres des suites voisines).
enum SourceVisibilite: Sendable {
    /// La vraie sonde. `espace` : le centre des annonces de `NSWorkspace` (ecrans, session) ; `verrou` : le centre des
    /// annonces du verrou (`com.apple.screenIsLocked`) ; nil : celui du systeme.
    case reelle(espace: NotificationCenter? = nil, verrou: NotificationCenter? = nil)
    /// Aucune sonde : la visibilite est toujours celle-ci.
    case fixe(VisibiliteFenetre)

    /// La fenetre est toujours vue, quoi que fasse le Mac.
    static let toujoursVue = SourceVisibilite.fixe(VisibiliteFenetre())
}

private struct CleSourceVisibilite: EnvironmentKey {
    static let defaultValue = SourceVisibilite.reelle()
}

extension EnvironmentValues {
    /// La source de visibilite de la vue par pieces : la vraie sonde, sauf dans les tests.
    var sourceVisibilite: SourceVisibilite {
        get { self[CleSourceVisibilite.self] }
        set { self[CleSourceVisibilite.self] = newValue }
    }
}

/// Rapporte ce que Djoko voit de la fenetre de la vue (`VisibiliteFenetre`), a chaque changement : la fenetre fermee,
/// reduite, rouverte, cachee ou de nouveau vue (`occlusionState`), les ecrans en veille ou rallumes, l'ecran verrouille ou
/// deverrouille, la session quittee ou reprise. Le rapport part hors de la mise a jour de la vue en cours.
struct SondeVisibilite: NSViewRepresentable {
    let rapporter: @MainActor (VisibiliteFenetre) -> Void
    var source = SourceVisibilite.reelle()

    func makeNSView(context: Context) -> Sonde { Sonde(rapporter, source: source) }
    func updateNSView(_ nsView: Sonde, context: Context) {}

    final class Sonde: NSView {
        let rapporter: @MainActor (VisibiliteFenetre) -> Void
        let source: SourceVisibilite
        /// Ce que la fenetre ne dit pas : les ecrans, le verrou, la session.
        private var mac = VisibiliteFenetre()
        private var derniere: VisibiliteFenetre?
        private var observateurs: [(NotificationCenter, NSObjectProtocol)] = []

        init(_ rapporter: @escaping @MainActor (VisibiliteFenetre) -> Void, source: SourceVisibilite = .reelle()) {
            self.rapporter = rapporter
            self.source = source
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for (centre, o) in observateurs { centre.removeObserver(o) }
            observateurs = []
            // Une source fixe n'ecoute rien : elle rapporte sa valeur, une fois.
            if case .reelle(let centreEspace, let centreVerrou) = source, let window {
                let fenetre = NotificationCenter.default
                for nom in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                            NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                    observer(fenetre, nom, objet: window) { _ in }
                }
                let espace = centreEspace ?? NSWorkspace.shared.notificationCenter
                observer(espace, NSWorkspace.screensDidSleepNotification) { $0.ecransEteints = true }
                observer(espace, NSWorkspace.screensDidWakeNotification) { $0.ecransEteints = false }
                observer(espace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionAilleurs = true }
                observer(espace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionAilleurs = false }
                let distribue = centreVerrou ?? DistributedNotificationCenter.default()
                observer(distribue, Notification.Name("com.apple.screenIsLocked")) { $0.verrouillee = true }
                observer(distribue, Notification.Name("com.apple.screenIsUnlocked")) { $0.verrouillee = false }
            }
            lire()
        }

        /// Ecoute `nom` sur `centre` : `changer` met a jour l'etat du Mac, puis la visibilite est relue.
        private func observer(_ centre: NotificationCenter, _ nom: Notification.Name, objet: AnyObject? = nil,
                              changer: @escaping @MainActor (inout VisibiliteFenetre) -> Void) {
            let o = centre.addObserver(forName: nom, object: objet, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    changer(&self.mac)
                    self.lire()
                }
            }
            observateurs.append((centre, o))
        }

        /// Relit la visibilite et la rapporte si elle a change, hors de la mise a jour de la vue en cours. Une fenetre qui
        /// se ferme (`willClose`) est encore visible a l'annonce : la lecture est refaite juste apres.
        private func lire() {
            rapporterSiChangee()
            Task { @MainActor [weak self] in self?.rapporterSiChangee() }
        }

        private func rapporterSiChangee() {
            let v: VisibiliteFenetre
            if case .fixe(let fixe) = source { v = fixe } else { v = VisibiliteFenetre(fenetre: window, mac: mac) }
            guard v != derniere else { return }
            derniere = v
            let rapporter = rapporter
            Task { @MainActor in rapporter(v) }
        }
    }
}
