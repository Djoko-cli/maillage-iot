import Foundation
import MaillageCoeur
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

// « Activer ce protocole » (tache 11), cote Bonjour et pont : `Recenseur` (Thread), `DecouvertePont` et `NomsPont` (Zigbee)
// s'arretent pour de bon et repartent. Les navigateurs Bonjour sont factices, le pont est simule (`PontSimule`) : aucun reseau.

@MainActor
@Suite("Arret du recenseur Bonjour de Thread", .timeLimit(.minutes(1)))
struct ArretRecenseurTests {
    /// Arret : plus un navigateur Bonjour, plus de releve periodique, plus de releve en attente de calme ; rien ne revient
    /// apres coup. Rallumage : quatre navigateurs neufs.
    @Test func arretRealEtRallumage() async throws {
        let fab = FabriqueBonjour()
        // Le premier releve est du des le demarrage (l'avance tient lieu des 10 s de mise en route).
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100))
        var releves = 0
        r.surReleve = { _ in releves += 1 }
        r.demarrer()
        #expect(fab.types == Recenseur.types && fab.enMarche == 4, "un navigateur par type de service")
        #expect(await attendreActivation { releves == 1 }, "le premier releve")

        // Un changement des navigateurs arme un releve dans 2 s.
        fab.crees[0].voir("Instance 1")
        #expect(r.tachesPlanifiees == 2, "releve periodique et releve apres calme")
        r.arreter()
        #expect(r.tachesPlanifiees == 0, "taches annulees, pas seulement rendues sans effet")
        #expect(fab.enMarche == 0 && fab.arrets == 4 && fab.crees.allSatisfy { $0.surChangement == nil })
        r.rafraichir()
        fab.crees[0].voir("Instance 2")
        try await Task.sleep(for: .milliseconds(2500))
        #expect(releves == 1, "le releve en attente de calme n'a pas eu lieu")
        #expect(r.tachesPlanifiees == 0 && r.etat == .demarrage && fab.crees.count == 4)

        r.demarrer()
        #expect(fab.crees.count == 8 && fab.enMarche == 4 && r.tachesPlanifiees == 1, "repart comme au lancement")
        #expect(await attendreActivation { releves == 2 }, "et fait son premier releve")
        r.arreter()
        #expect(fab.enMarche == 0 && r.tachesPlanifiees == 0)
    }

    /// Basculer vite ne laisse rien de vivant.
    @Test func basculesRapides() async throws {
        let fab = FabriqueBonjour()
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100))
        var releves = 0
        r.surReleve = { _ in releves += 1 }
        r.demarrer()
        r.arreter()
        r.demarrer()
        r.arreter()
        #expect(fab.enMarche == 0 && fab.demarrages == fab.arrets && fab.crees.count == 8)
        #expect(r.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(releves == 0 && r.tachesPlanifiees == 0, "aucun releve ne vient d'une ecoute eteinte")
    }
}

@MainActor
@Suite("Arret de la decouverte du pont Hue", .timeLimit(.minutes(1)))
struct ArretDecouvertePontTests {
    @Test func arretEtRallumage() {
        let bonjour = BonjourFactice(type: DecouvertePont.type)
        let d = DecouvertePont(navigateur: bonjour)
        d.demarrer()
        d.demarrer()
        #expect(d.demarree && bonjour.demarrages == 1 && bonjour.enMarche, "un seul navigateur, meme appele deux fois")
        d.arreter()
        #expect(!d.demarree && !bonjour.enMarche && bonjour.arrets == 1 && bonjour.surChangement == nil)
        d.relancer()
        #expect(bonjour.demarrages == 1, "relancer ne reveille pas une decouverte arretee")
        d.demarrer()
        #expect(d.demarree && bonjour.demarrages == 2 && bonjour.enMarche, "repart")
        d.arreter()
        #expect(bonjour.arrets == 2 && !bonjour.enMarche)
    }
}

@MainActor
@Suite("Arret du client du pont Hue", .timeLimit(.minutes(1)))
struct ArretNomsPontTests {
    struct Banc {
        let pont: NomsPont
        let simule: PontSimule
    }

