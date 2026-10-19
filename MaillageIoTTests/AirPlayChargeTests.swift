import Foundation
import Synchronization
import Testing
@testable import MaillageIoT

/// La charge de l'ecoute AirPlay : une instance est resolue une fois (avec un plafond de tentatives si elle ne repond pas), et
/// un changement du seul TXT AirPlay n'arme aucun releve. Noms inventes ; aucun reseau (ecoutes et resolveur factices).
@MainActor
@Suite("AirPlay : charge du recenseur", .timeLimit(.minutes(1)))
struct AirPlayChargeTests {
    static let airplay = Recenseur.typeAirPlay

    /// Resolutions demandees, par "type|instance".
    final class Compte: Sendable {
        private let n = Mutex<[String: Int]>([:])
        func noter(_ type: String, _ instance: String) {
            n.withLock { $0[Recenseur.cle(type, instance), default: 0] += 1 }
        }
        func de(_ instance: String, type: String = Recenseur.typeAirPlay) -> Int {
            n.withLock { $0[Recenseur.cle(type, instance)] ?? 0 }
        }
    }

    /// Releves rapportes par un recenseur.
    @MainActor final class Releves {
        var n = 0
    }

    /// Un recenseur dont le resolveur repond pour "Repond" seulement ; calme de 20 ms ; ses releves comptes.
    static func recenseur(_ fab: FabriqueBonjour, _ compte: Compte) -> (Recenseur, Releves) {
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100), delaiCalme: .milliseconds(20),
                          resolveur: { type, instance in
                              compte.noter(type, instance)
                              return instance == "Repond" ? ResolveurDNSSD.Cible(hote: "h1.local", port: 7000, txt: Data()) : nil
                          })
        let releves = Releves()
        r.surReleve = { _ in releves.n += 1 }
        return (r, releves)
    }

    /// Attend `n` releves de plus que `releves.n`.
    static func attendre(_ n: Int, _ releves: Releves) async -> Bool {
        let attendu = releves.n + n
        return await attendreActivation { releves.n >= attendu }
    }

    /// `n` releves de plus, chacun arme par un changement d'un navigateur (un service Matter de plus).
    static func armer(_ n: Int, fab: FabriqueBonjour, _ releves: Releves) async -> Bool {
        let matter = fab.crees.first { $0.type == "_matter._tcp" }
        for _ in 0..<n {
            matter?.voir("Matter \(matter?.instances.count ?? 0)")
            guard await attendre(1, releves) else { return false }
        }
        return true
    }

    @Test func uneResolutionParInstance() async throws {
        let fab = FabriqueBonjour()
        let compte = Compte()
        let (r, releves) = Self.recenseur(fab, compte)
        r.demarrer()
        let airplay = try #require(fab.crees.first { $0.type == Self.airplay })
        airplay.voir("Repond")
        airplay.voir("Muet")
        #expect(await attendreActivation { releves.n >= 1 }, "le premier releve")
        #expect(await Self.armer(6, fab: fab, releves))
        #expect(compte.de("Repond") == 1, "une instance resolue ne l'est plus aux releves suivants")
        #expect(compte.de("Muet") >= 1)
        #expect(compte.de("Muet") <= Recenseur.plafondTentativesAirPlay,
                "une instance AirPlay muette n'est pas re-resolue a chaque releve : plafond de \(Recenseur.plafondTentativesAirPlay)")
        r.arreter()
    }

    @Test func uneInstanceQuiDisparaitPuisRevientEstResolueDeNouveau() async throws {
        let fab = FabriqueBonjour()
        let compte = Compte()
        let (r, releves) = Self.recenseur(fab, compte)
        r.demarrer()
        let airplay = try #require(fab.crees.first { $0.type == Self.airplay })
        airplay.voir("Muet")
        #expect(await attendreActivation { releves.n >= 1 })
        #expect(await Self.armer(6, fab: fab, releves))
        let avant = compte.de("Muet")
        #expect(avant == Recenseur.plafondTentativesAirPlay, "plafond atteint")

        // Elle disparait, puis revient : de nouvelles tentatives.
        airplay.instances = [:]
        airplay.surChangement?()
        #expect(await Self.attendre(1, releves))
        airplay.voir("Muet")
        #expect(await Self.attendre(1, releves))
        #expect(compte.de("Muet") > avant, "revenue : resolue de nouveau")
        r.arreter()
    }

    @Test func uneInstanceDeNomChangeEstResolue() async throws {
        let fab = FabriqueBonjour()
        let compte = Compte()
        let (r, releves) = Self.recenseur(fab, compte)
        r.demarrer()
        let airplay = try #require(fab.crees.first { $0.type == Self.airplay })
        airplay.voir("Muet")
        #expect(await attendreActivation { releves.n >= 1 })
        #expect(await Self.armer(6, fab: fab, releves))
        airplay.instances = ["Muet renomme": Data()]
        airplay.surChangement?()
        #expect(await Self.attendre(1, releves))
        #expect(compte.de("Muet renomme") == 1, "un autre nom : une autre instance")
        r.arreter()
    }

    @Test func lesAutresTypesSontToujoursResolusTantQuilsNeRepondentPas() async throws {
        let fab = FabriqueBonjour()
        let compte = Compte()
        let (r, releves) = Self.recenseur(fab, compte)
        r.demarrer()
        let routeur = try #require(fab.crees.first { $0.type == "_meshcop._udp" })
        routeur.voir("Routeur muet")
        #expect(await attendreActivation { releves.n >= 1 })
        #expect(await Self.armer(5, fab: fab, releves))
        #expect(compte.de("Routeur muet", type: "_meshcop._udp") > Recenseur.plafondTentativesAirPlay,
                "un routeur de bordure non resolu reste cherche a chaque releve : le plafond ne vaut que pour AirPlay")
        r.arreter()
    }

    // MARK: TXT AirPlay

    @Test func unTXTAirPlayQuiChangeNArmeAucunReleve() {
        let n = NavigateurBonjour(type: Recenseur.typeAirPlay)
        var appels = 0
        n.surChangement = { appels += 1 }
        n.appliquer(["HomePod Salon": Data([5]) + Data("a=b".utf8)])
        #expect(appels == 1, "une instance de plus")
        n.appliquer(["HomePod Salon": Data([5]) + Data("a=c".utf8)])
        #expect(appels == 1, "le TXT seul a change : aucun changement")
        #expect(n.instances["HomePod Salon"] == Data([5]) + Data("a=c".utf8), "mais le TXT garde est le dernier")
        n.appliquer(["HomePod Salon": Data([5]) + Data("a=c".utf8), "Apple TV": Data()])
        #expect(appels == 2, "une instance de plus")
        n.appliquer(["Apple TV": Data()])
        #expect(appels == 3, "une instance de moins")
    }

    @Test func unTXTQuiChangeArmeUnReleveHorsAirPlay() {
        for type in ["_meshcop._udp", "_matter._tcp", "_hap._udp", "_trel._udp"] {
            let n = NavigateurBonjour(type: type)
            var appels = 0
            n.surChangement = { appels += 1 }
            n.appliquer(["X": Data([3]) + Data("a=b".utf8)])
            n.appliquer(["X": Data([3]) + Data("a=c".utf8)])
            #expect(appels == 2, "\(type) : le TXT fait partie de l'etat compare")
        }
    }
}
