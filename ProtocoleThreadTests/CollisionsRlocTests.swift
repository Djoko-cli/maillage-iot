import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Cles "rloc:" qualifiees en cas de collision (phase 8, decisions de Djoko du 20/10) : une collision n'existe que
/// pendant une scission, entre partitions actives en meme temps (celles que Bonjour annonce ensemble pour le reseau de la
/// sonde, gardees dans le releve). Un RLOC16 qu'ont deux de ces partitions est qualifie "rloc:<partition>:XXXX" pour les
/// partitions qui ne gardent pas la cle simple : la tenante, gardee toute la scission ; parmi les partitions qui avaient
/// deja l'identifiant, la partition du releve precedent, puis la plus grande, puis le plus petit identifiant. Seuls
/// comptent les releves de la scission en cours ; une partition qui n'est plus active ne cree jamais de collision.
/// Valeurs inventees.
@Suite("Cles rloc qualifiees en cas de collision")
struct CollisionsRlocTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_006_400)
    static let a = "0000000A"
    static let b = "0000000B"
    static let c = "0000000C"
    static let jour: TimeInterval = 24 * 3600

    /// Releve a `jours` de t0 de la partition `p` : les routeurs donnes, sans ExtMac sauf `ext` ; `actives` : les
    /// partitions que Bonjour annoncait ensemble (vide : reseau non scinde).
    static func releve(jours: Double, _ p: String, _ routeurs: [Int], ext: [Int: String] = [:],
                       liens: [(Int, Int)] = [], actives: [String] = []) -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(jours * jour), partition: p,
                       routeurs: routeurs.sorted().map { .init(id: $0, extMac: ext[$0]) },
                       liens: liens.map { LienRadio(a: $0.0, b: $0.1, qualiteAB: 3, qualiteBA: 2) }, enfants: [], signaux: [],
                       parentSonde: nil, actives: actives)
    }

    /// Maillage de la partition `p` a `jours` de t0 : les routeurs donnes (le premier est chef), sans ExtMac, et un
    /// enfant non identifie sous chacun.
    static func maillage(jours: Double, _ p: String, _ routeurs: [Int]) -> Maillage {
        var c = ConstructionMaillage(date: t0.addingTimeInterval(jours * jour), partition: p)
        c.routeurs(Route64(sequence: 1, routes: routeurs.map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: routeurs[0])
        for id in routeurs { c.enfant(EnfantMaillage(rloc16: UInt16(id) << 10 | 2, qualite: 3, source: .tableEnfants)) }
        if routeurs.count > 1 { c.lien(routeurs[0], routeurs[1], sortante: 3, entrante: 3) }
        return c.maillage()
    }

    /// Les cles du routeur `id` a chaque releve de la liste.
    static func cles(_ releves: [ReleveMaillage], routeur id: Int = 1) -> [String] {
        let cles = ClesHistorique(releves: releves)
        return releves.indices.map { cles.cle(releve: $0, routeur: id) }
    }

    /// La seule fabrique : la cle simple, ou qualifiee par la partition telle que l'app l'affiche ; un enfant suit son
    /// parent (l'identifiant de routeur de son RLOC16).
    @Test func fabrique() {
        #expect(CleRloc.cle(0x0400, partition: Self.b, collisions: []) == "rloc:0400")
        #expect(CleRloc.cle(0x0400, partition: Self.b, collisions: [2]) == "rloc:0400", "collision d'un autre identifiant")
        #expect(CleRloc.cle(0x0400, partition: Self.b, collisions: [1]) == "rloc:0000000B:0400")
        #expect(CleRloc.cle(0x0402, partition: Self.b, collisions: [1]) == "rloc:0000000B:0402", "enfant du routeur 1")
        #expect(CleRloc.cle(0xF800, partition: Self.b, collisions: [62]) == "rloc:0000000B:F800")
        #expect(IdNoeud(texte: "thread:rloc:0000000B:0400") == idt("rloc:0000000B:0400"), "coupee au premier « : »")
    }

    /// Sans scission, aucune collision, meme sur 60 jours et meme quand la sonde passe d'une partition a l'autre (jamais
    /// annoncees ensemble) : les cles d'avant la phase 8.
    @Test func sansScission() {
        let seule = (0..<60).map { Self.releve(jours: Double($0), Self.a, [0, 1, 5]) }
        #expect(seule.indices.allSatisfy { CollisionsRloc(releves: seule).collisions(releve: $0).isEmpty })
        #expect(Self.cles(seule) == Array(repeating: "rloc:0400", count: 60))
        #expect(Self.cles(seule, routeur: 5).allSatisfy { $0 == "rloc:1400" })
        let alternees = (0..<6).map { Self.releve(jours: Double($0), $0 % 2 == 0 ? Self.a : Self.b, [0, 1, 2]) }
        #expect(Self.cles(alternees) == Array(repeating: "rloc:0400", count: 6), "jamais actives ensemble")
    }

    /// Un simple changement d'identifiant de partition (memes routeurs, l'ancienne partition n'est plus annoncee) :
    /// les cles simples restent, dans l'historique comme pour le maillage recu, et rien n'est qualifie ensuite.
    @Test func changementDIdentifiantDePartition() {
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2]), Self.releve(jours: 1, Self.a, [0, 1, 2]),
                       Self.releve(jours: 1.1, Self.b, [0, 1, 2]), Self.releve(jours: 2, Self.b, [0, 1, 2]),
                       Self.releve(jours: 40, Self.b, [0, 1, 2])]
        #expect(Self.cles(releves) == Array(repeating: "rloc:0400", count: 5))
        #expect(Self.cles(releves, routeur: 2) == Array(repeating: "rloc:0800", count: 5))
        let collisions = CollisionsRloc(releves: releves)
        #expect(releves.indices.allSatisfy { collisions.collisions(releve: $0).isEmpty })
        let m = Self.maillage(jours: 41, Self.b, [0, 1, 2])
        #expect(collisions.collisions(apres: m, actives: []).isEmpty)
        #expect(collisions.collisions(apres: m, actives: [Self.b]).isEmpty, "Bonjour n'annonce que la nouvelle")
        #expect(collisions.collisions(apres: m, actives: [Self.a, Self.c]).isEmpty,
                "une scission ou la partition de la sonde n'est pas annoncee : pas la sienne")
    }

    /// Deux partitions actives ensemble avec le meme RLOC16 : deux noeuds. La partition du releve precedent garde la
    /// cle simple, l'autre est qualifiee ; un identifiant qu'une seule partition a reste simple. Tant que la sonde n'a
    /// jamais vu l'autre partition, ses identifiants sont inconnus : pas de collision.
    @Test func deuxPartitionsActives() throws {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1, 5]), Self.releve(jours: 0.01, Self.a, [1, 5], actives: actives),
                       Self.releve(jours: 0.02, Self.b, [0, 1, 2, 3], actives: actives)]
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0400", "rloc:0000000B:0400"])
        #expect(Self.cles(releves, routeur: 2) == ["rloc:0800", "rloc:0800", "rloc:0800"], "seule B a le 2")
        #expect(Self.cles(releves, routeur: 5) == ["rloc:1400", "rloc:1400", "rloc:1400"], "seule A a le 5")
        let collisions = CollisionsRloc(releves: releves)
        #expect(collisions.collisions(releve: 1).isEmpty && collisions.collisions(releve: 2) == [1])
        // Dans la scene : le routeur 1 de A et celui de B sont deux noeuds.
        let i = RapprochementTests.instantane(ailleurs: [])
        let r = try #require(i.reseaux.first)
        let mA = Self.maillage(jours: 0.01, Self.a, [1, 5]), mB = Self.maillage(jours: 0.02, Self.b, [0, 1, 2, 3])
        let avant = CollisionsRloc(releves: Array(releves.prefix(2)))
        let nA = MaillageAffiche(maillage: mA, reseau: r, appareils: i.appareils,
                                 collisions: CollisionsRloc(releves: Array(releves.prefix(1))).collisions(apres: mA, actives: actives))
        let nB = MaillageAffiche(maillage: mB, reseau: r, appareils: i.appareils,
                                 collisions: avant.collisions(apres: mB, actives: actives))
        #expect(nA.routeurs[1]?.id == "rloc:0400" && nB.routeurs[1]?.id == "rloc:0000000B:0400")
        #expect(nB.enfants[0x0402]?.id == "rloc:0000000B:0402" && nB.routeurs[2]?.id == "rloc:0800")
    }

    /// Departage quand plusieurs partitions qui avaient deja l'identifiant le recoivent ensemble (le jeu des partitions
    /// actives change pendant la scission) et que la partition du releve precedent ne l'a pas : la plus grande (nombre
    /// de routeurs de son dernier releve de la scission), puis le plus petit identifiant de partition.
    @Test func departageTaillePuisIdentifiant() {
        let (ac, ab, abc) = ([Self.a, Self.c], [Self.a, Self.b], [Self.a, Self.b, Self.c])
        // C a ete vue d'abord ; B est plus grande : B garde la cle simple, C est qualifiee.
        let taille = [Self.releve(jours: 0, Self.c, [1, 2], actives: ac), Self.releve(jours: 0.1, Self.b, [1, 2, 7], actives: ab),
                      Self.releve(jours: 0.2, Self.a, [5], actives: ab), Self.releve(jours: 0.3, Self.a, [5], actives: abc),
                      Self.releve(jours: 0.4, Self.c, [1, 2], actives: abc),
                      Self.releve(jours: 0.5, Self.b, [1, 2, 7], actives: abc)]
        #expect(Self.cles(taille) == ["rloc:0400", "rloc:0400", "rloc:0400", "rloc:0400", "rloc:0000000C:0400", "rloc:0400"])
        // A taille egale, le plus petit identifiant : B.
        let egale = [Self.releve(jours: 0, Self.c, [1, 2], actives: ac), Self.releve(jours: 0.1, Self.b, [1, 2], actives: ab),
                     Self.releve(jours: 0.2, Self.a, [5], actives: ab), Self.releve(jours: 0.3, Self.a, [5], actives: abc),
                     Self.releve(jours: 0.4, Self.c, [1, 2], actives: abc)]
        #expect(Self.cles(egale).last == "rloc:0000000C:0400")
        // La partition du releve precedent, qui l'avait deja, l'emporte sur la taille : C garde la cle.
        let precedent = [Self.releve(jours: 0, Self.b, [1, 2, 7], actives: ab), Self.releve(jours: 0.1, Self.c, [1, 2], actives: ac),
                         Self.releve(jours: 0.2, Self.c, [1, 2], actives: abc),
                         Self.releve(jours: 0.3, Self.b, [1, 2, 7], actives: abc)]
        #expect(Self.cles(precedent) == ["rloc:0400", "rloc:0400", "rloc:0400", "rloc:0000000B:0400"])
    }

    /// Collision stable sur trois releves de chaque partition, en alternance pendant la scission : les memes cles a
    /// chaque fois, sans osciller (la plus grande, B, ne prend pas la cle tant que la tenante, A, est active).
    @Test func collisionStable() {
        let actives = [Self.a, Self.b]
        let releves = (0..<6).map { n in
            n % 2 == 0 ? Self.releve(jours: Double(n) / 10, Self.a, [1], actives: actives)
                : Self.releve(jours: Double(n) / 10, Self.b, [0, 1, 2, 3], actives: actives)
        }
        let avant = [Self.releve(jours: -1, Self.b, [0, 1, 2, 3]), Self.releve(jours: -0.5, Self.a, [1])]
        #expect(Array(Self.cles(avant + releves).dropFirst(2))
                == ["rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0000000B:0400"])
    }

    /// Les collisions de chaque releve de la liste.
    static func collisions(_ releves: [ReleveMaillage]) -> [Set<Int>] {
        let c = CollisionsRloc(releves: releves)
        return releves.indices.map { c.collisions(releve: $0) }
    }

    /// Relecture finale, Critique 1 : un routeur de la partition qualifiee (celle de la sonde) absent d'un seul releve
    /// pendant la scission. La tenante (A) est gardee toute la scission : au retour du routeur 1 de B, sa cle reste
    /// qualifiee, et celle du routeur 1 de A reste simple.
    @Test func routeurAbsentDUnReleve() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2, 3], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [0, 1], actives: actives),
                       Self.releve(jours: 0.2, Self.b, [0], actives: actives),
                       Self.releve(jours: 0.3, Self.b, [0, 1], actives: actives),
                       Self.releve(jours: 0.4, Self.a, [0, 1, 2, 3], actives: actives)]
        #expect(Self.collisions(releves) == [[], [0, 1], [0], [0, 1], []])
        let cles = Self.cles(releves)
        #expect(cles[3] == "rloc:0000000B:0400" && cles[4] == "rloc:0400")
    }

    /// Relecture finale, Critique 1 : la tenante n'est pas oubliee quand son propre releve n'a plus l'identifiant (un
    /// routeur de A qui redemarre) ; B, seule a l'avoir a ce moment, reste qualifiee : ses courbes ne rejoignent jamais
    /// celles du routeur de A.
    @Test func tenanteGardeeToutLaScission() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [1, 5], actives: actives),
                       Self.releve(jours: 0.2, Self.a, [0, 2], actives: actives),
                       Self.releve(jours: 0.3, Self.b, [1, 5], actives: actives),
                       Self.releve(jours: 0.4, Self.a, [0, 1, 2], actives: actives)]
        #expect(Self.collisions(releves) == [[], [1], [], [1], []])
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0000000B:0400", "rloc:0400"])
    }

    /// Relecture finale, Critique 1 : un nouveau routeur de la partition de la sonde qui prend un identifiant qu'une
    /// autre partition active a deja ; le nouveau venu ne passe jamais devant elle, meme plus grand.
    @Test func nouveauVenuSurUnIdentifiantTenu() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2, 3], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [0, 1], actives: actives),
                       Self.releve(jours: 0.2, Self.b, [0, 1, 2], actives: actives)]
        #expect(Self.collisions(releves) == [[], [0, 1], [0, 1, 2]])
        #expect(Self.cles(releves, routeur: 2) == ["rloc:0800", "rloc:0800", "rloc:0000000B:0800"])
        let plusGrande = [Self.releve(jours: 0, Self.a, [2], actives: actives),
                          Self.releve(jours: 0.1, Self.b, [0, 1], actives: actives),
                          Self.releve(jours: 0.2, Self.b, [0, 1, 2, 3, 4], actives: actives),
                          Self.releve(jours: 0.3, Self.a, [2], actives: actives)]
        #expect(Self.collisions(plusGrande) == [[], [], [2], []])
    }

    /// Relecture finale, Important 1 (decision de Djoko : une collision n'existe qu'entre partitions actives en meme
    /// temps) : la moitie de la sonde forme une nouvelle partition et garde ses identifiants ; le releve d'avant la
    /// scission (l'ancienne partition) ne compte pas : aucune qualification, sans vraie collision. Une vraie collision
    /// pendant la scission (l'autre moitie redistribue le 3, la sonde y passe) est qualifiee, et la tenante reste.
    @Test func moitieRenommeeSansCollision() {
        let actives = [Self.a, Self.b]
        let renommee = [Self.releve(jours: 0, Self.a, [0, 1, 2, 3, 4, 5]),
                        Self.releve(jours: 0.1, Self.b, [3, 4, 5], actives: actives),
                        Self.releve(jours: 0.2, Self.b, [3, 4, 5], actives: actives),
                        Self.releve(jours: 1, Self.b, [3, 4, 5], actives: actives)]
        #expect(Self.collisions(renommee) == [[], [], [], []])
        #expect(Self.cles(renommee, routeur: 3) == Array(repeating: "rloc:0C00", count: 4))
        let vraie = renommee + [Self.releve(jours: 1.1, Self.a, [0, 1, 2, 3], actives: actives),
                                Self.releve(jours: 1.2, Self.b, [3, 4, 5], actives: actives),
                                Self.releve(jours: 1.3, Self.a, [0, 1, 2, 3], actives: actives),
                                Self.releve(jours: 1.4, Self.b, [3, 4, 5], actives: actives)]
        #expect(Self.collisions(vraie) == [[], [], [], [], [3], [], [3], []])
        #expect(Self.cles(vraie, routeur: 3).suffix(4) == ["rloc:0000000A:0C00", "rloc:0C00", "rloc:0000000A:0C00", "rloc:0C00"])
    }

    /// Relecture finale, Important 1 : un simple changement d'identifiant de partition pendant la transition de Bonjour
    /// (des routeurs de bordure annoncent encore l'ancienne, les deux sont annoncees ensemble) : aucune qualification.
    @Test func transitionBonjourSansCollision() {
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2]),
                       Self.releve(jours: 0.01, Self.b, [0, 1, 2], actives: [Self.a, Self.b]),
                       Self.releve(jours: 0.02, Self.b, [0, 1, 2])]
        #expect(Self.collisions(releves) == [[], [], []])
        #expect(Self.cles(releves) == Array(repeating: "rloc:0400", count: 3))
        let m = Self.maillage(jours: 0.01, Self.b, [0, 1, 2])
        #expect(CollisionsRloc(releves: Array(releves.prefix(1))).collisions(apres: m, actives: [Self.a, Self.b]).isEmpty)
    }

    /// Fin de la scission : Bonjour n'annonce plus qu'une partition, plus de collision. Le routeur qui tenait la cle
    /// simple la garde (la sonde revenue dans A) ; les releves de B pendant la scission restent qualifies (recalcules de
    /// la liste seule, rien n'est melange). Si c'est B qui reste seule, elle reprend la cle simple : sans ExtMac, rien ne
    /// distingue ses routeurs (comportement d'avant la phase 8, accepte).
    /// Marge (decision de Djoko du 20/10) : la scission ne finit qu'au troisieme releve de suite sans scission.
    @Test func finDeScission() {
        let actives = [Self.a, Self.b]
        let scission = [Self.releve(jours: 0, Self.a, [1]), Self.releve(jours: 0.1, Self.a, [1], actives: actives),
                        Self.releve(jours: 0.2, Self.b, [1, 2], actives: actives),
                        Self.releve(jours: 0.3, Self.a, [1], actives: actives)]
        let finA = scission + [Self.releve(jours: 0.4, Self.a, [1]), Self.releve(jours: 0.5, Self.a, [1]),
                               Self.releve(jours: 0.6, Self.a, [1])]
        #expect(Self.cles(finA) == ["rloc:0400", "rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0400", "rloc:0400",
                                    "rloc:0400"])
        let finB = scission + [Self.releve(jours: 0.4, Self.b, [1, 2]), Self.releve(jours: 0.5, Self.b, [1, 2]),
                               Self.releve(jours: 0.6, Self.b, [1, 2])]
        #expect(Self.cles(finB) == ["rloc:0400", "rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0000000B:0400",
                                    "rloc:0000000B:0400", "rloc:0400"])
        // Une nouvelle scission plus tard : seuls ses releves comptent. A, vue pendant celle-ci, tient de nouveau la cle
        // simple ; sans releve de A pendant la nouvelle scission, B garde la cle simple (rien ne montre une collision).
        let encore = finA + [Self.releve(jours: 2, Self.a, [1], actives: actives), Self.releve(jours: 2.1, Self.b, [1, 2], actives: actives)]
        #expect(Self.cles(encore).last == "rloc:0000000B:0400")
        let sansA = finA + [Self.releve(jours: 2, Self.b, [1, 2], actives: actives)]
        #expect(Self.cles(sansA).last == "rloc:0400")
    }

    /// Marge, un releve sans scission au milieu (Bonjour qui vacille le temps d'une tournee) : rien ne change. La
    /// partition qualifiee (B, celle de la sonde) reste qualifiee pendant ce releve, la tenante (A) garde la cle simple.
    @Test func margeUnReleveSansScission() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [0, 1, 2, 3], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [0, 1], actives: actives),
                       Self.releve(jours: 0.2, Self.b, [0, 1]),
                       Self.releve(jours: 0.3, Self.b, [0, 1], actives: actives),
                       Self.releve(jours: 0.4, Self.a, [0, 1, 2, 3], actives: actives)]
        #expect(Self.collisions(releves) == [[], [0, 1], [0, 1], [0, 1], []])
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400", "rloc:0000000B:0400", "rloc:0000000B:0400",
                                       "rloc:0400"])
        // La tenante dans un releve de marge garde la cle simple.
        let tenante = Array(releves.prefix(2)) + [Self.releve(jours: 0.2, Self.a, [0, 1, 2, 3])]
        #expect(Self.collisions(tenante) == [[], [0, 1], []])
    }

    /// Marge, deux releves sans scission puis la scission revient : c'est la meme scission, avec la meme tenante et les
    /// memes cles. Sans marge, la scission reprise depuis B donnerait la cle simple a B (vue d'abord), et A, tenante de la
    /// scission, serait qualifiee. Le maillage d'un releve de marge, evalue avant ou apres son entree dans la liste, donne
    /// les memes collisions (l'app evalue deux fois le maillage recu).
    @Test func margeDeuxRelevesPuisRetour() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [1, 2], actives: actives),
                       Self.releve(jours: 0.2, Self.b, [1, 2]),
                       Self.releve(jours: 0.3, Self.b, [1, 2]),
                       Self.releve(jours: 0.4, Self.b, [1, 2], actives: actives),
                       Self.releve(jours: 0.5, Self.a, [1], actives: actives)]
        #expect(Self.collisions(releves) == [[], [1], [1], [1], [1], []])
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400", "rloc:0000000B:0400", "rloc:0000000B:0400",
                                       "rloc:0000000B:0400", "rloc:0400"])
        let m = Self.maillage(jours: 0.3, Self.b, [1, 2])
        #expect(CollisionsRloc(releves: Array(releves.prefix(3))).collisions(apres: m, actives: []) == [1], "pas encore dedans")
        #expect(CollisionsRloc(releves: Array(releves.prefix(4))).collisions(apres: m, actives: []) == [1], "deja dedans")
    }

    /// Marge : au troisieme releve de suite sans scission, la scission est finie ; ce releve a les cles simples, et une
    /// scission plus tard repart de zero. Un releve d'une partition qui n'etait pas de la scission (C) n'a aucune
    /// collision pendant la marge, et compte dans la marge.
    @Test func margeTroisRelevesSansScission() {
        let actives = [Self.a, Self.b]
        let scission = [Self.releve(jours: 0, Self.a, [1], actives: actives),
                        Self.releve(jours: 0.1, Self.b, [1, 2], actives: actives)]
        let fin = scission + [Self.releve(jours: 0.2, Self.b, [1, 2]), Self.releve(jours: 0.3, Self.b, [1, 2]),
                              Self.releve(jours: 0.4, Self.b, [1, 2])]
        #expect(Self.collisions(fin) == [[], [1], [1], [1], []])
        #expect(Self.cles(fin).last == "rloc:0400")
        let nouvelle = fin + [Self.releve(jours: 1, Self.b, [1, 2], actives: actives)]
        #expect(Self.collisions(nouvelle).last == [], "nouvelle scission : A pas encore vue")
        let avecC = scission + [Self.releve(jours: 0.2, Self.c, [1, 2]), Self.releve(jours: 0.3, Self.b, [1, 2]),
                                Self.releve(jours: 0.4, Self.b, [1, 2])]
        #expect(Self.collisions(avecC) == [[], [1], [], [1], []])
    }

    /// Le debut d'une scission reste immediat : le premier releve qui montre deux partitions actives avec le meme
    /// identifiant qualifie, sans marge, y compris juste apres la fin d'une scission.
    @Test func debutImmediat() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1]), Self.releve(jours: 0.1, Self.a, [1], actives: actives),
                       Self.releve(jours: 0.2, Self.b, [1], actives: actives)]
        #expect(Self.collisions(releves) == [[], [], [1]])
        let apresFin = [Self.releve(jours: 0, Self.a, [1], actives: actives), Self.releve(jours: 0.1, Self.b, [1], actives: actives),
                        Self.releve(jours: 0.2, Self.b, [1]), Self.releve(jours: 0.3, Self.b, [1]),
                        Self.releve(jours: 0.4, Self.b, [1]),
                        Self.releve(jours: 1, Self.b, [1], actives: actives), Self.releve(jours: 1.1, Self.a, [1], actives: actives)]
        #expect(Self.collisions(apresFin) == [[], [1], [1], [1], [], [], [1]], "B vue d'abord : A qualifiee")
    }

    /// Deterministe : la meme liste donne les memes cles ; le maillage du dernier releve, evalue apres la liste avec les
    /// memes partitions actives, donne les memes collisions que ce releve (l'app evalue le maillage recu avant de
    /// l'ajouter a l'historique). Sans historique (demo), aucune, meme pendant une scission.
    @Test func deterministeEtIdempotent() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1], actives: actives),
                       Self.releve(jours: 1, Self.b, [0, 1, 2], liens: [(0, 1)], actives: actives)]
        #expect(Self.cles(releves) == Self.cles(releves))
        let collisions = CollisionsRloc(releves: releves)
        let m = Self.maillage(jours: 1, Self.b, [0, 1, 2])
        #expect(collisions.collisions(releve: 1) == [1])
        #expect(collisions.collisions(apres: m, actives: actives) == collisions.collisions(releve: 1))
        #expect(CollisionsRloc(releves: Array(releves.prefix(1))).collisions(apres: m, actives: actives) == [1])
        #expect(CollisionsRloc(releves: []).collisions(apres: m, actives: actives).isEmpty, "sans historique (demo) : aucune")
    }

    /// Le releve garde les partitions actives, triees et avec la sienne, et seulement pendant une scission : une ligne
    /// hors scission s'ecrit exactement comme avant (rejeu, `HistoriqueTests.ligneDUnReleve`) ; une ligne d'avant se
    /// relit sans scission.
    @Test func partitionsActivesDuReleve() throws {
        let scinde = Self.releve(jours: 0, Self.b, [1], actives: [Self.c, Self.b, Self.c])
        #expect(scinde.actives == [Self.b, Self.c])
        let json = String(decoding: try CodageJSON.encodeur().encode(scinde), as: UTF8.self)
        #expect(json.contains(#""actives":["0000000B","0000000C"]"#))
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(json.utf8)) == scinde)
        #expect(Self.releve(jours: 0, Self.b, [1], actives: [Self.b]).actives.isEmpty, "une seule partition")
        #expect(Self.releve(jours: 0, Self.b, [1], actives: [Self.a, Self.c]).actives.isEmpty, "sans la sienne")
        let normal = Self.releve(jours: 0, Self.b, [1])
        #expect(!String(decoding: try CodageJSON.encodeur().encode(normal), as: UTF8.self).contains("actives"))
        let m = Self.maillage(jours: 0, Self.b, [1, 2])
        #expect(ReleveMaillage(m, actives: [Self.a, Self.b]).actives == [Self.a, Self.b])
        #expect(ReleveMaillage(m).actives.isEmpty)
    }

    /// Un routeur identifie (ExtMac) garde son ExtMac pendant une collision : seule la cle de repli est qualifiee. Un
    /// identifiant seulement cite (un lien) qu'a aussi une autre partition active est qualifie aussi.
    @Test func extMacEtCites() {
        let x = "E0000000000000C1"
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1, 4], actives: actives),
                       Self.releve(jours: 0.1, Self.b, [1, 2], ext: [1: x], liens: [(2, 4)], actives: actives)]
        #expect(Self.cles(releves) == ["rloc:0400", x])
        #expect(Self.cles(releves, routeur: 4) == ["rloc:1000", "rloc:0000000B:1000"])
    }

    /// Courbes : chaque routeur a les siennes ; la cle simple ne montre que la partition qui la tient.
    @Test func courbesSeparees() {
        let actives = [Self.a, Self.b]
        let releves = [Self.releve(jours: 0, Self.a, [1, 2], liens: [(1, 2)], actives: actives),
                       Self.releve(jours: 0.01, Self.b, [1, 3], liens: [(1, 3)], actives: actives)]
        let fin = Self.t0.addingTimeInterval(Self.jour)
        let simple = CourbesNoeud(cle: "rloc:0400", releves: releves, periode: .jour, fin: fin)
        #expect(simple.liens.map(\.id) == ["rloc:0800"])
        let qualifiee = CourbesNoeud(cle: "rloc:0000000B:0400", releves: releves, periode: .jour, fin: fin)
        #expect(qualifiee.liens.map(\.id) == ["rloc:0C00"], "le 3 n'est qu'a B : simple")
    }

    /// Rapprochement et scene : pendant une collision, les noeuds de la sonde de la partition qualifiee (routeurs et
    /// leurs enfants) ont la cle qualifiee, dans le maillage affiche, les liens et le graphe ; sans collision, les cles
    /// d'avant.
    @Test func sceneQualifiee() throws {
        let i = RapprochementTests.instantane(ailleurs: [("HomePod cuisine", "E0000000000000B1")])
        let r = try #require(i.reseaux.first)
        let p = "73586B68"
        let m = Self.maillage(jours: 0, p, [1, 5])
        let simple = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils)
        #expect(simple.routeurs[1]?.id == "rloc:0400" && simple.enfants[0x0402]?.id == "rloc:0402")
        let affiche = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils, collisions: [1])
        #expect(affiche.routeurs[1]?.id == "rloc:73586B68:0400")
        #expect(affiche.routeurs[5]?.id == "rloc:1400", "le 5 n'est pas en collision")
        #expect(affiche.enfants[0x0402]?.id == "rloc:73586B68:0402" && affiche.enfants[0x1402]?.id == "rloc:1402")
        #expect(affiche.liens.contains { $0.de == "rloc:73586B68:0402" && $0.vers == "rloc:73586B68:0400" })
        #expect(affiche.noeud("rloc:73586B68:0400")?.rloc16 == 0x0400 && affiche.noeud("rloc:0400") == nil)
        let g = GrapheReseau(reseau: r, appareils: RapprochementTests.affiches(i), maillage: affiche)
        let n = try #require(g.noeud(idt("rloc:73586B68:0400")))
        #expect(n.partition == p && n.inconnu && n.routeur)
        #expect(g.noeud(idt("rloc:0400")) == nil)
    }

    /// Suivi du maillage : les sujets de repli suivent la meme fabrique ; une cle qui change dans une meme partition (fin
    /// de la scission) ne fait ni apparition ni disparition de routeur ; la sonde qui passe dans l'autre partition est un
    /// changement de partition, point de depart sans evenement.
    @Test func suiviSansEvenementParasite() {
        var suivi = SuiviMaillage()
        let a = Self.maillage(jours: 0, Self.a, [0, 1, 2])
        let b1 = Self.maillage(jours: 0.1, Self.b, [0, 1, 2])
        let b2 = Self.maillage(jours: 0.2, Self.b, [0, 1, 2])
        let b3 = Self.maillage(jours: 0.3, Self.b, [0, 1])
        #expect(suivi.integrer(a, sujets: SujetsMaillage()).isEmpty)
        #expect(suivi.integrer(b1, sujets: SujetsMaillage(collisions: [0, 1, 2])).isEmpty, "autre partition : point de depart")
        #expect(suivi.integrer(b2, sujets: SujetsMaillage()).isEmpty, "fin de la scission : cles changees, aucun evenement")
        let ev = suivi.integrer(b3, sujets: SujetsMaillage())
        #expect(ev.map(\.type) == [.routeurThreadDisparu] && ev.first?.sujet?.id == "rloc:0800")
        var qualifie = SuiviMaillage()
        _ = qualifie.integrer(b1, sujets: SujetsMaillage(collisions: [0, 1, 2]))
        let parti = qualifie.integrer(Self.maillage(jours: 0.15, Self.b, [0, 1]), sujets: SujetsMaillage(collisions: [0, 1, 2]))
        #expect(parti.first?.sujet?.id == "rloc:0000000B:0800", "sujet de repli qualifie")
    }
}
