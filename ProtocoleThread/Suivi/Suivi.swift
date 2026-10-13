import Foundation
import MaillageCoeur

/// Suit le reseau de releve en releve et en tire les evenements du journal.
///
/// - Un releve vide (ni routeur, ni Matter, ni HAP) est ignore : le Mac
///   n'entend rien (reseau local coupe, acces refuse, invite en attente), rien
///   n'est conclu sur Thread et rien ne change.
/// - Au premier releve non vide : un seul point de depart (`surveillanceDemarree`),
///   et une scission deja la est notee comme constatee, sans autre comparaison.
/// - Un reseau Thread vu pour la premiere fois ensuite est son propre point de
///   depart : son `surveillanceDemarree`, sa scission constatee s'il est scinde,
///   et ni "apparu", ni "nouveau", ni "nouveau prefixe" pour ses membres (un
///   disparu qui y revient reste "revenu"). Un reseau deja vu qui revient est
///   compare normalement ; s'il revient scinde, sa scission est constatee,
///   comme au lancement.
/// - Ensuite : differences entre deux instantanes. Une absence (service ou
///   adresses) n'est retenue qu'apres 2 min (`MemoireAnnonces`) et datee de la
///   premiere absence.
/// - Apres une veille du Mac, ce qui est constate dans les 4 min qui suivent le
///   reveil est date de la veille (`periode`), jamais du reveil ; un point de
///   depart garde sa date. Une absence en cours reprend au reveil : son sursis
///   de 2 min ne compte pas la veille, et si elle est retenue, elle est datee
///   du reveil, donc de la veille.
public struct Suivi: Sendable {
    /// Ce que le suivi sait d'un appareil qui annoncait une adresse : de quoi le redemander a la sonde apres une
    /// relance de l'app (`Suivi.adressesGardees`, `Suivi.amorcer(_:)`).
    public struct AdresseGardee: Codable, Hashable, Sendable {
        /// Derniere adresse de l'appareil sur le prefixe OMR de sa partition.
        public var adresse: AdresseIPv6
        public var partition: String
        /// Date du dernier releve ou il l'annoncait.
        public var annonce: Date

        public init(adresse: AdresseIPv6, partition: String, annonce: Date) {
            self.adresse = adresse
            self.partition = partition
            self.annonce = annonce
        }
    }

    public static let apresReveil: TimeInterval = 240

    public private(set) var instantane: Instantane?
    /// Appareils disparus depuis le lancement (dernier etat connu), jusqu'a leur retour.
    public private(set) var disparus: [String: Appareil] = [:]
    /// Derniere partition connue de chaque appareil (pour placer un appareil sans adresse ou disparu).
    public private(set) var dernieresPartitions: [String: String] = [:]
    /// Derniere adresse de chaque appareil sur le prefixe OMR de sa partition, mise a jour a chaque instantane ou il en
    /// a une : la sonde verifie avec elle un appareil qui ne l'annonce plus (sans adresse ou disparu).
    public private(set) var dernieresAdresses: [String: AdresseIPv6] = [:]
    /// Date du dernier releve ou chaque appareil avait une adresse sur le prefixe OMR de sa partition (celle de
    /// `dernieresAdresses`) : une resolution de la sonde plus ancienne ne prouve rien apres la perte de l'annonce.
    public private(set) var dernieresAnnonces: [String: Date] = [:]
    private var memoire = MemoireAnnonces()
    private var derniereVeille: DateInterval?
    /// Reseaux (`Reseau.id`) vus depuis le lancement.
    private var reseauxVus: Set<String> = []

    public init() {}

    /// La partition qui porte AUJOURD'HUI le prefixe de la derniere adresse de l'appareil, dans l'instantane courant :
    /// apres un changement de partition (perte du chef, fusion), la derniere partition vue par l'appareil n'existe plus
    /// ou n'est plus celle de la sonde, alors que le prefixe OMR est le meme. Repli : sa derniere partition connue
    /// (`dernieresPartitions`), sans adresse gardee ou sans partition qui porte ce prefixe.
    public func partitionActuelle(de id: String) -> String? {
        if let adresse = dernieresAdresses[id],
           let p = instantane?.reseaux.flatMap(\.partitions).first(where: { p in
               p.prefixes.contains { $0.contient(adresse) }
           }) {
            return p.id
        }
        return dernieresPartitions[id]
    }

    /// La derniere adresse de l'appareil est annoncee aujourd'hui, dans l'instantane courant, par un autre
    /// identifiant : c'est le meme appareil revenu sous un nouvel hote, pas un appareil perdu a verifier.
    public func adresseAnnonceeParUnAutre(_ id: String) -> Bool {
        guard let adresse = dernieresAdresses[id], let i = instantane else { return false }
        return i.appareils.contains { $0.id != id && $0.adresses.contains(adresse) }
    }

