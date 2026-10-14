import Foundation
import MaillageCoeur

/// Routeur Thread vu par la sonde.
public struct RouteurMaillage: Hashable, Sendable, Identifiable, Codable {
    /// Identifiant de routeur, de 0 a 62 : son RLOC16 est `id << 10`.
    public let id: Int
    public var extMac: String?
    /// Publie un prefixe, une route ou le service SRP (Network Data).
    public var bordure = false
    public var bbrPrincipal = false
    public var chef = false
    /// N'a pas repondu a la tournee : ses liens et ses enfants ne viennent que des autres.
    public var muet = false
    public var version: Int?
    /// Version de la pile (TLV 28).
    public var pile: String?
    /// Dernier message MLE de ce routeur que la sonde a entendu (`annonces`, firmware 1.1.0) ; nil s'il n'est pas
    /// entendu.
    public var entendu: Date?

    public init(id: Int) { self.id = id }

    public var rloc16: UInt16 { UInt16(id) << 10 }
}

/// D'ou vient la mesure d'un sens d'un lien entre routeurs (spec de la sonde tout-en-un, section 2.1). Un lien est un
/// lien : il est dessine pareil quelle que soit sa source ; la fiche dit la source et l'age.
public enum SourceLien: String, Hashable, Sendable, Codable {
    /// Route64 d'un routeur qui repond au diagnostic, mesuree au debut de la tournee.
    case diagnostic = "diag"
    /// Route64 d'une annonce MLE que la sonde a entendue, datee de l'age que la sonde donne.
    case ecoute
}

/// Lien radio entre deux routeurs voisins (a < b), avec la qualite dans chaque
/// sens, de 0 a 3 ; nil : inconnue.
public struct LienRadio: Hashable, Sendable, Codable {
    public let a: Int
    public let b: Int
    /// Qualite du lien de a vers b.
    public var qualiteAB: Int?
    /// Qualite du lien de b vers a.
    public var qualiteBA: Int?
    /// Source de la mesure de chaque sens ; nil : inconnue (maillage de demo, historique d'avant la 1.1.0).
    public var sourceAB: SourceLien?
    public var sourceBA: SourceLien?
    /// Date de la mesure de chaque sens ; nil : inconnue. L'historique ne la garde pas.
    public var dateAB: Date?
    public var dateBA: Date?

    /// La moins bonne des qualites connues.
    public var qualite: Int? { [qualiteAB, qualiteBA].compactMap { $0 }.min() }

    /// Le meme lien sans les dates de ses mesures, comme l'historique le garde.
    public var sansDates: LienRadio {
        var l = self
        l.dateAB = nil
        l.dateBA = nil
        return l
    }
}

/// Couverture de l'ecoute (Reglages › Sonde) : les routeurs de la partition que la sonde entend, sur tous.
public struct CouvertureEcoute: Hashable, Sendable {
    public let entendus: Int
    public let routeurs: Int

    public init(entendus: Int, routeurs: Int) {
        self.entendus = entendus
        self.routeurs = routeurs
    }
}

/// D'ou vient un enfant.
public enum SourceEnfant: String, Hashable, Sendable, Codable {
    /// Child Table de son parent, un routeur qui repond.
    case tableEnfants
    /// Rattache a son parent par la resolution d'adresse (spec de la sonde tout-en-un, section 2.2), sous un routeur
    /// qui ne repond pas au diagnostic.
    case resolution
    /// La sonde elle-meme.
    case sonde
}

/// Enfant d'un routeur (appareil endormi ou non, ou la sonde).
public struct EnfantMaillage: Hashable, Sendable, Identifiable, Codable {
    public let rloc16: UInt16
    public var extMac: String?
    /// Qualite du lien de l'enfant vers son parent, de 0 a 3 ; nil sous un routeur muet.
    public var qualite: Int?
    /// Delai d'expiration de l'enfant (Child Timeout), en secondes.
    public var delai: Int?
    public var endormi: Bool?
    /// Adresses donnees par l'enfant (TLV 8), pour le reconnaitre par son adresse OMR.
    public var adresses: [AdresseIPv6]
    public var source: SourceEnfant
    /// Date de la resolution d'adresse qui l'a rattache (source `.resolution`) ; nil sinon.
    public var resolu: Date?
    /// Taux d'acces au canal refuses de l'enfant entre deux releves de ses compteurs MAC (enfant resolu sous un routeur
    /// qui ne repond pas, spec de la sonde tout-en-un, section 2.3), a titre d'information : il ne donne pas sa qualite
    /// (`AccesCanal`) ; nil sinon.
    public var echecs: Double?

