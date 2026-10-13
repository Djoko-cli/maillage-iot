import Foundation

/// Cle d'une partition : son reseau et son identifiant.
struct ClePartition: Hashable, Sendable {
    let reseau: String
    let partition: String
}

/// Appareil en cours de construction (instances regroupees par hote).
private struct Brouillon {
    var hote: String?
    var services: [String] = []
    var instances: [InstanceMatter] = []
    var proprietes: ProprietesMatter?
    var hap: AccessoireHAP?
}

/// Place d'un appareil d'apres ses adresses.
private struct Place {
    var genre: GenreAppareil
    var cle: ClePartition?
    var prefixe: PrefixeIPv6?
}

extension Instantane {
    /// Calcule l'instantane a partir des annonces : routeurs groupes en
    /// reseaux (`xp`) et partitions (`pt`), prefixes OMR attribues, appareils places.
    ///
    /// Prefixe OMR -> partition. Chaque partition qui le revendique compte : par
    /// le champ `omr` d'un de ses routeurs, ou par une route du Mac dont la
    /// passerelle est une adresse lien-local d'un de ses routeurs. Une seule : il
    /// est a elle. Plusieurs : il est partage (`Partition.prefixesPartages`, sur
    /// chacune) et va a celle qui a le plus de routeurs de bordure, puis a celle
    /// qui a un chef connu, puis au plus petit identifiant. Enfin, par
    /// elimination, si un seul reseau est visible : il n'a qu'une partition, ou
    /// une seule de ses partitions n'a pas de prefixe et un seul prefixe reste.
    /// Sinon le prefixe reste sans partition (ses appareils : etat inconnu).
    /// Les prefixes du reseau local (interfaces du Mac, prefixe tire de `xp`) ne
    /// sont jamais des prefixes OMR.
    public init(annonces a: Annonces) {
        let routeurs = a.routeurs.map { RouteurBordure(annonce: $0, adresses: a.adresses(de: $0.hote)) }
        let cleDe: (RouteurBordure) -> ClePartition = {
            ClePartition(reseau: $0.idReseau ?? "nn:" + ($0.nomReseau ?? $0.instance), partition: $0.partition ?? "?")
        }
        var locaux = Set(a.prefixesLocaux.compactMap { PrefixeIPv6($0) })
        locaux.formUnion(routeurs.compactMap(\.prefixeReseauLocal))

        // 1. Prefixes OMR : toutes les revendications (champ omr, routes du Mac),
        //    puis une partition par prefixe ; revendique par plusieurs, il est partage.
        var revendications: [PrefixeIPv6: Set<ClePartition>] = [:]
        for r in routeurs {
            if let p = r.prefixeOMR { revendications[p, default: []].insert(cleDe(r)) }
        }
        var parLien: [AdresseIPv6: RouteurBordure] = [:]
        for r in routeurs {
            for l in r.adressesLien where parLien[l] == nil { parLien[l] = r }
        }
        for route in a.routes {
            guard let p = PrefixeIPv6(route.prefixe), !locaux.contains(p),
                  let g = route.passerelle.flatMap({ AdresseIPv6($0) }), let r = parLien[g] else { continue }
            revendications[p, default: []].insert(cleDe(r))
        }
        let routeursDe = Dictionary(grouping: routeurs, by: cleDe)
        // Preferee : le plus de routeurs de bordure, puis un chef connu, puis le plus petit identifiant.
        func avant(_ c1: ClePartition, _ c2: ClePartition) -> Bool {
            let n1 = routeursDe[c1]?.count ?? 0
            let n2 = routeursDe[c2]?.count ?? 0
            if n1 != n2 { return n1 > n2 }
            let chef1 = routeursDe[c1]?.contains { $0.role == .chef } ?? false
            let chef2 = routeursDe[c2]?.contains { $0.role == .chef } ?? false
            if chef1 != chef2 { return chef1 }
            return (c1.partition, c1.reseau) < (c2.partition, c2.reseau)
        }
        var attribution: [PrefixeIPv6: ClePartition] = [:]
        var partages: [ClePartition: [PrefixeIPv6]] = [:]
        for (p, cles) in revendications {
            attribution[p] = cles.min(by: avant)
            if cles.count > 1 {
                for c in cles { partages[c, default: []].append(p) }
            }
        }

        // 2. Appareils : instances Matter et accessoires HAP regroupes par hote.
        var brouillons: [String: Brouillon] = [:]
        for s in a.matter {
            let id = Self.idAppareil(hote: s.hote, instance: s.instance)
            var b = brouillons[id] ?? Brouillon(hote: s.hote)
            b.services.append(s.instance)
            if let i = InstanceMatter(instance: s.instance) { b.instances.append(i) }
            let p = ProprietesMatter(txt: s.txt)
            if b.proprietes == nil || (b.proprietes?.endormi == false && p.endormi) { b.proprietes = p }
            brouillons[id] = b
        }
        for s in a.hap {
            let id = Self.idAppareil(hote: s.hote, instance: s.instance)
            var b = brouillons[id] ?? Brouillon(hote: s.hote)
            b.hap = AccessoireHAP(annonce: s)
            brouillons[id] = b
        }
        let adressesDe: [String: [String]] = brouillons.mapValues { a.adresses(de: $0.hote) }

        // 3. Elimination, pour les prefixes des appareils restes sans partition.
        var restants = Set(adressesDe.values.joined().compactMap { AdresseIPv6($0) }
            .filter { !$0.estLienLocal }.map(\.prefixe))
            .subtracting(locaux).filter { attribution[$0] == nil }
        let partitions = Set(routeurs.map(cleDe))
        if Set(partitions.map(\.reseau)).count == 1 && !restants.isEmpty {
            let sansPrefixe = partitions.subtracting(Set(attribution.values))
            if partitions.count == 1, let seule = partitions.first {
                for p in restants { attribution[p] = seule }
                restants = []
            } else if sansPrefixe.count == 1, restants.count == 1,
                      let cle = sansPrefixe.first, let p = restants.first {
                attribution[p] = cle
                restants = []
            }
        }

        // 4. Place de chaque appareil.
        var places: [String: Place] = [:]
        for id in brouillons.keys {
            let textes = adressesDe[id] ?? []
            let v6 = textes.compactMap { AdresseIPv6($0) }
            let horsLien = v6.filter { !$0.estLienLocal }
            let v4 = textes.filter { AdresseIPv6.estIPv4($0) }
            if let ad = horsLien.first(where: { attribution[$0.prefixe] != nil }) {
                places[id] = Place(genre: .thread, cle: attribution[ad.prefixe], prefixe: ad.prefixe)
            } else if let ad = horsLien.first(where: { restants.contains($0.prefixe) }) {
                places[id] = Place(genre: .thread, cle: nil, prefixe: ad.prefixe)
            } else if !v6.isEmpty || !v4.isEmpty {
                places[id] = Place(genre: .ip, cle: nil, prefixe: nil)
            } else {
                places[id] = Place(genre: .sansAdresse, cle: nil, prefixe: nil)
            }
        }

        // 5. Reseaux et partitions ; la principale : le plus de noeuds (routeurs
        //    et appareils), puis un chef connu, puis l'identifiant.
        var reseaux: [Reseau] = []
        var principales = Set<ClePartition>()
        for (idReseau, duReseau) in Dictionary(grouping: routeurs, by: { cleDe($0).reseau }) {
            var groupes: [(cle: ClePartition, routeurs: [RouteurBordure], appareils: [String])] = []
            for rs in Dictionary(grouping: duReseau, by: { cleDe($0).partition }).values {
                let cle = cleDe(rs[0])
                let apps = places.filter { $0.value.cle == cle }.map(\.key).sorted()
                groupes.append((cle, Self.ordonner(rs), apps))
            }
            groupes.sort { g1, g2 in
                let n1 = g1.routeurs.count + g1.appareils.count
                let n2 = g2.routeurs.count + g2.appareils.count
                if n1 != n2 { return n1 > n2 }
                let c1 = g1.routeurs.contains { $0.role == .chef }
                let c2 = g2.routeurs.contains { $0.role == .chef }
                if c1 != c2 { return c1 }
                return g1.cle.partition < g2.cle.partition
            }
            if let p = groupes.first?.cle { principales.insert(p) }
            let parts = groupes.enumerated().map { i, g in
                Partition(id: g.cle.partition, routeurs: g.routeurs,
                          prefixes: attribution.filter { $0.value == g.cle }.map(\.key).sorted(),
                          prefixesPartages: (partages[g.cle] ?? []).sorted(),
                          appareils: g.appareils, estPrincipale: i == 0)
            }
            reseaux.append(Reseau(id: idReseau, nom: duReseau.compactMap(\.nomReseau).first ?? idReseau,
                                  partitions: parts, prefixeLocal: duReseau.compactMap(\.prefixeReseauLocal).first))
        }
        reseaux.sort { ($0.nom, $0.id) < ($1.nom, $1.id) }

        // 6. Appareils.
        var threads: [Appareil] = []
        var ips: [Appareil] = []
        for (id, b) in brouillons {
            let place = places[id] ?? Place(genre: .sansAdresse, cle: nil, prefixe: nil)
            let textes = adressesDe[id] ?? []
            let etat: EtatAppareil
            switch place.genre {
            case .sansAdresse: etat = .sansAdresse
            case .ip: etat = .joignable
            case .thread:
                if let cle = place.cle {
                    etat = principales.contains(cle) ? .joignable : .partitionCoupee
                } else {
                    etat = .inconnu
                }
            }
            let appareil = Appareil(
                id: id, hote: b.hote, instances: b.instances.sorted(), servicesMatter: b.services.sorted(),
                proprietes: b.proprietes, hap: b.hap,
                adresses: Array(Set(textes.compactMap { AdresseIPv6($0) }.filter { !$0.estLienLocal })).sorted(),
                adressesIPv4: textes.filter { AdresseIPv6.estIPv4($0) }.sorted(),
                genre: place.genre, idReseau: place.cle?.reseau, partition: place.cle?.partition,
                prefixe: place.prefixe, etat: etat)
            if place.genre == .ip { ips.append(appareil) } else { threads.append(appareil) }
        }

        date = a.date
        self.reseaux = reseaux
        appareils = threads.sorted { $0.id < $1.id }
        appareilsIP = ips.sorted { $0.id < $1.id }
        prefixesSansPartition = restants.sorted()
        trel = Set(a.trel.compactMap { $0.txt["xa"].flatMap { $0.count == 8 ? $0.hexa : nil } })
    }

    /// Centre d'abord (chef, sinon BBR primaire, sinon le premier par nom), puis par nom.
    static func ordonner(_ rs: [RouteurBordure]) -> [RouteurBordure] {
        let tries = rs.sorted { $0.instance < $1.instance }
        guard let centre = tries.first(where: { $0.role == .chef })
                ?? tries.first(where: { $0.etat?.bbrPrimaire == true }) ?? tries.first else { return [] }
        return [centre] + tries.filter { $0.instance != centre.instance }
    }

    /// Identifiant d'un appareil : son hote sans ".local" ni point final.
    static func idAppareil(hote: String?, instance: String) -> String {
        guard var h = hote, !h.isEmpty else { return "instance:" + instance }
        if h.hasSuffix(".") { h.removeLast() }
        if h.lowercased().hasSuffix(".local") { h.removeLast(6) }
        return h
    }
}
