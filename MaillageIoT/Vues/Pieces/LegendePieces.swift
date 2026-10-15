import AppKit
import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// Legende de la vue par pieces (polissage B, section 2 ; maquette de la legende, colonne de droite) :
/// en bas a gauche, au-dessus de la fiche quand elle est ouverte ; quatre
/// groupes en grille de deux colonnes, qui ne montrent que ce que la scene affichee contient, chaque signe
/// dessine comme dans la scene (`SigneLegende`). En verre, comme les capsules du haut (verification du 02/10 :
/// le choix de Djoko, au lieu du panneau sombre de la maquette). Repliee, il ne reste que l'etiquette
/// « Legende » ; son etat est garde d'un lancement a l'autre, par la ligne du bas (`LigneDuBas`). Une legende
/// sans entree n'est pas montree. Quand la scene a des noeuds des deux protocoles, une ligne « ● Thread ⬢ Zigbee » ouvre
/// le panneau (`ligneProtocoles`) : le rond est Thread, l'hexagone Zigbee ; les entrees communes restent rondes.
struct LegendePieces: View {
    @Environment(\.accessibilityReduceMotion) private var reduire
    let rubriques: [Rubrique]
    /// La ligne des protocoles, sous l'en-tete du panneau ouvert (`montreLesProtocoles`).
    var ligneProtocoles = false
    /// Repliee ou ouverte : un clic sur l'en-tete bascule.
    @Binding var repliee: Bool

    /// La preference qui garde le repli.
    static let cleRepliee = "legendeRepliee"

    /// L'ecart du panneau entre ses elements (l'en-tete, la ligne des protocoles, la grille).
    static let ecartLigneProtocoles: CGFloat = 7

    var body: some View {
        if !rubriques.isEmpty {
            // Le panneau parait depuis l'etiquette et s'y replie, en 0,45 s ; un fondu seul avec « Reduire les
            // animations ».
            if repliee {
                etiquette
                    .transition(Apparition.transitionLegende(reduire: reduire))
            } else {
                panneau
                    .transition(Apparition.transitionLegende(reduire: reduire))
            }
        }
    }

