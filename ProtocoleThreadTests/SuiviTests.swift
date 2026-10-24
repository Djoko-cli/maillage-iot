import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

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

    /// Appareil Matter du reseau local (Wi-Fi, Ethernet, pont) : hote a 12 hexa, adresse dans le prefixe du reseau local.
    static let ip = "C0FFEE000001"
    static let adresseIP = "fd4b:36a2:b7fe:200b:c2ff:eeff:fe00:1"

    /// Appareil jamais vu avec une adresse (nouveau venu, hote a 16 hexa ou 12) : ses annonces sont la, ses adresses pas encore.
    static let neuf = "AAAA000000000009"
    static let adresseNeuf = "fd19:961f:2db3::19"

    /// Cas du 24/10 : un appareil du reseau local entre au releve avant que ses adresses repondent. Jamais vu avec une
    /// adresse, il n'est range nulle part (ni Thread, ni appareils IP) et n'entre pas au journal ; quand son adresse
    /// repond, il va dans les appareils IP, sans evenement (comme un appareil IP arrive avec son adresse). Il n'a jamais
    /// ete perdu.
    @Test func sansAdressePuisSurIPAttendSonAdresse() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.appareil(Self.ip, noeud: 9, adresses: [])
        #expect(s.integrer(b.annonces).isEmpty, "sans adresse : rien au journal")
        #expect(s.instantane?.appareil(Self.ip) == nil, "sans adresse : range nulle part")
        #expect(s.instantane?.appareils.map(\.id) == [Self.a1, Self.a2])
        #expect(s.instantane?.appareilsIP.isEmpty == true)

        // Il reste en attente, meme au-dela du sursis de 2 min : ni perdu, ni nouveau.
        for t in [120.0, 180, 240] {
            b.date = Self.t0 + t
            #expect(s.integrer(b.annonces).isEmpty)
        }
        #expect(s.disparus.isEmpty)

        b.date = Self.t0 + 300
        b.adresses[Self.ip + ".local"] = [Self.adresseIP]
        let ev = s.integrer(b.annonces)
        #expect(ev.isEmpty, "comme un appareil IP arrive directement avec son adresse : aucun evenement")
        #expect(s.disparus.isEmpty)
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.ip])
        #expect(s.instantane?.appareils.contains { $0.id == Self.ip } == false)

        b.date = Self.t0 + 360
        #expect(s.integrer(b.annonces).isEmpty, "une seule fois")
    }

    /// Meme attente, mais l'adresse qui repond est une adresse Thread : il va dans Thread, nouveau, une seule fois.
    @Test func sansAdressePuisThreadAttendSonAdresse() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.appareil(Self.neuf, noeud: 9, adresses: [])
        #expect(s.integrer(b.annonces).isEmpty)
        #expect(s.instantane?.appareil(Self.neuf) == nil)

        b.date = Self.t0 + 120
        b.adresses[Self.neuf + ".local"] = [Self.adresseNeuf]
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilNouveau], "nouveau, pas revenu")
        #expect(ev.first?.apres == "73586B68")
        #expect(s.instantane?.appareils.first { $0.id == Self.neuf }?.genre == .thread)

        b.date = Self.t0 + 180
        #expect(s.integrer(b.annonces).isEmpty, "une seule fois")
    }

    /// Un appareil sans adresse des le premier releve du lancement n'est pas range : il attend son adresse. Quand elle
    /// repond sur IP, il arrive sans evenement (il etait la au depart).
    @Test func sansAdresseDesLeLancementPuisSurIP() throws {
        var b = Self.banc(Self.t0)
        b.appareil(Self.ip, noeud: 9, adresses: [])
        var s = Suivi()
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree])
        #expect(ev.first?.details["appareils"] == "2")
        #expect(s.instantane?.appareil(Self.ip) == nil)

        b.date = Self.t0 + 60
        b.adresses[Self.ip + ".local"] = [Self.adresseIP]
        #expect(s.integrer(b.annonces).isEmpty, "present au depart : ni nouveau, ni autre evenement")
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.ip])
        b.date = Self.t0 + 120
        #expect(s.integrer(b.annonces).isEmpty)
    }

    /// Meme chose quand l'adresse qui repond est une adresse Thread : il entre dans Thread sans evenement (ni nouveau, ni
    /// revenu), une fois pour toutes.
    @Test func sansAdresseDesLeLancementPuisThread() throws {
        var b = Self.banc(Self.t0)
        b.appareil(Self.neuf, noeud: 9, adresses: [])
        var s = Suivi()
        #expect(s.integrer(b.annonces).map(\.type) == [.surveillanceDemarree])
        #expect(s.instantane?.appareil(Self.neuf) == nil)

        b.date = Self.t0 + 60
        #expect(s.integrer(b.annonces).isEmpty, "toujours en attente")
        b.date = Self.t0 + 120
        b.adresses[Self.neuf + ".local"] = [Self.adresseNeuf]
        #expect(s.integrer(b.annonces).isEmpty, "present au depart : aucun evenement")
        #expect(s.instantane?.appareils.first { $0.id == Self.neuf }?.genre == .thread)
        b.date = Self.t0 + 180
        #expect(s.integrer(b.annonces).isEmpty)
    }

    /// Un appareil present des le depart avec son adresse (Thread ou IP) reste silencieux : compte au depart, rien ensuite.
    @Test func presentDesLeLancementAvecSonAdresseResteSilencieux() throws {
        var b = Self.banc(Self.t0)
        b.appareil(Self.ip, noeud: 9, adresses: [Self.adresseIP])
        b.appareil(Self.neuf, noeud: 10, adresses: [Self.adresseNeuf])
        var s = Suivi()
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.surveillanceDemarree])
        #expect(ev.first?.details["appareils"] == "3", "a1, a2 et l'appareil Thread ; l'appareil IP est hors de Thread")
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.ip])
        for t in [60.0, 120, 180] {
            b.date = Self.t0 + t
            #expect(s.integrer(b.annonces).isEmpty)
        }
    }

    /// Le depart n'est que le premier releve : un appareil vu sans adresse seulement apres lui reste nouveau (sur Thread),
    /// meme si un autre, sans adresse des le depart, est arrive sans bruit au meme releve.
    @Test func attenteDuDepartNExemptePasLesAutres() throws {
        var b = Self.banc(Self.t0)
        b.appareil(Self.neuf, noeud: 9, adresses: [])
        var s = Suivi()
        _ = s.integrer(b.annonces)

        let tard = "AAAA00000000000A"
        b.date = Self.t0 + 60
        b.appareil(tard, noeud: 10, adresses: [])
        #expect(s.integrer(b.annonces).isEmpty)

        b.date = Self.t0 + 120
        b.adresses[Self.neuf + ".local"] = [Self.adresseNeuf]
        b.adresses[tard + ".local"] = ["fd19:961f:2db3::1a"]
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilNouveau], "seul celui vu apres le depart est nouveau")
        #expect(ev.first?.sujet?.id == tard)
    }

    /// Un appareil deja vu sur le reseau local qui perd ses adresses reste hors de Thread : jamais range en "sans adresse"
    /// parmi les noeuds Thread, jamais disparu, rien au journal ; son retour sur IP n'est pas un nouvel appareil.
    @Test func appareilIPSansAdresseResteHorsDeThread() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.appareil(Self.ip, noeud: 9, adresses: [Self.adresseIP])
        _ = s.integrer(b.annonces)
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.ip])

        b.adresses[Self.ip + ".local"] = []
        for t in [120.0, 180, 240, 300] {
            b.date = Self.t0 + t
            let ev = s.integrer(b.annonces)
            #expect(ev.isEmpty, "rien au journal : ni sans adresse, ni disparu, ni nouveau")
            #expect(s.instantane?.appareils.contains { $0.id == Self.ip } == false, "hors de Thread")
            #expect(s.disparus.isEmpty)
        }

        b.date = Self.t0 + 360
        b.adresses[Self.ip + ".local"] = [Self.adresseIP]
        #expect(s.integrer(b.annonces).isEmpty, "deja vu : pas nouveau")
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.ip])
        #expect(s.disparus.isEmpty)
    }

    /// Un noeud Thread vu une fois « sur IP » (releve mal resolu : plus que des adresses locales) reste un noeud Thread : s'il
    /// perd ensuite ses adresses, il est « sans adresse » dans Thread, jamais retenu en silence (relecture finale, M1).
    @Test func noeudThreadVuUneFoisSurIPResteThread() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.appareil(Self.neuf, noeud: 9, adresses: [Self.adresseNeuf])
        _ = s.integrer(b.annonces)
        #expect(s.instantane?.appareils.contains { $0.id == Self.neuf } == true)

        b.date = Self.t0 + 120
        b.adresses[Self.neuf + ".local"] = [Self.adresseIP]
        _ = s.integrer(b.annonces)
        #expect(s.disparus.isEmpty)

        b.adresses[Self.neuf + ".local"] = []
        var types: [TypeEvenement] = []
        for t in [180.0, 240, 300, 360] {
            b.date = Self.t0 + t
            types += s.integrer(b.annonces).map(\.type)
        }
        #expect(s.instantane?.appareils.first { $0.id == Self.neuf }?.genre == .sansAdresse, "toujours dans Thread")
        #expect(s.disparus.isEmpty)
        #expect(types.contains(.appareilSansAdresse), "signale, pas retenu en silence : \(types)")
        #expect(!types.contains(.appareilNouveau) && !types.contains(.appareilDisparu), "ni nouveau ni disparu : \(types)")
    }

    /// Un appareil Thread connu (deja vu avec une adresse Thread) qui perd son adresse garde l'etat "sans adresse" dans
    /// Thread, que la session l'ait vu des le lancement ou apres son attente.
    @Test func appareilThreadConnuSansAdresseResteDansThread() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.appareil(Self.neuf, noeud: 9, adresses: [])
        _ = s.integrer(b.annonces)
        b.date = Self.t0 + 120
        b.adresses[Self.neuf + ".local"] = [Self.adresseNeuf]
        _ = s.integrer(b.annonces)

        b.date = Self.t0 + 180
        b.adresses[Self.neuf + ".local"] = []
        #expect(s.integrer(b.annonces).isEmpty, "sursis de 2 min")
        b.date = Self.t0 + 300
        let ev = s.integrer(b.annonces)
        #expect(ev.map(\.type) == [.appareilSansAdresse])
        #expect(s.instantane?.appareils.first { $0.id == Self.neuf }?.etat == .sansAdresse)
        #expect(s.disparus.isEmpty)

        // Celui du lancement aussi (a2 est deja couvert par `sansAdresse`) : a1 perd son adresse puis la retrouve.
        b.adresses[Self.a1 + ".local"] = []
        for t in [360.0, 420, 480] {
            b.date = Self.t0 + t
            _ = s.integrer(b.annonces)
        }
        #expect(s.instantane?.appareils.first { $0.id == Self.a1 }?.genre == .sansAdresse)
    }

    /// Ce qu'un lancement precedent avait garde (adresse Thread) rend un appareil "connu" : sans adresse au premier releve,
    /// il reste dans Thread (sans adresse) et la sonde peut le redemander.
    @Test func appareilGardeSansAdresseAuLancementResteDansThread() throws {
        var s = Suivi()
        s.amorcer([Self.neuf: .init(adresse: AdresseIPv6(Self.adresseNeuf)!, partition: "73586B68", annonce: Self.t0 - 600)])
        var b = Self.banc(Self.t0)
        b.appareil(Self.neuf, noeud: 9, adresses: [])
        _ = s.integrer(b.annonces)
        #expect(s.instantane?.appareils.first { $0.id == Self.neuf }?.etat == .sansAdresse)
    }

    /// Un disparu qui revient sur le reseau local n'est plus garde parmi les disparus : il est la, dans les appareils IP.
    @Test func disparuRevenuSurIPNestPlusDisparu() throws {
        var s = Self.demarre()
        var b = Self.banc(Self.t0 + 60)
        b.retirer(Self.a2)
        for t in [120.0, 180, 240] {
            b.date = Self.t0 + t
            _ = s.integrer(b.annonces)
        }
        #expect(Array(s.disparus.keys) == [Self.a2], "absent plus de 2 min : disparu")

        b.date = Self.t0 + 300
        b.appareil(Self.a2, noeud: 2, adresses: [Self.adresseIP])
        let ev = s.integrer(b.annonces)
        #expect(!ev.contains { $0.type == .appareilDisparu })
        #expect(s.disparus.isEmpty, "revenu sur le reseau local : plus perdu")
        #expect(s.instantane?.appareilsIP.map(\.id) == [Self.a2])
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
        // Le decodeur du journal connait les types de Thread (sans eux, un type garderait la gravite `info`).
        let decodeur = CodageJSON.decodeur()
        decodeur.userInfo[.typesEvenement] = PolitiqueJournalThread().typesParNom
        #expect(try decodeur.decode(Evenement.self, from: json) == e)
        let ancien = Data(#"{"date":"2026-09-27T00:14:00Z","type":"appareilDisparu"}"#.utf8)
        let lu = try decodeur.decode(Evenement.self, from: ancien)
        #expect(lu.gravite == .attention && !lu.constate && lu.details.isEmpty, "champs manquants : valeurs par defaut")
        #expect(e.id == "1790000000000-thread-reseauScinde-4B36A2B7FEFB200B", "l'identifiant porte le protocole (Thread sans protocole)")
    }
}
