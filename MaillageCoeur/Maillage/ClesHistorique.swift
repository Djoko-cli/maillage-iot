import Foundation

/// Cles des routeurs dans une liste de releves de l'historique (verification du 05/10). La sonde peut perdre puis
/// retrouver l'ExtMac d'un routeur : sans elle, `ReleveMaillage.cle(routeur:)` le range sous "rloc:XXXX", et ses
/// courbes se coupent en deux. Ici, la cle du routeur d'identifiant `id` dans un releve est :
/// - son ExtMac dans ce releve, s'il en a une (celle du premier routeur de cet `id`, comme `cle(routeur:)`) ;
/// - sinon, l'ExtMac du meme `id`, dans la meme partition, au releve suivant le plus proche qui en a une, a 7 jours au
///   plus (`ecartMax`) ; a defaut, au precedent le plus proche, a 7 jours au plus ;
/// - sinon "rloc:XXXX".
///
/// Deux routeurs d'un releve n'ont jamais la meme cle : une ExtMac ainsi trouvee est refusee (la cle reste "rloc")
/// si un autre identifiant du releve, de sa liste ou seulement cite (lien, parent d'un enfant, signal, parent de la
/// sonde), la tient ou la trouve de meme. Un suivant refuse ne laisse pas place au precedent : les indices se
/// contredisent, la courbe ne devine pas. (Seules des donnees non conformes, deux routeurs du releve qui donnent la
/// meme ExtMac, peuvent encore partager une cle.) Un `id` hors de 0...62 rend "rloc:?".
///
/// Calculee une fois pour toute la liste, et non pour la seule periode affichee : un routeur identifie juste apres la
/// fin de la periode compte. Les releves vont du plus ancien au plus recent.
///
/// Cout, pour N releves de R routeurs : la construction est un passage, en O(N R). Une cle coute O(log N) quand le
/// releve tient l'ExtMac ou qu'aucune ne se trouve. Quand elle vient d'un autre releve, la garde parcourt le releve
/// (O(R + C), C identifiants cites) et cherche, en O(log N) chacun, celles des k autres identifiants sans ExtMac dans
/// ce releve : O(R + C + k log N). "rloc:XXXX" n'est forme que s'il est rendu.
public struct ClesHistorique: Sendable {
    /// Ecart le plus grand entre un releve et le releve dont il prend l'ExtMac, dans un sens comme dans l'autre (demande
    /// de Djoko, 05/10) : au-dela, un identifiant repris par un routeur jamais identifie ne prend plus l'historique de
    /// l'appareil parti.
    public static let ecartMax: TimeInterval = 7 * 24 * 3600

    /// Un routeur d'une partition.
    private struct Routeur: Hashable, Sendable {
        let partition: String
        let id: Int
    }

    /// Un releve de la liste ou le routeur a une ExtMac.
    private struct Identifie: Sendable {
        let releve: Int
        let extMac: String
    }

    private let releves: [ReleveMaillage]
    /// Par partition et identifiant : les releves ou le premier routeur de cet identifiant a une ExtMac, par indice
    /// croissant.
    private let identifies: [Routeur: [Identifie]]

    /// `releves` : du plus ancien au plus recent.
    public init(releves: [ReleveMaillage]) {
        var identifies: [Routeur: [Identifie]] = [:]
        for (i, r) in releves.enumerated() {
            // Identifiants deja vus dans ce releve, en masque (0...62 tient dans 64 bits) : seul le premier compte.
            var vus: UInt64 = 0
            for x in r.routeurs where ReleveMaillage.identifiantsRouteur.contains(x.id) {
                let bit: UInt64 = 1 << UInt64(x.id)
                guard vus & bit == 0 else { continue }
                vus |= bit
                guard let e = x.extMac else { continue }
                identifies[Routeur(partition: r.partition, id: x.id), default: []].append(Identifie(releve: i, extMac: e))
            }
        }
        self.releves = releves
        self.identifies = identifies
    }

    private static func rloc(_ id: Int) -> String { String(format: "rloc:%04X", UInt16(id) << 10) }

    /// Cle du routeur `id` au releve d'indice `i` de la liste (voir le type). Fonction totale : un releve hors de la
    /// liste rend "rloc:XXXX".
    public func cle(releve i: Int, routeur id: Int) -> String {
        guard ReleveMaillage.identifiantsRouteur.contains(id) else { return "rloc:?" }
        guard releves.indices.contains(i), let (e, directe) = extMac(releve: i, routeur: id) else { return Self.rloc(id) }
        return directe || !prise(e, releve: i, sauf: id) ? e : Self.rloc(id)
    }

    /// L'ExtMac `e` est tenue ou trouvee par un autre identifiant que `id` au releve `i`, de sa liste ou cite. Un
    /// identifiant qui a son ExtMac dans le releve ne peut prendre qu'elle : elle se compare sans recherche ; seuls les
    /// autres passent par `extMac(releve:routeur:)`. Les identifiants sont en masques de 64 bits (0...62), sans
    /// allocation.
    private func prise(_ e: String, releve i: Int, sauf id: Int) -> Bool {
        let r = releves[i]
        let plage = ReleveMaillage.identifiantsRouteur
        var vus: UInt64 = 1 << UInt64(id)
        var sansExtMac: UInt64 = 0
        for x in r.routeurs where plage.contains(x.id) {
            let bit: UInt64 = 1 << UInt64(x.id)
            guard vus & bit == 0 else { continue }
            vus |= bit
            if let ex = x.extMac {
                if ex == e { return true }
            } else {
                sansExtMac |= bit
            }
        }
        func cite(_ j: Int) {
            guard plage.contains(j) else { return }
            let bit: UInt64 = 1 << UInt64(j)
            if vus & bit == 0 {
                vus |= bit
                sansExtMac |= bit
            }
        }
        for l in r.liens {
            cite(l.a)
            cite(l.b)
        }
        for x in r.enfants { cite(x.parent) }
        for x in r.signaux { cite(x.routeur) }
        if let p = r.parentSonde { cite(p) }
        while sansExtMac != 0 {
            let j = sansExtMac.trailingZeroBitCount
            sansExtMac &= sansExtMac - 1
            if extMac(releve: i, routeur: j)?.extMac == e { return true }
        }
        return false
    }

    /// L'ExtMac du routeur `id` au releve `i`, avant la garde : la sienne (`directe`), sinon celle du suivant, puis du
    /// precedent le plus proche de sa partition, a `ecartMax` au plus ; nil sans aucune.
    private func extMac(releve i: Int, routeur id: Int) -> (extMac: String, directe: Bool)? {
        guard let liste = identifies[Routeur(partition: releves[i].partition, id: id)] else { return nil }
        // Le premier releve de la liste a l'indice `i` ou apres : ce releve lui-meme, ou le suivant le plus proche.
        var bas = 0, haut = liste.count
        while bas < haut {
            let milieu = (bas + haut) / 2
            if liste[milieu].releve < i { bas = milieu + 1 } else { haut = milieu }
        }
        if bas < liste.count, liste[bas].releve == i { return (liste[bas].extMac, true) }
        let date = releves[i].date
        if bas < liste.count, releves[liste[bas].releve].date.timeIntervalSince(date) <= Self.ecartMax {
            return (liste[bas].extMac, false)
        }
        if bas > 0, date.timeIntervalSince(releves[liste[bas - 1].releve].date) <= Self.ecartMax {
            return (liste[bas - 1].extMac, false)
        }
        return nil
    }
}
