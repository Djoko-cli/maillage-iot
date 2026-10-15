import AppKit
import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI
import Testing
@testable import MaillageIoT

/// La demo combinee (`-demo`) : les deux demos ensemble, la demo de Zigbee recalee sur l'horloge de celle de Thread, et
/// chaque noeud lu a l'horloge de son modele. Les deux demos seules (`-demo-thread`, `-demo-zigbee`) restent telles quelles
/// (leurs references de rejeu : `ReferenceRejeuTests`, `ReferenceRejeuZigbeeTests`).
@MainActor
@Suite("Demo combinee")
struct DemoCombineeTests {
    static let heure = Date(timeIntervalSince1970: 1_790_000_000)

    static func combinee() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
        s.demarrer()
        return s
    }

    /// Sans recalage (la demo de Zigbee d'origine, 08/10 : 11 jours apres la panne de Thread), les deux modeles ont deux
    /// horloges. Chaque noeud se lit a celle de son modele : la fiche, la fenetre et l'alerte de Thread ne voient jamais celle
    /// de Zigbee (la plus tardive, que prend `Surveillance.maintenant`).
    @Test func horlogeDuModeleDuNoeud() throws {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee, demoZigbee: .seule)
        s.demarrer()
        #expect(s.maintenant(de: .thread, a: Self.heure) == ScenarioPanne.fin)
        #expect(s.maintenant(de: .zigbee, a: Self.heure) == MaillageDemoZigbee.fin)
        #expect(s.maintenant(de: .thread, a: Self.heure) == s.thread.maintenant(a: Self.heure))
        #expect(s.maintenant(de: .zigbee, a: Self.heure) == s.zigbee.maintenant(a: Self.heure))
        #expect(s.maintenant(a: Self.heure) == MaillageDemoZigbee.fin, "la coque prend le plus tard : pas pour un noeud")
        // Thread, a la sienne : son maillage est frais, le noeud verifie par la sonde ; a celle de Zigbee (le piege), perime.
        let sienne = s.maintenant(de: .thread, a: Self.heure)
        #expect(s.thread.fraicheurMaillage(a: sienne) == .frais)
        #expect(s.thread.fraicheurMaillage(a: s.maintenant) == .perime, "l'horloge de l'autre protocole : perime")
        let reseau = try #require(s.thread.reseau)
        #expect(s.thread.maillageAffiche(pour: reseau) != nil, "le maillage de Thread est rapproche du reseau, a son horloge")
        // L'alerte de Thread compte « dans l'heure » a l'horloge de Thread : sa panne y est encore.
        let graves = s.evenements.filter { $0.protocole == .thread && $0.gravite == .alerte }
        #expect(!graves.isEmpty && graves.allSatisfy { $0.date >= sienne.addingTimeInterval(-3600) }, "la panne est dans l'heure de Thread")
        #expect(s.alerte(de: .thread))
    }

    /// Dans la demo combinee, la demo de Zigbee est recalee : ses deux modeles ont la meme fin de demo (celle de la panne de
    /// Thread, 27/09 04:30 heure de la demo), et la combinee n'a plus un noeud vieux a cote de l'autre.
    @Test func zigbeeRecaleSurThread() throws {
        let s = Self.combinee()
        #expect(s.zigbee.demo.fin == ScenarioPanne.fin)
        #expect(s.maintenant(de: .zigbee, a: Self.heure) == ScenarioPanne.fin)
        #expect(s.maintenant(de: .thread, a: Self.heure) == s.maintenant(de: .zigbee, a: Self.heure))
        #expect(s.zigbee.fraicheurMaillage(a: s.maintenant(de: .zigbee, a: Self.heure)) == .frais)
        #expect(s.thread.fraicheurMaillage(a: s.maintenant(de: .thread, a: Self.heure)) == .frais)
        let pont = try #require(s.zigbee.nomsPont)
        #expect(pont.date == ScenarioPanne.fin.addingTimeInterval(-5 * 60))
        #expect(s.zigbee.maillage?.date == ScenarioPanne.fin)
        #expect(s.evenements.allSatisfy { $0.date <= ScenarioPanne.fin }, "aucun evenement apres la fin de la demo")
    }

    /// Le journal de la combinee est dans l'ordre du temps : les evenements de Zigbee, recales sur l'horloge de Thread, se
    /// melent a ceux de Thread. Celui d'une demo seule l'etait deja : le tri n'y change rien.
    @Test func journalChronologique() {
        let dates = Self.combinee().evenements.map(\.date)
        #expect(!dates.isEmpty && zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 })
        let protocoles = Set(Self.combinee().evenements.compactMap(\.protocole))
        #expect(protocoles == [.thread, .zigbee], "les evenements des deux demos")
        for demo in [DemoLancee.thread, .zigbee] {
            let seule = Surveillance(mode: .demo, dossier: nil, demo: demo)
            seule.demarrer()
            let dates = seule.evenements.map(\.date)
            #expect(!dates.isEmpty && zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 }, "la demo \(demo), seule : deja ordonnee")
        }
    }

    /// Les deux demos seules ne changent pas : celle de Zigbee a ses dates et ses noms d'origine, celle de Thread n'a pas de
    /// Zigbee ; les references de rejeu l'attestent a l'octet.
    @Test func lesDemosSeulesGardentLeursDates() {
        let zigbee = Surveillance(mode: .demo, dossier: nil, demo: .zigbee)
        zigbee.demarrer()
        #expect(zigbee.zigbee.demo == .seule && zigbee.zigbee.demo.fin == MaillageDemoZigbee.fin)
        #expect(zigbee.zigbee.nomsPont == NomsDemo.maisonPont && zigbee.zigbee.releveMaison == NomsDemo.releveMaison)
        #expect(zigbee.maintenant(de: .zigbee, a: Self.heure) == MaillageDemoZigbee.fin)
        let thread = Surveillance(mode: .demo, dossier: nil, demo: .thread)
        thread.demarrer()
        #expect(thread.maintenant(de: .thread, a: Self.heure) == ScenarioPanne.fin)
        #expect(thread.zigbee.maillage == nil && !thread.zigbee.rejoueLaDemo)
        #expect(Surveillance(mode: .demo, dossier: nil).thread.rejoueLaDemo, "le defaut : la demo de Thread, seule")
    }

    /// La demo combinee ne change que le calendrier et les homonymes : la demo de Zigbee recalee a les memes dates relatives, et
    /// la demo seule n'a aucun renommage.
    @Test func renommageDesHomonymes() {
        let rejouee = DemoLancee.combinee.zigbeeRejouee
        #expect(DemoLancee.zigbee.zigbeeRejouee == .seule && DemoLancee.thread.zigbeeRejouee == .seule)
        #expect(Set(rejouee.renommes.keys) == ["Ampoule entrée", "Interrupteur cuisine", "Lampe arcade", "Lampe chambre d'amis",
                                              "Prise salon", "Prise terrasse"])
        #expect(rejouee.renommes.values.allSatisfy { $0.hasSuffix(" (Hue)") })
        #expect(DemoZigbee.seule.maisonPont == NomsDemo.maisonPont, "la demo d'origine : ses noms")
        #expect(rejouee.maisonPont.accessoires.count == NomsDemo.maisonPont.accessoires.count)
        #expect(rejouee.maisonPont.date == ScenarioPanne.fin.addingTimeInterval(-5 * 60))
        #expect(rejouee.maillage.date == ScenarioPanne.fin && rejouee.maillageAvant.date == ScenarioPanne.fin.addingTimeInterval(-15 * 60))
        // Les appareils renommes sont les memes, a leur adresse longue.
        let d = Dictionary(uniqueKeysWithValues: rejouee.maisonPont.accessoires.map { ($0.ieee, $0.nom) })
        #expect(d[NomsDemo.Ieee.lampeArcade] == "Lampe arcade (Hue)" && d[NomsDemo.Ieee.pont] == "Pont Hue")
    }

    /// Les images de la demo combinee : des cas de chaque protocole, aux noeuds qui existent dans la scene combinee.
    @Test func capturesDeLaDemoCombinee() throws {
        let cas = CapturesPieces.casCombinee
        #expect(Set(cas.map(\.nom)).count == cas.count && cas.first?.nom == "01-2d")
        let s = Self.combinee()
        s.zigbee.noms.maison = s.zigbee.demo.maisonFusionnee
        let r = try #require(s.thread.reseau)
        let marges = (CGFloat(139), CGFloat(30))
        for c in cas {
            let (m, e) = CapturesPieces.preparer(c, surveillance: s, reseau: r, marges: marges)
            #expect(e.protocoles == [.thread, .zigbee], "\(c.nom)")
            if let id = m.selection ?? m.survol { #expect(e.graphe.noeuds.contains { $0.id == id }, "\(c.nom) : \(id.texte)") }
        }
    }
}

