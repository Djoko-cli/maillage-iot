import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : etages, pieces et noeuds")
struct ScenePiecesTests {
    /// Voir `FixturesScene.graphe(sonde:)`.
    static func graphe(sonde: Bool) throws -> GrapheReseau { try FixturesScene.graphe(sonde: sonde) }

    static let libelles = [idt("Apple TV"): "Apple TV 👑", idt("HomePod"): "HomePod", idt("E000000000000002"): "Lampe salon",
                           idt("E000000000000003"): "Capteur", idt("E000000000000004"): "Prise", idt("E000000000000005"): "Bouton"]

    static func noms(_ s: ScenePieces, etage e: Int) -> [ScenePieces.NomPiece] {
        s.etages[e].pieces.map { s.pieces[$0].nom }
    }

    static func piece(_ s: ScenePieces, _ nom: ScenePieces.NomPiece) throws -> ScenePieces.Piece {
        try #require(s.pieces.first { $0.nom == nom })
    }

    /// Zones : une piece dans deux zones va dans la plus precise (celle qui a le moins de pieces) ; une zone sans piece montree n'est pas un
    /// etage ; les pieces hors zone forment « Autres pieces » ; une piece sans noeud n'est pas montree.
    @Test func zones() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre", idt("E000000000000002"): "Bureau",
                      idt("E000000000000003"): "Garage", idt("E000000000000004"): "Salon", idt("E000000000000005"): "Chambre"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Chambre"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"]),
                     ZoneMaison(nom: "Grenier", pieces: ["Débarras"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(s.etages.map(\.nom) == [.zone("Rez-de-chaussée"), .zone("Étage"), .autresPieces])
        #expect(Self.noms(s, etage: 0) == [.maison("Salon")])
        #expect(Self.noms(s, etage: 1) == [.maison("Bureau"), .maison("Chambre")], "Chambre : Etage a 2 pieces, le rez-de-chaussee 3")
        #expect(Self.noms(s, etage: 2) == [.maison("Garage")])
        #expect(!s.pieces.contains { $0.nom == .maison("Cuisine") || $0.nom == .maison("Débarras") })
        #expect(try Self.piece(s, .maison("Salon")).noeuds == [idt("Apple TV"), idt("E000000000000004")])
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage", "autres-pieces"])
        #expect(!s.sansPiecesMaison)
    }

    /// Niveaux (polissage C, section 1) : une zone a cote rejoint son etage principal, juste apres lui, meme
    /// rangee avant lui par Maison ; les plateaux sont ranges niveau par niveau. « Sans piece » va sur le
    /// plateau du bas, l'etage principal du premier niveau. Sans choix, l'ordre de Maison.
    @Test func niveaux() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre", idt("E000000000000002"): "Terrasse"]
        let zones = [ZoneMaison(nom: "Jardin", pieces: ["Terrasse"]), ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true,
                            aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)], classement: FixturesScene.classement)
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage"])
        #expect(s.etages.map(\.niveau) == [0, 0, 1] && s.etages.map(\.principal) == [true, false, true])
        #expect(s.etages.map(\.dehors) == [false, true, false])
        #expect(s.niveaux.liste == [["zone:Rez-de-chaussée", "zone:Jardin"], ["zone:Étage"]])
        #expect(Self.noms(s, etage: 0) == [.maison("Salon"), .sansPiece], "« Sans piece » sur le plateau du bas")
        #expect(Self.noms(s, etage: 1) == [.maison("Terrasse")])
        let sans = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                               piecesMaison: true, classement: FixturesScene.classement)
        #expect(sans.etages.map(\.id) == ["zone:Jardin", "zone:Rez-de-chaussée", "zone:Étage"])
        #expect(sans.etages.map(\.niveau) == [0, 1, 2] && sans.etages.allSatisfy(\.principal))
    }

    /// Deux zones de Maison du meme nom (inattendu) : un seul etage, a la place de la premiere, avec les
    /// pieces des deux ; aucune cle d'etage en double. La premiere compte meme sans piece montree.
    @Test func zonesHomonymes() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre", idt("E000000000000002"): "Bureau"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre"]),
                     ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Bureau", "Salon"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage"])
        #expect(Self.noms(s, etage: 0) == [.maison("Bureau"), .maison("Salon"), .sansPiece])
        #expect(Self.noms(s, etage: 1) == [.maison("Chambre")])
        let vide = [ZoneMaison(nom: "Étage", pieces: ["Grenier"]), ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                    ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"])]
        let t = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: vide, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(t.etages.map(\.id) == ["zone:Étage", "zone:Rez-de-chaussée"])
        #expect(Self.noms(t, etage: 0) == [.maison("Bureau"), .maison("Chambre"), .sansPiece])
    }

    /// Maison sans zones, ou fichier d'avant les zones (le champ manque : nil) : un seul plateau.
    @Test func sansZones() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre"]
        for zones in [nil, []] as [[ZoneMaison]?] {
            let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                                piecesMaison: true, classement: FixturesScene.classement)
            #expect(s.etages.map(\.nom) == [.maison])
            #expect(Self.noms(s, etage: 0) == [.maison("Chambre"), .maison("Salon"), .sansPiece])
        }
        let ancien = """
        {"version": 1, "date": "2026-09-28T10:00:00Z", "statut": "ok", "accessoires": [{"nom": "Lampe", "piece": "Salon"}]}
        """
        let n = try NomsMaison.lire(Data(ancien.utf8))
        #expect(n.zones == nil)
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: n.zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(s.etages.map(\.nom) == [.maison])
    }

    /// « Sans piece » : les noeuds que Maison ne place pas, sur le plateau du bas, celui de l'ordre
    /// garde s'il y en a un ; une cle inconnue de l'ordre garde est ignoree.
    @Test func sansPieceSurLePlateauDuBas() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Chambre"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(Self.noms(s, etage: 0) == [.maison("Salon"), .sansPiece])
        #expect(try Self.piece(s, .sansPiece).noeuds == [idt("E000000000000005"), idt("E000000000000003"), idt("E000000000000002"),
                                                          idt("E000000000000004")], "par libelle")
        let inverse = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                                  piecesMaison: true, ordreEtages: ["zone:Étage", "inconnu", "zone:Rez-de-chaussée"], classement: FixturesScene.classement)
        #expect(inverse.etages.map(\.nom) == [.zone("Étage"), .zone("Rez-de-chaussée")])
        #expect(Self.noms(inverse, etage: 0) == [.maison("Chambre"), .sansPiece])
        #expect(try Self.piece(inverse, .sansPiece).etage == 0)
    }

    /// Une scene sans aucun noeud (tout est masque, ou rien a montrer) n'a ni etage, ni piece, ni niveau : le plateau
    /// « Maison » n'existe que pour porter les cartes des routeurs d'une maison sans pieces, il n'est pas une zone
    /// artificielle de la scene vide (banc de la phase 6). Avec des noeuds mais sans piece de Maison, il reste.
    @Test func sceneVideSansEtageNiPiece() throws {
        let vide = GrapheReseau(noeuds: [])
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"])]
        for (z, pieces) in [(nil, false), (zones, true), (zones, false)] as [([ZoneMaison]?, Bool)] {
            let s = ScenePieces(graphe: vide, libelles: [:], piecesNoeuds: [:], zones: z, chefs: [], piecesMaison: pieces,
                                ordreEtages: ["maison"], classement: FixturesScene.classement)
            #expect(s.etages.isEmpty && s.pieces.isEmpty && s.noeuds.isEmpty && s.liens.isEmpty, "zones \(z != nil), pieces \(pieces)")
            #expect(s.niveaux.liste.isEmpty && s.cleDisposition == ScenePieces.CleDisposition())
        }
        // Des noeuds, sans piece de Maison : le plateau « Maison » et ses cartes de routeur restent.
        let sans = ScenePieces(graphe: try Self.graphe(sonde: true), libelles: Self.libelles, piecesNoeuds: [:], zones: nil,
                               chefs: [], piecesMaison: false, classement: FixturesScene.classement)
        #expect(sans.etages.map(\.nom) == [.maison] && !sans.pieces.isEmpty && sans.sansPiecesMaison)
    }

    /// Pas encore de pieces de Maison : un plateau « Maison », une carte par routeur avec ses enfants
    /// (vus par la sonde) ; sans parent connu, « Sans piece ». Sans sonde, aucun parent : chaque
    /// routeur seul dans sa carte.
    @Test func groupementParRouteur() throws {
        let s = ScenePieces(graphe: try Self.graphe(sonde: true), libelles: Self.libelles, piecesNoeuds: [:], zones: nil,
                            chefs: [], piecesMaison: false, classement: FixturesScene.classement)
        #expect(s.sansPiecesMaison)
        #expect(s.etages.map(\.nom) == [.maison])
        #expect(try Self.piece(s, .routeur(idt("Apple TV"))).noeuds == [idt("Apple TV"), idt("E000000000000002")])
        #expect(try Self.piece(s, .routeur(idt("HomePod"))).noeuds == [idt("HomePod"), idt("E000000000000003")])
        #expect(try Self.piece(s, .routeur(idt("E000000000000004"))).noeuds == [idt("E000000000000004")], "appareil qui route")
        #expect(try Self.piece(s, .sansPiece).noeuds == [idt("E000000000000005")])
        let sans = ScenePieces(graphe: try Self.graphe(sonde: false), libelles: Self.libelles, piecesNoeuds: [:],
                               zones: nil, chefs: [], piecesMaison: false, classement: FixturesScene.classement)
        #expect(try Self.piece(sans, .routeur(idt("Apple TV"))).noeuds == [idt("Apple TV")])
        #expect(try Self.piece(sans, .sansPiece).noeuds.count == 4)
    }

    /// La cle de la disposition et les cartes ne dependent pas des badges (polissage D, section 2) : la scene voit les
    /// noms sans eux, et un autre chef ne reordonne pas les lignes. Un autre nom, une autre piece, une pile qui devient
    /// connue changent la cle ; la largeur reservee d'un nom (ici 7 px par caractere de `texteReserve`, plus 50 pour la
    /// pastille d'une pile connue) fait des cartes egales, avec ou sans badge, et une carte plus large avec une pile
    /// connue (polissage D, section 2, decision du 05/10).
    @Test func cleSansLesBadges() throws {
        let g = try Self.graphe(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        func scene(chefs: Set<IdNoeud>, libelles: [IdNoeud: String] = Self.libelles, pieces: [IdNoeud: String]? = nil,
                   piles: Set<IdNoeud> = []) -> ScenePieces {
            ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: pieces ?? tous, zones: nil, chefs: chefs, piecesMaison: true,
                        piles: piles, classement: FixturesScene.classement)
        }
        let a = scene(chefs: [idt("Apple TV")]), b = scene(chefs: [idt("HomePod")]), c = scene(chefs: [])
        #expect(a.cleDisposition == b.cleDisposition && a.cleDisposition == c.cleDisposition)
        #expect(a.pieces.map(\.noeuds) == b.pieces.map(\.noeuds))
        func largeurs(_ s: ScenePieces) -> [IdNoeud: Double] {
            Dictionary(uniqueKeysWithValues: s.noeuds.map {
                ($0.id, 7.0 * Double(CartesPieces.texteReserve($0.libelle, routeur: $0.route).count) + ($0.pile ? 50 : 0))
            })
        }
        #expect(CartesPieces.cartes(a, largeurs: largeurs(a)) == CartesPieces.cartes(b, largeurs: largeurs(b)))
        let pile = scene(chefs: [idt("Apple TV")], piles: [idt("E000000000000002")])
        #expect(pile.noeud(idt("E000000000000002"))?.pile == true && a.noeud(idt("E000000000000002"))?.pile == false)
        #expect(pile.cleDisposition != a.cleDisposition, "une pile connue")
        let salonPile = try #require(pile.pieces.firstIndex { $0.nom == .maison("Salon") })
        #expect(CartesPieces.cartes(pile, largeurs: largeurs(pile))[salonPile].largeur
                > CartesPieces.cartes(a, largeurs: largeurs(a))[salonPile].largeur, "une carte plus large avec une pile connue")
        var renomme = Self.libelles
        renomme[idt("E000000000000002")] = "Lampe du salon"
        #expect(scene(chefs: [idt("Apple TV")], libelles: renomme).cleDisposition != a.cleDisposition, "un autre nom")
        var ailleurs = tous
        ailleurs[idt("E000000000000002")] = "Cuisine"
        #expect(scene(chefs: [idt("Apple TV")], pieces: ailleurs).cleDisposition != a.cleDisposition, "une autre piece")
        let salon = try #require(a.cleDisposition.pieces["maison"]?["piece:Salon"])
        #expect(salon.contains("HomePod|HomePod|R|") && salon.contains("E000000000000002|Lampe salon||"), "l'id, le nom, s'il route")
        #expect(try #require(pile.cleDisposition.pieces["maison"]?["piece:Salon"]).contains("E000000000000002|Lampe salon||P"),
                "et si sa pile est connue")
        #expect(a.cleDisposition.niveaux == ["maison": "maison#0"])
    }

    /// « Le noeud route » (polissage D, section 2) s'ecrit d'une seule facon, `Noeud.route` : un routeur de bordure ou un
    /// autre routeur, jamais un autre noeud ; il suit le graphe et le rang de la carte (1 ou 2). La cle de la disposition
    /// en tire son « R ».
    @Test func leNoeudRoute() throws {
        let g = try Self.graphe(sonde: true)
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: Dictionary(uniqueKeysWithValues: g.noeuds.map {
            ($0.id, "Salon")
        }), zones: nil, chefs: [], piecesMaison: true, classement: FixturesScene.classement)
        #expect(Set(s.noeuds.map(\.rang)) == [1, 2, 3], "des noeuds de chaque rang")
        let cles = try #require(s.cleDisposition.pieces["maison"]?["piece:Salon"])
        for n in s.noeuds {
            #expect(n.route == (n.bordure || n.routeur), "\(n.id) : le graphe")
            #expect(n.route == (n.rang == 1 || n.rang == 2), "\(n.id) : le rang")
            let cle = try #require(cles.first { $0.hasPrefix(n.id.cle + "|") }).split(separator: "|", omittingEmptySubsequences: false)
            #expect(cle[2] == (n.route ? "R" : ""), "\(n.id) : la cle")
        }
    }

    /// Lignes d'une carte : les routeurs de bordure, les autres routeurs, puis les autres noeuds, par nom ; le chef reste
    /// dans son groupe (polissage D, section 2) ; rayons 15 (centre), 13, 8 et 7.
    @Test func lignesEtRayons() throws {
        let g = try Self.graphe(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: [idt("HomePod")],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(try Self.piece(s, .maison("Salon")).noeuds
                == [idt("Apple TV"), idt("HomePod"), idt("E000000000000004"), idt("E000000000000005"), idt("E000000000000003"), idt("E000000000000002")])
        #expect(s.noeud(idt("HomePod"))?.rang == 1 && s.noeud(idt("HomePod"))?.rayon == 13 && s.noeud(idt("HomePod"))?.chef == true)
        #expect(s.noeud(idt("Apple TV"))?.rang == 1 && s.noeud(idt("Apple TV"))?.rayon == 15)
        #expect(s.noeud(idt("E000000000000004"))?.rang == 2 && s.noeud(idt("E000000000000004"))?.rayon == 8)
        #expect(s.noeud(idt("E000000000000002"))?.rang == 3 && s.noeud(idt("E000000000000002"))?.rayon == 7)
        #expect(s.noeud(idt("E000000000000002"))?.libelle == "Lampe salon")
        #expect(s.liens == g.liens)
    }

    /// Le classement des noeuds (rang de carte, rayon de pastille) est un parametre obligatoire : le coeur n'a pas de
    /// regle par defaut. Une regle fournie donne ses rangs et ses rayons, et les lignes d'une carte la suivent.
    @Test func classementFourni() throws {
        let g = try Self.graphe(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        func scene(_ classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double)) -> ScenePieces {
            ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: [],
                        piecesMaison: true, classement: classement)
        }
        // La regle des fixtures (celle de `lignesEtRayons`) : bordure 1, routeur 2, sinon 3.
        let defaut = scene(FixturesScene.classement)
        #expect(defaut.noeud(idt("HomePod"))?.rang == 1 && defaut.noeud(idt("HomePod"))?.rayon == 13)
        #expect(defaut.noeud(idt("Apple TV"))?.rang == 1 && defaut.noeud(idt("Apple TV"))?.rayon == 15)
        #expect(defaut.noeud(idt("E000000000000004"))?.rang == 2 && defaut.noeud(idt("E000000000000004"))?.rayon == 8)
        #expect(defaut.noeud(idt("E000000000000002"))?.rang == 3 && defaut.noeud(idt("E000000000000002"))?.rayon == 7)
        // Une regle inventee : le centre d'abord (rayon 20), puis les routeurs (rayon 9), puis les autres (rayon 5).
        let regle: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) = { n in
            n.genre == .centre ? (1, 20) : n.routeur ? (2, 9) : (3, 5)
        }
        let s = scene(regle)
        #expect(s.noeud(idt("Apple TV"))?.rang == 1 && s.noeud(idt("Apple TV"))?.rayon == 20)
        #expect(s.noeud(idt("HomePod"))?.rang == 2 && s.noeud(idt("HomePod"))?.rayon == 9)
        #expect(s.noeud(idt("E000000000000004"))?.rang == 2 && s.noeud(idt("E000000000000004"))?.rayon == 9)
        #expect(s.noeud(idt("E000000000000002"))?.rang == 3 && s.noeud(idt("E000000000000002"))?.rayon == 5)
        #expect(s.noeud(idt("HomePod"))?.route == true && s.noeud(idt("E000000000000005"))?.route == false)
        #expect(try Self.piece(s, .maison("Salon")).noeuds
                == [idt("Apple TV"), idt("HomePod"), idt("E000000000000004"), idt("E000000000000005"), idt("E000000000000003"), idt("E000000000000002")],
                "les lignes suivent le rang fourni, puis le libelle")
    }

    /// Teintes : FNV-1a 32 bits du nom, modulo 8 ; dans un etage, la suivante libre si elle est prise
    /// (Chambre, Salle de bain et Cellier donnent 3) ; d'un etage a l'autre, pas de conflit.
    @Test func teintes() throws {
        #expect(ScenePieces.fnv1a("") == 0x811C_9DC5)
        #expect(ScenePieces.fnv1a("a") == 0xE40C_292C)
        #expect(ScenePieces.fnv1a("foobar") == 0xBF9C_F968)
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salle de bain", idt("HomePod"): "Chambre", idt("E000000000000002"): "Cellier",
                      idt("E000000000000003"): "Salon", idt("E000000000000004"): "Chambre", idt("E000000000000005"): "Salon"]
        let zones = [ZoneMaison(nom: "Étage", pieces: ["Salle de bain", "Chambre", "Cellier"]),
                     ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(try Self.piece(s, .maison("Cellier")).teinte == 3, "premier par nom")
        #expect(try Self.piece(s, .maison("Chambre")).teinte == 4)
        #expect(try Self.piece(s, .maison("Salle de bain")).teinte == 5)
        #expect(try Self.piece(s, .maison("Salon")).teinte == 2)
        #expect(ScenePieces.teintes.count == 8 && ScenePieces.teintes[0] == 0x3B82F5)
    }

    /// Maison sans pieces : la teinte et le rang de la carte d'un routeur viennent de son id, pas de son
    /// libelle decore ; ils ne changent ni quand la couronne passe a un autre routeur, ni quand ☾ ou ⚠︎
    /// apparait.
    @Test func cartesDeRouteurStables() throws {
        let g = try Self.graphe(sonde: true)
        func cartes(_ libelles: [IdNoeud: String], chef: String) -> [String] {
            let s = ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: [:], zones: nil, chefs: [idt(chef)],
                                piecesMaison: false, classement: FixturesScene.classement)
            return s.etages[0].pieces.map { "\(s.pieces[$0].id) #\(s.pieces[$0].teinte)" }
        }
        var libelles = Self.libelles
        libelles[idt("Apple TV")] = "Salon 👑"
        libelles[idt("HomePod")] = "Salon bas"
        let avant = cartes(libelles, chef: "Apple TV")
        #expect(avant.count == 4)
        libelles[idt("Apple TV")] = "Salon"
        libelles[idt("HomePod")] = "Salon bas 👑"
        #expect(cartes(libelles, chef: "HomePod") == avant, "la couronne passe a l'autre routeur")
        libelles[idt("E000000000000004")] = "Prise ☾ ⚠︎"
        #expect(cartes(libelles, chef: "HomePod") == avant, "l'appareil qui route s'endort et n'a plus d'adresse")
    }

    // MARK: - Phase 10 : une piece de plusieurs zones

    /// Scene de zones inventees : « Piece 1 » (Apple TV), « Piece 2 » (HomePod), « Piece 3 » (E...02) ; les autres noeuds
    /// n'ont pas de piece.
    static func sceneZones(_ zones: [ZoneMaison], choix: [String: String] = [:], montrees: [String] = ["Pièce 1", "Pièce 2", "Pièce 3"],
                           aCote: [String: PlacesGardees.ACote] = [:]) throws -> ScenePieces {
        let ids = [idt("Apple TV"), idt("HomePod"), idt("E000000000000002")]
        let pieces = Dictionary(uniqueKeysWithValues: zip(ids, montrees))
        return ScenePieces(graphe: try graphe(sonde: false), libelles: libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                           piecesMaison: true, aCote: aCote, zonesChoisies: choix, classement: FixturesScene.classement)
    }

    /// Regle 1 : une piece de deux zones va dans celle qui a le moins de pieces, quel que soit l'ordre de Maison ; la zone
    /// precise garde son plateau, meme si toutes ses pieces sont aussi ailleurs.
    @Test func pieceDePlusieursZonesDansLaPlusPrecise() throws {
        let a = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2", "Pièce 3"])
        let b = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1"])
        for zones in [[a, b], [b, a]] {
            let s = try Self.sceneZones(zones)
            #expect(Set(s.etages.map(\.id)) == ["zone:Zone A", "zone:Zone B"], "Zone B garde son plateau")
            let e = try #require(s.etages.first { $0.id == "zone:Zone B" })
            #expect(e.pieces.map { s.pieces[$0].nom }.filter { $0 != .sansPiece } == [.maison("Pièce 1")])
            let e2 = try #require(s.etages.first { $0.id == "zone:Zone A" })
            #expect(e2.pieces.map { s.pieces[$0].nom }.filter { $0 != .sansPiece } == [.maison("Pièce 2"), .maison("Pièce 3")])
            #expect(s.pieces.filter { $0.nom == .maison("Pièce 1") }.count == 1, "une seule carte")
        }
        #expect(try Self.sceneZones([a, b]).etages.map(\.id).first == "zone:Zone A")
        #expect(try Self.sceneZones([b, a]).etages.map(\.id).first == "zone:Zone B")
    }

    /// A egalite de taille, la premiere zone dans l'ordre de Maison. Les pieces comptent distinctes, montrees ou non, une
    /// fois par zone meme listee deux fois ; deux zones du meme nom comptent leurs pieces ensemble.
    @Test func egaliteEtComptage() throws {
        let a = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2"])
        let b = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1", "Pièce 3"])
        func etage(_ s: ScenePieces) throws -> String {
            let i = try #require(s.pieces.first { $0.nom == .maison("Pièce 1") }?.etage)
            return s.etages[i].id
        }
        #expect(try etage(Self.sceneZones([a, b])) == "zone:Zone A")
        #expect(try etage(Self.sceneZones([b, a])) == "zone:Zone B")
        // Montrees ou non : A et B ont 3 pieces chacune, seules les pieces 1 et 2 ont un noeud ; A (premiere) l'emporte,
        // et B, sans piece rangee chez elle, n'a pas de plateau.
        let a3 = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2", "Pièce 3"])
        let b3 = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1", "Pièce 4", "Pièce 5"])
        let s = try Self.sceneZones([a3, b3], montrees: ["Pièce 1", "Pièce 2", "Pièce 3"])
        #expect(try etage(s) == "zone:Zone A" && s.etages.map(\.id) == ["zone:Zone A"])
        // Une piece listee deux fois dans une zone ne compte qu'une fois : A = 2 pieces distinctes, B = 3.
        let double = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 1", "Pièce 2"])
        let b2 = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1", "Pièce 3", "Pièce 4"])
        #expect(try etage(Self.sceneZones([b2, double])) == "zone:Zone A")
        // Zones du meme nom : fusionnees, 3 pieces ensemble (1, 2, 3) contre B a 2.
        let a1 = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2"])
        let a2 = ZoneMaison(nom: "Zone A", pieces: ["Pièce 3"])
        let b4 = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1", "Pièce 4"])
        #expect(try etage(Self.sceneZones([a1, b4, a2])) == "zone:Zone B")
    }

    /// Une zone dont aucune piece n'est rangee chez elle n'a pas de plateau (comme avant).
    @Test func zoneSansPieceRangeeChezElle() throws {
        let a = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1"])
        let b = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1", "Pièce 4"])
        let s = try Self.sceneZones([b, a], montrees: ["Pièce 1", "Pièce 2", "Pièce 3"])
        #expect(s.etages.map(\.id) == ["zone:Zone A", "autres-pieces"], "B n'a que Piece 1, rangee dans A ; Pieces 2 et 3 hors zone")
    }

    /// Regle 2 : le choix gardé l'emporte ; un choix perime (zone qui ne contient pas la piece, ou inconnue) laisse la regle 1.
    @Test func choixGardeEtChoixPerime() throws {
        let a = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2", "Pièce 3"])
        let b = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1"])
        let c = ZoneMaison(nom: "Zone C", pieces: ["Pièce 2"])
        func etage(_ s: ScenePieces) throws -> String {
            let i = try #require(s.pieces.first { $0.nom == .maison("Pièce 1") }?.etage)
            return s.etages[i].id
        }
        #expect(try etage(Self.sceneZones([a, b, c])) == "zone:Zone B")
        #expect(try etage(Self.sceneZones([a, b, c], choix: ["Pièce 1": "Zone A"])) == "zone:Zone A")
        #expect(try etage(Self.sceneZones([a, b, c], choix: ["Pièce 1": "Zone C"])) == "zone:Zone B", "C ne contient pas la piece")
        #expect(try etage(Self.sceneZones([a, b, c], choix: ["Pièce 1": "Zone Z"])) == "zone:Zone B", "zone inconnue")
        // Le choix d'une autre piece ne la touche pas.
        #expect(try etage(Self.sceneZones([a, b, c], choix: ["Pièce 2": "Zone C"])) == "zone:Zone B")
        // Un choix qui vide une zone de son plateau : B n'a plus de piece rangee chez elle.
        let s = try Self.sceneZones([a, b], choix: ["Pièce 1": "Zone A"])
        #expect(s.etages.map(\.id) == ["zone:Zone A"])
    }

    /// `zonesDe` (menu) et `zoneChoisie` (coche) : une piece partagee, une piece simple, une piece sans zone, une piece inconnue.
    @Test func zonesDeEtZoneChoisie() throws {
        let a = ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2", "Pièce 3"])
        let b = ZoneMaison(nom: "Zone B", pieces: ["Pièce 1"])
        let zones = [a, b, ZoneMaison(nom: "Zone C", pieces: ["Pièce 2"])]
        let s = try Self.sceneZones(zones, montrees: ["Pièce 1", "Pièce 2", "Pièce 9"])
        #expect(s.zonesDe("Pièce 1") == ["Zone A", "Zone B"], "ordre de Maison, pas celui de la scene")
        #expect(s.zonesDe("Pièce 2") == ["Zone A", "Zone C"])
        #expect(s.zonesDe("Pièce 9").isEmpty, "piece sans zone")
        #expect(s.zonesDe("Pièce 7").isEmpty, "piece inconnue")
        #expect(s.zoneChoisie("Pièce 1") == nil && s.zoneChoisie("Pièce 9") == nil)
        let c = try Self.sceneZones(zones, choix: ["Pièce 1": "Zone A", "Pièce 2": "Zone Z", "Pièce 3": "Zone A"])
        #expect(c.zoneChoisie("Pièce 1") == "Zone A")
        #expect(c.zoneChoisie("Pièce 2") == nil, "choix perime")
        #expect(c.zoneChoisie("Pièce 3") == "Zone A")
        // Zones du meme nom : fusionnees, une seule fois dans le menu.
        let h = try Self.sceneZones([ZoneMaison(nom: "Zone A", pieces: ["Pièce 1"]), ZoneMaison(nom: "Zone A", pieces: ["Pièce 1", "Pièce 2"]), b])
        #expect(h.zonesDe("Pièce 1") == ["Zone A", "Zone B"])
        // Sans zones : rien a choisir.
        let sans = ScenePieces(graphe: try Self.graphe(sonde: false), libelles: Self.libelles, piecesNoeuds: [idt("Apple TV"): "Pièce 1"],
                               zones: nil, chefs: [], piecesMaison: true, zonesChoisies: ["Pièce 1": "Zone A"], classement: FixturesScene.classement)
        #expect(sans.zonesDe("Pièce 1").isEmpty && sans.zoneChoisie("Pièce 1") == nil)
    }

    /// Non-regression : sans piece partagee, la meme scene qu'avant (etages, pieces, ordre), avec ou sans choix gardes, et sur
    /// les zones de la demo.
    @Test func sansPieceCommuneRienNeChange() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = [idt("Apple TV"): "Salon", idt("HomePod"): "Terrasse", idt("E000000000000002"): "Chambre",
                      idt("E000000000000003"): "Grenier", idt("E000000000000004"): "Cuisine"]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: NomsDemo.zones, chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage", "zone:Combles"])
        #expect(Self.noms(s, etage: 0) == [.maison("Cuisine"), .maison("Salon"), .sansPiece])
        #expect(Self.noms(s, etage: 1) == [.maison("Terrasse")])
        #expect(Self.noms(s, etage: 2) == [.maison("Chambre")])
        #expect(Self.noms(s, etage: 3) == [.maison("Grenier")])
        // Des choix gardes (meme perimes) ne changent rien : aucune piece n'a le choix.
        let choix = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: NomsDemo.zones, chefs: [],
                                piecesMaison: true, zonesChoisies: ["Salon": "Combles", "Terrasse": "Jardin"], classement: FixturesScene.classement)
        #expect(choix.etages == s.etages && choix.pieces == s.pieces && choix.noeuds == s.noeuds)
        #expect(choix.zoneChoisie("Terrasse") == "Jardin" && choix.zoneChoisie("Salon") == nil)
        // Zones de plusieurs pieces mais disjointes : l'ordre de Maison et les pieces par nom, comme avant.
        let t = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: Array(NomsDemo.zones.reversed()), chefs: [],
                            piecesMaison: true, classement: FixturesScene.classement)
        #expect(t.etages.map(\.id) == ["zone:Combles", "zone:Étage", "zone:Jardin", "zone:Rez-de-chaussée"])
    }

    /// Le choix « a cote / hors de la maison » d'une zone est garde par sa cle : il revient quand la zone retrouve une piece.
    /// Cas reel : une zone d'une seule piece, qui est aussi dans une zone plus grande.
    @Test func lePlateauRetrouveSonChoixDePlace() throws {
        let dehors = ["zone:Zone 1": PlacesGardees.ACote(etage: "zone:Zone 2", dehors: true)]
        let petite = ZoneMaison(nom: "Zone 1", pieces: ["Pièce 1"])
        let grande = ZoneMaison(nom: "Zone 2", pieces: ["Pièce 1", "Pièce 2", "Pièce 3"])
        let avec = try Self.sceneZones([grande, petite], aCote: dehors)
        #expect(avec.etages.map(\.id) == ["zone:Zone 2", "zone:Zone 1"] && avec.etages.map(\.dehors) == [false, true])
        #expect(avec.etages.map(\.niveau) == [0, 0] && avec.etages.map(\.principal) == [true, false])
        // Choix de la grande zone : la petite perd son plateau (et son choix de place reste dans le fichier).
        let sans = try Self.sceneZones([grande, petite], choix: ["Pièce 1": "Zone 2"], aCote: dehors)
        #expect(sans.etages.map(\.id) == ["zone:Zone 2"] && sans.etages.map(\.dehors) == [false])
        // « Automatiquement » : la petite zone revient, au meme endroit.
        let retour = try Self.sceneZones([grande, petite], aCote: dehors)
        #expect(retour.etages == avec.etages && retour.niveaux == avec.niveaux)
    }
}
