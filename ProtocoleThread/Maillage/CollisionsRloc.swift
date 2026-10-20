import Foundation
import MaillageCoeur

/// Cles "rloc:" des noeuds Thread que seule la sonde connait (phase 8, decision de Djoko du 20/10). Deux partitions
/// actives en meme temps peuvent avoir le meme RLOC16 : ce sont deux routeurs (les identifiants de routeur sont
/// distribues dans chaque partition). La cle reste "rloc:XXXX" hors collision ; pendant une collision seulement, les
/// noeuds des partitions qui ne tiennent pas la cle simple prennent "rloc:<partition>:XXXX" (`CollisionsRloc` dit
/// lesquels). Aucun fichier n'est converti : hors collision, les cles sont celles d'avant.
public enum CleRloc {
    /// Cle d'un identifiant de routeur hors de 0...62 (fonction totale : jamais d'arret du programme).
    public static let horsPlage = "rloc:?"

    /// La seule fabrique des cles "rloc:" : le RLOC16 en 4 hexa majuscules ; precede de la partition (telle que l'app
    /// l'affiche, `Maillage.partition`) si l'identifiant de routeur de ce RLOC16 est dans `collisions`, ceux dont une
    /// autre partition tient la cle simple. Un enfant suit son parent : son RLOC16 porte l'identifiant de son parent.
    public static func cle(_ rloc16: UInt16, partition: String, collisions: Set<Int>) -> String {
        let simple = String(format: "%04X", rloc16)
        return collisions.contains(Int(rloc16 >> 10)) ? "rloc:" + partition + ":" + simple : "rloc:" + simple
    }
}

/// Collisions de RLOC16 entre partitions actives en meme temps (decision de Djoko du 20/10), d'apres les releves de
/// l'historique, du plus ancien au plus recent.
///
/// Une collision n'existe que pendant une scission : le releve garde les partitions que Bonjour annoncait ensemble pour
/// le reseau de la sonde (`ReleveMaillage.actives`, la scission du bandeau « Reseau scinde »), la sienne comprise. La
/// sonde ne voit qu'une partition a la fois : les identifiants de routeur d'une autre partition active sont ceux de son
/// dernier releve de la liste (sa liste des routeurs et les identifiants cites : liens, parents des enfants, signaux,
/// parent de la sonde) ; une partition jamais vue n'en a aucun. Un identifiant qu'ont deux partitions actives ou plus est
/// en collision ; garde la cle simple :
/// 1. la tenante, tant qu'elle l'a (pas d'oscillation pendant une collision stable) ;
/// 2. a defaut, la partition du releve precedent, si elle l'avait sans y etre qualifiee ;
/// 3. puis la plus grande partition (le nombre de routeurs de son dernier releve) ;
/// 4. puis le plus petit identifiant de partition (en hexadecimal, a defaut en texte).
/// Les autres sont qualifiees. Une partition qui n'est plus active (ancien identifiant, plus annoncee) ne cree jamais de
/// collision : un simple changement d'identifiant de partition garde les cles simples. Hors scission, plus de collision
/// ni de tenante : la partition de la sonde a la cle simple (si c'est l'autre partition qui reste seule, ses routeurs
/// reprennent "rloc:XXXX" ; sans ExtMac rien ne les distingue, comportement d'avant la phase 8).
///
/// Deterministe : la meme liste donne les memes collisions. Calcule en un passage : O(1) par releve hors scission,
/// O(63 x P) pendant une scission de P partitions.
public struct CollisionsRloc: Sendable {
    /// L'etat apres un releve.
    struct Etat: Sendable {
        /// Par partition : les identifiants de routeur de son dernier releve, cites compris (masque, 0...62).
        var identifiants: [String: UInt64] = [:]
        /// Par partition : le nombre de routeurs de la liste de son dernier releve.
        var tailles: [String: Int] = [:]
        /// Par identifiant de routeur en collision : la partition qui tient la cle simple.
        var tenantes: [Int: String] = [:]
        /// La partition du releve precedent et ses collisions.
        var precedent: (partition: String, collisions: Set<Int>)?