/// La legende et la fenetre de la demo combinee : la premiere scene des deux protocoles, avec la ligne « ● Thread ⬢ Zigbee » et
/// les entrees des deux. Les constantes de hauteur de la fenetre (`FenetrePieces.sceneMinimale`, les fenetres de
/// `FenetrePiecesTests`) ont ete mesurees sur les demos d'un protocole seul ; ici, sur celle-ci.
@MainActor
@Suite("Demo combinee : legende et fenetre")
struct DemoCombineeLegendeTests {
    /// Une fenetre assez haute pour que la legende ouverte tienne au-dessus de la fiche de n'importe quel noeud de la demo
    /// combinee : sa legende fait 345 pt (240 pour Thread seul, 257 pour Zigbee seul : les entrees des deux protocoles et la ligne
    /// des protocoles, 21 pt), la scene y garde 231 pt au moins sous la fiche la plus haute (de 231 a 329 pt). A 1100 x 880, la
    /// fenetre assez haute des demos seules, la legende se replie sous 51 des 54 fiches (de 151 a 249 pt) ; a 1100 x 760, la
    /// fenetre par defaut, sous toutes (de 31 a 129 pt : la legende seule y laisse 250 pt a la scene).
    static let hauteAssez = CGSize(width: 1100, height: 960)

