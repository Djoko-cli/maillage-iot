import Foundation
import MaillageCoeur

/// Textes de la vue par pieces : le libelle de chaque noeud (nom, couronne, lune, alerte) et la
/// pastille de sa batterie faible ; les noms des pieces et des etages ; le compte d'une piece ; le
/// texte d'un repere « ailleurs ».
enum LibellesNoeuds {
    /// La couronne du chef et la lune d'un endormi, a la suite du nom ; la legende les reprend.
    static let couronne = CartesPieces.couronne
    static let lune = CartesPieces.lune

    /// Libelle d'un noeud : son texte, et la pastille de sa batterie faible ; son nom, sans ses badges (polissage D,
    /// section 2) : la scene et sa carte ne voient que lui.
    struct Libelle: Hashable {
        var texte: String
        var pastille: String?
        var nom: String

        /// Le nom est toujours donne : la scene ne voit que lui, et un oubli lui montrerait les badges.
        init(texte: String, pastille: String? = nil, nom: String) {
            self.texte = texte
            self.pastille = pastille
            self.nom = nom
        }

        /// Un texte pur, sans badge : mesures, reperes, noeud sans libelle ; son nom est le texte.
        init(texte: String) {
            self.init(texte: texte, nom: texte)
        }
    }

    /// Nom d'un noeud que seule la sonde connait : « Routeur de bordure · B400 »,
    /// « Routeur · 5000 », « Non identifie · AC05 » (« Non identifie » seul pour un enfant resolu, au RLOC16 invente).
    /// Un routeur de bordure non identifie
    /// montre ses candidats, sous leur nom (`noms`, par instance ; l'instance a defaut) :
    /// « HomePod Avant ou HomePod Palier · 0400 » ; un seul, sans elimination possible :
    /// « HomePod salon ? · 0400 », car ce n'est peut-etre pas lui.
    static func inconnu(_ n: NoeudSonde, noms: [String: String] = [:]) -> String {
        let rloc = String(format: "%04X", n.rloc16)
        switch n.genre {
        case .routeur:
            let candidats = n.candidats.map { noms[$0] ?? $0 }
            if candidats.count > 1 { return String(localized: "\(candidats.formatted(.list(type: .or))) · \(rloc)") }
            if let seul = candidats.first { return String(localized: "\(seul)\u{202F}? · \(rloc)") }
            return n.bordure ? String(localized: "Routeur de bordure · \(rloc)") : String(localized: "Routeur · \(rloc)")
        case .enfant:
            // Le RLOC16 d'un enfant resolu est invente (`EnfantMaillage.bitInvente`) : on ne l'affiche jamais.
            if n.rloc16 & EnfantMaillage.bitInvente != 0 { return String(localized: "Non identifié") }
            return String(localized: "Non identifié · \(rloc)")
        }
    }

    /// Texte de la pastille d'une batterie faible : son niveau, sinon « faible » ; nil si elle ne
    /// l'est pas.
    static func pastilleBatterie(_ b: BatterieMaison?) -> String? {
        guard let b, b.faible else { return nil }
        return b.niveau.map { String(localized: "\($0)\u{202F}%") } ?? String(localized: "faible")
    }

    /// Noeuds couronnes : le chef de chaque partition (son annonce), et celui du maillage de la sonde.
    static func chefs(reseau: Reseau, maillage: Maillage?, affiche: MaillageAffiche?) -> Set<String> {
        var c = Set(reseau.partitions.compactMap { $0.chef?.instance })
        if let chef = maillage?.chef, let n = affiche?.routeurs[chef.id] { c.insert(n.id) }
        return c
    }

    /// Un noeud endormi, qui porte ☾ : un appareil qui s'annonce a veille, sauf s'il route. Un routeur Thread n'est
    /// jamais endormi, meme si son annonce Matter le dit (relecture finale du polissage C) ; la legende suit cette
    /// regle.
    static func endormi(_ a: AppareilAffiche?, routeur: Bool) -> Bool {
        a?.endormi == true && !routeur
    }

    /// Libelle de chaque noeud : son nom (coupe a 40 caracteres), la couronne du chef, ☾ endormi (pas pour un noeud
    /// qui route), ⚠︎ sans adresse ou disparu ; la pastille d'une batterie faible.
    static func libelles(graphe: GrapheReseau, appareils: [String: AppareilAffiche], nomsRouteurs: [String: String],
                         maillage: MaillageAffiche?, chefs: Set<String>) -> [String: Libelle] {
        func inconnu(_ n: NoeudSonde) -> String { Self.inconnu(n, noms: nomsRouteurs) }
        var libelles: [String: Libelle] = [:]
        for n in graphe.noeuds {
            let a = appareils[n.id]
            let nom = a?.nom ?? nomsRouteurs[n.id] ?? maillage?.noeud(n.id).map(inconnu) ?? n.id
            let coupe = CartesPieces.couper(nom)
            let texte = CartesPieces.texte(coupe, chef: chefs.contains(n.id), endormi: endormi(a, routeur: n.routeur),
                                           alerte: a?.etat == .sansAdresse || a?.etat == .disparu)
            libelles[n.id] = Libelle(texte: texte, pastille: pastilleBatterie(a?.batterie), nom: coupe)
        }
        return libelles
    }

