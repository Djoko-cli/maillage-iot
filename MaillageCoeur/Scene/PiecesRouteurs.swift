import Foundation

/// Piece d'un routeur de bordure que Maison ne place pas (precisions 23 et 24 du plan 4b) : HomeKit
/// ne donne a une app tierce ni les HomePod ni l'Apple TV, leur annonce n'a donc pas d'accessoire de
/// Maison. Un routeur qui en a un garde sa piece ; pour les autres, dans cet ordre :
/// - **le choix** (« Placer dans une piece… », dans la fiche du routeur), garde par maison
///   (`domicile`) sous l'identifiant du routeur (`thread:<instance de l'annonce>`), dans `pieces-noeuds.json` ; un
///   choix dont la piece n'est plus dans Maison ne compte pas ;
/// - **le nom** du routeur, celui qu'affiche l'app (son surnom, sinon son annonce) : la piece de
///   Maison dont le nom y figure, en mots entiers, sans egard a la casse ni aux accents ; le nom de
///   piece le plus long gagne ; si deux pieces ont cette longueur, aucune.
///
/// Piece d'un autre noeud que Maison ne place pas (precision 27, spec de la vue par pieces, section
/// 2.3) : un appareil Matter dont l'annonce a expire, que la sonde seule connait, ou une annonce
/// sans accessoire de Maison ; un routeur Thread qui n'est pas de bordure ; un noeud Zigbee que le pont ne place
/// pas. La piece de Maison, sinon le choix, garde par maison sous son adresse longue (ExtMac, IEEE) prefixee du
/// protocole dans le meme fichier, sinon « Sans piece » ; pas de regle du nom. Un noeud sans adresse longue connue n'a
/// pas de choix.
///
/// Les choix sont gardes par `IdNoeud` : deux noeuds de deux protocoles qui ont la meme adresse ne se confondent pas.
/// Les fonctions de calcul d'un routeur de bordure (`piece(routeur:...)`, `pieceDeMaison(routeur:...)`,
/// `piece(candidats:...)`) prennent l'instance brute de l'annonce : un routeur de bordure est un noeud Thread, et son
/// choix est garde sous `thread:<instance>`.
public struct PiecesRouteurs: Hashable, Sendable, Codable {
    /// Version 2 : les cles de noeud portent leur protocole (`thread:<instance>`, `thread:<ExtMac>`, `zigbee:<IEEE>`).
    /// Le fichier de la version 1 (`pieces-routeurs.json`, cles brutes d'un seul protocole) se relit a la place du
    /// nouveau tant que celui-ci n'existe pas (`lire(_:ancien:protocoleParDefaut:)`), et n'est jamais reecrit.
    public static let versionActuelle = 2

