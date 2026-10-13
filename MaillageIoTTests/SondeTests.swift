import Foundation
import MaillageCoeur
import Observation
import Synchronization
import Testing
@testable import MaillageIoT

/// Canal rejoue : chaque commande envoyee produit les lignes que `repondre` donne.
final class CanalRejoue: CanalSonde {
    private struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var envoyes: [String] = []
    }

    private let etat = Mutex(Etat())
    let repondre: @Sendable (String) -> [String]
    /// Fin du flux differee apres `fermer`, comme la liaison serie qui ferme le port sur sa file :
    /// d'ici la, les commandes ont encore leurs reponses.
    let fermetureDifferee: Duration?

    init(fermetureDifferee: Duration? = nil, repondre: @escaping @Sendable (String) -> [String]) {
        self.fermetureDifferee = fermetureDifferee
        self.repondre = repondre
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        return flux
    }

    func envoyer(_ ligne: String) {
        let reponses = repondre(ligne)
        etat.withLock { e in
            e.envoyes.append(ligne)
            for r in reponses { e.suite?.yield(Data(r.utf8)) }
        }
    }

    /// Lignes spontanees de la sonde.
    func emettre(_ lignes: [String]) {
        etat.withLock { e in
            for r in lignes { e.suite?.yield(Data(r.utf8)) }
        }
    }

    func fermer() {
        guard let d = fermetureDifferee else {
            etat.withLock { $0.suite?.finish() }
            return
        }
        Task { [self] in
            try? await Task.sleep(for: d)
            etat.withLock { $0.suite?.finish() }
        }
    }

    var envoyes: [String] { etat.withLock { $0.envoyes } }

    static let bonjour = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.0","mac":"A00000000001","appairee":true,"code":null,"qr":null}"#
    /// bonjour du firmware 1.0.1 : nom, code et QR code, meme appairee (valeurs inventees).
    static let bonjourNomme = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.1","nom":"SONDE-01","mac":"A00000000001","appairee":true,"code":"12345678901","qr":"MT:ABCDEFGHIJ0123456789"}"#
    static let etatDetache = #"{"v":1,"t":"etat","role":"detached","rloc16":"FFFE","mode":"rn","parent":null,"partition":null,"chef":null,"canal":25,"prefixeMaille":null,"xp":null,"suspendue":false}"#

    static func diag(_ id: Int, _ cible: String, tlv: String) -> String {
        #"{"v":1,"t":"diag","id":\#(id),"cible":"\#(cible)","ms":40,"ok":true,"code":"2.04","tlv":"\#(tlv)"}"#
    }

    /// Ligne `annonces` (firmware 1.1.0) : un routeur entendu, sa Route64 brute (ExtMac inventee) ; `suite` :
    /// d'autres lignes suivent.
    static func annonce(_ rloc16: String, route64: String?, age: Int = 5, suite: Bool) -> String {
        #"{"v":1,"t":"annonces","rloc16":"\#(rloc16)","ext":"E0000000000000\#(rloc16.prefix(2))","partition":"0000000A","route64":\#(route64.map { "\"\($0)\"" } ?? "null"),"seq":null,"rssi":-70,"rssi_min":-75,"rssi_max":-65,"nb":3,"age_s":\#(age),"suite":\#(suite)}"#
    }

    static let annoncesVides = #"{"v":1,"t":"annonces","vide":true}"#

    /// Reponse a `resoudre` (firmware 1.1.0) : le RLOC16 trouve et, s'il est donne, le ML-EID (32 hexa).
    static func resolution(_ id: Int, _ cible: String, rloc16: String, mleid: String? = nil,
                           repondu: Bool = true) -> String {
        #"{"v":1,"t":"resoudre","id":\#(id),"cible":"\#(cible)","ok":true,"ms":120,"rloc16":"\#(rloc16)","repondu":\#(repondu),"mleid":\#(mleid.map { "\"\($0)\"" } ?? "null")}"#
    }

    /// Ligne `routeurs` (firmware 1.0.2) : chaque routeur par son RLOC16, avec son ExtMac s'il
    /// est entendu (lien etabli, qualites 3) ; `suite` : d'autres lignes suivent.
    static func routeurs(_ table: [(rloc16: String, ext: String?)], suite: Bool) -> String {
        let liste = table.map { r in
            let id = (UInt16(r.rloc16, radix: 16) ?? 0) >> 10
            let lq = r.ext == nil ? 0 : 3
            return #"{"id":\#(id),"rloc16":"\#(r.rloc16)","ext":\#(r.ext.map { "\"\($0)\"" } ?? "null"),"lqIn":\#(lq),"lqOut":\#(lq),"age":4,"lien":\#(r.ext != nil)}"#
        }
        return #"{"v":1,"t":"routeurs","liste":[\#(liste.joined(separator: ","))],"suite":\#(suite)}"#
    }

    /// Ligne `voisins` : chaque routeur par son RLOC16 et son signal (ExtMac inventee).
    static func voisins(_ liste: [(rloc16: String, rssi: Int)]) -> String {
        let l = liste.map { #"{"rloc16":"\#($0.rloc16)","ext":"E0000000000000\#($0.rloc16.prefix(2))","rssi":\#($0.rssi),"lqi":3,"routeur":true}"# }
        return #"{"v":1,"t":"voisins","liste":[\#(l.joined(separator: ","))]}"#
    }

    /// Sonde attachee (valeurs inventees) : enfant 0001 du routeur 0, qui est le chef.
    static let etatAttache = #"{"v":1,"t":"etat","role":"child","rloc16":"0001","mode":"rn","parent":null,"partition":"0000000A","chef":0,"canal":25,"prefixeMaille":"FD00000000000000","xp":null,"suspendue":false}"#

    /// Reseau d'un seul routeur, le chef 0, qui ne donne que sa Route64 : la tournee
    /// aboutit (maillage d'un routeur muet, sans enfant). `diag <cible> <tlv> <id> <ms>` :
    /// la Route64 a la demande de la liste des routeurs, `delai` a toute autre requete ;
    /// `routeurs` : le chef seul, parent de la sonde, donc sans ExtMac ; `voisins` : aucun ;
    /// `annonces` (firmware 1.1.0) : aucun routeur entendu.
    static func reseauMinimal(_ ligne: String) -> [String] {
        switch ligne {
        case "bonjour\n": return [bonjour]
        case "etat\n": return [etatAttache]
        case "routeurs\n": return [routeurs([("0000", nil)], suite: false)]
        case "voisins\n": return [voisins([])]
        case "annonces\n": return [annoncesVides]
        default: break
        }
        let mots = ligne.trimmingCharacters(in: .newlines).split(separator: " ").map(String.init)
        guard mots.count >= 4, mots[0] == "diag", let id = Int(mots[3]) else { return [] }
        if mots[1] == "0000" && mots[2] == "5,6" { return [diag(id, "0000", tlv: "050A01800000000000000001")] }
        return [#"{"v":1,"t":"diag","id":\#(id),"cible":"\#(mots[1])","ok":false,"erreur":"delai"}"#]
    }
}

/// Canal d'un port qui ne s'ouvre pas (tenu par une autre app, retire entre-temps).
struct CanalEnPanne: CanalSonde {
    struct Panne: Error {}

    func ouvrir() throws -> AsyncStream<Data> { throw Panne() }
    func envoyer(_ ligne: String) {}
    func fermer() {}
}

/// Horloge des tests, avancee a la main (ou par un canal, pendant une tournee).
final class HorlogeFactice: Sendable {
    private let t: Mutex<Date>

    init(_ debut: Date) {
        t = Mutex(debut)
    }

    var maintenant: Date { t.withLock { $0 } }

    func avancer(_ secondes: TimeInterval) {
        t.withLock { $0 += secondes }
    }
}

/// Journal commun a des canaux de test ; on peut y attendre une ligne.
final class JournalCanaux: Sendable {
    private struct Etat {
        var lignes: [String] = []
        var attentes: [(ligne: String, suite: CheckedContinuation<Void, Never>)] = []
    }

    private let etat = Mutex(Etat())

    func noter(_ ligne: String) {
        let prets = etat.withLock { e in
            e.lignes.append(ligne)
            let prets = e.attentes.filter { $0.ligne == ligne }.map(\.suite)
            e.attentes.removeAll { $0.ligne == ligne }
            return prets
        }
        for p in prets { p.resume() }
    }

    /// Rend la main une fois `ligne` notee (tout de suite si elle l'est deja).
    func attendre(_ ligne: String) async {
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let deja = etat.withLock { e in
                guard !e.lignes.contains(ligne) else { return true }
                e.attentes.append((ligne, suite))
                return false
            }
            if deja { suite.resume() }
        }
    }

    var lignes: [String] { etat.withLock { $0.lignes } }

    /// Ouvertures, fermetures et fins de flux, sans les commandes.
    var cycle: [String] {
        lignes.filter { l in ["ouvrir", "fermer", "fin"].contains(l.split(separator: " ").first.map(String.init)) }
    }
}