    /// La derniere adresse, la derniere partition et la derniere annonce de chaque appareil qui a les trois, par
    /// identifiant : ce que l'app garde sur disque entre deux lancements.
    public var adressesGardees: [String: AdresseGardee] {
        var gardees: [String: AdresseGardee] = [:]
        for (id, adresse) in dernieresAdresses {
            guard let partition = dernieresPartitions[id], let annonce = dernieresAnnonces[id] else { continue }
            gardees[id] = AdresseGardee(adresse: adresse, partition: partition, annonce: annonce)
        }
        return gardees
    }

    /// Reprend ce qu'un lancement precedent avait garde (`adressesGardees`) : un appareil sans adresse au premier
    /// releve est ainsi redemande a la sonde avec sa derniere adresse et sa derniere annonce. Ce que le suivi sait
    /// deja, d'un releve de ce lancement, l'emporte : l'adresse et l'annonce vont ensemble, la partition seule.
    public mutating func amorcer(_ gardees: [String: AdresseGardee]) {
        for (id, g) in gardees {
            if dernieresAdresses[id] == nil || dernieresAnnonces[id] == nil {
                dernieresAdresses[id] = g.adresse
                dernieresAnnonces[id] = g.annonce
            }
            if dernieresPartitions[id] == nil { dernieresPartitions[id] = g.partition }
        }
    }

    /// Note une veille du Mac et rend son evenement.
    public mutating func noterVeille(_ periode: DateInterval) -> [Evenement] {
        derniereVeille = periode
        memoire.reprendre(apres: periode.end)
        return [Evenement(date: periode.end, type: .veille, periode: periode)]
    }

    /// Integre un releve et rend les evenements qu'il fait apparaitre.
    public mutating func integrer(_ releve: Annonces, noms: ResolveurNoms = ResolveurNoms()) -> [Evenement] {
        // Releve vide : le Mac n'entend rien, rien a conclure sur Thread.
        guard !releve.estVide else { return [] }
        let nouveau = Instantane(annonces: memoire.completer(releve))
        let date = releve.date
        var ev: [Evenement] = []
        if let ancien = instantane {
            // Reseaux vus pour la premiere fois : chacun son point de depart.
            let apparus = nouveau.reseaux.filter { !reseauxVus.contains($0.id) }
            for r in apparus {
                let appareils = nouveau.appareils.filter { $0.idReseau == r.id }.count
                ev.append(Evenement(date: date, type: .surveillanceDemarree, reseau: r.id, sujet: Sujet(id: r.id, nom: r.nom),
                                    details: ["routeurs": String(r.routeurs.count), "appareils": String(appareils)]))
                if r.estScinde { ev.append(Self.scissionConstatee(r, date, noms)) }
            }
            // Reseaux deja vus qui reviennent (absents de l'instantane precedent) : une
            // scission est constatee, rien n'etant a comparer ; leurs membres, si.
            for r in nouveau.reseaux where r.estScinde && reseauxVus.contains(r.id) && ancien.reseau(r.id) == nil {
                ev.append(Self.scissionConstatee(r, date, noms))
            }
            let fabrique = noms.fabriqueApple(appareils: nouveau.appareils + nouveau.appareilsIP + ancien.appareils)
            ev += Self.evenementsReseaux(ancien, nouveau, date, noms)
            ev += evenementsRouteurs(ancien, nouveau, date, noms, sauf: Set(apparus.flatMap(\.routeurs).map(\.instance)))
            ev += Self.evenementsPrefixes(ancien, nouveau, date, sauf: Set(apparus.flatMap(\.prefixes)))
            ev += evenementsAppareils(ancien, nouveau, date, noms, fabrique, sauf: Set(apparus.map(\.id)))
        } else {
            ev.append(Evenement(date: date, type: .surveillanceDemarree,
                                details: ["routeurs": String(nouveau.routeurs.count),
                                          "appareils": String(nouveau.appareils.count)]))
            for r in nouveau.reseaux where r.estScinde {
                ev.append(Self.scissionConstatee(r, date, noms))
            }
        }
        instantane = nouveau
        reseauxVus.formUnion(nouveau.reseaux.map(\.id))
        for a in nouveau.appareils {
            if let p = a.partition { dernieresPartitions[a.id] = p }
            if let ad = a.adresseOMR {
                dernieresAdresses[a.id] = ad
                dernieresAnnonces[a.id] = date
            }
        }
        return ev.map(dater)
    }

