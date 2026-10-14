import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Les reperes de changement de chemin sur l'historique de la demo Zigbee (valeurs inventees). Le regroupement des
/// reperes est generique et teste au coeur (`ReperesCourbeTests`).
@Suite("Reperes des changements de chemin de la demo Zigbee")
struct ReperesCourbeZigbeeTests {
    typealias I = NomsDemo.Ieee

    /// Sur l'historique de la demo : la lampe du bureau hesite onze fois (dix changements 15 min l'un de l'autre, puis le
    /// passage au lampadaire 10 h avant la fin). Sur 24 h, ils se fondent deux a deux ; sur 7 j, en un seul repere
    /// dont la bulle liste six lignes et « 4 autres » (dix changements moins six), puis un repere isole.
    @Test func demoDuBureau() {
        let c = CourbesNoeud(zigbee: I.lampeBureau, releves: MaillageDemoZigbee.historique, periode: .jour,
                             fin: MaillageDemoZigbee.fin)
        #expect(c.chemins.count == 11 && c.chemins.last?.parent == I.lampadaireSalon)
        #expect(zip(c.chemins, c.chemins.dropFirst()).allSatisfy { $0.parent != $1.parent }, "chaque changement change")
        let jour = ReperesCourbe.regrouper(c.chemins, duree: PeriodeCourbes.jour.duree, largeur: 700)
        #expect(jour.map(\.nombre) == [2, 2, 2, 2, 2, 1], "24 h sur 700 pt : 12 pt = 24 min")
        let semaine = ReperesCourbe.regrouper(c.chemins, duree: PeriodeCourbes.semaine.duree, largeur: 700)
        #expect(semaine.map(\.nombre) == [10, 1], "7 j sur 700 pt : 12 pt = 2 h 53 min")
        #expect(semaine[0].visibles().count == 6 && semaine[0].autres() == 4)
    }
}
