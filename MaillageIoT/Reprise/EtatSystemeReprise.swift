import Foundation
import MaillageCoeur
import Security
import ServiceManagement
import UserNotifications

// Phase 4, tache 7 : la liste « A refaire » du resume de la reprise (spec 4.4), lue sur l'etat REEL du Mac au moment du resume,
// jamais sur ce que l'import croit avoir fait. Rien n'est affiche qui soit deja en ordre.
//
// Trois sources :
// - les cles du trousseau : pour chaque cle de l'ancienne app, est-elle dans le service de l'app (reprise), demandee sans succes
//   (refus, absente, acces refuse par le bac a sable : a refaire), ou pas encore demandee (elle l'est a la premiere connexion) ?
//   L'inventaire ne lit que les ATTRIBUTS des elements (jamais une cle, aucune fenetre de macOS) ; la memoire des reprises
//   (`MemoireReprises`) dit lesquelles ont ete tentees ;
// - les autorisations et l'ouverture de session de macOS : notifications (`UNUserNotificationCenter`), ouverture a la connexion
//   (`SMAppService.mainApp.status`), reseau local (seul son refus, observe par Bonjour, est connu : rien ne le lit avant).

// MARK: Cles du trousseau

/// Ou en est la reprise d'une cle de l'ancienne app.
enum EtatCleReprise: Equatable, Sendable {
    /// L'ancienne app n'a jamais eu cette cle : rien a reprendre, rien a refaire.
    case aucune
    /// Toutes les cles de l'ancienne app sont dans le service de l'app.
    case reprise
    /// Au moins une cle n'est pas encore dans le service de l'app et n'a pas ete demandee : macOS demandera l'accord de
    /// l'utilisateur a la premiere connexion.
    case aReprendre
    /// Au moins une cle a ete demandee a l'ancien service sans qu'elle arrive dans celui de l'app (refus, cle absente, acces
    /// refuse par le bac a sable) : a refaire.
    case nonAboutie

    /// L'etat deduit des comptes de trois inventaires : le service de l'app, celui de l'ancienne app, et les comptes dont la
    /// reprise a deja ete tentee.
    static func deduire(nouvelles: Set<String>, anciennes: Set<String>, tentees: Set<String>) -> EtatCleReprise {
        guard !anciennes.isEmpty else { return .aucune }
        let restantes = anciennes.subtracting(nouvelles)
        if restantes.isEmpty { return .reprise }
        return restantes.isSubset(of: tentees) ? .nonAboutie : .aReprendre
    }
}

/// Les comptes (attributs seulement) d'un service du trousseau. Une couture : les tests donnent un inventaire a la main.
protocol InventaireTrousseau: Sendable {
    func comptes(service: String) -> Set<String>
}

/// L'inventaire du trousseau du Mac : une requete d'attributs, comme `TrousseauSystemeThread.lister` (jamais la valeur d'une
/// cle, donc aucune fenetre de macOS ni tentative consommee). Les elements de l'ancienne app y apparaissent aussi.
struct InventaireTrousseauSysteme: InventaireTrousseau {
    func comptes(service: String) -> Set<String> {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let elements = r as? [[String: Any]] else { return [] }
        return Set(elements.compactMap { $0[kSecAttrAccount as String] as? String })
    }
}

// MARK: Autorisations de macOS

/// L'autorisation des notifications de l'app.
enum StatutNotifications: Equatable, Sendable {
    case autorisees
    /// macOS n'a pas encore demande (ou la demande n'a pas eu de reponse).
    case nonDemandees
    case refusees

    init(_ statut: UNAuthorizationStatus) {
        switch statut {
        case .authorized, .provisional: self = .autorisees
        case .notDetermined: self = .nonDemandees
        case .denied: self = .refusees
        @unknown default: self = .nonDemandees
        }
    }
}

/// L'ouverture de session (« Ouvrir a la connexion »).
enum StatutOuverture: Equatable, Sendable {
    case active
    /// Inscrite, mais l'utilisateur doit l'approuver dans Reglages Systeme.
    case aApprouver
    case inactive

    init(_ statut: SMAppService.Status) {
        switch statut {
        case .enabled: self = .active
        case .requiresApproval: self = .aApprouver
        case .notRegistered, .notFound: self = .inactive
        @unknown default: self = .inactive
        }
    }
}

// MARK: L'etat et la liste

