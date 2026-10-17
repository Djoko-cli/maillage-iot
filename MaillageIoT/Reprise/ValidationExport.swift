import Foundation
import MaillageCoeur

// Phase 4, tache 3 : la validation d'un export de reprise par l'app.
//
// Le controle complet du dossier est dans le contrat (`ContratExport.verifierDossier` : manifeste lisible, format, app,
// chemins, fichiers listes et presents, tailles et empreintes, reglages.json). Ce fichier ne le refait pas : il l'appelle
// et traduit chaque erreur du contrat en une cause lisible pour l'assistant (`CauseRefus`, textes francais et anglais),
// puis ajoute ce que le contrat ne peut pas savoir : la version de l'app source (`ValidationExport.versionEstPrise`),
// l'export deja repris (`imports.json`, `JournalImports`) et le resume du contenu pour l'ecran de confirmation
// (`ResumeExport`). Rien n'est ecrit ni copie : valider ne modifie ni l'export ni les donnees de l'app.

// MARK: Resultat

/// Ce que donne la validation d'un dossier d'export.
enum ResultatValidation: Equatable, Sendable {
    /// L'export est intact, d'une version prise en charge, et pas encore repris.
    case acceptee(ResumeExport)
    /// L'export est intact mais son identifiant est dans `imports.json` : ce n'est pas une erreur, l'assistant dit
    /// « deja repris le ... » et ne propose pas de le reprendre une seconde fois.
    case dejaRepris(ImportRepris, ResumeExport)
    /// L'export est refuse, pour cette cause. Rien n'est importe.
    case refuse(CauseRefus)
}

// MARK: Resume pour l'assistant

/// Les familles de contenu d'un export, pour compter ce qu'il apporte sans citer de nom ni de valeur.
enum GenreContenu: String, CaseIterable, Sendable {
    /// `surnoms.json`.
    case surnoms
    /// `pieces-routeurs.json` et `positions-pieces.json`.
    case pieces
    /// Le releve de Maison : `noms.json` (Thread) ou `releve-maison.json` (Zigbee).
    case nomsMaison
    /// Le dernier etat connu des reseaux : `dernier-maillage.json`, `dernieres-adresses.json`, `associations.json`,
    /// `identites-routeurs.json` (Thread), `noms-pont.json`, `appariements-maison.json` (Zigbee).
    case etatDesModules
    /// Un fichier par mois : `maillage-AAAA-MM.jsonl`.
    case historiqueSonde
    /// Un fichier par mois : `Journal/journal-AAAA-MM.jsonl`.
    case journal
    /// Un fichier connu du contrat mais sans famille ici : compte quand meme, jamais perdu de vue (un test verifie
    /// qu'aucun fichier connu n'y tombe).
    case autres

    /// La famille d'un fichier de l'export (chemin relatif). `reglages.json` n'a pas de famille : il se compte a part.
    static func genre(de chemin: String) -> GenreContenu {
        switch chemin {
        case "surnoms.json": return .surnoms
        case "pieces-routeurs.json", "positions-pieces.json": return .pieces
        case "noms.json", "releve-maison.json": return .nomsMaison
        case "dernier-maillage.json", "dernieres-adresses.json", "associations.json", "identites-routeurs.json",
             "noms-pont.json", "appariements-maison.json":
            return .etatDesModules
        default:
            guard ContratExport.mois(de: chemin) != nil else { return .autres }
            return chemin.hasPrefix("Journal/") ? .journal : .historiqueSonde
        }
    }

    /// Le nom de la famille, pour l'ecran de confirmation.
    var libelle: String { libelle(locale: .current) }

    func libelle(locale: Locale) -> String {
        switch self {
        case .surnoms: traduire("Surnoms", locale)
        case .pieces: traduire("Pièces et dispositions", locale)
        case .nomsMaison: traduire("Relevé de Maison", locale)
        case .etatDesModules: traduire("Dernier état des réseaux", locale)
        case .historiqueSonde: traduire("Historique du maillage", locale)
        case .journal: traduire("Journal des événements", locale)
        case .autres: traduire("Autres fichiers", locale)
        }
    }
}

