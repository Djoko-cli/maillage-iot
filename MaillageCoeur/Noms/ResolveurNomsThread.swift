import Foundation

/// Nom affiche d'un noeud, par priorite : surnom (donne dans l'app) > nom dans
/// Maison (noeud sur la fabrique d'Apple, puis association faite a la main) > nom HomeKit (`_hap._udp`) > hote.
public struct ResolveurNoms: Hashable, Sendable {
    /// Identifiant de noeud (appareil ou instance de routeur) -> surnom.
    public var surnoms: [String: String]
    public var maison: NomsMaison?
    /// Identifiant d'appareil -> `noeudMatter` (16 hexa majuscules) de l'accessoire de Maison que l'utilisateur lui a
    /// associe : pour un appareil qui a perdu son inscription a la fabrique d'Apple, que Maison exporte sous un noeud
    /// que plus personne n'annonce (`Associations`).
    public var associations: [String: String]

    public init(surnoms: [String: String] = [:], maison: NomsMaison? = nil, associations: [String: String] = [:]) {
        self.surnoms = surnoms
        self.maison = maison
        self.associations = associations
    }

    /// Noeud a 0 : accessoire non Matter, il n'identifie personne.
    public static let noeudNul = "0000000000000000"

    /// Fabrique d'Apple : celle dont les noeuds recouvrent le plus de
    /// `noeudMatter` de Maison (au moins un) ; a egalite, la plus petite.
    public func fabriqueApple(appareils: [Appareil]) -> String? {
        let connus = Set(maison?.accessoires.compactMap { $0.noeudMatter?.uppercased() } ?? []).subtracting([Self.noeudNul])
        guard !connus.isEmpty else { return nil }
        var scores: [String: Int] = [:]
        for a in appareils {
            for i in a.instances where connus.contains(i.noeud) { scores[i.fabrique, default: 0] += 1 }
        }
        return scores.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Accessoire de Maison d'un appareil : par son noeud sur la fabrique d'Apple ; sinon, par l'association que
    /// l'utilisateur a faite (`associations`). Un appareil qui retrouve son noeud prend l'accessoire de ce noeud : le
    /// noeud l'emporte, l'association reste sans effet (et gardee, voir `Associations`).
    /// Un pont porte plusieurs accessoires sur un seul noeud : le noeud prend
    /// le nom du pont (du premier par nom s'il y en a plusieurs), sinon du
    /// premier accessoire par nom ; l'ordre du fichier ne compte pas.
    public func accessoire(de a: Appareil, fabriqueApple f: String?) -> AccessoireMaison? {
        if let f, let noeud = a.instances.first(where: { $0.fabrique == f })?.noeud,
           let trouve = accessoire(noeud: noeud) {
            return trouve
        }
        return associations[a.id].flatMap { accessoire(noeud: $0) }
    }

    /// L'accessoire de Maison de ce noeud (hors noeud nul) ; ceux qui le partagent : le pont d'abord, puis le premier
    /// par nom.
    private func accessoire(noeud: String) -> AccessoireMaison? {
        let noeud = noeud.uppercased()
        guard let maison, noeud != Self.noeudNul else { return nil }
        let candidats = maison.accessoires.filter { $0.noeudMatter?.uppercased() == noeud }
        return candidats.filter { $0.pont == true }.min { $0.nom < $1.nom } ?? candidats.min { $0.nom < $1.nom }
    }

    /// Le nom vient d'une association faite a la main : l'appareil n'a pas d'accessoire par son noeud, et son
    /// association en designe un.
    public func associeALaMain(_ a: Appareil, fabriqueApple f: String?) -> Bool {
        guard let n = associations[a.id], accessoire(noeud: n) != nil else { return false }
        if let f, let noeud = a.instances.first(where: { $0.fabrique == f })?.noeud, accessoire(noeud: noeud) != nil {
            return false
        }
        return true
    }

    /// Les accessoires de Maison a proposer pour une association : ceux qui ont un noeud (non nul) qu'aucun des
    /// `appareils` n'annonce sur la fabrique d'Apple, et qu'aucun de ces `appareils` (presents ou disparus) n'a deja
    /// associe (un accessoire qui partage son noeud avec un accessoire deja associe n'est plus propose : le noeud est
    /// pris ; l'association d'un appareil inconnu de `appareils` ne le prend pas). Par noeud, un seul : celui que
    /// `accessoire(noeud:)` rendrait (le pont, sinon le premier par nom), car c'est son nom que l'appareil prendrait.
    /// Sans fabrique d'Apple connue (`f` nil), aucun annonceur n'est connu : rien n'est propose. Par nom, puis par
    /// piece.
    public func orphelins(appareils: [Appareil], fabriqueApple f: String?) -> [AccessoireMaison] {
        guard let maison, let f else { return [] }
        let annonces = Set(appareils.flatMap { $0.instances.filter { $0.fabrique == f }.map(\.noeud) })
        // Seules comptent les associations d'appareils presents ou disparus (`appareils`) : celle d'un appareil que
        // plus personne ne connait ne prend pas l'accessoire.
        let ids = Set(appareils.map(\.id))
        let pris = Set(associations.filter { ids.contains($0.key) }.values.map { $0.uppercased() })
        return maison.accessoires.filter { a in
            guard let noeud = a.noeudMatter?.uppercased(), noeud != Self.noeudNul else { return false }
            return !annonces.contains(noeud) && !pris.contains(noeud) && accessoire(noeud: noeud) == a
        }.sorted { ($0.nom, $0.piece ?? "", $0.noeudMatter ?? "") < ($1.nom, $1.piece ?? "", $1.noeudMatter ?? "") }
    }

    public func nom(appareil a: Appareil, fabriqueApple f: String?) -> String {
        if let s = surnoms[a.id], !s.isEmpty { return s }
        if let m = accessoire(de: a, fabriqueApple: f)?.nom, !m.isEmpty { return m }
        if let h = a.hap?.nom, !h.isEmpty { return h }
        return a.id
    }

    public func nom(routeur r: RouteurBordure) -> String {
        if let s = surnoms[r.instance], !s.isEmpty { return s }
        return r.instance
    }
}
