import Foundation

/// Releve d'une tournee pour l'historique (spec de la sonde, section 6) : la qualite de chaque
/// lien, entre routeurs et d'enfant a parent, et le signal des routeurs que la sonde entend.
/// Une ligne JSON de `maillage-AAAA-MM.jsonl`, en tableaux pour rester courte :
/// - `routeurs` : `[identifiant, ExtMac ou null]`, chaque routeur de la liste ;
/// - `liens` : `[a, b, qualite de a vers b, qualite de b vers a]` (null : inconnue), puis, depuis la
///   sonde tout-en-un (spec, section 2.5), la source de chaque sens : `d` diagnostic, `e` ecoute (null :
///   inconnue) ; un lien sans source n'en a pas ;
/// - `enfants` : `[ExtMac, identifiant du parent, qualite ou null]`, les enfants identifies, la
///   sonde comprise, puis leur source (`t` table de son parent, `r` resolution, `s` la sonde) et, quand
///   leurs compteurs MAC le donnent, le taux d'acces au canal refuses (au 1/10 000), a titre d'information :
///   il ne donne pas de qualite (`AccesCanal`). Un enfant sans ExtMac n'a pas d'identite stable (son
///   RLOC16 change avec son parent) : il n'est pas garde ;
/// - `signaux` : `[identifiant, dBm]`, les routeurs que la sonde entend, son parent compris ;
/// - `parentSonde` : identifiant du parent de la sonde (absent sans parent connu).
/// Les champs facultatifs manquent aux lignes d'avant : elles se lisent comme avant, sources et taux
/// inconnus ; une source inconnue (version plus recente) aussi.
public struct ReleveMaillage: Hashable, Sendable {
    /// Routeur de la liste et son ExtMac (nil : inconnue).
    public struct Routeur: Hashable, Sendable {
        public let id: Int
        public let extMac: String?

        public init(id: Int, extMac: String?) {
            self.id = id
            self.extMac = extMac
        }
    }

    /// Enfant identifie, son parent et la qualite de son lien (nil sous un routeur muet), sa source et le
    /// taux d'acces au canal refuses de ses compteurs MAC, a titre d'information (nil : ligne d'avant, ou inconnus).
    public struct Enfant: Hashable, Sendable {
        public let extMac: String
        public let parent: Int
        public let qualite: Int?
        public let source: SourceEnfant?
        public let echecs: Double?

        public init(extMac: String, parent: Int, qualite: Int?, source: SourceEnfant? = nil, echecs: Double? = nil) {
            self.extMac = extMac
            self.parent = parent
            self.qualite = qualite
            self.source = source
            self.echecs = echecs
        }
    }

    public let date: Date
    public let partition: String
    /// Par identifiant croissant.
    public let routeurs: [Routeur]
    public let liens: [LienRadio]
    /// Par ExtMac croissante.
    public let enfants: [Enfant]
    public let signaux: [SignalSonde]
    public let parentSonde: Int?

    public init(date: Date, partition: String, routeurs: [Routeur], liens: [LienRadio], enfants: [Enfant],
                signaux: [SignalSonde], parentSonde: Int?) {
        self.date = date
        self.partition = partition
        self.routeurs = routeurs
        self.liens = liens
        self.enfants = enfants
        self.signaux = signaux
        self.parentSonde = parentSonde
    }

    /// Releve d'un maillage : ses enfants identifies (`Maillage.enfantsIdentifies`), avec leur source et leur taux
    /// d'acces au canal refuses arrondi au 1/10 000 ; ses liens sans les dates de leurs mesures.
    public init(_ m: Maillage) {
        self.init(date: m.date, partition: m.partition,
                  routeurs: m.routeurs.map { Routeur(id: $0.id, extMac: $0.extMac) },
                  liens: m.liens.map(\.sansDates),
                  enfants: m.enfantsIdentifies.sorted { $0.key < $1.key }
                      .map { Enfant(extMac: $0.key, parent: $0.value.parent, qualite: $0.value.qualite, source: $0.value.source,
                                    echecs: $0.value.echecs.map { ($0 * 10_000).rounded() / 10_000 }) },
                  signaux: m.signaux, parentSonde: m.parentSonde)
    }