/// Canal de test de la connexion : note au journal ses ouvertures, sa fermeture,
/// la fin de son flux (le port vraiment ferme) et les commandes recues. Il peut
/// retenir la reponse a `bonjour`, et finir son flux en differe, comme la liaison
/// serie qui ferme le port sur sa file.
final class CanalTemoin: CanalSonde {
    let nom: String
    let journal: JournalCanaux
    let retenirBonjour: Bool
    let fermetureDifferee: Duration?
    private let suite = Mutex<AsyncStream<Data>.Continuation?>(nil)

    init(_ nom: String, journal: JournalCanaux, retenirBonjour: Bool = false, fermetureDifferee: Duration? = nil) {
        self.nom = nom
        self.journal = journal
        self.retenirBonjour = retenirBonjour
        self.fermetureDifferee = fermetureDifferee
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (flux, s) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        suite.withLock { $0 = s }
        journal.noter("ouvrir \(nom)")
        return flux
    }

    func envoyer(_ ligne: String) {
        let commande = ligne.trimmingCharacters(in: .newlines)
        journal.noter("\(commande) \(nom)")
        switch commande {
        case "bonjour" where !retenirBonjour: repondre(CanalRejoue.bonjour)
        case "etat": repondre(CanalRejoue.etatDetache)
        default: break
        }
    }

    /// La reponse retenue a `bonjour` arrive enfin.
    func libererBonjour() {
        repondre(CanalRejoue.bonjour)
    }

    private func repondre(_ l: String) {
        suite.withLock { _ = $0?.yield(Data(l.utf8)) }
    }

    /// Une seule fermeture effective ; rien a fermer si le canal n'a pas ete ouvert.
    func fermer() {
        guard let s = suite.withLock({ s in
            defer { s = nil }
            return s
        }) else { return }
        journal.noter("fermer \(nom)")
        guard let d = fermetureDifferee else {
            journal.noter("fin \(nom)")
            s.finish()
            return
        }
        let journal = journal, nom = nom
        Task {
            try? await Task.sleep(for: d)
            journal.noter("fin \(nom)")
            s.finish()
        }
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@Suite("Sonde USB : commandes et reponses", .timeLimit(.minutes(1)))
struct SondeUSBTests {
    /// bonjour et etat, dans l'ordre.
    @Test func bonjourEtat() async throws {
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjour] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let b = try await s.bonjour()
        #expect(b.estSonde && b.version == "1.0.0")
        let e = try await s.etat()
        #expect(e.role == "detached" && !e.estAttachee)
        #expect(canal.envoyes == ["bonjour\n", "etat\n"])
    }

    /// Deux diag en vol : la seconde reponse arrive avant la premiere, chacune va a son id.
    @Test func diagDansLeDesordre() async throws {
        let canal = CanalRejoue { l in
            // La reponse a la premiere requete ne part qu'avec la seconde.
            l.hasPrefix("diag 0400") ? [CanalRejoue.diag(2, "0400", tlv: "01020400"), CanalRejoue.diag(1, "5000", tlv: "01025000")] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        async let a = s.diag(0x5000, [1], delaiMs: 3000)
        try await Task.sleep(for: .milliseconds(50))
        async let b = s.diag(0x0400, [1], delaiMs: 3000)
        let (ra, rb) = try await (a, b)
        #expect(ra.reponse?.rloc16 == 0x5000)
        #expect(rb.reponse?.rloc16 == 0x0400)
        #expect(canal.envoyes == ["diag 5000 1 1 3000\n", "diag 0400 1 2 3000\n"])
    }

    /// Reponse tardive d'une connexion precedente, au meme id mais pour une autre cible (la carte
    /// finit ses requetes en vol apres une reconnexion USB) : ignoree, la requete attend la sienne.
    @Test(.timeLimit(.minutes(1))) func diagDUneAutreCibleIgnore() async throws {
        let canal = CanalRejoue { l in
            l.hasPrefix("diag 0400") ? [CanalRejoue.diag(1, "5000", tlv: "01025000"), CanalRejoue.diag(1, "0400", tlv: "01020400")] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let r = try await s.diag(0x0400, [1], delaiMs: 3000)
        #expect(r.cible == "0400")
        #expect(r.reponse?.rloc16 == 0x0400)
    }

    /// Sans reponse de la sonde : `delai` apres le delai donne et la marge.
    @Test func delai() async throws {
        let s = SondeUSB(canal: CanalRejoue { _ in [] }, marge: .milliseconds(50))
        try await s.demarrer {}
        let r = try await s.diag(0x5000, [1], delaiMs: 0)
        #expect(!r.ok && r.erreur == "delai")
        await #expect(throws: SondeUSB.Erreur.sansReponse("bonjour")) { try await s.bonjour() }
    }

    /// Liaison fermee : les attentes sont liberees, les commandes suivantes refusees.
    @Test func fermeture() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        let fermee = Mutex(false)
        try await s.demarrer { fermee.withLock { $0 = true } }
        let requete = Task { try await s.diag(0x5000, [1], delaiMs: 30000) }
        try await Task.sleep(for: .milliseconds(50))
        canal.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await requete.value }
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await s.etat() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fermee.withLock { $0 })
    }

    /// `routeurs` sur deux lignes (la table coupee, `suite`) : les deux parties reunies, dans
    /// l'ordre ; puis une table d'une ligne (ExtMac inventees).
    @Test func routeursSurPlusieursLignes() async throws {
        let canal = CanalRejoue { l in
            guard l == "routeurs\n" else { return [] }
            return [CanalRejoue.routeurs([("0400", nil), ("AC00", nil)], suite: true),
                    CanalRejoue.routeurs([("E400", "E0000000000000E4")], suite: false)]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let table = try await s.routeurs()
        #expect(table.map(\.rloc16) == ["0400", "AC00", "E400"])
        #expect(table.map(\.ext) == [nil, nil, "E0000000000000E4"])
        #expect(canal.envoyes == ["routeurs\n"])
        #expect(try await s.routeurs().count == 3, "une nouvelle table, sans reste de la precedente")
    }

    /// La sonde n'a pas le verrou d'OpenThread (`occupee`) : `etat`, `voisins` et `routeurs`
    /// echouent tout de suite en `occupee`, sans attendre le delai, et le message le dit.
    @Test(.timeLimit(.minutes(1)), arguments: ["etat", "voisins", "routeurs"])
    func commandeOccupee(_ commande: String) async throws {
        let s = SondeUSB(canal: CanalRejoue { l in
            l == commande + "\n" ? [#"{"v":1,"t":"\#(commande)","erreur":"occupee"}"#] : []
        })
        try await s.demarrer {}
        let debut = ContinuousClock.now
        await #expect(throws: SondeUSB.Erreur.occupee(commande)) {
            switch commande {
            case "etat": _ = try await s.etat()
            case "voisins": _ = try await s.voisins()
            default: _ = try await s.routeurs()
            }
        }
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
        #expect(SondeUSB.Erreur.occupee(commande).localizedDescription
                == String(localized: "la sonde est occupée et n'a pas répondu à « \(commande) »"))
    }

    /// La sonde refuse `etat`, `voisins` ou `routeurs` pour une autre raison que `occupee` : l'erreur
    /// est `refusee`, avec la raison, tout de suite (et non `occupee`, ni `sansReponse`).
    @Test(.timeLimit(.minutes(1)), arguments: ["etat", "voisins", "routeurs"])
    func commandeRefusee(_ commande: String) async throws {
        let s = SondeUSB(canal: CanalRejoue { l in
            l == commande + "\n" ? [#"{"v":1,"t":"\#(commande)","erreur":"pas de pile"}"#] : []
        })
        try await s.demarrer {}
        let debut = ContinuousClock.now
        await #expect(throws: SondeUSB.Erreur.refusee("pas de pile")) {
            switch commande {
            case "etat": _ = try await s.etat()
            case "voisins": _ = try await s.voisins()
            default: _ = try await s.routeurs()
            }
        }
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
    }

    /// Pas de fin de table dans le delai (la sonde s'arrete apres une ligne `suite`) : `routeurs`
    /// echoue en `sansReponse`, et la partie recue est abandonnee : la table suivante ne la
    /// reprend pas.
    @Test(.timeLimit(.minutes(1))) func routeursExpire() async throws {
        let appels = Mutex(0)
        let canal = CanalRejoue { l in
            guard l == "routeurs\n" else { return [] }
            let n = appels.withLock { a in
                a += 1
                return a
            }
            return n == 1 ? [CanalRejoue.routeurs([("0400", "E0000000000000D1")], suite: true)]
                          : [CanalRejoue.routeurs([("E400", "E0000000000000E4")], suite: false)]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.sansReponse("routeurs")) { _ = try await s.routeurs() }
        #expect(try await s.routeurs().map(\.rloc16) == ["E400"])
    }

