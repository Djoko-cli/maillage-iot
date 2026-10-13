import Foundation

/// Panne du 27/09/2026 (heures du Mac, Asia/Tbilisi), reconstituee a partir du releve
/// du 28/09 et du journal de halo-routes, pour les tests et le mode demo :
/// - 03:55 : reseau sain, une partition, prefixe OMR fd4f:9c:ed42::/64 ;
/// - 04:04:03 : l'Apple TV (chef) change d'adresse de lien (redemarrage) et
///   publie fd19:961f:2db3::/64 ; a 04:06 les appareils y passent, fd4f part ;
/// - 04:14 : l'Aqara HubM100 se retrouve seul dans la partition E2E79FFC ;
///   1E5019DAC2638F92 perd son adresse ;
/// - 04:15, 04:16, 04:18, 04:20 : quatre appareils disparaissent.
/// Illustratif : les appareils perdus, leurs heures et l'ancienne adresse de
/// lien de l'Apple TV sont choisis, pas releves.
public enum ScenarioPanne {
    public static let fuseau = TimeZone(secondsFromGMT: 4 * 3600)!

    /// 27/09/2026 a h:m:s, heure du Mac.
    public static func date(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = DateComponents(year: 2026, month: 9, day: 27, hour: h, minute: m, second: s)
        c.timeZone = fuseau
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    public static let debut = date(3, 55)
    public static let fin = date(4, 30)

    /// Releves toutes les 60 s, de 03:55 a 04:30.
    public static var releves: [Annonces] {
        (0...35).map { annonces(a: debut.addingTimeInterval(TimeInterval($0) * 60)) }
    }

    public static let sansAdresse = "1E5019DAC2638F92"
    /// Appareils qui disparaissent, et quand.
    public static let perdus: [(hote: String, absentDes: Date)] = [
        ("46F77B36E071F8D0", date(4, 15)), ("7AF0B6D5006CF95F", date(4, 16)),
        ("D661EE20B3E97C66", date(4, 18)), ("FA15027BC681BB16", date(4, 20)),
    ]

    static let lienAncienATV = "fe80::5a:d5f3:dc72:c700"
    static let lienATV = "fe80::5a:d5f3:dc72:e7d6"
    static let lienHomePodMiniBureau = "fe80::e14:1eca:d086:9a92"
    static let lienHomePodGauche = "fe80::ae:f065:37ea:3d33"
    static let lienAqara = "fe80::56ef:44ff:fe97:b882"
    static let fd4f = "fd4f:9c:ed42:0:"
    static let fd19 = "fd19:961f:2db3:0:"

    public static func annonces(a t: Date) -> Annonces {
        var a = Releve20260928.annonces
        a.date = t
        a.note = "Scénario reconstitué de la panne du 27/09/2026."
        let redemarrage = date(4, 4, 3)
        let bascule = date(4, 6)
        let scission = date(4, 14)
        let prefixe = t < bascule ? fd4f : fd19

        // Routeurs : adresse de lien de l'Apple TV, partition et etat de l'Aqara.
        let ancienLien = t < redemarrage ? lienAncienATV : lienATV
        a.adresses["Apple-TV-4K.local"] = a.adresses["Apple-TV-4K.local"]?.map { $0 == lienATV ? ancienLien : $0 }
        a.adresses["HomePod-mini-bureau.local"] = a.adresses["HomePod-mini-bureau.local"]?
            .map { $0.hasPrefix("fe80::") ? lienHomePodMiniBureau : $0 }
        if t < scission, let i = a.routeurs.firstIndex(where: { $0.instance == "Aqara HubM100 #DFEB" }) {
            var v = a.routeurs[i].txt.valeurs
            v["pt"] = Data([0x73, 0x58, 0x6B, 0x68])
            v["sb"] = Data([0x00, 0x00, 0x00, 0xB1])   // BBR actif, pas primaire
            a.routeurs[i].txt = ChampsTXT(v)
        }

        // Routes du Mac.
        var routes: [RouteIPv6] = []
        if t < bascule { routes.append(RouteIPv6(prefixe: "fd4f:9c:ed42::/64", passerelle: lienHomePodMiniBureau, interface: "en0")) }
        if t >= redemarrage { routes.append(RouteIPv6(prefixe: "fd19:961f:2db3::/64", passerelle: lienATV, interface: "en0")) }
        routes.append(RouteIPv6(prefixe: "fd03:54f0:5de:1::/64", passerelle: t < scission ? lienHomePodGauche : lienAqara,
                                interface: "en0"))
        a.routes = routes

        // Appareils : prefixe courant, 724C avec son adresse de 00:42, 1E50, perdus.
        a.adresses["724CC16B32D8F820.local"] = [fd19 + "a2b6:12e8:48c5:dee3"]
        a.adresses[sansAdresse + ".local"] = t < scission ? [fd19 + "1e50:19da:c263:8f92"] : []
        for (hote, liste) in a.adresses where !liste.isEmpty {
            a.adresses[hote] = liste.map { $0.hasPrefix(fd19) ? prefixe + $0.dropFirst(fd19.count) : $0 }
        }
        for (hote, absentDes) in perdus where t >= absentDes {
            a.matter.removeAll { $0.hote == hote + ".local" }
            a.adresses[hote + ".local"] = nil
        }
        return a
    }
}