    public init(rloc16: UInt16, extMac: String? = nil, qualite: Int? = nil, delai: Int? = nil, endormi: Bool? = nil,
                adresses: [AdresseIPv6] = [], source: SourceEnfant, resolu: Date? = nil, echecs: Double? = nil) {
        self.rloc16 = rloc16
        self.extMac = extMac
        self.qualite = qualite
        self.delai = delai
        self.endormi = endormi
        self.adresses = adresses
        self.source = source
        self.resolu = resolu
        self.echecs = echecs
    }

    public var id: UInt16 { rloc16 }
    /// Identifiant de routeur du parent.
    public var parent: Int { Int(rloc16 >> 10) }

    /// Bit 9 d'un RLOC16 : toujours nul dans un vrai (6 bits de routeur, un bit nul, 9 bits d'enfant). Un enfant resolu
    /// sous un routeur qui repond par son propre RLOC16 (Apple) n'a pas le sien : il recoit un numero invente sous son
    /// parent, ce bit a 1, qui ne peut etre celui d'aucun autre noeud.
    public static let bitInvente: UInt16 = 0x0200

    /// Son vrai RLOC16 est connu (`bitInvente` nul).
    public var rloc16Connu: Bool { rloc16 & Self.bitInvente == 0 }
}

/// Signal d'un routeur tel que la sonde l'entend a une tournee (spec de la sonde, section 6) :
/// son parent (`etat`) ou un routeur voisin (`voisins`).
public struct SignalSonde: Hashable, Sendable, Codable {
    /// Identifiant du routeur.
    public let routeur: Int
    /// RSSI moyen, en dBm.
    public let rssi: Int

    public init(routeur: Int, rssi: Int) {
        self.routeur = routeur
        self.rssi = rssi
    }
}

