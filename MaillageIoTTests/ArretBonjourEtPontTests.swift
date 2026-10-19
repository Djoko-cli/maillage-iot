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
        #expect(fab.types == Recenseur.types && fab.enMarche == Recenseur.types.count, "un navigateur par type de service")
        #expect(await attendreActivation { releves == 1 }, "le premier releve")

        // Un changement des navigateurs arme un releve dans 2 s.
        fab.crees[0].voir("Instance 1")
        #expect(r.tachesPlanifiees == 2, "releve periodique et releve apres calme")
        r.arreter()
        #expect(r.tachesPlanifiees == 0, "taches annulees, pas seulement rendues sans effet")
        #expect(fab.enMarche == 0 && fab.arrets == Recenseur.types.count && fab.crees.allSatisfy { $0.surChangement == nil })
        r.rafraichir()
        fab.crees[0].voir("Instance 2")
        try await Task.sleep(for: .milliseconds(2500))
        #expect(releves == 1, "le releve en attente de calme n'a pas eu lieu")
        #expect(r.tachesPlanifiees == 0 && r.etat == .demarrage && fab.crees.count == Recenseur.types.count)

        r.demarrer()
        #expect(fab.crees.count == 2 * Recenseur.types.count && fab.enMarche == Recenseur.types.count && r.tachesPlanifiees == 1, "repart comme au lancement")
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
        #expect(fab.enMarche == 0 && fab.demarrages == fab.arrets && fab.crees.count == 2 * Recenseur.types.count)
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
    /// `lie` faux : le pont est retenu mais sa cle n'est pas au trousseau (etat « trouve »). `relecture` : la duree de la
    /// relecture de 5 minutes.
    static func banc(lie: Bool = true, relecture: Duration = .milliseconds(30)) -> Banc {
        let simule = PontSimule()
        let date = NomsPontTests.date
        let cles = lie ? [PontSimule.identifiant: PontSimule.cle] : [:]
        let d = DependancesPont(transport: simule, trousseau: TrousseauMemoireZigbee(cles),
                                memoire: MemoireVive(NomsPontTests.retenu), cache: nil, attendre: { duree in
            try await Task.sleep(for: duree == NomsPont.periodeLecture ? relecture : duree)
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

    /// Zigbee eteint, le pont est a l'etat « trouve » : « Lier… » est refuse (aucune demande au pont, aucune tache), et
    /// aucune relecture n'est armee.
    @Test func lierRefuseEteint() async throws {
        let b = Self.banc(lie: false)
        b.pont.demarrer()
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: PontSimule.identifiant))
        b.pont.arreter()
        #expect(b.pont.lier() == nil, "refuse")
        #expect(b.pont.tacheLiaison == nil && b.pont.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.simule.appels.isEmpty, "rien n'est demande au pont")
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: PontSimule.identifiant) && b.pont.tachesPlanifiees == 0)
    }

    /// Zigbee eteint, « Identifier » est refuse sans rien noter ni envoyer.
    @Test func identifierRefuseEteint() async throws {
        let b = Self.banc(relecture: .seconds(3600))
        b.pont.demarrer()
        #expect(await attendreActivation { b.pont.noms != nil })
        let ieee = try #require(b.pont.noms?.accessoires.compactMap(\.ieee).first)
        b.pont.arreter()
        #expect(await attendreActivation { !b.pont.lectureEnCours })
        let appels = b.simule.appels.count
        #expect(b.pont.identifier(ieee: ieee) == nil, "refuse")
        #expect(b.pont.identifications.isEmpty && b.pont.tachesPlanifiees == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.simule.appels.count == appels, "rien n'est envoye au pont")
    }

    /// Eteint puis rallume pendant une lecture : la lecture abandonnee ne montre pas d'erreur ni ne relance la decouverte, et
    /// la lecture neuve n'est pas refusee (le pont n'attend pas 5 minutes de plus).
    @Test func basculeRapideAllumeePendantUneLecture() async throws {
        let b = Self.banc(relecture: .seconds(3600))
        var echecs = 0
        b.pont.surEchecReseau = { echecs += 1 }
        // La lecture en vol echouera (reseau coupe quand elle part), la neuve reussira.
        b.simule.modifier { $0.reseauCoupe = true }
        b.simule.retenir("GET")
        b.pont.demarrer()
        #expect(await attendreActivation { b.simule.retient })
        b.pont.arreter()
        b.simule.modifier { $0.reseauCoupe = false }
        b.pont.demarrer()
        #expect(await attendreActivation { b.pont.noms != nil }, "la lecture neuve a lieu tout de suite : \(b.pont.etat)")

        b.simule.liberer()
        #expect(await attendreActivation { !b.pont.lectureEnCours && b.pont.tachesPlanifiees == 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(echecs == 0, "la decouverte n'est pas relancee")
        #expect(b.pont.etat == .lie, "pas d'erreur montree : \(b.pont.etat)")
        b.pont.arreter()
    }
}
