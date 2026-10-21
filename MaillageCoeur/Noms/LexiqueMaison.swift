import Foundation

/// Un mot de la maison (nom d'appareil ou de piece) : sa forme au singulier et au pluriel, son genre, son elision.
/// Tout est lu dans la table ci-dessous, jamais devine : l'accord automatique d'Apple ne connait pas le genre des noms
/// courants (essai du 20/10), et un h peut etre muet (« l'horloge ») ou aspire (« le hall »).
public struct MotMaison: Hashable, Sendable {
    public enum Genre: Sendable { case masculin, feminin }
    /// Ce qui place quelque chose dans une piece : « dans le salon » par defaut, « sur la terrasse », « a l'etage ».
    public enum Locatif: Sendable { case dans, sur, a }
    /// Preposition suivie de l'article defini : « de » donne du, de la, de l', des ; « a » donne au, a la, a l', aux.
    public enum Preposition: Sendable { case de, a, dans, sur }

    /// Forme ecrite au singulier, en minuscules (sauf sigle : « WC »).
    public let singulier: String
    public let pluriel: String
    public let genre: Genre
    /// Un mot qui ne s'emploie qu'au pluriel (« les combles », « les toilettes », « les WC »).
    public let toujoursPluriel: Bool
    /// Au singulier, l'article defini s'elide : voyelle ou h muet.
    public let elision: Bool
    public let locatif: Locatif

    /// Lit une ligne de la table : `genre mot[/pluriel] [!] [@sur|@a]`.
    /// - genre : `m`, `f`, `mp` ou `fp` (p : toujours au pluriel) ;
    /// - `!` : h aspire, pas d'elision ;
    /// - le pluriel par defaut est le singulier suivi d'un s (inchange s'il finit par s, x ou z).
    init(_ ligne: String) {
        let morceaux = ligne.split(separator: " ").map(String.init)
        precondition(morceaux.count >= 2, "ligne du lexique : \(ligne)")
        let codeGenre = morceaux[0]
        genre = codeGenre.hasPrefix("f") ? .feminin : .masculin
        toujoursPluriel = codeGenre.hasSuffix("p")
        let formes = morceaux[1].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        singulier = formes[0]
        if formes.count > 1 {
            pluriel = formes[1]
        } else if let fin = formes[0].last, "sxz".contains(fin) || toujoursPluriel {
            pluriel = formes[0]
        } else {
            pluriel = formes[0] + "s"
        }
        let options = Set(morceaux.dropFirst(2))
        let initiale = Texte.plier(singulier).first
        elision = !options.contains("!") && initiale.map { "aeiouh".contains($0) } == true
        locatif = options.contains("@sur") ? .sur : options.contains("@a") ? .a : .dans
    }

    /// La forme du mot au nombre voulu.
    public func forme(pluriel plur: Bool) -> String { plur || toujoursPluriel ? pluriel : singulier }

    /// Le mot precede de l'article defini : « la lampe », « l'entrée », « les volets ».
    public func defini(pluriel plur: Bool) -> String {
        articleDefini(pluriel: plur) + forme(pluriel: plur)
    }

    /// L'article defini, avec son espace ou son apostrophe : « la », « l'»...
    func articleDefini(pluriel plur: Bool) -> String {
        if plur || toujoursPluriel { return "les " }
        if elision { return "l'" }
        return genre == .masculin ? "le " : "la "
    }

    /// Preposition et article contractes : « du », « de la », « de l'», « des » ; « au », « à la »...
    func avecPreposition(_ p: Preposition, pluriel plur: Bool) -> String {
        let auPluriel = plur || toujoursPluriel
        let masculinPlein = !auPluriel && !elision && genre == .masculin
        let racine: String
        switch p {
        case .de: racine = auPluriel ? "des " : masculinPlein ? "du " : "de "
        case .a: racine = auPluriel ? "aux " : masculinPlein ? "au " : "à "
        case .dans: racine = "dans "
        case .sur: racine = "sur "
        }
        // Contracte (du, des, au, aux) : l'article est deja dans la racine.
        if auPluriel || masculinPlein, p == .de || p == .a { return racine + forme(pluriel: plur) }
        return racine + defini(pluriel: plur)
    }
}

