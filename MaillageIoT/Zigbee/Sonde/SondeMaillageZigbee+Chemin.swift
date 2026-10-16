import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role Chemin : choix du chemin (Automatique, USB, Reseau), bascules apres un changement de ports, d'annonces
// ou de reglage.
extension SondeMaillageZigbee {
    /// Ports branches : la sonde retenue revient, ou s'en va.
    func portsChanges(_ liste: [PortUSB]) {
        portsVus = liste.filter(\.estEspressif)
        choixRefuse = nil
        guard actif, let serie else { return }
        if reglageChemin != .reseau, let p = ports.first(where: { $0.serie == serie }) {
            // `lancerConnexion` passe tout de suite a `.connexion` : un second appel n'en lance pas d'autre. Une
            // tentative par le reseau, elle, cede a l'USB (constat 6 de la relecture finale).
            if (sonde == nil || acces == .reseau) && (etat != .connexion || tentativeReseau) {
                lancerConnexion(p, choisi: false)
            }
        } else if acces != .reseau && !versUnAutrePort {
            if sonde != nil || etat != .absente { deconnecter(.absente) }
            reevaluer()
        }
    }

    /// Les instances `_maillage-zigbee._tcp` vues sur le reseau local (navigateur Bonjour ; les tests l'appellent).
    func annoncesChangees(_ noms: Set<String>) {
        guard actif else { return }
        instanceAnnoncee = nom.flatMap { CheminSonde.instance(de: $0, parmi: noms) }
        let vue = instanceAnnoncee != nil
        guard vue != annoncee || (vue && acces == nil && etat != .connexion) else { return }
        annoncee = vue
        reevaluer()
    }

    /// Applique le chemin choisi (spec sonde Wi-Fi, 4.2) apres un changement de ports, d'annonces ou de reglage.
    func reevaluer() {
        guard actif, serie != nil else { return }
        let port = ports.first { $0.serie == serie }
        switch CheminSonde.choisir(reglageChemin, branchee: port != nil, cleConnue: cleReseauConnue, annoncee: annoncee) {
        case .usb?:
            guard let port, acces != .usb, etat != .connexion else { return }
            lancerConnexion(port, choisi: false)
        case .reseau?:
            guard acces != .reseau, etat != .connexion else { return }
            deconnecter(.connexion)
            tentativeReseau = true
            serieEtat = serie
            let n = essai
            Task {
                guard n == essai else { return }
                await connecterReseau()
            }
        case nil:
            if (sonde != nil || etat == .connexion || etat == .injoignable) && !versUnAutrePort { deconnecter(.absente) }
        }
    }

    /// Une connexion, en cours ou etablie, vise un autre port que celui de la sonde retenue (un choix des Reglages) :
    /// l'absence de la sonde retenue ne l'annule pas.
    private var versUnAutrePort: Bool {
        (etat == .connexion || sonde != nil) && serieEtat != serie
    }
}
