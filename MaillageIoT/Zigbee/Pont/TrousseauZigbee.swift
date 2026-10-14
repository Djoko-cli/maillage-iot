import Foundation
import Security
import Synchronization

/// La cle d'application du pont Hue, donnee une fois par l'appui sur son bouton, rangee sous l'identifiant du pont.
/// Repris du trousseau de Maillage Thread. La cle ne quitte le trousseau que pour une requete au pont : jamais dans un
/// journal, une preference ni un fichier.
protocol TrousseauClesZigbee: Sendable {
    /// La cle du pont `identifiant` ; `ErreurTrousseauZigbee.absente` s'il n'y en a pas.
    func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String
    func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee)
    /// Sans erreur si la cle n'y est pas.
    func oublier(identifiant: String) throws(ErreurTrousseauZigbee)
}

enum ErreurTrousseauZigbee: Error, Equatable, Sendable, LocalizedError {
    case absente(String)
    case systeme(Int32)

    var errorDescription: String? {
        switch self {
        case .absente(let identifiant):
            String(localized: "Clé absente de ce Mac pour le pont \(identifiant) : liez le pont depuis les Réglages.")
        case .systeme(let s):
            String(localized: "Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))")
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service `fr.djoko.maillage.iot.pont-hue`, compte =
/// identifiant du pont, libelle « Maillage IoT - pont Hue <identifiant> », valeur = la cle en UTF-8. Accessible apres
/// le premier deverrouillage, sur ce Mac seulement, jamais synchronise par iCloud. (Dans le trousseau de session de
/// macOS, ou l'app range ses elements, l'accessibilite n'est pas appliquee : l'element suit le verrou du trousseau,
/// ouvert a la connexion ; elle est donnee pour le jour ou l'element irait au trousseau a protection des donnees.)
struct TrousseauSystemeZigbee: TrousseauClesZigbee {
    /// Libelle de l'element (colonne Nom de Trousseaux d'acces) et son commentaire, d'apres le compte et la cle.
    typealias Etiquette = @Sendable (_ identifiant: String, _ cle: String) -> (libelle: String, commentaire: String?)

    let service: String
    let etiquette: Etiquette

    init(service: String = "fr.djoko.maillage.iot.pont-hue",
         etiquette: @escaping Etiquette = { identifiant, _ in ("Maillage IoT - pont Hue \(identifiant)", nil) }) {
        self.service = service
        self.etiquette = etiquette
    }

    /// Ce qui est ecrit avec la cle : la valeur, le libelle, le commentaire s'il y en a un, l'accessibilite. Pur : les
    /// tests le lisent sans toucher au trousseau.
    func valeurs(identifiant: String, cle: String) -> [String: Any] {
        let e = etiquette(identifiant, cle)
        var v: [String: Any] = [kSecValueData as String: Data(cle.utf8),
                                kSecAttrLabel as String: e.libelle,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if let c = e.commentaire { v[kSecAttrComment as String] = c }
        return v
    }

    private func requete(_ identifiant: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: identifiant,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String {
        var q = requete(identifiant)
        q[kSecReturnData as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw .absente(identifiant) }
        guard s == errSecSuccess else { throw .systeme(s) }
        guard let d = r as? Data, let cle = String(data: d, encoding: .utf8), !cle.isEmpty else {
            throw .systeme(errSecDecode)
        }
        return cle
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee) {
        let valeurs = valeurs(identifiant: identifiant, cle: cle)
        var s = SecItemUpdate(requete(identifiant) as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete(identifiant).merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw .systeme(s) }
    }

    func oublier(identifiant: String) throws(ErreurTrousseauZigbee) {
        let s = SecItemDelete(requete(identifiant) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw .systeme(s) }
    }
}

/// Trousseau en memoire : celui des tests (aucun acces au vrai trousseau).
final class TrousseauMemoireZigbee: TrousseauClesZigbee {
    private let cles: Mutex<[String: String]>

    init(_ cles: [String: String] = [:]) {
        self.cles = Mutex(cles)
    }

    func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String {
        guard let c = cles.withLock({ $0[identifiant] }) else { throw .absente(identifiant) }
        return c
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee) {
        cles.withLock { $0[identifiant] = cle }
    }

    func oublier(identifiant: String) throws(ErreurTrousseauZigbee) {
        _ = cles.withLock { $0.removeValue(forKey: identifiant) }
    }

    /// Les identifiants qui ont une cle (tests).
    var identifiants: [String] { cles.withLock { $0.keys.sorted() } }
}

/// Les cles de Maillage Zigbee 1.1.1 reprises sans nouvel appairage (spec, 4.4) : la cle se lit d'abord dans le
/// trousseau de l'app ; absente, elle est demandee une seule fois a l'ancien service (macOS demande alors l'accord de
/// l'utilisateur, l'element appartenant a l'ancienne app), puis recopiee sous le service de l'app. L'ancien element
/// n'est jamais modifie ni efface : l'ancienne app continue de marcher. Un refus, une cle absente ou un oubli ne
/// redemandent plus rien (une tentative par identifiant, notee dans `reprises`).
struct TrousseauRepris: TrousseauClesZigbee {
    static let servicePontAncien = "fr.djoko.maillage.zigbee.pont"
    static let serviceSondeAncien = "fr.djoko.maillage.zigbee.sonde"

    let actuel: any TrousseauClesZigbee
    let ancien: any TrousseauClesZigbee
    let reprises: MemoireReprises

    func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String {
        do {
            return try actuel.lire(identifiant: identifiant)
        } catch {
            guard case .absente = error, !reprises.tentee(identifiant) else { throw error }
            reprises.noter(identifiant)
            guard let cle = try? ancien.lire(identifiant: identifiant) else { throw .absente(identifiant) }
            try? actuel.ranger(identifiant: identifiant, cle: cle)
            return cle
        }
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee) {
        try actuel.ranger(identifiant: identifiant, cle: cle)
    }

    /// N'efface que la cle de l'app, et ne reprend plus celle de l'ancienne app.
    func oublier(identifiant: String) throws(ErreurTrousseauZigbee) {
        reprises.noter(identifiant)
        try actuel.oublier(identifiant: identifiant)
    }
}

/// Les identifiants dont la reprise a deja ete tentee.
struct MemoireReprises: Sendable {
    let tentee: @Sendable (String) -> Bool
    let noter: @Sendable (String) -> Void

    /// Dans les preferences de l'app, sous `cle` (une liste d'identifiants).
    static func preferences(cle: String) -> MemoireReprises {
        MemoireReprises(tentee: { UserDefaults.standard.stringArray(forKey: cle)?.contains($0) == true },
                        noter: { id in
                            var ids = UserDefaults.standard.stringArray(forKey: cle) ?? []
                            if !ids.contains(id) { ids.append(id) }
                            UserDefaults.standard.set(ids, forKey: cle)
                        })
    }

    /// En memoire : celle des tests.
    static func memoire() -> MemoireReprises {
        let partage = Partage()
        return MemoireReprises(tentee: { id in partage.ids.withLock { $0.contains(id) } },
                               noter: { id in _ = partage.ids.withLock { $0.insert(id) } })
    }

    private final class Partage: Sendable {
        let ids = Mutex<Set<String>>([])
    }
}
