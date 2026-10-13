import Foundation
import ServiceManagement
import Testing
@testable import MaillageIoT

/// L'etat de Thread Route, lu de ce que le systeme dit de ses deux plists : le sien et celui de
/// halo-routes, son ancien nom. Jamais l'etat reel du Mac, qui depend de la machine : la decision se teste
/// sur des etats donnes, et la lecture sur une source simulee des deux plists.
@Suite("Thread Route : son etat")
struct ThreadRouteTests {
    /// Ce que dirait le systeme des deux plists, et les plists qu'on lui a demandes. Les chemins sont ecrits
    /// en dur : une constante de l'app qui changerait ne ferait pas suivre le test.
    final class SourceSimulee {
        let nouveau: SMAppService.Status
        let ancien: SMAppService.Status
        private(set) var interroges: [String] = []

        init(nouveau: SMAppService.Status, ancien: SMAppService.Status) {
            self.nouveau = nouveau
            self.ancien = ancien
        }

        func statut(_ plist: URL) -> SMAppService.Status {
            interroges.append(plist.path)
            switch plist.path {
            case "/Library/LaunchDaemons/fr.djoko.thread.route.plist": return nouveau
            case "/Library/LaunchDaemons/fr.djoko.halo.routes.plist": return ancien
            default:
                Issue.record("plist inattendu : \(plist.path)")
                return .notFound
            }
        }
    }

    /// L'etat que lit `lire` quand le systeme repond `nouveau` pour Thread Route et `ancien` pour halo-routes.
    static func lu(nouveau: SMAppService.Status, ancien: SMAppService.Status) -> EtatThreadRoute {
        EtatThreadRoute.lire(statut: SourceSimulee(nouveau: nouveau, ancien: ancien).statut)
    }

