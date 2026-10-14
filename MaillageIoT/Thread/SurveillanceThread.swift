import AppKit
import MaillageCoeur
import ProtocoleThread
import Observation
import os

/// Chiffres du reseau affiche, pour la barre des menus.
struct ResumeReseauThread: Equatable {
    var nom: String
    var partitions: Int
    var routeurs: Int
    var appareils: Int
    /// Appareils Thread qui ne sont pas joignables (adresse non annoncee, isoles, inconnus) ou disparus, hors ceux
    /// que la sonde a trouves (`SurveillanceThread.verification`).
    var injoignables: Int
}

/// Le dernier maillage de la sonde, tel qu'il est garde sur disque (`dernier-maillage.json`) pour le lancement suivant
/// (repris de Maillage Zigbee, 12/10).
private struct MaillageGarde: Codable {
    var maillage: Maillage
    /// Reception du maillage (`SurveillanceThread.maillageRecu`).
    var recu: Date
}

/// Les dernieres adresses des appareils, telles qu'elles sont gardees sur disque (`dernieres-adresses.json`) pour le
/// lancement suivant : un appareil qui n'annonce plus d'adresse y garde la derniere, pour que la sonde le verifie.
private struct AdressesGardees: Codable {
    /// Par identifiant d'appareil.
    var appareils: [String: Suivi.AdresseGardee]
}

/// Le modele de Thread, un des modeles de protocole de la coque `Surveillance` : releves de Bonjour -> suivi ; maillages
/// de la sonde -> historique ; noms ; etat lu par les vues, avec ses fichiers sous `Thread/` et ses seuils de fraicheur
/// (6 et 15 min). Le journal, les alertes, les surnoms et la veille sont ceux de la coque (`coque`) : les evenements
/// de Thread y vont par `Surveillance.ajouter(_:de:)`, qui les marque du protocole Thread.
@MainActor
@Observable
final class SurveillanceThread: ModeleProtocole {
    typealias Fraicheur = Surveillance.Fraicheur

    enum EtatEcoute: Equatable {
        case demarrage, active, reseauLocalRefuse, demo
        case erreur(String)
    }

    let mode: Surveillance.Mode
    /// Ce modele rejoue la panne du 27/09 ; faux : en demo, un modele muet (la demo n'a qu'un reseau a la fois, la demo
    /// combinee est a l'etape 3b).
    let rejoueLaDemo: Bool
    private(set) var etatEcoute: EtatEcoute
    private(set) var suivi = Suivi()
    private(set) var dernierReleve: Annonces?
    /// Date du premier releve vide recu alors qu'un instantane existe (le Mac
    /// n'entend plus rien : reseau local coupe, acces refuse) ; nil des qu'un
    /// releve non vide arrive.
    private(set) var rienVuDepuis: Date?
    private(set) var routesLisibles: Bool?
    var noms: ResolveurNoms
    /// Reseau affiche (`xp`) ; nil : le premier.
    var reseauChoisi: String?
    /// Dernier maillage de la sonde ; nil sans sonde.
    private(set) var maillage: Maillage?
    /// Reception du dernier maillage, a la fin de sa tournee : son age se compte
    /// depuis (le maillage, lui, est date du debut de sa tournee).
    private(set) var maillageRecu: Date?
    /// Le maillage affiche est celui relu au lancement (`chargerMaillageGarde`), pas encore remplace par une tournee :
    /// il se montre quel que soit son age, frais ou « ancien » selon la regle normale, mais jamais perime (la
    /// peremption de 15 min ne vaut que pour un maillage recu pendant que l'app tourne).
    private(set) var maillageRelu = false
    /// Une tournee de la sonde est en cours (`SondeMaillageThread.surTournee`) : le
    /// maillage affiche attend le suivant, il n'est pas « ancien ».
    var tourneeEnCours = false
    /// Historique de la sonde (spec de la sonde, section 6) : les releves des 30 derniers jours,
    /// du plus ancien au plus recent ; toujours vide en demo.
    private(set) var historique: [ReleveMaillage] = []
    /// Resolution des cles de l'historique (`ClesHistorique`), construite a la premiere demande et gardee jusqu'au
    /// prochain changement de l'historique : `recevoir` et `chargerHistorique` l'effacent (relecture, Mineur 3).
    @ObservationIgnored private var clesGardees: ClesHistorique?
    /// Nombre de resolutions construites : une par changement de l'historique au plus (lu par les tests).
    @ObservationIgnored private(set) var constructionsCles = 0

    /// La coque qui porte le journal, les alertes et les surnoms ; posee par `Surveillance.init`.
    @ObservationIgnored weak var coque: Surveillance?
    @ObservationIgnored private let recenseur: Recenseur?
    /// Les associations a la main appareil -> accessoire de Maison (`associations.json`) : mode direct avec un
    /// dossier ; nil : nulle part (demo, tests sans dossier).
    @ObservationIgnored private let fichierAssociations: URL?
    /// Le dernier maillage garde (`dernier-maillage.json`) : mode direct avec un dossier ; nil : nulle part (demo).
    @ObservationIgnored private let fichierMaillage: URL?
    /// Les dernieres adresses gardees (`dernieres-adresses.json`) : mode direct avec un dossier ; nil : nulle part
    /// (demo, tests sans dossier).
    @ObservationIgnored private let fichierAdresses: URL?
    /// Ce qui est sur disque dans `dernieres-adresses.json` (vide : rien d'ecrit, ou fichier illisible) : on n'ecrit
    /// que ce qui change.
    @ObservationIgnored private var adressesEcrites: [String: Suivi.AdresseGardee] = [:]
    @ObservationIgnored private var suiviMaillage = SuiviMaillage()
    /// Historique sur disque : mode direct avec un dossier ; nil : nulle part (demo, tests).
    @ObservationIgnored private let fichiersHistorique: HistoriqueFichiers?
    /// Ou garder les scissions deja notifiees (`cleScissionsNotifiees`).
    @ObservationIgnored private let preferences: UserDefaults
    /// Scissions notifiees lues (au demarrage, en mode direct) : ecrites ensuite a
    /// chaque changement. Sinon (demo, surveillance pas demarree : tests), ni lues ni ecrites.
    @ObservationIgnored private var scissionsChargees = false

