import Foundation
import Synchronization

/// Canal de la sonde par le reseau Thread (contrat 1.0.2), sur le transport UDP repris du
/// pont Halo : un `CanalSonde` de plus, `SondeUSB` et la tournee ne changent pas.
/// - Chaque commande part en `<rid> <commande>` (rid decimal, croissant) ; sans aucune
///   reponse, elle repart avec le meme rid a 2 s puis a 4 s : la carte ne relance rien, elle
///   renvoie la reponse gardee (ou se tait, `diag` ou `resoudre` encore en vol). Un `diag` repart
///   ensuite 1 s apres la fin de son vol, puis tous les 3 s, jusqu'a 1 s avant l'echeance de
///   `SondeUSB` : sa reponse perdue apres le vol se redemande ; un `resoudre` de meme, son vol
///   etant de 15 s.
/// - Au plus 18 nouvelles commandes par seconde glissante (la carte en accepte 20 par session,
///   au-dela elle se tait) : les suivantes attendent, dans l'ordre ; les renvois ne comptent
///   pas et partent a l'heure.
/// - Chaque reponse `<rid> <ligne JSON>` passe a `SondeUSB` sans le rid, comme une ligne du
///   canal serie ; un doublon (meme rid, meme ligne) est ecarte.
/// - Apres 10 s sans aucune ligne, un `etat` de veille, dont la reponse reste ici : sans
///   reponse (sonde debranchee, redemarree, hors de portee), le canal se ferme, et l'app se
///   reconnecte (nouvelle poignee de main). La session de l'app ne reste ainsi jamais muette
///   30 s, au-dela desquelles la carte donne sa place a un autre client.
/// - La cle ne passe jamais par le reseau : les commandes `cle ...` ne partent pas.
/// - Fermee, il garde la cause (`raisonFermeture`), montree comme dans Halo :
///   « Connexion reseau perdue : <cause> ».
final class CanalReseau: CanalSonde, CauseFermeture {
    struct Reglages: Sendable {
        /// Renvois d'une commande sans reponse, comptes depuis son premier envoi.
        var renvois: [Duration] = [.seconds(2), .seconds(4)]
        /// `diag` : muet cote carte tant qu'il est en vol (son delai, 6 a 8 s), il tombe pendant
        /// ces renvois. Ensuite, un renvoi `apresVolDiag` apres la fin du vol, puis tous les
        /// `pasDiag`, le dernier au plus tard `avanceDiag` avant l'echeance de `SondeUSB` (delai
        /// du diag + `margeDiag`) : une reponse perdue apres le vol se redemande, et la carte rend
        /// celle qu'elle a gardee. Les renvois fixes (2 et 4 s) partent encore pendant le vol ;
        /// ceux d'apres le vol n'y tombent plus.
        var apresVolDiag: Duration = .seconds(1)
        var pasDiag: Duration = .seconds(3)
        var margeDiag: Duration = SondeUSB.margeDiag
        var avanceDiag: Duration = .seconds(1)
        /// Vol d'un `resoudre` (firmware 1.1.0) : 15 s au plus sur la carte, muette pendant ce temps.
        var volResolution: Duration = SondeUSB.delaiResolution
        /// Silence (aucune ligne recue) avant une veille : 10 s, comme le ping de Halo. La carte
        /// donne a un nouveau client la place d'une session muette depuis 30 s : la veille garde
        /// celle de l'app.
        var veille: Duration = .seconds(10)
        /// Reponse a la veille, ses renvois compris : au plus.
        var attenteVeille: Duration = .seconds(6)
        /// Doublons : lignes des derniers rid gardees.
        var memoireDoublons = 256
        /// Cadence de la carte : 20 commandes par seconde glissante et par session, au-dela rien
        /// (le renvoi de 2 s rattrape). L'app envoie au plus `cadence` nouveaux rid par
        /// `fenetreCadence` glissante, dans l'ordre ; les renvois ne comptent pas et partent a
        /// l'heure.
        var cadence = 18
        var fenetreCadence: Duration = .seconds(1)

        /// Pas de la garde (veille, et silence qui suit) : 1 s au plus, plus court pour des
        /// reglages de test rapides.
        var pasGarde: Duration { min(.seconds(1), veille / 4, attenteVeille / 4) }

