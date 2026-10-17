import Foundation
import MaillageCoeur

// Phase 4, tache 5 : la conversion d'un export de Maillage Zigbee 1.1.x / 1.2.x en plan de reprise. Meme forme que
// `ConversionThread` (tache 4), memes regles de fusion (`FusionReprise.swift` : l'existant l'emporte, rien n'est ecrase) ;
// seuls les fichiers et les reglages different.
//
// Entree : un dossier d'export (verifie : manifeste, tailles, empreintes), l'etat actuel de Maillage IoT (lecture seule)
// et la date de reference. Sortie : un `PlanReprise`. Rien n'est ecrit ni dans l'export ni dans l'app.
//
// Ce que chaque fichier de l'export devient (inventaire du 17/10, section 2 ; spec 4.3 et 6.8) :
//
//   surnoms.json            -> surnoms.json (v1, cles `zigbee:<IEEE>`, jamais lu par le lecteur plat qui suppose Thread)
//   pieces-routeurs.json    -> pieces-noeuds.json (v2, cles `zigbee:<IEEE>` en majuscules, domiciles gardes tels quels)
//   positions-pieces.json   -> positions-pieces.json (fusion en profondeur)
//   releve-maison.json      -> releve-maison.json (le plus recent des deux)
//   noms-pont.json, appariements-maison.json, dernier-maillage.json -> Zigbee/ (memes cles)
//   maillage-AAAA-MM.jsonl  -> Zigbee/maillage-AAAA-MM.jsonl (mois finis depuis plus de 90 jours ecartes)
//   Journal/journal-AAAA-MM.jsonl -> Journal/journal-AAAA-MM.jsonl : CHAQUE LIGNE recoit `"protocole":"zigbee"` (sans
//                              quoi l'app la lirait comme Thread), puis est ajoutee a l'existant sans doublon
//   reglages.json           -> preferences : `sonde*`, `pont.hue`, `liensMontres`, `voisinsALaSelection` en `zigbee.*`,
//                              `notification.<cat>` en `notification.zigbee.<cat>`, les reglages communs sous leur cle ;
//                              `sondeJournalPages` (transitoire) n'est pas repris
//
// Rien ne se perd en silence : chaque fichier de l'export est dans le plan ou cite parmi ce qui n'est pas pris, avec la
// raison, de meme que chaque reglage et chaque fichier que l'export a vu sans le copier.

enum ConversionZigbee {
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
        guard manifeste.app == .maillageZigbee, reglages.app == .maillageZigbee else {
            throw ErreurConversion.appInattendue(manifeste.app)
        }
        var plan = ConstructionPlan(dossier: dossier, manifeste: manifeste, etat: etat, maintenant: maintenant, calendrier: calendrier)
        for fichier in manifeste.fichiers.sorted(by: { $0.chemin < $1.chemin }) where fichier.chemin != ContratExport.nomReglages {
            let chemin = fichier.chemin
            switch chemin {
            case "surnoms.json": try plan.surnoms(chemin, protocole: .zigbee)
            case "pieces-routeurs.json": try plan.pieces(chemin, protocole: .zigbee)
            case "positions-pieces.json": try plan.positions(chemin)
            case "releve-maison.json": try plan.releveDeMaison(chemin)
            case "noms-pont.json": try plan.nomsPont(chemin, vers: "Zigbee/noms-pont.json")
            case "appariements-maison.json": try plan.appariements(chemin, vers: "Zigbee/appariements-maison.json")
            case "dernier-maillage.json": try plan.dernierMaillage(chemin, vers: "Zigbee/dernier-maillage.json")
            default:
                if ContratExport.mois(de: chemin) == nil {
                    plan.sansEquivalent(chemin)
                } else if chemin.hasPrefix("Journal/") {
                    try plan.mensuel(chemin, vers: chemin, transformer: { FusionReprise.avecProtocole($0, .zigbee) })
                } else {
                    try plan.mensuel(chemin, vers: "Zigbee/\(chemin)")
                }
            }
        }
        plan.reglages(reglages)
        plan.fichiersLaissesParLExport()
        return plan.plan()
    }
}