/// Mots d'un nom ou d'une piece : comparaison sans casse ni accents, mot entier par mot entier.
enum Texte {
    /// Minuscules sans accents : « Entrée » et « ENTREE » se comparent egaux.
    static func plier(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
    }

    struct Jeton {
        /// Le mot plie.
        let plie: String
        /// Sa place dans le texte d'origine.
        let plage: Range<String.Index>
        /// Suivi d'une apostrophe (« l' », « d' ») : une elision, pas une lettre isolee.
        let elide: Bool
    }

    /// Les mots (lettres et chiffres) du texte, dans l'ordre ; tout le reste les separe.
    static func jetons(_ s: String) -> [Jeton] {
        var jetons: [Jeton] = []
        var debut: String.Index?
        var i = s.startIndex
        func clore(a fin: String.Index) {
            guard let d = debut else { return }
            let apostrophe = fin < s.endIndex && "'’ʼ".contains(s[fin])
            jetons.append(Jeton(plie: plier(String(s[d..<fin])), plage: d..<fin, elide: apostrophe))
            debut = nil
        }
        while i < s.endIndex {
            if s[i].isLetter || s[i].isNumber {
                if debut == nil { debut = i }
            } else {
                clore(a: i)
            }
            i = s.index(after: i)
        }
        clore(a: s.endIndex)
        return jetons
    }
}

/// Le lexique : les noms d'appareils et de pieces de la maison, avec leur genre. Un mot absent n'est jamais accorde
/// (la phrase du sujet n'invente aucun article).
public enum LexiqueMaison {
    public static let appareils: [MotMaison] = lignesAppareils.map(MotMaison.init)
    public static let pieces: [MotMaison] = lignesPieces.map(MotMaison.init)

    /// Un mot trouve dans un texte : le mot, son nombre, et les mots du texte qu'il couvre.
    struct Trouve {
        let mot: MotMaison
        let pluriel: Bool
        let longueur: Int
    }

    private static func index(_ mots: [MotMaison]) -> [String: (mot: MotMaison, pluriel: Bool)] {
        // Les singuliers d'abord : un mot du lexique gagne sur le pluriel d'un autre (« cours » n'est pas « les cour »).
        var r: [String: (mot: MotMaison, pluriel: Bool)] = [:]
        for singuliers in [true, false] {
            for m in mots {
                let (forme, plur) = singuliers ? (m.singulier, m.toujoursPluriel) : (m.pluriel, true)
                let cle = Texte.jetons(forme).map(\.plie).joined(separator: " ")
                if r[cle] == nil { r[cle] = (m, plur) }
            }
        }
        return r
    }

    private static let indexAppareils = index(appareils)
    private static let indexPieces = index(pieces)
    /// Le plus long mot du lexique, en mots du texte (« lave-linge » : 2).
    private static let longueurMax = 3

    /// Le mot d'appareil qui commence les jetons a `debut` (le plus long d'abord).
    static func appareil(dans jetons: [Texte.Jeton], depuis debut: Int) -> Trouve? {
        chercher(indexAppareils, jetons, debut)
    }

    static func piece(dans jetons: [Texte.Jeton], depuis debut: Int = 0) -> Trouve? {
        chercher(indexPieces, jetons, debut)
    }

    private static func chercher(_ index: [String: (mot: MotMaison, pluriel: Bool)], _ jetons: [Texte.Jeton],
                                 _ debut: Int) -> Trouve? {
        guard debut < jetons.count else { return nil }
        for n in stride(from: min(longueurMax, jetons.count - debut), through: 1, by: -1) {
            let cle = jetons[debut..<(debut + n)].map(\.plie).joined(separator: " ")
            if let t = index[cle] { return Trouve(mot: t.mot, pluriel: t.pluriel, longueur: n) }
        }
        return nil
    }

    // MARK: La table

