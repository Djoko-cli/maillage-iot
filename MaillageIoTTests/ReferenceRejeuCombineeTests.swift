import Foundation
import MaillageCoeur
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Resultat de reference du rejeu de la demo combinee (spec de Maillage IoT, sections 3.6 et 6.7) : la scene de la vue par
/// pieces quand la demo de Thread et celle de Zigbee tournent ensemble (`-demo`, `Surveillance(demo: .combinee)`), telle que
/// `EntreeScene` la construit, ecrite en JSON trie dans `docs/rejeu/maillage-iot-demo.json`. Les identifiants y sont en forme
/// texte (`thread:<cle>`, `zigbee:<cle>`) : les deux protocoles s'y melangent, la cle seule ne les distingue plus. Les deux
/// references d'un protocole seul (`thread-demo.json`, `zigbee-demo.json`, `-demo-thread` et `-demo-zigbee`) restent intactes ;
/// celle-ci a la sienne, ecrite une seule fois puis jamais regeneree. Fichier absent : le test l'ecrit dans son dossier
/// temporaire (bac a sable) et echoue une fois ; le copier, le controler (controle d'anonymisation), puis relancer.
///
/// Ce que la combinee change des deux demos seules : la demo de Zigbee est recalee sur l'horloge de celle de Thread (sa fin est
/// celle de la panne rejouee) et ses appareils qui portent le nom d'un appareil de Thread sont renommes (« Lampe arcade
/// (Hue) ») ; le reste de la scene est la leur, noeud par noeud.
@MainActor
@Suite("Reference du rejeu de la demo combinee : la scene de Maillage IoT")
struct ReferenceRejeuCombineeTests {
    static let fichier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageIoTTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/rejeu/maillage-iot-demo.json")

    struct Reference: Codable, Equatable {
        struct Noeud: Codable, Equatable {
            var id, genre, partition: String
            var routeur, bordure, inconnu, sonde: Bool
            var extMac: String?
            /// Etat affiche de l'appareil (nil : noeud sans appareil affiche) et sommeil.
            var etat: String?
            var endormi: Bool
        }
        struct Lien: Codable, Equatable {
            var de, vers, genre: String
            /// Qualite du lien, de 0 a 3 ; nil : inconnue.
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

    /// La demo combinee, demarree, et sa scene sur des places vides (comme les deux autres references).
    static func combinee() -> (Surveillance, EntreeScene) {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
        s.demarrer()
        return (s, EntreeScene(surveillance: s, places: PlacesGardees()))
    }

    static func reference() throws -> Reference {
        let (_, e) = combinee()
        let sc = e.scene
        let pieces = sc.pieces.map(\.nom.cle)
        let etages = sc.etages.map(\.nom.cle)
        // Les identifiants sont ecrits en forme texte, avec leur protocole.
        func sonde(_ id: IdNoeud) -> Bool {
            id.cle == (id.protocole == .thread ? e.maillageThread?.sonde : e.maillageZigbee?.sonde)
        }
        let noeuds: [Reference.Noeud] = e.graphe.noeuds.map {
            .init(id: $0.id.texte, genre: $0.genre.rawValue, partition: $0.partition, routeur: $0.routeur,
                  bordure: $0.bordure, inconnu: $0.inconnu, sonde: sonde($0.id), extMac: $0.extMac,
                  etat: e.appareils[$0.id]?.etat.rawValue, endormi: e.appareils[$0.id]?.endormi ?? false)
        }.sorted { $0.id < $1.id }
        let liens: [Reference.Lien] = e.graphe.liens.map {
            .init(de: $0.de.texte, vers: $0.vers.texte, genre: $0.genre.rawValue, qualite: $0.qualite, suppose: $0.suppose)
        }.sorted { ($0.de, $0.vers, $0.genre) < ($1.de, $1.vers, $1.genre) }
        let scene: [Reference.NoeudScene] = sc.noeuds.map {
            .init(id: $0.id.texte, libelle: $0.libelle, genre: $0.genre.rawValue,
                  piece: pieces.indices.contains($0.piece) ? pieces[$0.piece] : "",
                  chef: $0.chef, pile: $0.pile, rang: $0.rang, rayon: ($0.rayon * 10_000).rounded() / 10_000)
        }.sorted { $0.id < $1.id }
        let cartes: [Reference.Piece] = sc.pieces.map {
            .init(cle: $0.nom.cle, etage: etages.indices.contains($0.etage) ? etages[$0.etage] : "",
                  teinte: $0.teinte, noeuds: $0.noeuds.map(\.texte).sorted())
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
            let ecrite = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-iot-demo.json")
            try calcule.write(to: ecrite)
            Issue.record("reference absente : ecrite dans \(ecrite.path) ; la copier dans docs/rejeu/, puis relancer")
            return
        }
        #expect(calcule == ReferenceRejeuTests.dansLaLangueDuTest(garde),
                "la scene de la demo combinee a change : comparer avec docs/rejeu/maillage-iot-demo.json")
    }

