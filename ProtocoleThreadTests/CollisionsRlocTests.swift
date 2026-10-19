import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Cles "rloc:" qualifiees en cas de collision (phase 8, decision de Djoko du 20/10) : deux partitions peuvent avoir le
/// meme RLOC16. La cle reste "rloc:XXXX" tant qu'une seule partition a cet identifiant de routeur ; pendant une
/// collision, les routeurs des autres partitions prennent "rloc:<partition>:XXXX". Garde la cle simple la partition qui
/// la tenait au releve precedent ; a defaut la plus grande partition, puis le plus petit identifiant de partition.
/// Valeurs inventees.
@Suite("Cles rloc qualifiees en cas de collision")
struct CollisionsRlocTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_006_400)
    static let a = "0000000A"
    static let b = "0000000B"
    static let c = "0000000C"
    static let jour: TimeInterval = 24 * 3600

    /// Releve a `jours` de t0 de la partition `p` : les routeurs donnes, sans ExtMac sauf `ext`.
    static func releve(jours: Double, _ p: String, _ routeurs: [Int], ext: [Int: String] = [:],
                       liens: [(Int, Int)] = []) -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(jours * jour), partition: p,
                       routeurs: routeurs.sorted().map { .init(id: $0, extMac: ext[$0]) },
                       liens: liens.map { LienRadio(a: $0.0, b: $0.1, qualiteAB: 3, qualiteBA: 2) }, enfants: [], signaux: [],
                       parentSonde: nil)
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

    /// Les cles du routeur 1 a chaque releve de la liste.
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

    /// Une seule partition, meme sur 60 jours : aucune collision, les cles d'avant.
    @Test func sansCollision() {
        let releves = (0..<60).map { Self.releve(jours: Double($0), Self.a, [0, 1, 5]) }
        let collisions = CollisionsRloc(releves: releves)
        #expect(releves.indices.allSatisfy { collisions.collisions(releve: $0).isEmpty })
        #expect(Self.cles(releves) == Array(repeating: "rloc:0400", count: 60))
        #expect(Self.cles(releves, routeur: 5).allSatisfy { $0 == "rloc:1400" })
    }

    /// Debut de collision : la partition qui tenait la cle au releve precedent la garde, meme plus petite ; l'autre est
    /// qualifiee des son premier releve. Un identifiant que l'autre partition n'a pas reste simple.
    @Test func debutDeCollision() {
        let releves = [Self.releve(jours: 0, Self.a, [1]), Self.releve(jours: 0.1, Self.b, [0, 1, 2, 3])]
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400"])
        #expect(Self.cles(releves, routeur: 2) == ["rloc:0800", "rloc:0800"], "seule B a le 2")
        #expect(CollisionsRloc(releves: releves).collisions(releve: 1) == [1])
    }

    /// Collision stable sur trois releves de chaque partition, en alternance : les memes cles a chaque fois, sans
    /// osciller (le departage par la taille ne joue pas tant que la tenante est la).
    @Test func collisionStable() {
        let releves = (0..<6).map { n in
            n % 2 == 0 ? Self.releve(jours: Double(n), Self.a, [1]) : Self.releve(jours: Double(n), Self.b, [0, 1, 2, 3])
        }
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0000000B:0400",
                                       "rloc:0400", "rloc:0000000B:0400"])
    }

    /// Fin de collision : la partition partie depuis plus de `duree` (30 jours, l'historique en memoire et la plus longue
    /// periode des courbes) ne compte plus ; le routeur qualifie retrouve la cle simple. 30 jours pile comptent encore.
    @Test func finDeCollision() {
        #expect(CollisionsRloc.duree == PeriodeCourbes.mois.duree)
        let releves = [Self.releve(jours: 0, Self.a, [1]), Self.releve(jours: 1, Self.b, [1]),
                       Self.releve(jours: 30, Self.b, [1]), Self.releve(jours: 30 + 1 / 86_400, Self.b, [1]),
                       Self.releve(jours: 40, Self.b, [1])]
        #expect(Self.cles(releves) == ["rloc:0400", "rloc:0000000B:0400", "rloc:0000000B:0400", "rloc:0400", "rloc:0400"])
        // La tenante revient apres la fin : la cle simple est a B, A est qualifiee a son tour.
        let retour = releves + [Self.releve(jours: 41, Self.a, [1])]
        #expect(Self.cles(retour).last == "rloc:0000000A:0400")
    }

    /// La tenante partie, deux autres partitions encore en collision : la plus grande prend la cle simple ; a taille
    /// egale, le plus petit identifiant de partition.
    @Test func departageTaillePuisIdentifiant() {
        let base = [Self.releve(jours: 0, Self.a, [0, 1, 2, 3, 4, 5]), Self.releve(jours: 10, Self.c, [0, 1, 2]),
                    Self.releve(jours: 20, Self.b, [1, 2])]
        #expect(Self.cles(base) == ["rloc:0400", "rloc:0000000C:0400", "rloc:0000000B:0400"], "A tient, meme plus petite plus tard")
        // Jour 31 : A est partie ; C (3 routeurs) l'emporte sur B (2).
        let taille = base + [Self.releve(jours: 31, Self.b, [1, 2])]
        #expect(Self.cles(taille).last == "rloc:0000000B:0400")
        #expect(Self.cles(taille + [Self.releve(jours: 32, Self.c, [0, 1, 2])]).last == "rloc:0400")
        // A taille egale (B passe a 3 routeurs), le plus petit identifiant : B.
        let egale = base.dropLast() + [Self.releve(jours: 20, Self.b, [1, 2, 7]), Self.releve(jours: 31, Self.b, [1, 2, 7])]
        #expect(Self.cles(Array(egale)).last == "rloc:0400")
        #expect(Self.cles(Array(egale) + [Self.releve(jours: 32, Self.c, [0, 1, 2])]).last == "rloc:0000000C:0400")
    }

    /// Deterministe : la meme liste donne les memes cles ; et le maillage du dernier releve, evalue apres la liste,
    /// donne les memes collisions que ce releve (l'app evalue le maillage recu avant de l'ajouter a l'historique).
    @Test func deterministeEtIdempotent() {
        let releves = [Self.releve(jours: 0, Self.a, [1]), Self.releve(jours: 1, Self.b, [1, 5])]
        #expect(Self.cles(releves) == Self.cles(releves))
        let collisions = CollisionsRloc(releves: releves)
        let m = Self.maillage(jours: 1, Self.b, [1, 5])
        #expect(collisions.collisions(apres: m) == collisions.collisions(releve: 1))
        #expect(CollisionsRloc(releves: Array(releves.prefix(1))).collisions(apres: m) == [1])
        #expect(CollisionsRloc(releves: []).collisions(apres: m).isEmpty, "sans historique (demo) : aucune")
    }

    /// Un routeur identifie (ExtMac) garde son ExtMac pendant une collision : seule la cle de repli est qualifiee. Un
    /// identifiant seulement cite (un lien) que tient une autre partition est qualifie aussi.
    @Test func extMacEtCites() {
        let x = "E0000000000000C1"
        let releves = [Self.releve(jours: 0, Self.a, [1, 4]), Self.releve(jours: 1, Self.b, [1, 2], ext: [1: x], liens: [(2, 4)])]
        #expect(Self.cles(releves) == ["rloc:0400", x])
        #expect(Self.cles(releves, routeur: 4) == ["rloc:1000", "rloc:0000000B:1000"])
    }

    /// Courbes : chaque routeur a les siennes ; la cle simple ne montre que la partition qui la tient.
    @Test func courbesSeparees() {
        let releves = [Self.releve(jours: 0, Self.a, [1, 2], liens: [(1, 2)]), Self.releve(jours: 0.01, Self.b, [1, 3], liens: [(1, 3)])]
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
    /// de collision) ne fait ni apparition ni disparition de routeur ; le debut d'une collision est un changement de
    /// partition, point de depart sans evenement.
    @Test func suiviSansEvenementParasite() {
        var suivi = SuiviMaillage()
        let a = Self.maillage(jours: 0, Self.a, [0, 1, 2])
        let b1 = Self.maillage(jours: 1, Self.b, [0, 1, 2])
        let b2 = Self.maillage(jours: 31, Self.b, [0, 1, 2])
        let b3 = Self.maillage(jours: 32, Self.b, [0, 1])
        #expect(suivi.integrer(a, sujets: SujetsMaillage()).isEmpty)
        #expect(suivi.integrer(b1, sujets: SujetsMaillage(collisions: [0, 1, 2])).isEmpty, "autre partition : point de depart")
        #expect(suivi.integrer(b2, sujets: SujetsMaillage()).isEmpty, "fin de collision : cles changees, aucun evenement")
        let ev = suivi.integrer(b3, sujets: SujetsMaillage())
        #expect(ev.map(\.type) == [.routeurThreadDisparu] && ev.first?.sujet?.id == "rloc:0800")
        var qualifie = SuiviMaillage()
        _ = qualifie.integrer(b1, sujets: SujetsMaillage(collisions: [0, 1, 2]))
        let parti = qualifie.integrer(Self.maillage(jours: 1.1, Self.b, [0, 1]), sujets: SujetsMaillage(collisions: [0, 1, 2]))
        #expect(parti.first?.sujet?.id == "rloc:0000000B:0800", "sujet de repli qualifie")
    }
}
