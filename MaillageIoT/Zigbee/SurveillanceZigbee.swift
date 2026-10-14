import AppKit
import MaillageCoeur
import Observation
import ProtocoleZigbee
import os

/// Chiffres du reseau Zigbee affiche, pour la barre des menus.
struct ResumeReseauZigbee: Equatable {
    /// Routeurs du maillage, le coordinateur compris.
    var routeurs: Int
    /// Appareils du pont, et noeuds finaux du maillage qu'il ne connait pas.
    var appareils: Int
    /// Appareils qui ne sont pas joignables (disparus, injoignables).
    var injoignables: Int
}

/// Le dernier maillage de la sonde, tel qu'il est garde sur disque (`dernier-maillage.json`) pour le lancement suivant.
private struct MaillageGarde: Codable {
    var maillage: MaillageZigbee
    /// Reception du maillage (`SurveillanceZigbee.maillageRecu`).
    var recu: Date
    var incomplet: Bool
}

/// Le modele de Zigbee, un des modeles de protocole de la coque `Surveillance` (comme `SurveillanceThread`) : maillages de
/// la sonde -> suivi, historique ; noms du pont et de Maison ; etat lu par les vues, avec ses fichiers sous `Zigbee/` et
/// ses seuils de fraicheur (16 et 45 min). Le pont le nourrit par `nomsPont` (`NomsPont.surNoms`) et `lecturePont`, la
/// coque par `recevoirReleveMaison` (le releve du Passeur, aussi donne a Thread) : `noms.maison` est leur fusion
/// (`FusionNoms`) ; la sonde, a chaque tournee, par `recevoir`. Le journal, les alertes, les surnoms et la veille sont
/// ceux de la coque (`coque`) : les evenements de Zigbee y vont par `Surveillance.ajouter(_:de:)`, qui les marque du
/// protocole Zigbee.
@MainActor
@Observable
final class SurveillanceZigbee: ModeleProtocole {
    typealias Fraicheur = Surveillance.Fraicheur

    let mode: Surveillance.Mode
    /// Ce modele rejoue la demo de Zigbee (le faux reseau Hue) ; faux : en demo, un modele muet (la demo n'a qu'un
    /// reseau a la fois, la demo combinee est a l'etape 3b).
    let rejoueLaDemo: Bool
    var noms: ResolveurNomsZigbee
    /// Les noms lus sur le pont Hue ; nil sans pont lu (le pont oublie : le suivi des connexions repart de zero).
    var nomsPont: NomsZigbee? {
        didSet {
            fusionner()
            if nomsPont == nil { suiviConnexions = SuiviConnexions() }
        }
    }
    /// Le dernier releve de Maison reussi, par le Passeur ; nil sans releve.
    var releveMaison: NomsMaison? {
        didSet { fusionner() }
    }
    /// Combien d'appareils du pont Maison nomme ; nil sans pont ou sans releve de Maison.
    private(set) var bilanFusion: FusionNoms.Bilan?
    /// Dernier maillage de la sonde ; nil sans sonde.
    private(set) var maillage: MaillageZigbee?
    /// Reception du dernier maillage, a la fin de sa tournee : son age se compte depuis (le maillage, lui, est date du
    /// debut de sa tournee).
    private(set) var maillageRecu: Date?
    /// La tournee qui a produit le maillage affiche a reporte des routes : une passe complementaire les lira
    /// (`SondeMaillageZigbee.passeComplementaire`). Relu au lancement avec le maillage garde.
    private(set) var maillageIncomplet = false
    /// Le maillage affiche est celui relu au lancement (`chargerMaillageGarde`), pas encore remplace par une tournee :
    /// il se montre quel que soit son age, avec la pastille « ancien » (la peremption de 45 min ne vaut que pour un
    /// maillage recu pendant que l'app tourne).
    private(set) var maillageRelu = false
    /// Une tournee de la sonde est en cours (`SondeMaillageZigbee.surTournee`) : le maillage affiche attend le suivant,
    /// il n'est pas « ancien ».
    var tourneeEnCours = false
    /// Historique de la sonde : les releves des 30 derniers jours, du plus ancien au plus recent ; toujours vide en
    /// demo, sauf dans ses captures (`historiqueDeCapture`).
    private(set) var historique: [ReleveMaillageZigbee] = []

