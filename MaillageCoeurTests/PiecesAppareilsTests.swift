import Foundation
import Testing
@testable import MaillageCoeur

/// Precision 27 (spec de la vue par pieces, section 2.3) : un noeud que Maison ne place pas et dont
/// l'ExtMac est connue (par la sonde, ou par son nom d'hote Matter) se place au choix, sous son ExtMac,
/// par maison ; la piece de Maison passe avant le choix. Donnees inventees.
@Suite("Scene : piece choisie d'un noeud que Maison ne place pas, sous son ExtMac")
struct PiecesAppareilsTests {
    static let partition = "46CBEBCD"
    static let domicile = "Maison inventée"
    /// Pieces d'une maison inventee.
    static let pieces = ["Bureau", "Cuisine", "Salon"]

    /// Reseau invente : l'Apple TV, routeur de bordure et chef ; `annonces` : les noms d'hote des
    /// appareils Matter annonces, dans la partition.
    static func instantane(annonces: [String] = []) -> Instantane {
        var b = Banc()
        let omr = "fd00:5555:6666::/64"
        b.routeur("Apple TV", partition: partition, role: .chef, primaire: true, lien: "fe80::1", omr: omr,
                  xa: "E0000000000000A1")
        for (k, hote) in annonces.enumerated() {
            b.appareil(hote, noeud: k + 2, adresses: ["fd00:5555:6666:0:b00::\(k + 2)"])
        }
        return Instantane(annonces: b.annonces)
    }

