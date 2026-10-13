import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleThread

@Suite("Protocole USB de la sonde")
struct ProtocoleSondeTests {
    static func messages() throws -> [MessageSonde] {
        try CaptureSonde.lignes().compactMap { MessageSonde.lire(Data($0.utf8)) }
    }

    /// Ligne JSON `erreur` de `octets` octets exactement (ASCII) : le message est complete par des `x`.
    static func jsonErreur(octets: Int) -> (json: String, message: String) {
        let debut = #"{"v":1,"t":"erreur","erreur":""#, fin = #""}"#
        let message = String(repeating: "x", count: octets - debut.utf8.count - fin.utf8.count)
        return (debut + message + fin, message)
    }

    /// Toute la capture se relit : 2 bonjour, 9 etat, 53 diag.
    @Test func capture() throws {
        let m = try Self.messages()
        #expect(m.count == 64)
        let bonjours = m.compactMap { if case .bonjour(let b) = $0 { b } else { nil } }
        #expect(bonjours.count == 2)
        #expect(bonjours.allSatisfy { $0.estSonde })
        #expect(bonjours.first?.version == "0.1.0-essai")
        #expect(bonjours.first?.appairee == false)
        #expect(bonjours.allSatisfy { $0.nom == nil }, "firmware d'essai : pas de nom")
        let etats = m.compactMap { if case .etat(let e) = $0 { e } else { nil } }
        #expect(etats.count == 9)
        #expect(etats.filter(\.estAttachee).count == 4, "5 releves avant l'appairage")
        let diags = m.compactMap { if case .diag(let d) = $0 { d } else { nil } }
        #expect(diags.count == 53)
    }

    /// Etat attache : parent, partition, chef, prefixe du reseau maille.
    @Test func etatAttache() throws {
        let e = try #require(try Self.messages().compactMap { if case .etat(let e) = $0, e.estAttachee { e } else { nil } }.first)
        #expect(e.role == "child")
        #expect(e.rloc16Valeur == 0xE401)
        #expect(e.parent == ParentSonde(rloc16: "E400", ext: "E000000000000001", lqIn: 3, lqOut: 3, rssi: -76))
        #expect(e.partition == "46CBEBCD")
        #expect(e.chef == 24)
        #expect(e.prefixeMaille == "FD00111122220C87")
        #expect(!e.suspendue)
        #expect(e.ext == nil, "firmware d'essai : pas d'ExtMac")
        let v1 = #"{"v":1,"t":"etat","role":"child","rloc16":"AC09","ext":"E0000000000000FF","mode":"rn","parent":null,"partition":"46CBEBCD","chef":24,"canal":25,"prefixeMaille":null,"xp":null,"suspendue":true}"#
        guard case .etat(let e1)? = MessageSonde.lire(Data(v1.utf8)) else {
            Issue.record("etat 1.0.0 illisible")
            return
        }
        #expect(e1.ext == "E0000000000000FF")
        #expect(e1.suspendue)
    }

