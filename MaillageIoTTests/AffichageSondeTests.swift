import AppKit
import Foundation
import MaillageCoeur
import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Affichage de la sonde : noms, qualites, fiche, menu, reglages")
struct AffichageSondeTests {
    /// Les attentes reprennent les memes cles interpolees que le code : elles suivent la
    /// langue de l'hote. (Un litteral sans interpolation n'est pas une cle du catalogue :
    /// il resterait en francais.)
    @Test func libelles() {
        #expect(LibellesNoeuds.inconnu(NoeudSonde(id: "rloc:B400", rloc16: 0xB400, genre: .routeur, reconnu: false,
                                                       bordure: true)) == String(localized: "Routeur de bordure · \("B400")"))
        #expect(LibellesNoeuds.inconnu(NoeudSonde(id: "rloc:5000", rloc16: 0x5000, genre: .routeur, reconnu: false,
                                                       bordure: false)) == String(localized: "Routeur · \("5000")"))
        #expect(LibellesNoeuds.inconnu(NoeudSonde(id: "rloc:AC05", rloc16: 0xAC05, genre: .enfant, reconnu: false,
                                                       bordure: false)) == String(localized: "Non identifié · \("AC05")"))
    }

    /// Le RLOC16 invente d'un enfant resolu (`EnfantMaillage.bitInvente`) n'est jamais affiche : « Non identifie » seul,
    /// sans code ; un vrai RLOC16 garde « Non identifie · XXXX ».
    @Test func libelleSansRloc16Invente() {
        let invente = NoeudSonde(id: "rloc:0E00", rloc16: 0x0C00 | EnfantMaillage.bitInvente, genre: .enfant,
                                 reconnu: false, bordure: false)
        let reel = NoeudSonde(id: "rloc:0C05", rloc16: 0x0C05, genre: .enfant, reconnu: false, bordure: false)
        #expect(LibellesNoeuds.inconnu(invente) == String(localized: "Non identifié"))
        #expect(!LibellesNoeuds.inconnu(invente).contains("0E00"))
        #expect(LibellesNoeuds.inconnu(reel) == String(localized: "Non identifié · \("0C05")"))
    }

    /// Routeur de bordure non identifie : ses candidats sous leur nom (« HomePod Avant ou HomePod
    /// Gauche · 0400 »), l'instance a defaut ; un seul candidat, avec un point d'interrogation (sans
    /// elimination possible, ce n'est peut-etre pas lui).
    @Test func libellesAvecCandidats() {
        let deux = NoeudSonde(id: "rloc:0400", rloc16: 0x0400, genre: .routeur, reconnu: false, bordure: true,
                              candidats: ["hp-droit", "HomePod Palier"])
        let liste = ["HomePod Avant", "HomePod Palier"].formatted(.list(type: .or))
        #expect(LibellesNoeuds.inconnu(deux, noms: ["hp-droit": "HomePod Avant"])
                == String(localized: "\(liste) · \("0400")"))
        let un = NoeudSonde(id: "rloc:CC00", rloc16: 0xCC00, genre: .routeur, reconnu: false, bordure: true,
                            candidats: ["HomePod salon"])
        #expect(LibellesNoeuds.inconnu(un) == String(localized: "\("HomePod salon")\u{202F}? · \("CC00")"))
        #expect(LibellesNoeuds.inconnu(un) != LibellesNoeuds.inconnu(deux))
    }

    /// Noms des routeurs de bordure d'un reseau, par instance, en un seul endroit (libelles de la
    /// vue, fiche, candidats) : le surnom d'abord, l'instance sinon.
    @Test func nomsDesRouteurs() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.thread.reseau)
        s.renommer(idt("HomePod Avant"), en: "Enceinte droite")
        let noms = s.thread.nomsRouteurs(pour: r)
        #expect(noms["HomePod Avant"] == "Enceinte droite")
        #expect(noms["HomePod Palier"] == "HomePod Palier")
        #expect(Set(noms.keys) == Set(r.routeurs.map(\.instance)))
    }

    /// Fiche d'un routeur de bordure non identifie : chaque candidat se choisit et ouvre la fiche
    /// de son annonce (role, adresses, journal, « Renommer… »), si l'instantane la connait
    /// encore ; sinon, il ne mene nulle part.
    @Test func selectionDUnCandidat() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        #expect(FicheNoeud.selection(candidat: "HomePod Avant", dans: s) == "HomePod Avant")
        #expect(FicheNoeud.renommable("HomePod Avant", dans: s), "sa fiche : « Renommer… »")
        #expect(FicheNoeud.selection(candidat: "Annonce disparue", dans: s) == nil)
    }

    /// Fiche d'un routeur de bordure non identifie : ce que la sonde en sait ; trois explications
    /// distinctes (routeur avec ou sans candidats, enfant).
    @Test func ficheAvecCandidats() {
        let avec = NoeudSonde(id: "rloc:0400", rloc16: 0x0400, genre: .routeur, reconnu: false, bordure: true,
                              candidats: ["HomePod Avant", "HomePod Palier"])
        let sans = NoeudSonde(id: "rloc:0400", rloc16: 0x0400, genre: .routeur, reconnu: false, bordure: true)
        let enfant = NoeudSonde(id: "rloc:AC05", rloc16: 0xAC05, genre: .enfant, reconnu: false, bordure: false)
        let textes = [avec, sans, enfant].map(FicheNoeud.explication)
        #expect(Set(textes).count == 3 && !textes.contains(""))
        #expect(!FicheNoeud.texteElimination.isEmpty)
    }

    @Test func niveaux() {
        #expect(Palette.NiveauLien(3) == .bon)
        #expect(Palette.NiveauLien(2) == .moyen)
        #expect(Palette.NiveauLien(1) == .faible)
        #expect(Palette.NiveauLien(0) == .inconnu)
        #expect(Palette.NiveauLien(nil) == .inconnu)
    }

    /// Mode demo : maillage de demo ; fiche d'un enfant et d'un routeur.
    @Test func ficheEtDemo() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.thread.reseau)
        let m = try #require(s.thread.maillageAffiche(pour: r))
        #expect(!s.thread.maillageAncien)
        let enfant = try #require(m.enfants.values.first { $0.reconnu && m.parent(de: $0.id) != nil })
        let ligne = FicheNoeud.ligneSonde(enfant, maillage: m, nom: { "P[\($0)]" })
        #expect(ligne.hasPrefix(String(format: "RLOC16 %04X", enfant.rloc16)))
        #expect(ligne.contains("P["))
        // Le chef du maillage de demo (routeur 1, RLOC16 0400) : 5 voisins et 4 enfants.
        let chef = try #require(m.routeurs[1])
        let voisins = 5
        let enfants = 4
        #expect(FicheNoeud.ligneSonde(chef, maillage: m, nom: { $0 })
                    == String(localized: "RLOC16 \("0400") · voisins : \(voisins) · enfants : \(enfants)"))
        #expect(FicheNoeud.texteQualite(nil) == String(localized: "qualité inconnue"))
        #expect(FicheNoeud.texteQualite(3) == String(localized: "qualité \(3)"))
    }

    /// Source et age d'un lien dans la fiche (spec de la sonde tout-en-un, section 2.4) : « diagnostic », « entendu il y
    /// a 3 minutes », « resolu il y a 12 minutes », « acces au canal refuses : 0,7 % », ou donne par la sonde ;
    /// plusieurs a la suite.
    @Test func origineDUnLien() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let diagnostic = String(localized: "diagnostic")
        let entendu = String(localized: "entendu \(FicheNoeud.relatif(t - 180, t))")
        #expect(FicheNoeud.texteOrigine(OrigineLien(diagnostic: true), t) == diagnostic)
        #expect(FicheNoeud.texteOrigine(OrigineLien(entendu: t - 180), t) == entendu)
        #expect(FicheNoeud.texteOrigine(OrigineLien(diagnostic: true, entendu: t - 180), t) == diagnostic + " · " + entendu)
        let pourcentage = 0.007.formatted(.percent.precision(.fractionLength(1)))
        #expect(FicheNoeud.texteAccesCanal(0.007) == String(localized: "accès au canal refusés : \(pourcentage)"))
        #expect(FicheNoeud.texteOrigine(OrigineLien(resolu: t - 720, echecs: 0.007), t)
                == String(localized: "résolu \(FicheNoeud.relatif(t - 720, t))") + " · " + FicheNoeud.texteAccesCanal(0.007))
        #expect(FicheNoeud.texteOrigine(OrigineLien(sonde: true), t) == String(localized: "donné par la sonde"))
        #expect(FenetreReglages.texteCouverture(CouvertureEcoute(entendus: 3, routeurs: 7))
                == String(localized: "routeurs entendus : \(3) sur \(7)"))
    }

    /// Fiche d'un routeur et de ses enfants avec la sonde 1.1.0 : chaque lien radio sur sa ligne, avec sa source et son
    /// age (un lien sans source, du maillage de demo, n'en a pas) ; « jamais entendu par la sonde » pour un routeur muet
    /// que la sonde n'entend pas ; un enfant resolu sous un routeur Apple, sans RLOC16 connu (appareils de la demo,
    /// maillage invente).
    @Test func ficheAvecLesSources() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.thread.reseau), i = try #require(s.thread.instantane), p = try #require(r.principale)
        let appareils = i.appareils.filter { $0.partition == p.id && $0.etat == .joignable }.sorted { $0.id < $1.id }
        let routeur = try #require(appareils.first), enfant = try #require(appareils.last)
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        // Route64 (hexa) : sequence 1, masque des routeurs 1, 2 et 3 (ou du seul 1), un octet par routeur.
        func route64(_ hexa: String) throws -> Route64 { try #require(ReponseDiagnostic(hexa: hexa)?.route64) }
        var c = ConstructionMaillage(date: t, partition: p.id)
        c.routeurs(try route64("050C" + "01" + "7000000000000000" + "000000"), chef: 1)
        c.identite(routeur.id.uppercased(), routeur: 2)
        // Le chef 1 repond : sa Route64 des routeurs 1, 2 et 3, voisin du 2 (qualites 3 et 3).
        c.reponse(try #require(ReponseDiagnostic(hexa: "050C" + "01" + "7000000000000000" + "00F100")), routeur: 1)
        // Le 2 entendu il y a 3 min : voisin du 1 (qualites 2 et 2), plus ancien que le diagnostic.
        c.ecoute(try route64("050A" + "01" + "4000000000000000" + "A1"), routeur: 2, date: t - 180)
        c.muet(2)
        c.muet(3)
        c.annoncesRecues()
        c.enfant(EnfantMaillage(rloc16: 0x0C00 | EnfantMaillage.bitInvente, extMac: enfant.id.uppercased(),
                                source: .resolution, resolu: t - 720, echecs: 0.012))
        let m = MaillageAffiche(maillage: c.maillage(), reseau: r, appareils: i.appareils)
        let n2 = try #require(m.noeud(routeur.id))
        let l = try #require(m.liens.first { $0.genre == .radio })
        let o = try #require(l.origine)
        let voisin = l.de == n2.id ? l.vers : l.de
        #expect(FicheThread.voisins(de: idt(n2.id), maillage: m).map(\.id.cle) == [voisin])
        #expect(FicheNoeud.origineVoisin(voisin, de: n2.id, maillage: m, instant: t)
                == FicheNoeud.texteQualite(l.qualite) + " · " + FicheNoeud.texteOrigine(o, t))
        #expect(FicheNoeud.origineVoisin("absent", de: n2.id, maillage: m, instant: t) == nil)
        #expect(!m.jamaisEntendu(n2.id), "entendu")
        #expect(m.jamaisEntendu(try #require(m.routeurs[3]?.id)), "muet, pas entendu")
        #expect(FicheNoeud.texteJamaisEntendu == String(localized: "jamais entendu par la sonde ; liens vus seulement par ses voisins"))
        let ne = try #require(m.noeud(enfant.id))
        let parent = try #require(m.parent(de: ne.id))
        #expect(FicheNoeud.ligneSonde(ne, maillage: m, nom: { "[\($0)]" }, instant: t)
                == String(localized: "parent \("[\(parent)]"), \(FicheNoeud.texteQualite(nil))") + " · "
                    + String(localized: "résolu \(FicheNoeud.relatif(t - 720, t))") + " · " + FicheNoeud.texteAccesCanal(0.012),
                "sans RLOC16 : il est invente")
        // Un enfant sans parent connu : son RLOC16, s'il est vrai ; jamais un RLOC16 invente.
        let sansParent = NoeudSonde(id: "rloc:0C01", rloc16: 0x0C01, genre: .enfant, reconnu: false, bordure: false)
        #expect(FicheNoeud.ligneSonde(sansParent, maillage: m, nom: { $0 }, instant: t) == String(localized: "RLOC16 \("0C01")"))
        let inventeSansParent = NoeudSonde(id: "absent", rloc16: 0x0C00 | EnfantMaillage.bitInvente | 1, genre: .enfant,
                                           reconnu: false, bordure: false)
        #expect(FicheNoeud.ligneSonde(inventeSansParent, maillage: m, nom: { $0 }, instant: t)
                == String(localized: "Non identifié"), "RLOC16 invente, sans parent : jamais affiche")
        // Maillage de demo : aucune source, la qualite seule.
        let demo = try #require(s.thread.maillageAffiche(pour: r))
        let chef = try #require(demo.routeurs[1])
        let lienDemo = try #require(demo.liens.first { $0.genre == .radio && ($0.de == chef.id || $0.vers == chef.id) })
        #expect(FicheNoeud.origineVoisin(lienDemo.de == chef.id ? lienDemo.vers : lienDemo.de, de: chef.id, maillage: demo,
                                         instant: t) == FicheNoeud.texteQualite(lienDemo.qualite))
    }

    /// « Renommer… » : pour un routeur de l'instantane, un appareil connu ou un appareil disparu
    /// (plus dans l'instantane, mais le suivi le garde, avec sa fiche), pas pour un noeud que la
    /// sonde seule connait (son RLOC16 est volatil : rien ne lirait le surnom).
    @Test func renommable() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.thread.reseau)
        let m = try #require(s.thread.maillageAffiche(pour: r))
        let routeur = try #require(r.routeurs.first)
        let appareil = try #require(s.thread.instantane?.appareils.first)
        let disparu = try #require(s.thread.suivi.disparus.keys.sorted().first)
        let inconnu = try #require(m.inconnus.first)
        #expect(m.noeud(inconnu.id) != nil, "connu de la sonde")
        #expect(s.thread.instantane?.appareil(disparu) == nil && s.thread.instantane?.routeur(disparu) == nil,
                "le disparu n'est plus dans l'instantane : seul le suivi le connait")
        #expect(FicheNoeud.renommable(routeur.instance, dans: s))
        #expect(FicheNoeud.renommable(appareil.id, dans: s))
        #expect(FicheNoeud.renommable(disparu, dans: s), "appareil disparu : sa fiche garde « Renommer… »")
        #expect(!FicheNoeud.renommable(inconnu.id, dans: s))
        #expect(!FicheNoeud.renommable("rloc:5000", dans: s), "ni la sonde ni l'instantane : « Ce nœud n'est plus visible. »")
    }

    /// Ligne du menu : le nom de la sonde a la place de « Sonde » quand il est donne (celui de la
    /// sonde retenue, quand l'etat la concerne : `SondeMaillage.nomEtat`) ; pendant une tournee,
    /// son etape et son compteur. Etat des Reglages : « SONDE-01 · connectee », l'etat seul sans nom.
    @Test func menuEtReglages() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let sonde = String(localized: "Sonde")
        #expect(SondeMaillage.nomAffiche(nil) == sonde)
        #expect(SondeMaillage.nomAffiche("SONDE-01") == "SONDE-01")
        #expect(MenuBarre.ligneSonde(.sansSonde, nom: nil, derniere: nil, avancement: nil, maintenant: t) == nil)
        #expect(MenuBarre.ligneSonde(.absente, nom: nil, derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\(sonde) : absente"))
        #expect(MenuBarre.ligneSonde(.absente, nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : absente"))
        #expect(MenuBarre.ligneSonde(.connexion, nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connexion…"))
        #expect(MenuBarre.ligneSonde(.erreur("x"), nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : erreur (voir les Réglages)"))
        guard case .bonjour(let b)? = MessageSonde.lire(Data(CanalRejoue.bonjourNomme.utf8)) else {
            Issue.record("bonjour illisible")
            return
        }
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connectée"))
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t - 120, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connectée · relevé \(FicheNoeud.relatif(t - 120, t))"))
        let resolution = AvancementTournee(etape: .resolution, fait: 24, total: 48)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t - 120, avancement: resolution, maintenant: t)
                == String(localized: "\("SONDE-01") : \(TexteTournee.etape(.resolution)) \(24)/\(48)…"))
        let rien = AvancementTournee(etape: .identites, fait: 0, total: 0)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: nil, derniere: nil, avancement: rien, maintenant: t)
                == String(localized: "\(sonde) : \(TexteTournee.etape(.identites))…"))
        #expect(FenetreReglages.texteEtatSonde(.connectee(b), nom: "SONDE-01")
                == String(localized: "\("SONDE-01") · \(String(localized: "connectée"))"))
        #expect(FenetreReglages.texteEtatSonde(.absente, nom: "SONDE-01")
                == String(localized: "\("SONDE-01") · \(String(localized: "absente (débranchée ?)"))"))
        #expect(FenetreReglages.texteEtatSonde(.connectee(b), nom: nil) == String(localized: "connectée"))
        #expect(FenetreReglages.texteEtatSonde(.refusee("pas une sonde"), nom: nil)
                == String(localized: "refusée : \("pas une sonde")"))
        #expect(FenetreReglages.texteEtatSonde(.sansSonde, nom: nil) == String(localized: "aucune sonde choisie"))
    }

    /// Choix du port : la sonde retenue sous son nom seul ; un autre port, un port sans numero
    /// de serie ou la sonde retenue sans nom connu (firmware 1.0.0), sous son nom de port et son
    /// numero de serie USB (la MAC) : seul moyen de distinguer la sonde du pont Halo avant la
    /// premiere connexion. Un port Espressif n'est pas forcement un C6 : rien ne l'affirme.
    @Test func libellesDesPorts() {
        let retenue = PortUSB(chemin: "/dev/cu.usbmodem11301", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                              produit: nil)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let sansSerie = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: nil, produit: nil)
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: "A0:00:00:00:00:01", nom: "SONDE-01") == "SONDE-01")
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: "A0:00:00:00:00:01", nom: nil)
                == "usbmodem11301 · A0:00:00:00:00:01")
        #expect(FenetreReglages.libellePort(autre, serieRetenue: "A0:00:00:00:00:01", nom: "SONDE-01")
                == "usbmodemFACTICE02 · B0:00:00:00:00:02")
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: nil, nom: "SONDE-01") == "usbmodem11301 · A0:00:00:00:00:01",
                "aucune sonde retenue")
        #expect(FenetreReglages.libellePort(sansSerie, serieRetenue: nil, nom: "SONDE-01") == "usbmodemFACTICE03")
    }

    /// Textes de l'avancement : libelles d'etape distincts ; « etape · fait/total », l'etape
    /// seule quand elle n'a rien a faire ; duree en m:ss dans la barre du graphe, en unites
    /// dans les Reglages.
    @Test func texteAvancement() {
        let etapes = AvancementTournee.Etape.allCases.map(TexteTournee.etape)
        #expect(Set(etapes).count == etapes.count)
        #expect(!etapes.contains(""))
        let a = AvancementTournee(etape: .resolution, fait: 24, total: 48)
        #expect(TexteTournee.avancement(a) == String(localized: "\(TexteTournee.etape(.resolution)) · \(24)/\(48)"))
        #expect(TexteTournee.avancement(AvancementTournee(etape: .identites, fait: 0, total: 0))
                == TexteTournee.etape(.identites))
        #expect(TexteTournee.chrono(42) == "0:42")
        #expect(TexteTournee.chrono(600) == "10:00")
        #expect(TexteTournee.chrono(3723) == "1:02:03")
        #expect(TexteTournee.chrono(-3) == "0:00", "horloge qui recule")
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(TexteTournee.barre(a, debut: t, maintenant: t + 42) == String(localized: "\(TexteTournee.avancement(a)) · \("0:42")"))
        #expect(TexteTournee.reglages(a, debut: t, maintenant: t + 42)
                == String(localized: "\(TexteTournee.avancement(a)) · depuis \(TexteTournee.duree(42))"))
        #expect(TexteTournee.duree(42).contains("42"))
        #expect(TexteTournee.duree(90).contains("1") && TexteTournee.duree(90).contains("30"))
    }

    /// Code d'appairage mis en forme 4-3-4 (11 chiffres) ou 4-3-4-5-5 (21) ; deja mis en forme
    /// ou d'une autre longueur, tel quel. QR code d'une charge « MT:... » : une image carree
    /// d'au moins 21 modules (valeurs inventees).
    @Test func codeMatter() throws {
        #expect(CodeMatter.formater("12345678901") == "1234-567-8901")
        #expect(CodeMatter.formater("123456789012345678901") == "1234-567-8901-23456-78901")
        #expect(CodeMatter.formater("1234-567-8901") == "1234-567-8901")
        #expect(CodeMatter.formater("12345") == "12345")
        #expect(CodeMatter.formater("1234567890a") == "1234567890a")
        let image = try #require(CodeMatter.imageQR("MT:ABCDEFGHIJ0123456789"))
        #expect(image.width == image.height)
        #expect(image.width >= 21)
    }

    /// Le QR code a sa place (120 pt et sa marge) des la construction de la vue : la section ne
    /// saute pas quand l'image, formee apres coup, arrive. Sans charge, pas de place pour lui.
    @Test func placeDuQRCodeReservee() {
        let avec = NSHostingView(rootView: CodeMatterSonde(qr: "MT:ABCDEFGHIJ0123456789", code: "12345678901",
                                                           appairee: true)).fittingSize
        #expect(avec.width >= 136 && avec.height >= 136)
        let sans = NSHostingView(rootView: CodeMatterSonde(qr: nil, code: "12345678901", appairee: true)).fittingSize
        #expect(sans.height < 136)
    }
}
