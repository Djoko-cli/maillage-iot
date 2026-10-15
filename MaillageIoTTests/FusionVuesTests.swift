import Foundation
import MaillageCoeur
import ProtocoleZigbee
import SwiftUI
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 7 : les fichiers de vue que Thread et Zigbee partagent portent les crochets des deux protocoles, sans
/// rien changer a Thread (la scene reunie vient a la tache 8, les tests de l'ancienne app de transition a la tache 9). Ces tests posent ce
/// que les fusions ajoutent : la part de Zigbee des libelles et des pieces, l'apparence et la couleur des liens par
/// protocole, la legende des deux protocoles, les reglages par defaut du moteur.
@MainActor
@Suite("Vues communes : les crochets de Zigbee")
struct FusionVuesTests {
    typealias Entree = LegendePieces.Entree
    typealias Lecture = LegendePieces.Lecture

    /// La scene de la demo de Zigbee, bâtie comme `EntreeScene` le fera (tache 8), par les fonctions de Zigbee.
    static func sceneZigbee() throws -> (scene: ScenePieces, surveillance: Surveillance, libelles: [IdNoeud: LibellesNoeuds.Libelle]) {
        let s = SurveillanceZigbeeTests.demoZigbee()
        let g = s.zigbee.graphe
        let affiches = s.zigbee.appareilsAffiches
        let parId = Dictionary(affiches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let chefs = LibellesNoeuds.chefs(g)
        let libelles = LibellesNoeuds.libelles(graphe: g, appareils: parId, nom: s.zigbee.nom, chefs: chefs)
        let maison = s.zigbee.noms.maison
        let pieces = LibellesNoeuds.pieces(appareils: affiches, maison: maison, graphe: g)
        let scene = ScenePieces(graphe: g, libelles: libelles.mapValues(\.nom), piecesNoeuds: pieces, zones: maison?.zones,
                                chefs: chefs, piecesMaison: maison?.accessoires.contains { $0.piece?.isEmpty == false } == true,
                                classement: s.zigbee.classement)
        return (scene, s, libelles)
    }

    /// La part de Zigbee des libelles : le coordinateur est couronne, un appareil disparu porte l'alerte, un routeur a son
    /// nom du pont ; les pieces viennent du pont.
    @Test func libellesEtPiecesDeZigbee() throws {
        let (scene, s, libelles) = try Self.sceneZigbee()
        let chefs = LibellesNoeuds.chefs(s.zigbee.graphe)
        #expect(chefs.count == 1 && chefs.allSatisfy { $0.protocole == .zigbee })
        #expect(scene.noeuds.allSatisfy { $0.id.protocole == .zigbee })
        let chef = try #require(chefs.first)
        #expect(libelles[chef]?.texte.contains(LibellesNoeuds.couronne) == true)
        let prise = IdNoeud(.zigbee, NomsDemo.Ieee.priseSalon)
        #expect(libelles[prise]?.nom == "Prise salon" && libelles[prise]?.texte.contains(CartesPieces.alerte) == true, "disparue : l'alerte")
        let lampe = IdNoeud(.zigbee, NomsDemo.Ieee.lampeBureau)
        #expect(scene.noeud(lampe).map { scene.pieces[$0.piece].nom } == .maison("Bureau"), "la piece que donne le pont")
        // Un graphe Thread n'a pas de coordinateur Zigbee.
        #expect(LibellesNoeuds.chefs(SurveillanceTests.demo().thread.graphe).isEmpty)
    }

    /// Les pieces du pont : celles de ses appareils et de ses zones, sans doublon ni vide, triees.
    @Test func piecesDuPont() {
        let s = SurveillanceZigbeeTests.demoZigbee()
        let pieces = PiecesRouteurs.pieces(de: s.zigbee.noms.maison)
        #expect(!pieces.isEmpty && pieces == pieces.sorted() && Set(pieces).count == pieces.count && !pieces.contains(""))
        #expect(PiecesRouteurs.pieces(de: nil as NomsZigbee?).isEmpty)
    }

    /// L'apparence d'un noeud Zigbee : ses routeurs ont toujours la couleur de la partition principale (Zigbee n'en a
    /// qu'une), ses appareils n'ont ni cercle ni anneau, meme s'ils routent ; un noeud Thread garde ses ornements.
    @Test func apparenceSelonLeProtocole() throws {
        let (scene, _, _) = try Self.sceneZigbee()
        for n in scene.noeuds {
            let sans = DessinNoeud.apparence(n, etat: .joignable, principale: true)
            let autre = DessinNoeud.apparence(n, etat: .joignable, principale: false, verifie: true)
            #expect(sans == autre, "Zigbee : ni partition, ni verification")
            #expect(!sans.cercle && !sans.verifie)
            #expect(sans.contour == .hexagone, "Zigbee : l'hexagone")
            if n.genre != .appareil { #expect(sans.couleur == .routeurZigbee || sans.couleur == .routeurInconnu) }
        }
        let thread = SurveillanceTests.demo().thread
        let g = thread.graphe
        let libelles = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, $0.id.cle) })
        let st = ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: [:], zones: nil, chefs: [], piecesMaison: false,
                             classement: thread.classement)
        let routeur = try #require(st.noeuds.first { $0.genre == .routeur })
        #expect(DessinNoeud.apparence(routeur, etat: nil, principale: false).couleur == .routeur(principale: false),
                "Thread : la partition compte")
        #expect(st.noeuds.allSatisfy { DessinNoeud.apparence($0, etat: .joignable, principale: true).contour == .rond },
                "Thread : le rond")
    }

    /// La qualite d'un lien : le 0 de Zigbee (un LQI sous 50) est un lien faible, orange ; celui de Thread reste « pas de
    /// lien », gris. Les autres valeurs sont les memes.
    @Test func qualiteDUnLienSelonLeProtocole() {
        let p = Palette(sombre: true)
        #expect(p.lienSonde(0, protocole: .zigbee) == p.lienSonde(1, protocole: .zigbee))
        #expect(p.lienSonde(0, protocole: .zigbee) == p.lienSonde(1))
        #expect(p.lienSonde(0) == p.lienSonde(nil) && p.lienSonde(0) != p.lienSonde(1), "Thread : 0 est inconnu")
        for q in [1, 2, 3, nil] as [Int?] { #expect(p.lienSonde(q) == p.lienSonde(q, protocole: .zigbee)) }
        #expect(Palette.qualiteAffichee(0, protocole: .zigbee) == 1 && Palette.qualiteAffichee(0, protocole: .thread) == 0)
        // La bande lue par la scene et la legende : le 0 de Thread reste inconnu (gris), celui de Zigbee est faible ;
        // la fiche lit le 0 « faible » pour les deux (`BandeQualite.init`) : l'ecart est voulu, il n'est que la.
        #expect(Palette.bande(0, protocole: .thread) == .inconnue && BandeQualite(0) == .faible)
        #expect(Palette.bande(0, protocole: .zigbee) == .faible)
        for q in [1, 2, 3, nil] as [Int?] {
            #expect(Palette.bande(q, protocole: .thread) == BandeQualite(q) && Palette.bande(q, protocole: .zigbee) == BandeQualite(q))
        }
        for protocole in [Protocole.thread, .zigbee] {
            for q in [0, 1, 2, 3, nil] as [Int?] {
                #expect(p.lienSonde(q, protocole: protocole) == p.couleur(Palette.bande(q, protocole: protocole)), "\(protocole) \(String(describing: q))")
            }
        }
    }

    /// La legende des deux protocoles : les entrees communes et celles de chacun, lues d'apres le protocole de chaque noeud
    /// et de chaque lien ; Zigbee garde ses chemins, ses voisins entendus et son parent d'avant, Thread son chef et ses
    /// partitions. Aucune entree propre a un protocole sans noeud de ce protocole.
    @Test func legendeDesDeuxProtocoles() {
        func radio(_ p: Protocole, _ q: Int?) -> ScenePieces.Lien {
            ScenePieces.Lien(de: IdNoeud(p, "A"), vers: IdNoeud(p, "B"), genre: .radio, qualite: q)
        }
        let t = idt("T1"), z = idz("Z1")
        // Les memes etats se lisent par protocole.
        let etats = Lecture(couleurs: [t: .routeur(principale: true), z: .routeurZigbee,
                                       idt("T2"): .appareil(.sansAdresse), idz("Z2"): .appareil(.injoignable),
                                       idt("T3"): .appareil(.injoignable)],
                            inconnus: [idt("T4"), idz("Z4")], chefs: [t, z])
        #expect(LegendePieces.entrees(etats) == [.routeur, .routeurZigbee, .sansAdresse, .injoignable,
                                                 .nonIdentifie, .nonIdentifieZigbee, .chef, .coordinateur])
        #expect(LegendePieces.entrees(Lecture(couleurs: [idz("Z5"): .appareil(.partitionCoupee)])) == [.injoignable],
                "un etat de Thread sur un noeud Zigbee : comme injoignable")
        // Les liens : le 0 de Zigbee est faible, celui de Thread inconnu ; un chemin et un voisin n'existent que chez Zigbee.
        #expect(LegendePieces.entrees(Lecture(liens: [radio(.zigbee, 0)])) == [.faible])
        #expect(LegendePieces.entrees(Lecture(liens: [radio(.thread, 0)])) == [.inconnue])
        let chemin = ScenePieces.Lien(de: idz("Z1"), vers: idz("Z0"), genre: .chemin, qualite: 3)
        #expect(LegendePieces.entrees(Lecture(liens: [chemin], mode: .chemins)) == [.chemin, .bonne])
        #expect(LegendePieces.entrees(Lecture(liens: [chemin], mode: .tous)).isEmpty, "un chemin ne se montre qu'en mode chemins")
        #expect(LegendePieces.entrees(Lecture(liens: [radio(.zigbee, 2)], mode: .chemins)) == [.voisinEntendu, .moyenne])
        #expect(LegendePieces.entrees(Lecture(liens: [radio(.zigbee, 2)], mode: .chemins, voisins: false)).isEmpty)
        #expect(LegendePieces.entrees(Lecture(liens: [radio(.thread, 2)], mode: .chemins)) == [.moyenne],
                "le mode des liens est celui de Zigbee : Thread montre ses liens radio quel que soit le mode")
        let davant = ScenePieces.Lien(de: idz("Z2"), vers: idz("Z1"), genre: .parent, suppose: true)
        let parent = ScenePieces.Lien(de: idt("T2"), vers: idt("T1"), genre: .parent)
        let rattachement = ScenePieces.Lien(de: idt("T3"), vers: idt("T1"), genre: .rattachement)
        #expect(LegendePieces.entrees(Lecture(liens: [davant, parent, rattachement])) == [.parentDAvant, .versParent, .rattachement])
        // Les groupes gardent l'ordre de chaque legende : Zigbee seul, puis Thread seul.
        let zigbee = Lecture(couleurs: [z: .routeurZigbee], chefs: [z],
                             liens: [chemin, davant, ScenePieces.Lien(de: z, vers: idz("Z9"), genre: .parent)], mode: .chemins)
        #expect(LegendePieces.rubriques(zigbee).map(\.entrees)
                == [[Entree.routeurZigbee, .coordinateur], [.bonne], [.chemin, .versParent, .parentDAvant]])
        let thread = Lecture(couleurs: [t: .routeur(principale: true)], chefs: [t], liens: [parent, rattachement])
        #expect(LegendePieces.rubriques(thread).map(\.entrees) == [[Entree.routeur, .chef], [.versParent, .rattachement]])
    }

    /// Le moteur : tous les liens radio par defaut (Thread n'a pas de chemin vers un pont), les voisins montres ; les liens
    /// et les voisins sont des reglages du moteur, que la scene reunie lira (tache 8).
    @Test func moteurLiensParDefaut() {
        let m = MoteurPieces()
        #expect(m.liens == .tous && m.voisins)
        let z = MoteurPieces(liens: .chemins, voisins: false)
        #expect(z.liens == .chemins && !z.voisins)
        #expect(FenetrePieces.modeLiens(nil) == .chemins && FenetrePieces.modeLiens("tous") == .tous
                && FenetrePieces.modeLiens("autre") == .chemins)
        #expect(FenetrePieces.voisinsMontres(nil) && !FenetrePieces.voisinsMontres(false) && FenetrePieces.voisinsMontres("x"))
        #expect(FenetrePieces.cleLiens == "zigbee.liensMontres" && FenetrePieces.cleVoisins == "zigbee.voisinsALaSelection")
    }
}
