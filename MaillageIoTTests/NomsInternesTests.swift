import Foundation
import MaillageCoeur
import Network
import Synchronization
import Testing
@testable import MaillageIoT

/// Faux passeur des tests : un client TCP sur 127.0.0.1. Il envoie des octets et ferme son
/// cote, puis attend que l'app ferme la connexion, comme le vrai passeur ; vrai si elle l'a
/// fermee, faux si la connexion a echoue (rien n'ecoute sur ce port).
enum FauxPasseur {
    static func envoyer(_ octets: Data, port: UInt16) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: port) else { return false }
        let c = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
        let fermee = await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
            let reprise = Reprise(suite)
            c.stateUpdateHandler = { etat in
                switch etat {
                case .ready:
                    c.send(content: octets, contentContext: .finalMessage, isComplete: true,
                           completion: .contentProcessed { erreur in
                        guard erreur == nil else { return reprise.reprendre(false) }
                        c.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, fin, e in
                            reprise.reprendre(fin || e != nil)
                        }
                    })
                case .waiting, .failed: reprise.reprendre(false)
                default: break
                }
            }
            c.start(queue: .global())
        }
        c.cancel()
        return fermee
    }

    /// Reprend la continuation une seule fois, depuis n'importe quel fil.
    final class Reprise: Sendable {
        private let suite: Mutex<CheckedContinuation<Bool, Never>?>

        init(_ suite: CheckedContinuation<Bool, Never>) {
            self.suite = Mutex(suite)
        }

        func reprendre(_ fermee: Bool) {
            suite.withLock { $0.take() }?.resume(returning: fermee)
        }
    }

    /// Client de la boucle locale qui reste connecte : il envoie les octets qu'on lui donne sans
    /// fermer son cote, puis se ferme proprement (`terminer`, comme le passeur) ou est coupe net
    /// (`couper`, la connexion est reinitialisee). Il se connecte des sa creation, sans attendre.
    final class Client: Sendable {
        private let connexion: NWConnection
        private let etat = Mutex<NWConnection.State>(.setup)

        init?(port: UInt16) {
            guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
            connexion = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
            connexion.stateUpdateHandler = { [weak self] nouvel in self?.etat.withLock { $0 = nouvel } }
            connexion.start(queue: .global())
        }

        deinit {
            connexion.cancel()
        }

        /// La connexion est etablie.
        var pret: Bool { etat.withLock { $0 == .ready } }

        /// Attend que la connexion soit etablie, au plus `delai` ; faux si elle echoue (rien
        /// n'ecoute sur ce port).
        func attendre(delai: Duration = .seconds(5)) async -> Bool {
            let fin = ContinuousClock.now + delai
            while ContinuousClock.now < fin {
                switch etat.withLock({ $0 }) {
                case .ready: return true
                case .waiting, .failed, .cancelled: return false
                default: try? await Task.sleep(for: .milliseconds(2))
                }
            }
            return false
        }

        /// Envoie ces octets sans fermer son cote ; vrai s'ils sont partis.
        func envoyer(_ octets: Data) async -> Bool {
            await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
                connexion.send(content: octets, completion: .contentProcessed { erreur in
                    suite.resume(returning: erreur == nil)
                })
            }
        }

        /// Envoie ces octets (s'il y en a) et ferme son cote, puis attend que l'app ferme la
        /// connexion, au plus 5 s ; vrai si elle l'a fermee.
        func terminer(_ octets: Data = Data()) async -> Bool {
            await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
                let reprise = Reprise(suite)
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { reprise.reprendre(false) }
                connexion.send(content: octets.isEmpty ? nil : octets, contentContext: .finalMessage,
                               isComplete: true, completion: .contentProcessed { [connexion] erreur in
                    guard erreur == nil else { return reprise.reprendre(false) }
                    connexion.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, fin, e in
                        reprise.reprendre(fin || e != nil)
                    }
                })
            }
        }

        /// Coupe net, sans fermeture propre : l'app recoit une erreur de connexion.
        func couper() {
            connexion.forceCancel()
        }
    }
}

/// Lancements du passeur demandes par l'app, dans l'ordre (leurs cibles : port et jeton).
final class LancementsPasseur: Sendable {
    private let liste = Mutex<[EnvoiPasseur.Cible]>([])

    func noter(_ cible: EnvoiPasseur.Cible) {
        liste.withLock { $0.append(cible) }
    }

    var tous: [EnvoiPasseur.Cible] { liste.withLock { $0 } }
    /// Port et jeton du dernier lancement.
    var cible: EnvoiPasseur.Cible? { tous.last }
}

