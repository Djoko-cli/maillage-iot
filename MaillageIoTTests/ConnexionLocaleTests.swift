import Foundation
import Network
import Synchronization
import Testing

/// Ecoute de test sur 127.0.0.1 : accepte et garde toutes les connexions.
final class EcouteTest: Sendable {
    let ecouteur: NWListener
    private let connexions = Mutex<[NWConnection]>([])

    init() throws {
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        ecouteur = try NWListener(using: p)
        ecouteur.newConnectionHandler = { [weak self] c in
            self?.connexions.withLock { $0.append(c) }
            c.start(queue: .global())
        }
        ecouteur.start(queue: .global())
    }

    deinit {
        ecouteur.cancel()
        connexions.withLock { $0.forEach { $0.cancel() } }
    }

    /// Le port, une fois l'ecoute prete (0 avant).
    var port: UInt16? { ecouteur.port.map(\.rawValue).flatMap { $0 == 0 ? nil : $0 } }
}

@Suite("Connexion locale des faux clients", .timeLimit(.minutes(1)))
struct ConnexionLocaleTests {
    /// Le couple d'adresses deja pris (le journal du 01/11 : `connectx failed [48: Address already in use]`) se distingue
    /// d'une connexion refusee.
    @Test func issueDesEtats() {
        #expect(ConnexionLocale.issue(.ready) == .prete)
        #expect(ConnexionLocale.issue(.waiting(.posix(.EADDRINUSE))) == .adresseOccupee)
        #expect(ConnexionLocale.issue(.failed(.posix(.EADDRINUSE))) == .adresseOccupee)
        #expect(ConnexionLocale.issue(.waiting(.posix(.ECONNREFUSED))) == .echec)
        #expect(ConnexionLocale.issue(.failed(.posix(.ECONNRESET))) == .echec)
        #expect(ConnexionLocale.issue(.cancelled) == .echec)
        #expect(ConnexionLocale.issue(.preparing) == nil)
    }

    /// Un essai qui tombe sur un couple d'adresses deja pris laisse place a une nouvelle connexion, au lieu d'attendre sans fin.
    @Test func adresseOccupeeRetentee() async throws {
        let e = try EcouteTest()
        #expect(await attendreQue { e.port != nil })
        let port = try #require(e.port)
        let essais = Mutex(0)
        let c = await ConnexionLocale.ouvrir(port: port) { c, delai in
            let n = essais.withLock { n in
                defer { n += 1 }
                return n
            }
            return n == 0 ? .adresseOccupee : await ConnexionLocale.essayer(c, delai: delai)
        }
        defer { c?.cancel() }
        #expect(c != nil)
        #expect(essais.withLock { $0 } == 2)
    }

    /// Un couple toujours pris : nil apres le dernier essai, jamais d'attente sans fin.
    @Test func essaisBornes() async {
        let essais = Mutex(0)
        let c = await ConnexionLocale.ouvrir(port: 9, essais: 3) { _, _ in
            essais.withLock { $0 += 1 }
            return .adresseOccupee
        }
        #expect(c == nil)
        #expect(essais.withLock { $0 } == 3)
    }

    /// Personne n'ecoute : nil, sans nouvel essai.
    @Test func refusee() async throws {
        let e = try EcouteTest()
        #expect(await attendreQue { e.port != nil })
        let port = try #require(e.port)
        e.ecouteur.cancel()
        try await Task.sleep(for: .milliseconds(50))
        let essais = Mutex(0)
        let c = await ConnexionLocale.ouvrir(port: port) { c, delai in
            essais.withLock { $0 += 1 }
            return await ConnexionLocale.essayer(c, delai: delai)
        }
        #expect(c == nil)
        #expect(essais.withLock { $0 } == 1)
    }
}
