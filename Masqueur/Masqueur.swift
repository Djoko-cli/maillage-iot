import AppKit
import ObjectiveC

/// Module AppKit charge par le demon Catalyst (`AppDelegate.chargerMasqueur`), avant que UIKit connecte la scene que
/// macOS 27 impose : toute fenetre de l'app nait transparente et inerte (initialiseurs de NSWindow echanges), avant
/// tout affichage ; politique d'activation `.accessory` ; par securite, toute fenetre qui deviendrait cle, principale,
/// mise a jour ou exposee est retiree de l'ecran. Valide au cinquieme essai du 12/10 : ni fenetre ni eclair. Repose
/// sur le comportement d'UIKit pour Mac : a reverifier a chaque version majeure de macOS.
@objc(Masqueur)
final class Masqueur: NSObject {
    @MainActor private static var installe = false
    @MainActor private static var observateurs: [any NSObjectProtocol] = []

    /// Appele par l'app, sur le fil principal.
    override init() {
        super.init()
        MainActor.assumeIsolated { Masqueur.installer() }
    }

    @MainActor
    private static func installer() {
        guard !installe else { return }
        installe = true
        intercepter()
        NSApplication.shared.setActivationPolicy(.accessory)
        for nom in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                    NSWindow.didUpdateNotification, NSWindow.didExposeNotification] {
            observateurs.append(NotificationCenter.default.addObserver(forName: nom, object: nil, queue: .main) { note in
                // Seule la fenetre (Sendable) passe a la section isolee, pas la notification.
                let fenetre = note.object as? NSWindow
                MainActor.assumeIsolated {
                    if let w = fenetre {
                        Masqueur.rendreInvisible(w)
                        w.orderOut(nil)
                    }
                }
            })
        }
        for w in NSApplication.shared.windows {
            rendreInvisible(w)
            w.orderOut(nil)
        }
    }

    @MainActor
    static func rendreInvisible(_ w: NSWindow) {
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior.insert([.transient, .ignoresCycle])
    }

    /// Echange les deux initialiseurs de NSWindow contre des versions qui rendent la fenetre invisible des sa creation.
    @MainActor
    private static func intercepter() {
        let paires: [(Selector, Selector)] = [
            (#selector(NSWindow.init(contentRect:styleMask:backing:defer:)),
             #selector(NSWindow.masquer_init(contentRect:styleMask:backing:defer:))),
            (#selector(NSWindow.init(contentRect:styleMask:backing:defer:screen:)),
             #selector(NSWindow.masquer_init(contentRect:styleMask:backing:defer:screen:))),
        ]
        for (original, remplacant) in paires {
            if let a = class_getInstanceMethod(NSWindow.self, original),
               let b = class_getInstanceMethod(NSWindow.self, remplacant) {
                method_exchangeImplementations(a, b)
            }
        }
    }
}

extension NSWindow {
    /// Apres l'echange, cet appel atteint l'initialiseur d'origine.
    @objc func masquer_init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType,
                            defer flag: Bool) -> NSWindow {
        let w = masquer_init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        Masqueur.rendreInvisible(w)
        return w
    }

    @objc func masquer_init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType,
                            defer flag: Bool, screen: NSScreen?) -> NSWindow {
        let w = masquer_init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag, screen: screen)
        Masqueur.rendreInvisible(w)
        return w
    }
}
