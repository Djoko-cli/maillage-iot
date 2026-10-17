import Foundation
import MaillageCoeur
import ProtocoleThread

// Phase 4, tache 4 : les regles de fusion d'un export avec ce que Maillage IoT a deja, partagees par la conversion de
// Thread (`ConversionThread`) et celle de Zigbee (tache 5). Deux niveaux :
// - `FusionReprise` : fonctions pures (fusion de dictionnaires, de surnoms, de pieces, de places ; ajout de lignes sans
//   doublon ; coupe a 90 jours ; cle de reglage cible) ;
// - `ConstructionPlan` : lit l'export et l'etat actuel de l'app (lecture seule), applique la regle de chaque fichier et
//   range le resultat dans un `PlanReprise`.
//
// Les regles, qui priment (spec 4.3 et 6.8) :
// 1. Un choix deja fait dans Maillage IoT n'est jamais ecrase : sur une cle commune, l'existant l'emporte ; l'export
//    n'ajoute que ce qui manque. Les entrees refusees sont comptees et citees (`ElementNonPris.entrees`).
// 2. Un fichier de Maillage IoT illisible ou d'une version plus recente n'est jamais touche : le fichier de l'export est
//    cite (`fichierExistantNonLisible`), pas fusionne a l'aveugle.
// 3. Un fichier de l'export qui n'apporte rien (tout y est deja) n'est pas redepose : il est cite (`dejaDansMaillageIoT`).
// 4. Un fichier de l'export illisible n'est pas repris et est cite (`fichierIllisible`) ; le reste de la reprise continue.
// 5. Sans fichier existant, un fichier qui n'a rien a convertir est copie TEL QUEL (memes octets, empreinte reverifiable).

enum FusionReprise {
    // MARK: Lecture sure d'un fichier garde

    /// Etat d'un fichier JSON a version dans le dossier de l'app, comme `FichiersGardes` : absent, lu, ou a ne pas toucher
    /// (illisible, d'une version plus recente ou d'un schema inconnu).
    enum Lecture<T> {
        case absente
        case lue(T)
        case nonLisible
    }

    private struct SeulementVersion: Decodable {
        var version: Int
    }