        /// Renvois d'une commande (sans fin de ligne), comptes depuis son premier envoi :
        /// `renvois`, puis pour un `diag` ou un `resoudre` ceux d'apres son vol, au-dela du dernier de
        /// `renvois` (2, 4, 7 et 10 s pour un diag de 6000 ms ; 2, 4, 9 et 12 s pour 8000 ms ; 2, 4, 16
        /// et 19 s pour un resoudre).
        func renvois(pour commande: String) -> [Duration] {
            guard let vol = volEnCours(commande), let fixe = renvois.last else { return renvois }
            var r = renvois
            let dernier = vol + margeDiag - avanceDiag
            var t = vol + apresVolDiag
            while t <= dernier {
                if t > fixe { r.append(t) }
                t += pasDiag
            }
            return r
        }

        /// Duree pendant laquelle la carte se tait sur la commande : le delai d'un `diag`, ou le vol d'un
        /// `resoudre <adresse> <id>` ; nil pour une autre commande.
        func volEnCours(_ commande: String) -> Duration? {
            if let ms = Self.delaiDiag(commande) { return .milliseconds(ms) }
            let mots = commande.split(separator: " ")
            return mots.count == 3 && mots[0] == "resoudre" ? volResolution : nil
        }

        /// Delai d'un `diag <cible> <tlv> <id> <ms>`, en ms ; nil pour une autre commande, ou
        /// sans delai lisible.
        static func delaiDiag(_ commande: String) -> Int? {
            let mots = commande.split(separator: " ")
            guard mots.count == 5, mots[0] == "diag", let ms = Int(mots[4]), ms >= 0 else { return nil }
            return ms
        }
    }

    private let transport: TransportUDP
    private let charges: AsyncStream<EvenementLiaison>
    private let reglages: Reglages