    /// Scission trouvee (au lancement, a la decouverte ou au retour d'un reseau) :
    /// constatee, pas observee.
    static func scissionConstatee(_ r: Reseau, _ date: Date, _ noms: ResolveurNoms) -> Evenement {
        Evenement(date: date, type: .reseauScinde, reseau: r.id, sujet: Sujet(id: r.id, nom: r.nom),
                  apres: String(r.partitions.count), constate: true, details: detailsPartitions(r, noms))
    }

    /// Partition -> noms de ses routeurs, pour dire qui est isole.
    static func detailsPartitions(_ r: Reseau, _ noms: ResolveurNoms) -> [String: String] {
        Dictionary(r.partitions.map { ($0.id, $0.routeurs.map { noms.nom(routeur: $0) }.joined(separator: ", ")) },
                   uniquingKeysWith: { a, _ in a })
    }

    static func evenementsReseaux(_ ancien: Instantane, _ nouveau: Instantane, _ date: Date,
                                  _ noms: ResolveurNoms) -> [Evenement] {
        var ev: [Evenement] = []
        for r in nouveau.reseaux {
            guard let a = ancien.reseau(r.id) else { continue }
            let s = Sujet(id: r.id, nom: r.nom)
            if r.estScinde && r.partitions.count > a.partitions.count {
                ev.append(Evenement(date: date, type: .reseauScinde, reseau: r.id, sujet: s,
                                    avant: String(a.partitions.count), apres: String(r.partitions.count),
                                    details: detailsPartitions(r, noms)))
            } else if r.partitions.count < a.partitions.count {
                ev.append(Evenement(date: date, type: .reseauReuni, reseau: r.id, sujet: s,
                                    avant: String(a.partitions.count), apres: String(r.partitions.count)))
            }
            if let c1 = a.principale?.chef, let c2 = r.principale?.chef, c1.instance != c2.instance {
                ev.append(Evenement(date: date, type: .chefChange, reseau: r.id, sujet: s,
                                    avant: noms.nom(routeur: c1), apres: noms.nom(routeur: c2)))
            }
            if let b1 = a.principale?.bbrPrimaire, let b2 = r.principale?.bbrPrimaire, b1.instance != b2.instance {
                ev.append(Evenement(date: date, type: .bbrPrimaireChange, reseau: r.id, sujet: s,
                                    avant: noms.nom(routeur: b1), apres: noms.nom(routeur: b2)))
            }
            if let j1 = a.routeurs.compactMap(\.jeuActif).max(), let j2 = r.routeurs.compactMap(\.jeuActif).max(), j1 != j2 {
                ev.append(Evenement(date: date, type: .jeuActifChange, reseau: r.id, sujet: s,
                                    avant: j1.formatted(.iso8601), apres: j2.formatted(.iso8601)))
            }
        }
        return ev
    }

    /// `membres` : routeurs des reseaux vus pour la premiere fois (jamais "apparus").
    private func evenementsRouteurs(_ ancien: Instantane, _ nouveau: Instantane, _ date: Date,
                                    _ noms: ResolveurNoms, sauf membres: Set<String>) -> [Evenement] {
        var ev: [Evenement] = []
        let anciens = Dictionary(ancien.routeurs.map { ($0.instance, $0) }, uniquingKeysWith: { a, _ in a })
        let nouveaux = Dictionary(nouveau.routeurs.map { ($0.instance, $0) }, uniquingKeysWith: { a, _ in a })
        for r in nouveau.routeurs {
            let s = Sujet(id: r.instance, nom: noms.nom(routeur: r))
            guard let a = anciens[r.instance] else {
                if !membres.contains(r.instance) {
                    ev.append(Evenement(date: date, type: .routeurApparu, reseau: r.idReseau, sujet: s, apres: r.partition))
                }
                continue
            }
            if let ra = a.role, let rn = r.role, ra != rn {
                ev.append(Evenement(date: date, type: .routeurRoleChange, reseau: r.idReseau, sujet: s,
                                    avant: ra.rawValue, apres: rn.rawValue))
            }
            let la = Set(a.adressesLien)
            let ln = Set(r.adressesLien)
            if !la.isEmpty && !ln.isEmpty && !ln.isSubset(of: la) {
                ev.append(Evenement(date: date, type: .routeurNouvelleAdresseLien, reseau: r.idReseau, sujet: s,
                                    avant: la.sorted().map(\.description).joined(separator: ", "),
                                    apres: ln.sorted().map(\.description).joined(separator: ", ")))
            }
        }
        for a in ancien.routeurs where nouveaux[a.instance] == nil {
            let debut = memoire.abandons[.init(famille: .routeur, instance: a.instance)] ?? date
            ev.append(Evenement(date: debut, type: .routeurDisparu, reseau: a.idReseau,
                                sujet: Sujet(id: a.instance, nom: noms.nom(routeur: a)), avant: a.partition))
        }
        return ev
    }

