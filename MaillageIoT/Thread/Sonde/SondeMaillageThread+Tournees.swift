import Foundation
import MaillageCoeur
import ProtocoleThread
import os

// Sonde Thread, role Tournees : rafraichissement, attente du premier releve, tournee et identites des routeurs.
extension SondeMaillageThread {
    /// Fichier des identites des routeurs : sous `Thread/`, dans le dossier de l'app ; nil en demo et sous les
    /// tests (qui passent le leur, temporaire).
    static func fichierIdentites(demo: Bool, sousTests: Bool) -> URL? {
        demo || sousTests
            ? nil
            : Surveillance.dossierThread(Surveillance.dossierParDefaut).appendingPathComponent("identites-routeurs.json")
    }

    /// Tournee tout de suite (bouton rafraichir) ; rien pendant une tournee : relancer la
    /// boucle ne ferait que repousser la suivante de 5 min apres ce clic.
    func rafraichir() {
        guard tourneeAuRafraichir else { return }
        lancerBoucle(attendre: false)
    }

    /// Avant la premiere tournee d'une liaison, attend que l'app ait recu son premier releve Bonjour (`reseauConnu`),
    /// quelques secondes apres le lancement, au plus `attenteReseau`. Sans lui, la liste des appareils a resoudre est
    /// vide : la sonde ne rattache aucun enfant sous les routeurs muets, et la premiere carte (ou le dernier maillage
    /// garde, relu au lancement) laisserait place a une carte appauvrie jusqu'a la tournee suivante, 5 min plus tard
    /// (banc du 12/10 : 2 enfants au lieu de 24). Ensuite (reconnexion), le releve est la : pas d'attente.
    func attendreReseau() async {
        guard let connu = reseauConnu else { return }
        let fin = ContinuousClock.now + attenteReseau
        while !Task.isCancelled, !connu(), ContinuousClock.now < fin {
            try? await Task.sleep(for: pasAttenteReseau)
        }
    }

    /// Etat de la sonde, puis une tournee ; le maillage part a la surveillance,
    /// avec l'heure de sa reception (la fin de la tournee), entre les signaux de
    /// debut et de fin de la tournee. L'avancement et l'heure du debut sont exposes
    /// pendant la tournee, remis a nil a sa fin (erreur et liaison fermee comprises).
    func uneTournee() async {
        guard let sonde, !tourneeEnCours else { return }
        tourneeEnCours = true
        debutTournee = horloge()
        surTournee?(true)
        // L'avancement vient de la tache de la tournee : il passe sur le MainActor dans
        // l'ordre, et tout est lu avant la remise a nil.
        let (flux, suite) = AsyncStream.makeStream(of: AvancementTournee.self)
        let lecture = Task { @MainActor [weak self] in
            for await a in flux { self?.avancement = a }
        }
        await executerTournee(sonde) { suite.yield($0) }
        suite.finish()
        await lecture.value
        avancement = nil
        debutTournee = nil
        tourneeEnCours = false
        surTournee?(false)
    }

    /// Corps de `uneTournee` : ses erreurs sont retenues ici, sauf la liaison fermee (`liaisonFermee`).
    /// Rien n'est retenu d'une tournee dont la liaison n'est plus celle de la sonde (oubliee,
    /// debranchee, reconnectee) : une reponse arrivee apres l'oubli ne remet ni releve ni maillage.
    private func executerTournee(_ sonde: SondeUSB, suivi: @escaping @Sendable (AvancementTournee) -> Void) async {
        do {
            let e = try await sonde.etat()
            guard sonde === self.sonde else { return }
            etatSonde = e
            let appareils = appareilsAResoudre?() ?? []
            let r = try await Tournee.executer(sonde, memoire: memoire, maintenant: horloge(), appareils: appareils,
                                               avancement: suivi)
            guard sonde === self.sonde else { return }
            // Meme sans maillage (pas de liste des routeurs), les identites apprises sont gardees.
            memoire = r.memoire
            garderIdentites()
            if let m = r.maillage {
                let recu = horloge()
                derniereTournee = recu
                couverture = m.couverture
                surMaillage?(m, recu)
            }
            erreurTournee = nil
        } catch SondeUSB.Erreur.fermee {
            // La liaison est fermee : `liaisonFermee` s'en occupe.
        } catch {
            guard sonde === self.sonde else { return }
            erreurTournee = error.localizedDescription
        }
    }

    /// Ecrit les identites des routeurs si elles ont change depuis le fichier. Un echec est
    /// consigne dans le journal du Mac ; les identites restent en memoire et l'ecriture est
    /// retentee a la tournee suivante.
    private func garderIdentites() {
        guard let f = fichierIdentites, let g = memoire.identitesGardees, g != identitesDuFichier else { return }
        do {
            try g.ecrire(dans: f)
            identitesDuFichier = g
        } catch {
            Self.journal.error("identites des routeurs non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }
}
