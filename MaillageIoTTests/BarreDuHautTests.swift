import AppKit
import Foundation
import MaillageCoeur
import ProtocoleZigbee
import SwiftUI
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 13 : le haut de la fenetre de la vue par pieces et son ecran d'attente suivent les protocoles de la scene.
/// Une scene qui a les deux reseaux montre les commandes de Thread et celles de Zigbee (liens, voisins, ligne de tournee) ;
/// la barre est une seule (etape 3b, tache 5 : `VueProtocolesTests` tient les interrupteurs de vue et le masquage).
@MainActor
@Suite("Haut de la fenetre : commandes et ecran d'attente par protocole")
struct BarreDuHautTests {
    /// Ce que le haut montre pour chaque ensemble de protocoles de la scene (tous montres). Une seule barre, quel que soit
    /// l'ensemble : ses lignes de tournee et ses commandes seules changent.
    @Test func commandesDuHaut() {
        let rien = ContenuHaut(protocoles: []), thread = ContenuHaut(protocoles: [.thread])
        let zigbee = ContenuHaut(protocoles: [.zigbee]), deux = ContenuHaut(protocoles: [.thread, .zigbee])
        // Thread seul, ou rien a montrer : sa ligne de tournee, pas de liens.
        for c in [rien, thread] {
            #expect(c.tournees == [.thread] && !c.liens)
        }
        // Zigbee seul : sa ligne de tournee, les liens et les voisins.
        #expect(zigbee.tournees == [.zigbee] && zigbee.liens)
        // Les deux : les deux lignes de tournee, Thread d'abord, et les liens et voisins de Zigbee.
        #expect(deux.tournees == [.thread, .zigbee] && deux.liens)
        #expect(deux.sansPiecesZigbee == false && zigbee.sansPiecesZigbee && !thread.sansPiecesZigbee)
    }

