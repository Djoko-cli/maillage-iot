import Foundation
import MaillageCoeur
import ProtocoleThread

/// Un appareil qui s'annonce par AirPlay (`_airplay._tcp`) : son nom, tel que Maison le donne, l'hote de sa cible et le
/// modele de son TXT (`model`, nil sans). Le recenseur ne garde que ceux dont l'hote est resolu.
struct ServiceAirPlay: Hashable, Sendable {
    let nom: String
    /// Hote mDNS ("Hote-1.local"), tel que le resolveur le donne.
    let hote: String
    let modele: String?
}

/// La piece qu'une proposition suggere pour un routeur de bordure, et le nom AirPlay dont elle vient : « Ignorer » est
/// memorise sous ce nom, et la proposition revient quand il change.
struct Proposition: Hashable, Sendable {
    let piece: String
    let nomAirPlay: String
}

/// Piece proposee aux routeurs de bordure Thread (HomePod, Apple TV) que Maison ne place pas : leur nom AirPlay contient
/// souvent leur piece. Le calcul est pur : l'ecoute est celle du recenseur (`Recenseur.typeAirPlay`), la piece de la fiche
/// et son bouton sont ailleurs. Rien n'est jamais place d'office, et un doute ne donne aucune proposition.
enum PieceAirPlay {
    /// Les services AirPlay d'un releve (hote resolu), tries par nom puis par hote.
    static func services(de releve: Annonces) -> [ServiceAirPlay] {
        releve.airplay.compactMap { s in
            guard let hote = s.hote, !cle(hote: hote).isEmpty else { return nil }
            return ServiceAirPlay(nom: s.instance, hote: hote, modele: s.txt.texte("model"))
        }.sorted { ($0.nom, $0.hote) < ($1.nom, $1.hote) }
    }

    /// Les routeurs de bordure d'un releve (hote resolu) : leur id de noeud (`thread:<instance>`) et leur hote.
    static func bordures(de releve: Annonces) -> [(id: IdNoeud, hote: String)] {
        releve.routeurs.compactMap { r in
            guard let hote = r.hote, !cle(hote: hote).isEmpty else { return nil }
            return (IdNoeud(.thread, r.instance), hote)
        }
    }

    /// Nom d'hote compare : sans casse et sans point final.
    static func cle(hote: String) -> String {
        var h = hote.lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        return h
    }

    /// La piece proposee de chaque routeur de bordure, par id de noeud.
    ///
    /// - Rattachement : le service et le routeur ont le meme nom d'hote (`cle(hote:)`), rien d'autre. Un hote partage par
    ///   deux routeurs n'en designe aucun.
    /// - Piece : une piece de `piecesMaison` contenue en mot entier dans le nom AirPlay, sans casse ni accents ; la plus
    ///   longue (`PiecesRouteurs.piece(nom:parmi:)`, aucune a egalite de longueur). Si plusieurs services partagent l'hote,
    ///   ils doivent s'accorder : deux pieces differentes ne donnent rien.
    /// - Un routeur qui a deja une piece (`piecesConnues` : Maison, choix ou nom) n'a pas de proposition.
    static func propositions(airplay: [ServiceAirPlay], bordures: [(id: IdNoeud, hote: String)], piecesMaison: [String],
                             piecesConnues: [IdNoeud: String]) -> [IdNoeud: Proposition] {
        var routeursParHote: [String: Set<IdNoeud>] = [:]
        for b in bordures { routeursParHote[cle(hote: b.hote), default: []].insert(b.id) }
        var servicesParHote: [String: [ServiceAirPlay]] = [:]
        for s in airplay { servicesParHote[cle(hote: s.hote), default: []].append(s) }

        var resultat: [IdNoeud: Proposition] = [:]
        for (hote, ids) in routeursParHote {
            guard ids.count == 1, let id = ids.first, !hote.isEmpty,
                  piecesConnues[id]?.isEmpty ?? true, let services = servicesParHote[hote] else { continue }
            // Les pieces que disent les noms : un nom sans piece ne dit rien, deux pieces differentes sont un doute.
            let dites = services.compactMap { s in
                PiecesRouteurs.piece(nom: s.nom, parmi: piecesMaison).map { (piece: $0, nom: s.nom) }
            }
            guard let premiere = dites.map(\.piece).first, dites.allSatisfy({ $0.piece == premiere }) else { continue }
            let nom = dites.map(\.nom).min() ?? ""
            resultat[id] = Proposition(piece: premiere, nomAirPlay: nom)
        }
        return resultat
    }
}
