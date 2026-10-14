import Foundation
import Synchronization
@testable import MaillageIoT

// Les doublures de l'arret reel d'un protocole (« Activer ce protocole », tache 11) : un suivi des ports, des ecoutes
// Bonjour et des ports serie qui comptent tout ce qu'on leur demande, sans IOKit, sans reseau, sans port reel.

/// Suivi des ports factice : compte ses demarrages et ses arrets ; `changement` simule un evenement USB.
@MainActor
final class PortsFactices: SurveillantPorts {
    var changement: (([PortUSB]) -> Void)?
    private(set) var demarrages = 0
    private(set) var arrets = 0
    private(set) var enMarche = false

    func demarrer() {
        demarrages += 1
        enMarche = true
    }

    func arreter() {
        arrets += 1
        enMarche = false
    }
}

/// Fabrique des suivis de ports d'une sonde : un neuf a chaque `demarrer` de la sonde.
@MainActor
final class FabriquePorts {
    private(set) var crees: [PortsFactices] = []

    func fabriquer() -> any SurveillantPorts {
        let p = PortsFactices()
        crees.append(p)
        return p
    }

    /// Combien de suivis tournent en ce moment.
    var enMarche: Int { crees.filter(\.enMarche).count }
    var demarrages: Int { crees.reduce(0) { $0 + $1.demarrages } }
    var arrets: Int { crees.reduce(0) { $0 + $1.arrets } }

    /// Un evenement USB : la liste des ports branches, donnee au suivi en marche (s'il n'y en a pas, personne n'ecoute).
    func brancher(_ liste: [PortUSB]) {
        crees.last { $0.enMarche }?.changement?(liste)
    }
}

/// Ecoute Bonjour factice : compte ses demarrages et ses arrets ; `voir` simule une annonce.
@MainActor
final class BonjourFactice: EcouteBonjour {
    let type: String
    var instances: [String: Data] = [:]
    var etat: NavigateurBonjour.Etat = .demarrage
    var surChangement: (() -> Void)?
    private(set) var demarrages = 0
    private(set) var arrets = 0
    private(set) var enMarche = false

    init(type: String) {
        self.type = type
    }

    func demarrer() {
        demarrages += 1
        enMarche = true
    }

    func arreter() {
        arrets += 1
        enMarche = false
        instances = [:]
    }

    /// Le service `nom` est annonce.
    func voir(_ nom: String) {
        instances[nom] = Data()
        surChangement?()
    }
}

/// Fabrique des ecoutes Bonjour : une par type et par demarrage.
@MainActor
final class FabriqueBonjour {
    private(set) var crees: [BonjourFactice] = []

    func fabriquer(_ type: String) -> any EcouteBonjour {
        let b = BonjourFactice(type: type)
        crees.append(b)
        return b
    }

    /// Combien d'ecoutes tournent en ce moment.
    var enMarche: Int { crees.filter(\.enMarche).count }
    var demarrages: Int { crees.reduce(0) { $0 + $1.demarrages } }
    var arrets: Int { crees.reduce(0) { $0 + $1.arrets } }
    var types: [String] { crees.map(\.type) }
}

/// Les ports serie qu'une sonde touche : chaque chemin demande a la fabrique de canaux, et les canaux ouverts et fermes.
/// Un port « ouvert » est un canal dont `ouvrir()` a reussi et dont `fermer()` n'a pas encore ete appele.
final class RegistrePorts: Sendable {
    private struct Etat {
        var chemins: [String] = []
        var ouvertures = 0
        var fermetures = 0
    }

    private let etat = Mutex(Etat())

    /// Chaque chemin pour lequel la sonde a demande un canal, dans l'ordre.
    var chemins: [String] { etat.withLock { $0.chemins } }
    var ouvertures: Int { etat.withLock { $0.ouvertures } }
    /// Ports ouverts et pas encore fermes.
    var ouverts: Int { etat.withLock { $0.ouvertures - $0.fermetures } }

    /// Le canal d'un port : `interne` repond, le registre compte.
    func canal(_ chemin: String, _ interne: any CanalSonde) -> CanalRegistre {
        etat.withLock { $0.chemins.append(chemin) }
        return CanalRegistre(interne: interne, registre: self)
    }

    fileprivate func noterOuverture() { etat.withLock { $0.ouvertures += 1 } }
    fileprivate func noterFermeture() { etat.withLock { $0.fermetures += 1 } }
}

/// Un canal qui note au registre son ouverture et sa premiere fermeture.
final class CanalRegistre: CanalSonde {
    private let interne: any CanalSonde
    private let registre: RegistrePorts
    private let ouvert = Mutex(false)

    fileprivate init(interne: any CanalSonde, registre: RegistrePorts) {
        self.interne = interne
        self.registre = registre
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let flux = try interne.ouvrir()
        ouvert.withLock { $0 = true }
        registre.noterOuverture()
        return flux
    }

    func envoyer(_ ligne: String) { interne.envoyer(ligne) }

    func fermer() {
        let etait = ouvert.withLock { o in
            defer { o = false }
            return o
        }
        interne.fermer()
        if etait { registre.noterFermeture() }
    }
}

/// Un compteur d'appels, sans verrou a prendre dans les fermetures des tests.
final class CompteurAppels: Sendable {
    private let n = Mutex(0)
    func incrementer() { n.withLock { $0 += 1 } }
    var valeur: Int { n.withLock { $0 } }
}

/// Attend, 5 s au plus, que `condition` soit vraie (relue toutes les 5 ms) ; rend sa derniere valeur.
@MainActor
func attendreActivation(_ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