/// Ce que contient un export valide : de quoi remplir l'ecran de confirmation de l'assistant. Des comptes et des noms
/// de fichiers ou de reglages seulement, jamais une valeur lue.
struct ResumeExport: Equatable, Sendable {
    /// L'identifiant du manifeste (celui que garde `imports.json`).
    let identifiant: UUID
    let app: ContratExport.AppSource
    /// La version de l'ancienne app, telle que le manifeste la donne.
    let versionApp: String
    /// La date de l'export.
    let date: Date
    /// Le nombre de fichiers par famille (un fichier par mois pour l'historique et le journal) ; `reglages.json` non
    /// compte (voir `reglagesRepris`). Une famille sans fichier est absente.
    let fichiersParGenre: [GenreContenu: Int]
    /// La taille de tous les fichiers listes (`reglages.json` compris), en octets.
    let tailleTotale: Int64
    /// Le nombre de reglages repris.
    let reglagesRepris: Int
    /// Les cles des reglages que l'ancienne app a laisses (Sparkle, fenetres...), avec la raison : ignores a l'import,
    /// le resume final le dit.
    let reglagesNonRepris: [String: ContratExport.RaisonNonRepris]
    /// Les fichiers vus dans le dossier de l'ancienne app mais non copies, tries par chemin.
    let fichiersNonRepris: [ContratExport.FichierNonRepris]

    func nombre(_ genre: GenreContenu) -> Int { fichiersParGenre[genre] ?? 0 }

    // Textes du resume : le pluriel suit le catalogue (variations `one` / `other` de chaque cle), jamais un « s » colle.

    /// « 1 fichier », « 2 fichiers ».
    static func nombreDeFichiers(_ n: Int, locale: Locale) -> String { traduire("\(n) fichiers", locale) }

    /// « 1 réglage repris », « 2 réglages repris ».
    static func nombreDeReglagesRepris(_ n: Int, locale: Locale) -> String { traduire("\(n) réglages repris", locale) }

    /// « 1 réglage laissé de côté », « 2 réglages laissés de côté ».
    static func nombreDeReglagesLaissesDeCote(_ n: Int, locale: Locale) -> String {
        traduire("\(n) réglages laissés de côté", locale)
    }

    /// « 1 fichier non repris », « 2 fichiers non repris ».
    static func nombreDeFichiersNonRepris(_ n: Int, locale: Locale) -> String {
        traduire("\(n) fichiers non repris", locale)
    }

    /// La ligne d'une famille pour l'ecran de confirmation : « Surnoms : 1 fichier ».
    func ligne(_ genre: GenreContenu, locale: Locale) -> String {
        traduire("\(genre.libelle(locale: locale)) : \(Self.nombreDeFichiers(nombre(genre), locale: locale))", locale)
    }

    func texteReglagesRepris(locale: Locale) -> String { Self.nombreDeReglagesRepris(reglagesRepris, locale: locale) }

    func texteReglagesLaissesDeCote(locale: Locale) -> String {
        Self.nombreDeReglagesLaissesDeCote(reglagesNonRepris.count, locale: locale)
    }

    func texteFichiersNonRepris(locale: Locale) -> String {
        Self.nombreDeFichiersNonRepris(fichiersNonRepris.count, locale: locale)
    }

    init(manifeste: ContratExport.Manifeste, reglages: ContratExport.Reglages) {
        identifiant = manifeste.identifiant
        app = manifeste.app
        versionApp = manifeste.versionApp
        date = manifeste.date
        var comptes: [GenreContenu: Int] = [:]
        for fichier in manifeste.fichiers where fichier.chemin != ContratExport.nomReglages {
            comptes[GenreContenu.genre(de: fichier.chemin), default: 0] += 1
        }
        fichiersParGenre = comptes
        tailleTotale = manifeste.fichiers.reduce(0) { $0 + $1.taille }
        reglagesRepris = reglages.valeurs.count
        reglagesNonRepris = reglages.nonRepris
        fichiersNonRepris = manifeste.fichiersNonRepris
    }
}

// MARK: Journal des reprises (imports.json)

/// Une reprise deja faite : l'identifiant du manifeste de l'export, l'ancienne app, sa version et la date de la reprise.
struct ImportRepris: Codable, Equatable, Sendable {
    let identifiant: UUID
    let app: ContratExport.AppSource
    let versionApp: String
    /// Quand l'export a ete repris (pas la date de l'export).
    let date: Date
}

