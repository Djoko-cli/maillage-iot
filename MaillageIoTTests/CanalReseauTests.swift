import Foundation
import MaillageCoeur
import ProtocoleThread
import Synchronization
import Testing
@testable import MaillageIoT

/// Lignes d'un canal, notees au fil de l'eau, puis `fin` a la fin du flux.
final class RecueilLignes: Sendable {
    private let lignes = Mutex<[String]>([])

    init(_ flux: AsyncStream<Data>) {
        Task { [self] in
            for await l in flux { noter(String(decoding: l, as: UTF8.self)) }
            noter("fin")
        }
    }

    private func noter(_ s: String) {
        lignes.withLock { $0.append(s) }
    }

    var liste: [String] { lignes.withLock { $0 } }
}

/// Canal reseau de la sonde (contrat 1.0.2) : rid, renvois, doublons, veille ; sur la carte
/// simulee, sans trafic reseau.
@Suite("Canal reseau de la sonde")
struct CanalReseauTests {
    static let hote = "0123456789ABCDEF"

    /// Renvois a 100 et 200 ms ; veille lointaine (hors des tests qui la visent).
    static func rapides(veille: Duration = .seconds(60), attenteVeille: Duration = .seconds(1)) -> CanalReseau.Reglages {
        var r = CanalReseau.Reglages()
        r.renvois = [.milliseconds(100), .milliseconds(200)]
        r.veille = veille
        r.attenteVeille = attenteVeille
        return r
    }

    static func canal(_ carte: CarteSimulee, reglages: CanalReseau.Reglages = rapides(),
                      connexions: ConnexionsSimulees? = nil) async throws -> CanalReseau {
        try await CanalReseau.connecter(hote: hote, cle: VecteursH1.psk, reglages: reglages,
                                        reglagesTransport: TransportUDPTests.rapides()) { h, p in
            let c = ConnexionSimulee(hote: h, port: p, carte: carte)
            connexions?.ajouter(c)
            return c
        }
    }

    /// `<rid> <commande>` -> rid et commande.
    static func decouper(_ charge: String) -> (rid: Int, commande: String)? {
        guard let espace = charge.firstIndex(of: " "), let rid = Int(charge[..<espace]) else { return nil }
        return (rid, String(charge[charge.index(after: espace)...]))
    }

    /// Une sonde du reseau minimal (`CanalRejoue.reseauMinimal`), chaque reponse precedee du rid.
    static func sonde(_ charge: String) -> [String] {
        guard let (rid, commande) = decouper(charge) else { return [] }
        return CanalRejoue.reseauMinimal(commande + "\n").map { "\(rid) \($0)" }
    }

