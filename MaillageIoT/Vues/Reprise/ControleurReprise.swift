import AppKit
import SwiftUI

/// La fenetre de l'assistant de reprise, une fenetre AppKit comme les Reglages (`ControleurReglages`) : creee a la premiere
/// ouverture, gardee ensuite, ouverte par l'entree « Reprendre des donnees… » de Reglages > General, par la proposition du premier
/// lancement et par le resume qui suit une reprise.
@MainActor
final class ControleurReprise: NSObject, NSWindowDelegate {
    let assistant: AssistantReprise
    private var fenetre: NSWindow?

    init(assistant: AssistantReprise) {
        self.assistant = assistant
    }

    /// Montre la fenetre au premier plan.
    func montrer() {
        assistant.rouvrir()
        let f = fenetre ?? creerFenetre()
        fenetre = f
        f.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func fermer() { fenetre?.close() }

    func creerFenetre() -> NSWindow {
        let vue = FenetreReprise(assistant: assistant, fermer: { [weak self] in self?.fermer() })
        let f = NSWindow(contentViewController: NSHostingController(rootView: vue))
        f.title = String(localized: "Reprendre des données")
        f.styleMask = [.titled, .closable, .miniaturizable]
        f.isReleasedWhenClosed = false
        f.setContentSize(NSSize(width: FenetreReprise.largeur, height: FenetreReprise.hauteur))
        f.delegate = self
        f.center()
        return f
    }

    /// Fermer la fenetre d'un assistant dont les modules sont arretes (apres un echec) relance l'app ; sur le resume, c'est le
    /// lire.
    func windowWillClose(_ notification: Notification) {
        Task { await assistant.fenetreFermee() }
    }
}

extension EnvironmentValues {
    /// L'assistant de reprise (nil : pas d'assistant, les tests des vues) ; Reglages > General l'ouvre.
    @Entry var controleurReprise: ControleurReprise?
}
