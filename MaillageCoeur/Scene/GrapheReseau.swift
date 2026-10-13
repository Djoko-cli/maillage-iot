import Foundation

/// Etat d'un appareil tel que la vue le montre.
public enum EtatAffiche: String, Hashable, Sendable {
    case joignable, partitionCoupee, sansAdresse, disparu, inconnu
}

/// Appareil a dessiner : nom deja choisi, partition courante ou derniere connue.
public struct AppareilAffiche: Hashable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var piece: String?
    public var partition: String?
    public var etat: EtatAffiche
    public var endormi: Bool
    /// Batterie selon Maison, pour un appareil qui en a une.
    public var batterie: BatterieMaison?
    /// Joignable parce que la sonde l'a trouve, alors qu'il n'annonce plus d'adresse : la carte l'entoure d'un anneau.
    public var verifie: Bool

    public init(id: String, nom: String, piece: String? = nil, partition: String?, etat: EtatAffiche,
                endormi: Bool = false, batterie: BatterieMaison? = nil, verifie: Bool = false) {
        self.id = id
        self.nom = nom
        self.piece = piece
        self.partition = partition
        self.etat = etat
        self.endormi = endormi
        self.batterie = batterie
        self.verifie = verifie
    }
}

/// Noeuds et liens d'un reseau, tels que la vue les montre, sans geometrie (spec de la vue par
/// pieces, section 2.3). Par partition : son centre (chef, sinon BBR primaire), ses autres routeurs
/// de bordure, ses appareils. Avec la sonde, dans sa partition : les routeurs et les enfants
/// qu'elle seule connait, et ses liens (radio entre routeurs, enfant vers parent) ; un noeud sans
/// lien connu est rattache au centre de sa partition (rattachement suppose, pas un lien radio).
/// Les appareils sans partition connue n'ont pas de lien.
///
/// Un seul noeud par routeur : l'annonce candidate d'un routeur de bordure non identifie n'est
/// pas un noeud a part, ce routeur la porte (`MaillageAffiche.annoncesCandidates`) ; le centre
/// reste le centre, candidat ou non. Ordre des noeuds : partition par partition, le centre, les
/// autres routeurs de bordure (ordre de la partition), les appareils par identifiant, puis les
/// inconnus de la sonde (routeurs, enfants, par RLOC16) ; les appareils sans partition a la fin.
public struct GrapheReseau: Hashable, Sendable {
    public enum Genre: String, Hashable, Sendable {
        /// Centre d'une partition : son premier routeur de bordure (chef, sinon BBR primaire).
        case centre
        /// Autre routeur de bordure, ou routeur que seule la sonde connait.
        case routeur
        /// Appareil (Matter, HomeKit), ou enfant que seule la sonde connait.
        case appareil
    }

    public struct Noeud: Hashable, Sendable, Identifiable {
        public var id: String
        public var genre: Genre
        /// Partition ; "" : sans partition connue.
        public var partition: String
        /// Route : routeur de bordure, routeur de la sonde, appareil qui route.
        public var routeur: Bool
        /// Routeur de bordure : annonce, ou routeur de bordure que seule la sonde connait.
        public var bordure: Bool
        /// Connu de la sonde seule ("rloc:...").
        public var inconnu: Bool
        /// ExtMac connue (16 hexa majuscules) : celle que lui connait la sonde, sinon le `xa` de l'annonce
        /// d'un routeur de bordure, ou le nom d'hote d'un appareil Matter, qui est son ExtMac ; nil si
        /// elle n'est pas connue. La cle de son choix de piece (precision 27).
        public var extMac: String?

        public init(id: String, genre: Genre, partition: String, routeur: Bool, bordure: Bool, inconnu: Bool,
                    extMac: String? = nil) {
            self.id = id
            self.genre = genre
            self.partition = partition
            self.routeur = routeur
            self.bordure = bordure
            self.inconnu = inconnu
            self.extMac = extMac
        }
    }

    public struct Lien: Hashable, Sendable {
        public enum Genre: String, Hashable, Sendable {
            /// Vers le centre de la partition : rattachement suppose, pas un lien radio.
            case rattachement
            /// Lien radio entre deux routeurs, vu par la sonde.
            case radio
            /// De l'enfant vers son parent, vu par la sonde.
            case parent
        }

