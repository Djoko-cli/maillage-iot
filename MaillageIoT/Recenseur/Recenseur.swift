import Foundation
import MaillageCoeur

/// Ecoute le reseau local et produit des releves (`Annonces`). Le premier des
/// que l'ecoute est prete (tous les navigateurs), qu'un routeur de bordure est
/// liste et que les annonces se sont calmees (aucun changement des navigateurs
/// depuis 2 s), jamais avant 10 s (le temps que les reponses arrivent) et au plus
/// tard 60 s apres le demarrage. Ensuite, a chaque changement des services (apres
/// 2 s de calme) et au moins toutes les 60 s ; un changement avant le premier
/// releve ne declenche rien (il retarde seulement le premier). Une instance
/// n'entre dans un releve qu'avec sa cible resolue (hote, port).
@MainActor
final class Recenseur {
    enum Etat: Equatable, Sendable {
        case demarrage, actif, reseauLocalRefuse
        case erreur(String)
    }

    nonisolated static let types = ["_meshcop._udp", "_matter._tcp", "_hap._udp", "_trel._udp"]
    nonisolated static let miseEnRoute: Duration = .seconds(10)
    nonisolated static let attenteMax: Duration = .seconds(60)
    nonisolated static let calme: Duration = .seconds(2)
    static let periode: Duration = .seconds(60)

    private(set) var etat: Etat = .demarrage
    /// La table de routage a-t-elle pu etre lue au dernier releve (nil : pas encore de releve).
    private(set) var routesLisibles: Bool?
    private(set) var dernierReleve: Annonces?
    var surReleve: ((Annonces) -> Void)?
    var surEtat: ((Etat) -> Void)?

    private var navigateurs: [NavigateurBonjour] = []
    /// "type|instance" -> derniere cible resolue, gardee tant que l'instance est listee.
    private var cibles: [String: ResolveurDNSSD.Cible] = [:]
    private var demarre = false
    private var enRoute = false
    private var releveEnCours = false
    private var releveEnAttente = false
    private var tachePeriodique: Task<Void, Never>?
    private var tacheCalme: Task<Void, Never>?
    /// Instant du dernier changement d'un navigateur (nil : aucun depuis le demarrage).
    private var dernierChangement: ContinuousClock.Instant?
    /// Demande de resoudre de nouveau toutes les instances listees, consommee au debut du prochain releve.
    private var toutResoudre = false

    func demarrer() {
        guard !demarre else { return }
        demarre = true
        navigateurs = Self.types.map { type in
            let n = NavigateurBonjour(type: type)
            n.surChangement = { [weak self] in self?.changement() }
            n.demarrer()
            return n
        }
        let debut = ContinuousClock.now
        tachePeriodique = Task { @MainActor [weak self] in
            // Premier releve : quand premierReleveDu le dit (verifie chaque seconde).
            while !Task.isCancelled {
                guard let self else { return }
                let maintenant = ContinuousClock.now
                if Self.premierReleveDu(depuis: maintenant - debut, etat: self.etat, routeurVu: self.routeurVu,
                                        calmeDepuis: maintenant - (self.dernierChangement ?? debut)) { break }
                try? await Task.sleep(for: .seconds(1))
            }
            while !Task.isCancelled {
                guard let self else { return }
                self.enRoute = true
                await self.releve()
                try? await Task.sleep(for: Self.periode)
            }
        }
    }

    /// Le premier releve est-il du ? Jamais avant la mise en route (10 s) ;
    /// ensuite des que l'ecoute est prete (tous les navigateurs), qu'un routeur
    /// de bordure est liste et que les navigateurs n'ont rien change depuis
    /// `calme` (`calmeDepuis` : temps ecoule depuis le dernier changement, ou
    /// depuis le demarrage s'il n'y en a pas eu) : les reponses ont fini
    /// d'arriver. Au plus tard `attenteMax` apres le demarrage, quel que soit
    /// l'etat (invite en attente, acces refuse, reseau muet, annonces sans fin).
    nonisolated static func premierReleveDu(depuis ecoule: Duration, etat: Etat, routeurVu: Bool,
                                            calmeDepuis: Duration) -> Bool {
        guard ecoule >= miseEnRoute else { return false }
        return ecoule >= attenteMax || (etat == .actif && routeurVu && calmeDepuis >= calme)
    }