    /// Chaque commande part en `<rid> <commande>`, rid croissants ; `SondeUSB` recoit les
    /// lignes JSON seules, comme par le canal serie ; la connexion vise `<hote>.local:5480`.
    @Test(.timeLimit(.minutes(1))) func ridEtLignesSeules() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let connexions = ConnexionsSimulees()
        let s = SondeUSB(canal: try await Self.canal(carte, connexions: connexions))
        try await s.demarrer {}
        #expect(try await s.bonjour().version == "1.0.0")
        #expect(try await s.etat().estAttachee)
        let recues = carte.recues.compactMap(Self.decouper)
        let commandes = recues.map { $0.commande }
        #expect(commandes == ["bonjour", "etat"])
        #expect(recues.count == 2 && recues[0].rid < recues[1].rid)
        let visees = connexions.toutes.map { "\($0.hote):\($0.port)" }
        #expect(visees == ["0123456789ABCDEF.local:5480"])
        await s.fermer()
    }

    /// Par le reseau, `SondeUSB` attend au-dela du second renvoi du canal : les deux premiers
    /// envois perdus, la reponse au second renvoi aboutit (ici renvois a 100 et 200 ms, attente
    /// de 800 ms, 600 ms de marge sous charge sans rien allonger ; dans l'app 2 et 4 s, attente
    /// de 6 s, et 3 s en USB).
    @Test(.timeLimit(.minutes(1))) func reponseAuSecondRenvoi() async throws {
        #expect(SondeUSB.delaiCommandeUSB == .seconds(3))
        #expect(SondeUSB.delaiCommandeReseau == .seconds(6))
        #expect(CanalReseau.Reglages().renvois == [.seconds(2), .seconds(4)])
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let s = SondeUSB(canal: try await Self.canal(carte), delaiCommande: .milliseconds(800))
        try await s.demarrer {}
        carte.perdre(2)
        #expect(try await s.bonjour().version == "1.0.0")
        carte.perdre(2)
        #expect(try await s.etat().estAttachee)
        #expect(carte.perdus == 4)
        await s.fermer()
    }

    /// Deux `etat` lents de suite par le reseau, comme au debut d'une tournee (`SondeMaillage`,
    /// puis `Tournee`) : chacun n'est servi qu'au second renvoi. L'echeance du premier, deja
    /// servi, n'expire pas le second, qui aboutit dans son propre delai (ici renvois a 0,4 et
    /// 0,8 s, attente de 1,2 s : l'app divisee par 5, renvois a 2 et 4 s, attente de 6 s).
    @Test(.timeLimit(.minutes(1))) func deuxEtatLentsDeSuite() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        var reglages = Self.rapides()
        reglages.renvois = [.milliseconds(400), .milliseconds(800)]
        let s = SondeUSB(canal: try await Self.canal(carte, reglages: reglages), delaiCommande: .milliseconds(1200))
        try await s.demarrer {}
        carte.perdre(2)
        #expect(try await s.etat().estAttachee)
        carte.perdre(2)
        #expect(try await s.etat().estAttachee, "le second, servi apres l'echeance du premier")
        #expect(carte.perdus == 4)
        await s.fermer()
    }

    /// Une tournee entiere par le reseau : le maillage du reseau minimal, table des routeurs
    /// comprise (la carte simulee repond a `routeurs`, sans attente du delai).
    @Test(.timeLimit(.minutes(1))) func tourneeParLeReseau() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let s = SondeUSB(canal: try await Self.canal(carte))
        try await s.demarrer {}
        let r = try await Tournee.executer(s, memoire: MemoireTournee(), maintenant: Date(timeIntervalSince1970: 1_790_000_000))
        let routeurs = r.maillage?.routeurs.map { $0.id }
        #expect(routeurs == [0])
        #expect(carte.recues.compactMap(Self.decouper).map(\.commande).contains("routeurs"))
        await s.fermer()
    }

    /// `routeurs` sur plusieurs lignes par le reseau (meme rid, `suite`) : chaque ligne traverse
    /// le canal, et `SondeUSB.routeurs()` rend la table entiere, dans l'ordre (ExtMac inventees).
    @Test(.timeLimit(.minutes(1))) func routeursSurPlusieursLignesParLeReseau() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk) { charge in
            guard let (rid, commande) = Self.decouper(charge), commande == "routeurs" else { return Self.sonde(charge) }
            return [CanalRejoue.routeurs([("0400", nil), ("AC00", "E0000000000000AC")], suite: true),
                    CanalRejoue.routeurs([("E400", "E0000000000000E4")], suite: true),
                    CanalRejoue.routeurs([("F000", nil)], suite: false)].map { "\(rid) \($0)" }
        }
        let s = SondeUSB(canal: try await Self.canal(carte))
        try await s.demarrer {}
        let table = try await s.routeurs()
        #expect(table.map(\.rloc16) == ["0400", "AC00", "E400", "F000"])
        #expect(table.map(\.ext) == [nil, "E0000000000000AC", "E0000000000000E4", nil])
        #expect(Set(carte.recues.compactMap(Self.decouper).map(\.commande)) == ["routeurs"])
        await s.fermer()
    }

    /// Sans aucune reponse, la commande repart avec le meme rid a 2 s puis 4 s (ici 100 et
    /// 200 ms), et plus ensuite.
    @Test func renvoisDuMemeRid() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk)  // ne repond a rien
        let c = try await Self.canal(carte)
        _ = RecueilLignes(try c.ouvrir())
        c.envoyer("etat\n")
        #expect(await attendreQue { carte.recues.count == 3 })
        try await Task.sleep(for: .milliseconds(300))
        let recues = carte.recues
        #expect(recues.count == 3, "premier envoi et deux renvois, pas plus")
        #expect(Set(recues).count == 1, "meme rid, meme commande")
        let ctrs = carte.ctrsRecus
        #expect(ctrs == ctrs.sorted() && Set(ctrs).count == 3, "ctr neuf a chaque envoi")
        c.fermer()
    }

    /// Charges arrivees a la carte, avec leur heure.
    final class Arrivees: Sendable {
        private let liste = Mutex<[(charge: String, quand: ContinuousClock.Instant)]>([])

        func noter(_ charge: String) {
            liste.withLock { $0.append((charge, .now)) }
        }

        var toutes: [(charge: String, quand: ContinuousClock.Instant)] { liste.withLock { $0 } }
    }

    /// Carte simulee qui note ses arrivees ; `repondre` donne les reponses.
    static func carteNotee(_ arrivees: Arrivees, repondre: @escaping @Sendable (String) -> [String]) -> CarteSimulee {
        CarteSimulee(cle: VecteursH1.psk) { charge in
            arrivees.noter(charge)
            return repondre(charge)
        }
    }

    /// Cadence de la carte (20 commandes par seconde glissante et par session, au-dela rien) :
    /// 30 commandes emises d'un coup partent dans l'ordre, 18 nouvelles par seconde au plus,
    /// etalees sur plus d'une seconde. Sans renvoi (la carte repond, renvois a 30 s) : chaque
    /// arrivee est un premier envoi, quelle que soit la lenteur d'une reponse.
    @Test(.timeLimit(.minutes(1))) func cadenceDesNouvellesCommandes() async throws {
        let arrivees = Arrivees()
        let carte = Self.carteNotee(arrivees, repondre: Self.sonde)
        var reglages = Self.rapides()
        reglages.renvois = [.seconds(30), .seconds(60)]
        let c = try await Self.canal(carte, reglages: reglages)
        let lignes = RecueilLignes(try c.ouvrir())
        for _ in 0..<30 { c.envoyer("etat\n") }
        #expect(await attendreQue { lignes.liste.count == 30 })
        let a = arrivees.toutes
        let rids = a.compactMap { Self.decouper($0.charge)?.rid }
        #expect(rids.count == 30 && rids == rids.sorted() && Set(rids).count == 30, "dans l'ordre, sans renvoi")
        let t = a.map(\.quand)
        #expect(t.count == 30 && t[18] - t[0] >= .milliseconds(950), "la 19e attend la fenetre d'une seconde")
        c.fermer()
    }

    /// La cadence tient au-dela de la premiere fenetre, et la fenetre est glissante : 9 commandes,
    /// puis 27 autres une demi-fenetre plus tard. La carte n'en voit jamais plus de 18 en une
    /// seconde : la 19e attend la sortie de la 1re, la 28e celle de la 10e. Une fenetre remise a
    /// zero par tranches laisserait partir les 18 dernieres d'un coup (0,5 s entre la 10e et la
    /// 28e). Sans renvoi (la carte repond, renvois a 30 s) : chaque arrivee est un premier envoi.
    @Test(.timeLimit(.minutes(1))) func cadenceGlissanteAuDelaDeLaPremiereFenetre() async throws {
        let defauts = CanalReseau.Reglages()
        #expect(defauts.cadence == 18 && defauts.fenetreCadence == .seconds(1))
        let arrivees = Arrivees()
        let carte = Self.carteNotee(arrivees, repondre: Self.sonde)
        var reglages = Self.rapides()
        reglages.renvois = [.seconds(30), .seconds(60)]
        let c = try await Self.canal(carte, reglages: reglages)
        defer { c.fermer() }
        let lignes = RecueilLignes(try c.ouvrir())
        for _ in 0..<9 { c.envoyer("etat\n") }
        #expect(await attendreQue { arrivees.toutes.count == 9 })
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<27 { c.envoyer("etat\n") }
        #expect(await attendreQue(.seconds(20)) { lignes.liste.count == 36 })
        let a = arrivees.toutes
        let rids = a.compactMap { Self.decouper($0.charge)?.rid }
        #expect(rids.count == 36 && rids == rids.sorted() && Set(rids).count == 36, "dans l'ordre, sans renvoi")
        let t = a.map(\.quand)
        try #require(t.count == 36)
        #expect(t[9] - t[0] >= .milliseconds(450), "les deux groupes sont separes d'une demi-fenetre")
        let ecarts = (0..<(t.count - 18)).map { t[$0 + 18] - t[$0] }
        let plusCourt = ecarts.min() ?? .zero
        #expect(plusCourt >= defauts.fenetreCadence - .milliseconds(100), "jamais plus de 18 en une fenetre glissante")
    }

    /// Les renvois ne comptent pas dans la cadence et partent a l'heure, meme quand des
    /// nouvelles commandes l'attendent (ici renvois a 300 et 600 ms, carte muette).
    @Test(.timeLimit(.minutes(1))) func renvoisHorsCadence() async throws {
        let arrivees = Arrivees()
        let carte = Self.carteNotee(arrivees) { _ in [] }
        var reglages = Self.rapides()
        reglages.renvois = [.milliseconds(300), .milliseconds(600)]
        let c = try await Self.canal(carte, reglages: reglages)
        _ = RecueilLignes(try c.ouvrir())
        let debut = ContinuousClock.now
        for _ in 0..<30 { c.envoyer("etat\n") }
        #expect(await attendreQue { arrivees.toutes.count == 90 }, "30 commandes, deux renvois chacune")
        let a = arrivees.toutes
        let premiere = try #require(a.first?.charge)
        let envois = a.filter { $0.charge == premiere }.map { $0.quand - debut }
        #expect(envois.count == 3)
        #expect(envois.count == 3 && envois[1] >= .milliseconds(300) && envois[1] < .milliseconds(800), "renvoi de 300 ms a l'heure")
        #expect(envois.count == 3 && envois[2] >= .milliseconds(600) && envois[2] < .milliseconds(900), "renvoi de 600 ms a l'heure")
        var nouvelles: [String] = []
        for x in a where !nouvelles.contains(x.charge) { nouvelles.append(x.charge) }
        let dixNeuvieme = try #require(nouvelles.count == 30 ? nouvelles[18] : nil)
        let quand = try #require(a.first { $0.charge == dixNeuvieme }?.quand) - debut
        #expect(quand >= .milliseconds(950) && quand < .milliseconds(1400), "les renvois ne retardent pas la 19e")
        c.fermer()
    }

    /// Renvois de l'app, comptes depuis le premier envoi : 2 et 4 s ; pour un `diag`, qui reste
    /// muet cote carte tant qu'il est en vol (son delai, lu dans la commande), ensuite 1 s apres
    /// la fin du vol puis tous les 3 s, le dernier au plus tard 1 s avant l'echeance de
    /// `SondeUSB` (le delai plus 5 s) : aucun renvoi pendant le vol au-dela de 4 s.
    @Test func renvoisSelonLaCommande() {
        let r = CanalReseau.Reglages()
        let s: (Int) -> Duration = { .seconds($0) }
        #expect(r.renvois(pour: "diag 5000 1 1 6000") == [s(2), s(4), s(7), s(10)])
        #expect(r.renvois(pour: "diag 0400 0,1,2,6,9,24,26 12 8000") == [s(2), s(4), s(9), s(12)])
        #expect(r.renvois(pour: "diag 5000 1 1 3000") == [s(2), s(4), s(7)])
        #expect(r.renvois(pour: "diag 5000 1 1 10000") == [s(2), s(4), s(11), s(14)])
        #expect(r.renvois(pour: "diag 5000 1 1 0") == [s(2), s(4)])
        #expect(r.renvois(pour: "diag 5000 1 1") == [s(2), s(4)], "sans delai lisible : comme les autres")
        for commande in ["bonjour", "etat", "voisins", "routeurs", "annonces"] {
            #expect(r.renvois(pour: commande) == [s(2), s(4)])
        }
        #expect(SondeUSB.margeDiag == r.margeDiag, "echeance de SondeUSB")
        // Une resolution (firmware 1.1.0) reste en vol 15 s au plus : renvois a 2 et 4 s, puis 16 et 19 s.
        #expect(r.renvois(pour: "resoudre fd00:aaaa:bbbb:1::17 7") == [s(2), s(4), s(16), s(19)])
        #expect(r.renvois(pour: "resoudre fd00:aaaa:bbbb:1::17") == [s(2), s(4)], "sans id : comme les autres")
        #expect(r.volResolution == SondeUSB.delaiResolution)
    }

    /// Reponse d'un `diag` perdue une fois apres le vol (la carte, muette pendant le vol, la garde
    /// et la rend a un renvoi du meme rid) : le renvoi suivant la ramene, avant l'echeance de
    /// `SondeUSB`. Ici tout divise par 10 : renvois a 200 et 400 ms, puis 100 ms apres le delai
    /// du diag (600 ms) et tous les 300 ms, soit 0,7 et 1 s ; vol de 550 ms, a 150 ms des
    /// renvois de 400 et 700 ms ; marge de 500 ms (echeance a 1,1 s).
    @Test(.timeLimit(.minutes(1))) func diagRedemandeApresLeVol() async throws {
        let vol: Duration = .milliseconds(550)
        let premiers = Mutex<[Int: ContinuousClock.Instant]>([:])
        let carte = CarteSimulee(cle: VecteursH1.psk) { charge in
            guard let (rid, commande) = Self.decouper(charge), commande.hasPrefix("diag ") else { return Self.sonde(charge) }
            let maintenant = ContinuousClock.now
            let debut = premiers.withLock { p in
                if p[rid] == nil { p[rid] = maintenant }
                return p[rid] ?? maintenant
            }
            // En vol : rien ; a la fin du vol, la reponse part et se perd ; ensuite, gardee, elle
            // repond a un renvoi du meme rid.
            return maintenant - debut >= vol ? Self.sonde(charge) : []
        }
        var reglages = Self.rapides()
        reglages.renvois = [.milliseconds(200), .milliseconds(400)]
        reglages.apresVolDiag = .milliseconds(100)
        reglages.pasDiag = .milliseconds(300)
        reglages.margeDiag = .milliseconds(500)
        reglages.avanceDiag = .milliseconds(100)
        let s = SondeUSB(canal: try await Self.canal(carte, reglages: reglages), marge: reglages.margeDiag)
        try await s.demarrer {}
        let r = try await s.diag(0x0000, [5, 6], delaiMs: 600)
        #expect(r.ok, "reponse gardee, rendue au renvoi apres le vol")
        // Au-dela du renvoi suivant (1 s) : il ne part pas, la reponse l'a annule.
        try await Task.sleep(for: .milliseconds(400))
        let diags = carte.recues.compactMap(Self.decouper).filter { $0.commande.hasPrefix("diag ") }
        #expect(diags.count == 4, "envoi, renvois a 200 et 400 ms pendant le vol, renvoi a 700 ms ; pas celui de 1 s")
        #expect(Set(diags.map(\.rid)).count == 1, "meme rid")
        await s.fermer()
    }

    /// Premier envoi perdu : le renvoi passe, la reponse arrive, et plus rien ne repart.
    @Test func renvoiApresUnePerte() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        var reglages = Self.rapides()
        reglages.renvois = [.milliseconds(100), .milliseconds(600)]
        let c = try await Self.canal(carte, reglages: reglages)
        let lignes = RecueilLignes(try c.ouvrir())
        carte.perdre(1)
        c.envoyer("etat\n")
        #expect(await attendreQue { lignes.liste == [CanalRejoue.etatAttache] })
        try await Task.sleep(for: .milliseconds(700))
        #expect(carte.recues.count == 1, "le renvoi seul arrive ; aucun autre apres la reponse")
        c.fermer()
    }

    /// Doublons ecartes (meme rid, meme ligne : reponse renvoyee par la carte) ; plusieurs
    /// lignes d'une meme reponse (`routeurs`, `suite`) passent toutes.
    @Test func doublonsEcartes() async throws {
        let l1 = #"{"v":1,"t":"routeurs","liste":[],"suite":true}"#
        let l2 = #"{"v":1,"t":"routeurs","liste":[],"suite":false}"#
        let carte = CarteSimulee(cle: VecteursH1.psk) { charge in
            guard let (rid, commande) = Self.decouper(charge) else { return [] }
            if commande == "routeurs" { return ["\(rid) \(l1)", "\(rid) \(l1)", "\(rid) \(l2)", "\(rid) \(l2)"] }
            return Self.sonde(charge)
        }
        let c = try await Self.canal(carte)
        let lignes = RecueilLignes(try c.ouvrir())
        c.envoyer("routeurs\n")
        c.envoyer("etat\n")
        #expect(await attendreQue { lignes.liste.count == 3 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(lignes.liste == [l1, l2, CanalRejoue.etatAttache])
        c.fermer()
    }

    /// Charge sans rid, rid illisible ou ligne vide : ecartee.
    @Test func chargesIllisiblesEcartees() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let c = try await Self.canal(carte)
        let lignes = RecueilLignes(try c.ouvrir())
        c.envoyer("etat\n")  // ouvre la session cote carte (adresse de reponse)
        #expect(await attendreQue { lignes.liste.count == 1 })
        for charge in [CanalRejoue.bonjour, "x " + CanalRejoue.bonjour, "12", "12 ", "-3 " + CanalRejoue.bonjour] {
            carte.envoyer(charge)
        }
        carte.envoyer("99 " + CanalRejoue.bonjour)
        #expect(await attendreQue { lignes.liste.count == 2 })
        #expect(lignes.liste == [CanalRejoue.etatAttache, CanalRejoue.bonjour])
        c.fermer()
    }

    /// La cle ne passe jamais par le reseau : `cle ...` n'est pas envoye (la carte le
    /// refuserait ; l'alea n'a rien a faire sur le reseau).
    @Test func jamaisDeCleParLeReseau() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let c = try await Self.canal(carte)
        let lignes = RecueilLignes(try c.ouvrir())
        c.envoyer(CommandeSonde.cleNouvelle(alea: Data(repeating: 0xAB, count: 32), id: 3).ligne)
        c.envoyer("cle\n")
        c.envoyer("etat\n")
        #expect(await attendreQue { lignes.liste.count == 1 })
        let commandes = carte.recues.compactMap(Self.decouper).map { $0.commande }
        #expect(commandes == ["etat"])
        c.fermer()
    }

    /// Silence : un `etat` de veille, dont la reponse n'est pas transmise ; le canal reste ouvert.
    @Test func veille() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let c = try await Self.canal(carte, reglages: Self.rapides(veille: .milliseconds(150), attenteVeille: .seconds(2)))
        let lignes = RecueilLignes(try c.ouvrir())
        #expect(await attendreQue { carte.recues.count >= 2 }, "une veille apres chaque silence")
        let veilles = carte.recues.compactMap(Self.decouper).allSatisfy { $0.commande == "etat" }
        #expect(veilles)
        #expect(lignes.liste.isEmpty, "reponses de veille gardees par le canal")
        c.fermer()
        #expect(await attendreQue { lignes.liste == ["fin"] })
    }

    /// Reglages de l'app : la veille part apres 10 s de silence, comme le ping de Halo, bien avant
    /// les 30 s au-dela desquelles la carte donne la place d'une session muette a un autre client ;
    /// pas de la garde de 1 s, reponse a la veille attendue 6 s. Les pas de la garde sont joues ici
    /// a 9,9 s puis a 10 s du dernier recu (l'ouverture), sans attendre.
    @Test func veilleApresDixSecondes() async throws {
        let r = CanalReseau.Reglages()
        #expect(r.veille == .seconds(10))
        #expect(r.attenteVeille == .seconds(6))
        #expect(r.pasGarde == .seconds(1))
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let c = try await Self.canal(carte, reglages: r)
        let lignes = RecueilLignes(try c.ouvrir())
        let ouverture = ContinuousClock.now
        #expect(c.surveiller(maintenant: ouverture + .milliseconds(9900)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(carte.recues.isEmpty, "pas de veille avant 10 s")
        #expect(c.surveiller(maintenant: ouverture + .seconds(10)))
        #expect(await attendreQue(.seconds(1)) { !carte.recues.isEmpty })
        #expect(carte.recues.compactMap(Self.decouper).map(\.commande) == ["etat"], "la veille, a 10 s")
        #expect(lignes.liste.isEmpty)
        c.fermer()
    }

    /// La veille et ses renvois perdus, mais une autre reponse arrive ensuite : la sonde est
    /// vivante, le canal reste ouvert.
    @Test func veillePerdueMaisSondeVivante() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let c = try await Self.canal(carte, reglages: Self.rapides(veille: .milliseconds(100), attenteVeille: .seconds(1)))
        let lignes = RecueilLignes(try c.ouvrir())
        carte.perdre(3)
        #expect(await attendreQue { carte.perdus == 3 }, "veille et ses deux renvois perdus")
        c.envoyer("etat\n")
        #expect(await attendreQue { lignes.liste == [CanalRejoue.etatAttache] })
        try await Task.sleep(for: .milliseconds(1500))
        #expect(!lignes.liste.contains("fin"), "canal toujours ouvert")
        c.fermer()
    }

    /// Veille levee par une autre reponse : ses renvois s'arretent (ici veille apres 1 s de
    /// silence, perdue ; renvois prevus a +400 ms et +1 s). Le pas de la garde qui la leve est
    /// joue des la reponse (`surveiller`), sans attendre le sien : 400 ms de marge avant le
    /// renvoi, et 400 ms entre le constat et la veille suivante (1 s apres la reponse).
    @Test func veilleLeveeSansRenvoi() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        var reglages = Self.rapides(veille: .seconds(1), attenteVeille: .seconds(3))
        reglages.renvois = [.milliseconds(400), .seconds(1)]
        let c = try await Self.canal(carte, reglages: reglages)
        let lignes = RecueilLignes(try c.ouvrir())
        carte.perdre(1)
        #expect(await attendreQue { carte.perdus == 1 }, "veille perdue")
        c.envoyer("etat\n")
        #expect(await attendreQue { lignes.liste == [CanalRejoue.etatAttache] })
        #expect(c.surveiller(), "veille levee, canal ouvert")
        try await Task.sleep(for: .milliseconds(600))
        let commandes = carte.recues.compactMap(Self.decouper).map { $0.commande }
        #expect(commandes == ["etat"], "le renvoi de la veille levee ne part pas")
        c.fermer()
    }

    /// Fermee, la garde s'arrete.
    @Test func gardeArreteeALaFermeture() async throws {
        let c = try await Self.canal(CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde))
        _ = RecueilLignes(try c.ouvrir())
        #expect(c.surveiller())
        c.fermer()
        #expect(!c.surveiller())
    }

    /// Sonde debranchee : la veille reste sans reponse, le canal se ferme (fin du flux).
    @Test func veilleSansReponseFermeLeCanal() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let connexions = ConnexionsSimulees()
        let c = try await Self.canal(carte, reglages: Self.rapides(veille: .milliseconds(100), attenteVeille: .milliseconds(300)),
                                     connexions: connexions)
        let lignes = RecueilLignes(try c.ouvrir())
        #expect(c.raisonFermeture == nil)
        carte.eteindre()
        #expect(await attendreQue { lignes.liste == ["fin"] })
        let annulees = connexions.toutes.allSatisfy { $0.annulee }
        #expect(annulees, "transport ferme")
        // La cause, montree comme dans Halo : « Connexion reseau perdue : la sonde ne repond plus… ».
        #expect(c.raisonFermeture == CanalReseau.raisonSilence)
        #expect(CanalReseau.raisonSilence.hasPrefix(ErreurReseau.cheminPerdu("").localizedDescription))
    }

    /// Fermeture par l'app, ou session perdue : fin du flux des lignes.
    @Test func fermetures() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde)
        let connexions = ConnexionsSimulees()
        let c = try await Self.canal(carte, connexions: connexions)
        let lignes = RecueilLignes(try c.ouvrir())
        c.fermer()
        #expect(await attendreQue { lignes.liste == ["fin"] })
        #expect(throws: (any Error).self) { _ = try c.ouvrir() }
        let d = try await Self.canal(carte, connexions: connexions)
        let lignesD = RecueilLignes(try d.ouvrir())
        connexions.toutes.last?.echouer(.pasDeRoute)
        #expect(await attendreQue { lignesD.liste == ["fin"] })
        #expect(d.raisonFermeture == TransportUDP.raisonPerte(.pasDeRoute), "cause de la perte gardee")
    }

    /// Canal sature : 30 commandes d'un coup, les 18 de la premiere fenetre partent et 12 attendent
    /// la cadence. La carte repond, sans renvoi pendant l'essai (renvois a 30 s).
    static func canalSature() async throws -> (canal: CanalReseau, arrivees: Arrivees, lignes: RecueilLignes) {
        let arrivees = Arrivees()
        var reglages = rapides()
        reglages.renvois = [.seconds(30), .seconds(60)]
        let c = try await canal(carteNotee(arrivees, repondre: sonde), reglages: reglages)
        let lignes = RecueilLignes(try c.ouvrir())
        for _ in 0..<30 { c.envoyer("etat\n") }
        #expect(await attendreQue { arrivees.toutes.count == 18 }, "la premiere fenetre est partie, 12 commandes attendent")
        return (c, arrivees, lignes)
    }

    /// Fermee pendant que des commandes attendent la cadence : elles ne partent pas, ni a la
    /// fermeture ni meme une fois la fenetre ecoulee (les 12 en file seraient parties 1 s apres les
    /// 18) ; le flux des lignes finit.
    @Test(.timeLimit(.minutes(1))) func fermeeAvecUneFileNonVide() async throws {
        let (c, arrivees, lignes) = try await Self.canalSature()
        c.fermer()
        #expect(await attendreQue { lignes.liste.last == "fin" }, "fin du flux des lignes")
        try await Task.sleep(for: .milliseconds(1300))
        #expect(arrivees.toutes.count == 18, "les 12 en file ne partent pas")
    }

    /// Fermee avant d'etre ouverte (connexion abandonnee) : flux fini aussitot.
    @Test func fermeeAvantOuverture() async throws {
        let c = try await Self.canal(CarteSimulee(cle: VecteursH1.psk, repondre: Self.sonde))
        c.fermer()
        let lignes = RecueilLignes(try c.ouvrir())
        #expect(await attendreQue { lignes.liste == ["fin"] })
    }

    /// Carte muette ou autre cle : la connexion echoue (aucun DEFI).
    @Test func connexionSansReponse() async throws {
        await #expect(throws: ErreurReseau.aucunDefi) {
            _ = try await Self.canal(CarteSimulee(cle: VecteursH1.psk, mode: .muette))
        }
    }
}
