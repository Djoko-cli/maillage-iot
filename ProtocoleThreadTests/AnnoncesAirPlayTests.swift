import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

@Suite("Annonces : services AirPlay")
struct AnnoncesAirPlayTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// Une capture d'avant AirPlay n'a pas `airplay` : vide ; une sans service AirPlay ne l'ecrit pas (octets inchanges).
    @Test func captureSansAirPlay() throws {
        let sans = Annonces(date: Self.date, routeurs: [AnnonceService(instance: "Routeur A", hote: "h.local", port: 1)])
        let json = try CodageJSON.encodeur().encode(sans)
        #expect(!String(decoding: json, as: UTF8.self).contains("airplay"))
        let relu = try CodageJSON.decodeur().decode(Annonces.self, from: json)
        #expect(relu == sans && relu.airplay.isEmpty)
    }

    @Test func allerRetourAvecAirPlay() throws {
        let a = Annonces(date: Self.date, airplay: [AnnonceService(instance: "HomePod Salon", hote: "h.local", port: 7000,
                                                                   txt: ChampsTXT(["model": Data("Test1,1".utf8)]))])
        let json = try CodageJSON.encodeur().encode(a)
        #expect(String(decoding: json, as: UTF8.self).contains("airplay"))
        #expect(try CodageJSON.decodeur().decode(Annonces.self, from: json) == a)
    }

    /// Les services AirPlay n'entrent pas dans « le Mac n'entend rien » : un reseau qui n'a que des AirPlay est vide.
    @Test func airPlaySeulResteVide() {
        #expect(Annonces(date: Self.date, airplay: [AnnonceService(instance: "X", hote: "h.local")]).estVide)
    }
}
