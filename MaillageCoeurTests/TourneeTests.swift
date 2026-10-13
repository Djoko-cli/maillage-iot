import Foundation
import Synchronization
import Testing
@testable import MaillageCoeur

/// Avancements recus d'une tournee, dans l'ordre.
final class ReleveAvancement: Sendable {
    private let liste = Mutex<[AvancementTournee]>([])

    func noter(_ a: AvancementTournee) {
        liste.withLock { $0.append(a) }
    }

    var avancements: [AvancementTournee] { liste.withLock { $0 } }

    /// Etapes dans l'ordre ou elles commencent (une etape revenue apres une autre y serait deux fois).
    var etapes: [AvancementTournee.Etape] {
        avancements.map(\.etape).reduce(into: []) { if $0.last != $1 { $0.append($1) } }
    }

    func de(_ e: AvancementTournee.Etape) -> [AvancementTournee] { avancements.filter { $0.etape == e } }

    /// Compteurs croissants : `fait` monte de 0 ou 1 a chaque appel, le total ne baisse jamais.
    static func croissants(_ a: [AvancementTournee]) -> Bool {
        zip(a, a.dropFirst()).allSatisfy { p, s in (0...1).contains(s.fait - p.fait) && s.total >= p.total }
    }
}

/// Sonde rejouee : repond avec les TLV de la capture, echoue en `delai` pour le reste (ou en
/// `trop_long`, reponse de plus de 1100 octets par le reseau, pour `tropLongs` ; ou refuse la
/// requete, pour `refus`), et note ses requetes. Depuis le firmware 1.1.0 : ses annonces, et ses
/// resolutions (`introuvable` pour une adresse qu'elle ne connait pas).
struct SondeRejouee: InterlocuteurSonde {
    actor Registre {
        /// Requetes `diag`, "<cible>|<tlv,...>", et `resoudre`, "<adresse>|resoudre".
        var requetes: [String] = []
        /// Demandes de la table des routeurs (`routeurs`).
        var tables = 0
        /// Demandes des voisins (`voisins`).
        var voisins = 0
        /// Demandes des routeurs entendus (`annonces`).
        var annonces = 0
        func noter(_ r: String) { requetes.append(r) }
        func noterTable() { tables += 1 }
        func noterVoisins() { voisins += 1 }
        func noterAnnonces() { annonces += 1 }
    }

    /// La sonde ne rend pas sa table (firmware sans `routeurs`, verrou d'OpenThread refuse).
    struct SansTable: Error {}
    /// La sonde ne rend pas ses voisins (verrou d'OpenThread refuse, liste trop longue).
    struct SansVoisins: Error {}
    /// La sonde ne rend pas ses annonces (firmware 1.0.x).
    struct SansAnnonces: Error {}

    let etatSonde: EtatSonde
    /// "<cible>|<tlv,...>" -> TLV hexa.
    let reponses: [String: String]
    /// Table des routeurs de la sonde ; nil : elle ne la rend pas.
    var table: [RouteurSonde]? = []
    /// "<cible>|<tlv,...>" dont la reponse est trop longue pour le reseau.
    var tropLongs: Set<String> = []
    /// Refus de la sonde (`occupee`, `suspendue`...) d'une requete "<cible>|<tlv,...>" : elle ne
    /// part pas ; nil : pas de refus.
    var refus: @Sendable (String) -> String? = { _ in nil }
    /// "<cible>|<tlv,...>" dont la reponse arrive plus tard ; les autres reviennent aussitot.
    var retards: [String: Duration] = [:]
    /// Routeurs voisins que la sonde entend ; nil : elle ne rend pas la liste.
    var listeVoisins: [VoisinSonde]? = []
    /// Routeurs dont la sonde entend les annonces ; nil : elle ne les rend pas (firmware 1.0.x).
    var listeAnnonces: [AnnonceSonde]? = []
    /// Resolutions, par adresse (sa forme courte) ; une autre adresse : `introuvable`.
    var resolutions: [String: ResultatResolution] = [:]
    let registre = Registre()

    /// Cle d'une requete : "<cible>|<tlv,...>".
    static func cle(_ cible: UInt16, _ tlv: [UInt8]) -> String {
        String(format: "%04X|", cible) + tlv.map(String.init).joined(separator: ",")
    }

    /// Cle d'une requete vers une adresse : "<adresse>|<tlv,...>".
    static func cle(_ adresse: AdresseIPv6, _ tlv: [UInt8]) -> String {
        "\(adresse)|" + tlv.map(String.init).joined(separator: ",")
    }

    /// Cle d'une resolution : "<adresse>|resoudre".
    static func cleResolution(_ adresse: AdresseIPv6) -> String { "\(adresse)|resoudre" }

    func etat() async throws -> EtatSonde { etatSonde }

    func routeurs() async throws -> [RouteurSonde] {
        await registre.noterTable()
        guard let table else { throw SansTable() }
        return table
    }

    func voisins() async throws -> [VoisinSonde] {
        await registre.noterVoisins()
        guard let listeVoisins else { throw SansVoisins() }
        return listeVoisins
    }

    func annonces() async throws -> [AnnonceSonde] {
        await registre.noterAnnonces()
        guard let listeAnnonces else { throw SansAnnonces() }
        return listeAnnonces
    }