/// `imports.json`, dans `Application Support/Maillage IoT/` : les exports deja repris. Un export dont l'identifiant y
/// est ne se reprend pas une seconde fois (spec 4.3, idempotence). Format :
/// `{"version": 1, "imports": [{"identifiant": "<UUID>", "app": "thread" | "zigbee", "versionApp": "1.4.0",
/// "date": "2026-10-17T12:00:00Z"}]}` (encodeur du contrat : cles triees, dates ISO 8601). La tache 7 (application de
/// l'import) y ajoute une ligne, une fois la reprise reussie.
struct JournalImports: Codable, Equatable, Sendable {
    static let nomFichier = "imports.json"
    static let versionCourante = 1
    static let vide = JournalImports(imports: [])

    let version: Int
    let imports: [ImportRepris]

    init(imports: [ImportRepris]) {
        version = Self.versionCourante
        self.imports = imports
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == Self.versionCourante else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "version inconnue")
        }
        imports = try c.decode([ImportRepris].self, forKey: .imports)
    }

    /// La reprise de l'export dont le manifeste porte cet identifiant, si elle a eu lieu.
    func entree(pour identifiant: UUID) -> ImportRepris? {
        imports.first { $0.identifiant == identifiant }
    }

    /// Le fichier en JSON, tel qu'il s'ecrit.
    func donnees() throws -> Data {
        try ContratExport.encodeur().encode(self)
    }

    /// Lit `imports.json` du dossier de donnees : absent = aucune reprise (`vide`) ; present mais illisible (JSON
    /// invalide, version inconnue, champ manquant) = erreur, pour ne jamais prendre un journal abime pour un journal vide.
    static func lire(dans dossierDonnees: URL) throws -> JournalImports {
        let url = dossierDonnees.appendingPathComponent(nomFichier)
        guard FileManager.default.fileExists(atPath: url.path) else { return .vide }
        return try ContratExport.decodeur().decode(JournalImports.self, from: Data(contentsOf: url))
    }

    /// Nom de la copie d'un journal illisible, quand `imports.json.abime` existe deja.
    static func nomCopieAbimee(date: Date, rang: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "imports-\(f.string(from: date))\(rang > 1 ? "-\(rang)" : "").json.abime"
    }

    /// Met de cote un `imports.json` illisible (JSON invalide, vide, version inconnue...) : le fichier est renomme en
    /// `imports.json.abime` (ou `imports-AAAAMMJJ-HHMMSS.json.abime`, suivi d'un rang si besoin, quand ce nom existe
    /// deja), **jamais supprime ni ecrase**. Ensuite le journal est absent : la validation reprend comme si aucun import
    /// n'avait eu lieu (un export deja repris pourra etre propose de nouveau, sans danger : le premier import l'emporte
    /// et la reprise est idempotente fichier par fichier). Renvoie l'emplacement de la copie, ou `nil` quand il n'y a
    /// rien a mettre de cote : journal absent, ou lisible (un journal valide garde la trace des reprises faites).
    @discardableResult
    static func mettreDeCoteImportsAbime(dans dossierDonnees: URL, date: Date = .now) throws -> URL? {
        let fm = FileManager.default
        let url = dossierDonnees.appendingPathComponent(nomFichier)
        guard fm.fileExists(atPath: url.path) else { return nil }
        if (try? lire(dans: dossierDonnees)) != nil { return nil }
        var rang = 0
        while true {
            let nom = rang == 0 ? "\(nomFichier).abime" : nomCopieAbimee(date: date, rang: rang)
            let cible = dossierDonnees.appendingPathComponent(nom)
            rang += 1
            if fm.fileExists(atPath: cible.path) { continue }
            try fm.moveItem(at: url, to: cible)
            return cible
        }
    }
}

// MARK: Causes de refus

/// Le detail d'un `ContratExport.Erreur.illisible` ou d'une erreur de `reglages.json`, rendu traduisible : un champ ou
/// un chemin, jamais une valeur lue.
enum DetailIllisible: Equatable, Sendable {
    case jsonInvalide
    case champManquant(String)
    case typeInattendu(String)
    case valeurAbsente(String)
    case valeurInvalide(String?)
    case lectureImpossible
    case cleVide
    case cleEnDouble(String)
    case typeInconnu(cle: String, type: String)
    /// Un detail que cette version ne connait pas : montre tel quel.
    case autre(String)

