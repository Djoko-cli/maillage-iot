import Foundation
import Security
import Synchronization

/// Sonde dont ce Mac a la cle : son nom d'hote SRP (16 hexa, sans `.local`) et l'empreinte de
/// sa cle.
struct SondeConnue: Hashable, Sendable, Identifiable {
    let nom: String
    let empreinte: String
    var id: String { nom }
    var hote: String { "\(nom).local" }
}

/// Cles de l'acces reseau a la sonde, reprises du trousseau du pont Halo (benq,
/// `HaloCompagnon/Reseau/Trousseau.swift`). La cle ne quitte le trousseau que pour ouvrir une
/// session : jamais dans un journal, une preference ni un fichier.
protocol TrousseauCles: Sendable {
    func lister() -> [SondeConnue]
    func lire(nom: String) throws -> Data
    func ranger(nom: String, cle: Data, empreinte: String) throws
    func oublier(nom: String) throws
}

enum ErreurTrousseau: Error, Equatable, Sendable, LocalizedError {
    case absente(String)
    case systeme(Int32)

    var errorDescription: String? {
        switch self {
        case .absente(let nom):
            String(localized: "Clé absente de ce Mac pour \(nom).local : brancher la sonde en USB, puis « Autoriser l'accès réseau ».")
        case .systeme(let s):
            String(localized: "Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))")
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service `fr.djoko.maillage.sonde`,
/// compte = nom d'hote SRP (sans `.local`), valeur = 64 hexa MAJUSCULES, commentaire =
/// empreinte. Non synchronise.
struct TrousseauSysteme: TrousseauCles {
    let service: String

    init(service: String = "fr.djoko.maillage.sonde") {
        self.service = service
    }

    private func requete(_ nom: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let nom { q[kSecAttrAccount as String] = nom }
        return q
    }

    func lister() -> [SondeConnue] {
        var q = requete()
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let elements = r as? [[String: Any]]
        else { return [] }
        return elements.compactMap { a in
            guard let nom = a[kSecAttrAccount as String] as? String else { return nil }
            return SondeConnue(nom: nom, empreinte: a[kSecAttrComment as String] as? String ?? "?")
        }.sorted { $0.nom < $1.nom }
    }

    func lire(nom: String) throws -> Data {
        var q = requete(nom)
        q[kSecReturnData as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw ErreurTrousseau.absente(nom) }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
        guard let d = r as? Data, let cle = H1.octets(hexa: String(decoding: d, as: UTF8.self)), cle.count == 32
        else { throw ErreurTrousseau.systeme(errSecDecode) }
        return cle
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        let valeurs: [String: Any] = [kSecValueData as String: Data(H1.hexa(cle).utf8),
                                      kSecAttrComment as String: empreinte,
                                      kSecAttrLabel as String: "Maillage Thread - sonde \(nom)"]
        var s = SecItemUpdate(requete(nom) as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete(nom).merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
    }

    func oublier(nom: String) throws {
        let s = SecItemDelete(requete(nom) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw ErreurTrousseau.systeme(s) }
    }
}

/// Trousseau en memoire : celui des tests, et celui de `SondeMaillage` tant qu'on ne lui en
/// donne pas d'autre (seul le lancement de l'app lui passe celui du Mac).
final class TrousseauMemoire: TrousseauCles {
    private let cles = Mutex<[String: (cle: Data, empreinte: String)]>([:])

    func lister() -> [SondeConnue] {
        cles.withLock { $0.map { SondeConnue(nom: $0.key, empreinte: $0.value.empreinte) } }.sorted { $0.nom < $1.nom }
    }

    func lire(nom: String) throws -> Data {
        guard let e = cles.withLock({ $0[nom] }) else { throw ErreurTrousseau.absente(nom) }
        return e.cle
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        cles.withLock { $0[nom] = (cle, empreinte) }
    }

    func oublier(nom: String) throws {
        _ = cles.withLock { $0.removeValue(forKey: nom) }
    }
}
