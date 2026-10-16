import Foundation

/// Les seuils qui rangent une valeur de signal en bande : `bonne` et plus, bonne ; de `moyenne` (compris) a `bonne`,
/// moyenne ; au-dessous, faible. Chaque protocole donne les siens, dans l'unite de son echelle.
public struct SeuilsBandes: Sendable, Equatable {
    public var bonne: Double
    public var moyenne: Double

    public init(bonne: Double, moyenne: Double) {
        self.bonne = bonne
        self.moyenne = moyenne
    }
}

/// Le signal vu par la sonde, dans la fiche (polissage D, section 4.3) : son echelle, toujours visible, meme pour un
/// seul point ou des valeurs toutes egales ; le releve sous le pointeur et son etiquette.
///
/// Une echelle par protocole (dBm pour Thread, LQI pour Zigbee) : l'unite, ou elle se place, le pas des graduations,
/// la marge du domaine autour des valeurs, les bornes dures de la grandeur, le domaine sans valeur et les seuils des
/// bandes de qualite (`bande(_:)`). Le coeur n'en
/// nomme aucune (chaque protocole declare la sienne, `EchelleSignal.dbm` dans ProtocoleThread). Ce qui ne depend pas de
/// l'unite (`portee`, `seuil`, `plusProche`, `heure`, `aGauche`) reste statique.
public struct EchelleSignal: Sendable {
    /// L'unite de l'etiquette : « dBm », « LQI ».
    public var unite: String
    /// Vrai : l'unite precede la valeur (« LQI 182 ») ; faux : elle la suit (« −67 dBm »).
    public var uniteAvant: Bool
    /// Le pas des graduations, et celui de l'arrondi des bornes du domaine : 10 (dBm), 50 (LQI).
    public var pas: Double
    /// Ce que le domaine ajoute de part et d'autre des valeurs, avant l'arrondi au pas : 5 (dBm), 10 (LQI).
    public var marge: Double
    /// Les bornes dures de la grandeur (le domaine y est coupe) ; nil : aucune (dBm), 0 a 255 (LQI).
    public var bornes: ClosedRange<Double>?
    /// Le domaine quand le noeud n'a aucune valeur : -100 a -40 (dBm), 0 a 255 (LQI).
    public var domaineParDefaut: ClosedRange<Double>
    /// Les seuils qui rangent une valeur en bande de qualite : -80 et -90 dBm, 170 et 100 LQI.
    public var bandes: SeuilsBandes

    public init(unite: String, uniteAvant: Bool, pas: Double, marge: Double, bornes: ClosedRange<Double>?,
                domaineParDefaut: ClosedRange<Double>, bandes: SeuilsBandes) {
        self.unite = unite
        self.uniteAvant = uniteAvant
        self.pas = pas
        self.marge = marge
        self.bornes = bornes
        self.domaineParDefaut = domaineParDefaut
        self.bandes = bandes
    }

    /// La bande de qualite d'une valeur de cette echelle : bonne des `bandes.bonne`, moyenne des `bandes.moyenne`,
    /// faible au-dessous (un lien reel mais tres faible compris) ; inconnue sans valeur (NaN).
    public func bande(_ valeur: Double) -> BandeQualite {
        if valeur.isNaN { return .inconnue }
        if valeur >= bandes.bonne { return .bonne }
        return valeur >= bandes.moyenne ? .moyenne : .faible
    }

    /// Un releve ne compte au survol qu'a moins de 2 % de la duree de la periode du pointeur (et d'un trou : `seuil`).
    public static let portee = 0.02

    /// La distance sous laquelle un releve compte au survol : la plus petite de 2 % de la duree de la periode et de
    /// l'ecart qui coupe sa courbe en troncons (20 min sur 24 h, 90 min sur 7 j, 6 h sur 30 j) ; aux trois periodes,
    /// c'est l'ecart. Au milieu d'un trou d'au moins deux ecarts, aucun releve n'est assez proche ; pres des bords d'un
    /// trou, ou dans un trou plus court, le plus proche compte encore.
    public static func seuil(periode: PeriodeCourbes) -> TimeInterval {
        seuil(duree: periode.duree, ecart: periode.ecartTroncon)
    }