    /// La coque qui porte le journal, les alertes et les surnoms ; posee par `Surveillance.init`.
    @ObservationIgnored weak var coque: Surveillance?
    /// Le dernier maillage garde (`MaillageGarde`) : mode direct avec un dossier ; nil : nulle part (demo, tests).
    @ObservationIgnored private let fichierMaillage: URL?
    /// Les appariements de Maison memorises (`MemoireAppariements`) : mode direct avec un dossier ; nil : nulle part.
    @ObservationIgnored private let fichierAppariements: URL?
    @ObservationIgnored private var appariements = MemoireAppariements()
    @ObservationIgnored private var suiviMaillage = SuiviMaillageZigbee()
    /// L'etat de connexion de chaque appareil selon le pont, d'une lecture a l'autre : « disparu », « revenu ».
    @ObservationIgnored private var suiviConnexions = SuiviConnexions()
    /// Le dernier parent connu de chaque appareil final (mode direct seulement) : un appareil final absent des dernieres
    /// tables garde son parent d'avant 24 h, en pointilles (`ParentsConnus`).
    @ObservationIgnored private var parentsConnus = ParentsConnus()
    /// Historique sur disque : mode direct avec un dossier ; nil : nulle part (demo, tests).
    @ObservationIgnored private let fichiersHistorique: HistoriqueFichiersZigbee?

    /// Fraicheur du maillage : frais jusqu'a 16 min (une tournee toutes les 15 min), et tant qu'une tournee est en cours ;
    /// ancien ensuite (la sonde ne repond plus) jusqu'a 45 min ; perime au-dela, tournee ou non (le graphe n'a plus de
    /// liens).
    nonisolated static let ageFrais: TimeInterval = 16 * 60
    nonisolated static let agePerime: TimeInterval = 45 * 60
    /// Le protocole de ce modele : ses evenements le portent (`ajouter`), ses surnoms sont sous ce protocole.
    nonisolated static let protocole = Protocole.zigbee
    var protocole: Protocole { Self.protocole }

    /// `dossier` : la racine des donnees de l'app ; les fichiers de Zigbee (dernier maillage, appariements de Maison,
    /// historique de la sonde) vont sous `Zigbee/` (nil : nulle part) ; `surnoms` : ceux de `surnoms.json`, de tous les
    /// protocoles (le resolveur de noms ne garde que ceux de Zigbee) ; `rejoueLaDemo` : en demo, le faux reseau Hue.
    init(mode: Surveillance.Mode, dossier: URL?, surnoms: [IdNoeud: String], rejoueLaDemo: Bool = true) {
        self.mode = mode
        self.rejoueLaDemo = rejoueLaDemo
        switch mode {
        case .direct:
            fichierMaillage = dossier.map { Surveillance.dossierZigbee($0).appendingPathComponent("dernier-maillage.json") }
            fichierAppariements = dossier.map { MemoireAppariements.fichier(dossier: Surveillance.dossierZigbee($0)) }
            appariements = fichierAppariements.map(MemoireAppariements.lire) ?? MemoireAppariements()
            noms = ResolveurNomsZigbee(surnoms: Surnoms.cles(de: surnoms, protocole: Self.protocole))
            fichiersHistorique = dossier.map { HistoriqueFichiersZigbee(dossier: Surveillance.dossierZigbee($0)) }
        case .demo:
            fichierMaillage = nil
            fichierAppariements = nil
            fichiersHistorique = nil
            if rejoueLaDemo {
                nomsPont = NomsDemo.maisonPont
                releveMaison = NomsDemo.releveMaison
                let f = FusionNoms.fusionner(pont: NomsDemo.maisonPont, maison: NomsDemo.releveMaison)
                noms = ResolveurNomsZigbee(maison: f.noms)
                bilanFusion = f.bilan
            } else {
                noms = ResolveurNomsZigbee()
            }
        }
    }

    /// Les captures de la demo montrent les courbes de la fiche (etape 5) : l'historique invente de la demo
    /// (`MaillageDemoZigbee.historique`). En demo seulement, et seulement pour elles ; rien sur disque.
    func historiqueDeCapture(_ releves: [ReleveMaillageZigbee]) {
        guard mode == .demo else { return }
        historique = releves
    }