        /// Integre le releve `r` ; rend les identifiants de routeur qu'il a et dont une autre partition active tient la
        /// cle simple. Integrer deux fois le meme releve rend la meme chose.
        mutating func integrer(_ r: ReleveMaillage) -> Set<Int> {
            let plage = ReleveMaillage.identifiantsRouteur
            var masque: UInt64 = 0
            func noter(_ id: Int) { if plage.contains(id) { masque |= 1 << UInt64(id) } }
            for x in r.routeurs { noter(x.id) }
            tailles[r.partition] = masque.nonzeroBitCount
            for l in r.liens {
                noter(l.a)
                noter(l.b)
            }
            for e in r.enfants { noter(e.parent) }
            for s in r.signaux { noter(s.routeur) }
            if let p = r.parentSonde { noter(p) }
            identifiants[r.partition] = masque
            var collisions: Set<Int> = []
            defer { precedent = (r.partition, collisions) }
            // `actives` est vide hors scission (`ReleveMaillage` le normalise) : aucune collision, aucune tenante.
            guard !r.actives.isEmpty else {
                tenantes = [:]
                return []
            }
            let actives = r.actives.map { (partition: $0, masque: identifiants[$0] ?? 0) }
            for id in plage {
                let bit: UInt64 = 1 << UInt64(id)
                let ont = actives.filter { $0.masque & bit != 0 }.map(\.partition)
                guard ont.count >= 2 else {
                    tenantes[id] = nil
                    continue
                }
                let tenante: String
                if let t = tenantes[id], ont.contains(t) {
                    tenante = t
                } else if let p = precedent, ont.contains(p.partition), !p.collisions.contains(id) {
                    tenante = p.partition
                } else {
                    tenante = ont.min(by: precede) ?? r.partition
                }
                tenantes[id] = tenante
                if tenante != r.partition && masque & bit != 0 { collisions.insert(id) }
            }
            return collisions
        }

        /// Ordre du departage : la plus grande partition d'abord, puis le plus petit identifiant (en hexadecimal, a
        /// defaut en texte).
        func precede(_ a: String, _ b: String) -> Bool {
            let (ta, tb) = (tailles[a] ?? 0, tailles[b] ?? 0)
            if ta != tb { return ta > tb }
            if let na = UInt64(a, radix: 16), let nb = UInt64(b, radix: 16), na != nb { return na < nb }
            return a < b
        }
    }

    /// Les collisions de chaque releve qui en a, par indice.
    private let parReleve: [Int: Set<Int>]
    /// L'etat apres le dernier releve.
    private let fin: Etat

    /// `releves` : du plus ancien au plus recent.
    public init(releves: [ReleveMaillage]) {
        var etat = Etat()
        var parReleve: [Int: Set<Int>] = [:]
        for (i, r) in releves.enumerated() {
            let c = etat.integrer(r)
            if !c.isEmpty { parReleve[i] = c }
        }
        self.parReleve = parReleve
        fin = etat
    }

    /// Identifiants de routeur du releve d'indice `i` dont une autre partition active tient la cle simple ; aucun pour
    /// un releve hors de la liste.
    public func collisions(releve i: Int) -> Set<Int> { parReleve[i] ?? [] }

    /// De meme pour le maillage `m`, evalue apres le dernier releve de la liste avec les partitions `actives` (celles de
    /// son releve, `ReleveMaillage(m, actives:)`) : le maillage d'une tournee, avant que son releve n'entre dans
    /// l'historique, ou deja dedans (meme resultat). Sans historique (demo) : aucun, les autres partitions n'ayant aucun
    /// identifiant connu.
    public func collisions(apres m: Maillage, actives: [String]) -> Set<Int> {
        var e = fin
        return e.integrer(ReleveMaillage(m, actives: actives))
    }
}