    static func seuil(duree: TimeInterval, ecart: TimeInterval) -> TimeInterval { min(portee * duree, ecart) }

    /// Le domaine vertical : du minimum moins `marge`, arrondi au multiple de `pas` inferieur, au maximum plus `marge`,
    /// arrondi au multiple de `pas` superieur, coupe aux `bornes` s'il y en a ; au moins un `pas` de haut (contre une
    /// borne, le haut ou le bas se decale). Nil sans valeur. En dBm (marge 5, pas 10) : du minimum moins 5 dB, arrondi
    /// a la dizaine inferieure, au maximum plus 5 dB, arrondi a la dizaine superieure ; en LQI (marge 10, pas 50) :
    /// dans 0 a 255.
    public func domaine(_ valeurs: [Double]) -> ClosedRange<Double>? {
        guard let bas = valeurs.min(), let haut = valeurs.max() else { return nil }
        var b = ((bas - marge) / pas).rounded(.down) * pas
        var h = ((haut + marge) / pas).rounded(.up) * pas
        if let bornes {
            b = max(bornes.lowerBound, b)
            h = min(bornes.upperBound, h)
        }
        if h - b < pas {
            if let bornes, b + pas > bornes.upperBound { b = h - pas } else { h = b + pas }
        }
        return b ... h
    }

    /// Les graduations : chaque multiple de `pas` du domaine, du bas vers le haut.
    public func graduations(_ d: ClosedRange<Double>) -> [Double] {
        stride(from: (d.lowerBound / pas).rounded(.up) * pas, through: d.upperBound, by: pas).map { $0 }
    }

    /// Le releve le plus proche de `date` dans le temps (`points` du plus ancien au plus recent), a moins de
    /// `seuil(periode:)` strictement ; nil s'il n'y en a pas (un trou de la courbe). A egale distance, le plus ancien.
    public static func plusProche(_ points: [PointCourbe], de date: Date, periode: PeriodeCourbes) -> PointCourbe? {
        let seuil = Self.seuil(periode: periode)
        return points.filter { abs($0.date.timeIntervalSince(date)) < seuil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// L'etiquette d'un releve : sa valeur arrondie, avec le vrai signe moins (U+2212) si elle est negative, et son
    /// unite avant ou apres (`uniteAvant`), puis son heure, au format de `locale`, dans le fuseau `fuseau`, en
    /// calendrier gregorien (celui de la machine n'y change rien) : « −67 dBm · 14:32 », « LQI 182 · 14:32 » ; en 7 j
    /// et 30 j, le jour aussi.
    public func etiquette(_ p: PointCourbe, periode: PeriodeCourbes, locale: Locale, fuseau: TimeZone) -> String {
        let v = Int(p.valeur.rounded())
        let nombre = (v < 0 ? "\u{2212}" : "") + String(abs(v))
        let valeur = uniteAvant ? unite + " " + nombre : nombre + " " + unite
        return valeur + " · " + Self.heure(p.date, periode: periode, locale: locale, fuseau: fuseau)
    }

    /// L'heure d'un releve, au format de `locale`, dans le fuseau `fuseau`, en calendrier gregorien : « 14:32 » ; en 7 j
    /// et 30 j, le jour aussi (« 8 oct., 14:32 »).
    public static func heure(_ d: Date, periode: PeriodeCourbes, locale: Locale, fuseau: TimeZone) -> String {
        let gregorien = Calendar(identifier: .gregorian)
        var style = Date.FormatStyle(locale: locale, calendar: gregorien, timeZone: fuseau).hour().minute()
        if periode != .jour { style = style.day().month(.abbreviated) }
        return d.formatted(style)
    }

    /// L'etiquette se pose a gauche du trait dans la moitie droite du graphe (`debut` a `fin`), a droite sinon : elle
    /// reste dans le cadre.
    public static func aGauche(_ date: Date, debut: Date, fin: Date) -> Bool {
        let duree = fin.timeIntervalSince(debut)
        return duree > 0 && date.timeIntervalSince(debut) / duree > 0.5
    }
}
