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
/// scission en cours est la suite des derniers releves qui en ont, marge comprise (plus bas) ; seuls ses releves
/// comptent (relecture finale, Important 1) : un releve d'avant la scission, celui d'une ancienne partition comme celui
/// de la partition de la sonde, ne cree jamais de collision. La moitie de la sonde qui prend un nouvel identifiant de partition en gardant ses
/// identifiants de routeur, ou la transition de Bonjour d'un simple changement d'identifiant, gardent donc les cles
/// simples. La sonde ne voit qu'une partition a la fois : les identifiants de routeur d'une autre partition active sont
/// ceux de son dernier releve de la scission (sa liste des routeurs et les identifiants cites : liens, parents des
/// enfants, signaux, parent de la sonde) ; une partition pas encore vue pendant la scission n'en a aucun. Un identifiant
/// qu'ont deux partitions actives ou plus est en collision et recoit une tenante, qui garde la cle simple jusqu'a la fin
/// de la scission (relecture finale, Critique 1 : un releve sans l'identifiant ne la fait pas oublier, et la cle ne
/// bascule jamais pendant la scission) :
/// 1. parmi les partitions qui avaient l'identifiant avant ce releve (le nouveau venu ne passe jamais devant une
///    partition qui l'avait deja) ;
/// 2. la partition du releve precedent, si elle l'y avait sans y etre qualifiee ;
/// 3. a defaut la plus grande partition (le nombre de routeurs de son dernier releve de la scission) ;
/// 4. puis le plus petit identifiant de partition (en hexadecimal, a defaut en texte).
/// Les autres partitions qui ont cet identifiant sont qualifiees, tant que dure la scission.
///
/// Une tenante dont la partition n'est plus active alors que la scission continue (une scission a trois partitions dont
/// une se resorbe, ou une partition renommee) reste tenante : les partitions actives qui ont cet identifiant restent
/// toutes qualifiees, et aucune ne reprend la cle simple avant la fin de la scission (la donner a l'une d'elles, sans
/// ExtMac pour distinguer les routeurs, les melangerait).
///
/// Marge (decision de Djoko du 20/10 ; les annonces de Bonjour vacillent) : le debut d'une scission est immediat, mais
/// elle ne finit qu'au troisieme releve de suite sans scission (`marge`). Les deux releves d'avant se lisent comme des
/// releves de la scission, avec les partitions actives de son dernier releve : memes tenantes, memes cles qualifiees ;
/// un releve d'une partition qui n'en etait pas n'a aucune collision. Une scission qui revient pendant la marge est la
/// meme scission (meme tenante). Comme la tenante, la marge se deduit des releves de la liste (leurs partitions
/// actives) : rien d'autre n'est garde, et l'historique relu au lancement suivant la reprend la ou elle en etait (un
/// redemarrage ne la remet pas a zero ; elle compte des releves, pas une duree : l'app eteinte ne la fait pas avancer).
/// Au bout de la marge, plus de collision ni de tenante, et rien n'est garde : la partition de la sonde a la cle simple
/// (si c'est l'autre partition qui reste seule, ses routeurs reprennent "rloc:XXXX" ; sans ExtMac rien ne les distingue,
/// comportement d'avant la phase 8).
///
/// Limite connue : la liste est celle de la fenetre de l'historique (30 jours, `Surveillance.dureeHistorique`). Quand
/// le debut d'une scission plus longue en sort, la marche repart d'un releve plus tard, comme au debut d'une scission :
/// la tenante peut alors changer d'une tournee a l'autre, malgre la regle ci-dessus.
///
/// Deterministe : la meme liste donne les memes collisions. Calcule en un passage : O(1) par releve hors scission,
/// O(63 x P) pendant une scission de P partitions.
public struct CollisionsRloc: Sendable {
    /// L'etat apres un releve.
    struct Etat: Sendable {
        /// Par partition : les identifiants de routeur de son dernier releve de la scission en cours, cites compris
        /// (masque, 0...62) ; vide hors scission.
        var identifiants: [String: UInt64] = [:]
        /// Par partition : le nombre de routeurs de la liste de son dernier releve de la scission en cours.
        var tailles: [String: Int] = [:]
        /// Par identifiant de routeur en collision : la partition qui tient la cle simple, jusqu'a la fin de la scission.
        var tenantes: [Int: String] = [:]
        /// Les partitions actives du dernier releve de la scission en cours (celles des releves de la marge) ; vide hors
        /// scission.
        var actives: [String] = []
        /// Le nombre de releves de suite sans scission depuis le dernier releve de la scission en cours (la marge, 0 a
        /// `marge - 1`).
        var sansScission = 0
        /// Le releve precedent (sa date et sa partition) et ses collisions.
        var precedent: (date: Date, partition: String, collisions: Set<Int>)?

