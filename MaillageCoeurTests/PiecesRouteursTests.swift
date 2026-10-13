import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : piece des routeurs que Maison ne place pas")
struct PiecesRouteursTests {
    /// Pieces d'une maison inventee.
    static let pieces = ["Bureau", "Chambre", "Chambre d'amis", "Entrée", "Salle de bain", "Salon"]

    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-routeurs.json")
    }

    /// D'apres le nom : en mots entiers, sans egard a la casse ni aux accents.
    @Test(arguments: [
        ("HomePod mini chambre", "Chambre"),
        ("HomePod mini bureau", "Bureau"),
        ("HOMEPOD ENTREE", "Entrée"),
        ("Apple TV (salon)", "Salon"),
        ("HomePod-salle-de-bain", "Salle de bain"),
    ])
    func dApresLeNom(nom: String, attendue: String) {
        #expect(PiecesRouteurs.piece(nom: nom, parmi: Self.pieces) == attendue)
    }

    /// Rien sans piece dans le nom : un mot entier, pas un bout de mot (« Salons », « Bureautique ») ;
    /// les mots de la piece doivent se suivre.
    @Test(arguments: ["HomePod Palier", "HomePod Avant", "Apple TV", "HomePod Salons", "Bureautique",
                      "HomePod salle, bain"])
    func sansPieceDansLeNom(nom: String) {
        #expect(PiecesRouteurs.piece(nom: nom, parmi: Self.pieces) == nil)
    }

    /// Le nom de piece le plus long gagne ; a egalite de longueur entre deux pieces, aucune.
    @Test func plusLongueOuAucune() {
        #expect(PiecesRouteurs.piece(nom: "HomePod chambre d'amis", parmi: Self.pieces) == "Chambre d'amis")
        #expect(PiecesRouteurs.piece(nom: "HomePod bureau entrée", parmi: Self.pieces) == nil, "Bureau et Entrée : 6 lettres")
        #expect(PiecesRouteurs.piece(nom: "HomePod salon chambre", parmi: Self.pieces) == "Chambre")
        #expect(PiecesRouteurs.piece(nom: "HomePod entree", parmi: ["Entrée", "Entree"]) == nil, "deux pieces, meme nom")
        #expect(PiecesRouteurs.piece(nom: "HomePod", parmi: []) == nil)
    }

    /// Le choix passe avant le nom ; un choix dont la piece n'est plus dans Maison ne compte pas ; nil
    /// revient a la regle du nom. Par maison.
    @Test func choixAvantLeNom() {
        var p = PiecesRouteurs()
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: Self.pieces,
                        domicile: "Maison") == "Chambre")
        p.choisir("Salon", routeur: "HomePod mini chambre", domicile: "Maison")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: Self.pieces,
                        domicile: "Maison") == "Salon")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: Self.pieces,
                        domicile: "Chalet") == "Chambre", "une autre maison")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: ["Chambre"],
                        domicile: "Maison") == "Chambre", "le salon n'est plus dans Maison")
        p.choisir(nil, routeur: "HomePod mini chambre", domicile: "Maison")
        #expect(p == PiecesRouteurs())
    }

    /// La chaine d'un routeur de bordure, une seule fonction (polissage D, section 4.1) : la piece de son accessoire de
    /// Maison, puis le choix garde sous son instance (si sa piece est encore une piece de la maison), puis la regle de son
    /// nom. Elle sert au routeur identifie comme a chaque candidat.
    @Test func chaineDUnRouteur() {
        var p = PiecesRouteurs()
        let maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "HomePod A", piece: "Bureau"),
        ])
        func piece(_ routeur: String, nom: String? = nil, maison m: NomsMaison? = nil, parmi: [String] = Self.pieces,
                   domicile: String = "Maison") -> String? {
            p.piece(routeur: routeur, nom: nom ?? routeur, maison: m, parmi: parmi, domicile: domicile)
        }
        #expect(piece("HomePod chambre") == "Chambre", "la regle du nom")
        #expect(piece("HomePod", nom: "HomePod du salon") == "Salon", "le surnom")
        #expect(piece("HomePod chambre", nom: "HomePod") == nil, "le nom est celui qu'on donne, pas l'instance")
        p.choisir("Entrée", routeur: "HomePod chambre", domicile: "Maison")
        #expect(piece("HomePod chambre") == "Entrée", "le choix avant le nom")
        #expect(piece("HomePod chambre", parmi: ["Chambre"]) == "Chambre", "un choix perime ne compte pas")
        #expect(piece("HomePod chambre", domicile: "Chalet") == "Chambre", "le choix d'une autre maison")
        p.choisir("Salon", routeur: "HomePod A", domicile: "Maison")
        #expect(piece("HomePod A", maison: maison) == "Bureau", "Maison avant le choix")
        #expect(piece("HomePod A") == "Salon", "sans Maison, le choix")
        #expect(piece("HomePod B", maison: maison) == nil, "ni Maison, ni choix, ni piece dans le nom")
    }

    /// Un routeur de bordure non identifie, aux candidats (polissage D, section 4.1) : il va dans leur piece s'ils sont
    /// tous dans la meme ; sinon, ou si l'un n'en a pas, nulle part (« Sans piece »). La piece d'un candidat : celle de
    /// son accessoire de Maison, sinon le choix garde sous son instance, avant la regle de son nom (son surnom, sinon
    /// l'instance).
    @Test func candidats() {
        var p = PiecesRouteurs()
        let maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "HomePod A", piece: "Bureau"), AccessoireMaison(nom: "HomePod B", piece: "Bureau"),
        ])
        func piece(_ c: [String], noms: [String: String] = [:], maison m: NomsMaison? = nil) -> String? {
            p.piece(candidats: c, noms: noms, maison: m, parmi: Self.pieces, domicile: "Maison")
        }
        #expect(piece(["HomePod Salon gauche", "HomePod Salon droit"]) == "Salon", "la meme piece, par le nom")
        #expect(piece(["HomePod Salon", "HomePod mini chambre"]) == nil, "des pieces differentes")
        #expect(piece(["HomePod Salon", "HomePod"]) == nil, "un candidat sans piece")
        #expect(piece(["HomePod"]) == nil && piece([]) == nil)
        #expect(piece(["HomePod"], noms: ["HomePod": "HomePod du salon"]) == "Salon", "le surnom")
        #expect(piece(["HomePod A", "HomePod B"], maison: maison) == "Bureau", "l'accessoire de Maison")
        #expect(piece(["HomePod A", "HomePod Salon"], maison: maison) == nil)
        p.choisir("Chambre", routeur: "HomePod Salon gauche", domicile: "Maison")
        #expect(piece(["HomePod Salon gauche", "HomePod Salon droit"]) == nil, "le choix avant le nom : deux pieces")
        p.choisir("Chambre", routeur: "HomePod Salon droit", domicile: "Maison")
        #expect(piece(["HomePod Salon gauche", "HomePod Salon droit"]) == "Chambre", "le choix avant le nom")
        p.choisir("Chambre", routeur: "HomePod A", domicile: "Maison")
        #expect(piece(["HomePod A", "HomePod B"], maison: maison) == "Bureau", "Maison avant le choix")
        #expect(PiecesRouteurs.pieceDeMaison(routeur: "HomePod A", maison: maison) == "Bureau")
        #expect(PiecesRouteurs.pieceDeMaison(routeur: "HomePod C", maison: maison) == nil)
    }

    /// Pieces de Maison : celles des accessoires et celles des zones, sans doublon ni nom vide.
    @Test func piecesDeLaMaison() {
        let maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Lampe", piece: "Salon"), AccessoireMaison(nom: "Prise", piece: ""),
            AccessoireMaison(nom: "Pont"),
        ], zones: [ZoneMaison(nom: "Étage", pieces: ["Chambre", "Salon"])])
        #expect(PiecesRouteurs.pieces(de: maison) == ["Chambre", "Salon"])
        #expect(PiecesRouteurs.pieces(de: nil).isEmpty)
    }

    /// Aller-retour sur disque ; un fichier absent, illisible ou d'une version plus recente donne des
    /// choix vides.
    @Test func allerRetour() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PiecesRouteurs()
        p.choisir("Salon", routeur: "HomePod Palier", domicile: "Maison")
        p.choisir("Bureau", routeur: "Apple TV", domicile: "")
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url) == p)
        #expect(PiecesRouteurs.lire(url).choix(routeur: "HomePod Palier", domicile: "Maison") == "Salon")
        #expect(PiecesRouteurs.lire(url.appendingPathExtension("absent")) == PiecesRouteurs())
        try Data(#"{"version":2,"maisons":{}}"#.utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
        try Data("pas du json".utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
    }
}