    /// Au moins un routeur de bordure (`_meshcop._udp`) est liste.
    private var routeurVu: Bool {
        navigateurs.contains { $0.type == "_meshcop._udp" && !$0.instances.isEmpty }
    }

    func arreter() {
        tachePeriodique?.cancel()
        tacheCalme?.cancel()
        navigateurs.forEach { $0.arreter() }
        navigateurs = []
        demarre = false
        enRoute = false
        dernierChangement = nil
    }

    /// Releve immediat (bouton rafraichir, reveil du Mac). Au releve suivant, chaque
    /// instance listee est resolue de nouveau : une reussite remplace sa cible, un
    /// echec garde la precedente. Un releve en cours n'est pas interrompu : celui-ci
    /// le suit. Avant la mise en route, rien n'est lance.
    func rafraichir() {
        toutResoudre = true
        guard enRoute else { return }
        Task { @MainActor [weak self] in await self?.releve() }
    }

    /// Tout changement d'un navigateur (instances ou etat), avant comme apres la
    /// mise en route : son instant compte pour le calme du premier releve ;
    /// ensuite, un releve 2 s apres le dernier changement.
    private func changement() {
        dernierChangement = .now
        mettreAJourEtat()
        guard enRoute else { return }
        tacheCalme?.cancel()
        tacheCalme = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.calme)
            guard !Task.isCancelled else { return }
            await self?.releve()
        }
    }

    private func mettreAJourEtat() {
        let etats = navigateurs.map(\.etat)
        let nouveau: Etat
        if etats.contains(.refuse) {
            nouveau = .reseauLocalRefuse
        } else if let e = etats.lazy.compactMap({ if case .erreur(let m) = $0 { m } else { nil } }).first {
            nouveau = .erreur(e)
        } else if !etats.isEmpty && etats.allSatisfy({ $0 == .pret }) {
            nouveau = .actif
        } else {
            nouveau = .demarrage
        }
        guard nouveau != etat else { return }
        etat = nouveau
        surEtat?(nouveau)
    }

    /// Un releve a la fois ; une demande pendant un releve en relance un apres.
    private func releve() async {
        guard !releveEnCours else {
            releveEnAttente = true
            return
        }
        releveEnCours = true
        repeat {
            releveEnAttente = false
            let a = await faireReleve()
            dernierReleve = a
            surReleve?(a)
        } while releveEnAttente
        releveEnCours = false
    }

    private func faireReleve() async -> Annonces {
        // 1. Instances listees, et leur cible (hote, port) : resolue une fois par
        //    instance, et de nouveau pour toutes apres rafraichir().
        var vues: [InstanceListee] = []
        for n in navigateurs {
            for (instance, txt) in n.instances { vues.append(InstanceListee(type: n.type, instance: instance, txt: txt)) }
        }
        let tout = toutResoudre
        toutResoudre = false
        let aResoudre = vues.filter { tout || cibles[Self.cle($0.type, $0.instance)] == nil }
        let resolues = await withTaskGroup(of: (String, ResolveurDNSSD.Cible?).self) { groupe in
            for v in aResoudre {
                let cle = Self.cle(v.type, v.instance)
                groupe.addTask { (cle, await ResolveurDNSSD.resoudre(instance: v.instance, type: v.type)) }
            }
            var r: [String: ResolveurDNSSD.Cible] = [:]
            for await (cle, cible) in groupe { if let cible { r[cle] = cible } }
            return r
        }
        cibles = Self.retenir(cibles: cibles, resolues: resolues, listees: Set(vues.map { Self.cle($0.type, $0.instance) }))

        // 2. Adresses de chaque hote, a chaque releve.
        let hotes = Set(cibles.values.map(\.hote))
        let adresses = await withTaskGroup(of: (String, [String]).self) { groupe in
            for hote in hotes {
                groupe.addTask { (hote, await ResolveurDNSSD.adresses(hote: hote)) }
            }
            var r: [String: [String]] = [:]
            for await (hote, liste) in groupe { r[hote] = liste }
            return r
        }

        // 3. Routes et prefixes du Mac.
        let routes = TableRoutage.lire()
        routesLisibles = routes != nil

        // 4. Le releve : seules les instances dont la cible est connue y entrent.
        return Self.assembler(vues: vues, cibles: cibles, adresses: adresses, routes: routes ?? [],
                              prefixesLocaux: InterfacesLocales.prefixes(), date: Date())
    }
}
