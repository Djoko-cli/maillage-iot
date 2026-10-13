import Foundation
import Testing
@testable import MaillageCoeur

@Suite("TypeEvenement ouvert : le journal reste lisible a l'identique")
struct TypeEvenementTests {
    static let typeEssai = TypeEvenement("essaiAttention", gravite: .attention)

    /// Decodeur du journal (dates comme les fichiers reels) qui connait les types donnes.
    static func decodeur(_ types: [TypeEvenement]) -> JSONDecoder {
        let d = CodageJSON.decodeur()
        d.userInfo[.typesEvenement] = Dictionary(uniqueKeysWithValues: types.map { ($0.rawValue, $0) })
        return d
    }

    @Test func encodeCommeUneChaine() throws {
        let data = try JSONEncoder().encode(TypeEvenement.veille)
        #expect(String(decoding: data, as: UTF8.self) == "\"veille\"")
    }

    @Test func egaliteParLeNomSeul() {
        #expect(TypeEvenement("x", gravite: .alerte) == TypeEvenement(rawValue: "x"))
        #expect(TypeEvenement("x", gravite: .alerte).hashValue == TypeEvenement(rawValue: "x").hashValue)
    }

    @Test func ligneSansGraviteRetrouveLaGraviteDuTypeConnu() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"essaiAttention"}"#
        let e = try Self.decodeur([Self.typeEssai]).decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.type == Self.typeEssai)
        #expect(e.gravite == .attention)
    }

    @Test func typeInconnuConserve() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"parentPerduZigbee","gravite":"alerte"}"#
        let e = try Self.decodeur([]).decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.type.rawValue == "parentPerduZigbee")
        #expect(e.gravite == .alerte)
    }

    @Test func typeInconnuSansGraviteEstUneInformation() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"parentPerduZigbee"}"#
        let e = try Self.decodeur([Self.typeEssai]).decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.gravite == .info)
    }

    @Test func typeInconnuSeReecritTelQuel() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"parentPerduZigbee","gravite":"alerte"}"#
        let e = try Self.decodeur([]).decode(Evenement.self, from: Data(ligne.utf8))
        let json = String(decoding: try CodageJSON.encodeur().encode(e), as: UTF8.self)
        #expect(json.contains(#""type":"parentPerduZigbee""#))
        #expect(json.contains(#""gravite":"alerte""#))
    }

    @Test func graviteHorsEncodageDuType() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.typeEssai), as: UTF8.self)
        #expect(json == "\"essaiAttention\"")
    }

    @Test func politiqueNeutreNeConnaitQueLesTypesDuCoeur() {
        #expect(PolitiqueJournalNeutre().types == [.surveillanceDemarree, .veille])
    }
}
