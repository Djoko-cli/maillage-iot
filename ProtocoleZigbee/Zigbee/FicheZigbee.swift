import Foundation
import MaillageCoeur

/// Le contenu propre a Zigbee des colonnes de la fiche (etape 5, section 2), tire du maillage de la sonde.
public enum FicheZigbee {
    /// Les voisins entendus d'un noeud : ses liens radio reunis par paire, chacun avec sa qualite (la moins bonne des
    /// deux mesures) et le LQI de chaque sens (le noeud, puis le voisin) ; dans l'ordre du maillage. Vide pour un noeud
    /// d'un autre protocole ; le maillage Zigbee est lu par `id.cle`, ses voisins ressortent en `IdNoeud` Zigbee.
    public static func voisins(de id: IdNoeud, maillage m: MaillageZigbee) -> [VoisinFiche] {
        guard id.protocole == .zigbee else { return [] }
        let cle = id.cle
        return MaillageZigbee.reunir(m.liens(de: cle)).compactMap { l in
            guard let autre = l.autre(que: cle) else { return nil }
            return VoisinFiche(id: IdNoeud(.zigbee, autre), qualite: l.qualite, lqiIci: l.a == cle ? l.lqiA : l.lqiB,
                               lqiLa: l.a == cle ? l.lqiB : l.lqiA)
        }
    }

    /// Les dependants d'un noeud : les routeurs dont le chemin vers le pont passe directement par lui (avec la qualite
    /// de leur lien radio, s'il est dans les tables), et les appareils dont il est le parent (avec la qualite que le
    /// parent mesure ; aucune pour un parent d'avant, perimee).
    public static func dependants(de id: IdNoeud, maillage m: MaillageZigbee) -> [DependantFiche] {
        guard id.protocole == .zigbee else { return [] }
        let cle = id.cle
        let routeurs = m.chemins.filter { $0.prochain == cle && $0.routeur != cle }.map {
            DependantFiche(id: IdNoeud(.zigbee, $0.routeur), qualite: m.lien(entre: $0.routeur, et: cle)?.qualite,
                           routeur: true)
        }
        let enfants = m.enfants(de: cle).map {
            DependantFiche(id: IdNoeud(.zigbee, $0.enfant), qualite: $0.dAvant ? nil : $0.qualite, routeur: false)
        }
        return routeurs + enfants
    }

    /// Les routeurs qui parlent directement au pont : ceux dont le prochain saut est le coordinateur.
    public static func routeursDirects(_ m: MaillageZigbee) -> Int {
        guard let pont = m.coordinateur?.ieee else { return 0 }
        return m.chemins.count { $0.prochain == pont }
    }

    /// La date des qualites des liens : celle des tables de voisins d'ou elles viennent (une tournee sur quatre), sinon
    /// celle du maillage.
    public static func dateQualites(_ m: MaillageZigbee) -> Date { m.dateTables ?? m.date }
}
