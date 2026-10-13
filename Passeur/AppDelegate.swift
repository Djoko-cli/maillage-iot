import UIKit

/// Passeur Noms, demon de Maison (spec du 12/10) : app Mac Catalyst sans fenetre ni Dock, lancee par une URL des apps
/// (`maillage-passeur://releve` ou `abonner`) ou a l'ouverture de session. Le coeur est `DemonPasseur` ; ici, ce qui
/// touche au systeme : le Masqueur, HomeKit, SMAppService, le reseau, la sortie.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Le module AppKit qui masque les fenetres, garde en vie.
    private var masqueur: NSObject?
    private var demon: DemonPasseur?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        chargerMasqueur()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let d = DemonPasseur(
            source: MaisonHomeKit(), ouverture: OuvertureSMAppService(), horloge: HorlogeReelle(), version: version,
            profilExpire: ProfilPasseur.expiration(paquet: Bundle.main.bundleURL),
            connecter: { ConnexionApp(cible: $0) },
            livrerPonctuel: { LivraisonPonctuelle.livrer($0, json: $1, fini: $2) },
            quitter: { raison in
                journal.notice("fin : \(raison, privacy: .public)")
                exit(0)
            })
        demon = d
        d.demarrer()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Defaut", sessionRole: session.role)
    }

    /// URL recues par une scene (`SceneDelegate`, qui reste connectee : sa fenetre est invisible).
    func recevoir(_ urls: [URL]) {
        guard let demon else { return }
        for url in urls {
            Task { await demon.recevoir(url: url) }
        }
    }

    /// Avant que UIKit connecte la scene : toute fenetre de l'app nait invisible (spec, section 3.1).
    private func chargerMasqueur() {
        guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Masqueur.bundle"),
              let module = Bundle(url: url), module.load(),
              let classe = module.principalClass as? NSObject.Type else {
            journal.error("Masqueur.bundle introuvable : la fenêtre imposée par UIKit restera visible")
            return
        }
        masqueur = classe.init()
    }
}
