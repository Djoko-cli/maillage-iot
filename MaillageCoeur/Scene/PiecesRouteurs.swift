import Foundation

/// Piece d'un routeur de bordure que Maison ne place pas (precisions 23 et 24 du plan 4b) : HomeKit
/// ne donne a une app tierce ni les HomePod ni l'Apple TV, leur annonce n'a donc pas d'accessoire de
/// Maison. Un routeur qui en a un garde sa piece ; pour les autres, dans cet ordre :
/// - **le choix** (« Placer dans une piece… », dans la fiche du routeur), garde par maison
///   (`domicile`) sous l'instance de l'annonce, dans `pieces-routeurs.json` ; un choix dont la piece
///   n'est plus dans Maison ne compte pas ;
/// - **le nom** du routeur, celui qu'affiche l'app (son surnom, sinon son annonce) : la piece de
///   Maison dont le nom y figure, en mots entiers, sans egard a la casse ni aux accents ; le nom de
///   piece le plus long gagne ; si deux pieces ont cette longueur, aucune.
///
/// Piece d'un autre noeud que Maison ne place pas (precision 27, spec de la vue par pieces, section
/// 2.3) : un appareil Matter dont l'annonce a expire, que la sonde seule connait, ou une annonce
/// sans accessoire de Maison ; un routeur Thread qui n'est pas de bordure. La piece de Maison, sinon
/// le choix, garde par maison sous son ExtMac dans le meme fichier, sinon « Sans piece » ; pas de
/// regle du nom. Un noeud sans ExtMac connue n'a pas de choix.
public struct PiecesRouteurs: Hashable, Sendable, Codable {
    /// Version 1 : les routeurs (`maisons`), puis, depuis la precision 27, les autres noeuds
    /// (`appareils`), un champ facultatif. Un fichier d'avant se lit sans perte ; une app d'avant lit
    /// encore les routeurs d'un fichier d'apres, et ignore les autres noeuds.
    public static let versionActuelle = 1

    public var version = PiecesRouteurs.versionActuelle
    /// Par domicile ("" : maison sans nom) : instance de l'annonce -> piece choisie.
    public var maisons: [String: [String: String]] = [:]
    /// Par domicile : ExtMac d'un autre noeud (16 hexa majuscules) -> piece choisie (precision 27).
    public var appareils: [String: [String: String]] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, maisons, appareils
    }

    /// `appareils` manque aux fichiers d'avant la precision 27 : aucun choix d'appareil. Mal forme, il
    /// est ignore de meme : un champ facultatif ne doit pas faire perdre les choix des routeurs.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        maisons = try c.decode([String: [String: String]].self, forKey: .maisons)
        appareils = (try? c.decodeIfPresent([String: [String: String]].self, forKey: .appareils)) ?? [:]
    }

    /// Vide si le fichier manque, est illisible, ou d'une version plus recente (`FichiersGardes`).
    public static func lire(_ url: URL) -> PiecesRouteurs {
        FichiersGardes.lire(PiecesRouteurs.self, url, version: versionActuelle) ?? PiecesRouteurs()
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

    /// Piece choisie pour un routeur (son instance) ; nil : la regle du nom.
    public func choix(routeur: String, domicile: String) -> String? {
        maisons[domicile]?[routeur]
    }

    /// Garde le choix d'une piece pour un routeur ; nil revient a la regle du nom.
    public mutating func choisir(_ piece: String?, routeur: String, domicile: String) {
        maisons[domicile, default: [:]][routeur] = piece
        if maisons[domicile]?.isEmpty == true { maisons[domicile] = nil }
    }

    /// Piece choisie pour un autre noeud (son ExtMac) ; nil : aucune, il est « Sans piece ».
    public func choix(appareil extMac: String, domicile: String) -> String? {
        appareils[domicile]?[extMac.uppercased()]
    }

    /// Garde le choix d'une piece pour un autre noeud (son ExtMac) ; nil, « Sans piece », l'efface.
    public mutating func choisir(_ piece: String?, appareil extMac: String, domicile: String) {
        appareils[domicile, default: [:]][extMac.uppercased()] = piece
        if appareils[domicile]?.isEmpty == true { appareils[domicile] = nil }
    }

    /// Cle du choix d'un noeud qui n'est pas un routeur de bordure (precision 27) : son ExtMac. Nil pour
    /// un routeur de bordure, qui suit les precisions 23 a 25, et pour un noeud sans ExtMac connue :
    /// ni choix ni menu.
    public static func cle(_ n: GrapheReseau.Noeud) -> String? {
        n.bordure ? nil : n.extMac?.uppercased()
    }

    /// Piece de chaque noeud du graphe : celle de Maison (`deMaison`, par id de noeud) ; sinon, pour un
    /// noeud qui a une cle (`cle(_:)`), la piece choisie sous cette cle, si elle est encore une piece de
    /// la maison (`pieces`). Un noeud qui n'y est pas va dans « Sans piece ». La piece d'un routeur de
    /// bordure se calcule a part (`piece(routeur:nom:parmi:domicile:)`).
    public func piecesNoeuds(_ graphe: GrapheReseau, deMaison: [String: String], parmi pieces: [String],
                             domicile: String) -> [String: String] {
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
        if let c = choix(routeur: routeur, domicile: domicile), pieces.contains(c) { return c }
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