/// Tout ce que la liste « A refaire » lit.
struct EtatSystemeReprise: Equatable, Sendable {
    var sondeThread: EtatCleReprise = .aucune
    var sondeZigbee: EtatCleReprise = .aucune
    var pontHue: EtatCleReprise = .aucune
    var notifications: StatutNotifications = .autorisees
    var ouverture: StatutOuverture = .active
    /// Bonjour a vu le reseau local refuse (le seul signal que macOS donne).
    var reseauLocalRefuse = false
}

/// Une cle du trousseau dont la reprise se lit.
enum CleReprise: Hashable, Sendable {
    case sondeThread, sondeZigbee, pontHue
}

/// Une chose que l'utilisateur doit encore faire apres la reprise.
enum TacheARefaire: Hashable, Sendable {
    /// La cle sera demandee a l'ancienne app a la premiere connexion : macOS demandera l'accord.
    case reprendreCle(CleReprise)
    /// La cle de l'ancienne app n'a pas pu etre reprise : brancher la sonde en USB (nouvelle cle ; l'ancienne est remplacee).
    case miseEnServiceSonde(ContratExport.AppSource)
    /// La cle du pont Hue n'a pas pu etre reprise : appairer le pont (appui sur son bouton).
    case relierPontHue
    case accepterNotifications
    case autoriserNotifications
    case activerOuverture
    case approuverOuverture
    case autoriserReseauLocal

    func titre(locale: Locale) -> String {
        switch self {
        case .reprendreCle(.sondeThread): traduire("Autoriser la reprise de la clé de la sonde Thread", locale)
        case .reprendreCle(.sondeZigbee): traduire("Autoriser la reprise de la clé de la sonde Zigbee", locale)
        case .reprendreCle(.pontHue): traduire("Autoriser la reprise de la clé du pont Hue", locale)
        case .miseEnServiceSonde(let app):
            traduire("Brancher la sonde \(Self.protocole(app)) en USB pour sa mise en service réseau", locale)
        case .relierPontHue: traduire("Appairer le pont Hue", locale)
        case .accepterNotifications: traduire("Accepter les notifications", locale)
        case .autoriserNotifications: traduire("Autoriser les notifications", locale)
        case .activerOuverture: traduire("Ouvrir à la connexion", locale)
        case .approuverOuverture: traduire("Approuver l'ouverture à la connexion", locale)
        case .autoriserReseauLocal: traduire("Autoriser le réseau local", locale)
        }
    }

    func detail(locale: Locale) -> String {
        switch self {
        case .reprendreCle:
            traduire("macOS demandera l'accord à la première connexion. La clé est alors recopiée dans Maillage IoT ; l'ancienne app garde la sienne et son accès.", locale)
        case .miseEnServiceSonde:
            traduire("La clé de l'ancienne app n'a pas pu être reprise. Une nouvelle clé sera écrite dans la sonde et dans le trousseau de Maillage IoT : l'ancienne clé est remplacée, et l'ancienne app verra la sonde injoignable.", locale)
        case .relierPontHue:
            traduire("La clé de l'ancienne app n'a pas pu être reprise. Appuyer sur le bouton du pont, puis le lier dans Réglages › Zigbee.", locale)
        case .accepterNotifications:
            traduire("macOS n'a pas encore reçu de réponse : accepter la demande d'autorisation de Maillage IoT.", locale)
        case .autoriserNotifications:
            traduire("Les notifications sont refusées : les autoriser dans Réglages Système › Notifications › Maillage IoT.", locale)
        case .activerOuverture:
            traduire("Maillage IoT ne s'ouvre pas à la connexion : allumer l'interrupteur dans Réglages › Général.", locale)
        case .approuverOuverture:
            traduire("Maillage IoT attend d'être approuvé : l'accepter dans Réglages Système › Général › Ouverture.", locale)
        case .autoriserReseauLocal:
            traduire("macOS a refusé le réseau local à Maillage IoT : l'autoriser dans Réglages Système › Confidentialité et sécurité › Réseau local.", locale)
        }
    }

    private static func protocole(_ app: ContratExport.AppSource) -> String {
        switch app {
        case .maillageThread: "Thread"
        case .maillageZigbee: "Zigbee"
        }
    }
}

