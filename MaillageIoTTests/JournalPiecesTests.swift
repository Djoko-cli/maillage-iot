import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Le journal, les notifications et le menu de la barre nomment le noeud avec sa piece (phase 9, tache 2). Les noeuds et
/// les pieces sont inventes. Les phrases francaises ne se verifient que dans une app en francais, les anglaises que dans
/// une app en anglais : le texte vient du catalogue de l'app, qui suit la langue de l'hote (passe anglaise de la porte).
@MainActor
@Suite("Journal : la piece du noeud dans les textes")
struct JournalPiecesTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)
    nonisolated static var francais: Bool { LangueSujet.courante == .francais }

    static let lampe = Sujet(id: "L1", nom: "Lampe bureau")
    static let volets = Sujet(id: "V1", nom: "Volets chambre")
    static let homepod = Sujet(id: "H1", nom: "HomePod Avant")
    static let hue = Sujet(id: "U1", nom: "Hue Go (droite)")

    /// Les pieces de la scene de ces noeuds de Thread.
    static let pieces = PiecesJournal(pieces: [IdNoeud(.thread, "L1"): "Bureau", IdNoeud(.thread, "V1"): "Chambre",
                                               IdNoeud(.thread, "H1"): "Salon", IdNoeud(.thread, "U1"): "Zone Z7",
                                               IdNoeud(.zigbee, "L1"): "Bureau", IdNoeud(.zigbee, "H1"): "Salon"], langue: .courante)

    static func ev(_ type: TypeEvenement, _ sujet: Sujet, _ protocole: Protocole? = nil, avant: String? = nil,
                   apres: String? = nil, details: [String: String] = [:]) -> Evenement {
        Evenement(date: t, type: type, sujet: sujet, avant: avant, apres: apres, details: details, protocole: protocole)
    }

    static func titre(_ e: Evenement, _ pieces: PiecesJournal = pieces) -> String {
        TexteEvenement.titre(e, pieces: pieces)
    }

    // MARK: Chaque type d'evenement de Thread, en francais

    /// Un sujet feminin : « La lampe du bureau », accord du participe.
    @Test(.enabled(if: JournalPiecesTests.francais))
    func threadSujetFeminin() {
        let l = Self.lampe
        #expect(Self.titre(Self.ev(.appareilNouveau, l)) == "La lampe du bureau est apparue")
        #expect(Self.titre(Self.ev(.routeurApparu, l)) == "La lampe du bureau est apparue")
        #expect(Self.titre(Self.ev(.appareilDisparu, l)) == "La lampe du bureau a disparu")
        #expect(Self.titre(Self.ev(.routeurDisparu, l)) == "La lampe du bureau a disparu")
        #expect(Self.titre(Self.ev(.appareilRevenu, l)) == "La lampe du bureau est revenue")
        #expect(Self.titre(Self.ev(.appareilSansAdresse, l)) == "La lampe du bureau n'annonce plus d'adresse")
        #expect(Self.titre(Self.ev(.appareilChangePartition, l, apres: "2")) == "La lampe du bureau a rejoint la partition 2")
        #expect(Self.titre(Self.ev(.appareilChangePartition, l, apres: "2", details: ["coupee": "oui"]))
                == "La lampe du bureau est isolée dans la partition 2")
        #expect(Self.titre(Self.ev(.parentChange, l, avant: "A", apres: "B")) == "La lampe du bureau a changé de parent : A → B")
        #expect(Self.titre(Self.ev(.sansParent, l, avant: "A")) == "La lampe du bureau n'a plus de parent")
        #expect(Self.titre(Self.ev(.routeurRoleChange, l, avant: "enfant", apres: "routeur"))
                == "La lampe du bureau : rôle enfant → routeur")
        #expect(Self.titre(Self.ev(.routeurNouvelleAdresseLien, l))
                == "La lampe du bureau : nouvelle adresse de lien (redémarrage probable)")
        // Le sujet au milieu d'une phrase : l'article en minuscules.
        #expect(Self.titre(Self.ev(.routeurThreadApparu, l)) == "Routeur Thread apparu : la lampe du bureau")
        #expect(Self.titre(Self.ev(.routeurThreadDisparu, l)) == "Routeur Thread disparu : la lampe du bureau")
    }

    /// Un sujet pluriel : le verbe et le participe suivent (ont, sont, leur).
    @Test(.enabled(if: JournalPiecesTests.francais))
    func threadSujetPluriel() {
        let v = Self.volets
        #expect(Self.titre(Self.ev(.appareilNouveau, v)) == "Les volets de la chambre sont apparus")
        #expect(Self.titre(Self.ev(.appareilDisparu, v)) == "Les volets de la chambre ont disparu")
        #expect(Self.titre(Self.ev(.appareilRevenu, v)) == "Les volets de la chambre sont revenus")
        #expect(Self.titre(Self.ev(.appareilSansAdresse, v)) == "Les volets de la chambre n'annoncent plus d'adresse")
        #expect(Self.titre(Self.ev(.appareilChangePartition, v, apres: "2")) == "Les volets de la chambre ont rejoint la partition 2")
        #expect(Self.titre(Self.ev(.appareilChangePartition, v, apres: "2", details: ["coupee": "oui"]))
                == "Les volets de la chambre sont isolés dans la partition 2")
        #expect(Self.titre(Self.ev(.parentChange, v, avant: "A", apres: "B")) == "Les volets de la chambre ont changé de parent : A → B")
        #expect(Self.titre(Self.ev(.sansParent, v)) == "Les volets de la chambre n'ont plus de parent")
        // Un pluriel feminin.
        let lampes = Sujet(id: "L1", nom: "Lampes bureau")
        #expect(Self.titre(Self.ev(.appareilNouveau, lampes)) == "Les lampes du bureau sont apparues")
        #expect(Self.titre(Self.ev(.appareilRevenu, lampes)) == "Les lampes du bureau sont revenues")
        #expect(Self.titre(Self.ev(.appareilChangePartition, lampes, apres: "2", details: ["coupee": "oui"]))
                == "Les lampes du bureau sont isolées dans la partition 2")
    }

    /// Le nom sans la piece, la piece connue : en incise ; la piece inconnue : aucun article invente.
    @Test(.enabled(if: JournalPiecesTests.francais))
    func threadInciseEtMotInconnu() {
        let h = Self.homepod
        #expect(Self.titre(Self.ev(.sansParent, h)) == "HomePod Avant, dans le salon, n'a plus de parent")
        #expect(Self.titre(Self.ev(.appareilNouveau, h)) == "HomePod Avant, dans le salon, est apparu")
        #expect(Self.titre(Self.ev(.parentChange, h, avant: "A", apres: "B")) == "HomePod Avant, dans le salon, a changé de parent : A → B")
        #expect(Self.titre(Self.ev(.routeurRoleChange, h, avant: "enfant", apres: "routeur"))
                == "HomePod Avant, dans le salon : rôle enfant → routeur")
        #expect(Self.titre(Self.ev(.routeurThreadDisparu, h)) == "Routeur Thread disparu : HomePod Avant, dans le salon")
        let u = Self.hue
        #expect(Self.titre(Self.ev(.appareilDisparu, u)) == "Hue Go (droite) — Zone Z7 : a disparu")
        #expect(Self.titre(Self.ev(.sansParent, u)) == "Hue Go (droite) — Zone Z7 : n'a plus de parent")
        #expect(Self.titre(Self.ev(.routeurRoleChange, u, avant: "enfant", apres: "routeur")) == "Hue Go (droite) — Zone Z7 : rôle enfant → routeur")
    }

    /// Sans piece (noeud absent de la scene, ou « Sans piece »), ou sans sujet : le texte d'avant, mot pour mot.
    @Test func sansPieceLeTexteDAvant() {
        let sans = Sujet(id: "Z9", nom: "Lampe bureau")
        for type in [TypeEvenement.appareilNouveau, .appareilDisparu, .appareilRevenu, .appareilSansAdresse, .sansParent,
                     .parentChange, .routeurRoleChange, .routeurThreadApparu] {
            let e = Self.ev(type, sans, avant: "A", apres: "B")
            #expect(Self.titre(e) == TexteEvenementThread.titre(e), "\(type)")
            #expect(Self.titre(e, .aucune) == TexteEvenementThread.titre(e), "\(type)")
        }
        let reseau = Self.ev(.reseauScinde, Sujet(id: "L1", nom: "Voisin"), apres: "2")
        #expect(Self.titre(reseau) == TexteEvenementThread.titre(reseau), "un reseau n'est pas un noeud : jamais de piece")
        let prefixe = Self.ev(.prefixeNouveau, Sujet(id: "L1", nom: "fd00::/64"))
        #expect(Self.titre(prefixe) == TexteEvenementThread.titre(prefixe))
    }

    // MARK: Zigbee

    @Test(.enabled(if: JournalPiecesTests.francais))
    func zigbee() {
        let z = Protocole.zigbee
        let l = Self.lampe
        #expect(Self.titre(Self.ev(.routeurApparu, l, z)) == "Routeur apparu : la lampe du bureau")
        #expect(Self.titre(Self.ev(.routeurDisparu, l, z)) == "Routeur disparu : la lampe du bureau")
        #expect(Self.titre(Self.ev(.appareilNouveau, l, z)) == "La lampe du bureau est apparue")
        #expect(Self.titre(Self.ev(.appareilDisparu, l, z)) == "La lampe du bureau a disparu")
        #expect(Self.titre(Self.ev(.appareilRevenu, l, z)) == "La lampe du bureau est revenue")
        #expect(Self.titre(Self.ev(.parentChange, l, z, avant: "A", apres: "B")) == "La lampe du bureau a changé de parent : A → B")
        #expect(Self.titre(Self.ev(.sansParent, l, z)) == "La lampe du bureau n'a plus de parent")
        #expect(Self.titre(Self.ev(.cheminChange, l, z, avant: "A", apres: "B"))
                == "La lampe du bureau a changé de chemin vers le pont : A → B")
        // La piece est celle du protocole du noeud : `zigbee:L1` est au bureau, `thread:V1` n'est pas une cle de Zigbee.
        #expect(Self.titre(Self.ev(.sansParent, Self.volets, z)) == TexteEvenementZigbee.titre(Self.ev(.sansParent, Self.volets, z)))
    }

    /// Une ligne de changements regroupes : le sujet du dernier changement.
    @Test(.enabled(if: JournalPiecesTests.francais))
    func lignesRegroupees() {
        let parents = LigneJournal.parents(Array(repeating: Self.ev(.parentChange, Self.lampe, avant: "A", apres: "B"), count: 3))
        #expect(TexteEvenement.titre(parents, pieces: Self.pieces) == "La lampe du bureau a changé 3 fois de parent en 1 h")
        let chemins = LigneJournal.chemins(Array(repeating: Self.ev(.cheminChange, Self.lampe, .zigbee, avant: "A", apres: "B"), count: 4))
        #expect(TexteEvenement.titre(chemins, pieces: Self.pieces) == "La lampe du bureau a changé 4 fois de chemin vers le pont en 1 h")
        let pl = LigneJournal.parents(Array(repeating: Self.ev(.parentChange, Self.volets, avant: "A", apres: "B"), count: 2))
        #expect(TexteEvenement.titre(pl, pieces: Self.pieces) == "Les volets de la chambre ont changé 2 fois de parent en 1 h")
        // Les pertes regroupees : leur titre ne nomme personne ; leur detail, une ligne par evenement.
        let pertes = [Self.ev(.appareilDisparu, Self.lampe), Self.ev(.appareilDisparu, Self.volets)]
        #expect(TexteEvenement.titre(LigneJournal.pertes(pertes), pieces: Self.pieces)
                == TexteEvenement.titre(LigneJournal.pertes(pertes), pieces: .aucune))
        #expect(TexteEvenement.titre(pertes[1], pieces: Self.pieces) == "Les volets de la chambre ont disparu")
    }

    // MARK: Anglais

    @Test(.enabled(if: !JournalPiecesTests.francais))
    func anglais() {
        let p = PiecesJournal(pieces: [IdNoeud(.thread, "L1"): "Office", IdNoeud(.thread, "V1"): "Bedroom"], langue: .courante)
        let lamp = Sujet(id: "L1", nom: "Desk lamp")
        #expect(Self.titre(Self.ev(.sansParent, lamp), p) == "Desk lamp (Office) has no parent anymore")
        #expect(Self.titre(Self.ev(.appareilNouveau, lamp), p) == "Desk lamp (Office) appeared")
        #expect(Self.titre(Self.ev(.parentChange, lamp, avant: "A", apres: "B"), p) == "Desk lamp (Office) changed parent: A → B")
        #expect(Self.titre(Self.ev(.routeurRoleChange, lamp, avant: "enfant", apres: "routeur"), p) == "Desk lamp (Office): role child → router")
        #expect(Self.titre(Self.ev(.routeurThreadDisparu, lamp), p) == "Thread router disappeared: Desk lamp (Office)")
        // Pas d'accord : le pluriel garde le singulier de l'anglais ; le nom qui finit par la piece ne la repete pas.
        #expect(Self.titre(Self.ev(.appareilDisparu, Sujet(id: "V1", nom: "Shutters bedroom")), p) == "Shutters bedroom disappeared")
        let l = LigneJournal.parents(Array(repeating: Self.ev(.parentChange, lamp, avant: "A", apres: "B"), count: 3))
        #expect(TexteEvenement.titre(l, pieces: p) == "Desk lamp (Office) changed parent 3 times within 1 h")
    }

    // MARK: Notifications

    /// La notification d'un routeur disparu reprend le titre de la ligne du journal, piece comprise, et son heure.
    @Test func notificationRouteurDisparu() {
        for protocole in Protocole.allCases {
            // « HomePod Avant » : en anglais, un nom qui finit par la piece (« Lampe bureau ») ne la repete pas.
            let e = Self.ev(.routeurDisparu, Self.homepod, protocole)
            let a = AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: "r", evenements: [e])
            let n = TexteEvenement.notification(a, pieces: Self.pieces)
            #expect(n.corps == TexteEvenement.titre(e, pieces: Self.pieces) + " · " + TexteEvenement.quand(e), "\(protocole)")
            #expect(n.corps != TexteEvenement.titre(e, pieces: .aucune) + " · " + TexteEvenement.quand(e), "\(protocole) : la piece y est")
        }
    }

    /// « Autres changements » : le titre de la notification est celui de la ligne du journal et du menu.
    @Test func notificationInformations() {
        let e = Self.ev(.sansParent, Self.homepod)
        let a = AlerteAEnvoyer(categorie: .informations, identifiant: "i", evenements: [e])
        let n = TexteEvenement.notification(a, pieces: Self.pieces)
        #expect(n.titre == TexteEvenement.titre(LigneJournal.evenement(e), pieces: Self.pieces))
        #expect(n.titre == TexteEvenement.titre(e, pieces: Self.pieces))
        #expect(n.titre != TexteEvenement.titre(e, pieces: .aucune), "la piece y est")
        #expect(n.corps == TexteEvenement.quand(e))
    }

    /// Les pertes groupees : la liste des noeuds les nomme avec leur piece ; une piece en incise a une virgule, la liste se
    /// separe alors par des points-virgules pour rester lisible.
    @Test(.enabled(if: JournalPiecesTests.francais))
    func notificationPertes() {
        let pertes = [Self.ev(.appareilDisparu, Self.lampe), Self.ev(.appareilDisparu, Self.volets)]
        let a = AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: pertes)
        let n = TexteEvenement.notification(a, pieces: Self.pieces)
        #expect(n.corps.hasSuffix(" : la lampe du bureau, les volets de la chambre"))
        let avec = [Self.ev(.appareilDisparu, Self.homepod), Self.ev(.appareilDisparu, Self.lampe)]
        let b = TexteEvenement.notification(AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: avec),
                                            pieces: Self.pieces)
        #expect(b.corps.hasSuffix(" : HomePod Avant, dans le salon ; la lampe du bureau"))
        let sans = TexteEvenement.notification(a, pieces: .aucune)
        #expect(sans.corps.hasSuffix(" : Lampe bureau, Volets chambre"), "sans piece : comme avant")
        #expect(n.titre == sans.titre)
    }

    // MARK: Recherche

    /// La recherche trouve toujours une ligne par le nom brut du noeud (« Lampe bureau », que le titre ne dit plus tel
    /// quel), par sa piece, et par l'identifiant du noeud.
    @Test func recherche() {
        let lignes = [LigneJournal.evenement(Self.ev(.sansParent, Self.lampe)),
                      LigneJournal.evenement(Self.ev(.sansParent, Self.homepod)),
                      LigneJournal.evenement(Self.ev(.appareilDisparu, Self.hue))]
        func trouve(_ r: String, _ p: PiecesJournal = Self.pieces) -> [String] {
            FiltreJournal(recherche: r).appliquer(lignes, pieces: p).compactMap { $0.evenements.first?.sujet?.nom }
        }
        #expect(trouve("lampe bureau") == ["Lampe bureau"], "le nom brut")
        #expect(trouve("homepod avant") == ["HomePod Avant"])
        #expect(trouve("Bureau") == ["Lampe bureau"], "la piece")
        #expect(trouve("salon") == ["HomePod Avant"], "la piece, que le nom ne dit pas")
        #expect(trouve("zone z7") == ["Hue Go (droite)"], "une piece inconnue du lexique")
        #expect(trouve("L1") == ["Lampe bureau"], "l'identifiant")
        #expect(trouve("introuvable").isEmpty)
        #expect(trouve("salon", .aucune).isEmpty, "sans piece, la recherche d'avant")
        // Dans la langue de l'app, le titre porte la piece : une recherche sur la phrase entiere la trouve.
        if Self.francais { #expect(trouve("du bureau") == ["Lampe bureau"]) }
    }

    /// Une piece que le titre ne dit pas (le nom la termine) se trouve quand meme.
    @Test func rechercheParLaPieceHorsDuTitre() {
        let e = Self.ev(.sansParent, Sujet(id: "X1", nom: "Prise zeta"))
        let p = PiecesJournal(pieces: [IdNoeud(.thread, "X1"): "Cave"], langue: .courante)
        // « Cave » n'est ni dans le titre (mot inconnu : « Prise zeta — Cave » ou « Prise zeta (Cave) » le dit), ni dans le nom :
        // la recherche la trouve par la scene, quelle que soit la phrase.
        #expect(FiltreJournal(recherche: "cave").appliquer([.evenement(e)], pieces: p).count == 1)
        #expect(FiltreJournal(recherche: "cave").appliquer([.evenement(e)], pieces: .aucune).isEmpty)
    }

    // MARK: La scene, lue a l'affichage

    static func combinee() -> Surveillance { DemoCombineeTests.combinee() }

    /// Les pieces sont celles de la scene : un noeud que Maison place a sa piece, un noeud que la scene range « Sans piece »
    /// n'en a pas, un protocole et un noeud qui n'existent pas non plus.
    @Test func piecesDeLaScene() throws {
        let s = Self.combinee()
        let pieces = PiecesJournal.de(s)
        #expect(!pieces.pieces.isEmpty, "la demo place des noeuds dans les pieces de Maison")
        #expect(Set(pieces.pieces.keys.map(\.protocole)) == [.thread, .zigbee], "les pieces des deux protocoles")
        let entree = EntreeScene(surveillance: s, places: PlacesGardees(), choix: s.piecesChoisies.choix)
        for n in entree.scene.noeuds {
            let nom = entree.scene.pieces[n.piece].nom
            if case .maison(let p) = nom {
                #expect(pieces.pieces[n.id] == p, "\(n.id.texte) : la piece de la scene")
            } else {
                #expect(pieces.pieces[n.id] == nil, "\(n.id.texte) : sans piece")
            }
        }
        #expect(PiecesJournal.de(Surveillance(mode: .direct, dossier: nil)).pieces.isEmpty, "rien a montrer : aucune piece")
    }

    /// La piece est lue a l'affichage : l'Apple TV de la demo, que Maison ne place pas, rangee dans une piece depuis sa fiche
    /// (« Placer dans une piece… »), la voit dans ses lignes du journal tout de suite ; le choix efface, elle la perd.
    @Test func lePlacementChangeLeJournal() throws {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .combinee, demoAirPlay: true)
        s.demarrer()
        let id = IdNoeud(.thread, "Apple TV 4K")
        #expect(PiecesJournal.de(s).pieces[id] == nil, "Maison ne la place pas")
        s.piecesChoisies.choisir("Bureau", .routeur(id), domicile: NomsDemo.domicile)
        #expect(PiecesJournal.de(s).pieces[id] == "Bureau", "la piece que la scene lui donne, lue a l'affichage")
        s.piecesChoisies.choisir(nil, .routeur(id), domicile: NomsDemo.domicile)
        #expect(PiecesJournal.de(s).pieces[id] == nil)
    }

    /// Le menu de la barre, la fenetre du journal et les notifications lisent la meme source, `PiecesJournal.de` : les trois
    /// premieres lignes du menu sont celles du journal, avec le meme texte.
    @Test func menuEtJournalIdentiques() {
        let s = Self.combinee()
        let pieces = PiecesJournal.de(s)
        let menu = MenuBarre.dernieresLignes(s)
        let lignes = Array(s.lignesJournal.prefix(3))
        #expect(menu.count == 3)
        #expect(menu.map(\.titre) == lignes.map { TexteEvenement.titre($0, pieces: pieces) })
        #expect(menu.map(\.quand) == lignes.map { $0.evenements.first.map(TexteEvenement.quand) ?? "" })
        #expect(menu.map(\.id) == lignes.map(\.id))
        // Les trois premieres lignes de la demo changent avec la piece en francais seulement : en anglais, « Prise salon (Hue) »
        // dit deja la piece dans son nom, et la parenthese finale reste telle quelle.
        if LangueSujet.courante == .francais {
            #expect(menu.map(\.titre) != lignes.map { TexteEvenement.titre($0, pieces: .aucune) }, "le menu nomme les pieces")
        }
        // Une alerte du journal : la notification et le menu disent le meme sujet.
        for ligne in s.lignesJournal {
            guard case .evenement(let e) = ligne, let nom = e.sujet?.nom, pieces.piece(de: e.sujet, protocole: e.protocole ?? .thread) != nil,
                  TexteEvenement.titre(e, pieces: pieces) != TexteEvenement.titre(e, pieces: .aucune) else { continue }
            let a = AlerteAEnvoyer(categorie: .informations, identifiant: "i", evenements: [e])
            #expect(TexteEvenement.notification(a, pieces: pieces).titre == TexteEvenement.titre(ligne, pieces: pieces), "\(nom)")
        }
    }

    /// Les lignes de la demo combinee, a la main : la ligne telle que la fenetre du journal la montre (et le menu, et la
    /// notification), puis, pour une ligne de pertes regroupees, chaque perte de son detail ; a droite, le texte d'avant (sans
    /// piece). Ecrit sur la sortie (marqueur `JOURNAL`) pour les captures de la tache, dans la langue de l'app.
    @Test func rendreLaDemo() {
        let s = Self.combinee()
        let pieces = PiecesJournal.de(s)
        let langue = Bundle.main.preferredLocalizations.first ?? "?"
        var avecPiece = 0
        func ecrire(_ marque: String, _ protocole: Protocole, _ apres: String, _ avant: String) {
            print("JOURNAL|\(langue)|\(protocole.rawValue)|\(marque)|\(apres)|\(avant)")
            if apres != avant { avecPiece += 1 }
        }
        for ligne in s.lignesJournal {
            let p = MarqueProtocole.protocole(de: ligne)
            ecrire("ligne", p, TexteEvenement.titre(ligne, pieces: pieces), TexteEvenement.titre(ligne, pieces: .aucune))
            if case .pertes(let groupe) = ligne {
                for e in groupe {
                    ecrire("perte", p, TexteEvenement.titre(e, pieces: pieces), TexteEvenement.titre(e, pieces: .aucune))
                }
            }
        }
        #expect(avecPiece > 0, "au moins une ligne de la demo nomme une piece")
    }
}
