import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Phase 6, tache 1 : le modele du panneau de sante (`SantePieces`, spec du panneau de sante, section 2). Il lit la scene
/// (`EntreeScene`), le focus (`Isolement`) et le journal, et rend tout ce que le panneau montre : la capsule (comptes de toute
/// la maison), la portee et ses sections, la ligne « Ailleurs ». Les nombres et les noms viennent de mondes inventes (des
/// noeuds de la scene, un par nature : appareil final, appareil qui route, routeur de bordure, routeur Zigbee, coordinateur) ;
/// la demo combinee confirme sur la vraie scene. Les causes sont des valeurs (`SantePieces.Cause`), jamais des textes : ces
/// tests valent dans toutes les langues.
@MainActor
@Suite("Panneau de sante : le modele")
struct SantePiecesTests {
    typealias Cause = SantePieces.Cause
    typealias Comptes = SantePieces.Comptes
    typealias Disparition = SantePieces.Disparition
    typealias Lecture = SantePieces.Lecture
    typealias Ligne = SantePieces.Ligne
    typealias RouteurDisparu = SantePieces.RouteurDisparu

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Mondes inventes

    /// Un noeud invente. `affiche` : l'appareil affiche (nil : un routeur de bordure, un noeud que la sonde seule connait).
    struct Faux {
        var id: IdNoeud
        var nom: String
        /// La piece placee dans la scene (`piecesNoeuds`) ; nil : la carte « Sans piece ».
        var piece: String? = "Salon"
        var genre: GrapheReseau.Genre = .appareil
        var routeur = false
        var bordure = false
        var inconnu = false
        var partition = "P1"
        /// Dans la partition principale : l'apparence d'un routeur de bordure.
        var principale = true
        var affiche: AppareilAffiche?
        /// L'appareil est affiche mais n'a pas de noeud dans la scene : aucune place.
        var horsScene = false
    }

    /// Un appareil du protocole, final ou qui route (`routeur`), place dans `piece`. `pieceMaison` : sa piece selon Maison, quand
    /// ce n'est pas celle ou la scene le place (un choix de l'utilisateur).
    static func appareil(_ cle: String, _ protocole: Protocole = .thread, nom: String? = nil, piece: String? = "Salon",
                         pieceMaison: String? = nil, etat: EtatAffiche = .joignable, batterie: BatterieMaison? = nil,
                         verifie: Bool = false, routeur: Bool = false, horsScene: Bool = false) -> Faux {
        let id = IdNoeud(protocole, cle)
        return Faux(id: id, nom: nom ?? cle, piece: piece, genre: routeur && protocole == .zigbee ? .routeur : .appareil,
                    routeur: routeur,
                    affiche: AppareilAffiche(id: id, nom: nom ?? cle, piece: pieceMaison ?? piece, partition: "P1", etat: etat,
                                             batterie: batterie, verifie: verifie),
                    horsScene: horsScene)
    }

    /// Un routeur de bordure de Thread : ni appareil, ni etat ; sa partition est la principale ou non.
    static func bordure(_ cle: String, piece: String? = "Salon", principale: Bool = true) -> Faux {
        Faux(id: idt(cle), nom: cle, piece: piece, genre: .routeur, routeur: true, bordure: true,
             partition: principale ? "P1" : "P2", principale: principale)
    }

    /// Le coordinateur de Zigbee : le pont, qui est un appareil de lui-meme (`etat` nil : le pont ne dit rien de lui).
    static func coordinateur(_ cle: String, etat: EtatAffiche? = .joignable, piece: String? = "Salon") -> Faux {
        let id = IdNoeud(.zigbee, cle)
        return Faux(id: id, nom: cle, piece: piece, genre: .centre, routeur: true,
                    affiche: etat.map { AppareilAffiche(id: id, nom: cle, piece: piece, partition: "zigbee", etat: $0) })
    }

    /// Un routeur que la sonde seule connait (rien de lui ne dit son etat).
    static func inconnu(_ cle: String, _ protocole: Protocole = .thread) -> Faux {
        Faux(id: IdNoeud(protocole, cle), nom: cle, piece: nil, genre: .routeur, routeur: true, inconnu: true)
    }

    /// Un monde : la scene (deux etages, « Rez » et « Etage »), les libelles, les appareils affiches et les apparences, comme
    /// `EntreeScene` les range. Une coque de demo qui n'a rien recu donne l'entree vide a remplir.
    @MainActor
    struct Monde {
        var faux: [Faux]
        var zones: [ZoneMaison]? = [ZoneMaison(nom: "Rez", pieces: ["Salon", "Cuisine"]),
                                   ZoneMaison(nom: "Etage", pieces: ["Chambre", "Bureau"])]

        func entree() -> EntreeScene {
            var e = EntreeScene(surveillance: Surveillance(mode: .demo, dossier: nil), places: PlacesGardees())
            let dansLaScene = faux.filter { !$0.horsScene }
            let graphe = GrapheReseau(noeuds: dansLaScene.map {
                GrapheReseau.Noeud(id: $0.id, genre: $0.genre, partition: $0.partition, routeur: $0.routeur,
                                   bordure: $0.bordure, inconnu: $0.inconnu)
            })
            let noms = Dictionary(uniqueKeysWithValues: dansLaScene.map { ($0.id, $0.nom) })
            let pieces = Dictionary(uniqueKeysWithValues: dansLaScene.compactMap { f in f.piece.map { (f.id, $0) } })
            let scene = ScenePieces(graphe: graphe, libelles: noms, piecesNoeuds: pieces, zones: zones, chefs: [],
                                    piecesMaison: true, classement: classementThread)
            let appareils = Dictionary(uniqueKeysWithValues: faux.compactMap { f in f.affiche.map { (f.id, $0) } })
            let principales = Dictionary(uniqueKeysWithValues: faux.map { ($0.id, $0.principale) })
            e.graphe = graphe
            e.scene = scene
            e.libelles = noms.mapValues { LibellesNoeuds.Libelle(texte: $0, nom: $0) }
            e.appareils = appareils
            e.apparences = Dictionary(uniqueKeysWithValues: scene.noeuds.map { n in
                (n.id, DessinNoeud.apparence(n, etat: appareils[n.id]?.etat, principale: principales[n.id] ?? true))
            })
            return e
        }
    }

    /// La lecture d'un monde, par la fonction pure (sans coque).
    static func lire(_ faux: [Faux], isolement: Isolement = .maison, montres: Set<Protocole> = [.thread, .zigbee],
                     disparitions: [IdNoeud: Disparition] = [:], routeursDisparus: [RouteurDisparu] = [],
                     sansReleve: Set<Protocole> = []) -> Lecture {
        SantePieces.lire(entree: Monde(faux: faux).entree(), isolement: isolement, montres: montres, disparitions: disparitions,
                         routeursDisparus: routeursDisparus, sansReleve: sansReleve)
    }

    /// Les lignes de toutes les sections.
    static func lignes(_ l: Lecture) -> [Ligne] { l.sections.flatMap(\.lignes) }

    /// Les lignes de la section d'un protocole (aucune si la lecture ne le montre pas).
    static func lignes(_ l: Lecture, _ p: Protocole) -> [Ligne] { l.sections.first { $0.protocole == p }?.lignes ?? [] }

    /// La ligne d'un noeud.
    static func ligne(_ l: Lecture, _ id: IdNoeud) -> Ligne? { lignes(l).first { $0.id == id } }

