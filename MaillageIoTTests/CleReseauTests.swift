import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Cle de l'acces reseau : demande par l'USB, verification, trousseau (en memoire seulement :
/// les tests ne touchent jamais au trousseau du Mac).
@Suite("Cle de l'acces reseau de la sonde")
struct CleReseauTests {
    static let hexaCle = H1.hexa(VecteursH1.psk)

    /// Reponse de la carte a `cle nouvelle <alea> <id>` (cle des vecteurs H1, valeurs inventees).
    static func reponse(_ id: Int, cle: String = hexaCle, empreinte: String = "630DCD29", hote: String? = "0123456789ABCDEF")
        -> String {
        let h = hote.map { "\"\($0)\"" } ?? "null"
        return #"{"v":1,"t":"cle","id":\#(id),"cle":"\#(cle)","empreinte":"\#(empreinte)","hote":\#(h)}"#
    }

    /// `cle nouvelle <alea en 64 hexa> <id>` : la reponse de meme id.
    @Test func cleNouvelle() async throws {
        let canal = CanalRejoue { l in
            guard l.hasPrefix("cle nouvelle ") else { return [] }
            let id = Int(l.trimmingCharacters(in: .newlines).split(separator: " ").last ?? "") ?? 0
            // Une reponse d'une autre demande d'abord : ignoree.
            return [Self.reponse(id + 50), Self.reponse(id)]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let alea = Data(repeating: 0xAB, count: 32)
        let r = try await s.cleNouvelle(alea: alea)
        #expect(r.id == 1 && r.cle == Self.hexaCle && r.empreinte == "630DCD29" && r.hote == "0123456789ABCDEF")
        #expect(canal.envoyes == ["cle nouvelle " + String(repeating: "AB", count: 32) + " 1\n"])
    }

    /// Une ligne `erreur` pendant l'attente (firmware sans acces reseau, refus) : `refusee`.
    @Test func cleNouvelleRefusee() async throws {
        let canal = CanalRejoue { _ in [#"{"v":1,"t":"erreur","erreur":"commande inconnue"}"#] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.refusee("commande inconnue")) {
            _ = try await s.cleNouvelle(alea: Data(repeating: 0xAB, count: 32))
        }
    }

    /// Sans reponse : `sansReponse`, dont le texte ne montre pas l'alea.
    @Test func cleNouvelleSansReponse() async throws {
        let s = SondeUSB(canal: CanalRejoue { _ in [] })
        try await s.demarrer {}
        do {
            _ = try await s.cleNouvelle(alea: Data(repeating: 0xAB, count: 32))
            Issue.record("une reponse ?")
        } catch {
            #expect(error as? SondeUSB.Erreur == .sansReponse("cle nouvelle"))
            #expect(!error.localizedDescription.contains("ABAB"))
            #expect(!String(describing: error).contains("ABAB"))
        }
    }

    /// Verification avant le trousseau : 64 hexa MAJUSCULES (32 octets), empreinte = 8 premiers
    /// hexa de SHA-256(cle).
    @Test func verifier() throws {
        func lire(_ json: String) throws -> ReponseCle {
            guard case .cle(let r)? = MessageSonde.lire(Data(json.utf8)) else { throw CleReseau.Erreur.cleIllisible }
            return r
        }
        let bonne = try lire(Self.reponse(3))
        let c = try CleReseau.verifier(bonne).get()
        #expect(c.cle == VecteursH1.psk)
        #expect(c.empreinte == "630DCD29")
        #expect(c.hote == "0123456789ABCDEF")
        let minuscules = try lire(Self.reponse(3, cle: Self.hexaCle.lowercased()))
        let courte = try lire(Self.reponse(3, cle: "ABCD"))
        let fausse = try lire(Self.reponse(3, empreinte: "00000000"))
        #expect(CleReseau.verifier(minuscules) == .failure(.cleIllisible))
        #expect(CleReseau.verifier(courte) == .failure(.cleIllisible))
        #expect(CleReseau.verifier(ReponseCle(id: 3, cle: nil, empreinte: "630DCD29", hote: nil)) == .failure(.cleIllisible))
        #expect(CleReseau.verifier(fausse) == .failure(.empreinteIncoherente))
        #expect(CleReseau.alea().count == 32)
        #expect(CleReseau.alea() != CleReseau.alea())
    }

    /// La cle verifiee n'apparait dans aucune description ni dump ; les erreurs non plus.
    @Test func cleMasquee() throws {
        let c = CleReseau.Creee(cle: VecteursH1.psk, empreinte: "630DCD29", hote: "0123456789ABCDEF")
        var vidage = ""
        dump(c, to: &vidage)
        let libelles = Mirror(reflecting: c).children.compactMap { $0.label }
        #expect(!libelles.contains("cle"))
        #expect(!String(describing: c).contains(Self.hexaCle) && !String(reflecting: c).contains(Self.hexaCle))
        #expect(vidage.contains("630DCD29"))
        let erreurs: [any Error] = [CleReseau.Erreur.cleIllisible, CleReseau.Erreur.empreinteIncoherente,
                                    CleReseau.Erreur.sansNomDHote, ErreurTrousseau.absente("0123456789ABCDEF")]
        let textes = erreurs.map { $0.localizedDescription }
        #expect(Set(textes).count == erreurs.count)
    }

    /// Trousseau en memoire (celui des tests) : ranger, lire, remplacer, oublier.
    @Test func trousseau() throws {
        let t = TrousseauMemoire()
        #expect(t.lister().isEmpty)
        #expect(throws: ErreurTrousseau.absente("0123456789ABCDEF")) { try t.lire(nom: "0123456789ABCDEF") }
        try t.ranger(nom: "0123456789ABCDEF", cle: VecteursH1.psk, empreinte: "630DCD29")
        #expect(t.lister() == [SondeConnue(nom: "0123456789ABCDEF", empreinte: "630DCD29")])
        #expect(try t.lire(nom: "0123456789ABCDEF") == VecteursH1.psk)
        // Nouvelle cle pour la meme sonde : remplacee, pas doublee.
        try t.ranger(nom: "0123456789ABCDEF", cle: Data(repeating: 9, count: 32), empreinte: "11111111")
        #expect(t.lister().count == 1)
        #expect(try t.lire(nom: "0123456789ABCDEF") == Data(repeating: 9, count: 32))
        try t.oublier(nom: "0123456789ABCDEF")
        #expect(t.lister().isEmpty)
        try t.oublier(nom: "0123456789ABCDEF")  // deja oubliee : sans erreur
        #expect(SondeConnue(nom: "0123456789ABCDEF", empreinte: "630DCD29").hote == "0123456789ABCDEF.local")
        // Le trousseau du Mac : service propre a la sonde (compte = nom d'hote).
        #expect(TrousseauSysteme().service == "fr.djoko.maillage.iot.sonde-thread")
    }
}
