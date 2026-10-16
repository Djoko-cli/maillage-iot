import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role Reseau : session reseau (connexion, sonde injoignable retentee), cle du trousseau, mise en service de
// l'acces par le reseau.
extension SondeMaillageZigbee {
    /// Nouvel essai de la connexion par le reseau, tant que le reseau reste le chemin choisi.
    static let delaiReessaiReseau: Duration = .seconds(60)
    /// Attente de `bonjour`, `etat` et `voisins` par le reseau : celle de l'USB, plus 3 s (spec sonde Wi-Fi, 4.1).
    static let delaiCommandeReseau: Duration = Sonde.delaiCommandeUSB + .seconds(3)
    /// Resolution Bonjour, connexion TCP et poignee de main H1 : le canal reseau se ferme s'il n'a pas de session
    /// apres ce delai (decision de la tache 13).
    static let delaiPoigneeDeMain: Duration = .seconds(15)
    /// Relecture d'`etat` hors tournee : la session H1 de la sonde est oubliee apres 10 min sans message, et la carte
    /// ferme une connexion muette depuis 300 s (`Portail::kMuetteMs`) : 180 s laissent 2 minutes de marge aux minuteries
    /// d'une app en arriere-plan (App Nap).
    static let periodeEntretien: Duration = .seconds(180)

    /// Une cle de l'acces par le reseau est dans le trousseau pour la sonde retenue.
    var cleReseauConnue: Bool { empreinteAcces != nil }

    /// La mise en service par l'USB est possible : la sonde retenue y est connectee, en firmware 1.1.0 ou plus, hors
    /// tournee, son adresse longue connue.
    var miseEnServicePossible: Bool {
        guard acces == .usb, !tourneeEnCours, ieee != nil, case .connectee(let b) = etat else { return false }
        return b.accepteReseau && serieEtat == serie
    }

    /// Oublie la sonde retenue (numero de serie, nom), son releve et son maillage dans le graphe (`surOubli`), et ferme
    /// la liaison.
    func oublier() async {
        if let ieee { try? trousseau.oublier(identifiant: ieee) }
        preferences.removeObject(forKey: Self.cleIeee)
        ieee = nil
        relireCleReseau()
        preferences.removeObject(forKey: Self.cleNomWifi)
        nomWifi = nil
        annoncee = false
        instanceAnnoncee = nil
        preferences.removeObject(forKey: Self.cleSerie)
        retenirSerie(nil)
        choixRefuse = nil
        retenirNom(nil)
        oublierReleve()
        surOubli?()
        deconnecter(.sansSonde)
    }

    /// Ce qu'a fait la mise en service de l'acces par le reseau (`autoriserReseau`).
    enum MiseEnService: Equatable {
        /// La cle, puis le Wi-Fi : la sonde redemarre et rejoint le Wi-Fi.
        case cleEtWifi
        /// La cle seulement : la sonde garde son Wi-Fi (mot de passe laisse vide).
        case cleSeule
        /// Le message a montrer.
        case echec(String)

        var erreur: String? {
            if case .echec(let m) = self { m } else { nil }
        }
    }

    /// La sonde connectee a deja un Wi-Fi configure (`etat.reseau`, ou `bonjour.reseau`).
    var wifiConfigure: Bool {
        if etatSonde?.reseau != nil { return true }
        if case .connectee(let b) = etat, b.reseau == true { return true }
        return false
    }

    /// La mise en service envoie aussi le Wi-Fi : un mot de passe est saisi, ou la sonde n'a encore aucun Wi-Fi (un
    /// mot de passe vide est alors un reseau ouvert). Mot de passe vide et Wi-Fi deja configure : la sonde garde le sien
    /// et seule la cle change (constat 1 de la relecture finale : `wifi <nom> -` effacait son mot de passe).
    static func envoiWifi(wifiConfigure: Bool, motDePasse: String) -> Bool {
        !motDePasse.isEmpty || !wifiConfigure
    }

    /// Mise en service de l'acces par le reseau (spec sonde Wi-Fi, 4.3), la cle d'abord (le Wi-Fi fait redemarrer la
    /// sonde) : alea de l'app, cle derivee par la carte, empreinte verifiee, cle rangee dans le trousseau ; puis le
    /// Wi-Fi, sauf si la sonde garde le sien (`envoiWifi`).
    func autoriserReseau(nomWifi: String, motDePasse: String) async -> MiseEnService {
        guard miseEnServicePossible, !miseEnServiceEnCours, let s = sonde, let ieee else {
            return .echec(String(localized: "Branchez la sonde 1.1.0 en USB, hors tournée."))
        }
        miseEnServiceEnCours = true
        let resultat = await mettreEnService(s, ieee: ieee, nomWifi: nomWifi, motDePasse: motDePasse)
        // Apres `.cleEtWifi`, la sonde redemarre : la tournee retenue ne part pas sur une liaison qui va se fermer, la
        // reconnexion planifie la premiere (N2 de la re-relecture finale).
        finirMiseEnService(s, relancer: resultat != .cleEtWifi)
        return resultat
    }

