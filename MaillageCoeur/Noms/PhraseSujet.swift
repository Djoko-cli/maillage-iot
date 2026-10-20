import Foundation

/// Langue des textes du journal. Seul le francais accorde ; toute autre langue nomme le noeud sans accord
/// (« Desk lamp (Office) lost its parent »).
public enum LangueSujet: Sendable, Equatable {
    case francais, anglais

    /// Depuis un code de langue (« fr », « fr-FR », « en »...) : le francais, sinon l'anglais (sans accord).
    public init(code: String?) {
        self = code?.lowercased().hasPrefix("fr") == true ? .francais : .anglais
    }
}

/// Genre et nombre du sujet, pour accorder le verbe et le participe qui le suivent : « La lampe du bureau est apparue »,
/// « Les volets de la chambre sont apparus ». Un sujet sans article (mot inconnu, sans piece, anglais) reste au masculin
/// singulier, comme le texte d'avant.
public struct AccordSujet: Hashable, Sendable {
    public var feminin: Bool
    public var pluriel: Bool

    public init(feminin: Bool = false, pluriel: Bool = false) {
        self.feminin = feminin
        self.pluriel = pluriel
    }
}

/// Le sujet d'une ligne du journal, d'une notification ou d'une entree du menu : le nom du noeud avec sa piece, en
/// francais naturel (« La lampe du bureau a perdu son parent »).
///
/// Cinq formes en francais (decisions de Djoko, 20/10) :
/// - **le nom contient la piece, mots connus** : « La lampe du bureau » (du, de la, de l', des ; elision) ;
/// - **nom sans la piece, piece connue** : « HomePod Avant, dans le salon, » (dans le, la, l', les ; sur, a l'etage) ;
/// - **mot inconnu** (appareil ou piece) : aucun article invente : « Hue Go (droite) — Zone Z7 : » ;
/// - **sans piece** : le nom seul, comme avant ;
/// - **anglais** : « Desk lamp (Office) », sans accord.
/// Un mot d'appareil connu recoit son article partout (« La lampe chevet, dans le bureau, »). Le mot de la piece n'est
/// retire du nom que s'il en termine ou en commence le texte, en mots entiers, sans casse ni accents : « Salon de thé »
/// dans la piece « Salon » ne perd pas son « Salon ». Une piece suivie d'un numero ou d'un mot court sans sens propre
/// (« Lampe salon 2 », « Prise cuisine bis ») est retiree aussi, et le numero passe avant elle : « La lampe 2 du salon ».
/// Un mot d'appareil colle a un trait d'union (« radio-reveil ») est un mot compose : connu au lexique il s'accorde, inconnu
/// il n'a pas d'article.
/// Une precision entre parentheses en fin de nom (« (Hue) », « (droite) ») est mise de cote : la phrase se construit sur le
/// reste, puis la parenthese est remise juste apres le groupe nominal (« La prise du salon (Hue) », « La lampe chevet
/// (droite), dans le bureau, »). Une parenthese au milieu du nom, ou qui est la piece elle-meme, n'est pas touchee.
public struct PhraseSujet: Hashable, Sendable {
    /// Le sujet, sans ponctuation finale : « La lampe du bureau », « HomePod Avant, dans le salon ». Il se place tel
    /// quel au milieu d'une phrase (avec `debutDePhrase: false`, sans majuscule a l'article).
    public let texte: String
    /// Ce qui separe le sujet du verbe : vide, « , » (la piece est une incise) ou « : » (precede d'une espace).
    public let suite: String

    init(texte: String, suite: String, accord: AccordSujet = AccordSujet()) {
        self.texte = texte
        self.suite = suite
        self.accord = accord
    }

    /// L'accord du verbe : celui du mot d'appareil quand le sujet a recu son article, sinon masculin singulier.
    public let accord: AccordSujet

    /// Le sujet suivi du reste de la phrase : `suivi(de: "a perdu son parent")`.
    public func suivi(de predicat: String) -> String { texte + suite + " " + predicat }