    /// Maillage de la sonde : le routeur 1, l'Apple TV par son ExtMac ; `routeurs` : identifiant, ExtMac
    /// (nil : inconnue) et routeur de bordure ; `enfants` : RLOC16 et ExtMac (nil : inconnue).
    static func maillage(routeurs: [(Int, String?, Bool)] = [], enfants: [(UInt16, String?)]) -> Maillage {
        var c = ConstructionMaillage(date: Date(timeIntervalSince1970: 1_790_000_000), partition: partition)
        let ids = [1] + routeurs.map { $0.0 }
        c.routeurs(Route64(sequence: 0, routes: ids.map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 1)
        c.identite("E0000000000000A1", routeur: 1)
        c.marquer(1, bordure: true, bbrPrincipal: true)
        for (id, ext, bordure) in routeurs {
            if let ext { c.identite(ext, routeur: id) }
            c.marquer(id, bordure: bordure)
        }
        for (rloc16, ext) in enfants {
            c.enfant(EnfantMaillage(rloc16: rloc16, extMac: ext, qualite: 3, endormi: true, source: .tableEnfants))
        }
        return c.maillage()
    }

    /// Graphe du reseau, avec la sonde si `m` est donne.
    static func graphe(_ i: Instantane, _ m: Maillage?) throws -> GrapheReseau {
        let r = try #require(i.reseaux.first)
        let apps = i.appareils.map { AppareilAffiche(id: $0.id, nom: $0.id, partition: $0.partition, etat: .joignable) }
        return GrapheReseau(reseau: r, appareils: apps,
                            maillage: m.map { MaillageAffiche(maillage: $0, reseau: r, appareils: i.appareils) })
    }

    /// Un choix sous l'ExtMac place l'appareil que la sonde seule connait (« rloc:0401 ») ; un routeur
    /// Thread qui n'est pas de bordure a lui aussi un choix ; un routeur de bordure, annonce ou connu de
    /// la sonde seule, n'en a pas (precisions 23 a 25). Le choix vaut pour sa maison, et tant que sa
    /// piece est dans Maison.
    @Test func choixParExtMac() throws {
        let m = Self.maillage(routeurs: [(2, "E0000000000000B2", true), (3, "E0000000000000C3", false)],
                              enfants: [(0x0401, "DEADBEEF00000001")])
        let i = Self.instantane()
        let r = try #require(i.reseaux.first)
        let affiche = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils)
        #expect(affiche.extMacs == ["Apple TV": "E0000000000000A1", "rloc:0800": "E0000000000000B2",
                                    "rloc:0C00": "E0000000000000C3", "rloc:0401": "DEADBEEF00000001"])
        let g = try Self.graphe(i, m)
        let detecteur = try #require(g.noeud("rloc:0401"))
        #expect(detecteur.extMac == "DEADBEEF00000001" && PiecesRouteurs.cle(detecteur) == "DEADBEEF00000001")
        #expect(PiecesRouteurs.cle(try #require(g.noeud("rloc:0C00"))) == "E0000000000000C3", "routeur Thread")
        let atv = try #require(g.noeud("Apple TV"))
        #expect(atv.extMac == "E0000000000000A1" && PiecesRouteurs.cle(atv) == nil, "routeur de bordure annonce")
        let inconnu = try #require(g.noeud("rloc:0800"))
        #expect(inconnu.bordure && inconnu.extMac == "E0000000000000B2" && PiecesRouteurs.cle(inconnu) == nil,
                "routeur de bordure connu de la sonde seule (precision 25)")
        var p = PiecesRouteurs()
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile).isEmpty, "sans choix")
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        p.choisir("Bureau", appareil: "E0000000000000C3", domicile: Self.domicile)
        // Un choix sous l'ExtMac d'un routeur de bordure (le drapeau des Network Data peut changer d'une
        // tournee a l'autre) ne le place pas : il suit les precisions 23 a 25.
        p.choisir("Cuisine", appareil: "E0000000000000B2", domicile: Self.domicile)
        p.choisir("Cuisine", appareil: "E0000000000000A1", domicile: Self.domicile)
        #expect(p.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == "Salon")
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile)
                == ["rloc:0401": "Salon", "rloc:0C00": "Bureau"])
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: "Chalet").isEmpty, "une autre maison")
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: ["Bureau", "Cuisine"], domicile: Self.domicile)
                == ["rloc:0C00": "Bureau"], "le salon n'est plus dans Maison : le choix ne compte plus")
        #expect(p.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == "Salon", "il reste dans le fichier")
    }

    /// Le meme appareil garde son choix sous un autre parent (autre RLOC16), puis quand son annonce
    /// revient : reconnu par la sonde (meme ExtMac), ou, sans sonde, par son nom d'hote Matter, en
    /// majuscules ou en minuscules.
    @Test func memeAppareilAutreRloc16OuAnnonce() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        func piece(_ g: GrapheReseau, _ id: String) -> String? {
            p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile)[id]
        }
        let avant = try Self.graphe(Self.instantane(), Self.maillage(enfants: [(0x0401, "DEADBEEF00000001")]))
        #expect(piece(avant, "rloc:0401") == "Salon")
        let ailleurs = try Self.graphe(Self.instantane(), Self.maillage(routeurs: [(3, nil, false)],
                                                                        enfants: [(0x0C02, "DEADBEEF00000001")]))
        #expect(ailleurs.noeud("rloc:0401") == nil)
        #expect(piece(ailleurs, "rloc:0C02") == "Salon", "autre parent, autre RLOC16")
        let annonce = Self.instantane(annonces: ["DEADBEEF00000001"])
        let reconnu = try Self.graphe(annonce, Self.maillage(enfants: [(0x0401, "DEADBEEF00000001")]))
        #expect(reconnu.noeud("rloc:0401") == nil && reconnu.noeud("DEADBEEF00000001")?.inconnu == false)
        #expect(piece(reconnu, "DEADBEEF00000001") == "Salon", "annonce revenue, avec la sonde")
        #expect(piece(try Self.graphe(annonce, nil), "DEADBEEF00000001") == "Salon", "sans la sonde : son nom d'hote")
        let minuscules = try Self.graphe(Self.instantane(annonces: ["deadbeef00000001"]), nil)
        #expect(minuscules.noeud("deadbeef00000001")?.extMac == "DEADBEEF00000001")
        #expect(piece(minuscules, "deadbeef00000001") == "Salon")
    }

    /// La piece de Maison passe avant le choix ; le choix reste, sans effet.
    @Test func maisonLEmporte() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        let g = try Self.graphe(Self.instantane(annonces: ["DEADBEEF00000001"]),
                                Self.maillage(enfants: [(0x0401, "DEADBEEF00000001")]))
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile)["DEADBEEF00000001"]
                == "Salon", "sans piece de Maison : le choix")
        let avecMaison = p.piecesNoeuds(g, deMaison: ["DEADBEEF00000001": "Cuisine"], parmi: Self.pieces,
                                        domicile: Self.domicile)
        #expect(avecMaison == ["DEADBEEF00000001": "Cuisine"], "Maison l'emporte")
        #expect(p.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == "Salon", "le choix reste")
    }

    /// Un noeud sans ExtMac connue n'a ni cle, ni choix, ni menu : un enfant ou un routeur Thread que
    /// la sonde connait sans ExtMac, une annonce dont le nom d'hote n'est pas une ExtMac (HomeKit).
    @Test func sansExtMacNiChoixNiMenu() throws {
        let i = Self.instantane(annonces: ["Eve-Motion-1A2B"])
        let g = try Self.graphe(i, Self.maillage(routeurs: [(3, nil, false)],
                                                 enfants: [(0x0401, "DEADBEEF00000001"), (0x0402, nil)]))
        for id in ["rloc:0402", "rloc:0C00", "Eve-Motion-1A2B"] {
            let n = try #require(g.noeud(id))
            #expect(n.extMac == nil && PiecesRouteurs.cle(n) == nil, "\(id)")
        }
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile) == ["rloc:0401": "Salon"],
                "seul le noeud qui a une ExtMac est place")
        #expect(GrapheReseau.extMac(hote: "Eve-Motion-1A2B") == nil && GrapheReseau.extMac(hote: "C4299622387B") == nil)
        #expect(GrapheReseau.extMac(hote: "deadbeef00000001") == "DEADBEEF00000001")
    }

    /// Un fichier d'avant les appareils (version 1, les routeurs seuls) se lit sans perte ; il se
    /// reecrit avec les choix d'appareils sans perdre ceux des routeurs ; une app d'avant lit encore
    /// les choix des routeurs du nouveau fichier.
    @Test func ancienFormat() throws {
        let url = PiecesRouteursTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ancien = """
            {
              "maisons" : {
                "" : {
                  "HomePod" : "Cuisine"
                },
                "Maison inventée" : {
                  "Apple TV" : "Salon",
                  "HomePod Palier" : "Bureau"
                }
              },
              "version" : 1
            }
            """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(ancien.utf8).write(to: url)
        let routeurs = ["": ["HomePod": "Cuisine"], Self.domicile: ["Apple TV": "Salon", "HomePod Palier": "Bureau"]]
        var p = PiecesRouteurs.lire(url)
        #expect(p.maisons == routeurs && p.appareils.isEmpty && p.version == 1)
        #expect(p.choix(routeur: "HomePod Palier", domicile: Self.domicile) == "Bureau")
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        try p.ecrire(dans: url)
        let relu = PiecesRouteurs.lire(url)
        #expect(relu == p && relu.maisons == routeurs)
        #expect(relu.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == "Salon")
        // Ce que lisait l'app d'avant : la version (au plus 1) et les routeurs ; elle ignore le reste.
        struct Avant: Decodable {
            var version: Int
            var maisons: [String: [String: String]]
        }
        let avant = try JSONDecoder().decode(Avant.self, from: Data(contentsOf: url))
        #expect(avant.version <= 1 && avant.maisons == routeurs)
    }

    /// Un `appareils` mal forme (champ facultatif que l'app n'ecrit jamais ainsi : fichier edite a la
    /// main ou abime) ne fait pas perdre les choix des routeurs : le champ seul est ignore, et le
    /// prochain choix reecrit un fichier sain. `null` vaut un champ absent (deja le cas avant).
    @Test(arguments: [#"["x"]"#, #""texte""#, #"{"Maison inventée": ["x"]}"#,
                      #"{"Maison inventée": {"DEADBEEF00000001": 5}}"#, "null"])
    func appareilsMalForme(champ: String) throws {
        let url = PiecesRouteursTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let json = """
            {
              "appareils" : \(champ),
              "maisons" : {
                "Maison inventée" : {
                  "Apple TV" : "Salon",
                  "HomePod Palier" : "Bureau"
                }
              },
              "version" : 1
            }
            """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        let routeurs = [Self.domicile: ["Apple TV": "Salon", "HomePod Palier": "Bureau"]]
        var p = PiecesRouteurs.lire(url)
        #expect(p.maisons == routeurs && p.version == 1, "les choix des routeurs restent")
        #expect(p.appareils.isEmpty, "le champ mal forme est ignore")
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        try p.ecrire(dans: url)
        let relu = PiecesRouteurs.lire(url)
        #expect(relu == p && relu.maisons == routeurs, "le fichier reecrit est sain")
        #expect(relu.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == "Salon")
    }

    /// « Sans piece » (nil) efface le choix d'un appareil ; la cle est l'ExtMac en majuscules ; les
    /// choix des routeurs restent.
    @Test func sansPieceEffaceLeChoix() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", routeur: "HomePod Palier", domicile: Self.domicile)
        let routeurs = p
        p.choisir("Salon", appareil: "DEADBEEF00000001", domicile: Self.domicile)
        p.choisir("Bureau", appareil: "deadbeef00000002", domicile: Self.domicile)
        #expect(p.choix(appareil: "DEADBEEF00000002", domicile: Self.domicile) == "Bureau", "en majuscules")
        let g = try Self.graphe(Self.instantane(), Self.maillage(enfants: [(0x0401, "DEADBEEF00000001")]))
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile) == ["rloc:0401": "Salon"])
        p.choisir(nil, appareil: "DEADBEEF00000001", domicile: Self.domicile)
        #expect(p.choix(appareil: "DEADBEEF00000001", domicile: Self.domicile) == nil)
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile).isEmpty, "Sans piece")
        p.choisir(nil, appareil: "DEADBEEF00000002", domicile: Self.domicile)
        #expect(p == routeurs, "plus aucun choix d'appareil pour cette maison")
        #expect(p.choix(routeur: "HomePod Palier", domicile: Self.domicile) == "Salon")
    }
}
