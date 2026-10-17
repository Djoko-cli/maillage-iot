import Foundation
import Security
import Synchronization
import Testing
@testable import MaillageIoT

/// L'identite de l'app (phase 4, tache 8) : l'app publiee et l'app de repetition (« Maillage IoT Repetition », identifiant,
/// conteneur et services de trousseau a part) ne partagent aucun element du trousseau qu'elles ECRIVENT, et la repetition
/// ne touche jamais aux elements des anciennes apps, qu'elle doit justement tester. Rien ici ne touche au vrai trousseau :
/// les trousseaux du Mac ne sont que construits, jamais lus ni ecrits.
@Suite("Identite de l'app et de la repetition")
struct IdentiteAppTests {
    static let reelle = IdentiteApp(identifiant: "fr.djoko.maillage.iot", suffixeServices: "", nom: "Maillage IoT")
    static let repetition = IdentiteApp(identifiant: "fr.djoko.maillage.iot.repetition", suffixeServices: ".repetition",
                                        nom: "Maillage IoT Répétition")

    /// Les trois services que l'app ecrit.
    static func ecrits(_ i: IdentiteApp) -> [String] { [i.serviceSondeThread, i.serviceSondeZigbee, i.servicePontHue] }

    /// Les trois services des anciennes apps, que l'app ne fait que lire.
    static let anciens = [TrousseauReprisThread.serviceAncien, TrousseauRepris.serviceSondeAncien, TrousseauRepris.servicePontAncien]

    // MARK: Les services de trousseau