    static func lire<T: Decodable>(_ type: T.Type, _ url: URL, version maximale: Int) -> Lecture<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absente }
        guard let donnees = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode(SeulementVersion.self, from: donnees), v.version <= maximale,
              let contenu = try? JSONDecoder().decode(T.self, from: donnees) else { return .nonLisible }
        return .lue(contenu)
    }

    /// Le meme encodage que `FichiersGardes.ecrire` (cles triees, indente) : les fichiers ecrits par la reprise sont ceux
    /// que l'app ecrirait.
    static func encodeur() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }

    /// Un objet JSON de premier niveau ; nil si le fichier manque, est illisible ou n'est pas un objet.
    static func objet(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return objet(d)
    }

    static func objet(_ donnees: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: donnees) as? [String: Any]
    }

    /// Un dictionnaire plat de textes (`surnoms.json` et `associations.json` d'avant).
    static func objetPlat(_ donnees: Data) -> [String: String]? {
        guard let o = objet(donnees) else { return nil }
        var plat: [String: String] = [:]
        for (c, v) in o {
            guard let t = v as? String else { return nil }
            plat[c] = t
        }
        return plat
    }

    private struct Recu: Decodable {
        var recu: Date
    }

    /// La date de reception d'un `dernier-maillage.json` ; nil s'il est illisible.
    static func recu(_ donnees: Data) -> Date? {
        (try? CodageJSON.decodeur().decode(Recu.self, from: donnees))?.recu
    }

    // MARK: Fusion de dictionnaires

    /// `existant` plus ce qui manque de `importe`. `refuses` : les cles des deux cotes dont les valeurs different (celle de
    /// `existant` reste) ; deux valeurs egales ne sont pas un conflit.
    static func fusionner<K: Hashable, V: Equatable>(_ existant: [K: V], avec importe: [K: V]) -> (fusion: [K: V], refuses: Int) {
        var fusion = existant
        var refuses = 0
        for (cle, valeur) in importe {
            if let e = existant[cle] {
                if e != valeur { refuses += 1 }
            } else {
                fusion[cle] = valeur
            }
        }
        return (fusion, refuses)
    }

    /// Les choix de pieces : par domicile, `existant` d'abord, puis ce qui manque.
    static func fusionner(_ existant: PiecesRouteurs, avec importe: PiecesRouteurs) -> (fusion: PiecesRouteurs, refuses: Int) {
        var fusion = existant
        var refuses = 0
        for (domicile, choix) in importe.maisons where !choix.isEmpty {
            let (f, n) = fusionner(existant.maisons[domicile] ?? [:], avec: choix)
            fusion.maisons[domicile] = f
            refuses += n
        }
        for (domicile, choix) in importe.appareils where !choix.isEmpty {
            let (f, n) = fusionner(existant.appareils[domicile] ?? [:], avec: choix)
            fusion.appareils[domicile] = f
            refuses += n
        }
        return (fusion, refuses)
    }

    /// Les places des pieces, en profondeur : domicile, puis etage, puis piece. L'ordre des etages garde l'existant et
    /// ajoute a la suite les etages qui manquent ; les choix de niveau (`aCote`) et les places de l'existant l'emportent.
    static func fusionner(_ existant: PlacesGardees, avec importe: PlacesGardees) -> (fusion: PlacesGardees, refuses: Int) {
        var fusion = existant
        var refuses = 0
        for (domicile, maisonImportee) in importe.maisons {
            guard var maison = fusion.maisons[domicile] else {
                fusion.maisons[domicile] = maisonImportee
                continue
            }
            for etage in maisonImportee.ordreEtages where !maison.ordreEtages.contains(etage) {
                maison.ordreEtages.append(etage)
            }
            for (etage, pieces) in maisonImportee.etages {
                let (f, n) = fusionner(maison.etages[etage] ?? [:], avec: pieces)
                maison.etages[etage] = f
                refuses += n
            }
            let (aCote, n) = fusionner(maison.aCote, avec: maisonImportee.aCote)
            maison.aCote = aCote
            refuses += n
            fusion.maisons[domicile] = maison
        }
        return (fusion, refuses)
    }

    // MARK: Lignes d'un fichier mensuel

    /// Les lignes d'un fichier JSON Lines : non vides, telles quelles (aucun octet change).
    static func lignes(_ donnees: Data) -> [Data] {
        donnees.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }

    /// Regle de doublon du journal et de l'historique : une ligne de l'export est un doublon si une ligne IDENTIQUE (memes
    /// octets) est deja dans le fichier de Maillage IoT. L'existant sert seul de reference : les lignes de l'export entre
    /// elles ne se dedoublonnent pas (on les prend telles quelles). Le resultat est l'existant, inchange, suivi des lignes
    /// de l'export qui n'y sont pas, dans l'ordre de l'export, chacune terminee par une fin de ligne (l'app ajoute ses
    /// lignes a la suite du fichier : sans fin de ligne, la premiere se collerait a la derniere). Les lecteurs trient par
    /// date : l'ordre dans le fichier ne compte pas.
    static func ajouter(existant: Data, importees: [Data]) -> (donnees: Data, ajoutees: Int, dejaPresentes: Int) {
        let connues = Set(lignes(existant))
        var sortie = existant
        var ajoutees = 0
        var dejaPresentes = 0
        for l in importees {
            if connues.contains(l) {
                dejaPresentes += 1
                continue
            }
            if ajoutees == 0, let dernier = sortie.last, dernier != 0x0A { sortie.append(0x0A) }
            sortie.append(l)
            sortie.append(0x0A)
            ajoutees += 1
        }
        return (sortie, ajoutees, dejaPresentes)
    }

    /// Le fichier se termine-t-il par une fin de ligne (ou est-il vide) ? Seul le dernier octet est lu.
    static func finitParFinDeLigne(_ url: URL) throws -> Bool {
        let f = try FileHandle(forReadingFrom: url)
        defer { try? f.close() }
        let fin = try f.seekToEnd()
        guard fin > 0 else { return true }
        try f.seek(toOffset: fin - 1)
        return try f.read(upToCount: 1)?.first == 0x0A
    }

    // MARK: Coupe a 90 jours

    /// Le mois d'un fichier mensuel (`maillage-AAAA-MM.jsonl`, `Journal/journal-AAAA-MM.jsonl`) est-il fini depuis plus de
    /// 90 jours ? La meme regle que la purge de l'app (`FichiersMensuels.purger`) : fin du mois dans le calendrier donne
    /// (celui des noms de fichiers de l'ancienne app), strictement plus de 90 jours avant `maintenant`. nil si le chemin
    /// n'est pas celui d'un fichier mensuel.
    static func moisEstTropAncien(_ chemin: String, maintenant: Date, calendrier: Calendar) -> Bool? {
        guard let m = ContratExport.mois(de: chemin),
              let debut = calendrier.date(from: DateComponents(year: m.annee, month: m.mois, day: 1)),
              let fin = calendrier.date(byAdding: .month, value: 1, to: debut) else { return nil }
        return maintenant.timeIntervalSince(fin) > FichiersMensuels.conservation
    }

    // MARK: Reglages

    /// Les reglages communs aux deux protocoles : meme cle dans Maillage IoT (premier import l'emporte).
    private static let reglagesCommuns: Set<String> = [
        "vuePieces3D", "etagesEnGrille", "legendeRepliee", "grapheDejaOuvert", "ouvertureSessionProposee", "AppleLanguages",
    ]

    private static func protocole(de app: ContratExport.AppSource) -> Protocole {
        switch app {
        case .maillageThread: .thread
        case .maillageZigbee: .zigbee
        }
    }

    /// La cle de Maillage IoT d'un reglage de l'ancienne app ; nil si l'app ne le reprend pas. `sonde*`,
    /// `scissionsNotifiees`, `pont.hue`, `liensMontres`, `voisinsALaSelection` prennent le prefixe du protocole
    /// (`thread.`, `zigbee.`) ; `notification.<categorie>` devient `notification.<protocole>.<categorie>` (jamais la cle
    /// commune de 3a, que l'app recopierait aux deux protocoles) ; les reglages communs gardent leur cle.
    static func cibleReglage(_ cle: String, de app: ContratExport.AppSource) -> String? {
        guard ContratExport.typeAttendu(cle: cle, de: app) != nil else { return nil }
        let prefixe = protocole(de: app).rawValue
        if let categorie = cle.hasPrefix("notification.") ? String(cle.dropFirst("notification.".count)) : nil {
            return "notification.\(prefixe).\(categorie)"
        }
        if reglagesCommuns.contains(cle) { return cle }
        if cle.hasPrefix("sonde") || ["scissionsNotifiees", "pont.hue", "liensMontres", "voisinsALaSelection"].contains(cle) {
            return "\(prefixe).\(cle)"
        }
        return nil
    }

    /// La cle commune de 3a (`notification.<categorie>`) d'un reglage de notification ; nil pour tout autre reglage. Posee
    /// dans Maillage IoT, elle fait foi pour le protocole tant que sa cle propre manque (`Notifications.active`) : ecrire la
    /// cle du protocole la remplacerait.
    static func cleCommuneDeNotification(_ cle: String, de app: ContratExport.AppSource) -> String? {
        guard cle.hasPrefix("notification."), ContratExport.typeAttendu(cle: cle, de: app) != nil else { return nil }
        return cle
    }

    // MARK: Schemas ecrits

    /// `surnoms.json` v1 (`Surnoms`).
    struct SurnomsV1: Codable {
        var version = 1
        var surnoms: [String: String]
    }

    /// `associations.json` v1 (`Associations`).
    struct AssociationsV1: Codable {
        var version = 1
        var associations: [String: String]
    }
}

