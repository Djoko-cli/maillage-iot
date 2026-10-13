import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Journal : filtre des lignes")
struct JournalVueTests {
    @Test func filtreDuJournal() {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let lignes = s.lignesJournal
        #expect(FiltreJournal().appliquer(lignes).count == 6)
        #expect(FiltreJournal(famille: .appareils).appliquer(lignes).count == 1, "la ligne des pertes")
        #expect(FiltreJournal(famille: .prefixes).appliquer(lignes).count == 2)
        #expect(FiltreJournal(graviteMinimale: .alerte).appliquer(lignes).map { $0.evenements.first?.type }
                == [.reseauScinde])
        #expect(FiltreJournal(recherche: "prise bureau").appliquer(lignes).count == 1, "nom d'un appareil du groupe")
        #expect(FiltreJournal(recherche: "4B36A2B7FEFB200B").appliquer(lignes).isEmpty == false, "identifiant du reseau")
        #expect(FiltreJournal(recherche: "introuvable").appliquer(lignes).isEmpty)
        #expect(FamilleEvenement.reseau.contient(.veille))
        #expect(!FamilleEvenement.routeurs.contient(.appareilDisparu))
    }

    /// La recherche trouve aussi les noms des parents (« avant » et « apres ») d'une ligne de
    /// changements de parent regroupes, dont le titre ne les cite pas.
    @Test func rechercheDesParentsRegroupes() {
        let t = ScenarioPanne.date(4, 14)
        let change = { (minutes: Double, avant: String, apres: String) in
            Evenement(date: t.addingTimeInterval(minutes * 60), type: .parentChange,
                      sujet: Sujet(id: "E0000000000000B1", nom: "Prise bureau"), avant: avant, apres: apres,
                      details: ["extMac": "E0000000000000B1"])
        }
        let lignes = Regroupement.lignes([change(0, "HomePod salon", "Routeur · 5000"), change(5, "Routeur · 5000", "HomePod salon")])
        #expect(lignes.count == 1 && lignes.first?.evenements.count == 2)
        #expect(FiltreJournal(recherche: "homepod").appliquer(lignes).count == 1, "nom « avant »")
        #expect(FiltreJournal(recherche: "5000").appliquer(lignes).count == 1, "nom « apres »")
        #expect(FiltreJournal(recherche: "prise").appliquer(lignes).count == 1, "sujet, comme avant")
        #expect(FiltreJournal(recherche: "introuvable").appliquer(lignes).isEmpty)
    }

    /// Les evenements du maillage de la sonde ont leur famille, « Maillage », et elle seule.
    @Test func familleMaillage() {
        for t in [TypeEvenement.parentChange, .sansParent, .routeurThreadApparu, .routeurThreadDisparu] {
            #expect(FamilleEvenement.allCases.filter { $0 != .toutes && $0.contient(t) } == [.maillage], "\(t)")
        }
    }
}