    /// La rangee du bas porte la ligne des protocoles : sa hauteur est celle de la legende avec elle, 21 pt de plus que sans.
    /// La marge du bas suit la rangee mesuree, comme dans les demos d'un protocole seul (`LegendePiecesTests.margeDuBas`).
    @Test func margeDuBasDeuxProtocoles() throws {
        let s = DemoCombineeTests.combinee()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        func hauteur(_ v: some View) -> CGFloat {
            NSHostingView(rootView: v.environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize.height
        }
        let moteur = MoteurPieces()
        let lecture = LegendePieces.Lecture(e, ailleurs: false, mode: moteur.liens, voisins: moteur.voisins)
        #expect(LegendePieces.montreLesProtocoles(lecture), "les deux protocoles : la ligne est montree")
        let rubriques = LegendePieces.rubriques(lecture)
        let h = hauteur(LigneDuBas(moteur: moteur, entree: e, legendeForcee: false))
        let avec = hauteur(LegendePieces(rubriques: rubriques, ligneProtocoles: true, repliee: .constant(false)))
        let sans = hauteur(LegendePieces(rubriques: rubriques, ligneProtocoles: false, repliee: .constant(false)))
        #expect(h == avec, "la rangee du bas est la legende, avec sa ligne des protocoles")
        #expect(abs((avec - sans) - (LegendePieces.hauteurLigne + LegendePieces.ecartLigneProtocoles)) < 0.5)
        #expect(h > 250, "la legende de la demo combinee, ouverte : \(h)")
        #expect(FenetrePieces.margeBas(pile: h) == FenetrePieces.bord + ceil(h) + FenetrePieces.espacement)
        for repliee in [false, true] {
            let rangee = hauteur(LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee))
            let pile = hauteur(VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee)
                FicheNoeud(id: IdNoeud(.thread, "Apple TV 4K"), entree: e, instant: Date(), aRenommer: .constant(nil)) {}
            }.frame(width: 1100 - 2 * FenetrePieces.bord))
            #expect(pile > rangee + FenetrePieces.espacement + 80, "repliee : \(repliee) ; la fiche sous la rangee (\(pile) pt)")
        }
    }

    /// Dans la demo combinee, la legende ouverte (345 pt) laisse moins de place a la scene sous une fiche que celle d'un
    /// protocole seul : la fenetre par defaut et celle des demos seules (1100 x 880) la replient sous la fiche de l'Apple TV 4K
    /// ; une fenetre de 960 pt de haut la garde ouverte sous toutes les fiches (la scene y garde 231 pt au moins).
    @Test(.timeLimit(.minutes(3))) func repliDeLaLegendeDeuxProtocoles() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let s = DemoCombineeTests.combinee()
        func ouverture(_ taille: CGSize, ids: [IdNoeud]?) async throws -> [(IdNoeud, legende: CGFloat, scene: CGFloat)] {
            let (fenetre, moteur) = try FenetrePiecesTests.fenetre(s, taille: taille, preferences: p)
            defer { FenetrePiecesTests.fermer(fenetre) }
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil && moteur.pret }
            try await Task.sleep(for: .milliseconds(300))
            let ouverte = try #require(moteur.cadresInterface["legende"]).height
            #expect(ouverte == 345, "\(taille) : la legende ouverte, sans fiche")
            let tous = (moteur.entree?.graphe.noeuds.map(\.id) ?? []).sorted()
            #expect(tous.count == 54, "les 54 noeuds de la demo combinee")
            var mesures: [(IdNoeud, legende: CGFloat, scene: CGFloat)] = []
            for id in ids ?? tous {
                moteur.selection = id
                try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] != nil }
                try await Task.sleep(for: .milliseconds(450))
                let legende = try #require(moteur.cadresInterface["legende"], "\(id.texte) : la legende reste, repliee ou non").height
                let fiche = try #require(moteur.cadresInterface["fiche"]).height
                // La scene que la legende ouverte laisserait sous la fiche (la regle du repli, `repliDePlace`).
                let scene = taille.height - moteur.marges.haut
                    - FenetrePieces.margeBas(pile: ouverte + FenetrePieces.espacement + fiche)
                mesures.append((id, legende, scene))
                moteur.selection = nil
                try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] == nil }
            }
            return mesures
        }
        let appleTV = [IdNoeud(.thread, "Apple TV 4K")]
        let pont = [IdNoeud(.zigbee, NomsDemo.Ieee.pont)]
        for taille in [CGSize(width: 1100, height: 760), CGSize(width: 1100, height: 880)] {
            for m in try await ouverture(taille, ids: appleTV + pont) {
                #expect(m.scene < FenetrePieces.sceneMinimale && m.legende < 40, "\(taille), \(m.0.texte) : repliee (\(m.legende) pt), la scene n'aurait que \(m.scene) pt")
            }
        }
        let hauts = try await ouverture(Self.hauteAssez, ids: nil)
        #expect(hauts.count == 54)
        #expect(hauts.allSatisfy { $0.scene >= FenetrePieces.sceneMinimale && $0.legende == 345 },
                "960 pt : la legende reste ouverte sous les 54 fiches (scene de \(hauts.map(\.scene).min() ?? 0) pt au moins)")
    }
}
