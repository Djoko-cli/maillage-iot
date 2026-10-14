import Synchronization
import Testing
@testable import MaillageIoT

/// Un trousseau qui compte ses lectures et peut refuser (l'utilisateur qui refuse la fenetre de macOS).
private final class TrousseauEspion: TrousseauClesZigbee {
    let interne: TrousseauMemoireZigbee
    let refus: Bool
    private let lectures = Mutex(0)

    init(_ cles: [String: String] = [:], refus: Bool = false) {
        interne = TrousseauMemoireZigbee(cles)
        self.refus = refus
    }

    var nombreDeLectures: Int { lectures.withLock { $0 } }

    func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String {
        lectures.withLock { $0 += 1 }
        if refus { throw .systeme(-128) }  // errSecUserCanceled
        return try interne.lire(identifiant: identifiant)
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee) {
        try interne.ranger(identifiant: identifiant, cle: cle)
    }

    func oublier(identifiant: String) throws(ErreurTrousseauZigbee) {
        try interne.oublier(identifiant: identifiant)
    }
}

@Suite("Reprise des cles de Maillage Zigbee 1.1.1")
struct TrousseauReprisTests {
    @Test func cleDejaRepriseLueSansToucherALAncien() throws {
        let ancien = TrousseauEspion(["P1": "ancienne"])
        let t = TrousseauRepris(actuel: TrousseauMemoireZigbee(["P1": "actuelle"]), ancien: ancien, reprises: .memoire())
        #expect(try t.lire(identifiant: "P1") == "actuelle")
        #expect(ancien.nombreDeLectures == 0)
    }

    @Test func cleDeLAncienneAppRepriseEtRecopiee() throws {
        let actuel = TrousseauMemoireZigbee()
        let ancien = TrousseauEspion(["P1": "ancienne"])
        let t = TrousseauRepris(actuel: actuel, ancien: ancien, reprises: .memoire())
        #expect(try t.lire(identifiant: "P1") == "ancienne")
        #expect(try actuel.lire(identifiant: "P1") == "ancienne")
        #expect(try ancien.interne.lire(identifiant: "P1") == "ancienne")
    }

    @Test func absenteDesDeuxTrousseaux() {
        let t = TrousseauRepris(actuel: TrousseauMemoireZigbee(), ancien: TrousseauEspion(), reprises: .memoire())
        #expect(throws: ErreurTrousseauZigbee.absente("P1")) { try t.lire(identifiant: "P1") }
    }

    @Test func uneSeuleTentativeParIdentifiant() {
        let ancien = TrousseauEspion()
        let t = TrousseauRepris(actuel: TrousseauMemoireZigbee(), ancien: ancien, reprises: .memoire())
        _ = try? t.lire(identifiant: "P1")
        _ = try? t.lire(identifiant: "P1")
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func refusDeLUtilisateurVuCommeAbsente() {
        let ancien = TrousseauEspion(["P1": "ancienne"], refus: true)
        let t = TrousseauRepris(actuel: TrousseauMemoireZigbee(), ancien: ancien, reprises: .memoire())
        #expect(throws: ErreurTrousseauZigbee.absente("P1")) { try t.lire(identifiant: "P1") }
        _ = try? t.lire(identifiant: "P1")
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func oublierNeTouchePasLAncienEtNeReprendPlus() throws {
        let ancien = TrousseauEspion(["P1": "ancienne"])
        let t = TrousseauRepris(actuel: TrousseauMemoireZigbee(), ancien: ancien, reprises: .memoire())
        _ = try t.lire(identifiant: "P1")
        try t.oublier(identifiant: "P1")
        #expect(throws: ErreurTrousseauZigbee.absente("P1")) { try t.lire(identifiant: "P1") }
        #expect(try ancien.interne.lire(identifiant: "P1") == "ancienne")
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func rangerVaALActuel() throws {
        let actuel = TrousseauMemoireZigbee()
        let ancien = TrousseauEspion()
        let t = TrousseauRepris(actuel: actuel, ancien: ancien, reprises: .memoire())
        try t.ranger(identifiant: "P1", cle: "neuve")
        #expect(try actuel.lire(identifiant: "P1") == "neuve")
        #expect(ancien.interne.identifiants.isEmpty)
    }

    @Test func servicesDeLAncienneApp() {
        #expect(TrousseauRepris.servicePontAncien == "fr.djoko.maillage.zigbee.pont")
        #expect(TrousseauRepris.serviceSondeAncien == "fr.djoko.maillage.zigbee.sonde")
    }
}
