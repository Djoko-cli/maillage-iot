import Foundation
import MaillageCoeur
import ProtocoleThread

// Sonde Thread, role USB : choix et ouverture des ports. `ouvrable` et chaque appel a `ouvrirCanal` restent ici,
// ensemble : aucun autre fichier n'ouvre un port.
extension SondeMaillageThread {
    /// Choix d'un port dans les Reglages : retenu seulement s'il repond en sonde.
    /// Le port de la sonde deja connectee n'est pas rouvert.
    /// Une carte que Zigbee retient est refusee (`choixRefuse`), sans que rien ne soit ouvert (spec 3.4).
    /// Reseau Thread choisi : pas de port (comme avant). Automatique : le choix prend la place d'une session reseau en cours.
    func choisir(_ port: PortUSB) {
        guard actif, reglage != .reseau, port.chemin != cheminConnecte else { return }
        if let autre = cartes.retenuePar(port.serie, hors: .thread) {
            choixRefuse = CartesRetenues.texteRefus(retenuePar: autre)
            return
        }
        choixRefuse = nil
        annulerRetourUSB()
        liaison = .usb
        reprise?.cancel()
        reprise = nil
        essaisReprise = 0
        dernierePerte = nil
        lancerConnexion(port, choisi: true)
    }

    /// Retient (ou rend, avec nil) le numero de serie de la sonde, et le publie aux cartes retenues : Zigbee ne propose
    /// plus cette carte et ne l'ouvre plus.
    func retenirSerie(_ s: String?) {
        serie = s
        cartes.retenir(s, par: .thread)
    }

    /// Ce port peut etre ouvert : aucun autre module ne retient sa carte, et ou bien l'utilisateur l'a choisi, ou bien c'est
    /// la carte retenue par cette sonde (un C6 inconnu n'est jamais ouvert de lui-meme : ouvrir un port fait basculer
    /// DTR/RTS et peut redemarrer la carte).
    private func ouvrable(_ port: PortUSB, choisi: Bool) -> Bool {
        guard !cartes.retenueParUnAutre(port.serie, que: .thread) else { return false }
        return choisi || (port.serie != nil && port.serie == serie)
    }

    /// Ports branches : la sonde retenue revient, ou s'en va.
    /// Avec « Reseau Thread » choisi, la sonde n'est jamais ouverte en USB, meme branchee. En Automatique, le chemin change
    /// avec la carte : elle part, le reseau (si la cle est connue et la sonde annoncee) ; elle revient, l'USB.
    func portsChanges(_ liste: [PortUSB]) {
        portsVus = liste.filter(\.estEspressif)
        portsConnus = true
        choixRefuse = nil
        guard actif, reglage != .reseau else { return }
        if reglage == .automatique { reevaluer() }
        guard liaison == .usb, let serie else { return }
        if let p = ports.first(where: { $0.serie == serie }) {
            // `lancerConnexion` passe tout de suite a `.connexion` : un second appel n'en lance pas d'autre.
            if sonde == nil && etat != .connexion { lancerConnexion(p, choisi: false) }
        } else if (sonde != nil || etat != .absente) && !versUnAutrePort {
            deconnecter(.absente)
        }
    }

    /// Une connexion, en cours ou etablie, vise un autre port que celui de la sonde retenue (un
    /// choix des Reglages) : l'absence de la sonde retenue ne l'annule pas.
    var versUnAutrePort: Bool {
        (etat == .connexion || sonde != nil) && serieEtat != serie
    }

