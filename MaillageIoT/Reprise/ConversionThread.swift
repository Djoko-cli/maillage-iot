import Foundation
import MaillageCoeur

// Phase 4, tache 4 : la conversion d'un export de Maillage Thread 1.3.x / 1.4.x en plan de reprise.
//
// Entree : un dossier d'export (verifie : manifeste, tailles, empreintes), l'etat actuel de Maillage IoT (dossier de
// donnees et cles de preferences deja posees, en lecture seule) et la date de reference. Sortie : un `PlanReprise`. Rien
// n'est ecrit ni dans l'export ni dans l'app ; la tache 6 applique le plan d'un coup, par un dossier d'attente.
//
// Ce que chaque fichier de l'export devient (inventaire du 17/10, section 1 ; spec 4.3 et 6.8). Les regles de fusion
// avec l'existant sont dans `FusionReprise.swift` (l'existant l'emporte, rien n'est ecrase) :
//
//   surnoms.json            -> surnoms.json (v1, cles `thread:<cle>`)
//   pieces-routeurs.json    -> pieces-noeuds.json (v2, cles `thread:<cle>`)
//   positions-pieces.json   -> positions-pieces.json (fusion en profondeur)
//   noms.json               -> releve-maison.json (renomme, si le plus recent)
//   associations.json, identites-routeurs.json, dernier-maillage.json, dernieres-adresses.json -> Thread/ (memes cles)
//   maillage-AAAA-MM.jsonl  -> Thread/maillage-AAAA-MM.jsonl (mois finis depuis plus de 90 jours ecartes)
//   Journal/journal-AAAA-MM.jsonl -> Journal/journal-AAAA-MM.jsonl (ajoute tel quel : une ligne sans `protocole` est
//                              Thread, aucune n'est reecrite ; mois finis depuis plus de 90 jours ecartes)
//   reglages.json           -> preferences : `sonde*` et `scissionsNotifiees` en `thread.*`, `notification.<cat>` en
//                              `notification.thread.<cat>`, les reglages communs sous leur cle
//
// Rien ne se perd en silence : chaque fichier de l'export est dans le plan ou cite parmi ce qui n'est pas pris, avec la
// raison, de meme que chaque reglage et chaque fichier que l'export a vu sans le copier.

enum ConversionThread {
    /// Verifie le dossier (`ContratExport.verifierDossier`, un passage complet : le dossier a pu changer depuis la
    /// validation de l'assistant) puis le convertit.
    static func convertir(dossier: URL, etat: EtatActuel, maintenant: Date, calendrier: Calendar = .current) throws -> PlanReprise {
        let (manifeste, reglages) = try ContratExport.verifierDossier(dossier)
        return try convertir(dossier: dossier, manifeste: manifeste, reglages: reglages, etat: etat,
                             maintenant: maintenant, calendrier: calendrier)
    }

    /// Convertit un export dont le manifeste et les reglages viennent d'etre verifies. `calendrier` : celui des noms de
    /// fichiers mensuels (le calendrier local de l'ancienne app, comme la purge de l'app).
    static func convertir(dossier: URL, manifeste: ContratExport.Manifeste, reglages: ContratExport.Reglages, etat: EtatActuel,
                          maintenant: Date, calendrier: Calendar = .current) throws -> PlanReprise {
        guard manifeste.app == .maillageThread, reglages.app == .maillageThread else {
            throw ErreurConversion.appInattendue(manifeste.app)
        }
        var plan = ConstructionPlan(dossier: dossier, manifeste: manifeste, etat: etat, maintenant: maintenant, calendrier: calendrier)
        for fichier in manifeste.fichiers.sorted(by: { $0.chemin < $1.chemin }) where fichier.chemin != ContratExport.nomReglages {
            let chemin = fichier.chemin
            switch chemin {
            case "surnoms.json": try plan.surnoms(chemin, protocole: .thread)
            case "pieces-routeurs.json": try plan.pieces(chemin, protocole: .thread)
            case "positions-pieces.json": try plan.positions(chemin)
            case "noms.json": try plan.releveDeMaison(chemin)
            case "associations.json": try plan.associations(chemin, vers: "Thread/associations.json")
            case "identites-routeurs.json": try plan.identitesDeRouteurs(chemin, vers: "Thread/identites-routeurs.json")
            case "dernier-maillage.json": try plan.dernierMaillage(chemin, vers: "Thread/dernier-maillage.json")
            case "dernieres-adresses.json": try plan.dernieresAdresses(chemin, vers: "Thread/dernieres-adresses.json")
            default:
                if ContratExport.mois(de: chemin) == nil {
                    plan.sansEquivalent(chemin)
                } else if chemin.hasPrefix("Journal/") {
                    try plan.mensuel(chemin, vers: chemin)
                } else {
                    try plan.mensuel(chemin, vers: "Thread/\(chemin)")
                }
            }
        }
        plan.reglages(reglages)
        plan.fichiersLaissesParLExport()
        return plan.plan()
    }
}