    func diag(adresse: AdresseIPv6, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag {
        let cle = Self.cle(adresse, tlv)
        await registre.noter(cle)
        if let e = refus(cle) { return ResultatDiag(id: 0, cible: "\(adresse)", ok: false, erreur: e) }
        guard let t = reponses[cle] else {
            return ResultatDiag(id: 0, cible: "\(adresse)", ok: false, ms: delaiMs, erreur: "delai")
        }
        return ResultatDiag(id: 0, cible: "\(adresse)", ok: true, ms: 900, code: "2.04", tlv: t)
    }

    func resoudre(_ adresse: AdresseIPv6) async throws -> ResultatResolution {
        let cle = Self.cleResolution(adresse)
        await registre.noter(cle)
        if let e = refus(cle) { return ResultatResolution(id: 0, cible: "\(adresse)", ok: false, erreur: e) }
        return resolutions["\(adresse)"] ?? ResultatResolution(id: 0, cible: "\(adresse)", ok: false, erreur: "introuvable")
    }

    /// Table des 7 routeurs de la capture, telle qu'une sonde en FED la donne : tous par leur
    /// RLOC16 ; l'ExtMac des seuls routeurs `entendus` (RLOC16 -> ExtMac inventee).
    static func table(entendus: [UInt16: String] = [:]) -> [RouteurSonde] {
        [0x0400, 0x5000, 0x6000, 0xAC00, 0xB400, 0xCC00, 0xE400].map { (r: UInt16) in
            let ext = entendus[r]
            return RouteurSonde(id: Int(r >> 10), rloc16: String(format: "%04X", r), ext: ext, lqIn: ext == nil ? 0 : 3,
                                lqOut: ext == nil ? 0 : 3, age: 4, lien: ext != nil)
        }
    }

    func diag(_ cible: UInt16, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag {
        let cle = Self.cle(cible, tlv)
        await registre.noter(cle)
        if let e = refus(cle) {
            return ResultatDiag(id: 0, cible: String(format: "%04X", cible), ok: false, erreur: e)
        }
        if let d = retards[cle] { try await Task.sleep(for: d) }
        if tropLongs.contains(cle) {
            return ResultatDiag(id: 0, cible: String(format: "%04X", cible), ok: false, erreur: "trop_long")
        }
        guard let t = reponses[cle] else {
            return ResultatDiag(id: 0, cible: String(format: "%04X", cible), ok: false, ms: delaiMs, erreur: "delai")
        }
        return ResultatDiag(id: 0, cible: String(format: "%04X", cible), ok: true, ms: 50, code: "2.04", tlv: t)
    }

    /// Etat de la capture apres le changement de parent : AC09, enfant de AC00 (muet), qu'elle entend
    /// a -89 dBm ; `ext` : l'ExtMac de la sonde (absente de la capture) ; `table` : celle des routeurs
    /// de la sonde, sans ExtMac par defaut (la capture vient d'une sonde en MED) ; `voisins` : aucun par
    /// defaut (la capture n'en a pas).
    static func capture(chef: Int = 24, ext: String? = nil, reponsesEnPlus: [String: String] = [:],
                        table: [RouteurSonde]? = SondeRejouee.table(), tropLongs: Set<String> = [],
                        voisins: [VoisinSonde]? = [], annonces: [AnnonceSonde]? = [],
                        resolutions: [String: ResultatResolution] = [:]) throws -> SondeRejouee {
        let champExt = ext.map { #","ext":"\#($0)""# } ?? ""
        let base = #"{"v":1,"t":"etat","role":"child","rloc16":"AC09"\#(champExt),"mode":"rn","parent":{"rloc16":"AC00","ext":"E000000000000007","lqIn":3,"lqOut":3,"rssi":-89},"partition":"46CBEBCD","chef":\#(chef),"canal":25,"prefixeMaille":"FD00111122220C87","xp":"A0A1A2A3A4A5A6A7","suspendue":false}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(base.utf8)) else { throw CaptureSonde.ErreurCapture(id: 0) }
        var r: [String: String] = [
            "6000|5,6": try CaptureSonde.tlv(204),
            "5000|0,1,5,16,8,24": try CaptureSonde.tlv(104),
            "6000|0,1,5,16,8,24": try CaptureSonde.tlv(106),
            "5000|25,26,27,28": try CaptureSonde.tlv(105),
            "6000|25,26,27,28": try CaptureSonde.tlv(107),
            "5000|7": try CaptureSonde.tlv(206),
            "AC01|0,1,2,8": try CaptureSonde.tlv(411),
            "5004|0,8": try CaptureSonde.tlv(116),
            "5001|0,8": try CaptureSonde.tlv(117),
            "6003|0,8": try CaptureSonde.tlv(118),
        ]
        for (n, id) in zip(3...8, 503...508) { r[String(format: "AC%02X|0,1,2,8", n)] = try CaptureSonde.tlv(id) }
        r.merge(reponsesEnPlus) { _, b in b }
        return SondeRejouee(etatSonde: e, reponses: r, table: table, tropLongs: tropLongs, listeVoisins: voisins,
                            listeAnnonces: annonces, resolutions: resolutions)
    }

    /// La meme sonde, avec seulement les reponses dont la cle est gardee ; registre neuf.
    func filtree(_ garder: (String) -> Bool) -> SondeRejouee {
        SondeRejouee(etatSonde: etatSonde, reponses: reponses.filter { garder($0.key) }, table: table, tropLongs: tropLongs,
                     refus: refus, retards: retards, listeVoisins: listeVoisins, listeAnnonces: listeAnnonces,
                     resolutions: resolutions)
    }

    /// La meme sonde, qui refuse (`erreur`) les requetes dont la cle est choisie ; registre neuf.
    func refusant(_ erreur: String = "occupee", _ choisies: @escaping @Sendable (String) -> Bool) -> SondeRejouee {
        SondeRejouee(etatSonde: etatSonde, reponses: reponses, table: table, tropLongs: tropLongs,
                     refus: { choisies($0) ? erreur : nil }, retards: retards, listeVoisins: listeVoisins,
                     listeAnnonces: listeAnnonces, resolutions: resolutions)
    }
}

/// Sonde dont la liaison se ferme a une requete "<cible>|<tlv,...>" : `diag` y echoue par une
/// erreur, comme `SondeUSB` une fois la liaison fermee.
struct SondeFermee: InterlocuteurSonde {
    struct Fermee: Error {}

    let base: SondeRejouee
    let sur: String

    func etat() async throws -> EtatSonde { try await base.etat() }
    func routeurs() async throws -> [RouteurSonde] { try await base.routeurs() }
    func voisins() async throws -> [VoisinSonde] { try await base.voisins() }
    func annonces() async throws -> [AnnonceSonde] { try await base.annonces() }

    func diag(_ cible: UInt16, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag {
        if SondeRejouee.cle(cible, tlv) == sur { throw Fermee() }
        return try await base.diag(cible, tlv, delaiMs: delaiMs)
    }

    func diag(adresse: AdresseIPv6, _ tlv: [UInt8], delaiMs: Int) async throws -> ResultatDiag {
        if SondeRejouee.cle(adresse, tlv) == sur { throw Fermee() }
        return try await base.diag(adresse: adresse, tlv, delaiMs: delaiMs)
    }

    func resoudre(_ adresse: AdresseIPv6) async throws -> ResultatResolution {
        if SondeRejouee.cleResolution(adresse) == sur { throw Fermee() }
        return try await base.resoudre(adresse)
    }
}

/// Requetes en vol pendant un essai de `parallele` : le maximum atteint, et les requetes parties
/// que la requete retenue a vues a sa sortie.
actor EnVol {
    private(set) var enVol = 0
    private(set) var maximum = 0
    private(set) var parties = 0
    private(set) var vues: Int?

    func partir() {
        enVol += 1
        parties += 1
        maximum = max(maximum, enVol)
    }

    func revenir() { enVol -= 1 }

    /// Retient la requete jusqu'a ce que `n` soient parties (2 s au plus) ; note celles qu'elle a vues.
    func retenir(jusqua n: Int) async {
        var essais = 0
        while parties < n && essais < 400 {
            try? await Task.sleep(for: .milliseconds(5))
            essais += 1
        }
        vues = parties
    }
}

extension Tournee {
    /// Tournee qui doit rendre un maillage (tests) : le maillage et la memoire ; nil sans maillage.
    static func complete(_ sonde: some InterlocuteurSonde, memoire: MemoireTournee, maintenant: Date,
                         appareils: [AppareilAResoudre] = [], avancement: (@Sendable (AvancementTournee) -> Void)? = nil)
        async throws -> (maillage: Maillage, memoire: MemoireTournee)? {
        let r = try await executer(sonde, memoire: memoire, maintenant: maintenant, appareils: appareils,
                                   avancement: avancement)
        return r.maillage.map { ($0, r.memoire) }
    }
}

@Suite("Tournee de la sonde")
struct TourneeTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Identifiant de routeur de la cible d'une requete "<cible>|<tlv,...>".
    static func routeur(_ requete: String) -> Int? {
        UInt16(requete.prefix(4), radix: 16).map { Int($0 >> 10) }
    }

    // MARK: Donnees de la sonde tout-en-un (inventees)

    /// Adresse OMR inventee d'un appareil : fd00:aaaa:bbbb:1::<n>.
    static func omr(_ n: Int) -> AdresseIPv6 { AdresseIPv6("fd00:aaaa:bbbb:1::\(String(n, radix: 16))")! }

    /// Appareils de la partition de la capture, et leur adresse OMR : sous AC00 (routeur Apple, muet), resolu par son
    /// RLOC16 (0A) ; sous AC00, resolu par celui de l'enfant (0B, AC05) ; introuvable (0C) ; sous le 20, qui repond (04) ;
    /// le routeur AC00 lui-meme (07) ; la sonde (AA) ; un accessoire HomeKit, dont l'hote n'est pas l'ExtMac, sous AC00 ;
    /// puis un appareil d'une autre partition.
    static let appareils: [AppareilAResoudre] = [
        AppareilAResoudre(id: "E00000000000000A", partition: "46CBEBCD", adresse: omr(0x0A)),
        AppareilAResoudre(id: "E00000000000000B", partition: "46CBEBCD", adresse: omr(0x0B)),
        AppareilAResoudre(id: "E00000000000000C", partition: "46CBEBCD", adresse: omr(0x0C)),
        AppareilAResoudre(id: "E000000000000004", partition: "46CBEBCD", adresse: omr(0x04)),
        AppareilAResoudre(id: "E000000000000007", partition: "46CBEBCD", adresse: omr(0x07)),
        AppareilAResoudre(id: "E0000000000000AA", partition: "46CBEBCD", adresse: omr(0xAA)),
        AppareilAResoudre(id: "Prise-HomeKit", partition: "46CBEBCD", adresse: omr(0x50)),
        AppareilAResoudre(id: "E0000000000000F1", partition: "73586B68", adresse: omr(0xF1)),
    ]

    /// Les resolutions de la sonde, par adresse : le RLOC16 du parent (AC00, routeur Apple) ou de l'enfant (AC05 ;
    /// 5004 sous le 20) ; le ML-EID (fd00:1111:2222:c87::<n>) quand le cache le donne.
    static let resolutions: [String: ResultatResolution] = {
        func ok(_ n: Int, _ rloc16: String, mleid: Bool) -> (String, ResultatResolution) {
            let cible = "\(omr(n))"
            return (cible, ResultatResolution(id: 0, cible: cible, ok: true, ms: 300, rloc16: rloc16,
                                              mleid: mleid ? String(format: "FD00111122220C87%016lX", n) : nil,
                                              repondu: true))
        }
        return Dictionary(uniqueKeysWithValues: [ok(0x0A, "AC00", mleid: true), ok(0x0B, "AC05", mleid: false),
                                                 ok(0x04, "5004", mleid: true), ok(0x07, "AC00", mleid: false),
                                                 ok(0x50, "AC00", mleid: true)])
    }()

    /// ML-EID d'un appareil resolu : fd00:1111:2222:c87::<n>.
    static func mleid(_ n: Int) -> AdresseIPv6 { AdresseIPv6("fd00:1111:2222:c87::\(String(n, radix: 16))")! }

    /// Requete des compteurs MAC d'un enfant, a son ML-EID.
    static func cleCompteurs(_ n: Int) -> String { SondeRejouee.cle(mleid(n), Tournee.tlvCompteurs) }

    /// TLV 9 (hexa) : `envois` trames unicast envoyees, dont `echecs` en echec.
    static func compteurs(envois: UInt32, echecs: UInt32) -> String {
        let c: [UInt32] = [0, 0, echecs, 500, 20, 0, envois, 12, 0]
        return Data([TypeTLV.compteursMac, 36] + c.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)) } }).hexa
    }

    /// La sonde de la capture, la sonde ayant pour ExtMac E0000000000000AA, avec ses resolutions.
    static func sondeResolue(reponsesEnPlus: [String: String] = [:], annonces: [AnnonceSonde]? = [],
                             resolutions: [String: ResultatResolution] = TourneeTests.resolutions) throws -> SondeRejouee {
        try SondeRejouee.capture(ext: "E0000000000000AA", reponsesEnPlus: reponsesEnPlus, annonces: annonces,
                                 resolutions: resolutions)
    }

    /// Annonce entendue d'un routeur de la capture, de la partition de la capture sauf `partition` ; Route64 des 7
    /// routeurs, avec les liens de `qualites` (sortante et entrante, vues par lui).
    static func annonce(_ rloc16: String, _ ext: String, qualites: [Int: (sortante: Int, entrante: Int)], age: Int,
                        partition: String = "46CBEBCD") -> AnnonceSonde {
        let route = String(Self.route64([1, 20, 24, 43, 45, 51, 57], qualites: qualites).dropFirst(4))
        return AnnonceSonde(rloc16: rloc16, ext: ext, partition: partition, route64: route, seq: 1, rssi: -70, rssiMin: -80,
                            rssiMax: -60, nb: 4, ageS: age)
    }

    /// Premiere tournee : routeurs, roles, liens, enfants des tables, memoire ; aucun appareil a resoudre.
    @Test func premiere() async throws {
        let sonde = try SondeRejouee.capture()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.partition == "46CBEBCD")
        #expect(m.routeurs.map(\.id) == [1, 20, 24, 43, 45, 51, 57])
        #expect(m.chef?.id == 24)
        #expect(m.routeurs.filter(\.muet).map(\.id) == [1, 43, 45, 51, 57])
        #expect(m.routeurs.filter(\.bordure).map(\.id) == [1, 43, 45, 51, 57])
        #expect(m.routeur(45)?.bbrPrincipal == true)
        #expect(m.routeur(43)?.extMac == "E000000000000007", "parent de la sonde")
        #expect(m.routeur(20)?.pile?.hasPrefix("SL-OPENTHREAD") == true)
        #expect(m.liens.count == 7)
        #expect(m.enfants(de: 43).map(\.rloc16) == [0xAC09], "la sonde ; sans appareil a resoudre, aucun enfant resolu")
        #expect(m.enfants(de: 43).last?.source == .sonde)
        #expect(m.enfants.count == 7)
        let de20 = m.enfants(de: 20)
        #expect(de20.map(\.extMac) == ["E000000000000005", "E000000000000004"], "tables : identifies une fois")
        #expect(de20.first?.adresses.count == 4)
        #expect(m.enfants(de: 24).filter { $0.extMac == nil }.map(\.rloc16) == [0x6002, 0x6005, 0x6006], "sans reponse")
        #expect(mem.echecs[43] == 1)
        #expect(!mem.estMuet(43), "muet a partir de 2 echecs de suite")
        #expect(mem.repondants == [20, 24])
        #expect(mem.identites[0xAC00] == "E000000000000007")
        #expect(mem.identites[0x5000] == "E000000000000002")
        #expect(mem.derniereResolution == Self.t0, "une resolution complete, sans appareil")
        #expect(m.resolution == Self.t0, "le maillage dit de quelle resolution viennent ses enfants resolus")
        #expect(m.annoncesLues && m.couverture == CouvertureEcoute(entendus: 0, routeurs: 7), "rien d'entendu")
        let requetes = await sonde.registre.requetes
        #expect(!requetes.contains { $0.hasSuffix("|resoudre") })
        #expect(requetes.filter { $0.hasSuffix("|25,26,27,28") }.count == 2)
        #expect(requetes.filter { $0.hasSuffix("|0,8") }.count == 6, "les 6 enfants des tables")
        #expect(mem.identifies.count == 3)
    }

    /// Deuxieme tournee (5 min) : les muets le deviennent ; pas de nouvelle resolution ;
    /// pile deja connue ; les enfants des tables sans reponse attendent 30 min.
    /// Troisieme (10 min) : les muets ne sont plus interroges.
    @Test func suivantes() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let avant2 = await sonde.registre.requetes.count
        let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300))
        let requetes2 = await sonde.registre.requetes.dropFirst(avant2)
        #expect(requetes2.count == 9, "chef, 7 routeurs, Network Data ; pas 6002, 6005, 6006, demandes il y a 5 min")
        #expect(mem2.estMuet(43))
        #expect(mem2.muetInterroge[43] == Self.t0 + 300)
        #expect(m2.enfants(de: 43).count == 1, "la sonde")
        #expect(m2.resolution == Self.t0, "pas de nouvelle resolution : celle de la premiere tournee")

        let avant3 = await sonde.registre.requetes.count
        let (m3, _) = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 600))
        let requetes3 = Array(await sonde.registre.requetes.dropFirst(avant3))
        #expect(requetes3.first == "6000|5,6", "la liste des routeurs d'abord")
        #expect(requetes3.sorted() == ["5000|0,1,5,16,8,24", "5000|7", "6000|0,1,5,16,8,24", "6000|5,6"],
                "en parallele : dans le desordre")
        #expect(m3.routeurs.filter(\.muet).map(\.id) == [1, 43, 45, 51, 57])
        #expect(m3.enfants.count == 7)
        #expect(m3.resolution == Self.t0)
    }

    /// Resolution de nouveau apres 30 min, et les 6 identites des enfants des tables redemandees
    /// parce que 30 min ont passe ; une seconde avant, ni l'une ni les autres.
    @Test func resolutionDue() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        let avant = await sonde.registre.requetes.count
        let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 1799,
                                                                appareils: Self.appareils))
        let pendant = await sonde.registre.requetes.count
        let (m3, _) = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 1800,
                                                             appareils: Self.appareils))
        #expect(m2.resolution == Self.t0 && m3.resolution == Self.t0 + 1800, "une nouvelle resolution, une nouvelle date")
        let toutes = await sonde.registre.requetes
        let presque = toutes[avant..<pendant], requetes = toutes[pendant...]
        #expect(presque.filter { $0.hasSuffix("|resoudre") || $0.hasSuffix("|0,8") || $0.hasSuffix("|9") }.isEmpty,
                "29 min 59 s : rien de du")
        #expect(requetes.filter { $0.hasSuffix("|resoudre") }.count == 6)
        #expect(requetes.filter { $0.hasSuffix("|9") }.count == 2, "les compteurs, avec la resolution")
        #expect(requetes.filter { $0.hasSuffix("|0,8") }.count == 6, "30 min ont passe : identites redemandees")
    }

    /// Resolution des parents (spec de la sonde tout-en-un, section 2.2) : chaque appareil de la partition de la sonde,
    /// elle exceptee, sauf ceux d'une autre partition. Le parent est le RLOC16 rendu, sans ses 10 bits de poids faible.
    /// Sous AC00, muet : l'appareil resolu par le RLOC16 de AC00 recoit un numero invente (AE00, AE01 : bit 9, dans
    /// l'ordre des appareils), celui resolu par AC05 le garde ; l'accessoire HomeKit est rattache par son adresse.
    /// Ni le routeur AC00 lui-meme, ni l'appareil sous le 20 (sa table fait foi), ni l'introuvable.
    @Test func resolutionDesParents() async throws {
        let sonde = try Self.sondeResolue()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        let demandes = await sonde.registre.requetes.filter { $0.hasSuffix("|resoudre") }
        #expect(demandes.sorted() == [0x04, 0x07, 0x0A, 0x0B, 0x0C, 0x50].map { "\(Self.omr($0))|resoudre" }.sorted(),
                "ni la sonde, ni l'autre partition")
        #expect(m.enfants(de: 43).map(\.rloc16) == [0xAC05, 0xAC09, 0xAE00, 0xAE01])
        let a = try #require(m.enfants.first { $0.rloc16 == 0xAE00 })
        #expect(a.extMac == "E00000000000000A" && a.source == .resolution && a.resolu == Self.t0 && !a.rloc16Connu)
        #expect(a.adresses == [Self.omr(0x0A)] && a.qualite == nil)
        let b = try #require(m.enfants.first { $0.rloc16 == 0xAC05 })
        #expect(b.extMac == "E00000000000000B" && b.rloc16Connu)
        let h = try #require(m.enfants.first { $0.rloc16 == 0xAE01 })
        #expect(h.extMac == nil && h.adresses == [Self.omr(0x50)], "HomeKit : rapproche par son adresse")
        #expect(!m.enfants.contains { $0.extMac == "E000000000000007" }, "le routeur AC00 lui-meme")
        #expect(!m.enfants.contains { $0.adresses.contains(Self.omr(0x04)) }, "sous le 20 : sa table")
        #expect(Set(mem.resolutions.keys) == ["E00000000000000A", "E00000000000000B", "E000000000000004",
                                              "E000000000000007", "Prise-HomeKit"])
        #expect(mem.resolutions["E00000000000000A"]?.mleid == Self.mleid(0x0A))
        #expect(mem.demandes == ["E00000000000000A", "E00000000000000B", "E00000000000000C", "E000000000000004",
                                 "E000000000000007", "Prise-HomeKit"], "l'introuvable compte comme demande")
        #expect(mem.derniereResolution == Self.t0 && m.resolution == Self.t0)
        // Gardes 30 min, comme le balayage qu'elles remplacent : a 5 min, les memes enfants, sans requete.
        let avant = await sonde.registre.requetes.count
        let (m2, _) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0 + 300,
                                                              appareils: Self.appareils))
        #expect(m2.enfants(de: 43).map(\.rloc16) == [0xAC05, 0xAC09, 0xAE00, 0xAE01])
        #expect(await sonde.registre.requetes.dropFirst(avant).filter { $0.hasSuffix("|resoudre") }.isEmpty)
    }

    /// Compteurs MAC des enfants des routeurs Apple (spec de la sonde tout-en-un, section 2.3) : a chaque resolution,
    /// la TLV 9 de chaque enfant resolu sous un routeur muet qui a un ML-EID, demandee a ce ML-EID. Le taux d'acces au
    /// canal refuses entre deux releves est garde a titre d'information (0,7 %) et ne donne aucune qualite : l'enfant
    /// reste en qualite inconnue (decision du 07/10). Moins de 50 trames entre les deux, ou un compteur qui baisse
    /// (l'appareil a redemarre) : pas de taux, et le releve repart. Un enfant qui ne repond pas : rien.
    @Test func compteursDesEnfants() async throws {
        func sonde(_ envois: UInt32, _ echecs: UInt32) throws -> SondeRejouee {
            try Self.sondeResolue(reponsesEnPlus: [Self.cleCompteurs(0x0A): Self.compteurs(envois: envois, echecs: echecs)])
        }
        func enfant(_ m: Maillage) throws -> EnfantMaillage { try #require(m.enfants.first { $0.rloc16 == 0xAE00 }) }
        let s1 = try sonde(1000, 3)
        let (m1, mem1) = try #require(try await Tournee.complete(s1, memoire: MemoireTournee(), maintenant: Self.t0,
                                                                 appareils: Self.appareils))
        #expect(await s1.registre.requetes.filter { $0.hasSuffix("|9") }.sorted() == [Self.cleCompteurs(0x0A), Self.cleCompteurs(0x50)].sorted(),
                "les deux enfants de AC00 qui ont un ML-EID")
        #expect(try enfant(m1).qualite == nil, "un seul releve")
        #expect(mem1.compteurs["E00000000000000A"]?.unicastEmis == 1000)
        #expect(mem1.compteurs["Prise-HomeKit"] == nil, "muet : rien")
        let (m2, mem2) = try #require(try await Tournee.complete(try sonde(2000, 10), memoire: mem1,
                                                                 maintenant: Self.t0 + 1800, appareils: Self.appareils))
        let e2 = try enfant(m2)
        #expect(e2.qualite == nil && e2.echecs.map { abs($0 - 0.007) < 1e-12 } == true, "7 refus sur 1000 envois")
        #expect(mem2.resolutions["E00000000000000A"]?.echecs.map { abs($0 - 0.007) < 1e-12 } == true)
        let (m3, mem3) = try #require(try await Tournee.complete(try sonde(2040, 15), memoire: mem2,
                                                                 maintenant: Self.t0 + 3600, appareils: Self.appareils))
        #expect(try enfant(m3).echecs == nil && mem3.compteurs["E00000000000000A"]?.unicastEmis == 2040, "40 trames")
        let (m4, mem4) = try #require(try await Tournee.complete(try sonde(100, 0), memoire: mem3,
                                                                 maintenant: Self.t0 + 5400, appareils: Self.appareils))
        #expect(try enfant(m4).echecs == nil && mem4.compteurs["E00000000000000A"]?.unicastEmis == 100, "redemarre")
        let (m5, _) = try #require(try await Tournee.complete(try sonde(400, 20), memoire: mem4,
                                                              maintenant: Self.t0 + 7200, appareils: Self.appareils))
        let e5 = try enfant(m5)
        #expect(e5.qualite == nil && e5.echecs.map { abs($0 - 20.0 / 300) < 1e-12 } == true, "20 refus sur 300 : 6,7 %")
    }

    /// Sans annonces (firmware 1.0.x, ou la sonde ne les rend pas) : ni ecoute, ni resolution, ni compteurs ; la
    /// couverture est inconnue, la resolution reste due.
    @Test func sansAnnonces() async throws {
        let sonde = try Self.sondeResolue(annonces: nil)
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        #expect(!m.annoncesLues && m.couverture == nil)
        #expect(await !sonde.registre.requetes.contains { $0.hasSuffix("|resoudre") || $0.hasSuffix("|9") })
        #expect(mem.derniereResolution == nil && mem.resolutions.isEmpty && m.resolution == nil)
        #expect(await sonde.registre.annonces == 1)
    }

    /// Annonces entendues (spec de la sonde tout-en-un, section 2.1) : les liens entre routeurs Apple, muets au
    /// diagnostic, viennent de leur Route64, dates de l'age de l'annonce ; chaque sens garde la mesure la plus recente,
    /// et le diagnostic d'un routeur qui repond l'emporte. Chaque annonce donne l'identite de son routeur. Une annonce
    /// d'une autre partition, ou d'un enfant, est ecartee. Couverture : 3 routeurs entendus sur 7 (ExtMac inventees).
    @Test func ecouteDesAnnonces() async throws {
        let annonces = [
            Self.annonce("AC00", "E000000000000007", qualites: [1: (3, 3), 57: (2, 1)], age: 30),
            Self.annonce("E400", "E0000000000000E4", qualites: [43: (3, 3), 45: (3, 2)], age: 120),
            Self.annonce("5000", "E000000000000002", qualites: [24: (1, 1)], age: 10),
            Self.annonce("CC00", "E0000000000000CC", qualites: [57: (3, 3)], age: 5, partition: "73586B68"),
            Self.annonce("AC05", "E0000000000000D5", qualites: [43: (3, 3)], age: 5),
        ]
        let sonde = try SondeRejouee.capture(annonces: annonces)
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let l4357 = try #require(m.liens.first { $0.a == 43 && $0.b == 57 })
        #expect(l4357.qualiteAB == 2 && l4357.qualiteBA == 1, "l'annonce de 43, plus recente que celle de 57")
        #expect(l4357.sourceAB == .ecoute && l4357.dateAB == Self.t0 - 30)
        let l4557 = try #require(m.liens.first { $0.a == 45 && $0.b == 57 })
        #expect(l4557.qualiteAB == 2 && l4557.qualiteBA == 3 && l4557.dateBA == Self.t0 - 120, "connu de 57 seul")
        #expect(m.liens.first { $0.a == 1 && $0.b == 43 }?.sourceBA == .ecoute, "entre deux routeurs Apple")
        let l2024 = try #require(m.liens.first { $0.a == 20 && $0.b == 24 })
        #expect(l2024.sourceAB == .diagnostic && l2024.qualite == 3, "le diagnostic, plus recent")
        #expect(!m.liens.contains { $0.a == 51 && $0.b == 57 }, "l'annonce de l'autre partition est ecartee")
        #expect(m.routeur(43)?.entendu == Self.t0 - 30 && m.routeur(57)?.entendu == Self.t0 - 120)
        #expect(m.routeur(51)?.entendu == nil && m.routeur(1)?.entendu == nil)
        #expect(mem.identites[0xE400] == "E0000000000000E4" && mem.identites[0xCC00] == nil && mem.identites[0xAC05] == nil)
        #expect(m.routeur(57)?.extMac == "E0000000000000E4", "muet : l'identite de son annonce")
        #expect(m.couverture == CouvertureEcoute(entendus: 3, routeurs: 7))
        #expect(await sonde.registre.annonces == 1)
    }

    /// Un appareil apparait entre deux resolutions completes : il est resolu a la tournee suivante, seul, et les autres
    /// gardent la leur. Un appareil deja demande, meme introuvable, ne l'est plus avant la resolution complete suivante.
    @Test func resolutionDUnAppareilNouveau() async throws {
        let sonde = try Self.sondeResolue()
        let deux = Array(Self.appareils.prefix(2))
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: deux))
        #expect(mem1.demandes == ["E00000000000000A", "E00000000000000B"])
        let avant = await sonde.registre.requetes.count
        let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300,
                                                                appareils: Self.appareils))
        let demandees = await sonde.registre.requetes.dropFirst(avant).filter { $0.hasSuffix("|resoudre") }
        #expect(demandees.sorted() == [0x04, 0x07, 0x0C, 0x50].map { "\(Self.omr($0))|resoudre" }.sorted(), "les nouveaux seuls")
        #expect(mem2.derniereResolution == Self.t0, "pas une resolution complete")
        #expect(mem2.resolutions.count == 5 && mem2.demandes.count == 6)
        #expect(m2.enfants(de: 43).map(\.rloc16) == [0xAC05, 0xAC09, 0xAE00, 0xAE01])
        let avant3 = await sonde.registre.requetes.count
        _ = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 600, appareils: Self.appareils))
        #expect(await sonde.registre.requetes.dropFirst(avant3).filter { $0.hasSuffix("|resoudre") }.isEmpty)
    }

    /// Le parent d'un appareil resolu sort de la liste des routeurs : sa resolution est oubliee, et l'appareil est demande
    /// de nouveau aussitot, sans attendre la resolution complete suivante (30 min), comme un appareil nouveau. Sinon la
    /// tournee le compterait sans parent, et le suivi emettrait un faux « n'a plus de parent ».
    @Test func appareilResoluDeNouveauQuandSonParentSortDeLaListe() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        #expect(mem1.resolutions["E00000000000000A"]?.parent == 43 && mem1.demandes.contains("E00000000000000A"))
        let sans43 = try Self.sondeResolue(reponsesEnPlus: ["6000|5,6": Self.route64([1, 20, 24, 45, 51, 57])])
        let (_, mem2) = try #require(try await Tournee.complete(sans43, memoire: mem1, maintenant: Self.t0 + 300,
                                                               appareils: Self.appareils))
        let demandees = await sans43.registre.requetes.filter { $0.hasSuffix("|resoudre") }
        #expect(demandees.sorted() == [0x07, 0x0A, 0x0B, 0x50].map { "\(Self.omr($0))|resoudre" }.sorted(),
                "les appareils d'en dessous, demandes aussitot ; les autres gardent leur resolution")
        #expect(mem2.derniereResolution == Self.t0, "pas une resolution complete")
        #expect(mem2.demandes.contains("E00000000000000A") && mem2.demandes.contains("E00000000000000B"))
    }

    /// Chef muet : Route64 d'un routeur qui a repondu a la tournee precedente.
    @Test func chefMuet() async throws {
        let sonde = try SondeRejouee.capture(chef: 45, reponsesEnPlus: ["5000|5,6": try CaptureSonde.tlv(104)])
        var mem = MemoireTournee()
        mem.echecs[45] = 2
        mem.repondants = [20]
        let (m, _) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(m.routeurs.count == 7)
        #expect(m.chef?.id == 45)
        #expect(await sonde.registre.requetes.first == "5000|5,6")
    }

    /// Chef muet des le lancement : memoire neuve, aucun secours connu. La Route64 vient
    /// d'abord des autres routeurs de la table de la sonde, en un groupe (le 20 et le 24 la
    /// donnent) : pas de recherche sur les autres identifiants.
    @Test func chefMuetSansSecours() async throws {
        let sonde = try SondeRejouee.capture(chef: 45, reponsesEnPlus: ["5000|5,6": try CaptureSonde.tlv(104)])
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeurs.map(\.id) == [1, 20, 24, 43, 45, 51, 57])
        #expect(m.chef?.id == 45)
        let requetes = await sonde.registre.requetes.filter { $0.hasSuffix("|5,6") }
        #expect(requetes.first == "B400|5,6", "le chef d'abord")
        #expect(requetes.dropFirst().compactMap(Self.routeur).sorted() == [1, 20, 24, 43, 51, 57], "puis la table")
        #expect(mem.repondants == [20, 24])
        #expect(mem.rechercheVaine == nil)
    }

    /// Chef muet des le lancement, sans table des routeurs (firmware 1.0.1) : la Route64 vient
    /// des autres identifiants, par groupes de 8 dans l'ordre croissant ; arret au groupe du 20.
    @Test func chefMuetSansSecoursNiTable() async throws {
        let sonde = try SondeRejouee.capture(chef: 45, reponsesEnPlus: ["5000|5,6": try CaptureSonde.tlv(104)], table: nil)
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeurs.map(\.id) == [1, 20, 24, 43, 45, 51, 57])
        let ids = await sonde.registre.requetes.filter { $0.hasSuffix("|5,6") }.compactMap(Self.routeur)
        #expect(ids.first == 45, "le chef d'abord")
        #expect(ids.dropFirst().sorted() == Array(0...23), "puis 0 a 23 : arret au groupe du 20")
        #expect(mem.repondants == [20, 24])
    }

    /// Rien ne repond, sonde attachee : pas de maillage ; la memoire rendue n'a que la partition,
    /// l'identite du parent et la date de cette recherche vaine. La liste des routeurs est
    /// demandee une fois a chaque identifiant, 63 en tout : au chef, aux autres routeurs de la
    /// table de la sonde, puis aux autres identifiants.
    @Test func rienNeRepond() async throws {
        let sonde = try SondeRejouee.capture().filtree { _ in false }
        let r = try await Tournee.executer(sonde, memoire: MemoireTournee(), maintenant: Self.t0)
        #expect(r.maillage == nil)
        var attendue = MemoireTournee()
        attendue.partition = "46CBEBCD"
        attendue.identites = [0xAC00: "E000000000000007"]
        attendue.rechercheVaine = Self.t0
        #expect(r.memoire == attendue)
        let requetes = await sonde.registre.requetes
        #expect(requetes.allSatisfy { $0.hasSuffix("|5,6") })
        let ids = requetes.compactMap(Self.routeur)
        #expect(ids.count == 63 && Set(ids) == Set(0...62), "une fois chaque identifiant")
        #expect(ids.first == 24, "le chef")
        #expect(Set(ids.dropFirst().prefix(6)) == [1, 20, 43, 45, 51, 57], "puis les autres routeurs de la table")
    }

    /// Apres une recherche complete vaine, pas de nouvelle recherche complete avant 30 min : le
    /// chef et les autres routeurs de la table seulement (7 requetes au lieu de 63), et la date
    /// est gardee ; l'avancement a ce total. A 30 min, de nouveau partout.
    @Test func rechercheBorneeApresUnEchec() async throws {
        let sonde = try SondeRejouee.capture().filtree { _ in false }
        let r1 = try await Tournee.executer(sonde, memoire: MemoireTournee(), maintenant: Self.t0)
        #expect(r1.memoire.rechercheVaine == Self.t0)
        let n1 = await sonde.registre.requetes.count
        let releve = ReleveAvancement()
        let r2 = try await Tournee.executer(sonde, memoire: r1.memoire, maintenant: Self.t0 + 1799,
                                            avancement: { releve.noter($0) })
        let n2 = await sonde.registre.requetes.count
        #expect(n2 - n1 == 7, "le chef et les 6 autres routeurs de la table")
        #expect(r2.memoire.rechercheVaine == Self.t0, "date gardee")
        let liste = releve.de(.listeRouteurs)
        #expect(liste.last == AvancementTournee(etape: .listeRouteurs, fait: 7, total: 7))
        #expect(ReleveAvancement.croissants(liste))
        let r3 = try await Tournee.executer(sonde, memoire: r2.memoire, maintenant: Self.t0 + 1800)
        #expect(await sonde.registre.requetes.count - n2 == 63, "30 min apres : partout")
        #expect(r3.memoire.rechercheVaine == Self.t0 + 1800)
    }

    /// Recherche dont la sonde refuse toutes les requetes (`occupee`) : ce n'est pas un echec, la
    /// suivante cherche de nouveau partout. Sans table ni secours, dans les 30 min d'une recherche
    /// vaine : le chef seul.
    @Test func rechercheRefuseeOuSansTable() async throws {
        let refusee = try SondeRejouee.capture().filtree { _ in false }.refusant { _ in true }
        let r = try await Tournee.executer(refusee, memoire: MemoireTournee(), maintenant: Self.t0)
        #expect(await refusee.registre.requetes.count == 63)
        #expect(r.memoire.rechercheVaine == nil)

        let sansTable = try SondeRejouee.capture(table: nil).filtree { _ in false }
        var mem = MemoireTournee()
        mem.partition = "46CBEBCD"
        mem.rechercheVaine = Self.t0
        let r2 = try await Tournee.executer(sansTable, memoire: mem, maintenant: Self.t0 + 300)
        #expect(r2.maillage == nil)
        #expect(await sansTable.registre.requetes == ["6000|5,6"], "le chef seul")
    }

    /// Chef muet et secours sans Route64 : la recherche ne leur redemande pas la liste. Le secours,
    /// puis le chef muet, puis les autres, chacun une fois : sans table, les 61 autres
    /// identifiants ; avec la table, d'abord ses autres routeurs.
    @Test func rechercheSansLesEssais() async throws {
        var mem = MemoireTournee()
        mem.partition = "46CBEBCD"
        mem.echecs[45] = 2
        mem.repondants = [20]
        let sansTable = try SondeRejouee.capture(chef: 45, table: nil).filtree { _ in false }
        let r = try await Tournee.executer(sansTable, memoire: mem, maintenant: Self.t0)
        #expect(r.maillage == nil)
        let ids = await sansTable.registre.requetes.compactMap(Self.routeur)
        #expect(Array(ids.prefix(2)) == [20, 45], "le secours, puis le chef muet")
        #expect(ids.count == 63 && Set(ids) == Set(0...62), "puis les 61 autres, une fois chacun")

        let avecTable = try SondeRejouee.capture(chef: 45).filtree { _ in false }
        _ = try await Tournee.executer(avecTable, memoire: mem, maintenant: Self.t0)
        let ids2 = await avecTable.registre.requetes.compactMap(Self.routeur)
        #expect(Array(ids2.prefix(2)) == [20, 45])
        #expect(Set(ids2.dropFirst(2).prefix(5)) == [1, 24, 43, 51, 57], "la table, sans eux")
        #expect(ids2.count == 63 && Set(ids2) == Set(0...62))
    }

    /// Sonde dont le chef (45) ne donne pas la Route64, sans table ni autre reponse que les
    /// Route64 de `listes` (identifiant -> routeurs de sa Route64) ; `lents` : 100 ms plus tard.
    static func rechercheSeule(_ listes: [Int: [Int]], lents: Set<Int> = []) throws -> SondeRejouee {
        let cle = { (id: Int) in SondeRejouee.cle(UInt16(id) << 10, Tournee.tlvChef) }
        let base = try SondeRejouee.capture(chef: 45, table: nil)
        return SondeRejouee(etatSonde: base.etatSonde,
                            reponses: Dictionary(uniqueKeysWithValues: listes.map { (cle($0.key), Self.route64($0.value)) }),
                            table: nil,
                            retards: Dictionary(uniqueKeysWithValues: lents.map { (cle($0), Duration.milliseconds(100)) }))
    }

    /// Recherche par groupes de 8 dans l'ordre croissant (sans table) : un routeur qui donne la
    /// Route64 en 7 l'arrete apres le premier groupe (0 a 7), en 9 apres le second (0 a 15). Dans
    /// un groupe, celle du plus petit identifiant qui la donne, meme revenue apres une autre (le
    /// 9, lent, et le 12 ; Route64 inventees).
    @Test func rechercheParGroupesDe8() async throws {
        let cas: [(listes: [Int: [Int]], lents: Set<Int>, requetes: Int, routeurs: [Int])] = [
            ([7: [7, 45]], [], 9, [7, 45]),
            ([9: [9, 45]], [], 17, [9, 45]),
            ([9: [9, 45], 12: [12, 45]], [9], 17, [9, 45]),
        ]
        for c in cas {
            let sonde = try Self.rechercheSeule(c.listes, lents: c.lents)
            let (m, _) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
            #expect(m.routeurs.map(\.id) == c.routeurs, "\(c.listes)")
            #expect(await sonde.registre.requetes.filter { $0.hasSuffix("|5,6") }.count == c.requetes, "\(c.listes)")
        }
    }

    /// Echec passager : le 20, qui repond d'habitude, rate une tournee. Sans reponse dans ce
    /// maillage, un echec ; muet au second echec de suite.
    @Test func echecPassager() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let sans20 = sonde.filtree { !$0.hasPrefix("5000|") }
        let (m2, mem2) = try #require(try await Tournee.complete(sans20, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(mem2.echecs[20] == 1 && !mem2.estMuet(20))
        #expect(m2.routeur(20)?.muet == true)

        let (_, mem3) = try #require(try await Tournee.complete(sans20, memoire: mem2, maintenant: Self.t0 + 600))
        #expect(mem3.estMuet(20))
    }

    /// La sonde refuse (`occupee`) les requetes aux routeurs deux tournees de suite : ce n'est pas
    /// un silence des routeurs. Aucun echec de plus, aucun routeur muet ; le maillage
    /// les marque sans reponse a la tournee, et les secours restent.
    @Test func refusNeComptentPasCommeSilence() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let occupee = sonde.refusant { $0.hasSuffix("|0,1,5,16,8,24") }
        let (m2, mem2) = try #require(try await Tournee.complete(occupee, memoire: mem1, maintenant: Self.t0 + 300))
        let (m3, mem3) = try #require(try await Tournee.complete(occupee, memoire: mem2, maintenant: Self.t0 + 600))
        #expect(mem3.echecs == mem1.echecs, "aucun echec de plus")
        #expect(!mem3.estMuet(20) && !mem3.estMuet(24) && !mem3.estMuet(43))
        #expect(mem3.muetInterroge.isEmpty)
        #expect(m2.routeurs.filter(\.muet).count == 7 && m3.routeurs.filter(\.muet).count == 7, "sans reponse")
        let requetes = await occupee.registre.requetes
        #expect(requetes.filter { $0 == "AC00|0,1,5,16,8,24" }.count == 2, "pas muet : interroge a chaque tournee")
        #expect(mem3.repondants == [20, 24])
    }

    /// Reponse `ok` illisible du 20 (TLV tronquee), deux tournees de suite : ce n'est pas un
    /// silence. Ses echecs ne bougent pas, il n'est pas muet ; le maillage le marque
    /// sans reponse a la tournee.
    @Test func reponseIllisibleNEstPasUnSilence() async throws {
        let (_, mem1) = try #require(try await Tournee.complete(try SondeRejouee.capture(), memoire: MemoireTournee(),
                                                               maintenant: Self.t0))
        let illisible = try SondeRejouee.capture(reponsesEnPlus: ["5000|0,1,5,16,8,24": "0008E0"])
        let (m2, mem2) = try #require(try await Tournee.complete(illisible, memoire: mem1, maintenant: Self.t0 + 300))
        let (m3, mem3) = try #require(try await Tournee.complete(illisible, memoire: mem2, maintenant: Self.t0 + 600))
        #expect(mem3.echecs[20] == 0 && !mem3.estMuet(20))
        #expect(m2.routeur(20)?.muet == true && m3.routeur(20)?.muet == true, "sans reponse")
    }

    /// Resolution due (30 min) dont la sonde refuse toutes les demandes : elle ne remplace pas la precedente. Les
    /// enfants resolus restent affiches, et elle est refaite a la tournee suivante. Une resolution ou rien n'est trouve
    /// (`introuvable`) remplace la precedente, elle : les appareils reviennent en rattachement suppose.
    @Test func resolutionRefuseeGardeLaPrecedente() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        #expect(mem1.resolutions.count == 5)
        let refusee = sonde.refusant("suspendue") { $0.hasSuffix("|resoudre") }
        let (m2, mem2) = try #require(try await Tournee.complete(refusee, memoire: mem1, maintenant: Self.t0 + 1800,
                                                                appareils: Self.appareils))
        #expect(await refusee.registre.requetes.filter { $0.hasSuffix("|resoudre") }.count == 6, "resolution tentee")
        #expect(mem2.resolutions == mem1.resolutions && mem2.demandes == mem1.demandes)
        #expect(mem2.derniereResolution == Self.t0, "a refaire")
        #expect(m2.enfants(de: 43).count == 4, "3 enfants resolus et la sonde")
        #expect(m2.resolution == Self.t0, "resolution refusee : ses enfants restent ceux de la precedente")

        let avant = await sonde.registre.requetes.count
        let (_, mem3) = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 2100,
                                                               appareils: Self.appareils))
        #expect(await sonde.registre.requetes.dropFirst(avant).filter { $0.hasSuffix("|resoudre") }.count == 6, "refaite")
        #expect(mem3.derniereResolution == Self.t0 + 2100)

        let rien = try Self.sondeResolue(resolutions: [:])
        let (m4, mem4) = try #require(try await Tournee.complete(rien, memoire: mem1, maintenant: Self.t0 + 1800,
                                                                appareils: Self.appareils))
        #expect(mem4.resolutions.isEmpty && mem4.derniereResolution == Self.t0 + 1800)
        #expect(m4.enfants(de: 43).map(\.source) == [.sonde])
        #expect(m4.resolution == Self.t0 + 1800, "une resolution d'introuvables est une resolution")
    }

    /// Resolution refusee en partie : l'appareil refuse garde sa resolution d'avant, et il est demande de nouveau a la
    /// tournee suivante, seul.
    @Test func resolutionRefuseeEnPartie() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        let cleB = "\(Self.omr(0x0B))|resoudre"
        let refusee = sonde.refusant { $0 == cleB }
        let (m2, mem2) = try #require(try await Tournee.complete(refusee, memoire: mem1, maintenant: Self.t0 + 1800,
                                                                appareils: Self.appareils))
        #expect(mem2.derniereResolution == Self.t0 + 1800)
        #expect(mem2.resolutions["E00000000000000B"] == mem1.resolutions["E00000000000000B"], "sa resolution d'avant")
        #expect(!mem2.demandes.contains("E00000000000000B"))
        #expect(m2.enfants.contains { $0.rloc16 == 0xAC05 })
        let avant = await sonde.registre.requetes.count
        let (_, mem3) = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 2100,
                                                               appareils: Self.appareils))
        #expect(await sonde.registre.requetes.dropFirst(avant).filter { $0.hasSuffix("|resoudre") } == [cleB])
        #expect(mem3.demandes.contains("E00000000000000B") && mem3.resolutions["E00000000000000B"]?.date == Self.t0 + 2100)
    }

    /// Resolution due sans aucun appareil a resoudre (tous partis de l'instantane) : elle remplace la precedente par
    /// rien et prend la date de la tournee ; les enfants resolus d'avant ne s'affichent plus.
    @Test func resolutionSansAppareil() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        #expect(!mem1.resolutions.isEmpty)
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 1800))
        #expect(mem2.resolutions.isEmpty && mem2.demandes.isEmpty && mem2.derniereResolution == Self.t0 + 1800)
        #expect(m.enfants(de: 43).map(\.source) == [.sonde])
    }

    /// Recherche sans aucun groupe a interroger : rien n'a ete refuse.
    @Test func rechercheVideNonRefusee() async throws {
        let r = try await Tournee.chercherRoute64(try SondeRejouee.capture(), groupes: [])
        #expect(r.route64 == nil && !r.refusee)
    }

    /// Routeur muet (43 : silences a 0 et 5 min) : interroge au plus une fois par heure. Pas a
    /// 5 min + 59 min 59 s, de nouveau a 5 min + 1 h.
    @Test func muetReinterrogeApresUneHeure() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let (_, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(mem2.estMuet(43) && mem2.muetInterroge[43] == Self.t0 + 300)
        let avant = await sonde.registre.requetes.count
        let (_, mem3) = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: Self.t0 + 300 + 3599))
        let pendant = await sonde.registre.requetes.count
        let (_, mem4) = try #require(try await Tournee.complete(sonde, memoire: mem3, maintenant: Self.t0 + 300 + 3600))
        let requetes = await sonde.registre.requetes
        #expect(!requetes[avant..<pendant].contains("AC00|0,1,5,16,8,24"), "dans l'heure")
        #expect(mem3.muetInterroge[43] == Self.t0 + 300)
        #expect(requetes[pendant...].contains("AC00|0,1,5,16,8,24"), "une heure apres")
        #expect(mem4.muetInterroge[43] == Self.t0 + 3900 && mem4.echecs[43] == 3)
    }

    /// TLV (hexa) d'une reponse dont le type est dans `types`, dans leur ordre : une moitie de
    /// la reponse entiere.
    static func garder(_ hexa: String, _ types: Set<UInt8>) throws -> String {
        let o = [UInt8](try #require(Data(hexa: hexa)))
        var i = 0, gardees: [UInt8] = []
        while i + 2 <= o.count {
            let fin = i + 2 + Int(o[i + 1])
            if types.contains(o[i]) { gardees += o[i..<fin] }
            i = fin
        }
        return Data(gardees).hexa
    }

    /// TLV Route64 (hexa) des routeurs `ids`, croissants : sequence 1 ; un lien vers chaque routeur
    /// de `qualites` (qualite sortante et entrante vues par celui qui repond, cout 1), aucun vers
    /// les autres.
    static func route64(_ ids: [Int], qualites: [Int: (sortante: Int, entrante: Int)] = [:]) -> String {
        let masque = ids.reduce(UInt64(0)) { $0 | UInt64(1) << (63 - $1) }
        let routes = ids.map { id in qualites[id].map { UInt8($0.sortante << 6 | $0.entrante << 4 | 1) } ?? 0 }
        let octets: [UInt8] = [TypeTLV.route64, UInt8(9 + ids.count), 1]
            + (0..<8).map { UInt8(truncatingIfNeeded: masque >> (56 - 8 * $0)) } + routes
        return Data(octets).hexa
    }

    /// Lien lu aux deux bouts, avec d'autres qualites dans chaque Route64 : la tournee applique
    /// les reponses par identifiant croissant, et celle du plus grand decide (regle de
    /// `ConstructionMaillage.lien`), meme revenue la premiere (le 10 est lent ; routeurs inventes).
    @Test func lienDecideParLePlusGrandIdentifiant() async throws {
        var sonde = try SondeRejouee.capture(chef: 12, reponsesEnPlus: [
            "3000|5,6": Self.route64([10, 12]),
            // Vu par le 10 : 10 -> 12 de qualite 1, 12 -> 10 de qualite 2.
            "2800|0,1,5,16,8,24": Self.route64([10, 12], qualites: [12: (sortante: 1, entrante: 2)]),
            // Vu par le 12 : 12 -> 10 de qualite 1, 10 -> 12 de qualite 3.
            "3000|0,1,5,16,8,24": Self.route64([10, 12], qualites: [10: (sortante: 1, entrante: 3)]),
        ], table: [])
        sonde.retards = ["2800|0,1,5,16,8,24": .milliseconds(100)]
        let (m, _) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeurs.map(\.id) == [10, 12] && !m.routeurs.contains(where: \.muet), "les deux repondent")
        #expect(m.liens == [LienRadio(a: 10, b: 12, qualiteAB: 3, qualiteBA: 1, sourceAB: .diagnostic, sourceBA: .diagnostic,
                                      dateAB: Self.t0, dateBA: Self.t0)], "le rapport du 12")
    }

    /// TLV Child Table (hexa) des enfants `numeros` : qualite 3, delai 2^8 s, endormis (mode 04).
    static func tableEnfants(_ numeros: [Int]) -> String {
        let octets = numeros.flatMap { n -> [UInt8] in
            let x = 12 << 11 | 3 << 9 | n
            return [UInt8(x >> 8), UInt8(x & 0xFF), 0x04]
        }
        return Data([TypeTLV.tableEnfants, UInt8(octets.count)] + octets).hexa
    }

    /// Reponse du routeur 20 trop longue pour le reseau (`trop_long` : plus de 1100 octets) : il a
    /// repondu. Sa requete est refaite une fois en deux moities de TLV, reunies : le maillage et
    /// la memoire sont ceux d'une reponse entiere ; aucun echec.
    @Test func tropLongEnDeuxMoities() async throws {
        let (m0, mem0) = try #require(try await Tournee.complete(try SondeRejouee.capture(), memoire: MemoireTournee(),
                                                                  maintenant: Self.t0))
        let entiere = try CaptureSonde.tlv(104)
        let sonde = try SondeRejouee.capture(reponsesEnPlus: ["5000|0,1,5": try Self.garder(entiere, [0, 1, 5]),
                                                              "5000|16,8,24": try Self.garder(entiere, [16, 8, 24])],
                                             tropLongs: ["5000|0,1,5,16,8,24"])
        let releve = ReleveAvancement()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               avancement: { releve.noter($0) }))
        #expect(m == m0)
        #expect(mem == mem0)
        #expect(m.routeur(20)?.muet == false)
        let routeurs = releve.de(.routeurs)
        #expect(ReleveAvancement.croissants(routeurs))
        #expect(routeurs.last == AvancementTournee(etape: .routeurs, fait: 9, total: 9), "7 routeurs, puis 2 moities")
        let requetes = await sonde.registre.requetes
        let de20 = requetes.filter { $0.hasPrefix("5000|") && $0 != "5000|7" && $0 != "5000|25,26,27,28" }
        #expect(de20.first == "5000|0,1,5,16,8,24", "la requete entiere d'abord")
        #expect(de20.dropFirst().sorted() == ["5000|0,1,5", "5000|16,8,24"], "puis ses moities, une seule fois, en parallele : dans le desordre")
    }

    /// Une moitie encore trop longue : ce qu'on a est garde (ExtMac, liens), sans nouveau
    /// decoupage, et le routeur n'est ni muet, ni en echec.
    @Test func tropLongUneMoitieTropLongue() async throws {
        let (m0, _) = try #require(try await Tournee.complete(try SondeRejouee.capture(), memoire: MemoireTournee(),
                                                               maintenant: Self.t0))
        let entiere = try CaptureSonde.tlv(104)
        let sonde = try SondeRejouee.capture(reponsesEnPlus: ["5000|0,1,5": try Self.garder(entiere, [0, 1, 5])],
                                             tropLongs: ["5000|0,1,5,16,8,24", "5000|16,8,24"])
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeur(20)?.muet == false)
        #expect(m.routeur(20)?.extMac == "E000000000000002")
        #expect(m.liens == m0.liens, "liens de sa Route64, dans la moitie gardee")
        #expect(m.enfants(de: 20).isEmpty, "table des enfants dans la moitie trop longue")
        #expect(mem.echecs[20] == 0)
        #expect(mem.repondants == [20, 24])
        let requetes = await sonde.registre.requetes
        let de20 = requetes.filter { $0.hasPrefix("5000|0,1,5") || $0.hasPrefix("5000|16,8") }
        #expect(de20.first == "5000|0,1,5,16,8,24", "la requete entiere d'abord")
        #expect(de20.dropFirst().sorted() == ["5000|0,1,5", "5000|16,8,24"], "ses moities, pas de troisieme decoupage")
    }

    /// Un routeur qui repond sans son ExtMac (ici la moitie qui la porte reste sans reponse)
    /// garde l'identite connue d'une tournee precedente, comme un muet : il ne perd pas son nom.
    @Test func repondantSansExtMacGardeSonIdentite() async throws {
        let (_, mem1) = try #require(try await Tournee.complete(try SondeRejouee.capture(), memoire: MemoireTournee(),
                                                                 maintenant: Self.t0))
        #expect(mem1.identites[0x5000] == "E000000000000002")
        let entiere = try CaptureSonde.tlv(104)
        let sonde = try SondeRejouee.capture(reponsesEnPlus: ["5000|16,8,24": try Self.garder(entiere, [16, 8, 24])],
                                             tropLongs: ["5000|0,1,5,16,8,24"])
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(m.routeur(20)?.muet == false)
        #expect(m.routeur(20)?.extMac == "E000000000000002", "identite connue")
        #expect(m.enfants(de: 20).count == 2, "sa table des enfants, dans la moitie recue")
        #expect(mem.identites[0x5000] == "E000000000000002")
        #expect(mem.echecs[20] == 0)
    }

    /// L'identite connue d'un routeur qui repond sans ExtMac se lit apres toutes les reponses :
    /// si un routeur suivant repond avec cette ExtMac (elle a change de routeur), la paire perimee
    /// est oubliee et le premier ne la prend pas (valeurs de la capture ; paire perimee inventee).
    @Test func identiteConnueApresToutesLesReponses() async throws {
        var memoire = MemoireTournee()
        memoire.partition = "46CBEBCD"
        memoire.identites = [0x5000: "E000000000000003"]  // l'ExtMac du 24, perimee sous le 20
        let entiere = try CaptureSonde.tlv(104)
        let sonde = try SondeRejouee.capture(reponsesEnPlus: ["5000|16,8,24": try Self.garder(entiere, [16, 8, 24])],
                                             tropLongs: ["5000|0,1,5,16,8,24"])
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: memoire, maintenant: Self.t0))
        #expect(m.routeur(24)?.extMac == "E000000000000003")
        #expect(m.routeur(20)?.extMac == nil, "la paire perimee est oubliee avant d'etre lue")
        #expect(mem.identites[0x5000] == nil)
        #expect(mem.identites[0x6000] == "E000000000000003")
    }

    /// Aucun routeur ne repond a sa requete (sonde occupee...) : les secours de la
    /// tournee precedente restent.
    @Test func repondantsGardes() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let seulChef = sonde.filtree { $0 == "6000|5,6" }
        let (m2, mem2) = try #require(try await Tournee.complete(seulChef, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(m2.routeurs.filter(\.muet).count == 7)
        #expect(mem2.repondants == [20, 24])
    }

    /// Identites gardees : a 30 min, les enfants des tables ne repondent pas a la
    /// nouvelle demande ; celles de la premiere tournee restent.
    @Test func identitesGardees() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let endormis = sonde.filtree { !$0.hasSuffix("|0,8") }
        let (m2, mem2) = try #require(try await Tournee.complete(endormis, memoire: mem1, maintenant: Self.t0 + 1800))
        #expect(await endormis.registre.requetes.filter { $0.hasSuffix("|0,8") }.count == 6, "redemandees")
        #expect(m2.enfants(de: 20).map(\.extMac) == ["E000000000000005", "E000000000000004"])
        #expect(mem2.identifies.count == 3)
    }

    /// Demandes d'identite refusees par la sonde (`occupee`) : elles ne comptent pas comme
    /// faites, et la tournee suivante (5 min) les refait ; les enfants qui repondent sont
    /// identifies.
    @Test func identitesRefuseesRedemandees() async throws {
        let sonde = try SondeRejouee.capture()
        let refusees = sonde.refusant { $0.hasSuffix("|0,8") }
        let (_, mem1) = try #require(try await Tournee.complete(refusees, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(await refusees.registre.requetes.filter { $0.hasSuffix("|0,8") }.count == 6)
        #expect(mem1.identiteDemandee.isEmpty && mem1.identifies.isEmpty)
        let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(await sonde.registre.requetes.filter { $0.hasSuffix("|0,8") }.count == 6, "redemandees")
        #expect(mem2.identifies.count == 3 && mem2.identiteDemandee.count == 6)
        #expect(m2.enfants(de: 20).map(\.extMac) == ["E000000000000005", "E000000000000004"])
    }

    /// Table des routeurs de la sonde (FED) : les paires RLOC16 ↔ ExtMac des routeurs qu'elle
    /// entend sont retenues comme celle de son parent, et donnent leur ExtMac aux routeurs
    /// muets ; une demande par tournee. La sonde les entend ensuite moins (elle a bouge) : les
    /// paires restent (ExtMac inventees).
    @Test func routeursEntendus() async throws {
        let entendus: [UInt16: String] = [0xE400: "E0000000000000E4", 0xCC00: "E0000000000000CC"]
        let sonde = try SondeRejouee.capture(table: SondeRejouee.table(entendus: entendus))
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeur(57)?.extMac == "E0000000000000E4")
        #expect(m.routeur(51)?.extMac == "E0000000000000CC")
        #expect(m.routeur(1)?.extMac == nil, "pas entendu")
        #expect(m.routeur(43)?.extMac == "E000000000000007", "le parent, par etat")
        #expect(mem.identites[0xE400] == "E0000000000000E4" && mem.identites[0xCC00] == "E0000000000000CC")
        #expect(mem.identites[0xAC00] == "E000000000000007")
        #expect(await sonde.registre.tables == 1)

        let ailleurs = try SondeRejouee.capture(table: SondeRejouee.table(entendus: [0xE400: "E0000000000000E4"]))
        let (m2, mem2) = try #require(try await Tournee.complete(ailleurs, memoire: mem, maintenant: Self.t0 + 300))
        #expect(m2.routeur(51)?.extMac == "E0000000000000CC", "retenue d'une tournee a l'autre")
        #expect(mem2.identites[0xCC00] == "E0000000000000CC")
        #expect(await ailleurs.registre.tables == 1)
    }

    /// Pas de table (firmware sans `routeurs`, verrou d'OpenThread refuse) : la tournee continue,
    /// sans ces paires.
    @Test func sansTable() async throws {
        let sonde = try SondeRejouee.capture(table: nil)
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeurs.map(\.id) == [1, 20, 24, 43, 45, 51, 57])
        #expect(mem.identites == [0xAC00: "E000000000000007", 0x5000: "E000000000000002", 0x6000: "E000000000000003"])
        #expect(await sonde.registre.tables == 1)
    }

    /// Une ExtMac n'a qu'un RLOC16 : un routeur qui a change d'identifiant (redemarrage) perd
    /// l'ancienne paire, qui ne donne plus son ExtMac a l'identifiant libere.
    @Test func identiteDeplacee() async throws {
        let sonde = try SondeRejouee.capture(table: SondeRejouee.table(entendus: [0xE400: "E0000000000000E4"]))
        var mem = MemoireTournee()
        mem.partition = "46CBEBCD"
        mem.identites[0x0400] = "E0000000000000E4"
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(mem2.identites[0x0400] == nil)
        #expect(mem2.identites[0xE400] == "E0000000000000E4")
        #expect(m.routeur(1)?.extMac == nil)
        #expect(m.routeur(57)?.extMac == "E0000000000000E4")
    }

    /// Pas de liste des routeurs (plus rien ne repond apres `etat`) : pas de maillage, mais la
    /// memoire rendue garde les identites apprises (parent, table des routeurs), pour qu'une sonde
    /// promenee les garde, et la date de la recherche vaine ; le reste est la memoire d'avant,
    /// aucun routeur ne passe pour muet. Dans une autre partition, elle est remise a zero, sauf
    /// ces identites et cette date (ExtMac inventee).
    @Test func identitesSansListe() async throws {
        let (_, mem1) = try #require(try await Tournee.complete(try SondeRejouee.capture(), memoire: MemoireTournee(),
                                                               maintenant: Self.t0))
        let muette = try SondeRejouee.capture(table: SondeRejouee.table(entendus: [0xE400: "E0000000000000E4"]))
            .filtree { _ in false }
        let r = try await Tournee.executer(muette, memoire: mem1, maintenant: Self.t0 + 300)
        #expect(r.maillage == nil)
        var attendue = mem1
        attendue.identites[0xE400] = "E0000000000000E4"
        attendue.rechercheVaine = Self.t0 + 300
        #expect(r.memoire == attendue, "la memoire d'avant, plus le routeur entendu et la recherche vaine")

        var ailleurs = mem1
        ailleurs.partition = "73586B68"
        let r2 = try await Tournee.executer(muette, memoire: ailleurs, maintenant: Self.t0 + 300)
        #expect(r2.maillage == nil)
        var neuve = MemoireTournee()
        neuve.partition = "46CBEBCD"
        neuve.identites = [0xAC00: "E000000000000007", 0xE400: "E0000000000000E4"]
        neuve.rechercheVaine = Self.t0 + 300
        #expect(r2.memoire == neuve)
    }

    /// Network Data en echec a la tournee suivante : les dernieres lues servent (routeurs de
    /// bordure, BBR principal) ; sinon, les routeurs de bordure et leurs candidats disparaitraient
    /// d'une tournee a l'autre. Sans Network Data deja lues, aucun routeur de bordure.
    @Test func reseauGarde() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(mem1.donneesReseau != nil)
        let sansReseau = sonde.filtree { $0 != "5000|7" }
        let (m2, mem2) = try #require(try await Tournee.complete(sansReseau, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(await sansReseau.registre.requetes.contains("5000|7"), "demandees, en echec")
        #expect(m2.routeurs.filter(\.bordure).map(\.id) == [1, 43, 45, 51, 57])
        #expect(m2.routeur(45)?.bbrPrincipal == true)
        #expect(mem2.donneesReseau == mem1.donneesReseau)
        let (m3, _) = try #require(try await Tournee.complete(sansReseau, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m3.routeurs.filter(\.bordure).isEmpty)
    }

    /// Autre partition : les Network Data gardees de l'ancienne sont oubliees avec le reste de la
    /// memoire ; la requete echouant, aucun routeur n'est marque d'apres elles (ni routeur de
    /// bordure, ni BBR principal).
    @Test func autrePartitionOublieLesNetworkData() async throws {
        let anciennes = try #require(DonneesReseau(MaillageTests.bbrE400PuisB400))
        var mem = MemoireTournee()
        mem.partition = "73586B68"
        mem.donneesReseau = anciennes
        let sonde = try SondeRejouee.capture().filtree { $0 != "5000|7" }
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(mem2.partition == "46CBEBCD")
        #expect(mem2.donneesReseau == nil)
        #expect(!m.routeurs.contains { $0.bordure || $0.bbrPrincipal })
    }

    /// Paire d'un routeur sorti de la liste des routeurs (routeur disparu, identifiant libere) :
    /// oubliee des que la tournee a la Route64. Celle d'un routeur encore dans la liste reste,
    /// meme s'il n'est plus entendu (ExtMac inventees).
    @Test func pairesHorsDeLaListe() async throws {
        let sonde = try SondeRejouee.capture()
        var mem = MemoireTournee()
        mem.partition = "46CBEBCD"
        mem.identites = [0x0800: "E0000000000000EE", 0xE400: "E0000000000000E4"]
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(!m.routeurs.contains { $0.id == 2 }, "l'identifiant 2 n'est pas dans la Route64")
        #expect(mem2.identites[0x0800] == nil, "oubliee")
        #expect(mem2.identites[0xE400] == "E0000000000000E4", "le routeur 57 est dans la liste : gardee")
        #expect(m.routeur(57)?.extMac == "E0000000000000E4")
    }

    /// Routeur sorti de la liste des routeurs (identifiant libere) : ses echecs, sa derniere
    /// interrogation de muet, sa pile, sa place de secours et les enfants resolus sous lui sont
    /// oublies des que la tournee a la Route64. L'identifiant reattribue repart de zero :
    /// interroge tout de suite, et non tenu pour un muet deja interroge dans l'heure (Route64 et
    /// appareils inventes).
    @Test func memoireOublieeHorsDeLaListe() async throws {
        let sonde = try SondeRejouee.capture()
        var mem = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0)).memoire
        mem.echecs[2] = 2
        mem.muetInterroge[2] = Self.t0
        mem.piles[2] = "SL-OPENTHREAD"
        mem.repondants = [2, 20]
        mem.resolutions["E0000000000000E2"] = ResolutionAppareil(rloc16: 0x0800, mleid: nil, adresse: Self.omr(0xE2), date: Self.t0)
        mem.resolutions["E0000000000000E3"] = ResolutionAppareil(rloc16: 0xAC00, mleid: nil, adresse: Self.omr(0xE3), date: Self.t0)
        let seulChef = sonde.filtree { $0 == "6000|5,6" }
        let (_, mem2) = try #require(try await Tournee.complete(seulChef, memoire: mem, maintenant: Self.t0 + 300))
        #expect(mem2.echecs[2] == nil && mem2.muetInterroge[2] == nil && mem2.piles[2] == nil)
        #expect(mem2.repondants == [20], "aucun routeur n'a repondu : les secours d'avant, sans le 2")
        #expect(mem2.derniereResolution == Self.t0, "pas de nouvelle resolution")
        #expect(Set(mem2.resolutions.keys) == ["E0000000000000E3"], "l'appareil resolu sous le 2, lui seul")

        let avec2 = try SondeRejouee.capture(reponsesEnPlus: ["6000|5,6": Self.route64([1, 2, 20, 24, 43, 45, 51, 57])])
        let (m3, mem3) = try #require(try await Tournee.complete(avec2, memoire: mem2, maintenant: Self.t0 + 600))
        #expect(await avec2.registre.requetes.contains("0800|0,1,5,16,8,24"), "interroge")
        #expect(mem3.echecs[2] == 1, "premier silence")
        #expect(m3.routeur(2)?.muet == true)
    }

    /// Enfant absent de la table de son parent, qui a repondu : son identite (ExtMac, adresses) et
    /// la date de sa derniere demande sont oubliees. Un appareil qui reprend son RLOC16 sans
    /// repondre n'a pas l'ancien nom, et son identite est demandee tout de suite.
    @Test func identiteOublieeHorsDeLaTable() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(mem1.identifies[0x5001]?.extMac == "E000000000000005")
        let sans5001 = try Self.garder(try CaptureSonde.tlv(104), [0, 1, 5, 8, 24]) + Self.tableEnfants([4])
        let parti = try SondeRejouee.capture(reponsesEnPlus: ["5000|0,1,5,16,8,24": sans5001])
        let (_, mem2) = try #require(try await Tournee.complete(parti, memoire: mem1, maintenant: Self.t0 + 300))
        #expect(mem2.identifies[0x5001] == nil && mem2.identiteDemandee[0x5001] == nil, "absent de la table du 20")
        #expect(mem2.identifies[0x5004]?.extMac == "E000000000000004", "encore dans sa table")
        #expect(mem2.identifies[0x6003]?.extMac == "E000000000000006")

        let repris = sonde.filtree { $0 != "5001|0,8" }
        let (m3, mem3) = try #require(try await Tournee.complete(repris, memoire: mem2, maintenant: Self.t0 + 600))
        #expect(await repris.registre.requetes.contains("5001|0,8"), "demandee tout de suite")
        let e = try #require(m3.enfants.first { $0.rloc16 == 0x5001 })
        #expect(e.extMac == nil, "pas l'ancien nom")
        #expect(mem3.identiteDemandee[0x5001] == Self.t0 + 600)
    }

    /// Identites d'enfants dont le parent est sorti de la liste des routeurs : oubliees. Celles des
    /// enfants d'un routeur muet, ou d'un routeur dont la table n'est pas venue (moitie de reponse
    /// trop longue), restent : leur table n'est pas lue (ExtMac inventees).
    @Test func identitesOublieesAvecLeParent() async throws {
        var mem = MemoireTournee()
        mem.partition = "46CBEBCD"
        let demande = Self.t0 - 60
        for x in [0x0801, 0xAC01, 0x5001] as [UInt16] {
            mem.identifies[x] = EnfantMaillage(rloc16: x, extMac: String(format: "E00000000000%04X", x), source: .tableEnfants)
            mem.identiteDemandee[x] = demande
        }
        let entiere = try CaptureSonde.tlv(104)
        let sonde = try SondeRejouee.capture(reponsesEnPlus: ["5000|0,1,5": try Self.garder(entiere, [0, 1, 5])],
                                             tropLongs: ["5000|0,1,5,16,8,24", "5000|16,8,24"])
        let (_, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0))
        #expect(mem2.identifies[0x0801] == nil && mem2.identiteDemandee[0x0801] == nil, "le 2 n'est plus dans la liste")
        #expect(mem2.identifies[0xAC01] != nil && mem2.identiteDemandee[0xAC01] == demande, "parent muet")
        #expect(mem2.identifies[0x5001] != nil && mem2.identiteDemandee[0x5001] == demande, "table du 20 pas venue")
    }

    /// Enfant resolu sous un routeur muet (AC05) passe a un routeur qui repond (5002, dans sa
    /// table) : a la tournee suivante, avant la resolution suivante, son identite le reconnait, et il
    /// n'est plus affiche sous l'ancien parent. Les autres enfants resolus restent.
    @Test func enfantAyantChangeDeParent() async throws {
        let sonde = try Self.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        #expect(mem1.resolutions["E00000000000000B"]?.rloc16 == 0xAC05)
        let table20 = try Self.garder(try CaptureSonde.tlv(104), [0, 1, 5, 8, 24]) + Self.tableEnfants([4, 1, 2])
        let parti = try Self.sondeResolue(reponsesEnPlus: ["5000|0,1,5,16,8,24": table20, "5002|0,8": "0008E00000000000000B"])
        let (m2, mem2) = try #require(try await Tournee.complete(parti, memoire: mem1, maintenant: Self.t0 + 300,
                                                                appareils: Self.appareils))
        #expect(mem2.derniereResolution == Self.t0, "pas de nouvelle resolution")
        #expect(m2.enfants.filter { $0.extMac == "E00000000000000B" }.map(\.rloc16) == [0x5002], "une seule fois")
        #expect(m2.enfants(de: 43).map(\.rloc16) == [0xAC09, 0xAE00, 0xAE01])
    }

    /// La sonde est un appareil Matter de l'instantane : elle n'est jamais resolue (elle se connait), ni un appareil
    /// d'une autre partition (la resolution ne traverse pas les partitions) ; la sonde n'est affichee qu'une fois.
    @Test func sondeEtAutrePartitionJamaisResolues() async throws {
        let sonde = try Self.sondeResolue()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: Self.appareils))
        let demandes = await sonde.registre.requetes.filter { $0.hasSuffix("|resoudre") }
        #expect(!demandes.contains("\(Self.omr(0xAA))|resoudre") && !demandes.contains("\(Self.omr(0xF1))|resoudre"))
        #expect(m.enfants.filter { $0.extMac == "E0000000000000AA" }.map(\.rloc16) == [0xAC09], "la sonde, une fois")
        #expect(!mem.demandes.contains("E0000000000000AA") && !mem.demandes.contains("E0000000000000F1"))
    }

    /// Autre partition (panne, fusion) : les identifiants de routeur y sont
    /// redistribues ; ce qui etait retenu de l'ancienne ne sert plus : resolutions, demandes et
    /// releves des compteurs (la resolution est refaite), identites d'enfants et dates de leurs
    /// demandes, recherche vaine (ExtMac inventees).
    @Test func autrePartition() async throws {
        let sonde = try SondeRejouee.capture()
        var mem = MemoireTournee()
        mem.partition = "73586B68"
        mem.identites[0xB400] = "E0000000000000EE"
        mem.echecs[20] = 2
        mem.muetInterroge[20] = Self.t0
        mem.resolutions["E0000000000000E2"] = ResolutionAppareil(rloc16: 0xAC00, mleid: nil, adresse: Self.omr(0xE2), date: Self.t0)
        mem.demandes = ["E0000000000000E2"]
        mem.derniereResolution = Self.t0
        mem.compteurs["E0000000000000E2"] = CompteursMac(protocolesInconnus: 0, erreursRecues: 0, erreursEmises: 1,
                                                         unicastRecus: 0, diffusionsRecues: 0, rejetsRecus: 0,
                                                         unicastEmis: 100, diffusionsEmises: 0, rejetsEmis: 0)
        mem.identiteDemandee[0x5001] = Self.t0 + 30
        mem.identifies[0x6002] = EnfantMaillage(rloc16: 0x6002, extMac: "E0000000000000EF", source: .tableEnfants)
        mem.rechercheVaine = Self.t0
        let (m, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: Self.t0 + 60))
        #expect(mem2.partition == "46CBEBCD")
        #expect(m.routeur(45)?.extMac == nil, "B400 : pas l'ExtMac retenu dans l'autre partition")
        #expect(m.routeur(20)?.muet == false, "5000 interroge de nouveau")
        #expect(mem2.derniereResolution == Self.t0 + 60, "resolution refaite")
        #expect(mem2.resolutions.isEmpty && mem2.demandes.isEmpty && mem2.compteurs.isEmpty)
        #expect(await sonde.registre.requetes.contains("5001|0,8"), "identite redemandee")
        #expect(mem2.identiteDemandee[0x5001] == Self.t0 + 60)
        let e = try #require(m.enfants.first { $0.rloc16 == 0x6002 })
        #expect(e.extMac == nil, "pas l'identite de l'autre partition")
        #expect(mem2.rechercheVaine == nil)
    }

    /// Sonde suspendue (interrupteur eteint dans Maison) : pas de tournee, aucune requete.
    @Test func suspendue() async throws {
        let base = #"{"v":1,"t":"etat","role":"child","rloc16":"AC09","mode":"rn","parent":null,"partition":"46CBEBCD","chef":24,"canal":25,"prefixeMaille":null,"xp":null,"suspendue":true}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(base.utf8)) else {
            Issue.record("etat illisible")
            return
        }
        let sonde = SondeRejouee(etatSonde: e, reponses: [:])
        var mem = MemoireTournee()
        mem.echecs[20] = 1
        let r = try await Tournee.executer(sonde, memoire: mem, maintenant: Self.t0)
        #expect(r.maillage == nil)
        #expect(r.memoire == mem, "memoire inchangee")
        #expect(await sonde.registre.requetes.isEmpty)
        #expect(await sonde.registre.tables == 0, "ni la table des routeurs")
        #expect(await sonde.registre.voisins == 0, "ni les voisins")
        #expect(await sonde.registre.annonces == 0, "ni les annonces")
    }

    /// Avancement de la premiere tournee : les sept etapes dans l'ordre, chacune annoncee a 0
    /// puis une requete a la fois jusqu'a son total, connu des son debut ici. Les totaux sont
    /// les requetes envoyees : `etat`, `routeurs`, `voisins` et `annonces` pour la sonde, 6
    /// resolutions et 2 releves de compteurs.
    @Test func avancementPremiere() async throws {
        let sonde = try Self.sondeResolue()
        let releve = ReleveAvancement()
        _ = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                   appareils: Self.appareils, avancement: { releve.noter($0) }))
        #expect(releve.etapes == AvancementTournee.Etape.allCases)
        let totaux: [AvancementTournee.Etape: Int] = [.etatSonde: 4, .listeRouteurs: 1, .routeurs: 7, .pileEtReseau: 3,
                                                       .resolution: 6, .compteurs: 2, .identites: 6]
        for (etape, total) in totaux {
            let a = releve.de(etape)
            #expect(a.map(\.fait) == Array(0...total), "\(etape)")
            #expect(a.allSatisfy { $0.total == total }, "\(etape)")
        }
        let requetes = await sonde.registre.requetes
        #expect(requetes.count == totaux.values.reduce(0, +) - 4,
                "une requete par pas, hors etat, routeurs, voisins et annonces de la sonde")
        #expect(await sonde.registre.tables == 1)
        #expect(await sonde.registre.voisins == 1)
        #expect(await sonde.registre.annonces == 1)
    }

    /// Deuxieme tournee (5 min) : la liste des routeurs s'arrete au chef, avant son total
    /// (le chef et un secours) ; piles connues : Network Data seules ; la resolution (pas due),
    /// les compteurs et les identites (demandees il y a 5 min) sont annonces sans rien a faire.
    @Test func avancementSuivante() async throws {
        let sonde = try SondeRejouee.capture()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        let releve = ReleveAvancement()
        _ = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300,
                                                   avancement: { releve.noter($0) }))
        #expect(releve.etapes == AvancementTournee.Etape.allCases)
        #expect(releve.de(.listeRouteurs) == [AvancementTournee(etape: .listeRouteurs, fait: 0, total: 2),
                                              AvancementTournee(etape: .listeRouteurs, fait: 1, total: 2)])
        #expect(releve.de(.pileEtReseau).last == AvancementTournee(etape: .pileEtReseau, fait: 1, total: 1))
        #expect(releve.de(.resolution) == [AvancementTournee(etape: .resolution, fait: 0, total: 0)])
        #expect(releve.de(.compteurs) == [AvancementTournee(etape: .compteurs, fait: 0, total: 0)])
        #expect(releve.de(.identites) == [AvancementTournee(etape: .identites, fait: 0, total: 0)])
        #expect(ReleveAvancement.croissants(releve.de(.routeurs)))
    }

    /// Chef muet des le lancement : le total de la liste des routeurs grandit quand la
    /// recherche commence (le chef, puis les 6 autres routeurs de la table et les 56 autres
    /// identifiants) ; elle s'arrete au groupe de la table, avant son total, apres 7 requetes.
    /// Sans table (les 62 autres identifiants), au groupe du 20, apres 25 requetes.
    @Test func avancementRecherche() async throws {
        let tlv20 = try CaptureSonde.tlv(104)
        for (table, faites) in [(SondeRejouee.table(), 7), (nil, 25)] as [([RouteurSonde]?, Int)] {
            let sonde = try SondeRejouee.capture(chef: 45, reponsesEnPlus: ["5000|5,6": tlv20], table: table)
            let releve = ReleveAvancement()
            _ = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                       avancement: { releve.noter($0) }))
            let liste = releve.de(.listeRouteurs)
            #expect(Array(liste.prefix(3)) == [AvancementTournee(etape: .listeRouteurs, fait: 0, total: 1),
                                               AvancementTournee(etape: .listeRouteurs, fait: 1, total: 1),
                                               AvancementTournee(etape: .listeRouteurs, fait: 1, total: 63)])
            #expect(liste.last == AvancementTournee(etape: .listeRouteurs, fait: faites, total: 63))
            #expect(ReleveAvancement.croissants(liste))
            #expect(await sonde.registre.requetes.filter { $0.hasSuffix("|5,6") }.count == faites)
        }
    }

    /// `parallele` sur 20 elements, en fenetre glissante : jamais plus de 8 requetes en vol, et
    /// l'element 0, retenu, n'empeche pas les 19 autres de partir (chaque requete revenue en lance
    /// une). Resultats dans l'ordre des elements ; `apresChacune` a chaque requete revenue.
    @Test(.timeLimit(.minutes(1))) func paralleleFenetreGlissante() async throws {
        let vol = EnVol()
        var faites: [Int] = []
        let r = try await Tournee.parallele(Array(0..<20), { e in
            await vol.partir()
            if e == 0 { await vol.retenir(jusqua: 20) } else { try await Task.sleep(for: .milliseconds(10)) }
            await vol.revenir()
            return ResultatDiag(id: e, cible: "", ok: false, erreur: "delai")
        }, apresChacune: { n, _, _ in faites.append(n) })
        #expect(await vol.vues == 20, "tous partis pendant que le 0 etait retenu")
        #expect(await vol.maximum <= Tournee.enVol)
        #expect(r.map(\.0) == Array(0..<20) && r.map(\.1.id) == Array(0..<20))
        #expect(faites == Array(1...20))
    }

    /// Liaison fermee au milieu d'un groupe (`diag` echoue par une erreur) : `parallele` rend
    /// l'erreur, et la tournee aussi ; l'appelant garde sa memoire.
    @Test func erreurAuMilieuDUnGroupe() async throws {
        await #expect(throws: SondeFermee.Fermee.self) {
            _ = try await Tournee.parallele(Array(0..<10), { e in
                if e == 4 { throw SondeFermee.Fermee() }
                return ResultatDiag(id: e, cible: "", ok: false, erreur: "delai")
            })
        }
        let sonde = SondeFermee(base: try SondeRejouee.capture(), sur: "5000|0,1,5,16,8,24")
        await #expect(throws: SondeFermee.Fermee.self) {
            _ = try await Tournee.executer(sonde, memoire: MemoireTournee(), maintenant: Self.t0)
        }
    }

    /// Signal des routeurs que la sonde entend (valeurs inventees) : son parent AC00 par `etat`
    /// (-89 dBm), qui passe avant sa ligne de `voisins` ; E400 par `voisins`. Ni un RSSI invalide
    /// (127, CC00), ni un enfant, ni un routeur hors de la liste (0800). Une demande par tournee.
    @Test func signauxDeLaSonde() async throws {
        let voisins = [VoisinSonde(rloc16: "E400", ext: "E0000000000000E4", rssi: -72, lqi: 3, routeur: true),
                       VoisinSonde(rloc16: "CC00", ext: "E0000000000000CC", rssi: 127, lqi: 0, routeur: true),
                       VoisinSonde(rloc16: "AC00", ext: "E000000000000007", rssi: -60, lqi: 3, routeur: true),
                       VoisinSonde(rloc16: "0800", ext: "E0000000000000EE", rssi: -80, lqi: 2, routeur: true),
                       VoisinSonde(rloc16: "5003", ext: "E0000000000000A3", rssi: -50, lqi: 3, routeur: false)]
        let sonde = try SondeRejouee.capture(voisins: voisins)
        let (m, _) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.signaux == [SignalSonde(routeur: 43, rssi: -89), SignalSonde(routeur: 57, rssi: -72)])
        #expect(m.parentSonde == 43)
        #expect(await sonde.registre.voisins == 1)
    }

    /// Bords du garde du signal : -1 dBm est valide ; 0 et les RSSI positifs (127 : invalide
    /// d'OpenThread) sont ignores ; le dernier signal valide d'un routeur l'emporte, et un invalide
    /// ne l'efface pas.
    @Test func bordsDuSignal() {
        var c = ConstructionMaillage(date: Self.t0, partition: "0000000A")
        c.routeurs(Route64(sequence: 1, routes: (1...4).map { RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1) }),
                   chef: 1)
        c.signal(SignalSonde(routeur: 1, rssi: -1))
        c.signal(SignalSonde(routeur: 2, rssi: 0))
        c.signal(SignalSonde(routeur: 3, rssi: 127))
        c.signal(SignalSonde(routeur: 4, rssi: -60))
        c.signal(SignalSonde(routeur: 4, rssi: 0))
        #expect(c.maillage().signaux == [SignalSonde(routeur: 1, rssi: -1), SignalSonde(routeur: 4, rssi: -60)])
    }

    /// Pas de liste des voisins (verrou d'OpenThread refuse...) : la tournee continue, avec le seul
    /// signal du parent.
    @Test func sansVoisins() async throws {
        let sonde = try SondeRejouee.capture(voisins: nil)
        let (m, _) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0))
        #expect(m.routeurs.count == 7)
        #expect(m.signaux == [SignalSonde(routeur: 43, rssi: -89)])
        #expect(await sonde.registre.voisins == 1)
    }

    /// Sonde pas encore dans le reseau.
    @Test func nonAttachee() async throws {
        let base = #"{"v":1,"t":"etat","role":"disabled","rloc16":"FFFE","mode":"rn","parent":null,"partition":null,"chef":null,"canal":11,"prefixeMaille":null,"xp":null,"suspendue":false}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(base.utf8)) else {
            Issue.record("etat illisible")
            return
        }
        let sonde = SondeRejouee(etatSonde: e, reponses: [:])
        let releve = ReleveAvancement()
        let r = try await Tournee.executer(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                           avancement: { releve.noter($0) })
        #expect(r.maillage == nil && r.memoire == MemoireTournee())
        #expect(await sonde.registre.tables == 0, "pas de table hors d'une partition")
        #expect(await sonde.registre.voisins == 0, "ni de voisins")
        #expect(releve.avancements == [AvancementTournee(etape: .etatSonde, fait: 0, total: 4),
                                       AvancementTournee(etape: .etatSonde, fait: 1, total: 4)],
                "l'etape s'arrete avant son total")
    }
}
