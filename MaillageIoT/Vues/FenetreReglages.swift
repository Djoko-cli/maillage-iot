import AppKit
import MaillageCoeur
import ProtocoleThread
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Onglets de la fenetre Reglages (`ControleurReglages`), dans la barre d'outils ; le dernier
/// ouvert est garde (demande de Djoko, 30/09 : une seule page etait trop chargee).
enum OngletReglages: String, CaseIterable {
    case general, notifications, maison, thread, zigbee, diagnostic
    static let cle = "reglages.onglet"

    /// Libelle de l'onglet, et titre de la fenetre quand il est choisi.
    var titre: String {
        switch self {
        case .general: String(localized: "Général")
        case .notifications: String(localized: "Notifications")
        case .maison: String(localized: "Maison")
        case .thread: String(localized: "Thread")
        case .zigbee: String(localized: "Zigbee")
        case .diagnostic: String(localized: "Diagnostic")
        }
    }

    /// Symbole SF de l'onglet (le repli des deux onglets a logo).
    var symbole: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .maison: "house"
        case .thread: "point.3.connected.trianglepath.dotted"
        case .zigbee: "antenna.radiowaves.left.and.right"
        case .diagnostic: "stethoscope"
        }
    }

    /// Le logo redessine de Thread ou de Zigbee, en vectoriel monochrome (`Logos.xcassets`, trace par
    /// `outils/icone/generer.swift`) : une image modele, teintee par la barre d'outils comme les symboles voisins
    /// (bleu quand l'onglet est choisi, clair en mode sombre). Les autres onglets n'en ont pas.
    var logo: NSImage? {
        let nom: String
        switch self {
        case .thread: nom = "LogoThread"
        case .zigbee: nom = "LogoZigbee"
        default: return nil
        }
        guard let image = NSImage(named: nom) else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = titre
        return image
    }

    /// L'image de l'onglet dans la barre d'outils : son logo, sinon son symbole SF.
    var image: NSImage {
        logo ?? NSImage(systemSymbolName: symbole, accessibilityDescription: titre) ?? NSImage()
    }
}

/// Une page des Reglages, celle d'un onglet : General (ouverture a la connexion, mises a jour, langue, vue par
/// pieces : les etages en 2D), Notifications (par categorie), Maison (le demon Passeur Noms et les noms qu'il a releves :
/// `ReglagesMaison`), Thread (liaison USB ou reseau Thread de la sonde, acces reseau, Thread Route), Zigbee (le pont Hue
/// et la sonde Zigbee : `ReglagesZigbee`), Diagnostic (ecoute de Thread, maillage de Zigbee, captures, journal). La
/// fenetre et ses onglets sont dans `ControleurReglages`.
struct FenetreReglages: View {
    let onglet: OngletReglages
    /// Appele a chaque changement de hauteur de la page : la fenetre la suit (`ControleurReglages`).
    var surHauteur: @MainActor (CGFloat) -> Void = { _ in }
    @Environment(Surveillance.self) private var surveillance
    @Environment(OuvertureSession.self) private var ouverture
    @Environment(SondeMaillageThread.self) private var sonde
    @Environment(MisesAJour.self) private var misesAJour
    @AppStorage(Notifications.cle(.scission)) private var scission = CategorieAlerte.scission.parDefaut
    @AppStorage(Notifications.cle(.routeurDisparu)) private var routeurDisparu = CategorieAlerte.routeurDisparu.parDefaut
    @AppStorage(Notifications.cle(.pertes)) private var pertes = CategorieAlerte.pertes.parDefaut
    @AppStorage(Notifications.cle(.informations)) private var informations = CategorieAlerte.informations.parDefaut
    @AppStorage(FenetrePieces.cleGrille) private var etagesEnGrille = true
    @State private var messageCapture: String?
    @State private var langue = LangueApp.lire()
    @State private var messageLangue: String?
    /// L'etat de Thread Route, suivi par la fenetre (`SuiviThreadRoute`) : relu a l'affichage de l'onglet, et a
    /// chaque retour de l'app au premier plan.
    @Environment(SuiviThreadRoute.self) private var suiviThreadRoute