    /// Liaison fermee pendant l'attente de la table : l'attente est liberee.
    @Test(.timeLimit(.minutes(1))) func routeursFermeture() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let requete = Task { try await s.routeurs() }
        try await Task.sleep(for: .milliseconds(50))
        canal.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await requete.value }
    }

    /// `annonces` (firmware 1.1.0) sur deux lignes (`suite`) : les deux routeurs entendus, dans l'ordre ; puis la ligne
    /// `vide` : aucun.
    @Test func annoncesSurPlusieursLignes() async throws {
        let appels = Mutex(0)
        let canal = CanalRejoue { l in
            guard l == "annonces\n" else { return [] }
            let n = appels.withLock { a in
                a += 1
                return a
            }
            return n == 1 ? [CanalRejoue.annonce("0400", route64: "01800000000000000000", suite: true),
                             CanalRejoue.annonce("AC00", route64: nil, age: 40, suite: false)]
                          : [CanalRejoue.annoncesVides]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let a = try await s.annonces()
        #expect(a.map(\.rloc16) == ["0400", "AC00"])
        #expect(a.map(\.ageS) == [5, 40])
        #expect(a.first?.route64Decodee?.routeurs == [0])
        #expect(try await s.annonces().isEmpty, "aucun routeur entendu")
        #expect(canal.envoyes == ["annonces\n", "annonces\n"])
    }

    /// Pas de fin d'`annonces` dans le delai (firmware 1.0.3 : `commande inconnue`, ou une ligne `suite` sans la
    /// derniere) : `sansReponse`, et la partie recue est abandonnee.
    @Test(.timeLimit(.minutes(1))) func annoncesSansReponse() async throws {
        let appels = Mutex(0)
        let canal = CanalRejoue { l in
            guard l == "annonces\n" else { return [] }
            let n = appels.withLock { a in
                a += 1
                return a
            }
            return n == 1 ? [CanalRejoue.annonce("0400", route64: nil, suite: true)]
                          : [#"{"v":1,"t":"erreur","erreur":"commande inconnue"}"#]
        }
        let s = SondeUSB(canal: canal, delaiCommande: .milliseconds(200))
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.sansReponse("annonces")) { _ = try await s.annonces() }
        await #expect(throws: SondeUSB.Erreur.sansReponse("annonces")) { _ = try await s.annonces() }
    }

    /// Lignes d'`annonces` orphelines : arrivees sans attente en cours (apres l'echeance), sans leur derniere ligne,
    /// elles ne sont pas gardees et ne se melent pas a la reponse suivante.
    @Test(.timeLimit(.minutes(1))) func annoncesOrphelinesOubliees() async throws {
        let appels = Mutex(0)
        let canal = CanalRejoue { l in
            guard l == "annonces\n" else { return [] }
            let n = appels.withLock { a in
                a += 1
                return a
            }
            return n == 1 ? [] : [CanalRejoue.annonce("AC00", route64: nil, suite: false)]
        }
        let s = SondeUSB(canal: canal, delaiCommande: .milliseconds(200), delaiAnnonces: .milliseconds(200))
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.sansReponse("annonces")) { _ = try await s.annonces() }
        // La fin de la premiere reponse arrive en retard, sans sa derniere ligne.
        canal.emettre([CanalRejoue.annonce("0400", route64: "01800000000000000000", suite: true)])
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await s.annonces().map(\.rloc16) == ["AC00"])
    }

    /// Lignes d'`annonces` etalees : la premiere ligne arrive apres le delai commun, mais avant le delai propre
    /// d'`annonces` ; la derniere ligne complete la reponse et elle est bien reunite (firmware 1.1.0 : environ
    /// 4 s pour 32 routeurs, avec marge pour le reseau).
    @Test(.timeLimit(.minutes(1))) func annoncesLignesEtalees() async throws {
        let delaiCommande = Duration.milliseconds(300)
        let canal = CanalRejoue { l in
            guard l == "annonces\n" else { return [] }
            return []
        }
        let s = SondeUSB(canal: canal, delaiCommande: delaiCommande)
        try await s.demarrer {}

        // Emettre les lignes en arriere-plan avec delai : la premiere apres delaiCommande,
        // mais avant le nouveau delai d'annonces
        _ = Task {
            try await Task.sleep(for: delaiCommande + .milliseconds(100))
            canal.emettre([CanalRejoue.annonce("0400", route64: "01800000000000000000", suite: true)])
            try await Task.sleep(for: .milliseconds(100))
            canal.emettre([CanalRejoue.annonce("AC00", route64: nil, suite: false)])
        }

        let a = try await s.annonces()
        #expect(a.count == 2)
        #expect(a.map(\.rloc16) == ["0400", "AC00"])
    }

    /// `resoudre` (firmware 1.1.0) : l'adresse part nue (sans zone) ; deux resolutions en vol, les reponses dans le
    /// desordre, chacune a son id et a sa cible ; une reponse d'un autre id, ou d'une autre cible au meme id, ignoree.
    @Test func resolutionsDansLeDesordre() async throws {
        let a1 = try #require(AdresseIPv6("fd00:aaaa:bbbb:1::17%en0"))
        let a2 = try #require(AdresseIPv6("fd00:aaaa:bbbb:1::18"))
        let canal = CanalRejoue { l in
            guard l.hasPrefix("resoudre fd00:aaaa:bbbb:1::18") else { return [] }
            return [CanalRejoue.resolution(2, "fd00:aaaa:bbbb:1::18", rloc16: "5003"),
                    CanalRejoue.resolution(1, "fd00:aaaa:bbbb:1::99", rloc16: "0400"),
                    CanalRejoue.resolution(1, "fd00:aaaa:bbbb:1::17", rloc16: "AC00", mleid: "FD00111122220C870000000000000017")]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        async let r1 = s.resoudre(a1)
        try await Task.sleep(for: .milliseconds(50))
        async let r2 = s.resoudre(a2)
        let (p, q) = try await (r1, r2)
        #expect(p.rloc16Valeur == 0xAC00 && p.adresseMleid == AdresseIPv6("fd00:1111:2222:c87::17"))
        #expect(q.rloc16Valeur == 0x5003 && q.adresseMleid == nil)
        #expect(canal.envoyes == ["resoudre fd00:aaaa:bbbb:1::17 1\n", "resoudre fd00:aaaa:bbbb:1::18 2\n"])
    }

    /// Sans reponse a `resoudre` (firmware sans resolution) : `delai`, apres les 15 s de la sonde et la marge ; liaison
    /// fermee pendant l'attente : `fermee`.
    @Test(.timeLimit(.minutes(1))) func resolutionSansReponse() async throws {
        let a = try #require(AdresseIPv6("fd00:aaaa:bbbb:1::17"))
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal, marge: .milliseconds(50), delaiResolution: .milliseconds(100))
        try await s.demarrer {}
        let r = try await s.resoudre(a)
        #expect(!r.ok && r.erreur == "delai" && r.cible == "fd00:aaaa:bbbb:1::17" && !r.introuvable)
        let lente = SondeUSB(canal: canal, delaiResolution: .seconds(30))
        try await lente.demarrer {}
        let requete = Task { try await lente.resoudre(a) }
        try await Task.sleep(for: .milliseconds(50))
        canal.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await requete.value }
    }

    /// `diag` vers une adresse (le ML-EID d'un enfant, pour ses compteurs MAC) : la reponse a sa cible, ecrite comme
    /// la commande l'a envoyee.
    @Test func diagParAdresse() async throws {
        let mleid = try #require(AdresseIPv6("fd00:1111:2222:c87::17"))
        let compteurs = "0924" + String(repeating: "00000001", count: 9)
        let canal = CanalRejoue { l in
            l.hasPrefix("diag fd00:1111:2222:c87::17 9 ") ? [CanalRejoue.diag(1, "fd00:1111:2222:c87::17", tlv: compteurs)] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let r = try await s.diag(adresse: mleid, [9], delaiMs: 8000)
        #expect(r.reponse?.compteursMac?.unicastEmis == 1)
        #expect(canal.envoyes == ["diag fd00:1111:2222:c87::17 9 1 8000\n"])
    }

    /// `voisins` : les routeurs que la sonde entend, avec leur signal (valeurs inventees).
    @Test func voisins() async throws {
        let canal = CanalRejoue { l in l == "voisins\n" ? [CanalRejoue.voisins([("E400", -72), ("CC00", -80)])] : [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let v = try await s.voisins()
        #expect(v.map(\.rloc16) == ["E400", "CC00"])
        #expect(v.map(\.rssi) == [-72, -80])
        #expect(canal.envoyes == ["voisins\n"])
    }

    /// Un bonjour non demande : la sonde vient de redemarrer.
    @Test func bonjourSpontane() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        canal.emettre([CanalRejoue.bonjour])
        try await Task.sleep(for: .milliseconds(50))
        #expect(await s.bonjourSpontane?.version == "1.0.0")
    }

    /// fermer rend la main une fois le flux fini (le port vraiment ferme), meme
    /// quand le canal le finit en differe.
    @Test func fermerAttendLaFinDuFlux() async throws {
        let journal = JournalCanaux()
        let s = SondeUSB(canal: CanalTemoin("1", journal: journal, fermetureDifferee: .milliseconds(50)))
        try await s.demarrer {}
        await s.fermer()
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1"])
        #expect(await s.fermee)
    }

    /// Fermee avant d'avoir demarre (connexion abandonnee) : le canal ne s'ouvre plus.
    @Test func fermeeAvantDeDemarrer() async throws {
        let journal = JournalCanaux()
        let s = SondeUSB(canal: CanalTemoin("1", journal: journal))
        await s.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { try await s.demarrer {} }
        #expect(journal.cycle.isEmpty)
    }

    /// L'echeance d'une requete deja servie n'expire pas la suivante : la premiere est servie
    /// tard (a 0,45 s, delai de 0,8 s), la seconde part aussitot et sa reponse arrive a 0,9 s,
    /// apres l'echeance de la premiere (0,8 s) et avant la sienne (1,25 s).
    @Test(.timeLimit(.minutes(1)), arguments: ["bonjour", "etat", "routeurs", "voisins"])
    func echeanceDUneRequeteServie(_ commande: String) async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal, delaiCommande: .milliseconds(800))
        try await s.demarrer {}
        let reponse = switch commande {
        case "bonjour": CanalRejoue.bonjour
        case "etat": CanalRejoue.etatDetache
        case "voisins": CanalRejoue.voisins([("0400", -70)])
        default: CanalRejoue.routeurs([("0400", nil)], suite: false)
        }
        @Sendable func requete() async throws {
            switch commande {
            case "bonjour": _ = try await s.bonjour()
            case "etat": _ = try await s.etat()
            case "voisins": _ = try await s.voisins()
            default: _ = try await s.routeurs()
            }
        }
        let premiere = Task { try await requete() }
        try await Task.sleep(for: .milliseconds(450))
        canal.emettre([reponse])
        try await premiere.value
        let seconde = Task { try await requete() }
        try await Task.sleep(for: .milliseconds(450))
        canal.emettre([reponse])
        try await seconde.value
        #expect(canal.envoyes == [commande + "\n", commande + "\n"])
    }
}

