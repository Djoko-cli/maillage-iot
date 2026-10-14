import Foundation
import MaillageCoeur

/// Protocole USB de la sonde, v1 (spec de la sonde, section 3) : une commande
/// texte par ligne vers la sonde ; en retour, des lignes machine RS (0x1E),
/// JSON compact en ASCII, LF, 4096 octets au plus, `v` et `t` en tete.
public enum ProtocoleSonde {
    public static let separateur: UInt8 = 0x1E
    public static let longueurMax = 4096
    /// `bonjour.produit` d'une sonde : tout autre port est refuse.
    public static let produit = "sonde-maillage"
}

/// Reponse a `bonjour`.
public struct Bonjour: Hashable, Sendable, Codable {
    public let produit: String
    public let version: String
    /// Nom de la sonde, garde par la carte (« SONDE-T1 » par defaut) ; firmware 1.0.1 et suivants.
    public let nom: String?
    public let mac: String?
    public let appairee: Bool
    /// Code d'appairage manuel : toujours (firmware 1.0.1 et suivants), avant seulement tant
    /// que la sonde n'etait pas dans Maison.
    public let code: String?
    /// Charge du QR code Matter (« MT:... »), comme `code`.
    public let qr: String?
    /// Nom d'hote SRP de la sonde, sans `.local` (celui que Matter enregistre) : l'acces par le
    /// reseau Thread vise `<hote>.local`. Firmware 1.0.2 et suivants ; nil tant qu'il n'est pas connu.
    public let hote: String?

    public var estSonde: Bool { produit == ProtocoleSonde.produit }
}

/// Reponse a `cle nouvelle` (USB seulement) : la cle de l'acces reseau, rendue une seule fois,
/// avec l'id de la demande et le nom d'hote ; ou reponse a `cle` : l'empreinte seule (nil sans
/// cle). La cle n'apparait dans aucune description (`description`, `dump`) : jamais dans un
/// journal, la console ni un message d'erreur.
public struct ReponseCle: Hashable, Sendable, Codable {
    public let id: Int?
    /// 64 hexa MAJUSCULES.
    public let cle: String?
    /// 8 premiers hexa de SHA-256(cle).
    public let empreinte: String?
    public let hote: String?

    public init(id: Int?, cle: String?, empreinte: String?, hote: String?) {
        self.id = id
        self.cle = cle
        self.empreinte = empreinte
        self.hote = hote
    }
}

extension ReponseCle: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var cleMasquee: String { cle == nil ? "nil" : "<masquee>" }

    public var description: String {
        "cle(id: \(id.map(String.init) ?? "nil"), cle: \(cleMasquee), empreinte: \(empreinte ?? "nil"), hote: \(hote ?? "nil"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["id": id as Any, "cle": cleMasquee, "empreinte": empreinte as Any, "hote": hote as Any],
               displayStyle: .struct)
    }
}

/// Parent de la sonde, tel qu'elle le voit.
public struct ParentSonde: Hashable, Sendable, Codable {
    public let rloc16: String
    public let ext: String
    public let lqIn: Int
    public let lqOut: Int
    public let rssi: Int
}

/// Compteurs de l'ecoute des messages MLE (`etat.ecoute`, firmware 1.1.0), depuis le demarrage de la sonde.
public struct CompteursEcoute: Hashable, Sendable, Codable {
    /// Trames recues.
    public let trames: Int
    /// Messages MLE dechiffres.
    public let mle: Int
    /// Messages MLE chiffres non dechiffres : en-tete illisible, cle indisponible, MIC faux.
    public let echecs: Int
    /// Trames perdues, la file de la sonde pleine.
    public let filePleine: Int

    public init(trames: Int, mle: Int, echecs: Int, filePleine: Int) {
        self.trames = trames
        self.mle = mle
        self.echecs = echecs
        self.filePleine = filePleine
    }

    enum CodingKeys: String, CodingKey {
        case trames, mle, echecs
        case filePleine = "file_pleine"
    }
}

/// Reponse a `etat`.
public struct EtatSonde: Hashable, Sendable, Codable {
    public let role: String
    public let rloc16: String
    /// ExtMac de la sonde (firmware 1.0.0 et suivants) : la sonde se retrouve dans l'instantane.
    public let ext: String?
    public let mode: String?
    public let parent: ParentSonde?
    public let partition: String?
    /// Identifiant de routeur du chef.
    public let chef: Int?
    public let canal: Int?
    /// Prefixe du reseau maille, 16 hexa.
    public let prefixeMaille: String?
    public let xp: String?
    public let suspendue: Bool
    /// Compteurs de l'ecoute (firmware 1.1.0) ; nil pour un firmware plus ancien.
    public let ecoute: CompteursEcoute?

