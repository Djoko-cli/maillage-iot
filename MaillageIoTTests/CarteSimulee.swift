import CryptoKit
import Foundation
import Synchronization
@testable import MaillageIoT

/// Connexion de datagrammes en memoire, cote app : ce que le transport envoie va a la carte
/// simulee, ce qu'elle renvoie arrive ici. Aucun trafic reseau (les tests de l'app tournent
/// dans l'app sandboxee, sans droit de serveur : pas de pair UDP local non plus).
final class ConnexionSimulee: ConnexionDatagrammes {
    /// Etat annonce au demarrage : prete, en attente (cause candidate), en echec, ou rien
    /// (jamais prete : nom qui ne se resout pas).
    enum Depart: Sendable {
        case prete
        case attente(ErreurReseau)
        case echec(ErreurReseau)
        case rien
    }

    let hote: String
    let port: UInt16
    private let carte: CarteSimulee?
    private let depart: Depart
    private let file = DispatchQueue(label: "fr.djoko.maillage.tests.connexion")

    private struct Etat {
        var changement: (@Sendable (EtatConnexion) -> Void)?
        var attente: (@Sendable (Result<Data, ErreurReseau>) -> Void)?
        var arrivees: [Data] = []
        var annulee = false
    }

    private let etat = Mutex(Etat())

    init(hote: String, port: UInt16, carte: CarteSimulee?, depart: Depart = .prete) {
        self.hote = hote
        self.port = port
        self.carte = carte
        self.depart = depart
    }

    var annulee: Bool { etat.withLock { $0.annulee } }

    func demarrer(_ changement: @escaping @Sendable (EtatConnexion) -> Void) {
        etat.withLock { $0.changement = changement }
        let d = depart
        file.async {
            switch d {
            case .prete: changement(.prete)
            case .attente(let e): changement(.attente(e))
            case .echec(let e): changement(.echec(e))
            case .rien: break
            }
        }
    }

    func recevoir(_ suite: @escaping @Sendable (Result<Data, ErreurReseau>) -> Void) {
        let d: Data? = etat.withLock { e in
            guard !e.annulee else { return nil }
            guard !e.arrivees.isEmpty else {
                e.attente = suite
                return nil
            }
            return e.arrivees.removeFirst()
        }
        if let d { file.async { suite(.success(d)) } }
    }

    func envoyer(_ datagramme: Data) {
        guard !annulee, let carte else { return }
        file.async { carte.recevoir(datagramme, de: self) }
    }

    func annuler() {
        etat.withLock { e in
            e.annulee = true
            e.attente = nil
        }
    }

    /// Datagramme de la carte vers l'app.
    func livrer(_ d: Data) {
        let suite: (@Sendable (Result<Data, ErreurReseau>) -> Void)? = etat.withLock { e in
            guard !e.annulee else { return nil }
            guard let s = e.attente else {
                e.arrivees.append(d)
                return nil
            }
            e.attente = nil
            return s
        }
        if let suite { file.async { suite(.success(d)) } }
    }

    /// La connexion echoue (chemin perdu apres l'ouverture...).
    func echouer(_ erreur: ErreurReseau) {
        let changement = etat.withLock { $0.changement }
        file.async { changement?(.echec(erreur)) }
    }
}

/// La sonde vue du reseau, en memoire (enveloppe H1 cote carte, comme `src/h1_proto.cpp` de
/// Halo) : un SALUT au bon kid et au MAC juste recoit un DEFI ; chaque message A au MAC juste
/// est note, et `repondre` donne les charges a renvoyer, scellees en C vers la derniere
/// connexion entendue. `mode` : carte muette, ou DEFI volontairement faux.
final class CarteSimulee: Sendable {
    enum Mode: Sendable, Equatable {
        case normal
        /// Ne repond jamais (sans cle, ou eteinte).
        case muette
        /// DEFI calcule pour le `na` de l'essai precedent (jamais celui de l'essai en cours).
        case defiNaPerime
        /// DEFI au bon kid, sid, nc et na, mais au MAC faux.
        case defiMacFaux
    }

    let cle: Data
    let mode: Mode
    private let repondre: @Sendable (String) -> [String]

    private struct Etat {
        var saluts = 0
        /// `na` de chaque SALUT recu : neuf a chaque essai.
        var nas: [Data] = []
        var naPrecedent: Data?
        var recues: [String] = []
        var ctrsRecus: [UInt32] = []
        var session: (sid: String, ks: SymmetricKey, ctr: UInt32)?
        var pair: ConnexionSimulee?
        /// Datagrammes de l'app a perdre en route, et perdus.
        var aPerdre = 0
        var perdus = 0
        /// Debranchee : plus rien n'arrive a la carte.
        var eteinte = false
    }

    private let etat = Mutex(Etat())

    init(cle: Data, mode: Mode = .normal, repondre: @escaping @Sendable (String) -> [String] = { _ in [] }) {
        self.cle = cle
        self.mode = mode
        self.repondre = repondre
    }

    var saluts: Int { etat.withLock { $0.saluts } }
    var nas: [Data] { etat.withLock { $0.nas } }
    /// Charges des messages A acceptes, dans l'ordre.
    var recues: [String] { etat.withLock { $0.recues } }
    var ctrsRecus: [UInt32] { etat.withLock { $0.ctrsRecus } }
    /// Datagrammes de l'app perdus en route (`perdre`).
    var perdus: Int { etat.withLock { $0.perdus } }

