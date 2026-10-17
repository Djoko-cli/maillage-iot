import Foundation
import MaillageCoeur
import UserNotifications
import os

/// Notifications du systeme (le mode Concentration s'applique de lui-meme).
/// Une categorie se coupe dans les reglages, protocole par protocole (Thread et Zigbee ont chacun leurs
/// interrupteurs) ; une notification de meme identifiant remplace la precedente (pertes groupees). Un refus ou un
/// echec du systeme est consigne dans le journal du Mac (Console, sous-systeme
/// fr.djoko.maillage.iot), jamais perdu en silence. Presentees aussi quand une
/// fenetre de l'app est au premier plan.
@MainActor
final class Notifications {
    nonisolated static let journal = Logger(subsystem: IdentiteApp.courante.identifiant, category: "notifications")
    /// Delegue du centre de notifications, retenu ici : le centre ne le garde qu'en reference faible.
    private let presentation = PresentationAuPremierPlan()

    /// Cle de l'interrupteur d'une categorie pour un protocole : `notification.<protocole>.<categorie>`.
    static func cle(_ c: CategorieAlerte, de protocole: Protocole) -> String {
        "notification.\(protocole.rawValue).\(c.rawValue)"
    }

    /// Cle commune de 3a (`notification.<categorie>`), d'avant les cles par protocole : relue une fois, pour reprendre sa valeur.
    static func cleCommune(_ c: CategorieAlerte) -> String { "notification.\(c.rawValue)" }

    /// Les categories qu'un protocole a dans les reglages : Thread les quatre, Zigbee sans la scission (son module ne
    /// l'emet jamais).
    static func categories(de protocole: Protocole) -> [CategorieAlerte] {
        switch protocole {
        case .thread: CategorieAlerte.allCases
        case .zigbee: CategorieAlerte.allCases.filter { $0 != .scission }
        }
    }

    /// Le libelle de l'interrupteur d'une categorie dans les reglages de ce protocole : Zigbee n'a pas de « bordure ».
    static func titre(_ c: CategorieAlerte, de protocole: Protocole) -> String {
        switch c {
        case .scission: String(localized: "Réseau scindé")
        case .routeurDisparu:
            protocole == .zigbee ? String(localized: "Routeur disparu") : String(localized: "Routeur de bordure disparu")
        case .pertes: String(localized: "Au moins 3 appareils perdus en 10 min (une notification groupée)")
        case .informations: String(localized: "Autres changements")
        }
    }

    /// Une categorie est-elle notifiee pour ce protocole : sa cle, sinon (premiere lecture) la cle commune de 3a, sinon le
    /// defaut. Une categorie coupee en 3a reste donc coupee pour les deux protocoles.
    static func active(_ c: CategorieAlerte, de protocole: Protocole, preferences: UserDefaults = .standard) -> Bool {
        preferences.object(forKey: cle(c, de: protocole)) as? Bool
            ?? preferences.object(forKey: cleCommune(c)) as? Bool
            ?? c.parDefaut
    }

    /// Reprend les cles communes de 3a sous les cles par protocole, une fois : une cle de protocole absente prend la valeur
    /// de la cle commune quand elle existe (rien n'est ecrit pour une categorie jamais touchee, elle garde son defaut). Les
    /// cles communes restent, et une cle deja la n'est jamais ecrasee : on peut rappeler sans risque. A appeler avant que
    /// les reglages lisent leurs interrupteurs (`@AppStorage` ne connait que la cle du protocole).
    static func reprendreClesCommunes(preferences: UserDefaults = .standard) {
        for protocole in Protocole.allCases {
            for c in categories(de: protocole) {
                let cle = cle(c, de: protocole)
                guard preferences.object(forKey: cle) == nil, let valeur = preferences.object(forKey: cleCommune(c)) as? Bool
                else { continue }
                preferences.set(valeur, forKey: cle)
            }
        }
    }

    /// Les alertes dont l'interrupteur, celui de leur protocole, est allume.
    static func aPresenter(_ alertes: [AlerteAEnvoyer], preferences: UserDefaults = .standard) -> [AlerteAEnvoyer] {
        alertes.filter { active($0.categorie, de: $0.protocole, preferences: preferences) }
    }

    func demanderAutorisation() {
        UNUserNotificationCenter.current().delegate = presentation
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { accordee, erreur in
            if let erreur {
                Self.journal.error("autorisation des notifications : \(erreur.localizedDescription, privacy: .public)")
            } else if !accordee {
                Self.journal.notice("notifications refusees : rien ne sera presente")
            }
        }
    }

    func presenter(_ alertes: [AlerteAEnvoyer]) {
        for a in Self.aPresenter(alertes) {
            let (titre, corps) = TexteEvenement.notification(a)
            let contenu = UNMutableNotificationContent()
            contenu.title = titre
            contenu.body = corps
            if a.categorie != .informations { contenu.sound = .default }
            let identifiant = a.identifiant
            let requete = UNNotificationRequest(identifier: identifiant, content: contenu, trigger: nil)
            UNUserNotificationCenter.current().add(requete) { erreur in
                if let erreur {
                    Self.journal.error("notification \(identifiant, privacy: .public) non presentee : \(erreur.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

/// Sans delegue, macOS tait les notifications tant qu'une fenetre de l'app a
/// le focus : celui-ci les presente toujours (banniere, son, centre de notifications).
@MainActor
final class PresentationAuPremierPlan: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
