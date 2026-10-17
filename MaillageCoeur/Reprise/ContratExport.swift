import CryptoKit
import Foundation

/// Contrat de l'export de reprise entre Maillage Thread, Maillage Zigbee et Maillage IoT (spec 4.1, 6.8). Les deux
/// anciennes apps ECRIVENT un dossier d'export, Maillage IoT le LIT : ce fichier est le seul endroit qui dit comment.
/// Il est identique a l'octet dans les trois depots (`outils/verifier-contrats.sh` le compare par `cmp`) : il ne depend
/// que de Foundation et de CryptoKit, aucun autre fichier du coeur, pour se compiler seul dans chaque ancienne app.
///
/// Le dossier d'export contient, a plat :
/// - `manifeste.json` (`Manifeste`) : format 1, identifiant d'export, app source et sa version, date, et la liste de
///   TOUS les autres fichiers du dossier (taille, SHA-256), `reglages.json` compris. Jamais `manifeste.json` lui-meme ;
/// - `reglages.json` (`Reglages`) : les reglages repris (UserDefaults), valeurs typees, sous leurs cles d'origine ;
/// - une copie des fichiers de `Application Support/<app>/` (`fichiersConnus(de:)`), sous le meme chemin relatif
///   (`Journal/journal-AAAA-MM.jsonl`), sans changement de contenu. Aucun secret du trousseau n'y figure.
/// Les deux ecritures (`ecrire`) et les deux lectures (`lireManifeste`, `lireReglages`) partagent les memes reglages
/// d'encodage (`encodeur()`, `decodeur()`) : cles triees, dates ISO 8601 a la seconde, sans echappement des barres.
/// Un format ou une app inconnus sont refuses avec une erreur typee (`Erreur`), jamais lus au mieux.
public enum ContratExport {
    /// Version du format du manifeste et de `reglages.json`. Un autre nombre est refuse (`Erreur.formatInconnu`).
    public static let formatCourant = 1
    /// Nom du manifeste, a la racine du dossier d'export. Reserve : aucun fichier repris ne le porte.
    public static let nomManifeste = "manifeste.json"
    /// Nom du fichier des reglages, a la racine du dossier d'export. Reserve : il est ecrit par l'export, jamais copie
    /// d'un dossier de l'app. Il est liste dans le manifeste, comme les autres fichiers.
    public static let nomReglages = "reglages.json"

    // MARK: Erreurs

    /// Ce qui fait refuser un manifeste ou un fichier de reglages, ou un chemin.
    public enum Erreur: Error, Equatable, Sendable {
        /// Le champ `format` est un entier autre que `formatCourant`.
        case formatInconnu(Int)
        /// L'app source n'est pas l'une des valeurs brutes de `AppSource`.
        case appInconnue(String)
        /// JSON invalide, champ manquant ou d'un mauvais type.
        case illisible
        /// Chemin absolu, avec `..` ou `.`, vide, avec un caractere de controle, ou trop long (`verifierChemin`).
        case cheminInvalide(String)
        /// Un lien symbolique est sur le chemin (`resoudre`) : dans un export, il n'a pas sa place.
        case lienSymbolique(String)
        /// Empreinte qui n'est pas 64 chiffres hexadecimaux minuscules (le chemin du fichier).
        case empreinteInvalide(String)
        /// Taille negative (le chemin du fichier).
        case tailleInvalide(String)
        /// Deux fichiers du manifeste portent le meme chemin, a la casse et a la normalisation Unicode pres (le
        /// systeme de fichiers du Mac les confondrait).
        case cheminEnDouble(String)
        /// Le manifeste liste `manifeste.json` (a la casse pres).
        case nomReserve(String)
        /// Un reglage a un type que ce contrat ne connait pas : jamais ignore en silence.
        case valeurInconnue(cle: String, type: String)
        /// Un type de valeur inconnu, vu hors d'une cle (usage interne ; `lireReglages` rend `valeurInconnue`).
        case typeDeValeurInconnu(String)
        /// Cle de reglage vide.
        case cleInvalide
    }

