import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

// Ce que le journal dit des protocoles (etape 3b, tache 7 ; spec 3.5 et 6.7) : ses interrupteurs « Thread » / « Zigbee », a lui
// (`journal.thread`, `journal.zigbee`, sans lien avec ceux de la vue, `vue.*`), la marque de protocole de chaque ligne, et les
// familles qui n'ont plus rien a montrer quand leur protocole est filtre.

/// Les interrupteurs du journal : les preferences communes `journal.thread` et `journal.zigbee` (vraies par defaut). Un protocole
/// eteint dans les Reglages garde son interrupteur : ses lignes restent au journal, on peut encore les lire.
enum InterrupteursJournal {
    /// La cle de la preference d'un protocole ; sans defaut : un troisieme protocole ne compile pas sans la sienne.
    static func cle(_ p: Protocole) -> String {
        switch p {
        case .thread: "journal.thread"
        case .zigbee: "journal.zigbee"
        }
    }

    /// Les protocoles que le journal montre : ceux dont la preference n'est pas fausse (vraie sans preference, ou pour une valeur
    /// qui n'est pas un booleen).
    static func preferes(dans d: UserDefaults = .standard) -> Set<Protocole> {
        Set(Protocole.allCases.filter { d.object(forKey: cle($0)) as? Bool ?? true })
    }
}

/// Les preferences du journal lues et ecrites par la fenetre (`@AppStorage` sur les cles de `InterrupteursJournal`).
struct PreferencesJournal: DynamicProperty {
    @AppStorage(InterrupteursJournal.cle(.thread)) private var thread = true
    @AppStorage(InterrupteursJournal.cle(.zigbee)) private var zigbee = true

    /// Les protocoles que le journal montre.
    var preferes: Set<Protocole> {
        Set(Protocole.allCases.filter { p in
            switch p {
            case .thread: thread
            case .zigbee: zigbee
            }
        })
    }

    /// Une liaison vers l'interrupteur de `p`.
    func liaison(_ p: Protocole) -> Binding<Bool> {
        switch p {
        case .thread: $thread
        case .zigbee: $zigbee
        }
    }
}

/// La marque de protocole d'une ligne du journal : le signe de la ligne des protocoles de la barre (le rond bleu de Thread, l'hexagone
/// violet de Zigbee, `LegendePieces.signeProtocole`), en petit. Une ligne sans protocole est de Thread.
enum MarqueProtocole {
    /// Le protocole d'une ligne : celui de son premier evenement, Thread sans protocole.
    static func protocole(de ligne: LigneJournal) -> Protocole { TexteEvenement.protocole(ligne) }

    /// Le glyphe d'un protocole : ● pour Thread, ⬢ pour Zigbee (le texte que lit une aide vocale ou une copie).
    static func glyphe(_ p: Protocole) -> String {
        switch p {
        case .thread: "●"
        case .zigbee: "⬢"
        }
    }

    static func glyphe(de ligne: LigneJournal) -> String { glyphe(protocole(de: ligne)) }

    /// Le signe dessine, le meme que celui des interrupteurs de la barre.
    @MainActor
    static func signe(_ p: Protocole) -> LegendePieces.Signe { LegendePieces.signeProtocole(p) }

    @MainActor
    static func nom(_ p: Protocole) -> String { LegendePieces.nomProtocole(p) }
}

/// La marque d'une ligne, a la taille de celle des interrupteurs de la barre.
struct MarqueProtocoleVue: View {
    let protocole: Protocole

    var body: some View {
        SigneLegende(signe: MarqueProtocole.signe(protocole))
            .scaleEffect(0.8)
            .frame(width: 11, height: 11)
            .accessibilityElement()
            .accessibilityLabel(MarqueProtocole.nom(protocole))
    }
}

/// L'interrupteur du journal d'un protocole, dans la barre d'outils : son signe et son nom.
struct InterrupteurJournal: View {
    let protocole: Protocole
    let allume: Binding<Bool>

    var body: some View {
        Toggle(isOn: allume) {
            HStack(spacing: 4) {
                MarqueProtocoleVue(protocole: protocole)
                Text(verbatim: MarqueProtocole.nom(protocole))
            }
        }
        .toggleStyle(.button)
        .help(allume.wrappedValue ? String(localized: "Masquer \(MarqueProtocole.nom(protocole)) dans le journal")
              : String(localized: "Montrer \(MarqueProtocole.nom(protocole)) dans le journal"))
    }
}

extension FamilleEvenement {
    /// Les protocoles dont la famille montre des evenements : ceux qui declarent un de ses types (hors les deux types neutres, du
    /// demarrage et de la veille, que tous ecrivent). « Tous » et « Surveillance » sont communes.
    var protocoles: Set<Protocole> {
        let propres = Set(Protocole.allCases.filter { p in
            let types = p == .thread ? TypeEvenement.thread : TypeEvenement.zigbee
            return types.contains { contient($0) }
        })
        return switch self {
        case .toutes, .surveillance: Set(Protocole.allCases)
        default: propres
        }
    }

    /// Une famille est grisee quand aucun des protocoles montres n'a d'evenement a y mettre.
    func grisee(montres: Set<Protocole>) -> Bool { protocoles.isDisjoint(with: montres) }
}