    /// `exclus` : prefixes des reseaux vus pour la premiere fois (jamais "nouveaux").
    static func evenementsPrefixes(_ ancien: Instantane, _ nouveau: Instantane, _ date: Date,
                                   sauf exclus: Set<PrefixeIPv6> = []) -> [Evenement] {
        let pa = Set(ancien.prefixes)
        let pn = Set(nouveau.prefixes)
        func reseau(_ p: PrefixeIPv6, _ i: Instantane) -> String? { i.reseaux.first { $0.prefixes.contains(p) }?.id }
        return pn.subtracting(pa).subtracting(exclus).sorted().map {
            Evenement(date: date, type: .prefixeNouveau, reseau: reseau($0, nouveau),
                      sujet: Sujet(id: $0.description, nom: $0.description))
        } + pa.subtracting(pn).sorted().map {
            Evenement(date: date, type: .prefixeRetire, reseau: reseau($0, ancien),
                      sujet: Sujet(id: $0.description, nom: $0.description))
        }
    }

    /// `reseauxApparus` : reseaux vus pour la premiere fois (leurs appareils ne sont pas "nouveaux").
    private mutating func evenementsAppareils(_ ancien: Instantane, _ nouveau: Instantane, _ date: Date,
                                              _ noms: ResolveurNoms, _ fabrique: String?,
                                              sauf reseauxApparus: Set<String>) -> [Evenement] {
        var ev: [Evenement] = []
        let anciens = Dictionary(ancien.appareils.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nouveaux = Dictionary(nouveau.appareils.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for n in nouveau.appareils {
            let s = Sujet(id: n.id, nom: noms.nom(appareil: n, fabriqueApple: fabrique))
            if let a = anciens[n.id] {
                if a.genre != .sansAdresse && n.genre == .sansAdresse {
                    let debut = n.hote.flatMap { memoire.adressesAbandonnees[$0] } ?? date
                    ev.append(Evenement(date: debut, type: .appareilSansAdresse, reseau: a.idReseau, sujet: s,
                                        avant: a.partition))
                } else if a.genre == .sansAdresse && n.genre != .sansAdresse {
                    ev.append(Evenement(date: date, type: .appareilRevenu, reseau: n.idReseau, sujet: s,
                                        apres: n.partition))
                } else if let p1 = a.partition, let p2 = n.partition, p1 != p2 {
                    let coupee = n.etat == .partitionCoupee
                    ev.append(Evenement(date: date, type: .appareilChangePartition, gravite: coupee ? .attention : .info,
                                        reseau: n.idReseau, sujet: s, avant: p1, apres: p2,
                                        details: coupee ? ["coupee": "oui"] : [:]))
                }
            } else if disparus[n.id] != nil {
                disparus[n.id] = nil
                ev.append(Evenement(date: date, type: .appareilRevenu, reseau: n.idReseau, sujet: s, apres: n.partition))
            } else if let r = n.idReseau, reseauxApparus.contains(r) {
                // Compte dans le point de depart de son reseau.
            } else {
                ev.append(Evenement(date: date, type: .appareilNouveau, reseau: n.idReseau, sujet: s, apres: n.partition))
            }
        }
        for a in ancien.appareils where nouveaux[a.id] == nil {
            var dates = a.servicesMatter.compactMap { memoire.abandons[.init(famille: .matter, instance: $0)] }
            if let h = a.hap, let d = memoire.abandons[.init(famille: .hap, instance: h.nom)] { dates.append(d) }
            ev.append(Evenement(date: dates.max() ?? date, type: .appareilDisparu, reseau: a.idReseau,
                                sujet: Sujet(id: a.id, nom: noms.nom(appareil: a, fabriqueApple: fabrique)),
                                avant: a.partition ?? dernieresPartitions[a.id]))
            disparus[a.id] = a
        }
        return ev
    }

    /// Ce qui est constate peu apres un reveil est date de la veille ; un point
    /// de depart (surveillance demarree, scission constatee) garde sa date.
    private func dater(_ e: Evenement) -> Evenement {
        guard let v = derniereVeille, e.type != .veille, e.type != .surveillanceDemarree, !e.constate, e.periode == nil,
              e.date >= v.end, e.date <= v.end.addingTimeInterval(Self.apresReveil) else { return e }
        var c = e
        c.periode = v
        return c
    }
}
