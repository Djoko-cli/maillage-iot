import Foundation
import Network
import Testing

/// Attend qu'une condition soit vraie, au plus `delai` ; rend la condition.
@MainActor
func attendreQue(_ delai: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while !condition(), ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
    return condition()
}

/// Une valeur que modifient les fermetures des tests (`surMessage`, `surFin`, `fini`) : une fermeture isolee a
/// l'acteur principal ne peut pas modifier une variable locale capturee.
@MainActor
final class Boite<Valeur> {
    var valeur: Valeur

    init(_ valeur: Valeur) {
        self.valeur = valeur
    }
}

/// Fausse app : ecoute sur 127.0.0.1, accepte une connexion, lit le jeton puis les trames (`LectureFlux`), et garde
/// tous les octets recus (releve ponctuel).
@MainActor
final class FausseApp {
    let jeton = String(repeating: "c3", count: 32)
    private let ecouteur: NWListener
    private var connexion: NWConnection?
    private var lecture: EnvoiPasseur.LectureFlux
    private(set) var recus: [MessagePasseur] = []
    private(set) var octets = Data()
    private(set) var fermee = false

    init() throws {
        lecture = EnvoiPasseur.LectureFlux(jeton: jeton)
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        ecouteur = try NWListener(using: p)
        ecouteur.newConnectionHandler = { [weak self] c in MainActor.assumeIsolated { self?.accepter(c) } }
        ecouteur.start(queue: .main)
    }

    /// Le port, une fois l'ecoute prete.
    func port() async -> UInt16? {
        // `port` vaut d'abord 0 (port `.any`) : on attend le vrai port, pas seulement une valeur.
        _ = await attendreQue { (ecouteur.port?.rawValue ?? 0) != 0 }
        return ecouteur.port?.rawValue
    }

    var jetonAccepte: Bool { lecture.jetonAccepte }

    private func accepter(_ c: NWConnection) {
        connexion = c
        c.start(queue: .main)
        lire(c)
    }

    private func lire(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] d, _, finie, e in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let d, !d.isEmpty {
                    self.octets.append(d)
                    for j in self.lecture.ajouter(d).trames {
                        if case .message(let m) = MessagePasseur.lire(j) { self.recus.append(m) }
                    }
                }
                if finie || e != nil {
                    self.fermee = true
                    return
                }
                self.lire(c)
            }
        }
    }

    func envoyer(_ o: Data) {
        connexion?.send(content: o, completion: .idempotent)
    }

    func fermer() {
        connexion?.cancel()
        ecouteur.cancel()
    }
}

@MainActor
@Suite("Connexions du demon sur la boucle locale", .timeLimit(.minutes(1)))
struct ConnexionAppTests {
    static func cible(_ app: FausseApp, _ d: EnvoiPasseur.Demande = .abonner) async throws -> EnvoiPasseur.Cible {
        EnvoiPasseur.Cible(port: try #require(await app.port()), jeton: app.jeton, demande: d)
    }

    /// Le jeton, puis les messages ; les messages de l'app arrivent par `surMessage`.
    @Test func echange() async throws {
        let app = try FausseApp()
        let lien = ConnexionApp(cible: try await Self.cible(app))
        let recus = Boite<[MessagePasseur]>([])
        lien.surMessage = { recus.valeur.append($0) }
        lien.envoyer(.etat(EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)))
        lien.envoyer(.releve(Data(#"{"version":2}"#.utf8)))
        #expect(await attendreQue { app.recus.count == 2 })
        #expect(app.jetonAccepte)
        app.envoyer(EnvoiPasseur.trame(.relire) + EnvoiPasseur.trame(.ouvertureSession(actif: true)))
        #expect(await attendreQue { recus.valeur.count == 2 })
        #expect(recus.valeur == [.relire, .ouvertureSession(actif: true)])
        lien.fermer()
        app.fermer()
    }

    /// L'app ferme : `surFin`, une seule fois.
    @Test func finQuandLAppFerme() async throws {
        let app = try FausseApp()
        let lien = ConnexionApp(cible: try await Self.cible(app))
        let fins = Boite(0)
        lien.surFin = { fins.valeur += 1 }
        lien.envoyer(.relire)
        #expect(await attendreQue { app.jetonAccepte })
        app.fermer()
        #expect(await attendreQue { fins.valeur == 1 })
        lien.fermer()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fins.valeur == 1)
    }

    /// Trame mal formee de l'app : la connexion se ferme.
    @Test func trameFausse() async throws {
        let app = try FausseApp()
        let lien = ConnexionApp(cible: try await Self.cible(app))
        let fini = Boite(false)
        lien.surFin = { fini.valeur = true }
        lien.envoyer(.relire)
        #expect(await attendreQue { app.jetonAccepte })
        app.envoyer(Data("x\n".utf8))
        #expect(await attendreQue { fini.valeur })
        #expect(await attendreQue { app.fermee })
        app.fermer()
    }

    /// Personne n'ecoute : `surFin`.
    @Test func personneNEcoute() async throws {
        let app = try FausseApp()
        let cible = try await Self.cible(app)
        app.fermer()
        try? await Task.sleep(for: .milliseconds(50))
        let lien = ConnexionApp(cible: cible)
        let fini = Boite(false)
        lien.surFin = { fini.valeur = true }
        #expect(await attendreQue { fini.valeur })
    }

    /// Releve ponctuel : la trame de l'ancien passeur, lue par `Lecture` ; `fini` apres la fermeture par l'app.
    @Test func livraisonPonctuelle() async throws {
        let app = try FausseApp()
        let cible = try await Self.cible(app, .releve)
        let json = Data(#"{"accessoires":[],"date":"2026-10-12T12:00:00.000Z","statut":"ok","version":1}"#.utf8)
        let fini = Boite(false)
        LivraisonPonctuelle.livrer(cible, json: json) { fini.valeur = true }
        /// Une lecture neuve de tout ce qui est arrive : la trame est-elle complete ?
        func complete() -> Bool {
            var l = EnvoiPasseur.Lecture(jeton: app.jeton)
            return l.ajouter(app.octets) == .json(json)
        }
        #expect(await attendreQue { complete() })
        #expect(!fini.valeur, "attend que l'app ferme")
        app.fermer()
        #expect(await attendreQue { fini.valeur })
    }

    /// `fait` sert a ne pas journaliser comme erreur le `.waiting` qui suit l'annulation d'une livraison reussie.
    @Test func uneFoisFait() async {
        let appels = Boite(0)
        let fin = UneFois { appels.valeur += 1 }
        #expect(!fin.fait)
        fin.appeler()
        #expect(fin.fait)
        fin.appeler()
        #expect(appels.valeur == 1)
    }
}