    /// Relit le texte court du contrat (`Erreur.illisible`) ; ce sont des textes figes du contrat.
    init(contrat texte: String) {
        func apres(_ debut: String) -> String? { texte.hasPrefix(debut) ? String(texte.dropFirst(debut.count)) : nil }
        if texte == "JSON invalide" {
            self = .jsonInvalide
        } else if let champ = apres("champ manquant : ") {
            self = .champManquant(champ)
        } else if let champ = apres("type inattendu : ") {
            self = .typeInattendu(champ)
        } else if let champ = apres("valeur absente : ") {
            self = .valeurAbsente(champ)
        } else if let champ = apres("valeur invalide : ") {
            self = .valeurInvalide(champ)
        } else if texte == "valeur invalide" {
            self = .valeurInvalide(nil)
        } else if texte == "lecture impossible" {
            self = .lectureImpossible
        } else {
            self = .autre(texte)
        }
    }

    func texte(locale: Locale) -> String {
        switch self {
        case .jsonInvalide: traduire("JSON invalide", locale)
        case .champManquant(let c): traduire("champ manquant : \(affichable(c))", locale)
        case .typeInattendu(let c): traduire("type inattendu : \(affichable(c))", locale)
        case .valeurAbsente(let c): traduire("valeur absente : \(affichable(c))", locale)
        case .valeurInvalide(let c?): traduire("valeur invalide : \(affichable(c))", locale)
        case .valeurInvalide(nil): traduire("valeur invalide", locale)
        case .lectureImpossible: traduire("lecture impossible", locale)
        case .cleVide: traduire("réglage sans nom", locale)
        case .cleEnDouble(let c): traduire("réglage en double : \(affichable(c))", locale)
        case .typeInconnu(let c, let t): traduire("réglage \(affichable(c)) d'un type inconnu : \(affichable(t))", locale)
        case .autre(let t): affichable(t)
        }
    }
}

/// Pourquoi un export est refuse. Chaque erreur du contrat a sa cause ; `message` la dit en clair, dans la langue de
/// l'app. Les chemins viennent du manifeste (donc de l'export, qui peut etre altere) : ils sont nettoyes a l'affichage.
enum CauseRefus: Error, Equatable, Sendable {
    /// Le dossier n'a pas pu etre lu (droits, disque) : une erreur du systeme, pas du contrat.
    case dossierIllisible
    case manifesteAbsent
    case manifesteIllisible(DetailIllisible)
    case formatInconnu(Int)
    case appInconnue(String)
    /// L'app source est connue, pas sa version (`ValidationExport.versionEstPrise`).
    case versionNonPrise(app: ContratExport.AppSource, version: String)
    case cheminInvalide(String)
    case lienSymbolique(String)
    case empreinteInvalide(String)
    case tailleInvalide(String)
    case cheminEnDouble(String)
    case nomReserve(String)
    case reglagesAbsents
    case reglagesIllisibles(DetailIllisible)
    case fichierManquant(String)
    case fichierEnTrop(String)
    case fichierInconnu(String)
    case tailleFausse(String)
    case empreinteFausse(String)
    case appDifferente
    /// `imports.json` existe mais ne se lit pas : on ne sait pas si l'export est deja repris. `chemin` : le fichier, avec
    /// le dossier de l'app. La cause dit quoi faire (`JournalImports.mettreDeCoteImportsAbime`).
    case journalDesImportsIllisible(chemin: String)

    /// Le message, dans la langue de l'app.
    var message: String { texte(locale: .current) }

