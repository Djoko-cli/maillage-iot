import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// Apres un choix fait dans la vue (« Ranger dans la zone… », les choix de niveau du menu d'un plateau), les plateaux
/// inchanges gardent leur place (phase 11, tache 1) : `DispositionPieces` est global, donc sans cela les pieces des autres
/// plateaux se rearrangent. Au lancement et apres un changement venu de Maison, la disposition reste calculee librement.
@MainActor
@Suite("Vue par pieces : les plateaux inchanges gardent leur place")
struct PlateauxInchangesTests {
    static let z1 = "zone:Zone 1", z2 = "zone:Zone 2", z3 = "zone:Zone 3", z4 = "zone:Zone 4"

    /// Les pieces de la Zone 1 (la demo n'en a pas d'autres a lui donner) : l'Abri est aussi seul dans la Zone 2.
    static let piecesZone1 = ["Salon", "Cuisine", "Buanderie", "Entrée", "Terrasse", "Abri"]

    /// La demo sur quatre zones inventees : la Zone 1 (plusieurs pieces), la Zone 2 (l'Abri seul, aussi dans la Zone 1), les
    /// Zones 3 et 4 (les autres pieces) ; `places` : les places gardees ; `zone1` : les pieces de la Zone 1.
    static func scene(_ places: PlacesGardees = PlacesGardees(), zone1: [String] = piecesZone1) throws -> EntreeScene {
        let (s, r, _) = try NomsSceneTests.demo()
        var maison = try #require(s.thread.noms.maison)
        maison.zones = [ZoneMaison(nom: "Zone 1", pieces: zone1),
                        ZoneMaison(nom: "Zone 2", pieces: ["Abri"]),
                        ZoneMaison(nom: "Zone 3", pieces: ["Chambre", "Salle de bain"]),
                        ZoneMaison(nom: "Zone 4", pieces: ["Bureau", "Chambre d'amis", "Grenier", "Salle de jeux"])]
        s.thread.noms.maison = maison
        return EntreeScene(surveillance: s, reseau: r, places: places)
    }

    /// Un moteur sur cette scene, la Zone 2 a cote de la Zone 1 et hors de la maison, ses places dans `fichier` (jamais le
    /// vrai fichier) ; une premiere image dessinee. L'Abri est dans la Zone 2 (la plus precise).
    static func moteur(_ fichier: URL) throws -> (MoteurPieces, EntreeScene) {
        let base = try scene()
        var places = PlacesGardees()
        places.ranger(Rangement(ordre: [z1, z2, z3, z4], aCote: [z2: PlacesGardees.ACote(etage: z1, dehors: true)]),
                      domicile: base.domicile)
        try places.ecrire(dans: fichier)
        let e = try scene(places)
        let m = MoteurPieces(troisD: false, fichierPlaces: fichier)
        m.marges = (84, 50)
        m.poserTaille(MoteurPiecesTests.taille)
        m.installerMaintenant(e)
        for _ in 0..<2 { MoteurPiecesTests.dessiner(m) }
        return (m, e)
    }

    /// Les positions locales, par cle de piece, des pieces de la scene posee qui sont dans les plateaux `zones`.
    static func positions(_ m: MoteurPieces, de zones: [String]) -> [String: SIMD2<Double>] {
        guard let s = m.entree?.scene else { return [:] }
        var r: [String: SIMD2<Double>] = [:]
        for (i, p) in s.pieces.enumerated() where zones.contains(s.etages[p.etage].id) { r[p.id] = m.positions[i] }
        return r
    }

    /// Le nom de la zone ou la scene posee range la piece de Maison `nom`.
    static func zone(de nom: String, dans m: MoteurPieces) -> String? {
        guard let s = m.entree?.scene, let p = s.pieces.first(where: { $0.nom == .maison(nom) }) else { return nil }
        return s.etages[p.etage].id
    }

