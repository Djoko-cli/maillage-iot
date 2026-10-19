import AppKit
import MaillageCoeur
import SwiftUI

/// Le panneau de sante de la vue par pieces (spec du panneau de sante, section 2) : les noeuds perdus et ceux a surveiller, par
/// protocole, d'un coup d'oeil. En haut a gauche, sous le haut de la vue (la legende reste en bas a gauche), en verre comme elle
/// (`verreDeLegende`, repli de capture compris) et avec son animation (`Apparition.transitionSante`, 0,45 s, ancree en haut a
/// gauche).
///
/// - **Replie : la capsule** (option C). « Sante », puis pour chaque protocole montre son signe (celui de la legende) et deux
///   pastilles, rouge (perdus) et orange (a surveiller), celle a zero cachee ; « Tout va bien » quand rien ne va mal nulle part ;
///   « … » pour un protocole sans releve. Les comptes sont ceux de toute la maison, quel que soit le focus.
/// - **Ouvert : la liste** (option B). Le titre « Sante · <portee> », une section par protocole (signe, nom, pastilles de la
///   portee), une ligne par noeud (point rouge ou orange, nom, piece, cause a droite ; perdus d'abord), « Rien a signaler » pour
///   une section vide, et, hors de la vue d'ensemble, la ligne « Ailleurs » qui ramene a la vue d'ensemble. La liste suit le
///   focus (`SantePieces.Lecture`, deja calculee par la fenetre). Sa hauteur est bornee (`hauteurMax` : la moitie de l'espace
///   libre) : au-dela, la liste defile dans le panneau.
/// - **Un clic sur une ligne** mene au noeud (`MoteurPieces.allerAuNoeud`) ; la ligne d'un noeud absent de la scene est attenuee
///   et ne se clique pas.
/// - **Le repli** est garde d'un lancement a l'autre (`cleRepliee`, distinct de celui de la legende), replie par defaut.
/// - **Obstacle** : replie ou ouvert, le panneau est un obstacle pour les noms de la scene (comme la legende), retire quand il
///   n'est pas montre.
///
/// Les textes viennent d'un modele d'affichage pur (`capsule`, `ouvert`), que les tests lisent : la vue ne fait que le dessiner.
struct PanneauSante: View {
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.capturePieces) private var capture
    @AppStorage(PanneauSante.cleRepliee) private var replieeGardee = true

    /// La preference qui garde le repli : replie par defaut.
    static let cleRepliee = "santeRepliee"
    /// Largeur du panneau ouvert (pt), marges comprises ; la capsule a celle de son contenu.
    static let largeur: CGFloat = 400
    /// Marges du panneau ouvert, comme la legende : 9, 12, 11 et 12 pt.
    static let marges = EdgeInsets(top: 9, leading: 12, bottom: 11, trailing: 12)

    /// Ce que le panneau montre, calcule une fois par rendu par la fenetre (`MemoSante`).
    let lecture: SantePieces.Lecture
    let moteur: MoteurPieces
    /// L'instant du rendu (la fenetre se redessine chaque minute) : les dates de disparition sont relatives a l'heure du modele de
    /// chaque protocole (`Surveillance.maintenant(de:a:)`), comme dans la fiche.
    var instant = Date()
    /// La hauteur maximale du panneau ouvert (pt) ; nil : sans limite.
    var hauteurMax: CGFloat?
    /// Replie ou ouvert, impose (captures) : la preference n'est alors ni ecrite, ni suivie.
    var forcee: Bool?

    private var estRepliee: Bool { forcee ?? replieeGardee }

    var body: some View {
        if !lecture.estVide {
            Group {
                // Le panneau parait depuis la capsule et s'y replie, en 0,45 s ; un fondu seul avec « Reduire les animations ».
                if estRepliee {
                    capsuleVue
                        .transition(Apparition.transitionSante(reduire: reduire))
                } else {
                    ouvertVue
                        .transition(Apparition.transitionSante(reduire: reduire))
                }
            }
            .animation(Apparition.animationDuConteneurLegende(reduire: reduire), value: estRepliee)
            .obstacle("sante", moteur)
        }
    }

    private func replier(_ r: Bool) {
        guard forcee == nil else { return }
        replieeGardee = r
    }

    // MARK: - Replie : la capsule

    /// « Sante », les protocoles et leurs pastilles, un chevron vers le bas (il ouvre vers le bas) : 11,5 pt semi-gras, marges de
    /// 6 x 12 pt, comme l'etiquette de la legende.
    private var capsuleVue: some View {
        let c = Self.capsule(lecture.capsule)
        return Button {
            replier(false)
        } label: {
            HStack(spacing: 8) {
                Text("Santé")
                    .font(.system(size: 11.5, weight: .semibold))
                if c.toutVaBien {
                    Text("Tout va bien")
                        .font(.system(size: 11))
                } else {
                    ForEach(c.entrees, id: \.protocole) { entreeVue($0) }
                }
                Self.chevron(repliee: true)
            }
            .foregroundStyle(Palette.texteLegende)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .flouDeCapture(capture)
            .verreDeLegende()
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilite(c))
    }

    /// Un protocole de la capsule : son signe, puis ses pastilles, ou « … » (sans releve), ou une coche (rien a signaler, alors
    /// qu'un autre protocole a quelque chose).
    private func entreeVue(_ e: EntreeCapsule) -> some View {
        HStack(spacing: 5) {
            SigneLegende(signe: LegendePieces.signeProtocole(e.protocole))
                .accessibilityHidden(true)
            switch e.contenu {
            case .attente:
                Text(verbatim: "…")
                    .accessibilityLabel(Text("premier relevé en attente"))
            case .pastilles(let pastilles):
                ForEach(pastilles) { PastilleSante(pastille: $0) }
            case .rienAFaire:
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Palette(sombre: true).appareil(.joignable))
                    .accessibilityLabel(Text("Tout va bien"))
            }
        }
        .font(.system(size: 11))
    }

    /// Le chevron de l'en-tete ou de la capsule : il montre ce que fait un clic. Le panneau s'ouvre vers le bas : replie, un
    /// chevron vers le bas ; ouvert, vers le haut (a l'inverse de la legende, qui s'ouvre vers le haut).
    static func chevron(repliee: Bool) -> some View {
        Image(systemName: repliee ? "chevron.down" : "chevron.up")
            .font(.system(size: 8.5, weight: .bold))
            .accessibilityHidden(true)
    }

    // MARK: - Ouvert : la liste

    private var ouvertVue: some View {
        let o = Self.ouvert(lecture) { surveillance.maintenant(de: $0, a: instant) }
        let borne = hauteurMax.map { max(0, $0 - Self.marges.top - Self.marges.bottom) }
        return ColonneLimitee(hauteurMax: borne, ecart: LegendePieces.ecartLigneProtocoles) {
            Button {
                replier(true)
            } label: {
                HStack {
                    Text(verbatim: o.titre)
                    Spacer(minLength: 8)
                    Self.chevron(repliee: false)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            corps(o)
            if let ailleurs = o.ailleurs {
                Button {
                    moteur.versMaison()
                } label: {
                    Text(verbatim: ailleurs)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.titreLegende)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .clipped()
        .font(.system(size: 11))
        .foregroundStyle(Palette.texteLegende)
        .frame(width: Self.largeur - Self.marges.leading - Self.marges.trailing)
        .padding(Self.marges)
        .flouDeCapture(capture)
        .verreDeLegende()
        // Le contenu qui change (le focus, un noeud qui entre ou sort) : le cadre en verre et les lignes suivent le mouvement.
        .animation(Apparition.animationDuContenuLegende(reduire: reduire), value: lecture)
    }

    /// Les sections, dans une zone qui defile. Une capture (`ImageRenderer`) ne rend pas un `ScrollView` : elle pose a sa place les
    /// sections, que la colonne coupe a sa hauteur (`clipped`).
    @ViewBuilder
    private func corps(_ o: Ouvert) -> some View {
        let sections = VStack(alignment: .leading, spacing: 9) {
            ForEach(o.sections) { sectionVue($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if capture {
            sections
        } else {
            ScrollView { sections }
        }
    }

    private func sectionVue(_ s: SectionAffichee) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                SigneLegende(signe: LegendePieces.signeProtocole(s.protocole))
                    .accessibilityHidden(true)
                Text(verbatim: s.nom)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                ForEach(s.pastilles) { PastilleSante(pastille: $0) }
            }
            switch s.corps {
            case .lignes(let lignes):
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(lignes) { ligneVue($0) }
                }
            case .rienASignaler:
                Text("Rien à signaler")
                    .foregroundStyle(Palette.titreLegende)
                    .padding(.horizontal, 4)
            case .attente:
                Text(verbatim: "…")
                    .foregroundStyle(Palette.titreLegende)
                    .padding(.horizontal, 4)
                    .accessibilityLabel(Text("premier relevé en attente"))
            }
        }
        .transition(Apparition.transitionLigneLegende)
    }

    /// Une ligne : le point de sa famille, le nom, la piece, la cause a droite. La cause garde sa place, puis la piece : c'est le
    /// nom qui se coupe. Un noeud absent de la scene est attenue, sans clic.
    @ViewBuilder
    private func ligneVue(_ l: LigneAffichee) -> some View {
        let contenu = HStack(spacing: 6) {
            Circle()
                .fill(Self.couleur(l.famille))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(verbatim: l.nom)
                .lineLimit(1)
            if let piece = l.piece {
                Text(verbatim: piece)
                    .foregroundStyle(Palette.titreLegende)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: l.cause)
                .foregroundStyle(Palette.texteLegende.opacity(0.78))
                .lineLimit(1)
                .layoutPriority(2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        if l.cliquable {
            Button {
                moteur.allerAuNoeud(l.id)
            } label: {
                contenu
            }
            .buttonStyle(StyleLigneSante())
            .transition(Apparition.transitionLigneLegende)
        } else {
            contenu
                .opacity(0.5)
                .help(Text("Ce nœud n'est pas dans la scène"))
                .transition(Apparition.transitionLigneLegende)
        }
    }

    /// Le rouge des perdus (celui d'un appareil disparu dans la scene) et l'orange des noeuds a surveiller.
    static func couleur(_ f: SantePieces.Famille) -> Color {
        switch f {
        case .perdu: Palette(sombre: true).appareil(.disparu)
        case .aSurveiller: Palette(sombre: true).appareil(.partitionCoupee)
        }
    }
}

extension View {
    /// Le flou du vrai verre, que la capture ne rend pas : sous le verre de repli (translucide, comme celui de la legende), un fond
    /// presque opaque, pour que la scene et les etiquettes de niveau, dessinees dessous, ne traversent pas la liste.
    fileprivate func flouDeCapture(_ capture: Bool) -> some View {
        background {
            if capture { RoundedRectangle(cornerRadius: 10).fill(fondVerreCapture.opacity(0.9)) }
        }
    }
}

// MARK: - Le modele d'affichage

extension PanneauSante {
    /// Une pastille : le nombre de noeuds d'une famille.
    struct Pastille: Equatable, Identifiable {
        var famille: SantePieces.Famille
        var nombre: Int
        var id: Int { famille == .perdu ? 0 : 1 }
    }

    /// Ce qu'un protocole montre dans la capsule.
    enum ContenuCapsule: Equatable {
        /// « … » : aucun releve encore.
        case attente
        case pastilles([Pastille])
        /// Rien a signaler, alors qu'un autre protocole a quelque chose : une coche, pour que le signe ne reste pas seul.
        case rienAFaire
    }

    struct EntreeCapsule: Equatable {
        var protocole: Protocole
        var contenu: ContenuCapsule
    }

    /// La capsule : « Tout va bien » (sans protocoles) ou les protocoles et leurs pastilles.
    struct Capsule: Equatable {
        var toutVaBien: Bool
        var entrees: [EntreeCapsule]
    }

    /// Une ligne du panneau ouvert, en texte.
    struct LigneAffichee: Equatable, Identifiable {
        var id: IdNoeud
        var nom: String
        var piece: String?
        var cause: String
        var famille: SantePieces.Famille
        var cliquable: Bool
    }

    enum CorpsSection: Equatable {
        case lignes([LigneAffichee])
        case rienASignaler
        /// « … » : le protocole n'a encore aucun releve.
        case attente
    }

    struct SectionAffichee: Equatable, Identifiable {
        var protocole: Protocole
        var nom: String
        var pastilles: [Pastille]
        var corps: CorpsSection
        var id: Protocole { protocole }
    }

    /// Le panneau ouvert : son titre, ses sections, la ligne « Ailleurs ».
    struct Ouvert: Equatable {
        var titre: String
        var sections: [SectionAffichee]
        var ailleurs: String?
    }

    /// Les pastilles d'un compte : les perdus (rouge) puis les a surveiller (orange), celles a zero omises.
    static func pastilles(_ c: SantePieces.Comptes) -> [Pastille] {
        var p: [Pastille] = []
        if c.perdus > 0 { p.append(Pastille(famille: .perdu, nombre: c.perdus)) }
        if c.aSurveiller > 0 { p.append(Pastille(famille: .aSurveiller, nombre: c.aSurveiller)) }
        return p
    }

    /// La capsule d'un resume (comptes de toute la maison). « Tout va bien » quand au moins un protocole est montre, tous releves,
    /// et rien de perdu ni a surveiller ; sinon chaque protocole : « … » sans releve, ses pastilles, ou une coche s'il n'a rien.
    static func capsule(_ r: SantePieces.Resume) -> Capsule {
        if r.toutVaBien { return Capsule(toutVaBien: true, entrees: []) }
        let entrees = r.entrees.map { e -> EntreeCapsule in
            guard let comptes = e.comptes else { return EntreeCapsule(protocole: e.protocole, contenu: .attente) }
            let p = pastilles(comptes)
            return EntreeCapsule(protocole: e.protocole, contenu: p.isEmpty ? .rienAFaire : .pastilles(p))
        }
        return Capsule(toutVaBien: false, entrees: entrees)
    }

    /// Le texte d'une pastille, en toutes lettres : « 1 perdu », « 3 perdus », « 2 a surveiller ».
    static func texte(_ p: Pastille) -> String {
        switch p.famille {
        case .perdu: p.nombre == 1 ? String(localized: "1 perdu") : String(localized: "\(p.nombre) perdus")
        case .aSurveiller: String(localized: "\(p.nombre) à surveiller")
        }
    }

    /// Le texte de la cause d'une ligne. `reference` : l'heure du modele du protocole du noeud ; la date de la disparition est
    /// relative a elle, en unites courtes, comme dans la fiche (« disparu il y a 5 min »), ou absente (« disparu » seul).
    static func texte(_ cause: SantePieces.Cause, reference: Date) -> String {
        func relatif(_ d: Date) -> String { FicheNoeud.relatif(d, reference, unites: .short) }
        switch cause {
        case .disparu(let depuis?): return String(localized: "disparu \(relatif(depuis))")
        case .disparu(nil): return String(localized: "disparu")
        case .routeurDisparu(let depuis?): return String(localized: "routeur disparu \(relatif(depuis))")
        case .routeurDisparu(nil): return String(localized: "routeur disparu")
        case .pontDisparu(let depuis?): return String(localized: "pont disparu \(relatif(depuis))")
        case .pontDisparu(nil): return String(localized: "pont disparu")
        case .injoignable: return String(localized: "injoignable")
        case .pontInjoignable: return String(localized: "pont injoignable")
        case .pile(let niveau?): return String(localized: "pile \(String(localized: "\(niveau)\u{202F}%"))")
        case .pile(nil): return String(localized: "pile faible")
        case .adressePlusAnnoncee: return String(localized: "adresse plus annoncée")
        case .adresseNonAnnoncee: return String(localized: "adresse non annoncée")
        case .autrePartition: return String(localized: "autre partition")
        }
    }

    /// Le titre du panneau ouvert : « Sante · » puis la portee (« Maison », le niveau ou la piece isoles, par leur nom).
    static func titre(_ p: SantePieces.Portee) -> String {
        let nom = switch p {
        case .maison: String(localized: "Maison")
        case .etage(let nom), .piece(let nom): nom
        }
        return String(localized: "Santé · \(nom)")
    }

    /// La ligne « Ailleurs » : « Ailleurs : 1 perdu, 2 a surveiller ».
    static func texteAilleurs(_ c: SantePieces.Comptes) -> String {
        String(localized: "Ailleurs : \(pastilles(c).map { texte($0) }.joined(separator: ", "))")
    }

    /// La phrase que lit VoiceOver pour la capsule.
    static func accessibilite(_ c: Capsule) -> String {
        let titre = String(localized: "Santé")
        if c.toutVaBien { return String(localized: "\(titre) : \(String(localized: "Tout va bien"))") }
        let parties = c.entrees.map { e -> String in
            let detail = switch e.contenu {
            case .attente: String(localized: "premier relevé en attente")
            case .pastilles(let p): p.map { texte($0) }.joined(separator: ", ")
            case .rienAFaire: String(localized: "Tout va bien")
            }
            return String(localized: "\(LegendePieces.nomProtocole(e.protocole)) : \(detail)")
        }
        return String(localized: "\(titre) : \(parties.joined(separator: " ; "))")
    }

    /// Le panneau ouvert d'une lecture, en texte. `reference` : l'heure du modele de chaque protocole.
    static func ouvert(_ l: SantePieces.Lecture, reference: (Protocole) -> Date) -> Ouvert {
        let sections = l.sections.map { s -> SectionAffichee in
            let corps: CorpsSection = if s.enAttente {
                .attente
            } else if s.lignes.isEmpty {
                .rienASignaler
            } else {
                .lignes(s.lignes.map { m in
                    LigneAffichee(id: m.id, nom: m.nom, piece: m.piece,
                                  cause: texte(m.cause, reference: reference(m.id.protocole)), famille: m.famille,
                                  cliquable: m.cliquable)
                })
            }
            return SectionAffichee(protocole: s.protocole, nom: LegendePieces.nomProtocole(s.protocole),
                                   pastilles: pastilles(s.comptes), corps: corps)
        }
        return Ouvert(titre: titre(l.portee), sections: sections, ailleurs: l.ailleurs.map(texteAilleurs))
    }

    /// La hauteur maximale du panneau ouvert : la moitie de l'espace libre, entre le haut de la vue (`margeHaut`, sous ce qui est
    /// pose en haut) et ce qui est pose en bas (`margeBas`, la legende ou la fiche) ; jamais negative. La scene reste lisible.
    static func hauteurMax(vue: CGFloat, margeHaut: CGFloat, margeBas: CGFloat) -> CGFloat {
        max(0, (vue - margeHaut - margeBas) / 2)
    }
}

// MARK: - Les gestes

extension MoteurPieces {
    /// Va au noeud `id`, comme un clic sur lui dans la scene, depuis la vue d'ensemble, un niveau isole ou une autre piece : la
    /// piece du noeud est isolee (le vol de camera habituel, sans rien faire si elle l'est deja), puis le noeud est choisi (sa
    /// fiche, le mode focus). Un second clic le garde choisi (le clic sur la scene, lui, le deselectionne). Rend faux, sans rien
    /// changer, pour un noeud qui n'est pas dans la scene, et pendant l'envol 2D / 3D (comme un clic sur la scene).
    @discardableResult
    func allerAuNoeud(_ id: IdNoeud) -> Bool {
        guard envol == nil, fondu == nil, let noeud = scene?.noeud(id) else { return false }
        isoler(noeud.piece)
        selection = id
        return true
    }
}

// MARK: - La lecture memoisee

/// La lecture du panneau, memoisee par la vue. Le journal (qui garde 90 jours d'evenements) est lu pour deux choses : les routeurs
/// disparus (`routeursDisparus`, tout le journal) et les dates de disparition (`disparitions`, les evenements de chaque noeud
/// disparu) ; aucun des deux ne change tant que le journal ne change pas, alors que la fenetre se redessine a chaque minute,
/// a chaque noeud survole ou choisi, a chaque isolement. Le reste de la lecture (les familles, la portee) se refait a chaque
/// fois : il ne relit que la scene, qui est petite.
@MainActor
final class MemoSante {
    /// Combien de fois le journal a ete relu pour les routeurs disparus, et pour les dates (les tests).
    private(set) var lecturesDuJournal = 0
    private(set) var lecturesDesDates = 0

    /// Ce qui change quand le journal change : sa taille et ses dates extremes (il ne fait que s'allonger, sauf une reprise ou
    /// un tri de demo, qui changent l'un des trois).
    private struct CleJournal: Equatable {
        var nombre: Int
        var premier: Date?
        var dernier: Date?
    }

    private struct CleRouteurs: Equatable {
        var journal: CleJournal
        var releves: Set<Protocole>
    }

    private struct CleDates: Equatable {
        var journal: CleJournal
        var disparus: Set<IdNoeud>
    }

    private var routeurs: (cle: CleRouteurs, valeur: [SantePieces.RouteurDisparu])?
    private var dates: (cle: CleDates, valeur: [IdNoeud: SantePieces.Disparition])?

    /// La lecture de la scene `entree` au focus `isolement` (`SantePieces.lire`), avec le journal lu seulement s'il a change.
    func lire(entree: EntreeScene, isolement: Isolement, surveillance s: Surveillance) -> SantePieces.Lecture {
        let journal = CleJournal(nombre: s.evenements.count, premier: s.evenements.first?.date, dernier: s.evenements.last?.date)
        let cleRouteurs = CleRouteurs(journal: journal, releves: SantePieces.releveDeLaSession(s))
        let disparus = Set(entree.appareils.values.filter { $0.etat == .disparu }.map(\.id))
        let cleDates = CleDates(journal: journal, disparus: disparus)
        if routeurs?.cle != cleRouteurs {
            lecturesDuJournal += 1
            routeurs = (cleRouteurs, SantePieces.routeursDisparus(journal: s.evenements, releves: cleRouteurs.releves))
        }
        if dates?.cle != cleDates {
            lecturesDesDates += 1
            dates = (cleDates, SantePieces.disparitions(entree: entree) { s.evenements(de: $0) })
        }
        return SantePieces.lire(entree: entree, isolement: isolement,
                                montres: SantePieces.montres(entree: entree, surveillance: s),
                                disparitions: dates?.valeur ?? [:], routeursDisparus: routeurs?.valeur ?? [],
                                sansReleve: SantePieces.sansReleve(s))
    }
}

/// Le panneau dans la fenetre : lit le focus du moteur (le titre et la liste le suivent) et la lecture memoisee, sans que la
/// fenetre entiere se redessine quand le focus change. Rien sans scene.
struct PanneauSanteDeLaFenetre: View {
    @Environment(Surveillance.self) private var surveillance
    let moteur: MoteurPieces
    let entree: EntreeScene?
    let instant: Date
    let hauteurMax: CGFloat?
    /// Replie ou ouvert, impose (captures) ; nil : le repli garde.
    var forcee: Bool?
    /// L'espace au-dessus du panneau (pt), quand il est montre : l'ecart qui le separe de la ligne du haut qui le precede
    /// (`HautPieces.apres`). Rien de plus quand il n'y a rien a montrer : la colonne du haut ne grandit pas.
    var ecart: CGFloat = 0
    @State private var memo = MemoSante()

    var body: some View {
        if let entree {
            let lecture = memo.lire(entree: entree, isolement: moteur.isolement, surveillance: surveillance)
            if !lecture.estVide {
                PanneauSante(lecture: lecture, moteur: moteur, instant: instant, hauteurMax: hauteurMax, forcee: forcee)
                    .padding(.top, ecart)
            }
        }
    }
}

// MARK: - Les pieces de la vue

/// Une pastille de compte : le nombre, dans la couleur de sa famille, en capsule teintee a 0,16 au filet de 0,5 pt a 0,5, comme
/// la pastille d'un releve ancien.
struct PastilleSante: View {
    let pastille: PanneauSante.Pastille

    var body: some View {
        let couleur = PanneauSante.couleur(pastille.famille)
        Text(verbatim: "\(pastille.nombre)")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(couleur)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(couleur.opacity(0.16)))
            .overlay(Capsule().strokeBorder(couleur.opacity(0.5), lineWidth: 0.5))
            .accessibilityLabel(Text(verbatim: PanneauSante.texte(pastille)))
    }
}

/// Le style d'une ligne cliquable : un fond clair au survol et au clic, la main du pointeur.
private struct StyleLigneSante: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Corps(etiquette: configuration.label, enfonce: configuration.isPressed)
    }

    private struct Corps<Etiquette: View>: View {
        let etiquette: Etiquette
        let enfonce: Bool
        @State private var survol = false

        var body: some View {
            etiquette
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(enfonce ? 0.16 : survol ? 0.09 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { survol = $0 }
                .pointerStyle(.link)
        }
    }
}

/// Une colonne de trois pieces au plus : l'en-tete, le corps defilant, le pied (facultatif). Sa hauteur est celle de son
/// contenu, bornee par `hauteurMax` (marges du panneau exclues) : au-dela, le corps prend le reste et defile. Sans proposition de
/// hauteur (`fittingSize`) comme avec une proposition de la fenetre, la borne est la meme : la hauteur ne vient jamais de ce que
/// la fenetre propose (un `ScrollView` prend toute la hauteur proposee, ce qui etirerait une liste courte).
private struct ColonneLimitee: Layout {
    var hauteurMax: CGFloat?
    var ecart: CGFloat
    /// Hauteur minimale du corps defilant, quand la borne est plus petite que l'en-tete et le pied (pt) : une ligne.
    static let corpsMinimal: CGFloat = 24

    private struct Mesure {
        var entete: CGFloat
        var pied: CGFloat
        var corps: CGFloat
        var fixe: CGFloat
    }

    private func mesure(largeur: CGFloat, _ sv: Subviews) -> Mesure {
        let p = ProposedViewSize(width: largeur, height: nil)
        let entete = sv[0].sizeThatFits(p).height
        let pied = sv.count > 2 ? sv[2].sizeThatFits(p).height : 0
        return Mesure(entete: entete, pied: pied, corps: sv[1].sizeThatFits(p).height,
                      fixe: entete + pied + ecart * CGFloat(sv.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count >= 2 else { return .zero }
        let largeur = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let m = mesure(largeur: largeur, subviews)
        let total = m.fixe + m.corps
        let borne = hauteurMax.map { max($0, m.fixe + Self.corpsMinimal) } ?? total
        return CGSize(width: largeur, height: min(total, borne))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let m = mesure(largeur: bounds.width, subviews)
        let corps = max(0, bounds.height - m.fixe)
        var y = bounds.minY
        func poser(_ i: Int, _ hauteur: CGFloat) {
            subviews[i].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: hauteur))
            y += hauteur + ecart
        }
        poser(0, m.entete)
        poser(1, corps)
        if subviews.count > 2 { poser(2, m.pied) }
    }
}
