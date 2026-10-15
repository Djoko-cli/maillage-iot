import Foundation
import MaillageCoeur
import Synchronization
import Testing
@testable import MaillageIoT

/// Un trousseau de Thread qui compte ses lectures et peut refuser (l'utilisateur qui refuse la fenetre de macOS).
private final class TrousseauEspionThread: TrousseauClesThread {
    let interne = TrousseauMemoireThread()
    let refus: Bool
    private let lectures = Mutex(0)
    private let listes = Mutex(0)

    init(_ cles: [String: Data] = [:], refus: Bool = false) throws {
        self.refus = refus
        for (nom, cle) in cles { try interne.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle)) }
    }

    var nombreDeLectures: Int { lectures.withLock { $0 } }
    var nombreDeListes: Int { listes.withLock { $0 } }

    func lister() -> [SondeConnue] {
        listes.withLock { $0 += 1 }
        return interne.lister()
    }

    func lire(nom: String) throws -> Data {
        lectures.withLock { $0 += 1 }
        if refus { throw ErreurTrousseauThread.systeme(-128) }  // errSecUserCanceled
        return try interne.lire(nom: nom)
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        try interne.ranger(nom: nom, cle: cle, empreinte: empreinte)
    }

    func oublier(nom: String) throws {
        try interne.oublier(nom: nom)
    }
}

@Suite("Reprise de la cle de la sonde Thread (Thread 1.3.0)")
struct TrousseauReprisThreadTests {
    static let hote = "0000000000000001"
    static let ancienne = Data(repeating: 7, count: 32)
    static let actuelle = Data(repeating: 9, count: 32)

    private func trousseau(actuel: TrousseauMemoireThread = TrousseauMemoireThread(), ancien: TrousseauEspionThread)
        -> TrousseauReprisThread {
        TrousseauReprisThread(actuel: actuel, ancien: ancien, reprises: .memoire())
    }