    func texte(locale: Locale) -> String {
        switch self {
        case .dossierIllisible:
            traduire("Le dossier d'export n'a pas pu être lu : vérifiez qu'il est complet et que Maillage IoT a le droit de le lire.", locale)
        case .manifesteAbsent:
            traduire("Ce dossier n'est pas un export de reprise : manifeste.json est absent.", locale)
        case .manifesteIllisible(let d):
            traduire("manifeste.json est illisible (\(d.texte(locale: locale))). Refaites l'export depuis l'ancienne app.", locale)
        case .formatInconnu(let n):
            traduire("Le format de cet export (\(n)) n'est pas pris en charge par cette version de Maillage IoT.", locale)
        case .appInconnue(let a):
            traduire("Cet export vient d'une app inconnue (« \(affichable(a)) »). Maillage IoT reprend Maillage Thread et Maillage Zigbee.", locale)
        case .versionNonPrise(let app, let version):
            switch ValidationExport.sens(de: version, app: app) {
            case .tropRecente:
                traduire("La version « \(affichable(version)) » de \(app.nomApp) est plus récente que celles que cette version de Maillage IoT sait reprendre (\(ValidationExport.seriesPrises(de: app, locale: locale))) : mettez Maillage IoT à jour, puis réessayez.", locale)
            case .tropAncienne:
                traduire("La version « \(affichable(version)) » de \(app.nomApp) est trop ancienne pour la reprise (versions acceptées : \(ValidationExport.seriesPrises(de: app, locale: locale))) : mettez \(app.nomApp) à jour, puis refaites l'export.", locale)
            case .inconnue:
                traduire("La version « \(affichable(version)) » de \(app.nomApp) n'est pas prise en charge : la reprise accepte les versions \(ValidationExport.seriesPrises(de: app, locale: locale)).", locale)
            }
        case .cheminInvalide(let c):
            traduire("Le chemin « \(affichable(c)) » est invalide ou sort du dossier d'export.", locale)
        case .lienSymbolique(let c):
            traduire("« \(affichable(c)) » est un lien symbolique : un export n'en contient pas.", locale)
        case .empreinteInvalide(let c):
            traduire("L'empreinte de « \(affichable(c)) » est mal formée dans le manifeste.", locale)
        case .tailleInvalide(let c):
            traduire("La taille de « \(affichable(c)) » est invalide dans le manifeste.", locale)
        case .cheminEnDouble(let c):
            traduire("« \(affichable(c)) » figure deux fois dans le manifeste.", locale)
        case .nomReserve(let c):
            traduire("Le manifeste liste « \(affichable(c)) », un nom réservé à l'export lui-même.", locale)
        case .reglagesAbsents:
            traduire("Le manifeste ne liste pas reglages.json.", locale)
        case .reglagesIllisibles(let d):
            traduire("reglages.json est illisible (\(d.texte(locale: locale))). Refaites l'export depuis l'ancienne app.", locale)
        case .fichierManquant(let c):
            traduire("Le fichier « \(affichable(c)) » est listé dans le manifeste mais absent du dossier.", locale)
        case .fichierEnTrop(let c):
            traduire("Le dossier contient « \(affichable(c)) », que le manifeste ne liste pas.", locale)
        case .fichierInconnu(let c):
            traduire("Le manifeste liste « \(affichable(c)) », qui n'est pas un fichier de cette app.", locale)
        case .tailleFausse(let c):
            traduire("« \(affichable(c)) » n'a pas la taille indiquée par le manifeste : le fichier est incomplet ou a été modifié.", locale)
        case .empreinteFausse(let c):
            traduire("« \(affichable(c)) » n'a pas l'empreinte indiquée par le manifeste : le fichier a été modifié ou abîmé.", locale)
        case .appDifferente:
            traduire("reglages.json vient d'une autre app que celle du manifeste.", locale)
        case .journalDesImportsIllisible(let chemin):
            traduire("Le journal des reprises de Maillage IoT est illisible (\(affichableChemin(chemin))) : impossible de savoir si cet export a déjà été repris. Mettez ce fichier de côté (il est renommé en imports.json.abime, jamais supprimé), puis recommencez : un export déjà repris pourra être proposé de nouveau, sans danger.", locale)
        }
    }
}

// MARK: Validation

/// La validation d'un dossier d'export avant tout import.
enum ValidationExport {
    /// Les series de versions de chaque ancienne app dont Maillage IoT connait les formats (voir `versionEstPrise`).
    static let series: [ContratExport.AppSource: [(majeure: Int, mineure: Int)]] = [
        .maillageThread: [(1, 3), (1, 4)],
        .maillageZigbee: [(1, 1), (1, 2)],
    ]

    /// La regle de version : on reprend **la serie de l'export et la precedente** de chaque ancienne app, toutes
    /// versions correctives comprises. Thread 1.3.x (la derniere version publiee, dont les formats sont ceux des
    /// exemples) et 1.4.x (la version qui ecrit l'export) ; Zigbee 1.1.x et 1.2.x. Toute autre serie est refusee, y
    /// compris une plus recente : ses fichiers ne sont pas connus, mieux vaut refuser que mal lire. La version doit
    /// etre numerique, de 2 a 4 composants de chiffres ASCII separes par des points, sans zero en tete (`1.4.0`, `1.4`) ;
    /// un suffixe (`1.4.0-beta`), un espace ou une version vide sont refuses.
    static func versionEstPrise(_ version: String, de app: ContratExport.AppSource) -> Bool {
        let composants = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(composants.count) else { return false }
        var nombres: [Int] = []
        for c in composants {
            guard !c.isEmpty, c.count <= 4, c.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  c == "0" || c.first != "0", let n = Int(c) else { return false }
            nombres.append(n)
        }
        return (series[app] ?? []).contains { $0.majeure == nombres[0] && $0.mineure == nombres[1] }
    }

