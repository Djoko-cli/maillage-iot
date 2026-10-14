import AppKit
import Foundation
@testable import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Courbes de l'historique dans la fiche")
struct CourbesFicheTests {
    /// Deux tournees (`JournalMaillageTests`) : l'appareil passe du routeur 1 au routeur 5.
    static func surveillance() throws -> Surveillance {
        let s = JournalMaillageTests.surveillance(dossier: nil)
        let t = Date().addingTimeInterval(-600)
        s.recevoir(try JournalMaillageTests.maillage(s, t, parent: 1), a: t)
        s.recevoir(try JournalMaillageTests.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        return s
    }

    /// Cle d'un noeud dans l'historique : l'ExtMac d'un appareil (son hote), "rloc:0400" pour un
    /// routeur sans ExtMac, le `xa` d'un routeur de bordure de l'instantane ; et le nom d'une cle.
    @Test func clesEtNoms() throws {
        let s = try Self.surveillance()
        let id = JournalMaillageTests.appareil
        #expect(s.cleHistorique(noeud: id) == id)
        #expect(s.cleHistorique(noeud: "rloc:0400") == "rloc:0400")
        let br = try #require(s.instantane?.routeurs.first { $0.adresseEtendue != nil })
        #expect(s.cleHistorique(noeud: br.instance) == br.adresseEtendue)
        #expect(s.cleHistorique(noeud: "instance:inconnue") == nil)
        #expect(s.cleHistorique(noeud: "ＤＥＡＤＢＥＥＦ00000001") == nil, "hexadecimaux pleine chasse : pas une ExtMac")
        let xa = try #require(br.adresseEtendue)
        let noms = s.nomsHistorique([id, "rloc:1400", xa, "E0000000000000FF"])
        #expect(noms[id] == s.nom(try #require(s.appareil(id))))
        #expect(noms["rloc:1400"] == String(localized: "Routeur · \("1400")"))
        #expect(noms[xa] == s.nom(br))
        #expect(noms["E0000000000000FF"] == "E0000000000000FF", "inconnue : la cle")
        #expect(CourbesFiche.nomLien(CourbesNoeud.cleParent, noms) == String(localized: "Parent"))
    }

    /// Courbes de l'appareil : la qualite vers son parent et son changement de parent ; du
    /// routeur 1 (sans ExtMac) : son enfant (l'appareil, a la premiere tournee), son lien avec le 5, et le signal vu par
    /// la sonde.
    @Test func courbes() throws {
        let s = try Self.surveillance()
        let c = try #require(s.courbes(noeud: JournalMaillageTests.appareil, periode: .jour, fin: Date()))
        #expect(c.liens.map(\.id) == [CourbesNoeud.cleParent])
        #expect(c.liens.first?.points.count == 2)
        #expect(c.parents.map(\.parent) == ["rloc:1400"])
        let r = try #require(s.courbes(noeud: "rloc:0400", periode: .jour, fin: Date()))
        #expect(r.liens.map(\.id) == [JournalMaillageTests.appareil, "rloc:1400"])
        #expect(r.signal.map(\.valeur) == [-61, -61])
    }

    /// Un routeur dont la sonde n'a l'ExtMac qu'a une tournee sur deux, la derniere ou la premiere (verification du
    /// 05/10) : sa cle est cette ExtMac, ses deux releves font une seule courbe, et la cle se nomme comme le noeud.
    @Test func routeurIdentifieAUneTournee() throws {
        let x = "E0000000000000C1"
        for derniere in [true, false] {
            let s = JournalMaillageTests.surveillance(dossier: nil)
            let t = Date().addingTimeInterval(-600)
            s.recevoir(try JournalMaillageTests.maillage(s, t, parent: 1, extMac1: derniere ? nil : x), a: t)
            s.recevoir(try JournalMaillageTests.maillage(s, t.addingTimeInterval(300), parent: 5, extMac1: derniere ? x : nil),
                       a: t.addingTimeInterval(300))
            #expect(s.cleHistorique(noeud: "rloc:0400") == x, "derniere : \(derniere)")
            let r = try #require(s.courbes(noeud: "rloc:0400", periode: .jour, fin: Date()))
            #expect(r.signal.map(\.valeur) == [-61, -61], "derniere : \(derniere)")
            #expect(r.liens.map(\.id) == [JournalMaillageTests.appareil, "rloc:1400"]
                    && r.courbe("rloc:1400")?.points.count == 2, "derniere : \(derniere)")
            #expect(s.nomsHistorique([x])[x] == String(localized: "Routeur · \("0400")"), "derniere : \(derniere)")
        }
    }

