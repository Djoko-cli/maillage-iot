import Foundation
import MaillageCoeur

/// Cle de l'acces reseau, creee par l'USB comme pour le pont Halo (contrat 1.0.2) : l'app
/// fournit un alea de 32 octets, la carte calcule `cle = HMAC-SHA256(alea de l'app, alea de la
/// carte)`, la garde et la rend une seule fois (`cle nouvelle <alea> <id>`).
enum CleReseau {
    /// Alea de l'app : 32 octets d'un generateur cryptographique.
    static func alea() -> Data { H1.aleatoire(32) }

    /// Cle verifiee, prete pour le trousseau ; `hote` : nom d'hote donne avec elle. La cle
    /// n'apparait dans aucune description ni dump.
    struct Creee: Sendable, Equatable {
        let cle: Data
        let empreinte: String
        let hote: String?
    }

    enum Erreur: Error, Sendable, Equatable, LocalizedError {
        case cleIllisible
        case empreinteIncoherente
        /// Nom d'hote SRP pas encore connu de la sonde : pas de compte pour la cle.
        case sansNomDHote

        var errorDescription: String? {
            switch self {
            case .cleIllisible:
                String(localized: "Réponse sans clé lisible (64 hexa majuscules attendus) : clé non rangée.")
            case .empreinteIncoherente:
                String(localized: "Empreinte incohérente avec la clé reçue : clé non rangée.")
            case .sansNomDHote:
                String(localized: "La sonde n'a pas encore de nom d'hôte (Matter ne l'a pas encore enregistré) : réessayer dans une minute.")
            }
        }
    }

    /// Reponse a `cle nouvelle` : la cle (64 hexa MAJUSCULES, 32 octets) et son empreinte
    /// (8 premiers hexa de SHA-256), verifiees avant tout rangement.
    static func verifier(_ r: ReponseCle) -> Result<Creee, Erreur> {
        guard let texte = r.cle, let cle = H1.octets(hexa: texte), cle.count == 32 else { return .failure(.cleIllisible) }
        guard let e = r.empreinte, e == H1.kid(cle: cle) else { return .failure(.empreinteIncoherente) }
        return .success(Creee(cle: cle, empreinte: e, hote: r.hote))
    }
}

extension CleReseau.Creee: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "cle(<masquee>, empreinte: \(empreinte), hote: \(hote ?? "nil"))" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["empreinte": empreinte, "hote": hote as Any], displayStyle: .struct)
    }
}