/// Le maillage d'une partition, tel qu'une tournee de la sonde le voit.
public struct Maillage: Hashable, Sendable, Codable {
    public let date: Date
    public let partition: String
    /// Par identifiant croissant.
    public let routeurs: [RouteurMaillage]
    /// Par (a, b) croissants.
    public let liens: [LienRadio]
    /// Par RLOC16 croissant.
    public let enfants: [EnfantMaillage]
    /// Signal des routeurs de la liste que la sonde entend, son parent compris, par identifiant
    /// croissant.
    public let signaux: [SignalSonde]
    /// Date de la resolution complete dont viennent les enfants resolus de ce maillage
    /// (`MemoireTournee.derniereResolution`) ; nil sans resolution.
    public var resolution: Date?
    /// La sonde a rendu ses annonces a cette tournee (firmware 1.1.0) : un routeur sans `entendu` n'est pas entendu.
    public var annoncesLues = false
    /// Appareils que la resolution d'adresse a trouves, par identifiant, avec la date de leur resolution
    /// (`MemoireTournee.resolutions` a la fin de la tournee), quel que soit leur parent : un appareil qui
    /// n'annonce plus son adresse et que la sonde trouve est joignable. Pas garde sur disque : un maillage relu
    /// au lancement n'en a aucun, jusqu'a la tournee suivante.
    public var resolus: [String: Date] = [:]
    /// Ceux de `resolus` dont l'appareil a repondu a la sonde (`ResolutionAppareil.repondu == true`) ; les autres n'ont
    /// que leur entree du cache d'adresses (repondu faux) ou une sonde au firmware ancien (nil). Pas garde sur disque.
    public var resolusRepondus: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case date, partition, routeurs, liens, enfants, signaux, resolution, annoncesLues
    }

    /// Couverture de l'ecoute : les routeurs entendus sur ceux de la partition ; nil si la sonde n'a pas rendu ses
    /// annonces (firmware 1.0.3, sonde muette).
    public var couverture: CouvertureEcoute? {
        annoncesLues ? CouvertureEcoute(entendus: routeurs.count { $0.entendu != nil }, routeurs: routeurs.count) : nil
    }

    /// Les identifiants de routeur sont possibles (0 a 62) et ceux des routeurs uniques : un maillage relu d'un
    /// fichier (`dernier-maillage.json`) qui ne l'est pas est ignore, plutot que d'arreter l'app (`rloc16`,
    /// dictionnaires par identifiant).
    public var identifiantsValides: Bool {
        let possibles = ReleveMaillage.identifiantsRouteur
        let ids = routeurs.map(\.id)
        return Set(ids).count == ids.count && ids.allSatisfy(possibles.contains)
            && liens.allSatisfy { possibles.contains($0.a) && possibles.contains($0.b) }
            && signaux.allSatisfy { possibles.contains($0.routeur) }
    }

    public func routeur(_ id: Int) -> RouteurMaillage? { routeurs.first { $0.id == id } }
    public func liens(de id: Int) -> [LienRadio] { liens.filter { $0.a == id || $0.b == id } }
    public func enfants(de id: Int) -> [EnfantMaillage] { enfants.filter { $0.parent == id } }
    public var chef: RouteurMaillage? { routeurs.first(where: \.chef) }
    /// Identifiant de routeur du parent de la sonde.
    public var parentSonde: Int? { enfants.first { $0.source == .sonde }?.parent }

    /// Enfants identifies (ExtMac connue), un par ExtMac. Vu deux fois (il a change de parent),
    /// l'entree la plus fraiche l'emporte : la sonde (elle sait son parent), puis la table d'un
    /// routeur qui repond (l'ancien parent garde l'enfant jusqu'a son echeance), puis la resolution
    /// sous un routeur muet, qui peut dater de 30 minutes ; a egalite, la premiere par RLOC16. Une
    /// entree de la resolution dont l'ExtMac est celle d'un routeur du maillage est ecartee : l'enfant
    /// est devenu routeur depuis.
    public var enfantsIdentifies: [String: EnfantMaillage] {
        func rang(_ s: SourceEnfant) -> Int {
            switch s {
            case .sonde: 0
            case .tableEnfants: 1
            case .resolution: 2
            }
        }
        let routeursExt = Set(routeurs.compactMap(\.extMac))
        var parExtMac: [String: EnfantMaillage] = [:]
        for e in enfants {
            guard let x = e.extMac, !(e.source == .resolution && routeursExt.contains(x)) else { continue }
            if let deja = parExtMac[x], rang(deja.source) <= rang(e.source) { continue }
            parExtMac[x] = e
        }
        return parExtMac
    }
}

/// Assemble un `Maillage` au fil des reponses d'une tournee.
public struct ConstructionMaillage: Sendable {
    private let date: Date
    private let partition: String
    private var routeurs: [Int: RouteurMaillage] = [:]
    private var liens: [Int: LienRadio] = [:]
    private var enfants: [UInt16: EnfantMaillage] = [:]
    private var signaux: [Int: SignalSonde] = [:]
    private var annoncesLues = false

    public init(date: Date, partition: String) {
        self.date = date
        self.partition = partition
    }

    /// Routeurs actifs de la partition (Route64 du chef, ou d'un routeur qui repond).
    public mutating func routeurs(_ r: Route64, chef: Int) {
        for id in r.routeurs where routeurs[id] == nil { routeurs[id] = RouteurMaillage(id: id) }
        routeurs[chef, default: RouteurMaillage(id: chef)].chef = true
    }

    /// Roles lus dans les Network Data. BBR principal, comme OpenThread : celui du chef s'il est
    /// parmi les serveurs, sinon le premier de `d.bbr` (de meme si le chef n'est pas encore connu).
    /// `seulementConnus` : Network Data d'une tournee precedente, pour les seuls routeurs deja dans
    /// le maillage (la liste des routeurs a pu changer depuis) ; un serveur BBR absent ne compte pas.
    public mutating func reseau(_ d: DonneesReseau, seulementConnus: Bool = false) {
        func pris(_ rloc: UInt16) -> Bool { !seulementConnus || routeurs[Int(rloc >> 10)] != nil }
        for rloc in d.routeursDeBordure where pris(rloc) {
            routeurs[Int(rloc >> 10), default: RouteurMaillage(id: Int(rloc >> 10))].bordure = true
        }
        let chef = routeurs.values.first(where: \.chef)?.rloc16
        let serveurs = d.bbr.filter(pris)
        if let principal = serveurs.first(where: { $0 == chef }) ?? serveurs.first {
            routeurs[Int(principal >> 10), default: RouteurMaillage(id: Int(principal >> 10))].bbrPrincipal = true
        }
    }