    /// Pourquoi une version n'est pas prise : plus recente que toutes les series connues (il faut mettre Maillage IoT a
    /// jour), plus ancienne que toutes (il faut mettre l'ancienne app a jour et refaire l'export), ou autrement (version
    /// mal formee, ou dans les series mais refusee pour sa forme).
    enum SensVersion: Equatable, Sendable { case tropRecente, tropAncienne, inconnue }

    /// Le sens du refus d'une version, lu avec indulgence : les deux premiers composants, chiffres de tete seulement
    /// (`1.5.0-beta` est plus recente que 1.4). Sans serie lisible, ou dans l'intervalle des series : `inconnue`.
    static func sens(de version: String, app: ContratExport.AppSource) -> SensVersion {
        let composants = version.split(separator: ".", omittingEmptySubsequences: false)
        guard composants.count >= 2 else { return .inconnue }
        func nombre(_ c: Substring) -> Int? {
            let chiffres = c.prefix { $0.isASCII && $0.isNumber }
            return chiffres.isEmpty || chiffres.count > 9 ? nil : Int(chiffres)
        }
        guard let majeure = nombre(composants[0]), let mineure = nombre(composants[1]),
              let premiere = series[app]?.first, let derniere = series[app]?.last else { return .inconnue }
        func avant(_ a: (Int, Int), _ b: (majeure: Int, mineure: Int)) -> Bool {
            a.0 != b.majeure ? a.0 < b.majeure : a.1 < b.mineure
        }
        if avant((majeure, mineure), premiere) { return .tropAncienne }
        if avant((derniere.majeure, derniere.mineure), (majeure, mineure)) { return .tropRecente }
        return .inconnue
    }

    /// Les series prises d'une app, en texte (`1.3 et 1.4`), pour le message.
    static func seriesPrises(de app: ContratExport.AppSource, locale: Locale) -> String {
        let formateur = ListFormatter()
        formateur.locale = locale
        return formateur.string(from: (series[app] ?? []).map { "\($0.majeure).\($0.mineure)" }) ?? ""
    }

    /// Valide l'export du dossier et dit s'il est deja repris. Ne modifie rien. Les controles, dans l'ordre : le
    /// manifeste se lit (format, app, chemins) ; la version de l'app source est prise en charge ; puis le contrat
    /// verifie tout le dossier (`ContratExport.verifierDossier`) ; enfin l'identifiant est cherche dans `imports`. Un
    /// export altere est refuse meme s'il est deja repris.
    static func valider(dossier: URL, imports: JournalImports) -> ResultatValidation {
        // Le manifeste d'abord, pour dire "version non prise" plutot que "fichier inconnu" devant un export plus recent.
        do {
            if let cause = causeDeVersion(try lireManifeste(dossier)) { return .refuse(cause) }
        } catch {
            return .refuse(cause(error, etape: .manifeste))
        }
        let manifeste: ContratExport.Manifeste
        let reglages: ContratExport.Reglages
        do {
            (manifeste, reglages) = try ContratExport.verifierDossier(dossier)
        } catch {
            return .refuse(cause(error, etape: .dossier))
        }
        // Le manifeste que le contrat a verifie fait foi, au cas ou le fichier aurait change entre les deux lectures.
        if let cause = causeDeVersion(manifeste) { return .refuse(cause) }
        let resume = ResumeExport(manifeste: manifeste, reglages: reglages)
        if let reprise = imports.entree(pour: manifeste.identifiant) { return .dejaRepris(reprise, resume) }
        return .acceptee(resume)
    }