    /// Les quatre cas : absent, a approuver, actif, ancien.
    @Test func quatreCas() {
        #expect(EtatThreadRoute.depuis(nouveau: .notRegistered, ancien: .notRegistered) == .absent)
        #expect(EtatThreadRoute.depuis(nouveau: .notFound, ancien: .notFound) == .absent)
        #expect(EtatThreadRoute.depuis(nouveau: .requiresApproval, ancien: .notRegistered) == .aApprouver,
                "desactive dans Reglages Systeme")
        #expect(EtatThreadRoute.depuis(nouveau: .enabled, ancien: .notRegistered) == .actif)
        #expect(EtatThreadRoute.depuis(nouveau: .notRegistered, ancien: .enabled) == .ancien, "halo-routes encore la")
        #expect(EtatThreadRoute.depuis(nouveau: .notRegistered, ancien: .requiresApproval) == .ancien)
    }

    /// Thread Route compte d'abord : un halo-routes reste n'y change rien.
    @Test func leNouveauDAbord() {
        #expect(EtatThreadRoute.depuis(nouveau: .enabled, ancien: .enabled) == .actif)
        #expect(EtatThreadRoute.depuis(nouveau: .requiresApproval, ancien: .enabled) == .aApprouver)
    }

    /// Les cas limites : `.notFound` (plist absent) se traite comme `.notRegistered`, des deux cotes.
    @Test func notFoundSeTraiteCommeNotRegistered() {
        #expect(EtatThreadRoute.depuis(nouveau: .notFound, ancien: .enabled) == .ancien,
                "halo-routes encore la, Thread Route introuvable")
        #expect(EtatThreadRoute.depuis(nouveau: .notFound, ancien: .requiresApproval) == .ancien)
        #expect(EtatThreadRoute.depuis(nouveau: .notRegistered, ancien: .notFound) == .absent)
        #expect(EtatThreadRoute.depuis(nouveau: .notFound, ancien: .notRegistered) == .absent)
    }

    /// `lire` interroge le systeme sur les deux plists, chacun a sa place : Thread Route pour `nouveau`,
    /// halo-routes pour `ancien`. Un plist permute, ou un etat constant, change au moins une ligne.
    @Test func lireLesDeuxPlists() {
        #expect(Self.lu(nouveau: .enabled, ancien: .notFound) == .actif)
        #expect(Self.lu(nouveau: .notFound, ancien: .enabled) == .ancien)
        #expect(Self.lu(nouveau: .requiresApproval, ancien: .notFound) == .aApprouver)
        #expect(Self.lu(nouveau: .notFound, ancien: .requiresApproval) == .ancien)
        #expect(Self.lu(nouveau: .notFound, ancien: .notFound) == .absent)
        #expect(Self.lu(nouveau: .enabled, ancien: .enabled) == .actif, "le nouveau d'abord")
        #expect(Self.lu(nouveau: .requiresApproval, ancien: .enabled) == .aApprouver)
        // Les deux plists sont demandes, une fois chacun.
        let source = SourceSimulee(nouveau: .notFound, ancien: .notFound)
        _ = EtatThreadRoute.lire(statut: source.statut)
        #expect(source.interroges.sorted() == [
            "/Library/LaunchDaemons/fr.djoko.halo.routes.plist",
            "/Library/LaunchDaemons/fr.djoko.thread.route.plist",
        ])
    }

    /// Les plists que lit l'app : ceux que posent l'installateur et l'ancien.
    @Test func plists() {
        #expect(EtatThreadRoute.plist.path == "/Library/LaunchDaemons/fr.djoko.thread.route.plist")
        #expect(EtatThreadRoute.plistAncien.path == "/Library/LaunchDaemons/fr.djoko.halo.routes.plist")
    }

    /// Les textes de chaque etat, mot pour mot, dans chaque langue ; les memes cles que Halo Compagnon,
    /// la commande d'installation exceptee (celle de la copie de ce depot).
    struct Textes {
        let absent, aApprouver, actif, ancien: String
        let consigneAbsent, consigneAApprouver, consigneAncien: String
    }

    static let francais = Textes(
        absent: "Absent",
        aApprouver: "Désactivé dans Réglages Système",
        actif: "Actif",
        ancien: "halo-routes, son ancien nom, est encore installé",
        consigneAbsent: "Pour l'installer : sh outils/thread-route/installer.sh (mot de passe administrateur).",
        consigneAApprouver: "L'autoriser dans Réglages Système, Général, Ouverture et extensions.",
        consigneAncien: "Pour le remplacer : sh outils/thread-route/installer.sh (mot de passe administrateur).")

    static let anglais = Textes(
        absent: "Absent",
        aApprouver: "Turned off in System Settings",
        actif: "Active",
        ancien: "halo-routes, its former name, is still installed",
        consigneAbsent: "To install it: sh outils/thread-route/installer.sh (administrator password).",
        consigneAApprouver: "Allow it in System Settings, General, Login Items & Extensions.",
        consigneAncien: "To replace it: sh outils/thread-route/installer.sh (administrator password).")

    /// La langue de ce lancement des tests (`-testLanguage`) : les textes de l'app la suivent.
    static var langue: String { Bundle.main.preferredLocalizations.first ?? "" }

    /// Ce que montrent les Reglages dans la langue du lancement : le libelle de chaque etat, et ce qu'il reste
    /// a faire. `.actif` n'a rien a faire : sa consigne est nil, son libelle l'affirme.
    @Test func libellesEtConsignes() throws {
        let t: Textes
        switch Self.langue {
        case "fr": t = Self.francais
        case "en": t = Self.anglais
        default: throw ErreurLangue(langue: Self.langue)
        }
        #expect(EtatThreadRoute.absent.libelle == t.absent)
        #expect(EtatThreadRoute.aApprouver.libelle == t.aApprouver)
        #expect(EtatThreadRoute.actif.libelle == t.actif)
        #expect(EtatThreadRoute.ancien.libelle == t.ancien)
        #expect(EtatThreadRoute.absent.consigne == t.consigneAbsent)
        #expect(EtatThreadRoute.aApprouver.consigne == t.consigneAApprouver)
        #expect(EtatThreadRoute.actif.consigne == nil, "rien a faire quand il est actif")
        #expect(EtatThreadRoute.ancien.consigne == t.consigneAncien)
    }

    struct ErreurLangue: Error, CustomStringConvertible {
        let langue: String
        var description: String { "langue des tests inattendue : \(langue)" }
    }

    /// Le catalogue de l'app, lu dans chacune de ses deux langues quelle que soit celle du lancement : chaque
    /// texte est traduit, mot pour mot. Les cles sont les textes francais.
    @Test(arguments: [("fr", francais), ("en", anglais)])
    func catalogueDansChaqueLangue(langue: String, t: Textes) throws {
        let chemin = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                   inDirectory: nil, forLocalization: langue),
                                  "catalogue \(langue) absent de l'app")
        let table = try #require(NSDictionary(contentsOfFile: chemin) as? [String: String])
        func traduit(_ cle: String) -> String? { table[cle] }
        #expect(traduit(Self.francais.absent) == t.absent)
        #expect(traduit(Self.francais.aApprouver) == t.aApprouver)
        #expect(traduit(Self.francais.actif) == t.actif)
        #expect(traduit(Self.francais.ancien) == t.ancien)
        #expect(traduit(Self.francais.consigneAbsent) == t.consigneAbsent)
        #expect(traduit(Self.francais.consigneAApprouver) == t.consigneAApprouver)
        #expect(traduit(Self.francais.consigneAncien) == t.consigneAncien)
        #expect(traduit("Thread Route") == "Thread Route")
        #expect(traduit("État") == (langue == "fr" ? "État" : "Status"))
        #expect(traduit("Ouvrir Réglages Système…") == (langue == "fr" ? "Ouvrir Réglages Système…" : "Open System Settings…"))
    }
}
