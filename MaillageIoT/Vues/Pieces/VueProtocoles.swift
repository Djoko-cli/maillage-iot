import MaillageCoeur
import ProtocoleThread
import SwiftUI

// Ce que la barre du haut dit des protocoles (etape 3b, tache 5 ; spec 3.1, 3.3 et 6.7) : le nom de la maison et son menu des
// reseaux par protocole, les interrupteurs de vue « ● Thread ⬢ Zigbee », et le message d'une vue dont tout est masque. Le
// masquage lui-meme n'agit qu'au dessin (`EntreeScene.montres`, `EtatAnime.masques`) : rien ici n'entre dans la scene calculee.

/// Les interrupteurs de vue : les preferences communes `vue.thread` et `vue.zigbee` (vraies par defaut, sans prefixe de module),
/// et ce que l'on en montre. Un protocole eteint dans les Reglages (`actif` faux) a son interrupteur grise et compte comme
/// masque, quelle que soit la preference.
enum InterrupteursVue {
    /// La cle de la preference d'un protocole ; sans defaut : un troisieme protocole ne compile pas sans la sienne.
    static func cle(_ p: Protocole) -> String {
        switch p {
        case .thread: "vue.thread"
        case .zigbee: "vue.zigbee"
        }
    }

    /// Les protocoles que Djoko veut voir : ceux dont la preference n'est pas fausse (vraie sans preference, ou pour une valeur
    /// qui n'est pas un booleen).
    static func preferes(dans d: UserDefaults = .standard) -> Set<Protocole> {
        Set(Protocole.allCases.filter { d.object(forKey: cle($0)) as? Bool ?? true })
    }

    /// Les protocoles montres : voulus et actifs.
    static func montres(preferes: Set<Protocole>, actifs: Set<Protocole>) -> Set<Protocole> {
        preferes.intersection(actifs)
    }

    /// L'etat d'un interrupteur : allume si le protocole est montre ; grise si le protocole est eteint (rien a montrer ni a
    /// masquer). Un protocole masque par Djoko est eteint mais pas grise : il se remet d'un clic.
    struct Etat: Equatable {
        var allume: Bool
        var grise: Bool
    }

    static func etat(_ p: Protocole, preferes: Set<Protocole>, actifs: Set<Protocole>) -> Etat {
        Etat(allume: montres(preferes: preferes, actifs: actifs).contains(p), grise: !actifs.contains(p))
    }

    /// L'aide d'un interrupteur : ce que le clic fait, ou pourquoi il est grise.
    @MainActor
    static func aide(_ p: Protocole, _ e: Etat) -> String {
        let nom = LegendePieces.nomProtocole(p)
        if e.grise { return String(localized: "\(nom) est éteint dans les Réglages") }
        return e.allume ? String(localized: "Masquer \(nom)") : String(localized: "Montrer \(nom)")
    }
}

/// Les preferences de vue lues et ecrites par une vue (`@AppStorage` sur les cles de `InterrupteursVue`) : la fenetre, qui en
/// tire les protocoles montres de la scene, et la barre, dont les interrupteurs les ecrivent.
struct PreferencesVue: DynamicProperty {
    @AppStorage(InterrupteursVue.cle(.thread)) private var thread = true
    @AppStorage(InterrupteursVue.cle(.zigbee)) private var zigbee = true

    /// Les protocoles que Djoko veut voir.
    var preferes: Set<Protocole> {
        Set(Protocole.allCases.filter { p in
            switch p {
            case .thread: thread
            case .zigbee: zigbee
            }
        })
    }

    /// Un clic sur l'interrupteur de `p`.
    func basculer(_ p: Protocole) {
        switch p {
        case .thread: thread.toggle()
        case .zigbee: zigbee.toggle()
        }
    }
}

