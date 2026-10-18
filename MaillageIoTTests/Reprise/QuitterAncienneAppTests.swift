import Foundation
import MaillageCoeur
import os
import Security
import Testing
@testable import MaillageIoT

/// Banc de la repetition : quitter l'ancienne app par la voie native (l'evenement Apple « quit »). Aucun test n'envoie un vrai
/// evenement : l'envoi est une couture (`EnvoyeurQuitter`), remplacee ici par un espion. L'essai reel (invite « Maillage IoT veut
/// controler Maillage Thread ») se fait au banc, avec Djoko.
@MainActor
@Suite("Quitter l'ancienne app")
struct QuitterAncienneAppTests {
    typealias App = ContratExport.AppSource

    /// Note les cibles et repond ce qu'on lui dit : jamais d'evenement reel.
    final class EspionEnvoi: EnvoyeurQuitter, Sendable {
        private let notes = OSAllocatedUnfairLock<[String]>(initialState: [])
        let issue: IssueQuitter
        init(_ issue: IssueQuitter) { self.issue = issue }
        var cibles: [String] { notes.withLock { $0 } }
        func envoyerQuitter(a identifiantBundle: String) async -> IssueQuitter {
            notes.withLock { $0.append(identifiantBundle) }
            return issue
        }
    }

    static func systeme(_ espion: EspionEnvoi, lances: [String?]) -> ApplicationsLanceesSysteme {
        ApplicationsLanceesSysteme(envoyeur: espion, identifiantsLances: { lances })
    }

    @Test(arguments: App.allCases)
    func lEvenementVaAL_ancienneAppDeLExport(app: App) async {
        let espion = EspionEnvoi(.envoyee)
        // Les deux anciennes apps tournent : seule celle de l'export est visee.
        let lances = App.allCases.map(\.identifiantBundle)
        let systeme = Self.systeme(espion, lances: lances)
        #expect(await systeme.demanderDeQuitter(app.identifiantBundle))
        #expect(espion.cibles == [app.identifiantBundle])
    }

    @Test func unRefusDuSystemeDonneLeRepli() async {
        for code in [-1743, -600, -1744] {
            let espion = EspionEnvoi(.refusee(code: code))
            let systeme = Self.systeme(espion, lances: [App.maillageThread.identifiantBundle])
            #expect(await systeme.demanderDeQuitter(App.maillageThread.identifiantBundle) == false, "code \(code)")
            #expect(espion.cibles == [App.maillageThread.identifiantBundle])
        }
    }

    @Test func unDelaiLaisseLaReverificationDecider() async {
        let espion = EspionEnvoi(.delai)
        let systeme = Self.systeme(espion, lances: [App.maillageZigbee.identifiantBundle])
        #expect(await systeme.demanderDeQuitter(App.maillageZigbee.identifiantBundle), "l'evenement est peut-etre parti : on reverifie")
    }

    @Test func aucunEvenementPourUneAutreAppNiPourUneAppQuiNeTournePas() async {
        // Une app qui tourne mais n'est pas une ancienne app : rien n'est envoye, la demande n'est pas acceptee.
        for autre in ["com.apple.finder", "fr.djoko.maillage.iot", "fr.djoko.maillage.iot.repetition", "fr.djoko.maillage.passeur"] {
            let espion = EspionEnvoi(.envoyee)
            let systeme = Self.systeme(espion, lances: [autre, App.maillageThread.identifiantBundle])
            #expect(await systeme.demanderDeQuitter(autre) == false, "\(autre)")
            #expect(espion.cibles.isEmpty, "aucun evenement pour \(autre)")
        }
        // Une ancienne app qui ne tourne pas : rien a quitter, rien d'envoye.
        let espion = EspionEnvoi(.envoyee)
        let systeme = Self.systeme(espion, lances: ["com.apple.finder"])
        #expect(await systeme.demanderDeQuitter(App.maillageThread.identifiantBundle))
        #expect(espion.cibles.isEmpty)
    }

    @Test func l_envoyeurDuSystemeRefuseUneAutreAppSansRienEnvoyer() async {
        // Ces identifiants ne sont pas des anciennes apps : l'envoyeur reel rend `nonAutorisee` avant tout evenement.
        for autre in ["com.apple.finder", "fr.djoko.maillage.iot", "fr.djoko.maillage."] {
            #expect(await EnvoyeurQuitterSysteme().envoyerQuitter(a: autre) == .nonAutorisee, "\(autre)")
        }
    }

    @Test func lesCodesDuSystemeDonnentLesIssues() {
        #expect(IssueQuitter(codeErreur: -1712) == .delai)
        #expect(IssueQuitter(codeErreur: -1743) == .refusee(code: -1743))
        #expect(IssueQuitter(codeErreur: -600) == .refusee(code: -600))
    }

    // MARK: Les droits du produit

