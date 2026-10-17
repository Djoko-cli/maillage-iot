import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role USB : liste des ports, carte retenue, ouverture gardee par `ouvrable`, liaison serie, nouveaux
// essais progressifs. Seul fichier qui ouvre un port (`ouvrirCanal`).
extension SondeMaillageZigbee {
    /// Nouvel essai d'une connexion automatique en echec, repete tant que le port de la sonde retenue est liste : une
    /// sonde qui demarre lentement (bonjour sans reponse) n'attend pas l'evenement USB suivant.
    /// Le premier delai ; il double a chaque echec de suite (`delaiNouvelEssai(rang:base:plafond:)`) jusqu'a
    /// `plafondNouvelEssai`, et repart de la a chaque evenement USB ou connexion reussie.
    static let delaiNouvelEssai: Duration = .seconds(5)
    /// Plafond de l'espacement progressif des nouveaux essais USB.
    static let plafondNouvelEssai: Duration = .seconds(60)

    /// Ports Espressif que cette sonde propose et peut ouvrir : les C6 branches, sauf ceux que Thread retient (spec 3.4).
    /// Un autre C6 (le pont Halo) y figure : il n'est ouvert que si on le choisit.
    var ports: [PortUSB] { cartes.choix(portsVus, pour: .zigbee) }

    /// Choix d'un port dans les Reglages : retenu seulement s'il repond en sonde. Le port de la sonde deja connectee
    /// n'est pas rouvert.
    /// Une carte que Thread retient est refusee (`choixRefuse`), sans que rien ne soit ouvert (spec 3.4).
    func choisir(_ port: PortUSB) {
        guard actif, port.chemin != cheminConnecte else { return }
        if let autre = cartes.retenuePar(port.serie, hors: .zigbee) {
            choixRefuse = CartesRetenues.texteRefus(retenuePar: autre)
            return
        }
        choixRefuse = nil
        lancerConnexion(port, choisi: true)
    }

    /// Retient (ou rend, avec nil) le numero de serie de la sonde, et le publie aux cartes retenues : Thread ne propose
    /// plus cette carte et ne l'ouvre plus.
    func retenirSerie(_ s: String?) {
        serie = s
        cartes.retenir(s, par: .zigbee)
    }

    /// Ce port peut etre ouvert : aucun autre module ne retient sa carte, et ou bien l'utilisateur l'a choisi, ou bien c'est
    /// la carte retenue par cette sonde (un C6 inconnu n'est jamais ouvert de lui-meme, meme en Automatique : ouvrir un
    /// port fait basculer DTR/RTS et peut redemarrer la carte).
    private func ouvrable(_ port: PortUSB, choisi: Bool) -> Bool {
        guard !cartes.retenueParUnAutre(port.serie, que: .zigbee) else { return false }
        return choisi || (port.serie != nil && port.serie == serie)
    }