    /// Le sujet du noeud `nom` dans la piece `piece` (celle de la scene ; nil ou vide : le nom seul).
    /// `debutDePhrase` : majuscule a l'article du groupe nominal (un nom propre garde sa casse).
    public static func de(nom: String, piece: String?, langue: LangueSujet, debutDePhrase: Bool = true) -> PhraseSujet {
        let piece = piece?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let jp = Texte.jetons(piece)
        guard !piece.isEmpty, !jp.isEmpty, !Texte.jetons(nom).isEmpty else { return PhraseSujet(texte: nom, suite: "") }
        // Les parentheses finales sont mises de cote : tout ce qui suit s'ecrit sur le nom restant.
        let (noyau, parentheses) = Self.sansParenthesesFinales(nom, piece: jp)
        let nom = noyau
        let jn = Texte.jetons(nom)
        let emplacement = Self.emplacement(de: jp, dans: jn)

        if langue == .anglais {
            // La piece est ajoutee entre parentheses seulement si le nom ne la dit pas deja, a n'importe quelle place.
            let dejaDite = Self.contient(jp, dans: jn)
            return PhraseSujet(texte: dejaDite ? noyau + parentheses : "\(noyau)\(parentheses) (\(piece))", suite: "")
        }

        let salle = LexiqueMaison.piece(dans: jp)
        func enTete(_ g: Groupe) -> String { debutDePhrase ? Self.majuscule(g.texte) : g.texte }

        // 1. Le nom contient la piece : on la retire, et si ce qui reste commence par un mot d'appareil connu on accorde.
        if let emplacement, let salle {
            let reste: Range<Int>
            switch emplacement {
            case .fin: reste = 0..<(jn.count - jp.count)
            case .debut: reste = jp.count..<jn.count
            case .avantQualificatif: reste = 0..<(jn.count - 1 - jp.count)
            }
            if let g = Self.groupe(nom, jn, reste) {
                let lieu = Self.lieu(piece, jp, salle)
                // « Lampe salon 2 » : le numero (ou le qualificatif) suit le groupe, la piece vient apres lui.
                let qualificatif = emplacement == .avantQualificatif ? " " + String(nom[jn[jn.count - 1].plage]) : ""
                let texte = g.texte + qualificatif + " " + lieu.avec(.de) + parentheses
                return PhraseSujet(texte: debutDePhrase ? Self.majuscule(texte) : texte, suite: "", accord: g.accord)
            }
        }
        // Le nom du noeud, avec l'article de son mot d'appareil quand il est connu, sinon tel quel.
        let groupeNom = Self.groupe(nom, jn, 0..<jn.count)
        let nomGroupe = (groupeNom.map(enTete) ?? nom) + parentheses
        let accord = groupeNom?.accord ?? AccordSujet()
        // 2. La piece termine le nom (mais le mot d'appareil est inconnu, ou la piece) : le nom dit deja la piece.
        if emplacement == .fin || emplacement == .avantQualificatif { return PhraseSujet(texte: nomGroupe, suite: "", accord: accord) }
        // 3. Piece connue : en incise.
        if let salle {
            let lieu = Self.lieu(piece, jp, salle)
            return PhraseSujet(texte: nomGroupe + ", " + lieu.dans, suite: ",", accord: accord)
        }
        // 4. Piece inconnue : aucun article invente.
        return PhraseSujet(texte: nomGroupe + " — " + piece, suite: " :", accord: accord)
    }

    // MARK: Interne

    /// `avantQualificatif` : la piece est suivie d'un seul mot final, un numero ou un qualificatif sans sens propre
    /// (« Lampe salon 2 », « Prise cuisine bis »).
    private enum Emplacement { case debut, fin, avantQualificatif }

    /// Ou la piece se trouve dans le nom : a la fin (de preference), au debut, ou juste avant un numero ou un qualificatif
    /// final qui suit un debut de nom (« Lampe salon 2 »), en mots entiers.
    private static func emplacement(de jp: [Texte.Jeton], dans jn: [Texte.Jeton]) -> Emplacement? {
        guard jp.count <= jn.count else { return nil }
        let mots = jp.map(\.plie)
        if Array(jn.suffix(jp.count)).map(\.plie) == mots { return .fin }
        if Array(jn.prefix(jp.count)).map(\.plie) == mots { return .debut }
        // Au moins un mot avant la piece, et un seul mot apres : le qualificatif.
        let apres = jn.count - 1
        if apres - jp.count >= 1, estQualificatif(jn[apres]),
           Array(jn[(apres - jp.count)..<apres]).map(\.plie) == mots { return .avantQualificatif }
        return nil
    }

    /// Mots courts sans sens propre qui suivent un nom : positions et variantes (« bis », « gauche »).
    private static let qualificatifs: Set<String> = ["bis", "ter", "quater", "gauche", "droite", "haut", "bas", "avant", "arriere"]

    /// Un numero, une lettre seule ou l'un des mots de `qualificatifs`.
    private static func estQualificatif(_ j: Texte.Jeton) -> Bool {
        guard !j.elide else { return false }
        return j.plie.allSatisfy(\.isNumber) || j.plie.count == 1 || qualificatifs.contains(j.plie)
    }

    /// Le texte de la piece (suite de mots entiers) apparait dans le nom, a n'importe quelle place.
    private static func contient(_ jp: [Texte.Jeton], dans jn: [Texte.Jeton]) -> Bool {
        let mots = jp.map(\.plie)
        guard !mots.isEmpty, mots.count <= jn.count else { return false }
        let noms = jn.map(\.plie)
        return (0...(noms.count - mots.count)).contains { Array(noms[$0..<($0 + mots.count)]) == mots }
    }