// MARK: - Construction d'un plan

/// Lit un export et l'etat actuel de l'app (lecture seule), applique la regle de chaque fichier, et range le resultat. Les
/// chemins cites (`ElementNonPris`) sont ceux de l'EXPORT.
struct ConstructionPlan {
    let app: ContratExport.AppSource
    private let dossier: URL
    private let manifeste: ContratExport.Manifeste
    private let etat: EtatActuel
    private let maintenant: Date
    private let calendrier: Calendar
    private var fichiers: [FichierAPlacer] = []
    private var reglagesAEcrire: [String: ContratExport.Valeur] = [:]
    private var nonPris: [ElementNonPris] = []

    init(dossier: URL, manifeste: ContratExport.Manifeste, etat: EtatActuel, maintenant: Date, calendrier: Calendar) {
        app = manifeste.app
        self.dossier = dossier
        self.manifeste = manifeste
        self.etat = etat
        self.maintenant = maintenant
        self.calendrier = calendrier
    }

    typealias Raison = ElementNonPris.Raison

    // MARK: Briques

    private func urlExport(_ chemin: String) throws -> URL {
        do { return try ContratExport.resoudre(chemin, dans: dossier) } catch { throw ErreurConversion.lectureImpossible(chemin) }
    }

    private func lireExport(_ chemin: String) throws -> Data {
        do { return try Data(contentsOf: try urlExport(chemin)) } catch { throw ErreurConversion.lectureImpossible(chemin) }
    }

