import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Coeur : identifiant de noeud par protocole")
struct IdNoeudTests {
    /// Aller-retour texte : la forme "protocole:cle" se relit a l'identique, pour les deux protocoles.
    @Test func allerRetourTexte() {
        #expect(IdNoeud(texte: "thread:0000000000000001")?.texte == "thread:0000000000000001")
        #expect(IdNoeud(texte: "zigbee:00000000000000A1")?.texte == "zigbee:00000000000000A1")
        #expect(IdNoeud(texte: "zigbee:00000000000000A1") == IdNoeud(.zigbee, "00000000000000A1"))
    }

    /// La coupure se fait au premier deux-points seulement : la cle garde les suivants.
    @Test func coupureAuPremierDeuxPoints() {
        let instance = IdNoeud(texte: "thread:instance:Pièce 1")
        #expect(instance == IdNoeud(.thread, "instance:Pièce 1"))
        #expect(instance?.cle == "instance:Pièce 1")
        #expect(IdNoeud(texte: "thread:rloc:0400")?.cle == "rloc:0400")
        #expect(IdNoeud(texte: "thread:rloc:0400")?.protocole == .thread)
    }

    /// Refus : protocole inconnu, cle vide, ou pas de deux-points du tout. Le decodage refuse pareil.
    @Test func refusTexteIllisible() throws {
        #expect(IdNoeud(texte: "zigbee:") == nil)
        #expect(IdNoeud(texte: "wifi:x") == nil)
        #expect(IdNoeud(texte: "sans-deux-points") == nil)
        #expect(IdNoeud(texte: "") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(IdNoeud.self, from: Data("\"wifi:x\"".utf8))
        }
    }

    /// Meme EUI-64 de part et d'autre : deux noeuds distincts, deux entrees dans un ensemble.
    @Test func memeCleDeuxProtocolesDistincts() {
        let thread = IdNoeud(.thread, "0000000000000001")
        let zigbee = IdNoeud(.zigbee, "0000000000000001")
        #expect(thread != zigbee)
        #expect(Set([thread, zigbee]).count == 2)
    }

    /// Ordre : le protocole d'abord (ordre des cas, thread avant zigbee), puis la cle.
    @Test func ordreParProtocolePuisCle() {
        let trie = [
            IdNoeud(.zigbee, "00000000000000A1"),
            IdNoeud(.thread, "rloc:0400"),
            IdNoeud(.zigbee, "00000000000000A0"),
            IdNoeud(.thread, "0000000000000001"),
        ].sorted()
        #expect(trie == [
            IdNoeud(.thread, "0000000000000001"),
            IdNoeud(.thread, "rloc:0400"),
            IdNoeud(.zigbee, "00000000000000A0"),
            IdNoeud(.zigbee, "00000000000000A1"),
        ])
        #expect(Protocole.thread < .zigbee)
        #expect(Protocole.allCases == [.thread, .zigbee])
    }

    /// Cle de dictionnaire JSON : un objet et non un tableau, qui se relit a l'identique.
    @Test func dictionnaireJSONCleTexte() throws {
        let dico: [IdNoeud: Int] = [IdNoeud(.thread, "0000000000000001"): 1]
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        let json = try encodeur.encode(dico)
        #expect(String(decoding: json, as: UTF8.self) == #"{"thread:0000000000000001":1}"#)
        let relu = try JSONDecoder().decode([IdNoeud: Int].self, from: json)
        #expect(relu == dico)
    }
}
