import Foundation
import Network
import Synchronization

/// Etat d'une connexion de datagrammes utile au transport, les erreurs deja classees.
enum EtatConnexion: Sendable, Equatable {
    case prete
    /// En attente : cause candidate, la connexion peut encore aboutir.
    case attente(ErreurReseau)
    case echec(ErreurReseau)
}

/// Canal qui sait pourquoi il s'est ferme (le canal reseau) : la cause est montree a la perte
/// de la liaison. nil tant que le canal est ouvert.
protocol CauseFermeture: AnyObject, Sendable {
    var raisonFermeture: String? { get }
}

/// Datagrammes UDP vers la sonde : Network.framework dans l'app (`ConnexionNW`), une carte
/// simulee en memoire dans les tests (aucun trafic reseau).
protocol ConnexionDatagrammes: AnyObject, Sendable {
    /// Demarre la connexion ; `changement` a chaque etat utile.
    func demarrer(_ changement: @escaping @Sendable (EtatConnexion) -> Void)
    /// Prochain datagramme, ou l'erreur de reception ; a rappeler pour le suivant.
    func recevoir(_ suite: @escaping @Sendable (Result<Data, ErreurReseau>) -> Void)
    func envoyer(_ datagramme: Data)
    func annuler()
}

/// UDP sur IPv6, `NWConnection` « connectee » vers `<hote>:<port>` : le nom est resolu a
/// chaque ouverture (l'adresse OMR de la sonde peut changer), comme dans le pont Halo.
final class ConnexionNW: ConnexionDatagrammes {
    private let connexion: NWConnection
    private let hote: String
    private let file = DispatchQueue(label: "fr.djoko.maillage.sonde.udp", qos: .userInitiated)

    init(hote: String, port: UInt16) {
        let parametres = NWParameters.udp
        if let ip = parametres.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v6 }
        self.hote = hote
        connexion = NWConnection(host: NWEndpoint.Host(hote), port: NWEndpoint.Port(rawValue: port) ?? 5480,
                                 using: parametres)
    }

    func demarrer(_ changement: @escaping @Sendable (EtatConnexion) -> Void) {
        let c = connexion, hote = hote
        c.stateUpdateHandler = { s in
            switch s {
            case .ready: changement(.prete)
            case .waiting(let e): changement(.attente(ErreurReseau.depuis(e, chemin: c.currentPath, hote: hote)))
            case .failed(let e): changement(.echec(ErreurReseau.depuis(e, chemin: c.currentPath, hote: hote)))
            default: break
            }
        }
        c.start(queue: file)
    }

    func recevoir(_ suite: @escaping @Sendable (Result<Data, ErreurReseau>) -> Void) {
        let c = connexion, hote = hote
        c.receiveMessage { donnees, _, _, erreur in
            if let erreur {
                suite(.failure(ErreurReseau.depuis(erreur, chemin: c.currentPath, hote: hote)))
            } else {
                suite(.success(donnees ?? Data()))
            }
        }
    }

    func envoyer(_ datagramme: Data) {
        connexion.send(content: datagramme, completion: .contentProcessed { _ in })
    }

    func annuler() {
        connexion.cancel()
    }
}

/// Transport reseau de la sonde, repris du pont Halo (benq,
/// `HaloProtocole/Transport/TransportUDP.swift`) : UDP sur IPv6 vers `<hote>.local:5480`,
/// enveloppe H1. Chaque datagramme valide recu donne sa charge ; chaque charge envoyee part
/// dans son propre datagramme scelle. Seul ecart : les charges ne sont pas mises en lignes
/// RS + JSON + LF (le canal reseau lit lui-meme `<rid> <ligne JSON>`).
final class TransportUDP: Sendable {
    struct Reglages: Sendable {
        var port: UInt16 = 5480
        /// Connexion prete (resolution du nom, route) : au plus.
        var attentePret: Duration = .seconds(5)
        /// DEFI juste apres chaque SALUT : au plus.
        var attenteDefi: Duration = .seconds(2)
        var essais = 3
    }

    let hote: String
    private let cle: Data
    private let reglages: Reglages
    private let fabrique: @Sendable (String, UInt16) -> any ConnexionDatagrammes

