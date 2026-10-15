import Foundation

/// Etat d'un appareil tel que la vue le montre.
public enum EtatAffiche: String, Hashable, Sendable {
    case joignable, partitionCoupee, sansAdresse
    /// Le pont (Zigbee) le dit injoignable : l'equivalent, pour un protocole a pont, de `sansAdresse`.
    case injoignable
    case disparu, inconnu
}

/// Appareil a dessiner : nom deja choisi, partition courante ou derniere connue.
public struct AppareilAffiche: Hashable, Sendable, Identifiable {
    public var id: IdNoeud
    public var nom: String
    public var piece: String?
    public var partition: String?
    public var etat: EtatAffiche
    public var endormi: Bool
    /// Batterie selon Maison, pour un appareil qui en a une.
    public var batterie: BatterieMaison?
    /// Joignable parce que la sonde l'a trouve, alors qu'il n'annonce plus d'adresse : la carte l'entoure d'un anneau.
    public var verifie: Bool

    public init(id: IdNoeud, nom: String, piece: String? = nil, partition: String? = nil, etat: EtatAffiche,
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
        public var id: IdNoeud
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

        public init(id: IdNoeud, genre: Genre, partition: String, routeur: Bool, bordure: Bool, inconnu: Bool,
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
            /// D'un routeur vers son prochain saut vers le pont (sa route « plusieurs vers un »), vu par le pont.
            case chemin
        }

        public var de: IdNoeud
        public var vers: IdNoeud
        public var genre: Genre
        /// De 0 a 3 ; nil : inconnue.
        public var qualite: Int?
        /// Suppose, faute de mieux : un chemin sans route active, ou le lien vers le parent d'avant d'un appareil
        /// absent des dernieres tables. Le trace est en pointilles.
        public var suppose: Bool

        public init(de: IdNoeud, vers: IdNoeud, genre: Genre = .rattachement, qualite: Int? = nil, suppose: Bool = false) {
            self.de = de
            self.vers = vers
            self.genre = genre
            self.qualite = qualite
            self.suppose = suppose
        }
    }

    public private(set) var noeuds: [Noeud] = []
    public private(set) var liens: [Lien] = []

    /// Graphe donne tel quel : la construction propre a un protocole (ProtocoleThread : `init(reseau:appareils:maillage:)`)
    /// delegue ici, et les tests du coeur s'en servent sans aucun type de protocole. Un lien dont un bout n'est pas
    /// un noeud est ignore.
    public init(noeuds: [Noeud], liens: [Lien] = []) {
        self.noeuds = noeuds
        let ids = Set(noeuds.map(\.id))
        self.liens = liens.filter { ids.contains($0.de) && ids.contains($0.vers) }
    }

    public func noeud(_ id: IdNoeud) -> Noeud? { noeuds.first { $0.id == id } }

    /// Le chemin d'un routeur vers le pont : son premier lien `chemin` (vers son prochain saut) ; nil sans chemin.
    public func chemin(de id: IdNoeud) -> Lien? {
        liens.first { $0.genre == .chemin && $0.de == id }
    }

    /// Parent d'un noeud vu par la sonde (lien enfant-parent) ; nil sinon.
    public func parent(de id: IdNoeud) -> IdNoeud? {
        liens.first { $0.genre == .parent && $0.de == id }?.vers
    }
}