    /// Piece de Maison de chaque noeud : celle de son accessoire (appareil), ou, pour un routeur de bordure, la chaine de
    /// `PiecesRouteurs.piece(routeur:nom:maison:parmi:domicile:)` : celle de l'accessoire de Maison qui porte le nom de
    /// son annonce ; pour un routeur que Maison ne place pas (HomePod, Apple TV), la piece choisie pour lui, sinon celle de
    /// son nom (`nomsRouteurs`, par instance). Un routeur de bordure que seule la sonde connait, non identifie, prend la
    /// piece de ses candidats s'ils sont tous dans la meme, par cette meme chaine (polissage D, section 4.1,
    /// `maillage`). Un autre noeud du graphe que Maison ne place pas prend la piece choisie pour son ExtMac
    /// (precision 27).
    static func pieces(reseau: Reseau, appareils: [AppareilAffiche], maison: NomsMaison?,
                       nomsRouteurs: [String: String] = [:], choix: PiecesRouteurs = PiecesRouteurs(),
                       graphe: GrapheReseau, maillage: MaillageAffiche? = nil) -> [String: String] {
        var pieces: [String: String] = [:]
        for a in appareils {
            if let p = a.piece, !p.isEmpty { pieces[a.id] = p }
        }
        let toutes = PiecesRouteurs.pieces(de: maison)
        let domicile = maison?.domicile ?? ""
        pieces = choix.piecesNoeuds(graphe, deMaison: pieces, parmi: toutes, domicile: domicile)
        for r in reseau.routeurs {
            if let p = choix.piece(routeur: r.instance, nom: nomsRouteurs[r.instance] ?? r.instance, maison: maison,
                                   parmi: toutes, domicile: domicile) {
                pieces[r.instance] = p
            }
        }
        // Seul un routeur de bordure non identifie a des candidats (`Rapprochement`), et rien ne l'a place avant : ni
        // Maison, ni un choix (sans instance ni ExtMac).
        for n in graphe.noeuds {
            guard let candidats = maillage?.noeud(n.id)?.candidats,
                  let p = choix.piece(candidats: candidats, noms: nomsRouteurs, maison: maison, parmi: toutes,
                                      domicile: domicile) else { continue }
            pieces[n.id] = p
        }
        return pieces
    }

    static func nom(_ e: ScenePieces.NomEtage) -> String {
        switch e {
        case .zone(let n): n
        case .autresPieces: String(localized: "Autres pièces")
        case .maison: String(localized: "Maison")
        }
    }

    static func nom(_ p: ScenePieces.NomPiece, libelles: [String: Libelle]) -> String {
        switch p {
        case .maison(let n): n
        case .routeur(let id): libelles[id]?.texte ?? id
        case .sansPiece: String(localized: "Sans pièce")
        }
    }

    /// « 1 appareil », « 6 appareils ».
    static func compte(_ n: Int) -> String {
        n == 1 ? String(localized: "1 appareil") : String(localized: "\(n) appareils")
    }

    /// Repere « ailleurs » (polissage C, section 5.2) : « ↗ HomePod Palier · Salon » pour un parent du meme
    /// plateau, « ↗ … · Terrasse, Jardin » pour un parent au meme niveau, dans une autre zone ; « ↓ … · Salon,
    /// Rez-de-chaussee » ou ↑ pour un parent a un autre niveau, avec le nom de son plateau (sans la couronne du
    /// chef).
    static func ailleurs(_ a: Ailleurs, scene: ScenePieces, libelles: [String: Libelle]) -> String {
        let fleche = switch a.sens {
        case .memeNiveau: "↗"
        case .dessous: "↓"
        case .dessus: "↑"
        }
        let parent = (libelles[a.parent]?.texte ?? a.parent).replacingOccurrences(of: " " + couronne, with: "")
        let piece = nom(scene.pieces[a.piece].nom, libelles: libelles)
        let ici = scene.noeud(a.enfant).map { scene.pieces[$0.piece].etage }
        guard a.etage != ici else { return "\(fleche) \(parent) · \(piece)" }
        return "\(fleche) \(parent) · \(piece), \(nom(scene.etages[a.etage].nom))"
    }
}
