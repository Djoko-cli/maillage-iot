import Foundation
import MaillageCoeur

// Phase 4, tache 7 : les mots de la fin de la reprise. Le resume dit ce qui a ete repris et ce qui a ete ignore (rien ne se
// perd en silence), les erreurs d'application ont des phrases, la recuperation du lancement montre ce qu'elle a defait.
// Aucun nom, aucune valeur lue dans les donnees de l'utilisateur : des comptes, des noms de fichiers de l'app et des cles de
// reglages. Les pluriels sont evites (« Fichiers repris : 3 ») : le catalogue n'a pas de variations pour ces textes.

// MARK: Raisons d'ignorer

/// Pourquoi quelque chose de l'ancienne app n'est pas repris, en une famille lisible (les raisons du plan, regroupees).
enum RaisonIgnoree: String, Codable, CaseIterable, Sendable {
    case plusDe90Jours, dejaDansMaillageIoT, vide, releveMaisonNonPlusRecent, fichierIllisible, fichierExistantNonLisible
    case sansEquivalent, horsContrat, exclu, typeInattendu, transitoire

    init(_ raison: ElementNonPris.Raison) {
        switch raison {
        case .plusDe90Jours: self = .plusDe90Jours
        case .dejaDansMaillageIoT: self = .dejaDansMaillageIoT
        case .vide: self = .vide
        case .releveMaisonNonPlusRecent: self = .releveMaisonNonPlusRecent
        case .fichierIllisible: self = .fichierIllisible
        case .fichierExistantNonLisible: self = .fichierExistantNonLisible
        case .sansEquivalent: self = .sansEquivalent
        case .laisseParLAncienneApp(let r):
            switch r {
            case .horsContrat: self = .horsContrat
            case .exclu: self = .exclu
            case .typeInattendu: self = .typeInattendu
            case .transitoire: self = .transitoire
            }
        }
    }

    func libelle(locale: Locale) -> String {
        switch self {
        case .plusDe90Jours: traduire("Historique de plus de 90 jours", locale)
        case .dejaDansMaillageIoT: traduire("Déjà dans Maillage IoT (ce qui existait est gardé)", locale)
        case .vide: traduire("Fichier sans contenu", locale)
        case .releveMaisonNonPlusRecent: traduire("Relevé de Maison déjà plus récent dans Maillage IoT", locale)
        case .fichierIllisible: traduire("Illisible ou d'une version inconnue", locale)
        case .fichierExistantNonLisible: traduire("Fichier de Maillage IoT illisible, laissé intact", locale)
        case .sansEquivalent: traduire("Sans équivalent dans Maillage IoT", locale)
        case .horsContrat: traduire("Propre à l'ancienne app (mises à jour, fenêtres…)", locale)
        case .exclu: traduire("Fichier système ou temporaire", locale)
        case .typeInattendu: traduire("Réglage d'un type inattendu", locale)
        case .transitoire: traduire("Réglage transitoire, sans sens après coup", locale)
        }
    }
}

// MARK: Resume final

/// Ce que la reprise a fait, gardé d'un lancement à l'autre (l'app se relance après l'import) : comptes et raisons, sans
/// aucune valeur lue.
struct ResumeFinal: Codable, Equatable, Sendable {
    struct Ignore: Codable, Equatable, Sendable {
        let raison: RaisonIgnoree
        let nombre: Int
    }

    let app: ContratExport.AppSource
    let versionApp: String
    let dateExport: Date
    let fichiersRepris: Int
    let reglagesRepris: Int
    /// Ce qui est laisse de cote, par raison, trie par raison (ordre stable).
    let ignores: [Ignore]
    /// Ce que l'app avait ecrit pendant l'import et qui est reste en place (jamais ecrase).
    let fichiersLaisses: [String]
    let reglagesLaisses: [String]
    /// L'etat de Maillage IoT a change pendant la reprise : le plan a ete refait avant d'etre applique.
    let planRecalcule: Bool

