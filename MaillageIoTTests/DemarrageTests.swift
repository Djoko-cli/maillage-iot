import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

@Suite("Demarrage de l'app (tests heberges)")
struct DemarrageTests {
    @MainActor
    @Test func identite() {
        #expect(Bundle.main.bundleIdentifier == "fr.djoko.maillage.iot")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true, "app de la barre des menus")
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        // Les trois sources des types ecoutes : le recenseur de Thread, le pont Hue, les sondes Zigbee.
        let attendus = Recenseur.types + [DecouvertePont.type, TransportTCP.typeBonjour]
        #expect(services == attendus, "chaque type ecoute est declare (sinon le reseau local peut etre refuse)")
        #expect(Set(attendus).count == 6, "six types, aucun en double")
    }

    /// Les arguments de lancement des demos : `-demo` lance la combinee (Thread et Zigbee ensemble), `-demo-thread` et
    /// `-demo-zigbee` chacune seule ; rien hors demo. Chaque demo seule fait tourner un seul modele, l'autre muet
    /// (`ModulesApp(demo:)`) ; la combinee, les deux.
    @MainActor
    @Test func argumentsDeLaDemo() {
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT"]) == nil)
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo"]) == .combinee)
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo-thread"]) == .thread)
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo-zigbee"]) == .zigbee)
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo", "-captures", "x"]) == .combinee)
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo", "-demo-zigbee"]) == .zigbee, "la plus precise")
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo", "-demo-thread"]) == .thread, "la plus precise")
        #expect(DemoLancee.depuis(arguments: ["Maillage IoT", "-demo-thread", "-demo-zigbee"]) == .combinee, "les deux seules : la combinee")
        for demo in [DemoLancee.thread, .zigbee, .combinee] {
            let m = ModulesApp(demo: demo, sousTests: true)
            m.surveillance.demarrer()
            let scene = EntreeScene(surveillance: m.surveillance, places: PlacesGardees())
            #expect(scene.protocoles == demo.protocoles, "la demo \(demo)")
            #expect(m.surveillance.modeles.filter { $0.graphe.noeuds.isEmpty }.map(\.protocole)
                    == Protocole.allCases.filter { !demo.rejoue($0) })
            #expect(m.surveillance.modelesMontres.map(\.protocole) == Protocole.allCases.filter { demo.rejoue($0) })
        }
    }

    /// Sous les tests, l'app porte les deux modeles de protocole, et rien n'est ouvert : aucun port, aucune ecoute
    /// Bonjour, aucun trousseau du Mac (un trousseau en memoire a la place), aucun fichier de l'app.
    @MainActor
    @Test func deuxModelesSousTests() throws {
        #expect(Surveillance.sousTests, "ce test tourne dans l'app hote des tests")
        let m = ModulesApp(demo: nil, sousTests: true)

        #expect(m.surveillance.modeles.map(\.protocole) == [.thread, .zigbee])
        #expect(m.surveillance.thread.protocole == .thread)
        #expect(m.surveillance.zigbee.protocole == .zigbee)
        #expect(m.surveillance.thread.coque === m.surveillance)
        #expect(m.surveillance.zigbee.coque === m.surveillance)

        // Aucun port : les deux sondes sont inactives (ni port, ni preferences, ni trousseau lus).
        #expect(!m.sondeThread.actif && !m.sondeZigbee.actif)
        #expect(m.sondeThread.ports.isEmpty && m.sondeZigbee.ports.isEmpty)
        #expect(m.sondeThread.serie == nil && m.sondeZigbee.serie == nil)
        m.sondeThread.demarrer()
        m.sondeZigbee.demarrer()
        #expect(m.sondeThread.ports.isEmpty && m.sondeZigbee.ports.isEmpty, "inactive : demarrer n'ouvre rien")

        // Aucun Bonjour : ni la decouverte du pont, ni le navigateur du pont, ni celui des sondes.
        #expect(!m.decouverte.demarree)
        #expect(!m.sondeZigbee.annoncee)

        // Aucun trousseau du Mac : celui de chaque sonde est en memoire, et le pont n'a aucune dependance reelle.
        #expect(m.sondeThread.trousseau is TrousseauMemoireThread)
        #expect(m.sondeZigbee.trousseau is TrousseauMemoireZigbee)
        #expect(!m.nomsPont.lie)
        #expect(m.nomsPont.etat == .introuvable)

        // Le releve de Maison, un seul, va aux deux modeles.
        #expect(m.surveillance.thread.noms.maison == nil && m.surveillance.zigbee.releveMaison == nil)
    }

    /// Le releve de Maison du Passeur est distribue aux deux modeles par la coque (un seul client du demon).
    @MainActor
    @Test func releveMaisonVaAuxDeuxModeles() {
        let s = Surveillance(mode: .direct, dossier: nil)
        #expect(s.thread.noms.maison == nil && s.zigbee.releveMaison == nil)
        let releve = NomsMaison(date: Date(timeIntervalSince1970: 1_000_000), domicile: "Domicile 1")
        s.recevoirReleveMaison(releve)
        #expect(s.thread.noms.maison?.domicile == "Domicile 1")
        #expect(s.zigbee.releveMaison?.domicile == "Domicile 1")
        #expect(s.zigbee.noms.maison == nil, "sans pont lu, la fusion n'a rien a nommer")
        s.recevoirReleveMaison(nil)
        #expect(s.thread.noms.maison == nil && s.zigbee.releveMaison == nil)
    }
}
