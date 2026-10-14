import Foundation
import Testing

/// Fausse maison : un releve donne a la main, les lectures et identifications notees.
@MainActor
final class FausseMaison: SourceMaison {
    var acces: EtatPasseur.Acces = .autorise
    var surChangement: (@MainActor () -> Void)?
    /// Ce que rend `releve(batteries:)` ; nil : Maison n'a pas encore repondu.
    var noms: NomsMaison?
    /// Chaque appel de `releve`, avec son `batteries`.
    private(set) var lectures: [Bool] = []
    var issues: [UUID: IssueIdentifier] = [:]
    private(set) var identifies: [UUID] = []

    func releve(batteries: Bool) async -> NomsMaison? {
        lectures.append(batteries)
        return noms
    }

    func identifier(_ accessoire: UUID) async -> IssueIdentifier {
        identifies.append(accessoire)
        return issues[accessoire] ?? .inconnu
    }

    /// Un changement dans Maison.
    func changer() {
        surChangement?()
    }
}

/// Faux lien vers une app : les messages envoyes, notes.
@MainActor
final class FauxLien: LienApp {
    var surMessage: (@MainActor (MessagePasseur) -> Void)?
    var surFin: (@MainActor () -> Void)?
    let cible: EnvoiPasseur.Cible
    private(set) var envoyes: [MessagePasseur] = []
    private(set) var ferme = false

    init(_ cible: EnvoiPasseur.Cible) {
        self.cible = cible
    }

    func envoyer(_ m: MessagePasseur) {
        envoyes.append(m)
    }

    func fermer() {
        ferme = true
        let f = surFin
        surFin = nil
        f?()
    }

    /// L'app s'en va : la connexion se ferme de son cote.
    func partir() {
        let f = surFin
        surFin = nil
        f?()
    }

    var releves: [NomsMaison] {
        envoyes.compactMap { m in
            guard case .releve(let json) = m else { return nil }
            return try? NomsMaison.lire(json)
        }
    }

    var etats: [EtatPasseur] {
        envoyes.compactMap { m in
            guard case .etat(let e) = m else { return nil }
            return e
        }
    }

    var reponses: [ReponseIdentifier] {
        envoyes.compactMap { m in
            guard case .identifie(let r) = m else { return nil }
            return r
        }
    }
}

/// Fausse ouverture a la session : le statut se regle a la main ; `erreur` fait echouer `regler`.
@MainActor
final class FausseOuverture: OuvertureSessionDemon {
    var statut: EtatPasseur.Ouverture = .inactive
    var erreur: String?
    private(set) var reglages: [Bool] = []

    func regler(actif: Bool) -> String? {
        reglages.append(actif)
        if let erreur { return erreur }
        statut = actif ? .active : .inactive
        return nil
    }
}

/// Horloge avancee a la main : les actions echues s'executent dans l'ordre de leur echeance, y compris celles qu'elles
/// planifient dans l'intervalle.
@MainActor
final class FausseHorloge: Horloge {
    final class Tache: Annulable {
        let echeance: Duration
        let action: @MainActor () async -> Void
        var annulee = false

        init(echeance: Duration, action: @escaping @MainActor () async -> Void) {
            self.echeance = echeance
            self.action = action
        }

        func annuler() {
            annulee = true
        }
    }

    private(set) var maintenant: Duration = .zero
    private var taches: [Tache] = []

    func apres(_ delai: Duration, _ action: @escaping @MainActor () async -> Void) -> any Annulable {
        let t = Tache(echeance: maintenant + delai, action: action)
        taches.append(t)
        return t
    }

    func avancer(_ d: Duration) async {
        let fin = maintenant + d
        while let t = taches.filter({ !$0.annulee && $0.echeance <= fin }).min(by: { $0.echeance < $1.echeance }) {
            taches.removeAll { $0 === t }
            maintenant = t.echeance
            await t.action()
        }
        maintenant = fin
    }
}

/// Un demon et ses imitations.
@MainActor
final class BancDemon {
    static let jeton = String(repeating: "ab", count: 32)

    let maison = FausseMaison()
    let ouverture = FausseOuverture()
    let horloge = FausseHorloge()
    private(set) var liens: [FauxLien] = []
    private(set) var ponctuels: [(cible: EnvoiPasseur.Cible, json: Data)] = []
    private var finsPonctuelles: [@MainActor () -> Void] = []
    private(set) var sorties: [String] = []
    private(set) var demon: DemonPasseur!

    init(statut: EtatPasseur.Ouverture = .inactive, noms: NomsMaison? = nil, profilExpire: Date? = nil) {
        ouverture.statut = statut
        maison.noms = noms
        demon = DemonPasseur(
            source: maison, ouverture: ouverture, horloge: horloge, version: "2.0", profilExpire: profilExpire,
            connecter: { [unowned self] cible in
                let l = FauxLien(cible)
                self.liens.append(l)
                return l
            },
            livrerPonctuel: { [unowned self] cible, json, fini in
                self.ponctuels.append((cible, json))
                self.finsPonctuelles.append(fini)
            },
            quitter: { [unowned self] raison in self.sorties.append(raison) })
        demon.demarrer()
    }

    /// Les apps ont lu leurs releves ponctuels et ferme la connexion.
    func finirPonctuels() {
        let f = finsPonctuelles
        finsPonctuelles = []
        f.forEach { $0() }
    }

    static func url(_ d: EnvoiPasseur.Demande, port: UInt16 = 50_000) -> URL {
        EnvoiPasseur.Cible(port: port, jeton: jeton, demande: d).url
    }

    /// Un abonne de plus ; rend son lien.
    func abonner(port: UInt16 = 50_000) async -> FauxLien? {
        await demon.recevoir(url: Self.url(.abonner, port: port))
        return liens.last
    }

    static func noms(_ nom: String = "Halo", date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> NomsMaison {
        NomsMaison(date: date, accessoires: [AccessoireMaison(nom: nom, id: "8D3C2A10-0000-4000-8000-000000000001")])
    }
}
