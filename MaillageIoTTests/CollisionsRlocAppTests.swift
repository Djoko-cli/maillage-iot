import Foundation
@testable import MaillageCoeur
@testable import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Cles "rloc:" qualifiees en cas de collision, dans l'app (phase 8, decision de Djoko du 20/10) : seulement pendant une
/// scission, entre partitions que Bonjour annonce ensemble (le bandeau « Reseau scinde ») ; un simple changement
/// d'identifiant de partition garde les cles simples. Valeurs inventees.
@MainActor
@Suite("Cles rloc qualifiees dans l'app")
struct CollisionsRlocAppTests {
    /// Maillage de `JournalMaillageTests` (routeurs 1 et 5 sans ExtMac, l'appareil enfant du 1), dans la partition `p`.
    static func maillage(_ date: Date, partition p: String, rssi: Int = -61) -> Maillage {
        var c = ConstructionMaillage(date: date, partition: p)
        c.routeurs(Route64(sequence: 1, routes: [1, 5].map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: 1)
        c.lien(1, 5, sortante: 3, entrante: 2)
        c.enfant(EnfantMaillage(rloc16: 0x0402, extMac: JournalMaillageTests.appareil, qualite: 3, source: .tableEnfants))
        c.signal(SignalSonde(routeur: 1, rssi: rssi))
        return c.maillage()
    }

    static let evenementsRouteur: [TypeEvenement] = [.routeurThreadApparu, .routeurThreadDisparu]

    /// Reseau non scinde : la sonde passe de la partition principale a un autre identifiant de partition (memes
    /// identifiants de routeur) ; rien n'est qualifie, ni au journal, ni dans la scene, ni dans l'historique, et le
    /// releve ne garde aucune partition active.
    @Test func changementDIdentifiantSansScission() throws {
        let s = JournalMaillageTests.surveillance(dossier: nil)
        #expect(s.thread.reseau?.estScinde == false)
        let principale = try #require(s.thread.reseau?.principale?.id)
        let t = Date().addingTimeInterval(-900)
        s.thread.recevoir(Self.maillage(t, partition: principale), a: t)
        let b = Self.maillage(t.addingTimeInterval(300), partition: "0000000B")
        #expect(s.thread.sujets(b).routeurs[1]?.id == "rloc:0400")
        s.thread.recevoir(b, a: t.addingTimeInterval(300))
        #expect(s.thread.sujets(b).routeurs[1]?.id == "rloc:0400" && s.thread.sujets(b).routeurs[5]?.id == "rloc:1400")
        #expect(s.thread.cleHistorique(noeud: "rloc:0400") == "rloc:0400")
        #expect(s.thread.historique.allSatisfy { $0.actives.isEmpty })
        let courbes = try #require(s.thread.courbes(noeud: "rloc:0400", periode: .jour, fin: Date()))
        #expect(courbes.signal.count == 2, "une seule courbe, comme avant la phase 8")
    }

    /// Relecture finale, Important 1 : la sonde, dans une partition avant la scission, se retrouve dans l'autre pendant
    /// la scission avec les memes identifiants de routeur (la transition de Bonjour, ou la moitie renommee) ; le releve
    /// d'avant la scission ne compte pas : rien n'est qualifie, ni au journal, ni dans la scene, ni dans l'historique.
    @Test func releveDAvantLaScissionNeComptePas() async throws {
        let dossier = JournalMaillageTests.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        // Les deux partitions de la panne rejouee, lues sur une surveillance a part.
        let essai = Surveillance(mode: .direct, dossier: nil)
        for a in ScenarioPanne.releves { essai.thread.integrer(a) }
        let principale = try #require(essai.thread.reseau?.principale?.id)
        let autre = try #require(essai.thread.reseau?.partitions.map(\.id).first { $0 != principale })
        let s = Surveillance(mode: .direct, dossier: dossier)
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 900)
        // Avant la scission (aucune annonce : aucune partition active) : la sonde dans l'autre, memes identifiants.
        s.thread.recevoir(Self.maillage(t, partition: autre), a: t)
        #expect(s.thread.historique.last?.actives == [])
        for a in ScenarioPanne.releves { s.thread.integrer(a) }
        let r = try #require(s.thread.reseau)
        #expect(r.estScinde && r.principale?.id == principale)
        let m = Self.maillage(t.addingTimeInterval(120), partition: principale)
        #expect(s.thread.sujets(m).routeurs[1]?.id == "rloc:0400")
        s.thread.recevoir(m, a: t.addingTimeInterval(120))
        #expect(s.thread.historique.last?.actives.isEmpty == false, "le releve garde la scission")
        #expect(s.thread.sujets(m).routeurs[1]?.id == "rloc:0400" && s.thread.sujets(m).routeurs[5]?.id == "rloc:1400")
        let affiche = try #require(s.thread.maillageAffiche(pour: r))
        #expect(affiche.routeurs[1]?.id == "rloc:0400")
        let cles = ClesHistorique(releves: s.thread.historique)
        #expect(s.thread.historique.indices.map { cles.cle(releve: $0, routeur: 1) } == ["rloc:0400", "rloc:0400"])
    }

