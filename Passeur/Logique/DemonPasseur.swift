import Foundation

/// Le coeur du demon Passeur Noms, sans HomeKit ni reseau (spec du 12/10, sections 2 et 3) : les abonnes (URL
/// `abonner`), les releves ponctuels (URL `releve`), le suivi de Maison avec regroupement de 2 s, les batteries toutes
/// les heures, « Identifier », l'ouverture a la session et la duree de vie. Tout ce qui touche au systeme est donne a
/// l'initialisation : HomeKit (`SourceMaison`), les connexions (`connecter`, `livrerPonctuel`), SMAppService
/// (`OuvertureSessionDemon`), le temps (`Horloge`) et la sortie (`quitter`).
@MainActor
final class DemonPasseur {
    /// Attente apres un changement dans Maison, le temps que les modifications groupees se terminent.
    static let regroupement: Duration = .seconds(2)
    /// Relecture des batteries : pas d'abonnement aux caracteristiques, pour ne pas solliciter les appareils.
    static let periodeBatteries: Duration = .seconds(3600)
    /// Fermeture apres le depart du dernier abonne (ou apres le lancement, si personne ne s'abonne), hors ouverture a
    /// la session.
    static let inactivite: Duration = .seconds(600)
    /// Attente de Maison pour un releve ponctuel ; au-dela, un releve en erreur part, comme l'ancien passeur.
    static let attenteMaison: Duration = .seconds(100)
    /// Verification legere : l'ouverture a la session change hors de l'app (Reglages Systeme), sans aucun evenement.
    static let verificationEtat: Duration = .seconds(60)

    private let source: any SourceMaison
    private let ouverture: any OuvertureSessionDemon
    private let horloge: any Horloge
    private let version: String
    private let profilExpire: Date?
    private let connecter: @MainActor (EnvoiPasseur.Cible) -> any LienApp
    private let livrerPonctuel: @MainActor (EnvoiPasseur.Cible, Data, @escaping @MainActor () -> Void) -> Void
    private let quitter: @MainActor (String) -> Void

    /// Les abonnes connectes, ou en cours de connexion.
    private(set) var abonnes: [ObjectIdentifier: any LienApp] = [:]
    /// Releves ponctuels en cours : en attente de Maison ou en cours d'envoi.
    private var ponctuels = 0
    /// Releves ponctuels qui attendent Maison.
    private var enAttente: [EnvoiPasseur.Cible] = []
    /// Le dernier releve lu dans Maison.
    private var dernierReleve: NomsMaison?
    /// Le dernier releve envoye aux abonnes, sous sa forme comparable (`comparable`).
    private var dernierEnvoye: NomsMaison?
    private var dernierEtat: EtatPasseur?
    private var regroupe: (any Annulable)?
    private var fermeture: (any Annulable)?
    private var batteries: (any Annulable)?
    private var verification: (any Annulable)?
    private var attente: (any Annulable)?
    /// Controle de 100 s apres le lancement : Maison a-t-elle donne un releve ok ?
    private var controleMaison: (any Annulable)?
    /// Un releve ok a ete lu depuis le lancement.
    private var releveOkLu = false
    /// Raison de la sortie decidee par le controle de Maison ; le demon part des que les envois en cours sont finis.
    private var sortiePrevue: String?

    init(source: any SourceMaison, ouverture: any OuvertureSessionDemon, horloge: any Horloge, version: String,
         profilExpire: Date?, connecter: @escaping @MainActor (EnvoiPasseur.Cible) -> any LienApp,
         livrerPonctuel: @escaping @MainActor (EnvoiPasseur.Cible, Data, @escaping @MainActor () -> Void) -> Void,
         quitter: @escaping @MainActor (String) -> Void) {
        self.source = source
        self.ouverture = ouverture
        self.horloge = horloge
        self.version = version
        self.profilExpire = profilExpire
        self.connecter = connecter
        self.livrerPonctuel = livrerPonctuel
        self.quitter = quitter
    }

    /// Au lancement : suivre Maison, planifier les batteries, et la fermeture si personne ne s'abonne.
    func demarrer() {
        source.surChangement = { [weak self] in self?.changement() }
        planifierBatteries()
        planifierVerification()
        verifierDuree()
        planifierControleMaison()
        journal.notice("lancement, version \(self.version, privacy: .public)")
    }

    var etat: EtatPasseur {
        EtatPasseur(version: version, acces: source.acces, ouvertureSession: ouverture.statut, profilExpire: profilExpire)
    }

    /// URL recue (au lancement ou demon deja ouvert). Jamais l'URL au journal : elle porte le jeton.
    func recevoir(url: URL) async {
        guard let cible = EnvoiPasseur.Cible(url: url) else {
            journal.error("URL illisible, ignorée")
            return
        }
        switch cible.demande {
        case .abonner: await abonner(cible)
        case .releve: await releverPonctuel(cible)
        }
    }