    @Test func lesServicesDeLaRepetitionDifferentDeCeuxDeLApp() {
        let app = Self.ecrits(Self.reelle), essai = Self.ecrits(Self.repetition)
        #expect(Set(app).isDisjoint(with: essai), "aucun service en commun")
        for (a, r) in zip(app, essai) { #expect(a != r) }
        #expect(Set(essai).count == 3 && Set(app).count == 3, "trois services distincts")
    }

    @Test func lesServicesDeLAppPublieeNOntPasChange() {
        // Les elements deja ranges par les versions publiees : ils ne changent jamais de service.
        #expect(Self.reelle.serviceSondeThread == "fr.djoko.maillage.iot.sonde-thread")
        #expect(Self.reelle.serviceSondeZigbee == "fr.djoko.maillage.iot.sonde-zigbee")
        #expect(Self.reelle.servicePontHue == "fr.djoko.maillage.iot.pont-hue")
        #expect(!Self.reelle.estRepetition)
    }

    @Test func lesServicesDeLaRepetitionSontSuffixes() {
        #expect(Self.repetition.serviceSondeThread == "fr.djoko.maillage.iot.sonde-thread.repetition")
        #expect(Self.repetition.serviceSondeZigbee == "fr.djoko.maillage.iot.sonde-zigbee.repetition")
        #expect(Self.repetition.servicePontHue == "fr.djoko.maillage.iot.pont-hue.repetition")
        #expect(Self.repetition.estRepetition)
    }

    @Test func lesAnciensServicesNeDependentPasDeLIdentite() {
        #expect(Self.anciens == ["fr.djoko.maillage.sonde", "fr.djoko.maillage.zigbee.sonde", "fr.djoko.maillage.zigbee.pont"])
        for ancien in Self.anciens {
            #expect(!Self.ecrits(Self.reelle).contains(ancien) && !Self.ecrits(Self.repetition).contains(ancien))
            #expect(!ancien.hasSuffix(".repetition"))
        }
    }

    // MARK: Lue dans le bundle

    private func bundle(_ info: [String: Any]) throws -> (Bundle, URL) {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: dossier.appendingPathComponent("Info.plist"))
        return (try #require(Bundle(url: dossier)), dossier)
    }

    @Test func lIdentiteSeLitDansLeBundle() throws {
        let (b, d) = try bundle(["CFBundleIdentifier": "fr.djoko.maillage.iot.repetition",
                                 "CFBundleDisplayName": "Maillage IoT Répétition", IdentiteApp.cleSuffixe: ".repetition"])
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(IdentiteApp(bundle: b) == Self.repetition)
        let (r, d2) = try bundle(["CFBundleIdentifier": "fr.djoko.maillage.iot", "CFBundleDisplayName": "Maillage IoT"])
        defer { try? FileManager.default.removeItem(at: d2) }
        #expect(IdentiteApp(bundle: r) == Self.reelle, "sans cle de suffixe : l'app publiee")
    }

    @Test func lAppDesTestsEstLAppPubliee() {
        // Les tests tournent dans MaillageIoT.app : jamais l'identite de repetition, donc aucun test ne peut viser les
        // services de la repetition.
        #expect(IdentiteApp.courante == Self.reelle)
        #expect(TrousseauSystemeThread.serviceParDefaut == Self.reelle.serviceSondeThread)
        #expect(CheminSonde.serviceTrousseau == Self.reelle.serviceSondeZigbee)
        #expect(TrousseauSystemeZigbee.servicePontParDefaut == Self.reelle.servicePontHue)
    }

    @Test func unIdentifiantSansLeSuffixeEstConserveTelQuel() {
        // Une configuration bancale n'invente pas l'identifiant de l'app publiee : les services partent de l'identifiant donne.
        let i = IdentiteApp(identifiant: "x.y", suffixeServices: ".repetition", nom: "N")
        #expect(i.serviceSondeThread == "x.y.sonde-thread.repetition")
    }

    // MARK: Les trousseaux construits depuis l'identite

    @Test func lesTrousseauxDeLaRepetitionEcriventSousSesServicesEtNeLisentQueLesAnciens() throws {
        let i = Self.repetition
        let thread = i.trousseauThread()
        #expect((thread.actuel as? TrousseauSystemeThread)?.service == i.serviceSondeThread)
        #expect((thread.ancien as? TrousseauSystemeThread)?.service == TrousseauReprisThread.serviceAncien)
        let sonde = i.trousseauSondeZigbee()
        #expect((sonde.actuel as? TrousseauSystemeZigbee)?.service == i.serviceSondeZigbee)
        #expect((sonde.ancien as? TrousseauSystemeZigbee)?.service == TrousseauRepris.serviceSondeAncien)
        let pont = i.trousseauPontHue()
        #expect((pont.actuel as? TrousseauSystemeZigbee)?.service == i.servicePontHue)
        #expect((pont.ancien as? TrousseauSystemeZigbee)?.service == TrousseauRepris.servicePontAncien)
        // Les libelles, dans Trousseaux d'acces, disent de quelle app vient l'element.
        let valeurs = (pont.actuel as? TrousseauSystemeZigbee)?.valeurs(identifiant: "ABCDEF", cle: "cle")
        #expect(valeurs?[kSecAttrLabel as String] as? String == "Maillage IoT Répétition - pont Hue ABCDEF")
        let reel = (Self.reelle.trousseauPontHue().actuel as? TrousseauSystemeZigbee)?.valeurs(identifiant: "ABCDEF", cle: "cle")
        #expect(reel?[kSecAttrLabel as String] as? String == "Maillage IoT - pont Hue ABCDEF")
    }

    /// Un trousseau d'ancienne app qui n'accepte que la lecture : toute ecriture ou tout oubli est compte.
    private final class AncienEnLectureSeule: TrousseauClesThread, TrousseauClesZigbee {
        let interne = TrousseauMemoireThread()
        let internePont = TrousseauMemoireZigbee()
        let ecritures = Mutex(0)
        func lister() -> [SondeConnue] { interne.lister() }
        func lire(nom: String) throws -> Data { try interne.lire(nom: nom) }
        func ranger(nom: String, cle: Data, empreinte: String) throws { ecritures.withLock { $0 += 1 } }
        func oublier(nom: String) throws { ecritures.withLock { $0 += 1 } }
        func lire(identifiant: String) throws(ErreurTrousseauZigbee) -> String { try internePont.lire(identifiant: identifiant) }
        func ranger(identifiant: String, cle: String) throws(ErreurTrousseauZigbee) { ecritures.withLock { $0 += 1 } }
        func oublier(identifiant: String) throws(ErreurTrousseauZigbee) { ecritures.withLock { $0 += 1 } }
    }

    @Test func laRepriseNeModifieNiNEffaceJamaisUnElementDesAnciennesApps() throws {
        // Thread
        let ancienT = AncienEnLectureSeule()
        let cle = Data(repeating: 7, count: 32)
        try ancienT.interne.ranger(nom: "0000000000000001", cle: cle, empreinte: "AAAAAAAA")
        let actuelT = TrousseauMemoireThread()
        let t = TrousseauReprisThread(actuel: actuelT, ancien: ancienT, reprises: .memoire())
        _ = t.lister()
        #expect(try t.lire(nom: "0000000000000001") == cle, "la cle est reprise")
        try t.ranger(nom: "0000000000000001", cle: Data(repeating: 9, count: 32), empreinte: "BBBBBBBB")
        try t.oublier(nom: "0000000000000001")
        #expect(ancienT.ecritures.withLock { $0 } == 0, "Thread : l'ancien service n'est ni modifie ni efface")
        // Zigbee (sonde et pont)
        let ancienZ = AncienEnLectureSeule()
        try ancienZ.internePont.ranger(identifiant: "pont-1", cle: "cle-inventee")
        let actuelZ = TrousseauMemoireZigbee()
        let z = TrousseauRepris(actuel: actuelZ, ancien: ancienZ, reprises: .memoire())
        #expect(try z.lire(identifiant: "pont-1") == "cle-inventee")
        try z.ranger(identifiant: "pont-1", cle: "autre")
        try z.oublier(identifiant: "pont-1")
        #expect(ancienZ.ecritures.withLock { $0 } == 0, "Zigbee : l'ancien service n'est ni modifie ni efface")
    }

    // MARK: L'etat de la reprise suit l'identite

    final class InventaireEspion: InventaireTrousseau {
        let demandes = Mutex<[String]>([])
        func comptes(service: String) -> Set<String> {
            demandes.withLock { $0.append(service) }
            return []
        }
    }

    @Test func lAssistantLitLesServicesDeLaRepetitionEtLesAnciens() async {
        let nom = "fr.djoko.maillage.iot.essai-identite-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: nom)?.removePersistentDomain(forName: nom) }
        let espion = InventaireEspion()
        let lecteur = LecteurEtatSystemeReel(inventaire: espion, suite: nom, identite: Self.repetition,
                                             notifications: { .nonDemandees }, ouverture: { .aApprouver },
                                             reseauLocalRefuse: { false })
        _ = await lecteur.lire()
        let vus = Set(espion.demandes.withLock { $0 })
        #expect(vus == Set(Self.ecrits(Self.repetition) + Self.anciens), "ses services et ceux des anciennes apps, rien d'autre")
        #expect(vus.isDisjoint(with: Self.ecrits(Self.reelle)), "jamais ceux de l'app publiee")
    }
}