    /// Pour la vraie scene reunie, la meme chose : ses protocoles donnent les commandes des deux, et le selecteur de liens
    /// (`CommandesVue`) est montre des qu'un noeud de Zigbee est de la scene.
    @Test func sceneReunieMontreLesCommandesDesDeux() throws {
        let reunie = EntreeScene(surveillance: EntreeSceneTests.deuxReseaux(), places: PlacesGardees())
        let c = ContenuHaut(protocoles: reunie.protocoles)
        #expect(c.tournees == [.thread, .zigbee] && c.liens)
        #expect(CommandesVue.montreLiens(protocoles: reunie.protocoles, montres: reunie.montres), "les liens de Zigbee, avec ceux de Thread")
        let seulThread = EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees())
        #expect(!CommandesVue.montreLiens(protocoles: seulThread.protocoles, montres: reunie.montres), "Thread seul : pas de liens")
        #expect(!CommandesVue.montreLiens(protocoles: [], montres: reunie.montres))
    }

    /// L'ecran d'attente dit l'etat de chaque protocole actif : « Ecoute du reseau local… » n'est pas dit quand Thread est
    /// eteint ; un protocole eteint ne parle pas ; les deux eteints, l'ecran le dit.
    @Test func ecranDAttenteParProtocoleActif() {
        let s = Surveillance(mode: .direct, dossier: nil)
        #expect(EtatVide.etats(s) == [.ecouteThread, .attenteZigbee], "les deux, Thread d'abord")
        s.thread.actif = false
        #expect(EtatVide.etats(s) == [.attenteZigbee], "Thread eteint : pas d'ecoute du reseau local")
        s.thread.actif = true
        s.zigbee.actif = false
        #expect(EtatVide.etats(s) == [.ecouteThread])
        s.thread.actif = false
        #expect(EtatVide.etats(s) == [.aucunProtocole])
    }

    /// En demo, seul le protocole rejoue parle : l'autre, muet, n'est pas « en attente ».
    @Test func enDemoSeulLeProtocoleRejoueParle() {
        #expect(EtatVide.etats(Surveillance(mode: .demo, dossier: nil)) == [.ecouteThread])
        #expect(EtatVide.etats(Surveillance(mode: .demo, dossier: nil, demo: .zigbee)) == [.attenteZigbee])
    }

    // MARK: Le selecteur « Liens » suit la scene a montrer, pas la scene animee du moteur

    /// Le haut de la fenetre est dessine d'apres la scene a montrer (`EntreeScene`, refaite a chaque rendu) : `moteur.scene`,
    /// elle, est la scene animee, posee apres coup (calcul de la disposition, fin d'un mouvement) et que SwiftUI n'observe pas.
    /// Banc 4 de la phase 6 : le selecteur « Liens : chemins | tous » et le bouton des voisins manquaient, au hasard, alors que
    /// Thread et Zigbee etaient montres.
    @Test func liensSelonLaSceneAMontrer() {
        let tous: Set<Protocole> = [.thread, .zigbee]
        #expect(CommandesVue.montreLiens(protocoles: tous, montres: tous), "les deux, tous montres")
        #expect(CommandesVue.montreLiens(protocoles: [.zigbee], montres: tous), "Zigbee seul")
        #expect(!CommandesVue.montreLiens(protocoles: [.thread], montres: tous), "Thread seul : pas de liens")
        #expect(!CommandesVue.montreLiens(protocoles: [], montres: tous), "rien a montrer")
        #expect(!CommandesVue.montreLiens(protocoles: tous, montres: [.thread]), "Zigbee masque")
        #expect(CommandesVue.montreLiens(protocoles: tous, montres: [.zigbee]), "Thread masque : Zigbee garde ses liens")
    }

    /// La largeur de la capsule de droite pour une scene a montrer (ses protocoles et ceux qui sont montres), posee sur un moteur
    /// qui garde la scene `posee` (nil : aucune scene encore, avant la premiere composition). Le selecteur et le bouton des
    /// voisins l'elargissent : c'est ce qui les distingue, quelle que soit la langue.
    private static func largeurDesCommandes(posee: EntreeScene?, protocoles: Set<Protocole>, montres: Set<Protocole>) -> CGFloat {
        let moteur = posee.map { MoteurPiecesTests.moteur($0) } ?? MoteurPieces()
        let vue = CommandesVue(moteur: moteur, troisD: .constant(false), protocoles: protocoles, montres: montres)
        return NSHostingView(rootView: vue.capsuleDeVerre()).fittingSize.width
    }

    /// Premier affichage : aucune scene n'est encore posee sur le moteur (le calcul de la disposition n'est pas fini), et la
    /// scene a montrer a Thread et Zigbee : le selecteur est la, comme avec une scene posee.
    @Test func selecteurAuPremierAffichage() {
        let tous = VueProtocolesTests.tous
        let reunie = VueProtocolesTests.scene(EntreeSceneTests.deuxReseaux())
        let sans = Self.largeurDesCommandes(posee: nil, protocoles: [.thread], montres: tous)
        let premier = Self.largeurDesCommandes(posee: nil, protocoles: reunie.protocoles, montres: reunie.montres)
        let pose = Self.largeurDesCommandes(posee: reunie, protocoles: reunie.protocoles, montres: reunie.montres)
        #expect(premier > sans, "le selecteur parait sans scene posee : \(premier) pt contre \(sans) pt sans lui")
        #expect(premier == pose, "meme etat, meme affichage : \(premier) pt, \(pose) pt")
    }

    /// Zigbee masque, puis remontre : le moteur garde la scene de Thread seul (la nouvelle attend la fin du mouvement), la
    /// scene a montrer a de nouveau Zigbee : le selecteur revient. Et a l'inverse, Zigbee masque alors que le moteur garde encore
    /// la scene des deux : le selecteur part tout de suite.
    @Test func selecteurQuandZigbeeEstMasquePuisRemontre() {
        let s = EntreeSceneTests.deuxReseaux()
        let reunie = VueProtocolesTests.scene(s)
        let thread = VueProtocolesTests.scene(s, montres: [.thread])
        #expect(thread.protocoles == [.thread] && reunie.protocoles == VueProtocolesTests.tous)
        let avec = Self.largeurDesCommandes(posee: reunie, protocoles: reunie.protocoles, montres: reunie.montres)
        let sans = Self.largeurDesCommandes(posee: thread, protocoles: thread.protocoles, montres: thread.montres)
        #expect(avec > sans)
        // Zigbee remontre : le moteur a encore la scene de Thread seul.
        let remontre = Self.largeurDesCommandes(posee: thread, protocoles: reunie.protocoles, montres: reunie.montres)
        #expect(remontre == avec, "Zigbee remontre, scene du moteur en retard : \(remontre) pt, attendu \(avec) pt")
        // Zigbee masque : le moteur a encore la scene des deux.
        let masque = Self.largeurDesCommandes(posee: reunie, protocoles: thread.protocoles, montres: thread.montres)
        #expect(masque == sans, "Zigbee masque, scene du moteur en retard : \(masque) pt, attendu \(sans) pt")
    }

    /// Thread seul, et Zigbee montre mais sans noeud : pas de selecteur, meme si le moteur garde une scene qui en avait un.
    @Test func pasDeSelecteurSansNoeudZigbee() {
        let tous = VueProtocolesTests.tous
        let reunie = VueProtocolesTests.scene(EntreeSceneTests.deuxReseaux())
        let thread = EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees())
        #expect(thread.protocoles == [.thread])
        let attendu = Self.largeurDesCommandes(posee: thread, protocoles: thread.protocoles, montres: thread.montres)
        let seul = Self.largeurDesCommandes(posee: reunie, protocoles: thread.protocoles, montres: tous)
        #expect(seul == attendu, "Thread seul, Zigbee montre sans noeud : \(seul) pt, attendu \(attendu) pt")
        let vide = Self.largeurDesCommandes(posee: reunie, protocoles: [], montres: tous)
        #expect(vide == attendu, "rien a montrer : \(vide) pt, attendu \(attendu) pt")
    }
}
