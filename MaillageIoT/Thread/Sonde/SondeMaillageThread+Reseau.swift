import Foundation
import MaillageCoeur
import ProtocoleThread

// Sonde Thread, role Reseau : session reseau, cle du trousseau, reprises de la liaison, oubli de la sonde.
extension SondeMaillageThread {
    /// Oublie la sonde retenue (numero de serie, nom, nom d'hote, cle de ce Mac pour elle :
    /// la sonde garde la sienne), son releve (etat, dernier releve, erreur de tournee) et son
    /// maillage dans le graphe (`surOubli`), et ferme la liaison ; retour a l'USB. L'etat change
    /// tout de suite, avant toute attente ; la cle s'efface ensuite hors de l'acteur principal, et
    /// le nom d'hote part avec elle. Si le trousseau refuse d'effacer la cle, l'echec est montre
    /// et le nom d'hote reste (comme la cle) : « Oublier » peut etre relance.
    func oublier() async {
        preferences.removeObject(forKey: Self.cleSerie)
        retenirSerie(nil)
        choixRefuse = nil
        retenirNom(nil)
        erreurAcces = nil
        // Plus de sonde, plus de reglage : retour a Automatique, comme une nouvelle installation.
        reglage = .automatique
        liaison = .usb
        preferences.removeObject(forKey: Self.cleLiaison)
        reprise?.cancel()
        annulerRetourUSB()
        essaisReprise = 0
        dernierePerte = nil
        etatSonde = nil
        derniereTournee = nil
        erreurTournee = nil
        couverture = nil
        surOubli?()
        deconnecter(.sansSonde)
        guard let h = hote else { return }
        let t = trousseau
        do {
            try await Self.horsActeurPrincipal { try t.oublier(nom: h) }
            // Pendant l'effacement, la sonde choisie de nouveau a pu donner un autre nom d'hote : il reste.
            if hote == h { retenirHote(nil) }
        } catch {
            erreurAcces = String(localized: "Clé de \(h).local non retirée du trousseau : \(error.localizedDescription)")
        }
    }

    /// Nom d'hote de la sonde retenue, garde a cote de son numero de serie ; l'empreinte de la
    /// cle de ce Mac pour lui est relue du trousseau.
    func retenirHote(_ h: String?) {
        if let h {
            preferences.set(h, forKey: Self.cleHote)
        } else {
            preferences.removeObject(forKey: Self.cleHote)
        }
        hote = h
        empreinteAcces = h.flatMap(empreinte(pour:))
    }

    func empreinte(pour nom: String) -> String? {
        trousseau.lister().first { $0.nom == nom }?.empreinte
    }

    /// Nom donne par le dernier `bonjour` : retenu a cote du numero de serie, efface si le
    /// firmware n'en donne pas.
    func retenirNom(_ n: String?) {
        if let n {
            preferences.set(n, forKey: Self.cleNom)
        } else {
            preferences.removeObject(forKey: Self.cleNom)
        }
        nom = n
    }

    /// Connexion par le reseau lancee sans l'attendre (Reglages, lancement) : la liaison en
    /// place est fermee et `etat` passe a `.connexion` tout de suite.
    func lancerConnexionReseau() {
        deconnecter(.connexion)
        serieEtat = serie
        let n = essai
        Task {
            guard n == essai else { return }
            await connecterReseau()
        }
    }

