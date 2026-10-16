import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Etape 3b, tache 7 : le journal a ses propres interrupteurs « Thread » / « Zigbee » (`journal.thread`, `journal.zigbee`,
/// independants de ceux de la vue), chaque ligne porte la marque de son protocole, et les familles propres a un protocole
/// filtre sont grisees. Une ligne sans protocole est de Thread ; les lignes regroupees sont par protocole, elles se filtrent
/// avec lui.
@MainActor
@Suite("Journal : filtres et marques par protocole")
struct JournalProtocolesTests {
    static let tous: Set<Protocole> = [.thread, .zigbee]

    /// Un journal des deux protocoles : un routeur disparu de chacun, un prefixe de Thread,
    /// et deux pertes de Zigbee rapprochees, que le regroupement met en une seule ligne.
    static func lignes() -> [LigneJournal] {
        let s = Surveillance(mode: .direct, dossier: nil)
        func ev(_ type: TypeEvenement, _ nom: String, _ minutes: Double, _ protocole: Protocole?) -> Evenement {
            JournalDeuxProtocolesTests.evenement(type, nom, minutes: minutes, protocole: protocole)
        }
        s.ajouter([ev(.routeurDisparu, "Routeur T", 1, nil), ev(.prefixeNouveau, "Prefixe T", 2, nil)], de: .thread)
        s.ajouter([ev(.routeurDisparu, "Routeur Z", 3, nil), ev(.appareilDisparu, "Lampe Z1", 4, nil),
                   ev(.appareilDisparu, "Lampe Z2", 5, nil)], de: .zigbee)
        return s.lignesJournal
    }

    static func protocoles(_ lignes: [LigneJournal]) -> [Protocole] { lignes.map { TexteEvenement.protocole($0) } }

    // MARK: Filtre

    /// Un evenement de Zigbee se cache quand l'interrupteur Zigbee du journal est eteint et revient quand il est allume ; Thread de
    /// meme. Les lignes regroupees suivent leur protocole.
    @Test func filtreDuJournalParProtocole() {
        let lignes = Self.lignes()
        #expect(lignes.count == 4, "deux de Thread, une de Zigbee, les deux pertes de Zigbee en une")
        #expect(Self.protocoles(FiltreJournal().appliquer(lignes)).count == 4, "les deux protocoles par defaut")
        #expect(FiltreJournal().protocoles == Self.tous)
        var f = FiltreJournal(protocoles: [.thread])
        #expect(Set(Self.protocoles(f.appliquer(lignes))) == [.thread], "Zigbee eteint : plus une ligne de Zigbee")
        #expect(f.appliquer(lignes).count == 2)
        f.protocoles = Self.tous
        #expect(f.appliquer(lignes).count == 4, "Zigbee rallume : ses lignes reviennent")
        f.protocoles = [.zigbee]
        let zigbee = f.appliquer(lignes)
        #expect(Set(Self.protocoles(zigbee)) == [.zigbee] && zigbee.count == 2, "Thread eteint : plus une ligne de Thread")
        #expect(zigbee.contains { if case .pertes = $0 { true } else { false } }, "le groupe de pertes suit son protocole")
        f.protocoles = []
        #expect(f.appliquer(lignes).isEmpty, "les deux eteints : rien")
        // Le filtre de protocole se combine aux autres.
        #expect(FiltreJournal(famille: .routeurs, protocoles: [.zigbee]).appliquer(lignes).count == 1)
        #expect(FiltreJournal(famille: .prefixes, protocoles: [.zigbee]).appliquer(lignes).isEmpty)
        #expect(FiltreJournal(famille: .prefixes, protocoles: [.thread]).appliquer(lignes).count == 1)
        #expect(FiltreJournal(recherche: "routeur z", protocoles: [.thread]).appliquer(lignes).isEmpty)
        #expect(FiltreJournal(recherche: "routeur z", protocoles: [.zigbee]).appliquer(lignes).count == 1)
    }

    /// Un evenement sans protocole est de Thread : il se cache avec Thread, pas avec Zigbee.
    @Test func sansProtocoleEstDeThread() {
        let e = JournalDeuxProtocolesTests.evenement(.routeurDisparu, "Routeur 1")
        #expect(e.protocole == nil)
        let ligne = LigneJournal.evenement(e)
        #expect(FiltreJournal(protocoles: [.thread]).appliquer([ligne]).count == 1)
        #expect(FiltreJournal(protocoles: [.zigbee]).appliquer([ligne]).isEmpty)
    }

    // MARK: Marque

    /// La marque d'une ligne : ● pour Thread, ⬢ pour Zigbee, le signe de la ligne des protocoles de la barre ; une ligne sans
    /// protocole, celle de Thread ; une ligne regroupee, celle de son protocole.
    @Test func marqueDeLigne() {
        #expect(MarqueProtocole.glyphe(.thread) == "●")
        #expect(MarqueProtocole.glyphe(.zigbee) == "⬢")
        let e = JournalDeuxProtocolesTests.evenement(.routeurDisparu, "Routeur 1")
        #expect(MarqueProtocole.protocole(de: .evenement(e)) == .thread, "sans protocole : Thread")
        #expect(MarqueProtocole.glyphe(de: .evenement(e)) == "●")
        var z = e
        z.protocole = .zigbee
        #expect(MarqueProtocole.glyphe(de: .evenement(z)) == "⬢")
        var t = e
        t.protocole = .thread
        #expect(MarqueProtocole.glyphe(de: .evenement(t)) == "●")
        let pertes = Self.lignes().first { if case .pertes = $0 { true } else { false } }
        #expect(pertes.map { MarqueProtocole.glyphe(de: $0) } == "⬢", "un groupe de Zigbee porte la marque de Zigbee")
        for p in Protocole.allCases {
            #expect(MarqueProtocole.signe(p) == LegendePieces.signeProtocole(p), "le signe des interrupteurs de la barre")
            #expect(!MarqueProtocole.nom(p).isEmpty)
        }
        #expect(MarqueProtocole.glyphe(.thread) != MarqueProtocole.glyphe(.zigbee))
    }

    // MARK: Preferences

    /// Les preferences du journal : vraies par defaut, gardees quand on les change, relues a la reouverture ; les cles sont
    /// `journal.thread` et `journal.zigbee`, et celles de la vue (`vue.*`) n'y changent rien, ni l'inverse.
    @Test func preferenceGardee() throws {
        let nom = "journal-protocoles-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: nom))
        defer { d.removePersistentDomain(forName: nom) }
        #expect(InterrupteursJournal.cle(.thread) == "journal.thread" && InterrupteursJournal.cle(.zigbee) == "journal.zigbee")
        #expect(InterrupteursJournal.preferes(dans: d) == Self.tous, "tout est montre sans preference")
        d.set(false, forKey: "journal.zigbee")
        #expect(InterrupteursJournal.preferes(dans: d) == [.thread])
        // « Reouverture » : une autre lecture des memes preferences.
        #expect(InterrupteursJournal.preferes(dans: UserDefaults(suiteName: nom)!) == [.thread])
        d.set(false, forKey: "journal.thread")
        d.set(true, forKey: "journal.zigbee")
        #expect(InterrupteursJournal.preferes(dans: d) == [.zigbee])
        d.removeObject(forKey: "journal.thread")
        #expect(InterrupteursJournal.preferes(dans: d) == Self.tous)
        // Independance : masquer Zigbee dans la vue ne le masque pas dans le journal, et reciproquement.
        d.set(false, forKey: "vue.zigbee")
        d.set(false, forKey: "vue.thread")
        #expect(InterrupteursJournal.preferes(dans: d) == Self.tous)
        #expect(InterrupteursVue.preferes(dans: d) == [])
        d.set(false, forKey: "journal.thread")
        d.set(true, forKey: "vue.thread")
        #expect(InterrupteursVue.preferes(dans: d) == [.thread], "le journal ne touche pas la vue")
        #expect(InterrupteursJournal.preferes(dans: d) == [.zigbee])
    }

    // MARK: Familles grisees

    /// Les familles propres a un protocole (« Réseau », « Préfixes » : Thread) sont grisees quand ce protocole est filtre ;
    /// les communes ne le sont que si les deux le sont.
    @Test func famillesGriseesQuandLeProtocoleEstFiltre() {
        #expect(FamilleEvenement.reseau.protocoles == [.thread])
        #expect(FamilleEvenement.prefixes.protocoles == [.thread])
        for f in [FamilleEvenement.toutes, .surveillance, .routeurs, .appareils, .maillage] {
            #expect(f.protocoles == Self.tous, "\(f)")
        }
        for f in FamilleEvenement.allCases {
            #expect(!f.grisee(montres: Self.tous), "\(f) : rien n'est filtre")
            #expect(f.grisee(montres: []), "\(f) : tout est filtre")
        }
        #expect(FamilleEvenement.reseau.grisee(montres: [.zigbee]) && FamilleEvenement.prefixes.grisee(montres: [.zigbee]))
        #expect(!FamilleEvenement.reseau.grisee(montres: [.thread]))
        for f in [FamilleEvenement.toutes, .surveillance, .routeurs, .appareils, .maillage] {
            #expect(!f.grisee(montres: [.zigbee]) && !f.grisee(montres: [.thread]), "\(f) : commune")
        }
        // Les types de Zigbee ne sont dans aucune famille de Thread seule.
        for t in TypeEvenement.zigbee { #expect(!FamilleEvenement.reseau.contient(t) || FamilleEvenement.reseau.protocoles.contains(.zigbee)) }
    }

    /// Quand le filtre de protocole grise la famille choisie (« Préfixes », propre a Thread, Thread filtre), la famille revient a
    /// « Tous » : sans cela la liste restait vide (« Aucun evenement ») alors que le journal a des evenements (relecture de la
    /// tache 7). Une famille non grisee, ou « Tous », ne bouge pas ; les autres reglages du filtre non plus.
    @Test func familleGriseeRevientAToutes() {
        let lignes = Self.lignes()
        var f = FiltreJournal(famille: .prefixes, graviteMinimale: .attention, recherche: "x")
        f.rattraper(montres: [.zigbee])
        #expect(f.famille == .toutes, "Thread filtre : Prefixes revient a Tous")
        #expect(f.graviteMinimale == .attention && f.recherche == "x", "le reste du filtre est garde")
        var g = FiltreJournal(famille: .prefixes)
        g.rattraper(montres: Self.tous)
        #expect(g.famille == .prefixes, "Thread montre : la famille reste")
        var h = FiltreJournal(famille: .routeurs)
        h.rattraper(montres: [.zigbee])
        #expect(h.famille == .routeurs, "famille commune : elle reste")
        // La liste n'est plus vide apres le rattrapage.
        var vide = FiltreJournal(famille: .reseau, protocoles: [.zigbee])
        #expect(vide.appliquer(lignes).isEmpty, "avant : liste vide alors que le journal a des evenements")
        vide.rattraper(montres: [.zigbee])
        #expect(!vide.appliquer(lignes).isEmpty && !lignes.isEmpty)
    }
}