/// Preferences des tests, en memoire (reprises de Maillage Zigbee, 09/10) : chaque lecture et chaque ecriture passent
/// par un dictionnaire, sans jamais toucher le domaine sur le disque. Avec `UserDefaults(suiteName:)`,
/// `removePersistentDomain` laissait un fichier vide par test dans `Library/Preferences` du conteneur de l'app (50 497
/// au 09/10 : cfprefsd ecrit en asynchrone).
final class PreferencesMemoire: UserDefaults, @unchecked Sendable {
    /// Sous `verrou` (des valeurs `Any`, que `Mutex` refuse de partager) ; `parDefaut` : celles de `register`.
    private var valeurs: [String: Any] = [:]
    private var parDefaut: [String: Any] = [:]
    private let verrou = NSLock()
    let domaine: String

    init?(domaine: String) {
        self.domaine = domaine
        super.init(suiteName: domaine)
    }

    override func object(forKey cle: String) -> Any? { verrou.withLock { valeurs[cle] ?? parDefaut[cle] } }
    /// Chaque changement est annonce par KVO, comme le fait `UserDefaults` : `@AppStorage` (les tests de la fenetre) le
    /// suit ainsi.
    override func set(_ valeur: Any?, forKey cle: String) {
        willChangeValue(forKey: cle)
        verrou.withLock { valeurs[cle] = valeur }
        didChangeValue(forKey: cle)
    }

    override func register(defaults: [String: Any]) {
        verrou.withLock { parDefaut.merge(defaults) { _, nouvelle in nouvelle } }
    }

    override func removeObject(forKey cle: String) { set(nil as Any?, forKey: cle) }
    override func string(forKey cle: String) -> String? { object(forKey: cle) as? String }
    override func stringArray(forKey cle: String) -> [String]? { object(forKey: cle) as? [String] }
    override func bool(forKey cle: String) -> Bool { object(forKey: cle) as? Bool ?? false }
    override func integer(forKey cle: String) -> Int { object(forKey: cle) as? Int ?? 0 }
    override func double(forKey cle: String) -> Double { object(forKey: cle) as? Double ?? 0 }
    override func data(forKey cle: String) -> Data? { object(forKey: cle) as? Data }
    override func set(_ valeur: Bool, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func set(_ valeur: Int, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func set(_ valeur: Double, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func dictionaryRepresentation() -> [String: Any] { verrou.withLock { parDefaut.merging(valeurs) { $1 } } }
    override func persistentDomain(forName nom: String) -> [String: Any]? {
        nom == domaine ? verrou.withLock { valeurs } : nil
    }
    override func removePersistentDomain(forName nom: String) {
        guard nom == domaine else { return }
        verrou.withLock { valeurs = [:] }
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@MainActor
@Suite("Sonde dans l'app : port retenu, refus, fraicheur du maillage", .timeLimit(.minutes(1)))
struct SondeMaillageTests {
    /// Preferences d'un test, en memoire (`PreferencesMemoire`) : aucun fichier dans le conteneur de l'app.
    static func preferences() throws -> (UserDefaults, String) {
        let domaine = "fr.djoko.maillage.tests.sonde.\(UUID().uuidString)"
        return (try #require(PreferencesMemoire(domaine: domaine)), domaine)
    }

    static let port = PortUSB(chemin: "/dev/cu.usbmodem11301", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                              produit: "USB JTAG/serial debug unit")

    /// Attend, sans delai, que `condition` soit vraie : elle est relue a chaque
    /// changement observe de ce qu'elle lit.
    static func attendre(_ condition: () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                withObservationTracking { _ = condition() } onChange: { suite.resume() }
            }
        }
    }

    static func connectee(_ s: SondeMaillage) -> Bool {
        if case .connectee = s.etat { true } else { false }
    }

    /// Demande de la liste des routeurs de la premiere tournee d'une connexion (id 1).
    static let listeRetenue = "diag 0000 5,6 1 6000"

    /// Canal du reseau minimal dont la liste des routeurs ne revient que quand le test la
    /// rend (`canal.emettre(CanalRejoue.reseauMinimal(listeRetenue + "\n"))`) : la tournee
    /// reste en cours. Les commandes sont notees au journal.
    static func canalRetenu(_ journal: JournalCanaux) -> CanalRejoue {
        CanalRejoue { l in
            journal.noter(l.trimmingCharacters(in: .newlines))
            return l.hasPrefix("diag 0000 5,6 ") ? [] : CanalRejoue.reseauMinimal(l)
        }
    }

    /// Un port qui repond en sonde est retenu (numero de serie USB) ; oublier le retire.
    @Test func retenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let canal = CanalRejoue { l in l == "bonjour\n" ? [CanalRejoue.bonjour] : l == "etat\n" ? [CanalRejoue.etatDetache] : [] }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(Self.port, choisi: true)
        guard case .connectee(let b) = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(b.version == "1.0.0")
        #expect(p.string(forKey: SondeMaillage.cleSerie) == "A0:00:00:00:00:01")
        await s.oublier()
        #expect(s.etat == .sansSonde)
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
    }

    /// Un autre C6 (le pont Halo) n'est pas une sonde : refuse, rien de retenu.
    @Test func refusee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let halo = #"{"v":1,"t":"bonjour","produit":"pont-halo","version":"0.4.0","mac":null,"appairee":true,"code":null,"qr":null}"#
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { _ in [halo] } })
        await s.connecter(Self.port, choisi: true)
        guard case .refusee(let m) = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(m.contains("pont-halo"))
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
    }

