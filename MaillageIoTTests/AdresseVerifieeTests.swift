import Foundation
@testable import MaillageCoeur
@testable import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

/// Appareil qui n'annonce plus d'adresse, verifie par la sonde (12/10) : trouve par la resolution, il est joignable,
/// rattache a son parent, sans alerte ni evenement ; pas trouve, son adresse est « non annoncee ». Valeurs inventees.
@MainActor
@Suite("Adresse non annoncee, verifiee par la sonde (app)")
struct AdresseVerifieeAppTests {
    static let partition = "0000AAAA"
    static let routeur = "Routeur inventé"
    /// Appareil Matter : son hote est son ExtMac.
    static let matter = "0000000000000001"
    /// Appareil dont l'hote n'est pas l'ExtMac (accessoire HomeKit) : reconnu a son adresse.
    static let hap = "Prise-inventee"
    static let temoin = "0000000000000003"

    static func adresse(_ n: Int) -> String { "fd00:aaaa:bbbb:1::\(n)" }

    /// Le chef de la partition, qui publie fd00:aaaa:bbbb:1::/64, et trois appareils ; `muets` : sans adresse ;
    /// `partis` : n'annoncent plus rien.
    static func annonces(_ date: Date, muets: Set<String> = [], partis: Set<String> = []) -> Annonces {
        let txt = ChampsTXT([
            "nn": Data("Maison inventee".utf8), "xp": Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
            "tv": Data("1.4.0".utf8), "pt": Data([0, 0, 0xAA, 0xAA]), "sb": Data([0, 0, 0x07, 0xB1]),
            "omr": Data([0x40, 0xFD, 0x00, 0xAA, 0xAA, 0xBB, 0xBB, 0x00, 0x01]),
            "xa": Data([0xE1, 0, 0, 0, 0, 0, 0, 0xA1]),
        ])
        var a = Annonces(date: date, routeurs: [AnnonceService(instance: routeur, hote: "Routeur-invente.local",
                                                                port: 49153, txt: txt)],
                         adresses: ["Routeur-invente.local": ["fe80::1"]])
        for (n, id) in [matter, hap, temoin].enumerated() where !partis.contains(id) {
            a.matter.append(AnnonceService(instance: String(format: "0000000000000F01-%016X", n + 1),
                                           hote: id + ".local", port: 5540))
            a.adresses[id + ".local"] = muets.contains(id) ? [] : [adresse(n + 1)]
        }
        return a
    }

    /// Mode direct sans dossier : le depart il y a 15 min, puis `muets` et `partis` au-dela du sursis de 2 min.
    static func surveillance(muets: Set<String> = [], partis: Set<String> = [], maintenant: Date) -> Surveillance {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.integrer(annonces(maintenant - 900))
        s.thread.integrer(annonces(maintenant - 840, muets: muets, partis: partis))
        s.thread.integrer(annonces(maintenant - 700, muets: muets, partis: partis))
        return s
    }

    /// Maillage de la sonde : le chef (routeur 3, son ExtMac est le `xa` de l'annonce), muet, et sous lui les
    /// enfants trouves par la resolution (numeros inventes, comme sous un routeur Apple) ; `resolus` : ce que porte
    /// le maillage. `places` faux : sans ces enfants, comme la tournee pour une resolution anterieure a la perte de
    /// l'annonce.
    /// `repondus` : ceux de `resolus` dont l'appareil a repondu a la sonde (nil : tous, firmware 1.1.1).
    static func maillage(_ date: Date, resolus: [String: Date], places: Bool = true,
                         repondus: Set<String>? = nil) -> Maillage {
        var c = ConstructionMaillage(date: date, partition: partition)
        c.routeurs(Route64(sequence: 1, routes: [RouteRouteur(idRouteur: 3, qualiteSortante: 0, qualiteEntrante: 0,
                                                              cout: 0)]), chef: 3)
        c.muet(3)
        c.identite("E1000000000000A1", routeur: 3)
        let ext: [String: String?] = [matter: matter, hap: nil]
        for (k, id) in [matter, hap].enumerated() {
            guard places, let d = resolus[id], let ad = AdresseIPv6(adresse(k + 1)) else { continue }
            c.enfant(EnfantMaillage(rloc16: 0x0C00 | EnfantMaillage.bitInvente | UInt16(k), extMac: ext[id] ?? nil,
                                    adresses: [ad], source: .resolution, resolu: d))
        }
        var m = c.maillage()
        m.resolution = resolus.values.max()
        m.resolus = resolus
        m.resolusRepondus = repondus ?? Set(resolus.keys)
        return m
    }