    private struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var ouvert = false
        var ferme = false
        /// Commandes sans aucune reponse (renvois dus), et leur tache de renvoi.
        var attendus: [Int: Task<Void, Never>] = [:]
        /// Lignes transmises, par rid (doublons) ; rid dans l'ordre, pour borner.
        var vues: [Int: Set<Data>] = [:]
        var ordre: [Int] = []
        /// Veille en cours : sa reponse reste ici.
        var veille: (rid: Int, depuis: ContinuousClock.Instant)?
        var dernierRecu = ContinuousClock.now
        /// Cause de la fermeture : celle du transport, ou le silence de la sonde.
        var raison: String?
        /// Garde (veille) ; la lecture des charges, elle, finit avec le transport.
        var garde: Task<Void, Never>?
        /// Nouvelles commandes qui attendent la cadence, dans l'ordre.
        var file: [(rid: Int, charge: Data, renvois: [Duration])] = []
        /// Premiers envois (nouveaux rid, veilles comprises) de la derniere fenetre de cadence,
        /// du plus ancien au plus recent.
        var envois: [ContinuousClock.Instant] = []
        /// Tache qui vide `file` au rythme de la cadence ; nil quand la file est vide.
        var videur: Task<Void, Never>?
    }

    /// Un pas du videur de la file.
    private enum PasCadence {
        case envoyer(rid: Int, charge: Data, renvois: [Duration])
        case attendre(Duration)
        case fin
    }

    private let etat = Mutex(Etat())

    /// Cause d'une fermeture pour silence (veille sans reponse).
    static var raisonSilence: String {
        ErreurReseau.cheminPerdu(String(localized: "la sonde ne répond plus (débranchée, redémarrée ou hors de portée ?)"))
            .localizedDescription
    }

    var raisonFermeture: String? { etat.withLock { $0.raison } }

    /// rid de toutes les commandes de l'app, croissants d'une connexion a l'autre.
    private static let compteur = Mutex(0)

    static func prochainRid() -> Int {
        compteur.withLock { n in
            n = n >= 999_999_999 ? 1 : n + 1
            return n
        }
    }

    /// Ouvre une session vers `<hote>.local:5480` (resolution, poignee de main H1) : le canal
    /// pret, ou l'erreur (`ErreurReseau`).
    static func connecter(hote: String, cle: Data, reglages: Reglages = Reglages(),
                          reglagesTransport: TransportUDP.Reglages = TransportUDP.Reglages(),
                          fabrique: @escaping @Sendable (String, UInt16) -> any ConnexionDatagrammes
                              = { ConnexionNW(hote: $0, port: $1) }) async throws -> CanalReseau {
        let t = TransportUDP(hote: "\(hote).local", cle: cle, reglages: reglagesTransport, fabrique: fabrique)
        let charges = try await t.ouvrir()
        return CanalReseau(transport: t, charges: charges, reglages: reglages)
    }

    init(transport: TransportUDP, charges: AsyncStream<EvenementLiaison>, reglages: Reglages = Reglages()) {
        self.transport = transport
        self.charges = charges
        self.reglages = reglages
    }

    /// Les lignes JSON de la sonde ; le flux finit quand la session se ferme. Une seule fois ;
    /// fermee avant, le canal rend un flux deja fini.
    func ouvrir() throws -> AsyncStream<Data> {
        let (lignes, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let (deja, ferme) = etat.withLock { e -> (Bool, Bool) in
            guard !e.ouvert else { return (true, e.ferme) }
            e.ouvert = true
            guard !e.ferme else { return (false, true) }
            e.suite = suite
            e.dernierRecu = .now
            return (false, false)
        }
        if deja { throw ErreurReseau.autre(String(localized: "canal réseau déjà ouvert")) }
        if ferme {
            suite.finish()
            return lignes
        }
        let charges = charges
        Task { [weak self] in
            for await e in charges {
                switch e {
                case .donnees(let d): self?.recu(d)
                case .ferme(let r): self?.noterRaison(r)
                }
            }
            // Session fermee (par l'app, la veille, ou perdue) : fin des lignes.
            self?.finir()
        }
        let pas = reglages.pasGarde
        let garde = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pas)
                guard !Task.isCancelled, let self, self.surveiller() else { return }
            }
        }
        etat.withLock { $0.garde = garde }
        suite.onTermination = { [weak self] _ in self?.fermer() }
        return lignes
    }

    /// Nouvelle commande : elle prend son rid tout de suite et part des que la cadence le permet,
    /// sans rien attendre ici (seul l'envoi suivant attend).
    func envoyer(_ ligne: String) {
        let commande = ligne.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commande.isEmpty, !Self.estCommandeCle(commande) else { return }
        let rid = Self.prochainRid()
        let charge = Data("\(rid) \(commande)".utf8), renvois = reglages.renvois(pour: commande)
        etat.withLock { e in
            guard !e.ferme else { return }
            e.file.append((rid, charge, renvois))
            if e.videur == nil { e.videur = Task { [weak self] in await self?.vider() } }
        }
    }

    /// Ferme la session ; la fin du flux des lignes suit. Les commandes qui attendaient la
    /// cadence ne partent pas.
    func fermer() {
        let taches = etat.withLock { e -> [Task<Void, Never>] in
            guard !e.ferme else { return [] }
            e.ferme = true
            // La lecture, elle, finit avec le transport (fin des lignes).
            let t = Array(e.attendus.values) + [e.garde, e.videur].compactMap { $0 }
            e.attendus.removeAll()
            e.file.removeAll()
            return t
        }
        taches.forEach { $0.cancel() }
        transport.fermer()
    }

    /// `cle`, `cle nouvelle ...`, `cle efface` : USB seulement.
    static func estCommandeCle(_ commande: String) -> Bool {
        commande.split(separator: " ").first == "cle"
    }

    /// `<rid> <ligne>` : rid decimal positif, ligne non vide ; sinon nil.
    static func lire(_ charge: Data) -> (rid: Int, ligne: Data)? {
        guard let espace = charge.firstIndex(of: 0x20) else { return nil }
        let chiffres = charge[charge.startIndex..<espace]
        guard (1...10).contains(chiffres.count), chiffres.allSatisfy({ (0x30...0x39).contains($0) }),
              let rid = Int(String(decoding: chiffres, as: UTF8.self)), rid > 0 else { return nil }
        let ligne = charge[charge.index(after: espace)...]
        guard !ligne.isEmpty else { return nil }
        return (rid, Data(ligne))
    }

    // MARK: - Envoi et renvois

    /// Vide la file des nouvelles commandes, dans l'ordre : au plus `cadence` premiers envois par
    /// `fenetreCadence` glissante ; au-dela, attend que le plus ancien sorte de la fenetre. S'arrete
    /// file vide (sous le verrou d'`envoyer` : une commande ajoutee relance un videur).
    private func vider() async {
        let cadence = reglages.cadence, fenetre = reglages.fenetreCadence
        while !Task.isCancelled {
            let pas = etat.withLock { e -> PasCadence in
                guard !e.ferme, !e.file.isEmpty else {
                    e.videur = nil
                    return .fin
                }
                let maintenant = ContinuousClock.now
                e.envois.removeAll { maintenant - $0 >= fenetre }
                if e.envois.count >= cadence, let plusAncien = e.envois.first {
                    return .attendre(fenetre - (maintenant - plusAncien))
                }
                e.envois.append(maintenant)
                let c = e.file.removeFirst()
                return .envoyer(rid: c.rid, charge: c.charge, renvois: c.renvois)
            }
            switch pas {
            case .envoyer(let rid, let charge, let renvois):
                emettre(rid, charge, renvois: renvois)
            case .attendre(let duree):
                try? await Task.sleep(for: duree)
            case .fin:
                return
            }
        }
    }

    /// Premier envoi, puis `renvois` (comptes depuis lui) tant qu'aucune reponse n'est arrivee.
    private func emettre(_ rid: Int, _ charge: Data, renvois: [Duration]) {
        let tache = Task { [weak self] in
            var ecoule: Duration = .zero
            for r in renvois {
                try? await Task.sleep(for: r - ecoule)
                ecoule = r
                guard !Task.isCancelled, let self, self.attend(rid) else { return }
                try? self.transport.envoyer(charge)
            }
            self?.oublier(rid)
        }
        let ouvert = etat.withLock { e -> Bool in
            guard !e.ferme else { return false }
            e.attendus[rid] = tache
            return true
        }
        guard ouvert else {
            tache.cancel()
            return
        }
        try? transport.envoyer(charge)
    }

    private func attend(_ rid: Int) -> Bool {
        etat.withLock { $0.attendus[rid] != nil }
    }

    private func oublier(_ rid: Int) {
        _ = etat.withLock { $0.attendus.removeValue(forKey: rid) }
    }

    // MARK: - Reception

    /// Une charge de la carte : la ligne passe, sauf reponse a une veille ou doublon.
    private func recu(_ charge: Data) {
        guard let (rid, ligne) = Self.lire(charge) else { return }
        let memoire = reglages.memoireDoublons
        let (suite, renvoi): (AsyncStream<Data>.Continuation?, Task<Void, Never>?) = etat.withLock { e in
            e.dernierRecu = .now
            let renvoi = e.attendus.removeValue(forKey: rid)
            if e.vues[rid] == nil {
                e.ordre.append(rid)
                if e.ordre.count > memoire { e.vues[e.ordre.removeFirst()] = nil }
            }
            guard e.vues[rid, default: []].insert(ligne).inserted else { return (nil, renvoi) }
            if e.veille?.rid == rid {
                e.veille = nil
                return (nil, renvoi)
            }
            return (e.suite, renvoi)
        }
        renvoi?.cancel()
        suite?.yield(ligne)
    }

    /// La premiere cause connue reste (le silence, pose avant la fermeture qu'il provoque).
    private func noterRaison(_ r: String) {
        etat.withLock { e in
            if e.raison == nil { e.raison = r }
        }
    }

    private func finir() {
        let suite = etat.withLock { e -> AsyncStream<Data>.Continuation? in
            e.ferme = true
            let s = e.suite
            e.suite = nil
            e.attendus.values.forEach { $0.cancel() }
            e.attendus.removeAll()
            e.garde?.cancel()
            e.videur?.cancel()
            e.file.removeAll()
            return s
        }
        suite?.finish()
    }

    // MARK: - Veille

    private enum Garde {
        case rien
        case veiller(Int)
        /// Veille levee sans reponse : ses renvois s'arretent.
        case lever(Task<Void, Never>?)
        case muette
        case arret
    }

    /// Un pas de la garde (interne pour les tests, qui peuvent le jouer a un instant donne) :
    /// veille apres un silence ; sans reponse a la veille, fermeture. Faux : la garde s'arrete
    /// (canal ferme).
    func surveiller(maintenant: ContinuousClock.Instant = .now) -> Bool {
        let action = etat.withLock { e -> Garde in
            guard !e.ferme else { return .arret }
            if let v = e.veille {
                // Une ligne recue depuis la veille : la sonde est vivante, meme si la veille s'est
                // perdue ; ses renvois s'arretent (une reponse tardive passera comme un `etat`).
                guard e.dernierRecu <= v.depuis else {
                    e.veille = nil
                    return .lever(e.attendus.removeValue(forKey: v.rid))
                }
                return maintenant - v.depuis >= reglages.attenteVeille ? .muette : .rien
            }
            guard maintenant - e.dernierRecu >= reglages.veille else { return .rien }
            let rid = Self.prochainRid()
            e.veille = (rid, maintenant)
            // Un rid neuf : il compte dans la cadence (a l'heure reelle), sans attendre la file.
            let reel = ContinuousClock.now
            e.envois.removeAll { reel - $0 >= reglages.fenetreCadence }
            e.envois.append(reel)
            return .veiller(rid)
        }
        switch action {
        case .rien:
            return true
        case .veiller(let rid):
            emettre(rid, Data("\(rid) etat".utf8), renvois: reglages.renvois)
            return true
        case .lever(let renvoi):
            renvoi?.cancel()
            return true
        case .muette:
            noterRaison(Self.raisonSilence)
            fermer()
            return false
        case .arret:
            return false
        }
    }
}