    /// Le protocole de ce modele : ses evenements le portent (`ajouter`), ses surnoms sont sous ce protocole.
    nonisolated static let protocole = Protocole.thread
    var protocole: Protocole { Self.protocole }
    /// Signatures des scissions deja notifiees (`[String]`), d'un lancement a l'autre.
    static let cleScissionsNotifiees = "thread.scissionsNotifiees"

    /// `dossier` : la racine des donnees de l'app ; les fichiers de Thread (associations, dernier maillage, adresses
    /// gardees, historique de la sonde) vont sous `Thread/` (nil : nulle part) ; `surnoms` : ceux de `surnoms.json`, de
    /// tous les protocoles (le resolveur de noms ne garde que ceux de Thread) ; `preferences` : les scissions deja
    /// notifiees (mode direct, une fois demarre) ; `rejoueLaDemo` : en demo, la panne du 27/09.
    init(mode: Surveillance.Mode, dossier: URL?, surnoms: [IdNoeud: String], preferences: UserDefaults,
         rejoueLaDemo: Bool = true) {
        self.mode = mode
        self.rejoueLaDemo = rejoueLaDemo
        self.preferences = preferences
        switch mode {
        case .direct:
            etatEcoute = .demarrage
            recenseur = Recenseur()
            fichierAssociations = dossier.map { Surveillance.dossierThread($0).appendingPathComponent("associations.json") }
            fichierMaillage = dossier.map { Surveillance.dossierThread($0).appendingPathComponent("dernier-maillage.json") }
            fichierAdresses = dossier.map { Surveillance.dossierThread($0).appendingPathComponent("dernieres-adresses.json") }
            noms = ResolveurNoms(surnoms: Surnoms.cles(de: surnoms, protocole: Self.protocole),
                                 associations: fichierAssociations.map(Associations.lire) ?? [:])
            fichiersHistorique = dossier.map { HistoriqueFichiers(dossier: Surveillance.dossierThread($0)) }
        case .demo:
            etatEcoute = .demo
            recenseur = nil
            fichierAssociations = nil
            fichierMaillage = nil
            fichierAdresses = nil
            noms = rejoueLaDemo ? ResolveurNoms(maison: NomsDemo.maison) : ResolveurNoms()
            fichiersHistorique = nil
        }
    }

    func demarrer() {
        switch mode {
        case .demo:
            guard rejoueLaDemo else { return }
            for a in ScenarioPanne.releves { integrer(a) }
            if let m = instantane.flatMap({ MaillageDemo.maillage($0, date: maintenant) }) {
                recevoir(m, a: maintenant)
            }
        case .direct:
            chargerScissionsNotifiees()
            chargerMaillageGarde()
            chargerAdressesGardees()
            Task { [weak self] in await self?.chargerHistorique() }
            recenseur?.surReleve = { [weak self] a in self?.integrer(a) }
            recenseur?.surEtat = { [weak self] e in self?.noterEtat(e) }
            recenseur?.demarrer()
        }
    }

    /// Lit les scissions deja notifiees (au demarrage, mode direct) : un reseau
    /// qui reste scinde n'est pas notifie de nouveau a chaque lancement.
    func chargerScissionsNotifiees() {
        coque?.reprendreScissionsNotifiees(Set(preferences.stringArray(forKey: Self.cleScissionsNotifiees) ?? []))
        scissionsChargees = true
    }

    /// Les scissions notifiees ont change (`Surveillance.ajouter`) : les garder, une fois chargees (mode direct).
    func garderScissionsNotifiees(_ signatures: Set<String>) {
        guard scissionsChargees else { return }
        preferences.set(signatures.sorted(), forKey: Self.cleScissionsNotifiees)
    }

    func arreter() {
        recenseur?.arreter()
    }

    /// Le Mac se reveille : releve immediat.
    func auReveil() {
        recenseur?.rafraichir()
    }

    /// Releve immediat.
    func rafraichir() {
        recenseur?.rafraichir()
    }

    /// Integre un releve : evenements, journal, notifications. Un releve vide ne
    /// change pas l'instantane (voir `Suivi`) : il est seulement note (`rienVuDepuis`).
    func integrer(_ a: Annonces) {
        dernierReleve = a
        routesLisibles = mode == .demo ? true : recenseur?.routesLisibles
        if !a.estVide {
            rienVuDepuis = nil
        } else if instantane != nil && rienVuDepuis == nil {
            rienVuDepuis = a.date
        }
        let nouveaux = suivi.integrer(a, noms: noms)
        ajouter(nouveaux)
        garderAdresses(releve: a.date)
    }

