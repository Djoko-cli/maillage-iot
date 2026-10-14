import AppKit
import Foundation
@testable import MaillageCoeur
@testable import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Vue par pieces : noms, apparences et scene de l'app")
struct NomsSceneTests {
    /// La demo : la panne rejouee, ses noms de Maison (pieces et etages de la maquette) et son
    /// maillage de sonde invente.
    static func demo() throws -> (Surveillance, Reseau, EntreeScene) {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.reseau)
        return (s, r, EntreeScene(surveillance: s, reseau: r, places: PlacesGardees()))
    }

    /// La maison de demo sans les accessoires de ses routeurs de bordure : comme chez Djoko, Maison ne
    /// donne ni les HomePod ni l'Apple TV.
    static func maisonSansRouteurs(_ s: Surveillance) -> NomsMaison? {
        guard var m = s.noms.maison, let r = s.reseau else { return nil }
        let routeurs = Set(r.routeurs.map(\.instance))
        m.accessoires.removeAll { routeurs.contains($0.nom) }
        return m
    }

    /// La demo sans les accessoires de ses routeurs (`maisonSansRouteurs`), dont le maillage a en plus,
    /// sous le chef, un enfant sans ExtMac (« rloc:0420 »). Celui qu'elle a deja, « rloc:041F »
    /// (E0000000000000FF), est un appareil que la sonde seule connait.
    static func demoAvecInconnus() throws -> (Surveillance, Reseau) {
        let (s, r, _) = try demo()
        s.noms.maison = maisonSansRouteurs(s)
        let m = try #require(s.maillage)
        let enfants = m.enfants + [EnfantMaillage(rloc16: 0x0420, qualite: 2, source: .tableEnfants)]
        s.recevoir(Maillage(date: m.date, partition: m.partition, routeurs: m.routeurs, liens: m.liens,
                            enfants: enfants.sorted { $0.rloc16 < $1.rloc16 }, signaux: m.signaux), a: s.maintenant)
        return (s, r)
    }

    /// `demoAvecInconnus`, dont le maillage a en plus un routeur Thread qui n'est pas de bordure, connu de
    /// la sonde seule (« rloc:B400 », E0000000000000F1).
    static func demoAvecRouteurThread() throws -> (Surveillance, Reseau) {
        let (s, r) = try demoAvecInconnus()
        let m = try #require(s.maillage)
        var thread = RouteurMaillage(id: 45)
        thread.extMac = "E0000000000000F1"
        s.recevoir(Maillage(date: m.date, partition: m.partition, routeurs: m.routeurs + [thread], liens: m.liens,
                            enfants: m.enfants, signaux: m.signaux), a: s.maintenant)
        return (s, r)
    }

    /// La demo dont les deux HomePod sont deux routeurs de bordure non identifies (polissage D, section 4.1) : leur
    /// annonce n'a plus d'ExtMac dans le maillage de la sonde ; leurs candidats sont les deux annonces.
    static func demoSansIdentite() throws -> (Surveillance, Reseau) {
        let (s, r, _) = try demo()
        let i = try #require(s.instantane)
        let m = try #require(MaillageDemo.maillage(i, date: s.maintenant, sansIdentite: ["HomePod Avant", "HomePod Palier"]))
        s.recevoir(m, a: s.maintenant)
        return (s, r)
    }

    /// Libelle d'un noeud : le nom coupe a 40 caracteres, la couronne du chef (celui de la partition
    /// et celui de la sonde), ☾ endormi, ⚠︎ sans adresse ou disparu ; la pastille d'une batterie faible.
    @Test func libelles() throws {
        let (s, r, e) = try Self.demo()
        #expect(e.libelles[idt("Apple TV 4K")]?.texte == "Apple TV 4K 👑")
        #expect(e.libelles[idt("86E7BD1A75F28E6D")] == LibellesNoeuds.Libelle(texte: "Nuki Ultra ☾", nom: "Nuki Ultra"))
        #expect(e.libelles[idt("7AF0B6D5006CF95F")]?.texte == "Prise salon ☾ ⚠︎", "disparue")
        #expect(e.libelles[idt("3A5DFAFCAB581AAF")]?.pastille == String(localized: "\(12)\u{202F}%"))
        #expect(e.libelles[idt("rloc:041F")]?.texte == String(localized: "Non identifié · \("041F")"))
        let m = try #require(s.maillageAffiche(pour: r))
        #expect(LibellesNoeuds.chefs(reseau: r, maillage: s.maillage, affiche: m) == [idt("Apple TV 4K")])
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(alerte: true)) == String(localized: "faible"))
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: 52)) == nil)
        #expect(LibellesNoeuds.inconnu(NoeudSonde(id: "rloc:5000", rloc16: 0x5000, genre: .routeur, reconnu: false,
                                                  bordure: false)) == String(localized: "Routeur · \("5000")"))
    }

    /// Pas de ☾ pour un noeud qui route (relecture finale, mineur T7-2) : un routeur Thread n'est jamais endormi, meme
    /// si son annonce Matter le dit a veille. Dans la demo, les deux appareils qui routent, « Prise console » et
    /// « Prise terrasse », s'annoncent ainsi : leur nom n'a pas de ☾, et la legende, qui reprend les signes de la
    /// scene, ne les compte pas parmi les endormis. Un enfant endormi, la serrure, garde sa lune.
    @Test func pasDeLunePourUnNoeudQuiRoute() throws {
        let (_, _, e) = try Self.demo()
        let prises = [idt("02A8C3C5600F136B"), idt("0A84D1254BD246AD")]
        for id in prises {
            let n = try #require(e.scene.noeuds.first { $0.id == id })
            #expect(n.routeur && e.appareils[id]?.endormi == true, "\(id) : route, et s'annonce endormi")
            let texte = e.libelles[id]?.texte ?? ""
            #expect(!texte.isEmpty && !texte.contains(LibellesNoeuds.lune), "\(id) : \(texte)")
        }
        #expect(e.libelles[idt("86E7BD1A75F28E6D")]?.texte == "Nuki Ultra ☾", "un enfant endormi garde sa lune")
        let lecture = LegendePieces.Lecture(e, ailleurs: false)
        #expect(lecture.endormis.isDisjoint(with: prises) && lecture.endormis.contains(idt("86E7BD1A75F28E6D")),
                "la legende : \(lecture.endormis.sorted())")
    }

    /// Pieces : celle de l'accessoire d'un appareil ; celle de l'accessoire du nom de l'annonce d'un
    /// routeur de bordure. Noms des etages, des pieces, compte, repere « ailleurs ».
    @Test func piecesEtNoms() throws {
        let (s, r, e) = try Self.demo()
        let pieces = LibellesNoeuds.pieces(reseau: r, appareils: s.appareilsAffiches(pour: r), maison: s.noms.maison,
                                           graphe: e.graphe)
        #expect(pieces[idt("Apple TV 4K")] == "Salon" && pieces[idt("HomePod mini chambre")] == "Chambre")
        #expect(pieces[idt("56B1E064401F74EF")] == "Bureau")
        #expect(pieces[idt("1E5019DAC2638F92")] == nil)
        #expect(LibellesNoeuds.nom(ScenePieces.NomEtage.zone("Étage")) == "Étage")
        #expect(LibellesNoeuds.nom(ScenePieces.NomEtage.maison) == String(localized: "Maison"))
        #expect(LibellesNoeuds.nom(ScenePieces.NomPiece.sansPiece, libelles: [:]) == String(localized: "Sans pièce"))
        #expect(LibellesNoeuds.nom(.routeur(idt("Apple TV 4K")), libelles: e.libelles) == "Apple TV 4K 👑")
        #expect(LibellesNoeuds.compte(1) == String(localized: "1 appareil"))
        #expect(LibellesNoeuds.compte(6) == String(localized: "\(6) appareils"))
        let salon = try #require(e.scene.pieces.firstIndex { $0.nom == .maison("Salon") })
        let reperes = SceneProjetee.reperes(e.scene, focus: salon)
        let volet = try #require(reperes.first { $0.enfant == idt("724CC16B32D8F820") })
        #expect(LibellesNoeuds.ailleurs(volet, scene: e.scene, libelles: e.libelles)
                == "↑ HomePod mini chambre · Chambre, Étage")
    }

    /// Un nom de plus de 40 caracteres est coupe a 39, suivi de « … », avant la couronne et ☾.
    @Test func nomCoupeA40Caracteres() throws {
        let (s, r, _) = try Self.demo()
        let serrure = "Serrure connectée de la porte arrière, garage"
        let atv = "Apple TV du salon, sous la télévision murale"
        #expect(serrure.count == 45 && atv.count == 44)
        s.renommer(idt("86E7BD1A75F28E6D"), en: serrure)
        s.renommer(idt("Apple TV 4K"), en: atv)
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        #expect(e.libelles[idt("86E7BD1A75F28E6D")]?.texte == "Serrure connectée de la porte arrière, …" + " ☾")
        #expect(e.libelles[idt("Apple TV 4K")]?.texte == "Apple TV du salon, sous la télévision m…" + " 👑")
        #expect(String(serrure.prefix(39)) == "Serrure connectée de la porte arrière, ")
    }

    /// Repere « ailleurs » d'un enfant dont le parent est le chef : le nom du parent sans la couronne,
    /// avec ☾ ou ⚠︎ s'il en a (precision 20).
    @Test func repereAilleursSansCouronne() throws {
        let (_, _, e) = try Self.demo()
        #expect(e.libelles[idt("Apple TV 4K")]?.texte == "Apple TV 4K 👑")
        let reperes = e.scene.pieces.indices.flatMap { SceneProjetee.reperes(e.scene, focus: $0) }
        let a = try #require(reperes.first { $0.parent == idt("Apple TV 4K") })
        let salon = LibellesNoeuds.nom(e.scene.pieces[a.piece].nom, libelles: e.libelles)
        #expect(salon == "Salon")
        let suite = a.sens == .memeNiveau ? "" : ", " + LibellesNoeuds.nom(e.scene.etages[a.etage].nom)
        let fleche = switch a.sens {
        case .memeNiveau: "↗"
        case .dessous: "↓"
        case .dessus: "↑"
        }
        #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles) == "\(fleche) Apple TV 4K · Salon\(suite)")
        var disparu = e.libelles
        disparu[idt("Apple TV 4K")]?.texte = "Apple TV 4K 👑 ☾ ⚠︎"
        #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: disparu) == "\(fleche) Apple TV 4K ☾ ⚠︎ · Salon\(suite)")
    }

    /// Repere « ailleurs » d'un parent au meme niveau, dans une autre zone (polissage C, section 5.2) : ↗, avec le
    /// nom de sa zone. L'entree mise dans un « Jardin » a cote du rez-de-chaussee : le parent de la serrure, l'Apple
    /// TV, est au salon. Sans le choix, le jardin est un etage au-dessus : ↓.
    @Test func repereAuMemeNiveau() throws {
        let (s, r, _) = try Self.demo()
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Buanderie"]),
                        ZoneMaison(nom: "Jardin", pieces: ["Entrée"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
                        ZoneMaison(nom: "Combles", pieces: ["Terrasse", "Abri", "Grenier", "Salle de jeux"])]
        s.noms.maison = maison
        var places = PlacesGardees()
        places.ranger(Rangement(ordre: [], aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée")]),
                      domicile: maison.domicile ?? "")
        for (p, attendu) in [(places, "↗ Apple TV 4K · Salon, Rez-de-chaussée"), (PlacesGardees(), "↓ Apple TV 4K · Salon, Rez-de-chaussée")] {
            let e = EntreeScene(surveillance: s, reseau: r, places: p)
            let entree = try #require(e.scene.pieces.firstIndex { $0.nom == .maison("Entrée") })
            let a = try #require(SceneProjetee.reperes(e.scene, focus: entree).first { $0.enfant == idt("86E7BD1A75F28E6D") })
            #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles) == attendu)
        }
    }

    /// Routeurs de bordure que Maison ne place pas : la piece de leur nom (« HomePod mini chambre »), sinon
    /// celle qu'on leur a choisie, qui passe avant ; les autres vont dans « Sans piece ». Un routeur que
    /// Maison place garde sa piece.
    @Test func piecesDesRouteurs() throws {
        let (s, r, depart) = try Self.demo()
        let maison = try #require(Self.maisonSansRouteurs(s))
        #expect(!maison.accessoires.contains { $0.nom == "Apple TV 4K" })
        let noms = s.nomsRouteurs(pour: r)
        var pieces = LibellesNoeuds.pieces(reseau: r, appareils: s.appareilsAffiches(pour: r), maison: maison,
                                           nomsRouteurs: noms, graphe: depart.graphe)
        #expect(pieces[idt("HomePod mini chambre")] == "Chambre" && pieces[idt("HomePod mini bureau")] == "Bureau")
        #expect(pieces[idt("HomePod Palier")] == nil && pieces[idt("HomePod Avant")] == nil && pieces[idt("Apple TV 4K")] == nil)
        var choix = PiecesRouteurs()
        choix.choisir("Salon", routeur: idt("HomePod Palier"), domicile: maison.domicile ?? "")
        choix.choisir("Bureau", routeur: idt("HomePod mini chambre"), domicile: maison.domicile ?? "")
        pieces = LibellesNoeuds.pieces(reseau: r, appareils: s.appareilsAffiches(pour: r), maison: maison,
                                       nomsRouteurs: noms, choix: choix, graphe: depart.graphe)
        #expect(pieces[idt("HomePod Palier")] == "Salon" && pieces[idt("HomePod mini chambre")] == "Bureau")
        let avecMaison = LibellesNoeuds.pieces(reseau: r, appareils: s.appareilsAffiches(pour: r), maison: s.noms.maison,
                                               nomsRouteurs: noms, choix: choix, graphe: depart.graphe)
        #expect(avecMaison[idt("HomePod mini chambre")] == "Chambre", "Maison passe avant le choix")
        s.noms.maison = maison
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees(), choix: choix)
        let gauche = try #require(e.scene.noeud(idt("HomePod Palier")))
        #expect(e.scene.pieces[gauche.piece].nom == .maison("Salon"))
        let atv = try #require(e.scene.noeud(idt("Apple TV 4K")))
        #expect(e.scene.pieces[atv.piece].nom == .sansPiece)
    }

    /// Un noeud que Maison ne place pas et dont l'ExtMac est connue passe dans la piece choisie pour son
    /// ExtMac (precision 27) : l'appareil que la sonde seule connait, l'annonce sans accessoire (son nom
    /// d'hote) ; la piece de Maison passe avant le choix ; un noeud sans ExtMac reste sans piece. La
    /// disposition suit.
    @Test func piecesDesAppareils() throws {
        let (s, r) = try Self.demoAvecInconnus()
        let domicile = try #require(s.noms.maison?.domicile)
        var choix = PiecesRouteurs()
        choix.choisir("Cuisine", appareil: idt("E0000000000000FF"), domicile: domicile)
        choix.choisir("Bureau", appareil: idt("1E5019DAC2638F92"), domicile: domicile)
        choix.choisir("Salon", appareil: idt("56B1E064401F74EF"), domicile: domicile)
        let avant = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees(), choix: choix)
        func piece(_ e: EntreeScene, _ id: String) throws -> ScenePieces.NomPiece {
            e.scene.pieces[try #require(e.scene.noeud(idt(id))).piece].nom
        }
        #expect(try piece(avant, "rloc:041F") == .sansPiece && piece(avant, "1E5019DAC2638F92") == .sansPiece)
        #expect(try piece(e, "rloc:041F") == .maison("Cuisine"), "connu de la sonde seule")
        #expect(try piece(e, "1E5019DAC2638F92") == .maison("Bureau"), "annonce sans accessoire de Maison")
        #expect(try piece(e, "56B1E064401F74EF") == .maison("Bureau"), "Maison passe avant le choix")
        #expect(try piece(e, "rloc:0420") == .sansPiece, "sans ExtMac")
        #expect(e.cleDisposition != avant.cleDisposition)
    }

    /// La maison de demo (polissage C, section 7) : les quatre plateaux et les douze pieces des maquettes, « Sans piece »
    /// sur le plateau du bas ; avec son choix de niveau, le jardin au niveau du rez-de-chaussee, hors de la maison ; les
    /// apparences du graphe d'avant.
    @Test func sceneDeLaDemo() throws {
        let (s, r, e) = try Self.demo()
        #expect(e.scene.etages.map(\.nom) == [.zone("Rez-de-chaussée"), .zone("Jardin"), .zone("Étage"), .zone("Combles")])
        func pieces(_ k: Int) -> [ScenePieces.NomPiece] { e.scene.etages[k].pieces.map { e.scene.pieces[$0].nom } }
        #expect(pieces(0) == [.maison("Buanderie"), .maison("Cuisine"), .maison("Entrée"), .maison("Salon"), .sansPiece])
        #expect(pieces(1) == [.maison("Abri"), .maison("Terrasse")])
        #expect(pieces(2) == [.maison("Bureau"), .maison("Chambre"), .maison("Chambre d'amis"), .maison("Salle de bain")])
        #expect(pieces(3) == [.maison("Grenier"), .maison("Salle de jeux")])
        let niveaux = EntreeScene(surveillance: s, reseau: r, places: NomsDemo.places()).scene
        #expect(niveaux.niveaux.liste == [["zone:Rez-de-chaussée", "zone:Jardin"], ["zone:Étage"], ["zone:Combles"]])
        #expect(niveaux.etages.map(\.dehors) == [false, true, false, false])
        // Un routeur dans la salle de jeux et sur la terrasse ; des liens entre niveaux et au meme niveau.
        for (id, piece) in [("02A8C3C5600F136B", "Salle de jeux"), ("0A84D1254BD246AD", "Terrasse")] {
            let n = try #require(niveaux.noeud(idt(id)))
            #expect(n.routeur && niveaux.pieces[n.piece].nom == .maison(piece))
        }
        let niveau = { (id: IdNoeud) in niveaux.noeud(id).map { niveaux.etages[niveaux.pieces[$0.piece].etage].niveau } }
        let liens = niveaux.liens.filter { $0.genre == .radio }.map { (niveau($0.de), niveau($0.vers)) }
        #expect(liens.contains { $0.0 != $0.1 } && liens.contains { $0.0 == $0.1 })
        #expect(!e.scene.sansPiecesMaison)
        #expect(e.domicile == "Maison (démo)")
        #expect(e.apparences[idt("Apple TV 4K")] == DessinNoeud.Apparence(forme: .sphere(halo: 10),
                                                                    couleur: .routeur(principale: true)))
        #expect(e.apparences[idt("HomePod Avant")]?.forme == .sphere(halo: 5))
        #expect(e.apparences[idt("Aqara HubM100 #DFEB")]?.couleur == .routeur(principale: false))
        #expect(e.apparences[idt("7AF0B6D5006CF95F")] == DessinNoeud.Apparence(forme: .anneau, couleur: .appareil(.disparu)))
        #expect(e.apparences[idt("56B1E064401F74EF")] == DessinNoeud.Apparence(forme: .pastille, couleur: .appareil(.joignable)))
        #expect(e.apparences[idt("rloc:041F")]?.couleur == .appareil(.inconnu))
        // Le cercle bleu : les appareils qui routent, sauf disparus, et eux seuls (demande de Djoko du 08/10).
        let cercles = Set(e.scene.noeuds.filter { e.apparences[$0.id]?.cercle == true }.map(\.id))
        #expect(!cercles.isEmpty)
        #expect(cercles == Set(e.scene.noeuds.filter {
            $0.genre == .appareil && $0.routeur && e.apparences[$0.id]?.couleur != .appareil(.disparu)
        }.map(\.id)))
    }

    /// La cle de la disposition ne change pas avec l'etat d'un noeud ; elle change avec son nom. Elle suit les
    /// niveaux tels que les voit le cout (polissage C, section 4) : une zone mise a cote d'un etage la change ;
    /// l'ordre des niveaux au-dessus du plateau du bas (qui porte « Sans piece »), ou une zone sortie de la
    /// maison, non.
    @Test func cleDeLaDisposition() throws {
        let (s, r, e) = try Self.demo()
        #expect(EntreeScene(surveillance: s, reseau: r, places: PlacesGardees()).cleDisposition == e.cleDisposition)
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Chambre d'amis"]),
                        ZoneMaison(nom: "Combles", pieces: ["Bureau", "Salle de bain"])]
        s.noms.maison = maison
        let domicile = maison.domicile ?? ""
        func cle(_ ordre: [String], _ aCote: [String: PlacesGardees.ACote]) -> EntreeScene.CleDisposition {
            var p = PlacesGardees()
            p.ranger(Rangement(ordre: ordre, aCote: aCote), domicile: domicile)
            return EntreeScene(surveillance: s, reseau: r, places: p).cleDisposition
        }
        let rdc = "zone:Rez-de-chaussée", etage = "zone:Étage", combles = "zone:Combles"
        let depart = cle([rdc, etage, combles], [:])
        let aCote = cle([rdc, etage, combles], [combles: PlacesGardees.ACote(etage: etage)])
        #expect(aCote != depart, "les combles a cote de l'etage")
        #expect(cle([rdc, combles, etage], [:]) == depart, "l'ordre des niveaux")
        #expect(cle([rdc, etage, combles], [combles: PlacesGardees.ACote(etage: etage, dehors: true)]) == aCote,
                "hors de la maison")
        s.renommer(idt("56B1E064401F74EF"), en: "Pont Halo")
        #expect(cle([rdc, etage, combles], [:]) != depart)
    }

    /// Un badge qui change ne change ni la scene ni la cle de la disposition (polissage D, section 2) : une pile qui
    /// faiblit donne sa pastille au libelle, sans plus. Le moteur pose la scene tout de suite, sans calcul : rien ne
    /// bouge, ni piece ni carte, rien ne glisse ; seul le nom change.
    @Test func unBadgeNeBougeRien() throws {
        let (s, r, e) = try Self.demo()
        let m = MoteurPiecesTests.moteur(e)
        var maison = try #require(s.noms.maison)
        let k = try #require(maison.accessoires.firstIndex { $0.nom == "Nuki Ultra" })
        maison.accessoires[k].batterie = BatterieMaison(niveau: 5)
        s.noms.maison = maison
        let e2 = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let nuki = "86E7BD1A75F28E6D"
        #expect(e2.libelles[idt(nuki)]?.pastille == String(localized: "\(5)\u{202F}%") && e.libelles[idt(nuki)]?.pastille == nil)
        #expect(e2.scene == e.scene && e2.cleDisposition == e.cleDisposition && e2 != e)
        // La scene ne voit que les noms : ni ☾, ni la couronne du chef.
        #expect(e.libelles[idt(nuki)]?.texte == "Nuki Ultra ☾" && e.scene.noeud(idt(nuki))?.libelle == "Nuki Ultra")
        #expect(e.libelles[idt("Apple TV 4K")]?.texte == "Apple TV 4K 👑" && e.scene.noeud(idt("Apple TV 4K"))?.libelle == "Apple TV 4K")
        let (positions, cartes) = (m.positions, m.cartes)
        // Les cartes tiennent le pire cas de chaque nom, tel qu'il s'afficherait : tous les badges qu'il peut porter, et la
        // plus large des pastilles si sa pile est connue. Le noeud route selon le graphe, non selon son rang.
        let mesure = MesureNoms()
        let pires = Dictionary(uniqueKeysWithValues: e.scene.noeuds.map { n -> (IdNoeud, Double) in
            let route = n.bordure || n.routeur
            let texte = CartesPieces.texte(n.libelle, chef: route, endormi: !route, alerte: true)
            let pastille = n.pile ? Self.pastilleLaPlusLarge(mesure) : nil
            let pire = LibellesNoeuds.Libelle(texte: texte, pastille: pastille, nom: n.libelle)
            return (n.id, Double(mesure.noeud(pire, routeur: route).width))
        })
        #expect(cartes == CartesPieces.cartes(e.scene, largeurs: pires), "les cartes reservent la place des badges")
        #expect(MoteurPiecesTests.moteur(e2).cartes == cartes, "la pastille du Nuki ne change pas les cartes")
        m.recevoir(e2)
        #expect(m.entree == e2, "posee tout de suite, sans calcul")
        #expect(m.positions == positions && m.cartes == cartes && m.transition == nil && m.glissementPlateaux == nil)
        #expect(m.textes.noeuds[idt(nuki)]?.pastille == String(localized: "\(5)\u{202F}%"))
        // Une pile qui devient connue (decision du 05/10) : la cle change, et la carte de la cuisine s'elargit, une fois.
        let k2 = try #require(maison.accessoires.firstIndex { $0.nom == "Interrupteur cuisine" })
        maison.accessoires[k2].batterie = BatterieMaison(niveau: 80)
        s.noms.maison = maison
        let e3 = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let cuisine = try MoteurPiecesTests.indice(e, "Cuisine")
        #expect(e3.cleDisposition != e.cleDisposition && e3.scene.noeud(idt("D6ECDD6EF9C0CB0C"))?.pile == true)
        #expect(e.scene.noeud(idt("D6ECDD6EF9C0CB0C"))?.pile == false && e.scene.noeud(idt(nuki))?.pile == true)
        #expect(MoteurPiecesTests.moteur(e3).cartes[cuisine].largeur > cartes[cuisine].largeur)
    }

    /// Les pastilles d'une pile faible, en valeurs fixes : un niveau de 1 a 3 chiffres (0 a 100 %), ou « faible ».
    static let pastilles = [0, 5, 9, 10, 50, 88, 99, 100].map { String(localized: "\($0)\u{202F}%") }
        + [String(localized: "faible")]

    /// La plus large d'entre elles, mesuree : celle que la carte reserve.
    static func pastilleLaPlusLarge(_ mesure: MesureNoms) -> String {
        pastilles.max { mesure.pastille($0).width < mesure.pastille($1).width } ?? ""
    }

    /// La place que la carte reserve au nom de chaque noeud de la demo (polissage D, section 2), avec la vraie police :
    /// chacun de ses noms affiches y tient, quels que soient ses badges, la pastille la plus large comprise pour un noeud
    /// dont la pile est connue ; sans pile connue, la reserve n'a pas de pastille (decision du 05/10).
    @Test func reserveDesBadges() throws {
        let (_, _, e) = try Self.demo()
        let mesure = MesureNoms()
        let large = mesure.pastilleReservee
        let largeur = mesure.pastille(large).width
        #expect(Self.pastilles.contains(large) && Self.pastilles.allSatisfy { mesure.pastille($0).width <= largeur })
        for n in e.scene.noeuds {
            let routeur = n.route
            let reserve = mesure.reserve(n.libelle, routeur: routeur, pile: n.pile)
            for badge in [false, true] {
                for alerte in [false, true] {
                    let texte = CartesPieces.texte(n.libelle, chef: routeur && badge, endormi: !routeur && badge, alerte: alerte)
                    let pire = LibellesNoeuds.Libelle(texte: texte, pastille: n.pile ? large : nil, nom: n.libelle)
                    let affiche = mesure.noeud(pire, routeur: routeur)
                    #expect(affiche.width <= reserve.width && affiche.height <= reserve.height, "\(texte)")
                }
            }
            let sansPastille = mesure.noeud(LibellesNoeuds.Libelle(texte: CartesPieces.texteReserve(n.libelle, routeur: routeur)),
                                            routeur: routeur)
            #expect(n.pile ? reserve.width > sansPastille.width : reserve == sansPastille, "\(n.libelle)")
            #expect(mesure.reserve(n.libelle, routeur: routeur, pile: true).width > sansPastille.width)
        }
        #expect(e.scene.noeuds.filter(\.pile).count == 9, "les neuf piles connues de la demo")
    }

    /// Deux routeurs de bordure non identifies (polissage D, section 4.1), les HomePod de la demo sans leur ExtMac :
    /// leurs candidats, les deux HomePod, sont au salon ; ils y vont, sous leur nom « A ou B · RLOC16 », et la fiche ne
    /// leur propose toujours pas « Placer dans une piece… ». Un candidat dans une autre piece : « Sans piece ».
    @Test func routeursAuxCandidats() throws {
        let (s, r) = try Self.demoSansIdentite()
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let inconnus = e.scene.noeuds.filter { $0.inconnu && $0.bordure }
        #expect(inconnus.count == 2)
        let candidats = ["HomePod Avant", "HomePod Palier"].formatted(.list(type: .or))
        for n in inconnus {
            #expect(e.scene.pieces[n.piece].nom == .maison("Salon"), "\(n.id)")
            let rloc = String(format: "%04X", try #require(e.maillage?.noeud(n.id.cle)).rloc16)
            #expect(e.libelles[n.id]?.texte == String(localized: "\(candidats) · \(rloc)"), "\(n.id)")
            // Pas de « Placer dans une piece… » : un routeur de bordure que la sonde seule connait (precision 25).
            #expect(PiecesChoisies.placement(n.id, dans: s, entree: e) == nil)
        }
        var maison = try #require(s.noms.maison)
        let k = try #require(maison.accessoires.firstIndex { $0.nom == "HomePod Avant" })
        maison.accessoires[k].piece = "Cuisine"
        s.noms.maison = maison
        let autre = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        for n in autre.scene.noeuds where n.inconnu && n.bordure {
            #expect(autre.scene.pieces[n.piece].nom == .sansPiece, "\(n.id)")
        }
    }

    /// La regle des candidats, telle que l'app la cable (`LibellesNoeuds.pieces`, polissage D, section 4.1) : comme pour
    /// un routeur identifie, le choix garde sous l'instance (et sous la maison, `domicile`) et le surnom comptent ; sans
    /// eux, ni Maison, ni nom : « Sans piece ».
    @Test func candidatsCables() throws {
        let (s, r) = try Self.demoSansIdentite()
        s.noms.maison = Self.maisonSansRouteurs(s)
        let domicile = try #require(s.noms.maison?.domicile)
        func pieces(_ choix: PiecesRouteurs = PiecesRouteurs()) throws -> [ScenePieces.NomPiece] {
            let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees(), choix: choix)
            let inconnus = e.scene.noeuds.filter { $0.inconnu && $0.bordure }
            try #require(inconnus.count == 2)
            return inconnus.map { e.scene.pieces[$0.piece].nom }
        }
        #expect(try pieces() == [.sansPiece, .sansPiece], "ni Maison, ni choix, ni piece dans le nom")
        var choix = PiecesRouteurs()
        choix.choisir("Salon", routeur: idt("HomePod Avant"), domicile: domicile)
        #expect(try pieces(choix) == [.sansPiece, .sansPiece], "un seul candidat choisi : l'autre n'a pas de piece")
        var autreMaison = choix
        autreMaison.choisir("Salon", routeur: idt("HomePod Palier"), domicile: "Autre maison")
        autreMaison.choisir("Salon", routeur: idt("HomePod Palier"), domicile: "")
        #expect(try pieces(autreMaison) == [.sansPiece, .sansPiece], "le choix d'une autre maison ne compte pas")
        choix.choisir("Salon", routeur: idt("HomePod Palier"), domicile: domicile)
        #expect(try pieces(choix) == [.maison("Salon"), .maison("Salon")], "le choix garde sous l'instance")
        s.renommer(idt("HomePod Avant"), en: "HomePod du salon")
        s.renommer(idt("HomePod Palier"), en: "HomePod du salon, a gauche")
        #expect(try pieces() == [.maison("Salon"), .maison("Salon")], "le surnom")
    }

    /// La scene porte ce dont elle est faite, construit une fois avec elle : le graphe, le maillage de la
    /// sonde rapproche, les chefs (ceux des libelles couronnes) et les appareils affiches. Ils n'entrent
    /// pas dans l'egalite : un maillage recu plus tard, qui ne change rien a la scene, ne la fait pas
    /// reposer par le moteur.
    @Test func constructionDeLaScene() throws {
        let (s, r, e) = try Self.demo()
        let m = try #require(s.maillageAffiche(pour: r))
        #expect(e.maillage == m)
        #expect(e.graphe == GrapheReseau(reseau: r, appareils: s.appareilsAffiches(pour: r), maillage: m))
        #expect(e.chefs == [idt("Apple TV 4K")])
        #expect(Set(e.libelles.filter { $0.value.texte.contains("👑") }.keys) == e.chefs, "la couronne suit les chefs")
        #expect(e.appareils[idt("56B1E064401F74EF")]?.piece == "Bureau")
        let maillage = try #require(s.maillage)
        s.recevoir(Maillage(date: maillage.date.addingTimeInterval(300), partition: maillage.partition,
                            routeurs: maillage.routeurs, liens: maillage.liens, enfants: maillage.enfants,
                            signaux: maillage.signaux), a: s.maintenant)
        let apres = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        #expect(apres.maillage?.date != e.maillage?.date)
        #expect(apres == e, "la meme scene")
    }

    /// Sur la maison de demo, avec les cartes du moteur, qui reservent la place des badges (polissage D, section 2) :
    /// aucun lien ne passe sur une piece autre que celles de ses bouts, aucune carte n'en recouvre une autre.
    @Test func demoSansTraversee() throws {
        let (_, _, e) = try Self.demo()
        let cartes = MoteurPiecesTests.moteur(e).cartes
        let d = DispositionPieces(scene: e.scene, cartes: cartes)
        let calcul = DispositionPieces.Calcul(scene: e.scene, cartes: cartes, fixees: [:])
        #expect(calcul.traversees(d.positions) == 0)
        #expect(d.cout < d.coutDepart)
        for et in e.scene.etages {
            for (k, a) in et.pieces.enumerated() {
                for b in et.pieces[(k + 1)...] {
                    let dx = abs(d.positions[b].x - d.positions[a].x), dz = abs(d.positions[b].y - d.positions[a].y)
                    let px = (cartes[a].largeur + cartes[b].largeur) / 2 + DispositionPieces.gap - dx
                    let pz = (cartes[a].profondeur + cartes[b].profondeur) / 2 + DispositionPieces.gap + DispositionPieces.lab - dz
                    #expect(!(px > 1e-6 && pz > 1e-6), "\(e.scene.pieces[a].id) / \(e.scene.pieces[b].id)")
                }
            }
        }
    }

    /// Tailles des textes rendues par `Canvas` a l'echelle 1, 2 et 3.
    static func taillesDessinees(_ textes: [Text], echelle: CGFloat) -> [CGSize] {
        final class Boite: @unchecked Sendable { var tailles: [CGSize] = [] }
        let boite = Boite()
        let rendu = ImageRenderer(content: Canvas { ctx, _ in
            boite.tailles = textes.map { ctx.resolve($0).measure(in: StylesNoms.grand) }
        }.frame(width: 10, height: 10))
        rendu.scale = echelle
        _ = rendu.cgImage
        return boite.tailles
    }

    /// La taille mesuree hors du `Canvas` couvre le texte dessine, a toute echelle : un nom ne deborde
    /// pas de la place que le placement lui donne (moins d'un point pres). Noms nus ou coupes a 40
    /// caracteres, en ecriture latine, chinoise ou japonaise ; pastille d'une batterie faible ; nom
    /// d'etage, de piece avec son compte, de la maison ; repere « ailleurs ». Les marges sont celles du
    /// dessin (`RenduCanvas.dessinerNoms`).
    @Test func tailleMesureeCommeDessinee() {
        let mesure = MesureNoms()
        let long = CartesPieces.couper("Serrure connectée de la porte arrière, garage")
        #expect(long.count == 40)
        let noms = ["Détecteur de passage lingerie sud ☾", "HomePod mini chambre", "Apple TV 4K 👑", "Salon", long,
                    long + " 👑 ☾ ⚠︎", "客厅吸顶灯 ☾", "寝室のスマートプラグ ⚠︎"]
        let pastilles = [String(localized: "\(12)\u{202F}%"), String(localized: "faible")]
        let comptes = [LibellesNoeuds.compte(1), LibellesNoeuds.compte(12)]
        for echelle in [1.0, 2.0, 3.0] {
            for n in noms {
                for routeur in [false, true] {
                    let dessinee = Self.taillesDessinees([StylesNoms.noeud(n, routeur: routeur, fort: true)],
                                                         echelle: echelle)[0]
                    let place = mesure.noeud(LibellesNoeuds.Libelle(texte: n), routeur: routeur)
                    #expect(dessinee.width + 10 <= place.width + 1 && dessinee.height <= place.height + 1,
                            "\(n) a \(echelle) : \(dessinee) dans \(place)")
                    // Pastille : 5 points, le texte, 5 points, la capsule, 5 points.
                    for v in pastilles {
                        let t = Self.taillesDessinees([DessinNoeud.iconePastille, DessinNoeud.textePastille(v)],
                                                      echelle: echelle)
                        let capsule = DessinNoeud.taillePastille(icone: t[0], valeur: t[1])
                        let avec = mesure.noeud(LibellesNoeuds.Libelle(texte: n, pastille: v, nom: n), routeur: routeur)
                        #expect(5 + ceil(dessinee.width) + 5 + capsule.width + 5 <= avec.width + 1
                                && capsule.height <= avec.height + 1 && dessinee.height <= avec.height + 1,
                                "\(n) et \(v) a \(echelle) : \(dessinee) et \(capsule) dans \(avec)")
                    }
                }
                let t = Self.taillesDessinees([StylesNoms.etage(n)], echelle: echelle)[0]
                let e = mesure.etage(n)
                #expect(t.width <= e.width + 1 && t.height <= e.height + 1)
                // Piece : bordure 1, marge 7, point 8, 6, nom, 6, compte, marge 7, bordure 1 ; 20 de haut.
                for c in comptes {
                    let d = Self.taillesDessinees([StylesNoms.nomPiece(n), StylesNoms.comptePiece(c)], echelle: echelle)
                    let piece = mesure.piece(nom: n, compte: c)
                    #expect(28 + ceil(d[0].width) + d[1].width + 8 <= piece.width + 1
                            && max(d[0].height, d[1].height) <= piece.height + 1,
                            "\(n), \(c) a \(echelle) : \(d) dans \(piece)")
                }
                // Repere « ailleurs » : bordure 1, marge 5, texte, marge 5, bordure 1 ; 1 dessus et dessous.
                let ailleurs = "↓ " + n + " · Chambre d'amis, Rez-de-chaussée"
                let a = Self.taillesDessinees([StylesNoms.ailleurs(ailleurs)], echelle: echelle)[0]
                let place = mesure.ailleurs(ailleurs)
                #expect(a.width + 12 <= place.width + 1 && a.height + 2 <= place.height + 1,
                        "\(ailleurs) a \(echelle) : \(a) dans \(place)")
            }
            let maison = String(localized: "⌂ Maison")
            let m = Self.taillesDessinees([StylesNoms.maison(maison)], echelle: echelle)[0]
            #expect(m.width <= mesure.maison(maison).width + 1 && m.height <= mesure.maison(maison).height + 1)
        }
    }

    /// Le noeud route, dans le moteur (relecture finale, Mineur 11) : les routeurs du dessin sont
    /// les noeuds qui routent, de rang 1 ou 2 ; le nom de chacun est mesure en routeur (12 points), plus large que le
    /// meme texte en appareil.
    @Test func routeursDuMoteur() throws {
        let (_, _, e) = try Self.demo()
        let m = MoteurPiecesTests.moteur(e)
        let routent = e.scene.noeuds.filter(\.route)
        #expect(routent.contains { $0.rang == 2 } && routent.contains { $0.rang == 1 }, "des deux rangs")
        #expect(m.routeurs == Set(routent.map(\.id)) && !m.routeurs.isEmpty)
        let mesure = MesureNoms()
        for n in routent {
            let libelle = try #require(m.textes.noeuds[n.id])
            let taille = try #require(m.etiquettes.first { $0.genre == .noeud(n.id) }?.taille)
            let routeur = mesure.noeud(libelle, routeur: true), appareil = mesure.noeud(libelle, routeur: false)
            #expect(taille == routeur && routeur.width > appareil.width, "\(n.id) : \(taille) \(appareil)")
        }
    }
}
