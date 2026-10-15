import Foundation

/// Lignes machine de la sonde et envoi des commandes : la liaison serie dans l'app, un canal rejoue dans les tests.
/// Commun aux deux sondes (Thread et Zigbee) ; le decoupeur de lignes est celui de chaque protocole.
protocol CanalSonde: Sendable {
    /// Lignes machine (JSON, sans RS ni LF) ; le flux finit quand le port se ferme.
    func ouvrir() throws -> AsyncStream<Data>
    func envoyer(_ ligne: String)
    func fermer()
}

/// Ce que la liaison serie demande au decoupeur du protocole : des octets en entree, des lignes machine en sortie
/// (`DecoupeurLignes` de Thread, `DecoupeurLignesZigbee` de Zigbee, identiques a la constante de separation pres).
protocol DecoupeurDeLignes: Sendable {
    mutating func ajouter(_ d: Data) -> [Data]
}

/// Canal sur la liaison serie : le flux USB decoupe en lignes machine par le decoupeur du protocole (`decoupeur` en
/// fabrique un neuf a chaque ouverture).
struct CanalSerie: CanalSonde {
    let liaison: LiaisonSerie
    let decoupeur: @Sendable () -> any DecoupeurDeLignes

    func ouvrir() throws -> AsyncStream<Data> {
        let flux = try liaison.ouvrir()
        let (lignes, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let nouveau = decoupeur
        let lecture = Task {
            var decoupeur = nouveau()
            for await e in flux {
                guard case .donnees(let d) = e else { break }
                for l in decoupeur.ajouter(d) { suite.yield(l) }
            }
            suite.finish()
        }
        suite.onTermination = { _ in lecture.cancel() }
        return lignes
    }

    func envoyer(_ ligne: String) { liaison.envoyer(Data(ligne.utf8)) }
    func fermer() { liaison.fermer() }
}

/// Attentes d'une commande sans id (`bonjour`, `etat`, `voisins`...) : les reponses les servent dans l'ordre. Chaque
/// attente a son jeton : son echeance n'expire qu'elle, et plus rien une fois qu'elle est servie (par le reseau, une
/// reponse lente ne fait plus echouer la requete suivante). Commune aux deux sondes.
struct FileAttentes<Valeur: Sendable> {
    private var attentes: [(jeton: Int, suite: CheckedContinuation<Valeur?, Never>)] = []

    var estVide: Bool { attentes.isEmpty }

    mutating func ajouter(_ jeton: Int, _ suite: CheckedContinuation<Valeur?, Never>) {
        attentes.append((jeton, suite))
    }

    /// La premiere attente recoit `valeur` ; rien sans attente.
    mutating func servir(_ valeur: Valeur?) {
        guard !attentes.isEmpty else { return }
        attentes.removeFirst().suite.resume(returning: valeur)
    }

    /// Echeance de l'attente `jeton` : nil pour elle si elle attend encore. Rend son rang dans
    /// la file (0 : la premiere), nil si elle est deja servie.
    @discardableResult
    mutating func expirer(_ jeton: Int) -> Int? {
        guard let i = attentes.firstIndex(where: { $0.jeton == jeton }) else { return nil }
        attentes.remove(at: i).suite.resume(returning: nil)
        return i
    }

    /// Liaison fermee : toutes recoivent nil.
    mutating func liberer() {
        attentes.forEach { $0.suite.resume(returning: nil) }
        attentes = []
    }
}