    /// La resolution des cles est gardee (relecture, Mineur 3) : une fiche (courbes, noms, cle, evenements) ne la
    /// construit qu'une fois par changement de l'historique ; un nouveau releve (`recevoir`) et la relecture du disque
    /// (`chargerHistorique`) la refont, cette derniere avec les releves relus. Les evenements d'un noeud n'en ont pas
    /// besoin.
    @Test func resolutionGardee() async throws {
        let x = "E0000000000000C1"
        let dossier = JournalMaillageTests.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 900)
        // Un lancement precedent : le routeur 1 identifie, sur le disque.
        let avant = JournalMaillageTests.surveillance(dossier: dossier)
        avant.recevoir(try JournalMaillageTests.maillage(avant, t, parent: 1, extMac1: x), a: t)
        let s = JournalMaillageTests.surveillance(dossier: dossier)
        s.recevoir(try JournalMaillageTests.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        func fiche() {
            _ = s.courbes(noeud: "rloc:0400", periode: .jour, fin: Date())
            _ = s.nomsHistorique(["rloc:0400", x])
            _ = s.cleHistorique(noeud: "rloc:0400")
            _ = s.evenements(de: "rloc:0400")
        }
        fiche()
        fiche()
        #expect(s.constructionsCles == 1)
        #expect(s.cleHistorique(noeud: "rloc:0400") == "rloc:0400", "le releve identifie n'est pas encore relu")
        await s.chargerHistorique()
        #expect(s.cleHistorique(noeud: "rloc:0400") == x, "refaite avec les releves relus")
        #expect(s.constructionsCles == 2)
        s.recevoir(try JournalMaillageTests.maillage(s, t.addingTimeInterval(600), parent: 5), a: t.addingTimeInterval(600))
        _ = s.evenements(de: "rloc:0400")
        #expect(s.constructionsCles == 2, "les evenements ne resolvent rien")
        fiche()
        fiche()
        #expect(s.constructionsCles == 3)
    }

    /// L'echelle du signal de la fiche (polissage D, section 4.3) : celle du coeur, sur les valeurs de la courbe ; deux
    /// releves egaux a -61 dBm donnent -70 ... -50, gradue -70, -60, -50 ; sans valeur, -100 ... -40.
    @Test func echelleDuSignal() throws {
        let s = try Self.surveillance()
        let r = try #require(s.courbes(noeud: "rloc:0400", periode: .jour, fin: Date()))
        let e = CourbesFiche.echelle(r)
        #expect(e.domaine == -70 ... -50 && e.graduations == [-70, -60, -50])
        let vide = try #require(s.courbes(noeud: JournalMaillageTests.appareil, periode: .jour, fin: Date()))
        #expect(vide.signal.isEmpty && CourbesFiche.echelle(vide).domaine == -100 ... -40)
        #expect(CourbesFiche.echelle(vide).graduations == [-100, -90, -80, -70, -60, -50, -40])
    }

    /// Ce que le graphe du signal affiche, decide sans fenetre (`GrapheSignal.affichage`, lu par la vue) : le domaine
    /// et les graduations ; le releve sous l'heure survolee, aucun sans survol ni dans un trou ; l'etiquette a gauche
    /// du trait (alignement `.trailing`) dans la moitie droite de la periode, a droite (`.leading`) sinon. Les
    /// changements de parent de la sonde ne sont plus ecrits dans le trace : ce sont des reperes (`ReperesFiche`).
    @Test func affichageDuSignal() throws {
        let s = try Self.surveillance()
        let maintenant = Date()
        // Les deux releves (-61 dBm) datent des dix dernieres minutes : a droite d'une periode qui finit maintenant, a
        // gauche d'une periode qui finit 21 h plus tard.
        let droite = try #require(s.courbes(noeud: "rloc:0400", periode: .jour, fin: maintenant))
        let tard = maintenant.addingTimeInterval(21 * 3600)
        let gauche = try #require(s.courbes(noeud: "rloc:0400", periode: .jour, fin: tard))
        let p0 = try #require(droite.signal.first), q0 = try #require(gauche.signal.first)
        let a = GrapheSignal.affichage(droite, survole: p0.date.addingTimeInterval(60), periode: .jour)
        #expect(a.domaine == -70 ... -50 && a.graduations == [-70, -60, -50])
        #expect(a.releve == p0 && a.alignement == .trailing)
        let b = GrapheSignal.affichage(gauche, survole: q0.date, periode: .jour)
        #expect(b.releve == q0 && b.alignement == .leading)
        #expect(b.domaine == a.domaine && b.graduations == a.graduations)
        #expect(GrapheSignal.affichage(droite, survole: nil, periode: .jour).releve == nil)
        #expect(GrapheSignal.affichage(droite, survole: droite.debut, periode: .jour).releve == nil, "dans un trou")
    }