    /// Attachee au reseau : enfant, routeur ou chef.
    public var estAttachee: Bool { ["child", "router", "leader"].contains(role) && partition != nil && chef != nil }
    public var rloc16Valeur: UInt16? { UInt16(rloc16, radix: 16) }
}

/// Voisin entendu par la sonde (`voisins`) ; son parent n'y est pas : `etat` le donne (la sonde
/// est FED depuis la 1.0.2, comme le dit `InterlocuteurSonde.voisins`).
public struct VoisinSonde: Hashable, Sendable, Codable {
    public let rloc16: String
    public let ext: String
    public let rssi: Int
    public let lqi: Int
    public let routeur: Bool
}

/// Routeur de la partition dans la table de la sonde (`routeurs`, firmware 1.0.2, en FED) :
/// tous les routeurs de la partition y sont, par leur RLOC16 ; l'ExtMac, seulement pour ceux
/// que la sonde entend (a qui elle demande un lien), jamais pour son parent (`etat` la donne).
public struct RouteurSonde: Hashable, Sendable, Codable {
    /// Identifiant de routeur, de 0 a 62.
    public let id: Int
    public let rloc16: String
    /// ExtMac, 16 hexa ; nil pour un routeur que la sonde n'a pas entendu.
    public let ext: String?
    /// Qualites du lien et age (secondes depuis la derniere annonce entendue ; sans
    /// signification pour un routeur jamais entendu) : lus, pas utilises par l'app.
    public let lqIn: Int?
    public let lqOut: Int?
    public let age: Int?
    /// Lien etabli avec ce routeur.
    public let lien: Bool?

    public var rloc16Valeur: UInt16? { UInt16(rloc16, radix: 16) }
}

/// Une ligne de `routeurs` : une partie de la table (`suite` : d'autres lignes suivent, la
/// derniere a `suite` faux), ou l'erreur (`occupee` : verrou d'OpenThread refuse).
public struct PartieRouteurs: Hashable, Sendable {
    public let liste: [RouteurSonde]
    public let suite: Bool
    public let erreur: String?
}

/// Routeur entendu par la sonde (`annonces`, firmware 1.1.0) : une ligne par routeur. La sonde dechiffre ses messages
/// MLE et garde sa derniere Route64, brute : l'app la decode (`route64Decodee`).
public struct AnnonceSonde: Hashable, Sendable, Codable {
    public let rloc16: String
    /// ExtMac de l'emetteur, 16 hexa.
    public let ext: String
    /// Partition de sa TLV Leader Data, 8 hexa ; nil sans elle.
    public let partition: String?
    /// Derniere Route64 brute (valeur de la TLV 9 du message MLE, en hexa) ; nil sans elle.
    public let route64: String?
    public let seq: Int?
    /// Signal du dernier message, et le plus faible et le plus fort depuis son entree dans la table, en dBm.
    public let rssi: Int
    public let rssiMin: Int
    public let rssiMax: Int
    /// Messages dechiffres.
    public let nb: Int
    /// Secondes depuis le dernier.
    public let ageS: Int

    enum CodingKeys: String, CodingKey {
        case rloc16, ext, partition, route64, seq, rssi, nb
        case rssiMin = "rssi_min"
        case rssiMax = "rssi_max"
        case ageS = "age_s"
    }

    public var rloc16Valeur: UInt16? { UInt16(rloc16, radix: 16) }

    /// La Route64 decodee comme celle du diagnostic (`ReponseDiagnostic.route64`) ; nil sans elle, ou illisible.
    public var route64Decodee: Route64? {
        route64.flatMap { Data(hexa: $0) }.flatMap { ReponseDiagnostic.route64([UInt8]($0)) }
    }
}

/// Une ligne d'`annonces` : un routeur entendu (`suite` : d'autres lignes suivent, la derniere a `suite` faux), ou
/// aucun (la ligne `vide`).
public struct PartieAnnonces: Hashable, Sendable {
    public let liste: [AnnonceSonde]
    public let suite: Bool

    public init(liste: [AnnonceSonde], suite: Bool) {
        self.liste = liste
        self.suite = suite
    }
}

/// Reponse a `resoudre` (firmware 1.1.0, `repondu` depuis la 1.1.1) : le RLOC16 que le cache d'adresses de la sonde
/// donne pour l'adresse (celui du parent pour un routeur Apple, celui de l'enfant pour un routeur tiers), et le
/// ML-EID de la cible quand la reponse l'a porte ; ou l'erreur (`introuvable`, `syntaxe`, `suspendue`, `occupee`,
/// `envoi`...).
public struct ResultatResolution: Hashable, Sendable, Codable {
    public let id: Int
    public let cible: String
    public let ok: Bool
    public let ms: Int?
    public let rloc16: String?
    /// ML-EID, 32 hexa ; nil si le cache ne le donne pas.
    public let mleid: String?
    public let erreur: String?
    /// Firmware 1.1.1 : l'appareil a repondu a la sonde (vrai), ou seule une entree du cache d'adresses l'a donne
    /// (faux, un appareil eteint peut y rester). nil : champ absent, firmware plus ancien, qui ne le dit pas.
    public let repondu: Bool?

