import AppKit
import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Mode focus dans l'app (repris de Maillage Zigbee, 09/10) : ce que Thread met en avant (`FocusThread`), le moteur qui
/// suit la selection, le second clic, le clic dans le vide, Echap, et la transition douce. Sur la demo (valeurs
/// inventees ; le chef est l'Apple TV 4K).
@MainActor
@Suite("Mode focus")
struct FocusTests {
    static let chef = idt("Apple TV 4K")

    /// Un appareil : lui, son parent et son lien vers lui, le chef, et le lien radio direct de son parent vers le chef
    /// s'il existe ; rien d'autre.
    @Test func appareil() throws {
        let (_, e) = try MoteurPiecesTests.moteur()
        let g = e.graphe
        let lien = try #require(g.liens.first { l in
            l.genre == .parent && g.noeud(l.de)?.routeur == false && l.vers != Self.chef
                && g.liens.contains { $0.genre == .radio && Set([$0.de, $0.vers]) == [l.vers, Self.chef] }
        })
        let m = try #require(e.miseEnAvant(de: lien.de, liens: .tous, voisins: true))
        #expect(m.noeuds == [lien.de, lien.vers, Self.chef])
        #expect(m.liens == [MiseEnAvant.cle(lien.de, lien.vers), MiseEnAvant.cle(lien.vers, Self.chef)])
        #expect(e.miseEnAvant(de: idt("absent"), liens: .tous, voisins: true) == nil)
    }

    /// Un routeur : ses enfants et leurs liens, ses liens radio et ses voisins, le chef ; un lien radio entre deux autres
    /// routeurs reste estompe.
    @Test func routeur() throws {
        let (_, e) = try MoteurPiecesTests.moteur()
        let g = e.graphe
        let r = try #require(g.noeuds.first { n in
            n.routeur && n.id != Self.chef && g.liens.contains { $0.genre == .parent && $0.vers == n.id }
        })
        let m = try #require(e.miseEnAvant(de: r.id, liens: .tous, voisins: true))
        for l in g.liens where l.de == r.id || l.vers == r.id {
            if l.genre == .radio || (l.genre == .parent && l.vers == r.id) {
                #expect(m.contient(lien: l), "\(l.de) - \(l.vers)")
            }
        }
        #expect(m.noeuds.contains(Self.chef))
        let autre = try #require(g.liens.first { $0.genre == .radio && $0.de != r.id && $0.vers != r.id })
        #expect(!m.contient(lien: autre))
    }

    /// Le moteur suit la selection : a la selection d'un appareil, ce qui n'est pas mis en avant s'estompe (une capture,
    /// figee, le prend tout de suite), ses pastilles et ses noms aussi, pas celles mises en avant ; Echap rend la vue
    /// normale.
    @Test func moteur() throws {
        let (m, e) = try MoteurPiecesTests.moteur()
        m.fige = true
        #expect(m.miseEnAvant == nil && m.noeudsEstompes.isEmpty)
        let lien = try #require(e.graphe.liens.first { $0.genre == .parent && $0.vers != Self.chef })
        m.selection = lien.de
        let focus = try #require(m.miseEnAvant)
        #expect(focus == e.miseEnAvant(de: lien.de, liens: .tous, voisins: true))
        #expect(m.noeudsEstompes.count == e.scene.noeuds.count - focus.noeuds.filter { e.scene.noeud($0) != nil }.count)
        let estompe = try #require(e.scene.noeuds.first { !focus.noeuds.contains($0.id) }).id
        MoteurPiecesTests.dessiner(m)
        let p = try #require(m.projetee)
        #expect(p.disques.first { $0.noeud == estompe }?.focus == MiseEnAvant.opaciteEstompee)
        #expect(p.disques.first { $0.noeud == lien.vers }?.focus == 1, "son parent reste net")
        #expect(p.facteur(noeud: estompe) < 1 && p.facteur(noeud: lien.de) == 1)
        #expect(m.sortir())
        #expect(m.selection == nil && m.miseEnAvant == nil && m.noeudsEstompes.isEmpty && m.liensEstompes.isEmpty)
    }

    /// Un clic sur un noeud le choisit ; un second clic sur lui le relache ; un clic sur un autre noeud change le focus ;
    /// un clic dans le vide le relache.
    @Test func secondClicEtVide() throws {
        let (m, e) = try MoteurPiecesTests.moteur()
        func centre(_ id: IdNoeud) throws -> CGPoint {
            MoteurPiecesTests.dessiner(m)
            return try #require(m.projetee?.disques.first { $0.noeud == id }).centre
        }
        let chef = try centre(Self.chef)
        m.cliquer(chef)
        #expect(m.selection == Self.chef && m.miseEnAvant != nil)
        m.cliquer(chef)
        #expect(m.selection == nil && m.miseEnAvant == nil, "second clic : la vue normale")
        m.cliquer(chef)
        let autre = try #require(e.graphe.liens.first { $0.genre == .parent && $0.vers == Self.chef }).de
        m.cliquer(try centre(autre))
        #expect(m.selection == autre && m.miseEnAvant?.noeuds.contains(autre) == true)
        m.cliquer(CGPoint(x: 5, y: MoteurPiecesTests.taille.height / 2))
        #expect(m.selection == nil && m.miseEnAvant == nil, "clic dans le vide")
    }

    /// L'estompement va en douceur : l'horloge continue tant qu'il est en route, et il arrive a sa cible.
    @Test func transitionDouce() throws {
        let (m, _) = try MoteurPiecesTests.moteur()
        m.selection = Self.chef
        #expect(m.focusEnRoute && m.doitContinuer(MoteurPieces.maintenant()))
        let k = 0.05 * MoteurPieces.vitesseFocus
        m.noeudsEstompes = MiseEnAvant.tendre(m.noeudsEstompes, vers: m.ciblesFocus.noeuds, k: k)
        let mi = try #require(m.noeudsEstompes.values.first)
        #expect(mi > 0 && mi < 1, "en route : \(mi)")
        for _ in 0..<60 {
            m.noeudsEstompes = MiseEnAvant.tendre(m.noeudsEstompes, vers: m.ciblesFocus.noeuds, k: k)
            m.liensEstompes = MiseEnAvant.tendre(m.liensEstompes, vers: m.ciblesFocus.liens, k: k)
        }
        #expect(!m.focusEnRoute, "arrive en 3 s au plus")
    }

    /// Le nom d'un noeud estompe se lit au survol (repris de Maillage Zigbee, 09/10) : sous le focus, un nom fort (survole)
    /// reste a 80 % au moins ; les autres suivent leur noeud.
    @Test func nomSurvoleSousLeFocus() {
        let estompe = MiseEnAvant.opaciteEstompee
        #expect(RenduCanvas.facteurNom(estompe, fort: true) == RenduCanvas.opaciteNomFort)
        #expect(RenduCanvas.facteurNom(estompe, fort: false) == estompe)
        #expect(RenduCanvas.facteurNom(1, fort: true) == 1 && RenduCanvas.facteurNom(1, fort: false) == 1)
        #expect(RenduCanvas.facteurNom(0.9, fort: true) == 0.9, "jamais plus estompe qu'avant, ni plus net que le noeud net")
    }

    /// Les rangees fluides : a la ligne quand la place manque ; un element plus large que la rangee est ramene a sa
    /// largeur (il ne deborde pas), avec ou sans largeur proposee, et une largeur infinie vaut aucune.
    @Test func rangeesFluides() {
        let t = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 12), CGSize(width: 200, height: 10)]
        let large = RangeesFluides.disposer(t, largeur: 100, espacement: 5, interligne: 4)
        #expect(large.places == [CGPoint(x: 0, y: 0), CGPoint(x: 45, y: 0), CGPoint(x: 0, y: 16)])
        #expect(large.tailles.map(\.width) == [40, 50, 100], "la pastille trop large est bornee a la rangee")
        #expect(large.total == CGSize(width: 100, height: 26))
        let libre = RangeesFluides.disposer(t, largeur: nil, espacement: 5, interligne: 4)
        #expect(libre.places.map(\.y) == [0, 0, 0] && libre.total.width == 40 + 5 + 50 + 5 + 200)
        #expect(RangeesFluides.disposer(t, largeur: .infinity).tailles.map(\.width) == [40, 50, 200])
        #expect(RangeesFluides.disposer([], largeur: 100).total == CGSize(width: 100, height: 0))
    }

    /// Les colonnes de la fiche : quatre, puis deux, puis une, selon la place ; une largeur infinie ne donne pas de
    /// colonne infinie. Les courbes : au-dela de huit, le trait change ; le graphe garde la courbe mise en avant dans son
    /// etat, refait par un autre noeud, une autre periode ou la case « tous les liens ».
    @Test func colonnesEtCourbes() {
        #expect(ColonnesFiche.colonnes(largeur: 4 * 190 + 3 * 24, nombre: 4) == 4)
        #expect(ColonnesFiche.colonnes(largeur: 4 * 190 + 3 * 24 - 1, nombre: 4) == 2, "jamais trois : des rangees pleines")
        #expect(ColonnesFiche.colonnes(largeur: 300, nombre: 4) == 1)
        let sansLimite = ColonnesFiche.grille(largeur: .infinity, nombre: 4)
        #expect(sansLimite.colonnes == 4 && sansLimite.largeur == ColonnesFiche.largeurMinimale)
        #expect(ColonnesFiche.grille(largeur: nil, nombre: 4).largeur == ColonnesFiche.largeurMinimale)
        #expect(CourbesFiche.tirets(0).isEmpty && CourbesFiche.tirets(7).isEmpty)
        #expect(!CourbesFiche.tirets(8).isEmpty && CourbesFiche.tirets(8) != CourbesFiche.tirets(16))
        #expect(CourbesFiche.couleur(8) == CourbesFiche.couleur(0))
        let base = CourbesFiche.identiteGraphe(id: idt("a"), tous: false, periode: .jour)
        #expect(base == CourbesFiche.identiteGraphe(id: idt("a"), tous: false, periode: .jour))
        #expect(base != CourbesFiche.identiteGraphe(id: idt("b"), tous: false, periode: .jour))
        #expect(base != CourbesFiche.identiteGraphe(id: idt("a"), tous: true, periode: .jour))
        #expect(base != CourbesFiche.identiteGraphe(id: idt("a"), tous: false, periode: .semaine))
        #expect(FicheNoeud.valeurPastille(qualite: 3) == String(localized: "qualité du lien : \(NiveauQualite.bonne.nom)"))
    }
}
