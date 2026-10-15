import Foundation
import MaillageCoeur

/// La cle de la sonde Thread de Maillage Thread 1.3.0 reprise sans nouvelle mise en service (spec, 4.3), comme
/// `TrousseauRepris` pour Zigbee : la cle se lit d'abord dans le trousseau de l'app (service `fr.djoko.maillage.iot.sonde-thread`) ;
/// absente, elle est demandee une seule fois a l'ancien service (`fr.djoko.maillage.sonde` : macOS demande alors l'accord de
/// l'utilisateur, l'element appartenant a l'ancienne app), puis recopiee sous le service de l'app. L'ancien element n'est jamais
/// modifie ni efface : l'ancienne app garde son acces reseau a la sonde. Un refus, une cle absente ou un oubli ne redemandent
/// plus rien (une tentative par sonde, notee dans `reprises`). Le transport UDP de la sonde n'a pas de service propre : il
/// utilise cette meme cle (`.udp` n'est que le nom de sa file d'attente).
struct TrousseauReprisThread: TrousseauClesThread {
    static let serviceAncien = "fr.djoko.maillage.sonde"

    let actuel: any TrousseauClesThread
    let ancien: any TrousseauClesThread
    let reprises: MemoireReprises

    /// Les sondes dont ce Mac a la cle : celles de l'app, puis celles de l'ancienne app dont la reprise n'a pas ete tentee.
    /// Leurs attributs seuls sont lus (jamais la cle) : aucune fenetre de macOS, aucune tentative consommee. C'est ce qui fait
    /// apparaitre le choix de la liaison par le reseau ; la cle est reprise a la connexion.
    func lister() -> [SondeConnue] {
        let courantes = actuel.lister()
        let connues = Set(courantes.map(\.nom))
        let proposees = ancien.lister().filter { !connues.contains($0.nom) && !reprises.tentee($0.nom) }
        return (courantes + proposees).sorted { $0.nom < $1.nom }
    }

    func lire(nom: String) throws -> Data {
        do {
            return try actuel.lire(nom: nom)
        } catch {
            guard let e = error as? ErreurTrousseauThread, case .absente = e, !reprises.tentee(nom) else { throw error }
            reprises.noter(nom)
            guard let cle = try? ancien.lire(nom: nom) else { throw ErreurTrousseauThread.absente(nom) }
            try? actuel.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle))
            return cle
        }
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        try actuel.ranger(nom: nom, cle: cle, empreinte: empreinte)
    }

    /// N'efface que la cle de l'app, et ne reprend plus celle de l'ancienne app.
    func oublier(nom: String) throws {
        reprises.noter(nom)
        try actuel.oublier(nom: nom)
    }
}