enum ListeARefaire {
    /// Ce qui reste a faire apres la reprise d'un export de `app`, d'apres l'etat reel : les cles de ses protocoles, puis les
    /// notifications, le reseau local, l'ouverture de session. Vide quand tout est en ordre.
    static func pour(_ app: ContratExport.AppSource, etat: EtatSystemeReprise) -> [TacheARefaire] {
        var taches: [TacheARefaire] = []
        switch app {
        case .maillageThread:
            taches += cle(etat.sondeThread, reprendre: .sondeThread, refaire: .miseEnServiceSonde(.maillageThread))
        case .maillageZigbee:
            taches += cle(etat.pontHue, reprendre: .pontHue, refaire: .relierPontHue)
            taches += cle(etat.sondeZigbee, reprendre: .sondeZigbee, refaire: .miseEnServiceSonde(.maillageZigbee))
        }
        switch etat.notifications {
        case .autorisees: break
        case .nonDemandees: taches.append(.accepterNotifications)
        case .refusees: taches.append(.autoriserNotifications)
        }
        if etat.reseauLocalRefuse { taches.append(.autoriserReseauLocal) }
        switch etat.ouverture {
        case .active: break
        case .aApprouver: taches.append(.approuverOuverture)
        case .inactive: taches.append(.activerOuverture)
        }
        return taches
    }

    private static func cle(_ etat: EtatCleReprise, reprendre: CleReprise, refaire: TacheARefaire) -> [TacheARefaire] {
        switch etat {
        case .aucune, .reprise: []
        case .aReprendre: [.reprendreCle(reprendre)]
        case .nonAboutie: [refaire]
        }
    }
}

// MARK: Lecture de l'etat

/// Lit l'etat reel du Mac, au moment du resume.
protocol LecteurEtatSysteme: Sendable {
    func lire() async -> EtatSystemeReprise
}

/// Le lecteur de l'app : trousseau (attributs), memoire des reprises (preferences), autorisation des notifications,
/// ouverture de session, refus du reseau local. Les trois dernieres sont des closures : l'app donne les vraies, les tests les leurs.
struct LecteurEtatSystemeReel: LecteurEtatSysteme {
    let inventaire: any InventaireTrousseau
    /// La suite de preferences qui garde la memoire des reprises (nil : les preferences de l'app). Le nom, pas l'objet :
    /// `UserDefaults` n'est pas `Sendable`.
    let suite: String?
    let notifications: @Sendable () async -> StatutNotifications
    let ouverture: @Sendable () -> StatutOuverture
    let reseauLocalRefuse: @Sendable () async -> Bool

    init(inventaire: any InventaireTrousseau = InventaireTrousseauSysteme(), suite: String? = nil,
         notifications: @escaping @Sendable () async -> StatutNotifications = Self.notificationsDuSysteme,
         ouverture: @escaping @Sendable () -> StatutOuverture = { StatutOuverture(SMAppService.mainApp.status) },
         reseauLocalRefuse: @escaping @Sendable () async -> Bool) {
        self.inventaire = inventaire
        self.suite = suite
        self.notifications = notifications
        self.ouverture = ouverture
        self.reseauLocalRefuse = reseauLocalRefuse
    }

    @Sendable static func notificationsDuSysteme() async -> StatutNotifications {
        StatutNotifications(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func lire() async -> EtatSystemeReprise {
        let preferences = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        func etat(nouveau: String, ancien: String, memoire: String) -> EtatCleReprise {
            .deduire(nouvelles: inventaire.comptes(service: nouveau), anciennes: inventaire.comptes(service: ancien),
                     tentees: Set(preferences.stringArray(forKey: memoire) ?? []))
        }
        return EtatSystemeReprise(
            sondeThread: etat(nouveau: TrousseauSystemeThread.serviceParDefaut, ancien: TrousseauReprisThread.serviceAncien,
                              memoire: MemoireReprises.cleSondeThread),
            sondeZigbee: etat(nouveau: CheminSonde.serviceTrousseau, ancien: TrousseauRepris.serviceSondeAncien,
                              memoire: MemoireReprises.cleSondeZigbee),
            pontHue: etat(nouveau: TrousseauSystemeZigbee.servicePontParDefaut, ancien: TrousseauRepris.servicePontAncien,
                          memoire: MemoireReprises.clePontZigbee),
            notifications: await notifications(), ouverture: ouverture(), reseauLocalRefuse: await reseauLocalRefuse())
    }
}

/// Le texte dans la langue demandee (le catalogue de l'app a le francais et l'anglais).
private func traduire(_ ressource: LocalizedStringResource, _ locale: Locale) -> String {
    var r = ressource
    r.locale = locale
    return String(localized: r)
}
