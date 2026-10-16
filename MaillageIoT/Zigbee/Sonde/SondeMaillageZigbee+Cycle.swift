import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role Cycle de vie : demarrage et arret reel de la sonde (Activer ce protocole).
extension SondeMaillageZigbee {
    /// Suit les ports ; reprend la sonde retenue des qu'elle est branchee. Apres `arreter()`, repart : l'ecoute des ports et
    /// l'ecoute Bonjour reprennent, et la sonde retenue (et elle seule : jamais un port inconnu) est rouverte si elle est
    /// branchee, ou rejointe par le reseau si elle y est annoncee.
    func demarrer() {
        guard vivante else { return }
        actif = true
        guard surveillantPorts == nil else { return }
        let p = surveillerPorts()
        p.changement = { [weak self] l in self?.portsChanges(l) }
        p.demarrer()
        surveillantPorts = p
        portsChanges(listerPorts())
        let n = fabriqueBonjour(TransportTCP.typeBonjour)
        n.surChangement = { [weak self, weak n] in
            guard let self, let n else { return }
            self.bonjourNonDeclare = n.etat == .nonDeclare
            self.annoncesChangees(Set(n.instances.keys))
        }
        n.demarrer()
        navigateur = n
    }

    /// Arret reel (Zigbee eteint) : le suivi des ports et l'ecoute Bonjour s'arretent, la liaison (le port serie ou la
    /// session reseau) se ferme, la tournee et la boucle des tournees, la relecture d'`etat` (entretien), les reprises de la
    /// liaison reseau et le nouvel essai USB planifie sont annules. Plus rien ne se connecte (`portsChanges`, `choisir`,
    /// `reevaluer` et `connecterReseau` gardent `actif`) tant que `demarrer()` n'a pas repris. La sonde retenue, son nom et
    /// sa cle restent. Sans effet sur une sonde inerte (demo, tests).
    func arreter() {
        guard vivante, actif else { return }
        actif = false
        surveillantPorts?.arreter()
        surveillantPorts = nil
        navigateur?.surChangement = nil
        navigateur?.arreter()
        navigateur = nil
        bonjourNonDeclare = false
        annoncee = false
        instanceAnnoncee = nil
        nouvelEssai?.cancel()
        nouvelEssai = nil
        rangNouvelEssai = 0
        tourneeRetenue = false
        // Ferme la liaison, annule la boucle, l'entretien et la reprise du reseau (`deconnecter`).
        deconnecter(serie == nil ? .sansSonde : .absente)
    }

    /// Des taches de fond sont encore planifiees ou en cours : la boucle des tournees, l'entretien, les reprises de la
    /// liaison reseau, le nouvel essai USB (lu par les tests de l'arret).
    var tachesPlanifiees: Int {
        [boucle, entretien, reessaiReseau, nouvelEssai].filter { $0 != nil && $0?.isCancelled == false }.count
    }
}
