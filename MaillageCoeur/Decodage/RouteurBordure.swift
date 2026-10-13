import Foundation

/// Role d'un routeur dans sa partition Thread.
public enum RoleThread: String, Codable, Hashable, Sendable {
    case detache, enfant, routeur, chef
}

/// Etat de l'interface Thread d'un agent de bordure.
public enum InterfaceThread: String, Codable, Hashable, Sendable {
    case nonInitialisee, inactive, active
}

/// Bits d'etat d'un agent de bordure (TXT `sb`, 32 bits, gros-boutiste).
public struct EtatAgent: Hashable, Sendable {
    public let brut: UInt32

    public init(brut: UInt32) { self.brut = brut }

    public init?(_ d: Data) {
        guard d.count == 4 else { return nil }
        brut = d.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// Bits 3-4.
    public var interface: InterfaceThread {
        switch (brut >> 3) & 3 {
        case 0: .nonInitialisee
        case 1: .inactive
        default: .active
        }
    }

    /// Bit 7 : routeur de dorsale (BBR) actif.
    public var bbrActif: Bool { (brut >> 7) & 1 == 1 }
    /// Bit 8 : BBR primaire de sa partition.
    public var bbrPrimaire: Bool { (brut >> 8) & 1 == 1 }
    /// Bits 9-10, sens garanti a partir de Thread 1.4 : lire `RouteurBordure.role`.
    var bitsRole: UInt32 { (brut >> 9) & 3 }
}

/// Routeur de bordure Thread tel qu'il s'annonce (`_meshcop._udp`).
public struct RouteurBordure: Hashable, Sendable, Identifiable {
    public var id: String { instance }
    /// Nom de l'instance mDNS ("Apple TV 4K").
    public let instance: String
    public let hote: String?
    /// `vn`, `mn`
    public let fabricant: String?
    public let modele: String?
    /// `tv` : version de Thread ("1.4.0").
    public let versionThread: String?
    /// `nn` : nom du reseau.
    public let nomReseau: String?
    /// `xp` : identifiant etendu du reseau, 16 hexa majuscules.
    public let idReseau: String?
    /// `xa` : adresse etendue du routeur, 16 hexa majuscules.
    public let adresseEtendue: String?
    /// `pt` : identifiant de partition, 8 hexa majuscules.
    public let partition: String?
    /// `at` : date du jeu de parametres actif (48 bits de secondes).
    public let jeuActif: Date?
    /// `sb`
    public let etat: EtatAgent?
    /// `omr` : prefixe OMR publie (quand le routeur l'annonce).
    public let prefixeOMR: PrefixeIPv6?
    /// Prefixe du reseau local tire de `xp`.
    public let prefixeReseauLocal: PrefixeIPv6?
    /// Adresses de l'hote, triees.
    public let adresses: [AdresseIPv6]

    public init(annonce: AnnonceService, adresses textes: [String]) {
        let t = annonce.txt
        instance = annonce.instance
        hote = annonce.hote
        fabricant = t.texte("vn")
        modele = t.texte("mn")
        versionThread = t.texte("tv")
        nomReseau = t.texte("nn")
        let xp = t["xp"].flatMap { $0.count == 8 ? $0 : nil }
        idReseau = xp?.hexa
        adresseEtendue = t["xa"].flatMap { $0.count == 8 ? $0.hexa : nil }
        partition = t["pt"].flatMap { $0.count == 4 ? $0.hexa : nil }
        jeuActif = t["at"].flatMap(Self.dateJeuActif)
        etat = t["sb"].flatMap { EtatAgent($0) }
        prefixeOMR = t["omr"].flatMap { PrefixeIPv6(omr: $0) }
        prefixeReseauLocal = xp.flatMap { PrefixeIPv6(reseauLocalDe: [UInt8]($0)) }
        adresses = Array(Set(textes.compactMap { AdresseIPv6($0) })).sorted()
    }

    /// Adresses lien-local (fe80::/10) : celles qu'on retrouve comme passerelles des routes.
    public var adressesLien: [AdresseIPv6] { adresses.filter(\.estLienLocal) }

    /// Role dans la partition. Les bits de role n'existent qu'a partir de
    /// Thread 1.4 : avant, ils valent 0 sans rien dire, et le role est inconnu
    /// (nil), jamais "detache".
    public var role: RoleThread? {
        guard let etat, Self.versionAuMoins(versionThread, 1, 4) else { return nil }
        switch etat.bitsRole {
        case 0: return .detache
        case 1: return .enfant
        case 2: return .routeur
        default: return .chef
        }
    }

    /// `at` : 6 octets de secondes depuis 1970, puis 2 octets (ticks, U).
    static func dateJeuActif(_ d: Data) -> Date? {
        guard d.count == 8 else { return nil }
        let secondes = d.prefix(6).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard secondes > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(secondes))
    }

    /// "1.4.0" >= (1, 4)
    static func versionAuMoins(_ v: String?, _ majeure: Int, _ mineure: Int) -> Bool {
        guard let v else { return false }
        let n = v.split(separator: ".").compactMap { Int($0) }
        guard n.count >= 2 else { return false }
        return (n[0], n[1]) >= (majeure, mineure)
    }
}
