import Foundation
import MaillageCoeur
import ProtocoleThread

// Sonde Thread, role Cycle de vie : demarrage et arret reel de la sonde (Activer ce protocole).
extension SondeMaillageThread {
    /// Suit les ports ; reprend la sonde retenue des qu'elle est branchee. Apres `arreter()`, repart : la sonde retenue
    /// (et elle seule : jamais un port inconnu) est rouverte si elle est branchee, ou rejointe par le reseau.
    func demarrer() {
        guard vivante else { return }
        actif = true
        guard surveillantPorts == nil else { return }
        let p = surveillerPorts()
        p.changement = { [weak self] l in self?.portsChanges(l) }
        p.demarrer()
        surveillantPorts = p
        portsChanges(listerPorts())
        // Reseau Thread choisi : la session part sans attendre l'annonce (comme avant). En Automatique, `portsChanges` a deja
        // choisi le chemin.
        if reglage == .reseau { lancerConnexionReseau() }
    }

    /// Arret reel (Thread eteint) : le suivi des ports s'arrete, la liaison (le port serie ou la session reseau) se ferme,
    /// la tournee, la boucle des tournees, les reprises de la liaison reseau et le nouvel essai planifie sont annules, et
    /// l'activite de la session reseau est rendue. Plus rien ne se connecte (`portsChanges`, `choisir`, `choisirLiaison`,
    /// `annoncesChangees`, `reevaluer` et `connecterReseau` gardent `actif`) tant que `demarrer()` n'a pas repris ; le retour a
    /// l'USB attendu est annule, et l'annonce oubliee (l'instantane de Thread repart de zero, la sonde ne le sait pas avant son
    /// premier releve) ; en Automatique le chemin est a refaire (`portsConnus`). La sonde retenue, son nom, sa cle et son
    /// reglage restent. Sans effet sur une sonde inerte (demo, tests).
    func arreter() {
        guard vivante, actif else { return }
        actif = false
        surveillantPorts?.arreter()
        surveillantPorts = nil
        reprise?.cancel()
        reprise = nil
        nouvelEssai?.cancel()
        nouvelEssai = nil
        annulerRetourUSB()
        essaisReprise = 0
        annonces = []
        portsConnus = false
        if reglage == .automatique { liaison = .usb }
        deconnecter(serie == nil ? .sansSonde : .absente)
    }

    /// Des taches de fond sont encore planifiees ou en cours : la boucle des tournees, une reprise de la liaison reseau, un
    /// nouvel essai de connexion, un retour a l'USB attendu (lu par les tests de l'arret).
    var tachesPlanifiees: Int {
        [boucle, reprise, nouvelEssai, retourUSB].filter { $0 != nil && $0?.isCancelled == false }.count
    }
}
