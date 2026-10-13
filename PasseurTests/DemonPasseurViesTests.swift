import Foundation
import Testing

@MainActor
@Suite("Demon Passeur Noms : identifier, ouverture, duree de vie, releve ponctuel")
struct DemonPasseurViesTests {
    static let uuid = UUID(uuidString: "8D3C2A10-0000-4000-8000-000000000001")!

    // MARK: Identifier

    @Test func identifier() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        b.maison.issues[Self.uuid] = .ok
        await b.demon.recevoir(.identifier(demande: 1, accessoire: Self.uuid.uuidString), de: l)
        b.maison.issues[Self.uuid] = .nonIdentifiable
        await b.demon.recevoir(.identifier(demande: 2, accessoire: Self.uuid.uuidString), de: l)
        b.maison.issues[Self.uuid] = .erreur("hors de portée")
        await b.demon.recevoir(.identifier(demande: 3, accessoire: Self.uuid.uuidString), de: l)
        await b.demon.recevoir(.identifier(demande: 4, accessoire: UUID().uuidString), de: l)
        #expect(l.reponses == [ReponseIdentifier(demande: 1, ok: true),
                               ReponseIdentifier(demande: 2, ok: false, erreur: ReponseIdentifier.nonIdentifiable),
                               ReponseIdentifier(demande: 3, ok: false, erreur: "hors de portée"),
                               ReponseIdentifier(demande: 4, ok: false, erreur: ReponseIdentifier.inconnu)])
    }

    /// Un identifiant qui n'est pas un UUID : inconnu, sans demander a Maison.
    @Test func identifiantIllisible() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        await b.demon.recevoir(.identifier(demande: 9, accessoire: "pas-un-uuid"), de: l)
        #expect(l.reponses == [ReponseIdentifier(demande: 9, ok: false, erreur: ReponseIdentifier.inconnu)])
        #expect(b.maison.identifies.isEmpty)
    }

    // MARK: Ouverture de session

    /// Inscription : SMAppService appele, `etat` a jour chez tous les abonnes.
    @Test func ouvertureSession() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner(port: 50_000))
        let autre = try #require(await b.abonner(port: 50_001))
        await b.demon.recevoir(.ouvertureSession(actif: true), de: l)
        #expect(b.ouverture.reglages == [true])
        #expect(l.etats.last?.ouvertureSession == .active)
        #expect(autre.etats.last?.ouvertureSession == .active)
    }

    /// Echec de l'inscription : `etat` repart quand meme, avec l'etat reel (l'interrupteur de l'app revient).
    @Test func ouvertureRefusee() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        b.ouverture.erreur = "Operation not permitted"
        await b.demon.recevoir(.ouvertureSession(actif: true), de: l)
        #expect(l.etats.count == 2)
        #expect(l.etats.last?.ouvertureSession == .inactive)
    }

    /// L'ouverture a la session change hors de l'app (Reglages Systeme) : la verification de 60 s le diffuse.
    @Test func ouvertureChangeeHorsDeLApp() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner(port: 50_000))
        let autre = try #require(await b.abonner(port: 50_001))
        let avant = (l.etats.count, autre.etats.count)
        b.ouverture.statut = .active
        await b.horloge.avancer(.seconds(59))
        #expect(l.etats.count == avant.0 && autre.etats.count == avant.1, "pas avant 60 s")
        await b.horloge.avancer(.seconds(1))
        #expect(l.etats.count == avant.0 + 1 && l.etats.last?.ouvertureSession == .active)
        #expect(autre.etats.count == avant.1 + 1 && autre.etats.last?.ouvertureSession == .active)
    }

    /// Rien n'a change : la verification de 60 s n'envoie aucun `etat`.
    @Test func verificationSansChangementSilencieuse() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        let avant = l.etats.count
        await b.horloge.avancer(.seconds(300))
        #expect(l.etats.count == avant)
    }

    /// Un changement silencieux, puis un nouvel abonne : l'ancien recoit aussi le nouvel etat.
    @Test func nouvelAbonneDiffuseLeChangementSilencieux() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let ancien = try #require(await b.abonner(port: 50_000))
        let avant = ancien.etats.count
        b.ouverture.statut = .active
        let nouveau = try #require(await b.abonner(port: 50_001))
        #expect(ancien.etats.count == avant + 1 && ancien.etats.last?.ouvertureSession == .active)
        #expect(nouveau.etats.count == 1 && nouveau.etats.last?.ouvertureSession == .active)
    }

    // MARK: Duree de vie

    @Test func fermeture10MinApresLeDernier() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        await b.horloge.avancer(.seconds(3000))
        #expect(b.sorties.isEmpty, "un abonne : le demon reste")
        l.partir()
        await b.horloge.avancer(.seconds(599))
        #expect(b.sorties.isEmpty)
        await b.horloge.avancer(.seconds(1))
        #expect(b.sorties == ["aucun abonné depuis 10 minutes"])
    }

    @Test func nouvelAbonneAnnuleLaFermeture() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner(port: 50_000))
        l.partir()
        await b.horloge.avancer(.seconds(300))
        _ = await b.abonner(port: 50_001)
        await b.horloge.avancer(.seconds(3000))
        #expect(b.sorties.isEmpty)
    }

    @Test func sansAbonneAuLancement() async {
        let b = BancDemon(noms: BancDemon.noms())
        // Maison repond au lancement : sans cela, le controle de 100 s fermerait le demon avant.
        b.maison.changer()
        await b.horloge.avancer(.seconds(600))
        #expect(b.sorties == ["aucun abonné depuis 10 minutes"])
    }

    @Test func ouvertureActiveNeFermeJamais() async throws {
        let b = BancDemon(statut: .active, noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        l.partir()
        await b.horloge.avancer(.seconds(7200))
        #expect(b.sorties.isEmpty)
    }

    /// Desinscrit par un abonne qui part ensuite : la fermeture reprend.
    @Test func desinscriptionPuisDepart() async throws {
        let b = BancDemon(statut: .active, noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        await b.demon.recevoir(.ouvertureSession(actif: false), de: l)
        l.partir()
        await b.horloge.avancer(.seconds(600))
        #expect(b.sorties.count == 1)
    }

    // MARK: Releve ponctuel

    /// Le releve ponctuel part au format de la version 1, sans `id` ; puis le demon se ferme.
    @Test func ponctuelEnVersion1() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        await b.demon.recevoir(url: BancDemon.url(.releve, port: 50_123))
        let p = try #require(b.ponctuels.first)
        #expect(p.cible.port == 50_123 && p.cible.demande == .releve)
        let n = try NomsMaison.lire(p.json)
        #expect(n.version == 1)
        #expect(n.accessoires.allSatisfy { $0.id == nil })
        #expect(n.accessoires.first?.nom == "Halo")
        #expect(b.sorties.isEmpty, "pas avant la fin de l'envoi")
        b.finirPonctuels()
        #expect(b.sorties == ["relevé ponctuel envoyé, aucun abonné"])
    }

    @Test func ponctuelAvecAbonneNeFermePas() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        _ = await b.abonner()
        await b.demon.recevoir(url: BancDemon.url(.releve))
        b.finirPonctuels()
        #expect(b.sorties.isEmpty)
    }

    @Test func ponctuelOuvertureActiveNeFermePas() async {
        let b = BancDemon(statut: .active, noms: BancDemon.noms())
        await b.demon.recevoir(url: BancDemon.url(.releve))
        b.finirPonctuels()
        #expect(b.sorties.isEmpty)
    }

    /// Maison pas encore prete : le releve part des qu'elle repond.
    @Test func ponctuelAttendMaison() async {
        let b = BancDemon()
        await b.demon.recevoir(url: BancDemon.url(.releve))
        #expect(b.ponctuels.isEmpty)
        b.maison.noms = BancDemon.noms()
        b.maison.changer()
        await b.horloge.avancer(.seconds(2))
        #expect(b.ponctuels.count == 1)
        await b.horloge.avancer(.seconds(600))
        #expect(b.sorties.isEmpty, "pas de fermeture pendant l'envoi")
    }

    /// Maison muette pendant 100 s : un releve en erreur, comme l'ancien passeur.
    @Test func ponctuelMaisonMuette() async throws {
        let b = BancDemon()
        await b.demon.recevoir(url: BancDemon.url(.releve))
        await b.horloge.avancer(.seconds(99))
        #expect(b.ponctuels.isEmpty)
        await b.horloge.avancer(.seconds(1))
        let n = try NomsMaison.lire(try #require(b.ponctuels.first).json)
        #expect(n.statut == .erreur)
        #expect(n.message == "Maison n'a pas répondu")
    }

    // MARK: Maison muette apres un lancement a froid par une ancienne app

    static let raisonMaisonMuette = "HomeKit ne répond pas : relance sans URL"

    /// Acces accorde, aucun releve ok en 100 s : le demon se ferme, meme avec un abonne (l'app se reabonne et le relance).
    @Test func maisonMuetteFermeLeDemonMemeAvecAbonne() async throws {
        let b = BancDemon()
        _ = await b.abonner()
        await b.horloge.avancer(.seconds(99))
        #expect(b.sorties.isEmpty)
        await b.horloge.avancer(.seconds(1))
        #expect(b.sorties == [Self.raisonMaisonMuette])
        await b.horloge.avancer(.seconds(3600))
        #expect(b.sorties == [Self.raisonMaisonMuette], "une seule sortie")
    }

    /// Un releve ok lu avant 100 s : le demon reste.
    @Test func maisonRepondueAvant100sNeFermePas() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        _ = await b.abonner()
        await b.horloge.avancer(.seconds(100))
        #expect(b.sorties.isEmpty)
    }

    /// Maison repond apres le lancement mais avant 100 s (changement groupe) : le demon reste.
    @Test func maisonRepondueParUnChangementNeFermePas() async throws {
        let b = BancDemon()
        _ = await b.abonner()
        await b.horloge.avancer(.seconds(30))
        b.maison.noms = BancDemon.noms()
        b.maison.changer()
        await b.horloge.avancer(.seconds(200))
        #expect(b.sorties.isEmpty)
    }

    /// Un releve en erreur ne compte pas comme une reponse de Maison.
    @Test func releveEnErreurNeComptePasCommeReponse() async throws {
        let b = BancDemon(noms: NomsMaison(date: .now, statut: .erreur, message: "Maison indisponible"))
        _ = await b.abonner()
        await b.horloge.avancer(.seconds(100))
        #expect(b.sorties == [Self.raisonMaisonMuette])
    }

    /// Autorisation en attente (invite a l'ecran) ou refusee : le demon ne se ferme pas pour cette raison.
    @Test(arguments: [EtatPasseur.Acces.attente, .refuse])
    func accesNonAccordeNeFermePas(acces: EtatPasseur.Acces) async throws {
        let b = BancDemon()
        b.maison.acces = acces
        _ = await b.abonner()
        await b.horloge.avancer(.seconds(100))
        #expect(b.sorties.isEmpty)
    }

    /// Un releve ponctuel qui attend Maison recoit le releve en erreur, puis le demon part quand l'envoi est fini.
    @Test func maisonMuetteServitLePonctuelPuisFerme() async throws {
        let b = BancDemon()
        _ = await b.abonner()
        await b.demon.recevoir(url: BancDemon.url(.releve, port: 50_123))
        await b.horloge.avancer(.seconds(100))
        let p = try #require(b.ponctuels.first)
        #expect(p.cible.port == 50_123)
        let n = try NomsMaison.lire(p.json)
        #expect(n.statut == .erreur && n.message == "Maison n'a pas répondu")
        #expect(b.ponctuels.count == 1)
        #expect(b.sorties.isEmpty, "pas avant la fin de l'envoi")
        b.finirPonctuels()
        #expect(b.sorties == [Self.raisonMaisonMuette])
    }
}
