import CryptoKit
import Foundation
import MaillageCoeur
import Network
import Synchronization
import Testing
@testable import MaillageIoT

/// Transport UDP de la sonde, repris du pont Halo, sur une connexion et une carte simulees.
@Suite("Transport UDP de la sonde (reprise du pont Halo)")
struct TransportUDPTests {
    static func rapides() -> TransportUDP.Reglages {
        var r = TransportUDP.Reglages()
        r.attentePret = .milliseconds(300)
        r.attenteDefi = .milliseconds(100)
        return r
    }

    /// Transport vers la carte ; `connexions` recoit chaque connexion creee.
    static func transport(_ carte: CarteSimulee?, depart: ConnexionSimulee.Depart = .prete, cle: Data = VecteursH1.psk,
                          attentePret: Duration? = nil, connexions: ConnexionsSimulees? = nil) -> TransportUDP {
        var reglages = rapides()
        if let attentePret { reglages.attentePret = attentePret }
        return TransportUDP(hote: "0123456789ABCDEF.local", cle: cle, reglages: reglages) { hote, port in
            let c = ConnexionSimulee(hote: hote, port: port, carte: carte, depart: depart)
            connexions?.ajouter(c)
            return c
        }
    }

    /// Poignee de main, puis dialogue : chaque charge part scellee (ctr neuf a chaque envoi,
    /// meme charge renvoyee), chaque message de la carte arrive en sa charge seule.
    @Test func poigneeDeMainEtDialogue() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk)
        let connexions = ConnexionsSimulees()
        let t = Self.transport(carte, connexions: connexions)
        let recueil = RecueilLiaison(try await t.ouvrir())
        #expect(connexions.toutes.map { "\($0.hote):\($0.port)" } == ["0123456789ABCDEF.local:5480"])
        try t.envoyer(Data("1 bonjour".utf8))
        #expect(await attendreQue { carte.recues == ["1 bonjour"] })
        try t.envoyer(Data("1 bonjour".utf8))
        #expect(await attendreQue { carte.recues == ["1 bonjour", "1 bonjour"] }, "meme charge renvoyee, recue deux fois")
        #expect(carte.ctrsRecus.count == 2 && carte.ctrsRecus[0] < carte.ctrsRecus[1], "ctr neuf a chaque envoi")
        carte.envoyer(#"1 {"v":1,"t":"etat"}"#)
        #expect(await attendreQue { recueil.liste == [#"donnees 1 {"v":1,"t":"etat"}"#] })
        #expect(t.ecartes == 0)
    }

    /// Carte muette (sans cle, eteinte) : trois SALUT, `na` neuf a chaque essai, puis `aucunDefi`.
    @Test func carteMuette() async throws {
        let carte = CarteSimulee(cle: VecteursH1.psk, mode: .muette)
        let connexions = ConnexionsSimulees()
        let t = Self.transport(carte, connexions: connexions)
        await #expect(throws: ErreurReseau.aucunDefi) { _ = try await t.ouvrir() }
        #expect(carte.saluts == 3)
        #expect(Set(carte.nas).count == 3, "les 3 na sont distincts")
        let annulees = connexions.toutes.allSatisfy { $0.annulee }
        #expect(annulees, "connexion annulee")
    }

    @Test func autreCle() async throws {
        let t = Self.transport(CarteSimulee(cle: Data(repeating: 7, count: 32)))
        await #expect(throws: ErreurReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    /// DEFI calcule pour le `na` de l'essai precedent : rejete a chaque essai.
    @Test func defiPourUnNaPerime() async throws {
        let t = Self.transport(CarteSimulee(cle: VecteursH1.psk, mode: .defiNaPerime))
        await #expect(throws: ErreurReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    @Test func defiAuMacFaux() async throws {
        let t = Self.transport(CarteSimulee(cle: VecteursH1.psk, mode: .defiMacFaux))
        await #expect(throws: ErreurReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    /// Sans route, abandon tout de suite : la connexion en attente ne repartirait pas seule au
    /// retour de la route (banc du 25/09 de Halo) ; la reconnexion reessaie a son rythme.
    @Test func sansRouteAbandonneAvantOuverture() async throws {
        let t = Self.transport(CarteSimulee(cle: VecteursH1.psk), depart: .attente(.pasDeRoute), attentePret: .seconds(10))
        let debut = ContinuousClock.now
        await #expect(throws: ErreurReseau.pasDeRoute) { _ = try await t.ouvrir() }
        #expect(ContinuousClock.now - debut < .seconds(5), "bien avant la fin de attentePret")
        #expect(TransportUDP.abandonAvantOuverture(.pasDeRoute))
        #expect(!TransportUDP.abandonAvantOuverture(.reseauLocalRefuse))
        #expect(!TransportUDP.abandonAvantOuverture(.nomIntrouvable("x.local")))
    }

    /// Reseau local refuse : on attend (une reautorisation relance la connexion en attente),
    /// puis l'erreur gardee ; un nom qui ne se resout pas : introuvable.
    @Test func attenteSansOuverture() async throws {
        let refus = Self.transport(nil, depart: .attente(.reseauLocalRefuse))
        await #expect(throws: ErreurReseau.reseauLocalRefuse) { _ = try await refus.ouvrir() }
        let muet = Self.transport(nil, depart: .rien)
        await #expect(throws: ErreurReseau.nomIntrouvable("0123456789ABCDEF.local")) { _ = try await muet.ouvrir() }
        let echec = Self.transport(nil, depart: .echec(.pasDeRoute))
        await #expect(throws: ErreurReseau.pasDeRoute) { _ = try await echec.ouvrir() }
    }

    /// Session perdue apres l'ouverture : le flux se ferme sur « Connexion reseau perdue : <cause> ».
    @Test func perteEnSession() async throws {
        let connexions = ConnexionsSimulees()
        let t = Self.transport(CarteSimulee(cle: VecteursH1.psk), connexions: connexions)
        let recueil = RecueilLiaison(try await t.ouvrir())
        connexions.toutes.first?.echouer(.pasDeRoute)
        let raison = TransportUDP.raisonPerte(.pasDeRoute)
        #expect(await attendreQue { recueil.liste == ["ferme " + raison, "fin"] })
        #expect(raison == ErreurReseau.cheminPerdu(ErreurReseau.pasDeRoute.localizedDescription).localizedDescription)
        #expect(raison != ErreurReseau.pasDeRoute.localizedDescription)
        #expect(throws: ErreurReseau.self) { try t.envoyer(Data("2 etat".utf8)) }
    }

    /// Fermeture par l'app : fin du flux, connexion annulee, plus d'envoi.
    @Test func fermer() async throws {
        let connexions = ConnexionsSimulees()
        let t = Self.transport(CarteSimulee(cle: VecteursH1.psk), connexions: connexions)
        let recueil = RecueilLiaison(try await t.ouvrir())
        t.fermer()
        #expect(await attendreQue { recueil.liste.last == "fin" })
        let annulees = connexions.toutes.allSatisfy { $0.annulee }
        #expect(annulees)
        #expect(throws: ErreurReseau.self) { try t.envoyer(Data("2 etat".utf8)) }
    }

    /// Course de l'ouverture : un echec ou une fermeture arrive apres le dernier coup d'oeil de
    /// la poignee de main, avant la pose du flux ; le poser rendrait un flux jamais ferme.
    @Test func echecAvantLaPoseDuFluxLaRefuse() throws {
        let session = SessionH1(sid: "5A5A0001", ks: SymmetricKey(data: VecteursH1.psk))
        let t = Self.transport(nil)
        t.echec(.pasDeRoute)
        let (_, suite) = AsyncStream.makeStream(of: EvenementLiaison.self)
        #expect(throws: ErreurReseau.pasDeRoute) { try t.adopter(session, suite) }
        let f = Self.transport(nil)
        f.fermer()
        let (_, suiteF) = AsyncStream.makeStream(of: EvenementLiaison.self)
        #expect(throws: ErreurReseau.self) { try f.adopter(session, suiteF) }
        let o = Self.transport(nil)
        let (_, suiteO) = AsyncStream.makeStream(of: EvenementLiaison.self)
        try o.adopter(session, suiteO)
        o.fermer()
    }

    /// Erreurs de Network.framework classees comme dans Halo.
    @Test func erreurs() {
        #expect(!ErreurReseau.portInjoignable.repriseAutomatique)
        #expect(ErreurReseau.reseauLocalRefuse.repriseAutomatique)
        #expect(ErreurReseau.pasDeRoute.repriseAutomatique)
        #expect(ErreurReseau.aucunDefi.repriseAutomatique)
        #expect(ErreurReseau.depuis(.posix(.EHOSTUNREACH), chemin: nil, hote: "x.local") == .pasDeRoute)
        #expect(ErreurReseau.depuis(.posix(.ENETUNREACH), chemin: nil, hote: "x.local") == .pasDeRoute)
        #expect(ErreurReseau.depuis(.posix(.ENETDOWN), chemin: nil, hote: "x.local") == .pasDeRoute)
        // ICMPv6 "adresse injoignable" : le noeud ne repond pas, la route n'y est pour rien.
        #expect(ErreurReseau.depuis(.posix(.EHOSTDOWN), chemin: nil, hote: "x.local") == .nomIntrouvable("x.local"))
        #expect(ErreurReseau.depuis(.posix(.ECONNREFUSED), chemin: nil, hote: "x.local") == .portInjoignable)
        // NoSuchRecord aussitot pour un nom .local : refus du reseau local (banc R7 de Halo) ;
        // hors .local, c'est un vrai nom absent.
        #expect(ErreurReseau.depuis(.dns(-65554), chemin: nil, hote: "x.local") == .reseauLocalRefuse)
        #expect(ErreurReseau.depuis(.dns(-65554), chemin: nil, hote: "X.LOCAL.") == .reseauLocalRefuse)
        #expect(ErreurReseau.depuis(.dns(-65554), chemin: nil, hote: "sonde.example.org") == .nomIntrouvable("sonde.example.org"))
        #expect(ErreurReseau.depuis(.dns(-65537), chemin: nil, hote: "x.local") == .nomIntrouvable("x.local"))
        #expect(ErreurReseau.depuis(.dns(-65570), chemin: nil, hote: "x.local") == .reseauLocalRefuse)
        // Chaque cas a son texte ; celui de « pas de route » renvoie au README de ce depot, jamais
        // a un outil ou un chemin d'un autre depot.
        let cas: [ErreurReseau] = [.reseauLocalRefuse, .pasDeRoute, .nomIntrouvable("x.local"), .portInjoignable,
                                   .aucunDefi, .cheminPerdu("x"), .autre("x")]
        #expect(Set(cas.map(\.localizedDescription)).count == cas.count)
        let pasDeRoute = ErreurReseau.pasDeRoute.localizedDescription
        #expect(pasDeRoute.contains("README"))
        #expect(!["halo-routes", "benq", "tools/", ".sh"].contains { pasDeRoute.contains($0) }, "\(pasDeRoute)")
    }

    /// La vraie connexion (Network.framework), sur la boucle locale seulement, vers un port sans
    /// ecoute (9, discard) : prete, trois SALUT partis, puis port injoignable (ICMPv6, parfois
    /// seulement apres l'annulation : constat de Halo) ou aucun DEFI. Aucun trafic hors de ce Mac,
    /// aucun port ouvert en ecoute (les tests tournent dans l'app sandboxee, sans droit de serveur).
    @Test func connexionReelleSurLaBoucleLocale() async throws {
        var r = Self.rapides()
        r.port = 9
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: r)
        do {
            _ = try await t.ouvrir()
            Issue.record("session sans pair ?")
        } catch let e as ErreurReseau {
            #expect(e == .portInjoignable || e == .aucunDefi, "\(e)")
        }
    }

    /// La cle du transport n'apparait pas dans un dump.
    @Test func cleMasquee() {
        let t = Self.transport(nil)
        #expect(Mirror(reflecting: t).children.map(\.label) == ["hote"])
    }
}