    /// « Legende ⌃ » : 11,5 pt semi-gras, marges de 6 x 12 pt ; le chevron vers le haut, qui ouvre la legende, centre
    /// sur la ligne de l'etiquette (`chevron`).
    private var etiquette: some View {
        Button {
            repliee = false
        } label: {
            HStack(spacing: 8) {
                Text("Légende")
                Self.chevron(repliee: true)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.texteLegende)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .verreDeLegende()
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// En-tete « Legende ⌄ » (7 pt dessous ; le chevron vers le bas, qui replie la legende), puis la grille ; marges de
    /// 9, 12, 11 et 12 pt. La largeur est celle de la grille : l'en-tete s'y etend, sans elargir le panneau.
    private var panneau: some View {
        VStack(alignment: .leading, spacing: Self.ecartLigneProtocoles) {
            Button {
                repliee = true
            } label: {
                HStack {
                    Text("Légende")
                    Spacer(minLength: 8)
                    Self.chevron(repliee: false)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ligneProtocoles { self.ligneDesProtocoles }
            GrilleLegende {
                ForEach(rubriques, id: \.groupe) { r in
                    groupe(r)
                }
            }
        }
        .fixedSize()
        .font(.system(size: 11))
        .foregroundStyle(Palette.texteLegende)
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 11, trailing: 12))
        .verreDeLegende()
    }

    /// Le chevron de l'en-tete ou de l'etiquette : il montre ce que fait un clic (choix de Djoko, 02/10, a l'inverse de
    /// la maquette A) : vers le bas, la legende ouverte, pour la replier ; vers le haut, repliee, pour l'ouvrir. Un
    /// symbole, et non les caracteres ⌄ et ⌃ de la maquette : centre sur la ligne de l'etiquette (le caractere ⌄ y
    /// tombait 3,5 pt trop bas, sur la ligne de base), a la taille de ces caracteres.
    static func chevron(repliee: Bool) -> some View {
        Image(systemName: repliee ? "chevron.up" : "chevron.down")
            .font(.system(size: 8.5, weight: .bold))
            .accessibilityHidden(true)
    }

    /// « ● Thread ⬢ Zigbee » : un noeud de chaque protocole, tel que la scene le dessine (`signeProtocole`), 7 pt, son nom ;
    /// 14 pt entre les deux. Une ligne de texte (`hauteurLigne`), a `ecartLigneProtocoles` de l'en-tete et de la grille.
    private var ligneDesProtocoles: some View {
        HStack(spacing: 14) {
            ForEach(Protocole.allCases, id: \.self) { p in
                HStack(spacing: 7) {
                    SigneLegende(signe: Self.signeProtocole(p))
                        .accessibilityHidden(true)
                    Text(Self.nomProtocole(p))
                }
            }
        }
    }

    /// Un groupe : son titre (10 pt semi-gras, gris bleute), 4 pt, puis ses entrees, a 3 pt l'une de
    /// l'autre, et 3 pt dessous.
    private func groupe(_ r: Rubrique) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.groupe.titre)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(Palette.titreLegende)
                .padding(.bottom, 1)
            ForEach(r.entrees, id: \.self) { e in
                ligne(e)
            }
        }
        .padding(.bottom, 3)
        .fixedSize()
    }

    /// Une entree : son signe, dessine comme dans la scene (`SigneLegende`), 7 pt, son texte.
    private func ligne(_ e: Entree) -> some View {
        HStack(spacing: 7) {
            SigneLegende(signe: Self.signe(e))
                .accessibilityHidden(true)
            Text(e.texte)
        }
    }

    /// Exemples des signes, comme dans la scene : la pastille d'une pile a 12 %, un repere « ailleurs »,
    /// un routeur et ses deux candidats.
    static var exemplePile: String { String(localized: "\(12)\u{202F}%") }
    static var exempleAilleurs: String { String(localized: "→ Salon") }
    static var exempleCandidats: String {
        LibellesNoeuds.inconnu(NoeudSonde(id: "rloc:0400", rloc16: 0x0400, genre: .routeur, reconnu: false,
                                          bordure: true, candidats: ["A", "B"]))
    }
}

extension LegendePieces {
    /// Une entree de la legende : un signe et son texte (spec du polissage B, section 2) ; la couronne du chef (Thread)
    /// ou du coordinateur (Zigbee) et la lune d'un endormi sont leur signe, dans un nom de noeud comme dans la scene.
    /// Les entrees propres a un protocole : `routeur` (de bordure), `routeurSimple`, `nonIdentifie`, `autrePartition`,
    /// `chef`, `verifiee`, `partitionCoupee`, `sansAdresse`, `rattachement`, `candidats` pour Thread ; `routeurZigbee`,
    /// `nonIdentifieZigbee`, `coordinateur`, `injoignable`, `chemin`, `cheminSuppose`, `voisinEntendu`, `parentDAvant`
    /// pour Zigbee. Les autres sont communes.
    enum Entree: Hashable, CaseIterable {
        /// `routeur` : un routeur de bordure ; `routeurSimple` : un routeur qui ne l'est pas.
        case routeur, routeurSimple, nonIdentifie, autrePartition, chef
        case routeurZigbee, nonIdentifieZigbee, coordinateur
        case joignable, verifiee, partitionCoupee, sansAdresse, injoignable, disparu, endormi, pile, sonde
        case chemin, cheminSuppose, voisinEntendu
        case bonne, moyenne, faible, inconnue
        case versParent, parentDAvant, rattachement, ailleurs, candidats

