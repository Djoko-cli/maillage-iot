import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Releve reel du 28/09 (donnees du mode demo et des tests)")
struct ReleveTests {
    let a = Releve20260928.annonces

    @Test func contenu() {
        #expect(a.routeurs.count == 6)
        #expect(a.matter.count == 57)
        #expect(a.hap.isEmpty)
        #expect(Set(a.matter.compactMap(\.hote)).count == 28)
        #expect(a.routes.count == 2)
        #expect(a.prefixesLocaux == ["fd4b:36a2:b7fe:200b::/64"])
        #expect(abs(a.date.timeIntervalSince1970 - 1_790_547_354.126) < 0.001, "2026-09-27T22:15:54.126Z")
    }

    @Test func routeursDecodes() throws {
        let routeurs = a.routeurs.map { RouteurBordure(annonce: $0, adresses: a.adresses(de: $0.hote)) }
        let parNom = Dictionary(uniqueKeysWithValues: routeurs.map { ($0.instance, $0) })
        let atv = try #require(parNom["Apple TV 4K"])
        #expect(atv.role == .chef)
        #expect(atv.partition == "73586B68")
        #expect(atv.adressesLien.map(\.description) == ["fe80::5a:d5f3:dc72:e7d6"])
        let aqara = try #require(parNom["Aqara HubM100 #DFEB"])
        #expect(aqara.partition == "E2E79FFC")
        #expect(aqara.role == nil, "Thread 1.3.0")
        #expect(aqara.prefixeOMR?.description == "fd03:54f0:5de:1::/64")
        #expect(Set(routeurs.compactMap(\.idReseau)) == ["4B36A2B7FEFB200B"])
        #expect(routeurs.filter { $0.role == .routeur }.count == 4)
    }

    @Test func horsAdresse() {
        let sans = a.matter.compactMap(\.hote).filter { a.adresses(de: $0).isEmpty }
        #expect(Set(sans) == ["1E5019DAC2638F92.local", "724CC16B32D8F820.local"])
    }

    @Test func allerRetour() throws {
        let json = try CodageJSON.encodeur().encode(a)
        #expect(try CodageJSON.decodeur().decode(Annonces.self, from: json) == a)
    }
}