    private func mettreEnService(_ s: Sonde, ieee: String, nomWifi: String, motDePasse: String) async -> MiseEnService {
        let wifi = Self.envoiWifi(wifiConfigure: wifiConfigure, motDePasse: motDePasse)
        let nom = Data(nomWifi.utf8), mdp = Data(motDePasse.utf8)
        guard !wifi || (1...32).contains(nom.count), mdp.isEmpty || (8...63).contains(mdp.count) else {
            return .echec(String(localized: "Nom du Wi-Fi de 1 à 32 octets, mot de passe vide ou de 8 à 63 caractères."))
        }
        do {
            let c = try await s.nouvelleCle(alea: H1.aleatoire(32))
            guard let hexa = c.cle, let cle = H1.octets(hexa: hexa), cle.count == 32, H1.kid(cle: cle) == c.empreinte else {
                return .echec(String(localized: "La sonde a rendu une clé invalide : rien n'a été enregistré."))
            }
            try trousseau.ranger(identifiant: ieee, cle: hexa)
            relireCleReseau()
        } catch {
            return .echec(error.localizedDescription)
        }
        guard wifi else { return .cleSeule }
        // La cle est rangee des deux cotes : si le Wi-Fi echoue, recommencer remplace simplement la cle.
        let sansConfirmation = String(localized: "Clé créée, mais la sonde n'a pas confirmé le Wi-Fi : recommencez.")
        do {
            let w = try await s.configurerWifi(nom: nom, motDePasse: mdp)
            guard w.configure else { return .echec(sansConfirmation) }
            self.nomWifi = nomWifi
            preferences.set(nomWifi, forKey: Self.cleNomWifi)
            return .cleEtWifi
        } catch {
            return .echec(sansConfirmation)
        }
    }

    /// Fin d'une mise en service : la tournee arrivee a son heure entre-temps part, si la sonde est toujours celle-la
    /// et si `relancer` (apres un `wifi`, la sonde redemarre : la fermeture de la liaison n'est pas encore vue, et sa
    /// reconnexion planifie de toute facon la premiere tournee).
    private func finirMiseEnService(_ s: Sonde, relancer: Bool) {
        miseEnServiceEnCours = false
        guard tourneeRetenue else { return }
        tourneeRetenue = false
        if relancer, sonde === s { planifierTournee(dans: .zero) }
    }

    /// Nom donne par le dernier `bonjour` : retenu a cote du numero de serie, efface si le firmware n'en donne pas.
    func retenirNom(_ n: String?) {
        if let n {
            preferences.set(n, forKey: Self.cleNom)
        } else {
            preferences.removeObject(forKey: Self.cleNom)
        }
        nom = n
    }

    /// La cle de l'acces par le reseau de la sonde retenue, depuis le trousseau ; nil sans sonde, sans adresse longue
    /// ou sans cle.
    private func cleReseau() -> Data? {
        guard let ieee, let hexa = try? trousseau.lire(identifiant: ieee) else { return nil }
        return H1.octets(hexa: hexa)
    }

    /// Releve `empreinteAcces` (donc `cleReseauConnue`) dans le trousseau.
    func relireCleReseau() {
        empreinteAcces = cleReseau().map { H1.kid(cle: $0) }
    }

    /// Connexion par le reseau a la sonde retenue (spec sonde Wi-Fi, 4.1 et 4.2) : `bonjour` doit dire la sonde Zigbee et
    /// son adresse longue celle retenue.
    func connecterReseau() async {
        guard actif else { return }
        guard let nom, let cle = cleReseau() else {
            // `reevaluer` a deja mis l'etat a `.connexion` : sans nom ni cle lisible (trousseau en echec, cle effacee
            // entre-temps), l'app ne doit pas y rester bloquee. La cle est relue, puis nouvel essai.
            relireCleReseau()
            guard etat == .connexion, tentativeReseau else { return }
            etat = .injoignable
            planifierReessaiReseau()
            return
        }
        deconnecter(.connexion)
        tentativeReseau = true
        // La connexion concerne la sonde retenue (sans port) : `versUnAutrePort` reste faux, `nomEtat` donne son nom.
        serieEtat = serie
        let n = essai
        await fermetures?.value
        guard n == essai else { return }
        // Une requete sans reponse ferme la liaison (la carte a pu oublier la session sans couper la connexion) :
        // `liaisonFermee`, puis `reevaluer`, la rouvrent.
        let s = Sonde(canal: ouvrirReseau(instanceAnnoncee ?? nom, cle), delaiCommande: delaiCommandeReseau,
                      delaiTable: delaiTable + .seconds(3), fermerSansReponse: true)
        enConnexion = s
        do {
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            // Le premier `bonjour` part avant la poignee de main (le canal le garde jusqu'a la session) : il attend
            // son delai en plus de celui de la poignee de main, sans quoi ces 15 s ne serviraient pas (constat 8).
            let b = try await s.bonjour(delai: Self.delaiPoigneeDeMain + delaiCommandeReseau)
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde, b.ieee == ieee else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "la sonde du réseau n'est pas la sonde retenue"))
                return
            }
            enConnexion = nil
            sonde = s
            acces = .reseau
            etat = .connectee(b)
            retenirNom(b.nom)
            // L'USB a pu devenir le chemin choisi pendant la tentative (sonde branchee, reglage change) : il l'emporte.
            // Si le chemin reste le reseau, rien n'est relance.
            reevaluer()
            guard n == essai, s === sonde else { return }
            await lireEtat(s)
            guard n == essai, s === sonde else { return }
            planifierTournee(dans: delaiPremiereTournee)
            entretenir(s)
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = .injoignable
            planifierReessaiReseau()
        }
    }

    private func planifierReessaiReseau() {
        reessaiReseau?.cancel()
        let n = essai
        let delai = delaiReessaiReseau
        reessaiReseau = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.etat == .injoignable else { return }
            self.etat = .absente
            self.reevaluer()
        }
    }
}