        var texte: String {
            switch self {
            case .routeur: String(localized: "routeur de bordure")
            case .routeurSimple, .routeurZigbee: String(localized: "routeur")
            case .nonIdentifie: String(localized: "non identifié")
            case .nonIdentifieZigbee: String(localized: "inconnu du pont")
            case .coordinateur: String(localized: "coordinateur (le pont)")
            case .autrePartition: String(localized: "routeur de bordure d'une autre partition")
            case .chef: String(localized: "chef du réseau Thread, élu automatiquement")
            case .joignable: String(localized: "joignable")
            case .verifiee: String(localized: "joignable, adresse plus annoncée")
            case .partitionCoupee: String(localized: "partition coupée")
            case .sansAdresse: String(localized: "adresse non annoncée")
            case .injoignable: String(localized: "injoignable")
            case .disparu: String(localized: "disparu")
            case .endormi: String(localized: "endormi")
            case .pile: String(localized: "pile")
            case .sonde: String(localized: "sonde")
            case .chemin: String(localized: "chemin vers le pont")
            case .cheminSuppose: String(localized: "chemin supposé")
            case .voisinEntendu: String(localized: "voisin entendu (à la sélection)")
            case .bonne: String(localized: "bonne")
            case .moyenne: String(localized: "moyenne")
            case .faible: String(localized: "faible")
            case .inconnue: String(localized: "inconnue")
            case .versParent: String(localized: "vers son parent")
            case .parentDAvant: String(localized: "parent d'avant (pointillé)")
            case .rattachement: String(localized: "rattachement supposé")
            case .ailleurs: String(localized: "parent dans une autre pièce")
            case .candidats: String(localized: "candidats")
            }
        }
    }

    /// Les quatre groupes, dans l'ordre de la grille, et leurs entrees, dans l'ordre.
    enum Groupe: Hashable, CaseIterable {
        case routeurs, appareils, liens, autres

        var entrees: [Entree] {
            switch self {
            case .routeurs:
                [.routeur, .routeurSimple, .routeurZigbee, .nonIdentifie, .nonIdentifieZigbee, .autrePartition, .chef,
                 .coordinateur]
            case .appareils:
                [.joignable, .verifiee, .partitionCoupee, .sansAdresse, .injoignable, .disparu, .endormi, .pile, .sonde]
            case .liens: [.bonne, .moyenne, .faible, .inconnue]
            // Les traits des chemins de Zigbee avec celui vers un parent : la rangee du bas prend une ligne de plus
            // quand ils depassent les qualites.
            case .autres:
                [.chemin, .cheminSuppose, .voisinEntendu, .versParent, .parentDAvant, .rattachement, .ailleurs, .candidats]
            }
        }

        var titre: String {
            switch self {
            case .routeurs: String(localized: "Routeurs")
            case .appareils: String(localized: "Appareils")
            case .liens: String(localized: "Liens radio (qualité)")
            case .autres: String(localized: "Autres")
            }
        }
    }

    /// Un groupe montre, et ses entrees presentes.
    struct Rubrique: Equatable {
        var groupe: Groupe
        var entrees: [Entree]
    }

    /// Ce que la legende lit de la scene affichee : la couleur de chaque noeud, les routeurs qui ne sont pas de
    /// bordure, la sonde, ceux que la sonde seule connait, les chefs, les endormis, les piles, les noeuds montres avec leurs candidats, les liens, et
    /// si des reperes « ailleurs » sont poses (piece isolee).
    struct Lecture {
        var couleurs: [IdNoeud: DessinNoeud.Couleur] = [:]
        /// Les routeurs qui ne sont pas de bordure (leur cercle).
        var routeursSimples: Set<IdNoeud> = []
        /// Les appareils joignables que la sonde a trouves alors qu'ils n'annoncent plus d'adresse (leur anneau).
        var verifies: Set<IdNoeud> = []
        /// La sonde elle-meme (ses ondes).
        var sondes: Set<IdNoeud> = []
        var inconnus: Set<IdNoeud> = []
        var chefs: Set<IdNoeud> = []
        var endormis: Set<IdNoeud> = []
        var piles: Set<IdNoeud> = []
        var candidats: Set<IdNoeud> = []
        var liens: [ScenePieces.Lien] = []
        var ailleurs = false
        /// Les liens montres (Zigbee : chemins vers le pont ou tous les liens radio ; sans effet sur ceux de Thread).
        var mode = ModeLiens.tous
        /// Les voisins entendus de Zigbee se montrent a la selection (mode « chemins ») : sinon ni leur entree ni leurs
        /// qualites.
        var voisins = true