    init(resultat: ResultatApplication, app: ContratExport.AppSource, versionApp: String, dateExport: Date) {
        self.app = app
        self.versionApp = versionApp
        self.dateExport = dateExport
        fichiersRepris = resultat.fichiersEcrits.count
        reglagesRepris = resultat.reglagesEcrits.count
        var comptes: [RaisonIgnoree: Int] = [:]
        for element in resultat.nonPris {
            let n: Int
            if case .entrees(_, let nombre) = element.nature { n = nombre } else { n = 1 }
            comptes[RaisonIgnoree(element.raison), default: 0] += n
        }
        ignores = comptes.sorted { $0.key.rawValue < $1.key.rawValue }.map { Ignore(raison: $0.key, nombre: $0.value) }
        fichiersLaisses = resultat.laisses.fichiers
        reglagesLaisses = resultat.laisses.reglages
        planRecalcule = resultat.planRecalcule
    }

    init(resultat: ResultatApplication, resume: ResumeExport) {
        self.init(resultat: resultat, app: resume.app, versionApp: resume.versionApp, dateExport: resume.date)
    }

    /// « Repris depuis Maillage Thread 1.4.0, export du 17 oct. 2026 ».
    func origine(locale: Locale) -> String {
        let date = dateExport.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        return traduire("Repris depuis \(app.nomApp) \(versionApp), export du \(date)", locale)
    }

    /// « Fichiers repris : 22 », « Réglages repris : 9 ».
    func lignesReprises(locale: Locale) -> [String] {
        [traduire("Fichiers repris : \(fichiersRepris)", locale), traduire("Réglages repris : \(reglagesRepris)", locale)]
    }

    /// Une ligne par raison : « Historique de plus de 90 jours : 3 ».
    func lignesIgnorees(locale: Locale) -> [String] {
        ignores.map { traduire("\($0.raison.libelle(locale: locale)) : \($0.nombre)", locale) }
    }

    /// Ce qui est reste en place parce que l'app l'avait ecrit entre-temps ; nil s'il n'y en a pas.
    func texteLaisses(locale: Locale) -> String? {
        TexteReprise.laisses(ElementsLaisses(fichiers: fichiersLaisses, reglages: reglagesLaisses), locale: locale)
    }

    /// Le plan a ete refait pendant l'application ; nil sinon.
    func texteRecalcul(locale: Locale) -> String? {
        planRecalcule ? traduire("Les données de Maillage IoT ont changé pendant la reprise : elle a été recalculée, sans rien écraser de ce qui avait été fait.", locale) : nil
    }
}

/// Le resume en attente du lancement suivant (preferences de l'app) : l'import reussi relance l'app, qui montre ce resume avec
/// l'etat reel du Mac a ce moment-la.
struct DepotResume {
    static let cle = "reprise.resumeEnAttente"
    let preferences: UserDefaults

    func ecrire(_ resume: ResumeFinal) {
        if let donnees = try? ContratExport.encodeur().encode(resume) { preferences.set(donnees, forKey: Self.cle) }
    }

    func lire() -> ResumeFinal? {
        preferences.data(forKey: Self.cle).flatMap { try? ContratExport.decodeur().decode(ResumeFinal.self, from: $0) }
    }

    func effacer() { preferences.removeObject(forKey: Self.cle) }
}

// MARK: Textes des erreurs et des elements laisses

enum TexteReprise {
    /// « Ce que l'app avait ecrit entre-temps est reste en place : surnoms.json, thread.sondeHote » ; nil si rien.
    static func laisses(_ l: ElementsLaisses, locale: Locale) -> String? {
        guard !l.estVide else { return nil }
        let liste = (l.fichiers + l.reglages).joined(separator: ", ")
        return traduire("Ce que l'app avait écrit entre-temps est resté en place, rien n'a été écrasé : \(liste). Les originaux remplacés sont gardés dans le dossier .reprise-conservee.", locale)
    }

