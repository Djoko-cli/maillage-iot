import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Alertes : une scission n'est notifiee qu'une fois")
struct AlertesTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)
    static let res = "RESEAU-A"
    static let voisin = "RESEAU-B"
    static let signatureAB = "RESEAU-A|PART-A,PART-B"
    static let signatureAC = "RESEAU-A|PART-A,PART-C"

    /// Scission d'un reseau en ces partitions (details : partition -> routeurs).
    static func scission(_ partitions: [String], constate: Bool, reseau: String = res) -> Evenement {
        Evenement(date: t, type: .essaiScission, reseau: reseau, sujet: Sujet(id: reseau, nom: reseau),
                  apres: String(partitions.count), constate: constate,
                  details: Dictionary(uniqueKeysWithValues: partitions.map { ($0, "routeurs de \($0)") }))
    }

    static func perte(_ secondes: Double, _ id: String = "x") -> Evenement {
        Evenement(date: t.addingTimeInterval(secondes), type: .essaiPerte, sujet: Sujet(id: id, nom: id))
    }

    @Test func signature() {
        #expect(Alertes.signature(Self.scission(["PART-B", "PART-A"], constate: true)) == Self.signatureAB,
                "reseau, puis ses partitions triees")
    }

    /// Une scission constatee (lancement, ouverture de session) deja notifiee ne l'est pas de nouveau.
    @Test func constateeDejaNotifiee() {
        var a = Alertes(politique: PolitiqueEssai())
        a.scissionsNotifiees = [Self.signatureAB]
        #expect(a.traiter([Self.scission(["PART-B", "PART-A"], constate: true)]).isEmpty)
        #expect(a.scissionsNotifiees == [Self.signatureAB])
    }

    /// Une scission constatee d'une nouvelle forme (autre signature) notifie, et est retenue.
    @Test func nouvelleSignature() {
        var a = Alertes(politique: PolitiqueEssai())
        a.scissionsNotifiees = [Self.signatureAB]
        let e = Self.scission(["PART-A", "PART-C"], constate: true)
        #expect(a.traiter([e]).map(\.categorie) == [.scission])
        #expect(a.scissionsNotifiees == [Self.signatureAB, Self.signatureAC])
        #expect(a.traiter([e]).isEmpty, "trouvee de nouveau (lancement suivant) : pas de seconde notification")
    }

    /// Une scission observee notifie toujours, et est retenue : le lancement suivant ne la notifie pas.
    @Test func observeeToujoursNotifiee() {
        var a = Alertes(politique: PolitiqueEssai())
        a.scissionsNotifiees = [Self.signatureAB]
        #expect(a.traiter([Self.scission(["PART-A", "PART-B"], constate: false)]).map(\.categorie) == [.scission],
                "observee : notifiee meme si deja connue")
        #expect(a.traiter([Self.scission(["PART-A", "PART-C"], constate: false)]).map(\.categorie) == [.scission])
        #expect(a.scissionsNotifiees.contains(Self.signatureAC))
        #expect(a.traiter([Self.scission(["PART-A", "PART-C"], constate: true)]).isEmpty)
    }

    /// Une reunion efface les signatures de son reseau, et seulement les siennes.
    @Test func reunion() {
        var a = Alertes(politique: PolitiqueEssai())
        a.scissionsNotifiees = [Self.signatureAB, Self.signatureAC, "RESEAU-B|PART-X,PART-Y"]
        let reuni = Evenement(date: Self.t, type: .essaiReunion, reseau: Self.res, sujet: Sujet(id: Self.res, nom: Self.res),
                              avant: "2", apres: "1")
        #expect(a.traiter([reuni]).map(\.categorie) == [.informations], "notification inchangee")
        #expect(a.scissionsNotifiees == ["RESEAU-B|PART-X,PART-Y"])
        #expect(a.traiter([Self.scission(["PART-A", "PART-B"], constate: true)]).map(\.categorie) == [.scission],
                "scinde de nouveau apres la reunion : notifie")
        #expect(a.traiter([Self.scission(["PART-X", "PART-Y"], constate: true, reseau: Self.voisin)]).isEmpty,
                "l'autre reseau garde la sienne")
    }

    /// Les pertes d'une fenetre de 10 min se notifient ensemble a partir de 3 ; la politique dit ce qui est une perte.
    @Test func pertesGroupeesParLaPolitique() {
        var a = Alertes(politique: PolitiqueEssai())
        #expect(a.traiter([Self.perte(0), Self.perte(60)]).isEmpty, "2 pertes : pas encore")
        let coupee = Evenement(date: Self.t.addingTimeInterval(120), type: .essaiCoupure, sujet: Sujet(id: "z", nom: "z"),
                               details: ["coupee": "oui"])
        let sortie = a.traiter([coupee])
        #expect(sortie.map(\.categorie) == [.pertes])
        #expect(sortie.first?.evenements.count == 3)
        let rejointe = Evenement(date: Self.t.addingTimeInterval(130), type: .essaiCoupure, details: ["coupee": "non"])
        #expect(a.traiter([rejointe]).map(\.categorie) == [.informations], "coupure non coupee : pas une perte")
    }

    /// Sans politique (`PolitiqueJournalNeutre`), rien ne se notifie.
    @Test func politiqueNeutreNeNotifieRien() {
        var a = Alertes(politique: PolitiqueJournalNeutre())
        #expect(a.traiter([Self.scission(["PART-A", "PART-B"], constate: false), Self.perte(0), Self.perte(1),
                           Self.perte(2)]).isEmpty)
    }
}
