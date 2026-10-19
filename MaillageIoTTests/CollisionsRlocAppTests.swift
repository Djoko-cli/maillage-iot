import Foundation
@testable import MaillageCoeur
@testable import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Cles "rloc:" qualifiees en cas de collision, dans l'app (phase 8) : la sonde passe de la partition principale a une
/// autre partition, ou les memes identifiants de routeur sont d'autres routeurs, jamais identifies. Valeurs inventees.
@MainActor
@Suite("Cles rloc qualifiees dans l'app")
struct CollisionsRlocAppTests {
    static let autre = "0000000B"

    /// Maillage de `JournalMaillageTests` (routeurs 1 et 5 sans ExtMac, l'appareil enfant du 1), dans la partition `p`.
    static func maillage(_ date: Date, partition p: String) -> Maillage {
        var c = ConstructionMaillage(date: date, partition: p)
        c.routeurs(Route64(sequence: 1, routes: [1, 5].map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: 1)
        c.lien(1, 5, sortante: 3, entrante: 2)
        c.enfant(EnfantMaillage(rloc16: 0x0402, extMac: JournalMaillageTests.appareil, qualite: 3, source: .tableEnfants))
        c.signal(SignalSonde(routeur: 1, rssi: p == autre ? -80 : -61))
        return c.maillage()
    }

    /// Deux tournees dans la partition principale, puis une dans l'autre : les routeurs de l'autre partition sont
    /// qualifies dans les sujets du journal, le maillage affiche, les cles et les courbes de l'historique ; ceux de la
    /// principale gardent les cles d'avant. Aucun evenement de routeur au changement de partition.
    @Test func sondeDansUneAutrePartition() throws {
        let s = JournalMaillageTests.surveillance(dossier: nil)
        let principale = try #require(s.thread.reseau?.principale?.id)
        let t = Date().addingTimeInterval(-900)
        let a1 = Self.maillage(t, partition: principale)
        let a2 = Self.maillage(t.addingTimeInterval(300), partition: principale)
        s.thread.recevoir(a1, a: t)
        s.thread.recevoir(a2, a: t.addingTimeInterval(300))
        #expect(s.thread.sujets(a2).routeurs[1]?.id == "rloc:0400", "sans collision : la cle d'avant")
        #expect(s.thread.cleHistorique(noeud: "rloc:0400") == "rloc:0400")
        let avant = s.evenements.count
        let b = Self.maillage(t.addingTimeInterval(600), partition: Self.autre)
        #expect(s.thread.sujets(b).routeurs[1]?.id == "rloc:0000000B:0400", "evalue avant d'entrer dans l'historique")
        s.thread.recevoir(b, a: t.addingTimeInterval(600))
        #expect(!s.evenements.dropFirst(avant).contains { [.routeurThreadApparu, .routeurThreadDisparu].contains($0.type) })
        #expect(s.thread.sujets(b).routeurs[1]?.id == "rloc:0000000B:0400")
        #expect(s.thread.sujets(b).routeurs[5]?.id == "rloc:0000000B:1400")
        let r = try #require(s.thread.reseau)
        let affiche = try #require(s.thread.maillageAffiche(pour: r))
        #expect(affiche.routeurs[1]?.id == "rloc:0000000B:0400" && affiche.noeud("rloc:0400") == nil)
        #expect(s.thread.cleHistorique(noeud: "rloc:0000000B:0400") == "rloc:0000000B:0400")
        let courbes = try #require(s.thread.courbes(noeud: "rloc:0000000B:0400", periode: .jour, fin: Date()))
        #expect(courbes.signal.map(\.valeur) == [-80], "le seul releve de l'autre partition")
        #expect(courbes.liens.map(\.id).contains("rloc:0000000B:1400"))
        let simple = CourbesNoeud(cle: "rloc:0400", releves: s.thread.historique, periode: .jour, fin: Date())
        #expect(simple.signal.map(\.valeur) == [-61, -61], "les deux releves de la principale, pas celui de l'autre")
        let noms = s.thread.nomsHistorique(["rloc:0000000B:0400"])
        #expect(noms["rloc:0000000B:0400"] == String(localized: "Routeur · \("0400")"))
    }
}