    /// Message d'un abonne.
    func recevoir(_ m: MessagePasseur, de lien: any LienApp) async {
        switch m {
        case .relire:
            await actualiser(batteries: true, demandeur: lien)
        case .identifier(let demande, let accessoire):
            var issue = IssueIdentifier.inconnu
            if let uuid = UUID(uuidString: accessoire) {
                issue = await source.identifier(uuid)
            }
            journal.notice("identification : \(Self.texte(issue), privacy: .public)")
            lien.envoyer(.identifie(issue.reponse(demande)))
        case .ouvertureSession(let actif):
            if let erreur = ouverture.regler(actif: actif) {
                journal.error("ouverture de session (\(actif ? "inscription" : "désinscription", privacy: .public)) : \(erreur, privacy: .public)")
            } else {
                journal.notice("ouverture de session : \(actif ? "inscrit" : "désinscrit", privacy: .public)")
            }
            // Toujours : l'interrupteur de l'app revient a l'etat reel si l'inscription a echoue.
            diffuserEtat(toujours: true)
            verifierDuree()
        case .etat, .releve, .identifie:
            // Messages du passeur vers l'app : ignores dans l'autre sens.
            break
        }
    }

    /// Ordre stable des accessoires : par nom, puis par identifiant (deux accessoires peuvent porter le meme nom).
    static func ordonner(_ a: [AccessoireMaison]) -> [AccessoireMaison] {
        a.sorted { ($0.nom, $0.id ?? "") < ($1.nom, $1.id ?? "") }
    }

    // MARK: Abonnes

    private func abonner(_ cible: EnvoiPasseur.Cible) async {
        let lien = connecter(cible)
        let cle = ObjectIdentifier(lien)
        // Un changement silencieux (ouverture a la session) part aux abonnes deja la, avant le nouveau.
        diffuserEtat()
        abonnes[cle] = lien
        lien.surMessage = { [weak self, weak lien] m in
            guard let self, let lien else { return }
            Task { await self.recevoir(m, de: lien) }
        }
        lien.surFin = { [weak self] in self?.depart(cle) }
        journal.notice("abonné accepté, port \(cible.port), \(self.abonnes.count) abonné(s)")
        verifierDuree()
        lien.envoyer(.etat(etat))
        if let n = dernierReleve {
            lien.envoyer(Self.message(n))
        } else {
            await actualiser(batteries: true, demandeur: nil)
        }
    }

    private func depart(_ cle: ObjectIdentifier) {
        guard abonnes.removeValue(forKey: cle) != nil else { return }
        journal.notice("abonné parti, \(self.abonnes.count) restant(s)")
        verifierDuree()
    }

    /// Envoie `etat` a tous les abonnes s'il a change (`toujours` : meme inchange).
    private func diffuserEtat(toujours: Bool = false) {
        let e = etat
        guard toujours || e != dernierEtat else { return }
        dernierEtat = e
        for l in abonnes.values { l.envoyer(.etat(e)) }
    }

    // MARK: Maison

    /// Changement dans Maison : `etat` tout de suite (l'acces a pu changer), le releve 2 s apres le dernier changement.
    private func changement() {
        diffuserEtat()
        regroupe?.annuler()
        regroupe = horloge.apres(Self.regroupement) { [weak self] in
            guard let self else { return }
            self.regroupe = nil
            // Tant qu'aucun releve ok n'a ete lu, les batteries sont lues ; ensuite on garde leurs valeurs connues.
            await self.actualiser(batteries: self.dernierReleve?.statut != .ok, demandeur: nil)
        }
    }

    /// Refait le releve ; l'envoie a tous les abonnes s'il differe du dernier envoye (date et ordre mis a part), et au
    /// `demandeur` dans tous les cas. Sert aussi les releves ponctuels qui attendaient Maison.
    private func actualiser(batteries: Bool, demandeur: (any LienApp)?) async {
        guard let n = await source.releve(batteries: batteries) else { return }
        dernierReleve = n
        if n.statut == .ok {
            releveOkLu = true
            controleMaison?.annuler()
            controleMaison = nil
        }
        servirPonctuels(n)
        let m = Self.message(n)
        let c = Self.comparable(n)
        if c != dernierEnvoye {
            dernierEnvoye = c
            for l in abonnes.values { l.envoyer(m) }
            if !abonnes.isEmpty {
                journal.notice("relevé envoyé : \(n.accessoires.count) accessoires, \(self.abonnes.count) abonné(s)")
            }
        } else if let d = demandeur, abonnes[ObjectIdentifier(d)] != nil {
            d.envoyer(m)
        }
    }

    private func planifierBatteries() {
        batteries = horloge.apres(Self.periodeBatteries) { [weak self] in
            guard let self else { return }
            await self.actualiser(batteries: true, demandeur: nil)
            self.planifierBatteries()
        }
    }

    /// Toutes les 60 s : `etat` s'il a change (l'ouverture a la session a pu changer dans les reglages du Mac), puis la
    /// duree de vie.
    private func planifierVerification() {
        verification = horloge.apres(Self.verificationEtat) { [weak self] in
            guard let self else { return }
            self.diffuserEtat()
            self.verifierDuree()
            self.planifierVerification()
        }
    }

