import UIKit

/// La scene que macOS 27 impose (une app UIKit sans scene s'arrete au lancement) : sans contenu, gardee connectee. Sa
/// fenetre est invisible des sa creation (Masqueur.bundle : alpha 0, sans souris, transitoire). La refermer des la
/// connexion perdait l'URL d'un lancement a froid : elle arrive en AppleEvent un instant apres, vers une scene deja
/// detruite. Elle porte aussi les URL des apps : a la connexion d'une scene neuve (`urlContexts`), ou a une scene
/// encore la (`openURLContexts`).
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        // Seulement des nombres : l'URL porte le jeton, elle n'entre jamais au journal.
        journal.notice("scène connectée : \(options.urlContexts.count) URL à la connexion")
        transmettre(options.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts contextes: Set<UIOpenURLContext>) {
        transmettre(contextes)
    }

    /// Rien de special : une URL ulterieure creera une scene neuve, qui recevra a son tour `urlContexts`.
    func sceneDidDisconnect(_ scene: UIScene) {}

    private func transmettre(_ contextes: Set<UIOpenURLContext>) {
        guard !contextes.isEmpty else { return }
        journal.notice("URL transmises au démon : \(contextes.count)")
        (UIApplication.shared.delegate as? AppDelegate)?.recevoir(contextes.map(\.url))
    }
}