    /// Reseau scinde (la panne rejouee : 73586B68 et E2E79FFC annonces ensemble) : la sonde dans la principale, puis dans
    /// l'autre partition, ou les memes identifiants sont d'autres routeurs ; ceux de l'autre sont qualifies (sujets du
    /// journal, maillage affiche, cles et courbes de l'historique, noms), sans evenement de routeur ; les releves gardent
    /// les partitions actives, sur disque aussi. Fin de la scission : la sonde revenue dans la principale, ses routeurs
    /// ont leur cle simple ; le releve de l'autre partition reste qualifie.
    @Test func scissionPuisFin() async throws {
        let dossier = JournalMaillageTests.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        for a in ScenarioPanne.releves { s.thread.integrer(a) }
        let r = try #require(s.thread.reseau)
        #expect(r.estScinde, "le bandeau de scission")
        let principale = try #require(r.principale?.id)
        let autre = try #require(r.partitions.map(\.id).first { $0 != principale })
        let actives = r.partitions.map(\.id).sorted()
        // Des secondes entieres : le fichier garde les dates a la milliseconde.
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 900)
        s.thread.recevoir(Self.maillage(t, partition: principale), a: t)
        s.thread.recevoir(Self.maillage(t.addingTimeInterval(120), partition: principale), a: t.addingTimeInterval(120))
        #expect(s.thread.historique.last?.actives == actives)
        let avant = s.evenements.count
        let b = Self.maillage(t.addingTimeInterval(240), partition: autre, rssi: -80)
        let qualifiee = "rloc:\(autre):0400"
        #expect(s.thread.sujets(b).routeurs[1]?.id == qualifiee, "evalue avant d'entrer dans l'historique")
        s.thread.recevoir(b, a: t.addingTimeInterval(240))
        #expect(!s.evenements.dropFirst(avant).contains { Self.evenementsRouteur.contains($0.type) })
        #expect(s.thread.sujets(b).routeurs[1]?.id == qualifiee && s.thread.sujets(b).routeurs[5]?.id == "rloc:\(autre):1400")
        let affiche = try #require(s.thread.maillageAffiche(pour: r))
        #expect(affiche.routeurs[1]?.id == qualifiee && affiche.noeud("rloc:0400") == nil)
        #expect(s.thread.cleHistorique(noeud: qualifiee) == qualifiee)
        let courbes = try #require(s.thread.courbes(noeud: qualifiee, periode: .jour, fin: Date()))
        #expect(courbes.signal.map(\.valeur) == [-80], "le seul releve de l'autre partition")
        let simple = CourbesNoeud(cle: "rloc:0400", releves: s.thread.historique, periode: .jour, fin: Date())
        #expect(simple.signal.map(\.valeur) == [-61, -61], "les deux releves de la principale, pas celui de l'autre")
        #expect(s.thread.nomsHistorique([qualifiee])[qualifiee] == String(localized: "Routeur · \("0400")"))