        /// Les protocoles dont la scene a un noeud (un noeud dessine, inconnu, chef ou sonde).
        var protocoles: Set<Protocole> {
            Set(couleurs.keys.map(\.protocole)).union(inconnus.map(\.protocole)).union(chefs.map(\.protocole))
                .union(sondes.map(\.protocole))
        }
    }

    /// La ligne « ● Thread ⬢ Zigbee » ne se montre que quand la scene a des noeuds des deux protocoles : avec un seul, la
    /// forme se lit sans elle, et la legende ne grandit pas.
    static func montreLesProtocoles(_ l: Lecture) -> Bool {
        Set(Protocole.allCases).isSubset(of: l.protocoles)
    }

    /// Les entrees que la scene contient (spec du polissage B, section 2) : chaque couleur de noeud (un appareil
    /// joignable avec l'anneau de la sonde a sa propre entree, « joignable » ne se montre que pour les autres) ; un
    /// routeur qui n'est pas de bordure (son cercle) ; la sonde (ses ondes) ; un noeud que la sonde seule connait,
    /// routeur ou enfant, en gris (« non identifie ») ; un chef, un endormi, une pile ; chaque qualite d'un lien
    /// radio trace ; un lien vers un parent, un rattachement suppose ; un repere « ailleurs » ; un routeur montre
    /// avec ses candidats. Un appareil d'etat inconnu, en gris, n'a pas d'entree.
    static func entrees(_ l: Lecture) -> Set<Entree> {
        var r = Set<Entree>()
        for (id, c) in l.couleurs {
            let zigbee = id.protocole == .zigbee
            switch c {
            case .routeur(principale: true): r.insert(zigbee ? .routeurZigbee : .routeur)
            case .routeurZigbee: r.insert(.routeurZigbee)
            case .routeur(principale: false): r.insert(.autrePartition)
            case .appareil(.joignable): r.insert(l.verifies.contains(id) ? .verifiee : .joignable)
            // Les etats de Thread, que Zigbee ne donne jamais : comme injoignable ; et `injoignable` (etat d'un pont),
            // que Thread n'emet pas : au plus proche, un appareil que l'on ne joint pas.
            case .appareil(.partitionCoupee): r.insert(zigbee ? .injoignable : .partitionCoupee)
            case .appareil(.sansAdresse), .appareil(.injoignable): r.insert(zigbee ? .injoignable : .sansAdresse)
            case .appareil(.disparu): r.insert(.disparu)
            case .routeurInconnu, .appareil(.inconnu): break
            }
        }
        if !l.routeursSimples.isEmpty { r.insert(.routeurSimple) }
        if !l.sondes.isEmpty { r.insert(.sonde) }
        if l.inconnus.contains(where: { $0.protocole == .thread }) { r.insert(.nonIdentifie) }
        if l.inconnus.contains(where: { $0.protocole == .zigbee }) { r.insert(.nonIdentifieZigbee) }
        if l.chefs.contains(where: { $0.protocole == .thread }) { r.insert(.chef) }
        if l.chefs.contains(where: { $0.protocole == .zigbee }) { r.insert(.coordinateur) }
        if !l.endormis.isEmpty { r.insert(.endormi) }
        if !l.piles.isEmpty { r.insert(.pile) }
        if !l.candidats.isEmpty { r.insert(.candidats) }
        func qualite(_ q: Int?, _ protocole: Protocole) {
            switch Palette.bande(q, protocole: protocole) {
            case .bonne: r.insert(.bonne)
            case .moyenne: r.insert(.moyenne)
            case .faible: r.insert(.faible)
            case .inconnue: r.insert(.inconnue)
            }
        }
        for lien in l.liens {
            if lien.de.protocole == .zigbee {
                switch (lien.genre, l.mode) {
                case (.radio, .tous):
                    qualite(lien.qualite, .zigbee)
                case (.radio, .chemins):
                    // Les voisins entendus ne paraissent qu'a la selection d'un noeud ; la legende ne change pas avec
                    // elle : leur entree et leurs qualites sont la des qu'il y en a, sauf s'ils sont masques.
                    guard l.voisins else { break }
                    r.insert(.voisinEntendu)
                    qualite(lien.qualite, .zigbee)
                case (.chemin, .chemins):
                    r.insert(lien.suppose ? .cheminSuppose : .chemin)
                    qualite(lien.qualite, .zigbee)
                case (.chemin, .tous), (.rattachement, _):
                    break
                case (.parent, _):
                    // Le parent d'avant (appareil final absent des dernieres tables) est trace en pointilles.
                    r.insert(lien.suppose ? .parentDAvant : .versParent)
                }
                continue
            }
            switch lien.genre {
            // Un chemin vers le pont (Zigbee, que Thread n'emet pas) se lit comme un lien radio : meme couleur de qualite.
            case .radio, .chemin: qualite(lien.qualite, .thread)
            case .parent: r.insert(.versParent)
            case .rattachement: r.insert(.rattachement)
            }
        }
        if l.ailleurs { r.insert(.ailleurs) }
        return r
    }

