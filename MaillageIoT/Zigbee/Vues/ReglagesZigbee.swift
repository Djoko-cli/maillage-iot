import AppKit
import MaillageCoeur
import ProtocoleZigbee
import SwiftUI

/// Reglages › Zigbee : le pont Hue (`ReglagesPont` : etat, liaison, adresse), puis la sonde Zigbee (liaison Automatique,
/// USB ou Wi-Fi, port, etat, releve) et l'acces par le reseau (cle, nom et mot de passe du Wi-Fi). La page est celle de
/// l'onglet Zigbee de `FenetreReglages` ; elle porte la saisie du Wi-Fi, oubliee a la fermeture de la fenetre.
struct ReglagesZigbee: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(NomsPont.self) private var nomsPont
    @Environment(SondeMaillageZigbee.self) private var sonde
    /// Le nom et le mot de passe du Wi-Fi tapes et pas encore mis en service (`SaisieWifi`) ; oublies a la fermeture
    /// de la fenetre (`FenetreReglages.estFenetreDesReglages`).
    @State private var saisie = SaisieWifi()
    @State private var messageReseau: String?
    /// Non nil tant que `messageReseau` est le message de succes de la mise en service : il s'efface quand la sonde,
    /// redemarree, est de retour sur le Wi-Fi (`SuiviSuccesReseau`). Une erreur n'a pas de suivi : elle reste.
    @State private var suiviSucces: SuiviSuccesReseau?
    /// `messageReseau` est un message d'information (la cle seule, Wi-Fi garde), ni erreur ni succes suivi.
    @State private var messageInformatif = false
    @State private var miseEnService = false

    var body: some View {
        FenetreReglages.page {
            PageProtocole(protocole: .zigbee) {
                pontHue
                reglagesSonde
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) {
            if FenetreReglages.estFenetreDesReglages($0.object) { saisie.fermerFenetre() }
        }
        .onChange(of: sonde.etat) { suivreSuccesReseau() }
        .onChange(of: sonde.etatSonde?.reseau?.connecte) { suivreSuccesReseau() }
    }

    /// Le refus de Bonjour ne bloque que si la liaison passe par le reseau (Wi-Fi ou Automatique) et que la sonde n'est pas
    /// connectee : en USB, ou sonde deja connectee, la recherche Bonjour est sans objet.
    static func afficherRefusBonjour(nonDeclare: Bool, chemin: ReglageChemin, connectee: Bool) -> Bool {
        nonDeclare && chemin != .usb && !connectee
    }

    /// Fait avancer le suivi du message de succes de la mise en service ; l'efface quand la sonde est de retour.
    private func suivreSuccesReseau() {
        guard var suivi = suiviSucces else { return }
        let efface = suivi.observer(sondeJointe: sonde.etat.estConnectee,
                                    wifiConnecte: FenetreReglages.motDePasseEnregistre(sonde.etatSonde?.reseau))
        if efface {
            messageReseau = nil
            suiviSucces = nil
        } else {
            suiviSucces = suivi
        }
    }

    /// Le pont Hue (`ReglagesPont`) ; en demo, les noms de la demo, sans pont.
    private var pontHue: some View {
        Section("Pont Hue") {
            if surveillance.mode == .demo {
                Text("Mode démo : les noms de la démo, pas de pont.").foregroundStyle(.secondary)
                if let n = nomsPont.noms {
                    LabeledContent("Appareils", value: ReglagesPont.texteLecture(n))
                }
            } else {
                ReglagesPont()
            }
        }
    }

    /// La sonde : liaison, port, chemin, etat, firmware, releve ; puis l'acces par le reseau.
    @ViewBuilder private var reglagesSonde: some View {
        Section("Sonde") {
            if surveillance.mode == .demo {
                Text("Mode démo : pas de sonde.").foregroundStyle(.secondary)
            } else {
                Picker("Liaison", selection: Binding(get: { sonde.reglageChemin },
                                                     set: { sonde.reglageChemin = $0 })) {
                    ForEach(ReglageChemin.allCases, id: \.self) { Text($0.libelle).tag($0) }
                }
                .pickerStyle(.segmented)
                if sonde.reglageChemin == .reseau {
                    // Par le Wi-Fi il n'y a pas de port : l'instance Bonjour de la sonde retenue la remplace.
                    if let nom = sonde.nom {
                        LabeledContent("Service Bonjour", value: nom)
                    }
                } else {
                    Picker("Port", selection: Binding(
                        get: { sonde.ports.first { $0.serie != nil && $0.serie == sonde.serie }?.chemin ?? "" },
                        set: { c in if let p = sonde.ports.first(where: { $0.chemin == c }) { sonde.choisir(p) } })) {
                        Text("—").tag("")
                        ForEach(sonde.ports) { p in
                            Text(verbatim: FenetreReglages.libellePort(p, serieRetenue: sonde.serie, nom: sonde.nom)).tag(p.chemin)
                        }
                    }
                    // Une carte que Thread retient n'est pas dans la liste ; un choix qui la vise malgre tout est refuse.
                    if let refus = sonde.choixRefuse {
                        Text(refus).font(.caption).foregroundStyle(.red)
                    }
                }
                LabeledContent("État", value: FenetreReglages.texteEtatSonde(sonde.etat, nom: sonde.nomEtat))
                if Self.afficherRefusBonjour(nonDeclare: sonde.bonjourNonDeclare, chemin: sonde.reglageChemin,
                                             connectee: sonde.etat.estConnectee) {
                    Text("macOS refuse la recherche de la sonde Zigbee à l'app (liste des services Bonjour de l'app pas à jour pour macOS) : redémarrez le Mac, ou branchez la sonde en USB.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                // Le chemin en service ne s'apprend que dans Automatique : les deux autres liaisons l'imposent.
                if sonde.reglageChemin == .automatique, let a = sonde.acces {
                    LabeledContent("Chemin", value: a.libelle)
                }
                if case .connectee(let b) = sonde.etat {
                    LabeledContent("Firmware", value: b.version)
                }
                ReleveSondeZigbee()
                if sonde.serie != nil {
                    Button("Oublier la sonde") {
                        messageReseau = nil
                        messageInformatif = false
                        suiviSucces = nil
                        Task { await sonde.oublier() }
                    }
                }
                if sonde.reglageChemin != .reseau {
                    Text("Seul le port choisi est ouvert. Un autre ESP32-C6 branché n'est jamais ouvert : ne le choisissez pas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if surveillance.mode != .demo {
            accesParLeReseau
        }
    }

    /// L'acces par le reseau. La cle est creee par la carte, branchee en USB, puis rangee dans le
    /// trousseau ; le mot de passe du Wi-Fi va a la sonde et nulle part ailleurs (le champ est vide des le clic).
    private var accesParLeReseau: some View {
        Section("Accès par le réseau") {
            LabeledContent("Accès réseau", value: FenetreReglages.texteAccesReseau(empreinte: sonde.empreinteAcces))
            if case .connectee(let b) = sonde.etat, !b.accepteReseau {
                Text("Sonde 1.1.0 requise.").foregroundStyle(.secondary)
            } else {
                TextField("Nom du Wi-Fi (2,4 GHz)", text: Binding(
                    get: { FenetreReglages.nomWifiAffiche(brouillon: saisie.brouillon, garde: sonde.nomWifi) },
                    set: { saisie.brouillon = $0 }))
                // Vide des le clic, par construction : quand le Wi-Fi de la sonde est joint, l'invite dit que le mot
                // de passe est dans la sonde. L'app ne le garde ni ne l'affiche.
                SecureField("Mot de passe", text: $saisie.motDePasse,
                            prompt: FenetreReglages.motDePasseEnregistre(sonde.etatSonde?.reseau) ? Text("Enregistré dans la sonde") : nil)
                // Mot de passe laisse vide et Wi-Fi deja configure : seule la cle change, la sonde garde son Wi-Fi.
                let envoiWifi = SondeMaillageZigbee.envoiWifi(wifiConfigure: sonde.wifiConfigure, motDePasse: saisie.motDePasse)
                HStack {
                    Button(FenetreReglages.titreBoutonAcces(empreinte: sonde.empreinteAcces, envoiWifi: envoiWifi)) {
                        miseEnService = true
                        messageReseau = nil
                        messageInformatif = false
                        suiviSucces = nil
                        let nom = FenetreReglages.nomWifiAffiche(brouillon: saisie.brouillon, garde: sonde.nomWifi)
                        let mdp = saisie.motDePasse
                        saisie.motDePasse = ""
                        Task {
                            switch await sonde.autoriserReseau(nomWifi: nom, motDePasse: mdp) {
                            case .echec(let erreur):
                                messageReseau = erreur
                            case .cleSeule:
                                messageReseau = String(localized: "Nouvelle clé rangée dans le trousseau. Le Wi-Fi de la sonde n'a pas changé.")
                                messageInformatif = true
                            case .cleEtWifi:
                                messageReseau = String(localized: "Accès réseau autorisé : la sonde redémarre et rejoint le Wi-Fi.")
                                saisie.brouillon = nil
                                var suivi = SuiviSuccesReseau()
                                // L'etat de depart : une sonde deja sur le Wi-Fi n'est « de retour » qu'apres un redemarrage.
                                _ = suivi.observer(sondeJointe: sonde.etat.estConnectee,
                                                   wifiConnecte: FenetreReglages.motDePasseEnregistre(sonde.etatSonde?.reseau))
                                suiviSucces = suivi
                            }
                            miseEnService = false
                        }
                    }
                    .disabled(!sonde.miseEnServicePossible || miseEnService
                              || (envoiWifi && FenetreReglages.nomWifiAffiche(brouillon: saisie.brouillon, garde: sonde.nomWifi).isEmpty))
                    if miseEnService {
                        ProgressView().controlSize(.small)
                    }
                }
                if let r = sonde.etatSonde?.reseau {
                    LabeledContent("Wi-Fi de la sonde", value: FenetreReglages.texteReseauSonde(r))
                }
                if let messageReseau {
                    Text(messageReseau).font(.caption)
                        .foregroundStyle(suiviSucces == nil && !messageInformatif ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Text("La clé passe par l'USB, sonde branchée, et reste dans le trousseau de ce Mac. Avec la liaison « Wi-Fi », la sonde peut être débranchée et alimentée ailleurs. Le mot de passe du Wi-Fi va directement à la sonde : l'app ne le garde pas. Laissé vide, la sonde garde son Wi-Fi, ou rejoint un réseau ouvert si elle n'en a pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension FenetreReglages {
    /// Le nom du Wi-Fi que montre le champ : le brouillon (meme vide : le nom a ete efface a la main), sinon le nom garde
    /// a la derniere mise en service reussie, sinon rien.
    static func nomWifiAffiche(brouillon: String?, garde: String?) -> String {
        brouillon ?? garde ?? ""
    }

    /// « 13 routeurs · 8 appareils finaux · 16 liens radio ».
    static func texteNoeuds(_ m: MaillageZigbee) -> String {
        let routeurs = m.noeuds.filter(\.route).count
        return String(localized: "\(routeurs) routeurs · \(m.noeuds.count - routeurs) appareils finaux · \(MaillageZigbee.reunir(m.liens).count) liens radio")
    }

    /// Reseau de la sonde (`etat`) : « canal 25 · parent 1A2B (LQI 180) », le parent sous son nom quand il est connu
    /// (`nomParent`, par son adresse longue) ; « hors réseau » si elle n'est pas membre.
    static func texteReseau(_ e: EtatSondeZigbee, nomParent: (String) -> String? = { _ in nil }) -> String {
        guard e.membre else { return String(localized: "hors réseau") }
        var parties: [String] = []
        if let c = e.canal { parties.append(String(localized: "canal \(c)")) }
        if let p = e.parent {
            let n = ProtocoleSondeZigbee.ieee(p.ieee).flatMap(nomParent) ?? p.court
            parties.append(p.lqi.map { String(localized: "parent \(n) (LQI \($0))") } ?? String(localized: "parent \(n)"))
        } else {
            parties.append(String(localized: "sans parent (rattachement en cours)"))
        }
        return parties.joined(separator: " · ")
    }

    /// Role de la sonde (`etat`) : « membre, appareil final » ; « hors réseau, recherche » ; « suspendue » en plus.
    static func texteRole(_ e: EtatSondeZigbee) -> String {
        var parties = [e.membre ? String(localized: "membre") : String(localized: "hors réseau")]
        if e.role == "final" { parties.append(String(localized: "appareil final")) }
        if !e.membre && e.recherche == true { parties.append(String(localized: "cherche un réseau")) }
        if e.suspendue { parties.append(String(localized: "suspendue")) }
        if let n = e.rattachementsEchoues, n > 0 { parties.append(String(localized: "\(n) rattachements échoués")) }
        return parties.joined(separator: ", ")
    }

    /// Derniere tournee : « 1 min 12 s · 36/36 tables · 15/15 routes · 20 routes reportées · 547 pages · 1 muet »
    /// (« passe complémentaire » apres la duree pour une passe des routes reportees ; les tables de voisins lues sur
    /// les demandees, une tournee sur quatre ; les tables de routage des routeurs, et celles remises a la tournee
    /// suivante faute de budget ; les pages envoyees a la sonde ; les routeurs muets), les pauses sur un refus de
    /// cadence, et « incomplète » quand elle l'est.
    static func texteBilan(_ b: BilanTournee, duree: TimeInterval?) -> String {
        var parties: [String] = []
        if let duree { parties.append(TexteTournee.duree(duree)) }
        if b.complementaire { parties.append(String(localized: "passe complémentaire")) }
        if b.avecTables { parties.append(String(localized: "\(b.tablesLues)/\(b.tablesDemandees) tables")) }
        parties.append(String(localized: "\(b.routesRouteursLues)/\(b.routesRouteursDemandees) routes"))
        if b.routesReportees > 0 { parties.append(String(localized: "\(b.routesReportees) routes reportées")) }
        if b.pages > 0 { parties.append(String(localized: "\(b.pages) pages")) }
        if b.pausesCadence > 0 { parties.append(String(localized: "\(b.pausesCadence) pauses de cadence")) }
        if b.muets > 0 { parties.append(String(localized: "\(b.muets) muets")) }
        if b.sansReponse > b.muets { parties.append(String(localized: "\(b.sansReponse - b.muets) sans réponse")) }
        if b.attentes > 0 { parties.append(String(localized: "\(b.attentes) attentes de la sonde")) }
        if b.lacune != nil { parties.append(String(localized: "incomplète")) }
        return parties.joined(separator: " · ")
    }

    /// Etat de la sonde, precede du nom de la sonde retenue quand il la concerne
    /// (« SONDE-01 · connectee ») ; seul pour un autre port choisi ou sans nom connu.
    static func texteEtatSonde(_ e: SondeMaillageZigbee.Etat, nom: String?) -> String {
        let texte = switch e {
        case .sansSonde: String(localized: "aucune sonde choisie")
        case .absente: String(localized: "absente (débranchée ?)")
        case .injoignable: String(localized: "Réseau — sonde injoignable")
        case .connexion: String(localized: "connexion…")
        case .connectee: String(localized: "connectée")
        case .refusee(let m): String(localized: "refusée : \(m)")
        case .erreur(let m): String(localized: "erreur : \(m)")
        }
        guard let nom else { return texte }
        return String(localized: "\(nom) · \(texte)")
    }

    /// Titre du bouton de l'acces reseau : autoriser tant qu'il n'y a pas de cle, puis en regenerer une (le bouton
    /// reste actif : une nouvelle cle remplace l'ancienne), seule si la sonde garde son Wi-Fi (`envoiWifi` faux :
    /// mot de passe vide, Wi-Fi deja configure), avec le Wi-Fi sinon.
    static func titreBoutonAcces(empreinte: String?, envoiWifi: Bool) -> String {
        if empreinte == nil { return String(localized: "Autoriser l'accès réseau") }
        return envoiWifi ? String(localized: "Régénérer la clé et changer le Wi-Fi") : String(localized: "Régénérer une clé")
    }

    /// Le Wi-Fi de la sonde est joint : le mot de passe est donc dans la sonde (l'invite du champ le dit). Le mot de
    /// passe lui-meme n'est jamais garde ni affiche.
    static func motDePasseEnregistre(_ r: ReseauSonde?) -> Bool {
        r?.connecte == true
    }

    /// Wi-Fi de la sonde (`etat.reseau`) : « connecté · canal 6 · −58 dBm » ; « non connecté (raison 201) ».
    static func texteReseauSonde(_ r: ReseauSonde) -> String {
        guard r.connecte else {
            if let raison = r.raison, raison != 0 { return String(localized: "non connecté (raison \(raison))") }
            return String(localized: "non connecté")
        }
        var parties = [String(localized: "connecté")]
        if let c = r.canal { parties.append(String(localized: "canal \(c)")) }
        if let s = r.rssi { parties.append("\(s.formatted()) dBm".replacingOccurrences(of: "-", with: "−")) }
        return parties.joined(separator: " · ")
    }
}

/// Le Wi-Fi saisi dans la page Zigbee et pas encore mis en service. `brouillon` : le nom tape ; nil tant que rien n'est
/// tape depuis l'ouverture de la fenetre, le champ montre alors le nom garde (`SondeMaillageZigbee.nomWifi`), et apres une mise
/// en service reussie. `motDePasse` : vide des le clic, jamais garde. La fenetre des Reglages est gardee a la fermeture :
/// `fermerFenetre` oublie la saisie.
struct SaisieWifi: Equatable {
    var brouillon: String?
    var motDePasse = ""

    mutating func fermerFenetre() {
        brouillon = nil
        motDePasse = ""
    }
}

/// Suivi du message de succes « la sonde redémarre et rejoint le Wi-Fi » : il s'efface quand la sonde est de retour,
/// jointe et sur le Wi-Fi, apres avoir ete vue redemarrer (liaison perdue ou Wi-Fi non joint). Sans cette exigence, une
/// sonde deja sur le Wi-Fi effacerait le message avant meme de redemarrer. `observer` s'appelle une fois au moment du
/// succes (etat de depart), puis a chaque changement de la liaison ou du Wi-Fi.
struct SuiviSuccesReseau: Equatable {
    private(set) var aRedemarre = false

    /// Vrai quand le message doit s'effacer.
    mutating func observer(sondeJointe: Bool, wifiConnecte: Bool) -> Bool {
        if !sondeJointe || !wifiConnecte {
            aRedemarre = true
            return false
        }
        return aRedemarre
    }
}

/// Releve de la sonde Zigbee (Reglages › Zigbee) : son role, son parent, son canal et sa suspension (`etat` de la sonde),
/// l'avertissement si elle n'est pas sur le reseau du pont, tournee en cours ou derniere tournee (date, duree, tables
/// lues, muets), derniere erreur. Seulement la sonde connectee : debranchee ou pendant une connexion, ces lignes
/// seraient perimees.
struct ReleveSondeZigbee: View {
    @Environment(SondeMaillageZigbee.self) private var sonde
    @Environment(Surveillance.self) private var surveillance

    var body: some View {
        if case .connectee = sonde.etat {
            if let e = sonde.etatSonde {
                LabeledContent("Rôle", value: FenetreReglages.texteRole(e))
                LabeledContent("Réseau", value: FenetreReglages.texteReseau(e) { ieee in
                    surveillance.zigbee.noms.nomConnu(ieee: ieee)
                })
                if e.suspendue {
                    Text("Sonde suspendue : pas de relevé.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let r = surveillance.zigbee.noms.maison?.reseau, !r.accueille(e) {
                    Text("La sonde n'est pas sur le réseau du pont (canal ou identifiant du réseau différent).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let a = sonde.avancement, let debut = sonde.debutTournee {
                TimelineView(.periodic(from: debut, by: 1)) { contexte in
                    LabeledContent("Tournée", value: TexteTourneeZigbee.reglages(a, debut: debut, maintenant: contexte.date))
                }
            } else if let d = sonde.derniereTournee {
                LabeledContent("Dernière tournée", value: FenetreReglages.texteDernierReleve(d))
            }
            if sonde.avancement == nil, let b = sonde.bilan {
                LabeledContent("Bilan", value: FenetreReglages.texteBilan(b, duree: sonde.dureeTournee))
            }
            if sonde.avancement == nil, let passe = sonde.passeComplementaire {
                ligneProchaineTournee(TexteTourneeZigbee.passeComplementaire(passe))
            }
            if sonde.avancement == nil, let differee = sonde.tourneeDifferee {
                ligneProchaineTournee(TexteTourneeZigbee.tourneeDifferee(differee))
            }
            if let e = sonde.erreurTournee {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// « Prochaine tournée » : le texte peut etre long (« la sonde a déjà beaucoup servi… »), il passe a la ligne au lieu
    /// d'etre tronque, aligne a droite comme les autres valeurs.
    private func ligneProchaineTournee(_ texte: String) -> some View {
        LabeledContent("Prochaine tournée") {
            Text(texte).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }
}