    /// Connexion au port : ferme la liaison en place et attend qu'elle le soit
    /// vraiment, ouvre le port, le garde s'il repond en sonde. Perimee par un
    /// `deconnecter` pendant une attente, elle ferme sa liaison (en l'attendant)
    /// et sort sans toucher a l'etat, a la sonde, ni au numero de serie retenu.
    /// Automatique (`choisi` faux) et en echec, elle est refaite une fois apres
    /// `delaiNouvelEssai` ; `dernierEssai` : c'est ce nouvel essai.
    func connecter(_ port: PortUSB, choisi: Bool, dernierEssai: Bool = false) async {
        guard ouvrable(port, choisi: choisi) else {
            refuserConnexionEnCours(port)
            return
        }
        deconnecter(.connexion, port: port)
        let n = essai
        // Tant que l'ancienne liaison tient le port, TIOCEXCL refuse de le rouvrir.
        await fermetures?.value
        guard n == essai else { return }
        // L'autre module a pu retenir la carte pendant l'attente : rien n'est ouvert, la sonde ne reste pas en « connexion ».
        guard ouvrable(port, choisi: choisi) else {
            refuserConnexionEnCours(port)
            return
        }
        let s = SondeUSB(canal: ouvrirCanal(port.chemin))
        enConnexion = s
        do {
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            guard n == essai else {
                await s.fermer()
                return
            }
            let b = try await s.bonjour()
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "\(port.libelle) n'est pas une sonde (« \(b.produit) »)"))
                return
            }
            // Zigbee a retenu cette carte pendant la connexion (deux choix en meme temps) : elle n'est pas a nous.
            if let autre = cartes.retenuePar(port.serie, hors: .thread) {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
                return
            }
            enConnexion = nil
            sonde = s
            cheminConnecte = port.chemin
            etat = .connectee(b)
            // Une liaison etablie par l'USB : les echecs du reseau d'avant ne comptent plus.
            essaisReprise = 0
            if choisi, let serieUSB = port.serie {
                let autre = serieUSB != serie
                preferences.set(serieUSB, forKey: Self.cleSerie)
                retenirSerie(serieUSB)
                // Le nom d'hote retenu etait celui d'une autre sonde, comme le releve.
                if autre {
                    retenirHote(nil)
                    etatSonde = nil
                    derniereTournee = nil
                    erreurTournee = nil
                    couverture = nil
                }
            }
            // Le nom va avec la sonde retenue (un port sans numero de serie ne l'est pas).
            let retenue = port.serie != nil && port.serie == serie
            retenirNom(retenue ? b.nom : nil)
            // Son nom d'hote aussi, s'il est connu (nil tant que Matter ne l'a pas enregistre).
            if retenue, let h = b.hote, h != hote { retenirHote(h) }
            lancerBoucle()
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = choisi ? .refusee(error.localizedDescription) : .erreur(error.localizedDescription)
            if !choisi && !dernierEssai { planifierNouvelEssai(port) }
        }
    }

    /// `connecter` refuse ce port (l'autre module retient sa carte) alors que `lancerConnexion` a deja passe la sonde en
    /// `.connexion` pour lui : elle passe en `.refusee` au lieu de rester bloquee (`portsChanges` ne relance pas une sonde en
    /// connexion). Sans effet si la sonde n'attend pas ce port (appel direct, autre connexion en cours).
    private func refuserConnexionEnCours(_ port: PortUSB) {
        guard case .connexion = etat, enConnexion == nil, sonde == nil, serieEtat == port.serie,
              let autre = cartes.retenuePar(port.serie, hors: .thread) else { return }
        etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
    }

    /// Connexion lancee sans l'attendre (Reglages, ports) : la liaison en place
    /// est fermee et `etat` passe a `.connexion` tout de suite ; un `deconnecter`
    /// d'ici au depart de la tache (oublier, autre choix, port retire) l'annule.
    func lancerConnexion(_ port: PortUSB, choisi: Bool) {
        guard ouvrable(port, choisi: choisi) else { return }
        deconnecter(.connexion, port: port)
        let n = essai
        Task {
            guard n == essai else { return }
            await connecter(port, choisi: choisi)
        }
    }

    /// Nouvel essai d'une connexion automatique en echec, apres `delaiNouvelEssai`, si rien n'a
    /// change depuis (aucun `deconnecter` : ni evenement USB, ni choix, ni oubli). C'est le seul :
    /// en echec a son tour, la sonde attend l'evenement USB suivant.
    private func planifierNouvelEssai(_ port: PortUSB) {
        let n = essai
        let delai = delaiNouvelEssai
        nouvelEssai?.cancel()
        nouvelEssai = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.liaison == .usb else { return }
            await self.connecter(port, choisi: false, dernierEssai: true)
        }
    }

    func liaisonFermee(_ s: SondeUSB) {
        guard sonde === s else { return }
        guard liaison == .reseau else {
            deconnecter(.absente)
            return
        }
        // Veille sans reponse (sonde debranchee, redemarree), session perdue : cause montree, et
        // gardee jusqu'a la connexion suivante reussie, puis reconnexion.
        let cause = (canalReseau as? any CauseFermeture)?.raisonFermeture ?? String(localized: "liaison réseau perdue")
        dernierePerte = Perte(cause: cause, date: horloge())
        deconnecter(.erreur(cause))
        serieEtat = serie
        // Automatique : la carte est peut-etre revenue, ou la sonde n'est plus annoncee ; sinon, la reprise.
        reevaluer(immediat: true)
        guard liaison == .reseau else { return }
        planifierReprise()
    }
}
