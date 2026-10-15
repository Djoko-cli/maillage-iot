import Foundation
import Network
import dnssd
import os

/// Ce que le recenseur de Thread, la decouverte du pont Hue et la sonde Zigbee demandent a une ecoute Bonjour : les tests
/// en donnent une factice (aucun reseau), et y comptent les demarrages et les arrets.
@MainActor
protocol EcouteBonjour: AnyObject {
    var type: String { get }
    /// Instance -> TXT brut (vide si l'ecoute n'en a pas donne).
    var instances: [String: Data] { get }
    var etat: NavigateurBonjour.Etat { get }
    /// Appele sur le fil principal a chaque changement d'instances ou d'etat.
    var surChangement: (() -> Void)? { get set }
    func demarrer()
    func arreter()
}

/// Ecoute Bonjour d'un type de service (NWBrowser, avec les TXT) : garde la
/// liste des instances vues et le TXT brut de chacune.
@MainActor
final class NavigateurBonjour: EcouteBonjour {
    enum Etat: Equatable, Sendable {
        case demarrage, pret
        /// Reseau local refuse a l'app (PolicyDenied).
        case refuse
        /// Type de service absent de la liste NSBonjourServices que macOS connait pour l'app (NoAuth, -65555) : le plus
        /// souvent un enregistrement de l'app perime (un type ajoute depuis le premier lancement), pas un refus de
        /// l'utilisateur.
        case nonDeclare
        case erreur(String)
    }

    nonisolated static let journal = Logger(subsystem: "fr.djoko.maillage.iot", category: "bonjour")

    let type: String
    /// Instance -> TXT brut (vide si le navigateur n'en a pas donne).
    private(set) var instances: [String: Data] = [:]
    private(set) var etat: Etat = .demarrage
    /// Appele sur le fil principal a chaque changement d'instances ou d'etat.
    var surChangement: (() -> Void)?
    private var navigateur: NWBrowser?
    /// Relance planifiee apres un echec du navigateur (10 s) : annulee par `arreter`.
    private var relance: Task<Void, Never>?

    init(type: String) {
        self.type = type
    }

    /// Lance l'ecoute ; sans effet si elle tourne deja (un seul NWBrowser a la fois).
    func demarrer() {
        guard navigateur == nil else { return }
        relance?.cancel()
        relance = nil
        let n = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: NWParameters())
        n.stateUpdateHandler = { [weak self] etat in
            MainActor.assumeIsolated { self?.changerEtat(etat) }
        }
        n.browseResultsChangedHandler = { [weak self] resultats, _ in
            MainActor.assumeIsolated { self?.noter(resultats) }
        }
        navigateur = n
        n.start(queue: .main)
    }

    /// Arret definitif de l'ecoute : le NWBrowser est annule sans plus rien rapporter, la relance planifiee aussi, et la
    /// liste des instances est videe (un nouveau `demarrer` repart de zero et rapporte tout ce qu'il voit).
    func arreter() {
        relance?.cancel()
        relance = nil
        fermer()
        instances = [:]
        etat = .demarrage
    }

    /// Ferme le NWBrowser, sans toucher a la liste ni a l'etat ; ses rappels ne sont plus ecoutes.
    private func fermer() {
        navigateur?.stateUpdateHandler = nil
        navigateur?.browseResultsChangedHandler = nil
        navigateur?.cancel()
        navigateur = nil
    }

    private func noter(_ resultats: Set<NWBrowser.Result>) {
        var vus: [String: Data] = [:]
        for r in resultats {
            // Un meme service est vu une fois par interface (en0, en18...) : une seule entree.
            guard case let .service(nom, _, _, _) = r.endpoint else { continue }
            var txt = Data()
            if case let .bonjour(enregistrement) = r.metadata { txt = enregistrement.data }
            if vus[nom]?.isEmpty ?? true { vus[nom] = txt }
        }
        guard vus != instances else { return }
        instances = vus
        surChangement?()
    }

    private func changerEtat(_ e: NWBrowser.State) {
        let nouveau: Etat
        switch e {
        case .setup, .cancelled: nouveau = .demarrage
        case .ready: nouveau = .pret
        case .waiting(let erreur), .failed(let erreur):
            nouveau = Self.etat(erreur)
            // Le type et le code seulement (aucun identifiant d'appareil ni de reseau).
            Self.journal.error("ecoute Bonjour \(self.type, privacy: .public) en echec : \(Self.code(erreur), privacy: .public)")
        @unknown default: nouveau = .demarrage
        }
        if case .failed = e {
            // Relance dans 10 s (le reseau revient souvent seul), sauf si `arreter` l'annule d'ici la.
            fermer()
            relance?.cancel()
            relance = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.demarrer()
            }
        }
        guard nouveau != etat else { return }
        etat = nouveau
        surChangement?()
    }

    /// Refus du reseau local : le navigateur attend avec l'erreur DNS PolicyDenied. Type non declare pour macOS : NoAuth.
    static func etat(_ erreur: NWError) -> Etat {
        if case .dns(let code) = erreur {
            if code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) { return .refuse }
            if code == DNSServiceErrorType(kDNSServiceErr_NoAuth) { return .nonDeclare }
        }
        return .erreur(erreur.debugDescription)
    }

    /// Le code de l'erreur, pour le journal : « DNS -65555 », sinon la description du systeme.
    static func code(_ erreur: NWError) -> String {
        if case .dns(let code) = erreur { return "DNS \(code)" }
        return erreur.debugDescription
    }
}