    /// Les positions que donne le calcul libre de `DispositionPieces` pour la scene posee, avec les seules places gardees a
    /// la main : ce que donnerait un calcul sans marque.
    static func libre(_ m: MoteurPieces) throws -> [SIMD2<Double>] {
        let e = try #require(m.entree)
        return DispositionPieces(scene: e.scene, cartes: m.cartes, fixees: m.places.fixees(e.scene, domicile: e.domicile)).positions
    }

    // MARK: Apres « Ranger dans la zone… »

    /// Le temoin de `rangerPieceGardeLesPlateauxInchanges` : sur cette scene, le calcul libre de l'aller deplace des pieces des
    /// Zones 3 et 4 ; sans la marque, elles bougeraient. En francais seulement : les cartes dependent de la largeur des noms
    /// mesures, et en anglais le calcul libre de cette scene laisse ces plateaux en place par hasard (passe anglaise du
    /// 23/10). Le comportement, lui, est verifie dans les deux langues.
    @Test(.enabled(if: Locale.preferredLanguages.first?.hasPrefix("fr") ?? false))
    func temoinLeCalculLibreRearrangeLesZones3Et4() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        m.installerMaintenant(try Self.scene(m.places))
        let libre = try Self.libre(m)
        let s = try #require(m.entree?.scene)
        let deplacees = s.pieces.indices.filter {
            [Self.z3, Self.z4].contains(s.etages[s.pieces[$0].etage].id) && libre[$0] != avant[s.pieces[$0].id]
        }
        #expect(!deplacees.isEmpty, "temoin : le calcul libre rearrange les Zones 3 et 4")
    }

    /// L'Abri passe de la Zone 2 a la Zone 1, puis revient (« Automatiquement ») : les pieces des Zones 3 et 4, qui ne
    /// changent pas, restent exactement au meme endroit (au bit pres). Le temoin : sans cela, un calcul libre les deplace.
    @Test func rangerPieceGardeLesPlateauxInchanges() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        #expect(avant.count == 6 && Self.zone(de: "Abri", dans: m) == Self.z2)
        #expect(!m.fixerInchanges, "pas de marque au lancement")
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        #expect(m.fixerInchanges, "le choix pose la marque")
        let choix = try Self.scene(m.places)
        m.installerMaintenant(choix)
        #expect(Self.zone(de: "Abri", dans: m) == Self.z1)
        #expect(!m.fixerInchanges, "le calcul qui la prend l'efface")
        #expect(Self.positions(m, de: [Self.z3, Self.z4]) == avant, "l'aller : les Zones 3 et 4 n'ont pas bouge")
        // Le retour : « Automatiquement ».
        m.rangerPiece("piece:Abri", dans: nil)
        #expect(m.fixerInchanges)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Abri", dans: m) == Self.z2 && !m.fixerInchanges)
        #expect(Self.positions(m, de: [Self.z3, Self.z4]) == avant, "le retour : les Zones 3 et 4 n'ont pas bouge")
    }

    /// Par le chemin asynchrone de l'app (`recevoir`, calcul hors du fil principal) : le meme resultat.
    @Test(.timeLimit(.minutes(1))) func rangerPieceParLeCalculAsynchrone() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        let choix = try Self.scene(m.places)
        m.recevoir(choix)
        try await MoteurPiecesTests.attendre { m.entree == choix }
        #expect(m.entree == choix && Self.zone(de: "Abri", dans: m) == Self.z1)
        #expect(Self.positions(m, de: [Self.z3, Self.z4]) == avant)
        #expect(!m.fixerInchanges)
    }

    // MARK: Apres un choix de niveau du menu d'un plateau

    /// « Hors de la maison » et « Au meme niveau que » : les plateaux dont les pieces, les noeuds et la place de niveau ne
    /// changent pas gardent leurs pieces au bit pres. La Zone 2 rejoint le niveau de la Zone 3 : les Zones 1, 3 et 4 sont
    /// inchangees.
    @Test func choixDeNiveauGardeLesPlateauxInchanges() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        let tout = [Self.z1, Self.z2, Self.z3, Self.z4]
        let avant = Self.positions(m, de: tout)
        // Hors de la maison : la Zone 2 est dehors, la voila dedans.
        m.basculerDehors(Self.z2)
        #expect(m.fixerInchanges)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(!m.fixerInchanges)
        #expect(Self.positions(m, de: tout) == avant, "hors de la maison : rien ne bouge")
        // Au meme niveau que la Zone 3.
        m.mettreAuNiveau(Self.z2, de: Self.z3)
        #expect(m.fixerInchanges)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(m.entree?.scene.niveaux.liste == [[Self.z1], [Self.z3, Self.z2], [Self.z4]])
        #expect(!m.fixerInchanges)
        let inchanges = [Self.z1, Self.z3, Self.z4]
        let apres = Self.positions(m, de: inchanges)
        #expect(apres.count == 12 && apres.allSatisfy { avant[$0.key] == $0.value },
                "au meme niveau que : les plateaux inchanges ne bougent pas")
    }

    /// Un choix qui ne change pas la cle de disposition (« Hors de la maison » n'y est pas) ne laisse pas de marque : la scene
    /// suivante n'a aucun calcul, donc rien qui l'efface ; elle ne traine pas jusqu'au prochain changement de Maison. Un
    /// choix sans effet (rien a ranger) ne pose rien.
    @Test func choixSansNouveauCalculEffaceLaMarque() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        m.basculerDehors(Self.z2)
        #expect(m.fixerInchanges)
        m.recevoir(try Self.scene(m.places))
        #expect(m.enCalcul == nil && m.attente == nil, "la disposition ne change pas : pas de calcul")
        #expect(!m.fixerInchanges, "la marque ne traine pas")
        m.deplacerEtage(Self.z4, de: 1)
        #expect(!m.fixerInchanges, "le dernier plateau ne monte pas")
        m.rangerPiece("piece:Inconnue", dans: "Zone 1")
        m.rangerPiece("piece:Chambre", dans: "Zone 1")
        #expect(!m.fixerInchanges, "une piece inconnue, une zone qui ne contient pas la piece")
    }

    /// Relecture finale de la phase 11, M1 : cliquer la zone deja cochee, ou « Automatiquement » deja coche, ne change rien :
    /// pas de scene differente, donc pas de calcul qui efface la marque. Elle ne se pose pas ; un changement de Maison qui
    /// suit est calcule librement.
    @Test func choixInchangeNePoseAucuneMarque() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        m.rangerPiece("piece:Abri", dans: nil)
        #expect(!m.fixerInchanges, "« Automatiquement » deja coche : pas de marque")
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        #expect(m.fixerInchanges, "un vrai choix pose la marque")
        m.installerMaintenant(try Self.scene(m.places))
        #expect(!m.fixerInchanges)
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        #expect(!m.fixerInchanges, "la zone deja cochee : pas de marque")
        // Un changement de Maison qui suit : la Cuisine quitte la Zone 1, la disposition est calculee librement.
        m.installerMaintenant(try Self.scene(m.places, zone1: Self.piecesZone1.filter { $0 != "Cuisine" }))
        #expect(m.positions == (try Self.libre(m)), "calcul libre, comme avant")
    }

    // MARK: Sans choix dans la vue

    /// Un changement venu de Maison (les places gardees sont changees sans passer par la vue) : le calcul est libre, comme
    /// avant, les plateaux inchanges ne sont pas fixes.
    @Test func sansChoixLeCalculEstLibre() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        m.places.choisirZone("Zone 1", piece: "Abri", domicile: e.domicile)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(Self.zone(de: "Abri", dans: m) == Self.z1)
        #expect(m.positions == (try Self.libre(m)), "meme positions que DispositionPieces, sans fixees en plus")
        // Une zone changee dans Maison : la Cuisine quitte la Zone 1.
        m.installerMaintenant(try Self.scene(m.places, zone1: Self.piecesZone1.filter { $0 != "Cuisine" }))
        #expect(m.positions == (try Self.libre(m)))
    }

    /// La marque ne vaut qu'une fois : un second changement, sans choix, est libre.
    @Test func laMarqueNeVautQuUneFois() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        m.installerMaintenant(try Self.scene(m.places))
        #expect(!m.fixerInchanges)
        m.places.choisirZone(nil, piece: "Abri", domicile: e.domicile)
        m.places.ranger(Rangement(ordre: [Self.z1, Self.z2, Self.z3, Self.z4], aCote: [:]), domicile: e.domicile)
        m.installerMaintenant(try Self.scene(m.places))
        #expect(m.positions == (try Self.libre(m)), "le second calcul est libre")
    }

    // MARK: La marque

    /// Un calcul abandonne (une scene de structure differente arrive avant sa fin) garde la marque pour le suivant, qui fixe
    /// les plateaux inchanges par rapport a la disposition affichee ; le calcul qui aboutit l'efface.
    @Test(.timeLimit(.minutes(1))) func unCalculAbandonneGardeLaMarque() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, initiale) = try Self.moteur(url)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        m.recevoir(try Self.scene(m.places))
        #expect(m.enCalcul != nil && m.fixerInchanges && m.calculFixe, "le premier calcul est en route, avec la marque")
        // Une scene d'une autre structure l'abandonne : la Cuisine quitte la Zone 1.
        let suivante = try Self.scene(m.places, zone1: Self.piecesZone1.filter { $0 != "Cuisine" })
        m.recevoir(suivante)
        #expect(m.entree == initiale && m.fixerInchanges, "le calcul abandonne a garde la marque")
        try await MoteurPiecesTests.attendre { m.entree == suivante }
        #expect(m.entree == suivante)
        #expect(!m.fixerInchanges, "le calcul qui aboutit l'efface")
        #expect(Self.positions(m, de: [Self.z3, Self.z4]) == avant, "le suivant a fixe les plateaux inchanges")
    }

    /// Un calcul lance avant le choix (sans marque) qui aboutit n'efface pas la marque : elle sert au calcul de la scene du
    /// choix, qui fixe les plateaux inchanges par rapport a la disposition que ce calcul vient de poser.
    @Test(.timeLimit(.minutes(1))) func unCalculSansMarqueNEffacePasLaMarque() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        // Un changement de Maison en calcul : la Cuisine quitte la Zone 1.
        let sansCuisine = Self.piecesZone1.filter { $0 != "Cuisine" }
        let maison = try Self.scene(m.places, zone1: sansCuisine)
        m.recevoir(maison)
        #expect(m.enCalcul != nil && !m.calculFixe)
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        try await MoteurPiecesTests.attendre { m.entree == maison }
        #expect(m.entree == maison && m.fixerInchanges, "le calcul parti sans la marque la laisse")
        let apres = Self.positions(m, de: [Self.z3, Self.z4])
        let choix = try Self.scene(m.places, zone1: sansCuisine)
        m.recevoir(choix)
        #expect(m.fixerInchanges && m.calculFixe, "le calcul du choix prend la marque")
        try await MoteurPiecesTests.attendre { m.entree == choix }
        #expect(m.entree == choix && !m.fixerInchanges && Self.zone(de: "Abri", dans: m) == Self.z1)
        #expect(Self.positions(m, de: [Self.z3, Self.z4]) == apres)
    }

    /// Le choix arrive avec une scene de la meme structure que celle d'un calcul parti sans la marque : ce calcul vaut pour
    /// elle, et la marque ne traine pas jusqu'au prochain changement de Maison.
    @Test(.timeLimit(.minutes(1))) func uneSceneDeMemeStructureNeLaisseAucuneMarque() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        let sansCuisine = Self.piecesZone1.filter { $0 != "Cuisine" }
        m.recevoir(try Self.scene(m.places, zone1: sansCuisine))
        #expect(m.enCalcul != nil && !m.calculFixe)
        m.basculerDehors(Self.z2)
        #expect(m.fixerInchanges)
        let choix = try Self.scene(m.places, zone1: sansCuisine)
        m.recevoir(choix)
        #expect(!m.fixerInchanges, "ce calcul est parti sans la marque : elle ne lui servira plus")
        try await MoteurPiecesTests.attendre { m.entree == choix }
        #expect(m.entree == choix && !m.fixerInchanges)
    }

    /// « Replacer les pieces automatiquement » efface la marque et recalcule tout, sans rien fixer.
    @Test(.timeLimit(.minutes(1))) func replacerPiecesEffaceLaMarqueEtRecalculeTout() async throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, _) = try Self.moteur(url)
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        m.installerMaintenant(try Self.scene(m.places))
        m.rangerPiece("piece:Abri", dans: nil)
        #expect(m.fixerInchanges)
        m.replacerPieces()
        #expect(!m.fixerInchanges, "replacer efface la marque")
        try await MoteurPiecesTests.attendre { m.enCalcul == nil && m.cleCalculee != nil }
        #expect(m.enCalcul == nil && !m.fixerInchanges)
        #expect(m.positions == (try Self.libre(m)), "tout est recalcule, sans fixees en plus")
    }

    // MARK: Les pieces fixees

    /// `fixeesInchangees` : les pieces des plateaux dont la cle, les pieces, leurs noeuds et la place de niveau sont ceux de la
    /// disposition affichee, a leur position calculee ; rien pour les plateaux changes, ni avant la premiere disposition.
    @Test func fixeesInchangeesDesPlateauxInchanges() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        // Aucune disposition affichee : rien.
        let vierge = MoteurPieces(troisD: false, fichierPlaces: url)
        #expect(vierge.fixeesInchangees(e).isEmpty)
        // L'Abri change de zone : les Zones 3 et 4 sont inchangees, les Zones 1 et 2 non.
        var places = m.places
        places.choisirZone("Zone 1", piece: "Abri", domicile: e.domicile)
        let choix = try Self.scene(places)
        let fixees = m.fixeesInchangees(choix)
        let s = choix.scene
        let attendu = s.pieces.indices.filter { [Self.z3, Self.z4].contains(s.etages[s.pieces[$0].etage].id) }
        #expect(Set(fixees.keys) == Set(attendu) && attendu.count == 6)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        for (i, place) in fixees { #expect(place == avant[s.pieces[i].id], "la position affichee de \(s.pieces[i].id)") }
        // La scene affichee elle-meme : tous les plateaux sont inchanges.
        #expect(m.fixeesInchangees(try #require(m.entree)).count == m.positions.count)
    }

    /// Une place gardee a la main l'emporte sur une position fixee.
    @Test func laPlaceGardeeALaMainL_emporte() throws {
        let url = MoteurPiecesTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(url)
        let avant = Self.positions(m, de: [Self.z3, Self.z4])
        let ancienne = try #require(avant["piece:Chambre"])
        let main = SIMD2(ancienne.x + 0.25, ancienne.y - 0.125)
        m.places.garder(main, piece: "piece:Chambre", etage: Self.z3, domicile: e.domicile)
        m.rangerPiece("piece:Abri", dans: "Zone 1")
        let choix = try Self.scene(m.places)
        let i = try #require(choix.scene.pieces.firstIndex { $0.id == "piece:Chambre" })
        #expect(m.fixeesInchangees(choix)[i] == ancienne, "la position fixee est celle de la disposition affichee")
        m.installerMaintenant(choix)
        let apres = Self.positions(m, de: [Self.z3, Self.z4])
        #expect(apres["piece:Chambre"] == main, "la place gardee a la main l'emporte")
        for (cle, place) in avant where cle != "piece:Chambre" { #expect(apres[cle] == place, "\(cle) ne bouge pas") }
    }
}
