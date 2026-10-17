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

    /// Tant que les modules sont arretes (reprise en cours, echec, relance qui n'a pas abouti), la croix ne ferme pas la fenetre :
    /// l'app ne tourne jamais sans ses modules, en silence. Apres un echec, elle relance l'app ; si la relance n'aboutit pas, la
    /// fenetre reste, avec le resume et « Quitter Maillage IoT ».
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard assistant.fermetureRefusee else { return true }
        Task { await assistant.relancerApresEchec() }
        NSSound.beep()
        return false
    }

    /// Fermer la fenetre : sur le resume, c'est le lire ; sur la confirmation, la preparation est lachee.
    func windowWillClose(_ notification: Notification) {
        Task { await assistant.fenetreFermee() }
    }
}

extension EnvironmentValues {
    /// L'assistant de reprise (nil : pas d'assistant, les tests des vues) ; Reglages > General l'ouvre.
    @Entry var controleurReprise: ControleurReprise?
}