    // MARK: App source

    /// L'ancienne app qui a ecrit l'export. Les valeurs brutes sont celles du manifeste : elles ne changent jamais ; ce
    /// sont aussi les cles de protocole de Maillage IoT (`thread`, `zigbee`).
    public enum AppSource: String, Sendable, CaseIterable, Codable {
        case maillageThread = "thread"
        case maillageZigbee = "zigbee"

        public init(from decoder: any Decoder) throws {
            let brut = try decoder.singleValueContainer().decode(String.self)
            guard let app = AppSource(rawValue: brut) else { throw Erreur.appInconnue(brut) }
            self = app
        }
    }

    // MARK: Encodage commun a l'ecriture et a la lecture

    /// L'encodeur de l'export : cles triees, dates ISO 8601 (`2026-10-17T12:00:00Z`), barres non echappees, mise en page
    /// lisible. Deux ecritures du meme contenu donnent les memes octets.
    public static func encodeur() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Le decodeur de l'export : dates ISO 8601, comme `encodeur()`.
    public static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Manifeste

    /// Un fichier du dossier d'export.
    public struct Fichier: Codable, Equatable, Hashable, Sendable {
        /// Chemin relatif au dossier d'export, avec des `/` (`Journal/journal-2026-10.jsonl`).
        public let chemin: String
        /// Taille en octets.
        public let taille: Int64
        /// SHA-256 du contenu : 64 chiffres hexadecimaux minuscules.
        public let sha256: String

        public init(chemin: String, taille: Int64, sha256: String) {
            self.chemin = chemin
            self.taille = taille
            self.sha256 = sha256
        }

        private enum CodingKeys: String, CodingKey { case chemin, taille, sha256 }

        /// Lecture stricte : chemin valide, taille positive ou nulle, empreinte bien formee.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chemin = try c.decode(String.self, forKey: .chemin)
            taille = try c.decode(Int64.self, forKey: .taille)
            sha256 = try c.decode(String.self, forKey: .sha256)
            try ContratExport.verifier(self)
        }