    static func etape(_ e: EtapeApplication, locale: Locale) -> String {
        switch e {
        case .preparation: traduire("la préparation", locale)
        case .remplacement: traduire("le remplacement des fichiers", locale)
        case .reglages: traduire("l'écriture des réglages", locale)
        case .validation: traduire("la validation", locale)
        }
    }

    /// La phrase d'une erreur d'application. Jamais un chemin : le domaine et le code de l'erreur du systeme seulement.
    static func erreur(_ e: ErreurApplication, locale: Locale) -> String {
        switch e {
        case .refuse(let cause):
            return cause.texte(locale: locale)
        case .exportModifie:
            return traduire("L'export a changé pendant la reprise : refaire l'export depuis l'ancienne app, puis recommencer. Rien n'a été modifié.", locale)
        case .dejaRepris(let reprise):
            let date = reprise.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
            return traduire("Cet export a déjà été repris le \(date). Rien n'a été modifié.", locale)
        case .etatInstable:
            return traduire("Les données de Maillage IoT n'ont pas cessé de changer pendant la reprise : rien n'a été modifié. Réessayer dans un instant.", locale)
        case .echec(let etape, let retablie, let code):
            let nom = Self.etape(etape, locale: locale)
            return retablie
                ? traduire("La reprise a échoué pendant \(nom) (\(code)). Rien n'a été modifié.", locale)
                : traduire("La reprise a échoué pendant \(nom) (\(code)). Le dossier sera remis en état au prochain lancement de Maillage IoT.", locale)
        case .echecAvecReste(let etape, let laisses, let code):
            let nom = Self.etape(etape, locale: locale)
            let reste = Self.laisses(laisses, locale: locale) ?? ""
            return traduire("La reprise a échoué pendant \(nom) (\(code)), et tout ce qu'elle avait fait est défait. \(reste)", locale)
        case .recuperationImpossible(let code):
            return traduire("Une reprise interrompue n'a pas pu être défaite (\(code)). Rien n'a été effacé : relancer Maillage IoT pour réessayer.", locale)
        }
    }
}

/// Ce que la recuperation du lancement a a dire (jamais en silence quand elle a defait quelque chose ou n'a pas pu).
struct AvisLancement: Equatable, Sendable {
    enum Cas: Equatable, Sendable {
        case annulee
        case annuleeSauf(ElementsLaisses)
        case impossible(code: String)
    }

    let cas: Cas

    /// nil quand il n'y avait rien a faire, ou que la reprise etait deja finie (seul le nettoyage restait).
    init?(_ issue: Result<IssueRecuperation, ErreurApplication>) {
        switch issue {
        case .success(.rienAFaire), .success(.nettoyee), .success(.terminee): return nil
        case .success(.annulee): cas = .annulee
        case .success(.annuleeSauf(let laisses)): cas = .annuleeSauf(laisses)
        case .failure(.recuperationImpossible(let code)): cas = .impossible(code: code)
        case .failure(let autre): cas = .impossible(code: String(describing: autre))
        }
    }

    func texte(locale: Locale) -> String {
        switch cas {
        case .annulee:
            return traduire("Une reprise interrompue a été défaite au lancement : Maillage IoT est revenu à l'état d'avant. La reprise peut être refaite.", locale)
        case .annuleeSauf(let laisses):
            let reste = TexteReprise.laisses(laisses, locale: locale) ?? ""
            return traduire("Une reprise interrompue a été défaite au lancement, sauf ce que l'app avait écrit depuis. \(reste)", locale)
        case .impossible(let code):
            return traduire("Une reprise interrompue n'a pas pu être défaite (\(code)). Rien n'a été effacé : relancer Maillage IoT pour réessayer.", locale)
        }
    }
}

/// Le texte dans la langue demandee (le catalogue de l'app a le francais et l'anglais).
private func traduire(_ ressource: LocalizedStringResource, _ locale: Locale) -> String {
    var r = ressource
    r.locale = locale
    return String(localized: r)
}