        public var de: String
        public var vers: String
        public var genre: Genre
        /// De 0 a 3 ; nil : inconnue.
        public var qualite: Int?

        public init(de: String, vers: String, genre: Genre = .rattachement, qualite: Int? = nil) {
            self.de = de
            self.vers = vers
            self.genre = genre
            self.qualite = qualite
        }
    }

    public private(set) var noeuds: [Noeud] = []
    public private(set) var liens: [Lien] = []

    public init(reseau: Reseau, appareils: [AppareilAffiche], maillage: MaillageAffiche? = nil) {
        let connues = Set(reseau.partitions.map(\.id))
        let parPartition = Dictionary(grouping: appareils) { a in
            a.partition.flatMap { connues.contains($0) ? $0 : nil } ?? ""
        }
        func tries(_ l: [AppareilAffiche]) -> [AppareilAffiche] { l.sorted { $0.id < $1.id } }
        // ExtMac d'un noeud : celle que lui connait la sonde, sinon `autre` (le `xa` d'une annonce, le
        // nom d'hote d'un appareil Matter).
        func ext(_ id: String, _ autre: String? = nil) -> String? { maillage?.extMacs[id] ?? autre }
        for p in reseau.partitions {
            guard let centre = p.routeurs.first else { continue }
            let sonde = maillage.flatMap { $0.partition == p.id ? $0 : nil }
            var ids: [String] = []
            func ajouter(_ n: Noeud) {
                noeuds.append(n)
                ids.append(n.id)
            }
            ajouter(Noeud(id: centre.instance, genre: .centre, partition: p.id, routeur: true, bordure: true,
                          inconnu: false, extMac: ext(centre.instance, centre.adresseEtendue)))
            for r in p.routeurs.dropFirst() where sonde?.annoncesCandidates.contains(r.instance) != true {
                ajouter(Noeud(id: r.instance, genre: .routeur, partition: p.id, routeur: true, bordure: true,
                              inconnu: false, extMac: ext(r.instance, r.adresseEtendue)))
            }
            let routeursSonde = sonde?.idsRouteurs ?? []
            for a in tries(parPartition[p.id] ?? []) {
                ajouter(Noeud(id: a.id, genre: .appareil, partition: p.id, routeur: routeursSonde.contains(a.id),
                              bordure: false, inconnu: false, extMac: ext(a.id, Self.extMac(hote: a.id))))
            }
            for n in sonde?.inconnus ?? [] {
                ajouter(Noeud(id: n.id, genre: n.genre == .routeur ? .routeur : .appareil, partition: p.id,
                              routeur: n.genre == .routeur, bordure: n.bordure, inconnu: true, extMac: ext(n.id)))
            }
            // Liens de la sonde entre noeuds de la partition ; le rattachement au centre pour les autres.
            let presents = Set(ids)
            var relies: Set<String> = [centre.instance]
            for l in sonde?.liens ?? [] where presents.contains(l.de) && presents.contains(l.vers) {
                liens.append(Lien(de: l.de, vers: l.vers, genre: l.genre == .radio ? .radio : .parent,
                                  qualite: l.qualite))
                relies.insert(l.de)
                relies.insert(l.vers)
            }
            for id in ids where !relies.contains(id) {
                liens.append(Lien(de: id, vers: centre.instance))
            }
        }
        for a in tries(parPartition[""] ?? []) {
            noeuds.append(Noeud(id: a.id, genre: .appareil, partition: "", routeur: false, bordure: false,
                                inconnu: false, extMac: ext(a.id, Self.extMac(hote: a.id))))
        }
    }

    public func noeud(_ id: String) -> Noeud? { noeuds.first { $0.id == id } }

    /// ExtMac d'un appareil d'apres son nom d'hote : un appareil Matter sur Thread s'annonce sous son
    /// ExtMac, 16 hexa (« 56B1E064401F74EF »), rendue en majuscules ; nil pour un autre nom.
    public static func extMac(hote: String) -> String? {
        hote.count == 16 && hote.allSatisfy { $0.isASCII && $0.isHexDigit } ? hote.uppercased() : nil
    }

    /// Parent d'un noeud vu par la sonde (lien enfant-parent) ; nil sinon.
    public func parent(de id: String) -> String? {
        liens.first { $0.genre == .parent && $0.de == id }?.vers
    }
}