    /// Les cles des lignes d'un protocole, dans l'ordre.
    static func cles(_ l: Lecture, _ p: Protocole = .thread) -> [String] {
        l.sections.first { $0.protocole == p }?.lignes.map(\.id.cle) ?? []
    }

    static func pile(_ niveau: Int?, alerte: Bool? = nil) -> BatterieMaison { BatterieMaison(niveau: niveau, alerte: alerte) }

    /// Une entree de la capsule.
    static func entree(_ p: Protocole, _ comptes: Comptes?) -> SantePieces.Resume.Entree {
        SantePieces.Resume.Entree(protocole: p, comptes: comptes)
    }

    // MARK: - Le tableau de la spec (2.1), une ligne apres l'autre, pour un appareil et pour un routeur

    /// Perdu, « disparu » : un appareil de Thread et de Zigbee, et un routeur de chacun (« routeur disparu »). La date vient du
    /// journal ; sans elle, « disparu » seul. Un routeur est un noeud qui route, ou que le journal dit routeur (le routeur de
    /// Zigbee sorti du maillage n'a plus de route).
    @Test func perduDisparu() {
        let l = Self.lire([
            Self.appareil("T-app", etat: .disparu),
            Self.appareil("T-rout", etat: .disparu, routeur: true),
            Self.appareil("Z-app", .zigbee, etat: .disparu),
            Self.appareil("Z-rout", .zigbee, etat: .disparu, routeur: true),
            Self.appareil("Z-sorti", .zigbee, etat: .disparu),
            Self.appareil("T-sans-date", etat: .disparu),
        ], disparitions: [
            idt("T-app"): Disparition(depuis: Self.t0, routeur: false),
            idt("Z-rout", .zigbee): Disparition(depuis: Self.t0.addingTimeInterval(60), routeur: true),
            idt("Z-sorti", .zigbee): Disparition(depuis: Self.t0.addingTimeInterval(120), routeur: true),
        ])
        #expect(Self.ligne(l, idt("T-app"))?.cause == .disparu(depuis: Self.t0), "appareil de Thread, date du journal")
        #expect(Self.ligne(l, idt("T-rout"))?.cause == .routeurDisparu(depuis: nil), "appareil qui route : un routeur")
        #expect(Self.ligne(l, idt("Z-app", .zigbee))?.cause == .disparu(depuis: nil), "appareil de Zigbee sans date : « disparu »")
        #expect(Self.ligne(l, idt("Z-rout", .zigbee))?.cause == .routeurDisparu(depuis: Self.t0.addingTimeInterval(60)))
        #expect(Self.ligne(l, idt("Z-sorti", .zigbee))?.cause == .routeurDisparu(depuis: Self.t0.addingTimeInterval(120)),
                "le journal dit routeur un noeud qui n'en a plus la route")
        #expect(Self.ligne(l, idt("T-sans-date"))?.cause == .disparu(depuis: nil))
        #expect(Self.lignes(l).count == 6 && Self.lignes(l).allSatisfy { $0.famille == .perdu && $0.cliquable })
    }

    /// Perdu, « injoignable » (le pont le dit tel) : un appareil et un routeur de Zigbee ; le pont lui-meme (le coordinateur) est
    /// « pont injoignable ».
    @Test func perduInjoignable() {
        let l = Self.lire([
            Self.appareil("Z-app", .zigbee, etat: .injoignable),
            Self.appareil("Z-rout", .zigbee, etat: .injoignable, routeur: true),
            Self.coordinateur("Z-pont", etat: .injoignable),
        ])
        #expect(Self.ligne(l, idt("Z-app", .zigbee))?.cause == .injoignable)
        #expect(Self.ligne(l, idt("Z-rout", .zigbee))?.cause == .injoignable, "un routeur du pont : comme un appareil")
        #expect(Self.ligne(l, idt("Z-pont", .zigbee))?.cause == .pontInjoignable)
        #expect(Self.lignes(l).count == 3 && Self.lignes(l).allSatisfy { $0.famille == .perdu })
        // Le pont qui se dit joignable, ou qui n'a rien a dire, n'est pas dans le panneau.
        for etat in [EtatAffiche.joignable, .inconnu] {
            #expect(Self.lignes(Self.lire([Self.coordinateur("Z-pont", etat: etat)])).isEmpty, "\(etat)")
        }
        #expect(Self.lignes(Self.lire([Self.coordinateur("Z-pont", etat: nil)])).isEmpty)
    }

    /// A surveiller, pile faible : le niveau si l'on a, sinon « faible » ; au plus 20 %, ou l'alerte de l'accessoire. Un appareil
    /// et un routeur des deux protocoles ; l'etat inconnu d'un appareil ne cache pas sa pile.
    @Test func aSurveillerPile() {
        let l = Self.lire([
            Self.appareil("T-app", batterie: Self.pile(12)),
            Self.appareil("T-alerte", batterie: Self.pile(nil, alerte: true)),
            Self.appareil("T-rout", batterie: Self.pile(20), routeur: true),
            Self.appareil("T-bonne", batterie: Self.pile(21)),
            Self.appareil("Z-app", .zigbee, batterie: Self.pile(5)),
            Self.appareil("Z-rout", .zigbee, batterie: Self.pile(nil, alerte: true), routeur: true),
            Self.appareil("Z-inconnu", .zigbee, etat: .inconnu, batterie: Self.pile(8)),
            Self.appareil("Z-sans-pile", .zigbee),
        ])
        #expect(Self.ligne(l, idt("T-app"))?.cause == .pile(niveau: 12))
        #expect(Self.ligne(l, idt("T-alerte"))?.cause == .pile(niveau: nil), "l'accessoire signale lui-meme sa pile : « pile faible »")
        #expect(Self.ligne(l, idt("T-rout"))?.cause == .pile(niveau: 20), "20 % est le seuil : faible")
        #expect(Self.ligne(l, idt("T-bonne")) == nil, "21 % : pas faible")
        #expect(Self.ligne(l, idt("Z-app", .zigbee))?.cause == .pile(niveau: 5))
        #expect(Self.ligne(l, idt("Z-rout", .zigbee))?.cause == .pile(niveau: nil))
        #expect(Self.ligne(l, idt("Z-inconnu", .zigbee))?.cause == .pile(niveau: 8))
        #expect(Self.ligne(l, idt("Z-sans-pile", .zigbee)) == nil)
        #expect(Self.lignes(l).count == 6 && Self.lignes(l).allSatisfy { $0.famille == .aSurveiller })
    }

    /// A surveiller, « adresse plus annoncee » : joignable parce que la sonde l'a trouve (anneau verifie) ; un appareil et un
    /// appareil qui route.
    @Test func aSurveillerAdressePlusAnnoncee() {
        let l = Self.lire([
            Self.appareil("T-app", verifie: true),
            Self.appareil("T-rout", verifie: true, routeur: true),
            Self.appareil("T-ok"),
        ])
        #expect(Self.ligne(l, idt("T-app"))?.cause == .adressePlusAnnoncee)
        #expect(Self.ligne(l, idt("T-rout"))?.cause == .adressePlusAnnoncee)
        #expect(Self.ligne(l, idt("T-ok")) == nil)
        #expect(Self.lignes(l).count == 2 && Self.lignes(l).allSatisfy { $0.famille == .aSurveiller })
    }

    /// A surveiller, « adresse non annoncee » : un appareil sans adresse, et un appareil qui route.
    @Test func aSurveillerAdresseNonAnnoncee() {
        let l = Self.lire([Self.appareil("T-app", etat: .sansAdresse), Self.appareil("T-rout", etat: .sansAdresse, routeur: true)])
        #expect(Self.ligne(l, idt("T-app"))?.cause == .adresseNonAnnoncee)
        #expect(Self.ligne(l, idt("T-rout"))?.cause == .adresseNonAnnoncee)
        #expect(Self.lignes(l).count == 2 && Self.lignes(l).allSatisfy { $0.famille == .aSurveiller })
    }

    /// A surveiller, « autre partition » : un appareil en partition coupee, un appareil qui route, et un routeur de bordure d'une
    /// partition qui n'est pas la principale (sa couleur dans la scene, celle de la legende). Un routeur de bordure de la
    /// principale, ou que la sonde seule connait, n'a rien a signaler.
    @Test func aSurveillerAutrePartition() {
        let l = Self.lire([
            Self.appareil("T-app", etat: .partitionCoupee),
            Self.appareil("T-rout", etat: .partitionCoupee, routeur: true),
            Self.bordure("T-bordure-autre", principale: false),
            Self.bordure("T-bordure"),
            Self.inconnu("T-inconnu"),
        ])
        #expect(Self.ligne(l, idt("T-app"))?.cause == .autrePartition)
        #expect(Self.ligne(l, idt("T-rout"))?.cause == .autrePartition)
        #expect(Self.ligne(l, idt("T-bordure-autre"))?.cause == .autrePartition)
        #expect(Self.ligne(l, idt("T-bordure")) == nil && Self.ligne(l, idt("T-inconnu")) == nil)
        #expect(Self.lignes(l).count == 3 && Self.lignes(l).allSatisfy { $0.famille == .aSurveiller && $0.cliquable })
        let bordure = Self.ligne(l, idt("T-bordure-autre"))
        #expect(bordure?.nom == "T-bordure-autre" && bordure?.piece == "Salon")
    }

    /// Ce qui est hors sujet : un noeud joignable, un etat inconnu, un endormi, le pont joignable, un routeur de bordure de la
    /// principale, un noeud que la sonde seule connait. Le panneau n'a alors rien a signaler : « tout va bien ».
    @Test func horsSujet() {
        var endormi = Self.appareil("T-endormi")
        endormi.affiche?.endormi = true
        let l = Self.lire([
            Self.appareil("T-ok"), endormi, Self.appareil("T-inconnu", etat: .inconnu), Self.appareil("T-rout", routeur: true),
            Self.bordure("T-bordure"), Self.inconnu("T-sonde-seule"), Self.coordinateur("Z-pont"),
            Self.appareil("Z-rout", .zigbee, routeur: true),
        ])
        #expect(Self.lignes(l).isEmpty)
        #expect(l.capsule.entrees == [Self.entree(.thread, Comptes()), Self.entree(.zigbee, Comptes())])
        #expect(l.capsule.toutVaBien && !l.estVide)
        #expect(l.sections.allSatisfy { $0.lignes.isEmpty && !$0.enAttente })
    }

    // MARK: - Un noeud une fois, la cause la plus grave

    /// Un noeud des deux familles n'apparait qu'une fois, dans Perdu, avec la cause de la perte (pas celle de la pile).
    @Test func perduEtASurveillerUneSeuleFois() {
        let l = Self.lire([
            Self.appareil("T-app", etat: .disparu, batterie: Self.pile(5)),
            Self.appareil("Z-rout", .zigbee, etat: .injoignable, batterie: Self.pile(nil, alerte: true), routeur: true),
            Self.appareil("T-ok", batterie: Self.pile(5)),
        ])
        #expect(Self.lignes(l).count == 3, "chaque noeud une fois")
        #expect(Self.ligne(l, idt("T-app"))?.cause == .disparu(depuis: nil))
        #expect(Self.ligne(l, idt("Z-rout", .zigbee))?.cause == .injoignable)
        #expect(Self.ligne(l, idt("T-ok"))?.cause == .pile(niveau: 5))
        #expect(l.sections.first { $0.protocole == .thread }?.comptes == Comptes(perdus: 1, aSurveiller: 1))
        #expect(l.sections.first { $0.protocole == .zigbee }?.comptes == Comptes(perdus: 1, aSurveiller: 0))
    }

    /// Un noeud a surveiller pour deux raisons montre la premiere du tableau : la pile, avant l'adresse plus annoncee, l'adresse
    /// non annoncee et l'autre partition.
    @Test func aSurveillerPourDeuxRaisons() {
        let l = Self.lire([
            Self.appareil("sans-adresse", etat: .sansAdresse, batterie: Self.pile(10)),
            Self.appareil("coupee", etat: .partitionCoupee, batterie: Self.pile(nil, alerte: true)),
            Self.appareil("verifie", batterie: Self.pile(3), verifie: true),
        ])
        #expect(Self.ligne(l, idt("sans-adresse"))?.cause == .pile(niveau: 10))
        #expect(Self.ligne(l, idt("coupee"))?.cause == .pile(niveau: nil))
        #expect(Self.ligne(l, idt("verifie"))?.cause == .pile(niveau: 3))
        #expect(Self.lignes(l).count == 3)
    }

    // MARK: - L'ordre

    /// Perdus d'abord, puis a surveiller ; dans chaque famille, par piece puis par nom, dans l'ordre de la langue (« Lampe 2 »
    /// avant « Lampe 10 ») ; un noeud sans place (hors de la scene) apres les autres. Les sections suivent l'ordre des protocoles.
    @Test func ordreDeTri() {
        let l = Self.lire([
            Self.appareil("p1", nom: "b", piece: "Salon", etat: .disparu),
            Self.appareil("p2", nom: "a", piece: "Cuisine", etat: .disparu),
            Self.appareil("p3", nom: "z", piece: nil, etat: .disparu, horsScene: true),
            Self.appareil("s1", nom: "c", piece: "Cuisine", batterie: Self.pile(9)),
            Self.appareil("s2", nom: "a", piece: "Salon", batterie: Self.pile(9)),
            Self.appareil("s3", nom: "Lampe 10", piece: "Bureau", batterie: Self.pile(9)),
            Self.appareil("s4", nom: "Lampe 2", piece: "Bureau", batterie: Self.pile(9)),
            Self.appareil("s5", nom: "b", piece: "Cuisine", batterie: Self.pile(9)),
            Self.appareil("zx", .zigbee, nom: "x", piece: "Chambre", etat: .disparu),
        ])
        #expect(l.sections.map(\.protocole) == [.thread, .zigbee])
        #expect(Self.cles(l) == ["p2", "p1", "p3", "s4", "s3", "s5", "s1", "s2"], "perdus (Cuisine, Salon, sans place), puis a surveiller")
        #expect(Self.lignes(l, .thread).map(\.famille) == [.perdu, .perdu, .perdu] + Array(repeating: .aSurveiller, count: 5))
        #expect(Self.lignes(l, .thread).map(\.piece) == ["Cuisine", "Salon", nil, "Bureau", "Bureau", "Cuisine", "Cuisine", "Salon"])
        #expect(Self.cles(l, .zigbee) == ["zx"])
    }

    // MARK: - La portee : maison, niveau, piece (par la piece placee)

    /// Un monde sur deux niveaux : le salon et la cuisine au « Rez », la chambre et le bureau a l'« Etage », et un noeud sans
    /// place. Chaque famille y est, des deux protocoles.
    static let mondePortee: [Faux] = [
        appareil("t-salon", piece: "Salon", etat: .disparu),
        appareil("z-salon", .zigbee, piece: "Salon", batterie: pile(15)),
        appareil("t-cuisine", piece: "Cuisine", etat: .sansAdresse),
        appareil("t-chambre", piece: "Chambre", etat: .disparu),
        appareil("z-chambre", .zigbee, piece: "Chambre", etat: .injoignable),
        appareil("t-bureau", piece: "Bureau"),
        appareil("t-absent", piece: nil, etat: .disparu, horsScene: true),
    ]

    static let capsuleDuMondePortee = [entree(.thread, Comptes(perdus: 3, aSurveiller: 1)),
                                       entree(.zigbee, Comptes(perdus: 1, aSurveiller: 1))]

    /// La vue d'ensemble : toute la maison, le titre « Maison », rien « ailleurs ». La capsule compte la maison.
    @Test func porteeMaison() {
        let l = Self.lire(Self.mondePortee)
        #expect(l.portee == .maison && l.ailleurs == nil)
        #expect(Set(Self.cles(l)) == ["t-salon", "t-cuisine", "t-chambre", "t-absent"])
        #expect(Set(Self.cles(l, .zigbee)) == ["z-salon", "z-chambre"])
        #expect(l.capsule.entrees == Self.capsuleDuMondePortee)
    }

    /// Un niveau isole : ses pieces seulement, le nom du niveau pour titre ; le reste est « ailleurs ».
    @Test func porteeNiveau() {
        let l = Self.lire(Self.mondePortee, isolement: .etage("zone:Etage"))
        #expect(l.portee == .etage("Etage"))
        #expect(Self.cles(l) == ["t-chambre"] && Self.cles(l, .zigbee) == ["z-chambre"])
        #expect(l.sections.map(\.comptes) == [Comptes(perdus: 1), Comptes(perdus: 1)])
        // Hors du niveau : le salon (perdu et pile), la cuisine (sans adresse), le noeud sans place (perdu).
        #expect(l.ailleurs == Comptes(perdus: 2, aSurveiller: 2))
        #expect(l.capsule.entrees == Self.capsuleDuMondePortee, "la capsule compte toujours la maison")
    }

    /// Une piece isolee (d'ou qu'on l'ait ouverte) : ses noeuds, son nom pour titre ; le reste est « ailleurs ».
    @Test func porteePiece() {
        for provenance in [nil, "zone:Rez", "zone:Etage"] {
            let l = Self.lire(Self.mondePortee, isolement: .piece("piece:Salon", provenance: provenance))
            #expect(l.portee == .piece("Salon"))
            #expect(Self.cles(l) == ["t-salon"] && Self.cles(l, .zigbee) == ["z-salon"])
            #expect(l.ailleurs == Comptes(perdus: 3, aSurveiller: 1), "chambre (2), sans place (1), cuisine (1)")
            #expect(l.capsule.entrees == Self.capsuleDuMondePortee)
        }
        // Une piece sans rien a signaler : ses sections sont vides (« Rien a signaler »), tout le reste est « ailleurs ».
        let propre = Self.lire(Self.mondePortee, isolement: .piece("piece:Bureau", provenance: nil))
        #expect(propre.portee == .piece("Bureau") && Self.lignes(propre).isEmpty)
        #expect(propre.sections.map(\.protocole) == [.thread, .zigbee] && propre.sections.allSatisfy { !$0.enAttente })
        #expect(propre.ailleurs == Comptes(perdus: 4, aSurveiller: 2))
    }

    /// La ligne « Ailleurs » n'existe pas quand tout est dans la portee, ni a la vue d'ensemble ; elle compte les deux familles
    /// de tous les protocoles montres.
    @Test func ailleursAbsentSiRienHorsPortee() {
        let seul = Self.lire([Self.appareil("t-salon", piece: "Salon", etat: .disparu)], isolement: .piece("piece:Salon", provenance: nil))
        #expect(Self.cles(seul) == ["t-salon"] && seul.ailleurs == nil, "rien hors de la piece : pas de ligne")
        let tout = Self.lire([Self.appareil("t-salon", piece: "Salon", etat: .disparu), Self.appareil("t-bureau", piece: "Bureau")],
                             isolement: .etage("zone:Rez"))
        #expect(Self.cles(tout) == ["t-salon"] && tout.ailleurs == nil)
    }

    /// La portee se compte sur la piece PLACEE dans la scene, pas sur la piece de Maison : un noeud que l'on a place dans le
    /// salon alors que Maison le met dans la cuisine est au salon (colonne « piece », tri, niveau et piece isolee).
    @Test func pieceDuNoeudEstCellePlacee() {
        let monde = [Self.appareil("t1", piece: "Salon", pieceMaison: "Cuisine", etat: .disparu),
                     Self.appareil("t2", piece: "Chambre", pieceMaison: "Salon", etat: .disparu),
                     Self.appareil("t3", piece: "Cuisine")]
        let salon = Self.lire(monde, isolement: .piece("piece:Salon", provenance: nil))
        #expect(Self.cles(salon) == ["t1"] && Self.ligne(salon, idt("t1"))?.piece == "Salon")
        #expect(salon.ailleurs == Comptes(perdus: 1))
        let cuisine = Self.lire(monde, isolement: .piece("piece:Cuisine", provenance: nil))
        #expect(Self.lignes(cuisine).isEmpty, "Maison le met dans la cuisine, la scene non")
        let etage = Self.lire(monde, isolement: .etage("zone:Etage"))
        #expect(Self.cles(etage) == ["t2"] && Self.ligne(etage, idt("t2"))?.piece == "Chambre")
        let rez = Self.lire(monde, isolement: .etage("zone:Rez"))
        #expect(Self.cles(rez) == ["t1"])
    }

    /// Un noeud sans piece placee (affiche, mais sans place dans la scene) compte dans la portee « Maison » ; hors de la vue
    /// d'ensemble, dans « Ailleurs ». Sa ligne n'est pas cliquable et n'a pas de piece. La carte « Sans piece » est une piece de la
    /// scene : ses noeuds s'y voient, leur ligne est cliquable et dit « Sans piece ».
    @Test func noeudSansPiecePlacee() {
        let monde = [Self.appareil("sans-place", piece: nil, etat: .disparu, horsScene: true),
                     Self.appareil("carte", piece: nil, etat: .disparu),
                     Self.appareil("salon", piece: "Salon", etat: .disparu)]
        let maison = Self.lire(monde)
        let sansPlace = Self.ligne(maison, idt("sans-place"))
        #expect(sansPlace?.piece == nil && sansPlace?.cliquable == false)
        let carte = Self.ligne(maison, idt("carte"))
        #expect(carte?.piece == LibellesNoeuds.nom(ScenePieces.NomPiece.sansPiece, libelles: [:]) && carte?.cliquable == true)
        #expect(Self.ligne(maison, idt("salon"))?.cliquable == true)
        let salon = Self.lire(monde, isolement: .piece("piece:Salon", provenance: nil))
        #expect(Self.cles(salon) == ["salon"] && salon.ailleurs == Comptes(perdus: 2), "le noeud sans place est « ailleurs »")
        let sansPiece = Self.lire(monde, isolement: .piece("sans-piece", provenance: nil))
        #expect(Self.cles(sansPiece) == ["carte"] && sansPiece.ailleurs == Comptes(perdus: 2))
    }

    /// Un focus que la scene ne connait pas (etage ou piece disparus, le moteur recale a la maison) lit la maison.
    @Test func focusInconnuLitLaMaison() {
        let maison = Self.lire(Self.mondePortee)
        #expect(!Self.lignes(maison).isEmpty && maison.portee == .maison)
        #expect(Self.lire(Self.mondePortee, isolement: .etage("zone:Nulle part")) == maison)
        #expect(Self.lire(Self.mondePortee, isolement: .piece("piece:Nulle part", provenance: nil)) == maison)
    }

    /// Le titre d'un etage est son nom comme la scene le dit (les etages par defaut ont un nom traduit) ; celui d'une piece, son
    /// nom comme la carte le dit.
    @Test func titresDeLaPortee() throws {
        let sansZones = Monde(faux: [Self.appareil("t", piece: "Salon", etat: .disparu)], zones: nil).entree()
        let plateaux = sansZones.scene.etages
        #expect(plateaux.count == 1)
        let plateau = try #require(plateaux.first)
        let l = SantePieces.lire(entree: sansZones, isolement: .etage(plateau.id), montres: [.thread])
        #expect(l.portee == .etage(LibellesNoeuds.nom(plateau.nom)))
        let autres = Monde(faux: [Self.appareil("t", piece: "Garage", etat: .disparu)]).entree()
        let e = try #require(autres.scene.pieces.first.map { autres.scene.etages[$0.etage] })
        #expect(e.nom == .autresPieces)
        let a = SantePieces.lire(entree: autres, isolement: .etage(e.id), montres: [.thread])
        #expect(a.portee == .etage(LibellesNoeuds.nom(ScenePieces.NomEtage.autresPieces)))
        #expect(Self.cles(a) == ["t"])
    }

    // MARK: - La capsule

    /// Les comptes de la capsule portent toujours sur toute la maison, quel que soit le focus.
    @Test func capsuleToujoursMaison() {
        let maison = Self.lire(Self.mondePortee).capsule
        for iso in [Isolement.etage("zone:Rez"), .etage("zone:Etage"), .piece("piece:Chambre", provenance: nil),
                    .piece("piece:Bureau", provenance: "zone:Etage")] {
            #expect(Self.lire(Self.mondePortee, isolement: iso).capsule == maison, "\(iso)")
        }
        #expect(maison.entrees == Self.capsuleDuMondePortee && !maison.toutVaBien)
    }

    /// « Tout va bien » : un releve de chaque protocole montre et rien a signaler. Un seul noeud fautif, et plus.
    @Test func toutVaBien() {
        let sain = Self.lire([Self.appareil("t"), Self.appareil("z", .zigbee)])
        #expect(sain.capsule.toutVaBien)
        let fautif = Self.lire([Self.appareil("t"), Self.appareil("z", .zigbee, batterie: Self.pile(3))])
        #expect(!fautif.capsule.toutVaBien)
        // Pas de protocole montre : la lecture est vide, et ne dit pas « tout va bien ».
        let vide = Self.lire([])
        #expect(vide.estVide && !vide.capsule.toutVaBien && vide.sections.isEmpty && vide.ailleurs == nil)
    }

    /// Un protocole actif et montre qui n'a encore aucun releve montre « … » (comptes nil), jamais « tout va bien » : meme sans
    /// aucun noeud. Avec un noeud fautif deja connu, ce sont ses comptes qui comptent. Sans releve et sans noeud, un protocole qui
    /// n'est pas en attente n'est pas montre.
    @Test func pointsDeSuspension() {
        let enAttente = Self.lire([Self.appareil("t"), Self.appareil("z", .zigbee)], sansReleve: [.zigbee])
        #expect(enAttente.capsule.entrees == [Self.entree(.thread, Comptes()), Self.entree(.zigbee, nil)])
        #expect(!enAttente.capsule.toutVaBien, "un protocole qui attend son releve : pas de « tout va bien »")
        #expect(enAttente.sections.map(\.enAttente) == [false, true] && Self.lignes(enAttente, .zigbee).isEmpty)
        // Aucun noeud : les deux attendent leur releve.
        let rien = Self.lire([], sansReleve: [.thread, .zigbee])
        #expect(rien.capsule.entrees == [Self.entree(.thread, nil), Self.entree(.zigbee, nil)])
        #expect(!rien.capsule.toutVaBien && !rien.estVide && rien.sections.allSatisfy(\.enAttente))
        // Sans releve mais avec un noeud perdu : un noeud fautif n'est jamais cache.
        let faute = Self.lire([Self.appareil("z", .zigbee, etat: .injoignable)], sansReleve: [.zigbee])
        #expect(faute.capsule.entrees == [Self.entree(.zigbee, Comptes(perdus: 1))])
        #expect(faute.sections.map(\.enAttente) == [false] && Self.cles(faute, .zigbee) == ["z"])
        // Releve fait, aucun noeud : le protocole n'a rien a montrer.
        #expect(Self.lire([]).estVide)
    }

    // MARK: - Les protocoles montres

    /// Un protocole masque (interrupteur de la vue) ou eteint n'est pas dans `montres` : il disparait du panneau, capsule,
    /// sections, « Ailleurs » et routeurs du journal compris ; son releve manquant ne le montre pas.
    @Test func protocoleMasque() {
        let monde = Self.mondePortee
        let disparu = RouteurDisparu(id: idt("Z-routeur", .zigbee), nom: "Routeur Zigbee", depuis: Self.t0)
        let thread = Self.lire(monde, montres: [.thread], routeursDisparus: [disparu], sansReleve: [.zigbee])
        #expect(thread.capsule.entrees == [Self.entree(.thread, Comptes(perdus: 3, aSurveiller: 1))])
        #expect(thread.sections.map(\.protocole) == [.thread])
        #expect(Self.lignes(thread).allSatisfy { $0.id.protocole == .thread })
        let piece = Self.lire(monde, isolement: .piece("piece:Salon", provenance: nil), montres: [.thread])
        #expect(piece.ailleurs == Comptes(perdus: 2, aSurveiller: 1), "chambre et sans place, cuisine : les noeuds de Thread seuls")
        let zigbee = Self.lire(monde, montres: [.zigbee], routeursDisparus: [disparu])
        #expect(zigbee.capsule.entrees == [Self.entree(.zigbee, Comptes(perdus: 2, aSurveiller: 1))], "le routeur du journal compte")
        #expect(Self.lire(monde, montres: []).estVide)
    }

    // MARK: - Depuis quand : le journal

    private static func evenement(_ type: TypeEvenement, _ sujet: String?, _ decalage: TimeInterval, _ protocole: Protocole? = .thread,
                                  reseau: String? = nil) -> Evenement {
        Evenement(date: t0.addingTimeInterval(decalage), type: type, reseau: reseau,
                  sujet: sujet.map { Sujet(id: $0, nom: "Nom de " + $0) }, protocole: protocole)
    }

    /// La disparition en cours d'un noeud : la plus recente des disparitions (appareil ou routeur) de son journal, dans
    /// n'importe quel ordre ; un retour, un changement de parent ne comptent pas ; le type dit si c'etait un routeur.
    @Test func disparitionLaPlusRecente() {
        let evenements = [Self.evenement(.appareilDisparu, "x", 0), Self.evenement(.appareilRevenu, "x", 30),
                          Self.evenement(.appareilDisparu, "x", 120), Self.evenement(.parentChange, "x", 500),
                          Self.evenement(.routeurDisparu, "x", 60)]
        let attendu = Disparition(depuis: Self.t0.addingTimeInterval(120), routeur: false)
        #expect(Disparition.plusRecente(parmi: evenements) == attendu)
        #expect(Disparition.plusRecente(parmi: evenements.reversed()) == attendu, "l'ordre du journal n'y change rien")
        #expect(Disparition.plusRecente(parmi: evenements + [Self.evenement(.routeurDisparu, "x", 200)])
                == Disparition(depuis: Self.t0.addingTimeInterval(200), routeur: true))
        #expect(Disparition.plusRecente(parmi: [Self.evenement(.appareilRevenu, "x", 0), Self.evenement(.sansParent, "x", 5)]) == nil)
        #expect(Disparition.plusRecente(parmi: []) == nil)
    }

    /// Le journal n'est lu que pour les noeuds disparus ; un noeud disparu sans evenement n'a pas de date.
    @Test func disparitionsDesNoeudsDisparus() {
        let entree = Monde(faux: [Self.appareil("a", etat: .disparu), Self.appareil("b"), Self.appareil("c", .zigbee, etat: .disparu),
                                  Self.appareil("d", etat: .injoignable), Self.appareil("e", etat: .disparu)]).entree()
        var demandes: [IdNoeud] = []
        let d = SantePieces.disparitions(entree: entree) { id in
            demandes.append(id)
            guard id.cle != "e" else { return [] }
            return [Self.evenement(id.cle == "a" ? .appareilDisparu : .routeurDisparu, id.cle, 10, id.protocole)]
        }
        #expect(Set(demandes) == [idt("a"), idt("c", .zigbee), idt("e")], "les noeuds disparus, et eux seuls")
        #expect(d == [idt("a"): Disparition(depuis: Self.t0.addingTimeInterval(10), routeur: false),
                      idt("c", .zigbee): Disparition(depuis: Self.t0.addingTimeInterval(10), routeur: true)])
    }

    /// Les routeurs que le journal dit disparus : un `routeurDisparu` que rien n'a suivi (ni retour du routeur, ni nouveau
    /// depart du protocole). Un appareil n'est pas un routeur ; un evenement sans sujet est ignore ; une ligne sans protocole est
    /// de Thread ; le routeur disparu deux fois garde la derniere date.
    @Test func routeursDisparusDuJournal() {
        func disparu(_ cle: String, _ p: Protocole, _ decalage: TimeInterval) -> RouteurDisparu {
            RouteurDisparu(id: IdNoeud(p, cle), nom: "Nom de " + cle, depuis: Self.t0.addingTimeInterval(decalage))
        }
        let journal = [
            Self.evenement(.routeurDisparu, "HomePod A", 10), Self.evenement(.routeurDisparu, "HomePod B", 20),
            Self.evenement(.routeurApparu, "HomePod B", 30), Self.evenement(.routeurDisparu, "Z1", 40, .zigbee),
            Self.evenement(.appareilDisparu, "Lampe", 50), Self.evenement(.routeurDisparu, nil, 60),
            Self.evenement(.routeurDisparu, "HomePod C", 70, nil),
        ]
        #expect(SantePieces.routeursDisparus(journal: journal)
                == [disparu("HomePod A", .thread, 10), disparu("HomePod C", .thread, 70), disparu("Z1", .zigbee, 40)])
        #expect(SantePieces.routeursDisparus(journal: []).isEmpty)
        // Disparu, revenu, disparu de nouveau : la derniere disparition.
        let deNouveau = journal + [Self.evenement(.routeurDisparu, "HomePod B", 80)]
        #expect(SantePieces.routeursDisparus(journal: deNouveau).contains(disparu("HomePod B", .thread, 80)))
        // Un nouveau depart de Thread (relance de l'app, Thread rallume) efface ce que le journal disait de Thread, pas de Zigbee.
        let relance = journal + [Self.evenement(.surveillanceDemarree, nil, 100, .thread)]
        #expect(SantePieces.routeursDisparus(journal: relance) == [disparu("Z1", .zigbee, 40)])
        let avantRelance = [Self.evenement(.surveillanceDemarree, nil, 0, .thread)] + journal
        #expect(SantePieces.routeursDisparus(journal: avantRelance).count == 3, "un depart d'avant ne change rien")
        // Le depart d'un reseau vu pour la premiere fois (reseau donne) n'efface rien.
        let autreReseau = journal + [Self.evenement(.surveillanceDemarree, nil, 100, .thread, reseau: "xp")]
        #expect(SantePieces.routeursDisparus(journal: autreReseau).count == 3)
        // Un protocole qui n'a pas encore de releve de la session : son journal est celui d'une session passee.
        #expect(SantePieces.routeursDisparus(journal: journal, releves: [.zigbee]) == [disparu("Z1", .zigbee, 40)])
        #expect(SantePieces.routeursDisparus(journal: journal, releves: [.thread]).map(\.id.protocole) == [.thread, .thread])
        #expect(SantePieces.routeursDisparus(journal: journal, releves: []).isEmpty)
    }

    /// Un routeur disparu du journal (il a quitte la scene) est une ligne perdue : le nom du journal, « routeur disparu depuis »,
    /// sans piece, non cliquable. Dans la portee « Maison » ; hors d'elle, « Ailleurs ». Un routeur qui est dans la scene, ou
    /// parmi les appareils, n'est pas compte deux fois ; celui d'un protocole masque non plus.
    @Test func routeurDisparuDuJournalDansLaLecture() {
        let bordure = RouteurDisparu(id: idt("HomePod salon"), nom: "HomePod du salon", depuis: Self.t0)
        let zigbee = RouteurDisparu(id: idt("Z-routeur", .zigbee), nom: "Routeur du couloir", depuis: Self.t0.addingTimeInterval(60))
        let l = Self.lire([Self.appareil("t", etat: .disparu)], routeursDisparus: [bordure, zigbee])
        let ligne = Self.ligne(l, idt("HomePod salon"))
        #expect(ligne == Ligne(id: idt("HomePod salon"), nom: "HomePod du salon", piece: nil,
                               cause: .routeurDisparu(depuis: Self.t0), cliquable: false))
        #expect(Self.ligne(l, idt("Z-routeur", .zigbee))?.cause == .routeurDisparu(depuis: Self.t0.addingTimeInterval(60)))
        #expect(l.capsule.entrees == [Self.entree(.thread, Comptes(perdus: 2)), Self.entree(.zigbee, Comptes(perdus: 1))],
                "le routeur disparu fait montrer son protocole, meme sans noeud dans la scene")
        let salon = Self.lire([Self.appareil("t", etat: .disparu)], isolement: .piece("piece:Salon", provenance: nil),
                              routeursDisparus: [bordure, zigbee])
        #expect(Self.cles(salon) == ["t"] && salon.ailleurs == Comptes(perdus: 2), "sans place : « Ailleurs »")
        // Revenu dans la scene (meme id) : la ligne du noeud, une seule fois, avec ses etats.
        let revenu = Self.lire([Self.bordure("HomePod salon", principale: false)], routeursDisparus: [bordure])
        #expect(Self.lignes(revenu).count == 1 && Self.ligne(revenu, idt("HomePod salon"))?.cause == .autrePartition)
        let affiche = Self.lire([Self.appareil("Z-routeur", .zigbee, etat: .disparu, routeur: true)], routeursDisparus: [zigbee])
        #expect(Self.lignes(affiche).count == 1 && Self.ligne(affiche, idt("Z-routeur", .zigbee))?.nom == "Z-routeur")
        let masque = Self.lire([], montres: [.thread], routeursDisparus: [bordure, zigbee])
        #expect(Self.cles(masque) == ["HomePod salon"] && masque.sections.map(\.protocole) == [.thread])
        // Deux fois le meme routeur dans la liste : une ligne, la derniere disparition.
        var plusTard = bordure
        plusTard.depuis = Self.t0.addingTimeInterval(500)
        for liste in [[bordure, plusTard], [plusTard, bordure]] {
            let deux = Self.lire([], routeursDisparus: liste)
            #expect(Self.lignes(deux).map(\.cause) == [.routeurDisparu(depuis: plusTard.depuis)])
        }
    }

    /// De bout en bout, par le vrai suivi : un routeur de bordure de Thread qui n'est plus annonce (le suivi le dit disparu apres
    /// 2 min, date de sa premiere absence) quitte la scene, et le journal le garde ; le panneau le montre perdu, sans place et
    /// sans clic. Il revient (`routeurApparu`) : il n'est plus perdu.
    @Test func routeurDeBordureDisparuDeBoutEnBout() throws {
        let s = DemoCombineeTests.combinee()
        let depart = ScenarioPanne.fin
        var absent = ScenarioPanne.annonces(a: depart.addingTimeInterval(60))
        absent.routeurs.removeAll { $0.instance == "HomePod Palier" }
        s.thread.integrer(absent)
        func disparition() -> Evenement? { s.evenements.last { $0.type == .routeurDisparu && $0.sujet?.id == "HomePod Palier" } }
        #expect(disparition() == nil, "dans le sursis de 2 min : rien")
        absent.date = depart.addingTimeInterval(240)
        s.thread.integrer(absent)
        let evenement = try #require(disparition())
        #expect(evenement.protocole == .thread && evenement.date == depart.addingTimeInterval(60))
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(e.scene.noeud(idt("HomePod Palier")) == nil, "le routeur a quitte la scene")
        let l = SantePieces.lire(entree: e, isolement: .maison, surveillance: s)
        let ligne = try #require(Self.ligne(l, idt("HomePod Palier")))
        #expect(ligne.cause == .routeurDisparu(depuis: depart.addingTimeInterval(60)) && ligne.piece == nil && !ligne.cliquable)
        #expect(ligne.nom == evenement.sujet?.nom && ligne.famille == .perdu)
        #expect(l.capsule.entrees.first?.comptes == Comptes(perdus: 5, aSurveiller: 4), "les quatre appareils perdus et le routeur")
        // Il revient.
        s.thread.integrer(ScenarioPanne.annonces(a: depart.addingTimeInterval(300)))
        #expect(s.evenements.last?.type == .routeurApparu)
        let revenu = SantePieces.lire(entree: EntreeScene(surveillance: s, places: PlacesGardees()), isolement: .maison,
                                      surveillance: s)
        #expect(Self.ligne(revenu, idt("HomePod Palier")) == nil, "revenu : plus perdu")
        #expect(revenu.capsule.entrees.first?.comptes == Comptes(perdus: 4, aSurveiller: 4))
    }

    /// Le journal garde 90 jours : un routeur disparu d'une session passee ne se montre pas avant le premier releve de celle-ci
    /// (Thread n'a pas d'instantane ; Zigbee n'a que le maillage relu au lancement), ni apres (ce premier releve est un nouveau
    /// depart) ; un routeur qui disparait pendant la session se montre, et revient avec elle.
    @Test func routeurDisparuDUneSessionPassee() throws {
        func lecture(_ s: Surveillance) -> Lecture {
            SantePieces.lire(entree: EntreeScene(surveillance: s, places: PlacesGardees()), isolement: .maison, surveillance: s)
        }
        // Thread : hier, un routeur a disparu.
        let thread = Surveillance(mode: .direct, dossier: nil)
        thread.ajouter([Self.evenement(.routeurDisparu, "Vieux HomePod", -86_400)], de: .thread)
        #expect(SantePieces.releveDeLaSession(thread).isEmpty)
        let avant = lecture(thread)
        #expect(Self.lignes(avant).isEmpty && avant.capsule.entrees == [Self.entree(.thread, nil), Self.entree(.zigbee, nil)])
        thread.thread.integrer(ScenarioPanne.annonces(a: ScenarioPanne.fin))
        #expect(SantePieces.releveDeLaSession(thread) == [.thread])
        #expect(Self.ligne(lecture(thread), idt("Vieux HomePod")) == nil, "le premier releve de la session est un nouveau depart")
        // Zigbee : le maillage relu au lancement est un releve a montrer, pas un releve de la session.
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let ecriture = Surveillance(mode: .direct, dossier: dossier)
        ecriture.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        let zigbee = Surveillance(mode: .direct, dossier: dossier)
        zigbee.zigbee.chargerMaillageGarde()
        zigbee.ajouter([Self.evenement(.routeurDisparu, "Z-vieux", -86_400, .zigbee)], de: .zigbee)
        #expect(zigbee.zigbee.maillageRelu && SantePieces.sansReleve(zigbee) == [.thread])
        #expect(SantePieces.releveDeLaSession(zigbee).isEmpty)
        #expect(Self.ligne(lecture(zigbee), idt("Z-vieux", .zigbee)) == nil, "pas avant la premiere tournee de la session")
        // La premiere tournee de la session (un nouveau depart), puis la suivante, ou la prise du salon (un routeur que le pont ne
        // donne pas ici) a quitte le maillage : elle se montre, perdue.
        zigbee.zigbee.recevoir(MaillageDemoZigbee.maillageAvant, a: Date().addingTimeInterval(-60))
        #expect(SantePieces.releveDeLaSession(zigbee) == [.zigbee])
        let prise = idt(NomsDemo.Ieee.priseSalon, .zigbee)
        let milieu = lecture(zigbee)
        #expect(Self.ligne(milieu, idt("Z-vieux", .zigbee)) == nil && Self.ligne(milieu, prise) == nil)
        zigbee.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        let apres = lecture(zigbee)
        let perdue = try #require(Self.ligne(apres, prise), "le routeur sorti du maillage")
        #expect(perdue.cause == .routeurDisparu(depuis: MaillageDemoZigbee.fin) && perdue.famille == .perdu && !perdue.cliquable)
        #expect(Self.ligne(apres, idt("Z-vieux", .zigbee)) == nil)
        // Elle revient avec le maillage qui la reprend.
        zigbee.zigbee.recevoir(MaillageDemoZigbee.maillageAvant, a: Date())
        #expect(Self.ligne(lecture(zigbee), prise) == nil, "revenue dans le maillage : plus perdue")
    }

    // MARK: - La demo combinee

    /// La demo combinee, lue par la coque : la lecture n'est pas vide, ne contient que des noeuds de la demo (chacun une fois), et
    /// dit ce que la demo a de fautif : les quatre appareils perdus de la panne de Thread, un sans adresse, un routeur de bordure
    /// de la partition coupee, deux piles faibles ; chez Zigbee, la prise (un routeur) sortie du maillage, deux piles faibles.
    @Test func demoCombinee() throws {
        let s = DemoCombineeTests.combinee()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let l = SantePieces.lire(entree: e, isolement: .maison, surveillance: s)
        let lignes = Self.lignes(l)
        #expect(!l.estVide && !lignes.isEmpty)
        let noeuds = Set(e.scene.noeuds.map(\.id))
        #expect(lignes.allSatisfy { noeuds.contains($0.id) && $0.cliquable }, "uniquement des noeuds de la demo, tous dans la scene")
        #expect(Set(lignes.map(\.id)).count == lignes.count, "chaque noeud une fois")
        #expect(l.sections.map(\.protocole) == [.thread, .zigbee] && l.portee == .maison && l.ailleurs == nil)
        func cause(_ cle: String, _ p: Protocole = .thread) -> Cause? { Self.ligne(l, IdNoeud(p, cle))?.cause }
        for (hote, absentDes) in ScenarioPanne.perdus {
            #expect(cause(hote) == .disparu(depuis: absentDes), "\(hote) : perdu depuis la panne")
        }
        #expect(cause("1E5019DAC2638F92") == .adresseNonAnnoncee)
        #expect(cause("Aqara HubM100 #DFEB") == .autrePartition, "le routeur de bordure de la partition coupee")
        #expect(cause("3A5DFAFCAB581AAF") == .pile(niveau: 12))
        #expect(cause("462DA5B311AFFCC7") == .pile(niveau: nil))
        #expect(cause(NomsDemo.Ieee.priseSalon, .zigbee) == .routeurDisparu(depuis: ScenarioPanne.fin),
                "la prise de Zigbee, un routeur sorti du maillage")
        #expect(cause(NomsDemo.Ieee.telecommandeChambre, .zigbee) == .pile(niveau: 12))
        #expect(cause(NomsDemo.Ieee.capteurGrenier, .zigbee) == .pile(niveau: nil))
        #expect(lignes.count == 11, "rien d'autre")
        #expect(l.capsule.entrees == [Self.entree(.thread, Comptes(perdus: 4, aSurveiller: 4)),
                                      Self.entree(.zigbee, Comptes(perdus: 1, aSurveiller: 2))])
        #expect(!l.capsule.toutVaBien)
        // Perdus d'abord, dans chaque section.
        for section in l.sections {
            #expect(section.lignes.map(\.famille) == section.lignes.map(\.famille).sorted(), "\(section.protocole)")
        }
    }

    /// Dans la demo combinee, quel que soit le focus (la maison, chaque niveau, chaque piece) : la capsule ne change pas, et la
    /// portee et « Ailleurs » se partagent exactement les noeuds de la maison.
    @Test func demoCombineeParPortee() throws {
        let s = DemoCombineeTests.combinee()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let maison = SantePieces.lire(entree: e, isolement: .maison, surveillance: s)
        let total = maison.capsule.entrees.reduce(Comptes()) { $0 + ($1.comptes ?? Comptes()) }
        var focus: [Isolement] = e.scene.etages.map { Isolement.etage($0.id) }
        focus += e.scene.pieces.map { Isolement.piece($0.id, provenance: nil) }
        #expect(focus.count == 4 + 13)
        for iso in focus {
            let l = SantePieces.lire(entree: e, isolement: iso, surveillance: s)
            #expect(l.capsule == maison.capsule, "\(iso)")
            let dedans = l.sections.reduce(Comptes()) { $0 + $1.comptes }
            #expect(dedans + (l.ailleurs ?? Comptes()) == total, "la portee et « Ailleurs » partagent la maison : \(iso)")
            #expect(l.ailleurs?.estVide != true, "pas de ligne « Ailleurs » a zero")
        }
        // Le niveau « Etage » (Bureau, Chambre, Chambre d'amis, Salle de bain) : quatre noeuds.
        let etage = try #require(e.scene.etages.first { $0.nom == .zone("Étage") })
        let l = SantePieces.lire(entree: e, isolement: .etage(etage.id), surveillance: s)
        #expect(l.portee == .etage("Étage"))
        #expect(Set(Self.lignes(l).map(\.id)) == [idt("46F77B36E071F8D0"), idt("D661EE20B3E97C66"), idt("462DA5B311AFFCC7"),
                                                  IdNoeud(.zigbee, NomsDemo.Ieee.telecommandeChambre)])
        #expect(l.ailleurs == Comptes(perdus: 3, aSurveiller: 4))
        // La chambre : un noeud perdu et une pile faible de Thread, la telecommande de Zigbee.
        let chambre = try #require(e.scene.pieces.first { $0.nom == .maison("Chambre") })
        let c = SantePieces.lire(entree: e, isolement: .piece(chambre.id, provenance: nil), surveillance: s)
        #expect(c.portee == .piece("Chambre") && Self.cles(c) == ["D661EE20B3E97C66", "462DA5B311AFFCC7"])
        #expect(Self.cles(c, .zigbee) == [NomsDemo.Ieee.telecommandeChambre])
    }

    /// Les protocoles sans releve, d'apres la coque : Thread tant qu'il n'a pas d'instantane, Zigbee tant qu'il n'a pas de
    /// maillage a montrer. Avant tout releve, la lecture dit « … » pour les deux (une coque directe qui n'ecoute rien) ; la demo
    /// d'un seul protocole ne montre que lui, l'autre est muet. Une pile faible connue se montre sans attendre le releve : un
    /// noeud fautif n'est jamais cache.
    @Test func sansReleveSelonLaCoque() {
        let direct = Surveillance(mode: .direct, dossier: nil)
        #expect(SantePieces.sansReleve(direct) == [.thread, .zigbee])
        let attente = SantePieces.lire(entree: EntreeScene(surveillance: direct, places: PlacesGardees()), isolement: .maison,
                                       surveillance: direct)
        #expect(attente.capsule.entrees == [Self.entree(.thread, nil), Self.entree(.zigbee, nil)])
        #expect(!attente.capsule.toutVaBien && !attente.estVide && attente.sections.allSatisfy { $0.enAttente && $0.lignes.isEmpty })
        #expect(SantePieces.sansReleve(DemoCombineeTests.combinee()).isEmpty, "la demo a rejoue ses deux releves")
        // La demo combinee avant son demarrage : les noms du pont sont la, pas le maillage ; les piles faibles se voient deja.
        let avant = Surveillance(mode: .demo, dossier: nil, demo: .combinee)
        #expect(SantePieces.sansReleve(avant) == [.thread, .zigbee])
        let l = SantePieces.lire(entree: EntreeScene(surveillance: avant, places: PlacesGardees()), isolement: .maison,
                                 surveillance: avant)
        #expect(l.capsule.entrees == [Self.entree(.thread, nil), Self.entree(.zigbee, Comptes(aSurveiller: 2))])
        // Une demo d'un seul protocole : l'autre est muet, il n'attend rien et n'est pas montre.
        for (demo, protocole) in [(DemoLancee.thread, Protocole.thread), (.zigbee, .zigbee)] {
            let s = Surveillance(mode: .demo, dossier: nil, demo: demo)
            s.demarrer()
            let l = SantePieces.lire(entree: EntreeScene(surveillance: s, places: PlacesGardees()), isolement: .maison, surveillance: s)
            #expect(l.capsule.entrees.map(\.protocole) == [protocole], "\(demo)")
            #expect(l.sections.map(\.protocole) == [protocole] && !Self.lignes(l).isEmpty)
            #expect(l.capsule.entrees.first?.comptes != nil, "\(demo) : son releve est la")
        }
    }

    /// Un protocole eteint (« Activer ce protocole ») ou masque par son interrupteur n'est pas montre : la lecture de la coque
    /// suit `EntreeScene.montres` et les protocoles actifs.
    @Test func protocoleMasqueOuEteintDansLaCoque() {
        let s = DemoCombineeTests.combinee()
        let masque = EntreeScene(surveillance: s, places: PlacesGardees(), montres: [.thread])
        let l = SantePieces.lire(entree: masque, isolement: .maison, surveillance: s)
        #expect(l.capsule.entrees.map(\.protocole) == [.thread] && Self.lignes(l).allSatisfy { $0.id.protocole == .thread })
        s.zigbee.actif = false
        let eteint = SantePieces.lire(entree: EntreeScene(surveillance: s, places: PlacesGardees()), isolement: .maison, surveillance: s)
        #expect(eteint.capsule.entrees.map(\.protocole) == [.thread] && eteint.sections.map(\.protocole) == [.thread])
    }
}
