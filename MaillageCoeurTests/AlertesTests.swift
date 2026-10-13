import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Alertes : une scission n'est notifiee qu'une fois")
struct AlertesTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)
    static let xp = "4B36A2B7FEFB200B"
    static let voisin = "1122334455667788"

    /// Scission d'un reseau en ces partitions (details : partition -> routeurs, comme `detailsPartitions`).
    static func scission(_ partitions: [String], constate: Bool, reseau: String = xp) -> Evenement {
        Evenement(date: t, type: .reseauScinde, reseau: reseau, sujet: Sujet(id: reseau, nom: reseau),
                  apres: String(partitions.count), constate: constate,
                  details: Dictionary(uniqueKeysWithValues: partitions.map { ($0, "routeurs de \($0)") }))
    }

    @Test func signature() {
        #expect(Alertes.signature(Self.scission(["E2E79FFC", "73586B68"], constate: true))
                == "4B36A2B7FEFB200B|73586B68,E2E79FFC", "reseau, puis ses partitions triees")
    }

    /// Une scission constatee (lancement, ouverture de session) deja notifiee ne l'est pas de nouveau.
    @Test func constateeDejaNotifiee() {
        var a = Alertes()
        a.scissionsNotifiees = ["4B36A2B7FEFB200B|73586B68,E2E79FFC"]
        #expect(a.traiter([Self.scission(["73586B68", "E2E79FFC"], constate: true)]).isEmpty)
        #expect(a.scissionsNotifiees == ["4B36A2B7FEFB200B|73586B68,E2E79FFC"])
    }

    /// Une scission constatee d'une nouvelle forme (autre signature) notifie, et est retenue.
    @Test func nouvelleSignature() {
        var a = Alertes()
        a.scissionsNotifiees = ["4B36A2B7FEFB200B|73586B68,E2E79FFC"]
        let e = Self.scission(["73586B68", "686B5873"], constate: true)
        #expect(a.traiter([e]).map(\.categorie) == [.scission])
        #expect(a.scissionsNotifiees == ["4B36A2B7FEFB200B|73586B68,E2E79FFC", "4B36A2B7FEFB200B|686B5873,73586B68"])
        #expect(a.traiter([e]).isEmpty, "trouvee de nouveau (lancement suivant) : pas de seconde notification")
    }

    /// Une scission observee notifie toujours, et est retenue : le lancement suivant ne la notifie pas.
    @Test func observeeToujoursNotifiee() {
        var a = Alertes()
        a.scissionsNotifiees = ["4B36A2B7FEFB200B|73586B68,E2E79FFC"]
        #expect(a.traiter([Self.scission(["73586B68", "E2E79FFC"], constate: false)]).map(\.categorie) == [.scission],
                "observee : notifiee meme si deja connue")
        #expect(a.traiter([Self.scission(["73586B68", "686B5873"], constate: false)]).map(\.categorie) == [.scission])
        #expect(a.scissionsNotifiees.contains("4B36A2B7FEFB200B|686B5873,73586B68"))
        #expect(a.traiter([Self.scission(["73586B68", "686B5873"], constate: true)]).isEmpty)
    }

    /// Une reunion efface les signatures de son reseau, et seulement les siennes.
    @Test func reunion() {
        var a = Alertes()
        a.scissionsNotifiees = ["4B36A2B7FEFB200B|73586B68,E2E79FFC", "4B36A2B7FEFB200B|686B5873,73586B68",
                                "1122334455667788|BBBBBBBB,CCCCCCCC"]
        let reuni = Evenement(date: Self.t, type: .reseauReuni, reseau: Self.xp, sujet: Sujet(id: Self.xp, nom: Self.xp),
                              avant: "2", apres: "1")
        #expect(a.traiter([reuni]).map(\.categorie) == [.informations], "notification inchangee")
        #expect(a.scissionsNotifiees == ["1122334455667788|BBBBBBBB,CCCCCCCC"])
        #expect(a.traiter([Self.scission(["73586B68", "E2E79FFC"], constate: true)]).map(\.categorie) == [.scission],
                "scinde de nouveau apres la reunion : notifie")
        #expect(a.traiter([Self.scission(["BBBBBBBB", "CCCCCCCC"], constate: true, reseau: Self.voisin)]).isEmpty,
                "l'autre reseau garde la sienne")
    }
}