    public init(id: Int, cible: String, ok: Bool, ms: Int? = nil, rloc16: String? = nil, mleid: String? = nil,
                erreur: String? = nil, repondu: Bool? = nil) {
        self.id = id
        self.cible = cible
        self.ok = ok
        self.ms = ms
        self.rloc16 = rloc16
        self.mleid = mleid
        self.erreur = erreur
        self.repondu = repondu
    }

    public var rloc16Valeur: UInt16? { ok ? rloc16.flatMap { UInt16($0, radix: 16) } : nil }

    public var adresseMleid: AdresseIPv6? {
        mleid.flatMap { Data(hexa: $0) }.flatMap { AdresseIPv6(octets: [UInt8]($0)) }
    }

    /// Aucun routeur n'a repondu pour l'adresse en 15 s : l'appareil reste en rattachement suppose.
    public var introuvable: Bool { !ok && erreur == "introuvable" }
}

/// Reponse a `diag` : les TLV en hexa, ou l'erreur (`delai`, `suspendue`, `occupee`, `envoi`...).
public struct ResultatDiag: Hashable, Sendable, Codable {
    public let id: Int
    public let cible: String
    public let ok: Bool
    public let ms: Int?
    public let code: String?
    public let tlv: String?
    public let erreur: String?

    public init(id: Int, cible: String, ok: Bool, ms: Int? = nil, code: String? = nil, tlv: String? = nil,
                erreur: String? = nil) {
        self.id = id
        self.cible = cible
        self.ok = ok
        self.ms = ms
        self.code = code
        self.tlv = tlv
        self.erreur = erreur
    }

    /// TLV decodees d'une reponse reussie.
    public var reponse: ReponseDiagnostic? { ok ? tlv.flatMap { ReponseDiagnostic(hexa: $0) } : nil }

    /// Reponse trop longue pour le reseau (`trop_long` : la carte limite une reponse a 1100
    /// octets, a distance seulement) : la cible a repondu, ce n'est pas un silence.
    public var tropLong: Bool { !ok && erreur == "trop_long" }
}

/// Message d'une ligne machine.
public enum MessageSonde: Hashable, Sendable {
    case bonjour(Bonjour)
    case etat(EtatSonde)
    case voisins([VoisinSonde])
    /// Une ligne de la table des routeurs (`SondeUSB` reunit les lignes d'une meme reponse).
    case routeurs(PartieRouteurs)
    case diag(ResultatDiag)
    /// Une ligne d'`annonces` (firmware 1.1.0 ; `SondeUSB` reunit les lignes d'une meme reponse).
    case annonces(PartieAnnonces)
    case resoudre(ResultatResolution)
    case cle(ReponseCle)
    /// Commande sans id (`etat`, `voisins`) que la sonde n'a pas servie : son nom et l'erreur de la
    /// ligne (`occupee` : verrou d'OpenThread refuse). `routeurs` porte la sienne dans `PartieRouteurs`.
    case refusee(commande: String, erreur: String)
    case erreur(String)
    /// Type inconnu (version plus recente de la sonde) : ignore.
    case inconnu(String)

    private struct Entete: Decodable {
        let v: Int
        let t: String
    }

    private struct Voisins: Decodable {
        let liste: [VoisinSonde]
    }

    private struct Routeurs: Decodable {
        let liste: [RouteurSonde]?
        let suite: Bool?
        let erreur: String?

        /// L'erreur, ou la liste (sans `suite` : derniere ligne) ; nil sans l'une ni l'autre.
        var partie: PartieRouteurs? {
            if let erreur { return PartieRouteurs(liste: [], suite: false, erreur: erreur) }
            return liste.map { PartieRouteurs(liste: $0, suite: suite ?? false, erreur: nil) }
        }
    }

    private struct Erreur: Decodable {
        let erreur: String
    }

    private struct Annonces: Decodable {
        let vide: Bool?
        let suite: Bool?
    }