    /// Identifiants de routeur possibles : 0 a 62 (un RLOC16 porte 6 bits de routeur ; 63 n'est pas
    /// attribue).
    static let identifiantsRouteur = 0...62

    /// Cle d'un routeur du releve : son ExtMac, sinon "rloc:XXXX" (valable dans sa partition) ;
    /// "rloc:?" pour un identifiant hors plage (fonction totale : jamais d'arret du programme).
    public func cle(routeur id: Int) -> String {
        guard Self.identifiantsRouteur.contains(id) else { return "rloc:?" }
        return routeurs.first { $0.id == id }?.extMac ?? String(format: "rloc:%04X", UInt16(id) << 10)
    }
}

extension ReleveMaillage: Codable {
    private enum CodingKeys: String, CodingKey {
        case date, partition, routeurs, liens, enfants, signaux, parentSonde
    }

    /// Codes courts des sources dans l'historique.
    private static let codesLiens: [SourceLien: String] = [.diagnostic: "d", .ecoute: "e"]
    private static let codesEnfants: [SourceEnfant: String] = [.tableEnfants: "t", .resolution: "r", .sonde: "s"]

    private static func sourceLien(_ code: String?) -> SourceLien? {
        code.flatMap { c in codesLiens.first { $0.value == c }?.key }
    }

    private static func sourceEnfant(_ code: String?) -> SourceEnfant? {
        code.flatMap { c in codesEnfants.first { $0.value == c }?.key }
    }

    /// Decode un identifiant de routeur ; hors de 0...62, la ligne entiere est refusee.
    private static func identifiant(_ l: inout any UnkeyedDecodingContainer) throws -> Int {
        let id = try l.decode(Int.self)
        guard identifiantsRouteur.contains(id) else {
            throw DecodingError.dataCorruptedError(in: l, debugDescription: "identifiant de routeur hors de 0...62 : \(id)")
        }
        return id
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var routeurs: [Routeur] = []
        var r = try c.nestedUnkeyedContainer(forKey: .routeurs)
        while !r.isAtEnd {
            var l = try r.nestedUnkeyedContainer()
            routeurs.append(Routeur(id: try Self.identifiant(&l), extMac: try l.decodeIfPresent(String.self)))
        }
        var liens: [LienRadio] = []
        var li = try c.nestedUnkeyedContainer(forKey: .liens)
        while !li.isAtEnd {
            var l = try li.nestedUnkeyedContainer()
            liens.append(LienRadio(a: try Self.identifiant(&l), b: try Self.identifiant(&l),
                                   qualiteAB: try l.decodeIfPresent(Int.self), qualiteBA: try l.decodeIfPresent(Int.self),
                                   sourceAB: Self.sourceLien(try l.decodeIfPresent(String.self)),
                                   sourceBA: Self.sourceLien(try l.decodeIfPresent(String.self))))
        }
        var enfants: [Enfant] = []
        var e = try c.nestedUnkeyedContainer(forKey: .enfants)
        while !e.isAtEnd {
            var l = try e.nestedUnkeyedContainer()
            enfants.append(Enfant(extMac: try l.decode(String.self), parent: try Self.identifiant(&l),
                                  qualite: try l.decodeIfPresent(Int.self),
                                  source: Self.sourceEnfant(try l.decodeIfPresent(String.self)),
                                  echecs: try l.decodeIfPresent(Double.self)))
        }
        var signaux: [SignalSonde] = []
        var s = try c.nestedUnkeyedContainer(forKey: .signaux)
        while !s.isAtEnd {
            var l = try s.nestedUnkeyedContainer()
            signaux.append(SignalSonde(routeur: try Self.identifiant(&l), rssi: try l.decode(Int.self)))
        }
        let parentSonde = try c.decodeIfPresent(Int.self, forKey: .parentSonde)
        if let p = parentSonde, !Self.identifiantsRouteur.contains(p) {
            throw DecodingError.dataCorruptedError(forKey: .parentSonde, in: c,
                                                   debugDescription: "identifiant de routeur hors de 0...62 : \(p)")
        }
        self.init(date: try c.decode(Date.self, forKey: .date), partition: try c.decode(String.self, forKey: .partition),
                  routeurs: routeurs, liens: liens, enfants: enfants, signaux: signaux, parentSonde: parentSonde)
    }