extension NomsInternes {
    /// Lanceur des tests qui ne doivent jamais lancer le passeur : s'il est appele, le test echoue.
    /// `NomsInternes` n'a pas de lanceur par defaut (l'oublier lancerait le vrai passeur) : tout test
    /// qui ne prevoit pas de lancement donne celui-ci.
    static let lanceurInterdit: Lanceur = { _ in
        Issue.record("le passeur ne doit pas etre lance par ce test")
        return "lanceur interdit"
    }
}

@MainActor
@Suite("Noms de Maison : client du demon Passeur Noms", .timeLimit(.minutes(1)))
struct NomsInternesTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static func noms(_ statut: StatutPasseur = .ok, nom: String = "Halo", message: String? = nil) -> NomsMaison {
        NomsMaison(date: date, statut: statut, message: message,
                   accessoires: statut == .ok ? [AccessoireMaison(nom: nom, noeudMatter: "00000000000002E9")] : [],
                   zones: statut == .ok ? [ZoneMaison(nom: "Étage", pieces: ["Bureau"])] : nil)
    }

    /// `noms.json` dans un dossier temporaire unique, a effacer apres le test.
    static func cache() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("noms-\(UUID().uuidString)")
            .appendingPathComponent(NomsInternes.fichier)
    }

    /// Faux lanceur : note chaque lancement ; `probleme` : le lancement echoue.
    static func lanceur(_ lancements: LancementsPasseur, probleme: String? = nil) -> NomsInternes.Lanceur {
        { cible in
            lancements.noter(cible)
            return probleme
        }
    }

    static func json(_ n: NomsMaison) throws -> Data { try n.donnees() }

    /// Attend que le faux lanceur ait ete appele `fois` fois, au plus 10 s ; rend la cible du
    /// dernier lancement.
    static func cible(_ lancements: LancementsPasseur, fois: Int = 1) async -> EnvoiPasseur.Cible? {
        let fin = ContinuousClock.now + .seconds(10)
        while lancements.tous.count < fois, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        return lancements.cible
    }

    /// Textes de l'app, dans la langue de l'hote des tests.
    static let refus = String(localized: "Accès à Maison refusé au passeur : Réglages Système › Confidentialité et sécurité › Maison.")

    /// Un client abonne a un faux demon connecte : le client, le demon et le fichier des noms.
    static func connecte(attentes: [Duration] = [.milliseconds(20)])
        async throws -> (NomsInternes, FauxDemon, LancementsPasseur, URL) {
        let cache = Self.cache()
        let lancements = LancementsPasseur()
        let n = NomsInternes(cache: cache, attentes: attentes, lanceur: Self.lanceur(lancements))
        n.demarrer()
        let cible = try #require(await Self.cible(lancements))
        let d = try #require(FauxDemon(port: cible.port))
        #expect(await d.jeton(cible.jeton))
        #expect(await attendreQue { n.connecte })
        return (n, d, lancements, cache)
    }

    /// Un releve reussi remplace les noms ; un echec du passeur les garde et dit
    /// pourquoi, avec les textes de l'app : le message du passeur (en francais
    /// seulement) n'est que le detail d'une erreur.
    @Test func echecGardeLesNoms() {
        let ancien = Self.noms(nom: "Halo")
        let (garde, probleme) = NomsInternes.retenir(Self.noms(.refuse, message: "Accès refusé"), ancien: ancien)
        #expect(garde == ancien)
        #expect(probleme == Self.refus)
        let (_, indisponible) = NomsInternes.retenir(Self.noms(.indisponible, message: "Capacité absente"), ancien: ancien)
        #expect(indisponible == String(localized: "HomeKit indisponible pour le passeur."))
        let (gardeAussi, erreur) = NomsInternes.retenir(Self.noms(.erreur, message: "Aucun domicile dans Maison"), ancien: ancien)
        #expect(gardeAussi == ancien)
        #expect(erreur == String(localized: "Le passeur a échoué : \("Aucun domicile dans Maison")"))
        let (_, sansDetail) = NomsInternes.retenir(Self.noms(.erreur), ancien: nil)
        #expect(sansDetail == String(localized: "Le passeur a échoué."))
        let (neuf, rien) = NomsInternes.retenir(Self.noms(nom: "Pont"), ancien: ancien)
        #expect(neuf?.accessoires.first?.nom == "Pont")
        #expect(rien == nil)
    }

    /// Les noms retenus sont ecrits dans le conteneur et relus au lancement ; un echec ne les
    /// efface pas.
    @Test func memoireDesNoms() throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let n = NomsInternes(cache: cache, lanceur: NomsInternes.lanceurInterdit)
        #expect(n.noms == nil)
        var recus: [NomsMaison?] = []
        n.surNoms = { recus.append($0) }
        n.integrer(Self.noms())
        n.integrer(Self.noms(.refuse, message: "Accès refusé"))
        #expect(n.noms == Self.noms(), "l'echec n'efface pas les noms")
        #expect(n.probleme == Self.refus)
        #expect(recus == [Self.noms()], "un seul changement")
        #expect(NomsInternes(cache: cache, lanceur: NomsInternes.lanceurInterdit).noms == Self.noms(), "relus au lancement")
    }

    /// Au demarrage : l'URL `abonner` ; puis `etat` et les releves successifs, gardes dans `noms.json`.
    @Test func abonnementEtReleves() async throws {
        let (n, d, lancements, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(lancements.cible?.demande == .abonner)
        #expect(lancements.cible?.jeton.count == 64)
        let e = EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)
        #expect(await d.message(.etat(e)))
        #expect(await attendreQue { n.etat == e })
        #expect(await d.message(.releve(try Self.json(Self.noms()))))
        #expect(await attendreQue { n.noms == Self.noms() })
        #expect(await d.message(.releve(try Self.json(Self.noms(nom: "Pont")))))
        #expect(await attendreQue { n.noms == Self.noms(nom: "Pont") })
        #expect(NomsInternes(cache: cache, lanceur: NomsInternes.lanceurInterdit).noms == Self.noms(nom: "Pont"))
        #expect(n.tentative == 0)
    }

    /// `relire`, `identifier` et `ouvertureSession` partent vers le demon ; la reponse a « Identifier » s'affiche pour
    /// son accessoire.
    @Test func commandesEnvoyees() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        n.relire()
        #expect(n.releveEnCours)
        n.identifier(accessoire: "A")
        n.reglerOuvertureSession(true)
        #expect(await attendreQue { d.messages.count == 3 })
        #expect(d.messages == [.relire, .identifier(demande: 1, accessoire: "A"), .ouvertureSession(actif: true)])
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 1, ok: true))))
        #expect(await attendreQue { n.identification != nil })
        #expect(n.identification == NomsInternes.Identification(accessoire: "A",
                                                                texte: String(localized: "Identification demandée")))
        #expect(await d.message(.releve(try Self.json(Self.noms()))))
        #expect(await attendreQue { !n.releveEnCours })
    }

    /// Une reponse a une demande plus ancienne que la derniere est ignoree.
    @Test func reponseIdentifierEnRetard() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        n.identifier(accessoire: "A")
        n.identifier(accessoire: "B")
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 1, ok: true))))
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 2, ok: false, erreur: ReponseIdentifier.nonIdentifiable))))
        #expect(await attendreQue { n.identification != nil })
        #expect(n.identification?.accessoire == "B")
        #expect(n.identification?.texte == String(localized: "Cet accessoire ne sait pas s'identifier"))
    }

    /// Le demon ferme : deconnecte, le probleme dit, et un nouvel abonnement (nouveau jeton) apres l'attente.
    @Test func reabonnementApresFermeture() async throws {
        let (n, d, lancements, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let premier = try #require(lancements.cible)
        d.fermer()
        #expect(await attendreQue { !n.connecte })
        #expect(n.probleme == String(localized: "Passeur Noms s'est déconnecté."))
        let second = try #require(await Self.cible(lancements, fois: 2))
        #expect(second.jeton != premier.jeton)
        #expect(second.demande == .abonner)
    }

    /// Lancement refuse : le probleme, puis d'autres essais ; un demon connecte remet le compte a zero.
    @Test func essaisApresUnEchec() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let introuvable = "Passeur Noms introuvable"
        let n = NomsInternes(cache: cache, attentes: [.milliseconds(10)], lanceur: Self.lanceur(lancements, probleme: introuvable))
        n.demarrer()
        _ = await Self.cible(lancements, fois: 3)
        #expect(lancements.tous.count >= 3)
        #expect(n.probleme == introuvable)
        #expect(n.tentative >= 2)
    }

    /// Les attentes avant de se reabonner : 5 s, 10 s, 30 s, puis toutes les minutes.
    @Test func attentesCroissantes() {
        let a = NomsInternes.reabonnements
        #expect(a == [.seconds(5), .seconds(10), .seconds(30), .seconds(60)])
        #expect(NomsInternes.attente(apres: 0, dans: a) == .seconds(5))
        #expect(NomsInternes.attente(apres: 1, dans: a) == .seconds(10))
        #expect(NomsInternes.attente(apres: 2, dans: a) == .seconds(30))
        #expect(NomsInternes.attente(apres: 3, dans: a) == .seconds(60))
        #expect(NomsInternes.attente(apres: 40, dans: a) == .seconds(60))
    }

    /// Aucun demon dans le delai : le probleme, puis un nouvel essai.
    @Test func delaiSansDemon() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsInternes(cache: cache, delai: .milliseconds(100), attentes: [.milliseconds(10)],
                             lanceur: Self.lanceur(lancements))
        n.demarrer()
        _ = await Self.cible(lancements, fois: 2)
        #expect(n.probleme == String(localized: "Passeur Noms ne s'est pas connecté en 2 minutes."))
    }

    /// Un releve illisible garde les noms et le dit.
    @Test func releveIllisible() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(await d.message(.releve(try Self.json(Self.noms()))))
        #expect(await attendreQue { n.noms != nil })
        #expect(await d.message(.releve(Data(#"{"x":1}"#.utf8))))
        #expect(await attendreQue { n.probleme != nil })
        #expect(n.noms == Self.noms())
    }

    /// Un demon connecte qui ne repond pas a `relire` : apres le delai, le bouton est libere, le probleme dit, et la
    /// connexion reste ouverte.
    @Test func releveSansReponse() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        // Le delai sert aussi de minuterie de connexion : 1 s laisse la connexion s'etablir sur une machine chargee.
        let n = NomsInternes(cache: cache, delai: .seconds(1), attentes: [.milliseconds(20)],
                             lanceur: Self.lanceur(lancements))
        n.demarrer()
        let cible = try #require(await Self.cible(lancements))
        let d = try #require(FauxDemon(port: cible.port))
        #expect(await d.jeton(cible.jeton))
        #expect(await attendreQue { n.connecte })
        n.relire()
        #expect(n.releveEnCours)
        #expect(await attendreQue { !n.releveEnCours })
        #expect(n.probleme == String(localized: "Passeur Noms n'a pas répondu à la demande de relevé."))
        #expect(n.connecte)
        #expect(d.messages == [.relire])
    }

    /// Sans memoire (demo, tests) : rien ne se lance, ni au demarrage ni sur demande.
    @Test func sansMemoire() {
        let n = NomsInternes(cache: nil, lanceur: NomsInternes.lanceurInterdit)
        n.demarrer()
        n.relire()
        n.identifier(accessoire: "A")
        #expect(!n.connecte && !n.releveEnCours)
    }

    /// Sans demon connecte, « Rafraichir depuis Maison » relance l'abonnement tout de suite, sans attendre.
    @Test func relireSansDemon() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsInternes(cache: cache, attentes: [.seconds(60)], lanceur: Self.lanceur(lancements, probleme: "absent"))
        n.demarrer()
        _ = await Self.cible(lancements)
        #expect(await attendreQue { n.probleme == "absent" })
        n.relire()
        #expect(await Self.cible(lancements, fois: 2) != nil)
        #expect(lancements.tous.count == 2)
    }

    /// L'ancien passeur (app iOS, sans le schema du protocole) n'est pas lance : il ne connait pas `abonner`.
    @Test func problemeInstallation() {
        let ancienne = String(localized: "Passeur Noms est l'ancienne version : relance outils/passeur.sh.")
        let introuvable = String(localized: "Passeur Noms introuvable : lance outils/passeur.sh.")
        #expect(NomsInternes.problemeInstallation(ancien: true) == ancienne)
        #expect(NomsInternes.problemeInstallation(ancien: false) == introuvable)
    }

    /// Les textes des fins d'abonnement.
    @Test func textesDesFins() {
        #expect(NomsInternes.texte(AbonnementPasseur.Fin.jetonFaux) == String(localized: "Connexion de Passeur Noms refusée : jeton faux."))
        #expect(NomsInternes.texte(AbonnementPasseur.Fin.trameFausse) == String(localized: "Message illisible de Passeur Noms : connexion fermée."))
        #expect(NomsInternes.texte(AbonnementPasseur.Fin.interrompue) == String(localized: "Connexion avec Passeur Noms coupée."))
        #expect(NomsInternes.texte(AbonnementPasseur.Fin.ecoute("occupé"))
                == String(localized: "Écoute de Passeur Noms impossible : \("occupé")"))
    }

    /// Reglages › Noms de Maison : les zones lues, dans l'ordre de Maison.
    @Test func zonesDansLesReglages() {
        #expect(FenetreReglages.texteZones([ZoneMaison(nom: "Rez-de-chaussée"), ZoneMaison(nom: "Étage")])
                == "Rez-de-chaussée, Étage")
        #expect(FenetreReglages.texteZones([]) == String(localized: "aucune zone dans Maison"))
    }
}
