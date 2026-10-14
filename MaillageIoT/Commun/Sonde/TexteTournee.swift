import Foundation

/// Ce que les textes de tournee des deux sondes ont en commun (`TexteTourneeThread`, `TexteTourneeZigbee` : les etapes
/// et l'avancement sont propres a chaque protocole) : la duree ecoulee.
enum TexteTournee {
    /// Duree ecoulee : « 0:42 », « 1:02:03 » au-dela d'une heure.
    static func chrono(_ secondes: TimeInterval) -> String {
        let s = max(0, Int(secondes))
        if s >= 3600 { return String(format: "%ld:%02ld:%02ld", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%ld:%02ld", s / 60, s % 60)
    }

    /// Duree ecoulee en unites : « 42 s », « 1 min 30 s ».
    static func duree(_ secondes: TimeInterval) -> String {
        Duration.seconds(max(0, Int(secondes)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}