    /// Connexion a la sonde retenue par le reseau Thread : cle du trousseau, session vers
    /// `<hote>.local:5480` (poignee de main H1), `bonjour`, puis tournees. Un echec est montre et
    /// la connexion reprise seule (1, 2, 5, 10 s, puis toutes les 30 s), sauf sans cle (il faut
    /// l'USB). Perimee par un `deconnecter`, elle ferme sa liaison et sort sans rien toucher.
    func connecterReseau() async {
        // Liaison USB : rien a fermer ni a changer.
        guard actif, liaison == .reseau else { return }
        deconnecter(.connexion)
        serieEtat = serie
        let n = essai
        // La liaison USB en place est vraiment fermee : le port est libre.
        await fermetures?.value
        guard n == essai, liaison == .reseau else { return }
        var canal: (any CanalSonde)?
        do {
            guard let hote else { throw CleReseau.Erreur.sansNomDHote }
            let cle = try await lireCle(hote)
            // Arretee (ou autre liaison choisie) pendant la lecture de la cle : aucune session n'est ouverte.
            guard n == essai else { return }
            let c = try await ouvrirReseau(hote, cle)
            canal = c
            guard n == essai else {
                c.fermer()
                return
            }
            // Par le reseau, une commande attend au-dela du renvoi de 4 s du canal.
            let s = SondeUSB(canal: c, delaiCommande: SondeUSB.delaiCommandeReseau)
            enConnexion = s
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
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
                etat = .refusee(String(localized: "\(hote).local n'est pas une sonde (« \(b.produit) »)"))
                return
            }
            enConnexion = nil
            sonde = s
            canalReseau = c
            tenirActivite()
            etat = .connectee(b)
            dernierePerte = nil
            essaisReprise = 0
            retenirNom(b.nom)
            lancerBoucle()
        } catch {
            // Session ouverte puis abandonnee (bonjour sans reponse...) : fermee ici.
            canal?.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = .erreur(error.localizedDescription)
            // Sans cle ou sans nom d'hote (trousseau, ou jamais appris) : il faut l'USB ; le reste
            // se reprend seul. Cle refusee ou absente : l'etat d'acces est relu (la reprise etant
            // notee, la liste ne montre plus l'ancienne cle : « non autorise », pas de selecteur).
            if error is ErreurTrousseauThread { empreinteAcces = hote.flatMap(empreinte(pour:)) }
            if error is ErreurTrousseauThread || error is CleReseau.Erreur { return }
            if let e = error as? ErreurReseau, !e.repriseAutomatique { return }
            planifierReprise()
        }
    }

    /// Lit la cle de l'hote, une seule lecture en vol : une seconde tentative (carte rebranchee puis retiree, annonce qui
    /// tombe puis revient, pendant que macOS attend l'accord de l'utilisateur) rejoint la lecture en cours au lieu d'en lancer
    /// une autre. Sinon la seconde echouerait en `absente` (la reprise est deja notee) et l'acces reseau serait indisponible
    /// jusqu'au relancement, alors que l'accord donne a la premiere recopie la cle. Le resultat est le meme pour toutes ; la
    /// liste du trousseau est relue a la fin, la recopie ayant change ce qu'elle montre.
    private func lireCle(_ hote: String) async throws -> Data {
        if let l = lectureCle, l.hote == hote { return try await l.tache.value }
        let t = trousseau
        let tache = Task { try await Self.horsActeurPrincipal { try t.lire(nom: hote) } }
        numeroLecture += 1
        let numero = numeroLecture
        lectureCle = (numero, hote, tache)
        defer {
            if lectureCle?.numero == numero { lectureCle = nil }
            if self.hote == hote { empreinteAcces = empreinte(pour: hote) }
        }
        return try await tache.value
    }

    /// Operation du trousseau hors de l'acteur principal : macOS peut d'abord demander
    /// l'autorisation d'acceder au trousseau (fenetre modale, signature ad hoc), sans figer le
    /// menu. Pour la lecture de la cle comme pour les ecritures (ranger, oublier) ; la liste des
    /// cles (attributs seulement, sans la cle) reste lue sur place.
    private nonisolated static func horsActeurPrincipal<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try operation() }.value
    }

    private func tenirActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session reseau de la sonde : veille et tournees")
    }

    func relacherActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    /// Nouvel essai de la liaison reseau apres un delai croissant.
    func planifierReprise() {
        let delai = delaisReprise[min(essaisReprise, delaisReprise.count - 1)]
        essaisReprise += 1
        let n = essai
        reprise?.cancel()
        reprise = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.liaison == .reseau else { return }
            await self.connecterReseau()
        }
    }

    // MARK: - Cle

    /// « Autoriser l'acces reseau » (Reglages, sonde retenue branchee en USB) : `bonjour` pour un
    /// nom d'hote a jour (sans lui, aucune cle n'est demandee), `cle nouvelle` par l'USB, cle
    /// verifiee puis rangee dans le trousseau sous ce nom. La carte remplace sa cle : une session
    /// reseau en cours (autre Mac) tombe.
    func autoriserAccesReseau() async {
        guard peutAutoriser, let s = sonde else { return }
        autorisationEnCours = true
        erreurAcces = nil
        defer { autorisationEnCours = false }
        do {
            let b = try await s.bonjour()
            if sonde === s {
                etat = .connectee(b)
                retenirNom(b.nom)
            }
            guard let nomHote = b.hote, !nomHote.isEmpty else { throw CleReseau.Erreur.sansNomDHote }
            let reponse = try await s.cleNouvelle(alea: CleReseau.alea())
            let c = try CleReseau.verifier(reponse).get()
            // La carte a adopte la cle : elle se range meme si la liaison s'est fermee depuis, sous
            // le nom d'hote de la reponse, sinon (nul ou vide) sous celui du `bonjour`.
            let nom = c.hote.flatMap { $0.isEmpty ? nil : $0 } ?? nomHote
            // Ecritures hors de l'acteur principal, comme la lecture de la cle.
            let t = trousseau
            try await Self.horsActeurPrincipal { try t.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte) }
            retenirHote(nom)
            // Une seule sonde retenue : les cles d'autres noms d'hote (mise en service anterieure)
            // ne servent plus ; un echec est montre, la nouvelle cle reste rangee.
            for ancien in trousseau.lister() where ancien.nom != nom {
                do {
                    try await Self.horsActeurPrincipal { try t.oublier(nom: ancien.nom) }
                } catch {
                    erreurAcces = String(localized: "Clé rangée ; l'ancienne clé de \(ancien.nom).local n'a pas pu être retirée du trousseau : \(error.localizedDescription)")
                }
            }
        } catch {
            erreurAcces = error.localizedDescription
        }
    }
}