    /// Verse des evenements au journal de la coque (qui les marque du protocole Thread, les garde et notifie). Un modele
    /// n'est jamais utilise apres la mort de sa coque : en Debug, des evenements perdus sont une erreur.
    private func ajouter(_ evenements: [Evenement]) {
        assert(coque != nil || evenements.isEmpty, "SurveillanceThread sans coque : des evenements seraient perdus")
        coque?.ajouter(evenements, de: Self.protocole)
    }

    /// Tant qu'un appareil annonce son adresse, son annonce avance a chaque releve (toutes les minutes) : une avance de
    /// moins de 15 min ne justifie pas une ecriture. Une annonce qui ne bouge plus est ecrite exacte (voir
    /// `adressesAEcrire`).
    nonisolated static let ecartAnnonceEcrite: TimeInterval = 15 * 60

    /// Duree de garde d'une adresse sur disque : au-dela de 30 jours sans annonce, l'appareil est oublie (ecriture et
    /// relecture), comme un appareil que la sonde ne cherche plus.
    nonisolated static let dureeAdressesGardees: TimeInterval = 30 * 24 * 3600

    /// Ce qui est sur disque differe-t-il de `actuelles` ? Un appareil de plus ou de moins, une autre adresse ou
    /// partition, ou une annonce differente. Seule exception : un appareil qui annonce encore a ce releve (`releve`)
    /// n'est reecrit que si son annonce a avance de `ecartAnnonceEcrite`. Quand il cesse d'annoncer, sa derniere
    /// annonce est ecrite exacte : celle que la sonde compare aux resolutions ne retarde jamais apres la relance.
    nonisolated static func adressesAEcrire(_ actuelles: [String: Suivi.AdresseGardee],
                                            ecrites: [String: Suivi.AdresseGardee], releve: Date) -> Bool {
        guard actuelles.keys == ecrites.keys else { return true }
        return actuelles.contains { id, a in
            guard let e = ecrites[id] else { return true }
            guard a.adresse == e.adresse, a.partition == e.partition else { return true }
            let ecart = abs(a.annonce.timeIntervalSince(e.annonce))
            return a.annonce == releve ? ecart >= ecartAnnonceEcrite : ecart > 0
        }
    }

    /// Les adresses dont la derniere annonce a au plus `dureeAdressesGardees` a `maintenant` ; les autres sont
    /// oubliees.
    nonisolated static func adressesRecentes(_ gardees: [String: Suivi.AdresseGardee],
                                             a maintenant: Date) -> [String: Suivi.AdresseGardee] {
        gardees.filter { maintenant.timeIntervalSince($0.value.annonce) <= dureeAdressesGardees }
    }

    /// Reprend les dernieres adresses gardees, avant le premier releve : le suivi les connait alors comme s'il les
    /// avait vues, et un appareil qui n'annonce plus d'adresse est demande a la sonde des le premier releve. Fichier
    /// absent : rien. Illisible ou incoherent (adresse invalide, partition vide) : rien non plus, consigne dans le
    /// journal du Mac. Les appareils sans annonce depuis plus de 30 jours (`dureeAdressesGardees`) sont oublies.
    /// Une annonce relue est bornee a `maintenant` : une date future (horloge reculee depuis l'ecriture, fichier
    /// modifie) bloquerait l'appareil, qu'aucune resolution ne pourrait plus rendre posterieure.
    func chargerAdressesGardees(maintenant: Date = Date()) {
        guard let fichierAdresses, FileManager.default.fileExists(atPath: fichierAdresses.path) else { return }
        do {
            let garde = try CodageJSON.decodeur().decode(AdressesGardees.self, from: Data(contentsOf: fichierAdresses))
            guard garde.appareils.allSatisfy({ !$0.key.isEmpty && !$0.value.partition.isEmpty }) else {
                Surveillance.journalMac.error("dernieres adresses incoherentes, ignorees")
                return
            }
            let relues = Self.adressesRecentes(garde.appareils, a: maintenant).mapValues { g in
                var g = g
                g.annonce = min(g.annonce, maintenant)
                return g
            }
            suivi.amorcer(relues)
            // Le disque est tel quel : ce que la purge a oublie y sera retire a la premiere ecriture.
            adressesEcrites = garde.appareils
        } catch {
            Surveillance.journalMac.error("dernieres adresses illisibles, ignorees")
        }
    }

