import Foundation
import Testing

/// Une app et ses catalogues de textes. Deux apps, tant que l'app de transition Zigbee existe (etape 2) : leurs deux
/// catalogues restent separes jusqu'a l'etape 3.
struct AppCatalogue: Sendable, CustomTestStringConvertible {
    /// Nom de la cible et de son dossier de sources (`MaillageIoT`, `MaillageIoTZigbee`).
    let nom: String
    var testDescription: String { nom }

    static let toutes = [AppCatalogue(nom: "MaillageIoT"), AppCatalogue(nom: "MaillageIoTZigbee")]

    var textes: URL { Catalogues.racine.appendingPathComponent("\(nom)/Ressources/Localizable.xcstrings") }
    var infoPlist: URL { Catalogues.racine.appendingPathComponent("\(nom)/Ressources/InfoPlist.xcstrings") }

    /// `.stringsdata` de l'app :
    /// `Build/Intermediates.noindex/MaillageIoT.build/<config>/<App>.build/Objects-normal/<arch>/` (le premier
    /// `MaillageIoT.build` est celui du projet, le second celui de la cible).
    var stringsdata: [URL] {
        let produits = Catalogues.produits
        let config = produits.lastPathComponent
        let objets = produits.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Intermediates.noindex/MaillageIoT.build")
            .appendingPathComponent(config)
            .appendingPathComponent("\(nom).build/Objects-normal")
        let fm = FileManager.default
        var fichiers: [URL] = []
        for arch in (try? fm.contentsOfDirectory(at: objets, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: arch, includingPropertiesForKeys: nil)) ?? []
            where f.pathExtension == "stringsdata" {
                fichiers.append(f)
            }
        }
        return fichiers
    }

    /// Cles extraites du code de l'app (table Localizable).
    func clesExtraites() throws -> Set<String> {
        var cles = Set<String>()
        for f in stringsdata {
            let d = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [String: Any]
            let tables = d?["tables"] as? [String: [[String: Any]]] ?? [:]
            for e in tables["Localizable"] ?? [] {
                if let k = e["key"] as? String { cles.insert(k) }
            }
        }
        return cles
    }
}

/// Ce que le test d'alignement fait d'une app, selon les `.stringsdata` trouves (voir `AppCatalogue.cas`).
enum CasCatalogue: Equatable {
    case verifier
    case sauter(String)
    case echouer(String)
}

extension AppCatalogue {
    /// Le cas d'une app d'apres le nombre de `.stringsdata` de chaque app (`nombres`, par nom) :
    /// - elle en a : on verifie ;
    /// - aucune app n'en a (mesure Release, schema du coeur seul : rien n'est compile) : on saute ;
    /// - elle n'en a pas mais une autre en a : on echoue, car le produit de cette app manque alors que les autres sont la.
    static func cas(_ app: String, nombres: [String: Int]) -> CasCatalogue {
        if nombres[app, default: 0] > 0 { return .verifier }
        if nombres.values.contains(where: { $0 > 0 }) {
            return .echouer("produits de compilation introuvables pour \(app), alors qu'une autre app a les siens")
        }
        return .sauter("produits de compilation introuvables : \(app)")
    }
}

/// Un catalogue (textes ou Info.plist) d'une app.
struct FichierCatalogue: Sendable, CustomTestStringConvertible {
    let app: AppCatalogue
    let chemin: URL
    let genre: String
    var testDescription: String { "\(app.nom) : \(genre)" }

    static let tous = AppCatalogue.toutes.flatMap {
        [FichierCatalogue(app: $0, chemin: $0.textes, genre: "Localizable"),
         FichierCatalogue(app: $0, chemin: $0.infoPlist, genre: "InfoPlist")]
    }
}

/// Catalogues de textes des apps, lus dans le depot. Ces tests vivent ici (et non dans les tests des apps) : les tests
/// des apps tournent dans l'app sandboxee, qui ne peut pas lire le depot.
enum Catalogues {
    static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageCoeurTests
        .deletingLastPathComponent()  // racine du depot

    static func entrees(_ chemin: URL) throws -> (source: String, cles: [String: [String: Any]]) {
        let d = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: chemin)) as? [String: Any])
        let cles = try #require(d["strings"] as? [String: [String: Any]])
        return (d["sourceLanguage"] as? String ?? "", cles)
    }

    /// Dossier des produits (`.../Build/Products/Debug`) : celui de ce paquet de test.
    private final class Ancre {}
    static var produits: URL { Bundle(for: Ancre.self).bundleURL.deletingLastPathComponent() }

    /// Specificateurs d'un format, sans leur position (`%1$@` -> `@`), dans l'ordre.
    static func specificateurs(_ s: String) -> [String] {
        let motif = /%(?:\d+\$)?(lld|ld|d|@|lf|f|%)/
        return s.matches(of: motif).map { String($0.output.1) }
    }

    /// Unites de texte d'une localisation : simple, ou formes du pluriel.
    static func unites(_ loc: [String: Any]) -> [String: [String: Any]] {
        if let u = loc["stringUnit"] as? [String: Any] { return ["": u] }
        let pluriel = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return pluriel.compactMapValues { $0["stringUnit"] as? [String: Any] }
    }
}