    /// JSON d'une ligne machine, sans RS ni LF ; nil si illisible ou d'une autre version.
    public static func lire(_ json: Data) -> MessageSonde? {
        let d = JSONDecoder()
        guard let e = try? d.decode(Entete.self, from: json), e.v == 1 else { return nil }
        switch e.t {
        case "bonjour": return (try? d.decode(Bonjour.self, from: json)).map { .bonjour($0) }
        case "etat":
            if let etat = try? d.decode(EtatSonde.self, from: json) { return .etat(etat) }
            return (try? d.decode(Erreur.self, from: json)).map { .refusee(commande: "etat", erreur: $0.erreur) }
        case "voisins":
            if let v = try? d.decode(Voisins.self, from: json) { return .voisins(v.liste) }
            return (try? d.decode(Erreur.self, from: json)).map { .refusee(commande: "voisins", erreur: $0.erreur) }
        case "routeurs": return (try? d.decode(Routeurs.self, from: json))?.partie.map { .routeurs($0) }
        case "diag": return (try? d.decode(ResultatDiag.self, from: json)).map { .diag($0) }
        case "annonces":
            if let a = try? d.decode(AnnonceSonde.self, from: json) {
                return .annonces(PartieAnnonces(liste: [a], suite: (try? d.decode(Annonces.self, from: json))?.suite ?? false))
            }
            guard (try? d.decode(Annonces.self, from: json))?.vide == true else { return nil }
            return .annonces(PartieAnnonces(liste: [], suite: false))
        case "resoudre": return (try? d.decode(ResultatResolution.self, from: json)).map { .resoudre($0) }
        case "cle": return (try? d.decode(ReponseCle.self, from: json)).map { .cle($0) }
        case "erreur": return (try? d.decode(Erreur.self, from: json)).map { .erreur($0.erreur) }
        default: return .inconnu(e.t)
        }
    }
}

/// Commande envoyee a la sonde.
public enum CommandeSonde: Hashable, Sendable {
    case bonjour
    case etat
    case voisins
    /// Table des routeurs de la sonde (firmware 1.0.2).
    case routeurs
    /// `diag <RLOC16> <t,t,...> <id> [<delai ms>]`
    case diag(cible: UInt16, tlv: [UInt8], id: Int, delaiMs: Int?)
    /// `diag <ipv6> <t,t,...> <id> [<delai ms>]` : vers une adresse du reseau maille (le ML-EID d'un enfant).
    case diagAdresse(cible: AdresseIPv6, tlv: [UInt8], id: Int, delaiMs: Int?)
    /// Routeurs entendus par la sonde (firmware 1.1.0).
    case annonces
    /// `resoudre <ipv6> <id>` (firmware 1.1.0) : l'adresse sans zone.
    case resoudre(adresse: AdresseIPv6, id: Int)
    /// `cle nouvelle <alea en 64 HEXA> <id>` (USB seulement) : la carte en tire la cle de
    /// l'acces reseau et la rend une seule fois (`cle`).
    case cleNouvelle(alea: Data, id: Int)

    /// Ligne a envoyer, fin de ligne comprise.
    public var ligne: String {
        switch self {
        case .bonjour: return "bonjour\n"
        case .etat: return "etat\n"
        case .voisins: return "voisins\n"
        case .routeurs: return "routeurs\n"
        case .diag(let cible, let tlv, let id, let delai):
            var l = String(format: "diag %04X ", cible) + tlv.map(String.init).joined(separator: ",") + " \(id)"
            if let delai { l += " \(delai)" }
            return l + "\n"
        case .diagAdresse(let cible, let tlv, let id, let delai):
            var l = "diag \(cible) " + tlv.map(String.init).joined(separator: ",") + " \(id)"
            if let delai { l += " \(delai)" }
            return l + "\n"
        case .annonces: return "annonces\n"
        case .resoudre(let adresse, let id): return "resoudre \(adresse) \(id)\n"
        case .cleNouvelle(let alea, let id):
            return "cle nouvelle " + alea.map { String(format: "%02X", $0) }.joined() + " \(id)\n"
        }
    }
}

/// Decoupe le flux USB en lignes machine (RS ... LF), sans le RS ; le reste
/// (journaux de la pile, lignes humaines) est ignore, comme une ligne trop longue.
/// La ligne machine commence au dernier RS de la ligne, comme dans le pont Halo : ce qui le
/// precede (queue d'un journal sans fin de ligne, invite, ligne machine coupee) est abandonne.
public struct DecoupeurLignes: Sendable {
    private var tampon: [UInt8] = []
    private var tropLongue = false

    public init() {}

    public mutating func ajouter(_ d: Data) -> [Data] {
        var lignes: [Data] = []
        for o in d {
            if o == ProtocoleSonde.separateur {
                // Le JSON est de l'ASCII imprimable, sans RS : un RS ouvre toujours une ligne machine.
                tampon.removeAll(keepingCapacity: true)
                tampon.append(o)
                tropLongue = false
            } else if o == 0x0A {
                if !tropLongue, tampon.first == ProtocoleSonde.separateur {
                    var l = tampon.dropFirst()
                    if l.last == 0x0D { l = l.dropLast() }
                    lignes.append(Data(l))
                }
                tampon.removeAll(keepingCapacity: true)
                tropLongue = false
            } else if tampon.count < ProtocoleSonde.longueurMax {
                tampon.append(o)
            } else {
                tropLongue = true
            }
        }
        return lignes
    }
}