/// L'interrupteur de vue d'un protocole dans la capsule de gauche : le signe du protocole tel que la scene le dessine (le rond
/// bleu de Thread, l'hexagone violet de Zigbee, en petit) et son nom ; allume quand le protocole est montre, grise quand il est
/// eteint dans les Reglages.
struct InterrupteurProtocole: View {
    let protocole: Protocole
    let etat: InterrupteursVue.Etat
    let basculer: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { etat.allume }, set: { _ in basculer() })) {
            HStack(spacing: 4) {
                SigneLegende(signe: LegendePieces.signeProtocole(protocole))
                    .scaleEffect(0.8)
                    .frame(width: 11, height: 11)
                    .accessibilityHidden(true)
                Text(verbatim: LegendePieces.nomProtocole(protocole))
            }
        }
        .toggleStyle(StyleBasculeCapsule())
        .disabled(etat.grise)
        .help(InterrupteursVue.aide(protocole, etat))
    }
}

/// Le contenu du menu du nom de la maison : les reseaux par protocole, Thread puis Zigbee. Une valeur, pour la tenir sans vue.
struct MenuReseaux: Equatable {
    /// Un reseau Thread vu : son identifiant, son titre (son nom, et ses partitions s'il est scinde) ; `choisi` : c'est celui
    /// que la vue montre (`SurveillanceThread.reseauChoisi`).
    struct ReseauThread: Equatable, Identifiable {
        var id: String
        var titre: String
        var choisi: Bool
    }

    /// Le pont Hue : son nom et son modele, et son etat.
    struct PontZigbee: Equatable {
        var titre: String
        var etat: String
    }

    /// Les reseaux de Thread, nil quand Thread est eteint (vide : aucun reseau vu).
    var thread: [ReseauThread]?
    /// Le pont de Zigbee, nil quand Zigbee est eteint.
    var zigbee: PontZigbee?

    @MainActor
    static func contenu(_ s: Surveillance, pont: NomsPont?) -> MenuReseaux {
        var m = MenuReseaux()
        if s.thread.actif {
            let choisi = s.thread.reseau?.id
            m.thread = (s.thread.instantane?.reseaux ?? []).map { r in
                ReseauThread(id: r.id, titre: r.estScinde ? String(localized: "\(r.nom) · \(r.partitions.count) partitions") : r.nom,
                             choisi: r.id == choisi)
            }
        }
        if s.zigbee.actif {
            let nom = String(localized: "Pont Hue")
            let modele = pont?.pont?.modele.flatMap { $0.isEmpty ? nil : $0 }
            m.zigbee = PontZigbee(titre: modele.map { String(localized: "\(nom) · \($0)") } ?? nom,
                                  etat: texteEtatPont(pont?.etat ?? .introuvable, demo: s.mode == .demo))
        }
        return m
    }

    /// L'etat du pont, en un mot ; en demo, la demo (le pont n'existe pas).
    static func texteEtatPont(_ e: NomsPont.Etat, demo: Bool) -> String {
        if demo { return String(localized: "Démo") }
        return switch e {
        case .introuvable: String(localized: "Introuvable")
        case .trouve, .aLier: String(localized: "Non lié")
        case .liaisonEnCours: String(localized: "Liaison en cours…")
        case .lie: String(localized: "Lié")
        case .erreur: String(localized: "Erreur (voir les Réglages)")
        }
    }

    /// Le nom de la maison, en tete de la capsule de gauche : le domicile du releve de Maison (celui de Thread, sinon celui que
    /// Zigbee a recu) ; « Maison » quand il est inconnu ou vide.
    @MainActor
    static func nomDeLaMaison(_ s: Surveillance) -> String {
        let nom = [s.thread.noms.maison?.domicile, s.zigbee.releveMaison?.domicile]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return nom ?? String(localized: "Maison")
    }
}

/// Ce que la vue dit quand tout ce qui est a montrer est masque : une ligne, sans bouton (les interrupteurs sont en haut).
enum MessageMasque {
    /// « Thread et Zigbee sont masqués », « Thread est masqué », « Zigbee est masqué » ; nil sans protocole.
    static func texte(protocoles: Set<Protocole>) -> String? {
        switch Protocole.allCases.filter(protocoles.contains) {
        case []: nil
        case [.thread]: String(localized: "Thread est masqué")
        case [.zigbee]: String(localized: "Zigbee est masqué")
        default: String(localized: "Thread et Zigbee sont masqués")
        }
    }
}

/// La ligne de la vue dont tout est masque, au centre de la fenetre.
struct VueToutMasque: View {
    let texte: String

    var body: some View {
        Text(verbatim: texte)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isStaticText)
    }
}