@Suite("Catalogues de textes (francais source, anglais complet)")
struct CataloguesTests {
    @Test(arguments: FichierCatalogue.tous)
    func chaqueCleATraductionAnglaise(_ fichier: FichierCatalogue) throws {
        let (source, cles) = try Catalogues.entrees(fichier.chemin)
        #expect(source == "fr", "le francais est la langue de developpement")
        #expect(!cles.isEmpty)
        for (cle, entree) in cles {
            #expect(entree["extractionState"] as? String != "stale", "cle perimee : \(cle)")
            let locs = entree["localizations"] as? [String: [String: Any]] ?? [:]
            let en = try #require(locs["en"], "pas d'anglais : \(cle)")
            let unites = Catalogues.unites(en)
            #expect(!unites.isEmpty, "anglais vide : \(cle)")
            if unites.keys.contains(where: { !$0.isEmpty }) {
                #expect(unites["one"] != nil && unites["other"] != nil, "pluriel incomplet : \(cle)")
            }
            let attendus = Catalogues.specificateurs(cle)
            for (forme, u) in unites {
                #expect(u["state"] as? String == "translated", "anglais non valide (\(forme)) : \(cle)")
                let valeur = u["value"] as? String ?? ""
                #expect(!valeur.isEmpty, "anglais vide (\(forme)) : \(cle)")
                #expect(Catalogues.specificateurs(valeur).sorted() == attendus.sorted(),
                        "specificateurs differents : \(cle) -> \(valeur)")
            }
        }
    }

    /// Le code et le catalogue vont ensemble, pour chaque app : aucune cle du code ne manque, aucune cle du catalogue
    /// n'est morte (apres un changement de texte : `outils/synchroniser-textes.sh <App>` puis outils/traduire.py).
    /// Sans les produits de compilation d'aucune app (le schema du coeur ne les compile pas), le test est saute ; si
    /// une app a les siens et l'autre non, il echoue (`AppCatalogue.cas`).
    @Test(arguments: AppCatalogue.toutes)
    func codeEtCatalogueAlignes(_ app: AppCatalogue) throws {
        let nombres = Dictionary(uniqueKeysWithValues: AppCatalogue.toutes.map { ($0.nom, $0.stringsdata.count) })
        switch AppCatalogue.cas(app.nom, nombres: nombres) {
        case .verifier: break
        case .sauter(let raison): try Test.cancel(Comment(rawValue: raison))
        case .echouer(let raison):
            Issue.record(Comment(rawValue: raison))
            return
        }
        let extraites = try app.clesExtraites()
        let catalogue = Set(try Catalogues.entrees(app.textes).cles.keys)
        #expect(!extraites.isEmpty)
        #expect(extraites.subtracting(catalogue).sorted() == [], "absentes du catalogue de \(app.nom)")
        #expect(catalogue.subtracting(extraites).sorted() == [], "inutilisees dans le catalogue de \(app.nom)")
    }

    /// La selection des cas, sans produits reels : echoue si une app a ses `.stringsdata` et l'autre non, saute
    /// seulement si aucune n'en a.
    @Test func selectionDesCas() {
        #expect(AppCatalogue.cas("MaillageIoT", nombres: ["MaillageIoT": 3, "MaillageIoTZigbee": 4]) == .verifier)
        #expect(AppCatalogue.cas("MaillageIoTZigbee", nombres: ["MaillageIoT": 3, "MaillageIoTZigbee": 4]) == .verifier)
        guard case .echouer = AppCatalogue.cas("MaillageIoTZigbee", nombres: ["MaillageIoT": 3, "MaillageIoTZigbee": 0]) else {
            Issue.record("une app sans produits, l'autre avec : doit echouer")
            return
        }
        guard case .echouer = AppCatalogue.cas("MaillageIoT", nombres: ["MaillageIoTZigbee": 4]) else {
            Issue.record("une app absente du decompte, l'autre avec produits : doit echouer")
            return
        }
        guard case .sauter = AppCatalogue.cas("MaillageIoT", nombres: ["MaillageIoT": 0, "MaillageIoTZigbee": 0]) else {
            Issue.record("aucune app avec produits : doit sauter")
            return
        }
        guard case .sauter = AppCatalogue.cas("MaillageIoT", nombres: [:]) else {
            Issue.record("aucun decompte : doit sauter")
            return
        }
    }
}
