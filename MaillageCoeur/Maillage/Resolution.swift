import Foundation

/// Appareil Matter ou HomeKit sur Thread que l'app connait, a resoudre par la sonde (spec de la sonde tout-en-un,
/// section 2.2) : son adresse sur le prefixe OMR de sa partition.
public struct AppareilAResoudre: Hashable, Sendable {
    /// Identifiant de l'appareil dans l'instantane : son hote, l'ExtMac d'un appareil Matter.
    public let id: String
    public let partition: String
    /// Son adresse sur le prefixe OMR de sa partition, sans zone (`AdresseIPv6`) : la sonde n'accepte que l'adresse nue.
    public let adresse: AdresseIPv6
    /// Date du dernier releve ou l'appareil annoncait cette adresse, pour un appareil qui ne l'annonce plus (sans
    /// adresse, disparu) ; nil pour un appareil qui l'annonce.
    public let derniereAnnonce: Date?
    /// Vrai pour un disparu (plus aucune instance Bonjour), faux pour un appareil sans adresse.
    public let disparu: Bool

    public init(id: String, partition: String, adresse: AdresseIPv6, derniereAnnonce: Date? = nil,
                disparu: Bool = false) {
        self.id = id
        self.partition = partition
        self.adresse = adresse
        self.derniereAnnonce = derniereAnnonce
        self.disparu = disparu
    }

    /// Un disparu dont la derniere annonce date de plus de `Tournee.ageMaxDisparu` : la sonde ne le cherche plus.
    func perduDepuisTropLongtemps(a maintenant: Date) -> Bool {
        guard disparu, let annonce = derniereAnnonce else { return false }
        return maintenant.timeIntervalSince(annonce) > Tournee.ageMaxDisparu
    }

    /// Un appareil qui n'annonce plus d'adresse, perdue depuis au plus `Tournee.periodeRedemande`, dont la resolution
    /// connue (`resolution`, nil si aucune) ne prouve pas qu'il est la depuis sa derniere annonce (`prouve(apres:)` :
    /// posterieure ET repondue) : a redemander a chaque tournee. Faux pour un appareil qui annonce son adresse.
    func aRedemander(a maintenant: Date, resolution: ResolutionAppareil?) -> Bool {
        guard let annonce = derniereAnnonce, maintenant.timeIntervalSince(annonce) <= Tournee.periodeRedemande else {
            return false
        }
        return !(resolution?.prouve(apres: annonce) ?? false)
    }

    /// Les appareils Thread d'un instantane qui ont une partition et une adresse sur son prefixe OMR, par identifiant.
    /// La tournee garde ceux de la partition de la sonde : la resolution ne traverse pas les partitions.
    public static func depuis(_ i: Instantane) -> [AppareilAResoudre] {
        i.appareils.compactMap { a in
            guard let p = a.partition, let adresse = a.adresseOMR else { return nil }
            return AppareilAResoudre(id: a.id, partition: p, adresse: adresse)
        }.sorted { $0.id < $1.id }
    }

    /// Ceux de l'instantane du suivi (`depuis(_:)`), puis les appareils qui n'annoncent plus d'adresse (sans adresse)
    /// ou plus rien (disparus), avec leur derniere adresse sur le prefixe OMR, la partition qui porte aujourd'hui ce
    /// prefixe (`Suivi.partitionActuelle`) et la date de leur derniere annonce (`Suivi.dernieresAnnonces`) : la sonde
    /// verifie s'ils sont toujours la. Un appareil dont l'une manque n'est pas demande, ni celui dont la derniere
    /// adresse est annoncee aujourd'hui par un autre identifiant (`Suivi.adresseAnnonceeParUnAutre`) : le meme
    /// appareil sous un nouvel hote, pas un doublon joignable. Par identifiant ; aucun sans instantane.
    public static func depuis(_ s: Suivi) -> [AppareilAResoudre] {
        guard let i = s.instantane else { return [] }
        let annoncent = depuis(i)
        let deja = Set(annoncent.map(\.id))
        let muets = i.appareils.filter { $0.genre == .sansAdresse }.map(\.id) + Array(s.disparus.keys)
        let verifies = Set(muets).subtracting(deja).compactMap { id -> AppareilAResoudre? in
            guard let p = s.partitionActuelle(de: id), let adresse = s.dernieresAdresses[id],
                  let annonce = s.dernieresAnnonces[id], !s.adresseAnnonceeParUnAutre(id) else { return nil }
            return AppareilAResoudre(id: id, partition: p, adresse: adresse, derniereAnnonce: annonce,
                                     disparu: s.disparus[id] != nil)
        }
        return (annoncent + verifies).sorted { $0.id < $1.id }
    }
}

extension Appareil {
    /// Son adresse sur le prefixe OMR de sa partition (appareil Thread place dans une partition) ; nil sinon.
    public var adresseOMR: AdresseIPv6? {
        guard genre == .thread, partition != nil, let prefixe else { return nil }
        return adresses.first(where: prefixe.contient)
    }
}

/// Parent d'un appareil trouve par la resolution d'adresse (spec de la sonde tout-en-un, section 2.2), garde en memoire
/// de la tournee jusqu'a la resolution complete suivante (30 min).
public struct ResolutionAppareil: Hashable, Sendable {
    /// RLOC16 rendu par la sonde : celui du parent (un routeur Apple repond pour son enfant avec le sien), ou celui de
    /// l'enfant (un routeur tiers repond avec celui de l'enfant).
    public let rloc16: UInt16
    /// ML-EID de l'appareil, quand le cache de la sonde le donne : ses compteurs MAC se demandent la (le diagnostic
    /// n'est accepte que sur les adresses internes du reseau). Jamais dans l'historique.
    public let mleid: AdresseIPv6?
    /// L'adresse resolue (sur le prefixe OMR de la partition).
    public let adresse: AdresseIPv6
    public let date: Date
    /// Taux d'acces au canal refuses tire des compteurs MAC a cette resolution (`AccesCanal`), a titre d'information :
    /// il ne donne pas de qualite ; nil : pas de taux.
    public var echecs: Double?
    /// L'appareil a repondu a la sonde a cette resolution (`ResultatResolution.repondu`) : vrai, il est la ; faux, seul
    /// le cache d'adresses de la sonde l'a donne ; nil, firmware ancien qui ne le dit pas.
    public let repondu: Bool?

    public init(rloc16: UInt16, mleid: AdresseIPv6?, adresse: AdresseIPv6, date: Date, echecs: Double? = nil,
                repondu: Bool? = nil) {
        self.rloc16 = rloc16
        self.mleid = mleid
        self.adresse = adresse
        self.date = date
        self.echecs = echecs
        self.repondu = repondu
    }

    /// Cette resolution prouve que l'appareil est la apres la perte de son annonce `annonce` : l'appareil a repondu
    /// (`repondu == true`) dans une resolution strictement posterieure. Un cache seul (faux) ou un firmware ancien
    /// (nil) ne prouve rien.
    public func prouve(apres annonce: Date) -> Bool { repondu == true && date > annonce }

    /// Identifiant de routeur du parent : le RLOC16 rendu, sans ses 10 bits de poids faible.
    public var parent: Int { Int(rloc16 >> 10) }
}
