import AppKit
import Foundation
@testable import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

/// « Ranger dans la zone… », au clic droit sur une piece (phase 10, tache 2) : la cible du clic droit, le menu natif de la
/// piece, le choix garde dans les places, et la cle de la piece qui tient quand la scene change.
@MainActor
@Suite("Vue par pieces : ranger une piece dans une de ses zones")
struct MenuZonesPieceTests {
    static let rdc = "zone:Rez-de-chaussée", jardin = "zone:Jardin", etage = "zone:Étage", combles = "zone:Combles"

    /// Les zones de la demo : la chambre est dans l'etage (2 pieces) et dans les combles (5) ; le salon dans une seule zone ;
    /// la cuisine dans aucune.
    static let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Buanderie"]),
                        ZoneMaison(nom: "Jardin", pieces: ["Entrée", "Terrasse", "Abri"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Salle de bain"]),
                        ZoneMaison(nom: "Combles", pieces: ["Bureau", "Chambre d'amis", "Grenier", "Salle de jeux", "Chambre"])]

    /// La demo sur ces zones, avec les places `places` (comme la fenetre refait la scene a chaque changement des places).
    static func scene(_ places: PlacesGardees = PlacesGardees()) throws -> EntreeScene {
        let (s, r, _) = try NomsSceneTests.demo()
        var maison = try #require(s.thread.noms.maison)
        maison.zones = zones
        s.thread.noms.maison = maison
        return EntreeScene(surveillance: s, reseau: r, places: places)
    }

    /// Un moteur sur cette scene, ses places dans `fichier` (jamais le vrai fichier), une premiere image dessinee.
    static func moteur(_ fichier: URL, places: PlacesGardees = PlacesGardees()) throws -> (MoteurPieces, EntreeScene) {
        let e = try scene(places)
        let m = MoteurPieces(troisD: false, fichierPlaces: fichier)
        m.marges = (84, 50)
        m.poserTaille(MoteurPiecesTests.taille)
        m.installerMaintenant(e)
        for _ in 0..<2 { MoteurPiecesTests.dessiner(m) }
        return (m, e)
    }

    /// Le nom de la zone ou la scene range la piece de Maison `nom`.
    static func zone(de nom: String, dans e: EntreeScene?) -> String? {
        guard let s = e?.scene, let p = s.pieces.first(where: { $0.nom == .maison(nom) }) else { return nil }
        return s.etages[p.etage].nom.cle
    }

    // MARK: La cible du clic droit

    /// Un clic droit sur une piece donne sa cle (avant : rien) ; sur un appareil, toujours rien ; le nom d'un etage, un
    /// disque et le fond ne changent pas.
    @Test func cibleDUnePiece() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        for nom in ["Chambre", "Salon", "Cuisine"] {
            let point = try MoteurPiecesTests.pointDePiece(m, try MoteurPiecesTests.indice(e, nom))
            #expect(m.cible(en: point) == .piece("piece:" + nom), "la piece \(nom)")
        }
        let pastille = try #require(m.projetee?.disques.first { $0.opacite > 0.5 })
        #expect(m.cible(en: pastille.centre) == .aucune, "un appareil")
        for k in e.scene.etages.indices {
            let et = e.scene.etages[k].id
            #expect(m.cible(en: try IsolementTests.nomDEtage(m, k)) == .etage(et), "le nom de \(et)")
            #expect(m.cible(en: try IsolementTests.pointDeDisque(m, k)) == .etage(et), "le disque de \(et)")
        }
        #expect(m.cible(en: CGPoint(x: 3, y: MoteurPiecesTests.taille.height - 3)) == .fond)
    }

    // MARK: Le menu d'une piece

