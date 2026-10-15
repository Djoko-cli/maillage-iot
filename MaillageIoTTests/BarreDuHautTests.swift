import Foundation
import MaillageCoeur
import ProtocoleZigbee
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
        let m = MoteurPiecesTests.moteur(reunie)
        #expect(CommandesVue.montreLiens(scene: m.scene, montres: reunie.montres), "les liens de Zigbee, avec ceux de Thread")
        let seulThread = MoteurPiecesTests.moteur(EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees()))
        #expect(!CommandesVue.montreLiens(scene: seulThread.scene, montres: reunie.montres), "Thread seul : pas de liens")
        #expect(!CommandesVue.montreLiens(scene: nil, montres: reunie.montres))
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
}