    /// Une lecture reussie du pont (`NomsPont.surLecture`, apres `nomsPont`) : les appareils passes de joignables a
    /// injoignables, ou revenus, d'apres l'etat de connexion que le pont donne, vont au journal (et aux notifications :
    /// les pertes groupees). La premiere lecture est un etat initial ; le cache relu au lancement n'arrive pas ici.
    func lecturePont(_ n: NomsZigbee) {
        ajouter(suiviConnexions.integrer(n) { [noms, maillage] ieee in
            Self.nom(ieee, noms: noms, sonde: maillage?.sonde)
        })
    }

    /// Les noms du pont, nommes par Maison (`FusionNoms`) : a chaque nouveau releve, de l'un ou de l'autre.
    private func fusionner() {
        let f = FusionNoms.fusionner(pont: nomsPont, maison: releveMaison, memoire: appariements)
        noms.maison = f.noms
        bilanFusion = f.bilan
        if f.memoire != appariements {
            appariements = f.memoire
            if let fichierAppariements { try? appariements.ecrire(dans: fichierAppariements) }
        }
    }

    /// Le releve de Maison donne par la coque (le meme que celui de Thread) : fusionne avec les noms du pont.
    func recevoirReleveMaison(_ releve: NomsMaison?) {
        releveMaison = releve
    }

    func demarrer() {
        switch mode {
        case .demo:
            guard rejoueLaDemo else { return }
            recevoir(MaillageDemoZigbee.maillageAvant, a: MaillageDemoZigbee.debut)
            recevoir(MaillageDemoZigbee.maillage, a: MaillageDemoZigbee.fin)
        case .direct:
            chargerMaillageGarde()
            Task { [weak self] in await self?.chargerHistorique() }
        }
    }

    func arreter() {}

    /// Le Mac se reveille : la sonde et le pont ont leurs minuteries, rien a faire ici.
    func auReveil() {}

    /// Verse des evenements au journal de la coque (qui les marque du protocole Zigbee, les garde et notifie). Un
    /// modele n'est jamais utilise apres la mort de sa coque : en Debug, des evenements perdus sont une erreur.
    private func ajouter(_ evenements: [Evenement]) {
        assert(coque != nil || evenements.isEmpty, "SurveillanceZigbee sans coque : des evenements seraient perdus")
        coque?.ajouter(evenements, de: Self.protocole)
    }

    /// Reprend le dernier maillage garde, avant la premiere tournee de la sonde : son age se compte depuis sa reception
    /// (la pastille « ancien » le dit). Fichier absent ou illisible : rien. Un maillage deja recu l'emporte.
    func chargerMaillageGarde() {
        guard maillage == nil, let fichierMaillage,
              let donnees = try? Data(contentsOf: fichierMaillage),
              let garde = try? CodageJSON.decodeur().decode(MaillageGarde.self, from: donnees) else { return }
        maillage = garde.maillage
        maillageRecu = garde.recu
        maillageIncomplet = garde.incomplet
        maillageRelu = true
    }

