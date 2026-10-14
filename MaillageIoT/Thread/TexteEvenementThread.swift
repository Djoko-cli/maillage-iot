import Foundation
import MaillageCoeur
import ProtocoleThread

/// Textes affiches des evenements, des lignes du journal et des notifications.
enum TexteEvenementThread {
    static func heure(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    /// Quand : date et heure, ou la periode de veille si la date est incertaine.
    static func quand(_ e: Evenement) -> String {
        if let p = e.periode {
            return String(localized: "entre \(heure(p.start)) et \(heure(p.end)) (Mac en veille)")
        }
        return e.date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Quand d'une ligne du journal : celui de l'evenement, du premier d'un groupe de pertes (leur
    /// titre donne « entre … et … ») ou du dernier changement d'une ligne de changements de parent
    /// (la ligne est classee a sa date, et son titre ne donne aucune heure).
    static func quand(_ l: LigneJournal) -> String {
        switch l {
        case .evenement(let e): quand(e)
        case .pertes(let g): g.first.map(quand) ?? ""
        case .parents(let g), .chemins(let g): g.last.map(quand) ?? ""
        }
    }

    static func role(_ brut: String?) -> String {
        switch brut.flatMap(RoleThread.init(rawValue:)) {
        case .chef?: String(localized: "chef")
        case .routeur?: String(localized: "routeur")
        case .enfant?: String(localized: "enfant")
        case .detache?: String(localized: "détaché")
        case nil: String(localized: "inconnu")
        }
    }

    static func titre(_ e: Evenement) -> String {
        let nom = e.sujet?.nom ?? ""
        let avant = e.avant ?? "?"
        let apres = e.apres ?? "?"
        switch e.type {
        case .surveillanceDemarree:
            let r = e.details["routeurs"] ?? "0"
            let a = e.details["appareils"] ?? "0"
            if e.sujet != nil {
                return String(localized: "Surveillance du réseau \(nom) démarrée (routeurs : \(r), appareils : \(a))")
            }
            return String(localized: "Surveillance démarrée (routeurs : \(r), appareils : \(a))")
        case .veille:
            guard let p = e.periode else { return String(localized: "Mac en veille") }
            return String(localized: "Mac en veille de \(heure(p.start)) à \(heure(p.end))")
        case .reseauScinde:
            // Constatee : au lancement, a la decouverte ou au retour du reseau.
            if e.constate { return String(localized: "Réseau \(nom) trouvé scindé") }
            return String(localized: "Réseau \(nom) scindé en \(apres) partitions")
        case .reseauReuni:
            return String(localized: "Réseau \(nom) réuni")
        case .chefChange:
            return String(localized: "Nouveau chef : \(apres) (avant : \(avant))")
        case .bbrPrimaireChange:
            return String(localized: "Nouveau BBR primaire : \(apres) (avant : \(avant))")
        case .jeuActifChange:
            return String(localized: "Réseau \(nom) : nouveau jeu de paramètres actif")
        case .routeurApparu, .appareilNouveau:
            return String(localized: "\(nom) est apparu")
        case .routeurDisparu, .appareilDisparu:
            return String(localized: "\(nom) a disparu")
        case .routeurRoleChange:
            return String(localized: "\(nom) : rôle \(role(e.avant)) → \(role(e.apres))")
        case .routeurNouvelleAdresseLien:
            return String(localized: "\(nom) : nouvelle adresse de lien (redémarrage probable)")
        case .prefixeNouveau:
            return String(localized: "Nouveau préfixe \(nom)")
        case .prefixeRetire:
            return String(localized: "Préfixe \(nom) retiré")
        case .appareilRevenu:
            return String(localized: "\(nom) est revenu")
        case .appareilSansAdresse:
            return String(localized: "\(nom) n'annonce plus d'adresse")
        case .appareilChangePartition:
            if e.details["coupee"] == "oui" { return String(localized: "\(nom) est isolé dans la partition \(apres)") }
            return String(localized: "\(nom) a rejoint la partition \(apres)")
        case .parentChange:
            return String(localized: "\(nom) a changé de parent : \(avant) → \(apres)")
        case .sansParent:
            return String(localized: "\(nom) n'a plus de parent")
        case .routeurThreadApparu:
            return String(localized: "Routeur Thread apparu : \(nom)")
        case .routeurThreadDisparu:
            return String(localized: "Routeur Thread disparu : \(nom)")
        default:
            // Type d'un autre protocole, ou relu d'un journal plus recent : son nom, tel que le journal l'ecrit.
            return e.type.rawValue
        }
    }

    static func titre(_ l: LigneJournal) -> String {
        switch l {
        case .evenement(let e):
            return titre(e)
        case .pertes(let p):
            let debut = heure(p.first?.date ?? .distantPast)
            let fin = heure(p.last?.date ?? .distantPast)
            return String(localized: "\(p.count) appareils perdus entre \(debut) et \(fin)")
        case .parents(let p), .chemins(let p):
            // Thread ne produit pas de `.chemins` (protocole Zigbee) : texte des changements de parent, sans cle neuve.
            // Le dernier nom connu : le nom d'un noeud peut changer d'un changement a l'autre.
            let nom = p.last?.sujet?.nom ?? ""
            return String(localized: "\(nom) a changé \(p.count) fois de parent en 1 h")
        }
    }

    /// Jour et mois d'une date, sous la forme courte de la langue (« 08/10 »).
    static func jour(_ d: Date) -> String {
        d.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
    }

    /// Plage horaire d'une ligne de changements regroupes : « 08/10 20:58 – 21:45 », le jour repete de l'autre cote
    /// quand elle passe minuit (reprise de Maillage Zigbee, 09/10).
    static func plage(_ evenements: [Evenement]) -> String {
        guard let debut = evenements.map(\.date).min(), let fin = evenements.map(\.date).max() else { return "" }
        let deb = "\(jour(debut)) \(heure(debut))"
        if Calendar.current.isDate(debut, inSameDayAs: fin) { return "\(deb) – \(heure(fin))" }
        return "\(deb) – \(jour(fin)) \(heure(fin))"
    }

    /// Ce que fait une ligne de changements regroupes, sans le nom du noeud (la fiche est la sienne) : « a changé 4 fois
    /// de parent ». Vide pour les autres lignes.
    static func changements(_ l: LigneJournal) -> String {
        switch l {
        case .parents(let p), .chemins(let p): String(localized: "a changé \(p.count) fois de parent")
        case .evenement, .pertes: ""
        }
    }

    /// Les relais d'une ligne de changements regroupes : « A → B → C · finit sur C » ; pour deux relais qui alternent,
    /// « A ⇄ B · finit sur A ».
    static func resume(_ r: ResumeRelais) -> String {
        guard let dernier = r.dernier else { return r.relais.joined(separator: " → ") }
        let finit = String(localized: "finit sur \(dernier)")
        guard r.relais.count >= 2 else { return finit }
        return r.relais.joined(separator: r.alternent ? " ⇄ " : " → ") + " · " + finit
    }

    /// Un changement dans le detail d'une ligne regroupee : « 20:58 → HomePod salon ».
    static func changement(_ e: Evenement) -> String {
        "\(heure(e.date)) → \(e.apres ?? "?")"
    }

    /// Routeurs des partitions a part (toutes sauf la plus grande), d'apres les details d'une scission.
    static func isoles(_ e: Evenement) -> String {
        let groupes = e.details.map { (partition: $0.key, routeurs: $0.value) }
            .sorted { ($0.routeurs.components(separatedBy: ", ").count, $1.partition)
                    > ($1.routeurs.components(separatedBy: ", ").count, $0.partition) }
        return groupes.dropFirst().map(\.routeurs).joined(separator: " ; ")
    }

    /// Titre et texte d'une notification.
    static func notification(_ a: AlerteAEnvoyer) -> (titre: String, corps: String) {
        guard let e = a.evenements.first else { return ("", "") }
        switch a.categorie {
        case .scission:
            let nom = e.sujet?.nom ?? ""
            return (String(localized: "Réseau Thread scindé"),
                    String(localized: "\(nom) — partition à part : \(isoles(e))"))
        case .routeurDisparu:
            return (String(localized: "Routeur de bordure disparu"), titre(e) + " · " + quand(e))
        case .pertes:
            let noms = a.evenements.compactMap { $0.sujet?.nom }.joined(separator: ", ")
            let debut = heure(a.evenements.first?.date ?? .distantPast)
            let fin = heure(a.evenements.last?.date ?? .distantPast)
            return (String(localized: "\(a.evenements.count) appareils Thread perdus"),
                    String(localized: "Entre \(debut) et \(fin) : \(noms)"))
        case .informations:
            return (titre(e), quand(e))
        }
    }
}