    /// Le nom sans ses parentheses finales (« Prise salon (Hue) » : « Prise salon » et « (Hue) »), dans l'ordre ecrit, chacune
    /// precedee d'une espace. Une parenthese qui est la piece elle-meme reste dans le nom (« Lampe (Bureau) »), et on ne met
    /// rien de cote si le nom n'a plus de mot ensuite.
    private static func sansParenthesesFinales(_ nom: String, piece jp: [Texte.Jeton]) -> (nom: String, parentheses: String) {
        let mots = jp.map(\.plie)
        var reste = Substring(nom).trimmingCharacters(in: .whitespacesAndNewlines)
        var trouvees: [String] = []
        while reste.hasSuffix(")"), let ouvrante = reste.lastIndex(of: "(") {
            let contenu = reste[reste.index(after: ouvrante)..<reste.index(before: reste.endIndex)]
            let jetons = Texte.jetons(String(contenu))
            guard !contenu.contains(")"), !jetons.isEmpty, jetons.map(\.plie) != mots else { break }
            let avant = String(reste[..<ouvrante]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Texte.jetons(avant).isEmpty else { break }
            trouvees.insert(String(reste[ouvrante...]), at: 0)
            reste = avant
        }
        guard !trouvees.isEmpty else { return (nom, "") }
        return (reste, trouvees.map { " " + $0 }.joined())
    }

    private static func majuscule(_ s: String) -> String {
        guard let c = s.first else { return s }
        return c.uppercased() + s.dropFirst()
    }

    /// Un groupe nominal d'appareil : l'article, le mot du lexique, et le reste du nom tel qu'ecrit.
    private struct Groupe {
        let texte: String
        /// Genre et nombre du mot d'appareil : ceux du sujet quand il recoit son article.
        let accord: AccordSujet
    }

    /// Mots qui lient (articles, prepositions) : retires aux bords du nom restant, jamais au milieu.
    private static let liaisons: Set<String> = ["de", "du", "des", "d", "la", "le", "les", "l", "dans", "au", "aux", "sur"]

    private static func estLiaison(_ j: Texte.Jeton) -> Bool {
        liaisons.contains(j.plie) && (j.plie.count > 1 || j.elide)
    }

    /// Le groupe nominal d'un nom (ou de ce qui en reste une fois la piece retiree) dont le premier mot, hors liaisons,
    /// est un mot d'appareil connu ; nil sinon.
    private static func groupe(_ nom: String, _ jetons: [Texte.Jeton], _ plage: Range<Int>) -> Groupe? {
        var debut = plage.lowerBound
        var fin = plage.upperBound
        while debut < fin, estLiaison(jetons[debut]) { debut += 1 }
        while fin > debut, estLiaison(jetons[fin - 1]) { fin -= 1 }
        guard debut < fin, let t = LexiqueMaison.appareil(dans: Array(jetons[..<fin]), depuis: debut) else { return nil }
        let dernierMot = jetons[debut + t.longueur - 1].plage.upperBound
        // Un mot colle a un trait d'union fait partie d'un mot compose inconnu (« radio-reveil », « capteur-temperature ») :
        // ce n'est pas le mot d'appareil, aucun article, aucun genre devine.
        if dernierMot < nom.endIndex, "-\u{2010}\u{2011}".contains(nom[dernierMot]) {
            let suivant = nom.index(after: dernierMot)
            if suivant < nom.endIndex, nom[suivant].isLetter || nom[suivant].isNumber { return nil }
        }
        var finTexte = jetons[fin - 1].plage.upperBound
        // Les fermantes qui suivent le dernier mot gardent leurs parentheses : « Lampe (droite) bureau ».
        while finTexte < nom.endIndex, ")]»".contains(nom[finTexte]) { finTexte = nom.index(after: finTexte) }
        let complement = dernierMot < finTexte ? String(nom[dernierMot..<finTexte]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let mot = t.mot.defini(pluriel: t.pluriel)
        return Groupe(texte: complement.isEmpty ? mot : mot + " " + complement,
                      accord: AccordSujet(feminin: t.mot.genre == .feminin, pluriel: t.pluriel || t.mot.toujoursPluriel))
    }

    /// Une piece connue, prete a recevoir une preposition : « salle de bain », « combles ».
    private struct Lieu {
        let mot: MotMaison
        let pluriel: Bool
        /// Ce que le nom de la piece ajoute au mot du lexique, tel qu'ecrit : « de bain ».
        let complement: String

        private var suite: String { complement.isEmpty ? "" : " " + complement }

        func avec(_ p: MotMaison.Preposition) -> String { mot.avecPreposition(p, pluriel: pluriel) + suite }

        var dans: String {
            switch mot.locatif {
            case .dans: avec(.dans)
            case .sur: avec(.sur)
            case .a: avec(.a)
            }
        }
    }

    private static func lieu(_ piece: String, _ jp: [Texte.Jeton], _ t: LexiqueMaison.Trouve) -> Lieu {
        let fin = piece.endIndex
        let apres = jp[t.longueur - 1].plage.upperBound
        let complement = apres < fin ? String(piece[apres..<fin]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return Lieu(mot: t.mot, pluriel: t.pluriel, complement: complement)
    }
}