    /// Lance par une URL `releve` d'une ancienne app alors que le demon ne tournait pas, HomeKit refuse parfois de
    /// repondre au demon (homed, banc du 13/10) : il ne recevra jamais les maisons. Si l'acces est accorde et qu'aucun
    /// releve ok n'est lu 100 s apres le lancement, les releves ponctuels en attente recoivent le releve en erreur et le
    /// demon se ferme, meme avec des abonnes : l'app 1.3.0 se reabonne 5 s plus tard et le relance proprement, sans URL.
    /// Acces en attente (invite en cours) ou refuse : le demon reste.
    private func planifierControleMaison() {
        controleMaison = horloge.apres(Self.attenteMaison) { [weak self] in
            guard let self else { return }
            self.controleMaison = nil
            guard !self.releveOkLu, self.source.acces == .autorise else { return }
            journal.error("Maison n'a donné aucun relevé : le démon se ferme pour être relancé sans URL")
            self.sortiePrevue = "HomeKit ne répond pas : relance sans URL"
            self.servirPonctuels(NomsMaison(date: .now, statut: .erreur, message: "Maison n'a pas répondu"))
            self.sortirSiPret()
        }
    }

    /// Part avec la raison prevue des qu'aucun envoi ponctuel n'est en cours (sinon la sortie couperait la livraison).
    private func sortirSiPret() {
        guard let raison = sortiePrevue, ponctuels == 0 else { return }
        sortiePrevue = nil
        quitter(raison)
    }

    /// Le releve en message `releve` (JSON compact).
    static func message(_ n: NomsMaison) -> MessagePasseur {
        .releve((try? CodageJSON.encodeur().encode(n)) ?? Data("{}".utf8))
    }

    /// Le releve sans sa date, ses accessoires dans un ordre stable : deux releves egaux sous cette forme ne different
    /// que par l'heure ou par l'ordre de HomeKit.
    static func comparable(_ n: NomsMaison) -> NomsMaison {
        var c = n
        c.date = .distantPast
        c.accessoires = ordonner(n.accessoires)
        return c
    }

    // MARK: Releve ponctuel

    private func releverPonctuel(_ cible: EnvoiPasseur.Cible) async {
        journal.notice("relevé ponctuel demandé, port \(cible.port)")
        ponctuels += 1
        verifierDuree()
        if let n = dernierReleve {
            livrer(n, a: cible)
            return
        }
        enAttente.append(cible)
        if attente == nil {
            attente = horloge.apres(Self.attenteMaison) { [weak self] in
                guard let self else { return }
                self.attente = nil
                self.servirPonctuels(NomsMaison(date: .now, statut: .erreur, message: "Maison n'a pas répondu"))
            }
        }
        await actualiser(batteries: true, demandeur: nil)
    }

    private func servirPonctuels(_ n: NomsMaison) {
        guard !enAttente.isEmpty else { return }
        attente?.annuler()
        attente = nil
        let cibles = enAttente
        enAttente = []
        for c in cibles { livrer(n, a: c) }
    }

    /// Envoie le releve au format de la version 1 (les anciennes apps refusent la version 2), puis, s'il ne reste
    /// personne et que le demon n'est pas inscrit a l'ouverture de session, le ferme.
    private func livrer(_ n: NomsMaison, a cible: EnvoiPasseur.Cible) {
        let json = (try? CodageJSON.encodeur().encode(n.enVersion1())) ?? Data("{}".utf8)
        livrerPonctuel(cible, json) { [weak self] in
            guard let self else { return }
            self.ponctuels -= 1
            journal.notice("relevé ponctuel envoyé : \(n.accessoires.count) accessoires")
            if self.sortiePrevue != nil {
                self.sortirSiPret()
            } else if self.abonnes.isEmpty, self.ponctuels == 0, self.ouverture.statut != .active {
                self.quitter("relevé ponctuel envoyé, aucun abonné")
            } else {
                self.verifierDuree()
            }
        }
    }

    // MARK: Duree de vie

    /// Ferme le demon 10 min apres le depart du dernier abonne (ou apres le lancement, si personne ne s'abonne), sauf
    /// s'il est inscrit a l'ouverture de session ou qu'un releve ponctuel est en cours.
    private func verifierDuree() {
        if resterOuvert {
            fermeture?.annuler()
            fermeture = nil
        } else if fermeture == nil {
            fermeture = horloge.apres(Self.inactivite) { [weak self] in
                guard let self else { return }
                self.fermeture = nil
                guard !self.resterOuvert else { return }
                self.quitter("aucun abonné depuis 10 minutes")
            }
        }
    }

    private var resterOuvert: Bool {
        ouverture.statut == .active || !abonnes.isEmpty || ponctuels > 0
    }

    /// Pour le journal : jamais l'identifiant de l'accessoire.
    private static func texte(_ i: IssueIdentifier) -> String {
        switch i {
        case .ok: "faite"
        case .inconnu: "accessoire inconnu"
        case .nonIdentifiable: "accessoire non identifiable"
        case .erreur: "erreur de HomeKit"
        }
    }
}
