import Foundation

/// Service DNS-SD vu sur le reseau local.
public struct AnnonceService: Codable, Hashable, Sendable {
    /// Nom de l'instance ("Apple TV 4K", "30FC8F95E0E1A385-00000000F89487F7").
    public var instance: String
    /// Hote de la cible SRV, sans point final ("Apple-TV-4K.local") ; nil si non resolu.
    public var hote: String?
    public var port: UInt16?
    public var txt: ChampsTXT

    public init(instance: String, hote: String? = nil, port: UInt16? = nil, txt: ChampsTXT = ChampsTXT()) {
        self.instance = instance
        self.hote = hote
        self.port = port
        self.txt = txt
    }
}

/// Route IPv6 du Mac vers un prefixe /64, par un routeur (passerelle lien-local).
public struct RouteIPv6: Codable, Hashable, Sendable {
    /// "fd19:961f:2db3::/64"
    public var prefixe: String
    /// "fe80::5a:d5f3:dc72:e7d6" (sans zone)
    public var passerelle: String?
    /// "en0"
    public var interface: String?

    public init(prefixe: String, passerelle: String?, interface: String? = nil) {
        self.prefixe = prefixe
        self.passerelle = passerelle
        self.interface = interface
    }
}

/// Tout ce que le Mac voit a un instant : la matiere d'un instantane, et le
/// format des captures (tests, mode demo, option de capture de l'app).
public struct Annonces: Codable, Equatable, Sendable {
    public var date: Date
    /// `_meshcop._udp` : routeurs de bordure.
    public var routeurs: [AnnonceService]
    /// `_matter._tcp` : une instance par appareil et par fabrique.
    public var matter: [AnnonceService]
    /// `_hap._udp` : accessoires HomeKit.
    public var hap: [AnnonceService]
    /// `_trel._udp` : routeurs Thread qui passent aussi par le reseau local (TREL) ; vide dans une capture d'avant.
    public var trel: [AnnonceService]
    /// Adresses resolues de chaque hote (cle : `AnnonceService.hote`), en texte.
    public var adresses: [String: [String]]
    /// Routes IPv6 /64 du Mac par un routeur lien-local (vide si illisibles).
    public var routes: [RouteIPv6]
    /// Prefixes /64 des interfaces du Mac, en texte.
    public var prefixesLocaux: [String]
    /// Remarque libre (origine d'une capture reconstituee...).
    public var note: String?

    public init(date: Date, routeurs: [AnnonceService] = [], matter: [AnnonceService] = [],
                hap: [AnnonceService] = [], trel: [AnnonceService] = [], adresses: [String: [String]] = [:],
                routes: [RouteIPv6] = [], prefixesLocaux: [String] = [], note: String? = nil) {
        self.date = date
        self.routeurs = routeurs
        self.matter = matter
        self.hap = hap
        self.trel = trel
        self.adresses = adresses
        self.routes = routes
        self.prefixesLocaux = prefixesLocaux
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case date, routeurs, matter, hap, trel, adresses, routes, prefixesLocaux, note
    }

    /// Une capture d'avant TREL n'a pas `trel` : vide.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        routeurs = try c.decode([AnnonceService].self, forKey: .routeurs)
        matter = try c.decode([AnnonceService].self, forKey: .matter)
        hap = try c.decode([AnnonceService].self, forKey: .hap)
        trel = try c.decodeIfPresent([AnnonceService].self, forKey: .trel) ?? []
        adresses = try c.decode([String: [String]].self, forKey: .adresses)
        routes = try c.decode([RouteIPv6].self, forKey: .routes)
        prefixesLocaux = try c.decode([String].self, forKey: .prefixesLocaux)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Adresses d'un hote (vide si inconnu).
    public func adresses(de hote: String?) -> [String] {
        hote.flatMap { adresses[$0] } ?? []
    }

    /// Rien d'annonce : ni routeur, ni Matter, ni HAP (le Mac n'entend rien).
    public var estVide: Bool { routeurs.isEmpty && matter.isEmpty && hap.isEmpty }
}