    /// Garde le maillage recu sur disque, d'un bloc. Un echec est consigne dans le journal du Mac ; le maillage reste
    /// en memoire.
    private func garderMaillage(_ m: MaillageZigbee, recu: Date, incomplet: Bool) {
        guard let fichierMaillage else { return }
        do {
            try FileManager.default.createDirectory(at: fichierMaillage.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let garde = MaillageGarde(maillage: m, recu: recu, incomplet: incomplet)
            try CodageJSON.encodeur().encode(garde).write(to: fichierMaillage, options: .atomic)
        } catch {
            Surveillance.journalMac.error("dernier maillage Zigbee non ecrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Nouveau maillage de la sonde, recu a `date` (fin de sa tournee) : ses evenements vont au journal ; en mode
    /// direct, son releve va a l'historique, en memoire et, avec un dossier, sur disque. Un echec d'ecriture est
    /// consigne dans le journal du Mac ; le releve reste en memoire. Le maillage est aussi garde sur disque, pour le
    /// prochain lancement. `incomplet` : la tournee qui l'a produit a reporte des routes (une passe complementaire les
    /// lira).
    func recevoir(_ recu: MaillageZigbee, a date: Date, incomplet: Bool = false) {
        // Les parents lus d'abord (ils prennent la place de ceux d'avant), puis ceux d'avant pour les appareils finaux que
        // les dernieres tables n'ont plus (mode direct seulement : la demo n'a pas d'avant).
        if mode == .direct { parentsConnus.retenir(recu) }
        let m = mode == .direct ? parentsConnus.completer(recu) : recu
        maillage = m
        maillageRecu = date
        maillageIncomplet = incomplet
        maillageRelu = false
        ajouter(suiviMaillage.integrer(m) { [noms] ieee in Self.nom(ieee, noms: noms, sonde: m.sonde) })
        guard mode == .direct else { return }
        let r = ReleveMaillageZigbee(m)
        let limite = date.addingTimeInterval(-Surveillance.dureeHistorique)
        historique = historique.filter { $0.date >= limite } + [r]
        coque?.purgerSiNouveauMois(date)
        garderMaillage(m, recu: date, incomplet: incomplet)
        guard let f = fichiersHistorique else { return }
        do {
            try f.ajouter(r)
        } catch {
            Surveillance.journalMac.error("releve de l'historique Zigbee non ecrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purge l'historique sur disque (mois finis depuis plus de 90 jours), a la demande de la coque quand le mois change.
    /// Un echec est ignore : la purge reviendra au lancement suivant. Sans dossier (demo, tests) : rien.
    func purgerHistorique(maintenant: Date) {
        _ = try? fichiersHistorique?.purger(maintenant: maintenant)
    }

    /// Relit les 30 derniers jours de l'historique, hors de l'acteur principal, apres avoir purge les mois finis depuis
    /// plus de 90 jours ; les releves recus entre-temps restent. Les releves des dernieres 24 h redonnent le dernier parent
    /// connu des appareils finaux (`ParentsConnus`). `maintenant` : l'heure du lancement (injectee par les tests). Sans
    /// dossier (demo, tests) : rien.
    func chargerHistorique(maintenant: Date = Date()) async {
        guard let f = fichiersHistorique else { return }
        coque?.noterPurge(a: maintenant)
        let debut = maintenant.addingTimeInterval(-Surveillance.dureeHistorique)
        do {
            let lus = try await Task.detached(priority: .utility) {
                // Une purge qui echoue n'empeche pas la lecture.
                _ = try? f.purger(maintenant: maintenant)
                return try f.lire(depuis: debut)
            }.value
            // Les dates relues sont tronquees a la milliseconde (codage) : un releve recu pendant la lecture, ecrit
            // puis relu, garde jusqu'a 1 ms de moins que sa copie en memoire. Il n'est pas repris.
            let premier = (historique.first?.date ?? .distantFuture).addingTimeInterval(-0.001)
            historique = lus.filter { $0.date < premier } + historique
            // Le dernier parent connu des appareils finaux, retrouve dans les releves des dernieres 24 h.
            for r in lus.filter({ $0.date >= maintenant.addingTimeInterval(-ParentsConnus.duree) }) {
                parentsConnus.retenir(r)
            }
        } catch {
            Surveillance.journalMac.error("historique Zigbee illisible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sonde oubliee (`SondeMaillageZigbee.surOubli`) : son maillage part tout de suite, sans attendre qu'il soit perime.
    /// Son suivi aussi : le maillage suivant (une autre sonde, plus tard) est un point de depart, sans evenement.
    /// L'historique reste : il parle du reseau, pas de la sonde.
    func oublierMaillage() {
        maillage = nil
        maillageRecu = nil
        maillageIncomplet = false
        maillageRelu = false
        if let fichierMaillage { try? FileManager.default.removeItem(at: fichierMaillage) }
        suiviMaillage = SuiviMaillageZigbee()
        parentsConnus = ParentsConnus()
    }

    /// Veille du Mac (appele au reveil par la coque) : ses evenements vont au journal.
    func noterVeille(_ intervalle: DateInterval) -> [Evenement] {
        suiviMaillage.noterVeille(intervalle)
    }

    /// Applique (ou retire) le surnom d'un noeud Zigbee au resolveur de noms ; `cle` : la cle brute du noeud.
    func appliquerSurnom(_ surnom: String?, cle: String) {
        noms.surnoms[cle] = surnom
    }

    /// Dernier maillage en JSON (Reglages › Diagnostic, « Enregistrer une capture… ») ; nil sans maillage.
    func captureJSON() throws -> Data? {
        try maillage.map { try CodageJSON.encodeur(lisible: true).encode($0) }
    }

    // MARK: - Pour les vues

    /// Reference des durees a l'heure `horloge` (celle de la fenetre du graphe, que sa `TimelineView` avance chaque
    /// minute) : cette heure, ou la fin de la demo en demo (`.distantPast` pour un modele muet : la coque prend le plus
    /// tard des modeles).
    func maintenant(a horloge: Date) -> Date {
        guard mode == .demo else { return horloge }
        return rejoueLaDemo ? MaillageDemoZigbee.fin : .distantPast
    }

    /// Nom affiche d'un noeud par son adresse longue : surnom, nom sur le pont, « Sonde » pour la sonde, sinon
    /// l'adresse longue ; « Nœud 1A2B » pour un noeud sans adresse longue (cle provisoire), jamais renomme.
    static func nom(_ ieee: String, noms: ResolveurNomsZigbee, sonde: String?) -> String {
        guard NoeudZigbee.cleConnue(ieee) else {
            return String(localized: "Nœud \(String(ieee.drop { $0 == "~" }))")
        }
        if let n = noms.nomConnu(ieee: ieee) { return n }
        if ieee == sonde { return String(localized: "Sonde") }
        return ieee
    }

    /// Nom affiche d'un noeud du graphe (son adresse longue).
    func nom(_ ieee: String) -> String { Self.nom(ieee, noms: noms, sonde: maillage?.sonde) }

    /// L'appareil du pont d'un noeud ; nil si le pont ne le connait pas.
    func accessoire(_ ieee: String) -> AppareilPont? { noms.accessoire(ieee: ieee) }

    /// Les appareils du pont qui ont une adresse longue, a dessiner (`etat(_:presents:)`). Endormi : un appareil final
    /// dont la table de son parent dit le recepteur eteint au repos (`ecoute` faux) ; sans maillage, rien n'est dit.
    var appareilsAffiches: [AppareilAffiche] {
        let m = maillageAffiche
        let presents = m.map { Set($0.noeuds.map(\.ieee)) }
        return (noms.maison?.accessoires ?? []).compactMap { a in
            guard let ieee = a.ieee?.uppercased() else { return nil }
            let etat = Self.etat(a, presents: presents)
            return AppareilAffiche(id: IdNoeud(.zigbee, ieee), nom: nom(ieee), piece: a.piece, etat: etat,
                                   endormi: m?.noeud(ieee)?.endormi == true, batterie: a.batterie)
        }
    }

    /// Etat affiche d'un appareil du pont. L'etat de connexion que donne le pont l'emporte : `connected`, joignable ;
    /// `connectivity_issue`, `disconnected`, `unidirectional_incoming`, injoignable. Sans cet etat (demo, etat inconnu
    /// de l'app) : joignable s'il est dans le maillage, disparu sinon, inconnu sans maillage (`presents` nil).
    nonisolated static func etat(_ a: AppareilPont, presents: Set<String>?) -> EtatAffiche {
        switch a.connexion {
        case .connecte: return .joignable
        case .deconnecte, .problemeConnexion, .entrantSeul: return .injoignable
        case .inconnue, nil: break
        }
        guard let presents, let ieee = a.ieee?.uppercased() else { return .inconnu }
        return presents.contains(ieee) ? .joignable : .disparu
    }

    /// Fraicheur d'un maillage recu a `recu`.
    nonisolated static func fraicheur(_ recu: Date, maintenant: Date, tourneeEnCours: Bool = false) -> Fraicheur {
        let age = maintenant.timeIntervalSince(recu)
        if age > agePerime { return .perime }
        return age <= ageFrais || tourneeEnCours ? .frais : .ancien
    }

    /// Fraicheur du maillage de la sonde a `maintenant` ; nil sans maillage. Un maillage relu au lancement n'est jamais
    /// perime : au-dela de 45 min il reste « ancien » jusqu'a la premiere tournee qui le remplace.
    func fraicheurMaillage(a maintenant: Date) -> Fraicheur? {
        let f = maillageRecu.map { Self.fraicheur($0, maintenant: maintenant, tourneeEnCours: tourneeEnCours) }
        return maillageRelu && f == .perime ? .ancien : f
    }

    /// Le maillage a montrer ; nil sans sonde ou s'il est perime (sauf celui relu au lancement).
    var maillageAffiche: MaillageZigbee? {
        guard let m = maillage, fraicheurMaillage(a: maintenant) != .perime else { return nil }
        return m
    }

    /// Il y a un reseau a dessiner : un maillage, ou des appareils du pont.
    var aUnReseau: Bool { maillageAffiche != nil || !appareilsAffiches.isEmpty }

    /// Chiffres du reseau affiche ; nil sans rien a montrer.
    var resume: ResumeReseauZigbee? {
        guard aUnReseau else { return nil }
        let affiches = appareilsAffiches
        let m = maillageAffiche
        let connus = Set(affiches.map(\.id.cle))
        let routeurs = m?.noeuds.filter(\.route).count ?? 0
        let finauxInconnus = m?.noeuds.filter { !$0.route && !connus.contains($0.ieee) }.count ?? 0
        let appareilsRoutant = Set(m?.noeuds.filter(\.route).map(\.ieee) ?? [])
        return ResumeReseauZigbee(routeurs: routeurs,
                                  appareils: affiches.filter { !appareilsRoutant.contains($0.id.cle) }.count
                                      + finauxInconnus,
                                  injoignables: affiches.filter { $0.etat == .disparu || $0.etat == .injoignable }.count)
    }

    /// Cle d'un noeud du graphe dans l'historique : son adresse longue, son id ; nil pour une cle provisoire.
    func cleHistorique(noeud id: String) -> String? { NoeudZigbee.cleConnue(id) ? id : nil }

    // MARK: - ModeleProtocole

    /// Noeuds et liens du reseau affiche : le graphe de la scene.
    var graphe: GrapheReseau { GrapheReseau(maillage: maillageAffiche, appareils: appareilsAffiches) }

    var appareils: [AppareilAffiche] { appareilsAffiches }

    var echelle: EchelleSignal { .lqi }

    /// Zigbee montre les chemins vers le pont ou tous les liens radio (`ModeLiens`), et ses voisins entendus a la selection.
    var suitModeLiens: Bool { true }

    var classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) { ScenePieces.classementZigbee }

    /// Le focus de Zigbee lit `voisins` (les voisins entendus du noeud choisi) et ignore `chefs` (le coordinateur n'a pas
    /// de regle propre).
    func miseEnAvant(de id: IdNoeud, graphe: GrapheReseau, chefs: Set<IdNoeud>, voisins: Bool) -> MiseEnAvant? {
        guard id.protocole == Self.protocole else { return nil }
        return FocusZigbee.miseEnAvant(de: id, graphe: graphe, voisins: voisins)
    }

    var aHistorique: Bool { !historique.isEmpty }

    /// Noms de noeuds de l'historique, par adresse longue.
    func nomsHistorique(_ cles: Set<String>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: cles.map { ($0, nom($0)) })
    }

    /// Courbes d'un noeud du graphe sur une periode qui finit a `fin` ; nil sans cle.
    func courbes(noeud id: String, periode: PeriodeCourbes, fin: Date) -> CourbesNoeud? {
        cleHistorique(noeud: id).map { CourbesNoeud(zigbee: $0, releves: historique, periode: periode, fin: fin) }
    }

    var resumeMenu: ResumeMenu? {
        resume.map { ResumeMenu(routeurs: $0.routeurs, appareils: $0.appareils, injoignables: $0.injoignables) }
    }

    /// Le pont et la sonde ne disent aucun etat de reseau qui soit une alerte en soi : seuls les evenements graves du
    /// journal en font une.
    var alerteReseau: Bool { false }

    /// Un evenement concerne le noeud `id` s'il est de son protocole (sans protocole : Thread) et si son sujet est ce noeud
    /// (`Sujet.id`, la cle brute) ou s'il porte son adresse longue (`details["ieee"]`) : un noeud d'un autre protocole
    /// qui aurait la meme cle n'est pas concerne.
    func concernant(_ id: IdNoeud) -> (Evenement) -> Bool {
        guard id.protocole == Self.protocole else { return { _ in false } }
        return { e in
            (e.protocole ?? .thread) == id.protocole && (e.sujet?.id == id.cle || e.details["ieee"] == id.cle)
        }
    }
}