    var body: some View {
        Group {
            switch onglet {
            case .general:
                page {
                    ouvertureALaConnexion
                    sectionMisesAJour
                    choixDeLangue
                    vueParPieces
                }
            case .notifications: page { notifications }
            case .maison: page { ReglagesMaison() }
            case .thread:
                page {
                    PageProtocole(protocole: .thread) {
                        reglagesSonde
                        threadRoute
                    }
                }
            case .zigbee: ReglagesZigbee()
            case .diagnostic:
                page {
                    diagnosticThread
                    diagnosticZigbee
                    diagnosticJournal
                }
            }
        }
        .frame(width: 560)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { surHauteur($0) }
        // Collee en haut : pendant que la fenetre change de hauteur, la page ne bouge pas.
        .frame(maxHeight: .infinity, alignment: .top)
        // Etat de l'ouverture a la connexion relu a chaque affichage de l'onglet (Reglages Systeme).
        .onAppear {
            if onglet == .general { ouverture.actualiser() }
            // Thread Route installe ou approuve entre-temps : son etat est relu a chaque affichage de l'onglet.
            if onglet == .thread { suiviThreadRoute.relire() }
        }
    }

    /// Page d'un onglet : un formulaire groupe, a la hauteur de son contenu. Un formulaire groupe
    /// connait sa hauteur ideale, mais accepte toute hauteur proposee : sans `fixedSize`, il
    /// n'annoncerait pas sa hauteur a la fenetre. Mesure du 30/09 : 121 pt pour 2 lignes, 367 pour 8.
    private func page<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        Self.page(contenu)
    }

    /// La page d'un onglet qui compose la sienne (`ReglagesZigbee`).
    static func page<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        Form { contenu() }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Onglet Notifications : une categorie par interrupteur.
    private var notifications: some View {
        Section {
            Toggle("Réseau scindé", isOn: $scission)
            Toggle("Routeur de bordure disparu", isOn: $routeurDisparu)
            Toggle("Au moins 3 appareils perdus en 10 min (une notification groupée)", isOn: $pertes)
            Toggle("Autres changements", isOn: $informations)
        }
    }

    /// Onglet General : ouverture a la connexion.
    private var ouvertureALaConnexion: some View {
        Section("Ouverture") {
            Toggle("Ouvrir à la connexion", isOn: Binding(get: { ouverture.active }, set: { ouverture.basculer($0) }))
            if ouverture.approbationRequise {
                Button("Approuver dans Réglages Système…") { ouverture.ouvrirReglagesSysteme() }
            }
            if let e = ouverture.erreur {
                Text(e).foregroundStyle(.red)
            }
        }
    }

    /// Onglet General : les mises a jour (Sparkle), recherche et installation automatiques, cochees par defaut.
    private var sectionMisesAJour: some View {
        Section("Mises à jour") {
            Toggle("Rechercher automatiquement",
                   isOn: Binding(get: { misesAJour.rechercheAuto }, set: { misesAJour.rechercheAuto = $0 }))
            Toggle("Installer automatiquement",
                   isOn: Binding(get: { misesAJour.installationAuto }, set: { misesAJour.installationAuto = $0 }))
                .disabled(!misesAJour.rechercheAuto)
            Button("Rechercher les mises à jour…") { misesAJour.rechercher() }
                .disabled(!misesAJour.peutRechercher)
        }
    }

    /// Onglet General : langue de l'app, appliquee au prochain lancement.
    private var choixDeLangue: some View {
        Section {
            Picker("Langue", selection: $langue) {
                Text("Celle du Mac").tag(LangueApp.systeme)
                Text(verbatim: "Français").tag(LangueApp.francais)
                Text(verbatim: "English").tag(LangueApp.anglais)
            }
            .onChange(of: langue) { _, l in LangueApp.ecrire(l) }
            if langue != LangueApp.auLancement {
                HStack {
                    Text("La langue change au prochain lancement.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Relancer maintenant") {
                        Task {
                            do { try await LangueApp.relancer() } catch { messageLangue = error.localizedDescription }
                        }
                    }
                }
            }
            if let messageLangue {
                Text(messageLangue).foregroundStyle(.red)
            }
        }
    }

    /// Onglet General : la vue par pieces (polissage C, section 3.1) ; les etages en 2D, en grille ou en rangee,
    /// s'appliquent tout de suite a la vue ouverte.
    private var vueParPieces: some View {
        Section("Vue par pièces") {
            Picker("Étages en 2D", selection: $etagesEnGrille) {
                Text("En grille").tag(true)
                Text("En rangée").tag(false)
            }
        }
    }

    /// Onglet Thread : la sonde (liaison, etat, code Matter, acces reseau, tournee).
    private var reglagesSonde: some View {
        Section {
            if surveillance.mode == .demo {
                Text("Mode démo : pas de sonde.").foregroundStyle(.secondary)
            } else {
                // Le reseau se propose une fois l'acces autorise (cle de ce Mac pour la sonde).
                if sonde.reseauDisponible || sonde.liaison == .reseau {
                    Picker("Liaison", selection: Binding(get: { sonde.liaison }, set: { sonde.choisirLiaison($0) })) {
                        Text("USB").tag(SondeMaillageThread.Liaison.usb)
                        Text("Réseau Thread").tag(SondeMaillageThread.Liaison.reseau)
                    }
                    .pickerStyle(.segmented)
                }
                if sonde.liaison == .reseau {
                    LabeledContent("Nom d'hôte", value: Self.texteHote(sonde.hote))
                } else {
                    Picker("Port", selection: Binding(
                        get: { sonde.ports.first { $0.serie != nil && $0.serie == sonde.serie }?.chemin ?? "" },
                        set: { c in if let p = sonde.ports.first(where: { $0.chemin == c }) { sonde.choisir(p) } })) {
                        Text("—").tag("")
                        ForEach(sonde.ports) { p in
                            Text(verbatim: Self.libellePort(p, serieRetenue: sonde.serie, nom: sonde.nom)).tag(p.chemin)
                        }
                    }
                    // Une carte que Zigbee retient n'est pas dans la liste ; un choix qui la vise malgre tout est refuse.
                    if let refus = sonde.choixRefuse {
                        Text(refus).font(.caption).foregroundStyle(.red)
                    }
                }
                LabeledContent("État", value: Self.texteEtatSonde(sonde.etat, nom: sonde.nomEtat))
                DernierePerteSonde()
                if case .connectee(let b) = sonde.etat {
                    LabeledContent("Firmware", value: b.version)
                    let qr = b.qr.flatMap { $0.isEmpty ? nil : $0 }
                    let code = b.code.flatMap { $0.isEmpty ? nil : $0 }
                    if qr != nil || code != nil {
                        CodeMatterSonde(qr: qr, code: code, appairee: b.appairee)
                    } else if let note = Self.noteCodeMatter(b, liaison: sonde.liaison) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ReleveSonde()
                // Le nom d'hote reste apres un oubli dont la cle n'a pas pu etre effacee.
                if sonde.serie != nil || sonde.hote != nil {
                    AccesReseauSonde()
                    Button("Oublier la sonde") { Task { await sonde.oublier() } }
                }
                Text("Seul le port choisi est ouvert. Un autre ESP32-C6 branché n'est jamais ouvert : ne le choisissez pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Onglet Diagnostic, Thread : ecoute du reseau local, dernier releve, table de routage, capture.
    private var diagnosticThread: some View {
        Section("Thread") {
            LabeledContent("Écoute", value: etatEcoute)
            LabeledContent("Dernier relevé",
                           value: surveillance.thread.dernierReleve?.date.formatted(date: .abbreviated, time: .standard) ?? "—")
            if let a = surveillance.thread.dernierReleve {
                LabeledContent("Services vus", value: "_meshcop._udp \(a.routeurs.count) · _matter._tcp \(a.matter.count) · _hap._udp \(a.hap.count)")
                LabeledContent("Préfixes du Mac", value: a.prefixesLocaux.joined(separator: ", "))
            }
            LabeledContent("Table de routage", value: routes)
            Button("Enregistrer une capture…") {
                enregistrerCapture(nom: "capture-maillage.json") { try surveillance.thread.captureJSON() }
            }
            .disabled(surveillance.thread.dernierReleve == nil)
        }
    }

    /// Onglet Diagnostic, Zigbee : dernier maillage, ses noeuds, capture.
    private var diagnosticZigbee: some View {
        Section("Zigbee") {
            LabeledContent("Dernier maillage",
                           value: surveillance.zigbee.maillageRecu?.formatted(date: .abbreviated, time: .standard) ?? "—")
            if let m = surveillance.zigbee.maillage {
                LabeledContent("Nœuds", value: Self.texteNoeuds(m))
            }
            Button("Enregistrer une capture…") {
                enregistrerCapture(nom: "capture-maillage-zigbee.json") { try surveillance.zigbee.captureJSON() }
            }
            .disabled(surveillance.zigbee.maillage == nil)
        }
    }

    /// Onglet Diagnostic, les deux protocoles : le journal commun.
    private var diagnosticJournal: some View {
        Section {
            if let e = surveillance.erreurJournal {
                LabeledContent("Journal", value: e)
            }
            Button("Afficher le journal dans le Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [Surveillance.dossierParDefaut.appendingPathComponent("Journal")])
            }
            .disabled(surveillance.mode == .demo)
            if let messageCapture {
                Text(messageCapture).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Onglet Thread : Thread Route, le demon qui garde la route du Mac vers le reseau Thread (et vers la sonde
    /// par « Reseau Thread ») ; son etat, et ce qu'il reste a faire.
    private var threadRoute: some View {
        Section("Thread Route") {
            LabeledContent("État", value: suiviThreadRoute.etat.libelle)
            if let c = suiviThreadRoute.etat.consigne {
                Text(c).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if suiviThreadRoute.etat == .aApprouver {
                Button("Ouvrir Réglages Système…") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }

    /// Zones de Maison lues par le passeur, dans l'ordre de Maison : « Rez-de-chaussee, Etage ».
    static func texteZones(_ zones: [ZoneMaison]) -> String {
        zones.isEmpty ? String(localized: "aucune zone dans Maison") : zones.map(\.nom).joined(separator: ", ")
    }

    /// Libelle d'un port dans le choix : la sonde retenue sous son nom seul ; tout autre port,
    /// ou la sonde retenue sans nom connu (firmware 1.0.0), sous son nom de port et son numero
    /// de serie USB (la MAC d'un C6), qui seul distingue la sonde du pont Halo avant la
    /// premiere connexion.
    static func libellePort(_ p: PortUSB, serieRetenue: String?, nom: String?) -> String {
        if let nom, let serie = p.serie, serie == serieRetenue { return nom }
        return p.libelle
    }

    /// Acces reseau de la sonde retenue : « autorise · cle 630DCD29 » (empreinte de la cle de
    /// ce Mac), ou « non autorise ».
    static func texteAccesReseau(empreinte: String?) -> String {
        guard let empreinte else { return String(localized: "non autorisé") }
        return String(localized: "autorisé · clé \(empreinte)")
    }

    /// Titre du bouton de l'acces reseau : autoriser tant qu'il n'y a pas de cle, puis en
    /// regenerer une (le bouton reste actif : une nouvelle cle remplace l'ancienne).
    static func titreBoutonAcces(empreinte: String?) -> String {
        empreinte == nil ? String(localized: "Autoriser l'accès réseau") : String(localized: "Régénérer une clé")
    }

    /// Note a la place du code Matter : par le reseau, la sonde (1.0.2) ne donne ni QR code ni
    /// code d'appairage, qui ne circulent pas en clair ; nil en USB, ou quand elle les donne.
    static func noteCodeMatter(_ b: Bonjour, liaison: SondeMaillageThread.Liaison) -> String? {
        guard liaison == .reseau, (b.qr ?? "").isEmpty, (b.code ?? "").isEmpty else { return nil }
        return String(localized: "Le code Matter ne passe pas par le réseau : branchez la sonde en USB pour l'afficher.")
    }

    /// Nom d'hote vise par la liaison reseau : « 0123456789ABCDEF.local ».
    static func texteHote(_ hote: String?) -> String {
        hote.map { "\($0).local" } ?? "—"
    }

    /// Couverture de l'ecoute (spec de la sonde tout-en-un, section 2.4) : « routeurs entendus : 3 sur 7 », les routeurs
    /// de la partition que la sonde entend ; elle varie quand on deplace la sonde.
    static func texteCouverture(_ c: CouvertureEcoute) -> String {
        String(localized: "routeurs entendus : \(c.entendus) sur \(c.routeurs)")
    }

    /// « Dernier releve » de la sonde : la date et l'heure (la sonde peut rester des jours sans
    /// relever), comme le dernier releve du reseau local (section Diagnostic).
    static func texteDernierReleve(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .standard)
    }

    /// Etat de la sonde, precede du nom de la sonde retenue quand il la concerne
    /// (« SONDE-T1 · connectee ») ; seul pour un autre port choisi ou sans nom connu.
    static func texteEtatSonde(_ e: SondeMaillageThread.Etat, nom: String?) -> String {
        let texte = switch e {
        case .sansSonde: String(localized: "aucune sonde choisie")
        case .absente: String(localized: "absente (débranchée ?)")
        case .connexion: String(localized: "connexion…")
        case .connectee: String(localized: "connectée")
        case .refusee(let m): String(localized: "refusée : \(m)")
        case .erreur(let m): String(localized: "erreur : \(m)")
        }
        guard let nom else { return texte }
        return String(localized: "\(nom) · \(texte)")
    }

    private var etatEcoute: String {
        switch surveillance.thread.etatEcoute {
        case .demarrage: String(localized: "démarrage")
        case .active: String(localized: "active")
        case .reseauLocalRefuse: String(localized: "accès au réseau local refusé")
        case .demo: String(localized: "mode démo")
        case .eteint: String(localized: "désactivé")
        case .erreur(let m): m
        }
    }

    private var routes: String {
        switch surveillance.thread.routesLisibles {
        case true?: String(localized: "lue")
        case false?: String(localized: "illisible : préfixes tirés des adresses")
        case nil: "—"
        }
    }

    /// Enregistre une capture JSON (`donnees`) dans un fichier choisi, sous le nom `nom` ; le resultat va dans
    /// `messageCapture`.
    private func enregistrerCapture(nom: String, _ donnees: () throws -> Data?) {
        let contenu: Data
        do {
            guard let d = try donnees() else { return }
            contenu = d
        } catch {
            messageCapture = error.localizedDescription
            return
        }
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [.json]
        panneau.nameFieldStringValue = nom
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        do {
            try contenu.write(to: url, options: .atomic)
            messageCapture = String(localized: "Capture enregistrée : \(url.lastPathComponent)")
        } catch {
            messageCapture = error.localizedDescription
        }
    }

    /// `objet` (celui d'une notification de fenetre) est la fenetre des Reglages (`ControleurReglages`).
    static func estFenetreDesReglages(_ objet: Any?) -> Bool {
        (objet as? NSWindow)?.contentViewController is OngletsReglages
    }
}

/// Acces reseau de la sonde retenue (Reglages › Thread) : son etat, et « Autoriser l'acces
/// reseau », qui cree la cle par l'USB (sonde branchee et connectee par son port).
struct AccesReseauSonde: View {
    @Environment(SondeMaillageThread.self) private var sonde

    var body: some View {
        LabeledContent("Accès réseau", value: FenetreReglages.texteAccesReseau(empreinte: sonde.empreinteAcces))
        if sonde.liaison == .usb {
            HStack {
                Button(FenetreReglages.titreBoutonAcces(empreinte: sonde.empreinteAcces)) {
                    Task { await sonde.autoriserAccesReseau() }
                }
                    .disabled(!sonde.peutAutoriser)
                if sonde.autorisationEnCours {
                    ProgressView().controlSize(.small)
                }
            }
        }
        if let e = sonde.erreurAcces {
            Text(e).font(.caption).foregroundStyle(.red)
        }
        Text("La clé passe par l'USB, sonde branchée, et reste dans le trousseau de ce Mac. Avec la liaison « Réseau Thread », la sonde peut être débranchée et alimentée ailleurs.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Derniere session reseau perdue (Reglages › Thread) : depuis quand, et sa cause, gardees
/// jusqu'a la connexion suivante reussie, quand l'etat est deja passe a la reprise (sonde
/// promenee dans la maison). Rien en USB.
struct DernierePerteSonde: View {
    @Environment(SondeMaillageThread.self) private var sonde

    var body: some View {
        if sonde.liaison == .reseau, let perte = sonde.dernierePerte {
            TimelineView(.periodic(from: perte.date, by: 1)) { contexte in
                LabeledContent("Dernière perte", value: FicheNoeud.relatif(perte.date, contexte.date))
            }
            Text(perte.cause).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Releve de la sonde (Reglages › Thread) : partition et suspension (`etat` de la sonde), tournee
/// en cours ou dernier releve, erreur de la derniere tournee. Seulement la sonde connectee :
/// debranchee, en reprise ou pendant une connexion, ces lignes seraient perimees.
struct ReleveSonde: View {
    @Environment(SondeMaillageThread.self) private var sonde

    var body: some View {
        if case .connectee = sonde.etat {
            if let e = sonde.etatSonde {
                LabeledContent("Partition", value: e.partition ?? "—")
                if let c = sonde.couverture {
                    LabeledContent("Couverture", value: FenetreReglages.texteCouverture(c))
                }
                if e.suspendue {
                    Text("Sonde suspendue dans Maison (interrupteur « Sonde maillage » éteint) : pas de relevé.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let a = sonde.avancement, let debut = sonde.debutTournee {
                TimelineView(.periodic(from: debut, by: 1)) { contexte in
                    LabeledContent("Tournée", value: TexteTourneeThread.reglages(a, debut: debut, maintenant: contexte.date))
                }
            } else if let d = sonde.derniereTournee {
                LabeledContent("Dernier relevé", value: FenetreReglages.texteDernierReleve(d))
            }
            if let e = sonde.erreurTournee {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// Code Matter de la sonde (Reglages › Thread), meme quand elle est dans Maison : le QR code,
/// agrandi sans lissage, noir sur blanc (marge blanche comprise, lisible en mode sombre), et le
/// code d'appairage mis en forme.
struct CodeMatterSonde: View {
    let qr: String?
    let code: String?
    let appairee: Bool
    /// QR code forme une fois par charge, et non a chaque rendu des Reglages.
    @State private var image: CGImage?

    var body: some View {
        HStack(spacing: 16) {
            if qr != nil {
                // Place reservee des la construction : la section ne saute pas quand l'image arrive.
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                    }
                }
                .frame(width: 120, height: 120)
                .padding(8)
                .background(.white, in: .rect(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Code Matter de la sonde").font(.caption).foregroundStyle(.secondary)
                if let code {
                    Text(verbatim: CodeMatter.formater(code))
                        .font(.title3.monospacedDigit())
                        .textSelection(.enabled)
                }
                if !appairee {
                    Text("Dans Maison : + › Ajouter un accessoire › Plus d'options, puis ce code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: qr) { image = qr.flatMap(CodeMatter.imageQR) }
    }
}