    /// Sonde detachee (ou eteinte) : le firmware rend `FFFE`, l'adresse courte invalide, sans
    /// partition ni chef. La valeur se lit (0xFFFE), mais la sonde n'est pas attachee : la
    /// tournee ne la prend pas pour son RLOC16 (`estAttachee`). Les 5 releves de la capture
    /// avant l'appairage (role `disabled`) sont dans le meme cas.
    @Test func rloc16DUneSondeDetachee() throws {
        let detache = #"{"v":1,"t":"etat","role":"detached","rloc16":"FFFE","mode":"rn","parent":null,"partition":null,"chef":null,"canal":25,"prefixeMaille":null,"xp":null,"suspendue":false}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(detache.utf8)) else {
            Issue.record("etat detache illisible")
            return
        }
        #expect(e.rloc16Valeur == 0xFFFE)
        #expect(!e.estAttachee)
        let sansAttache = try Self.messages().compactMap { if case .etat(let e) = $0, !e.estAttachee { e } else { nil } }
        #expect(sansAttache.count == 5)
        #expect(sansAttache.allSatisfy { $0.role == "disabled" && $0.rloc16Valeur == 0xFFFE })
    }

    /// bonjour du firmware 1.0.1 : nom, code et QR code, meme appairee (valeurs inventees) ;
    /// celui de la 1.0.0 n'a pas de nom.
    @Test func bonjourNom() {
        let v101 = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.1","nom":"SONDE-01","mac":"A00000000001","appairee":true,"code":"12345678901","qr":"MT:ABCDEFGHIJ0123456789"}"#
        guard case .bonjour(let b)? = MessageSonde.lire(Data(v101.utf8)) else {
            Issue.record("bonjour 1.0.1 illisible")
            return
        }
        #expect(b.nom == "SONDE-01")
        #expect(b.appairee)
        #expect(b.code == "12345678901")
        #expect(b.qr == "MT:ABCDEFGHIJ0123456789")
        let v100 = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.0","mac":"A00000000001","appairee":true,"code":null,"qr":null}"#
        guard case .bonjour(let a)? = MessageSonde.lire(Data(v100.utf8)) else {
            Issue.record("bonjour 1.0.0 illisible")
            return
        }
        #expect(a.estSonde)
        #expect(a.nom == nil)
        #expect(a.code == nil && a.qr == nil)
    }

    /// bonjour du firmware 1.0.2 : nom d'hote SRP, sans `.local` (valeur inventee), nul tant
    /// qu'il n'est pas connu ; absent des firmwares precedents.
    @Test func bonjourHote() {
        let base = #""v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.2","nom":"SONDE-01","mac":"A00000000001","appairee":true,"code":"12345678901","qr":"MT:ABCDEFGHIJ0123456789""#
        guard case .bonjour(let b)? = MessageSonde.lire(Data(("{" + base + #","hote":"0123456789ABCDEF"}"#).utf8)),
              case .bonjour(let inconnu)? = MessageSonde.lire(Data(("{" + base + #","hote":null}"#).utf8)),
              case .bonjour(let ancien)? = MessageSonde.lire(Data(("{" + base + "}").utf8)) else {
            Issue.record("bonjour 1.0.2 illisible")
            return
        }
        #expect(b.hote == "0123456789ABCDEF")
        #expect(inconnu.hote == nil, "pas encore enregistre par SRP")
        #expect(ancien.hote == nil, "firmware 1.0.1")
    }

    /// `estSonde` : seul le produit exact est une sonde. Un autre produit (le pont Halo, un autre
    /// firmware), une autre casse, un espace de trop ou un produit vide se lisent, mais ne sont
    /// pas une sonde : l'app refuse alors le port. Sans `produit`, la ligne est illisible.
    @Test func estSondeNegatif() {
        func bonjour(produit: String) -> Bonjour? {
            let json = #"{"v":1,"t":"bonjour","produit":"\#(produit)","version":"1.0.2","mac":"A00000000001","appairee":true}"#
            guard case .bonjour(let b)? = MessageSonde.lire(Data(json.utf8)) else { return nil }
            return b
        }
        #expect(bonjour(produit: ProtocoleSonde.produit)?.estSonde == true, "le produit attendu")
        for autre in ["halo", "Sonde-Maillage", "sonde-maillage ", "sonde", ""] {
            let lu = bonjour(produit: autre)
            #expect(lu != nil, "\(autre) : bonjour lisible")
            #expect(lu?.estSonde == false, "\(autre) : pas une sonde")
        }
        let sansProduit = #"{"v":1,"t":"bonjour","version":"1.0.2","mac":"A00000000001","appairee":true}"#
        #expect(MessageSonde.lire(Data(sansProduit.utf8)) == nil, "sans produit : illisible")
    }

    /// Cle des vecteurs H1 (00..1F) et son empreinte (8 premiers hexa de SHA-256).
    static let cleVecteurs = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F"

    /// `cle` : reponse a `cle nouvelle` (la cle, une seule fois, avec l'id de la demande et le
    /// nom d'hote) et a `cle` (l'empreinte seule, nulle sans cle).
    @Test func messageCle() {
        let nouvelle = #"{"v":1,"t":"cle","id":7,"cle":"\#(Self.cleVecteurs)","empreinte":"630DCD29","hote":"0123456789ABCDEF"}"#
        guard case .cle(let r)? = MessageSonde.lire(Data(nouvelle.utf8)) else {
            Issue.record("cle illisible")
            return
        }
        #expect(r.id == 7)
        #expect(r.cle == Self.cleVecteurs)
        #expect(r.empreinte == "630DCD29")
        #expect(r.hote == "0123456789ABCDEF")
        let sansHote = #"{"v":1,"t":"cle","id":8,"cle":"\#(Self.cleVecteurs)","empreinte":"630DCD29","hote":null}"#
        guard case .cle(let s)? = MessageSonde.lire(Data(sansHote.utf8)) else {
            Issue.record("cle sans hote illisible")
            return
        }
        #expect(s.hote == nil)
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"cle","empreinte":"630DCD29"}"#.utf8))
                == .cle(ReponseCle(id: nil, cle: nil, empreinte: "630DCD29", hote: nil)))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"cle","empreinte":null}"#.utf8))
                == .cle(ReponseCle(id: nil, cle: nil, empreinte: nil, hote: nil)))
    }

    /// La cle n'apparait dans aucune description (journal, console, message d'erreur) :
    /// ni celle de la reponse, ni celle du message, ni un dump.
    @Test func cleMasquee() {
        let r = ReponseCle(id: 7, cle: Self.cleVecteurs, empreinte: "630DCD29", hote: "0123456789ABCDEF")
        var vidage = ""
        dump(r, to: &vidage)
        var vidageMessage = ""
        dump(MessageSonde.cle(r), to: &vidageMessage)
        let textes = [String(describing: r), String(reflecting: r), "\(r)", vidage, vidageMessage,
                      String(describing: MessageSonde.cle(r)), String(reflecting: MessageSonde.cle(r))]
        for t in textes {
            #expect(!t.contains("000102030405"), "cle visible")
        }
        #expect(String(describing: r).contains("630DCD29"), "l'empreinte reste")
    }

    /// Firmware 1.0.2 : `code` et `qr` nuls (par le reseau), `etat.eligible`, `udp` et `tas` dans
    /// la reponse `cle` : tout se lit.
    @Test func toleranceDuFirmware102() {
        let bonjour = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.0.2","nom":"SONDE-01","mac":"A00000000001","appairee":true,"code":null,"qr":null,"hote":"0123456789ABCDEF"}"#
        let etat = #"{"v":1,"t":"etat","role":"child","rloc16":"AC09","ext":"E0000000000000FF","mode":"rdn","eligible":false,"parent":null,"partition":"46CBEBCD","chef":24,"canal":25,"prefixeMaille":null,"xp":null,"suspendue":false}"#
        let cle = #"{"v":1,"t":"cle","id":7,"cle":"\#(Self.cleVecteurs)","empreinte":"630DCD29","hote":"0123456789ABCDEF","udp":{"port":5480,"ouvert":true},"tas":123456}"#
        guard case .bonjour(let b)? = MessageSonde.lire(Data(bonjour.utf8)),
              case .etat(let e)? = MessageSonde.lire(Data(etat.utf8)),
              case .cle(let r)? = MessageSonde.lire(Data(cle.utf8)) else {
            Issue.record("message 1.0.2 illisible")
            return
        }
        #expect(b.code == nil && b.qr == nil && b.hote == "0123456789ABCDEF")
        #expect(e.mode == "rdn" && e.partition == "46CBEBCD")
        #expect(r.id == 7 && r.empreinte == "630DCD29" && r.hote == "0123456789ABCDEF")
    }

    /// Diag : reussi (TLV decodees) et echoue (delai, occupee).
    @Test func diag() throws {
        let diags = try Self.messages().compactMap { if case .diag(let d) = $0 { d } else { nil } }
        let ok = try #require(diags.first { $0.id == 104 })
        #expect(ok.ok && ok.ms == 73 && ok.code == "2.04")
        #expect(ok.reponse?.rloc16 == 0x5000)
        let delai = try #require(diags.first { $0.id == 102 })
        #expect(!delai.ok && delai.erreur == "delai" && delai.reponse == nil)
        #expect(diags.first { $0.id == 402 }?.erreur == "occupee")
    }

    /// `etat` et `voisins` que la sonde n'a pas pu servir (verrou d'OpenThread refuse) : la commande
    /// et l'erreur, pour que l'app le dise tout de suite, sans attendre l'echeance.
    @Test func refusees() {
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"etat","erreur":"occupee"}"#.utf8))
                == .refusee(commande: "etat", erreur: "occupee"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"voisins","erreur":"occupee"}"#.utf8))
                == .refusee(commande: "voisins", erreur: "occupee"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"etat","role":"child"}"#.utf8)) == nil, "ni etat lisible, ni erreur")
    }

    @Test func autres() {
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"voisins","liste":[{"rloc16":"AC00","ext":"E000000000000007","rssi":-89,"lqi":3,"routeur":true}]}"#.utf8))
                == .voisins([VoisinSonde(rloc16: "AC00", ext: "E000000000000007", rssi: -89, lqi: 3, routeur: true)]))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"erreur","erreur":"commande inconnue"}"#.utf8)) == .erreur("commande inconnue"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"nouveau"}"#.utf8)) == .inconnu("nouveau"))
        #expect(MessageSonde.lire(Data(#"{"v":2,"t":"etat"}"#.utf8)) == nil, "autre version")
        #expect(MessageSonde.lire(Data("pas du json".utf8)) == nil)
    }

    /// `routeurs` (firmware 1.0.2, en FED) : une partie de la table par ligne, `suite` sur chaque
    /// ligne sauf la derniere ; `ext` nul pour un routeur jamais entendu (le parent compris) ;
    /// l'erreur `occupee` quand le verrou d'OpenThread est refuse (ExtMac inventees).
    @Test func routeurs() {
        let ligne = #"{"v":1,"t":"routeurs","liste":[{"id":43,"rloc16":"AC00","ext":null,"lqIn":0,"lqOut":0,"age":12,"lien":false},{"id":57,"rloc16":"E400","ext":"E0000000000000E4","lqIn":3,"lqOut":3,"age":4,"lien":true}],"suite":false}"#
        let e400 = RouteurSonde(id: 57, rloc16: "E400", ext: "E0000000000000E4", lqIn: 3, lqOut: 3, age: 4, lien: true)
        guard case .routeurs(let p)? = MessageSonde.lire(Data(ligne.utf8)) else {
            Issue.record("routeurs illisible")
            return
        }
        #expect(p.liste.count == 2)
        #expect(p.liste.first?.ext == nil, "le parent : jamais d'ExtMac dans la table")
        #expect(p.liste.last == e400)
        #expect(p.liste.last?.rloc16Valeur == 0xE400)
        #expect(!p.suite && p.erreur == nil)
        let coupee = #"{"v":1,"t":"routeurs","liste":[{"id":1,"rloc16":"0400","ext":null,"lqIn":0,"lqOut":0,"age":200,"lien":false}],"suite":true}"#
        guard case .routeurs(let debut)? = MessageSonde.lire(Data(coupee.utf8)) else {
            Issue.record("routeurs coupe illisible")
            return
        }
        #expect(debut.suite && debut.liste.map(\.rloc16) == ["0400"])
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"routeurs","erreur":"occupee"}"#.utf8))
                == .routeurs(PartieRouteurs(liste: [], suite: false, erreur: "occupee")))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"routeurs","suite":false}"#.utf8)) == nil, "ni liste ni erreur")
    }

    /// `etat` du firmware 1.1.0 : les compteurs de l'ecoute (`ecoute`) ; un firmware plus ancien n'en a pas.
    @Test func etatEcoute() throws {
        let base = #""v":1,"t":"etat","role":"child","rloc16":"AC09","ext":"E0000000000000FF","mode":"rdn","eligible":false,"parent":null,"partition":"1234ABCD","chef":20,"canal":25,"prefixeMaille":"FD00111122220C87","xp":"A0A1A2A3A4A5A6A7","suspendue":false"#
        guard case .etat(let e)? = MessageSonde.lire(Data(("{" + base + #","ecoute":{"trames":1200,"mle":340,"echecs":2,"file_pleine":1}}"#).utf8)),
              case .etat(let ancien)? = MessageSonde.lire(Data(("{" + base + "}").utf8)) else {
            Issue.record("etat 1.1.0 illisible")
            return
        }
        #expect(e.ecoute == CompteursEcoute(trames: 1200, mle: 340, echecs: 2, filePleine: 1))
        #expect(ancien.ecoute == nil, "firmware 1.0.3")
    }

    /// `annonces` (firmware 1.1.0) : une ligne par routeur entendu, `suite` sur chaque ligne sauf la derniere ;
    /// sans routeur entendu, une ligne `vide`. La Route64 brute se decode comme celle du diagnostic (valeurs
    /// inventees : la Route64 des routeurs 1, 20 et 43).
    @Test func annonces() throws {
        let route = "7A" + "4000080000100000" + "F10092"
        let ligne = #"{"v":1,"t":"annonces","rloc16":"5000","ext":"E000000000000A01","partition":"1234ABCD","route64":"\#(route)","seq":122,"rssi":-61,"rssi_min":-70,"rssi_max":-55,"nb":12,"age_s":7,"suite":true}"#
        guard case .annonces(let p)? = MessageSonde.lire(Data(ligne.utf8)) else {
            Issue.record("annonces illisible")
            return
        }
        #expect(p.suite)
        let a = try #require(p.liste.first)
        #expect(p.liste.count == 1)
        #expect(a == AnnonceSonde(rloc16: "5000", ext: "E000000000000A01", partition: "1234ABCD", route64: route, seq: 122,
                                  rssi: -61, rssiMin: -70, rssiMax: -55, nb: 12, ageS: 7))
        #expect(a.rloc16Valeur == 0x5000)
        let r64 = try #require(a.route64Decodee)
        #expect(r64.sequence == 0x7A && r64.routeurs == [1, 20, 43])
        #expect(r64.route(vers: 43) == RouteRouteur(idRouteur: 43, qualiteSortante: 2, qualiteEntrante: 1, cout: 2))
        let derniere = #"{"v":1,"t":"annonces","rloc16":"AC00","ext":"E000000000000C03","partition":null,"route64":null,"seq":null,"rssi":-80,"rssi_min":-80,"rssi_max":-80,"nb":1,"age_s":0,"suite":false}"#
        guard case .annonces(let fin)? = MessageSonde.lire(Data(derniere.utf8)) else {
            Issue.record("derniere annonce illisible")
            return
        }
        #expect(!fin.suite && fin.liste.first?.partition == nil && fin.liste.first?.route64Decodee == nil)
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"annonces","vide":true}"#.utf8))
                == .annonces(PartieAnnonces(liste: [], suite: false)))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"annonces","rloc16":"5000"}"#.utf8)) == nil, "ni annonce lisible, ni vide")
        let abimee = AnnonceSonde(rloc16: "5000", ext: "E000000000000A01", partition: nil, route64: "7A40", seq: nil,
                                  rssi: -61, rssiMin: -61, rssiMax: -61, nb: 1, ageS: 0)
        #expect(abimee.route64Decodee == nil, "Route64 trop courte")
    }

    /// `resoudre` (firmware 1.1.0) : le RLOC16 trouve et le ML-EID (32 hexa) si le cache le donne ; ou
    /// `introuvable`, ou un refus (valeurs inventees).
    @Test func resoudre() throws {
        let ok = #"{"v":1,"t":"resoudre","id":7,"cible":"fd00:aaaa:bbbb:1::17","ok":true,"ms":340,"rloc16":"AC00","mleid":"FD00111122220C870000000000000017"}"#
        guard case .resoudre(let r)? = MessageSonde.lire(Data(ok.utf8)) else {
            Issue.record("resoudre illisible")
            return
        }
        #expect(r.ok && r.id == 7 && r.cible == "fd00:aaaa:bbbb:1::17" && r.ms == 340)
        #expect(r.rloc16Valeur == 0xAC00)
        #expect(r.adresseMleid == AdresseIPv6("fd00:1111:2222:c87::17"))
        #expect(!r.introuvable)
        let sansMleid = #"{"v":1,"t":"resoudre","id":8,"cible":"fd00:aaaa:bbbb:1::18","ok":true,"ms":90,"rloc16":"5003","mleid":null}"#
        guard case .resoudre(let s)? = MessageSonde.lire(Data(sansMleid.utf8)) else {
            Issue.record("resoudre sans ML-EID illisible")
            return
        }
        #expect(s.rloc16Valeur == 0x5003 && s.adresseMleid == nil)
        let introuvable = #"{"v":1,"t":"resoudre","id":9,"cible":"fd00:aaaa:bbbb:1::19","ok":false,"erreur":"introuvable"}"#
        guard case .resoudre(let i)? = MessageSonde.lire(Data(introuvable.utf8)) else {
            Issue.record("resoudre introuvable illisible")
            return
        }
        #expect(i.introuvable && i.rloc16Valeur == nil)
        #expect(ResultatResolution(id: 1, cible: "fd00::1", ok: false, erreur: "occupee").introuvable == false)
        #expect(r.repondu == nil && s.repondu == nil && i.repondu == nil, "firmware 1.1.0 : le champ est absent")
    }

    /// `repondu` (firmware 1.1.1) : vrai si l'appareil a repondu a la sonde, faux si seule une entree du cache
    /// d'adresses l'a donne ; absent (nil) avec un firmware plus ancien.
    @Test func resoudreRepondu() throws {
        func lire(_ repondu: String) -> ResultatResolution? {
            let json = #"{"v":1,"t":"resoudre","id":7,"cible":"fd00:aaaa:bbbb:1::17","ok":true,"ms":340,"#
                + #""rloc16":"AC00","# + repondu + #""mleid":null}"#
            if case .resoudre(let r)? = MessageSonde.lire(Data(json.utf8)) { return r }
            return nil
        }
        #expect(lire(#""repondu":true,"#)?.repondu == true)
        #expect(lire(#""repondu":false,"#)?.repondu == false)
        #expect(lire("")?.repondu == nil)
        #expect(lire(#""repondu":true,"#)?.rloc16Valeur == 0xAC00, "le reste est lu comme avant")
    }

    /// Commandes du firmware 1.1.0 : l'adresse IPv6 part sans zone, sous la forme courte (`AdresseIPv6`).
    @Test func commandesToutEnUn() throws {
        let a = try #require(AdresseIPv6("fd00:aaaa:bbbb:1::17%en0"))
        #expect(CommandeSonde.annonces.ligne == "annonces\n")
        #expect(CommandeSonde.resoudre(adresse: a, id: 7).ligne == "resoudre fd00:aaaa:bbbb:1::17 7\n")
        let mleid = try #require(AdresseIPv6("fd00:1111:2222:c87::17"))
        #expect(CommandeSonde.diagAdresse(cible: mleid, tlv: [9], id: 8, delaiMs: 8000).ligne
                == "diag fd00:1111:2222:c87::17 9 8 8000\n")
    }

    @Test func commandes() {
        #expect(CommandeSonde.bonjour.ligne == "bonjour\n")
        #expect(CommandeSonde.etat.ligne == "etat\n")
        #expect(CommandeSonde.voisins.ligne == "voisins\n")
        #expect(CommandeSonde.routeurs.ligne == "routeurs\n")
        #expect(CommandeSonde.diag(cible: 0x5000, tlv: [0, 1, 5, 16, 8, 24], id: 12, delaiMs: 6000).ligne
                == "diag 5000 0,1,5,16,8,24 12 6000\n")
        #expect(CommandeSonde.diag(cible: 0x0400, tlv: [7], id: 3, delaiMs: nil).ligne == "diag 0400 7 3\n")
        // Alea de l'app en 64 hexa MAJUSCULES, id decimal obligatoire.
        let alea = Data((0..<32).map { UInt8(0xE0 &+ $0) })
        #expect(CommandeSonde.cleNouvelle(alea: alea, id: 12).ligne
                == "cle nouvelle E0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF 12\n")
    }

    /// Lignes machine seulement, meme coupees en morceaux ; lignes humaines et trop longues ignorees.
    @Test func decoupage() {
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data("I (123) chip: log\n\u{1E}{\"v\":1,".utf8)).isEmpty)
        let l = d.ajouter(Data("\"t\":\"etat\"}\r\n\u{1E}{}\n".utf8))
        #expect(l == [Data(#"{"v":1,"t":"etat"}"#.utf8), Data("{}".utf8)])
        var long = Data([ProtocoleSonde.separateur]) + Data(repeating: 0x41, count: 5000)
        long.append(0x0A)
        #expect(d.ajouter(long + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)])
    }

    // Une ligne machine commence au dernier RS de la ligne, comme dans le pont Halo (le JSON est de
    // l'ASCII imprimable : jamais de RS dedans) ; ce qui precede le RS sur la ligne est abandonne.

    /// Du texte sans fin de ligne juste avant le RS (queue d'un log coupe, invite d'une session humaine) :
    /// la ligne machine intacte est retrouvee, dans le meme morceau ou dans le suivant.
    @Test func decoupageTexteAvantLeRS() {
        let json = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data("E (48213) chip[DL]: fin d'un log\u{1E}\(json)\n".utf8)) == [Data(json.utf8)],
                "queue de log et ligne machine dans le meme morceau")
        #expect(d.ajouter(Data("> ".utf8)).isEmpty)
        #expect(d.ajouter(Data("\u{1E}\(json)\r\n".utf8)) == [Data(json.utf8)], "invite, puis la ligne dans le morceau suivant")
    }

    /// Ligne machine coupee (RS et debut du JSON) suivie d'une ligne complete : seule la complete sort,
    /// et non les deux collees en une ligne que `lire` refuserait, la bonne perdue avec elle.
    @Test func decoupageLigneCoupee() {
        let coupee = #"{"v":1,"t":"diag","id":11,"cible":"5000","ok":true,"ms":73,"code":"2.04","tlv":"0E08"#
        let complete = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        let l = d.ajouter(Data("\u{1E}\(coupee)\u{1E}\(complete)\n".utf8))
        #expect(l == [Data(complete.utf8)], "la coupee et la complete dans le meme morceau")
        #expect(l.compactMap { MessageSonde.lire($0) } == [.erreur("occupee")])
        #expect(d.ajouter(Data("\u{1E}\(coupee)".utf8)).isEmpty)
        #expect(d.ajouter(Data("\u{1E}\(complete)\n".utf8)) == [Data(complete.utf8)], "la complete dans le morceau suivant")
    }

    /// Un RS remet a zero l'etat "ligne trop longue" : la ligne machine qui le suit est retrouvee.
    @Test func decoupageRSApresUneLigneTropLongue() {
        let trop = Data(repeating: 0x41, count: 5000)
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data([ProtocoleSonde.separateur]) + trop + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)],
                "ligne machine trop longue, coupee")
        #expect(d.ajouter(trop + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)], "texte trop long, sans fin de ligne")
    }

    /// RS suivi aussitot de LF : une ligne machine vide. Elle sort vide (le RS est retire), `lire`
    /// la refuse, et la suite n'en souffre pas ; meme coupee entre deux morceaux, ou avec un CR.
    @Test func decoupageRSLF() {
        let json = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data([ProtocoleSonde.separateur, 0x0A])) == [Data()], "RS LF")
        #expect(MessageSonde.lire(Data()) == nil, "une ligne vide est illisible : ignoree")
        #expect(d.ajouter(Data([ProtocoleSonde.separateur])).isEmpty)
        #expect(d.ajouter(Data([0x0A])) == [Data()], "RS et LF dans deux morceaux")
        #expect(d.ajouter(Data([ProtocoleSonde.separateur, 0x0D, 0x0A])) == [Data()], "RS CR LF")
        #expect(d.ajouter(Data("\u{1E}\(json)\n".utf8)) == [Data(json.utf8)], "la ligne suivante est intacte")
    }

    /// Frontiere de la longueur : la limite (`longueurMax`, 4096) porte sur la ligne machine, RS
    /// compris et LF non compris. A 4096 octets la ligne passe, et `lire` la comprend ; a 4097
    /// elle est ecartee en entier, sans ligne coupee. (Le firmware n'en emet jamais plus de
    /// 4095, RS et LF compris : aucune ligne valide n'est perdue.)
    @Test func decoupageFrontiereDeLongueur() {
        #expect(ProtocoleSonde.longueurMax == 4096)
        let juste = Self.jsonErreur(octets: ProtocoleSonde.longueurMax - 1)  // avec le RS : 4096
        let trop = Self.jsonErreur(octets: ProtocoleSonde.longueurMax)  // avec le RS : 4097
        let suivante = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        let lignes = d.ajouter(Data("\u{1E}\(juste.json)\n".utf8))
        #expect(lignes == [Data(juste.json.utf8)], "4096 octets, RS compris : la ligne passe")
        #expect(lignes.compactMap { MessageSonde.lire($0) } == [.erreur(juste.message)], "et elle se lit")
        #expect(d.ajouter(Data("\u{1E}\(trop.json)\n".utf8)).isEmpty, "4097 octets : ecartee")
        #expect(d.ajouter(Data("\u{1E}\(suivante)\n".utf8)) == [Data(suivante.utf8)], "la ligne suivante est retrouvee")
    }

    /// Ligne trop longue coupee entre deux `ajouter` : l'etat "trop longue" passe d'un appel a
    /// l'autre. Ni la fin de la ligne, seule dans le morceau suivant, ni un reste qui ressemble a
    /// une ligne complete, ne sortent (surtout pas la ligne coupee a la limite) ; la limite
    /// franchie dans le second morceau, ou pile entre les deux, se traite comme dans un seul.
    @Test func decoupageTropLongueEntreDeuxMorceaux() {
        let limite = ProtocoleSonde.longueurMax
        let rs = Data([ProtocoleSonde.separateur]), lf = Data([0x0A])
        func remplissage(_ n: Int) -> Data { Data(repeating: 0x41, count: n) }
        let suivante = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        let ressemble = Data("\(suivante)\n".utf8)
        let cas: [(nom: String, morceaux: [Data], lignes: [Data])] = [
            ("limite franchie dans le premier morceau, LF seul ensuite",
             [rs + remplissage(5000), lf], []),
            ("idem, puis un reste qui ressemble a une ligne complete",
             [rs + remplissage(5000), ressemble], []),
            ("limite franchie dans le second morceau",
             [rs + remplissage(3000), remplissage(3000) + lf], []),
            ("pile a la limite, LF dans le second morceau",
             [rs + remplissage(limite - 1), lf], [remplissage(limite - 1)]),
            ("un octet de plus dans le second morceau",
             [rs + remplissage(limite - 1), remplissage(1) + lf], []),
        ]
        for (nom, morceaux, attendues) in cas {
            var d = DecoupeurLignes()
            var lignes: [Data] = []
            for m in morceaux { lignes += d.ajouter(m) }
            #expect(lignes == attendues, "\(nom)")
            #expect(d.ajouter(rs + ressemble) == [Data(suivante.utf8)], "\(nom) : la ligne suivante est retrouvee")
        }
    }
}
