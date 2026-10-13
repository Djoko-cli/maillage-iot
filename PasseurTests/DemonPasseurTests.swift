import Foundation
import Testing

@MainActor
@Suite("Demon Passeur Noms : abonnement et releves")
struct DemonPasseurTests {
    static let etatDeBase = EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)

    /// A la connexion : `etat`, puis le releve (batteries lues, premier releve du demon).
    @Test func abonnementEnvoieEtatPuisReleve() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        #expect(l.etats == [Self.etatDeBase])
        #expect(l.releves == [BancDemon.noms()])
        #expect(l.envoyes.first == .etat(Self.etatDeBase), "etat d'abord")
        #expect(b.maison.lectures == [true])
        #expect(b.demon.abonnes.count == 1)
    }

    /// L'expiration du profil voyage dans `etat`.
    @Test func profilDansLEtat() async throws {
        let fin = Date(timeIntervalSince1970: 1_823_000_000)
        let b = BancDemon(noms: BancDemon.noms(), profilExpire: fin)
        let l = try #require(await b.abonner())
        #expect(l.etats.first?.profilExpire == fin)
    }

    /// Un abonne arrive apres un releve : il recoit le dernier, sans nouvelle lecture.
    @Test func secondAbonneRecoitLeDernier() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        _ = await b.abonner(port: 50_000)
        let second = try #require(await b.abonner(port: 50_001))
        #expect(second.releves == [BancDemon.noms()])
        #expect(b.maison.lectures == [true])
    }

    /// Maison pas encore prete : `etat` seulement ; le releve part 2 s apres le changement qui l'annonce.
    @Test func releveAuChangement() async throws {
        let b = BancDemon()
        let l = try #require(await b.abonner())
        #expect(l.releves.isEmpty)
        b.maison.noms = BancDemon.noms()
        b.maison.changer()
        await b.horloge.avancer(.milliseconds(1999))
        #expect(l.releves.isEmpty, "pas avant 2 s")
        await b.horloge.avancer(.milliseconds(1))
        #expect(l.releves == [BancDemon.noms()])
    }

    /// Tant qu'aucun releve ok n'a ete lu (releve en erreur), les batteries sont relues au releve suivant.
    @Test func batteriesReluesApresUnReleveEnErreur() async throws {
        let b = BancDemon(noms: NomsMaison(date: .now, statut: .erreur, message: "Aucun domicile dans Maison"))
        _ = try #require(await b.abonner())
        b.maison.noms = BancDemon.noms()
        b.maison.changer()
        await b.horloge.avancer(.seconds(2))
        #expect(b.maison.lectures == [true, true])
        b.maison.noms = BancDemon.noms("Halo 2")
        b.maison.changer()
        await b.horloge.avancer(.seconds(2))
        #expect(b.maison.lectures == [true, true, false], "releve ok lu : les batteries gardent leurs valeurs")
    }

    /// Des changements groupes : un seul releve, 2 s apres le dernier.
    @Test func regroupement() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        b.maison.noms = BancDemon.noms("Halo 2")
        b.maison.changer()
        await b.horloge.avancer(.seconds(1))
        b.maison.changer()
        await b.horloge.avancer(.milliseconds(1500))
        b.maison.changer()
        await b.horloge.avancer(.milliseconds(1999))
        #expect(l.releves.count == 1, "toujours le seul releve de la connexion")
        await b.horloge.avancer(.milliseconds(1))
        #expect(l.releves.map { $0.accessoires.first?.nom } == ["Halo", "Halo 2"])
    }

    /// Releve identique au dernier envoye, date mise a part : rien ne part.
    @Test func identiqueNonRenvoye() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        b.maison.noms = BancDemon.noms(date: Date(timeIntervalSince1970: 1_790_003_600))
        b.maison.changer()
        await b.horloge.avancer(.seconds(2))
        #expect(l.releves.count == 1)
        #expect(b.maison.lectures == [true, false], "changement : batteries pas relues")
    }

    /// Deux accessoires de meme nom, dans un ordre ou l'autre : le meme releve, rien ne part.
    @Test func ordreStableDesHomonymes() async throws {
        let a = AccessoireMaison(nom: "Capteur", id: "8D3C2A10-0000-4000-8000-00000000000A")
        let z = AccessoireMaison(nom: "Capteur", id: "8D3C2A10-0000-4000-8000-00000000000B")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let b = BancDemon(noms: NomsMaison(date: date, accessoires: [a, z]))
        let l = try #require(await b.abonner())
        b.maison.noms = NomsMaison(date: date, accessoires: [z, a])
        b.maison.changer()
        await b.horloge.avancer(.seconds(2))
        #expect(l.releves.count == 1)
        #expect(DemonPasseur.ordonner([z, a]) == [a, z])
    }

    /// `relire` : releve immediat, batteries relues ; envoye au demandeur meme identique, aux autres seulement s'il a
    /// change.
    @Test func relire() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let demandeur = try #require(await b.abonner(port: 50_000))
        let autre = try #require(await b.abonner(port: 50_001))
        await b.demon.recevoir(.relire, de: demandeur)
        #expect(demandeur.releves.count == 2)
        #expect(autre.releves.count == 1)
        #expect(b.maison.lectures.last == true)
        b.maison.noms = BancDemon.noms("Halo 2")
        await b.demon.recevoir(.relire, de: demandeur)
        #expect(demandeur.releves.count == 3)
        #expect(autre.releves.count == 2)
    }

    /// Un message de l'app passe par `surMessage` du lien.
    @Test func messageParLeLien() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        l.surMessage?(.relire)
        let fin = ContinuousClock.now + .seconds(5)
        while l.releves.count < 2, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(l.releves.count == 2)
    }

    /// Toutes les heures : batteries relues, releve envoye s'il a change.
    @Test func batteriesToutesLesHeures() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        var n = BancDemon.noms()
        n.accessoires[0].batterie = BatterieMaison(niveau: 40)
        b.maison.noms = n
        await b.horloge.avancer(.seconds(3600))
        #expect(b.maison.lectures == [true, true])
        #expect(l.releves.last?.accessoires.first?.batterie?.niveau == 40)
        await b.horloge.avancer(.seconds(3600))
        #expect(b.maison.lectures == [true, true, true])
    }

    /// L'acces change : `etat` part tout de suite, sans attendre le regroupement.
    @Test func accesChangeEtat() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        let l = try #require(await b.abonner())
        b.maison.acces = .refuse
        b.maison.changer()
        #expect(l.etats.last?.acces == .refuse)
        #expect(l.etats.count == 2)
    }

    /// Une URL qui n'est pas celle du passeur : rien.
    @Test func urlIllisible() async throws {
        let b = BancDemon(noms: BancDemon.noms())
        await b.demon.recevoir(url: try #require(URL(string: "maillage-passeur://autre?port=1&jeton=\(BancDemon.jeton)")))
        #expect(b.liens.isEmpty && b.ponctuels.isEmpty)
    }
}