    /// Les groupes a montrer, dans l'ordre, chacun avec ses entrees presentes ; un groupe sans entree
    /// disparait.
    static func rubriques(_ l: Lecture) -> [Rubrique] {
        let presentes = entrees(l)
        return Groupe.allCases.compactMap { g in
            let e = g.entrees.filter(presentes.contains)
            return e.isEmpty ? nil : Rubrique(groupe: g, entrees: e)
        }
    }
}

extension LegendePieces.Lecture {
    /// Lecture de la scene d'un rendu (`EntreeScene`) ; `ailleurs` : des reperes « ailleurs » sont
    /// poses ; `mode` : les liens montres, et `voisins` : les voisins entendus a la selection (Zigbee).
    init(_ e: EntreeScene, ailleurs: Bool, mode: ModeLiens = .tous, voisins: Bool = true) {
        let ids = e.scene.noeuds.map(\.id)
        couleurs = Dictionary(ids.compactMap { id in e.apparences[id].map { (id, $0.couleur) } },
                              uniquingKeysWith: { a, _ in a })
        routeursSimples = Set(ids.filter { e.apparences[$0]?.cercle == true })
        verifies = Set(ids.filter { e.apparences[$0]?.verifie == true })
        sondes = Set(ids.filter { e.apparences[$0]?.sonde == true })
        inconnus = Set(e.scene.noeuds.filter(\.inconnu).map(\.id))
        chefs = Set(e.scene.noeuds.filter(\.chef).map(\.id))
        endormis = Set(e.scene.noeuds.filter { LibellesNoeuds.endormi(e.appareils[$0.id], routeur: $0.routeur) }
            .map(\.id))
        piles = Set(ids.filter { e.libelles[$0]?.pastille != nil })
        candidats = Set(ids.filter { id in
            // Les candidats sont ceux d'un routeur de bordure du maillage de Thread, par cle de Thread.
            id.protocole == .thread
                && e.maillageThread?.noeud(id.cle).map { $0.genre == .routeur && !$0.candidats.isEmpty } == true
        })
        liens = e.scene.liens
        self.ailleurs = ailleurs
        self.mode = mode
        self.voisins = voisins
    }
}