    /// Les `n` prochains datagrammes de l'app se perdent.
    func perdre(_ n: Int) {
        etat.withLock { $0.aPerdre = n }
    }

    /// Debranchee (ou redemarree) : plus rien n'arrive, sa session est oubliee.
    func eteindre() {
        etat.withLock { e in
            e.eteinte = true
            e.session = nil
        }
    }

    /// Charge scellee en C et envoyee a la derniere connexion entendue.
    func envoyer(_ charge: String) {
        let (datagramme, pair): (Data?, ConnexionSimulee?) = etat.withLock { e in
            guard var s = e.session else { return (nil, nil) }
            s.ctr += 1
            e.session = s
            let c = Data(charge.utf8)
            let m = H1.mac(s.ks, Data("C|\(s.sid)|\(s.ctr)|".utf8) + c)
            return (Data("H1 \(s.sid) \(s.ctr) \(m) ".utf8) + c, e.pair)
        }
        guard let datagramme, let pair else { return }
        pair.livrer(datagramme)
    }

    func recevoir(_ d: Data, de c: ConnexionSimulee) {
        let perdu = etat.withLock { e -> Bool in
            if e.eteinte { return true }
            guard e.aPerdre > 0 else { return false }
            e.aPerdre -= 1
            e.perdus += 1
            return true
        }
        guard !perdu else { return }
        let champs = d.split(separator: 0x20, maxSplits: 4, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if champs.count == 5, champs[1] == "SALUT" {
            salut(kid: champs[2], naHexa: champs[3], macSalut: champs[4], de: c)
            return
        }
        // Message A : MAC verifie avec Ks, charge et ctr notes.
        let charge: String? = etat.withLock { e in
            guard let s = e.session, champs.count == 5, champs[1] == s.sid, let ctr = UInt32(champs[2]) else { return nil }
            let attendu = H1.mac(s.ks, Data("A|\(s.sid)|\(champs[2])|".utf8) + Data(champs[4].utf8))
            guard attendu == champs[3] else { return nil }
            e.recues.append(champs[4])
            e.ctrsRecus.append(ctr)
            e.pair = c
            return champs[4]
        }
        guard let charge else { return }
        for r in repondre(charge) { envoyer(r) }
    }

    private func salut(kid: String, naHexa: String, macSalut: String, de c: ConnexionSimulee) {
        let na = H1.octets(hexa: naHexa)
        etat.withLock { e in
            e.saluts += 1
            if let na { e.nas.append(na) }
        }
        guard mode != .muette, let na, kid == H1.kid(cle: cle) else { return }
        // La carte ne repond qu'a un SALUT au MAC juste.
        guard H1.mac(SymmetricKey(data: cle), Data("H1|SALUT|\(kid)|\(naHexa)".utf8)) == macSalut else { return }
        let sid = "5A5A0001", nc = H1.hexa(H1.aleatoire(16))
        let naPrecedent = etat.withLock { e -> Data? in
            let p = e.naPrecedent
            e.naPrecedent = na
            return p
        }
        if mode == .defiNaPerime, naPrecedent == nil { return }  // 1er essai : rien a perimer encore
        let naDuDefi = mode == .defiNaPerime ? (naPrecedent ?? na) : na
        var mac = H1.mac(SymmetricKey(data: cle), Data("H1|DEFI|\(kid)|\(H1.hexa(naDuDefi))|\(nc)|\(sid)".utf8))
        if mode == .defiMacFaux { mac = (mac.first == "A" ? "B" : "A") + mac.dropFirst() }
        etat.withLock { e in
            e.session = (sid, H1.cleSession(cle: cle, na: na, nc: nc, sid: sid), 0)
            e.pair = c
        }
        c.livrer(Data("H1 DEFI \(sid) \(nc) \(mac)".utf8))
    }
}

/// Evenements d'un flux de liaison, notes au fil de l'eau : `donnees <texte>`, `ferme <raison>`,
/// puis `fin` a la fin du flux.
final class RecueilLiaison: Sendable {
    private let evenements = Mutex<[String]>([])

    init(_ flux: AsyncStream<EvenementLiaison>) {
        Task { [self] in
            for await e in flux {
                switch e {
                case .donnees(let d): noter("donnees " + String(decoding: d, as: UTF8.self))
                case .ferme(let r): noter("ferme " + r)
                }
            }
            noter("fin")
        }
    }

    private func noter(_ s: String) {
        evenements.withLock { $0.append(s) }
    }

    var liste: [String] { evenements.withLock { $0 } }
}

/// Attend une condition, au plus `delai` ; rend la condition.
nonisolated(nonsending) func attendreQue(_ delai: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Connexions simulees creees par une fabrique, dans l'ordre.
final class ConnexionsSimulees: Sendable {
    private let liste = Mutex<[ConnexionSimulee]>([])

    func ajouter(_ c: ConnexionSimulee) {
        liste.withLock { $0.append(c) }
    }

    var toutes: [ConnexionSimulee] { liste.withLock { $0 } }
}
