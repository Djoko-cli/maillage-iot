import Foundation
import MaillageCoeur
import ProtocoleThread

// Sonde Thread, role Chemin : reglage de liaison (Automatique, USB, Reseau Thread), choix du chemin, bascules et
// retour a l'USB differe.
extension SondeMaillageThread {
    /// Reglage de liaison choisi dans les Reglages, garde dans les preferences. « Reseau Thread » exige une cle de ce Mac pour la
    /// sonde retenue : la liaison USB est fermee (le port libere), la session reseau ouverte. « USB » ferme la session reseau et
    /// reprend la sonde retenue si elle est branchee (une liaison USB en place n'est pas rouverte). « Automatique » garde ce qui
    /// tient et change de chemin sans delai si l'autre est celui qu'il choisit (le choix est explicite : pas de stabilite a
    /// attendre).
    func choisirLiaison(_ r: ReglageLiaison) {
        guard actif, r != reglage, r != .reseau || reseauDisponible else { return }
        reglage = r
        preferences.set(r.rawValue, forKey: Self.cleLiaison)
        reprise?.cancel()
        reprise = nil
        annulerRetourUSB()
        essaisReprise = 0
        dernierePerte = nil
        switch r {
        case .reseau:
            // Une session reseau ouverte (Automatique) est gardee ; sinon elle part.
            guard liaison != .reseau || sonde == nil else { return }
            liaison = .reseau
            lancerConnexionReseau()
        case .usb:
            if liaison == .reseau {
                liaison = .usb
                deconnecter(serie == nil ? .sansSonde : .absente)
            }
            portsChanges(portsVus)
        case .automatique:
            reevaluer(immediat: true)
        }
    }

    /// Automatique : applique le chemin choisi (`CheminLiaison.choisir`) apres un changement de ports, d'annonce ou de reglage.
    /// Aucun effet pour USB et Reseau Thread, qui fixent le chemin (leurs regles sont celles de Thread 1.3.0). Ne touche pas
    /// une connexion que l'utilisateur a choisie vers un autre port (`versUnAutrePort`), ni rien avant que les cartes branchees
    /// soient connues (`portsConnus` : USB d'abord).
    /// - L'USB est le chemin et la sonde est sur le reseau : retour a l'USB, apres `delaiRetourUSB` de branchement continu si
    ///   une session reseau tient (`immediat` : sans delai), tout de suite sinon.
    /// - Le reseau est le chemin et la sonde est sur l'USB (ou nulle part) : le reseau.
    /// - Aucun chemin : une session reseau ouverte reste (elle prouve que la sonde est joignable, meme si Bonjour la perd de vue
    ///   un instant) ; les essais d'une session qui n'aboutit pas s'arretent.
    /// Idempotente : un chemin deja pris n'est pas relance (les annonces et evenements sans effet ne relancent rien).
    func reevaluer(immediat: Bool = false) {
        guard actif, reglage == .automatique, portsConnus, !versUnAutrePort else { return }
        let port = ports.first { $0.serie != nil && $0.serie == serie }
        let voulu = CheminLiaison.choisir(.automatique, branchee: port != nil, cleConnue: reseauDisponible,
                                          annoncee: annoncee)
        if voulu != .usb { annulerRetourUSB() }
        switch (voulu, liaison) {
        case (.usb?, .reseau):
            guard let port else { return }
            if sonde == nil || immediat {
                versUSB(port)
            } else {
                planifierRetourUSB()
            }
        case (.reseau?, .usb):
            versReseau()
        case (nil, .reseau):
            guard sonde == nil else { return }
            arreterReseau()
        default:
            break
        }
    }

    /// Automatique : de la session reseau (ou de ses reprises) vers l'USB, la carte retenue ouverte comme au demarrage (la
    /// session reseau se ferme, le port s'ouvre une fois).
    private func versUSB(_ port: PortUSB) {
        annulerRetourUSB()
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        dernierePerte = nil
        lancerConnexion(port, choisi: false)
    }

    /// Automatique : vers le reseau. Les echecs d'avant, sans connexion reussie depuis (`essaisReprise`), gardent l'espacement
    /// de la reprise : une annonce qui clignote ou une carte qui se debranche ne relancent pas une session a chaque fois.
    private func versReseau() {
        annulerRetourUSB()
        liaison = .reseau
        dernierePerte = nil
        reprise?.cancel()
        reprise = nil
        if essaisReprise == 0 {
            lancerConnexionReseau()
        } else {
            deconnecter(.connexion)
            serieEtat = serie
            planifierReprise()
        }
    }

    /// Automatique : plus de chemin (sonde plus annoncee, cle perdue) et aucune session ouverte : les essais s'arretent, la
    /// sonde est « absente ». `essaisReprise` reste, pour l'espacement du retour.
    private func arreterReseau() {
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        dernierePerte = nil
        deconnecter(serie == nil ? .sansSonde : .absente)
    }

    /// Retour a l'USB attendu : la carte doit rester branchee `delaiRetourUSB` ; `reevaluer` decide ensuite, d'apres l'etat de
    /// ce moment-la (une carte repartie dans l'intervalle annule le retour, `annulerRetourUSB`).
    private func planifierRetourUSB() {
        guard retourUSB == nil else { return }
        let delai = delaiRetourUSB
        retourUSB = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self else { return }
            self.retourUSB = nil
            self.reevaluer(immediat: true)
        }
    }

    func annulerRetourUSB() {
        retourUSB?.cancel()
        retourUSB = nil
    }

    /// Les hotes que Bonjour montre avec une adresse (l'instantane de Thread, a chaque releve). La sonde est « annoncee » quand
    /// son hote en fait partie. Seul un changement de cette annonce fait choisir le chemin de nouveau : un releve sans effet
    /// ne relance rien. Rien eteint.
    func annoncesChangees(_ hotes: Set<String>) {
        guard actif else { return }
        let avant = annoncee
        let nouvelles = Set(hotes.map { $0.uppercased() })
        if nouvelles != annonces { annonces = nouvelles }
        guard annoncee != avant else { return }
        reevaluer()
    }
}
