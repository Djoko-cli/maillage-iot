import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Resultat de reference du rejeu (spec de Maillage IoT, section 6.1, etape 0) : la scene de la vue par pieces en
/// mode demo, telle que `EntreeScene` la construit, ecrite en JSON trie dans `docs/rejeu/thread-demo.json`. Maillage
/// IoT rejoue la meme demo et compare, prefixes `thread:` retires. Fichier absent : le test l'ecrit dans son dossier
/// temporaire (bac a sable) et echoue une fois ; le copier, le controler (controle d'anonymisation), puis relancer.
@MainActor
@Suite("Reference du rejeu : la scene de la demo")
struct ReferenceRejeuTests {
    static let fichier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageIoTTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/rejeu/thread-demo.json")

    struct Reference: Codable, Equatable {
        struct Noeud: Codable, Equatable {
            var id, genre, partition: String
            var routeur, bordure, inconnu: Bool
            var extMac: String?
        }
        struct Lien: Codable, Equatable {
            var de, vers, genre: String
            var qualite: Int?
        }
        struct NoeudScene: Codable, Equatable {
            var id, libelle, piece: String
            var chef, pile: Bool
            var rang: Int
            var rayon: Double
        }
        struct Piece: Codable, Equatable {
            var cle, etage: String
            var noeuds: [String]
        }
        struct Etage: Codable, Equatable {
            var cle: String
            var niveau: Int
            var principal, dehors: Bool
        }
        var noeuds: [Noeud]
        var liens: [Lien]
        var scene: [NoeudScene]
        var pieces: [Piece]
        var etages: [Etage]
    }

    static func reference() throws -> Reference {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.reseau)
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let sc = e.scene
        let pieces = sc.pieces.map(\.nom.cle)
        let etages = sc.etages.map(\.nom.cle)
        return Reference(
            noeuds: e.graphe.noeuds.map {
                .init(id: $0.id, genre: $0.genre.rawValue, partition: $0.partition, routeur: $0.routeur,
                      bordure: $0.bordure, inconnu: $0.inconnu, extMac: $0.extMac)
            }.sorted { $0.id < $1.id },
            liens: e.graphe.liens.map {
                .init(de: $0.de, vers: $0.vers, genre: $0.genre.rawValue, qualite: $0.qualite)
            }.sorted { ($0.de, $0.vers, $0.genre) < ($1.de, $1.vers, $1.genre) },
            scene: sc.noeuds.map {
                .init(id: $0.id, libelle: $0.libelle,
                      piece: pieces.indices.contains($0.piece) ? pieces[$0.piece] : "",
                      chef: $0.chef, pile: $0.pile, rang: $0.rang, rayon: ($0.rayon * 10_000).rounded() / 10_000)
            }.sorted { $0.id < $1.id },
            pieces: sc.pieces.map {
                .init(cle: $0.nom.cle, etage: etages.indices.contains($0.etage) ? etages[$0.etage] : "",
                      noeuds: $0.noeuds.sorted())
            }.sorted { $0.cle < $1.cle },
            etages: sc.etages.map {
                .init(cle: $0.nom.cle, niveau: $0.niveau, principal: $0.principal, dehors: $0.dehors)
            }.sorted { $0.cle < $1.cle })
    }

    static func json(_ r: Reference) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(r) + Data("\n".utf8)
    }

    /// Deux constructions de suite donnent le meme JSON : la reference ne depend ni de l'heure ni d'un ordre de hasard.
    @Test func stable() throws {
        #expect(try Self.json(Self.reference()) == Self.json(Self.reference()))
    }

    @Test func egaleALaReference() throws {
        let calcule = try Self.json(Self.reference())
        guard let garde = try? Data(contentsOf: Self.fichier) else {
            // L'app hote est en bac a sable : elle lit le depot mais n'y ecrit pas. La reference part dans son
            // dossier temporaire, a copier dans docs/rejeu/ a la main.
            let ecrite = FileManager.default.temporaryDirectory.appendingPathComponent("thread-demo.json")
            try calcule.write(to: ecrite)
            Issue.record("reference absente : ecrite dans \(ecrite.path) ; la copier dans docs/rejeu/, puis relancer")
            return
        }
        #expect(calcule == garde, "la scene de la demo a change : comparer avec docs/rejeu/thread-demo.json")
    }
}