        /// Integre le releve `r` ; rend les identifiants de routeur qu'il a et dont une autre partition tient la cle
        /// simple. Le meme releve (meme date, meme partition) integre deux fois de suite rend la meme chose et ne change
        /// rien la seconde fois : il ne compte qu'une fois dans la marge.
        mutating func integrer(_ r: ReleveMaillage) -> Set<Int> {
            if let p = precedent, p.date == r.date, p.partition == r.partition { return p.collisions }
            let plage = ReleveMaillage.identifiantsRouteur
            var masque: UInt64 = 0
            func noter(_ id: Int) { if plage.contains(id) { masque |= 1 << UInt64(id) } }
            for x in r.routeurs { noter(x.id) }
            let taille = masque.nonzeroBitCount
            for l in r.liens {
                noter(l.a)
                noter(l.b)
            }
            for e in r.enfants { noter(e.parent) }
            for s in r.signaux { noter(s.routeur) }
            if let p = r.parentSonde { noter(p) }
            var collisions: Set<Int> = []
            defer { precedent = (r.date, r.partition, collisions) }
            // `r.actives` est vide hors scission (`ReleveMaillage` le normalise). Pendant la marge, le releve se lit comme
            // un releve de la scission, avec les partitions actives du dernier ; au bout de la marge, la scission est
            // finie : aucune collision, et rien n'est garde, ni identifiants ni tenantes (seuls comptent les releves de la
            // scission en cours).
            if !r.actives.isEmpty {
                actives = r.actives
                sansScission = 0
            } else if !actives.isEmpty, sansScission + 1 < CollisionsRloc.marge {
                sansScission += 1
            } else {
                identifiants = [:]
                tailles = [:]
                tenantes = [:]
                actives = []
                sansScission = 0
                return []
            }
            // Un releve de marge d'une partition qui n'etait pas de la scission : aucune collision, rien n'est garde.
            guard actives.contains(r.partition) else { return [] }
            // Les identifiants de la partition du releve avant lui, pendant la scission (le nouveau venu, regle 1).
            let avant = identifiants[r.partition] ?? 0
            identifiants[r.partition] = masque
            tailles[r.partition] = taille
            let masques = actives.map { (partition: $0, masque: identifiants[$0] ?? 0) }
            for id in plage {
                let bit: UInt64 = 1 << UInt64(id)
                if tenantes[id] == nil {
                    let ont = masques.filter { $0.masque & bit != 0 }.map(\.partition)
                    if ont.count >= 2 {
                        // Les autres partitions l'avaient a leur dernier releve, d'avant celui-ci.
                        let avaient = ont.filter { $0 != r.partition || avant & bit != 0 }
                        if let p = precedent, avaient.contains(p.partition), !p.collisions.contains(id) {
                            tenantes[id] = p.partition
                        } else {
                            tenantes[id] = avaient.min(by: precede)
                        }
                    }
                }
                if let t = tenantes[id], t != r.partition, masque & bit != 0 { collisions.insert(id) }
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

    /// Le nombre de releves de suite sans scission qui finit une scission (decision de Djoko du 20/10) : les releves
    /// d'avant, la marge, restent dans la scission.
    static let marge = 3

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
