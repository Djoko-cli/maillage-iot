import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Panne du 27/09 rejouee")
struct ScenarioPanneTests {
    typealias D = ScenarioPanne

    /// Rejoue le scenario : (date du releve, evenements) a chaque releve.
    static func rejouer() -> (suivi: Suivi, pas: [(Date, [Evenement])]) {
        var s = Suivi()
        let noms = ResolveurNoms(maison: NomsDemo.maison)
        let pas = D.releves.map { a in (a.date, s.integrer(a, noms: noms)) }
        return (s, pas)
    }

    @Test func evenements() {
        let tous = Self.rejouer().pas.flatMap(\.1)
        let attendus: [(TypeEvenement, Date)] = [
            (.surveillanceDemarree, D.date(3, 55)),
            (.routeurNouvelleAdresseLien, D.date(4, 5)),
            (.prefixeNouveau, D.date(4, 5)),
            (.prefixeRetire, D.date(4, 6)),
            (.reseauScinde, D.date(4, 14)),
            (.appareilSansAdresse, D.date(4, 14)),
            (.appareilDisparu, D.date(4, 15)),
            (.appareilDisparu, D.date(4, 16)),
            (.appareilDisparu, D.date(4, 18)),
            (.appareilDisparu, D.date(4, 20)),
        ]
        #expect(tous.map(\.type) == attendus.map(\.0))
        #expect(tous.map(\.date) == attendus.map(\.1))
        #expect(tous.first?.details == ["routeurs": "6", "appareils": "24"])
        #expect(tous[1].sujet?.nom == "Apple TV 4K")
        #expect(tous[2].sujet?.id == "fd19:961f:2db3::/64")
        #expect(tous[3].sujet?.id == "fd4f:9c:ed42::/64")
        #expect(tous[4].details["E2E79FFC"] == "Aqara HubM100 #DFEB")
        #expect(tous[5].sujet?.id == D.sansAdresse)
        #expect(tous.suffix(4).map { $0.sujet?.nom ?? "" }
                == ["Prise bureau", "Prise salon", "Thermo chambre", "Ampoule entrée"], "noms de la demo")
    }

    @Test func detectionApresDeuxMinutes() {
        let pas = Self.rejouer().pas
        let quand = pas.filter { !$0.1.isEmpty }.map(\.0)
        #expect(quand == [D.date(3, 55), D.date(4, 5), D.date(4, 6), D.date(4, 14), D.date(4, 16),
                          D.date(4, 17), D.date(4, 18), D.date(4, 20), D.date(4, 22)])
    }

    @Test func etatFinal() throws {
        let s = Self.rejouer().suivi
        let i = try #require(s.instantane)
        #expect(i.reseaux.first?.partitions.map(\.id) == ["73586B68", "E2E79FFC"])
        #expect(i.appareil(D.sansAdresse)?.etat == .sansAdresse)
        #expect(Set(s.disparus.keys) == Set(D.perdus.map(\.hote)))
        #expect(s.dernieresPartitions["46F77B36E071F8D0"] == "73586B68")
        #expect(i.appareils.filter { $0.etat == .joignable }.count == 19)
    }

    @Test func uneLigneDePertes() throws {
        let lignes = Regroupement.lignes(Self.rejouer().pas.flatMap(\.1))
        #expect(lignes.count == 6)
        guard case .pertes(let pertes) = lignes.first else {
            Issue.record("la ligne la plus recente devrait regrouper les pertes")
            return
        }
        #expect(pertes.count == 5)
        #expect(pertes.first?.date == D.date(4, 14))
        #expect(pertes.last?.date == D.date(4, 20))
        #expect(lignes.first?.date == D.date(4, 20))
        #expect(lignes.first?.gravite == .attention)
        #expect(lignes.map(\.evenements.first?.type) == [.appareilSansAdresse, .reseauScinde, .prefixeRetire,
                                                          .prefixeNouveau, .routeurNouvelleAdresseLien,
                                                          .surveillanceDemarree])
    }

    @Test func notifications() {
        var alertes = Alertes()
        var envoyees: [(Date, AlerteAEnvoyer)] = []
        for (date, ev) in Self.rejouer().pas {
            for a in alertes.traiter(ev) { envoyees.append((date, a)) }
        }
        let importantes = envoyees.filter { $0.1.categorie != .informations }
        #expect(importantes.map(\.1.categorie) == [.scission, .pertes, .pertes, .pertes])
        #expect(importantes.map(\.0) == [D.date(4, 14), D.date(4, 18), D.date(4, 20), D.date(4, 22)])
        #expect(importantes.dropFirst().map(\.1.evenements.count) == [3, 4, 5])
        #expect(Set(importantes.dropFirst().map(\.1.identifiant)).count == 1, "la meme notification, mise a jour")
        #expect(envoyees.filter { $0.1.categorie == .informations }.count == 3)
        #expect(CategorieAlerte.allCases.filter(\.parDefaut) == [.scission, .routeurDisparu, .pertes])
    }

    /// L'identifiant de la notification groupee est fixe a l'ouverture de sa
    /// fenetre : une perte arrivee apres, mais datee avant, la met a jour sur place.
    @Test func identifiantDesPertesFige() throws {
        let t = D.date(4, 0)
        func perte(_ secondes: TimeInterval, _ id: String) -> Evenement {
            Evenement(date: t.addingTimeInterval(secondes), type: .appareilDisparu, sujet: Sujet(id: id, nom: id))
        }
        var alertes = Alertes()
        let premieres = alertes.traiter([perte(0, "a"), perte(10, "b"), perte(20, "c")])
        let x = try #require(premieres.first { $0.categorie == .pertes }).identifiant
        let suite = alertes.traiter([perte(-90, "d")])
        #expect(suite.map(\.categorie) == [.pertes])
        #expect(suite.first?.identifiant == x, "la meme notification, remplacee")
        #expect(suite.first?.evenements.count == 4)
    }

    @Test func regroupementSepareLesFenetres() {
        let t = D.date(4, 0)
        func perte(_ minutes: Double) -> Evenement {
            Evenement(date: t.addingTimeInterval(minutes * 60), type: .appareilDisparu,
                      sujet: Sujet(id: "\(minutes)", nom: "\(minutes)"))
        }
        let lignes = Regroupement.lignes([perte(0), perte(5), perte(12), perte(30), perte(31)])
        #expect(lignes.map(\.evenements.count) == [2, 1, 2], "10 min comptees depuis la premiere perte")
        let isole = Evenement(date: t, type: .appareilChangePartition, details: ["coupee": "oui"])
        #expect(Regroupement.estPerte(isole))
        #expect(!Regroupement.estPerte(Evenement(date: t, type: .appareilChangePartition)))
    }
}