    /// Le libelle d'un noeud de Zigbee dans la scene combinee, avant le renommage de ses homonymes de Thread.
    static func libelleDOrigine(_ libelle: String) -> String {
        let suffixe = " " + DemoLancee.suffixeHomonymes
        return libelle.hasSuffix(suffixe) ? String(libelle.dropLast(suffixe.count)) : libelle
    }

    /// La scene combinee est l'union des deux references d'un protocole seul (relues, jamais regenerees) : chaque noeud, chaque
    /// lien, chaque libelle, piece, rang et rayon y est, sous son identifiant prefixe, et elle n'a rien d'autre. Seuls les
    /// libelles des homonymes de Zigbee changent (suffixe), et les pieces sont partagees (les deux protocoles les nomment de
    /// meme).
    @Test func unionDesDeuxReferences() throws {
        // Les references sont relues dans la langue du test (leurs deux libelles du catalogue), comme la scene calculee.
        let thread = try JSONDecoder().decode(
            ReferenceRejeuTests.Reference.self,
            from: ReferenceRejeuTests.dansLaLangueDuTest(Data(contentsOf: ReferenceRejeuTests.fichier)))
        let zigbee = try JSONDecoder().decode(
            ReferenceRejeuZigbeeTests.Reference.self,
            from: ReferenceRejeuTests.dansLaLangueDuTest(Data(contentsOf: ReferenceRejeuZigbeeTests.fichier)))
        let c = try Self.reference()

        // Les lignes de comparaison : des textes, pour des ensembles lisibles.
        func ligne(_ champs: [String]) -> String { champs.joined(separator: "|") }
        func oui(_ b: Bool) -> String { b ? "oui" : "non" }
        func t(_ id: String) -> String { "thread:" + id }
        func z(_ id: String) -> String { "zigbee:" + id }

        // Noeuds : ce que les deux references ont en commun, prefixe.
        var noeudsAttendus = Set<String>()
        for n in thread.noeuds {
            noeudsAttendus.insert(ligne([t(n.id), n.genre, n.partition, oui(n.routeur), oui(n.bordure), oui(n.inconnu), n.extMac ?? "-"]))
        }
        for n in zigbee.noeuds {
            noeudsAttendus.insert(ligne([z(n.id), n.genre, n.partition, oui(n.routeur), oui(n.bordure), oui(n.inconnu), n.extMac ?? "-"]))
        }
        var noeudsC: [String] = []
        for n in c.noeuds {
            noeudsC.append(ligne([n.id, n.genre, n.partition, oui(n.routeur), oui(n.bordure), oui(n.inconnu), n.extMac ?? "-"]))
        }
        #expect(noeudsC.count == thread.noeuds.count + zigbee.noeuds.count)
        #expect(Set(noeudsC) == noeudsAttendus, "les noeuds : l'union des deux references")
        // Ce que seule celle de Zigbee dit de plus (la sonde, l'etat, le sommeil), la combinee le garde pour ses noeuds.
        var detailsAttendus = Set<String>()
        for n in zigbee.noeuds { detailsAttendus.insert(ligne([z(n.id), n.etat ?? "-", oui(n.endormi), oui(n.sonde)])) }
        var detailsC = Set<String>()
        for n in c.noeuds where n.id.hasPrefix("zigbee:") { detailsC.insert(ligne([n.id, n.etat ?? "-", oui(n.endormi), oui(n.sonde)])) }
        #expect(detailsC == detailsAttendus)

        // Liens : de meme (Zigbee ajoute « suppose »).
        func q(_ qualite: Int?) -> String { qualite.map { String($0) } ?? "-" }
        var liensAttendus = Set<String>()
        for l in thread.liens { liensAttendus.insert(ligne([t(l.de), t(l.vers), l.genre, q(l.qualite)])) }
        for l in zigbee.liens { liensAttendus.insert(ligne([z(l.de), z(l.vers), l.genre, q(l.qualite), oui(l.suppose)])) }
        var liensC: [String] = []
        for l in c.liens {
            liensC.append(ligne(l.de.hasPrefix("zigbee:") ? [l.de, l.vers, l.genre, q(l.qualite), oui(l.suppose)]
                                                          : [l.de, l.vers, l.genre, q(l.qualite)]))
        }
        #expect(liensC.count == thread.liens.count + zigbee.liens.count)
        #expect(Set(liensC) == liensAttendus, "les liens : l'union des deux references")

        // Scene : libelle (a un suffixe pres), piece, chef, pile, rang, rayon.
        func champsScene(_ id: String, _ libelle: String, _ piece: String, _ chef: Bool, _ pile: Bool, _ rang: Int,
                         _ rayon: Double) -> String {
            ligne([id, libelle, piece, oui(chef), oui(pile), String(rang), String(rayon)])
        }
        var sceneAttendue = Set<String>()
        for n in thread.scene { sceneAttendue.insert(champsScene(t(n.id), n.libelle, n.piece, n.chef, n.pile, n.rang, n.rayon)) }
        for n in zigbee.scene { sceneAttendue.insert(champsScene(z(n.id), n.libelle, n.piece, n.chef, n.pile, n.rang, n.rayon)) }
        var sceneC: [String] = []
        for n in c.scene {
            let libelle = n.id.hasPrefix("zigbee:") ? Self.libelleDOrigine(n.libelle) : n.libelle
            sceneC.append(champsScene(n.id, libelle, n.piece, n.chef, n.pile, n.rang, n.rayon))
        }
        #expect(sceneC.count == thread.scene.count + zigbee.scene.count)
        let ecart = Set(sceneC).symmetricDifference(sceneAttendue).sorted()
        #expect(ecart.isEmpty, "la scene : l'union des deux references, a un suffixe pres : \(ecart.prefix(3))")

        // Les homonymes renommes ne le sont que cote Zigbee, et seuls les noms que Thread porte aussi.
        let nomsThread = Set(thread.scene.map(\.libelle))
        let suffixe = " " + DemoLancee.suffixeHomonymes
        let renommes = c.scene.filter { $0.id.hasPrefix("zigbee:") && $0.libelle.hasSuffix(suffixe) }
        #expect(!renommes.isEmpty && renommes.allSatisfy { nomsThread.contains(Self.libelleDOrigine($0.libelle)) })
        #expect(c.scene.filter { $0.id.hasPrefix("thread:") }.allSatisfy { !$0.libelle.hasSuffix(suffixe) })

        // Pieces : celles des deux references, partagees ; chaque noeud y est, une fois.
        var piecesParNoeud: [String: String] = [:]
        for p in c.pieces { for n in p.noeuds { piecesParNoeud[n] = p.cle } }
        #expect(c.pieces.flatMap(\.noeuds).count == c.noeuds.count, "chaque noeud est dans une seule piece")
        for n in c.scene where !n.piece.isEmpty { #expect(piecesParNoeud[n.id] == n.piece, "\(n.id)") }
        let clesC = Set(c.pieces.map(\.cle))
        let clesAttendues = Set(thread.pieces.map(\.cle)).union(zigbee.pieces.map(\.cle))
        #expect(clesC == clesAttendues, "les pieces : les memes que celles des deux references")
        #expect(c.domicile == zigbee.domicile, "la meme maison")
        let etagesAttendus = Set(zigbee.etages.map(\.cle)).union(thread.etages.map(\.cle))
        #expect(Set(c.etages.map(\.cle)) == etagesAttendus)
    }

    /// Dans la demo combinee, aucun libelle n'est porte par deux noeuds de protocoles differents : les homonymes de la demo de
    /// Zigbee sont renommes, rien d'autre. Six noms le sont a la source ; le sixieme, « Interrupteur cuisine », n'est plus un
    /// libelle de la scene (Maison nomme cet appareil « Variateur cuisine » : la fusion des noms le remplace).
    @Test func aucunHomonymeEntreLesProtocoles() throws {
        let (_, e) = Self.combinee()
        let parProtocole = Dictionary(grouping: e.scene.noeuds, by: \.id.protocole).mapValues { Set($0.map(\.libelle)) }
        let thread = try #require(parProtocole[.thread]), zigbee = try #require(parProtocole[.zigbee])
        #expect(thread.intersection(zigbee).isEmpty, "libelles en double : \(thread.intersection(zigbee).sorted())")
        let renommes = zigbee.filter { $0.hasSuffix(" " + DemoLancee.suffixeHomonymes) }
        #expect(renommes.sorted() == [
            "Ampoule entrée (Hue)", "Lampe arcade (Hue)", "Lampe chambre d'amis (Hue)", "Prise salon (Hue)",
            "Prise terrasse (Hue)",
        ])
    }
}
