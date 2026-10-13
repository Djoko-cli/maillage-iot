import Foundation

/// Le signal vu par la sonde, dans la fiche (polissage D, section 4.3) : son echelle, toujours visible, meme pour un
/// seul point ou des valeurs toutes egales ; le releve sous le pointeur et son etiquette.
public enum EchelleSignal {
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

    /// Le domaine vertical (dBm) : du minimum moins 5 dB, arrondi a la dizaine inferieure, au maximum plus 5 dB, arrondi
    /// a la dizaine superieure ; au moins 10 dB. Nil sans valeur.
    public static func domaine(_ valeurs: [Double]) -> ClosedRange<Double>? {
        guard let bas = valeurs.min(), let haut = valeurs.max() else { return nil }
        return ((bas - 5) / 10).rounded(.down) * 10 ... ((haut + 5) / 10).rounded(.up) * 10
    }

    /// Les graduations : chaque dizaine du domaine, du bas vers le haut.
    public static func graduations(_ d: ClosedRange<Double>) -> [Double] {
        stride(from: (d.lowerBound / 10).rounded(.up) * 10, through: d.upperBound, by: 10).map { $0 }
    }

    /// Le releve le plus proche de `date` dans le temps (`points` du plus ancien au plus recent), a moins de
    /// `seuil(periode:)` strictement ; nil s'il n'y en a pas (un trou de la courbe). A egale distance, le plus ancien.
    public static func plusProche(_ points: [PointCourbe], de date: Date, periode: PeriodeCourbes) -> PointCourbe? {
        let seuil = Self.seuil(periode: periode)
        return points.filter { abs($0.date.timeIntervalSince(date)) < seuil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// L'etiquette d'un releve : sa valeur arrondie au dBm, avec le vrai signe moins, puis son heure, au format de
    /// `locale`, dans le fuseau `fuseau`, en calendrier gregorien (celui de la machine n'y change rien) :
    /// « −67 dBm · 14:32 » ; en 7 j et 30 j, le jour aussi.
    public static func etiquette(_ p: PointCourbe, periode: PeriodeCourbes, locale: Locale, fuseau: TimeZone) -> String {
        let v = Int(p.valeur.rounded())
        let valeur = (v < 0 ? "\u{2212}" : "") + String(abs(v))
        return valeur + " dBm · " + heure(p.date, periode: periode, locale: locale, fuseau: fuseau)
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