        // Fin de la scission : Bonjour n'annonce plus qu'une partition.
        var reunie = ScenarioPanne.annonces(a: ScenarioPanne.date(4, 10))
        reunie.date = ScenarioPanne.fin.addingTimeInterval(60)
        s.thread.integrer(reunie)
        #expect(s.thread.reseau?.estScinde == false)
        let a3 = Self.maillage(t.addingTimeInterval(360), partition: principale)
        s.thread.recevoir(a3, a: t.addingTimeInterval(360))
        #expect(s.thread.sujets(a3).routeurs[1]?.id == "rloc:0400" && s.thread.historique.last?.actives == [])
        #expect(!s.evenements.dropFirst(avant).contains { Self.evenementsRouteur.contains($0.type) })
        #expect(CourbesNoeud(cle: "rloc:0400", releves: s.thread.historique, periode: .jour, fin: Date()).signal.count == 3)
        #expect(CourbesNoeud(cle: qualifiee, releves: s.thread.historique, periode: .jour, fin: Date()).signal.map(\.valeur) == [-80])

        // Relu par un nouveau lancement : les memes partitions actives, donc les memes cles.
        let relu = Surveillance(mode: .direct, dossier: dossier)
        await relu.thread.chargerHistorique()
        #expect(relu.thread.historique.map(\.actives) == s.thread.historique.map(\.actives))
        let cles = ClesHistorique(releves: relu.thread.historique)
        #expect(relu.thread.historique.indices.map { cles.cle(releve: $0, routeur: 1) }
                == ["rloc:0400", "rloc:0400", qualifiee, "rloc:0400"])
    }

    /// Marge avant la fin d'une scission (decision de Djoko du 20/10), a travers un redemarrage de l'app : la sonde dans
    /// l'autre partition, Bonjour n'annonce plus la scission. Le premier releve sans scission garde les cles qualifiees ;
    /// relue par un nouveau lancement, la marge continue la ou elle en etait (elle se deduit des releves de l'historique,
    /// comme la tenante) : le deuxieme releve reste qualifie, le troisieme finit la scission.
    @Test func margeAPresUnRedemarrage() async throws {
        let dossier = JournalMaillageTests.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        for a in ScenarioPanne.releves { s.thread.integrer(a) }
        let r = try #require(s.thread.reseau)
        let principale = try #require(r.principale?.id)
        let autre = try #require(r.partitions.map(\.id).first { $0 != principale })
        let qualifiee = "rloc:\(autre):0400"
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 900)
        s.thread.recevoir(Self.maillage(t, partition: principale), a: t)
        let b1 = Self.maillage(t.addingTimeInterval(120), partition: autre)
        s.thread.recevoir(b1, a: t.addingTimeInterval(120))
        #expect(s.thread.sujets(b1).routeurs[1]?.id == qualifiee)
        var reunie = ScenarioPanne.annonces(a: ScenarioPanne.date(4, 10))
        reunie.date = ScenarioPanne.fin.addingTimeInterval(60)
        s.thread.integrer(reunie)
        #expect(s.thread.reseau?.estScinde == false)
        let b2 = Self.maillage(t.addingTimeInterval(240), partition: autre)
        #expect(s.thread.sujets(b2).routeurs[1]?.id == qualifiee, "marge : evalue avant d'entrer dans l'historique")
        s.thread.recevoir(b2, a: t.addingTimeInterval(240))
        #expect(s.thread.historique.last?.actives == [])
        #expect(s.thread.sujets(b2).routeurs[1]?.id == qualifiee, "marge : deja dans l'historique")

        let relu = Surveillance(mode: .direct, dossier: dossier)
        await relu.thread.chargerHistorique()
        relu.thread.integrer(reunie)
        let b3 = Self.maillage(t.addingTimeInterval(360), partition: autre)
        #expect(relu.thread.sujets(b3).routeurs[1]?.id == qualifiee, "deuxieme releve de la marge, apres le redemarrage")
        relu.thread.recevoir(b3, a: t.addingTimeInterval(360))
        #expect(relu.thread.sujets(b3).routeurs[1]?.id == qualifiee)
        let b4 = Self.maillage(t.addingTimeInterval(480), partition: autre)
        #expect(relu.thread.sujets(b4).routeurs[1]?.id == "rloc:0400", "troisieme releve sans scission : fin")
        relu.thread.recevoir(b4, a: t.addingTimeInterval(480))
        #expect(relu.thread.sujets(b4).routeurs[1]?.id == "rloc:0400")
        let cles = ClesHistorique(releves: relu.thread.historique)
        #expect(relu.thread.historique.indices.map { cles.cle(releve: $0, routeur: 1) }
                == ["rloc:0400", qualifiee, qualifiee, qualifiee, "rloc:0400"])
    }
}