    private func existant(_ chemin: String) -> URL { etat.dossier.appendingPathComponent(chemin) }

    private func empreinte(_ chemin: String) throws -> String {
        guard let f = manifeste.fichiers.first(where: { $0.chemin == chemin }) else { throw ErreurConversion.lectureImpossible(chemin) }
        return f.sha256
    }

    private mutating func placer(_ chemin: String, _ contenu: ContenuAPlacer, sources: [String]) {
        fichiers.append(FichierAPlacer(chemin: chemin, contenu: contenu, sources: sources))
    }

    /// Copie le fichier de l'export tel quel.
    private mutating func copier(_ source: String, vers chemin: String) throws {
        placer(chemin, .copie(try urlExport(source), sha256: try empreinte(source)), sources: [source])
    }

    private mutating func laisser(_ nature: ElementNonPris.Nature, _ raison: Raison) {
        nonPris.append(ElementNonPris(nature: nature, raison: raison))
    }

    // MARK: Surnoms

    /// `surnoms.json` plat (cles brutes d'un seul protocole) -> `surnoms.json` v1 (`<protocole>:<cle>`), fusionne avec celui
    /// de Maillage IoT. Le lecteur d'avant (`Surnoms.lire`) fait la conversion des cles.
    mutating func surnoms(_ chemin: String, protocole: Protocole) throws {
        let source = try urlExport(chemin)
        let brut = try lireExport(chemin)
        let lus = Surnoms.lire(source, protocoleParDefaut: protocole)
        guard let plat = FusionReprise.objetPlat(brut), lus.count == plat.count else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        // Une cle vide donnerait « thread: » : le lecteur de l'app prendrait tout le fichier pour celui d'une app plus
        // recente (`IdNoeud(texte:)` nil) et ne le reecrirait plus jamais.
        let importes = lus.filter { !$0.key.cle.isEmpty }
        if importes.count < lus.count { laisser(.entrees(fichier: chemin, nombre: lus.count - importes.count), .fichierIllisible) }
        guard !importes.isEmpty else {
            if lus.isEmpty { laisser(.fichier(chemin), .vide) }
            return
        }
        var presents: [IdNoeud: String] = [:]
        switch FusionReprise.lire(FusionReprise.SurnomsV1.self, existant("surnoms.json"), version: 1) {
        case .absente:
            break
        case .nonLisible:
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        case .lue(let f):
            for (cle, surnom) in f.surnoms {
                guard let id = IdNoeud(texte: cle) else {
                    laisser(.fichier(chemin), .fichierExistantNonLisible)
                    return
                }
                presents[id] = surnom
            }
        }
        let (fusion, refuses) = FusionReprise.fusionner(presents, avec: importes)
        if refuses > 0 { laisser(.entrees(fichier: chemin, nombre: refuses), .dejaDansMaillageIoT) }
        guard fusion != presents else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
            return
        }
        let fichier = FusionReprise.SurnomsV1(surnoms: Dictionary(uniqueKeysWithValues: fusion.map { ($0.key.texte, $0.value) }))
        placer("surnoms.json", .donnees(try FusionReprise.encodeur().encode(fichier)), sources: [chemin])
    }

    // MARK: Pieces choisies

    /// `pieces-routeurs.json` (v1, cles brutes) -> `pieces-noeuds.json` (v2, cles `<protocole>:<cle>`), fusionne avec celui
    /// de Maillage IoT. Le fichier d'avant n'est jamais depose sous son nom : l'app le relirait sous le protocole Thread.
    mutating func pieces(_ chemin: String, protocole: Protocole) throws {
        let source = try urlExport(chemin)
        guard let objet = FusionReprise.objet(try lireExport(chemin)), objet["version"] as? Int == 1 else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        // Le fichier d'avant ne doit pas exister sous le nom du nouveau : l'export n'a que des fichiers connus.
        let lu = PiecesRouteurs.lire(dossier.appendingPathComponent("pieces-noeuds.json"), ancien: source, protocoleParDefaut: protocole)
        // Le lecteur rend un choix vide pour un champ mal forme : on compare aux comptes du fichier pour ne rien perdre.
        guard Self.comptes(objet, lu) else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        var importe = PiecesRouteurs()
        var ignores = 0
        for (domicile, choix) in lu.maisons {
            let valides = choix.filter { !$0.key.cle.isEmpty }
            ignores += choix.count - valides.count
            if !valides.isEmpty { importe.maisons[domicile] = valides }
        }
        for (domicile, choix) in lu.appareils {
            let valides = choix.filter { !$0.key.cle.isEmpty }
            ignores += choix.count - valides.count
            if !valides.isEmpty { importe.appareils[domicile] = valides }
        }
        if ignores > 0 { laisser(.entrees(fichier: chemin, nombre: ignores), .fichierIllisible) }
        guard !importe.maisons.isEmpty || !importe.appareils.isEmpty else {
            if ignores == 0 { laisser(.fichier(chemin), .vide) }
            return
        }
        var presentes = PiecesRouteurs()
        switch FusionReprise.lire(PiecesRouteurs.self, existant("pieces-noeuds.json"), version: PiecesRouteurs.versionActuelle) {
        case .absente: break
        case .nonLisible:
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        case .lue(let p): presentes = p
        }
        let (fusion, refuses) = FusionReprise.fusionner(presentes, avec: importe)
        if refuses > 0 { laisser(.entrees(fichier: chemin, nombre: refuses), .dejaDansMaillageIoT) }
        guard fusion != presentes else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
            return
        }
        placer("pieces-noeuds.json", .donnees(try FusionReprise.encodeur().encode(fusion)), sources: [chemin])
    }

    /// Le fichier de la version 1 a-t-il ete lu en entier ? Autant de choix lus que d'entrees dans le fichier (les adresses
    /// longues qui ne different que par la casse se rejoignent).
    private static func comptes(_ objet: [String: Any], _ lu: PiecesRouteurs) -> Bool {
        func entrees(_ cle: String, majuscules: Bool) -> Int? {
            guard let brut = objet[cle] else { return 0 }
            guard let domiciles = brut as? [String: [String: String]] else { return nil }
            return domiciles.values.reduce(0) { total, choix in
                total + (majuscules ? Set(choix.keys.map { $0.uppercased() }).count : choix.count)
            }
        }
        guard let maisons = entrees("maisons", majuscules: false), let appareils = entrees("appareils", majuscules: true) else {
            return false
        }
        return maisons == lu.maisons.values.reduce(0) { $0 + $1.count }
            && appareils == lu.appareils.values.reduce(0) { $0 + $1.count }
    }

    // MARK: Places des pieces

    /// `positions-pieces.json` : fusion en profondeur (domicile, etage, piece) avec celui de Maillage IoT. Les cles ne sont
    /// pas prefixees.
    mutating func positions(_ chemin: String) throws {
        let source = try urlExport(chemin)
        guard case .lue(let importe) = FusionReprise.lire(PlacesGardees.self, source, version: PlacesGardees.versionActuelle) else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard !importe.maisons.isEmpty else {
            laisser(.fichier(chemin), .vide)
            return
        }
        switch FusionReprise.lire(PlacesGardees.self, existant(chemin), version: PlacesGardees.versionActuelle) {
        case .absente:
            try copier(chemin, vers: chemin)
        case .nonLisible:
            laisser(.fichier(chemin), .fichierExistantNonLisible)
        case .lue(let presentes):
            let (fusion, refuses) = FusionReprise.fusionner(presentes, avec: importe)
            if refuses > 0 { laisser(.entrees(fichier: chemin, nombre: refuses), .dejaDansMaillageIoT) }
            if fusion == presentes {
                laisser(.fichier(chemin), .dejaDansMaillageIoT)
            } else {
                placer(chemin, .donnees(try FusionReprise.encodeur().encode(fusion)), sources: [chemin])
            }
        }
    }

    // MARK: Releve de Maison

    /// Le releve de Maison de l'export (`noms.json` de Thread, `releve-maison.json` de Zigbee) -> `releve-maison.json`, sans
    /// prefixe ni autre changement : pris seulement si Maillage IoT n'en a pas, ou si celui de l'export est strictement plus
    /// recent (sa date). Les deux sont des caches que le demon reecrit a la premiere connexion.
    mutating func releveDeMaison(_ chemin: String) throws {
        let cible = "releve-maison.json"
        guard let importe = try? NomsMaison.lire(try lireExport(chemin)) else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            try copier(chemin, vers: cible)
            return
        }
        guard let donnees = try? Data(contentsOf: existant(cible)), let present = try? NomsMaison.lire(donnees) else {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        }
        if importe.date > present.date {
            try copier(chemin, vers: cible)
        } else {
            laisser(.fichier(chemin), .releveMaisonNonPlusRecent)
        }
    }

    // MARK: Fichiers d'un module

    /// `associations.json` (plat, ou v1) : fusion des cles, l'existant gagne ; sans existant, copie telle quelle.
    mutating func associations(_ chemin: String, vers cible: String) throws {
        guard let importees = Self.associations(try lireExport(chemin)) else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            try copier(chemin, vers: cible)
            return
        }
        guard let donnees = try? Data(contentsOf: existant(cible)), let presentes = Self.associations(donnees) else {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        }
        let (fusion, refuses) = FusionReprise.fusionner(presentes, avec: importees)
        if refuses > 0 { laisser(.entrees(fichier: chemin, nombre: refuses), .dejaDansMaillageIoT) }
        guard fusion != presentes else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
            return
        }
        placer(cible, .donnees(try FusionReprise.encodeur().encode(FusionReprise.AssociationsV1(associations: fusion))), sources: [chemin])
    }

    /// Les associations d'un fichier plat ou v1 ; nil s'il est illisible ou d'une version plus recente.
    private static func associations(_ donnees: Data) -> [String: String]? {
        if let plat = FusionReprise.objetPlat(donnees) { return plat }
        guard let objet = FusionReprise.objet(donnees), let version = objet["version"] as? Int, version == 1 else { return nil }
        return objet["associations"] as? [String: String]
    }

    /// `identites-routeurs.json` : propre a une partition. Sans existant, copie ; avec un existant lisible, il est garde
    /// (on ne melange pas les identites de deux partitions).
    mutating func identitesDeRouteurs(_ chemin: String, vers cible: String) throws {
        guard let objet = FusionReprise.objet(try lireExport(chemin)), objet["partition"] is String, objet["routeurs"] is [String: String] else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            try copier(chemin, vers: cible)
            return
        }
        if FusionReprise.objet(existant(cible)) == nil {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
        } else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
        }
    }

    /// `dernier-maillage.json` : un cache, la reception la plus recente (`recu`) l'emporte ; sans existant, copie.
    mutating func dernierMaillage(_ chemin: String, vers cible: String) throws {
        guard let recu = FusionReprise.recu(try lireExport(chemin)) else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            try copier(chemin, vers: cible)
            return
        }
        guard let donnees = try? Data(contentsOf: existant(cible)), let present = FusionReprise.recu(donnees) else {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        }
        if recu > present {
            try copier(chemin, vers: cible)
        } else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
        }
    }

    /// `dernieres-adresses.json` : fusion des appareils, l'existant gagne ; sans existant, copie.
    mutating func dernieresAdresses(_ chemin: String, vers cible: String) throws {
        guard let objet = FusionReprise.objet(try lireExport(chemin)), let importes = objet["appareils"] as? [String: Any] else {
            laisser(.fichier(chemin), .fichierIllisible)
            return
        }
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            try copier(chemin, vers: cible)
            return
        }
        guard var present = FusionReprise.objet(existant(cible)), let presents = present["appareils"] as? [String: Any] else {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        }
        var fusion = presents
        var refuses = 0
        for (cle, valeur) in importes {
            if let e = presents[cle] {
                if !((e as? NSObject)?.isEqual(valeur as? NSObject) ?? false) { refuses += 1 }
            } else {
                fusion[cle] = valeur
            }
        }
        if refuses > 0 { laisser(.entrees(fichier: chemin, nombre: refuses), .dejaDansMaillageIoT) }
        guard fusion.count > presents.count else {
            laisser(.fichier(chemin), .dejaDansMaillageIoT)
            return
        }
        present["appareils"] = fusion
        let donnees = try JSONSerialization.data(withJSONObject: present, options: [.sortedKeys, .withoutEscapingSlashes])
        placer(cible, .donnees(donnees), sources: [chemin])
    }

    // MARK: Fichiers mensuels (historique, journal)

    /// Un fichier mensuel : ecarte si son mois est fini depuis plus de 90 jours ; sinon copie tel quel (sans existant), ou
    /// ajoute a la suite de celui de Maillage IoT sans doublon de ligne (`FusionReprise.ajouter`). Aucune ligne n'est
    /// reecrite.
    mutating func mensuel(_ chemin: String, vers cible: String) throws {
        if FusionReprise.moisEstTropAncien(chemin, maintenant: maintenant, calendrier: calendrier) == true {
            laisser(.fichier(chemin), .plusDe90Jours)
            return
        }
        let source = try urlExport(chemin)
        guard FileManager.default.fileExists(atPath: existant(cible).path) else {
            let finit: Bool
            do { finit = try FusionReprise.finitParFinDeLigne(source) } catch { throw ErreurConversion.lectureImpossible(chemin) }
            guard manifeste.fichiers.first(where: { $0.chemin == chemin })?.taille != 0 else {
                laisser(.fichier(chemin), .vide)
                return
            }
            if finit {
                try copier(chemin, vers: cible)
            } else {
                // Sans fin de ligne, la premiere ligne que l'app ajoute se collerait a la derniere.
                placer(cible, .donnees(FusionReprise.ajouter(existant: Data(), importees: FusionReprise.lignes(try lireExport(chemin))).donnees),
                       sources: [chemin])
            }
            return
        }
        guard let present = try? Data(contentsOf: existant(cible)) else {
            laisser(.fichier(chemin), .fichierExistantNonLisible)
            return
        }
        let importees = FusionReprise.lignes(try lireExport(chemin))
        let resultat = FusionReprise.ajouter(existant: present, importees: importees)
        if resultat.ajoutees > 0 {
            if resultat.dejaPresentes > 0 { laisser(.entrees(fichier: chemin, nombre: resultat.dejaPresentes), .dejaDansMaillageIoT) }
            placer(cible, .donnees(resultat.donnees), sources: [chemin])
        } else {
            laisser(.fichier(chemin), importees.isEmpty ? .vide : .dejaDansMaillageIoT)
        }
    }

    // MARK: Reglages et ce que l'ancienne app laisse

    /// Les reglages de l'export -> les cles de Maillage IoT. Une cle deja posee dans Maillage IoT (ou, pour une notification,
    /// sa cle commune de 3a) n'est jamais ecrasee ; une cle absente de l'export reste absente (jamais de defaut) ; ce que
    /// l'ancienne app a laisse est cite.
    mutating func reglages(_ r: ContratExport.Reglages) {
        for cle in r.valeurs.keys.sorted() {
            guard let cible = FusionReprise.cibleReglage(cle, de: app), let valeur = r.valeurs[cle] else {
                laisser(.reglage(cle), .sansEquivalent)
                continue
            }
            var present = etat.reglagesPresents.contains(cible)
            if let commune = FusionReprise.cleCommuneDeNotification(cle, de: app), etat.reglagesPresents.contains(commune) {
                present = true
            }
            if present {
                laisser(.reglage(cle), .dejaDansMaillageIoT)
            } else {
                reglagesAEcrire[cible] = valeur
            }
        }
        for (cle, raison) in r.nonRepris { laisser(.reglage(cle), .laisseParLAncienneApp(raison)) }
    }

    /// Les fichiers que l'export a vus sans les copier (`.DS_Store`, fichiers hors contrat) : cites.
    mutating func fichiersLaissesParLExport() {
        for f in manifeste.fichiersNonRepris { laisser(.fichier(f.chemin), .laisseParLAncienneApp(f.raison)) }
    }

    /// Un fichier de l'export qu'aucune regle ne place : cite plutot que perdu.
    mutating func sansEquivalent(_ chemin: String) {
        laisser(.fichier(chemin), .sansEquivalent)
    }

    // MARK: Resultat

    func plan() -> PlanReprise {
        PlanReprise(app: app, fichiers: fichiers.sorted { $0.chemin < $1.chemin }, reglages: reglagesAEcrire,
                    nonPris: ElementNonPris.trier(nonPris))
    }
}
