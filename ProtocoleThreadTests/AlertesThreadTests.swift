import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Le mecanisme (signatures, oubli a la reunion, regroupement des pertes) est teste dans le coeur
/// (`MaillageCoeurTests/AlertesTests.swift`, politique d'essai) ; ici, ce que Thread decide.
@Suite("Alertes Thread : scission, reunion et pertes selon PolitiqueJournalThread")
struct AlertesThreadTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)
    static let xp = "4B36A2B7FEFB200B"
    static let voisin = "1122334455667788"

    /// Scission d'un reseau en ces partitions (details : partition -> routeurs, comme `detailsPartitions`).
    static func scission(_ partitions: [String], constate: Bool, reseau: String = xp) -> Evenement {
        Evenement(date: t, type: .reseauScinde, reseau: reseau, sujet: Sujet(id: reseau, nom: reseau),
                  apres: String(partitions.count), constate: constate,
                  details: Dictionary(uniqueKeysWithValues: partitions.map { ($0, "routeurs de \($0)") }))
    }

    /// `reseauScinde` est la scission de Thread : constatee et deja notifiee, silence ; autre forme ou observee,
    /// categorie `.scission`, retenue.
    @Test func scissionThreadNotifieeUneFois() {
        var a = Alertes(politique: PolitiqueJournalThread())
        a.scissionsNotifiees = ["4B36A2B7FEFB200B|73586B68,E2E79FFC"]
        #expect(a.traiter([Self.scission(["73586B68", "E2E79FFC"], constate: true)]).isEmpty)
        let autre = Self.scission(["73586B68", "686B5873"], constate: true)
        #expect(a.traiter([autre]).map(\.categorie) == [.scission])
        #expect(a.scissionsNotifiees == ["4B36A2B7FEFB200B|73586B68,E2E79FFC", "4B36A2B7FEFB200B|686B5873,73586B68"])
        #expect(a.traiter([autre]).isEmpty, "trouvee de nouveau (lancement suivant) : pas de seconde notification")
        #expect(a.traiter([Self.scission(["73586B68", "E2E79FFC"], constate: false)]).map(\.categorie) == [.scission],
                "observee : notifiee meme si deja connue")
    }

    /// `reseauReuni` fait oublier les scissions de son reseau, et seulement les siennes ; il se notifie en
    /// `.informations`.
    @Test func reunion() {
        var a = Alertes(politique: PolitiqueJournalThread())
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

    /// Pour Thread, `appareilDisparu` est une perte : trois en 10 min, une notification `.pertes` ; la disparition
    /// d'un routeur de bordure se notifie a part.
    @Test func pertesThread() {
        var a = Alertes(politique: PolitiqueJournalThread())
        func disparu(_ s: Double, _ id: String) -> Evenement {
            Evenement(date: Self.t.addingTimeInterval(s), type: .appareilDisparu, sujet: Sujet(id: id, nom: id))
        }
        #expect(a.traiter([disparu(0, "a"), disparu(60, "b")]).isEmpty)
        #expect(a.traiter([disparu(120, "c")]).map(\.categorie) == [.pertes])
        let routeur = Evenement(date: Self.t, type: .routeurDisparu, sujet: Sujet(id: "r", nom: "r"))
        #expect(a.traiter([routeur]).map(\.categorie) == [.routeurDisparu])
    }
}
