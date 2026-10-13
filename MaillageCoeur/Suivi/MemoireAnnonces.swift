import Foundation

/// Garde un temps ce qui manque a un releve : un service absent reste present
/// `sursis` secondes avec ses derniers champs ; passe ce delai, il est
/// abandonne et la date de sa premiere absence est gardee. De meme pour les
/// adresses d'un hote qui ne se resolvent plus. Une absence n'est donc retenue
/// que si elle dure (anti-fausses alertes). Au reveil du Mac, une absence en
/// cours reprend au reveil (`reprendre`) : son sursis ne compte pas la veille.
struct MemoireAnnonces: Sendable {
    static let sursis: TimeInterval = 120

    enum Famille: String, Hashable, Sendable {
        case routeur, matter, hap
    }

    struct Cle: Hashable, Sendable {
        let famille: Famille
        let instance: String
    }

    private var services: [Cle: AnnonceService] = [:]
    private var absences: [Cle: Date] = [:]
    private var adresses: [String: [String]] = [:]
    private var absencesAdresses: [String: Date] = [:]
    /// Services abandonnes au dernier releve -> date de leur premiere absence.
    private(set) var abandons: [Cle: Date] = [:]
    /// Hotes dont les adresses ont ete abandonnees au dernier releve -> premiere absence.
    private(set) var adressesAbandonnees: [String: Date] = [:]

    /// Le releve, complete de ce qui est encore en sursis.
    mutating func completer(_ releve: Annonces) -> Annonces {
        abandons = [:]
        adressesAbandonnees = [:]
        var sortie = releve
        let presents = Self.services(de: releve)
        for (cle, s) in presents {
            services[cle] = s
            absences[cle] = nil
        }
        let absents = services.filter { presents[$0.key] == nil }
            .sorted { ($0.key.famille.rawValue, $0.key.instance) < ($1.key.famille.rawValue, $1.key.instance) }
        for (cle, s) in absents {
            let debut = absences[cle] ?? releve.date
            if releve.date.timeIntervalSince(debut) >= Self.sursis {
                abandons[cle] = debut
                services[cle] = nil
                absences[cle] = nil
            } else {
                absences[cle] = debut
                switch cle.famille {
                case .routeur: sortie.routeurs.append(s)
                case .matter: sortie.matter.append(s)
                case .hap: sortie.hap.append(s)
                }
            }
        }

        // Adresses des hotes encore la (vus ou en sursis).
        let hotes = Set((sortie.routeurs + sortie.matter + sortie.hap).compactMap(\.hote))
        for hote in hotes {
            let vues = releve.adresses[hote] ?? []
            if !vues.isEmpty {
                adresses[hote] = vues
                absencesAdresses[hote] = nil
            } else if let anciennes = adresses[hote] {
                let debut = absencesAdresses[hote] ?? releve.date
                if releve.date.timeIntervalSince(debut) >= Self.sursis {
                    adressesAbandonnees[hote] = debut
                    adresses[hote] = nil
                    absencesAdresses[hote] = nil
                    sortie.adresses[hote] = []
                } else {
                    absencesAdresses[hote] = debut
                    sortie.adresses[hote] = anciennes
                }
            }
        }
        for hote in adresses.keys where !hotes.contains(hote) {
            adresses[hote] = nil
            absencesAdresses[hote] = nil
        }
        return sortie
    }

    /// Au reveil (`fin` de la veille) : chaque absence en cours, de service ou
    /// d'adresses, commencee avant `fin` reprend a `fin`. Un releve fait pendant
    /// l'endormissement (reseau deja coupe) ou juste apres le reveil (resolution
    /// pas prete) ne fait donc rien abandonner d'un coup ; une absence retenue
    /// ensuite est datee du reveil.
    mutating func reprendre(apres fin: Date) {
        absences = absences.mapValues { max($0, fin) }
        absencesAdresses = absencesAdresses.mapValues { max($0, fin) }
    }

    static func services(de a: Annonces) -> [Cle: AnnonceService] {
        var r: [Cle: AnnonceService] = [:]
        for s in a.routeurs { r[Cle(famille: .routeur, instance: s.instance)] = s }
        for s in a.matter { r[Cle(famille: .matter, instance: s.instance)] = s }
        for s in a.hap { r[Cle(famille: .hap, instance: s.instance)] = s }
        return r
    }
}
