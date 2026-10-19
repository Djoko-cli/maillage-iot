import Foundation
import MaillageCoeur

/// Cles "rloc:" des noeuds Thread que seule la sonde connait (phase 8, decision de Djoko du 20/10). Deux partitions
/// peuvent avoir le meme RLOC16 : ce sont deux routeurs (les identifiants de routeur sont redistribues d'une
/// partition a l'autre). La cle reste "rloc:XXXX" tant qu'une seule partition a cet identifiant de routeur ; pendant
/// une collision seulement, les noeuds des autres partitions prennent "rloc:<partition>:XXXX" (`CollisionsRloc` dit
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

/// Collisions de RLOC16 entre partitions, d'apres les releves de l'historique (du plus ancien au plus recent) : la
/// sonde ne voit qu'une partition a la fois, l'historique dit lesquelles ont eu chaque identifiant de routeur.
///
/// Une partition a un identifiant de routeur tant que son dernier releve qui l'a dans sa liste des routeurs date de
/// `duree` au plus (avec ou sans ExtMac : la cle de repli d'un noeud de la scene ne depend pas de son ExtMac). Un
/// identifiant qu'ont deux partitions ou plus est en collision : la cle simple reste a la partition qui la tenait au
/// releve precedent ; si elle ne l'a plus, elle va a la plus grande (le nombre de routeurs de son dernier releve), puis
/// au plus petit identifiant de partition (en hexadecimal). Les autres sont qualifiees. Quand une seule partition a
/// l'identifiant, la collision est finie : elle tient la cle simple, qualifiee jusque-la ou non.
///
/// Deterministe : la meme liste donne les memes collisions. Seule limite : la liste commence 30 jours en arriere ;
/// une collision ou les deux partitions reviennent sans cesse pendant plus de 30 jours peut changer de tenante quand
/// le debut de la liste glisse au-dela du premier releve de l'ancienne. Calcule en un passage, en O(N x 63 x P) pour
/// N releves et P partitions vues en `duree`, sans tri tant que la tenante reste.
public struct CollisionsRloc: Sendable {
    /// Duree pendant laquelle une partition garde un identifiant apres son dernier releve : 30 jours, l'historique
    /// garde en memoire et la plus longue periode des courbes. Une cle ne montre ainsi jamais, dans une courbe, deux
    /// routeurs de partitions differentes.
    public static let duree: TimeInterval = PeriodeCourbes.mois.duree

    /// L'etat apres un releve.
    struct Etat: Sendable {
        /// Par identifiant de routeur : la date du dernier releve de chaque partition qui l'a dans sa liste.
        var vus: [Int: [String: Date]] = [:]
        /// Nombre de routeurs de chaque partition, a son dernier releve.
        var tailles: [String: Int] = [:]
        /// Par identifiant de routeur : la partition qui tient la cle simple.
        var tenantes: [Int: String] = [:]

        /// Integre le releve de la partition `partition`, date `date`, dont la liste des routeurs a les identifiants
        /// `routeurs` ; rend les identifiants dont une autre partition tient la cle simple, a ce releve. Integrer deux
        /// fois le meme releve rend la meme chose.
        mutating func integrer(partition: String, date: Date, routeurs: [Int]) -> Set<Int> {
            let ids = Set(routeurs.filter(ReleveMaillage.identifiantsRouteur.contains))
            tailles[partition] = ids.count
            for id in ids { vus[id, default: [:]][partition] = date }
            var collisions: Set<Int> = []
            for (id, parts) in vus {
                let vivantes = parts.allSatisfy { date.timeIntervalSince($0.value) <= CollisionsRloc.duree }
                    ? parts : parts.filter { date.timeIntervalSince($0.value) <= CollisionsRloc.duree }
                guard !vivantes.isEmpty else {
                    vus[id] = nil
                    tenantes[id] = nil
                    continue
                }
                if vivantes.count != parts.count { vus[id] = vivantes }
                let tenante: String
                if let t = tenantes[id], vivantes[t] != nil {
                    tenante = t
                } else {
                    tenante = vivantes.keys.min(by: precede) ?? partition
                    tenantes[id] = tenante
                }
                if tenante != partition { collisions.insert(id) }
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
            let c = etat.integrer(partition: r.partition, date: r.date, routeurs: r.routeurs.map(\.id))
            if !c.isEmpty { parReleve[i] = c }
        }
        self.parReleve = parReleve
        fin = etat
    }

    /// Identifiants de routeur du releve d'indice `i` dont une autre partition tient la cle simple ; aucun pour un
    /// releve hors de la liste.
    public func collisions(releve i: Int) -> Set<Int> { parReleve[i] ?? [] }

    /// De meme pour le maillage `m`, evalue apres le dernier releve de la liste : le maillage d'une tournee, avant que
    /// son releve n'entre dans l'historique, ou deja dedans (meme resultat). Sans historique (demo) : aucun.
    public func collisions(apres m: Maillage) -> Set<Int> {
        var e = fin
        return e.integrer(partition: m.partition, date: m.date, routeurs: m.routeurs.map(\.id))
    }
}