    /// Reponse d'un routeur : identite, version, ses liens (Route64) et ses enfants (Child Table).
    public mutating func reponse(_ r: ReponseDiagnostic, routeur id: Int) {
        var routeur = routeurs[id, default: RouteurMaillage(id: id)]
        routeur.extMac = r.extMac ?? routeur.extMac
        routeur.version = r.version ?? routeur.version
        routeur.muet = false
        routeurs[id] = routeur
        for route in r.route64?.routes ?? [] where route.idRouteur != id {
            if routeurs[route.idRouteur] == nil { routeurs[route.idRouteur] = RouteurMaillage(id: route.idRouteur) }
            guard route.estVoisin else { continue }
            lien(id, route.idRouteur, sortante: route.qualiteSortante, entrante: route.qualiteEntrante, source: .diagnostic,
                 date: date)
        }
        for e in r.enfants ?? [] {
            enfant(EnfantMaillage(rloc16: e.rloc16(parent: routeur.rloc16), qualite: e.qualite, delai: e.delai,
                                  endormi: e.mode.endormi, source: .tableEnfants))
        }
    }

    /// Annonce d'un routeur que la sonde a entendue (`annonces`), datee de son age : le routeur est entendu, et sa
    /// Route64, s'il y en a une, donne ses liens avec les routeurs du maillage, dans les deux sens (spec de la sonde
    /// tout-en-un, section 2.1). Ni le routeur ni ses voisins ne sont ajoutes : une annonce d'un routeur hors de la
    /// liste des routeurs est ecartee, comme un voisin qui n'y est pas.
    public mutating func ecoute(_ r: Route64?, routeur id: Int, date: Date) {
        guard var routeur = routeurs[id] else { return }
        routeur.entendu = max(routeur.entendu ?? date, date)
        routeurs[id] = routeur
        for route in r?.routes ?? [] where route.idRouteur != id && route.estVoisin && routeurs[route.idRouteur] != nil {
            lien(id, route.idRouteur, sortante: route.qualiteSortante, entrante: route.qualiteEntrante, source: .ecoute,
                 date: date)
        }
    }

    /// La sonde a rendu ses annonces a cette tournee : un routeur sans `entendu` n'a pas ete entendu (couverture).
    public mutating func annoncesRecues() {
        annoncesLues = true
    }

    /// ExtMac apprise ailleurs (parent de la sonde, table des routeurs, tournee precedente) : pour
    /// un routeur qui ne la donne pas lui-meme, muet ou dont la reponse n'a pas l'ExtMac. Ne
    /// remplace jamais celle qu'il a donnee.
    public mutating func identite(_ ext: String, routeur id: Int) {
        var r = routeurs[id, default: RouteurMaillage(id: id)]
        r.extMac = r.extMac ?? ext
        routeurs[id] = r
    }

    public mutating func pile(_ p: String?, routeur id: Int) {
        routeurs[id, default: RouteurMaillage(id: id)].pile = p
    }

    /// Routeur qui n'a pas repondu.
    public mutating func muet(_ id: Int) {
        routeurs[id, default: RouteurMaillage(id: id)].muet = true
    }

    /// Enfant trouve (table, resolution, sonde) ; complete celui qui est deja connu.
    public mutating func enfant(_ e: EnfantMaillage) {
        guard var connu = enfants[e.rloc16] else {
            enfants[e.rloc16] = e
            return
        }
        connu.extMac = connu.extMac ?? e.extMac
        connu.qualite = connu.qualite ?? e.qualite
        connu.delai = connu.delai ?? e.delai
        connu.endormi = connu.endormi ?? e.endormi
        connu.resolu = connu.resolu ?? e.resolu
        connu.echecs = connu.echecs ?? e.echecs
        if connu.adresses.isEmpty { connu.adresses = e.adresses }
        if e.source == .sonde { connu.source = .sonde }
        enfants[e.rloc16] = connu
    }

