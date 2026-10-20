import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

/// Cles des routeurs dans l'historique (verification du 05/10) : un routeur sans ExtMac dans un releve prend celle du
/// meme identifiant, dans la meme partition, au releve suivant le plus proche qui en a une, a defaut au precedent le
/// plus proche, l'un et l'autre a 7 jours au plus ; sinon "rloc:XXXX". Une ExtMac que tient ou que prend un autre
/// routeur du releve n'est pas prise. Valeurs inventees.
@Suite("Cles des routeurs dans l'historique")
struct ClesHistoriqueTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_006_400)
    static let c1 = "E0000000000000C1"
    static let c2 = "E0000000000000C2"
    static let c3 = "E0000000000000C3"

    /// Releve `n` (a `n` fois 5 min de t0) de la partition `p` : les routeurs donnes, par identifiant, avec leur ExtMac
    /// ou nil.
    static func releve(_ n: Int, _ routeurs: [Int: String?], partition p: String = "0000000A") -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(Double(n) * 300), partition: p,
                       routeurs: routeurs.keys.sorted().map { .init(id: $0, extMac: routeurs[$0] ?? nil) },
                       liens: [], enfants: [], signaux: [], parentSonde: nil)
    }

    /// Releve a `jours` de t0, de la partition `p` : les routeurs donnes, et des identifiants seulement cites (un lien
    /// de chacun vers le routeur 0, et le parent de la sonde).
    static func releve(jours: Double, _ routeurs: [Int: String?], partition p: String = "0000000A", cites: [Int] = [],
                       parentSonde: Int? = nil, actives: [String] = []) -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(jours * 24 * 3600), partition: p,
                       routeurs: routeurs.keys.sorted().map { .init(id: $0, extMac: routeurs[$0] ?? nil) },
                       liens: cites.map { LienRadio(a: 0, b: $0, qualiteAB: 3, qualiteBA: 3) }, enfants: [], signaux: [],
                       parentSonde: parentSonde, actives: actives)
    }

    static let semaine: TimeInterval = 7 * 24 * 3600

    /// Le releve lui-meme d'abord ; sans ExtMac, le suivant le plus proche qui en a une, puis le precedent le plus
    /// proche. L'identifiant 1 passe d'un routeur (c1) a un autre (c2) : chaque releve prend le plus proche, pas le
    /// premier ni le dernier de la liste.
    @Test func suivantPuisPrecedent() {
        let releves = [Self.releve(0, [1: nil]), Self.releve(1, [1: Self.c1]), Self.releve(2, [1: nil]),
                       Self.releve(3, [1: Self.c2]), Self.releve(4, [1: nil]), Self.releve(5, [1: nil])]
        let cles = ClesHistorique(releves: releves)
        #expect(releves.indices.map { cles.cle(releve: $0, routeur: 1) } == [Self.c1, Self.c1, Self.c2, Self.c2, Self.c2, Self.c2])
    }

    /// Jamais identifie : "rloc:XXXX", qu'il soit dans la liste des routeurs du releve ou seulement cite.
    @Test func jamaisIdentifie() {
        let releves = [Self.releve(0, [1: nil]), Self.releve(1, [0: Self.c1, 1: nil])]
        let cles = ClesHistorique(releves: releves)
        #expect(cles.cle(releve: 0, routeur: 1) == "rloc:0400" && cles.cle(releve: 1, routeur: 1) == "rloc:0400")
        #expect(cles.cle(releve: 0, routeur: 5) == "rloc:1400", "cite, hors de la liste")
        #expect(cles.cle(releve: 0, routeur: 0) == Self.c1, "cite au releve 0, identifie au suivant")
    }

    /// Le meme identifiant dans une autre partition est un autre routeur : son ExtMac ne compte pas, meme plus proche.
    @Test func autrePartition() {
        let releves = [Self.releve(0, [1: nil]), Self.releve(1, [1: Self.c1], partition: "0000000B"),
                       Self.releve(2, [1: nil]), Self.releve(3, [1: nil], partition: "0000000B"),
                       Self.releve(4, [1: Self.c2])]
        let cles = ClesHistorique(releves: releves)
        #expect(releves.indices.map { cles.cle(releve: $0, routeur: 1) } == [Self.c2, Self.c1, Self.c2, Self.c1, Self.c2])
        let seule = ClesHistorique(releves: [Self.releve(0, [1: nil]), Self.releve(1, [1: Self.c1], partition: "0000000B")])
        #expect(seule.cle(releve: 0, routeur: 1) == "rloc:0400")
    }

    /// Fonction totale : un identifiant hors de 0...62 rend "rloc:?", meme avec une ExtMac (donnees non conformes) ; un
    /// releve hors de la liste rend "rloc:XXXX".
    @Test func plage() {
        let releves = [Self.releve(0, [62: nil, 63: Self.c3, 64: Self.c3]), Self.releve(1, [63: nil, 64: nil])]
        let cles = ClesHistorique(releves: releves)
        for id in [63, 64, -1, 70000, 1 << 40] {
            #expect(cles.cle(releve: 0, routeur: id) == "rloc:?" && cles.cle(releve: 1, routeur: id) == "rloc:?", "\(id)")
        }
        #expect(cles.cle(releve: 0, routeur: 62) == "rloc:F800")
        #expect(cles.cle(releve: 0, routeur: 0) == "rloc:0000")
        #expect(cles.cle(releve: 2, routeur: 1) == "rloc:0400" && cles.cle(releve: -1, routeur: 1) == "rloc:0400")
        #expect(ClesHistorique(releves: []).cle(releve: 0, routeur: 1) == "rloc:0400")
    }

    /// Une ExtMac que tient un autre routeur du meme releve n'est pas prise (le routeur c1 a change d'identifiant ;
    /// l'ancien reste sans ExtMac) : deux routeurs d'un releve n'ont jamais la meme cle.
    @Test func extMacDejaPrise() {
        let releves = [Self.releve(0, [1: Self.c1]), Self.releve(1, [1: nil, 2: Self.c1])]
        let cles = ClesHistorique(releves: releves)
        #expect(cles.cle(releve: 1, routeur: 1) == "rloc:0400")
        #expect(cles.cle(releve: 1, routeur: 2) == Self.c1)
        #expect(cles.cle(releve: 0, routeur: 2) == "rloc:0800", "au releve 0, c1 est au routeur 1")
    }
    /// Deux routeurs sans ExtMac d'un meme releve qui se resolvent vers la meme (relecture, Mineur 1) : c1 est le
    /// routeur 1 aux releves 0 et 1, le routeur 2 aux releves 3 et 4 ; au releve 2, le 1 prendrait le precedent, le 2
    /// le suivant. Aucun ne la tient : tous deux gardent "rloc".
    @Test func deuxResolusVersLaMeme() {
        let releves = [Self.releve(0, [1: Self.c1]), Self.releve(1, [1: Self.c1]), Self.releve(2, [1: nil, 2: nil]),
                       Self.releve(3, [2: Self.c1]), Self.releve(4, [2: Self.c1])]
        let cles = ClesHistorique(releves: releves)
        #expect(cles.cle(releve: 2, routeur: 1) == "rloc:0400" && cles.cle(releve: 2, routeur: 2) == "rloc:0800")
        #expect(cles.cle(releve: 1, routeur: 1) == Self.c1 && cles.cle(releve: 3, routeur: 2) == Self.c1)
    }

    /// Un identifiant liste deux fois (donnees non conformes) : seul le premier compte, comme pour
    /// `ReleveMaillage.cle(routeur:)`. Sans ExtMac, il prend celle du suivant, non celle du doublon.
    @Test func premierRouteurDUnIdentifiant() {
        let double = ReleveMaillage(date: Self.t0, partition: "0000000A",
                                    routeurs: [.init(id: 1, extMac: nil), .init(id: 1, extMac: Self.c1)],
                                    liens: [], enfants: [], signaux: [], parentSonde: nil)
        #expect(double.cle(routeur: 1) == "rloc:0400")
        let cles = ClesHistorique(releves: [double, Self.releve(1, [1: Self.c2])])
        #expect(cles.cle(releve: 0, routeur: 1) == Self.c2)
    }

    /// Le suivant refuse par la garde (relecture, Mineur 2) : c2 est au routeur 2 dans ce releve. Choix fixe : la cle
    /// reste "rloc", sans essayer le precedent (c1) ; les indices se contredisent, la courbe ne devine pas.
    @Test func suivantRefuse() {
        let releves = [Self.releve(0, [1: Self.c1]), Self.releve(1, [1: nil, 2: Self.c2]), Self.releve(2, [1: Self.c2])]
        let cles = ClesHistorique(releves: releves)
        #expect(cles.cle(releve: 1, routeur: 1) == "rloc:0400")
        #expect(cles.cle(releve: 1, routeur: 2) == Self.c2)
    }

    /// Un identifiant seulement cite (lien, parent de la sonde) compte aussi pour la garde : le routeur 1, sans ExtMac,
    /// et le routeur 5, cite par un lien, se resoudraient tous deux vers c1.
    @Test func citeCompteDansLaGarde() {
        let releves = [Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: 1, [1: nil], cites: [5]),
                       Self.releve(jours: 2, [5: Self.c1])]
        let cles = ClesHistorique(releves: releves)
        #expect(cles.cle(releve: 1, routeur: 1) == "rloc:0400" && cles.cle(releve: 1, routeur: 5) == "rloc:1400")
        let sonde = [Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: 1, [1: nil], parentSonde: 5),
                     Self.releve(jours: 2, [5: Self.c1])]
        #expect(ClesHistorique(releves: sonde).cle(releve: 1, routeur: 1) == "rloc:0400")
    }

    /// Borne de 7 jours (demande de Djoko, 05/10), de part et d'autre, pour le suivant comme pour le precedent : 7 jours
    /// pile comptent, 7 jours et 1 s non. Un suivant trop loin laisse place au precedent.
    @Test func borneDeSeptJours() {
        #expect(ClesHistorique.ecartMax == 7 * 24 * 3600)
        let j = Self.semaine / (24 * 3600)
        let s = 1.0 / (24 * 3600)
        func cle(_ releves: [ReleveMaillage], _ i: Int) -> String { ClesHistorique(releves: releves).cle(releve: i, routeur: 1) }
        #expect(cle([Self.releve(jours: 0, [1: nil]), Self.releve(jours: j, [1: Self.c1])], 0) == Self.c1, "suivant a 7 j")
        #expect(cle([Self.releve(jours: 0, [1: nil]), Self.releve(jours: j + s, [1: Self.c1])], 0) == "rloc:0400",
                "suivant a 7 j et 1 s")
        #expect(cle([Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: j, [1: nil])], 1) == Self.c1, "precedent a 7 j")
        #expect(cle([Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: j + s, [1: nil])], 1) == "rloc:0400",
                "precedent a 7 j et 1 s")
        let loin = [Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: 3, [1: nil]), Self.releve(jours: 3 + j + s, [1: Self.c2])]
        #expect(cle(loin, 1) == Self.c1, "suivant trop loin : le precedent")
        let deuxLoin = [Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: j + s, [1: nil]),
                        Self.releve(jours: 2 * (j + s), [1: Self.c2])]
        #expect(cle(deuxLoin, 1) == "rloc:0400", "les deux trop loin")
    }

    /// Le cas du relecteur (Mineur 5) : l'identifiant 1, c1 jusqu'au jour 0, est repris par un routeur jamais identifie.
    /// A plus de 7 jours de c1, il garde "rloc" : il ne prend plus l'historique de l'appareil parti.
    @Test func reattribueJamaisIdentifie() {
        let releves = [Self.releve(jours: 0, [1: Self.c1]), Self.releve(jours: 6, [1: nil]), Self.releve(jours: 8, [1: nil]),
                       Self.releve(jours: 20, [1: nil])]
        let cles = ClesHistorique(releves: releves)
        #expect(releves.indices.map { cles.cle(releve: $0, routeur: 1) } == [Self.c1, Self.c1, "rloc:0400", "rloc:0400"])
    }

    /// La regle ecrite a la lettre, sans index ni dichotomie : le releve lui-meme, puis le suivant, puis le precedent
    /// (meme partition, 7 jours au plus, en parcourant la liste) ; une ExtMac que tient ou que prend un autre
    /// identifiant du releve (de sa liste ou cite) est refusee. Rend aussi le cas rencontre. Sans ExtMac, "rloc:XXXX",
    /// qualifie par la partition si l'identifiant est dans `collisions`, celles du releve (`naiveCollisions`).
    enum Cas: Hashable { case horsPlage, jamais, directe, suivant, precedent, refusee, horsBorne }

    static func naive(_ releves: [ReleveMaillage], _ i: Int, _ id: Int, collisions: [Set<Int>]) -> (cle: String, cas: Cas) {
        guard (0...62).contains(id) else { return ("rloc:?", .horsPlage) }
        let simple = String(format: "%04X", id << 10)
        guard releves.indices.contains(i) else { return ("rloc:" + simple, .jamais) }
        let r = releves[i]
        let rloc = collisions[i].contains(id) ? "rloc:\(r.partition):" + simple : "rloc:" + simple
        func ext(_ k: Int, _ id: Int) -> String? {
            releves[k].partition == r.partition ? releves[k].routeurs.first { $0.id == id }?.extMac : nil
        }
        func proche(_ id: Int, borne: Bool) -> (String, Cas)? {
            if let e = ext(i, id) { return (e, .directe) }
            for k in (i + 1)..<releves.count where !borne || releves[k].date.timeIntervalSince(r.date) <= 7 * 24 * 3600 {
                if let e = ext(k, id) { return (e, .suivant) }
            }
            for k in stride(from: i - 1, through: 0, by: -1) where !borne || r.date.timeIntervalSince(releves[k].date) <= 7 * 24 * 3600 {
                if let e = ext(k, id) { return (e, .precedent) }
            }
            return nil
        }
        guard let (e, cas) = proche(id, borne: true) else {
            return (rloc, proche(id, borne: false) == nil ? .jamais : .horsBorne)
        }
        if cas == .directe { return (e, cas) }
        let ids = Set(r.routeurs.map(\.id) + r.liens.flatMap { [$0.a, $0.b] } + r.enfants.map(\.parent) + r.signaux.map(\.routeur)
                      + (r.parentSonde.map { [$0] } ?? [])).filter { (0...62).contains($0) && $0 != id }
        return ids.contains { proche($0, borne: true)?.0 == e } ? (rloc, .refusee) : (e, cas)
    }

    /// Les collisions de RLOC16 a la lettre (phase 8, correctifs du 20/10), ecrites d'apres le texte de la regle et non
    /// d'apres le code, en rejouant les releves 0 a `i`. Les partitions actives d'un releve : les siennes (deux ou plus,
    /// dont la sienne) ; a defaut, pendant la marge (un des deux releves qui suivent un releve de la scission, decision de
    /// Djoko du 20/10), celles du dernier releve de la scission. La scission en cours : la suite des releves jusqu'a `i`
    /// qui ont des partitions actives ; hors scission, ou pour un releve dont la partition n'en est pas, aucune
    /// collision. Seuls comptent les releves
    /// de la scission en cours : une partition active a un identifiant si son dernier releve de la scission le cite (liste,
    /// lien, parent d'un enfant, signal, parent de la sonde). Un identifiant qu'ont deux partitions actives ou plus et qui
    /// n'a pas encore de tenante en recoit une, gardee jusqu'a la fin de la scission : parmi elles, celles qui l'avaient
    /// avant ce releve (le nouveau venu ne passe jamais devant) ; la partition du releve precedent si elle l'y avait sans
    /// y etre qualifiee ; sinon la plus grande (nombre de routeurs de son dernier releve de la scission), puis le plus
    /// petit identifiant de partition. Rend les identifiants du releve `i` qu'il a et dont une autre partition est la
    /// tenante.
    static func naiveCollisions(_ releves: [ReleveMaillage], _ i: Int) -> Set<Int> {
        func cites(_ r: ReleveMaillage) -> Set<Int> {
            Set(r.routeurs.map(\.id) + r.liens.flatMap { [$0.a, $0.b] } + r.enfants.map(\.parent) + r.signaux.map(\.routeur)
                + (r.parentSonde.map { [$0] } ?? [])).filter { (0...62).contains($0) }
        }
        func scinde(_ r: ReleveMaillage) -> Bool { Set(r.actives).count >= 2 && r.actives.contains(r.partition) }
        func actives(_ k: Int) -> [String] {
            if scinde(releves[k]) { return releves[k].actives }
            return (max(0, k - 2)..<k).last { scinde(releves[$0]) }.map { releves[$0].actives } ?? []
        }
        func membre(_ k: Int) -> Bool { actives(k).contains(releves[k].partition) }
        guard membre(i) else { return [] }
        let debut = (0...i).last { actives($0).isEmpty }.map { $0 + 1 } ?? 0
        var tenantes: [Int: String] = [:]
        var resultat: Set<Int> = []
        for k in debut...i {
            let r = releves[k]
            /// Le dernier releve de `p` dans la scission, jusqu'a `fin` compris.
            func dernier(_ p: String, jusqua fin: Int) -> ReleveMaillage? {
                fin < debut ? nil : (debut...fin).last { releves[$0].partition == p && membre($0) }.map { releves[$0] }
            }
            func a(_ p: String, _ id: Int, jusqua fin: Int) -> Bool { dernier(p, jusqua: fin).map { cites($0).contains(id) } ?? false }
            let precedent = resultat
            resultat = []
            guard membre(k) else { continue }
            for id in 0...62 {
                let ont = Set(actives(k)).filter { a($0, id, jusqua: k) }
                if tenantes[id] == nil && ont.count >= 2 {
                    let avant = ont.filter { a($0, id, jusqua: k - 1) }
                    if k > debut, avant.contains(releves[k - 1].partition), cites(releves[k - 1]).contains(id), !precedent.contains(id) {
                        tenantes[id] = releves[k - 1].partition
                    } else {
                        func taille(_ p: String) -> Int {
                            Set(dernier(p, jusqua: k)!.routeurs.map(\.id).filter { (0...62).contains($0) }).count
                        }
                        tenantes[id] = avant.sorted {
                            (taille($0), UInt64($1, radix: 16)!) > (taille($1), UInt64($0, radix: 16)!)
                        }.first
                    }
                }
                if cites(r).contains(id), let t = tenantes[id], t != r.partition { resultat.insert(id) }
            }
        }
        return resultat
    }

    /// `cle` contre la version naive (relecture, Mineur 4) : 50 releves sur pres de deux mois, trois partitions, des
    /// identifications eparses, des ExtMac qui changent d'identifiant, des identifiants seulement cites. Tirage fixe (un
    /// generateur congruentiel de graine donnee) : aucun hasard. Chaque cas de la regle est rencontre. Deux scissions
    /// (phase 8) : A et B actives ensemble aux releves 18 a 23, A et C aux releves 36 a 45 (B y est active aussi un
    /// releve sur trois) ; les releves 24 et 25 sont la marge de la premiere ; les releves 26 a 31 (B seule, apres A) sont
    /// un changement d'identifiant, sans collision.
    @Test func commeLaVersionNaive() {
        var graine: UInt64 = 0x5EED
        func tirage(_ n: UInt64) -> Int {
            graine = graine &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((graine >> 33) % n)
        }
        let pas = [1.0, 1, 3, 1, 2, 0.5, 4]
        let macs = (0..<6).map { String(format: "E0000000000000D%X", $0) }
        var jours = 0.0
        var releves: [ReleveMaillage] = []
        for n in 0..<50 {
            let partition = n < 20 ? "0000000A" : n < 32 ? "0000000B" : (n % 3 == 0 ? "0000000C" : "0000000A")
            var routeurs: [Int: String?] = [:]
            for id in 0..<6 where tirage(10) < 7 {
                // Une ExtMac une fois sur cinq ; l'ExtMac d'un identifiant change tous les 17 releves (unique dans le releve).
                routeurs[id] = tirage(5) == 0 ? macs[(id + n / 17) % 6] : nil
            }
            let cites = [5, 6].filter { routeurs[$0] == nil && tirage(2) == 0 }
            let actives = (18..<24).contains(n) ? ["0000000A", "0000000B"]
                : (36..<46).contains(n) ? (n % 3 == 0 ? ["0000000A", "0000000B", "0000000C"] : ["0000000A", "0000000C"]) : []
            releves.append(Self.releve(jours: jours, routeurs, partition: partition, cites: cites,
                                       parentSonde: routeurs[4] == nil && tirage(3) == 0 ? 4 : nil, actives: actives))
            jours += pas[n % pas.count]
        }
        let cles = ClesHistorique(releves: releves)
        let collisions = releves.indices.map { Self.naiveCollisions(releves, $0) }
        var vus: Set<Cas> = []
        var qualifiees = 0
        for i in -1...50 {
            for id in [-1, 0, 1, 2, 3, 4, 5, 6, 7, 62, 63] {
                let n = Self.naive(releves, i, id, collisions: collisions)
                vus.insert(n.cas)
                if n.cle.filter({ $0 == ":" }).count == 2 { qualifiees += 1 }
                #expect(cles.cle(releve: i, routeur: id) == n.cle, "releve \(i), routeur \(id)")
            }
        }
        #expect(vus == [.horsPlage, .jamais, .directe, .suivant, .precedent, .refusee, .horsBorne], "\(vus)")
        #expect(qualifiees > 0, "des cles qualifiees (deux scissions)")
        #expect((26..<32).allSatisfy { collisions[$0].isEmpty }, "changement d'identifiant : aucune collision")
        #expect(!collisions[24].isEmpty || !collisions[25].isEmpty, "la marge de la premiere scission")
        #expect(releves.indices.allSatisfy { cles.collisions.collisions(releve: $0) == collisions[$0] })
    }
}