    /// `genre mot[/pluriel] [!] [@sur|@a]` : voir `MotMaison.init`.
    private static let lignesAppareils: [String] = [
        // Lumieres
        "f lampe", "f ampoule", "f lumière", "f veilleuse", "f applique", "f suspension", "f guirlande",
        "m plafonnier", "m lampadaire", "m spot", "m projecteur", "m lustre", "m luminaire", "m néon", "m bandeau/bandeaux",
        "m ruban", "f torche", "m variateur", "m abat-jour/abat-jour",
        // Prises et commandes
        "f prise", "f multiprise", "f rallonge", "m interrupteur", "m bouton", "m poussoir", "m commutateur",
        "m contacteur", "m relais", "m module", "m boîtier", "f télécommande", "m détecteur", "m capteur",
        "m thermomètre", "m hygromètre", "m compteur", "f sonde", "f balise", "f sirène", "f alarme", "f centrale",
        "m avertisseur", "m déclencheur", "m thermostat",
        // Ouvrants et occultants
        "m volet", "m store", "m rideau/rideaux", "m portail", "m portillon", "f porte", "f fenêtre", "f baie",
        "f trappe", "f serrure", "m verrou", "f gâche", "f sonnette", "m interphone", "m visiophone", "f caméra",
        // Chauffage, air, eau
        "m radiateur", "m convecteur", "m chauffage", "m ventilateur", "m climatiseur", "m humidificateur",
        "m purificateur", "m diffuseur", "m chauffe-eau/chauffe-eau", "m ballon", "m cumulus", "f vanne", "f électrovanne", "f pompe",
        "m robinet", "f hotte !",
        // Son, image
        "f enceinte", "m haut-parleur !", "f barre", "m caisson", "m ampli", "m décodeur", "m écran", "m téléviseur",
        "f télévision", "f télé", "f radio", "m lecteur", "f console", "f tablette", "m ordinateur", "f imprimante",
        // Electromenager
        "m four", "m réfrigérateur", "m frigo", "m congélateur", "m lave-linge/lave-linge", "m lave-vaisselle/lave-vaisselle", "m sèche-linge/sèche-linge",
        "m micro-ondes", "f cafetière", "f bouilloire", "m aspirateur", "m robot", "f machine", "f horloge",
        // Composes (un seul mot : le s du pluriel va au premier mot, ou rien)
        "f porte-fenêtre/portes-fenêtres", "m radio-réveil/radios-réveils", "m robot-aspirateur/robots-aspirateurs",
        "m porte-serviettes/porte-serviettes", "m sèche-serviettes/sèche-serviettes", "m chauffe-serviettes/chauffe-serviettes",
        "m sèche-cheveux/sèche-cheveux", "m sèche-mains/sèche-mains", "m grille-pain/grille-pain", "m va-et-vient/va-et-vient",
        "m porte-manteau/porte-manteaux", "m porte-clés/porte-clés", "m thermo-hygromètre/thermo-hygromètres",
        // Reseau
        "m pont", "m routeur", "m répéteur", "f passerelle", "f borne", "f box", "m hub !",
    ]

    private static let lignesPieces: [String] = [
        "m bureau/bureaux", "f cuisine", "f entrée", "m salon", "m séjour", "f chambre", "f salle", "f pièce", "f suite",
        "m grenier", "m garage", "m cellier", "f buanderie", "f lingerie", "m dressing", "m couloir", "m dégagement",
        "m palier @sur", "fp toilettes", "mp WC", "m sous-sol", "f cave", "f terrasse @sur", "m balcon @sur",
        "m jardin", "m abri", "f véranda", "mp combles", "m étage @a", "m rez-de-chaussée/rez-de-chaussée @a", "m rangement",
        "m atelier", "f cour", "f cours/cours", "m hall !", "f mezzanine", "f loggia", "m patio", "m vestibule", "m sas", "m porche",
        "f allée", "m cabinet", "m placard", "m cagibi", "m débarras", "m appentis", "f serre", "f piscine",
        "m local/locaux", "f nursery", "m studio", "m loft", "m living", "f bibliothèque", "f mansarde", "f grange",
        "f remise", "m cabanon", "m carport", "m garde-manger/garde-manger", "f arrière-cuisine", "m coin", "m espace", "m office",
        "m escalier", "m toit @sur", "f toiture", "m parking",
    ]
}
