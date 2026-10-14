import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

@MainActor
@Suite("Journal : filtre des lignes (Zigbee)")
struct JournalVueZigbeeTests {

    /// La recherche trouve aussi les noms des parents (« avant » et « apres ») d'une ligne de
    /// changements de parent regroupes, dont le titre ne les cite pas.
    @Test func rechercheDesParentsRegroupes() {
        let t = MaillageDemoZigbee.fin
        let change = { (minutes: Double, avant: String, apres: String) in
            Evenement(date: t.addingTimeInterval(minutes * 60), type: .parentChange,
                      sujet: Sujet(id: "A0000000000000B1", nom: "Détecteur abri"), avant: avant, apres: apres,
                      details: ["ieee": "A0000000000000B1"])
        }
        let lignes = Regroupement.lignes([change(0, "Ruban cuisine", "A0000000000000FD"),
                                          change(5, "A0000000000000FD", "Ruban cuisine")], politique: PolitiqueJournalZigbee())
        #expect(lignes.count == 1 && lignes.first?.evenements.count == 2)
        #expect(FiltreJournal(recherche: "ruban").appliquer(lignes).count == 1, "nom « avant »")
        #expect(FiltreJournal(recherche: "00FD").appliquer(lignes).count == 1, "nom « apres »")
        #expect(FiltreJournal(recherche: "détecteur").appliquer(lignes).count == 1, "sujet, comme avant")
        #expect(FiltreJournal(recherche: "introuvable").appliquer(lignes).isEmpty)
    }

    /// Les evenements du maillage de la sonde ont leur famille, « Maillage », et elle seule.
    @Test func familleMaillage() {
        for t in [TypeEvenement.parentChange, .sansParent] {
            #expect(FamilleEvenement.allCases.filter { $0 != .toutes && $0.contient(t) } == [.maillage], "\(t)")
        }
    }
}
