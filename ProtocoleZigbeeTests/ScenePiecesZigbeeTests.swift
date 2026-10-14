import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Le classement des noeuds de Zigbee dans la scene par pieces (`ScenePieces.classementZigbee`), sur le petit reseau
/// de `ScenePiecesZigbee.grapheZigbee`. Le reste de la scene est generique et teste au coeur (`ScenePiecesTests`).
@Suite("Scene Zigbee : rang, rayon et lignes d'une carte")
struct ScenePiecesZigbeeTests {
    static let libelles = ["Apple TV": "Apple TV 👑", "HomePod": "HomePod", "E000000000000002": "Lampe salon",
                           "E000000000000003": "Capteur", "E000000000000004": "Prise", "E000000000000005": "Bouton"]

    static func piece(_ s: ScenePieces, _ nom: ScenePieces.NomPiece) throws -> ScenePieces.Piece {
        try #require(s.pieces.first { $0.nom == nom })
    }

    /// « Le noeud route » (polissage D, section 2) s'ecrit d'une seule facon, `Noeud.route` : le coordinateur ou un
    /// routeur, jamais un autre noeud ; il suit le graphe et le rang de la carte (1 ou 2). La cle de la disposition en
    /// tire son « R ».
    @Test func leNoeudRoute() throws {
        let g = try ScenePiecesZigbee.grapheZigbee(sonde: true)
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: Dictionary(uniqueKeysWithValues: g.noeuds.map {
            ($0.id, "Salon")
        }), zones: nil, chefs: [], piecesMaison: true, classement: ScenePieces.classementZigbee)
        #expect(Set(s.noeuds.map(\.rang)) == [1, 2, 3], "des noeuds de chaque rang")
        let cles = try #require(s.cleDisposition.pieces["maison"]?["piece:Salon"])
        for n in s.noeuds {
            #expect(!n.bordure && n.route == n.routeur, "\(n.id) : le graphe")
            #expect(n.route == (n.rang == 1 || n.rang == 2), "\(n.id) : le rang")
            let cle = try #require(cles.first { $0.hasPrefix(n.id + "|") }).split(separator: "|", omittingEmptySubsequences: false)
            #expect(cle[2] == (n.route ? "R" : ""), "\(n.id) : la cle")
        }
    }

    /// Lignes d'une carte : le coordinateur, les routeurs, puis les appareils finaux, par nom ; la couronne ne change pas
    /// de groupe (polissage D, section 2) ; rayons 15 (coordinateur), 8 (routeur) et 7.
    @Test func lignesEtRayons() throws {
        let g = try ScenePiecesZigbee.grapheZigbee(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: ["HomePod"],
                            piecesMaison: true, classement: ScenePieces.classementZigbee)
        #expect(try Self.piece(s, .maison("Salon")).noeuds
                == ["Apple TV", "HomePod", "E000000000000004", "E000000000000005", "E000000000000003", "E000000000000002"])
        #expect(s.noeud("HomePod")?.rang == 2 && s.noeud("HomePod")?.rayon == 8 && s.noeud("HomePod")?.chef == true)
        #expect(s.noeud("Apple TV")?.rang == 1 && s.noeud("Apple TV")?.rayon == 15)
        #expect(s.noeud("E000000000000004")?.rang == 2 && s.noeud("E000000000000004")?.rayon == 8)
        #expect(s.noeud("E000000000000002")?.rang == 3 && s.noeud("E000000000000002")?.rayon == 7)
        #expect(s.noeud("E000000000000002")?.libelle == "Lampe salon")
        #expect(s.liens == g.liens)
    }

    /// Une regle fondee sur les routeurs de bordure (celle de Thread, copiee ici : un module ne depend pas de l'autre)
    /// donne le rang 2 au pont, qui n'est pas un routeur de bordure, au lieu du rang 1 : c'est pourquoi Zigbee passe la
    /// sienne. Les autres rangs sont les memes.
    @Test func laReglePourZigbeeDiffereDeCelleDesBordures() throws {
        let g = try ScenePiecesZigbee.grapheZigbee(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        let parBordure = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: [],
                                     piecesMaison: true, classement: { n in
            (n.bordure ? 1 : n.routeur ? 2 : 3, n.genre == .centre ? 15 : n.bordure ? 13 : n.routeur ? 8 : 7)
        })
        let zigbee = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: [],
                                 piecesMaison: true, classement: ScenePieces.classementZigbee)
        #expect(parBordure.noeud("Apple TV")?.rang == 2 && zigbee.noeud("Apple TV")?.rang == 1)
        for id in ["HomePod", "E000000000000004", "E000000000000002"] {
            #expect(parBordure.noeud(id)?.rang == zigbee.noeud(id)?.rang, "\(id)")
        }
    }
}
