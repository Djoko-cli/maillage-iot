import Foundation
import Network
import dnssd

/// Echec de l'acces reseau a la sonde, avec son texte et sa reprise ; repris du pont Halo
/// (benq, `HaloProtocole/Reseau/ErreurReseau.swift`), textes propres a la sonde.
enum ErreurReseau: Error, Sendable, Equatable, LocalizedError {
    /// Autorisation "reseau local" refusee (Reglages Systeme) : macOS refuse la resolution du
    /// nom `.local` de la sonde.
    case reseauLocalRefuse
    /// Pas de route IPv6 vers le reseau Thread (prefixe OMR) : macOS ne l'installe pas toujours,
    /// ou la perd en changeant de routeur de bordure ; le README (« Route vers le reseau Thread »)
    /// explique quoi faire.
    case pasDeRoute
    /// `<nom>.local` introuvable, ou le noeud ne repond pas (`EHOSTDOWN`).
    case nomIntrouvable(String)
    /// ICMPv6 "port injoignable" : port 5480 ferme (la sonde 1.0.2 sans cle reste muette).
    case portInjoignable
    /// Aucun DEFI juste apres les essais du SALUT : sonde eteinte, ou autre cle.
    case aucunDefi
    /// Connexion perdue apres son ouverture : son texte est la raison de fermeture du flux, la
    /// cause ensuite (`TransportUDP.raisonPerte`).
    case cheminPerdu(String)
    case autre(String)

    /// Vrai : la reconnexion reessaie seule ; faux : il faut l'USB (nouvelle cle).
    var repriseAutomatique: Bool {
        if case .portInjoignable = self { return false }
        return true
    }

    var errorDescription: String? {
        switch self {
        case .reseauLocalRefuse:
            String(localized: "Accès au réseau local refusé : Réglages Système › Confidentialité et sécurité › Réseau local › Maillage Thread.")
        case .pasDeRoute:
            String(localized: "Pas de route IPv6 vers le réseau Thread : ce Mac n'a pas de route vers le préfixe OMR, où est l'adresse de la sonde. Voir « Route vers le réseau Thread » dans README.fr.md.")
        case .nomIntrouvable(let hote):
            String(localized: "Sonde introuvable (\(hote)) : éteinte, hors du réseau Thread, ou routeurs de bordure injoignables.")
        case .portInjoignable:
            String(localized: "La sonde refuse l'accès réseau : la brancher en USB, puis « Régénérer une clé ».")
        case .aucunDefi:
            String(localized: "La sonde ne répond pas : éteinte, pas encore dans le réseau Thread, ou clé différente de celle de ce Mac (la brancher en USB, puis « Régénérer une clé »).")
        case .cheminPerdu(let raison):
            String(localized: "Connexion réseau perdue : \(raison)")
        case .autre(let raison):
            String(localized: "Erreur réseau : \(raison)")
        }
    }

    /// Erreur de Network.framework ; `chemin` : dernier chemin connu de la connexion.
    static func depuis(_ e: NWError, chemin: NWPath?, hote: String) -> ErreurReseau {
        if chemin?.unsatisfiedReason == .localNetworkDenied { return .reseauLocalRefuse }
        switch e {
        case .posix(let code):
            switch code {
            case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN: return .pasDeRoute
            // ICMPv6 "adresse injoignable" : la route existe, c'est le noeud
            // qui ne repond pas (eteint, hors du reseau Thread).
            case .EHOSTDOWN: return .nomIntrouvable(hote)
            case .ECONNREFUSED: return .portInjoignable
            default: return .autre(String(describing: code))
            }
        case .dns(let code):
            // Reseau local refuse : `PolicyDenied` selon la documentation ;
            // macOS repond en fait `NoSuchRecord`, aussitot, a la resolution
            // d'un nom `.local` (banc R7 de Halo). Un nom `.local` absent, lui,
            // reste sans reponse : l'attente de `attentePret` le classe introuvable.
            switch Int(code) {
            case kDNSServiceErr_PolicyDenied: return .reseauLocalRefuse
            case kDNSServiceErr_NoSuchRecord where estLocal(hote): return .reseauLocalRefuse
            default: return .nomIntrouvable(hote)
            }
        default:
            return .autre(String(describing: e))
        }
    }

    /// Nom mDNS (`.local`, avec ou sans point final).
    static func estLocal(_ hote: String) -> Bool {
        let h = hote.lowercased()
        return h.hasSuffix(".local") || h.hasSuffix(".local.")
    }
}
