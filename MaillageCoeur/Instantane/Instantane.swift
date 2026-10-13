import Foundation

/// Ou se trouve un appareil, d'apres ses adresses.
public enum GenreAppareil: String, Codable, Hashable, Sendable {
    /// Adresse dans un prefixe OMR (reseau Thread).
    case thread
    /// Adresses du reseau local seulement (Wi-Fi, Ethernet).
    case ip
    /// Aucune adresse resolue.
    case sansAdresse
}

/// Etat d'un appareil dans un instantane (l'etat "disparu" vient du suivi).
public enum EtatAppareil: String, Codable, Hashable, Sendable {
    /// Annonce avec une adresse Thread dans la partition principale, ou sur le
    /// reseau local : annonce, pas forcement "repond" (l'app ecoute sans sonder).
    case joignable
    /// Adresse Thread dans une partition qui n'est pas la principale.
    case partitionCoupee
    /// Aucune adresse.
    case sansAdresse
    /// Adresse dans un prefixe dont la partition est inconnue.
    case inconnu
}

/// Appareil Matter ou HomeKit : ses instances regroupees par hote.
public struct Appareil: Hashable, Sendable, Identifiable {
    /// Hote sans ".local" ("56B1E064401F74EF") ; "instance:<nom>" si l'hote est inconnu.
    public let id: String
    public let hote: String?
    /// Instances Matter (une par fabrique), triees.
    public let instances: [InstanceMatter]
    /// Noms des instances `_matter._tcp`, tels qu'annonces.
    public let servicesMatter: [String]
    public let proprietes: ProprietesMatter?
    public let hap: AccessoireHAP?
    /// Adresses IPv6 hors lien-local, triees.
    public let adresses: [AdresseIPv6]
    public let adressesIPv4: [String]
    public let genre: GenreAppareil
    public let idReseau: String?
    public let partition: String?
    /// Prefixe OMR de son adresse Thread.
    public let prefixe: PrefixeIPv6?
    public let etat: EtatAppareil

    public var endormi: Bool { proprietes?.endormi ?? false }
    /// Fabriques ou l'appareil est present, triees.
    public var fabriques: [String] { Array(Set(instances.map(\.fabrique))).sorted() }
}

/// Partition d'un reseau Thread.
public struct Partition: Hashable, Sendable, Identifiable {
    /// Identifiant `pt` (8 hexa), "?" s'il manque.
    public let id: String
    /// Centre d'abord (chef, sinon BBR primaire, sinon le premier par nom), puis par nom.
    public let routeurs: [RouteurBordure]
    /// Prefixes OMR attribues a la partition, tries.
    public let prefixes: [PrefixeIPv6]
    /// Prefixes que la partition revendique et qu'au moins une autre revendique
    /// aussi, tries : sur celle a qui le prefixe est attribue comme sur les autres.
    public let prefixesPartages: [PrefixeIPv6]
    /// Identifiants des appareils Thread de la partition, tries.
    public let appareils: [String]
    public let estPrincipale: Bool

    public var chef: RouteurBordure? { routeurs.first { $0.role == .chef } }
    public var bbrPrimaire: RouteurBordure? { routeurs.first { $0.etat?.bbrPrimaire == true } }
    public var centre: RouteurBordure? { routeurs.first }
}

/// Reseau Thread (un `xp`), et ses partitions.
public struct Reseau: Hashable, Sendable, Identifiable {
    /// `xp` (16 hexa), ou "nn:<nom>" s'il manque.
    public let id: String
    public let nom: String
    /// La principale d'abord : le plus de noeuds, puis un chef connu, puis l'identifiant.
    public let partitions: [Partition]
    public let prefixeLocal: PrefixeIPv6?

    public var estScinde: Bool { partitions.count > 1 }
    public var principale: Partition? { partitions.first }
    public var routeurs: [RouteurBordure] { partitions.flatMap(\.routeurs) }
    public var prefixes: [PrefixeIPv6] { partitions.flatMap(\.prefixes) }
}

/// Le reseau Thread tel qu'on le voit a un instant, calcule a partir des annonces.
public struct Instantane: Hashable, Sendable {
    public let date: Date
    public let reseaux: [Reseau]
    /// Appareils Thread et sans adresse, tries par identifiant.
    public let appareils: [Appareil]
    /// Appareils du reseau local (hors Thread), tries par identifiant.
    public let appareilsIP: [Appareil]
    /// Prefixes OMR vus sans partition connue.
    public let prefixesSansPartition: [PrefixeIPv6]
    /// Adresses etendues (16 hexa majuscules) des routeurs qui annoncent TREL (`_trel._udp`, champ `xa`) : ils peuvent
    /// se parler par le reseau local, et leurs liens entre eux ne prouvent aucun lien radio.
    public let trel: Set<String>

    public var routeurs: [RouteurBordure] { reseaux.flatMap(\.routeurs) }
    public var prefixes: [PrefixeIPv6] { (reseaux.flatMap(\.prefixes) + prefixesSansPartition).sorted() }

    public func appareil(_ id: String) -> Appareil? {
        appareils.first { $0.id == id } ?? appareilsIP.first { $0.id == id }
    }

    public func routeur(_ instance: String) -> RouteurBordure? {
        routeurs.first { $0.instance == instance }
    }

    public func reseau(_ id: String) -> Reseau? {
        reseaux.first { $0.id == id }
    }

    /// La partition de l'appareil lui vient d'un prefixe partage (une autre
    /// partition le revendique aussi) : il peut aussi bien etre dans l'autre.
    public func partitionIncertaine(_ a: Appareil) -> Bool {
        guard let p = a.prefixe, let id = a.partition, let r = a.idReseau.flatMap({ reseau($0) }) else { return false }
        return r.partitions.first { $0.id == id }?.prefixesPartages.contains(p) ?? false
    }
}
