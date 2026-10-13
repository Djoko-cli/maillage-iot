import Foundation
import Testing
@testable import MaillageCoeur

/// Le resume des relais d'une ligne de changements de parent regroupes (repris de Maillage Zigbee, 09/10) : les parents
/// dans l'ordre ou le noeud y est passe, sans doublon, et celui sur lequel il finit. Valeurs inventees.
@Suite("Resume des relais")
struct ResumeRelaisTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func change(_ minutes: Double, _ avant: String?, _ apres: String?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: "x", nom: "Capteur"),
                  avant: avant, apres: apres)
    }

    @Test func relais() {
        // Trois parents qui reviennent les uns aux autres : leur ordre de premiere apparition, sans doublon.
        let trois = Regroupement.resumeRelais([Self.change(0, "A", "B"), Self.change(10, "B", "C"), Self.change(20, "C", "A"),
                                               Self.change(30, "A", "C")])
        #expect(trois.relais == ["A", "B", "C"] && trois.dernier == "C" && !trois.alternent)
        // Deux parents qui alternent.
        let deux = Regroupement.resumeRelais([Self.change(0, "A", "B"), Self.change(5, "B", "A"), Self.change(9, "A", "B"),
                                              Self.change(12, "B", "A")])
        #expect(deux.relais == ["A", "B"] && deux.dernier == "A" && deux.alternent)
        // L'ordre des dates prime sur celui des evenements donnes.
        let melange = Regroupement.resumeRelais([Self.change(10, "B", "C"), Self.change(0, "A", "B")])
        #expect(melange.relais == ["A", "B", "C"] && melange.dernier == "C")
        // Noms absents ou vides ignores ; aucun changement.
        let trous = Regroupement.resumeRelais([Self.change(0, nil, "B"), Self.change(5, "", "")])
        #expect(trous.relais == ["B"] && trous.dernier == nil && !trous.alternent)
        let rien = Regroupement.resumeRelais([])
        #expect(rien.relais.isEmpty && rien.dernier == nil)
    }
}