    /// Trouves par la sonde : le sans adresse (Matter et HomeKit) est joignable, rattache a son parent sur la carte,
    /// sans alerte ; sa fiche dit « joignable, adresse plus annoncee » et l'age de la verification. Aucun evenement
    /// ni notification nouveaux, ni au maillage ni au releve suivant.
    @Test func trouveParLaSonde() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.matter, Self.hap], maintenant: maintenant)
        #expect(s.evenements.filter { $0.type == .appareilSansAdresse }.count == 2, "l'evenement existant reste")
        #expect(s.thread.appareilsAResoudre().map(\.id) == [Self.matter, Self.temoin, Self.hap].sorted())
        #expect(s.thread.appareilsAResoudre().first { $0.id == Self.hap }?.adresse == AdresseIPv6(Self.adresse(2)))
        var alertes: [AlerteAEnvoyer] = []
        s.surAlertes = { alertes += $0 }
        let avant = s.evenements
        let trouve = maintenant - 120
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.matter: trouve, Self.hap: trouve]),
                   a: maintenant - 60)

        let r = try #require(s.thread.reseau)
        let affiches = s.thread.appareilsAffiches(pour: r)
        #expect(affiches.first { $0.id == idt(Self.matter) }?.etat == .joignable)
        #expect(affiches.first { $0.id == idt(Self.hap) }?.etat == .joignable)
        #expect(s.thread.resume?.injoignables == 0)
        #expect(s.thread.verification(Self.matter, a: maintenant) == trouve)
        #expect(s.thread.verification(Self.temoin, a: maintenant) == nil, "il annonce son adresse : rien a verifier")
        let m = try #require(s.thread.maillageAffiche(pour: r))
        #expect(m.parent(de: Self.matter) == Self.routeur, "par son ExtMac")
        #expect(m.parent(de: Self.hap) == Self.routeur, "par sa derniere adresse")
        let graphe = GrapheReseau(reseau: r, appareils: affiches, maillage: m)
        #expect(graphe.parent(de: idt(Self.hap)) == idt(Self.routeur))
        #expect(graphe.liens.contains { $0.de == idt(Self.hap) && $0.genre == .parent })

        #expect(FicheNoeud.texteEtat(.sansAdresse, disparu: false, verifie: true)
                == String(localized: "joignable, adresse plus annoncée"))
        #expect(FicheNoeud.texteVerification(trouve, maintenant)
                == String(localized: "vérifié par la sonde \(FicheNoeud.relatif(trouve, maintenant))"))

        #expect(s.evenements == avant, "aucun evenement nouveau")
        s.thread.integrer(Self.annonces(maintenant - 30, muets: [Self.matter, Self.hap]))
        #expect(s.evenements == avant, "ni au releve suivant")
        #expect(alertes.isEmpty, "aucune notification")
    }

    /// Pas trouve par la sonde (l'introuvable n'est pas dans la memoire de la tournee), ou sans sonde : « adresse non
    /// annoncee », en alerte comme avant ; une verification de plus de 2 resolutions ou un maillage perime ne comptent
    /// pas.
    @Test func pasTrouve() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.hap], maintenant: maintenant)
        let r = try #require(s.thread.reseau)
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil, "sans sonde")
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [:]), a: maintenant - 60)
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
        #expect(s.thread.resume?.injoignables == 1)
        #expect(s.thread.maillageAffiche(pour: r)?.parent(de: Self.hap) == nil)
        #expect(FicheNoeud.texteEtat(.sansAdresse, disparu: false, verifie: false)
                == String(localized: "adresse non annoncée"))

        let vieille = maintenant - SurveillanceThread.ageMaxVerification - 60
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.hap: vieille]), a: maintenant - 60)
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil, "resolution trop ancienne")
        s.thread.recevoir(Self.maillage(maintenant - 1100, resolus: [Self.hap: maintenant - 1100]), a: maintenant - 16 * 60)
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil, "maillage perime")
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
    }

    /// Le cache d'adresses seul ne verifie pas : un appareil trouve mais qui n'a pas repondu a la sonde (repondu faux,
    /// ou firmware ancien qui ne le dit pas) reste « adresse non annoncee », en alerte, sans parent ; celui qui a
    /// repondu est joignable.
    @Test func cacheSeulNeVerifiePas() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.matter, Self.hap], maintenant: maintenant)
        let r = try #require(s.thread.reseau)
        let trouve = maintenant - 120
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.matter: trouve, Self.hap: trouve], places: false,
                                 repondus: []), a: maintenant - 60)
        #expect(s.thread.verification(Self.matter, a: maintenant) == nil && s.thread.verification(Self.hap, a: maintenant) == nil)
        #expect(s.thread.appareilsAffiches(pour: r).filter { $0.etat == .sansAdresse }.count == 2)
        #expect(s.thread.resume?.injoignables == 2)
        #expect(s.thread.appareilsAffiches(pour: r).allSatisfy { !$0.verifie })
        let carte = s.thread.maillageAffiche(pour: r)
        #expect(carte?.parent(de: Self.matter) == nil && carte?.parent(de: Self.hap) == nil)
        // L'un a repondu, l'autre non.
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.matter: trouve, Self.hap: trouve],
                                 repondus: [Self.matter]), a: maintenant - 60)
        #expect(s.thread.verification(Self.matter, a: maintenant) == trouve)
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.matter) }?.etat == .joignable)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
        #expect(s.thread.resume?.injoignables == 1)
    }

    /// Un perdu dont la derniere adresse est annoncee aujourd'hui par un autre identifiant (le meme appareil sous un
    /// nouvel hote) n'est ni demande ni verifie, meme si la sonde l'a trouve avant : pas de doublon joignable.
    @Test func perduRevenuSousUnAutreHoteNiDemandeNiVerifie() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.hap], maintenant: maintenant)
        let r = try #require(s.thread.reseau)
        let trouve = maintenant - 120
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.hap: trouve]), a: maintenant - 60)
        #expect(s.thread.verification(Self.hap, a: maintenant) == trouve)
        #expect(s.thread.appareilsAResoudre().contains { $0.id == Self.hap })
        var a = Self.annonces(maintenant - 30, muets: [Self.hap])
        a.matter.append(AnnonceService(instance: "0000000000000F01-00000000000000AA", hote: "Autre.local", port: 5540))
        a.adresses["Autre.local"] = [Self.adresse(2)]
        s.thread.integrer(a)
        #expect(!s.thread.appareilsAResoudre().contains { $0.id == Self.hap }, "plus demande")
        #expect(s.thread.verification(Self.hap, a: maintenant) == nil, "plus verifie")
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
    }

    /// Un disparu demande a la sonde avec sa derniere adresse, et trouve : joignable, a sa place, sans alerte.
    @Test func disparuTrouve() throws {
        let maintenant = Date()
        let s = Self.surveillance(partis: [Self.matter], maintenant: maintenant)
        #expect(s.thread.suivi.disparus[Self.matter] != nil)
        #expect(s.thread.appareilsAResoudre().first { $0.id == Self.matter }
                == AppareilAResoudre(id: Self.matter, partition: Self.partition,
                                     adresse: try #require(AdresseIPv6(Self.adresse(1))),
                                     derniereAnnonce: s.thread.suivi.dernieresAnnonces[Self.matter], disparu: true))
        let r = try #require(s.thread.reseau)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.matter) }?.etat == .disparu)
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.matter: maintenant - 120]), a: maintenant - 60)
        let affiche = try #require(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.matter) })
        #expect(affiche.etat == .joignable && affiche.partition == Self.partition)
        #expect(s.thread.maillageAffiche(pour: r)?.parent(de: Self.matter) == Self.routeur)
        #expect(FicheNoeud.texteEtat(.joignable, disparu: true, verifie: true)
                == String(localized: "joignable, adresse plus annoncée"))
        #expect(FicheNoeud.texteEtat(.joignable, disparu: true, verifie: false) == String(localized: "disparu"))
    }

    /// Une resolution faite avant la perte de l'annonce ne prouve rien (l'appareil annoncait encore son adresse),
    /// egale a la derniere annonce non plus : l'appareil reste « adresse non annoncee » ou « disparu ». Posterieure
    /// a la perte, elle le montre joignable.
    @Test func resolutionAnterieureALaPerte() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.hap], partis: [Self.matter], maintenant: maintenant)
        let r = try #require(s.thread.reseau)
        let annonceHap = try #require(s.thread.suivi.dernieresAnnonces[Self.hap])
        let annonceMatter = try #require(s.thread.suivi.dernieresAnnonces[Self.matter])
        #expect(s.thread.appareilsAResoudre().first { $0.id == Self.hap }?.derniereAnnonce == annonceHap)
        #expect(s.thread.appareilsAResoudre().first { $0.id == Self.matter }?.derniereAnnonce == annonceMatter)

        for (hap, matter) in [(annonceHap - 60, annonceMatter - 60), (annonceHap, annonceMatter)] {
            s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.hap: hap, Self.matter: matter], places: false),
                       a: maintenant - 60)
            #expect(s.thread.verification(Self.hap, a: maintenant) == nil)
            #expect(s.thread.verification(Self.matter, a: maintenant) == nil)
            #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .sansAdresse)
            #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.matter) }?.etat == .disparu)
            #expect(s.thread.resume?.injoignables == 2)
            let carte = s.thread.maillageAffiche(pour: r)
            #expect(carte?.parent(de: Self.hap) == nil && carte?.parent(de: Self.matter) == nil)
            #expect(carte?.inconnus.isEmpty == true, "pas de noeud fantome sous le routeur")
        }

        let apres = maintenant - 120
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.hap: apres, Self.matter: apres]), a: maintenant - 60)
        #expect(s.thread.verification(Self.hap, a: maintenant) == apres)
        #expect(s.thread.verification(Self.matter, a: maintenant) == apres)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.hap) }?.etat == .joignable)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.matter) }?.etat == .joignable)
        #expect(s.thread.resume?.injoignables == 0)
    }

    // MARK: Dernieres adresses sur disque

    static let depart = Date(timeIntervalSince1970: 1_790_000_000)
    /// Le lancement qui relit le disque (3 h apres le depart) : l'heure est donnee, pour que la purge de 30 jours ne
    /// depende pas de la date du jour.
    static let lancement = depart + 3 * 3600

    static func dossierJetable() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maillage-adresses-\(UUID().uuidString)")
    }

    /// Mode direct avec ce dossier : le depart, puis `hap` sans adresse au-dela du sursis de 2 min.
    static func surveillanceSurDisque(_ dossier: URL) -> Surveillance {
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.integrer(annonces(depart))
        s.thread.integrer(annonces(depart + 60, muets: [hap]))
        s.thread.integrer(annonces(depart + 200, muets: [hap]))
        return s
    }

    /// Les dernieres adresses sont gardees sur disque ; une nouvelle surveillance les relit (sans ecouter le reseau)
    /// et, au premier releve ou `hap` est deja sans adresse, le demande a la sonde avec sa derniere adresse et sa
    /// derniere annonce, comme avant la relance. Le fichier ne contient que des valeurs du suivi, par appareil.
    @Test func dernieresAdressesGardeesEtRelues() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernieres-adresses.json")
        let avant = Self.surveillanceSurDisque(dossier)
        #expect(FileManager.default.fileExists(atPath: fichier.path))
        let annonce = try #require(avant.thread.suivi.dernieresAnnonces[Self.hap])
        let attendu = try #require(avant.thread.appareilsAResoudre().first { $0.id == Self.hap })
        #expect(attendu.derniereAnnonce == annonce && attendu.adresse == AdresseIPv6(Self.adresse(2)))

        let relu = Surveillance(mode: .direct, dossier: dossier)
        #expect(relu.thread.suivi.dernieresAdresses.isEmpty, "rien avant la relecture")
        relu.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(relu.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(2)))
        #expect(relu.thread.suivi.dernieresAnnonces[Self.hap] == annonce, "l'annonce relue telle quelle")
        #expect(relu.thread.suivi.dernieresPartitions[Self.hap] == Self.partition)
        #expect(relu.thread.appareilsAResoudre().isEmpty, "pas d'instantane : rien a demander")
        // Premier releve de la nouvelle session (3 h plus tard) : hap n'a plus d'adresse, il est demande.
        relu.thread.integrer(Self.annonces(Self.depart + 3 * 3600, muets: [Self.hap]))
        let demande = try #require(relu.thread.appareilsAResoudre().first { $0.id == Self.hap })
        #expect(demande == AppareilAResoudre(id: attendu.id, partition: attendu.partition, adresse: attendu.adresse,
                                             derniereAnnonce: annonce),
                "meme adresse, meme partition, meme derniere annonce")
        #expect(!demande.disparu)
        #expect(relu.thread.appareilsAResoudre().map(\.id) == [Self.matter, Self.temoin, Self.hap].sorted())
    }

    /// On n'ecrit que ce qui change : un releve identique (annonce avancee de moins de 15 min) ne reecrit pas le
    /// fichier ; une autre adresse, un appareil de plus ou une annonce qui a avance de 15 min, si.
    @Test func dernieresAdressesEcritesSeulementSiChangement() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernieres-adresses.json")
        let s = Self.surveillanceSurDisque(dossier)
        try FileManager.default.removeItem(at: fichier)
        s.thread.integrer(Self.annonces(Self.depart + 260, muets: [Self.hap]))
        #expect(!FileManager.default.fileExists(atPath: fichier.path), "releve identique, 60 s plus tard")
        s.thread.integrer(Self.annonces(Self.depart + 200 + 1000, muets: [Self.hap]))
        #expect(FileManager.default.fileExists(atPath: fichier.path), "l'annonce de matter a avance de plus de 15 min")
        try FileManager.default.removeItem(at: fichier)
        var changee = Self.annonces(Self.depart + 1300, muets: [Self.hap])
        changee.adresses[Self.matter + ".local"] = [Self.adresse(9)]
        s.thread.integrer(changee)
        #expect(FileManager.default.fileExists(atPath: fichier.path), "matter a une autre adresse")
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(relu.thread.suivi.dernieresAdresses[Self.matter] == AdresseIPv6(Self.adresse(9)))

        // La regle seule : un appareil qui annonce encore et dont l'annonce avance de moins de 15 min ne s'ecrit pas ;
        // une annonce qui ne bouge plus s'ecrit exacte.
        let g = Suivi.AdresseGardee(adresse: try #require(AdresseIPv6(Self.adresse(1))), partition: Self.partition,
                                    annonce: Self.depart)
        var proche = g
        proche.annonce = Self.depart + 899
        var loin = g
        loin.annonce = Self.depart + 900
        #expect(!SurveillanceThread.adressesAEcrire(["x": g], ecrites: ["x": g], releve: Self.depart))
        #expect(!SurveillanceThread.adressesAEcrire(["x": proche], ecrites: ["x": g], releve: proche.annonce))
        #expect(SurveillanceThread.adressesAEcrire(["x": loin], ecrites: ["x": g], releve: loin.annonce))
        #expect(SurveillanceThread.adressesAEcrire(["x": proche], ecrites: ["x": g], releve: loin.annonce),
                "il n'annonce plus : sa derniere annonce s'ecrit")
        #expect(SurveillanceThread.adressesAEcrire(["x": g, "y": g], ecrites: ["x": g], releve: Self.depart))
        #expect(SurveillanceThread.adressesAEcrire([:], ecrites: ["x": g], releve: Self.depart))
        var autre = g
        autre.partition = "0000BBBB"
        #expect(SurveillanceThread.adressesAEcrire(["x": autre], ecrites: ["x": g], releve: Self.depart))
    }

    /// Un fichier illisible, ou en JSON valide mais incoherent (adresse invalide, partition vide), est ignore sans
    /// arreter l'app : le suivi ne sait rien, aucun appareil sans adresse n'est demande ; un changement le remplace.
    @Test func dernieresAdressesIllisibles() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: Surveillance.dossierThread(dossier), withIntermediateDirectories: true)
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernieres-adresses.json")
        let valide = #"{"adresse":"fd00:aaaa:bbbb:1::2","partition":"0000AAAA","annonce":"2026-10-12T08:00:00.000Z"}"#
        let cas = [
            "{ pas du json",
            #"{"appareils":{"\#(Self.hap)":{"adresse":"pas une adresse","partition":"0000AAAA","#
                + #""annonce":"2026-10-12T08:00:00.000Z"}}}"#,
            #"{"appareils":{"\#(Self.hap)":{"adresse":"fd00:aaaa:bbbb:1::2","partition":"","#
                + #""annonce":"2026-10-12T08:00:00.000Z"}}}"#,
            #"{"appareils":{"\#(Self.hap)":\#(valide), "":\#(valide)}}"#,
            #"{"appareils":{"\#(Self.hap)":{"adresse":"fd00:aaaa:bbbb:1::2"}}}"#,
        ]
        for texte in cas {
            try Data(texte.utf8).write(to: fichier)
            let s = Surveillance(mode: .direct, dossier: dossier)
            s.thread.chargerAdressesGardees(maintenant: Self.lancement)
            #expect(s.thread.suivi.dernieresAdresses.isEmpty && s.thread.suivi.dernieresAnnonces.isEmpty
                    && s.thread.suivi.dernieresPartitions.isEmpty, "ignore : \(texte)")
            s.thread.integrer(Self.annonces(Self.depart + 3 * 3600, muets: [Self.hap]))
            #expect(s.thread.appareilsAResoudre().map(\.id) == [Self.matter, Self.temoin].sorted(), "hap non demande")
        }
        // Le fichier valide du dernier cas est lisible tel quel (garde-fou du test).
        try Data(#"{"appareils":{"\#(Self.hap)":\#(valide)}}"#.utf8).write(to: fichier)
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(s.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(2)))
        // Un fichier illisible est remplace par le premier changement.
        try Data("{ pas du json".utf8).write(to: fichier)
        let t = Surveillance(mode: .direct, dossier: dossier)
        t.thread.chargerAdressesGardees(maintenant: Self.lancement)
        t.thread.integrer(Self.annonces(Self.depart))
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(relu.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(2)))
    }

    /// La demo n'ecrit ni ne lit rien, meme avec un dossier ; sans dossier, rien sur disque non plus.
    @Test func dernieresAdressesJamaisEnDemoNiSansDossier() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        _ = Self.surveillanceSurDisque(dossier)
        let avant = try Data(contentsOf: Surveillance.dossierThread(dossier).appendingPathComponent("dernieres-adresses.json"))
        let demo = Surveillance(mode: .demo, dossier: dossier)
        demo.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(demo.thread.suivi.dernieresAdresses.isEmpty, "rien relu")
        demo.demarrer()
        #expect(!demo.thread.suivi.dernieresAdresses.isEmpty, "la demo a son propre suivi")
        #expect(try Data(contentsOf: Surveillance.dossierThread(dossier).appendingPathComponent("dernieres-adresses.json")) == avant, "rien ecrit")

        let vide = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: vide) }
        let demoVide = Surveillance(mode: .demo, dossier: vide)
        demoVide.demarrer()
        #expect(!FileManager.default.fileExists(atPath: vide.path), "aucun dossier cree")
        let sansDossier = Surveillance(mode: .direct, dossier: nil)
        sansDossier.thread.chargerAdressesGardees(maintenant: Self.lancement)
        sansDossier.thread.integrer(Self.annonces(Self.depart))
        #expect(!sansDossier.thread.suivi.dernieresAdresses.isEmpty)
    }

    /// Une annonce relue est bornee a l'heure du lancement : une date future (horloge reculee, fichier modifie) ne
    /// bloque pas l'appareil. Une resolution posterieure a l'annonce bornee le verifie ; le disque est corrige au
    /// premier changement ecrit, et une annonce non future est relue telle quelle (aucune marge).
    @Test func annonceReluePasDansLeFutur() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let brute = try #require(Self.surveillanceSurDisque(dossier).thread.suivi.dernieresAnnonces[Self.hap])
        // Relue telle quelle, sans marge.
        let normal = Surveillance(mode: .direct, dossier: dossier)
        normal.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(normal.thread.suivi.dernieresAnnonces[Self.hap] == brute)
        // Lancement avant la date du disque : bornee a l'heure du lancement.
        let tot = Surveillance(mode: .direct, dossier: dossier)
        let lancement = brute - 3600
        tot.thread.chargerAdressesGardees(maintenant: lancement)
        #expect(tot.thread.suivi.dernieresAnnonces[Self.hap] == lancement)
        // Une resolution posterieure a l'annonce bornee verifie l'appareil (avec une annonce future, jamais).
        tot.thread.integrer(Self.annonces(lancement + 60, muets: [Self.hap]))
        let t = lancement + 120
        tot.thread.recevoir(Self.maillage(lancement + 90, resolus: [Self.hap: lancement + 100]), a: t - 10)
        #expect(tot.thread.verification(Self.hap, a: t) == lancement + 100)
        #expect(tot.thread.appareilsAResoudre().first { $0.id == Self.hap }?.derniereAnnonce != nil)
        // Le disque est corrige : relue plus tard, l'annonce n'est plus la date future d'origine.
        let relue = Surveillance(mode: .direct, dossier: dossier)
        relue.thread.chargerAdressesGardees(maintenant: brute + 7200)
        #expect(relue.thread.suivi.dernieresAnnonces[Self.hap] == lancement)
    }

    /// Les appareils sans annonce depuis plus de 30 jours sont oublies, a l'ecriture comme a la relecture.
    @Test func adressesDePlusDeTrenteJoursOubliees() throws {
        let trente = SurveillanceThread.dureeAdressesGardees
        #expect(trente == 30 * 24 * 3600)
        let g = Suivi.AdresseGardee(adresse: try #require(AdresseIPv6(Self.adresse(1))), partition: Self.partition,
                                    annonce: Self.depart)
        #expect(SurveillanceThread.adressesRecentes(["x": g], a: Self.depart + trente).keys.contains("x"), "30 jours pile")
        #expect(SurveillanceThread.adressesRecentes(["x": g], a: Self.depart + trente + 1).isEmpty)

        // A la relecture : le fichier garde hap (annonce a `brute`) ; relu 30 jours apres, il est oublie.
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let brute = try #require(Self.surveillanceSurDisque(dossier).thread.suivi.dernieresAnnonces[Self.hap])
        let pile = Surveillance(mode: .direct, dossier: dossier)
        pile.thread.chargerAdressesGardees(maintenant: brute + trente)
        #expect(pile.thread.suivi.dernieresAdresses[Self.hap] != nil)
        let oublie = Surveillance(mode: .direct, dossier: dossier)
        oublie.thread.chargerAdressesGardees(maintenant: Self.depart + 200 + trente + 1)
        #expect(oublie.thread.suivi.dernieresAdresses[Self.hap] == nil)
        #expect(oublie.thread.suivi.dernieresAdresses[Self.matter] == nil, "matter aussi : annonce a Self.depart + 200")

        // A l'ecriture : un releve 31 jours plus tard ou matter et temoin annoncent encore reecrit le fichier sans hap.
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.chargerAdressesGardees(maintenant: Self.depart + 3600)
        s.thread.integrer(Self.annonces(Self.depart + 31 * 24 * 3600, muets: [Self.hap]))
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.thread.chargerAdressesGardees(maintenant: Self.depart + 3600)
        #expect(relu.thread.suivi.dernieresAdresses[Self.hap] == nil, "hap oublie dans le fichier")
        #expect(relu.thread.suivi.dernieresAdresses[Self.matter] != nil && relu.thread.suivi.dernieresAdresses[Self.temoin] != nil)
    }

    /// Une adresse annoncee de nouveau remplace celle qui a ete relue, avec sa date : l'appareil n'est plus demande
    /// comme un appareil perdu.
    @Test func adresseAnnonceeRemplaceLaRelue() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        _ = Self.surveillanceSurDisque(dossier)
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.chargerAdressesGardees(maintenant: Self.lancement)
        let plusTard = Self.depart + 3 * 3600
        var a = Self.annonces(plusTard)
        a.adresses[Self.hap + ".local"] = [Self.adresse(9)]
        s.thread.integrer(a)
        #expect(s.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(9)))
        #expect(s.thread.suivi.dernieresAnnonces[Self.hap] == plusTard)
        let demande = try #require(s.thread.appareilsAResoudre().first { $0.id == Self.hap })
        #expect(demande.adresse == AdresseIPv6(Self.adresse(9)) && demande.derniereAnnonce == nil)
        // Un appareil relu que le releve ne montre pas du tout garde sa derniere adresse, et le fichier aussi.
        let seul = Surveillance(mode: .direct, dossier: dossier)
        seul.thread.chargerAdressesGardees(maintenant: Self.lancement)
        seul.thread.integrer(Self.annonces(plusTard + 60, partis: [Self.hap]))
        #expect(seul.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(9)))
        let encore = Surveillance(mode: .direct, dossier: dossier)
        encore.thread.chargerAdressesGardees(maintenant: Self.lancement)
        #expect(encore.thread.suivi.dernieresAdresses[Self.hap] == AdresseIPv6(Self.adresse(9)))
    }

    /// L'anneau de la variante B (12/10) : porte par l'appareil que la sonde a trouve, et par lui seul ; la carte garde
    /// son vert, y ajoute l'anneau pointille jaune (2 pt, tirets 3/3, rayon du point plus 4 pt pour un point de 8) ; la
    /// legende a son entree, apres « joignable », montree seulement quand un appareil est verifie.
    @Test func anneauDesAppareilsVerifies() throws {
        let maintenant = Date()
        let s = Self.surveillance(muets: [Self.matter, Self.hap], maintenant: maintenant)
        let r = try #require(s.thread.reseau)
        #expect(s.thread.appareilsAffiches(pour: r).allSatisfy { !$0.verifie }, "rien de verifie sans la sonde")
        let sans = try #require(FenetrePiecesTests.entree(s))
        #expect(sans.apparences.values.allSatisfy { !$0.verifie })
        #expect(!LegendePieces.entrees(LegendePieces.Lecture(sans, ailleurs: false)).contains(.verifiee))

        let trouve = maintenant - 120
        s.thread.recevoir(Self.maillage(maintenant - 150, resolus: [Self.matter: trouve, Self.hap: trouve]),
                   a: maintenant - 60)
        let affiches = s.thread.appareilsAffiches(pour: r)
        #expect(Set(affiches.filter(\.verifie).map(\.id)) == [idt(Self.matter), idt(Self.hap)])
        #expect(affiches.first { $0.id == idt(Self.temoin) }?.verifie == false, "il annonce son adresse")
        #expect(affiches.filter(\.verifie).allSatisfy { $0.etat == .joignable }, "le point reste joignable, donc vert")
        let entree = try #require(FenetrePiecesTests.entree(s))
        #expect(Set(entree.apparences.filter { $0.value.verifie }.keys) == [idt(Self.matter), idt(Self.hap)])
        #expect(entree.apparences[idt(Self.matter)]?.couleur == .appareil(.joignable))
        #expect(entree.apparences[idt(Self.temoin)]?.verifie == false)
        let entrees = LegendePieces.entrees(LegendePieces.Lecture(entree, ailleurs: false))
        #expect(entrees.isSuperset(of: [.joignable, .verifiee]), "le temoin reste « joignable »")
        let rubriques = LegendePieces.rubriques(LegendePieces.Lecture(entree, ailleurs: false))
        let appareils = try #require(rubriques.first { $0.groupe == .appareils })
        #expect(Array(appareils.entrees.prefix(2)) == [.joignable, .verifiee], "juste apres « joignable »")
        // Tous verifies : plus de « joignable » simple.
        #expect(LegendePieces.entrees(LegendePieces.Lecture(couleurs: [idt("a"): .appareil(.joignable)], verifies: [idt("a")]))
                == [.verifiee])

        // Les valeurs de la maquette.
        #expect(Palette(sombre: true).anneauVerifie == Color(red: 232 / 255, green: 240 / 255, blue: 90 / 255))
        #expect(Palette(sombre: false).anneauVerifie == Palette(sombre: true).anneauVerifie)
        #expect(DessinNoeud.epaisseurAnneauVerifie == 2)
        #expect(DessinNoeud.tiretsAnneauVerifie == [3, 3])
        #expect(DessinNoeud.rayonAnneauVerifie(8) == 12)
        #expect(DessinNoeud.rayonAnneauVerifie(4) == 6, "proportionnel au point")
        // Seul un appareil joignable porte l'anneau ; l'apparence du point ne change pas.
        let vert = DessinNoeud.apparenceAppareil(.joignable)
        #expect(DessinNoeud.apparenceAppareil(.joignable, verifie: true).couleur == vert.couleur)
        #expect(DessinNoeud.apparenceAppareil(.joignable, verifie: true).forme == vert.forme)
        #expect(DessinNoeud.apparenceAppareil(.sansAdresse, verifie: true).verifie == false)
        #expect(LegendePieces.signe(.verifiee)
                == .noeud(DessinNoeud.apparenceAppareil(.joignable, verifie: true), rayon: LegendePieces.rayonAppareil))
        #expect(SigneLegende.taille(LegendePieces.signe(.verifiee))
                == SigneLegende.taille(LegendePieces.signe(.joignable)))
    }

    /// Rendu : de l'encre jaune autour du point d'un appareil verifie (signe de la legende, tel que la scene le
    /// dessine), et nulle part pour un point joignable ordinaire.
    @Test func anneauDessine() throws {
        func jaunes(_ e: LegendePieces.Entree) throws -> Int {
            let p = try LegendePiecesTests.pixels(SigneLegende(signe: LegendePieces.signe(e)).padding(12))
            return stride(from: 0, to: p.octets.count, by: 4).filter { i in
                p.octets[i + 3] > 200 && p.octets[i] > 180 && p.octets[i + 1] > 190 && p.octets[i + 2] < 150
            }.count
        }
        #expect(try jaunes(.joignable) == 0)
        #expect(try jaunes(.verifiee) > 4)
    }

    /// Les textes dans la langue du lancement des tests (`-testLanguage fr`, puis `en`).
    @Test func textesFrancaisEtAnglais() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let francais = ThreadRouteTests.langue == "fr"
        guard francais || ThreadRouteTests.langue == "en" else {
            throw ThreadRouteTests.ErreurLangue(langue: ThreadRouteTests.langue)
        }
        #expect(FicheNoeud.texteEtat(.sansAdresse, disparu: false, verifie: false)
                == (francais ? "adresse non annoncée" : "address not advertised"))
        #expect(LegendePieces.Entree.sansAdresse.texte
                == (francais ? "adresse non annoncée" : "address not advertised"))
        #expect(FicheNoeud.texteEtat(.sansAdresse, disparu: false, verifie: true)
                == (francais ? "joignable, adresse plus annoncée" : "reachable, address no longer advertised"))
        let verifie = FicheNoeud.texteVerification(t - 600, t)
        #expect(verifie.hasPrefix(francais ? "vérifié par la sonde " : "checked by the probe "))
        #expect(verifie.hasSuffix(FicheNoeud.relatif(t - 600, t)))
        let e = Evenement(date: t, type: .appareilSansAdresse, sujet: Sujet(id: "x", nom: "Prise"))
        #expect(TexteEvenementThread.titre(e)
                == (francais ? "Prise n'annonce plus d'adresse" : "Prise no longer advertises an address"))
    }
}
