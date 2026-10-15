import Testing
@testable import MaillageIoT

// Banc de l'etape 3a : le refus de Bonjour ne s'affiche que s'il bloque (pont lie par son adresse, sonde en USB : pas de
// message rouge trompeur).

@MainActor
@Suite("Refus de Bonjour : affiche seulement s'il bloque")
struct RefusBonjourAffichageTests {
    // Pont Hue
    @Test func pontLieNAfficheRien() {
        #expect(!ReglagesPont.afficherRefusBonjour(nonDeclare: true, pontRetenu: true, lie: true))
    }

    @Test func pontRetenuSansCleNAfficheRien() {
        #expect(!ReglagesPont.afficherRefusBonjour(nonDeclare: true, pontRetenu: true, lie: false))
    }

    @Test func pontLieSansPontRetenuNAfficheRien() {
        #expect(!ReglagesPont.afficherRefusBonjour(nonDeclare: true, pontRetenu: false, lie: true))
    }

    @Test func aucunPontEtRefusAfficheLeMessage() {
        #expect(ReglagesPont.afficherRefusBonjour(nonDeclare: true, pontRetenu: false, lie: false))
    }

    @Test func pontSansRefusNAfficheRien() {
        #expect(!ReglagesPont.afficherRefusBonjour(nonDeclare: false, pontRetenu: false, lie: false))
    }

    // Sonde Zigbee
    @Test func sondeUSBConnecteeNAfficheRien() {
        #expect(!ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .usb, connectee: true))
        #expect(!ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .usb, connectee: false))
    }

    @Test func wifiNonConnecteeAfficheLeMessage() {
        #expect(ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .reseau, connectee: false))
    }

    @Test func automatiqueNonConnecteeAfficheLeMessage() {
        #expect(ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .automatique, connectee: false))
    }

    @Test func sondeConnecteeNAfficheRien() {
        #expect(!ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .reseau, connectee: true))
        #expect(!ReglagesZigbee.afficherRefusBonjour(nonDeclare: true, chemin: .automatique, connectee: true))
    }

    @Test func sondeSansRefusNAfficheRien() {
        #expect(!ReglagesZigbee.afficherRefusBonjour(nonDeclare: false, chemin: .reseau, connectee: false))
    }
}
