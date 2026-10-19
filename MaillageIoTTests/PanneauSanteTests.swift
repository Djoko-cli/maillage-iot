import AppKit
import Foundation
import MaillageCoeur
import ProtocoleZigbee
import SwiftUI
import Testing
@testable import MaillageIoT

/// Phase 6, tache 2 : la vue du panneau de sante (`PanneauSante`, spec du panneau de sante, sections 2.2 a 2.4 et 5). Le
/// panneau se dessine d'un modele d'affichage pur (`Capsule`, `Ouvert`) que ces tests lisent : les textes, les pastilles, les
/// lignes et leur ordre ; puis la vue elle-meme (repli garde, tailles, hauteur bornee a la moitie de l'espace libre), les gestes
/// (un clic sur une ligne mene au noeud, « Ailleurs » a la vue d'ensemble) et la vraie fenetre (obstacle des noms, vrai clic).
/// Les textes sont lus dans les deux langues : la passe anglaise de la porte rejoue ces tests.
@MainActor
@Suite("Panneau de sante : la vue")
struct PanneauSanteTests {
    typealias Comptes = SantePieces.Comptes
    typealias Cause = SantePieces.Cause
    typealias Pastille = PanneauSante.Pastille

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// La langue des tests : le francais, sauf la passe anglaise (`-testLanguage en`).
    static var anglais: Bool { Bundle.main.preferredLocalizations.first == "en" }

    /// Le texte attendu dans la langue des tests.
    static func texte(fr: String, en: String) -> String { anglais ? en : fr }

    /// La demo combinee, sa scene et sa lecture a la vue d'ensemble.
    static func combinee() -> (Surveillance, EntreeScene, SantePieces.Lecture) {
        let s = DemoCombineeTests.combinee()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        return (s, e, SantePieces.lire(entree: e, isolement: .maison, surveillance: s))
    }

    /// Une vue du panneau dans un hote AppKit, avec les preferences `p` : sa taille naturelle.
    static func taille(_ lecture: SantePieces.Lecture, _ s: Surveillance, preferences p: UserDefaults,
                       forcee: Bool? = nil, hauteurMax: CGFloat? = nil, moteur: MoteurPieces = MoteurPieces()) -> CGSize {
        NSHostingView(rootView: PanneauSante(lecture: lecture, moteur: moteur, instant: DemoCombineeTests.heure,
                                             hauteurMax: hauteurMax, forcee: forcee)
            .environment(s).defaultAppStorage(p)).fittingSize
    }

    // MARK: - Le modele d'affichage