    /// Un pont lie et sa cle, simules ; la relecture de 5 minutes dure 30 ms (on la voit tourner), toute autre attente est
    /// celle des tests de la liaison. Rien ne passe par le reseau.
    static func banc() -> Banc {
        let simule = PontSimule()
        let date = NomsPontTests.date
        let d = DependancesPont(transport: simule, trousseau: TrousseauMemoireZigbee([PontSimule.identifiant: PontSimule.cle]),
                                memoire: MemoireVive(NomsPontTests.retenu), cache: nil, attendre: { duree in
            try await Task.sleep(for: duree == NomsPont.periodeLecture ? .milliseconds(30) : duree)
        }, maintenant: { date }, nomMac: "Mac invente")
        return Banc(pont: NomsPont(dependances: d), simule: simule)
    }

    /// Arret : plus de relecture (periodique ni en cours), plus rien de rapporte ; une decouverte tardive est ignoree ;
    /// rallumage : le pont est relu comme au lancement.
    @Test func arretEtRallumage() async throws {
        let b = Self.banc()
        var recus = 0
        b.pont.surNoms = { n in if n != nil { recus += 1 } }
        b.pont.demarrer()
        #expect(b.pont.lie && b.pont.etat == .lie)
        #expect(await attendreActivation { recus >= 3 && b.simule.appels.count > 20 }, "le pont est relu en boucle")
        #expect(b.pont.tachesPlanifiees >= 1)

        b.pont.arreter()
        #expect(b.pont.suspendu)
        let lectures = b.simule.appels.count
        let rapportes = recus
        // Une lecture en vol finit (le simule ne sait pas s'interrompre), sans rien rapporter.
        #expect(await attendreActivation { !b.pont.lectureEnCours && b.pont.tachesPlanifiees == 0 })
        let apres = b.simule.appels.count
        #expect(apres - lectures < PontHue.ressources.count + 1, "au plus la lecture en vol")
        try await Task.sleep(for: .milliseconds(250))
        #expect(b.simule.appels.count == apres, "plus aucune relecture")
        #expect(recus <= rapportes, "rien de rapporte apres l'arret")
        b.pont.pontDecouvert(NomsPontTests.decouvert)
        #expect(b.pont.relire() == nil && b.pont.tachesPlanifiees == 0)
        #expect(b.simule.appels.count == apres)

        b.pont.demarrer()
        #expect(!b.pont.suspendu && b.pont.lie)
        #expect(await attendreActivation { b.simule.appels.count > apres + 20 }, "relu de nouveau")
        b.pont.arreter()
    }

    /// Une lecture en vol a l'arret ne montre ni noms, ni erreur, et ne relance pas la decouverte.
    @Test func lectureEnVolAbandonnee() async throws {
        let b = Self.banc()
        var recus = 0
        var echecs = 0
        b.pont.surNoms = { _ in recus += 1 }
        b.pont.surEchecReseau = { echecs += 1 }
        b.simule.retenir("GET")
        b.pont.demarrer()
        #expect(await attendreActivation { b.simule.retient })
        b.pont.arreter()
        b.simule.modifier { $0.reseauCoupe = true }
        b.simule.liberer()
        #expect(await attendreActivation { !b.pont.lectureEnCours })
        try await Task.sleep(for: .milliseconds(100))
        #expect(recus == 0 && echecs == 0 && b.pont.noms == nil, "ni noms, ni decouverte relancee")
        if case .erreur = b.pont.etat { Issue.record("l'erreur d'une lecture abandonnee ne se montre pas") }
        #expect(b.pont.tachesPlanifiees == 0)
    }

    /// Basculer vite ne laisse rien de vivant.
    @Test func basculesRapides() async throws {
        let b = Self.banc()
        b.pont.demarrer()
        b.pont.arreter()
        b.pont.demarrer()
        b.pont.arreter()
        #expect(await attendreActivation { !b.pont.lectureEnCours })
        #expect(b.pont.tachesPlanifiees == 0 && b.pont.suspendu)
        let n = b.simule.appels.count
        try await Task.sleep(for: .milliseconds(250))
        #expect(b.simule.appels.count == n, "plus aucune lecture")
    }
}
