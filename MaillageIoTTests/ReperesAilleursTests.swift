import AppKit
import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Les reperes « ailleurs » d'une piece isolee sous une selection (point 9 de la vue des liens) : sans selection, tous ;
/// avec une selection, seuls ceux de ses propres liens vers une autre piece ou un autre niveau (dans les deux sens) ; les
/// autres s'effacent avec la meme animation que la mise en avant, et leur fil avec eux. Sur la demo combinee (valeurs
/// inventees).
@MainActor
@Suite("Reperes ailleurs sous une selection")
struct ReperesAilleursTests {
    /// Isole `piece` et attend la fin de l'isolement (le vol, la part de la piece), puis fige le moteur : l'estompement est
    /// pris tout de suite, sans horloge.
    static func isoler(_ m: MoteurPieces, _ piece: Int) {
        m.isoler(piece)
        for _ in 0..<60 {
            MoteurPiecesTests.dessiner(m)
            Thread.sleep(forTimeInterval: 0.05)
        }
        m.fige = true
        MoteurPiecesTests.dessiner(m)
    }

    /// Une piece isolee de la demo combinee qui a au moins deux reperes « ailleurs », son moteur (fige : l'estompement est
    /// pris tout de suite), la scene et les reperes de la piece, en ordre.
    static func pieceIsolee() throws -> (m: MoteurPieces, e: EntreeScene, piece: Int, reperes: [Ailleurs]) {
        let e = EntreeScene(surveillance: DemoCombineeTests.combinee(), places: PlacesGardees())
        let m = MoteurPiecesTests.moteur(e)
        m.poserZoom(echelle: 1, vers: nil)
        let piece = try #require(e.scene.pieces.indices.first { SceneProjetee.reperes(e.scene, focus: $0).count >= 2 },
                                 "une piece de la demo combinee avec au moins deux reperes")
        Self.isoler(m, piece)
        return (m, e, piece, SceneProjetee.reperes(e.scene, focus: piece))
    }

    /// Les reperes « ailleurs » vus a l'image : l'enfant de chacun, dont le nom est pose.
    static func vus(_ m: MoteurPieces) -> Set<IdNoeud> {
        MoteurPiecesTests.dessiner(m)
        return Set(m.etiquettes.compactMap { l in
            if case .ailleurs(let id) = l.genre, l.vu { id } else { nil }
        })
    }

    /// Sans selection : tous les reperes, comme avant.
    @Test func sansSelection() throws {
        let (m, _, _, reperes) = try Self.pieceIsolee()
        #expect(m.selection == nil && m.textes.ailleurs.count == reperes.count)
        let vus = Self.vus(m)
        let etats = m.etiquettes.compactMap { l -> String? in
            if case .ailleurs = l.genre { return "voulu=\(l.voulu) vu=\(l.vu)" } else { return nil }
        }
        #expect(vus == Set(reperes.map(\.enfant)), "tous les reperes, un par enfant : \(etats) ; s=\(m.s) focus=\(String(describing: m.focus))")
        #expect(m.projetee?.fils.count == reperes.count, "et un fil chacun")
    }

    /// Un noeud de la piece qui a un lien vers ailleurs : seul son repere reste (et son fil) ; la deselection les rend tous.
    @Test func selectionAvecUnLienAilleurs() throws {
        let (m, _, _, reperes) = try Self.pieceIsolee()
        let a = try #require(reperes.first)
        m.selection = a.enfant
        #expect(Self.vus(m) == [a.enfant], "seulement le repere du noeud selectionne")
        #expect(m.projetee?.fils.count == 1, "et son fil seul")
        m.selection = nil
        #expect(Self.vus(m) == Set(reperes.map(\.enfant)), "la deselection les rend tous")
        #expect(m.projetee?.fils.count == reperes.count)
    }

    /// Un noeud de la piece sans lien vers ailleurs : aucun repere, aucun fil.
    @Test func selectionSansLienAilleurs() throws {
        let (m, e, piece, reperes) = try Self.pieceIsolee()
        let ailleurs = Set(reperes.map(\.enfant))
        let sans = try #require(e.scene.pieces[piece].noeuds.first { !ailleurs.contains($0) }, "un noeud de la piece sans repere")
        m.selection = sans
        #expect(Self.vus(m).isEmpty, "aucun repere")
        #expect(m.projetee?.fils.isEmpty == true, "aucun fil")
        m.selection = nil
        #expect(Self.vus(m) == ailleurs)
    }

    /// Dans l'autre sens : le parent d'un repere (dans une autre piece), selectionne, garde le repere de son enfant, et seuls
    /// ceux des enfants qu'il a dans la piece isolee.
    @Test func selectionDuParentAilleurs() throws {
        let (m, _, _, reperes) = try Self.pieceIsolee()
        let a = try #require(reperes.first)
        m.selection = a.parent
        let attendus = Set(reperes.filter { $0.parent == a.parent }.map(\.enfant))
        #expect(attendus.contains(a.enfant))
        #expect(Self.vus(m) == attendus, "les reperes dont le parent est le noeud selectionne")
    }

    /// Une piece qu'on isole sous une selection : les reperes suivent la selection des l'isolement.
    @Test func isolerSousUneSelection() throws {
        let e = EntreeScene(surveillance: DemoCombineeTests.combinee(), places: PlacesGardees())
        let m = MoteurPiecesTests.moteur(e)
        m.poserZoom(echelle: 1, vers: nil)
        let piece = try #require(e.scene.pieces.indices.first { SceneProjetee.reperes(e.scene, focus: $0).count >= 2 })
        let reperes = SceneProjetee.reperes(e.scene, focus: piece)
        let a = try #require(reperes.first)
        m.selection = a.enfant
        Self.isoler(m, piece)
        #expect(Self.vus(m) == [a.enfant])
    }

    /// L'effacement va en douceur, avec le pas du mode focus : l'horloge continue tant qu'il est en route, le repere est
    /// a moitie efface en route (son nom et son fil encore la), puis efface (ni ancre, ni nom), et la deselection le rend.
    @Test func effacementEnDouceur() throws {
        let (m, _, _, reperes) = try Self.pieceIsolee()
        m.fige = false
        let a = try #require(reperes.first), autre = try #require(reperes.last)
        #expect(a.enfant != autre.enfant)
        m.selection = a.enfant
        #expect(m.focusEnRoute && m.doitContinuer(MoteurPieces.maintenant()))
        #expect(m.ciblesAilleurs == [autre.enfant: 1] || m.ciblesAilleurs[a.enfant] == nil)
        let k = 0.05 * MoteurPieces.vitesseFocus
        m.ailleursEstompes = MiseEnAvant.tendre(m.ailleursEstompes, vers: m.ciblesAilleurs, k: k)
        let mi = try #require(m.ailleursEstompes[autre.enfant])
        #expect(mi > 0 && mi < 1 && m.ailleursEstompes[a.enfant] == nil, "en route : \(mi)")
        for _ in 0..<80 {
            m.ailleursEstompes = MiseEnAvant.tendre(m.ailleursEstompes, vers: m.ciblesAilleurs, k: k)
            m.noeudsEstompes = MiseEnAvant.tendre(m.noeudsEstompes, vers: m.ciblesFocus.noeuds, k: k)
            m.liensEstompes = MiseEnAvant.tendre(m.liensEstompes, vers: m.ciblesFocus.liens, k: k)
        }
        #expect(!m.focusEnRoute && m.ailleursEstompes[autre.enfant] == 1, "arrive, efface")
        m.fige = true
        #expect(Self.vus(m) == [a.enfant])
        m.selection = nil
        #expect(m.ciblesAilleurs.isEmpty && m.ailleursEstompes.isEmpty, "figee, la deselection les rend tout de suite")
        #expect(Self.vus(m) == Set(reperes.map(\.enfant)))
    }

    /// Le signe « parent dans une autre piece » de la legende suit les reperes qui restent : un noeud sans lien vers ailleurs
    /// selectionne, il n'y en a plus, et la legende n'en montre plus le signe.
    @Test func legendeSuitLesReperes() throws {
        let (m, e, piece, reperes) = try Self.pieceIsolee()
        #expect(m.aDesReperesAilleurs)
        m.selection = reperes[0].enfant
        #expect(m.aDesReperesAilleurs, "le repere du noeud selectionne reste")
        let ailleurs = Set(reperes.map(\.enfant))
        let sans = try #require(e.scene.pieces[piece].noeuds.first { !ailleurs.contains($0) }, "un noeud sans repere")
        m.selection = sans
        #expect(!m.aDesReperesAilleurs, "plus de repere")
        m.selection = nil
        #expect(m.aDesReperesAilleurs)
    }
}
