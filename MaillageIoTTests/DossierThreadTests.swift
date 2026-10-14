import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Les fichiers propres a Thread s'ecrivent sous `Thread/` (spec 2.2, 6.6) ; ceux de tous les protocoles restent a la
/// racine du dossier de l'app. Aucune migration : rien n'est lu d'un ancien emplacement.
@MainActor
@Suite("Dossier Thread : fichiers de Thread sous Thread/, fichiers communs a la racine")
struct DossierThreadTests {
    static let racines = ["associations.json", "dernier-maillage.json", "dernieres-adresses.json", "identites-routeurs.json"]

    /// L'historique, `dernier-maillage.json`, les adresses gardees et les associations s'ecrivent sous `Thread/` ; le
    /// surnom (`surnoms.json`) reste a la racine ; rien de Thread ne se retrouve a la racine.
    @Test func fichiersDeThreadSousThread() throws {
        let dossier = SurveillanceTests.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = AdresseVerifieeAppTests.surveillanceSurDisque(dossier)
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        s.recevoir(try SurveillanceTests.maillageGarde(recu.addingTimeInterval(-60)), a: recu)
        s.noms.maison = AssociationMaisonTests.maison()
        s.associer(AssociationMaisonTests.muet, a: AssociationMaisonTests.maison().accessoires[1])
        s.renommer(idt(AssociationMaisonTests.muet), en: "Mon surnom")

        let fm = FileManager.default
        let thread = dossier.appendingPathComponent("Thread", isDirectory: true)
        let sousThread = try fm.contentsOfDirectory(atPath: thread.path).sorted()
        #expect(sousThread.contains("associations.json"))
        #expect(sousThread.contains("dernier-maillage.json"))
        #expect(sousThread.contains("dernieres-adresses.json"))
        let historique = sousThread.filter { $0.hasPrefix("maillage-") && $0.hasSuffix(".jsonl") }
        #expect(historique.count == 1, "l'historique du mois : \(sousThread)")
        let racine = try fm.contentsOfDirectory(atPath: dossier.path).sorted()
        #expect(racine.contains("surnoms.json"), "les surnoms sont communs : \(racine)")
        for nom in Self.racines { #expect(!racine.contains(nom), "\(nom) ne reste pas a la racine") }
        #expect(!racine.contains { $0.hasPrefix("maillage-") }, "pas d'historique a la racine : \(racine)")

        // Le lancement suivant relit tout sous Thread/.
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.chargerMaillageGarde()
        #expect(relu.maillage != nil)
        #expect(relu.noms.associations == [AssociationMaisonTests.muet: "00000000000000AA"])
        #expect(relu.surnom(de: idt(AssociationMaisonTests.muet)) == "Mon surnom")
    }

    /// Le dossier de Thread, et les fichiers hors de Surveillance : les identites des routeurs sous `Thread/`, le releve
    /// de Maison (commun aux protocoles) a la racine.
    @Test func cheminsDesFichiers() {
        let racine = Surveillance.dossierParDefaut
        #expect(Surveillance.dossierThread(racine) == racine.appendingPathComponent("Thread", isDirectory: true))
        #expect(SondeMaillage.fichierIdentites(demo: false, sousTests: false)
                == Surveillance.dossierThread(racine).appendingPathComponent("identites-routeurs.json"))
        #expect(NomsPasseur.fichierCache(dossier: racine) == racine.appendingPathComponent("releve-maison.json"))
    }
}