    /// Garde les dernieres adresses sur disque, d'un bloc, quand elles ont change au releve `releve`
    /// (`adressesAEcrire`). Un echec est consigne dans le journal du Mac ; le suivi garde tout en memoire et l'ecriture
    /// est retentee au releve suivant.
    private func garderAdresses(releve: Date) {
        guard let fichierAdresses else { return }
        let actuelles = Self.adressesRecentes(suivi.adressesGardees, a: releve)
        guard Self.adressesAEcrire(actuelles, ecrites: adressesEcrites, releve: releve) else { return }
        do {
            try FileManager.default.createDirectory(at: fichierAdresses.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try CodageJSON.encodeur().encode(AdressesGardees(appareils: actuelles)).write(to: fichierAdresses,
                                                                                          options: .atomic)
            adressesEcrites = actuelles
        } catch {
            Surveillance.journalMac.error("dernieres adresses non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reprend le dernier maillage garde, avant la premiere tournee de la sonde : son age se compte depuis sa reception
    /// (la pastille « ancien » le dit). Fichier absent : rien. Illisible ou incoherent : rien non plus, consigne dans
    /// le journal du Mac. Un maillage deja recu l'emporte.
    func chargerMaillageGarde() {
        guard maillage == nil, let fichierMaillage,
              let donnees = try? Data(contentsOf: fichierMaillage) else { return }
        guard let garde = try? CodageJSON.decodeur().decode(MaillageGarde.self, from: donnees),
              garde.maillage.identifiantsValides else {
            Surveillance.journalMac.error("dernier maillage illisible, ignore")
            return
        }
        maillage = garde.maillage
        maillageRecu = garde.recu
        maillageRelu = true
    }

    /// Garde le maillage recu sur disque, d'un bloc. Un echec est consigne dans le journal du Mac ; le maillage reste
    /// en memoire.
    private func garderMaillage(_ m: Maillage, recu: Date) {
        guard let fichierMaillage else { return }
        do {
            try FileManager.default.createDirectory(at: fichierMaillage.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try CodageJSON.encodeur().encode(MaillageGarde(maillage: m, recu: recu)).write(to: fichierMaillage,
                                                                                          options: .atomic)
        } catch {
            Surveillance.journalMac.error("dernier maillage non ecrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Nouveau maillage de la sonde, recu a `date` (fin de sa tournee) : ses evenements vont au
    /// journal (changements de parent, routeurs Thread) ; en mode direct, son releve va a
    /// l'historique, en memoire et, avec un dossier, sur disque. Un echec d'ecriture est consigne
    /// dans le journal du Mac ; le releve reste en memoire. Le maillage est aussi garde sur disque, pour le prochain
    /// lancement.
    func recevoir(_ m: Maillage, a date: Date) {
        maillage = m
        maillageRecu = date
        maillageRelu = false
        ajouter(suiviMaillage.integrer(m, sujets: sujets(m)))
        guard mode == .direct else { return }
        garderMaillage(m, recu: date)
        let r = ReleveMaillage(m)
        let limite = date.addingTimeInterval(-Surveillance.dureeHistorique)
        historique = historique.filter { $0.date >= limite } + [r]
        clesGardees = nil
        coque?.purgerSiNouveauMois(date)
        guard let f = fichiersHistorique else { return }
        do {
            try f.ajouter(r)
        } catch {
            Surveillance.journalMac.error("releve de l'historique non ecrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purge l'historique sur disque (mois finis depuis plus de 90 jours), a la demande de la coque quand le mois change.
    /// Un echec est ignore : la purge reviendra au lancement suivant. Sans dossier (demo, tests) : rien.
    func purgerHistorique(maintenant: Date) {
        _ = try? fichiersHistorique?.purger(maintenant: maintenant)
    }

    /// Relit les 30 derniers jours de l'historique, hors de l'acteur principal, apres avoir purge
    /// les mois finis depuis plus de 90 jours ; les releves recus entre-temps restent. Sans dossier
    /// (demo, tests) : rien.
    func chargerHistorique() async {
        guard let f = fichiersHistorique else { return }
        let maintenant = Date()
        coque?.noterPurge(a: maintenant)
        let debut = maintenant.addingTimeInterval(-Surveillance.dureeHistorique)
        do {
            let lus = try await Task.detached(priority: .utility) {
                // Une purge qui echoue n'empeche pas la lecture.
                _ = try? f.purger(maintenant: maintenant)
                return try f.lire(depuis: debut)
            }.value
            // Les dates relues sont tronquees a la milliseconde (codage) : un releve recu pendant la
            // lecture, ecrit puis relu, garde jusqu'a 1 ms de moins que sa copie en memoire. Il n'est pas repris.
            let premier = (historique.first?.date ?? .distantFuture).addingTimeInterval(-0.001)
            historique = lus.filter { $0.date < premier } + historique
            clesGardees = nil
        } catch {
            Surveillance.journalMac.error("historique illisible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rapprochement d'un maillage avec le reseau de sa partition (a defaut, le reseau affiche),
    /// frais ou non ; nil sans instantane.
    private func rapprochement(_ m: Maillage) -> MaillageAffiche? {
        guard let i = instantane,
              let r = i.reseaux.first(where: { r in r.partitions.contains { $0.id == m.partition } }) ?? reseau else {
            return nil
        }
        return MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils + Array(suivi.disparus.values),
                               trel: i.trel, dernieresAdresses: dernieresAdressesVerifiees(a: maintenant))
    }

    /// Noeuds d'un maillage pour le journal : leur id dans le graphe et leur nom affiche,
    /// d'apres le rapprochement avec le reseau de sa partition (a defaut, le reseau affiche). Un
    /// enfant identifie est d'abord l'appareil de meme ExtMac : vu deux fois (resolution ancienne,
    /// table), il n'a son id d'appareil qu'une fois dans le graphe.
    func sujets(_ m: Maillage) -> SujetsMaillage {
        let affiche = rapprochement(m)
        let appareils = (instantane?.appareils ?? []) + Array(suivi.disparus.values)
        func sujet(_ n: NoeudSonde?, rloc16: UInt16, genre: NoeudSonde.Genre, bordure: Bool) -> Sujet {
            let noeud = n ?? NoeudSonde(id: String(format: "rloc:%04X", rloc16), rloc16: rloc16, genre: genre,
                                        reconnu: false, bordure: bordure)
            return Sujet(id: noeud.id, nom: nomNoeud(noeud.id, maillage: affiche) ?? LibellesNoeuds.inconnu(noeud))
        }
        var s = SujetsMaillage()
        for r in m.routeurs {
            s.routeurs[r.id] = sujet(affiche?.routeurs[r.id], rloc16: r.rloc16, genre: .routeur, bordure: r.bordure)
        }
        for e in m.enfants {
            if let x = e.extMac, let a = appareils.first(where: { $0.id.uppercased() == x }) {
                s.enfants[e.rloc16] = Sujet(id: a.id, nom: nom(a))
            } else {
                s.enfants[e.rloc16] = sujet(affiche?.enfants[e.rloc16], rloc16: e.rloc16, genre: .enfant, bordure: false)
            }
        }
        return s
    }

    /// Appareils que la sonde doit resoudre (spec de la sonde tout-en-un, section 2.2) : ceux de l'instantane qui ont
    /// une adresse sur le prefixe OMR de leur partition, l'adresse nue, puis ceux qui n'annoncent plus d'adresse (sans
    /// adresse, disparus) avec leur derniere (`AppareilAResoudre.depuis(_: Suivi)`) ; aucun sans instantane.
    func appareilsAResoudre() -> [AppareilAResoudre] {
        AppareilAResoudre.depuis(suivi)
    }

    /// Age au-dela duquel une resolution ne verifie plus un appareil : deux resolutions completes (une toutes les
    /// 30 min) ; en marche normale, celle que garde la memoire de la tournee a moins de 35 min.
    static let ageMaxVerification: TimeInterval = 2 * Tournee.periodeResolution

    /// Date a laquelle la sonde a trouve, par la resolution d'adresse, un appareil qui n'annonce plus d'adresse (sans
    /// adresse, ou disparu) : il est joignable. Nil s'il annonce son adresse, si la derniere resolution ne l'a pas
    /// trouve ou si l'appareil n'y a pas repondu (cache seul, firmware ancien), sans maillage ou s'il est perime, si la
    /// resolution a plus de `ageMaxVerification`, et si elle n'est pas strictement posterieure a la derniere annonce de
    /// son adresse (`Suivi.dernieresAnnonces`). L'instantane reste le reflet de Bonjour : cet etat est derive ici, a
    /// chaque lecture, du dernier maillage de la sonde.
    /// Partition montree pour un appareil (liste, graphe, fiche) : la sienne s'il en a une ; verifie par la sonde,
    /// celle qui porte aujourd'hui le prefixe de sa derniere adresse ; sinon sa derniere partition connue.
    func partitionAffichee(_ a: Appareil, verifie: Bool) -> String? {
        a.partition ?? (verifie ? suivi.partitionActuelle(de: a.id) : suivi.dernieresPartitions[a.id])
    }

    func verification(_ id: String, a maintenant: Date) -> Date? {
        verifications(a: maintenant)[id]
    }

    /// Appareils qui n'annoncent plus d'adresse et que la sonde a trouves (`verification`), avec la date.
    func verifications(a maintenant: Date) -> [String: Date] {
        guard let m = maillage, let i = instantane, fraicheurMaillage(a: maintenant) != .perime else { return [:] }
        let muets = Set(i.appareils.filter { $0.genre == .sansAdresse }.map(\.id)).union(suivi.disparus.keys)
        // Une resolution d'avant la derniere annonce de l'adresse ne prouve rien : l'appareil l'annoncait encore. Il
        // faut aussi que l'appareil ait repondu a la sonde (`resolusRepondus`) : une entree du cache d'adresses seule,
        // ou un firmware ancien qui ne le dit pas, ne vaut pas verification.
        return m.resolus.filter { id, d in
            guard muets.contains(id), m.resolusRepondus.contains(id), !suivi.adresseAnnonceeParUnAutre(id),
                  maintenant.timeIntervalSince(d) <= Self.ageMaxVerification,
                  let annonce = suivi.dernieresAnnonces[id] else { return false }
            return d > annonce
        }
    }

    /// Derniere adresse de chaque appareil verifie (`verifications`) : le rapprochement le reconnait a elle.
    private func dernieresAdressesVerifiees(a maintenant: Date) -> [String: AdresseIPv6] {
        let verifies = verifications(a: maintenant)
        return suivi.dernieresAdresses.filter { verifies[$0.key] != nil }
    }

    /// Sonde oubliee (`SondeMaillageThread.surOubli`) : son maillage part tout de suite, sans attendre
    /// qu'il soit perime ; le graphe revient aux pointilles. Son suivi aussi : le maillage suivant
    /// (une autre sonde, plus tard) est un point de depart, sans evenement. L'historique reste : il
    /// parle du reseau, pas de la sonde.
    func oublierMaillage() {
        maillage = nil
        maillageRecu = nil
        maillageRelu = false
        if let fichierMaillage, FileManager.default.fileExists(atPath: fichierMaillage.path) {
            do {
                try FileManager.default.removeItem(at: fichierMaillage)
            } catch {
                Surveillance.journalMac.error("dernier maillage non efface : \(error.localizedDescription, privacy: .public)")
            }
        }
        suiviMaillage = SuiviMaillage()
    }

    /// Veille du Mac (appele au reveil par la coque) : ses evenements vont au journal.
    func noterVeille(_ intervalle: DateInterval) -> [Evenement] {
        suivi.noterVeille(intervalle)
    }

    /// Le releve de Maison du Passeur (le meme que celui de Zigbee) : le resolveur de noms de Thread le garde.
    func recevoirReleveMaison(_ releve: NomsMaison?) {
        noms.maison = releve
    }

    /// Applique (ou retire) le surnom d'un noeud Thread au resolveur de noms ; `cle` : la cle brute du noeud.
    func appliquerSurnom(_ surnom: String?, cle: String) {
        noms.surnoms[cle] = surnom
    }

    /// Associe l'appareil `id` a un accessoire de Maison (« Associer a un accessoire de Maison… ») : il en prend le nom
    /// et la piece, comme s'il etait trouve par son noeud. Garde dans `associations.json`, en mode direct avec un
    /// dossier seulement ; sans effet pour un accessoire sans noeud.
    func associer(_ id: String, a accessoire: AccessoireMaison) {
        guard let noeud = accessoire.noeudMatter?.uppercased(), noeud != ResolveurNoms.noeudNul else { return }
        guard noms.associations[id] != noeud else { return }
        noms.associations[id] = noeud
        ecrireAssociations()
    }

    /// Defait l'association de l'appareil `id` (« Dissocier »).
    func dissocier(_ id: String) {
        guard noms.associations.removeValue(forKey: id) != nil else { return }
        ecrireAssociations()
    }

    private func ecrireAssociations() {
        guard let fichierAssociations else { return }
        do {
            try Associations.ecrire(noms.associations, dans: fichierAssociations)
        } catch {
            coque?.noterErreurJournal(error.localizedDescription)
        }
    }

    private func noterEtat(_ e: Recenseur.Etat) {
        switch e {
        case .demarrage: etatEcoute = .demarrage
        case .actif: etatEcoute = .active
        case .reseauLocalRefuse: etatEcoute = .reseauLocalRefuse
        case .erreur(let m): etatEcoute = .erreur(m)
        }
    }

    // MARK: - Pour les vues

    var instantane: Instantane? { suivi.instantane }

    /// Reference des durees a l'heure `horloge` (celle de la fenetre du graphe, que sa `TimelineView`
    /// avance chaque minute) : cette heure, ou la fin de la panne rejouee en demo (`.distantPast` pour un modele muet :
    /// la coque prend le plus tard des modeles).
    func maintenant(a horloge: Date) -> Date {
        guard mode == .demo else { return horloge }
        return rejoueLaDemo ? (dernierReleve?.date ?? horloge) : .distantPast
    }

    var reseau: Reseau? {
        guard let i = instantane else { return nil }
        return reseauChoisi.flatMap { i.reseau($0) } ?? i.reseaux.first
    }

    var fabriqueApple: String? {
        guard let i = instantane else { return nil }
        return noms.fabriqueApple(appareils: i.appareils + i.appareilsIP + Array(suivi.disparus.values))
    }

    func nom(_ a: Appareil) -> String { noms.nom(appareil: a, fabriqueApple: fabriqueApple) }
    func nom(_ r: RouteurBordure) -> String { noms.nom(routeur: r) }

    /// Nom affiche de chaque routeur de bordure d'un reseau, par instance : libelles du graphe,
    /// fiche, candidats d'un routeur de bordure non identifie.
    func nomsRouteurs(pour r: Reseau) -> [String: String] {
        Dictionary(r.routeurs.map { ($0.instance, nom($0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// La resolution des cles de l'historique, gardee (`clesGardees`).
    private var clesHistorique: ClesHistorique {
        if let c = clesGardees { return c }
        let c = ClesHistorique(releves: historique)
        clesGardees = c
        constructionsCles += 1
        return c
    }

    /// La resolution des cles de l'historique et l'indice du releve du maillage `m`, le dernier de l'historique (en mode
    /// direct, `recevoir` l'y ajoute) ; nil si tous les routeurs de `m` ont une ExtMac (rien a resoudre) ou si son releve
    /// n'est pas le dernier (demo : pas d'historique).
    private func resolution(_ m: Maillage) -> (cles: ClesHistorique, releve: Int)? {
        guard m.routeurs.contains(where: { $0.extMac == nil }), let dernier = historique.last,
              dernier.date == m.date, dernier.partition == m.partition else { return nil }
        return (clesHistorique, historique.count - 1)
    }

    /// Cle d'un routeur du dernier maillage dans l'historique, celle de ses courbes (verification du 05/10) : son
    /// ExtMac ; sans elle, celle que `ClesHistorique` donne au releve du maillage dans l'historique ; sinon "rloc:XXXX".
    private func cleHistorique(routeur r: RouteurMaillage, _ resolution: (cles: ClesHistorique, releve: Int)?) -> String {
        if let x = r.extMac { return x }
        guard let resolution else { return String(format: "rloc:%04X", r.rloc16) }
        return resolution.cles.cle(releve: resolution.releve, routeur: r.id)
    }

    /// Cle d'un noeud du graphe dans l'historique : pour un routeur du dernier maillage, sa cle
    /// (`cleHistorique(routeur:_:)` : son ExtMac, ou celle que l'historique lui connait, sinon "rloc:XXXX") ;
    /// pour un enfant, son ExtMac dans le dernier maillage ; sinon le `xa` de l'annonce
    /// d'un routeur de bordure, ou l'hote d'un appareil (l'ExtMac d'un appareil Matter, d'apres
    /// `GrapheReseau.extMac(hote:)`, comme la piece d'un noeud) ; nil si le noeud n'en a pas.
    func cleHistorique(noeud id: String) -> String? { cleHistorique(noeud: id, resoudre: true) }

    /// `resoudre` faux : un routeur sans ExtMac garde "rloc:XXXX", sans resolution (`concernant`, qui ne compare
    /// que l'ExtMac d'un enfant).
    private func cleHistorique(noeud id: String, resoudre: Bool) -> String? {
        if let m = maillage, let n = rapprochement(m)?.noeud(id) {
            switch n.genre {
            case .routeur:
                if let r = m.routeur(Int(n.rloc16 >> 10)) { return cleHistorique(routeur: r, resoudre ? resolution(m) : nil) }
            case .enfant:
                if let x = m.enfants.first(where: { $0.rloc16 == n.rloc16 })?.extMac { return x }
            }
        }
        if let xa = instantane?.routeur(id)?.adresseEtendue { return xa }
        return GrapheReseau.extMac(hote: id)
    }

    /// Noms de noeuds de l'historique, par cle : leur nom dans le graphe, si le dernier maillage
    /// ou l'instantane les connait ; la cle sinon. Un routeur du dernier maillage se reconnait a la cle
    /// de ses courbes (`cleHistorique(routeur:_:)`). Un enfant vu deux fois prend l'entree que retient
    /// le rapprochement (`Maillage.enfantsIdentifies`, precision 26 du plan 4b). Le rapprochement
    /// et la resolution des cles ne sont faits qu'une fois.
    func nomsHistorique(_ cles: Set<String>) -> [String: String] {
        let affiche = maillage.flatMap(rapprochement)
        let enfants = maillage?.enfantsIdentifies ?? [:]
        var routeurs: [(routeur: RouteurMaillage, cle: String)] = []
        if let m = maillage {
            let r = resolution(m)
            routeurs = m.routeurs.map { ($0, cleHistorique(routeur: $0, r)) }
        }
        func nomDe(_ cle: String) -> String {
            if let affiche {
                if let r = routeurs.first(where: { $0.cle == cle })?.routeur,
                   let n = affiche.routeurs[r.id], let x = nomNoeud(n.id, maillage: affiche) {
                    return x
                }
                if let e = enfants[cle], let n = affiche.enfants[e.rloc16], let x = nomNoeud(n.id, maillage: affiche) {
                    return x
                }
            }
            if let r = instantane?.routeurs.first(where: { $0.adresseEtendue == cle }) { return nom(r) }
            if let a = (instantane?.appareils ?? []).first(where: { $0.id.uppercased() == cle }) { return nom(a) }
            return cle
        }
        return Dictionary(uniqueKeysWithValues: cles.map { ($0, nomDe($0)) })
    }

    /// Courbes d'un noeud du graphe sur une periode qui finit a `fin` ; nil sans cle.
    func courbes(noeud id: String, periode: PeriodeCourbes, fin: Date) -> CourbesNoeud? {
        cleHistorique(noeud: id).map {
            CourbesNoeud(cle: $0, releves: historique, cles: clesHistorique, periode: periode, fin: fin,
                         trel: instantane?.trel ?? [])
        }
    }

    /// Nom affiche d'un noeud du graphe : routeur de bordure, appareil, ou noeud que seule la sonde
    /// connait (« Routeur · 5000 », candidats d'un routeur de bordure non identifie) ; nil s'il
    /// n'est nulle part.
    func nomNoeud(_ id: String, maillage m: MaillageAffiche?) -> String? {
        if let r = instantane?.routeur(id) { return nom(r) }
        if let a = appareil(id) { return nom(a) }
        guard let n = m?.noeud(id) else { return nil }
        let noms = Dictionary((instantane?.routeurs ?? []).map { ($0.instance, nom($0)) }, uniquingKeysWith: { a, _ in a })
        return LibellesNoeuds.inconnu(n, noms: noms)
    }
    func accessoire(_ a: Appareil) -> AccessoireMaison? { noms.accessoire(de: a, fabriqueApple: fabriqueApple) }

    /// Le nom de l'appareil vient d'une association faite a la main (et non de son noeud).
    func associeALaMain(_ a: Appareil) -> Bool { noms.associeALaMain(a, fabriqueApple: fabriqueApple) }

    /// Accessoires de Maison a proposer a « Associer a un accessoire de Maison… » : ceux dont le noeud n'est annonce
    /// par aucun appareil de l'instantane (ni disparu) sur la fabrique d'Apple, et pas deja associes.
    var accessoiresOrphelins: [AccessoireMaison] {
        guard let i = instantane else { return [] }
        return noms.orphelins(appareils: i.appareils + i.appareilsIP + Array(suivi.disparus.values),
                              fabriqueApple: fabriqueApple)
    }

    /// Appareil par identifiant, present ou disparu.
    func appareil(_ id: String) -> Appareil? { instantane?.appareil(id) ?? suivi.disparus[id] }

    /// Appareils a dessiner pour un reseau : presents, puis disparus (a leur place). Un appareil qui n'annonce plus
    /// d'adresse et que la sonde a trouve (`verification`) est joignable.
    func appareilsAffiches(pour r: Reseau) -> [AppareilAffiche] {
        guard let i = instantane else { return [] }
        let premier = i.reseaux.first?.id == r.id
        let verifies = verifications(a: maintenant)
        func appartient(_ a: Appareil) -> Bool {
            if let x = a.idReseau { return x == r.id }
            // Partition qui porte aujourd'hui le prefixe de sa derniere adresse, sinon la derniere connue : l'appareil
            // va au reseau qui la contient, et a lui seul.
            if let p = suivi.partitionActuelle(de: a.id),
               let proprio = i.reseaux.first(where: { $0.partitions.contains { $0.id == p } }) {
                return proprio.id == r.id
            }
            return premier
        }
        // Un appareil verifie par la sonde est dans la partition qui porte aujourd'hui le prefixe de sa derniere
        // adresse.
        func partitionDerniere(_ a: Appareil, verifie: Bool) -> String? { partitionAffichee(a, verifie: verifie) }
        func affiche(_ a: Appareil, _ etat: EtatAffiche, verifie: Bool = false) -> AppareilAffiche {
            let maison = accessoire(a)
            return AppareilAffiche(id: IdNoeud(.thread, a.id), nom: nom(a), piece: maison?.piece,
                                   partition: a.partition ?? partitionDerniere(a, verifie: verifie), etat: etat,
                                   endormi: a.endormi, batterie: maison?.batterie, verifie: verifie)
        }
        var liste = i.appareils.filter(appartient).map { a in
            let etat: EtatAffiche = switch a.etat {
            case .joignable: .joignable
            case .partitionCoupee: .partitionCoupee
            case .sansAdresse: verifies[a.id] != nil ? .joignable : .sansAdresse
            case .inconnu: .inconnu
            }
            return affiche(a, etat, verifie: a.etat == .sansAdresse && verifies[a.id] != nil)
        }
        liste += suivi.disparus.values.filter(appartient).map {
            let verifie = verifies[$0.id] != nil
            return affiche($0, verifie ? .joignable : .disparu, verifie: verifie)
        }
        return liste
    }

    /// Fraicheur d'un maillage recu a `recu`.
    nonisolated static func fraicheur(_ recu: Date, maintenant: Date, tourneeEnCours: Bool = false) -> Fraicheur {
        let age = maintenant.timeIntervalSince(recu)
        if age > 15 * 60 { return .perime }
        return age <= 6 * 60 || tourneeEnCours ? .frais : .ancien
    }

    /// Fraicheur du maillage de la sonde a `maintenant` ; nil sans maillage. Un maillage relu au lancement n'est jamais
    /// perime : au-dela de 15 min il reste « ancien » jusqu'a la premiere tournee qui le remplace.
    func fraicheurMaillage(a maintenant: Date) -> Fraicheur? {
        let f = maillageRecu.map { Self.fraicheur($0, maintenant: maintenant, tourneeEnCours: tourneeEnCours) }
        return maillageRelu && f == .perime ? .ancien : f
    }

    /// Maillage de la sonde rapproche d'un reseau ; nil sans sonde ou s'il est perime.
    func maillageAffiche(pour r: Reseau) -> MaillageAffiche? {
        guard let m = maillage, let i = instantane, fraicheurMaillage(a: maintenant) != .perime else {
            return nil
        }
        return MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils + Array(suivi.disparus.values),
                               trel: i.trel, dernieresAdresses: dernieresAdressesVerifiees(a: maintenant))
    }

    /// Chiffres du reseau affiche.
    var resume: ResumeReseauThread? {
        guard let i = instantane, let r = reseau else { return nil }
        let affiches = appareilsAffiches(pour: r)
        return ResumeReseauThread(nom: r.nom, partitions: r.partitions.count, routeurs: r.routeurs.count,
                            appareils: affiches.count,
                            injoignables: affiches.filter { $0.etat != .joignable }.count
                                + i.appareilsIP.filter { $0.etat != .joignable }.count)
    }

    /// Derniere scission du reseau (pour le bandeau : "depuis" ou "constate a").
    func derniereScission(_ r: Reseau) -> Evenement? {
        coque?.evenements.last { $0.type == .reseauScinde && $0.reseau == r.id }
    }

    // MARK: - ModeleProtocole

    /// Noeuds et liens du reseau affiche, ceux de la fenetre : le graphe de `EntreeScene`.
    var graphe: GrapheReseau {
        reseau.map(graphe(pour:)) ?? GrapheReseau(noeuds: [])
    }

    func graphe(pour r: Reseau) -> GrapheReseau {
        GrapheReseau(reseau: r, appareils: appareilsAffiches(pour: r), maillage: maillageAffiche(pour: r))
    }

    var appareils: [AppareilAffiche] { reseau.map(appareilsAffiches(pour:)) ?? [] }

    var echelle: EchelleSignal { .dbm }

    /// Thread n'a pas de chemin vers un pont : sa carte est radio, ses liens ne suivent pas `ModeLiens`.
    var suitModeLiens: Bool { false }

    var classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) { classementThread }

    func miseEnAvant(de id: IdNoeud, graphe: GrapheReseau, chefs: Set<IdNoeud>, voisins: Bool) -> MiseEnAvant? {
        FocusThread.miseEnAvant(de: id, graphe: graphe, chefs: chefs, voisins: voisins)
    }

    var aHistorique: Bool { !historique.isEmpty }

    var resumeMenu: ResumeMenu? {
        resume.map { ResumeMenu(routeurs: $0.routeurs, appareils: $0.appareils, injoignables: $0.injoignables) }
    }

    /// Un reseau scinde est une alerte.
    var alerteReseau: Bool { instantane?.reseaux.contains(where: \.estScinde) == true }

    /// Un evenement concerne le noeud `id` s'il est de son protocole (sans protocole : Thread) et, par son ExtMac s'il la
    /// porte (l'id du sujet d'un enfant sans appareil change avec son parent), sinon par l'id de son sujet (la cle brute
    /// du noeud) : un noeud d'un autre protocole qui aurait la meme cle n'est pas concerne.
    func concernant(_ id: IdNoeud) -> (Evenement) -> Bool {
        guard id.protocole == Self.protocole else { return { _ in false } }
        let ext = cleHistorique(noeud: id.cle, resoudre: false)
        return { e in
            guard (e.protocole ?? .thread) == id.protocole else { return false }
            if let x = e.details["extMac"], let ext { return x == ext }
            return e.sujet?.id == id.cle
        }
    }
}