    /// Connexion au port : ferme la liaison en place et attend qu'elle le soit vraiment, ouvre le port, le garde s'il
    /// repond en sonde Zigbee. Perimee par un `deconnecter` pendant une attente, elle ferme sa liaison (en l'attendant)
    /// et sort sans toucher a l'etat, a la sonde, ni au numero de serie retenu. Automatique (`choisi` faux) et en echec,
    /// elle est refaite, de plus en plus espacee, tant que le port reste liste (`planifierNouvelEssai`).
    func connecter(_ port: PortUSB, choisi: Bool) async {
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
        let s = Sonde(canal: ouvrirCanal(port.chemin), delaiTable: delaiTable)
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
                etat = .refusee(String(localized: "\(port.libelle) n'est pas une sonde Zigbee (« \(b.produit) »)"))
                return
            }
            // Thread a retenu cette carte pendant la connexion (deux choix en meme temps) : elle n'est pas a nous.
            if let autre = cartes.retenuePar(port.serie, hors: .zigbee) {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
                return
            }
            enConnexion = nil
            sonde = s
            cheminConnecte = port.chemin
            acces = .usb
            etat = .connectee(b)
            rangNouvelEssai = 0
            if choisi, let serieUSB = port.serie {
                // Le releve etait celui d'une autre sonde.
                if serieUSB != serie { oublierReleve() }
                preferences.set(serieUSB, forKey: Self.cleSerie)
                retenirSerie(serieUSB)
            }
            // Le nom va avec la sonde retenue (un port sans numero de serie ne l'est pas).
            let retenue = port.serie != nil && port.serie == serie
            retenirNom(retenue ? b.nom : nil)
            if retenue, let i = b.ieee {
                preferences.set(i, forKey: Self.cleIeee)
                ieee = i
                relireCleReseau()
            }
            await lireEtat(s)
            guard n == essai, s === sonde else { return }
            planifierTournee(dans: delaiPremiereTournee)
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = choisi ? .refusee(error.localizedDescription) : .erreur(error.localizedDescription)
            if !choisi { planifierNouvelEssai(port) }
        }
    }

    /// `connecter` refuse ce port (l'autre module retient sa carte) alors que `lancerConnexion` a deja passe la sonde en
    /// `.connexion` pour lui : elle passe en `.refusee` au lieu de rester bloquee (`portsChanges` ne relance pas une sonde en
    /// connexion). Sans effet si la sonde n'attend pas ce port (appel direct, autre connexion en cours).
    private func refuserConnexionEnCours(_ port: PortUSB) {
        guard case .connexion = etat, enConnexion == nil, sonde == nil, serieEtat == port.serie,
              let autre = cartes.retenuePar(port.serie, hors: .zigbee) else { return }
        etat = .refusee(CartesRetenues.texteRefus(retenuePar: autre))
    }

    /// Connexion lancee sans l'attendre (Reglages, ports) : la liaison en place est fermee et `etat` passe a
    /// `.connexion` tout de suite ; un `deconnecter` d'ici au depart de la tache (oublier, autre choix, port retire)
    /// l'annule.
    func lancerConnexion(_ port: PortUSB, choisi: Bool) {
        guard ouvrable(port, choisi: choisi) else { return }
        // Un evenement USB (ou un choix) : l'espacement des nouveaux essais repart du premier delai.
        rangNouvelEssai = 0
        deconnecter(.connexion, port: port)
        let n = essai
        Task {
            guard n == essai else { return }
            await connecter(port, choisi: choisi)
        }
    }

    /// Nouvel essai d'une connexion automatique en echec, apres un delai progressif (`delaiNouvelEssai(rang:base:plafond:)`, 5 s
    /// puis 10, 20... au plus 60 s ; un evenement USB ou une connexion reussie le remet a 5 s), si rien n'a change depuis (aucun
    /// `deconnecter` : ni evenement USB, ni choix, ni oubli) et que le port est toujours liste. En echec a son tour, il
    /// en planifie un autre : une sonde qui ne lit l'USB qu'apres une longue attente (Wi-Fi absent ou refuse) finit par
    /// repondre, sans debrancher (constat 2 de la relecture finale).
    private func planifierNouvelEssai(_ port: PortUSB) {
        let n = essai
        let delai = Self.delaiNouvelEssai(rang: rangNouvelEssai, base: delaiNouvelEssai, plafond: plafondNouvelEssai)
        rangNouvelEssai += 1
        let dormir = self.dormir
        nouvelEssai?.cancel()
        nouvelEssai = Task { [weak self] in
            try? await dormir(delai)
            guard !Task.isCancelled, let self, n == self.essai,
                  self.ports.contains(where: { $0.chemin == port.chemin }) else { return }
            await self.connecter(port, choisi: false)
        }
    }

    /// L'espacement des nouveaux essais USB : `base`, puis le double a chaque echec de suite, au plus `plafond` (par
    /// exemple 5, 10, 20, 40, 60, 60 s) : une carte qui ne repond jamais n'est plus rouverte toutes les 5 s.
    static func delaiNouvelEssai(rang: Int, base: Duration, plafond: Duration) -> Duration {
        min(plafond, base * (1 << min(max(rang, 0), 16)))
    }

    func liaisonFermee(_ s: Sonde) {
        guard sonde === s else { return }
        let etaitReseau = acces == .reseau
        deconnecter(.absente)
        // Une sonde du reseau coupee est retentee si elle reste annoncee ; une liaison USB fermee attend, comme avant,
        // l'evenement USB suivant.
        if etaitReseau { reevaluer() }
    }
}