    /// N'ecrit jamais un identifiant de routeur hors de 0...62 (donnees non conformes) : la lecture
    /// refuserait toute la ligne. Les routeurs, liens, enfants et signaux qui en citent un sont retires,
    /// et le parent de la sonde s'il en est un ; le reste de la ligne est garde.
    public func encode(to encoder: any Encoder) throws {
        let ids = Self.identifiantsRouteur
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(partition, forKey: .partition)
        var r = c.nestedUnkeyedContainer(forKey: .routeurs)
        for x in routeurs where ids.contains(x.id) {
            var l = r.nestedUnkeyedContainer()
            try l.encode(x.id)
            try l.encodeOuNul(x.extMac)
        }
        var li = c.nestedUnkeyedContainer(forKey: .liens)
        for x in liens where ids.contains(x.a) && ids.contains(x.b) {
            var l = li.nestedUnkeyedContainer()
            try l.encode(x.a)
            try l.encode(x.b)
            try l.encodeOuNul(x.qualiteAB)
            try l.encodeOuNul(x.qualiteBA)
            if x.sourceAB != nil || x.sourceBA != nil {
                try l.encodeOuNul(x.sourceAB.flatMap { Self.codesLiens[$0] })
                try l.encodeOuNul(x.sourceBA.flatMap { Self.codesLiens[$0] })
            }
        }
        var e = c.nestedUnkeyedContainer(forKey: .enfants)
        for x in enfants where ids.contains(x.parent) {
            var l = e.nestedUnkeyedContainer()
            try l.encode(x.extMac)
            try l.encode(x.parent)
            try l.encodeOuNul(x.qualite)
            if x.source != nil || x.echecs != nil {
                try l.encodeOuNul(x.source.flatMap { Self.codesEnfants[$0] })
                if let echecs = x.echecs { try l.encode(echecs) }
            }
        }
        var s = c.nestedUnkeyedContainer(forKey: .signaux)
        for x in signaux where ids.contains(x.routeur) {
            var l = s.nestedUnkeyedContainer()
            try l.encode(x.routeur)
            try l.encode(x.rssi)
        }
        try c.encodeIfPresent(parentSonde.flatMap { ids.contains($0) ? $0 : nil }, forKey: .parentSonde)
    }
}

private extension UnkeyedEncodingContainer {
    /// La valeur, ou null.
    mutating func encodeOuNul<T: Encodable>(_ v: T?) throws {
        if let v { try encode(v) } else { try encodeNil() }
    }
}

/// Historique des tournees sur disque (spec de la sonde, section 6) : JSON Lines mensuel
/// (`maillage-AAAA-MM.jsonl`) dans le dossier de l'app, garde 90 jours comme le journal.
public struct HistoriqueFichiers: Sendable {
    private let fichiers: FichiersMensuels

    public init(dossier: URL, calendrier: Calendar = .current) {
        fichiers = FichiersMensuels(dossier: dossier, prefixe: "maillage", calendrier: calendrier)
    }

    /// Nom du fichier du mois d'une date (« maillage-2026-09.jsonl »).
    public func nomFichier(_ date: Date) -> String { fichiers.nomFichier(date) }

    /// Ajoute le releve a la fin du fichier de son mois.
    public func ajouter(_ r: ReleveMaillage) throws {
        try fichiers.ajouter([(date: r.date, json: try CodageJSON.encodeur().encode(r))])
    }

    /// Releves dates de `debut` ou apres, du plus ancien au plus recent ; seuls les fichiers des
    /// mois qui finissent apres `debut` sont lus. Une ligne illisible est ignoree.
    public func lire(depuis debut: Date) throws -> [ReleveMaillage] {
        let decodeur = CodageJSON.decodeur()
        return try fichiers.lignes(depuis: debut)
            .compactMap { try? decodeur.decode(ReleveMaillage.self, from: $0) }
            .filter { $0.date >= debut }
            .sorted { $0.date < $1.date }
    }

    /// Supprime les fichiers des mois finis depuis plus de 90 jours ; rend leurs noms.
    @discardableResult
    public func purger(maintenant: Date) throws -> [String] {
        try fichiers.purger(maintenant: maintenant)
    }
}