    private struct Etat {
        var connexion: (any ConnexionDatagrammes)?
        var pret = false
        var echoue = false
        var erreur: ErreurReseau?
        /// Datagrammes arrives pendant la poignee de main (16 au plus).
        var recus: [Data] = []
        var session: SessionH1?
        var suite: AsyncStream<EvenementLiaison>.Continuation?
        var fini = false
    }

    private let etat = Mutex(Etat())

    init(hote: String, cle: Data, reglages: Reglages = Reglages(),
         fabrique: @escaping @Sendable (String, UInt16) -> any ConnexionDatagrammes = { ConnexionNW(hote: $0, port: $1) }) {
        self.hote = hote
        self.cle = cle
        self.reglages = reglages
        self.fabrique = fabrique
    }

    /// Datagrammes ecartes (forme, sid, MAC, rejeu) depuis l'ouverture.
    var ecartes: Int { etat.withLock { $0.session?.ecartes ?? 0 } }

    /// Resolution, poignee de main ; le flux des charges, qui finit apres `.ferme`.
    func ouvrir() async throws -> AsyncStream<EvenementLiaison> {
        let c = fabrique(hote, reglages.port)
        etat.withLock { $0.connexion = c }
        c.demarrer { [weak self] e in self?.changement(e) }
        do {
            try await attendrePret()
            recevoir(c)
            let session = try await poigneeDeMain(c)
            let (flux, suite) = AsyncStream.makeStream(of: EvenementLiaison.self, bufferingPolicy: .unbounded)
            try adopter(session, suite)
            suite.onTermination = { [weak self] _ in self?.fermer() }
            return flux
        } catch {
            etat.withLock { e in
                e.fini = true
                e.connexion = nil
            }
            c.annuler()
            throw error
        }
    }

    /// Pose la session et le flux, sauf si un echec ou une fermeture est arrive entre le
    /// dernier coup d'oeil de la poignee de main et ce verrou : le flux ne recevrait alors
    /// jamais `.ferme`. L'erreur gardee est levee ; `ouvrir` annule la connexion.
    func adopter(_ session: SessionH1, _ suite: AsyncStream<EvenementLiaison>.Continuation) throws {
        let refus: ErreurReseau? = etat.withLock { e in
            guard !e.fini, !e.echoue else {
                return e.erreur ?? .autre(String(localized: "session réseau fermée par l'app"))
            }
            e.session = session
            e.suite = suite
            e.recus.removeAll()
            return nil
        }
        if let refus { throw refus }
    }

    /// Raison de fermeture d'une session perdue apres son ouverture :
    /// "Connexion reseau perdue : <cause>".
    static func raisonPerte(_ cause: ErreurReseau) -> String {
        ErreurReseau.cheminPerdu(cause.localizedDescription).localizedDescription
    }

    /// Sans route avant l'ouverture, la connexion en attente ne repart pas quand la route
    /// revient (banc du 25/09 de Halo) : abandon tout de suite, la reconnexion reessaie a son
    /// rythme. Les autres attentes vont jusqu'a `attentePret` (une reautorisation du reseau
    /// local relance la connexion en attente).
    static func abandonAvantOuverture(_ e: ErreurReseau) -> Bool { e == .pasDeRoute }

    // MARK: - Connexion

    private func changement(_ e: EtatConnexion) {
        switch e {
        case .prete:
            etat.withLock { $0.pret = true }
        case .attente(let err):
            // Avant l'ouverture : cause candidate (sauf sans route : abandonAvantOuverture).
            let ouverte = etat.withLock { et -> Bool in
                et.erreur = err
                return et.suite != nil
            }
            if ouverte {
                terminer(Self.raisonPerte(err))
            } else if Self.abandonAvantOuverture(err) {
                echec(err)
            }
        case .echec(let err):
            echec(err)
        }
    }

