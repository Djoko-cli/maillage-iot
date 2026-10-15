import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

/// Familles d'evenements, pour le filtre du journal : celles des deux protocoles (leurs interrupteurs sont dans
/// `ProtocolesJournal.swift`, avec les familles qui se grisent). « Reseau » est celle de Thread, « Surveillance » celle de
/// Zigbee ; les types communs vont dans la meme famille.
enum FamilleEvenement: String, CaseIterable, Identifiable {
    case toutes, reseau, surveillance, routeurs, prefixes, appareils, maillage

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .toutes: String(localized: "Tous")
        case .reseau: String(localized: "Réseau")
        case .surveillance: String(localized: "Surveillance")
        case .routeurs: String(localized: "Routeurs")
        case .prefixes: String(localized: "Préfixes")
        case .appareils: String(localized: "Appareils")
        case .maillage: String(localized: "Maillage")
        }
    }

    func contient(_ t: TypeEvenement) -> Bool {
        switch self {
        case .toutes:
            true
        case .reseau:
            [.surveillanceDemarree, .veille, .reseauScinde, .reseauReuni, .chefChange, .bbrPrimaireChange,
             .jeuActifChange].contains(t)
        case .surveillance:
            [.surveillanceDemarree, .veille].contains(t)
        case .routeurs:
            [.routeurApparu, .routeurDisparu, .routeurRoleChange, .routeurNouvelleAdresseLien].contains(t)
        case .prefixes:
            [.prefixeNouveau, .prefixeRetire].contains(t)
        case .appareils:
            [.appareilNouveau, .appareilDisparu, .appareilRevenu, .appareilSansAdresse, .appareilChangePartition].contains(t)
        case .maillage:
            [.parentChange, .sansParent, .cheminChange, .routeurThreadApparu, .routeurThreadDisparu].contains(t)
        }
    }
}

/// Filtre du journal : protocoles montres, famille, gravite minimale, recherche dans le titre, le sujet et les noms
/// « avant » et « apres » (les parents d'un changement de parent regroupe ne sont pas dans son titre). Une ligne est du protocole
/// de son premier evenement, Thread sans protocole ; les lignes regroupees sont par protocole, elles suivent le leur.
struct FiltreJournal: Equatable {
    var famille: FamilleEvenement = .toutes
    var graviteMinimale: Gravite = .info
    var recherche = ""
    var protocoles = Set(Protocole.allCases)

    func appliquer(_ lignes: [LigneJournal]) -> [LigneJournal] {
        let r = recherche.trimmingCharacters(in: .whitespaces)
        return lignes.filter { l in
            let ev = l.evenements
            guard protocoles.contains(MarqueProtocole.protocole(de: l)) else { return false }
            guard ev.contains(where: { famille.contient($0.type) }), l.gravite >= graviteMinimale else { return false }
            guard !r.isEmpty else { return true }
            return TexteEvenement.titre(l).localizedCaseInsensitiveContains(r)
                || ev.contains { ($0.sujet?.id ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.sujet?.nom ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.avant ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.apres ?? "").localizedCaseInsensitiveContains(r) }
        }
    }
}

/// Fenetre du journal : evenements dates, filtres par famille et gravite, recherche.
struct FenetreJournal: View {
    @Environment(Surveillance.self) private var surveillance
    @State private var filtre = FiltreJournal()
    private let preferences = PreferencesJournal()

    /// Le filtre de la fenetre et les protocoles que le journal montre (ses interrupteurs a lui, pas ceux de la vue).
    private var filtreApplique: FiltreJournal {
        var f = filtre
        f.protocoles = preferences.preferes
        return f
    }

    var body: some View {
        let montres = preferences.preferes
        let lignes = filtreApplique.appliquer(surveillance.lignesJournal)
        List(lignes) { ligne in
            LigneJournalVue(ligne: ligne)
        }
        .overlay {
            if lignes.isEmpty {
                ContentUnavailableView("Aucun événement", systemImage: "list.bullet.rectangle")
            }
        }
        .searchable(text: $filtre.recherche)
        .toolbar {
            ForEach(Protocole.allCases, id: \.self) { p in
                InterrupteurJournal(protocole: p, allume: preferences.liaison(p))
            }
            Picker("Famille", selection: $filtre.famille) {
                ForEach(FamilleEvenement.allCases) { f in
                    Text(f.titre).tag(f).disabled(f.grisee(montres: montres))
                }
            }
            Picker("Gravité", selection: $filtre.graviteMinimale) {
                Text("Tout").tag(Gravite.info)
                Text("Attention et alertes").tag(Gravite.attention)
                Text("Alertes").tag(Gravite.alerte)
            }
        }
        .navigationTitle("Journal")
        .frame(minWidth: 560, minHeight: 360)
        .fenetreDeLApp()
    }
}

/// Une ligne : pastille de gravite, marque de protocole, titre, quand ; le detail des pertes regroupees ; pour les changements de parent
/// regroupes, les relais et, a deplier, leurs changements (comme dans la fiche).
struct LigneJournalVue: View {
    let ligne: LigneJournal

    var body: some View {
        switch ligne {
        case .evenement(let e):
            contenu(TexteEvenement.titre(e), quand: TexteEvenement.quand(e), gravite: e.gravite)
        case .parents(let groupe), .chemins(let groupe):
            // Les relais, et a deplier leurs changements, comme dans la fiche (repris de Maillage Zigbee, 09/10).
            LigneChangements(groupe: groupe, police: .callout) {
                contenu(TexteEvenement.titre(ligne), quand: TexteEvenement.quand(ligne), gravite: ligne.gravite)
            }
        case .pertes(let groupe):
            DisclosureGroup {
                ForEach(groupe) { e in
                    Text("\(TexteEvenement.heure(e.date)) · \(TexteEvenement.titre(e))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } label: {
                contenu(TexteEvenement.titre(ligne), quand: TexteEvenement.quand(ligne),
                        gravite: ligne.gravite)
            }
        }
    }

    private func contenu(_ titre: String, quand: String, gravite: Gravite) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Self.couleur(gravite)).frame(width: 8, height: 8)
            MarqueProtocoleVue(protocole: MarqueProtocole.protocole(de: ligne))
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                Text(quand).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func couleur(_ g: Gravite) -> Color {
        switch g {
        case .info: .secondary
        case .attention: .orange
        case .alerte: .red
        }
    }
}
