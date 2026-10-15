import Foundation
import MaillageCoeur

/// Construction du graphe d'un reseau Thread : le coeur ne connait que `init(noeuds:liens:)`.
public extension GrapheReseau {
    init(reseau: Reseau, appareils: [AppareilAffiche], maillage: MaillageAffiche? = nil) {
        // Les appareils d'un autre protocole ne sont pas des noeuds de Thread : leur cle y serait prise pour une cle de Thread.
        let appareils = appareils.filter { $0.id.protocole == .thread }
        var noeuds: [Noeud] = []
        var liens: [Lien] = []
        let connues = Set(reseau.partitions.map(\.id))
        let parPartition = Dictionary(grouping: appareils) { a in
            a.partition.flatMap { connues.contains($0) ? $0 : nil } ?? ""
        }
        // La cle Thread d'un appareil : l'etat interne de Thread (maillage, sonde) reste en texte, indexe par cle ;
        // seul le noeud qui sort du graphe porte le protocole (`IdNoeud(.thread, ...)`).
        func tries(_ l: [AppareilAffiche]) -> [AppareilAffiche] { l.sorted { $0.id.cle < $1.id.cle } }
        func idThread(_ cle: String) -> IdNoeud { IdNoeud(.thread, cle) }
        // ExtMac d'un noeud : celle que lui connait la sonde, sinon `autre` (le `xa` d'une annonce, le
        // nom d'hote d'un appareil Matter).
        func ext(_ cle: String, _ autre: String? = nil) -> String? { maillage?.extMacs[cle] ?? autre }
        for p in reseau.partitions {
            guard let centre = p.routeurs.first else { continue }
            let sonde = maillage.flatMap { $0.partition == p.id ? $0 : nil }
            var ids: [IdNoeud] = []
            func ajouter(_ n: Noeud) {
                noeuds.append(n)
                ids.append(n.id)
            }
            ajouter(Noeud(id: idThread(centre.instance), genre: .centre, partition: p.id, routeur: true, bordure: true,
                          inconnu: false, extMac: ext(centre.instance, centre.adresseEtendue)))
            for r in p.routeurs.dropFirst() where sonde?.annoncesCandidates.contains(r.instance) != true {
                ajouter(Noeud(id: idThread(r.instance), genre: .routeur, partition: p.id, routeur: true, bordure: true,
                              inconnu: false, extMac: ext(r.instance, r.adresseEtendue)))
            }
            let routeursSonde = sonde?.idsRouteurs ?? []
            for a in tries(parPartition[p.id] ?? []) {
                ajouter(Noeud(id: idThread(a.id.cle), genre: .appareil, partition: p.id,
                              routeur: routeursSonde.contains(a.id.cle), bordure: false, inconnu: false,
                              extMac: ext(a.id.cle, Self.extMac(hote: a.id.cle))))
            }
            for n in sonde?.inconnus ?? [] {
                ajouter(Noeud(id: idThread(n.id), genre: n.genre == .routeur ? .routeur : .appareil, partition: p.id,
                              routeur: n.genre == .routeur, bordure: n.bordure, inconnu: true, extMac: ext(n.id)))
            }
            // Liens de la sonde entre noeuds de la partition ; le rattachement au centre pour les autres.
            let presents = Set(ids)
            var relies: Set<IdNoeud> = [idThread(centre.instance)]
            for l in sonde?.liens ?? [] where presents.contains(idThread(l.de)) && presents.contains(idThread(l.vers)) {
                liens.append(Lien(de: idThread(l.de), vers: idThread(l.vers), genre: l.genre == .radio ? .radio : .parent,
                                  qualite: l.qualite))
                relies.insert(idThread(l.de))
                relies.insert(idThread(l.vers))
            }
            for id in ids where !relies.contains(id) {
                liens.append(Lien(de: id, vers: idThread(centre.instance)))
            }
        }
        for a in tries(parPartition[""] ?? []) {
            noeuds.append(Noeud(id: idThread(a.id.cle), genre: .appareil, partition: "", routeur: false, bordure: false,
                                inconnu: false, extMac: ext(a.id.cle, Self.extMac(hote: a.id.cle))))
        }
        self.init(noeuds: noeuds, liens: liens)
    }

    /// ExtMac d'un appareil d'apres son nom d'hote : un appareil Matter sur Thread s'annonce sous son
    /// ExtMac, 16 hexa (« 56B1E064401F74EF »), rendue en majuscules ; nil pour un autre nom.
    static func extMac(hote: String) -> String? {
        hote.count == 16 && hote.allSatisfy { $0.isASCII && $0.isHexDigit } ? hote.uppercased() : nil
    }
}
