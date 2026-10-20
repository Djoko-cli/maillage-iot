import Foundation
import MaillageCoeur

/// Textes des evenements du journal unique, de ses lignes et des notifications : ceux du module du protocole de l'evenement
/// (`TexteEvenementThread`, `TexteEvenementZigbee`), jamais ceux d'un autre. Un evenement sans protocole est de Thread (lignes
/// d'avant l'etape 3) ; une ligne regroupee a le protocole de son premier evenement (les regroupements sont propres a un
/// protocole). Le `switch` n'a pas de defaut : un troisieme protocole ne compile pas sans ses textes.
enum TexteEvenement {
    /// Le protocole de l'evenement ; Thread sans protocole.
    static func protocole(_ e: Evenement) -> Protocole { e.protocole ?? .thread }

    /// Le protocole d'une ligne du journal : celui de son premier evenement ; Thread sans evenement.
    static func protocole(_ l: LigneJournal) -> Protocole { l.evenements.first.map(protocole) ?? .thread }

    /// Heure d'une date, la meme pour tous les protocoles.
    static func heure(_ d: Date) -> String { TexteEvenementThread.heure(d) }

    /// Quand : date et heure, ou la periode de veille si la date est incertaine (le meme pour les deux modules).
    static func quand(_ e: Evenement) -> String {
        switch protocole(e) {
        case .thread: TexteEvenementThread.quand(e)
        case .zigbee: TexteEvenementZigbee.quand(e)
        }
    }

    static func quand(_ l: LigneJournal) -> String {
        switch protocole(l) {
        case .thread: TexteEvenementThread.quand(l)
        case .zigbee: TexteEvenementZigbee.quand(l)
        }
    }

    /// Le titre d'un evenement : son sujet nomme avec sa piece (`pieces`, la meme dans la fenetre du journal, les
    /// notifications et le menu de la barre).
    static func titre(_ e: Evenement, pieces: PiecesJournal) -> String {
        switch protocole(e) {
        case .thread: TexteEvenementThread.titre(e, pieces: pieces)
        case .zigbee: TexteEvenementZigbee.titre(e, pieces: pieces)
        }
    }

    static func titre(_ l: LigneJournal, pieces: PiecesJournal) -> String {
        switch protocole(l) {
        case .thread: TexteEvenementThread.titre(l, pieces: pieces)
        case .zigbee: TexteEvenementZigbee.titre(l, pieces: pieces)
        }
    }

    /// Un changement dans le detail d'une ligne regroupee : « 20:58 → HomePod salon ».
    static func changement(_ e: Evenement) -> String {
        switch protocole(e) {
        case .thread: TexteEvenementThread.changement(e)
        case .zigbee: TexteEvenementZigbee.changement(e)
        }
    }

    /// Les relais d'une ligne de changements regroupes : « A → B → C · finit sur C ».
    static func resume(_ r: ResumeRelais, protocole: Protocole) -> String {
        switch protocole {
        case .thread: TexteEvenementThread.resume(r)
        case .zigbee: TexteEvenementZigbee.resume(r)
        }
    }

    /// Titre et texte d'une notification : ceux du protocole de son premier evenement (une notification groupee ne l'est que
    /// de pertes d'un meme protocole, `Alertes`).
    static func notification(_ a: AlerteAEnvoyer, pieces: PiecesJournal) -> (titre: String, corps: String) {
        switch a.evenements.first.map(protocole) ?? .thread {
        case .thread: TexteEvenementThread.notification(a, pieces: pieces)
        case .zigbee: TexteEvenementZigbee.notification(a, pieces: pieces)
        }
    }
}
