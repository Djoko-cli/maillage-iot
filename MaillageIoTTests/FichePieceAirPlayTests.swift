import AppKit
import Foundation
import MaillageCoeur
import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

/// La piece que l'annonce AirPlay propose, dans la fiche d'un routeur de bordure que Maison ne place pas (phase 7, tache 2) :
/// la ligne « Piece proposee : <piece> (d'apres AirPlay) », « Placer ici » (le meme choix que « Placer dans une piece… ») et
/// « Ignorer » (retenu jusqu'a ce que le nom AirPlay change) ; et la demo, qui montre la proposition.
@MainActor
@Suite("Fiche : piece proposee par AirPlay")
struct FichePieceAirPlayTests {
    static let domicile = "Maison (démo)"

    /// La demo combinee, avec son Apple TV et son HomePod que Maison ne place pas, et leur annonce AirPlay.
    static func demo() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee, demoAirPlay: true)
        s.demarrer()
        return s
    }

    static func entree(_ s: Surveillance, _ choisies: PiecesChoisies) -> EntreeScene {
        EntreeScene(surveillance: s, places: PlacesGardees(), choix: choisies.choix)
    }

    static func proposition(_ id: String, _ s: Surveillance, _ choisies: PiecesChoisies) -> Proposition? {
        PropositionPiece.pour(idt(id), dans: s, entree: entree(s, choisies), choisies: choisies)
    }

    /// Un dossier a soi pour `pieces-noeuds.json` : jamais le vrai.
    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fiche-airplay-\(UUID().uuidString)/pieces-noeuds.json")
    }

    // MARK: La proposition

    /// L'Apple TV et un HomePod de la demo, que Maison ne place pas, ont une proposition ; ceux que Maison place, un appareil,
    /// un noeud de Zigbee n'en ont pas.
    @Test func propositionPourUnRouteurDeBordureSansPiece() {
        let s = Self.demo()
        let choisies = PiecesChoisies(fichier: nil)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon"))
        #expect(Self.proposition("HomePod Avant", s, choisies) == Proposition(piece: "Cuisine", nomAirPlay: "HomePod Cuisine"))
        #expect(Self.proposition("HomePod Palier", s, choisies) == nil, "Maison le place")
        #expect(Self.proposition("HomePod mini bureau", s, choisies) == nil, "Maison le place")
        #expect(Self.proposition("56B1E064401F74EF", s, choisies) == nil, "un appareil, pas un routeur de bordure")
        let zigbee = PropositionPiece.pour(idt("Apple TV 4K", .zigbee), dans: s, entree: Self.entree(s, choisies), choisies: choisies)
        #expect(zigbee == nil, "pas le meme protocole")
    }

    /// Une piece deja choisie (« Placer dans une piece… ») ecarte la proposition : rien n'ecrase un choix.
    @Test func unChoixEcarteLaProposition() {
        let s = Self.demo()
        let choisies = PiecesChoisies(fichier: nil)
        choisies.choisir("Bureau", .routeur(idt("Apple TV 4K")), domicile: Self.domicile)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == nil)
        choisies.choisir(nil, .routeur(idt("Apple TV 4K")), domicile: Self.domicile)
        #expect(Self.proposition("Apple TV 4K", s, choisies)?.piece == "Salon", "le choix efface, elle revient")
    }

    /// Sans releve AirPlay (la demo d'avant, une vraie maison sans HomePod AirPlay), aucune proposition ; et la demo sans
    /// l'option garde ses trois routeurs places par Maison.
    @Test func sansAirPlayPasDeProposition() throws {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
        s.demarrer()
        let choisies = PiecesChoisies(fichier: nil)
        #expect(try #require(s.thread.dernierReleve).airplay.isEmpty)
        for id in ["Apple TV 4K", "HomePod Avant", "HomePod Palier", "HomePod mini bureau", "HomePod mini chambre"] {
            #expect(Self.proposition(id, s, choisies) == nil, "\(id)")
        }
        let e = Self.entree(s, choisies)
        #expect(e.piecesNoeuds[idt("Apple TV 4K")] == "Salon" && e.piecesNoeuds[idt("HomePod Avant")] == "Salon")
    }

    /// La demo avec AirPlay ne change de la demo des references de rejeu que ces deux routeurs, sans piece : les memes noeuds,
    /// les memes liens, les memes libelles et les memes pieces pour tous les autres.
    @Test func laDemoNeChangeQueDeuxRouteurs() {
        let avec = Self.entree(Self.demo(), PiecesChoisies(fichier: nil))
        let sans = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
        sans.demarrer()
        let origine = Self.entree(sans, PiecesChoisies(fichier: nil))
        #expect(avec.graphe == origine.graphe)
        #expect(avec.libelles == origine.libelles)
        let differents = Set(avec.piecesNoeuds.keys).union(origine.piecesNoeuds.keys)
            .filter { avec.piecesNoeuds[$0] != origine.piecesNoeuds[$0] }
        #expect(differents == [idt("Apple TV 4K"), idt("HomePod Avant")])
        #expect(avec.piecesNoeuds[idt("Apple TV 4K")] == nil && avec.piecesNoeuds[idt("HomePod Avant")] == nil)
    }

    // MARK: Placer ici, Ignorer

    /// « Placer ici » fait ce que fait « Placer dans une piece… » pour cette piece : le meme choix, au meme endroit, sur
    /// disque ; la proposition disparait (le noeud a une piece).
    @Test func placerIci() throws {
        let s = Self.demo()
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ici = PiecesChoisies(fichier: url)
        let proposition = try #require(Self.proposition("Apple TV 4K", s, ici))
        PropositionPiece.placer(proposition, pour: idt("Apple TV 4K"), domicile: Self.domicile, choisies: ici)
        // Le menu : le meme noeud, la meme piece.
        let urlMenu = Self.fichier()
        defer { try? FileManager.default.removeItem(at: urlMenu.deletingLastPathComponent()) }
        let menu = PiecesChoisies(fichier: urlMenu)
        let placement = try #require(PiecesChoisies.placement(idt("Apple TV 4K"), dans: s, entree: Self.entree(s, menu)))
        MenuPlacer(placement: placement, domicile: Self.domicile, choisies: menu).selection.wrappedValue = proposition.piece
        #expect(ici.choix == menu.choix)
        #expect(try Data(contentsOf: url) == Data(contentsOf: urlMenu))
        #expect(PiecesChoisies(fichier: url).choix.choix(routeur: idt("Apple TV 4K"), domicile: Self.domicile) == "Salon")
        #expect(Self.proposition("Apple TV 4K", s, ici) == nil, "placee : plus de proposition")
        #expect(Self.entree(s, ici).piecesNoeuds[idt("Apple TV 4K")] == "Salon", "et la scene l'a rangee au salon")
        #expect(Self.proposition("HomePod Avant", s, ici)?.piece == "Cuisine", "l'autre n'est pas touche")
    }

    /// « Ignorer » cache la proposition et se retient, sur disque, pour ce routeur seul.
    @Test func ignorerCacheEtPersiste() throws {
        let s = Self.demo()
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let choisies = PiecesChoisies(fichier: url)
        let proposition = try #require(Self.proposition("Apple TV 4K", s, choisies))
        PropositionPiece.ignorer(proposition, pour: idt("Apple TV 4K"), domicile: Self.domicile, choisies: choisies)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == nil)
        #expect(Self.proposition("HomePod Avant", s, choisies) != nil, "l'autre routeur garde la sienne")
        let relu = PiecesChoisies(fichier: url)
        #expect(Self.proposition("Apple TV 4K", s, relu) == nil, "meme apres un relancement")
        #expect(relu.choix.choix(routeur: idt("Apple TV 4K"), domicile: Self.domicile) == nil, "ignorer ne place rien")
        // Une autre maison ne la connait pas.
        #expect(relu.airPlayIgnore(idt("Apple TV 4K"), domicile: "Chalet") == nil)
    }

    /// Ignoree, la proposition ne revient pas tant que le nom AirPlay est le meme (un releve de plus) ; il change, elle revient.
    @Test func unNomChangeLaFaitRevenir() throws {
        let s = Self.demo()
        let choisies = PiecesChoisies(fichier: nil)
        let proposition = try #require(Self.proposition("Apple TV 4K", s, choisies))
        PropositionPiece.ignorer(proposition, pour: idt("Apple TV 4K"), domicile: Self.domicile, choisies: choisies)
        var releve = try #require(s.thread.dernierReleve)
        releve.date = releve.date.addingTimeInterval(60)
        s.thread.integrer(releve)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == nil, "un releve de plus, le meme nom")
        // L'Apple TV change de nom dans Maison : une autre piece, un autre nom AirPlay.
        releve.date = releve.date.addingTimeInterval(60)
        releve.airplay = releve.airplay.map { a in
            a.instance == "Apple TV Salon" ? AnnonceService(instance: "Apple TV Bureau", hote: a.hote, port: a.port, txt: a.txt) : a
        }
        s.thread.integrer(releve)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == Proposition(piece: "Bureau", nomAirPlay: "Apple TV Bureau"))
        // Meme piece sous un autre nom : le nom a change, elle revient aussi.
        PropositionPiece.ignorer(try #require(Self.proposition("Apple TV 4K", s, choisies)), pour: idt("Apple TV 4K"),
                                 domicile: Self.domicile, choisies: choisies)
        releve.date = releve.date.addingTimeInterval(60)
        releve.airplay = releve.airplay.map { a in
            a.instance == "Apple TV Bureau" ? AnnonceService(instance: "Salon Apple TV", hote: a.hote, port: a.port, txt: a.txt) : a
        }
        s.thread.integrer(releve)
        #expect(Self.proposition("Apple TV 4K", s, choisies) == Proposition(piece: "Salon", nomAirPlay: "Salon Apple TV"))
    }

    // MARK: La fiche

    /// Les textes que la fiche montre, mot pour mot, dans la langue du lancement des tests.
    @Test func textesFrancaisEtAnglais() throws {
        let francais = ThreadRouteTests.langue == "fr"
        guard francais || ThreadRouteTests.langue == "en" else {
            throw ThreadRouteTests.ErreurLangue(langue: ThreadRouteTests.langue)
        }
        let p = Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon")
        #expect(PropositionPiece.texte(p) == (francais ? "Pièce proposée : Salon (d'après AirPlay)"
                                                       : "Suggested room: Salon (from AirPlay)"))
        #expect(String(localized: "Placer ici") == (francais ? "Placer ici" : "Place here"))
        #expect(String(localized: "Ignorer") == (francais ? "Ignorer" : "Ignore"))
    }

    static func fiche(_ id: String, _ s: Surveillance, _ choisies: PiecesChoisies) -> some View {
        FicheNoeud(id: idt(id), entree: entree(s, choisies), instant: s.maintenant(de: .thread, a: Date()),
                   aRenommer: .constant(nil), fermer: {})
            .environment(s)
            .environment(choisies)
    }

    /// La taille de la fiche de `id` a la largeur de la fenetre par defaut, et son image.
    static func rendu(_ id: String, _ s: Surveillance, _ choisies: PiecesChoisies) -> (taille: CGSize, image: Data?) {
        let vue = fiche(id, s, choisies).frame(width: 1000)
        return (NSHostingView(rootView: vue).fittingSize, ImageRenderer(content: vue).nsImage?.tiffRepresentation)
    }

    /// La ligne et ses boutons paraissent dans la fiche du routeur sans piece qui a une proposition (la fiche est plus haute, et
    /// autre), et nulle part ailleurs ; placee ou ignoree, elle repart (la fiche redevient celle d'un routeur sans proposition).
    @Test func laLigneParaitDansLaFiche() throws {
        let s = Self.demo()
        let choisies = PiecesChoisies(fichier: nil)
        let avec = Self.rendu("Apple TV 4K", s, choisies)
        // Le meme routeur, sa proposition ignoree : la fiche sans la ligne.
        PropositionPiece.ignorer(Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon"), pour: idt("Apple TV 4K"),
                                 domicile: Self.domicile, choisies: choisies)
        let sans = Self.rendu("Apple TV 4K", s, choisies)
        #expect(avec.taille.height > sans.taille.height, "\(avec.taille) contre \(sans.taille)")
        #expect(avec.image != nil && avec.image != sans.image)
        // Placee, de meme.
        let placee = PiecesChoisies(fichier: nil)
        PropositionPiece.placer(Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon"), pour: idt("Apple TV 4K"),
                                domicile: Self.domicile, choisies: placee)
        #expect(Self.rendu("Apple TV 4K", s, placee).taille.height < avec.taille.height)
        // Maison place ce HomePod : pas de ligne, pas de bouton ; ignorer pour lui ne change rien.
        let palier = Self.rendu("HomePod Palier", s, PiecesChoisies(fichier: nil))
        let apres = PiecesChoisies(fichier: nil)
        apres.ignorerAirPlay("HomePod Salon", idt("HomePod Palier"), domicile: Self.domicile)
        #expect(Self.rendu("HomePod Palier", s, apres).taille == palier.taille)
        // La ligne seule : plus haute qu'un routeur sans proposition, de la hauteur de ses deux lignes.
        let ligne = LignePropositionPiece(proposition: Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon"),
                                          placer: {}, ignorer: {})
        #expect(NSHostingView(rootView: ligne.frame(width: 300)).fittingSize.height > 30)
    }

    /// Les images de la fiche pour la relecture : avec `TEST_RUNNER_CAPTURES_T2=1`, le journal des tests porte chacune en PNG
    /// base64 (`CAPTURE-T2 <nom> <donnees>` : l'app hote est en bac a sable, elle n'ecrit pas dans le depot) ; rendu de capture,
    /// comme `CapturesPieces` (sombre, sans verre). Sans la variable, rien n'est rendu.
    @Test func imagesDeLaFiche() throws {
        guard ProcessInfo.processInfo.environment["CAPTURES_T2"] != nil else { return }
        let s = Self.demo()
        let choisies = PiecesChoisies(fichier: nil)
        func ecrire(_ nom: String, _ id: String) throws {
            let vue = Self.fiche(id, s, choisies)
                .environment(\.capturePieces, true)
                .environment(\.colorScheme, .dark)
                .frame(width: 1000)
                .padding(24)
                .background(Color(red: 0.07, green: 0.09, blue: 0.16))
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 2
            let image = try #require(rendu.cgImage)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            print("CAPTURE-T2 \(nom) \(png.base64EncodedString())")
        }
        try ecrire("fiche-apple-tv-proposition", "Apple TV 4K")
        try ecrire("fiche-homepod-avant-proposition", "HomePod Avant")
        try ecrire("fiche-homepod-palier-sans-proposition", "HomePod Palier")
        PropositionPiece.ignorer(Proposition(piece: "Salon", nomAirPlay: "Apple TV Salon"), pour: idt("Apple TV 4K"),
                                 domicile: Self.domicile, choisies: choisies)
        try ecrire("fiche-apple-tv-ignoree", "Apple TV 4K")
        PropositionPiece.placer(Proposition(piece: "Cuisine", nomAirPlay: "HomePod Cuisine"), pour: idt("HomePod Avant"),
                                domicile: Self.domicile, choisies: choisies)
        try ecrire("fiche-homepod-avant-placee", "HomePod Avant")
    }
}
