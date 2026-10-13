import Foundation
import MaillageCoeur

/// Ce que la tournee demande a la sonde : la liaison USB dans l'app, une sonde
/// rejouee dans les tests.
public protocol InterlocuteurSonde: Sendable {
    func etat() async throws -> EtatSonde
    /// Table des routeurs de la sonde (`routeurs`, lignes `suite` reunies) : tous les routeurs
    /// de la partition par leur RLOC16, l'ExtMac de ceux qu'elle entend. Requete locale, sans
    /// delai reseau.
    func routeurs() async throws -> [RouteurSonde]
    /// Routeurs voisins que la sonde entend (`voisins`), avec leur signal ; son parent n'y est
    /// pas (`etat` le donne). Requete locale, sans delai reseau.
    func voisins() async throws -> [VoisinSonde]
    /// Routeurs dont la sonde a entendu les messages MLE (`annonces`, lignes `suite` reunies ; firmware 1.1.0),
    /// avec leur derniere Route64 brute. Requete locale, sans delai reseau. Un firmware plus ancien ne la connait pas.
    func annonces() async throws -> [AnnonceSonde]
    /// `DIAG_GET` vers un RLOC16 : la reponse, ou l'echec (`delai`, `occupee`...).
    func diag(_ cible: UInt16, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag
    /// `DIAG_GET` vers une adresse du reseau maille (le ML-EID d'un enfant) : la reponse, ou l'echec.
    func diag(adresse: AdresseIPv6, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag
    /// Resolution d'une adresse (`resoudre`, firmware 1.1.0) : le RLOC16 trouve en 15 s au plus, ou l'echec
    /// (`introuvable`, un refus).
    func resoudre(_ adresse: AdresseIPv6) async throws -> ResultatResolution
}

/// Avancement d'une tournee : l'etape en cours, ses requetes revenues et le total prevu a
/// ce moment. Au cours d'une etape, `fait` monte de un a chaque requete revenue et le total
/// ne baisse jamais. Liste des routeurs : le chef et les secours, puis, s'il faut chercher,
/// les autres routeurs de la table de la sonde et tous les autres identifiants (ceux-ci pas
/// dans les 30 min qui suivent une recherche complete vaine) ; l'etape s'arrete a la premiere
/// Route64, souvent avant son total.
public struct AvancementTournee: Hashable, Sendable {
    /// Etapes d'une tournee, dans l'ordre.
    public enum Etape: CaseIterable, Hashable, Sendable {
        /// `etat` de la sonde, puis sa table des routeurs (`routeurs`), ses voisins (`voisins`) et les routeurs
        /// qu'elle entend (`annonces`).
        case etatSonde
        /// Route64 : au chef, aux secours, puis recherche.
        case listeRouteurs
        /// Interrogation des routeurs.
        case routeurs
        /// Pile (une fois par routeur qui repond) et Network Data.
        case pileEtReseau
        /// Resolution des parents des appareils (toutes les 30 min, et un appareil nouveau).
        case resolution
        /// Compteurs MAC des enfants resolus sous un routeur qui ne repond pas.
        case compteurs
        /// Identite des enfants des tables.
        case identites
    }

    public let etape: Etape
    /// Requetes de l'etape revenues.
    public let fait: Int
    /// Requetes prevues pour l'etape a ce moment ; 0 : rien a faire.
    public let total: Int

    public init(etape: Etape, fait: Int, total: Int) {
        self.etape = etape
        self.fait = fait
        self.total = total
    }
}

/// Ce que la tournee retient d'une fois sur l'autre (spec de la sonde, section 4).
public struct MemoireTournee: Hashable, Sendable {
    /// Silences de suite (`delai`), par routeur : muet a partir de 2. Un refus de la sonde
    /// (`occupee`, `suspendue`...) ou une reponse illisible n'en est pas un.
    public var echecs: [Int: Int] = [:]
    /// Derniere interrogation d'un routeur muet : une fois par heure.
    public var muetInterroge: [Int: Date] = [:]
    /// Pile (TLV 28), demandee une fois par routeur qui repond ; "" : aucune.
    public var piles: [Int: String] = [:]
    /// ExtMac des routeurs, par RLOC16 : parents successifs de la sonde, routeurs qui repondent,
    /// routeurs que la sonde entend (sa table des routeurs, ses annonces). Une ExtMac n'a qu'un RLOC16 (`retenir`).
    public var identites: [UInt16: String] = [:]
    /// Parents trouves par la resolution d'adresse, par appareil (spec de la sonde tout-en-un, section 2.2) : ceux de
    /// la derniere resolution complete, et des appareils nouveaux depuis ; oublies quand leur parent sort de la liste.
    public var resolutions: [String: ResolutionAppareil] = [:]
    /// Appareils demandes depuis la derniere resolution complete, resolus ou non (une demande que la sonde refuse ne
    /// compte pas) : un appareil qui n'y est pas est nouveau, et se resout a la tournee suivante.
    public var demandes: Set<String> = []
    /// Derniere resolution complete (toutes les 30 min ; une resolution dont la sonde a refuse toutes les demandes ne
    /// compte pas).
    public var derniereResolution: Date?
    /// Dernier releve des compteurs MAC de chaque enfant resolu sous un routeur muet, par appareil : le prochain
    /// donnera son taux d'acces au canal refuses (`AccesCanal`).
    public var compteurs: [String: CompteursMac] = [:]
    /// Enfants des tables identifies (ExtMac, adresses), par RLOC16 : gardes jusqu'a une nouvelle
    /// reponse ; oublies quand leur parent sort de la liste des routeurs, ou qu'ils manquent a la
    /// table de leur parent qui l'a donnee.
    public var identifies: [UInt16: EnfantMaillage] = [:]
    /// Derniere demande d'identite a un enfant des tables, par RLOC16 : une par demi-heure
    /// au plus, qu'il ait repondu ou non (une demande refusee par la sonde ne compte pas) ;
    /// oubliee avec son identite.
    public var identiteDemandee: [UInt16: Date] = [:]
    /// Routeurs qui ont repondu a la derniere tournee ou l'un a repondu : Route64 de
    /// secours quand le chef ne la donne pas.
    public var repondants: [Int] = []
    /// Derniere recherche complete de la Route64 restee vaine (une recherche dont la sonde a
    /// refuse toutes les requetes ne compte pas) : pas de nouvelle recherche complete avant
    /// `Tournee.periodeRecherche`.
    public var rechercheVaine: Date?
    /// Dernieres Network Data lues : elles servent quand leur requete echoue ou n'est pas faite
    /// (aucun routeur ne repond) ; sinon les routeurs de bordure, le BBR principal et les
    /// candidats disparaitraient d'une tournee a l'autre.
    public var donneesReseau: DonneesReseau?
    /// Partition de ce qui est retenu : une autre remet tout a zero.
    public var partition: String?

    public init() {}

    public func estMuet(_ id: Int) -> Bool { (echecs[id] ?? 0) >= 2 }

    /// Retient l'ExtMac d'un routeur. Un routeur qui a change d'identifiant (redemarrage) perd
    /// l'ancienne paire : elle ne donne plus son ExtMac a l'identifiant libere.
    mutating func retenir(_ ext: String, rloc16: UInt16) {
        for (r, e) in identites where e == ext && r != rloc16 { identites[r] = nil }
        identites[rloc16] = ext
    }
}

/// Tournee de la sonde : liste des routeurs, routeurs qui repondent, roles, liens entendus par la
/// sonde, puis resolution des parents des appareils et taux d'acces au canal refuses des enfants des routeurs muets.
public enum Tournee {
    public static let tlvChef: [UInt8] = [TypeTLV.route64, TypeTLV.donneesChef]
    public static let tlvRouteur: [UInt8] = [TypeTLV.extMac, TypeTLV.address16, TypeTLV.route64, TypeTLV.tableEnfants,
                                             TypeTLV.adresses, TypeTLV.version]
    public static let tlvPile: [UInt8] = [TypeTLV.fabricant, TypeTLV.modele, TypeTLV.versionLogicielle, TypeTLV.pile]
    public static let tlvReseau: [UInt8] = [TypeTLV.donneesReseau]
    public static let tlvIdentite: [UInt8] = [TypeTLV.extMac, TypeTLV.adresses]
    /// Compteurs MAC d'un enfant, demandes a son ML-EID (spec de la sonde tout-en-un, section 2.3).
    public static let tlvCompteurs: [UInt8] = [TypeTLV.compteursMac]
    public static let delaiRouteur = 6000
    /// Requetes en vol a la fois (la sonde en tient 8, et 8 resolutions).
    public static let enVol = 8
    /// Delai d'un enfant : un endormi ne repond qu'a son reveil.
    public static let delaiEnfant = 8000
    /// Identites des enfants des tables : redemandees apres ce delai.
    public static let periodeIdentite: TimeInterval = 30 * 60
    /// Resolution complete des parents : toutes les 30 min (un appareil nouveau, a la tournee suivante).
    public static let periodeResolution: TimeInterval = 30 * 60
    /// Un appareil qui n'annonce plus d'adresse (sans adresse, disparu) est redemande a chaque tournee pendant ce delai
    /// apres sa derniere annonce, tant que sa resolution connue date d'avant cette annonce.
    public static let periodeRedemande: TimeInterval = 30 * 60
    /// Un disparu dont la derniere annonce date de plus que cela n'est plus demande a la sonde.
    public static let ageMaxDisparu: TimeInterval = 24 * 3600
    public static let periodeMuet: TimeInterval = 3600
    /// Apres une recherche complete de la Route64 vaine, delai avant la suivante.
    public static let periodeRecherche: TimeInterval = 30 * 60

    /// Une tournee, et la resolution des parents si elle est due : le maillage et la memoire a garder. Pas de
    /// maillage si la sonde n'est pas attachee, ou suspendue dans Maison (ses requetes echoueraient toutes : aucun
    /// routeur ne doit passer pour muet ; memoire inchangee), ou si aucun routeur n'a donne la liste des routeurs
    /// (Route64) : la memoire rendue est alors celle d'avant (remise a zero dans une autre partition), avec les seules
    /// identites apprises par `etat`, la table des routeurs et les annonces, qu'une sonde promenee garde ainsi, et la
    /// date d'une recherche complete vaine.
    /// Le maillage porte aussi le signal des routeurs que la sonde entend (`voisins`) et celui de son parent (`etat`),
    /// pour l'historique (spec de la sonde, section 6) ; et, depuis le firmware 1.1.0 (spec de la sonde tout-en-un,
    /// section 2), les liens des routeurs dont la sonde entend les annonces, fusionnes avec ceux du diagnostic, et les
    /// enfants des routeurs muets rattaches par la resolution d'adresse de `appareils` (ceux de la partition de la
    /// sonde, elle exceptee), avec, a titre d'information, le taux d'acces au canal refuses que donnent leurs compteurs MAC, sans qualite.
    /// `avancement` est appele au debut de chaque etape atteinte, puis a chaque requete revenue (voir
    /// `AvancementTournee`), depuis la tache de la tournee.
    public static func executer(_ sonde: some InterlocuteurSonde, memoire: MemoireTournee, maintenant: Date,
                                appareils: [AppareilAResoudre] = [],
                                avancement: (@Sendable (AvancementTournee) -> Void)? = nil)
        async throws -> (maillage: Maillage?, memoire: MemoireTournee) {
        func signaler(_ etape: AvancementTournee.Etape, _ fait: Int, _ total: Int) {
            avancement?(AvancementTournee(etape: etape, fait: fait, total: total))
        }
        var mem = memoire
        signaler(.etatSonde, 0, 4)
        let etat = try await sonde.etat()
        signaler(.etatSonde, 1, 4)
        guard etat.estAttachee, !etat.suspendue, let partition = etat.partition, let chef = etat.chef,
              let moi = etat.rloc16Valeur else { return (nil, memoire) }
        // Autre partition : les identifiants de routeur y sont redistribues, rien ne vaut plus.
        if let ancienne = mem.partition, ancienne != partition { mem = MemoireTournee() }
        mem.partition = partition
        // Table des routeurs de la sonde (requete locale, sans delai reseau) : ExtMac des routeurs
        // qu'elle entend. Sans table (firmware sans `routeurs`, sonde occupee), la tournee continue.
        let table = (try? await sonde.routeurs()) ?? []
        signaler(.etatSonde, 2, 4)
        // Voisins de la sonde (requete locale) : le signal de chaque routeur qu'elle entend. Sans
        // reponse, la tournee continue sans eux.
        let voisins = (try? await sonde.voisins()) ?? []
        signaler(.etatSonde, 3, 4)
        // Routeurs dont la sonde entend les messages MLE (requete locale, firmware 1.1.0) : ceux de sa partition, du
        // plus ancien message au plus recent. Sans reponse (firmware 1.0.x), la tournee continue sans l'ecoute, sans
        // la resolution et sans les compteurs, que la sonde ne connait pas.
        let annonces = (try? await sonde.annonces()).map { liste in
            liste.filter { $0.partition == partition && ($0.rloc16Valeur.map { $0 & 0x3FF == 0 } ?? false) }
                .sorted { $0.ageS > $1.ageS }
        }
        signaler(.etatSonde, 4, 4)
        var c = ConstructionMaillage(date: maintenant, partition: partition)
        for v in voisins where v.routeur {
            if let r = UInt16(v.rloc16, radix: 16) { c.signal(SignalSonde(routeur: Int(r >> 10), rssi: v.rssi)) }
        }
        // Chaque annonce relie un RLOC16 a une ExtMac, comme le parent de la sonde ; la plus recente l'emporte, et le
        // parent et la table, plus frais, passent apres.
        for a in annonces ?? [] {
            if let r = a.rloc16Valeur { mem.retenir(a.ext, rloc16: r) }
        }
        if let p = etat.parent, let rp = UInt16(p.rloc16, radix: 16) {
            mem.retenir(p.ext, rloc16: rp)
            c.enfant(EnfantMaillage(rloc16: moi, extMac: etat.ext, qualite: p.lqOut, source: .sonde))
            // Apres les voisins : le signal du parent, donne par `etat`, passe avant.
            c.signal(SignalSonde(routeur: Int(rp >> 10), rssi: p.rssi))
        }
        for r in table {
            if let ext = r.ext, let rloc = r.rloc16Valeur { mem.retenir(ext, rloc16: rloc) }
        }

        // 1. Liste des routeurs : Route64 du chef, puis des routeurs qui ont repondu a la
        // tournee precedente (avant le chef s'il est muet) ; sinon, des autres routeurs de la
        // table de la sonde, puis des autres identifiants.
        let secours = mem.repondants.filter { $0 != chef }
        let essais = mem.estMuet(chef) ? secours + [chef] : [chef] + secours
        var route64: Route64?
        signaler(.listeRouteurs, 0, essais.count)
        for (n, id) in essais.enumerated() {
            let r = try await sonde.diag(rloc16(id), tlvChef, delaiMs: delaiRouteur)
            signaler(.listeRouteurs, n + 1, essais.count)
            if let r64 = r.reponse?.route64 {
                route64 = r64
                break
            }
        }
        if route64 == nil {
            // D'abord les autres routeurs de la table de la sonde ; puis les autres identifiants,
            // sauf dans les 30 min qui suivent une recherche complete vaine (sans reponse, elle
            // coute 63 requetes, pres d'une minute).
            let deLaTable = Set(table.map(\.id)).subtracting(essais).filter { (0...62).contains($0) }.sorted()
            let complete = mem.rechercheVaine.map { maintenant.timeIntervalSince($0) >= periodeRecherche } ?? true
            let autres = complete ? (0...62).filter { !essais.contains($0) && !deLaTable.contains($0) } : []
            let parGroupes = groupes(deLaTable) + groupes(autres)
            let recherche = try await chercherRoute64(sonde, groupes: parGroupes) { faites, prevues in
                signaler(.listeRouteurs, essais.count + faites, essais.count + prevues)
            }
            route64 = recherche.route64
            if route64 == nil, complete, !recherche.refusee { mem.rechercheVaine = maintenant }
        }
        guard let route64 else { return (nil, mem) }
        c.routeurs(route64, chef: chef)
        // Routeurs sortis de la liste (routeur disparu, identifiant libere) : leur paire, leurs
        // echecs, leur pile, leur place de secours et les enfants resolus sous eux sont oublies ; un
        // identifiant reattribue repart de zero.
        let liste = Set(route64.routeurs)
        mem.identites = mem.identites.filter { liste.contains(Int($0.key >> 10)) }
        mem.echecs = mem.echecs.filter { liste.contains($0.key) }
        mem.muetInterroge = mem.muetInterroge.filter { liste.contains($0.key) }
        mem.piles = mem.piles.filter { liste.contains($0.key) }
        mem.repondants = mem.repondants.filter { liste.contains($0) }
        // Un appareil dont la resolution est oubliee est de nouveau demande a cette tournee (comme un appareil nouveau),
        // sans attendre la resolution complete suivante : sinon il resterait sans parent jusque-la.
        let orphelins = mem.resolutions.filter { !liste.contains($0.value.parent) }.keys
        mem.resolutions = mem.resolutions.filter { liste.contains($0.value.parent) }
        mem.demandes.subtract(orphelins)

        // 2. Chaque routeur, en parallele, sauf un muet deja interroge dans l'heure.
        let aInterroger = route64.routeurs.filter { id in
            guard mem.estMuet(id), let quand = mem.muetInterroge[id] else { return true }
            return maintenant.timeIntervalSince(quand) >= periodeMuet
        }
        signaler(.routeurs, 0, aInterroger.count)
        var repondants: [Int] = []
        let reponsesRouteurs = try await parallele(aInterroger, {
            try await sonde.diag(rloc16($0), tlvRouteur, delaiMs: delaiRouteur)
        }, apresChacune: { n, _, _ in signaler(.routeurs, n, aInterroger.count) })
        // Reponse trop longue pour le reseau : le routeur a repondu. Sa requete est refaite une
        // fois, en deux moities de TLV, reunies ; une moitie encore trop longue (ou sans reponse)
        // est laissee : ce qu'on a est garde, sans echec.
        let aCouper = reponsesRouteurs.filter { $0.1.tropLong }.flatMap { r in moities(tlvRouteur).map { (r.0, $0) } }
        var reunies: [Int: String] = [:]
        if !aCouper.isEmpty {
            let total = aInterroger.count + aCouper.count
            signaler(.routeurs, aInterroger.count, total)
            let reponsesMoities = try await parallele(aCouper, {
                try await sonde.diag(rloc16($0.0), $0.1, delaiMs: delaiRouteur)
            }, apresChacune: { n, _, _ in signaler(.routeurs, aInterroger.count + n, total) })
            for ((id, _), r) in reponsesMoities {
                if let t = r.tlv, r.reponse != nil { reunies[id, default: ""] += t }
            }
        }
        var sansExtMac: [Int] = []
        // Enfants de la table de chaque routeur qui l'a donnee.
        var tables: [Int: Set<UInt16>] = [:]
        for (id, r) in reponsesRouteurs {
            if let rep = r.tropLong ? ReponseDiagnostic(hexa: reunies[id] ?? "") : r.reponse {
                c.reponse(rep, routeur: id)
                mem.echecs[id] = 0
                mem.muetInterroge[id] = nil
                if let ext = rep.extMac {
                    mem.retenir(ext, rloc16: rloc16(id))
                } else {
                    sansExtMac.append(id)
                }
                if let enfants = rep.enfants { tables[id] = Set(enfants.map { $0.rloc16(parent: rloc16(id)) }) }
                repondants.append(id)
            } else if r.silence {
                // Seul un silence compte : un refus de la sonde, ou une reponse illisible, ne dit
                // pas que le routeur se tait.
                mem.echecs[id, default: 0] += 1
                if mem.estMuet(id) { mem.muetInterroge[id] = maintenant }
            }
        }
        // Personne n'a repondu (sonde occupee...) : les secours d'avant restent.
        if !repondants.isEmpty { mem.repondants = repondants }
        let muets = Set(route64.routeurs).subtracting(repondants)
        for id in muets.sorted() { c.muet(id) }
        // Muets, et repondants sans ExtMac (moitie d'un `trop_long` sans reponse...) : l'identite
        // connue, lue apres toutes les reponses (une ExtMac passee a un autre routeur a oublie sa
        // paire perimee).
        for id in muets.sorted() + sansExtMac {
            if let ext = mem.identites[rloc16(id)] { c.identite(ext, routeur: id) }
        }

        // 3. Pile, une fois ; Network Data, a un routeur qui repond.
        let sansPile = repondants.filter { mem.piles[$0] == nil }
        let totalPile = sansPile.count + (repondants.isEmpty ? 0 : 1)
        signaler(.pileEtReseau, 0, totalPile)
        for (n, id) in sansPile.enumerated() {
            let r = try await sonde.diag(rloc16(id), tlvPile, delaiMs: delaiRouteur)
            signaler(.pileEtReseau, n + 1, totalPile)
            if let rep = r.reponse { mem.piles[id] = rep.pile ?? "" }
        }
        for id in repondants {
            c.pile(mem.piles[id].flatMap { $0.isEmpty ? nil : $0 }, routeur: id)
        }
        var lues: DonneesReseau?
        if let id = repondants.first {
            let r = try await sonde.diag(rloc16(id), tlvReseau, delaiMs: delaiRouteur)
            signaler(.pileEtReseau, totalPile, totalPile)
            if let brutes = r.reponse?.donneesReseau { lues = DonneesReseau(brutes) }
        }
        if let d = lues {
            c.reseau(d)
            mem.donneesReseau = d
        } else if let d = mem.donneesReseau {
            // Requete en echec, ou aucun routeur qui reponde : les dernieres lues, pour les seuls
            // routeurs de la liste.
            c.reseau(d, seulementConnus: true)
        }

        // 4. Ecoute (spec de la sonde tout-en-un, section 2.1) : la Route64 de chaque annonce d'un routeur de la
        // liste donne ses liens, dates de l'age que donne la sonde ; chaque sens garde la mesure la plus recente,
        // diagnostic ou ecoute (`ConstructionMaillage.lien`).
        if let annonces {
            for a in annonces {
                guard let r = a.rloc16Valeur else { continue }
                c.ecoute(a.route64Decodee, routeur: Int(r >> 10), date: maintenant.addingTimeInterval(-TimeInterval(a.ageS)))
            }
            c.annoncesRecues()
        }

        // 5. Resolution des parents (spec de la sonde tout-en-un, section 2.2), a la place du balayage : toutes les
        // 30 min, et pour un appareil nouveau a la tournee suivante ; 8 en vol. Une demande que la sonde refuse ne
        // compte pas : elle est refaite a la tournee suivante. Une resolution complete remplace la precedente, sauf
        // si la sonde a refuse toutes ses demandes ; un appareil non resolu reste en rattachement suppose.
        let moiExt = etat.ext?.uppercased()
        let cibles = appareils.filter {
            $0.partition == partition && $0.id.uppercased() != moiExt && !$0.perduDepuisTropLongtemps(a: maintenant)
        }.sorted { $0.id < $1.id }
        let complete = mem.derniereResolution.map { maintenant.timeIntervalSince($0) >= periodeResolution } ?? true
        // Un appareil qui vient de perdre son annonce (sans adresse, disparu) est redemande a chaque tournee, comme un
        // appareil nouveau, tant que sa resolution connue date d'avant la perte : elle ne prouve rien d'apres.
        let aResoudre = annonces == nil ? [] : complete ? cibles : cibles.filter {
            !mem.demandes.contains($0.id) || $0.aRedemander(a: maintenant, resolution: mem.resolutions[$0.id])
        }
        signaler(.resolution, 0, aResoudre.count)
        let resolues = try await parallele(aResoudre, { try await sonde.resoudre($0.adresse) },
                                           apresChacune: { n, _, _ in signaler(.resolution, n, aResoudre.count) })
        var nouvelles: [String: ResolutionAppareil] = [:]
        var demandees: Set<String> = []
        for (a, r) in resolues where !r.refus {
            demandees.insert(a.id)
            if let rloc = r.rloc16Valeur {
                nouvelles[a.id] = ResolutionAppareil(rloc16: rloc, mleid: r.adresseMleid, adresse: a.adresse,
                                                     date: maintenant, repondu: r.repondu)
            }
        }
        if complete && annonces != nil {
            if aResoudre.isEmpty || !demandees.isEmpty {
                // Un appareil refuse cette fois garde sa resolution d'avant, et sera demande de nouveau.
                let refuses = Set(aResoudre.map(\.id)).subtracting(demandees)
                mem.resolutions = nouvelles.merging(mem.resolutions.filter { refuses.contains($0.key) }) { n, _ in n }
                mem.demandes = demandees
                mem.derniereResolution = maintenant
            }
        } else {
            mem.resolutions.merge(nouvelles) { _, n in n }
            mem.demandes.formUnion(demandees)
        }

        // 6. Compteurs MAC (spec de la sonde tout-en-un, section 2.3) : a sa resolution, chaque enfant d'un routeur
        // muet (Apple) dont la sonde connait le ML-EID ; le taux d'acces au canal refuses entre deux releves est garde
        // a titre d'information, sans donner de qualite (`AccesCanal`) : l'enfant reste en qualite inconnue. Sans
        // reponse, pas de taux, et le releve d'avant reste.
        let aMesurer = nouvelles.filter { muets.contains($0.value.parent) }.sorted { $0.key < $1.key }
            .compactMap { id, r in r.mleid.map { (id, $0) } }
        signaler(.compteurs, 0, aMesurer.count)
        let mesures = try await parallele(aMesurer, {
            try await sonde.diag(adresse: $0.1, tlvCompteurs, delaiMs: delaiEnfant)
        }, apresChacune: { n, _, _ in signaler(.compteurs, n, aMesurer.count) })
        for ((id, _), r) in mesures {
            guard let releve = r.reponse?.compteursMac else { continue }
            if let avant = mem.compteurs[id], let taux = AccesCanal.taux(avant: avant, apres: releve) {
                mem.resolutions[id]?.echecs = taux
            }
            mem.compteurs[id] = releve
        }

        // 7. Enfants des tables : ExtMac et adresses, gardees jusqu'a une nouvelle reponse ;
        // demandees de nouveau apres 30 min, que l'enfant ait repondu ou non.
        // Endormis sous un routeur qui repond : interroges au plus une fois par demi-heure, la Child Table ne donnant pas leur ExtMac.
        // L'identite d'un enfant (et la date de sa demande) est oubliee quand son parent sort de la
        // liste, ou qu'il manque a la table de son parent qui l'a donnee : un appareil qui reprend
        // son RLOC16 n'a pas l'ancien nom, et son identite est demandee tout de suite.
        func garde(_ enfant: UInt16) -> Bool {
            let parent = Int(enfant >> 10)
            return liste.contains(parent) && (tables[parent].map { $0.contains(enfant) } ?? true)
        }
        mem.identifies = mem.identifies.filter { garde($0.key) }
        mem.identiteDemandee = mem.identiteDemandee.filter { garde($0.key) }
        let aIdentifier = c.enfantsSansIdentite.filter { cible in
            mem.identiteDemandee[cible].map { maintenant.timeIntervalSince($0) >= periodeIdentite } ?? true
        }
        signaler(.identites, 0, aIdentifier.count)
        let identites = try await parallele(aIdentifier, {
            try await sonde.diag($0, tlvIdentite, delaiMs: delaiEnfant)
        }, apresChacune: { n, _, _ in signaler(.identites, n, aIdentifier.count) })
        for (cible, r) in identites {
            // Une demande refusee par la sonde n'est pas faite : elle le sera a la tournee suivante.
            if !r.refus { mem.identiteDemandee[cible] = maintenant }
            guard let rep = r.reponse else { continue }
            mem.identifies[cible] = EnfantMaillage(rloc16: cible, extMac: rep.extMac, adresses: rep.adresses, source: .tableEnfants)
        }
        for cible in c.enfantsSansIdentite {
            if let e = mem.identifies[cible] { c.enfant(e) }
        }

        // 8. Enfants resolus, sous leur parent muet (sous un routeur qui repond, sa table fait foi), apres les
        // identites : pas un appareil deja la (meme ExtMac ou meme adresse qu'un enfant des tables ou de la sonde : il
        // a change de parent depuis), ni un routeur lui-meme. Le RLOC16 rendu est celui de l'enfant (routeur tiers),
        // ou celui du parent (routeur Apple) : l'enfant recoit alors un numero invente sous lui
        // (`EnfantMaillage.bitInvente`), dans l'ordre des appareils.
        let dejaLa = c.maillage()
        let extMacs = Set(dejaLa.enfants.compactMap(\.extMac)), adresses = Set(dejaLa.enfants.flatMap(\.adresses))
        var inventes: [Int: UInt16] = [:]
        // Un appareil qui n'annonce plus son adresse n'est dessine sous ce parent que si la sonde l'a retrouve depuis
        // la perte : une resolution posterieure a sa derniere annonce ET repondue (`ResolutionAppareil.prouve`). Une
        // resolution plus ancienne, ou que le cache seul a donnee (repondu faux, ou firmware ancien), ne prouve rien.
        let pertes = Dictionary(appareils.compactMap { a in a.derniereAnnonce.map { (a.id, $0) } },
                                uniquingKeysWith: { a, _ in a })
        // Un appareil que l'app ne demande plus (son adresse est annoncee par un autre identifiant, ou il a quitte la
        // liste) n'est plus dessine : sa resolution d'avant ne vaut plus pour lui. Sans liste (tests anciens), rien.
        let demandables = Set(appareils.map(\.id))
        for (id, r) in mem.resolutions.sorted(by: { $0.key < $1.key }) where muets.contains(r.parent) {
            if !appareils.isEmpty, !demandables.contains(id) { continue }
            if let annonce = pertes[id], !r.prouve(apres: annonce) { continue }
            let ext = GrapheReseau.extMac(hote: id)
            if let ext, extMacs.contains(ext) { continue }
            if adresses.contains(r.adresse) { continue }
            var rloc = r.rloc16
            if rloc & 0x3FF == 0 {
                // Le RLOC16 d'un routeur : l'appareil est ce routeur lui-meme (son ExtMac), ou un enfant d'un routeur Apple.
                if let ext, ext == dejaLa.routeur(r.parent)?.extMac?.uppercased() { continue }
                let k = inventes[r.parent, default: 0]
                inventes[r.parent] = k + 1
                rloc = rloc16(r.parent) | EnfantMaillage.bitInvente | (k & 0x1FF)
            } else if rloc == moi {
                continue
            }
            c.enfant(EnfantMaillage(rloc16: rloc, extMac: ext, adresses: [r.adresse], source: .resolution, resolu: r.date,
                                    echecs: r.echecs))
        }
        var maillage = c.maillage()
        // Date de la resolution complete dont viennent les enfants resolus (une resolution refusee ne la change pas).
        maillage.resolution = mem.derniereResolution
        maillage.resolus = mem.resolutions.mapValues(\.date)
        maillage.resolusRepondus = Set(mem.resolutions.filter { $0.value.repondu == true }.keys)
        return (maillage, mem)
    }

    static func rloc16(_ routeur: Int) -> UInt16 { UInt16(routeur) << 10 }

    /// Une requete coupee en deux moities de TLV (reponse trop longue pour le reseau).
    static func moities(_ tlv: [UInt8]) -> [[UInt8]] {
        let milieu = tlv.count / 2
        return [Array(tlv[..<milieu]), Array(tlv[milieu...])].filter { !$0.isEmpty }
    }

    /// Identifiants par groupes de `enVol`, dans l'ordre.
    static func groupes(_ ids: [Int]) -> [[Int]] {
        stride(from: 0, to: ids.count, by: enVol).map { Array(ids[$0..<min($0 + enVol, ids.count)]) }
    }

    /// Route64 quand ni le chef ni les secours ne l'ont donnee (chef muet des le lancement) :
    /// les `groupes` d'identifiants dans l'ordre, chacun en parallele ; au premier groupe ou l'un
    /// la donne, celle du premier du groupe (le plus petit). `refusee` : il y a eu des requetes,
    /// et la sonde les a toutes refusees. `suivi` : requetes revenues et prevues (tous ces
    /// identifiants), au debut puis a chaque requete revenue.
    static func chercherRoute64(_ sonde: some InterlocuteurSonde, groupes: [[Int]],
                                suivi: (_ faites: Int, _ prevues: Int) -> Void = { _, _ in }) async throws
        -> (route64: Route64?, refusee: Bool) {
        let prevues = groupes.reduce(0) { $0 + $1.count }
        suivi(0, prevues)
        var faites = 0
        var refusee = !groupes.isEmpty
        for groupe in groupes {
            let avant = faites
            let resultats = try await parallele(groupe, {
                try await sonde.diag(rloc16($0), tlvChef, delaiMs: delaiRouteur)
            }, apresChacune: { n, _, _ in suivi(avant + n, prevues) })
            faites += groupe.count
            for (_, r) in resultats {
                if let route64 = r.reponse?.route64 { return (route64, false) }
                refusee = refusee && r.refus
            }
        }
        return (nil, refusee)
    }

    /// Au plus `enVol` requetes a la fois ; resultats dans l'ordre des elements.
    /// `apresChacune` : a chaque requete revenue, le nombre de revenues, l'element et son resultat.
    static func parallele<E: Sendable, R: Sendable>(_ elements: [E],
                                                    _ requete: @escaping @Sendable (E) async throws -> R,
                                                    apresChacune: (_ faites: Int, _ element: E, _ resultat: R) -> Void = { _, _, _ in })
        async throws -> [(E, R)] {
        var resultats: [(Int, E, R)] = []
        try await withThrowingTaskGroup(of: (Int, E, R).self) { groupe in
            var suivant = 0
            func lancer() {
                let i = suivant
                suivant += 1
                let e = elements[i]
                groupe.addTask { (i, e, try await requete(e)) }
            }
            while suivant < min(enVol, elements.count) { lancer() }
            while let r = try await groupe.next() {
                resultats.append(r)
                apresChacune(resultats.count, r.1, r.2)
                if suivant < elements.count { lancer() }
            }
        }
        return resultats.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }
}

fileprivate extension ResultatDiag {
    /// Silence de la cible : la requete est partie, et rien n'est revenu a temps (`delai`). Une
    /// reponse illisible (`ok`, TLV tronquee) n'en est pas un.
    var silence: Bool { !ok && erreur == "delai" }

    /// Refus : ni reponse (lisible ou non), ni `trop_long`, ni silence. La sonde n'a pas envoye
    /// la requete (`occupee`, `suspendue`, `envoi...`), ou elle rend une autre erreur d'OpenThread
    /// apres l'envoi (`Abort`...) : dans les deux cas, rien n'est dit de la cible.
    var refus: Bool { !ok && !tropLong && !silence }
}

fileprivate extension ResultatResolution {
    /// Refus : ni le RLOC16 trouve, ni `introuvable`. La sonde n'a pas fait la demande (`occupee`, `suspendue`,
    /// `envoi...`, `syntaxe`), ou ne l'a pas rendue a temps (`delai`) : rien n'est dit de l'appareil.
    var refus: Bool { !ok && !introuvable }
}
