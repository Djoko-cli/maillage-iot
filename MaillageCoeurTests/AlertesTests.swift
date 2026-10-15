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

    /// Les pertes oubliees (un protocole eteint) ne comptent plus : ni pour le seuil, ni dans la notification.
    @Test func pertesOublieesNeComptentPlus() {
        var a = Alertes(politique: PolitiqueEssai())
        #expect(a.traiter([Self.perte(0, "z1"), Self.perte(1, "z2")]).isEmpty)
        a.oublierPertes { $0.sujet?.id.hasPrefix("z") == true }
        #expect(a.traiter([Self.perte(300, "t1")]).isEmpty, "deux oubliees + une : pas trois")
        let sortie = a.traiter([Self.perte(301, "t2"), Self.perte(302, "t3")])
        #expect(sortie.map(\.categorie) == [.pertes])
        #expect(sortie.first?.evenements.map(\.sujet?.id) == ["t1", "t2", "t3"], "rien des oubliees")
        a.oublierPertes { _ in true }
        #expect(a.traiter([Self.perte(400), Self.perte(401)]).isEmpty, "fenetre videe puis rouverte : 2 pertes seulement")
    }

    /// Sans politique (`PolitiqueJournalNeutre`), rien ne se notifie.
    @Test func politiqueNeutreNeNotifieRien() {
        var a = Alertes(politique: PolitiqueJournalNeutre())
        #expect(a.traiter([Self.scission(["PART-A", "PART-B"], constate: false), Self.perte(0), Self.perte(1),
                           Self.perte(2)]).isEmpty)
    }

    /// Les pertes se comptent par protocole : trois pertes de deux protocoles ne font pas une notification groupee, et celle
    /// d'un protocole n'embarque que les siennes, sous un identifiant a lui.
    @Test func pertesParProtocole() {
        func perte(_ secondes: Double, _ protocole: Protocole, _ id: String) -> Evenement {
            Evenement(date: Self.t.addingTimeInterval(secondes), type: .essaiPerte, sujet: Sujet(id: id, nom: id),
                      protocole: protocole)
        }
        var a = Alertes(politique: PolitiqueEssai())
        #expect(a.traiter([perte(0, .thread, "t1"), perte(1, .zigbee, "z1"), perte(2, .thread, "t2")]).isEmpty,
                "trois pertes en tout, mais deux et une")
        let sortie = a.traiter([perte(3, .zigbee, "z2"), perte(4, .zigbee, "z3")])
        #expect(sortie.map(\.categorie) == [.pertes])
        #expect(sortie.first?.evenements.compactMap(\.sujet?.id) == ["z1", "z2", "z3"], "rien de Thread")
        let thread = a.traiter([perte(5, .thread, "t3")])
        #expect(thread.first?.evenements.compactMap(\.sujet?.id) == ["t1", "t2", "t3"], "rien de Zigbee")
        #expect(thread.first?.identifiant != sortie.first?.identifiant, "deux groupes ouverts a la meme minute : deux identifiants")
        // Un protocole oublie (eteint) laisse l'autre intact.
        a.oublierPertes { $0.protocole == .zigbee }
        #expect(a.traiter([perte(6, .thread, "t4")]).first?.evenements.compactMap(\.sujet?.id) == ["t1", "t2", "t3", "t4"])
    }
}