    /// Signal d'un routeur entendu par la sonde ; le dernier donne pour un routeur l'emporte. Un
    /// RSSI positif ou nul est ignore (127 : RSSI invalide d'OpenThread, rien d'entendu encore).
    public mutating func signal(_ s: SignalSonde) {
        guard s.rssi < 0 else { return }
        signaux[s.routeur] = s
    }

    /// Roles poses a la main (maillage de demo).
    mutating func marquer(_ id: Int, bordure: Bool, bbrPrincipal: Bool = false) {
        var r = routeurs[id, default: RouteurMaillage(id: id)]
        r.bordure = bordure
        r.bbrPrincipal = bbrPrincipal
        routeurs[id] = r
    }

    /// Lien vu par `de` : qualite sortante (de -> vers) et entrante (vers -> de), mesurees a `date` par `source`.
    /// Un lien est souvent lu aux deux bouts (chaque routeur qui repond le voit dans sa Route64, chaque annonce
    /// entendue aussi). Les rapports ne sont pas fusionnes : chaque sens prend la mesure la plus recente (spec de la
    /// sonde tout-en-un, section 2.1), ni moyenne, ni meilleure, ni pire valeur ; a date egale, le diagnostic
    /// l'emporte sur l'ecoute, et entre deux mesures de meme source la derniere appliquee ; sans date (maillage de
    /// demo), la derniere appliquee. Le diagnostic d'une tournee est date de son debut, et la tournee applique les
    /// reponses par identifiant croissant : quand les deux bouts repondent, celui de plus grand identifiant decide,
    /// pour les deux sens. Un lien lu par un seul bout garde ses deux sens, ranges de `a` vers `b` (le plus petit
    /// identifiant d'abord). Une entree de Route64 sans qualite (pas voisin, `estVoisin` faux) n'est pas
    /// appliquee : elle ne remplace pas le rapport de l'autre bout.
    mutating func lien(_ de: Int, _ vers: Int, sortante: Int, entrante: Int, source: SourceLien? = nil, date: Date? = nil) {
        let (a, b) = (min(de, vers), max(de, vers))
        var l = liens[a * 64 + b] ?? LienRadio(a: a, b: b)
        let (ab, ba) = de == a ? (sortante, entrante) : (entrante, sortante)
        if Self.remplace(l.qualiteAB, l.sourceAB, l.dateAB, par: source, date) {
            l.qualiteAB = ab
            l.sourceAB = source
            l.dateAB = date
        }
        if Self.remplace(l.qualiteBA, l.sourceBA, l.dateBA, par: source, date) {
            l.qualiteBA = ba
            l.sourceBA = source
            l.dateBA = date
        }
        liens[a * 64 + b] = l
    }

    /// Une mesure (`source`, `date`) remplace celle d'un sens : sens inconnu, ou l'une sans date ; sinon la plus recente,
    /// et a date egale toujours, sauf l'ecoute devant le diagnostic.
    static func remplace(_ qualite: Int?, _ ancienne: SourceLien?, _ quand: Date?, par source: SourceLien?,
                         _ date: Date?) -> Bool {
        guard qualite != nil, let quand, let date else { return true }
        if date != quand { return date > quand }
        return !(ancienne == .diagnostic && source == .ecoute)
    }

    /// Enfants des tables encore sans ExtMac, par RLOC16 : a identifier (la sonde exceptee ; un enfant resolu, dont le
    /// RLOC16 peut etre invente, aussi).
    public var enfantsSansIdentite: [UInt16] {
        enfants.values.filter { $0.extMac == nil && $0.source != .sonde && $0.source != .resolution }.map(\.rloc16).sorted()
    }

    /// Le maillage ; les signaux des seuls routeurs de la liste.
    public func maillage() -> Maillage {
        var m = Maillage(date: date, partition: partition,
                         routeurs: routeurs.values.sorted { $0.id < $1.id },
                         liens: liens.values.sorted { ($0.a, $0.b) < ($1.a, $1.b) },
                         enfants: enfants.values.sorted { $0.rloc16 < $1.rloc16 },
                         signaux: signaux.values.filter { routeurs[$0.routeur] != nil }.sorted { $0.routeur < $1.routeur })
        m.annoncesLues = annoncesLues
        return m
    }
}