    private func attendrePret() async throws {
        let limite = ContinuousClock.now + reglages.attentePret
        while ContinuousClock.now < limite {
            let (pret, echoue, erreur) = etat.withLock { ($0.pret, $0.echoue, $0.erreur) }
            if pret { return }
            if echoue, let erreur { throw erreur }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw etat.withLock { $0.erreur } ?? ErreurReseau.nomIntrouvable(hote)
    }

    private func recevoir(_ c: any ConnexionDatagrammes) {
        c.recevoir { [weak self] r in
            guard let self else { return }
            switch r {
            case .failure(let err):
                self.echec(err)
                return
            case .success(let d):
                if !d.isEmpty { self.arrivee(d) }
            }
            if !self.etat.withLock({ $0.fini }) { self.recevoir(c) }
        }
    }

    private func arrivee(_ d: Data) {
        let charge: Data? = etat.withLock { e in
            guard var s = e.session else {
                if e.recus.count < 16 { e.recus.append(d) }
                return nil
            }
            let c = s.ouvrir(d)
            e.session = s
            return c
        }
        guard let charge else { return }
        _ = etat.withLock { $0.suite?.yield(.donnees(charge)) }
    }

    /// Interne (et non privee) : les tests y simulent un echec, sans reseau.
    func echec(_ err: ErreurReseau) {
        let ouverte = etat.withLock { e -> Bool in
            e.erreur = err
            e.echoue = true
            return e.suite != nil
        }
        if ouverte { terminer(Self.raisonPerte(err)) }
    }

    // MARK: - Poignee de main

    private func poigneeDeMain(_ c: any ConnexionDatagrammes) async throws -> SessionH1 {
        for _ in 0..<reglages.essais {
            let na = H1.aleatoire(16)
            c.envoyer(H1.salut(cle: cle, na: na))
            let limite = ContinuousClock.now + reglages.attenteDefi
            while ContinuousClock.now < limite {
                let (recu, echoue, erreur) = etat.withLock { e -> (Data?, Bool, ErreurReseau?) in
                    (e.recus.isEmpty ? nil : e.recus.removeFirst(), e.echoue, e.erreur)
                }
                if echoue, let erreur { throw erreur }
                if let recu {
                    if let d = H1.verifierDefi(recu, cle: cle, na: na) {
                        return SessionH1(sid: d.sid, ks: H1.cleSession(cle: cle, na: na, nc: d.nc, sid: d.sid))
                    }
                    continue  // DEFI d'un essai precedent, ou autre datagramme
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        throw try await echecPoignee(c)
    }

    /// Aucun DEFI apres tous les essais : sonde muette (eteinte, sans cle) ou autre cle. Un
    /// ICMPv6 "port injoignable" peut n'arriver qu'apres l'annulation de la connexion (constat
    /// de Halo sur `::1`) : une derniere attente breve avant de conclure `aucunDefi`.
    private func echecPoignee(_ c: any ConnexionDatagrammes) async throws -> ErreurReseau {
        c.annuler()
        etat.withLock { $0.fini = true }
        let limite = ContinuousClock.now + .milliseconds(150)
        while ContinuousClock.now < limite {
            let (echoue, erreur) = etat.withLock { ($0.echoue, $0.erreur) }
            if echoue { return erreur == .portInjoignable ? .portInjoignable : .aucunDefi }
            try await Task.sleep(for: .milliseconds(10))
        }
        return .aucunDefi
    }

    // MARK: - Envoi et fermeture

    /// Une charge, un datagramme scelle ; leve une erreur si la session est fermee.
    func envoyer(_ charge: Data) throws {
        let (c, datagramme): ((any ConnexionDatagrammes)?, Data?) = etat.withLock { e in
            guard !e.fini, let c = e.connexion, var s = e.session else { return (nil, nil) }
            let d = s.sceller(charge)
            e.session = s
            return (c, d)
        }
        guard let c, let datagramme else {
            throw ErreurReseau.cheminPerdu(String(localized: "session réseau fermée"))
        }
        c.envoyer(datagramme)
    }

    func fermer() {
        terminer(String(localized: "session réseau fermée par l'app"))
    }

    private func terminer(_ raison: String) {
        let (c, suite) = etat.withLock { e -> ((any ConnexionDatagrammes)?, AsyncStream<EvenementLiaison>.Continuation?) in
            guard !e.fini else { return (nil, nil) }
            e.fini = true
            let r = (e.connexion, e.suite)
            e.connexion = nil
            e.suite = nil
            return r
        }
        c?.annuler()
        suite?.yield(.ferme(raison))
        suite?.finish()
    }
}

extension TransportUDP: CustomReflectable {
    /// Sans la cle : un dump ne la montre jamais.
    var customMirror: Mirror { Mirror(self, children: ["hote": hote]) }
}
