import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Suivi : evenements du journal")
struct SuiviTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let a1 = "AAAA000000000001"
    static let a2 = "AAAA000000000002"

    /// Reseau de base : un chef, un routeur, deux appareils dans fd19.
    static func banc(_ date: Date) -> Banc {
        var b = Banc(date: date)
        b.routeur("Chef", role: .chef, primaire: true, lien: "fe80::1")
        b.routeur("Second", lien: "fe80::2")
        b.route("fd19:961f:2db3::/64", via: "fe80::1")
        b.appareil(a1, noeud: 1, adresses: ["fd19:961f:2db3::11"])
        b.appareil(a2, noeud: 2, adresses: ["fd19:961f:2db3::12"], sii: 6000)
        return b
    }

    static func demarre() -> Suivi {
        var s = Suivi()
        _ = s.integrer(banc(t0).annonces)
        return s
    }

    static let xpVoisin = "1122334455667788"

    /// Second reseau Thread (Voisin, autre xp) : un chef qui publie son prefixe
    /// OMR et ses appareils ; scinde : un second chef dans une autre partition.
    static func ajouterVoisin(_ b: inout Banc, scinde: Bool = false, appareils: Int = 1) {
        b.routeur("Voisin", partition: "BBBBBBBB", role: .chef, primaire: true, lien: "fe80::b1",
                  omr: "fd99:0:0:1::/64", xp: xpVoisin, nn: "Voisin")
        if scinde {
            b.routeur("Voisin isole", partition: "CCCCCCCC", role: .chef, primaire: true, lien: "fe80::c1",
                      omr: "fd98:0:0:1::/64", xp: xpVoisin, nn: "Voisin")
        }
        for n in 0..<appareils {
            b.appareil(String(format: "BBBB%012X", n + 1), noeud: 11 + n, adresses: ["fd99:0:0:1::\(n + 1)"])
        }
    }

    @Test func lancement() {
        var s = Suivi()
        let ev = s.integrer(Self.banc(Self.t0).annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree])
        #expect(ev.first?.details == ["routeurs": "2", "appareils": "2"])
        #expect(ev.first?.gravite == .info)
        #expect(s.integrer(Self.banc(Self.t0 + 60).annonces).isEmpty, "rien n'a change")
        #expect(s.dernieresPartitions[Self.a1] == "73586B68")
    }

    @Test func lancementSurUnReseauScinde() throws {
        var b = Self.banc(Self.t0)
        b.routeur("Isole", partition: "E2E79FFC", role: nil, primaire: true, lien: "fe80::3")
        var s = Suivi()
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree, .reseauScinde])
        let scission = try #require(ev.last)
        #expect(scission.constate)
        #expect(scission.gravite == .alerte)
        #expect(scission.details["E2E79FFC"] == "Isole")
        #expect(scission.details["73586B68"] == "Chef, Second")
    }

    /// Un releve vide ne dit rien de Thread (reseau local coupe, acces refuse,
    /// invite en attente) : il est ignore, meme au-dela du sursis.
    @Test func releveVideIgnore() {
        #expect(Annonces(date: Self.t0).estVide)
        #expect(!Annonces(date: Self.t0, hap: [AnnonceService(instance: "Eve Door 4A3B")]).estVide, "un accessoire HomeKit suffit")
        var s = Self.demarre()
        for minute in 1...4 {
            #expect(s.integrer(Annonces(date: Self.t0 + Double(minute) * 60)).isEmpty, "\(minute) min sans rien")
            #expect(s.instantane?.date == Self.t0, "instantane inchange")
        }
        #expect(s.integrer(Self.banc(Self.t0 + 600).annonces).isEmpty, "le meme reseau 10 min plus tard : ni perte ni apparu")
    }

    @Test func premierReleveVide() throws {
        var s = Suivi()
        #expect(s.integrer(Annonces(date: Self.t0)).isEmpty)
        #expect(s.instantane == nil, "le point de depart attend un releve non vide")
        var b = Self.banc(Self.t0 + 60)
        b.routeur("Isole", partition: "E2E79FFC", role: nil, primaire: true, lien: "fe80::3")
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree, .reseauScinde])
        #expect(ev.first?.date == Self.t0 + 60)
        let scission = try #require(ev.last)
        #expect(scission.constate)
    }

    /// Un reseau vu pour la premiere fois apres le lancement est son propre point
    /// de depart : ni "apparu", ni "nouveau", ni "nouveau prefixe" pour ses membres.
    @Test func nouveauReseauPointDeDepart() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        Self.ajouterVoisin(&b, scinde: true)
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree, .reseauScinde])
        let depart = try #require(ev.first)
        #expect(depart.reseau == Self.xpVoisin)
        #expect(depart.sujet == Sujet(id: Self.xpVoisin, nom: "Voisin"))
        #expect(depart.details == ["routeurs": "2", "appareils": "1"])
        let scission = try #require(ev.last)
        #expect(scission.reseau == Self.xpVoisin)
        #expect(scission.sujet == Sujet(id: Self.xpVoisin, nom: "Voisin"))
        #expect(scission.constate)
        #expect(scission.apres == "2")
        #expect(scission.details == ["BBBBBBBB": "Voisin", "CCCCCCCC": "Voisin isole"])

        // Ensuite, comparaison normale : un appareil ajoute au voisin est nouveau.
        var c = Self.banc(Self.t0 + 120)
        Self.ajouterVoisin(&c, scinde: true, appareils: 2)
        let suite = s.integrer(c.annonces)
        #expect(suite.map(\.type) == [.appareilNouveau])
        #expect(suite.first?.reseau == Self.xpVoisin)
    }

    /// Un appareil disparu qui revient dans un reseau vu pour la premiere fois : "revenu".
    @Test func revenuDansUnNouveauReseau() {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.retirer(Self.a2)
        _ = s.integrer(b.annonces)
        b.date = Self.t0 + 180
        #expect(s.integrer(b.annonces).map(\.type) == [.appareilDisparu])
        var c = Self.banc(Self.t0 + 240)
        Self.ajouterVoisin(&c, appareils: 0)
        c.adresses[Self.a2 + ".local"] = ["fd99:0:0:1::12"]
        let ev = s.integrer(c.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree, .appareilRevenu])
        #expect(ev.first?.details == ["routeurs": "1", "appareils": "1"])
        #expect(ev.last?.reseau == Self.xpVoisin)
        #expect(s.disparus.isEmpty)
    }

    /// Un reseau deja vu qui disparait puis revient n'est pas un nouveau depart.
    @Test func reseauQuiRevient() {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        Self.ajouterVoisin(&b)
        #expect(s.integrer(b.annonces).map(\.type) == [.surveillanceDemarree])
        var sans = Self.banc(Self.t0 + 120)
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 180
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 240
        #expect(s.integrer(sans.annonces).map(\.type) == [.routeurDisparu, .prefixeRetire, .appareilDisparu])
        var retour = Self.banc(Self.t0 + 300)
        Self.ajouterVoisin(&retour)
        #expect(s.integrer(retour.annonces).map(\.type) == [.routeurApparu, .prefixeNouveau, .appareilRevenu])
    }

    /// Un reseau deja vu qui se tait au-dela du sursis (le Mac entend toujours le
    /// reste), puis revient scinde : sa scission est constatee, comme au
    /// lancement ; ses membres ont leurs evenements habituels.
    @Test func reseauQuiRevientScinde() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        Self.ajouterVoisin(&b)
        #expect(s.integrer(b.annonces).map(\.type) == [.surveillanceDemarree])
        var sans = Self.banc(Self.t0 + 120)
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 180
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 240
        #expect(s.integrer(sans.annonces).map(\.type) == [.routeurDisparu, .prefixeRetire, .appareilDisparu])
        var retour = Self.banc(Self.t0 + 300)
        Self.ajouterVoisin(&retour, scinde: true)
        let ev = s.integrer(retour.annonces)
        #expect(ev.map(\.type) == [.reseauScinde, .routeurApparu, .routeurApparu, .prefixeNouveau, .prefixeNouveau,
                                   .appareilRevenu])
        let scission = try #require(ev.first { $0.type == .reseauScinde })
        #expect(scission.constate)
        #expect(scission.date == Self.t0 + 300)
        #expect(scission.reseau == Self.xpVoisin)
        #expect(scission.sujet == Sujet(id: Self.xpVoisin, nom: "Voisin"))
        #expect(scission.apres == "2", "comme au lancement : le nombre de partitions")
        #expect(scission.details == ["BBBBBBBB": "Voisin", "CCCCCCCC": "Voisin isole"])
    }

    /// Le meme retour, sans scission : pas de scission constatee, meme si le reseau
    /// etait scinde a sa decouverte (seul compte l'etat au retour).
    @Test func reseauQuiRevientSansScission() {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        Self.ajouterVoisin(&b, scinde: true)
        #expect(s.integrer(b.annonces).map(\.type) == [.surveillanceDemarree, .reseauScinde])
        var sans = Self.banc(Self.t0 + 120)
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 180
        #expect(s.integrer(sans.annonces).isEmpty)
        sans.date = Self.t0 + 240
        #expect(s.integrer(sans.annonces).map(\.type)
                == [.routeurDisparu, .routeurDisparu, .prefixeRetire, .prefixeRetire, .appareilDisparu])
        var retour = Self.banc(Self.t0 + 300)
        Self.ajouterVoisin(&retour)
        #expect(s.integrer(retour.annonces).map(\.type) == [.routeurApparu, .prefixeNouveau, .appareilRevenu])
    }

    /// Un point de depart (reseau vu peu apres un reveil) garde sa date : la
    /// surveillance de ce reseau commence au releve, pas pendant la veille.
    @Test func departApresUnReveil() {
        var s = Self.demarre()
        let veille = DateInterval(start: Self.t0 + 60, end: Self.t0 + 3600)
        _ = s.noterVeille(veille)
        var b = Self.banc(veille.end + 10)
        Self.ajouterVoisin(&b, scinde: true)
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree, .reseauScinde])
        #expect(ev.allSatisfy { $0.periode == nil && $0.date == veille.end + 10 })
    }

    @Test func disparitionConfirmeeApresDeuxMinutes() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.retirer(Self.a2)
        #expect(s.integrer(b.annonces).isEmpty, "absence constatee, pas encore retenue")
        b.date = Self.t0 + 120
        #expect(s.integrer(b.annonces).isEmpty, "60 s d'absence")
        b.date = Self.t0 + 180
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilDisparu])
        let e = try #require(ev.first)
        #expect(e.date == Self.t0 + 60, "datee de la premiere absence")
        #expect(e.sujet == Sujet(id: Self.a2, nom: Self.a2))
        #expect(e.avant == "73586B68")
        #expect(e.gravite == .attention)
        #expect(Array(s.disparus.keys) == [Self.a2])

        let retour = s.integrer(Self.banc(Self.t0 + 240).annonces)
        #expect(retour.map(\.type) == [.appareilRevenu])
        #expect(s.disparus.isEmpty)
    }

    @Test func retourAvantConfirmation() {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.retirer(Self.a2)
        #expect(s.integrer(b.annonces).isEmpty)
        #expect(s.instantane?.appareil(Self.a2)?.etat == .joignable, "en sursis : toujours la")
        #expect(s.integrer(Self.banc(Self.t0 + 120).annonces).isEmpty)
        #expect(s.integrer(Self.banc(Self.t0 + 300).annonces).isEmpty, "le sursis a ete leve")
    }

    @Test func sansAdresse() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.adresses[Self.a2 + ".local"] = []
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = Self.t0 + 180
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilSansAdresse])
        #expect(ev.first?.date == Self.t0 + 60)
        #expect(s.instantane?.appareil(Self.a2)?.etat == .sansAdresse)
        #expect(s.dernieresPartitions[Self.a2] == "73586B68", "derniere partition connue gardee")
        #expect(s.integrer(Self.banc(Self.t0 + 240).annonces).map(\.type) == [.appareilRevenu])
    }

    @Test func routeurs() throws {
        var s = Self.demarre()
        // Nouvelle adresse de lien du chef (redemarrage probable), la route suit.
        var b = Self.banc(Self.t0 + 60)
        b.adresses["Chef.local"] = ["fe80::a"]
        b.routes = [RouteIPv6(prefixe: "fd19:961f:2db3::/64", passerelle: "fe80::a")]
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.routeurNouvelleAdresseLien])
        #expect(ev.first?.avant == "fe80::1")
        #expect(ev.first?.apres == "fe80::a")

        // Le second disparait : alerte, datee de la premiere absence.
        b.routeurs.removeAll { $0.instance == "Second" }
        b.date = Self.t0 + 120
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = Self.t0 + 240
        let d = s.integrer(b.annonces)
        #expect(d.map(\.type) == [.routeurDisparu])
        #expect(d.first?.gravite == .alerte)
        #expect(d.first?.date == Self.t0 + 120)

        // Il revient.
        var c = Self.banc(Self.t0 + 300)
        c.adresses["Chef.local"] = ["fe80::a"]
        c.routes = b.routes
        #expect(s.integrer(c.annonces).map(\.type) == [.routeurApparu])
    }

    @Test func roleEtChef() {
        var s = Self.demarre()
        var b = Banc(date: Self.t0 + 60)
        b.routeur("Chef", role: .routeur, primaire: true, lien: "fe80::1")
        b.routeur("Second", role: .chef, lien: "fe80::2")
        b.route("fd19:961f:2db3::/64", via: "fe80::1")
        b.appareil(Self.a1, noeud: 1, adresses: ["fd19:961f:2db3::11"])
        b.appareil(Self.a2, noeud: 2, adresses: ["fd19:961f:2db3::12"], sii: 6000)
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.chefChange, .routeurRoleChange, .routeurRoleChange])
        #expect(ev.first?.avant == "Chef")
        #expect(ev.first?.apres == "Second")
    }

    @Test func scissionEtReunion() throws {
        var s = Self.demarre()
        var b = Banc(date: Self.t0 + 60)
        b.routeur("Chef", role: .chef, primaire: true, lien: "fe80::1")
        b.routeur("Second", partition: "E2E79FFC", role: .chef, primaire: true, lien: "fe80::2")
        b.route("fd19:961f:2db3::/64", via: "fe80::1")
        b.appareil(Self.a1, noeud: 1, adresses: ["fd19:961f:2db3::11"])
        b.appareil(Self.a2, noeud: 2, adresses: ["fd19:961f:2db3::12"], sii: 6000)
        let ev = s.integrer(b.annonces)
        let scission = try #require(ev.first)
        #expect(scission.type == .reseauScinde)
        #expect(scission.avant == "1")
        #expect(scission.apres == "2")
        #expect(!scission.constate)
        #expect(scission.details["E2E79FFC"] == "Second")
        #expect(s.integrer(Self.banc(Self.t0 + 120).annonces).map(\.type) == [.reseauReuni, .routeurRoleChange],
                "le chef de la partition isolee redevient simple routeur")
    }

    @Test func changementDePartitionEtPrefixes() throws {
        var s = Self.demarre()
        var b = Banc(date: Self.t0 + 60)
        b.routeur("Chef", role: .chef, primaire: true, lien: "fe80::1")
        b.routeur("Second", role: .routeur, lien: "fe80::2")
        b.routeur("Isole", partition: "E2E79FFC", role: nil, primaire: true, lien: "fe80::3",
                  omr: "fd03:54f0:5de:1::/64")
        b.route("fd19:961f:2db3::/64", via: "fe80::1")
        b.appareil(Self.a1, noeud: 1, adresses: ["fd19:961f:2db3::11"])
        b.appareil(Self.a2, noeud: 2, adresses: ["fd03:54f0:5de:1::12"], sii: 6000)
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.reseauScinde, .routeurApparu, .prefixeNouveau, .appareilChangePartition])
        let change = try #require(ev.last)
        #expect(change.avant == "73586B68")
        #expect(change.apres == "E2E79FFC")
        #expect(change.details["coupee"] == "oui")
        #expect(change.gravite == .attention)
        #expect(ev[2].sujet?.id == "fd03:54f0:5de:1::/64")
    }

    @Test func veilleDuMac() throws {
        var s = Self.demarre()
        let veille = DateInterval(start: Self.t0 + 60, end: Self.t0 + 6 * 3600)
        let v = s.noterVeille(veille)
        #expect(v.map(\.type) == [.veille])
        #expect(v.first?.date == veille.end)
        #expect(v.first?.periode == veille)

        var b = Self.banc(veille.end + 10)
        b.retirer(Self.a2)
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = veille.end + 130
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilDisparu])
        #expect(ev.first?.periode == veille, "pendant la veille, pas au reveil")

        // Loin du reveil : datation normale.
        var c = Self.banc(veille.end + 600)
        c.retirer(Self.a1)
        c.retirer(Self.a2)
        _ = s.integrer(c.annonces)
        c.date = veille.end + 720
        let tard = s.integrer(c.annonces)
        #expect(tard.map(\.type) == [.appareilDisparu])
        #expect(tard.first?.periode == nil)
        #expect(tard.first?.date == veille.end + 600)
    }

    /// Veille de 8 h ; une absence commence au releve fait 10 s avant (reseau deja coupe).
    static let longueVeille = DateInterval(start: t0 + 60, duration: 8 * 3600)

    /// Des adresses manquent 10 s avant la veille, et encore 5 s apres le reveil
    /// (resolution pas prete) : le sursis reprend au reveil, rien n'est abandonne.
    /// Revenues 60 s apres : aucun evenement, ni perte ni retour.
    @Test func sursisReprisAuReveil() {
        var s = Self.demarre()
        let veille = Self.longueVeille
        var b = Self.banc(veille.start - 10)
        b.adresses[Self.a2 + ".local"] = []
        #expect(s.integrer(b.annonces).isEmpty)
        #expect(s.noterVeille(veille).map(\.type) == [.veille])
        b.date = veille.end + 5
        #expect(s.integrer(b.annonces).isEmpty, "5 s apres le reveil : toujours en sursis")
        #expect(s.integrer(Self.banc(veille.end + 60).annonces).isEmpty, "revenues : ni perte ni retour")
        #expect(s.instantane?.appareil(Self.a2)?.etat == .joignable)
    }

    /// Les memes adresses manquent encore 130 s apres le reveil : une seule perte,
    /// datee du reveil, donc de la veille.
    @Test func sansAdresseDateeDuReveil() throws {
        var s = Self.demarre()
        let veille = Self.longueVeille
        var b = Self.banc(veille.start - 10)
        b.adresses[Self.a2 + ".local"] = []
        #expect(s.integrer(b.annonces).isEmpty)
        #expect(s.noterVeille(veille).map(\.type) == [.veille])
        b.date = veille.end + 5
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = veille.end + 60
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = veille.end + 130
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilSansAdresse])
        let e = try #require(ev.first)
        #expect(e.sujet?.id == Self.a2)
        #expect(e.date == veille.end, "datee du reveil, pas de l'endormissement")
        #expect(e.periode == veille, "pendant la veille")
    }

    /// Le meme debut pour des services absents (l'appareil n'annonce plus rien) :
    /// disparu 2 min apres le reveil seulement, date du reveil, donc de la veille.
    @Test func disparuDateDuReveil() throws {
        var s = Self.demarre()
        let veille = Self.longueVeille
        var b = Self.banc(veille.start - 10)
        b.retirer(Self.a2)
        #expect(s.integrer(b.annonces).isEmpty)
        #expect(s.noterVeille(veille).map(\.type) == [.veille])
        b.date = veille.end + 5
        #expect(s.integrer(b.annonces).isEmpty)
        b.date = veille.end + 119
        #expect(s.integrer(b.annonces).isEmpty, "moins de 2 min apres le reveil")
        b.date = veille.end + 130
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilDisparu])
        let e = try #require(ev.first)
        #expect(e.sujet?.id == Self.a2)
        #expect(e.date == veille.end, "date du reveil")
        #expect(e.periode == veille, "pendant la veille")
        #expect(Array(s.disparus.keys) == [Self.a2])
    }

    @Test func formatJSON() throws {
        let e = Evenement(date: Self.t0, type: .reseauScinde, reseau: "4B36A2B7FEFB200B",
                          sujet: Sujet(id: "4B36A2B7FEFB200B", nom: "MyHome1482620090"), avant: "1", apres: "2",
                          periode: DateInterval(start: Self.t0 - 60, end: Self.t0), constate: true,
                          details: ["E2E79FFC": "Aqara HubM100 #DFEB"])
        let json = try CodageJSON.encodeur().encode(e)
        #expect(try CodageJSON.decodeur().decode(Evenement.self, from: json) == e)
        let ancien = Data(#"{"date":"2026-09-27T00:14:00Z","type":"appareilDisparu"}"#.utf8)
        let lu = try CodageJSON.decodeur().decode(Evenement.self, from: ancien)
        #expect(lu.gravite == .attention && !lu.constate && lu.details.isEmpty, "champs manquants : valeurs par defaut")
        #expect(e.id == "1790000000000-reseauScinde-4B36A2B7FEFB200B")
    }
}
