import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : piece des routeurs que Maison ne place pas")
struct PiecesRouteursTests {
    /// Pieces d'une maison inventee.
    static let pieces = ["Bureau", "Chambre", "Chambre d'amis", "Entrée", "Salle de bain", "Salon"]

    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-noeuds.json")
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
        p.choisir("Salon", routeur: idt("HomePod mini chambre"), domicile: "Maison")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: Self.pieces,
                        domicile: "Maison") == "Salon")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: Self.pieces,
                        domicile: "Chalet") == "Chambre", "une autre maison")
        #expect(p.piece(routeur: "HomePod mini chambre", nom: "HomePod mini chambre", parmi: ["Chambre"],
                        domicile: "Maison") == "Chambre", "le salon n'est plus dans Maison")
        p.choisir(nil, routeur: idt("HomePod mini chambre"), domicile: "Maison")
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
        p.choisir("Entrée", routeur: idt("HomePod chambre"), domicile: "Maison")
        #expect(piece("HomePod chambre") == "Entrée", "le choix avant le nom")
        #expect(piece("HomePod chambre", parmi: ["Chambre"]) == "Chambre", "un choix perime ne compte pas")
        #expect(piece("HomePod chambre", domicile: "Chalet") == "Chambre", "le choix d'une autre maison")
        p.choisir("Salon", routeur: idt("HomePod A"), domicile: "Maison")
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
        p.choisir("Chambre", routeur: idt("HomePod Salon gauche"), domicile: "Maison")
        #expect(piece(["HomePod Salon gauche", "HomePod Salon droit"]) == nil, "le choix avant le nom : deux pieces")
        p.choisir("Chambre", routeur: idt("HomePod Salon droit"), domicile: "Maison")
        #expect(piece(["HomePod Salon gauche", "HomePod Salon droit"]) == "Chambre", "le choix avant le nom")
        p.choisir("Chambre", routeur: idt("HomePod A"), domicile: "Maison")
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
        p.choisir("Salon", routeur: idt("HomePod Palier"), domicile: "Maison")
        p.choisir("Bureau", routeur: idt("Apple TV"), domicile: "")
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url) == p)
        #expect(PiecesRouteurs.lire(url).choix(routeur: idt("HomePod Palier"), domicile: "Maison") == "Salon")
        #expect(PiecesRouteurs.lire(url.appendingPathExtension("absent")) == PiecesRouteurs())
        try Data(#"{"version":3,"maisons":{}}"#.utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
        try Data("pas du json".utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
    }

    /// Un fichier ecrit par Maillage Zigbee 1.1.1 (`pieces-routeurs.json` version 1) n'a que `appareils` (ni `maisons`) : il
    /// se lit, avec ses choix sous le protocole de l'app (Zigbee), et s'ecrit au nouveau format sans perte. Un `maisons`
    /// mal forme n'est pas lu, comme avant ; sans `appareils`, la version seule donne un fichier vide, mais lisible.
    @Test func fichierSansMaisonsLisible() throws {
        let url = Self.fichier()
        let ancien = url.deletingLastPathComponent().appendingPathComponent("pieces-routeurs.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let zigbee = """
        {
          "appareils" : {
            "" : {
              "0000000000000001" : "Salon"
            },
            "Maison" : {
              "0000000000000002" : "Bureau"
            }
          },
          "version" : 1
        }
        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(zigbee.utf8).write(to: ancien)
        let lu = PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .zigbee)
        #expect(lu.maisons.isEmpty && lu.version == 2)
        #expect(lu.choix(appareil: idz("0000000000000001"), domicile: "") == "Salon")
        #expect(lu.choix(appareil: idz("0000000000000002"), domicile: "Maison") == "Bureau")
        try lu.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url) == lu, "ecrit puis relu : les memes choix")
        try Data(#"{"version":1}"#.utf8).write(to: ancien)
        try FileManager.default.removeItem(at: url)
        #expect(PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .zigbee) == PiecesRouteurs())
    }

    /// `pieces-routeurs.json` version 1 (Maillage Thread 1.3 : routeurs sous leur instance, autres noeuds sous leur ExtMac)
    /// se relit par `pieces-noeuds.json` absent : les cles brutes prennent le protocole de l'app ; le fichier de la
    /// version 2 ecrit ensuite est celui qu'on relit, l'ancien n'est plus consulte. Une ecriture n'efface pas l'ancien.
    @Test func piecesRouteursVersion1Relu() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let ancien = d.appendingPathComponent("pieces-routeurs.json")
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let v1 = #"{"appareils":{"Maison":{"AAAA000000000001":"Salon","bbbb000000000002":"Bureau"}},"maisons":{"Maison":{"HomePod 1":"Cuisine"}},"version":1}"#
        try Data(v1.utf8).write(to: ancien)
        let lu = PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .thread)
        #expect(lu.version == 2)
        #expect(lu.maisons == ["Maison": [idt("HomePod 1"): "Cuisine"]])
        #expect(lu.appareils == ["Maison": [idt("AAAA000000000001"): "Salon", idt("BBBB000000000002"): "Bureau"]],
                "l'ExtMac se lit en majuscules")
        #expect(PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .zigbee).appareils["Maison"]?.keys.first?.protocole
                == .zigbee, "le protocole de l'app")
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs(), "sans l'ancien : rien")
        try lu.ecrire(dans: url)
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(texte.contains(#""version" : 2"#) && texte.contains(#""thread:HomePod 1" : "Cuisine""#)
                && texte.contains(#""thread:AAAA000000000001" : "Salon""#), "\(texte)")
        #expect(try Data(contentsOf: ancien) == Data(v1.utf8), "l'ancien fichier n'est pas touche")
        // Ecrit sur un `pieces-noeuds.json` plus recent, le nouveau n'est pas remplace par l'ancien relu.
        try Data(#"{"version":3}"#.utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .thread) == PiecesRouteurs(),
                "un fichier plus recent ne retombe pas sur l'ancien")
    }

    /// Un `pieces-routeurs.json` version 1 a la main avec deux ExtMac qui ne different que par la casse : ils se
    /// rejoignent en majuscules. La lecture ne plante pas ; le choix garde est toujours le meme (celui de la cle la
    /// plus petite par ordre des octets, donc la majuscule avant la minuscule), jamais celui d'un ordre de hachage.
    @Test func piecesRouteursVersion1CleEnDouble() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("v1-double-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let ancien = d.appendingPathComponent("pieces-routeurs.json")
        let url = d.appendingPathComponent("pieces-noeuds.json")
        let v1 = #"{"appareils":{"Maison":{"aaaa000000000001":"Bureau","AAAA000000000001":"Salon","cccc000000000003":"Cave"}},"version":1}"#
        try Data(v1.utf8).write(to: ancien)
        for _ in 0..<20 {
            let lu = PiecesRouteurs.lire(url, ancien: ancien, protocoleParDefaut: .thread)
            #expect(lu.appareils == ["Maison": [idt("AAAA000000000001"): "Salon", idt("CCCC000000000003"): "Cave"]])
        }
    }

    /// Aller-retour sur disque des choix d'un noeud autre qu'un routeur de bordure (sous son ExtMac, en majuscules) ;
    /// un fichier absent, illisible ou d'une version plus recente donne des choix vides (repris de Maillage Zigbee).
    @Test func allerRetourDesAppareils() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: idt("A000000000000010"), domicile: "Maison")
        p.choisir("Bureau", appareil: idz("A000000000000001"), domicile: "")
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url) == p)
        #expect(PiecesRouteurs.lire(url).choix(appareil: idt("A000000000000010"), domicile: "Maison") == "Salon")
        #expect(PiecesRouteurs.lire(url).choix(appareil: idz("A000000000000001"), domicile: "") == "Bureau")
        #expect(PiecesRouteurs.lire(url).choix(appareil: idt("A000000000000001"), domicile: "") == nil,
                "le meme texte sous un autre protocole est un autre noeud")
        #expect(PiecesRouteurs.lire(url).choix(appareil: idt("a000000000000010"), domicile: "Maison") == "Salon", "majuscules")
        #expect(PiecesRouteurs.lire(url.appendingPathExtension("absent")) == PiecesRouteurs())
        try Data(#"{"version":3,"appareils":{}}"#.utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
        try Data("pas du json".utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
    }
}