    /// Le pointeur : l'heure du releve le plus proche de sa position dans la zone de trace, la meme tant que ce releve
    /// ne change pas (relecture finale, Mineur 4 : l'etat du graphe ne change pas a chaque pixel) ; aucune dans un
    /// trou, hors de la zone, et a la sortie (`.ended`). Sur 24 h, un releve compte a moins de 20 min.
    @Test func heureSurvolee() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let signal = [PointCourbe(date: d, valeur: -60, troncon: 0),
                      PointCourbe(date: d.addingTimeInterval(300), valeur: -62, troncon: 0),
                      PointCourbe(date: d.addingTimeInterval(7200), valeur: -64, troncon: 1)]
        func heure(_ phase: HoverPhase) -> Date? {
            GrapheSignal.heureSurvolee(phase, signal: signal, periode: .jour) { d.addingTimeInterval($0.x) }
        }
        #expect(heure(.active(CGPoint(x: 10, y: 5))) == d && heure(.active(CGPoint(x: 100, y: 40))) == d,
                "deux positions proches du meme releve : son heure")
        #expect(heure(.active(CGPoint(x: 200, y: 5))) == d.addingTimeInterval(300), "le suivant, plus proche")
        #expect(heure(.active(CGPoint(x: 3750, y: 5))) == nil, "dans un trou")
        #expect(GrapheSignal.heureSurvolee(.active(.zero), signal: signal, periode: .jour) { _ in nil } == nil,
                "hors de la zone de trace")
        #expect(GrapheSignal.heureSurvolee(.ended, signal: signal, periode: .jour) { _ in d } == nil)
    }

    /// La fiche montre les courbes des qu'il y a un historique (jamais en demo), et la vue lui
    /// garde plus de place en bas : la marge du bas suit la pile mesuree, plus haute avec les courbes (elle
    /// remplace les 190 et 360 pt fixes) ; pour un noeud sans historique, une ligne de texte.
    @Test func ficheEtMarge() throws {
        let s = try Self.surveillance()
        #expect(FicheNoeud.courbesVisibles(dans: s))
        let demo = Surveillance(mode: .demo, dossier: nil)
        demo.demarrer()
        #expect(!FicheNoeud.courbesVisibles(dans: demo))
        let entree = FenetrePiecesTests.entree(s)
        func pile(_ id: String) -> CGFloat {
            let v = VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                LigneDuBas(moteur: MoteurPieces(), entree: entree, legendeForcee: true)
                FicheNoeud(id: id, entree: entree, instant: Date(), aRenommer: .constant(nil)) {}
            }.frame(width: 1100 - 2 * FenetrePieces.bord)
            return NSHostingView(rootView: v.environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize.height
        }
        let avecCourbes = pile(JournalMaillageTests.appareil)
        let sansCourbes = pile("instance:inconnue")
        #expect(FenetrePieces.margeBas(pile: avecCourbes) > FenetrePieces.margeBas(pile: sansCourbes) + 100,
                "\(avecCourbes) \(sansCourbes)")
        let avec = NSHostingView(rootView: CourbesFiche(id: JournalMaillageTests.appareil, instant: Date()).environment(s)).fittingSize
        let sans = NSHostingView(rootView: CourbesFiche(id: "instance:inconnue", instant: Date()).environment(s)).fittingSize
        #expect(avec.height > sans.height + 100, "\(avec) \(sans)")
    }

    /// Un troncon d'un seul point est dessine en point : une ligne en demande deux (ajout du
    /// controleur, relecture de la tache 9).
    @Test func tronconsDUnPoint() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let points = [PointCourbe(date: t, valeur: 1, troncon: 0),
                      PointCourbe(date: t.addingTimeInterval(300), valeur: 2, troncon: 0),
                      PointCourbe(date: t.addingTimeInterval(3600), valeur: 3, troncon: 1)]
        #expect(CourbesFiche.tronconsSeuls(points) == [1])
        #expect(CourbesFiche.tronconsSeuls([]).isEmpty)
    }
}
