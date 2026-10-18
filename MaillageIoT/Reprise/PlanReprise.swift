import Foundation
import MaillageCoeur

// Phase 4, tache 4 : le plan qu'une conversion d'export rend (`ConversionThread`, puis celle de Zigbee).
//
// Un plan dit TOUT ce que l'import ferait, sans rien faire : les fichiers a deposer dans le dossier d'attente (leur
// contenu final, une fois fusionne avec ce que Maillage IoT a deja), les reglages a ecrire, et ce qui n'est pas pris,
// avec la raison, pour le resume. La tache 6 l'applique d'un coup (rien, ou tout) ; elle n'a plus aucune decision a
// prendre. Le plan ne porte que des chemins, des comptes et des cles de reglage dans ce qu'il cite : jamais une valeur
// lue (un surnom, une piece, une adresse), qui peut etre personnelle.

/// Ce que Maillage IoT a deja, en lecture seule : la conversion le lit, ne l'ecrit jamais.
struct EtatActuel: Sendable {
    /// La racine des donnees de l'app (`Application Support/Maillage IoT`) : fichiers a la racine, `Thread/`, `Zigbee/`,
    /// `Journal/`.
    let dossier: URL
    /// Les cles deja posees dans le domaine de preferences de Maillage IoT (`persistentDomain`, pas les valeurs globales du
    /// Mac) : une cle presente n'est jamais ecrasee.
    let reglagesPresents: Set<String>

    init(dossier: URL, reglagesPresents: Set<String> = []) {
        self.dossier = dossier
        self.reglagesPresents = reglagesPresents
    }
}

/// Le contenu d'un fichier du plan.
enum ContenuAPlacer: Equatable, Sendable {
    /// Le contenu final, en memoire (un fichier converti ou fusionne).
    case donnees(Data)
    /// Un fichier de l'export, a copier tel quel (sans le lire en entier : l'historique peut peser des dizaines de Mo).
    /// `sha256` : l'empreinte que le manifeste donne, a reverifier sur la copie.
    case copie(URL, sha256: String)

    /// Les octets (pour un fichier copie : relus).
    func octets() throws -> Data {
        switch self {
        case .donnees(let d): d
        case .copie(let url, _): try Data(contentsOf: url)
        }
    }
}

/// Un fichier a deposer dans le dossier d'attente.
struct FichierAPlacer: Equatable, Sendable {
    /// Le chemin relatif dans le dossier de donnees de Maillage IoT (`surnoms.json`, `Thread/maillage-2026-10.jsonl`).
    let chemin: String
    let contenu: ContenuAPlacer
    /// Les fichiers de l'export qui y sont passes (chemins relatifs a l'export) : de quoi verifier que chacun est pris ou
    /// cite.
    let sources: [String]
}

/// Quelque chose de l'ancienne app qui n'est pas repris, et pourquoi : le resume le dit, rien ne se perd en silence. Les
/// chemins et les cles sont ceux de l'EXPORT (l'ancienne app).
struct ElementNonPris: Equatable, Hashable, Sendable {
    enum Nature: Equatable, Hashable, Sendable {
        /// Un fichier de l'export, en entier.
        case fichier(String)
        /// Un reglage de l'export (sa cle d'origine).
        case reglage(String)
        /// `nombre` entrees d'un fichier repris (surnoms, pieces, lignes d'un journal...) : le reste du fichier est pris.
        case entrees(fichier: String, nombre: Int)
    }

    enum Raison: Equatable, Hashable, Sendable {
        /// Fichier mensuel dont le mois est fini depuis plus de 90 jours.
        case plusDe90Jours
        /// Maillage IoT a deja la meme chose ou un choix different : il l'emporte.
        case dejaDansMaillageIoT
        /// Le fichier de l'export n'a rien a apporter.
        case vide
        /// Le releve de Maison de Maillage IoT est aussi recent ou plus.
        case releveMaisonNonPlusRecent
        /// Le fichier (ou l'entree) de l'export est illisible ou d'une version que l'app ne connait pas.
        case fichierIllisible
        /// Le fichier de Maillage IoT qu'il aurait fallu fusionner est illisible ou plus recent : il n'est pas touche.
        case fichierExistantNonLisible
        /// L'export lui-meme l'a laisse (`reglages.json`, `manifeste.json`) : Sparkle, fenetres, fichiers hors contrat.
        case laisseParLAncienneApp(ContratExport.RaisonNonRepris)
        /// Un reglage ou un fichier connu de l'export qu'aucune regle ne place : cite plutot que perdu.
        case sansEquivalent
    }

    let nature: Nature
    let raison: Raison

    /// Cle de tri stable (nature, nom, raison) : le plan est le meme d'un appel a l'autre.
    fileprivate var cleDeTri: String {
        switch nature {
        case .fichier(let c): "0|\(c)|\(raison)"
        case .reglage(let c): "1|\(c)|\(raison)"
        case .entrees(let f, let n): "2|\(f)|\(n)|\(raison)"
        }
    }

    static func trier(_ elements: [ElementNonPris]) -> [ElementNonPris] {
        elements.sorted { $0.cleDeTri < $1.cleDeTri }
    }
}

/// Le plan d'une conversion.
struct PlanReprise: Equatable, Sendable {
    /// L'app dont l'export est converti.
    let app: ContratExport.AppSource
    /// Les fichiers a deposer, tries par chemin.
    let fichiers: [FichierAPlacer]
    /// Les reglages a ecrire dans les preferences de Maillage IoT : cle de Maillage IoT -> valeur. Jamais une cle deja
    /// posee, jamais une valeur par defaut.
    let reglages: [String: ContratExport.Valeur]
    /// Ce qui n'est pas pris, trie.
    let nonPris: [ElementNonPris]

    func fichier(_ chemin: String) -> FichierAPlacer? { fichiers.first { $0.chemin == chemin } }
}

/// Pourquoi une conversion ne peut pas avoir lieu (rien n'est alors ecrit nulle part).
enum ErreurConversion: Error, Equatable, Sendable {
    /// L'export n'est pas celui de l'app que cette conversion traite.
    case appInattendue(ContratExport.AppSource)
    /// Un fichier de l'export, verifie un instant plus tot, n'a pas pu etre lu.
    case lectureImpossible(String)
}