    @Test func cleDejaRepriseLueSansToucherALAncien() throws {
        let actuel = TrousseauMemoireThread()
        try actuel.ranger(nom: Self.hote, cle: Self.actuelle, empreinte: "AAAAAAAA")
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne])
        let t = trousseau(actuel: actuel, ancien: ancien)
        #expect(try t.lire(nom: Self.hote) == Self.actuelle)
        #expect(ancien.nombreDeLectures == 0)
    }

    @Test func cleDeLAncienneAppRepriseEtRecopiee() throws {
        let actuel = TrousseauMemoireThread()
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne])
        let t = trousseau(actuel: actuel, ancien: ancien)
        #expect(try t.lire(nom: Self.hote) == Self.ancienne)
        #expect(try actuel.lire(nom: Self.hote) == Self.ancienne)
        #expect(actuel.lister() == [SondeConnue(nom: Self.hote, empreinte: H1.kid(cle: Self.ancienne))])
        #expect(try ancien.interne.lire(nom: Self.hote) == Self.ancienne)
    }

    @Test func absenteDesDeuxTrousseaux() throws {
        let t = trousseau(ancien: try TrousseauEspionThread())
        #expect(throws: ErreurTrousseauThread.absente(Self.hote)) { try t.lire(nom: Self.hote) }
    }

    @Test func uneSeuleTentativeParSonde() throws {
        let ancien = try TrousseauEspionThread()
        let t = trousseau(ancien: ancien)
        _ = try? t.lire(nom: Self.hote)
        _ = try? t.lire(nom: Self.hote)
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func refusDeLUtilisateurVuCommeAbsente() throws {
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne], refus: true)
        let t = trousseau(ancien: ancien)
        #expect(throws: ErreurTrousseauThread.absente(Self.hote)) { try t.lire(nom: Self.hote) }
        _ = try? t.lire(nom: Self.hote)
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func oublierNeTouchePasLAncienEtNeReprendPlus() throws {
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne])
        let t = trousseau(ancien: ancien)
        _ = try t.lire(nom: Self.hote)
        try t.oublier(nom: Self.hote)
        #expect(throws: ErreurTrousseauThread.absente(Self.hote)) { try t.lire(nom: Self.hote) }
        #expect(try ancien.interne.lire(nom: Self.hote) == Self.ancienne)
        #expect(ancien.nombreDeLectures == 1)
    }

    @Test func oublierAvantToutEssaiNeReprendPlus() throws {
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne])
        let t = trousseau(ancien: ancien)
        try t.oublier(nom: Self.hote)
        #expect(throws: ErreurTrousseauThread.absente(Self.hote)) { try t.lire(nom: Self.hote) }
        #expect(ancien.nombreDeLectures == 0)
        #expect(try ancien.interne.lire(nom: Self.hote) == Self.ancienne)
    }

    @Test func rangerVaALActuel() throws {
        let actuel = TrousseauMemoireThread()
        let ancien = try TrousseauEspionThread()
        let t = trousseau(actuel: actuel, ancien: ancien)
        try t.ranger(nom: Self.hote, cle: Self.actuelle, empreinte: "AAAAAAAA")
        #expect(try actuel.lire(nom: Self.hote) == Self.actuelle)
        #expect(ancien.interne.lister().isEmpty)
    }

    /// La liste (qui donne `empreinteAcces`, donc le selecteur « Liaison ») montre la cle de l'ancienne app sans la lire :
    /// ni fenetre de macOS, ni tentative consommee. Le selecteur apparait, et la reprise se fait a la connexion.
    @Test func listeMontreLAncienneCleSansLaLire() throws {
        let actuel = TrousseauMemoireThread()
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne])
        let t = trousseau(actuel: actuel, ancien: ancien)
        #expect(t.lister() == [SondeConnue(nom: Self.hote, empreinte: H1.kid(cle: Self.ancienne))])
        #expect(ancien.nombreDeLectures == 0 && actuel.lister().isEmpty)
        _ = try t.lire(nom: Self.hote)
        #expect(t.lister().count == 1 && actuel.lister().count == 1)
    }

    @Test func listeNeMontrePlusUneCleRefuseeOuOubliee() throws {
        let refuse = try TrousseauEspionThread([Self.hote: Self.ancienne], refus: true)
        let t = trousseau(ancien: refuse)
        _ = try? t.lire(nom: Self.hote)
        #expect(t.lister().isEmpty, "refusee : plus proposee")
        let oublie = trousseau(ancien: try TrousseauEspionThread([Self.hote: Self.ancienne]))
        try oublie.oublier(nom: Self.hote)
        #expect(oublie.lister().isEmpty, "oubliee : plus proposee")
    }

    @Test func listeDonneLaPrioriteALActuel() throws {
        let actuel = TrousseauMemoireThread()
        try actuel.ranger(nom: Self.hote, cle: Self.actuelle, empreinte: "AAAAAAAA")
        let t = trousseau(actuel: actuel, ancien: try TrousseauEspionThread([Self.hote: Self.ancienne]))
        #expect(t.lister() == [SondeConnue(nom: Self.hote, empreinte: "AAAAAAAA")])
    }

    @Test func serviceDeLAncienneApp() {
        #expect(TrousseauReprisThread.serviceAncien == "fr.djoko.maillage.sonde")
        #expect(TrousseauSystemeThread(service: TrousseauReprisThread.serviceAncien).service == "fr.djoko.maillage.sonde")
    }

    /// Banc de l'etape 3a, I1 : l'ancienne cle est listee (attributs seuls), donc « autorise » et le selecteur de liaison
    /// apparaissent ; Djoko refuse la fenetre de macOS a la connexion : l'etat d'acces est relu (plus de cle, plus de reseau).
    @Test @MainActor func refusALaConnexionRetireLEtatAcces() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set(Self.hote, forKey: SondeMaillageThread.cleHote)
        p.set(SondeMaillageThread.Liaison.reseau.rawValue, forKey: SondeMaillageThread.cleLiaison)
        let ancien = try TrousseauEspionThread([Self.hote: Self.ancienne], refus: true)
        let t = trousseau(ancien: ancien)
        let s = SondeReseauTests.sondeMaillage(p, trousseau: t, reseau: ReseauFactice([]))
        #expect(s.empreinteAcces == H1.kid(cle: Self.ancienne) && s.reseauDisponible)
        await s.connecterReseau()
        #expect(s.etat == .erreur(ErreurTrousseauThread.absente(Self.hote).localizedDescription))
        #expect(s.empreinteAcces == nil && !s.reseauDisponible)
        await s.oublier()
    }
}
