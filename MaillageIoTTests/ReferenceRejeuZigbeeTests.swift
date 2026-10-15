import Foundation
import MaillageCoeur
import Testing
import ProtocoleZigbee
@testable import MaillageIoT

/// Resultat de reference du rejeu de Zigbee (spec de Maillage IoT, section 6.1, etape 0) : la scene de la vue par pieces
/// en mode demo, telle que `EntreeScene` la construit, ecrite en JSON trie dans `docs/rejeu/zigbee-demo.json`. Dans
/// l'app unique, la demo de Zigbee tourne seule (`Surveillance(demo: .zigbee)` : Thread est muet) et la scene reunie
/// n'a que ses noeuds : elle doit redonner la reference de l'ancienne app de transition (celle de Zigbee 1.1.1), a l'octet. Les identifiants sont compares
/// par leur cle (`IdNoeud.cle`), sans le protocole ; le fichier de reference ne change jamais. La demo ne lit pas
/// l'horloge du Mac (dates fixes de `MaillageDemoZigbee`, `Surveillance.maintenant` = la fin de la demo). Fichier
/// absent : le test l'ecrit dans son dossier temporaire (bac a sable) et echoue une fois ; le copier, le controler
/// (controle d'anonymisation), puis relancer.
@MainActor
@Suite("Reference du rejeu de Zigbee : la scene de la demo")
struct ReferenceRejeuZigbeeTests {
    static let fichier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageIoTTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/rejeu/zigbee-demo.json")

    struct Reference: Codable, Equatable {
        struct Noeud: Codable, Equatable {
            var id, genre, partition: String
            var routeur, bordure, inconnu, sonde: Bool
            var extMac: String?
            /// Etat affiche de l'appareil du pont (nil : noeud sans appareil du pont) et sommeil.
            var etat: String?
            var endormi: Bool
        }
        struct Lien: Codable, Equatable {
            var de, vers, genre: String
            /// Qualite du lien (LQI), de 0 a 3 ; nil : inconnue.
            var qualite: Int?
            var suppose: Bool
        }
        struct NoeudScene: Codable, Equatable {
            var id, libelle, genre, piece: String
            var chef, pile: Bool
            var rang: Int
            var rayon: Double
        }
        struct Piece: Codable, Equatable {
            var cle, etage: String
            var teinte: Int
            var noeuds: [String]
        }
        struct Etage: Codable, Equatable {
            var cle: String
            var niveau: Int
            var principal, dehors: Bool
        }
        var domicile: String
        var noeuds: [Noeud]
        var liens: [Lien]
        var scene: [NoeudScene]
        var pieces: [Piece]
        var etages: [Etage]
    }

    static func reference() throws -> Reference {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .zigbee)
        s.demarrer()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let sc = e.scene
        let pieces = sc.pieces.map(\.nom.cle)
        let etages = sc.etages.map(\.nom.cle)
        // Les identifiants sont ecrits par leur cle : la reference ne porte pas le protocole.
        let noeuds: [Reference.Noeud] = e.graphe.noeuds.map {
            .init(id: $0.id.cle, genre: $0.genre.rawValue, partition: $0.partition, routeur: $0.routeur,
                  bordure: $0.bordure, inconnu: $0.inconnu, sonde: $0.id.cle == e.maillageZigbee?.sonde, extMac: $0.extMac,
                  etat: e.appareils[$0.id]?.etat.rawValue, endormi: e.appareils[$0.id]?.endormi ?? false)
        }.sorted { $0.id < $1.id }
        let liens: [Reference.Lien] = e.graphe.liens.map {
            .init(de: $0.de.cle, vers: $0.vers.cle, genre: $0.genre.rawValue, qualite: $0.qualite, suppose: $0.suppose)
        }.sorted { ($0.de, $0.vers, $0.genre) < ($1.de, $1.vers, $1.genre) }
        let scene: [Reference.NoeudScene] = sc.noeuds.map {
            .init(id: $0.id.cle, libelle: $0.libelle, genre: $0.genre.rawValue,
                  piece: pieces.indices.contains($0.piece) ? pieces[$0.piece] : "",
                  chef: $0.chef, pile: $0.pile, rang: $0.rang, rayon: ($0.rayon * 10_000).rounded() / 10_000)
        }.sorted { $0.id < $1.id }
        let cartes: [Reference.Piece] = sc.pieces.map {
            .init(cle: $0.nom.cle, etage: etages.indices.contains($0.etage) ? etages[$0.etage] : "",
                  teinte: $0.teinte, noeuds: $0.noeuds.map(\.cle).sorted())
        }.sorted { $0.cle < $1.cle }
        let plateaux: [Reference.Etage] = sc.etages.map {
            .init(cle: $0.nom.cle, niveau: $0.niveau, principal: $0.principal, dehors: $0.dehors)
        }.sorted { $0.cle < $1.cle }
        return Reference(domicile: e.domicile, noeuds: noeuds, liens: liens, scene: scene, pieces: cartes, etages: plateaux)
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
            let ecrite = FileManager.default.temporaryDirectory.appendingPathComponent("zigbee-demo.json")
            try calcule.write(to: ecrite)
            Issue.record("reference absente : ecrite dans \(ecrite.path) ; la copier dans docs/rejeu/, puis relancer")
            return
        }
        #expect(calcule == garde, "la scene de la demo a change : comparer avec docs/rejeu/zigbee-demo.json")
    }
}
