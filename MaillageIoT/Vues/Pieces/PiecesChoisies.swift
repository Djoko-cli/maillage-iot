import Foundation
import MaillageCoeur
import SwiftUI

/// Pieces choisies pour les noeuds que Maison ne place pas (« Placer dans une piece… », dans leur
/// fiche) : un routeur de bordure sous l'instance de son annonce (precision 24 du plan 4b), un autre
/// noeud sous son ExtMac (precision 27, spec de la vue par pieces, section 2.3) ; par maison, dans
/// `pieces-routeurs.json`, a cote des places des pieces ; en memoire seulement en demo et sous les
/// tests. Le calcul est dans le coeur (`PiecesRouteurs`).
@MainActor
@Observable
final class PiecesChoisies {
    /// Ce sous quoi le choix d'un noeud est garde.
    enum Cle: Hashable {
        /// Routeur de bordure : l'instance de son annonce.
        case routeur(String)
        /// Autre noeud : son ExtMac, en 16 hexa majuscules.
        case appareil(String)
    }

    /// « Placer dans une piece… » d'un noeud : la cle de son choix, et les pieces de la maison, par nom.
    struct Placement: Equatable {
        var cle: Cle
        var pieces: [String]
    }

    private(set) var choix: PiecesRouteurs
    @ObservationIgnored private let fichier: URL?

    /// `fichier` : `pieces-routeurs.json` (`fichier(demo:sousTests:)`) ; nil : ni lu ni ecrit.
    init(fichier: URL?) {
        self.fichier = fichier
        choix = fichier.map(PiecesRouteurs.lire) ?? PiecesRouteurs()
    }

    /// A cote des places des pieces ; ni en demo ni sous les tests.
    static func fichier(demo: Bool, sousTests: Bool) -> URL? {
        demo || sousTests ? nil : Surveillance.dossierParDefaut.appendingPathComponent("pieces-routeurs.json")
    }

    /// Piece choisie pour un noeud (sa cle) ; nil : « D'apres son nom » pour un routeur de bordure,
    /// « Sans piece » pour un autre noeud.
    func pieceChoisie(_ cle: Cle, domicile: String) -> String? {
        switch cle {
        case .routeur(let instance): choix.choix(routeur: instance, domicile: domicile)
        case .appareil(let extMac): choix.choix(appareil: extMac, domicile: domicile)
        }
    }

    /// Place un noeud (sa cle) dans une piece de la maison ; nil : d'apres son nom pour un routeur de
    /// bordure, « Sans piece » pour un autre noeud (son choix s'efface).
    func choisir(_ piece: String?, _ cle: Cle, domicile: String) {
        switch cle {
        case .routeur(let instance): choix.choisir(piece, routeur: instance, domicile: domicile)
        case .appareil(let extMac): choix.choisir(piece, appareil: extMac, domicile: domicile)
        }
        guard let fichier else { return }
        do {
            try choix.ecrire(dans: fichier)
        } catch {
            MoteurPieces.journal.error("pieces choisies non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension PiecesChoisies {
    /// « Placer dans une piece… » pour un noeud du reseau affiche, dans une maison qui a des pieces : un
    /// routeur de bordure de l'instantane que Maison ne place pas (precision 24) ; un autre noeud sans
    /// piece de Maison dont l'ExtMac est connue (precision 27). Nil pour un noeud que Maison place, un
    /// routeur de bordure que la sonde seule connait (precision 25), un noeud sans ExtMac. `entree` : la
    /// scene du meme rendu, dont le graphe et les appareils servent tels quels.
    static func placement(_ id: String, dans surveillance: Surveillance, entree: EntreeScene) -> Placement? {
        let maison = surveillance.noms.maison
        let pieces = PiecesRouteurs.pieces(de: maison).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !pieces.isEmpty else { return nil }
        if surveillance.instantane?.routeur(id) != nil {
            guard PiecesRouteurs.pieceDeMaison(routeur: id, maison: maison) == nil else { return nil }
            return Placement(cle: .routeur(id), pieces: pieces)
        }
        // Un autre noeud : par le graphe de la scene, donc sous la meme cle.
        if let p = entree.appareils[id]?.piece, !p.isEmpty { return nil }
        guard let n = entree.graphe.noeud(id), let cle = PiecesRouteurs.cle(n) else { return nil }
        return Placement(cle: .appareil(cle), pieces: pieces)
    }
}

/// « Placer dans une piece… », dans la fiche d'un noeud que Maison ne place pas : un premier article,
/// puis les pieces de la maison ; le choix en cours est coche.
struct MenuPlacer: View {
    /// Un article du menu : son texte, et la piece qu'il choisit (nil : le premier article).
    struct Article: Hashable {
        var texte: String
        var piece: String?
    }

    let placement: PiecesChoisies.Placement
    let domicile: String
    let choisies: PiecesChoisies

    /// Les articles, dans l'ordre : « D'apres son nom » (la regle du nom) pour un routeur de bordure,
    /// « Sans piece » (le choix efface) pour un autre noeud ; puis les pieces.
    static func articles(_ p: PiecesChoisies.Placement) -> [Article] {
        let premier = switch p.cle {
        case .routeur: String(localized: "D'après son nom")
        case .appareil: String(localized: "Sans pièce")
        }
        return [Article(texte: premier, piece: nil)] + p.pieces.map { Article(texte: $0, piece: $0) }
    }

    /// Le choix en cours, que le menu coche : nil (le premier article) quand la piece choisie n'est plus
    /// une piece du menu. Un choix perime ne compte plus, la scene l'ignore ; sans cela, le menu ne
    /// cocherait aucun article. Il reste dans le fichier.
    var selection: Binding<String?> {
        Binding(
            get: {
                guard let c = choisies.pieceChoisie(placement.cle, domicile: domicile),
                      placement.pieces.contains(c) else { return nil }
                return c
            },
            set: { choisies.choisir($0, placement.cle, domicile: domicile) })
    }

    var body: some View {
        Menu("Placer dans une pièce…") {
            Picker("Placer dans une pièce…", selection: selection) {
                ForEach(Self.articles(placement), id: \.piece) { Text(verbatim: $0.texte).tag($0.piece) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }
}
