import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Suivi du maillage : journal des parents et des routeurs Thread")
struct SuiviMaillageTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Enfant d'un maillage de test : RLOC16, ExtMac (nil : non identifie), source.
    struct Enfant {
        let rloc16: UInt16
        let ext: String?
        var source: SourceEnfant = .tableEnfants
    }

    /// Maillage de la partition 0000000A a `minutes` de t0 (valeurs inventees) : le chef 0 (routeur
    /// de bordure), et les routeurs 1 et 2 par defaut ; `muets` ; ExtMac des routeurs `routeursExt` ;
    /// `resolution` : date de la resolution dont viennent les enfants resolus, en minutes apres t0
    /// (nil : aucune resolution).
    static func maillage(_ minutes: Double, routeurs: [Int] = [0, 1, 2], bordures: Set<Int> = [0], muets: Set<Int> = [],
                         routeursExt: [Int: String] = [:], enfants: [Enfant], partition: String = "0000000A",
                         resolution: Double? = nil) -> Maillage {
        var c = ConstructionMaillage(date: t0.addingTimeInterval(minutes * 60), partition: partition)
        c.routeurs(Route64(sequence: 1, routes: routeurs.map { RouteRouteur(idRouteur: $0, qualiteSortante: 0, qualiteEntrante: 0, cout: 1) }),
                   chef: routeurs[0])
        for id in routeurs where bordures.contains(id) { c.marquer(id, bordure: true) }
        for id in muets { c.muet(id) }
        for (id, ext) in routeursExt { c.identite(ext, routeur: id) }
        for e in enfants {
            c.enfant(EnfantMaillage(rloc16: e.rloc16, extMac: e.ext, qualite: e.source == .resolution ? nil : 3, source: e.source))
        }
        var m = c.maillage()
        m.resolution = resolution.map { t0.addingTimeInterval($0 * 60) }
        return m
    }

    /// Noms des noeuds : « R<id> » pour un routeur, « N-<ExtMac> » pour un enfant.
    static func sujets(_ m: Maillage) -> SujetsMaillage {
        var s = SujetsMaillage()
        for r in m.routeurs { s.routeurs[r.id] = Sujet(id: "r\(r.id)", nom: "R\(r.id)") }
        for e in m.enfants { s.enfants[e.rloc16] = Sujet(id: e.extMac ?? "?", nom: "N-" + (e.extMac ?? "?")) }
        return s
    }

    /// Integre les maillages dans l'ordre ; les evenements de chacun.
    static func suivre(_ maillages: [Maillage]) -> [[Evenement]] {
        var suivi = SuiviMaillage()
        return maillages.map { suivi.integrer($0, sujets: sujets($0)) }
    }

    static let b1 = "E0000000000000B1"

    /// Comme l'app pour un enfant que le graphe ne rapproche d'aucun appareil : son id de sujet est
    /// « rloc:XXXX », donc il change avec son parent.
    static func sujetsRloc(_ m: Maillage) -> SujetsMaillage {
        var s = sujets(m)
        for e in m.enfants {
            s.enfants[e.rloc16] = Sujet(id: String(format: "rloc:%04X", e.rloc16), nom: "N-" + (e.extMac ?? "?"))
        }
        return s
    }

    /// Evenements regroupes pour l'affichage, d'un suivi dont les enfants ont un sujet « rloc: ».
    static func lignes(_ maillages: [Maillage]) -> [LigneJournal] {
        var suivi = SuiviMaillage()
        return Regroupement.lignes(maillages.flatMap { suivi.integrer($0, sujets: sujetsRloc($0)) })
    }

    /// L'ExtMac de l'enfant est dans les details des evenements qui parlent de lui : c'est elle
    /// qui le designe quand son id de sujet (« rloc:XXXX ») change avec son parent.
    @Test func extMacDansLesDetails() throws {
        let b2 = "E0000000000000B2"
        let ev = Self.suivre([
            Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1), Enfant(rloc16: 0x0402, ext: b2)]),
            Self.maillage(5, enfants: [Enfant(rloc16: 0x0801, ext: Self.b1)]),
            Self.maillage(10, enfants: [Enfant(rloc16: 0x0801, ext: Self.b1)]),
        ])
        #expect(ev[1].map(\.type) == [.parentChange])
        #expect(ev[1].first?.details["extMac"] == Self.b1)
        #expect(ev[2].map(\.type) == [.sansParent])
        #expect(ev[2].first?.details["extMac"] == b2)
    }

    /// Un enfant sans appareil (id de sujet « rloc: ») qui fait A → B → A → B dans l'heure : une
    /// seule ligne regroupee, malgre les deux ids de sujet.
    @Test func unEnfantQuiOscilleFaitUneLigne() {
        let sous = { (minutes: Double, rloc: UInt16) in
            Self.maillage(minutes, routeurs: [0, 1, 2], enfants: [Enfant(rloc16: rloc, ext: Self.b1)])
        }
        let lignes = Self.lignes([sous(0, 0x0401), sous(5, 0x0802), sous(10, 0x0401), sous(15, 0x0802)])
        #expect(lignes.count == 1)
        guard case .parents(let groupe)? = lignes.first else {
            Issue.record("les trois changements regroupes en une ligne")
            return
        }
        #expect(groupe.count == 3)
    }

    /// Deux enfants d'ExtMac differentes qui passent tour a tour par le meme RLOC16 (donc le meme
    /// id de sujet « rloc: ») ne sont pas regroupes : B1 change deux fois de parent (une ligne de
    /// deux), B2 une fois (sa ligne, a part, plus recente).
    @Test func deuxEnfantsSurLeMemeRloc() {
        let b2 = "E0000000000000B2"
        let routeurs = [0, 1, 2, 3]
        let lignes = Self.lignes([
            Self.maillage(0, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1), Enfant(rloc16: 0x0C01, ext: b2)]),
            Self.maillage(5, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0801, ext: Self.b1), Enfant(rloc16: 0x0C01, ext: b2)]),
            Self.maillage(10, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0C02, ext: Self.b1), Enfant(rloc16: 0x0C01, ext: b2)]),
            Self.maillage(15, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0C02, ext: Self.b1), Enfant(rloc16: 0x0801, ext: b2)]),
        ])
        #expect(lignes.map(\.evenements.count) == [1, 2])
        #expect(lignes[0].evenements.map { $0.details["extMac"] } == [b2])
        #expect(lignes[1].evenements.map { $0.details["extMac"] } == [Self.b1, Self.b1])
    }

    /// Le premier maillage est un point de depart ; le meme ensuite ne dit rien.
    @Test func pointDeDepart() {
        let m = Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)])
        #expect(Self.suivre([m, m]) == [[], []])
    }

    /// Un enfant identifie passe du routeur 1 au 2 : « a change de parent », date de la tournee.
    /// Une tournee identique ensuite ne redit rien (l'etat suit le nouveau parent) ; un nouveau
    /// changement (2 vers 3) est note depuis le dernier parent. Un enfant sans ExtMac n'est pas
    /// suivi : son RLOC16 change avec son parent, il n'est jamais « sans parent ».
    @Test func changementDeParent() throws {
        let routeurs = [0, 1, 2, 3]
        let sansExt = Enfant(rloc16: 0x0403, ext: nil)
        let ev = Self.suivre([
            Self.maillage(0, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1), sansExt]),
            Self.maillage(5, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0802, ext: Self.b1), Enfant(rloc16: 0x0804, ext: nil)]),
            Self.maillage(10, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0802, ext: Self.b1), Enfant(rloc16: 0x0804, ext: nil)]),
            Self.maillage(15, routeurs: routeurs, enfants: [Enfant(rloc16: 0x0C02, ext: Self.b1), Enfant(rloc16: 0x0804, ext: nil)]),
        ])
        #expect(ev[0].isEmpty)
        #expect(ev[1].count == 1)
        let e = try #require(ev[1].first)
        #expect(e.type == .parentChange && e.gravite == .info)
        #expect(e.sujet == Sujet(id: Self.b1, nom: "N-" + Self.b1))
        #expect(e.avant == "R1" && e.apres == "R2")
        #expect(e.date == Self.t0.addingTimeInterval(300))
        #expect(ev[2].isEmpty, "meme parent : l'etat est rafraichi, le changement n'est pas redit")
        #expect(ev[3].count == 1)
        let f = try #require(ev[3].first)
        #expect(f.type == .parentChange)
        #expect(f.avant == "R2" && f.apres == "R3")
        #expect(f.date == Self.t0.addingTimeInterval(900))
    }

    /// Absent sous un parent qui repond : « n'a plus de parent » a la seconde absence, une seule
    /// fois ; revu sous un autre parent : « a change de parent » depuis le dernier connu.
    @Test func sansParentApresDeuxAbsences() {
        let present = Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)])
        let absent = { (minutes: Double) in Self.maillage(minutes, enfants: []) }
        let ev = Self.suivre([present, absent(5), absent(10), absent(15),
                              Self.maillage(20, enfants: [Enfant(rloc16: 0x0802, ext: Self.b1)])])
        #expect(ev[1].isEmpty, "une absence : on attend")
        #expect(ev[2].map(\.type) == [.sansParent])
        #expect(ev[2].first?.avant == "R1")
        #expect(ev[2].first?.gravite == .attention)
        #expect(ev[3].isEmpty, "pas de seconde fois")
        #expect(ev[4].map(\.type) == [.parentChange])
        #expect(ev[4].first?.avant == "R1" && ev[4].first?.apres == "R2")
    }

    /// Revu entre deux absences : le compte repart de zero.
    @Test func absencesDeSuite() {
        let present = Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)])
        let ev = Self.suivre([present, Self.maillage(5, enfants: []), present, Self.maillage(15, enfants: [])])
        #expect(ev.allSatisfy { $0.isEmpty })
    }

    /// Enfant lu dans la table d'un routeur qui se tait ensuite : son absence ne dit rien (le
    /// routeur n'a pas ete interroge). Enfant resolu sous un routeur muet : absent, c'est qu'une
    /// nouvelle resolution ne l'a pas trouve ; il faut deux resolutions distinctes (ici aux minutes 5 et 10).
    @Test func absenceSousUnRouteurMuet() {
        let b2 = "E0000000000000B2"
        let ev = Self.suivre([
            Self.maillage(0, muets: [2], enfants: [Enfant(rloc16: 0x0401, ext: Self.b1),
                                                     Enfant(rloc16: 0x0805, ext: b2, source: .resolution)], resolution: 0),
            Self.maillage(5, muets: [1, 2], enfants: [], resolution: 5),
            Self.maillage(10, muets: [1, 2], enfants: [], resolution: 10),
        ])
        #expect(ev[1].isEmpty)
        #expect(ev[2].map(\.type) == [.sansParent])
        #expect(ev[2].first?.sujet?.id == b2)
    }

    /// Une resolution est reutilisee par les tournees jusqu'a la suivante : une seule observation,
    /// meme comptee a chaque tournee, n'est pas une absence de plus. Enfant resolu sous un routeur
    /// muet (2), present a la resolution de la minute 0, absent de celle de la minute 5 (reutilisee
    /// aux minutes 10 et 15) : une absence. Absent de celle de la minute 35 : « sans parent », une
    /// seule fois.
    @Test func uneResolutionNeCompteQuUneFois() {
        let b2 = "E0000000000000B2"
        let absent = { (minutes: Double, resolution: Double) in
            Self.maillage(minutes, muets: [2], enfants: [], resolution: resolution)
        }
        let ev = Self.suivre([
            Self.maillage(0, muets: [2], enfants: [Enfant(rloc16: 0x0805, ext: b2, source: .resolution)], resolution: 0),
            absent(5, 5), absent(10, 5), absent(15, 5),
            absent(35, 35), absent(40, 35),
        ])
        #expect(ev[1].isEmpty && ev[2].isEmpty && ev[3].isEmpty, "la meme resolution, vue trois fois")
        #expect(ev[4].map(\.type) == [.sansParent], "une seconde resolution ne le trouve pas")
        #expect(ev[4].first?.sujet?.id == b2 && ev[4].first?.avant == "R2")
        #expect(ev[5].isEmpty, "pas de seconde fois")
    }

    /// Sans resolution (nil) sous un parent muet : l'enfant resolu n'est pas retrouve, mais rien n'a
    /// ete observe : aucune absence. Seules deux resolutions distinctes (minutes 25 et 30) comptent.
    @Test func sansResolutionSousUnParentMuet() {
        let b2 = "E0000000000000B2"
        let sans = { (minutes: Double) in Self.maillage(minutes, muets: [2], enfants: [], resolution: nil) }
        let ev = Self.suivre([
            Self.maillage(0, muets: [2], enfants: [Enfant(rloc16: 0x0805, ext: b2, source: .resolution)], resolution: 0),
            sans(5), sans(10), sans(15), sans(20),
            Self.maillage(25, muets: [2], enfants: [], resolution: 25),
            Self.maillage(30, muets: [2], enfants: [], resolution: 30),
        ])
        #expect(ev[1...4].allSatisfy { $0.isEmpty }, "quatre tournees sans resolution : pas une absence")
        #expect(ev[5].isEmpty, "premiere resolution qui ne le trouve pas")
        #expect(ev[6].map(\.type) == [.sansParent], "seconde resolution : le compte n'avait pas avance avant")
    }

    /// « N'a plus de parent » nomme l'enfant et son dernier parent connu (R2, pas R1 d'avant son
    /// changement de parent), a la date de la seconde absence.
    @Test func sansParentNommeLeDernierParent() throws {
        let ev = Self.suivre([
            Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)]),
            Self.maillage(5, enfants: [Enfant(rloc16: 0x0802, ext: Self.b1)]),
            Self.maillage(10, enfants: []),
            Self.maillage(15, enfants: []),
        ])
        let e = try #require(ev[3].first)
        #expect(e.type == .sansParent)
        #expect(e.avant == "R2", "le dernier parent connu")
        #expect(e.sujet == Sujet(id: Self.b1, nom: "N-" + Self.b1))
        #expect(e.date == Self.t0.addingTimeInterval(900), "seconde absence")
    }

    /// Parent sorti de la liste des routeurs : son enfant est sans parent a la seconde tournee.
    @Test func parentDisparu() {
        let ev = Self.suivre([Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)]),
                              Self.maillage(5, routeurs: [0, 2], enfants: []),
                              Self.maillage(10, routeurs: [0, 2], enfants: [])])
        #expect(ev[1].map(\.type) == [.routeurThreadDisparu])
        #expect(ev[2].map(\.type) == [.sansParent])
    }

    /// Un routeur de bordure qui entre dans la liste ne dit rien ici (le journal des annonces le dit).
    @Test func routeurDeBordureApparu() {
        let ev = Self.suivre([Self.maillage(0, enfants: []),
                              Self.maillage(5, routeurs: [0, 1, 2, 4], bordures: [0, 4], enfants: [])])
        #expect(ev == [[], []])
    }

    /// Routeurs hors routeurs de bordure : entree (3) et sortie (2) de la liste, nommes par leur
    /// derniere tournee ; un routeur de bordure (0) qui sort ne dit rien ici (le journal des
    /// annonces le dit).
    @Test func routeursThread() {
        let ev = Self.suivre([Self.maillage(0, enfants: []),
                              Self.maillage(5, routeurs: [1, 3], bordures: [], enfants: [])])
        #expect(ev[1].map(\.type) == [.routeurThreadApparu, .routeurThreadDisparu])
        #expect(ev[1].map { $0.sujet?.nom } == ["R3", "R2"])
        #expect(ev[1].map(\.gravite) == [.info, .attention])
    }

    /// La sonde n'est jamais « sans parent » ; son changement de parent est note.
    @Test func sonde() {
        let sonde = { (minutes: Double, rloc: UInt16) in
            Self.maillage(minutes, enfants: [Enfant(rloc16: rloc, ext: "E0000000000000C1", source: .sonde)])
        }
        let ev = Self.suivre([sonde(0, 0x0401), Self.maillage(5, enfants: []), Self.maillage(10, enfants: []),
                              sonde(15, 0x0801)])
        #expect(ev[1].isEmpty && ev[2].isEmpty)
        #expect(ev[3].map(\.type) == [.parentChange])
    }

    /// Enfant devenu routeur : son ExtMac est celle d'un routeur de la liste ; il n'est pas « sans
    /// parent », le routeur apparait.
    @Test func enfantDevenuRouteur() {
        let ev = Self.suivre([Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)]),
                              Self.maillage(5, routeurs: [0, 1, 2, 3], routeursExt: [3: Self.b1], enfants: []),
                              Self.maillage(10, routeurs: [0, 1, 2, 3], routeursExt: [3: Self.b1], enfants: [])])
        #expect(ev[1].map(\.type) == [.routeurThreadApparu])
        #expect(ev[2].isEmpty)
    }

    /// Autre partition : les identifiants de routeur y sont redistribues ; nouveau point de depart.
    @Test func autrePartition() {
        let ev = Self.suivre([Self.maillage(0, enfants: [Enfant(rloc16: 0x0401, ext: Self.b1)]),
                              Self.maillage(5, routeurs: [5, 6], enfants: [Enfant(rloc16: 0x1801, ext: Self.b1)],
                                            partition: "0000000B")])
        #expect(ev[1].isEmpty)
    }

    /// Aucune notification par defaut : ces evenements relevent de « Autres changements ».
    @Test func autresChangements() {
        var a = Alertes()
        let ev = [TypeEvenement.parentChange, .sansParent, .routeurThreadApparu, .routeurThreadDisparu].map {
            Evenement(date: Self.t0, type: $0, sujet: Sujet(id: Self.b1, nom: "Prise"))
        }
        #expect(a.traiter(ev).map(\.categorie) == Array(repeating: .informations, count: 4))
        #expect(!CategorieAlerte.informations.parDefaut)
    }
}