    /// Une pastille a zero n'est pas montree ; rouge (perdus) avant orange (a surveiller).
    @Test func pastillesSansZero() {
        #expect(PanneauSante.pastilles(Comptes(perdus: 2, aSurveiller: 0)) == [Pastille(famille: .perdu, nombre: 2)])
        #expect(PanneauSante.pastilles(Comptes(perdus: 0, aSurveiller: 3)) == [Pastille(famille: .aSurveiller, nombre: 3)])
        #expect(PanneauSante.pastilles(Comptes(perdus: 1, aSurveiller: 4))
                == [Pastille(famille: .perdu, nombre: 1), Pastille(famille: .aSurveiller, nombre: 4)])
        #expect(PanneauSante.pastilles(Comptes()).isEmpty)
    }

    /// La capsule (option C) : les pastilles de chaque protocole montre, celles a zero cachees ; « Tout va bien » quand rien ne va
    /// mal nulle part ; « … » pour un protocole sans releve, jamais « Tout va bien » ; sans protocole, rien.
    @Test func capsule() {
        typealias Entree = SantePieces.Resume.Entree
        func resume(_ e: Entree...) -> SantePieces.Resume { SantePieces.Resume(entrees: e) }
        let deux = PanneauSante.capsule(resume(Entree(protocole: .thread, comptes: Comptes(perdus: 2, aSurveiller: 1)),
                                               Entree(protocole: .zigbee, comptes: Comptes(perdus: 0, aSurveiller: 3))))
        #expect(!deux.toutVaBien)
        #expect(deux.entrees == [
            PanneauSante.EntreeCapsule(protocole: .thread, contenu: .pastilles([Pastille(famille: .perdu, nombre: 2),
                                                                                Pastille(famille: .aSurveiller, nombre: 1)])),
            PanneauSante.EntreeCapsule(protocole: .zigbee, contenu: .pastilles([Pastille(famille: .aSurveiller, nombre: 3)])),
        ])
        let bien = PanneauSante.capsule(resume(Entree(protocole: .thread, comptes: Comptes()),
                                               Entree(protocole: .zigbee, comptes: Comptes())))
        #expect(bien.toutVaBien && bien.entrees.isEmpty, "« Tout va bien » remplace les protocoles")
        let attente = PanneauSante.capsule(resume(Entree(protocole: .thread, comptes: nil),
                                                  Entree(protocole: .zigbee, comptes: Comptes())))
        #expect(!attente.toutVaBien, "un protocole sans releve n'est pas « tout va bien »")
        #expect(attente.entrees == [PanneauSante.EntreeCapsule(protocole: .thread, contenu: .attente),
                                    PanneauSante.EntreeCapsule(protocole: .zigbee, contenu: .rienAFaire)])
        let melange = PanneauSante.capsule(resume(Entree(protocole: .thread, comptes: Comptes(perdus: 1, aSurveiller: 0)),
                                                  Entree(protocole: .zigbee, comptes: Comptes())))
        #expect(!melange.toutVaBien && melange.entrees.map(\.contenu)
                == [.pastilles([Pastille(famille: .perdu, nombre: 1)]), .rienAFaire])
        let vide = PanneauSante.capsule(resume())
        #expect(!vide.toutVaBien && vide.entrees.isEmpty)
    }

    /// Chaque cause a son texte, dans les deux langues (spec 2.1 : « disparu depuis… », « injoignable », « pile 12 % »,
    /// « adresse plus annoncee »...) ; la date est relative a l'heure du modele, comme dans la fiche.
    @Test func texteDesCauses() {
        let depuis = Self.t0.addingTimeInterval(-5 * 60)
        let relatif = FicheNoeud.relatif(depuis, Self.t0, unites: .short)
        let pourcent = String(localized: "\(12)\u{202F}%")
        let attendu: [(Cause, String, String)] = [
            (.disparu(depuis: depuis), "disparu \(relatif)", "disappeared \(relatif)"),
            (.disparu(depuis: nil), "disparu", "disappeared"),
            (.routeurDisparu(depuis: depuis), "routeur disparu \(relatif)", "router disappeared \(relatif)"),
            (.routeurDisparu(depuis: nil), "routeur disparu", "router disappeared"),
            (.pontDisparu(depuis: depuis), "pont disparu \(relatif)", "bridge disappeared \(relatif)"),
            (.pontDisparu(depuis: nil), "pont disparu", "bridge disappeared"),
            (.injoignable, "injoignable", "unreachable"),
            (.pontInjoignable, "pont injoignable", "bridge unreachable"),
            (.pile(niveau: 12), "pile \(pourcent)", "battery \(pourcent)"),
            (.pile(niveau: nil), "pile faible", "low battery"),
            (.adressePlusAnnoncee, "adresse plus annoncée", "address no longer advertised"),
            (.adresseNonAnnoncee, "adresse non annoncée", "address not advertised"),
            (.autrePartition, "autre partition", "other partition"),
        ]
        for (cause, fr, en) in attendu {
            #expect(PanneauSante.texte(cause, reference: Self.t0) == Self.texte(fr: fr, en: en), "\(cause)")
        }
        #expect(Set(attendu.map { PanneauSante.texte($0.0, reference: Self.t0) }).count == attendu.count, "toutes differentes")
    }

    /// Le titre du panneau ouvert : « Sante · » puis la portee, la maison ou le nom du niveau ou de la piece isoles.
    @Test func titreDeLaPortee() {
        let maison = String(localized: "Maison")
        #expect(PanneauSante.titre(.maison) == Self.texte(fr: "Santé · Maison", en: "Health · Home"))
        #expect(maison == Self.texte(fr: "Maison", en: "Home"))
        #expect(PanneauSante.titre(.etage("Étage")) == Self.texte(fr: "Santé · Étage", en: "Health · Étage"))
        #expect(PanneauSante.titre(.piece("Salon")) == Self.texte(fr: "Santé · Salon", en: "Health · Salon"))
    }

    /// La ligne « Ailleurs » : les perdus puis les a surveiller, les familles vides omises, le pluriel du francais.
    @Test func texteDeLigneAilleurs() {
        #expect(PanneauSante.texteAilleurs(Comptes(perdus: 1, aSurveiller: 2))
                == Self.texte(fr: "Ailleurs : 1 perdu, 2 à surveiller", en: "Elsewhere: 1 lost, 2 to watch"))
        #expect(PanneauSante.texteAilleurs(Comptes(perdus: 0, aSurveiller: 3))
                == Self.texte(fr: "Ailleurs : 3 à surveiller", en: "Elsewhere: 3 to watch"))
        #expect(PanneauSante.texteAilleurs(Comptes(perdus: 2, aSurveiller: 0))
                == Self.texte(fr: "Ailleurs : 2 perdus", en: "Elsewhere: 2 lost"))
        #expect(PanneauSante.texteAilleurs(Comptes(perdus: 1, aSurveiller: 1))
                == Self.texte(fr: "Ailleurs : 1 perdu, 1 à surveiller", en: "Elsewhere: 1 lost, 1 to watch"))
    }

    /// Le panneau ouvert de la demo combinee, a la vue d'ensemble : le titre « Maison », une section par protocole (Thread puis
    /// Zigbee) avec ses pastilles, toutes les lignes du modele dans son ordre (nom, piece, cause, famille, clic), pas de ligne
    /// « Ailleurs ». Puis une piece isolee : sa portee seule, et « Ailleurs » pour le reste.
    @Test func ouvertDeLaDemoCombinee() throws {
        let (s, e, lecture) = Self.combinee()
        let reference: (Protocole) -> Date = { s.maintenant(de: $0, a: DemoCombineeTests.heure) }
        let o = PanneauSante.ouvert(lecture, reference: reference)
        #expect(o.titre == PanneauSante.titre(.maison) && o.ailleurs == nil)
        #expect(o.sections.map(\.protocole) == [.thread, .zigbee])
        #expect(o.sections.map(\.nom) == [String(localized: "Thread"), String(localized: "Zigbee")])
        for (affichee, section) in zip(o.sections, lecture.sections) {
            #expect(affichee.pastilles == PanneauSante.pastilles(section.comptes), "\(section.protocole)")
            guard case .lignes(let lignes) = affichee.corps else {
                Issue.record("\(section.protocole) : des lignes attendues")
                continue
            }
            #expect(lignes.map(\.id) == section.lignes.map(\.id), "l'ordre du modele")
            for (l, m) in zip(lignes, section.lignes) {
                #expect(l.nom == m.nom && l.piece == m.piece && l.famille == m.famille && l.cliquable == m.cliquable)
                #expect(l.cause == PanneauSante.texte(m.cause, reference: reference(m.id.protocole)))
            }
        }
        // Un noeud connu de la demo : la prise du salon (un routeur Zigbee disparu) en tete des perdus de Zigbee.
        guard o.sections.count == 2, case .lignes(let zigbee) = o.sections[1].corps, let prise = zigbee.first else {
            Issue.record("Zigbee : des lignes attendues")
            return
        }
        #expect(prise.famille == .perdu && prise.cause.hasPrefix(Self.texte(fr: "routeur disparu", en: "router disappeared")))
        // Une piece isolee : la portee, et « Ailleurs » pour le reste de la maison.
        let piece = try #require(e.scene.pieces.first { $0.nom == .maison("Salon") })
        let focus = SantePieces.lire(entree: e, isolement: .piece(piece.id, provenance: nil), surveillance: s)
        let dedans = PanneauSante.ouvert(focus, reference: reference)
        #expect(dedans.titre == PanneauSante.titre(.piece(LibellesNoeuds.nom(piece.nom, libelles: e.libelles))))
        let ailleurs = try #require(focus.ailleurs)
        #expect(dedans.ailleurs == PanneauSante.texteAilleurs(ailleurs))
    }

    /// Un protocole sans rien dans la portee dit « Rien a signaler » ; un protocole sans releve, « … ».
    @Test func sectionsSansLigne() {
        let lecture = SantePieces.Lecture(
            capsule: SantePieces.Resume(entrees: []), portee: .maison,
            sections: [SantePieces.SectionProtocole(protocole: .thread, lignes: [], enAttente: false),
                       SantePieces.SectionProtocole(protocole: .zigbee, lignes: [], enAttente: true)],
            ailleurs: nil)
        let o = PanneauSante.ouvert(lecture) { _ in Self.t0 }
        #expect(o.sections.map(\.corps) == [.rienASignaler, .attente])
        #expect(o.sections.allSatisfy { $0.pastilles.isEmpty })
    }

    /// La hauteur du panneau ouvert ne passe jamais la moitie de la place libre entre le haut de la vue (sa marge) et ce qui est
    /// pose en bas (sa marge) ; jamais negative.
    @Test func hauteurMax() {
        #expect(PanneauSante.hauteurMax(vue: 800, margeHaut: 140, margeBas: 100) == 280)
        #expect(PanneauSante.hauteurMax(vue: 700, margeHaut: 150, margeBas: 30) == 260)
        #expect(PanneauSante.hauteurMax(vue: 300, margeHaut: 200, margeBas: 200) == 0)
    }

    // MARK: - La vue

    /// Une lecture longue, inventee : `n` noeuds perdus de Thread, tous dans le salon.
    static func longue(_ n: Int) -> SantePieces.Lecture {
        let lignes = (0..<n).map { k in
            SantePieces.Ligne(id: IdNoeud(.thread, "T\(k)"), nom: "Lampe \(k)", piece: "Salon",
                              cause: .disparu(depuis: nil), cliquable: true)
        }
        return SantePieces.Lecture(
            capsule: SantePieces.Resume(entrees: [.init(protocole: .thread, comptes: Comptes(perdus: n, aSurveiller: 0))]),
            portee: .maison, sections: [SantePieces.SectionProtocole(protocole: .thread, lignes: lignes, enAttente: false)],
            ailleurs: Comptes(perdus: 1, aSurveiller: 0))
    }

    /// Le panneau est replie par defaut, et le repli est garde dans les preferences (`santeRepliee`, a lui, distinct de celui de
    /// la legende) ; un etat impose (captures) passe avant, sans rien ecrire.
    @Test func repliParDefautEtGarde() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, _, lecture) = Self.combinee()
        #expect(PanneauSante.cleRepliee == "santeRepliee" && PanneauSante.cleRepliee != LegendePieces.cleRepliee)
        let repliee = Self.taille(lecture, s, preferences: p, forcee: true)
        let ouverte = Self.taille(lecture, s, preferences: p, forcee: false)
        #expect(repliee.height > 10 && repliee.height < 40, "la capsule : \(repliee)")
        #expect(ouverte.height > 4 * repliee.height, "le panneau ouvert : \(ouverte)")
        #expect(p.object(forKey: PanneauSante.cleRepliee) == nil)
        #expect(Self.taille(lecture, s, preferences: p) == repliee, "sans preference : replie")
        p.set(false, forKey: PanneauSante.cleRepliee)
        #expect(Self.taille(lecture, s, preferences: p) == ouverte, "ouvert, tel que Djoko l'a laisse")
        #expect(Self.taille(lecture, s, preferences: p, forcee: true) == repliee)
        p.set(true, forKey: PanneauSante.cleRepliee)
        #expect(Self.taille(lecture, s, preferences: p) == repliee)
        // Le repli de la legende n'est pas le sien.
        p.removeObject(forKey: PanneauSante.cleRepliee)
        p.set(false, forKey: LegendePieces.cleRepliee)
        #expect(Self.taille(lecture, s, preferences: p) == repliee)
        #expect(p.object(forKey: PanneauSante.cleRepliee) == nil, "l'etat impose n'ecrit rien")
    }

    /// Sans rien a dire (aucun protocole montre), le panneau n'est pas dessine.
    @Test func lectureVideSansPanneau() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, _, _) = Self.combinee()
        let vide = SantePieces.Lecture(capsule: SantePieces.Resume(entrees: []), portee: .maison, sections: [], ailleurs: nil)
        #expect(vide.estVide)
        for forcee in [true, false] {
            #expect(Self.taille(vide, s, preferences: p, forcee: forcee) == .zero)
        }
    }

    /// La hauteur du panneau ouvert est bornee (`hauteurMax`, la moitie de l'espace libre) : une liste longue defile dans le
    /// panneau au lieu de le grandir ; une liste courte ne s'etire pas jusqu'a la limite ; le repli, lui, n'a pas de limite.
    @Test func hauteurBorneeAvecDefilement() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (s, _, _) = Self.combinee()
        let longue = Self.longue(40), courte = Self.longue(2)
        let libre = Self.taille(longue, s, preferences: p, forcee: false)
        #expect(libre.height > 600, "40 lignes sans limite : \(libre)")
        for limite in [200.0, 320.0] {
            let borne = Self.taille(longue, s, preferences: p, forcee: false, hauteurMax: limite)
            #expect(abs(borne.height - limite) < 0.5, "limite \(limite) : \(borne)")
            #expect(borne.width == libre.width && borne.width == PanneauSante.largeur)
        }
        let naturelle = Self.taille(courte, s, preferences: p, forcee: false)
        #expect(Self.taille(courte, s, preferences: p, forcee: false, hauteurMax: 600) == naturelle, "une liste courte ne s'etire pas")
        #expect(Self.taille(courte, s, preferences: p, forcee: false, hauteurMax: 600).height < 600)
        let capsule = Self.taille(longue, s, preferences: p, forcee: true)
        #expect(Self.taille(longue, s, preferences: p, forcee: true, hauteurMax: 40) == capsule)
    }

    // MARK: - Les gestes

    /// Les deux noeuds de la demo, perdus ou a surveiller, dans deux pieces de deux niveaux differents.
    static func deuxNoeuds(_ lecture: SantePieces.Lecture, _ e: EntreeScene) throws -> (SantePieces.Ligne, SantePieces.Ligne) {
        let lignes = lecture.sections.flatMap(\.lignes).filter(\.cliquable)
        func etage(_ l: SantePieces.Ligne) -> Int? { e.scene.noeud(l.id).map { e.scene.pieces[$0.piece].etage } }
        let a = try #require(lignes.first)
        let b = try #require(lignes.first { etage($0) != etage(a) }, "deux niveaux differents")
        return (a, b)
    }

    static func piece(_ l: SantePieces.Ligne, _ e: EntreeScene) throws -> (Int, ScenePieces.Piece) {
        let i = try #require(e.scene.noeud(l.id)).piece
        return (i, e.scene.pieces[i])
    }

    /// Un clic sur une ligne mene au noeud comme un clic sur lui : la piece du noeud est isolee (le vol de camera habituel) et le
    /// noeud choisi (sa fiche, le mode focus) ; depuis la vue d'ensemble, depuis un autre niveau isole, depuis une autre piece.
    @Test func cliquerUneLigneMeneAuNoeud() throws {
        let (_, e, lecture) = Self.combinee()
        let (a, b) = try Self.deuxNoeuds(lecture, e)
        let (_, pieceA) = try Self.piece(a, e)
        let (_, pieceB) = try Self.piece(b, e)
        // Depuis la vue d'ensemble.
        let m = MoteurPiecesTests.moteur(e)
        #expect(m.isolement == .maison && m.selection == nil)
        #expect(m.allerAuNoeud(a.id))
        #expect(m.isolement == .piece(pieceA.id, provenance: nil) && m.selection == a.id)
        // Depuis une autre piece : l'autre noeud, son autre piece.
        #expect(m.allerAuNoeud(b.id))
        guard case .piece(let cle, _) = m.isolement else { Issue.record("une piece isolee : \(m.isolement)"); return }
        #expect(cle == pieceB.id && m.selection == b.id)
        // Depuis un autre niveau isole.
        let n = MoteurPiecesTests.moteur(e)
        n.allerEtage(pieceB.etage)
        #expect(n.isolement == .etage(e.scene.etages[pieceB.etage].id))
        #expect(n.allerAuNoeud(a.id))
        guard case .piece(let autre, _) = n.isolement else { Issue.record("une piece isolee : \(n.isolement)"); return }
        #expect(autre == pieceA.id && n.selection == a.id)
        // Un noeud de la piece deja isolee : la vue ne bouge pas, le noeud est choisi, et choisi encore au second clic.
        let avant = n.isolement
        let voisin = lecture.sections.flatMap(\.lignes).first { $0.cliquable && $0.id != a.id && (try? Self.piece($0, e))?.1.id == pieceA.id }
        if let voisin {
            #expect(n.allerAuNoeud(voisin.id))
            #expect(n.isolement == avant && n.selection == voisin.id)
            #expect(n.allerAuNoeud(voisin.id) && n.selection == voisin.id, "un second clic ne ferme pas la fiche")
        }
    }

    /// Un noeud absent de la scene n'a pas de piece a isoler : rien ne change, le clic est refuse. Pendant l'envol 2D / 3D, comme
    /// un clic sur la scene, rien non plus.
    @Test func cliquerSansEffet() throws {
        let (_, e, lecture) = Self.combinee()
        let (a, _) = try Self.deuxNoeuds(lecture, e)
        let m = MoteurPiecesTests.moteur(e)
        #expect(!m.allerAuNoeud(IdNoeud(.thread, "ABSENT")))
        #expect(m.isolement == .maison && m.selection == nil)
        m.basculer(troisD: true)
        #expect(m.envol != nil)
        #expect(!m.allerAuNoeud(a.id))
        #expect(m.isolement == .maison && m.selection == nil, "pas pendant l'envol")
    }

    // MARK: - La lecture memoisee

    /// Le journal n'est lu que s'il a change (l'arrivee d'un evenement, un releve de la session) et non a chaque rendu : la
    /// lecture est celle du modele, que le focus change ou non.
    @Test func lectureMemoisee() throws {
        let s = DemoCombineeTests.combinee()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let memo = MemoSante()
        let premiere = memo.lire(entree: e, isolement: .maison, surveillance: s)
        #expect(premiere == SantePieces.lire(entree: e, isolement: .maison, surveillance: s))
        #expect(memo.lecturesDuJournal == 1 && memo.lecturesDesDates == 1)
        for _ in 0..<5 { _ = memo.lire(entree: e, isolement: .maison, surveillance: s) }
        let piece = try #require(e.scene.pieces.first)
        let focus = memo.lire(entree: e, isolement: .piece(piece.id, provenance: nil), surveillance: s)
        #expect(focus == SantePieces.lire(entree: e, isolement: .piece(piece.id, provenance: nil), surveillance: s))
        #expect(memo.lecturesDuJournal == 1 && memo.lecturesDesDates == 1, "ni le rendu, ni le focus ne relisent le journal")
        // Un evenement arrive au journal : il est relu, une fois.
        let id = try #require(e.appareils.values.first { $0.etat == .disparu && $0.id.protocole == .thread }).id
        s.ajouter([Evenement(date: DemoCombineeTests.heure, type: .appareilDisparu, sujet: Sujet(id: id.cle, nom: "x"))], de: .thread)
        let apres = memo.lire(entree: e, isolement: .maison, surveillance: s)
        #expect(apres == SantePieces.lire(entree: e, isolement: .maison, surveillance: s))
        #expect(memo.lecturesDuJournal == 2 && memo.lecturesDesDates == 2)
        _ = memo.lire(entree: e, isolement: .maison, surveillance: s)
        #expect(memo.lecturesDuJournal == 2 && memo.lecturesDesDates == 2)
    }

    // MARK: - La vraie fenetre

    /// Dans la vraie fenetre (demo combinee, la plus petite taille) : le panneau est replie en haut a gauche, sous le haut de la
    /// vue, et c'est un obstacle pour les noms ; un vrai clic l'ouvre, et la preference garde son etat ; ouvert, il ne passe pas
    /// la moitie de l'espace libre ni ne touche ce qui est en bas ; un second clic sur son en-tete le replie.
    @Test(.timeLimit(.minutes(3))) func dansLaFenetre() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let s = DemoCombineeTests.combinee()
        let taille = FenetrePieces.tailleMinimale
        let (fenetre, moteur) = try FenetrePiecesTests.fenetre(s, taille: taille, preferences: p)
        defer { FenetrePiecesTests.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["sante"] != nil && moteur.cadresInterface["legende"] != nil && moteur.pret }
        try await Task.sleep(for: .milliseconds(600))
        let repliee = try #require(moteur.cadresInterface["sante"], "obstacle des noms, replie")
        #expect(repliee.height < 40 && repliee.minX == FenetrePieces.bord, "en haut a gauche : \(repliee)")
        let haut = try #require(moteur.cadresInterface["niveau"])
        #expect(repliee.minY >= haut.maxY, "sous le haut de la vue : \(repliee) sous \(haut)")
        #expect(moteur.surInterface(CGPoint(x: repliee.midX, y: repliee.midY)))
        // Un vrai clic sur la capsule l'ouvre.
        try await FenetrePiecesTests.cliquer(fenetre, en: CGPoint(x: repliee.midX, y: repliee.midY))
        try await MoteurPiecesTests.attendre { p.object(forKey: PanneauSante.cleRepliee) as? Bool == false }
        #expect(p.object(forKey: PanneauSante.cleRepliee) as? Bool == false)
        try await MoteurPiecesTests.attendre { (moteur.cadresInterface["sante"]?.height ?? 0) > 100 }
        try await Task.sleep(for: .milliseconds(700))
        let ouverte = try #require(moteur.cadresInterface["sante"])
        #expect(ouverte.height > 100 && ouverte.width == PanneauSante.largeur && ouverte.minX == repliee.minX && ouverte.minY == repliee.minY)
        // La hauteur de la vue : celle du contenu de la fenetre (la barre d'outils invisible compte : 52 pt de plus que la taille minimale).
        let hauteurVue = try #require(fenetre.contentView).bounds.height
        #expect(hauteurVue >= taille.height)
        let limite = PanneauSante.hauteurMax(vue: hauteurVue, margeHaut: moteur.marges.haut, margeBas: moteur.marges.bas)
        #expect(ouverte.height <= limite + 0.5, "moitie de l'espace libre : \(ouverte.height) sur \(limite)")
        let legende = try #require(moteur.cadresInterface["legende"])
        #expect(ouverte.maxY <= legende.minY, "au-dessus de la legende : \(ouverte) \(legende)")
        // Un clic sur l'en-tete (la premiere ligne) le replie.
        try await FenetrePiecesTests.cliquer(fenetre, en: CGPoint(x: ouverte.minX + 40, y: ouverte.minY + 16))
        try await MoteurPiecesTests.attendre { p.object(forKey: PanneauSante.cleRepliee) as? Bool == true }
        #expect(p.object(forKey: PanneauSante.cleRepliee) as? Bool == true)
    }

    /// Dans une fenetre haute, la legende repliee : la liste de la demo (courte) tient sans defiler, a sa hauteur naturelle (elle ne
    /// s'etire pas jusqu'a la limite que la fenetre lui laisse) ; les gestes de la vraie fenetre : un clic dans un coin vide du
    /// panneau ne touche pas la scene dessous, un vrai clic sur une ligne isole la piece du noeud et le choisit, un vrai clic sur
    /// « Ailleurs » revient a la vue d'ensemble.
    @Test(.timeLimit(.minutes(3))) func gestesDansLaFenetre() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        p.set(true, forKey: LegendePieces.cleRepliee)
        p.set(false, forKey: PanneauSante.cleRepliee)
        let s = DemoCombineeTests.combinee()
        let (fenetre, moteur) = try FenetrePiecesTests.fenetre(s, taille: CGSize(width: 1100, height: 960), preferences: p)
        defer { FenetrePiecesTests.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["sante"] != nil && moteur.pret }
        try await Task.sleep(for: .milliseconds(800))
        let entree = try #require(moteur.entree)
        let lecture = SantePieces.lire(entree: entree, isolement: .maison, surveillance: s)
        let panneau = try #require(moteur.cadresInterface["sante"])
        // Sa hauteur naturelle, sans limite, et sous la limite que la fenetre lui laisse.
        let naturelle = Self.taille(lecture, s, preferences: p, forcee: false).height
        let limite = PanneauSante.hauteurMax(vue: try #require(fenetre.contentView).bounds.height, margeHaut: moteur.marges.haut,
                                             margeBas: moteur.marges.bas)
        #expect(naturelle < limite - 20, "la demo tient dans la fenetre : \(naturelle) pour \(limite)")
        #expect(abs(panneau.height - naturelle) < 0.5, "pas etire : \(panneau.height) pour \(naturelle)")
        // Un coin vide du panneau (sa marge droite) ne laisse pas passer le clic a la scene : la fiche ouverte reste ouverte.
        let chef = IdNoeud(.thread, "Apple TV 4K")
        moteur.selection = chef
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] != nil }
        try await Task.sleep(for: .milliseconds(700))
        try await FenetrePiecesTests.cliquer(fenetre, en: CGPoint(x: panneau.maxX - 4, y: panneau.midY))
        try await Task.sleep(for: .milliseconds(300))
        #expect(moteur.selection == chef, "le clic dans le panneau n'a pas atteint la scene")
        moteur.selection = nil
        try await Task.sleep(for: .milliseconds(700))
        // Un vrai clic sur une ligne : on balaie le panneau jusqu'a la premiere ligne cliquable.
        let lignes = Dictionary(uniqueKeysWithValues: lecture.sections.flatMap(\.lignes).filter(\.cliquable).map { ($0.id, $0) })
        var y = panneau.minY + 36
        while moteur.selection == nil, y < panneau.maxY - 8 {
            try await FenetrePiecesTests.cliquer(fenetre, en: CGPoint(x: panneau.minX + 50, y: y))
            try await Task.sleep(for: .milliseconds(40))
            y += 5
        }
        let choisi = try #require(moteur.selection, "une ligne cliquee")
        #expect(lignes[choisi] != nil, "un noeud de la liste")
        let pieceDuNoeud = try #require(entree.scene.noeud(choisi)).piece
        #expect(moteur.isolement == .piece(entree.scene.pieces[pieceDuNoeud].id, provenance: nil))
        // La liste suit le focus : « Ailleurs » parait, un vrai clic dessus ramene a la vue d'ensemble.
        try await MoteurPiecesTests.attendre { (moteur.cadresInterface["sante"]?.height ?? 0) > 0 }
        try await Task.sleep(for: .milliseconds(1500))
        let isole = try #require(moteur.cadresInterface["sante"])
        try await FenetrePiecesTests.cliquer(fenetre, en: CGPoint(x: isole.minX + 60, y: isole.maxY - Self.marges.bottom - 6))
        try await Task.sleep(for: .milliseconds(100))
        #expect(moteur.isolement == .maison, "« Ailleurs » : la vue d'ensemble")
    }

    // MARK: - Sous la derniere ligne du haut

    /// Correctif du banc (phase 6) : l'ecart entre le bas de la derniere ligne du haut de la vue (la ligne de niveau, toujours la)
    /// et le haut du panneau, replie ou ouvert, dans la vraie fenetre ; nil avant que l'un des deux soit pose.
    static func ecartSousLeHaut(_ moteur: MoteurPieces) -> CGFloat? {
        guard let sante = moteur.cadresInterface["sante"], let bas = FenetrePiecesTests.basDuHaut(moteur) else { return nil }
        return sante.minY - bas
    }

    /// Le panneau est juste sous la derniere ligne du haut, a l'ecart qui separe les lignes du haut entre elles
    /// (`FenetrePieces.espacement`), quoi qu'il y ait au-dessus : le reseau scinde (son bandeau), la ligne de la tournee, la place
    /// que la scene lui garde apres sa fin (la marge du haut ne bouge pas, le panneau suit le texte), la sonde oubliee. Et il
    /// suit les lignes qui paraissent et disparaissent sans jamais s'en eloigner, a aucun instant du mouvement.
    @Test(.timeLimit(.minutes(2))) func sousLaDerniereLigneAvecBandeauEtTournee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let journal = JournalCanaux()
        let canal = SondeMaillageTests.canalRetenu(journal)
        let sonde = SondeMaillageThread(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let s = DemoCombineeTests.combinee()
        #expect(s.thread.reseau?.estScinde == true, "la demo : le bandeau de scission")
        let (fenetre, moteur) = try FenetrePiecesTests.fenetre(s, taille: CGSize(width: 1100, height: 900), preferences: p, sonde: sonde)
        defer { FenetrePiecesTests.fermer(fenetre) }
        func stable() async throws {
            try await MoteurPiecesTests.attendre { moteur.pret && Self.ecartSousLeHaut(moteur) != nil && !moteur.margesEnRoute }
            try await Task.sleep(for: .milliseconds(500))
        }
        func verifier(_ cas: String) throws {
            let ecart = try #require(Self.ecartSousLeHaut(moteur), Comment(rawValue: cas))
            #expect(abs(ecart - FenetrePieces.espacement) < 0.5, "\(cas) : \(ecart) pt sous la derniere ligne, au lieu de \(FenetrePieces.espacement)")
        }
        try await stable()
        try verifier("bandeau de scission, sans sonde")
        // Une sonde retenue, en tournee : la ligne de la tournee parait au-dessus du bandeau.
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        await journal.attendre(SondeMaillageTests.listeRetenue)
        await SondeMaillageTests.attendre { sonde.avancement != nil }
        try await stable()
        try verifier("pendant la tournee")
        let margePendant = moteur.marges.haut
        // La tournee finit : sa ligne repart, la marge du haut la garde, le panneau remonte avec le texte, et reste a l'ecart a chaque instant.
        canal.emettre(CanalRejoue.reseauMinimal(SondeMaillageTests.listeRetenue + "\n"))
        await SondeMaillageTests.attendre { !sonde.tourneeEnCours }
        var ecarts: [CGFloat] = []
        let t0 = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - t0 < 0.9 {
            if let e = Self.ecartSousLeHaut(moteur) { ecarts.append(e) }
            try await Task.sleep(for: .milliseconds(4))
        }
        #expect(moteur.marges.haut == margePendant, "la scene ne bouge pas")
        #expect(ecarts.count > 20 && ecarts.allSatisfy { abs($0 - FenetrePieces.espacement) < 0.5 },
                "a chaque instant de la fin de la tournee : \(Set(ecarts.map { ($0 * 10).rounded() / 10 }).sorted())")
        try await stable()
        try verifier("apres la tournee, la place gardee")
        // La sonde oubliee : la marge ne compte plus la ligne, le panneau ne bouge pas.
        await sonde.oublier()
        try await MoteurPiecesTests.attendre { moteur.marges.haut < margePendant && !moteur.margesEnRoute }
        try await stable()
        try verifier("sonde oubliee")
        // Ouvert, au meme endroit.
        p.set(false, forKey: PanneauSante.cleRepliee)
        try await MoteurPiecesTests.attendre { (moteur.cadresInterface["sante"]?.height ?? 0) > 100 }
        try await stable()
        try verifier("panneau ouvert")
    }

    /// Sans bandeau de partition (Zigbee seul), la meme chose : la place gardee a la ligne de la tournee, la sonde retenue hors
    /// tournee, ne laisse pas de vide au-dessus du panneau ; « Maillage incomplet » (qui prend la place de la ligne), puis la ligne
    /// de la tournee, qui le remplace, laissent le panneau a l'ecart.
    @Test(.timeLimit(.minutes(2))) func sousLaDerniereLigneSansBandeauAvecMaillageIncomplet() async throws {
        let (p, domaine) = try SondeMaillageZigbeeTests.preferences()
        defer { SondeMaillageZigbeeTests.nettoyer(p, domaine) }
        p.set(false, forKey: PanneauSante.cleRepliee)
        let canal = CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) }
        let sonde = SondeMaillageZigbee(preferences: p, actif: true, trousseau: TrousseauMemoireZigbee(), ouvrirCanal: { _ in canal })
        let demo = NomsSceneZigbeeTests.surveillanceDemo()
        #expect(demo.thread.reseau == nil, "Zigbee seul : pas de bandeau de partition")
        let (fenetre, moteur) = try FenetrePiecesZigbeeTests.fenetre(demo, taille: CGSize(width: 1100, height: 900), preferences: p,
                                                                     sonde: sonde)
        defer { FenetrePiecesTests.fermer(fenetre) }
        func stable() async throws {
            try await MoteurPiecesTests.attendre { moteur.pret && Self.ecartSousLeHaut(moteur) != nil && !moteur.margesEnRoute }
            try await Task.sleep(for: .milliseconds(500))
        }
        func verifier(_ cas: String) throws {
            let ecart = try #require(Self.ecartSousLeHaut(moteur), Comment(rawValue: cas))
            #expect(abs(ecart - FenetrePieces.espacement) < 0.5, "\(cas) : \(ecart) pt sous la derniere ligne, au lieu de \(FenetrePieces.espacement)")
        }
        try await stable()
        try verifier("sans sonde")
        // Une sonde retenue, hors tournee : la scene garde la place de la ligne, le panneau ne la garde pas.
        await sonde.connecter(SondeMaillageZigbeeTests.port, choisi: true)
        sonde.debuterTournee()
        sonde.finirTournee(nil)
        try await stable()
        try verifier("sonde retenue, hors tournee")
        // Le maillage affiche est marque incomplet : l'indicateur prend la place de la ligne.
        demo.zigbee.recevoir(MaillageDemoZigbee.maillage, a: MaillageDemoZigbee.fin, incomplet: true)
        try await MoteurPiecesZigbeeTests.attendre { moteur.cadresInterface["colonne"].map { $0.height > 40 } ?? false }
        try await stable()
        try verifier("Maillage incomplet")
        // Une tournee commence : sa ligne prend la place de l'indicateur.
        sonde.debuterTournee()
        try await stable()
        try verifier("pendant la tournee")
        await sonde.oublier()
    }

    static let marges = PanneauSante.marges
}