        /// Le fichier `chemin` du dossier : sa taille et son empreinte, lues sur le disque. Refuse un chemin invalide,
        /// un lien symbolique, un fichier absent ou qui n'est pas un fichier ordinaire.
        public static func decrire(chemin: String, dans dossier: URL) throws -> Fichier {
            let url = try ContratExport.resoudre(chemin, dans: dossier)
            let valeurs = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard valeurs.isRegularFile == true, let taille = valeurs.fileSize else {
                throw Erreur.cheminInvalide(chemin)
            }
            return Fichier(chemin: chemin, taille: Int64(taille), sha256: try ContratExport.sha256(fichier: url))
        }
    }

    /// Le manifeste (`manifeste.json`), version 1.
    public struct Manifeste: Codable, Equatable, Sendable {
        /// Toujours `formatCourant` : un autre nombre est refuse a la lecture.
        public let format: Int
        /// Identifiant unique de cet export : Maillage IoT le garde (`imports.json`) pour ne pas reimporter le meme.
        public let identifiant: UUID
        /// L'ancienne app qui a ecrit l'export.
        public let app: AppSource
        /// Version de l'ancienne app (`1.4.0`), en texte libre.
        public let versionApp: String
        /// Date de l'export, a la seconde (les fractions sont retirees a la construction : ce qui s'ecrit se relit egal).
        public let date: Date
        /// Tous les fichiers du dossier sauf le manifeste, `reglages.json` compris, dans l'ordre de l'ecriture.
        public let fichiers: [Fichier]

        public init(identifiant: UUID, app: AppSource, versionApp: String, date: Date, fichiers: [Fichier]) {
            self.format = ContratExport.formatCourant
            self.identifiant = identifiant
            self.app = app
            self.versionApp = versionApp
            self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
            self.fichiers = fichiers
        }

        private enum CodingKeys: String, CodingKey { case format, identifiant, app, versionApp, date, fichiers }

        /// Lecture stricte : format reconnu d'abord (un manifeste d'un autre format peut avoir une autre forme), puis
        /// app, puis chaque fichier (`ContratExport.verifier(_:)`), sans chemin en double ni nom reserve.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let format = try c.decode(Int.self, forKey: .format)
            guard format == ContratExport.formatCourant else { throw Erreur.formatInconnu(format) }
            let app = try c.decode(AppSource.self, forKey: .app)
            let fichiers = try c.decode([Fichier].self, forKey: .fichiers)
            try ContratExport.verifierListe(fichiers)
            self.format = format
            self.app = app
            self.fichiers = fichiers
            identifiant = try c.decode(UUID.self, forKey: .identifiant)
            versionApp = try c.decode(String.self, forKey: .versionApp)
            date = try c.decode(Date.self, forKey: .date)
        }
    }

    /// Le manifeste en JSON. Refuse ce que `lireManifeste` refuserait : on ne produit pas un export illisible.
    public static func ecrire(_ manifeste: Manifeste) throws -> Data {
        guard manifeste.format == formatCourant else { throw Erreur.formatInconnu(manifeste.format) }
        try verifierListe(manifeste.fichiers)
        return try encodeur().encode(manifeste)
    }

    /// Lit un manifeste : format 1 seulement, app connue, fichiers valides ; toute autre erreur de forme donne
    /// `Erreur.illisible`.
    public static func lireManifeste(_ donnees: Data) throws -> Manifeste {
        try lire(Manifeste.self, donnees)
    }

    // MARK: Reglages

    /// Les types de valeur qu'un reglage repris peut avoir : ceux des UserDefaults de l'inventaire du 17/10.
    /// Les valeurs brutes sont celles de `reglages.json`.
    public enum TypeValeur: String, Sendable, CaseIterable, Codable {
        case bool, entier, decimal, texte, donnees, listeTextes, listeEntiers
    }

    /// La valeur d'un reglage, avec son type. Ecrite `{"type": "<TypeValeur>", "valeur": ...}` : un `1` entier, un
    /// `1,0` decimal et un booleen ne se confondent pas a la relecture. `donnees` est en base64 (la valeur Data d'un
    /// UserDefaults, comme `pont.hue`).
    public enum Valeur: Equatable, Hashable, Sendable, Codable {
        case bool(Bool)
        case entier(Int)
        case decimal(Double)
        case texte(String)
        case donnees(Data)
        case listeTextes([String])
        case listeEntiers([Int])

        public var type: TypeValeur {
            switch self {
            case .bool: .bool
            case .entier: .entier
            case .decimal: .decimal
            case .texte: .texte
            case .donnees: .donnees
            case .listeTextes: .listeTextes
            case .listeEntiers: .listeEntiers
            }
        }

        private enum CodingKeys: String, CodingKey { case type, valeur }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let brut = try c.decode(String.self, forKey: .type)
            guard let type = TypeValeur(rawValue: brut) else { throw Erreur.typeDeValeurInconnu(brut) }
            switch type {
            case .bool: self = .bool(try c.decode(Bool.self, forKey: .valeur))
            case .entier: self = .entier(try c.decode(Int.self, forKey: .valeur))
            case .decimal: self = .decimal(try c.decode(Double.self, forKey: .valeur))
            case .texte: self = .texte(try c.decode(String.self, forKey: .valeur))
            case .donnees: self = .donnees(try c.decode(Data.self, forKey: .valeur))
            case .listeTextes: self = .listeTextes(try c.decode([String].self, forKey: .valeur))
            case .listeEntiers: self = .listeEntiers(try c.decode([Int].self, forKey: .valeur))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            switch self {
            case .bool(let v): try c.encode(v, forKey: .valeur)
            case .entier(let v): try c.encode(v, forKey: .valeur)
            case .decimal(let v): try c.encode(v, forKey: .valeur)
            case .texte(let v): try c.encode(v, forKey: .valeur)
            case .donnees(let v): try c.encode(v, forKey: .valeur)
            case .listeTextes(let v): try c.encode(v, forKey: .valeur)
            case .listeEntiers(let v): try c.encode(v, forKey: .valeur)
            }
        }
    }

    /// `reglages.json` : les reglages repris de l'ancienne app, sous leurs cles d'origine (sans prefixe : c'est
    /// l'import qui les range sous les cles de Maillage IoT). Une cle absente du fichier n'avait pas de valeur dans
    /// l'ancienne app : l'export n'ecrit jamais de valeur par defaut a sa place.
    public struct Reglages: Codable, Equatable, Sendable {
        public let format: Int
        /// L'app dont ils viennent : le manifeste dit la meme.
        public let app: AppSource
        public let valeurs: [String: Valeur]

        public init(app: AppSource, valeurs: [String: Valeur]) {
            self.format = ContratExport.formatCourant
            self.app = app
            self.valeurs = valeurs
        }

        private enum CodingKeys: String, CodingKey { case format, app, valeurs }

        private struct CleDynamique: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        /// Lecture stricte : format reconnu, app connue, aucune cle vide, aucun type de valeur inconnu.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let format = try c.decode(Int.self, forKey: .format)
            guard format == ContratExport.formatCourant else { throw Erreur.formatInconnu(format) }
            let app = try c.decode(AppSource.self, forKey: .app)
            let v = try c.nestedContainer(keyedBy: CleDynamique.self, forKey: .valeurs)
            var valeurs: [String: Valeur] = [:]
            for cle in v.allKeys {
                guard !cle.stringValue.isEmpty else { throw Erreur.cleInvalide }
                do {
                    valeurs[cle.stringValue] = try v.decode(Valeur.self, forKey: cle)
                } catch Erreur.typeDeValeurInconnu(let type) {
                    throw Erreur.valeurInconnue(cle: cle.stringValue, type: type)
                }
            }
            self.format = format
            self.app = app
            self.valeurs = valeurs
        }
    }

    /// Les reglages en JSON. Refuse une cle vide ; un decimal non fini (NaN, infini) fait echouer l'ecriture.
    public static func ecrire(_ reglages: Reglages) throws -> Data {
        guard reglages.format == formatCourant else { throw Erreur.formatInconnu(reglages.format) }
        guard !reglages.valeurs.keys.contains("") else { throw Erreur.cleInvalide }
        return try encodeur().encode(reglages)
    }

    /// Lit `reglages.json` : format 1, app connue, types connus ; toute autre erreur de forme donne `Erreur.illisible`.
    public static func lireReglages(_ donnees: Data) throws -> Reglages {
        try lire(Reglages.self, donnees)
    }

    private static func lire<T: Decodable>(_ type: T.Type, _ donnees: Data) throws -> T {
        do {
            return try decodeur().decode(type, from: donnees)
        } catch let e as Erreur {
            throw e
        } catch {
            throw Erreur.illisible
        }
    }

    // MARK: Fichiers et reglages connus

    /// Un mois de calendrier d'un fichier mensuel (`maillage-2026-10.jsonl`), pour la coupe a 90 jours.
    public struct Mois: Equatable, Hashable, Comparable, Sendable {
        public let annee: Int
        public let mois: Int

        public init(annee: Int, mois: Int) {
            self.annee = annee
            self.mois = mois
        }

        public static func < (a: Mois, b: Mois) -> Bool {
            (a.annee, a.mois) < (b.annee, b.mois)
        }
    }

    /// Un fichier connu de l'ancienne app : son chemin relatif, ou son modele quand il est mensuel
    /// (`maillage-AAAA-MM.jsonl`, `Journal/journal-AAAA-MM.jsonl`).
    public struct FichierConnu: Equatable, Hashable, Sendable {
        public let modele: String

        public init(_ modele: String) {
            self.modele = modele
        }

        /// Un fichier par mois : le modele porte `AAAA-MM`.
        public var estMensuel: Bool { modele.contains(Self.joker) }

        static let joker = "AAAA-MM"

        /// Le chemin `chemin` est celui de ce fichier (pour un mensuel : une annee de 4 chiffres, un mois de 01 a 12).
        public func correspond(_ chemin: String) -> Bool {
            guard estMensuel else { return chemin == modele }
            return Self.mois(de: chemin, modele: modele) != nil
        }

        /// Le mois d'un chemin mensuel qui suit le modele.
        static func mois(de chemin: String, modele: String) -> Mois? {
            guard let separation = modele.range(of: joker) else { return nil }
            let debut = String(modele[..<separation.lowerBound]), fin = String(modele[separation.upperBound...])
            guard chemin.hasPrefix(debut), chemin.hasSuffix(fin),
                  chemin.utf8.count == debut.utf8.count + joker.utf8.count + fin.utf8.count else { return nil }
            let milieu = Array(chemin.utf8.dropFirst(debut.utf8.count).prefix(joker.utf8.count))
            // AAAA-MM : quatre chiffres, un tiret, deux chiffres.
            func chiffres(_ r: Range<Int>) -> Int? {
                let tranche = milieu[r]
                guard tranche.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
                return tranche.reduce(0) { $0 * 10 + Int($1 - 0x30) }
            }
            guard milieu.count == 7, milieu[4] == 0x2D, let annee = chiffres(0..<4), let mois = chiffres(5..<7),
                  (1...12).contains(mois) else { return nil }
            return Mois(annee: annee, mois: mois)
        }
    }

    /// Les fichiers que l'export reprend de `Application Support/<app>/` (inventaire du 17/10, section 5). Un fichier du
    /// dossier d'export qui n'est pas dans cette liste (ni `reglages.json`) est un fichier "en trop" pour l'import.
    public static func fichiersConnus(de app: AppSource) -> [FichierConnu] {
        let mensuels = ["maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        let modeles: [String]
        switch app {
        case .maillageThread:
            // noms.json : le releve de Maison de Thread (devient releve-maison.json a l'import).
            modeles = ["surnoms.json", "associations.json", "identites-routeurs.json", "dernier-maillage.json",
                       "dernieres-adresses.json", "noms.json", "pieces-routeurs.json", "positions-pieces.json"] + mensuels
        case .maillageZigbee:
            modeles = ["surnoms.json", "dernier-maillage.json", "appariements-maison.json", "noms-pont.json",
                       "releve-maison.json", "pieces-routeurs.json", "positions-pieces.json"] + mensuels
        }
        return modeles.map(FichierConnu.init)
    }

    /// Le chemin est celui d'un fichier connu de l'app (`fichiersConnus(de:)`).
    public static func estConnu(_ chemin: String, de app: AppSource) -> Bool {
        fichiersConnus(de: app).contains { $0.correspond(chemin) }
    }

    /// Le mois d'un fichier mensuel connu (`maillage-2026-10.jsonl`, `Journal/journal-2026-10.jsonl`) ; nil pour tout
    /// autre chemin. Le mois est celui du nom, jamais recalcule d'un contenu (les fichiers sont groupes par le calendrier
    /// local de l'ancienne app).
    public static func mois(de chemin: String) -> Mois? {
        for modele in ["maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"] {
            if let m = FichierConnu.mois(de: chemin, modele: modele) { return m }
        }
        return nil
    }

    /// Ce que l'export ne copie jamais : `.DS_Store` et les fichiers mis de cote par l'app quand ils etaient illisibles
    /// (`*.illisible-*.json`), a n'importe quelle profondeur.
    public static func estExcluDeLExport(_ chemin: String) -> Bool {
        let nom = chemin.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? chemin
        return nom == ".DS_Store" || (nom.hasSuffix(".json") && nom.contains(".illisible-"))
    }

    /// Un reglage repris : sa cle dans les UserDefaults de l'ancienne app, et son type.
    public struct ReglageConnu: Equatable, Hashable, Sendable {
        public let cle: String
        public let type: TypeValeur

        public init(_ cle: String, _ type: TypeValeur) {
            self.cle = cle
            self.type = type
        }
    }

    /// Les reglages que l'export ecrit dans `reglages.json` (inventaire du 17/10, section 5), sous leurs cles
    /// d'origine. Sont absents a dessein : les reglages de Sparkle (`SU*`), les etats de fenetre (`NSWindow Frame *`,
    /// `NSNav*`), `reglages.onglet`, `dossierNoms`, les secrets (trousseau, mot de passe Wi-Fi). Une cle absente de
    /// l'UserDefaults de l'ancienne app est absente du fichier, jamais ecrite avec une valeur par defaut.
    public static func reglagesConnus(de app: AppSource) -> [ReglageConnu] {
        let communs: [ReglageConnu] = [
            ReglageConnu("vuePieces3D", .bool), ReglageConnu("etagesEnGrille", .bool),
            ReglageConnu("legendeRepliee", .bool), ReglageConnu("grapheDejaOuvert", .bool),
            ReglageConnu("ouvertureSessionProposee", .bool), ReglageConnu("AppleLanguages", .listeTextes),
        ]
        switch app {
        case .maillageThread:
            return [
                ReglageConnu("sondeSerieUSB", .texte), ReglageConnu("sondeNom", .texte), ReglageConnu("sondeHote", .texte),
                // Recopiee telle quelle, jamais de defaut : absente, l'ancienne app la lit comme USB.
                ReglageConnu("sondeLiaison", .texte),
                ReglageConnu("scissionsNotifiees", .listeTextes),
                ReglageConnu("notification.scission", .bool), ReglageConnu("notification.routeurDisparu", .bool),
                ReglageConnu("notification.pertes", .bool), ReglageConnu("notification.informations", .bool),
            ] + communs
        case .maillageZigbee:
            return [
                ReglageConnu("sondeSerieUSB", .texte), ReglageConnu("sondeNom", .texte), ReglageConnu("sondeIeee", .texte),
                ReglageConnu("sondeNomWifi", .texte),
                // Le budget de la tournee de la sonde (spec 4.2).
                ReglageConnu("sondeJournalPages", .listeEntiers), ReglageConnu("sondePagesTables", .entier),
                ReglageConnu("sondeChemin", .texte),
                // JSON du pont retenu (adresse, identifiant, modele ; jamais sa cle) : donnee personnelle.
                ReglageConnu("pont.hue", .donnees),
                ReglageConnu("liensMontres", .texte), ReglageConnu("voisinsALaSelection", .bool),
                ReglageConnu("notification.routeurDisparu", .bool), ReglageConnu("notification.pertes", .bool),
                ReglageConnu("notification.informations", .bool),
            ] + communs
        }
    }

    /// Le type que `reglagesConnus(de:)` donne a la cle ; nil si la cle n'est pas un reglage repris de cette app.
    public static func typeAttendu(cle: String, de app: AppSource) -> TypeValeur? {
        reglagesConnus(de: app).first { $0.cle == cle }?.type
    }

    // MARK: Chemins

    /// Un chemin d'export est relatif et reste dans le dossier. Verification lexicale seulement (`resoudre` ajoute les
    /// liens symboliques) : refuse le chemin vide ou absolu, un composant vide, `.` ou `..`, un `\`, un caractere de
    /// controle (dont NUL), un composant de plus de 255 octets ou un chemin de plus de 1024 octets.
    public static func cheminEstValide(_ chemin: String) -> Bool {
        guard !chemin.isEmpty, chemin.utf8.count <= 1024, !chemin.hasPrefix("/") else { return false }
        guard !chemin.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\\" }) else {
            return false
        }
        return chemin.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { composant in
            !composant.isEmpty && composant != "." && composant != ".." && composant.utf8.count <= 255
        }
    }

    /// `cheminEstValide`, ou `Erreur.cheminInvalide(chemin)`.
    public static func verifierChemin(_ chemin: String) throws {
        guard cheminEstValide(chemin) else { throw Erreur.cheminInvalide(chemin) }
    }

    /// L'URL du fichier `chemin` du dossier d'export, apres verification : chemin valide (`verifierChemin`), aucun
    /// lien symbolique sur le chemin (le fichier lui-meme compris), et le resultat reste dans le dossier. Le fichier
    /// peut ne pas exister encore (a l'ecriture). Le dossier lui-meme peut etre derriere un lien.
    public static func resoudre(_ chemin: String, dans dossier: URL) throws -> URL {
        try verifierChemin(chemin)
        let base = dossier.standardizedFileURL
        var courant = base
        for composant in chemin.split(separator: "/") {
            courant = courant.appendingPathComponent(String(composant))
            // Un composant absent n'est pas un lien : seul un lien existant est refuse.
            if (try? courant.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Erreur.lienSymbolique(chemin)
            }
        }
        let racine = base.resolvingSymlinksInPath().path
        let fichier = courant.resolvingSymlinksInPath().path
        guard fichier.hasPrefix(racine.hasSuffix("/") ? racine : racine + "/") else { throw Erreur.cheminInvalide(chemin) }
        return courant
    }

    // MARK: Empreintes

    /// Taille du bloc lu a la fois pour l'empreinte d'un fichier : 1 Mio. Un historique de 100 Mo n'est jamais en memoire.
    private static let tailleBloc = 1 << 20

    /// SHA-256 de `donnees`, en hexadecimal minuscule (64 caracteres).
    public static func sha256(_ donnees: Data) -> String {
        hexadecimal(SHA256.hash(data: donnees))
    }

    /// SHA-256 du contenu du fichier, lu par blocs de 1 Mio, en hexadecimal minuscule. Les erreurs de lecture passent
    /// (fichier absent, illisible) : aucune empreinte n'est inventee.
    public static func sha256(fichier: URL) throws -> String {
        let lecteur = try FileHandle(forReadingFrom: fichier)
        defer { try? lecteur.close() }
        var hachage = SHA256()
        while try autoreleasepool(invoking: {
            guard let bloc = try lecteur.read(upToCount: tailleBloc), !bloc.isEmpty else { return false }
            hachage.update(data: bloc)
            return true
        }) {}
        return hexadecimal(hachage.finalize())
    }

    /// 64 chiffres hexadecimaux minuscules : la forme d'une empreinte du manifeste.
    public static func empreinteEstValide(_ empreinte: String) -> Bool {
        empreinte.utf8.count == 64 && empreinte.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    private static func hexadecimal(_ resume: some Sequence<UInt8>) -> String {
        let chiffres = Array("0123456789abcdef".utf8)
        var octets: [UInt8] = []
        octets.reserveCapacity(64)
        for o in resume {
            octets.append(chiffres[Int(o >> 4)])
            octets.append(chiffres[Int(o & 0x0F)])
        }
        return String(decoding: octets, as: UTF8.self)
    }

    // MARK: Verifications du manifeste

    /// Un fichier du manifeste : chemin valide, taille positive ou nulle, empreinte bien formee.
    static func verifier(_ fichier: Fichier) throws {
        try verifierChemin(fichier.chemin)
        guard fichier.taille >= 0 else { throw Erreur.tailleInvalide(fichier.chemin) }
        guard empreinteEstValide(fichier.sha256) else { throw Erreur.empreinteInvalide(fichier.chemin) }
    }

    /// La liste du manifeste : chaque fichier valide, aucun doublon (casse et normalisation Unicode comprises), jamais
    /// `manifeste.json`.
    static func verifierListe(_ fichiers: [Fichier]) throws {
        var vus: Set<String> = []
        for f in fichiers {
            try verifier(f)
            let cle = f.chemin.precomposedStringWithCanonicalMapping.lowercased()
            guard cle != nomManifeste else { throw Erreur.nomReserve(f.chemin) }
            guard vus.insert(cle).inserted else { throw Erreur.cheminEnDouble(f.chemin) }
        }
    }
}