    /// Le menu d'une piece : son nom, les zones qui la contiennent dans l'ordre de Maison, « Automatiquement » coche tant
    /// qu'aucun choix ne s'applique ; le sous-menu est grise pour une piece d'une seule zone ou d'aucune.
    @Test func menuDUnePiece() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        typealias Z = MenuPiece.Zone
        #expect(m.menuPiece("piece:Chambre") == MenuPiece(nom: "Chambre", automatique: true,
                                                          zones: [Z(nom: "Étage", coche: false), Z(nom: "Combles", coche: false)]))
        #expect(m.menuPiece("piece:Chambre")?.peutRanger == true)
        #expect(m.menuPiece("piece:Salon") == MenuPiece(nom: "Salon", automatique: true,
                                                        zones: [Z(nom: "Rez-de-chaussée", coche: false)]))
        #expect(m.menuPiece("piece:Salon")?.peutRanger == false, "une seule zone")
        #expect(m.menuPiece("piece:Cuisine") == MenuPiece(nom: "Cuisine", automatique: true, zones: []))
        #expect(m.menuPiece("piece:Cuisine")?.peutRanger == false, "aucune zone")
        #expect(m.menuPiece("piece:Inconnue") == nil)
        // Un choix qui s'applique : la zone choisie est cochee, « Automatiquement » ne l'est plus.
        var places = PlacesGardees()
        places.choisirZone("Combles", piece: "Chambre", domicile: e.domicile)
        m.installerMaintenant(try Self.scene(places))
        #expect(m.menuPiece("piece:Chambre") == MenuPiece(nom: "Chambre", automatique: false,
                                                          zones: [Z(nom: "Étage", coche: false), Z(nom: "Combles", coche: true)]))
        // Un choix perime (la piece n'est plus dans cette zone) est ignore : « Automatiquement » est coche.
        places.choisirZone("Jardin", piece: "Chambre", domicile: e.domicile)
        m.installerMaintenant(try Self.scene(places))
        #expect(m.menuPiece("piece:Chambre")?.automatique == true && m.menuPiece("piece:Chambre")?.zones.contains { $0.coche } == false)
    }

    /// Le menu natif, tel qu'AppKit le demande a la vue hebergee ou `MenuPieces` est pose comme dans `VuePieces` : le nom de la
    /// piece en tete, grise ; « Ranger dans la zone… » et son sous-menu. Chaque article range la chambre, le choix est garde
    /// dans le fichier ; rouvert apres la scene de ce choix, le menu suit les coches.
    @Test(.timeLimit(.minutes(1))) func menuNatif() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        func gardees() -> [String: String] { PlacesGardees.lire(url).zonesChoisies(e.domicile) }
        let hote = NSHostingView(rootView: HoteMenu(moteur: m))
        let fenetre = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 300, height: 300), styleMask: [.titled],
                               backing: .buffered, defer: false)
        fenetre.isReleasedWhenClosed = false
        fenetre.contentView = hote
        fenetre.orderFrontRegardless()
        defer { FenetrePiecesTests.fermer(fenetre) }
        hote.layoutSubtreeIfNeeded()
        var numero = 0
        func clicDroit() -> NSMenu? {
            numero += 1
            let clic = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 150, y: 150), modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: fenetre.windowNumber, context: nil, eventNumber: numero,
                                          clickCount: 1, pressure: 1)
            return clic.flatMap { hote.menu(for: $0) }
        }
        // Les articles, comme Djoko les voit : le titre, « ✓ » coche, « (grise) » grise ; sans les separateurs.
        func lire(_ mn: NSMenu?) -> [String] {
            (mn?.items ?? []).filter { !$0.isSeparatorItem }.map { a in
                a.title + (a.state == .on ? " ✓" : "") + (a.isEnabled ? "" : " (grise)")
            }
        }
        let ranger = String(localized: "Ranger dans la zone…"), auto = String(localized: "Automatiquement")
        func sousMenu(_ mn: NSMenu?) -> NSMenu? { mn?.items.first { $0.title == ranger }?.submenu }
        // Le menu, des qu'il se lit comme `attendu` (et son sous-menu comme `sous`, quand on l'attend) : SwiftUI le refait a sa
        // prochaine mise a jour.
        func rouvrir(_ attendu: [String], sous: [String]? = nil) async throws -> NSMenu? {
            func bon(_ mn: NSMenu) -> Bool { lire(mn) == attendu && (sous == nil || lire(sousMenu(mn)) == sous) }
            for _ in 0..<300 {
                if let mn = clicDroit(), bon(mn) { return mn }
                try await Task.sleep(for: .milliseconds(10))
            }
            return clicDroit()
        }
        // Un choix : l'article declenche, puis la scene de ce choix, que la fenetre remet au moteur (`recevoir`).
        func choisir(_ titre: String, dans mn: NSMenu?) throws {
            let mn = try #require(mn, "le menu de « \(titre) »")
            let i = try #require(mn.items.firstIndex { $0.title == titre }, "l'article « \(titre) »")
            mn.performActionForItem(at: i)
            m.recevoir(try Self.scene(m.places))
        }
        let tete = ["Chambre (grise)", ranger]
        // Le menu de la chambre : son nom en tete, grise ; le sous-menu actif, « Automatiquement » coche.
        m.survoler(try MoteurPiecesTests.pointDePiece(m, try MoteurPiecesTests.indice(e, "Chambre")))
        #expect(m.cibleMenu == .piece("piece:Chambre"))
        var mn = try await rouvrir(tete, sous: [auto + " ✓", "Étage", "Combles"])
        #expect(lire(mn) == tete)
        #expect(lire(sousMenu(mn)) == [auto + " ✓", "Étage", "Combles"])
        #expect(sousMenu(mn)?.items.contains { $0.isSeparatorItem } == true, "un separateur entre « Automatiquement » et les zones")
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.etage, "la zone la plus precise")
        // Un choix : les combles.
        try choisir("Combles", dans: sousMenu(mn))
        #expect(gardees() == ["Chambre": "Combles"], "le choix, garde dans le fichier")
        try await MoteurPiecesTests.attendre { Self.zone(de: "Chambre", dans: m.entree) == Self.combles }
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.combles, "la disposition suit, calculee hors du fil principal")
        mn = try await rouvrir(tete, sous: [auto, "Étage", "Combles ✓"])
        #expect(lire(sousMenu(mn)) == [auto, "Étage", "Combles ✓"], "rouvert : la zone choisie cochee")
        // Un autre : l'etage.
        try choisir("Étage", dans: sousMenu(mn))
        #expect(gardees() == ["Chambre": "Étage"])
        mn = try await rouvrir(tete, sous: [auto, "Étage ✓", "Combles"])
        #expect(lire(sousMenu(mn)) == [auto, "Étage ✓", "Combles"])
        // « Automatiquement » : le choix est oublie.
        try choisir(auto, dans: sousMenu(mn))
        #expect(gardees().isEmpty, "le choix oublie")
        mn = try await rouvrir(tete, sous: [auto + " ✓", "Étage", "Combles"])
        #expect(lire(sousMenu(mn)) == [auto + " ✓", "Étage", "Combles"])
        // Une piece d'une seule zone, une piece sans zone : le sous-menu est grise.
        // SwiftUI grise un sous-menu en grisant tous ses articles (l'article parent reste actif pour AppKit).
        for (nom, zone) in [("Salon", ["Rez-de-chaussée (grise)"]), ("Cuisine", [])] {
            let sous = [auto + " ✓ (grise)"] + zone
            m.survoler(try MoteurPiecesTests.pointDePiece(m, try MoteurPiecesTests.indice(e, nom)))
            let menu = try await rouvrir([nom + " (grise)", ranger], sous: sous)
            #expect(lire(menu) == [nom + " (grise)", ranger])
            #expect(lire(sousMenu(menu)) == sous, "\(nom) : tous les articles du sous-menu sont grises")
        }
    }

    // MARK: Le choix garde

    /// `rangerPiece` : la piece passe dans la zone choisie, le choix est ecrit dans les places (fichier de test), il survit a
    /// une nouvelle scene et a un nouveau moteur ; « Automatiquement » l'oublie, la zone la plus precise revient. Une zone qui
    /// ne contient pas la piece, une piece inconnue : rien.
    @Test func rangerPiece() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        func gardees() -> [String: String] { PlacesGardees.lire(url).zonesChoisies(e.domicile) }
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.etage && gardees().isEmpty)
        m.rangerPiece("piece:Chambre", dans: "Combles")
        #expect(gardees() == ["Chambre": "Combles"], "le choix est ecrit")
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.combles, "la scene suivante le prend")
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.combles, "une autre scene aussi")
        #expect(MoteurPieces(fichierPlaces: url).places.zonesChoisies(e.domicile) == ["Chambre": "Combles"], "un autre lancement")
        // Rien : une zone qui ne contient pas la piece, une piece inconnue.
        m.rangerPiece("piece:Chambre", dans: "Jardin")
        m.rangerPiece("piece:Inconnue", dans: "Combles")
        m.rangerPiece("Chambre", dans: "Etage")
        #expect(gardees() == ["Chambre": "Combles"], "ni une zone etrangere, ni une piece inconnue")
        // « Automatiquement » : le choix est oublie, la regle de la zone la plus precise revient.
        m.rangerPiece("piece:Chambre", dans: nil)
        #expect(gardees().isEmpty)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.etage)
    }

    /// Un choix fait pendant qu'une scene attend (un vol, le calcul de sa disposition) : le menu de la scene la plus recente
    /// le porte, le moteur n'ecrit que ce choix.
    @Test func choixPendantQuUneSceneAttend() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        m.allerEtage(try IsolementTests.indiceEtage(e, Self.jardin))
        m.rangerPiece("piece:Chambre", dans: "Combles")
        m.recevoir(try Self.scene(m.places))
        #expect(m.entree == e && m.enMouvement, "la scene du choix attend")
        #expect(m.menuPiece("piece:Chambre")?.zones.map(\.coche) == [false, true], "le menu suit le choix")
    }

    /// La cible garde la cle de la piece : une scene qui change l'ordre des plateaux pendant que le menu est ouvert (les
    /// indices des pieces changent) ne fait pas ranger une autre piece.
    @Test func cibleDeCle() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        let avant = try MoteurPiecesTests.indice(e, "Chambre")
        m.survoler(try MoteurPiecesTests.pointDePiece(m, avant))
        guard case .piece(let cle) = m.cibleMenu else {
            Issue.record("le clic droit sur une piece donne sa cle")
            return
        }
        // La scene suivante range les plateaux dans un autre ordre : la chambre a un autre indice.
        var places = m.places
        places.ranger(Rangement(ordre: [Self.combles, Self.etage, Self.jardin, Self.rdc], aCote: [:]), domicile: e.domicile)
        let autre = try Self.scene(places)
        #expect(try MoteurPiecesTests.indice(autre, "Chambre") != avant, "la chambre change d'indice")
        m.places = places
        m.installerMaintenant(autre)
        #expect(m.menuPiece(cle)?.nom == "Chambre", "le menu vise toujours la chambre")
        m.rangerPiece(cle, dans: "Combles")
        #expect(PlacesGardees.lire(url).zonesChoisies(e.domicile) == ["Chambre": "Combles"], "la chambre, et elle seule")
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Chambre", dans: m.entree) == Self.combles)
        #expect(Self.zone(de: "Salon", dans: m.entree) == Self.rdc, "les autres pieces ne bougent pas")
    }

    // MARK: Textes

    /// Les textes, en francais et en anglais (le catalogue de l'app).
    @Test func textes() {
        let en = Bundle.main.preferredLocalizations.first == "en"
        #expect(String(localized: "Ranger dans la zone…") == (en ? "Move to Zone…" : "Ranger dans la zone…"))
        #expect(String(localized: "Automatiquement") == (en ? "Automatically" : "Automatiquement"))
    }
}
