import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee

/// La demo lancee par les arguments de l'app : `-demo` (la demo combinee : la panne de Thread et le faux reseau Hue de
/// Zigbee, ensemble), `-demo-thread` (celle de Thread, seule) et `-demo-zigbee` (celle de Zigbee, seule). Chaque demo seule
/// garde ses dates, ses noms et son rejeu exact (`docs/rejeu/thread-demo.json`, `zigbee-demo.json`) ; la combinee a le sien
/// (`docs/rejeu/maillage-iot-demo.json`).
enum DemoLancee: Equatable, Sendable {
    case thread, zigbee, combinee

    /// La demo que les arguments de lancement demandent ; nil hors demo. Les deux demos seules ensemble sont la combinee ;
    /// `-demo` avec l'une des deux donne celle-la, la plus precise.
    static func depuis(arguments: [String]) -> DemoLancee? {
        let thread = arguments.contains("-demo-thread"), zigbee = arguments.contains("-demo-zigbee")
        if thread && zigbee { return .combinee }
        if zigbee { return .zigbee }
        if thread { return .thread }
        return arguments.contains("-demo") ? .combinee : nil
    }

    /// Les protocoles dont cette demo rejoue le reseau.
    var protocoles: Set<Protocole> {
        switch self {
        case .thread: [.thread]
        case .zigbee: [.zigbee]
        case .combinee: [.thread, .zigbee]
        }
    }

    func rejoue(_ protocole: Protocole) -> Bool { protocoles.contains(protocole) }

    /// Le suffixe des noms de Zigbee que Thread porte aussi, dans la demo combinee : « Lampe arcade (Hue) ».
    nonisolated static let suffixeHomonymes = "(Hue)"

    /// La demo de Zigbee que celle-ci rejoue. Seule, la sienne, a ses dates et a ses noms. Combinee, la meme, recalee sur
    /// l'horloge de la demo de Thread (sa fin est celle de la panne rejouee : aucun noeud de Thread n'est vieux a cote de ceux
    /// de Zigbee) et ses appareils qui ont le nom d'un appareil de Thread renommes.
    var zigbeeRejouee: DemoZigbee {
        guard self == .combinee else { return .seule }
        let nomsThread = NomsDemo.maison.accessoires.map(\.nom)
        return DemoZigbee(fin: ScenarioPanne.fin).renommant(homonymesDe: nomsThread, suffixe: Self.suffixeHomonymes)
    }
}