    /// Aucune sonde retenue : un C6 branche est liste pour les Reglages, jamais ouvert
    /// (spec, section 3 : aucun port qu'on ne lui a pas designe).
    @Test func sansSondeRetenueAucunPortOuvert() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalRejoue { _ in [CanalRejoue.bonjour] }
        })
        s.portsChanges([Self.port])
        // Une connexion lancee passerait avant la suite du test (meme acteur, dans l'ordre).
        await Task.yield()
        #expect(s.ports == [Self.port])
        #expect(canaux == 0)
        #expect(s.etat == .sansSonde)
    }

    /// La sonde retenue (serie S) n'est pas branchee, un autre C6 l'est (serie H, le
    /// pont Halo par exemple) : il n'est jamais ouvert, la sonde est absente.
    @Test func autreC6JamaisOuvert() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: "USB JTAG/serial debug unit")
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalRejoue { _ in [CanalRejoue.bonjour] }
        })
        s.portsChanges([autre])
        await Task.yield()
        #expect(s.ports == [autre])
        #expect(canaux == 0)
        #expect(s.etat == .absente)
    }

    /// La sonde retenue absente, un autre port choisi dans les Reglages : un changement de ports
    /// pendant sa connexion (evenement IOKit) ne l'annule pas ; le port choisi est retenu.
    @Test(.timeLimit(.minutes(1))) func choixDUnAutrePortSansLaSondeRetenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let journal = JournalCanaux()
        let canal = CanalTemoin("2", journal: journal, retenirBonjour: true)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        s.portsChanges([autre])
        #expect(s.etat == .absente)
        s.choisir(autre)
        await journal.attendre("bonjour 2")
        s.portsChanges([autre])
        try #require(s.etat == .connexion, "choix annule : \(s.etat)")
        canal.libererBonjour()
        await Self.attendre { Self.connectee(s) }
        #expect(s.serie == "B0:00:00:00:00:02")
        #expect(journal.cycle == ["ouvrir 2"])
        await s.oublier()
    }

    /// La sonde retenue debranchee : absente.
    @Test func debranchee() throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { _ in [] } })
        s.portsChanges([])
        #expect(s.etat == .absente)
    }

    /// « Oublier » pendant la verification du port (bonjour encore sans reponse) :
    /// la connexion en cours est abandonnee et son port ferme ; rien n'est retenu.
    @Test func oublierPendantLaConnexion() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let canal = CanalTemoin("1", journal: journal, retenirBonjour: true)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let connexion = Task { await s.connecter(Self.port, choisi: true) }
        await journal.attendre("bonjour 1")
        await s.oublier()
        // La reponse arrive apres coup : elle ne change plus rien.
        canal.libererBonjour()
        await connexion.value
        #expect(s.etat == .sansSonde)
        #expect(s.serie == nil)
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1"])
    }

    /// Deux changements de ports de suite, la sonde retenue branchee : une seule connexion.
    @Test func deuxChangementsDePorts() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalTemoin("\(canaux)", journal: journal)
        })
        s.portsChanges([Self.port])
        s.portsChanges([Self.port])
        await Self.attendre { Self.connectee(s) }
        #expect(canaux == 1)
        #expect(journal.cycle == ["ouvrir 1"])
        await s.oublier()
    }

    /// Choisir le port de la sonde deja connectee : rien n'est ferme ni rouvert.
    @Test func choisirLePortConnecte() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalTemoin("\(canaux)", journal: journal)
        })
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        s.choisir(Self.port)
        // Une connexion lancee par `choisir` passerait avant la suite du test
        // (meme acteur, dans l'ordre) et creerait son canal.
        await Task.yield()
        #expect(canaux == 1)
        #expect(Self.connectee(s))
        #expect(journal.cycle == ["ouvrir 1"])
        await s.oublier()
    }

    /// Reconnexion : l'ancienne liaison est vraiment fermee (fin de son flux)
    /// avant que la nouvelle ne s'ouvre ; sinon le port serait encore tenu.
    @Test func reconnexion() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            // Fin du flux en differe, comme la liaison serie qui ferme le port sur sa file.
            return CanalTemoin("\(canaux)", journal: journal, fermetureDifferee: .milliseconds(50))
        })
        await s.connecter(Self.port, choisi: true)
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1", "ouvrir 2"])
        await s.oublier()
    }

    /// Connexion automatique en echec (sonde qui demarre en plus de 3 s, port pas encore pret) :
    /// un nouvel essai quelques secondes apres, sans attendre l'evenement USB suivant.
    @Test(.timeLimit(.minutes(1))) func nouvelEssaiApresUneConnexionAutomatiqueEnEchec() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ -> any CanalSonde in
            canaux += 1
            return canaux == 1 ? CanalEnPanne() : CanalRejoue { CanalRejoue.reseauMinimal($0) }
        }, delaiNouvelEssai: .milliseconds(50))
        // Un seul evenement USB : le second canal vient du nouvel essai.
        s.portsChanges([Self.port])
        #expect(await SondeReseauTests.sonder { Self.connectee(s) }, "nouvel essai : \(s.etat)")
        #expect(canaux == 2)
        await s.oublier()
    }

    /// Un seul nouvel essai : en echec a son tour, la sonde reste en erreur jusqu'a l'evenement
    /// USB suivant. Un port choisi dans les Reglages, puis refuse, n'est pas essaye de nouveau.
    @Test(.timeLimit(.minutes(1))) func unSeulNouvelEssaiEtAucunPourUnChoix() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalEnPanne()
        }, delaiNouvelEssai: .milliseconds(20))
        s.portsChanges([Self.port])
        #expect(await SondeReseauTests.sonder { canaux == 2 }, "nouvel essai")
        try await Task.sleep(for: .milliseconds(200))
        #expect(canaux == 2, "un seul")
        guard case .erreur = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        await s.connecter(Self.port, choisi: true)
        guard case .refusee = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(canaux == 3, "aucun pour un port choisi")
        await s.oublier()
    }

    /// Le nouvel essai planifie est perime si la sonde est debranchee, oubliee, ou si un autre port
    /// est choisi pendant son attente : il n'ouvre rien (aucun port qu'on ne lui a pas designe).
    @Test(.timeLimit(.minutes(1)), arguments: ["debranchee", "oubliee", "autre port choisi"])
    func nouvelEssaiPerime(_ cas: String) async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let journal = JournalCanaux()
        var ouverts: [String] = []
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { chemin -> any CanalSonde in
            ouverts.append(chemin)
            return chemin == autre.chemin ? CanalTemoin("autre", journal: journal, retenirBonjour: true) : CanalEnPanne()
        }, delaiNouvelEssai: .milliseconds(50))
        // Connexion automatique en echec : a son retour, le nouvel essai est planifie, et le
        // changement suit dans le meme tour de l'acteur principal, avant qu'il ne parte.
        await s.connecter(Self.port, choisi: false)
        guard case .erreur = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        switch cas {
        case "debranchee": s.portsChanges([])
        case "oubliee": await s.oublier()
        default: s.choisir(autre)
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(ouverts.filter { $0 == Self.port.chemin }.count == 1, "\(cas) : \(ouverts)")
        switch cas {
        case "debranchee": #expect(s.etat == .absente)
        case "oubliee": #expect(s.etat == .sansSonde)
        default: #expect(s.etat == .connexion, "le choix continue")
        }
        await s.oublier()
    }

    /// Reseau minimal dans une partition donnee ; la table des routeurs donne l'ExtMac du chef 0
    /// (muet : il ne rend que sa Route64) s'il est entendu (valeur inventee).
    static func canalIdentites(ext: String?, partition: String) -> CanalRejoue {
        CanalRejoue { l in
            switch l {
            case "etat\n": return [CanalRejoue.etatAttache.replacingOccurrences(of: "0000000A", with: partition)]
            case "routeurs\n": return [CanalRejoue.routeurs([("0000", ext)], suite: false)]
            default: return CanalRejoue.reseauMinimal(l)
            }
        }
    }

    /// Identites des routeurs gardees dans un fichier (ici temporaire) : relues au lancement
    /// suivant, ou le chef muet garde l'ExtMac que la sonde n'entend plus ; une autre partition
    /// les efface, dans le fichier aussi.
    @Test(.timeLimit(.minutes(1))) func identitesGardeesDUnLancementALAutre() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = dossier.appendingPathComponent("identites-routeurs.json")
        /// Un lancement de l'app : une sonde, une tournee, son maillage.
        func lancement(ext: String?, partition: String = "0000000A") async -> Maillage? {
            let s = SondeMaillage(preferences: p, actif: true,
                                  ouvrirCanal: { _ in Self.canalIdentites(ext: ext, partition: partition) },
                                  fichierIdentites: fichier)
            var recu: Maillage?
            s.surMaillage = { m, _ in recu = m }
            await s.connecter(Self.port, choisi: true)
            await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
            await s.oublier()
            return recu
        }
        let m1 = await lancement(ext: "E0000000000000A0")
        #expect(m1?.routeur(0)?.extMac == "E0000000000000A0", "entendu par la sonde")
        #expect(IdentitesGardees.lire(fichier) == IdentitesGardees(partition: "0000000A", identites: [0x0000: "E0000000000000A0"]))
        let m2 = await lancement(ext: nil)
        #expect(m2?.routeur(0)?.extMac == "E0000000000000A0", "relue au lancement suivant")
        let m3 = await lancement(ext: nil, partition: "0000000B")
        #expect(m3?.routeur(0)?.extMac == nil, "autre partition")
        #expect(IdentitesGardees.lire(fichier) == IdentitesGardees(partition: "0000000B", identites: [:]))
    }

    /// Reseau minimal ou personne ne donne la liste des routeurs (tout `diag` echoue) : la
    /// tournee ne rend pas de maillage ; la table des routeurs donne l'ExtMac du chef 0 (inventee).
    static func canalSansListe() -> CanalRejoue {
        CanalRejoue { l in
            if l == "routeurs\n" { return [CanalRejoue.routeurs([("0000", "E0000000000000A0")], suite: false)] }
            let mots = l.trimmingCharacters(in: .newlines).split(separator: " ").map(String.init)
            if mots.first == "diag", mots.count >= 4, let id = Int(mots[3]) {
                return [#"{"v":1,"t":"diag","id":\#(id),"cible":"\#(mots[1])","ok":false,"erreur":"delai"}"#]
            }
            return CanalRejoue.reseauMinimal(l)
        }
    }

    /// Tournee sans liste des routeurs : pas de maillage, mais l'identite entendue est gardee,
    /// dans le fichier aussi (une sonde promenee ne perd rien).
    @Test(.timeLimit(.minutes(1))) func identitesGardeesSansListeDesRouteurs() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = dossier.appendingPathComponent("identites-routeurs.json")
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in Self.canalSansListe() },
                              fichierIdentites: fichier)
        let (fins, fin) = AsyncStream.makeStream(of: Void.self)
        s.surTournee = { enCours in if !enCours { fin.yield() } }
        await s.connecter(Self.port, choisi: true)
        for await _ in fins { break }
        #expect(s.derniereTournee == nil, "pas de maillage")
        #expect(IdentitesGardees.lire(fichier) == IdentitesGardees(partition: "0000000A", identites: [0x0000: "E0000000000000A0"]))
        await s.oublier()
    }

    /// Fichier des identites reecrit seulement quand elles changent : efface apres la premiere
    /// tournee, il n'est pas recree par une tournee qui n'apprend rien de nouveau ; il l'est par
    /// celle ou le chef change d'ExtMac (valeurs inventees).
    @Test(.timeLimit(.minutes(1))) func fichierReecritSeulementSiChangement() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = dossier.appendingPathComponent("identites-routeurs.json")
        let entendue = Mutex("E0000000000000A0")
        let canal = CanalRejoue { l in
            guard l == "routeurs\n" else { return CanalRejoue.reseauMinimal(l) }
            return [CanalRejoue.routeurs([("0000", entendue.withLock { $0 })], suite: false)]
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, fichierIdentites: fichier)
        let (fins, fin) = AsyncStream.makeStream(of: Void.self)
        s.surTournee = { enCours in if !enCours { fin.yield() } }
        var tournees = fins.makeAsyncIterator()
        await s.connecter(Self.port, choisi: true)
        _ = await tournees.next()
        #expect(IdentitesGardees.lire(fichier) != nil, "premiere tournee : ecrit")
        try FileManager.default.removeItem(at: fichier)
        s.rafraichir()
        _ = await tournees.next()
        #expect(!FileManager.default.fileExists(atPath: fichier.path), "rien de change : pas reecrit")
        entendue.withLock { $0 = "E0000000000000A1" }
        s.rafraichir()
        _ = await tournees.next()
        #expect(IdentitesGardees.lire(fichier) == IdentitesGardees(partition: "0000000A", identites: [0x0000: "E0000000000000A1"]))
        await s.oublier()
    }

    /// Ecriture du fichier des identites en echec (un fichier a la place de son dossier) : tracee,
    /// les identites restent en memoire et l'ecriture est retentee a la tournee suivante.
    @Test(.timeLimit(.minutes(1))) func ecritureDesIdentitesRetentee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let bouchon = dossier.appendingPathComponent("Maillage Thread")
        try Data().write(to: bouchon)
        let fichier = bouchon.appendingPathComponent("identites-routeurs.json")
        let s = SondeMaillage(preferences: p, actif: true,
                              ouvrirCanal: { _ in Self.canalIdentites(ext: "E0000000000000A0", partition: "0000000A") },
                              fichierIdentites: fichier)
        let (fins, fin) = AsyncStream.makeStream(of: Void.self)
        s.surTournee = { enCours in if !enCours { fin.yield() } }
        var tournees = fins.makeAsyncIterator()
        await s.connecter(Self.port, choisi: true)
        _ = await tournees.next()
        #expect(IdentitesGardees.lire(fichier) == nil, "pas ecrit")
        try FileManager.default.removeItem(at: bouchon)
        s.rafraichir()
        _ = await tournees.next()
        #expect(IdentitesGardees.lire(fichier) == IdentitesGardees(partition: "0000000A", identites: [0x0000: "E0000000000000A0"]),
                "retentee, sans changement des identites")
        await s.oublier()
    }

    /// Fichier des identites : dans le dossier de l'app ; jamais en demo ni sous les tests (qui
    /// passent leur propre fichier, temporaire).
    @Test func fichierDesIdentites() {
        #expect(SondeMaillage.fichierIdentites(demo: true, sousTests: false) == nil)
        #expect(SondeMaillage.fichierIdentites(demo: false, sousTests: true) == nil)
        #expect(SondeMaillage.fichierIdentites(demo: true, sousTests: true) == nil)
        #expect(SondeMaillage.fichierIdentites(demo: false, sousTests: false)
                == Surveillance.dossierParDefaut.appendingPathComponent("identites-routeurs.json"))
    }

    /// En demo et sous tests : rien de lu.
    @Test func inactive() throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        let s = SondeMaillage(preferences: p, actif: false)
        #expect(s.serie == nil)
        #expect(s.nom == nil)
    }

    /// Nom donne par la carte (firmware 1.0.1) : retenu a cote du numero de serie, relu au
    /// lancement ; oublier la sonde l'oublie aussi.
    @Test func nomRetenu() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        #expect(s.nom == nil)
        await s.connecter(Self.port, choisi: true)
        #expect(s.nom == "SONDE-01")
        #expect(p.string(forKey: SondeMaillage.cleNom) == "SONDE-01")
        #expect(SondeMaillage(preferences: p, actif: true).nom == "SONDE-01", "relu au lancement")
        await s.oublier()
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
    }

    /// Port sans numero de serie : la sonde n'est pas retenue, son nom non plus (il resterait
    /// affiche sans sonde choisie apres un relancement).
    @Test func nomSansSerieNonRetenu() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let sansSerie = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: nil, produit: nil)
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(sansSerie, choisi: true)
        #expect(Self.connectee(s))
        #expect(s.serie == nil)
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
        await s.oublier()
    }

    /// Le nom de la sonde retenue va a l'etat qui la concerne (connectee, absente) ; pas au
    /// refus d'un autre port choisi, ni a la connexion d'un autre port, ni sans sonde.
    @Test(.timeLimit(.minutes(1))) func nomSeulementPourLaSondeRetenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let halo = #"{"v":1,"t":"bonjour","produit":"pont-halo","version":"0.4.0","mac":null,"appairee":true,"code":null,"qr":null}"#
        let pont = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                           produit: nil)
        let troisieme = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: "C0:00:00:00:00:03",
                                produit: nil)
        let journal = JournalCanaux()
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { chemin in
            if chemin == Self.port.chemin {
                return CanalRejoue { l in
                    l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
                }
            }
            if chemin == pont.chemin { return CanalRejoue { _ in [halo] } }
            return CanalTemoin("3", journal: journal, retenirBonjour: true)
        })
        #expect(s.nomEtat == nil, "aucune sonde")
        await s.connecter(Self.port, choisi: true)
        #expect(s.nomEtat == "SONDE-01")
        await s.connecter(pont, choisi: true)
        guard case .refusee = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(s.nom == "SONDE-01", "la sonde reste retenue")
        #expect(s.nomEtat == nil, "refus d'un autre port")
        s.portsChanges([pont])
        #expect(s.etat == .absente)
        #expect(s.nomEtat == "SONDE-01", "la sonde retenue est absente")
        s.choisir(troisieme)
        await journal.attendre("bonjour 3")
        #expect(s.etat == .connexion)
        #expect(s.nomEtat == nil, "connexion d'un autre port")
        await s.oublier()
        #expect(s.nomEtat == nil)
    }

    /// La sonde retenue elle-meme, reprise au branchement (sans choix dans les Reglages) : son
    /// nom aussi pendant sa connexion, et apres une erreur de son port.
    @Test(.timeLimit(.minutes(1))) func nomDeLaSondeRetenueEnConnexionEtEnErreur() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ -> any CanalSonde in
            canaux += 1
            // D'abord un bonjour qui tarde (connexion en cours), puis un port qui ne s'ouvre pas.
            return canaux == 1 ? CanalTemoin("1", journal: journal, retenirBonjour: true) : CanalEnPanne()
        })
        s.portsChanges([Self.port])
        await journal.attendre("bonjour 1")
        #expect(s.etat == .connexion)
        #expect(s.nomEtat == "SONDE-01", "connexion de la sonde retenue")
        s.portsChanges([])
        s.portsChanges([Self.port])
        await Self.attendre { if case .erreur = s.etat { true } else { false } }
        #expect(s.nomEtat == "SONDE-01", "erreur de la sonde retenue")
        await s.oublier()
    }

    /// Le nom suit chaque bonjour : un firmware sans nom (1.0.0) l'efface.
    @Test func nomSuitLeBonjour() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            let b = canaux == 1 ? CanalRejoue.bonjourNomme : CanalRejoue.bonjour
            return CanalRejoue { l in l == "bonjour\n" ? [b] : l == "etat\n" ? [CanalRejoue.etatDetache] : [] }
        })
        await s.connecter(Self.port, choisi: true)
        #expect(s.nom == "SONDE-01")
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
        await s.oublier()
    }

    /// Pendant une tournee : son avancement (etape, fait, total) et l'heure de son debut ;
    /// l'un et l'autre remis a nil a sa fin.
    @Test(.timeLimit(.minutes(1))) func avancementPendantLaTournee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let horloge = HorlogeFactice(t0)
        let journal = JournalCanaux()
        let canal = Self.canalRetenu(journal)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, horloge: { horloge.maintenant })
        #expect(s.avancement == nil && s.debutTournee == nil)
        await s.connecter(Self.port, choisi: true)
        await journal.attendre(Self.listeRetenue)
        await Self.attendre { s.avancement?.etape == .listeRouteurs }
        #expect(s.avancement == AvancementTournee(etape: .listeRouteurs, fait: 0, total: 1))
        #expect(s.debutTournee == t0)
        canal.emettre(CanalRejoue.reseauMinimal(Self.listeRetenue + "\n"))
        await Self.attendre { !s.tourneeEnCours }
        #expect(s.derniereTournee == t0)
        #expect(s.avancement == nil)
        #expect(s.debutTournee == nil)
        await s.oublier()
    }

    /// La liaison se ferme pendant une tournee (oubli, debranchement) : la tournee finit sans
    /// erreur a montrer, son avancement est remis a nil.
    @Test(.timeLimit(.minutes(1))) func avancementRemisANilALaFermeture() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in Self.canalRetenu(journal) })
        await s.connecter(Self.port, choisi: true)
        await journal.attendre(Self.listeRetenue)
        await Self.attendre { s.avancement != nil }
        await s.oublier()
        await Self.attendre { !s.tourneeEnCours }
        #expect(s.avancement == nil)
        #expect(s.debutTournee == nil)
        #expect(s.erreurTournee == nil)
    }

    /// « Oublier la sonde » efface son releve : etat de la sonde (partition, suspension), dernier
    /// releve et erreur de tournee ne restent pas apres elle.
    /// Firmware 1.1.0 : chaque tournee demande a l'app ses appareils a resoudre, et les passe a la sonde ; la couverture
    /// de l'ecoute (routeurs entendus sur ceux de la partition) est retenue avec le releve, et oubliee avec lui (valeurs
    /// inventees : le chef 0, entendu et muet ; l'appareil resolu sous lui, avec son propre RLOC16).
    @Test(.timeLimit(.minutes(1))) func couvertureEtResolution() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let canal = CanalRejoue { l in
            if l == "annonces\n" { return [CanalRejoue.annonce("0000", route64: "01800000000000000000", suite: false)] }
            let mots = l.trimmingCharacters(in: .newlines).split(separator: " ").map(String.init)
            if mots.count == 3, mots[0] == "resoudre", let id = Int(mots[2]) {
                return [CanalRejoue.resolution(id, mots[1], rloc16: "0002")]
            }
            return CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let adresse = try #require(AdresseIPv6("fd00:aaaa:bbbb:1::17"))
        var demandes = 0
        s.appareilsAResoudre = {
            demandes += 1
            return [AppareilAResoudre(id: "E0000000000000C1", partition: "0000000A", adresse: adresse)]
        }
        var recu: Maillage?
        s.surMaillage = { m, _ in recu = m }
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        #expect(demandes == 1)
        #expect(s.couverture == CouvertureEcoute(entendus: 1, routeurs: 1))
        #expect(canal.envoyes.contains { $0.hasPrefix("resoudre fd00:aaaa:bbbb:1::17 ") })
        let e = try #require(recu?.enfants.first { $0.extMac == "E0000000000000C1" })
        #expect(e.rloc16 == 0x0002 && e.source == .resolution, "sous le chef, muet")
        await s.oublier()
        #expect(s.couverture == nil)
    }

    @Test(.timeLimit(.minutes(1))) func oublierEffaceLeReleve() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        // Une premiere tournee complete ; ensuite `etat` reste sans reponse (erreur de tournee a 3 s).
        let muette = Mutex(false)
        let canal = CanalRejoue { l in
            l == "etat\n" && muette.withLock({ $0 }) ? [] : CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        muette.withLock { $0 = true }
        s.rafraichir()
        await Self.attendre { s.erreurTournee != nil }
        #expect(s.etatSonde != nil && s.derniereTournee != nil)
        await s.oublier()
        #expect(s.etatSonde == nil)
        #expect(s.derniereTournee == nil)
        #expect(s.erreurTournee == nil)
    }

    /// Un autre port choisi retient une autre sonde : le releve de la precedente (etat, dernier
    /// releve, erreur de tournee) ne s'affiche pas pour elle.
    @Test(.timeLimit(.minutes(1))) func autreSondeSansLeReleveDeLaPrecedente() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        // Premiere sonde : une tournee complete, puis `etat` sans reponse (erreur de tournee a 3 s).
        // Seconde sonde : `bonjour` seulement, sa tournee attend.
        let muette = Mutex(false)
        let premiere = CanalRejoue { l in
            l == "etat\n" && muette.withLock({ $0 }) ? [] : CanalRejoue.reseauMinimal(l)
        }
        let seconde = CanalRejoue { l in l == "bonjour\n" ? [CanalRejoue.bonjour] : [] }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { $0 == autre.chemin ? seconde : premiere })
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        muette.withLock { $0 = true }
        s.rafraichir()
        await Self.attendre { s.erreurTournee != nil }
        #expect(s.etatSonde != nil && s.derniereTournee != nil)
        // Au retour de la connexion, la tournee de la seconde sonde n'a pas encore commence.
        await s.connecter(autre, choisi: true)
        #expect(s.serie == autre.serie)
        #expect(s.etatSonde == nil)
        #expect(s.derniereTournee == nil)
        #expect(s.erreurTournee == nil)
        await s.oublier()
    }

    /// « Oublier la sonde » retire aussi son maillage du graphe, branche comme dans l'app
    /// (`surOubli`) : retour aux pointilles tout de suite, sans attendre qu'il soit perime.
    @Test(.timeLimit(.minutes(1))) func oublierRetireLeMaillage() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { CanalRejoue.reseauMinimal($0) } })
        s.surMaillage = { m, recu in surveillance.recevoir(m, a: recu) }
        s.surOubli = { surveillance.oublierMaillage() }
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { surveillance.maillage != nil }
        #expect(surveillance.fraicheurMaillage(a: Date()) == .frais)
        await s.oublier()
        #expect(surveillance.maillage == nil)
        #expect(surveillance.fraicheurMaillage(a: Date()) == nil)
    }

    /// « Oublier » pendant que la reponse a `etat` de la tournee est en route : arrivee apres
    /// l'oubli (avant la fin du flux), elle ne remet pas l'etat de la sonde.
    @Test(.timeLimit(.minutes(1))) func etatRecuApresLOubli() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        // `etat` ne repond que quand le test le rend.
        let canal = CanalRejoue { l in
            journal.noter(l.trimmingCharacters(in: .newlines))
            return l == "etat\n" ? [] : CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(Self.port, choisi: true)
        await journal.attendre("etat")
        await s.oublier()
        canal.emettre([CanalRejoue.etatAttache])
        await Self.attendre { !s.tourneeEnCours }
        #expect(s.etatSonde == nil)
    }

    /// « Oublier » pendant une tournee : la liaison met un instant a se fermer et la tournee
    /// aboutit entre-temps ; ni dernier releve ni maillage ne reviennent apres l'oubli.
    @Test(.timeLimit(.minutes(1))) func tourneeFinieApresLOubli() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let canal = CanalRejoue(fermetureDifferee: .seconds(2)) { l in
            journal.noter(l.trimmingCharacters(in: .newlines))
            return l.hasPrefix("diag 0000 5,6 ") ? [] : CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        var maillages = 0
        s.surMaillage = { _, _ in maillages += 1 }
        await s.connecter(Self.port, choisi: true)
        await journal.attendre(Self.listeRetenue)
        await s.oublier()
        canal.emettre(CanalRejoue.reseauMinimal(Self.listeRetenue + "\n"))
        await Self.attendre { !s.tourneeEnCours }
        #expect(maillages == 0)
        #expect(s.derniereTournee == nil)
        #expect(s.etatSonde == nil)
    }

    /// `etat` refuse au debut d'une tournee (sonde occupee) : l'erreur de la tournee le dit tout de
    /// suite, au lieu de « la sonde ne repond pas » au bout de l'echeance.
    @Test(.timeLimit(.minutes(1))) func etatOccupee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let canal = CanalRejoue { l in
            l == "etat\n" ? [#"{"v":1,"t":"etat","erreur":"occupee"}"#] : CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let debut = ContinuousClock.now
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { s.erreurTournee != nil }
        #expect(s.erreurTournee == SondeUSB.Erreur.occupee("etat").localizedDescription)
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
        await s.oublier()
    }

    /// Age compte depuis la reception : frais jusqu'a 6 min, ancien jusqu'a 15, perime
    /// ensuite ; pendant une tournee, jamais ancien, mais perime apres 15 min.
    @Test func fraicheur() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(Surveillance.fraicheur(t, maintenant: t + 300) == .frais)
        #expect(Surveillance.fraicheur(t, maintenant: t + 7 * 60) == .ancien)
        #expect(Surveillance.fraicheur(t, maintenant: t + 16 * 60) == .perime)
        #expect(Surveillance.fraicheur(t, maintenant: t + 7 * 60, tourneeEnCours: true) == .frais)
        #expect(Surveillance.fraicheur(t, maintenant: t + 16 * 60, tourneeEnCours: true) == .perime)
    }

    /// Une tournee de 90 s : le maillage, date du debut de sa tournee, est recu a sa fin
    /// (debut, maillage, fin).
    @Test(.timeLimit(.minutes(1))) func tourneeRecueASaFin() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let horloge = HorlogeFactice(t0)
        let canal = CanalRejoue { l in
            // La demande de la liste des routeurs « dure » 90 s.
            if l.hasPrefix("diag 0000 5,6 ") { horloge.avancer(90) }
            return CanalRejoue.reseauMinimal(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, horloge: { horloge.maintenant })
        var suite: [String] = []
        var recus: [(date: Date, recu: Date)] = []
        s.surTournee = { suite.append($0 ? "debut" : "fin") }
        s.surMaillage = { m, recu in
            suite.append("maillage")
            recus.append((m.date, recu))
        }
        // La connexion lance la premiere tournee.
        await s.connecter(Self.port, choisi: true)
        await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        #expect(suite == ["debut", "maillage", "fin"])
        #expect(recus.first?.date == t0)
        #expect(recus.first?.recu == t0 + 90)
        #expect(s.derniereTournee == t0 + 90)
        await s.oublier()
    }

    /// Rafraichir pendant une tournee (bouton du graphe) : ni seconde tournee, ni boucle
    /// relancee (la tournee suivante partirait 5 min apres le clic, et non apres la fin de
    /// celle-ci). Hors tournee, une tournee part tout de suite.
    @Test(.timeLimit(.minutes(1))) func rafraichirPendantUneTournee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let canal = Self.canalRetenu(journal)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        #expect(!s.tourneeAuRafraichir, "sans sonde connectee")
        await s.connecter(Self.port, choisi: true)
        await journal.attendre(Self.listeRetenue)
        #expect(s.tourneeEnCours)
        #expect(!s.tourneeAuRafraichir, "pendant une tournee")
        let boucle = try #require(s.boucle)
        s.rafraichir()
        await Task.yield()
        #expect(s.boucle == boucle, "boucle gardee")
        #expect(!boucle.isCancelled)
        #expect(canal.envoyes.filter { $0 == "etat\n" }.count == 2, "une seule tournee : etat, puis celui de la tournee")
        canal.emettre(CanalRejoue.reseauMinimal(Self.listeRetenue + "\n"))
        await Self.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        #expect(s.tourneeAuRafraichir, "connectee et libre")
        s.rafraichir()
        await Self.attendre { s.tourneeEnCours }
        #expect(s.boucle != boucle, "hors tournee : une tournee tout de suite")
        await s.oublier()
    }

    /// Marche normale : une tournee de 90 s, la pause de 5 min, une tournee de 10 s, la
    /// pause, de nouveau 90 s. Chaque maillage est date du debut de sa tournee et recu a
    /// sa fin, comme dans l'app : il n'est jamais « ancien », ni perime.
    @Test func fraicheurEnMarcheNormale() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        var tournees: [(debut: TimeInterval, fin: TimeInterval)] = []
        var t: TimeInterval = 0
        for duree in [90.0, 10, 90] {
            tournees.append((t, t + duree))
            t += duree + 300
        }
        var vues: [Surveillance.Fraicheur] = []
        for seconde in stride(from: 0, through: t, by: 1.0) {
            for tr in tournees {
                if seconde == tr.debut { s.tourneeEnCours = true }
                if seconde == tr.fin {
                    s.recevoir(ConstructionMaillage(date: t0 + tr.debut, partition: "0000000A").maillage(), a: t0 + seconde)
                    s.tourneeEnCours = false
                }
            }
            if let f = s.fraicheurMaillage(a: t0 + seconde) { vues.append(f) }
        }
        #expect(vues.count == Int(t - 90) + 1, "un maillage des la fin de la premiere tournee")
        #expect(vues.filter { $0 != .frais }.isEmpty)
    }

    /// Sans tournee (sonde muette, debranchee, ou tournee sans Route64) : ancien apres
    /// 6 min, perime apres 15 ; une tournee en cours ne retient pas un maillage perime.
    @Test func fraicheurSansTournee() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(s.fraicheurMaillage(a: t0) == nil)
        // Tournee de 90 s : le maillage est recu a t0.
        s.recevoir(ConstructionMaillage(date: t0 - 90, partition: "0000000A").maillage(), a: t0)
        #expect(s.fraicheurMaillage(a: t0 + 6 * 60) == .frais)
        #expect(s.fraicheurMaillage(a: t0 + 6 * 60 + 1) == .ancien)
        #expect(s.fraicheurMaillage(a: t0 + 15 * 60) == .ancien)
        #expect(s.fraicheurMaillage(a: t0 + 15 * 60 + 1) == .perime)
        s.tourneeEnCours = true
        #expect(s.fraicheurMaillage(a: t0 + 6 * 60 + 1) == .frais)
        #expect(s.fraicheurMaillage(a: t0 + 15 * 60 + 1) == .perime)
    }
}