    public var version = PiecesRouteurs.versionActuelle
    /// Par domicile ("" : maison sans nom) : routeur de bordure (`thread:<instance de l'annonce>`) -> piece choisie.
    public var maisons: [String: [IdNoeud: String]] = [:]
    /// Par domicile : autre noeud (son protocole et son adresse longue en 16 hexa majuscules) -> piece choisie
    /// (precision 27).
    public var appareils: [String: [IdNoeud: String]] = [:]
    /// Par domicile : routeur de bordure (`thread:<instance de l'annonce>`) -> le nom AirPlay dont la piece proposee a ete
    /// ignoree (« Ignorer », dans sa fiche). La proposition revient quand son nom AirPlay n'est plus celui-la. Le champ n'est
    /// ecrit que s'il y en a un : un fichier sans ignore garde les octets d'avant.
    public var airPlayIgnores: [String: [IdNoeud: String]] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, maisons, appareils, ignoreAirPlay
    }

    /// `appareils` et `maisons` peuvent manquer : aucun choix. `appareils` mal forme est ignore : un champ facultatif ne
    /// doit pas faire perdre les choix des routeurs. Une cle de noeud d'un protocole inconnu (une app plus recente a ecrit
    /// le fichier) leve `FichiersGardes.FormatPlusRecent` : le fichier n'est ni lu ni reecrit.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version >= Self.versionActuelle else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "version anterieure : ancien fichier")
        }
        maisons = try Self.cles(try c.decodeIfPresent([String: [String: String]].self, forKey: .maisons) ?? [:])
        appareils = try Self.cles((try? c.decodeIfPresent([String: [String: String]].self, forKey: .appareils)) ?? [:])
        // Facultatif comme `appareils` : mal forme, il est ignore sans faire perdre les choix.
        airPlayIgnores = (try? Self.cles((try? c.decodeIfPresent([String: [String: String]].self, forKey: .ignoreAirPlay)) ?? [:])) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(Self.textes(maisons), forKey: .maisons)
        try c.encode(Self.textes(appareils), forKey: .appareils)
        if !airPlayIgnores.isEmpty { try c.encode(Self.textes(airPlayIgnores), forKey: .ignoreAirPlay) }
    }

    private static func cles(_ brut: [String: [String: String]]) throws -> [String: [IdNoeud: String]] {
        try brut.mapValues { choix in
            Dictionary(uniqueKeysWithValues: try choix.map { (try FichiersGardes.idNoeud($0.key), $0.value) })
        }
    }

    private static func textes(_ choix: [String: [IdNoeud: String]]) -> [String: [String: String]] {
        choix.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.texte, $0.value) }) }
    }

    /// Le fichier de la version 1 (`pieces-routeurs.json`) : `maisons` sous l'instance de l'annonce, `appareils` sous
    /// l'ExtMac ou l'IEEE, cles brutes d'un seul protocole. `maisons` manque aux fichiers de Maillage Zigbee (pas de
    /// routeur de bordure) ; `appareils` aux fichiers d'avant la precision 27, ou mal forme : ignore.
    private struct Version1: Decodable {
        var version: Int
        var maisons: [String: [String: String]]
        var appareils: [String: [String: String]]

        enum CodingKeys: String, CodingKey { case version, maisons, appareils }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            maisons = try c.decodeIfPresent([String: [String: String]].self, forKey: .maisons) ?? [:]
            appareils = (try? c.decodeIfPresent([String: [String: String]].self, forKey: .appareils)) ?? [:]
        }
    }

    /// Vide si le fichier manque, est illisible, d'une version plus recente, ou d'un protocole inconnu (`FichiersGardes`).
    public static func lire(_ url: URL) -> PiecesRouteurs {
        FichiersGardes.lire(PiecesRouteurs.self, url, version: versionActuelle) ?? PiecesRouteurs()
    }

    /// Comme `lire(_:)` ; si `url` (`pieces-noeuds.json`) n'existe pas, relit `ancien` (`pieces-routeurs.json`, version 1) :
    /// ses cles brutes prennent le protocole de l'app (`protocoleParDefaut`), les ExtMac en majuscules. L'ancien fichier
    /// n'est jamais ecrit ; un `url` qui existe (meme illisible ou plus recent) n'est jamais remplace par l'ancien.
    public static func lire(_ url: URL, ancien: URL, protocoleParDefaut: Protocole) -> PiecesRouteurs {
        guard FichiersGardes.examiner(PiecesRouteurs.self, url, version: versionActuelle).etat == .absent else {
            return lire(url)
        }
        guard let v1 = FichiersGardes.lire(Version1.self, ancien, version: 1) else { return PiecesRouteurs() }
        var p = PiecesRouteurs()
        p.maisons = v1.maisons.mapValues { choix in
            Dictionary(uniqueKeysWithValues: choix.map { (IdNoeud(protocoleParDefaut, $0.key), $0.value) })
        }
        // Deux cles qui ne different que par la casse se rejoignent en majuscules : on garde la premiere par ordre des
        // octets de la cle d'origine (jamais celle d'un ordre de hachage), sans planter.
        p.appareils = v1.appareils.mapValues { choix in
            Dictionary(choix.sorted { $0.key < $1.key }.map { (IdNoeud(protocoleParDefaut, $0.key.uppercased()), $0.value) },
                       uniquingKeysWith: { premier, _ in premier })
        }
        return p
    }

    /// Rien n'est ecrit sur un fichier d'une version plus recente ; un fichier illisible est d'abord mis
    /// de cote (`FichiersGardes`).
    public func ecrire(dans url: URL) throws {
        try FichiersGardes.ecrire(self, dans: url, version: Self.versionActuelle)
    }

    /// Piece de Maison d'un routeur de bordure (son instance) : celle de l'accessoire qui porte son nom.
    public static func pieceDeMaison(routeur: String, maison: NomsMaison?) -> String? {
        maison?.accessoires.first { $0.nom == routeur && $0.piece?.isEmpty == false }?.piece
    }

    /// Piece d'un routeur de bordure, par la chaine entiere : celle de son accessoire de Maison, sinon le choix garde
    /// sous son instance, sinon la regle de `nom` (son surnom, sinon son instance). Nil : « Sans piece ». Une seule
    /// ecriture, pour un routeur identifie comme pour chaque candidat d'un routeur qui ne l'est pas.
    public func piece(routeur: String, nom: String, maison: NomsMaison?, parmi pieces: [String],
                      domicile: String) -> String? {
        Self.pieceDeMaison(routeur: routeur, maison: maison)
            ?? piece(routeur: routeur, nom: nom, parmi: pieces, domicile: domicile)
    }

    /// Piece d'un routeur de bordure non identifie (polissage D, section 4.1), d'apres ses candidats, les annonces
    /// qui peuvent etre la sienne : celle de chacun, comme pour un routeur identifie qui porterait son annonce
    /// (`piece(routeur:nom:maison:parmi:domicile:)`, avec le nom de `noms`, l'instance a defaut). Si tous en ont une, et
    /// que c'est la meme, le routeur y va ; sinon nil : « Sans piece ».
    public func piece(candidats: [String], noms: [String: String], maison: NomsMaison?, parmi pieces: [String],
                      domicile: String) -> String? {
        let p = candidats.map { c in
            piece(routeur: c, nom: noms[c] ?? c, maison: maison, parmi: pieces, domicile: domicile)
        }
        guard let premiere = p.first ?? nil, p.allSatisfy({ $0 == premiere }) else { return nil }
        return premiere
    }

    /// Piece choisie pour un routeur de bordure (`thread:<instance>`) ; nil : la regle du nom.
    public func choix(routeur: IdNoeud, domicile: String) -> String? {
        maisons[domicile]?[routeur]
    }

    /// Garde le choix d'une piece pour un routeur de bordure ; nil revient a la regle du nom.
    public mutating func choisir(_ piece: String?, routeur: IdNoeud, domicile: String) {
        maisons[domicile, default: [:]][routeur] = piece
        if maisons[domicile]?.isEmpty == true { maisons[domicile] = nil }
    }

    /// Le nom AirPlay dont la piece proposee a ete ignoree pour un routeur de bordure (`thread:<instance>`) ; nil : aucun.
    public func airPlayIgnore(routeur: IdNoeud, domicile: String) -> String? {
        airPlayIgnores[domicile]?[routeur]
    }

    /// Retient « Ignorer » pour un routeur de bordure : le nom AirPlay dont la piece proposee est ignoree ; nil l'oublie.
    public mutating func ignorerAirPlay(_ nomAirPlay: String?, routeur: IdNoeud, domicile: String) {
        airPlayIgnores[domicile, default: [:]][routeur] = nomAirPlay
        if airPlayIgnores[domicile]?.isEmpty == true { airPlayIgnores[domicile] = nil }
    }

    /// La cle d'un autre noeud : son protocole et son adresse longue en majuscules.
    private static func majuscules(_ id: IdNoeud) -> IdNoeud { IdNoeud(id.protocole, id.cle.uppercased()) }

    /// Piece choisie pour un autre noeud (son protocole et son adresse longue, `cle(_:)`) ; nil : aucune, il est
    /// « Sans piece ».
    public func choix(appareil: IdNoeud, domicile: String) -> String? {
        appareils[domicile]?[Self.majuscules(appareil)]
    }

    /// Garde le choix d'une piece pour un autre noeud (son protocole et son adresse longue) ; nil, « Sans piece »,
    /// l'efface.
    public mutating func choisir(_ piece: String?, appareil: IdNoeud, domicile: String) {
        appareils[domicile, default: [:]][Self.majuscules(appareil)] = piece
        if appareils[domicile]?.isEmpty == true { appareils[domicile] = nil }
    }

    /// Cle du choix d'un noeud qui n'est pas un routeur de bordure (precision 27) : son protocole et son adresse longue
    /// (ExtMac, IEEE). Nil pour un routeur de bordure, qui suit les precisions 23 a 25, et pour un noeud sans adresse
    /// longue connue : ni choix ni menu.
    public static func cle(_ n: GrapheReseau.Noeud) -> IdNoeud? {
        n.bordure ? nil : n.extMac.map { IdNoeud(n.id.protocole, $0.uppercased()) }
    }

    /// Piece de chaque noeud du graphe : celle de Maison (`deMaison`, par id de noeud) ; sinon, pour un
    /// noeud qui a une cle (`cle(_:)`), la piece choisie sous cette cle, si elle est encore une piece de
    /// la maison (`pieces`). Un noeud qui n'y est pas va dans « Sans piece ». La piece d'un routeur de
    /// bordure se calcule a part (`piece(routeur:nom:parmi:domicile:)`).
    public func piecesNoeuds(_ graphe: GrapheReseau, deMaison: [IdNoeud: String], parmi pieces: [String],
                             domicile: String) -> [IdNoeud: String] {
        var resultat = deMaison.filter { !$0.value.isEmpty }
        for n in graphe.noeuds where resultat[n.id] == nil {
            if let x = Self.cle(n), let c = choix(appareil: x, domicile: domicile), pieces.contains(c) {
                resultat[n.id] = c
            }
        }
        return resultat
    }

    /// Piece d'un routeur que Maison ne place pas : son choix, s'il est encore une piece de la maison,
    /// sinon d'apres son nom ; nil : « Sans piece ».
    public func piece(routeur: String, nom: String, parmi pieces: [String], domicile: String) -> String? {
        if let c = choix(routeur: IdNoeud(.thread, routeur), domicile: domicile), pieces.contains(c) { return c }
        return Self.piece(nom: nom, parmi: pieces)
    }

    /// Piece d'apres un nom : celle dont les mots se suivent dans les siens ; la plus longue (en
    /// caracteres, sans casse ni accents) ; nil sans piece, ou a egalite entre deux pieces.
    public static func piece(nom: String, parmi pieces: [String]) -> String? {
        let motsNom = mots(nom)
        var meilleure: (piece: String, longueur: Int)?
        var egalite = false
        for p in pieces {
            let m = mots(p)
            guard !m.isEmpty, contient(motsNom, m) else { continue }
            let longueur = m.joined(separator: " ").count
            if let b = meilleure, b.longueur > longueur { continue }
            if let b = meilleure, b.longueur == longueur {
                if b.piece != p { egalite = true }
                continue
            }
            meilleure = (p, longueur)
            egalite = false
        }
        return egalite ? nil : meilleure?.piece
    }

    /// Pieces de Maison : celles des accessoires et celles des zones, sans doublon, par nom.
    public static func pieces(de maison: NomsMaison?) -> [String] {
        guard let maison else { return [] }
        var toutes = Set(maison.accessoires.compactMap(\.piece))
        for z in maison.zones ?? [] { toutes.formUnion(z.pieces) }
        return toutes.filter { !$0.isEmpty }.sorted()
    }

    /// Mots d'un nom : suites de lettres ou de chiffres, sans casse ni accents (« Chambre d'amis » :
    /// chambre, d, amis).
    static func mots(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Les mots `m` se suivent dans `nom`.
    private static func contient(_ nom: [String], _ m: [String]) -> Bool {
        guard m.count <= nom.count else { return false }
        return (0...(nom.count - m.count)).contains { Array(nom[$0..<($0 + m.count)]) == m }
    }
}