/// Grille de la legende (maquette : `grid-template-columns: 1fr 1fr ; gap: 9px 18px`) : deux colonnes
/// de meme largeur, celle du groupe le plus large, et au moins la moitie d'un panneau de 440 pt ; les
/// groupes se rangent deux par deux, dans l'ordre. La maquette borne le panneau a 440 pt, et ses
/// entrees, qui ne passent jamais a la ligne, en debordent quand elles y sont toutes : la grille
/// s'elargit plutot.
struct GrilleLegende: Layout {
    static let largeurPanneau: CGFloat = 440
    /// Marges du panneau, a gauche et a droite.
    static let marges: CGFloat = 24
    static let ecartColonnes: CGFloat = 18
    static let ecartRangs: CGFloat = 9

    /// Largeur des deux colonnes, d'apres la largeur de chaque groupe.
    static func largeurColonne(_ largeurs: [CGFloat]) -> CGFloat {
        max((largeurPanneau - marges - ecartColonnes) / 2, largeurs.max() ?? 0)
    }

    private struct Mise {
        var colonne: CGFloat
        var tailles: [CGSize]
        var rangs: [CGFloat]
    }

    private func mise(_ subviews: Subviews) -> Mise {
        let tailles = subviews.map { $0.sizeThatFits(.unspecified) }
        let rangs = stride(from: 0, to: tailles.count, by: 2).map { i in
            max(tailles[i].height, i + 1 < tailles.count ? tailles[i + 1].height : 0)
        }
        return Mise(colonne: Self.largeurColonne(tailles.map(\.width)), tailles: tailles, rangs: rangs)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = mise(subviews)
        return CGSize(width: 2 * m.colonne + Self.ecartColonnes,
                      height: m.rangs.reduce(0, +) + Self.ecartRangs * CGFloat(max(0, m.rangs.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = mise(subviews)
        var y = bounds.minY
        for (k, hauteur) in m.rangs.enumerated() {
            for c in 0..<2 where 2 * k + c < subviews.count {
                let i = 2 * k + c
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(c) * (m.colonne + Self.ecartColonnes), y: y),
                                  proposal: ProposedViewSize(m.tailles[i]))
            }
            y += hauteur + Self.ecartRangs
        }
    }
}

/// « Releve de la sonde ancien » : une petite pastille orange, a cote de la ligne de niveau, en haut a gauche
/// (`RangeeNiveau`), quand le releve de la sonde a plus de 6 minutes (polissage B, section 2). Le dessin de la
/// pastille du chef de la fiche (10,5 pt, marges de 2 x 8 pt, capsule teintee a 0,16 au filet de 0,5 pt a 0,5), en
/// orange.
struct PastilleAncien: View {
    /// Sa hauteur (pt), mesuree : celle de la rangee de la ligne de niveau (`RangeeNiveau`).
    static let hauteur = NSHostingView(rootView: PastilleAncien()).fittingSize.height

    var body: some View {
        Text("Relevé de la sonde ancien")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette(sombre: true).appareil(.partitionCoupee))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette(sombre: true).appareil(.partitionCoupee).opacity(0.16)))
            .overlay(Capsule().strokeBorder(Palette(sombre: true).appareil(.partitionCoupee).opacity(0.5), lineWidth: 0.5))
    }
}

extension View {
    /// Verre de la legende (verification du 02/10 : le choix de Djoko, au lieu du panneau sombre de la maquette A) :
    /// celui des capsules du haut, en rectangle aux coins de 10 pt ; le texte, clair, se lit sur la scene sombre. Une
    /// capture, qui ne rend pas le verre, pose a sa place le fond des capsules dans les captures (rgba(40, 48, 72,
    /// 0,38), filet de 0,5 pt blanc a 0,22, ombre noire a 0,35), aux memes coins.
    func verreDeLegende() -> some View {
        modifier(VerreDeLegende())
    }
}

private struct VerreDeLegende: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content
                .background(RoundedRectangle(cornerRadius: 10).fill(fondVerreCapture.opacity(0.38))
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}
