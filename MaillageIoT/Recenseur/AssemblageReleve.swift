import Foundation
import MaillageCoeur

/// Parties pures du releve, sans entree-sortie : assemblage des annonces et
/// cibles gardees d'un releve a l'autre.
extension Recenseur {
    /// Instance listee par un navigateur, et son TXT brut (vide si le navigateur n'en a pas donne).
    struct InstanceListee: Equatable, Sendable {
        let type: String
        let instance: String
        let txt: Data
    }

    /// Cle d'une instance dans les cibles : "type|instance".
    nonisolated static func cle(_ type: String, _ instance: String) -> String {
        "\(type)|\(instance)"
    }

    /// Releve de ce que le Mac a recu. Une instance listee n'y entre qu'avec sa
    /// cible resolue (hote, port) : sans cible, elle attend le releve suivant (un
    /// service deja connu passe alors par le sursis de `MemoireAnnonces` au lieu
    /// d'etre publie sans hote). TXT : celui du navigateur, sinon celui de la
    /// cible. Services tries par instance.
    nonisolated static func assembler(vues: [InstanceListee], cibles: [String: ResolveurDNSSD.Cible],
                                      adresses: [String: [String]], routes: [RouteIPv6],
                                      prefixesLocaux: [String], date: Date) -> Annonces {
        func services(_ type: String) -> [AnnonceService] {
            vues.filter { $0.type == type }.compactMap { v in
                // TREL : seul le TXT (`xa`) sert ; celui du navigateur suffit, sans attendre la cible.
                if type == "_trel._udp", !v.txt.isEmpty, cibles[cle(type, v.instance)] == nil {
                    return AnnonceService(instance: v.instance, txt: ChampsTXT(brut: v.txt))
                }
                guard let cible = cibles[cle(type, v.instance)] else { return nil }
                let txt = v.txt.isEmpty ? cible.txt : v.txt
                return AnnonceService(instance: v.instance, hote: cible.hote, port: cible.port, txt: ChampsTXT(brut: txt))
            }.sorted { $0.instance < $1.instance }
        }
        return Annonces(date: date, routeurs: services("_meshcop._udp"), matter: services("_matter._tcp"),
                        hap: services("_hap._udp"), trel: services("_trel._udp"), adresses: adresses, routes: routes, prefixesLocaux: prefixesLocaux)
    }

    /// Cibles apres un releve : une resolution reussie remplace la cible de son
    /// instance, un echec garde la precedente ; une instance qui n'est plus
    /// listee perd la sienne.
    nonisolated static func retenir(cibles: [String: ResolveurDNSSD.Cible], resolues: [String: ResolveurDNSSD.Cible],
                                    listees: Set<String>) -> [String: ResolveurDNSSD.Cible] {
        cibles.merging(resolues) { _, nouvelle in nouvelle }.filter { listees.contains($0.key) }
    }
}