    /// `valider(dossier:imports:)` avec le journal des reprises lu dans le dossier de donnees de Maillage IoT
    /// (`imports.json`). Absent : aucune reprise. Illisible : refus (`journalDesImportsIllisible`, avec le chemin du
    /// fichier) ; `JournalImports.mettreDeCoteImportsAbime` le met de cote pour reprendre comme si aucun import n'avait eu lieu.
    static func valider(dossier: URL, dossierDonnees: URL) -> ResultatValidation {
        let imports: JournalImports
        do {
            imports = try JournalImports.lire(dans: dossierDonnees)
        } catch {
            return .refuse(.journalDesImportsIllisible(chemin: dossierDonnees.appendingPathComponent(JournalImports.nomFichier).path))
        }
        return valider(dossier: dossier, imports: imports)
    }

    // MARK: Interne

    private enum Etape { case manifeste, dossier }

    private static func lireManifeste(_ dossier: URL) throws -> ContratExport.Manifeste {
        let url = try ContratExport.resoudre(ContratExport.nomManifeste, dans: dossier)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ContratExport.Erreur.manifesteAbsent }
        let octets: Data
        do { octets = try Data(contentsOf: url) } catch { throw ContratExport.Erreur.illisible("lecture impossible") }
        return try ContratExport.lireManifeste(octets)
    }

    private static func causeDeVersion(_ manifeste: ContratExport.Manifeste) -> CauseRefus? {
        versionEstPrise(manifeste.versionApp, de: manifeste.app)
            ? nil : .versionNonPrise(app: manifeste.app, version: manifeste.versionApp)
    }

    /// Une erreur du contrat devient une cause. Pas de `default` : une erreur ajoutee au contrat doit etre traitee ici.
    /// A l'etape `dossier`, le manifeste est deja lu : un `illisible` ou une erreur de valeur vient de `reglages.json`.
    private static func cause(_ erreur: any Error, etape: Etape) -> CauseRefus {
        guard let e = erreur as? ContratExport.Erreur else { return .dossierIllisible }
        switch e {
        case .formatInconnu(let n): return .formatInconnu(n)
        case .appInconnue(let a): return .appInconnue(a)
        case .illisible(let d):
            return etape == .manifeste ? .manifesteIllisible(DetailIllisible(contrat: d))
                : .reglagesIllisibles(DetailIllisible(contrat: d))
        case .cheminInvalide(let c): return .cheminInvalide(c)
        case .lienSymbolique(let c): return .lienSymbolique(c)
        case .empreinteInvalide(let c): return .empreinteInvalide(c)
        case .tailleInvalide(let c): return .tailleInvalide(c)
        case .cheminEnDouble(let c): return .cheminEnDouble(c)
        case .nomReserve(let c): return .nomReserve(c)
        case .valeurInconnue(let cle, let type): return .reglagesIllisibles(.typeInconnu(cle: cle, type: type))
        case .cleInvalide: return .reglagesIllisibles(.cleVide)
        case .cleEnDouble(let cle): return .reglagesIllisibles(.cleEnDouble(cle))
        case .manifesteAbsent: return .manifesteAbsent
        case .reglagesAbsents: return .reglagesAbsents
        case .fichierManquant(let c): return .fichierManquant(c)
        case .fichierEnTrop(let c): return .fichierEnTrop(c)
        case .fichierInconnu(let c): return .fichierInconnu(c)
        case .tailleFausse(let c): return .tailleFausse(c)
        case .empreinteFausse(let c): return .empreinteFausse(c)
        case .appDifferente: return .appDifferente
        }
    }
}

// MARK: Outils de texte

/// Le texte dans la langue demandee (le catalogue de l'app a le francais et l'anglais).
private func traduire(_ ressource: LocalizedStringResource, _ locale: Locale) -> String {
    var r = ressource
    r.locale = locale
    return String(localized: r)
}

/// Un nom venu de l'export, sur un seul rang et de longueur bornee : sans caractere de controle ni de mise en forme
/// (retour a la ligne, inversion du sens d'ecriture), coupe a 60 caracteres.
private func affichable(_ texte: String) -> String {
    let propre = String(String.UnicodeScalarView(texte.unicodeScalars.filter {
        $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
    }))
    return propre.count > 60 ? String(propre.prefix(60)) + "…" : propre
}

/// Un chemin de fichier de l'app, nettoye comme `affichable` mais coupe au **debut** (jamais la fin : c'est le nom du
/// fichier qui compte), a 200 caracteres.
private func affichableChemin(_ chemin: String) -> String {
    let propre = String(String.UnicodeScalarView(chemin.unicodeScalars.filter {
        $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
    }))
    return propre.count > 200 ? "…" + String(propre.suffix(199)) : propre
}
