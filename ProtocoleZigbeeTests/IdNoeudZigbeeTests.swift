import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Les identifiants de noeud de Zigbee (etape 3a, conception B) : le graphe emballe ses adresses longues (ou cles
/// provisoires `~XXXX`) en `IdNoeud` Zigbee, la partition reste l'etiquette `zigbee`, et les crochets de fiche et de
/// focus ne regardent que les noeuds Zigbee, par leur cle.
@Suite("Zigbee : identifiants de noeud types")
struct IdNoeudZigbeeTests {
    typealias I = NomsDemo.Ieee

    /// La demo : tout noeud et tout bout de lien est un `IdNoeud` Zigbee ; la partition n'est pas prefixee (`zigbee`, pas
    /// `zigbee:zigbee`) ; la cle est l'adresse longue telle quelle.
    @Test func toutEstZigbee() {
        let m = MaillageDemoZigbee.maillage
        let g = GrapheReseau(maillage: m, appareils: GrapheReseauZigbeeTests.affiches(m))
        #expect(g.noeuds.allSatisfy { $0.id.protocole == .zigbee && !$0.id.cle.hasPrefix("zigbee:") })
        #expect(g.liens.allSatisfy { $0.de.protocole == .zigbee && $0.vers.protocole == .zigbee })
        #expect(g.noeuds.allSatisfy { $0.partition == "zigbee" })
        #expect(g.noeud(idz(I.pont))?.id.cle == I.pont)
        #expect(g.noeud(idt(I.pont)) == nil, "le meme texte sous Thread n'est pas ce noeud")
    }

    /// Un noeud sans adresse longue garde sa cle provisoire `~XXXX` comme cle : le `:` du texte vient apres le protocole.
    @Test func cleProvisoire() {
        let n = GrapheReseau.Noeud(zigbee: "~4F2A", genre: .appareil, routeur: false, inconnu: true)
        #expect(n.id == idz("~4F2A") && n.id.texte == "zigbee:~4F2A" && n.extMac == nil)
        #expect(IdNoeud(texte: n.id.texte) == n.id)
    }

    /// Le focus et la fiche de Zigbee ne voient pas un noeud Thread, meme de meme cle.
    @Test func focusEtFicheIgnorentUnAutreProtocole() throws {
        let m = MaillageDemoZigbee.maillage
        let g = GrapheReseau(maillage: m, appareils: [])
        #expect(FocusZigbee.miseEnAvant(de: idt(I.lampeChambre), graphe: g, voisins: true) == nil)
        #expect(FocusZigbee.dependants(de: idt(I.lampeChambre), graphe: g).isEmpty, "aucun lien ne vise un noeud Thread")
        #expect(FicheZigbee.voisins(de: idt(I.lampeChambre), maillage: m).isEmpty)
        #expect(FicheZigbee.dependants(de: idt(I.lampeChambre), maillage: m).isEmpty)
        let v = FicheZigbee.voisins(de: idz(I.lampeChambre), maillage: m)
        #expect(!v.isEmpty && v.allSatisfy { $0.id.protocole == .zigbee })
        let d = FicheZigbee.dependants(de: idz(I.lampeChambre), maillage: m)
        #expect(!d.isEmpty && d.allSatisfy { $0.id.protocole == .zigbee })
        // Deux noeuds de meme cle, un par protocole : le focus Zigbee n'embarque pas le noeud Thread.
        let t = GrapheReseau.Noeud(id: idt(I.lampeChambre), genre: .appareil, partition: "p", routeur: false, bordure: false,
                                   inconnu: false)
        let deux = GrapheReseau(noeuds: g.noeuds + [t], liens: g.liens)
        let avec = try #require(FocusZigbee.miseEnAvant(de: idz(I.lampeChambre), graphe: deux, voisins: true))
        #expect(avec.noeuds.allSatisfy { $0.protocole == .zigbee })
    }
}