    @Test func lesIdentifiantsAutorisesSontExactementLesDeuxAnciennesApps() {
        #expect(AnciennesApps.identifiantsAutorises == ["fr.djoko.maillage", "fr.djoko.maillage.zigbee"])
    }

    /// Les droits signes du processus de test (l'app elle-meme) : l'exception Apple events est limitee a ces deux identifiants.
    @Test func lesDroitsDuProduitContiennentExactementCesDeuxIdentifiants() throws {
        let tache = try #require(SecTaskCreateFromSelf(nil))
        let valeur = SecTaskCopyValueForEntitlement(tache, "com.apple.security.temporary-exception.apple-events" as CFString, nil)
        let identifiants = try #require(valeur as? [String], "le droit manque dans les droits signes de l'app")
        #expect(Set(identifiants) == AnciennesApps.identifiantsAutorises && identifiants.count == 2)
        // L'app est en runtime durci : sans ce droit macOS refuse tout evenement (et ne demande rien). Le bac a sable, lui, ne
        // laisse viser que les deux identifiants de l'exception ci-dessus.
        #expect(SecTaskCopyValueForEntitlement(tache, "com.apple.security.automation.apple-events" as CFString, nil) as? Bool == true)
    }

    @Test func laRaisonDeLAutomatisationEstDitePourChaqueLangue() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String != nil)
        for langue in ["fr", "en"] {
            let chemin = try #require(Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: langue),
                                      "catalogue InfoPlist \(langue)")
            let dictionnaire = try #require(NSDictionary(contentsOfFile: chemin) as? [String: String])
            let texte = try #require(dictionnaire["NSAppleEventsUsageDescription"], "texte \(langue)")
            #expect(texte.contains("Maillage Thread") && texte.contains("Maillage Zigbee"), "\(langue) : \(texte)")
        }
    }

    // MARK: L'assistant pendant l'envoi

    /// Des apps dont la demande de quitter reste en vol (l'invite d'Automatisation attend Djoko) jusqu'a `ouvrir()`.
    @MainActor
    final class AppsEnAttente: ApplicationsLancees {
        let porte = AssistantRepriseTests.Porte()
        var tourne = true
        var demandes = 0
        func instances(de identifiantBundle: String) -> Int { tourne ? 1 : 0 }
        func demanderDeQuitter(_ identifiantBundle: String) async -> Bool {
            demandes += 1
            await porte.attendre()
            return false
        }
    }

    /// L'invite d'Automatisation peut attendre longtemps : pendant ce temps l'ecran dit qu'on attend (le bouton « Quitter » ne
    /// repart pas), puis, si macOS refuse, l'assistant passe a « la quitter soi-meme ».
    @Test func pendantLInviteLEcranAttendEtUnSecondClicNEnvoieRien() async throws {
        let b = try AssistantRepriseTests.Banc()
        defer { b.nettoyer() }
        let apps = AppsEnAttente()
        let assistant = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: apps,
                                         lecteur: AssistantRepriseTests.LecteurFactice(), preferences: b.preferences,
                                         arreterModules: {}, relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        await assistant.valider(try ApplicationImportTests.exemple(.maillageZigbee))
        #expect(assistant.ancienneApp == .tourne)
        let premier = Task { @MainActor in await assistant.quitterAncienneApp() }
        for _ in 0..<200 where apps.demandes == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(apps.demandes == 1)
        #expect(assistant.ancienneApp == .demandeEnvoyee, "l'invite est a l'ecran : on attend")
        let second = Task { @MainActor in await assistant.quitterAncienneApp() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(apps.demandes == 1, "un second clic n'envoie rien de plus")
        apps.porte.ouvrir()
        await premier.value
        await second.value
        #expect(assistant.ancienneApp == .aQuitterSoiMeme, "refus de macOS : repli")
    }

    @Test func annulerPendantLInviteNeLaisseRienDeTravers() async throws {
        let b = try AssistantRepriseTests.Banc()
        defer { b.nettoyer() }
        let apps = AppsEnAttente()
        let assistant = AssistantReprise(importeur: b.importeur, dossierDonnees: b.donnees.racine, applications: apps,
                                         lecteur: AssistantRepriseTests.LecteurFactice(), preferences: b.preferences,
                                         arreterModules: {}, relancer: {}, choisirDossier: { nil }, attendre: { _ in })
        await assistant.valider(try ApplicationImportTests.exemple(.maillageThread))
        let envoi = Task { @MainActor in await assistant.quitterAncienneApp() }
        for _ in 0..<200 where apps.demandes == 0 { try await Task.sleep(for: .milliseconds(5)) }
        assistant.recommencer()
        apps.porte.ouvrir()
        await envoi.value
        #expect(assistant.etape == .accueil && assistant.ancienneApp == .absente, "la reponse tardive ne change plus rien")
    }
}