/// Avant la premiere tournee d'une liaison, la sonde attend le premier releve Bonjour de l'app : sans lui, aucun enfant
/// n'est rattache sous les routeurs muets (banc du 12/10 : 2 enfants au lieu de 24 a chaque lancement). Pas un clic sur
/// rafraichir.
@MainActor
@Suite("Sonde : attente du premier releve Bonjour avant la premiere tournee")
struct AttenteReseauTests {
    // Une attente de 10 min sous une limite d'une minute : un test qui attendrait au lieu de partir echoue.
    /// Le premier releve Bonjour, recu ou non.
    final class Releve {
        var recu = false
    }

    /// Une sonde sur un canal rejoue, qui attend au plus `attente` le releve Bonjour (`connu`).
    /// Une tournee est partie : la sonde a demande la liste des routeurs (jamais hors tournee).
    static func tournee(_ c: CanalRejoue) -> Bool { c.envoyes.contains("routeurs\n") }

    static func sonde(_ p: UserDefaults, attente: Duration, connu: @escaping @MainActor () -> Bool)
        -> (SondeMaillage, CanalRejoue) {
        let canal = CanalRejoue { CanalRejoue.reseauMinimal($0) }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, attenteReseau: attente,
                              pasAttenteReseau: .milliseconds(10))
        s.reseauConnu = connu
        return (s, canal)
    }

    @Test(.timeLimit(.minutes(1))) func premiereTourneeApresLeReleve() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let releve = Releve()
        let (s, canal) = Self.sonde(p, attente: .seconds(600)) { releve.recu }
        await s.connecter(SondeMaillageTests.port, choisi: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!Self.tournee(canal) && !s.tourneeEnCours, "pas de tournee avant le releve")
        releve.recu = true
        await SondeMaillageTests.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        #expect(Self.tournee(canal), "le releve arrive : la tournee part sans attendre la limite")
        await s.oublier()
    }

    @Test(.timeLimit(.minutes(1))) func limiteSansReleve() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, _) = Self.sonde(p, attente: .milliseconds(100)) { false }
        await s.connecter(SondeMaillageTests.port, choisi: true)
        await SondeMaillageTests.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        await s.oublier()
    }

    @Test(.timeLimit(.minutes(1))) func rafraichirNAttendPas() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, canal) = Self.sonde(p, attente: .seconds(600)) { false }
        await s.connecter(SondeMaillageTests.port, choisi: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!Self.tournee(canal), "la liaison attend le releve")
        s.rafraichir()
        await SondeMaillageTests.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        await s.oublier()
    }

    @Test(.timeLimit(.minutes(1))) func oublierPendantLAttente() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, canal) = Self.sonde(p, attente: .seconds(600)) { false }
        await s.connecter(SondeMaillageTests.port, choisi: true)
        let boucle = try #require(s.boucle)
        await s.oublier()
        await boucle.value
        #expect(!Self.tournee(canal), "aucune tournee sur une liaison oubliee")
    }

    @Test(.timeLimit(.minutes(1))) func sansSourcePasDAttente() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let canal = CanalRejoue { CanalRejoue.reseauMinimal($0) }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, attenteReseau: .seconds(600))
        await s.connecter(SondeMaillageTests.port, choisi: true)
        await SondeMaillageTests.attendre { s.derniereTournee != nil && !s.tourneeEnCours }
        await s.oublier()
    }
}
