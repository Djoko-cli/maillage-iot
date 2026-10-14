import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// Fiche du noeud choisi : carte de verre en bas de la fenetre, sur toute sa largeur, en quatre colonnes cote a cote
/// (`ColonnesFiche`, moins dans une fenetre etroite ; reprise de Maillage Zigbee, 09/10) :
/// 1. identite : le nom, la description, la pastille du chef, l'etat, la pile, les adresses, et les boutons
///    « Renommer… » et « Placer dans une pièce… » ;
/// 2. role et parent : le role (routeur de bordure) ou le genre (appareil), ce que la sonde en sait (son parent et la
///    qualite du lien, avec sa source et son age), la partition et le prefixe ; puis le journal du noeud ;
/// 3. enfants : en pastilles, ceux dont il est le parent ;
/// 4. voisins radio, resumes (nombre par qualite, barre de repartition) ; un clic deplie leur liste en grille, sous
///    les colonnes. La carte est radio seulement : les liens entre routeurs TREL n'y sont pas, une ligne le dit.
/// Dessous, sur toute la largeur, les courbes de l'historique (`CourbesFiche`). Le contenu des colonnes est propre a
/// Thread ; les colonnes et leurs composants sont generiques (`ComposantsFiche`).
struct FicheNoeud: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.colorScheme) private var apparence
    /// Une capture ne rend pas un bouton en lien : elle dessine son texte.
    @Environment(\.capturePieces) private var capture
    /// Pieces choisies pour les noeuds que Maison ne place pas : la vue par pieces seule les donne.
    @Environment(PiecesChoisies.self) private var piecesChoisies: PiecesChoisies?
    /// Le noeud choisi, au-dessus des modules ; ce qui interroge Thread (instantane, sonde, journal, courbes) le lit par
    /// `cle`, la cle de Thread.
    let id: IdNoeud
    /// La scene du meme rendu (`EntreeScene`), avec ce dont elle est faite : la fiche y lit le maillage
    /// rapproche, et « Placer dans une piece… » le graphe, sans rien reconstruire ; nil sans reseau.
    let entree: EntreeScene?
    /// Heure de la fenetre du graphe (sa `TimelineView`, chaque minute ; la fin de la panne en demo) :
    /// les durees de la fiche (« vu il y a... ») suivent l'heure sans autre evenement.
    let instant: Date
    @Binding var aRenommer: NoeudChoisi?
    /// Choisit un autre noeud (la fiche d'un candidat, d'un enfant, d'un voisin).
    var choisir: (IdNoeud) -> Void = { _ in }
    var fermer: () -> Void
    /// La liste des voisins radio, depliee d'un clic ; repliee par defaut, et de nouveau a chaque autre noeud.
    @State private var voisinsDeplies = false

    private var deplies: Bool { voisinsDeplies }

    /// La cle du noeud pour Thread : la fiche n'ouvre que des noeuds Thread (`id.protocole`), le reste n'a pas de fiche ici.
    private var cle: String { id.cle }

    /// Les couleurs des qualites, celles de la legende (la fenetre reste sombre).
    private static let palette = Palette(sombre: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if Self.connu(cle, dans: surveillance, maillage: sonde) {
                ColonnesFiche {
                    colonneIdentite()
                    colonneRole()
                    colonneEnfants()
                    colonneVoisins()
                }
                // La place du bouton de fermeture, en haut a droite.
                .padding(.trailing, 30)
                if deplies, let m = sonde {
                    listeVoisins(m)
                }
            } else {
                Text("Ce nœud n'est plus visible.").foregroundStyle(.secondary)
            }
            if Self.courbesVisibles(dans: surveillance) {
                Divider().opacity(0.5)
                CourbesFiche(id: cle, instant: instant)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button {
                fermer()
            } label: {
                Image(systemName: "xmark")
            }
            .boutonDeFiche()
            .help("Fermer")
            .padding(12)
        }
        .modifier(FondDeFiche())
        .onChange(of: id) { voisinsDeplies = false }
    }

    /// Le noeud a une fiche : un routeur de bordure de l'instantane, un appareil connu, ou un noeud que la sonde seule
    /// connait.
    static func connu(_ id: String, dans surveillance: Surveillance, maillage: MaillageAffiche?) -> Bool {
        surveillance.thread.instantane?.routeur(id) != nil || surveillance.thread.appareil(id) != nil || maillage?.noeud(id) != nil
    }

    // MARK: Colonne 1 : identite

    private func colonneIdentite() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = surveillance.thread.instantane?.routeur(cle) {
                identiteRouteur(r)
            } else if let a = surveillance.thread.appareil(cle) {
                identiteAppareil(a)
            } else if let m = sonde, let n = m.noeud(cle) {
                identiteSonde(n)
            }
            boutonsIdentite
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Renommer… », « Placer dans une pièce… », et pour un appareil Thread que Maison ne nomme pas « Associer à un
    /// accessoire de Maison… » (« Dissocier » s'il l'est a la main), et « Identifier » pour un appareil relie a un
    /// accessoire de Maison (`BoutonIdentifier`), sous l'identite.
    private var boutonsIdentite: some View {
        RangeesFluides(espacement: 8, interligne: 6) {
            if Self.renommable(cle, dans: surveillance) {
                Button("Renommer…") { aRenommer = NoeudChoisi(id: id) }
                    .boutonDeFiche()
            }
            if let a = surveillance.thread.appareil(cle) {
                if surveillance.thread.associeALaMain(a) {
                    Button("Dissocier") { surveillance.thread.dissocier(cle) }
                        .boutonDeFiche()
                } else if MenuAssocier.propose(a, dans: surveillance) {
                    MenuAssocier(id: cle)
                }
                if let accessoire = surveillance.thread.accessoire(a) {
                    BoutonIdentifier(accessoire: accessoire)
                }
            }
            if let piecesChoisies, let entree,
               let placement = PiecesChoisies.placement(id, dans: surveillance, entree: entree) {
                MenuPlacer(placement: placement, domicile: surveillance.thread.noms.maison?.domicile ?? "",
                           choisies: piecesChoisies)
            }
        }
    }

    // MARK: Colonne 2 : role et parent

    private func colonneRole() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TitreColonne(titre: "Rôle et parent")
            if let r = surveillance.thread.instantane?.routeur(cle) {
                roleRouteur(r)
                lignesPartition(partition: r.partition, prefixe: r.prefixeOMR)
            } else if let a = surveillance.thread.appareil(cle) {
                let genre = genre(a)
                if !genre.isEmpty { Text(genre).foregroundStyle(.secondary) }
                if !a.fabriques.isEmpty {
                    Text("Fabriques : \(a.fabriques.count)").foregroundStyle(.secondary)
                }
                ligneSonde
                let verifie = surveillance.thread.verification(a.id, a: surveillance.maintenant) != nil
                lignesPartition(partition: surveillance.thread.partitionAffichee(a, verifie: verifie), prefixe: a.prefixe,
                                incertaine: surveillance.thread.instantane?.partitionIncertaine(a) == true)
            } else if let m = sonde, let n = m.noeud(cle) {
                ligneSonde
                Text(Self.explication(n)).font(.caption).foregroundStyle(.secondary)
            }
            journal
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Colonne 3 : enfants

    private func colonneEnfants() -> some View {
        let enfants = sonde.map { DependantFiche.trier(FicheThread.enfants(de: id, maillage: $0), nom: nomNoeud) } ?? []
        return VStack(alignment: .leading, spacing: 6) {
            TitreColonne(titre: "Enfants")
            if sonde == nil {
                Text(Self.texteSansSonde).font(.caption).foregroundStyle(.secondary)
            } else if sonde?.noeud(cle) == nil {
                Text(Self.textePasVuParLaSonde).font(.caption).foregroundStyle(.secondary)
            } else if enfants.isEmpty {
                Text("aucun").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(Self.ligneEnfants(enfants.count)).font(.caption).foregroundStyle(.secondary)
                RangeesFluides {
                    ForEach(enfants) { d in
                        PastilleNoeud(nom: nomNoeud(d.id), couleur: Self.palette.lienSonde(d.qualite),
                                      valeur: Self.valeurPastille(qualite: d.qualite)) {
                            choisir(d.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Colonne 4 : voisins radio

    private func colonneVoisins() -> some View {
        let voisins = sonde.map { FicheThread.voisins(de: id, maillage: $0) } ?? []
        let resume = ResumeVoisins(voisins)
        // Routeur ou enfant : ce que la sonde en sait ; un noeud qu'elle n'a pas (une autre partition, un reseau scinde)
        // n'est ni l'un ni l'autre pour elle.
        let routeur = sonde?.noeud(cle)?.genre == .routeur
        return VStack(alignment: .leading, spacing: 5) {
            TitreColonne(titre: "Voisins radio")
            if sonde == nil {
                Text(Self.texteSansSonde).font(.caption).foregroundStyle(.secondary)
            } else if sonde?.noeud(cle) == nil {
                Text(Self.textePasVuParLaSonde).font(.caption).foregroundStyle(.secondary)
            } else if !routeur {
                Text(Self.texteEnfantSeul).font(.caption).foregroundStyle(.secondary)
            } else if voisins.isEmpty {
                Text("aucun").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(Self.ligneResume(resume)).font(.caption)
                BarreRepartition(parts: resume.parts.map { (Self.palette.couleur($0.niveau), $0.nombre) })
                    .frame(maxWidth: 220)
                if capture {
                    etiquetteListe.foregroundStyle(.link)
                } else {
                    Button {
                        voisinsDeplies.toggle()
                    } label: {
                        etiquetteListe
                    }
                    .buttonStyle(.link)
                }
            }
            if routeur, Self.trel(cle, maillage: sonde, graphe: entree?.graphe, dans: surveillance) {
                Text(Self.texteTrel).font(.caption).foregroundStyle(.secondary)
            }
            if sonde?.jamaisEntendu(cle) == true {
                Text(Self.texteJamaisEntendu).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Afficher la liste » ou « Replier la liste », selon la liste des voisins.
    @ViewBuilder
    private var etiquetteListe: some View {
        if deplies {
            Label("Replier la liste", systemImage: "chevron.up").font(.caption)
        } else {
            Label("Afficher la liste", systemImage: "chevron.down").font(.caption)
        }
    }

    /// La liste des voisins radio, depliee sous les colonnes, en grille sur plusieurs colonnes : de la meilleure qualite
    /// a la plus faible, chacun avec son point de couleur et sa qualite ; la source et l'age de la mesure au survol ; un
    /// clic le choisit.
    private func listeVoisins(_ m: MaillageAffiche) -> some View {
        let voisins = ResumeVoisins.trier(FicheThread.voisins(de: id, maillage: m), nom: nomNoeud)
        return GrilleListe {
            ForEach(voisins) { v in
                Button {
                    choisir(v.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Self.palette.lienSonde(v.qualite)).frame(width: 7, height: 7)
                        Text(verbatim: nomNoeud(v.id)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.texteQualite(v.qualite)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Self.origineVoisin(v.id.cle, de: cle, maillage: m, instant: instant) ?? "")
            }
        }
    }

    /// Le noeud annonce TREL : son ExtMac (celle que la sonde lui connait, sinon celle du graphe) est dans l'instantane
    /// (`Instantane.trel`) ; ses liens avec les autres routeurs TREL ne sont pas sur la carte.
    static func trel(_ id: String, maillage: MaillageAffiche?, graphe: GrapheReseau?,
                     dans surveillance: Surveillance) -> Bool {
        guard let ext = maillage?.extMacs[id] ?? graphe?.noeud(IdNoeud(.thread, id))?.extMac else { return false }
        return surveillance.thread.instantane?.trel.contains(ext.uppercased()) == true
    }

    /// Ce que le point de couleur d'une pastille d'enfant dit a VoiceOver : « qualité du lien : bonne ».
    static func valeurPastille(qualite: Int?) -> String {
        String(localized: "qualité du lien : \(NiveauQualite(qualite).nom)")
    }

    /// « 4 enfants ».
    static func ligneEnfants(_ n: Int) -> String {
        n == 1 ? String(localized: "1 enfant") : String(localized: "\(n) enfants")
    }

    /// « 5 voisins · 2 bons · 2 moyens · 1 faible » (« · 2 inconnus ») : les niveaux absents n'y sont pas.
    static func ligneResume(_ r: ResumeVoisins) -> String {
        func compte(_ n: Int, un: String, plusieurs: String) -> String? {
            n == 0 ? nil : n == 1 ? un : plusieurs
        }
        let b = r.nombre(.bonne), m = r.nombre(.moyenne), f = r.nombre(.faible), i = r.nombre(.inconnue)
        return [r.total == 1 ? String(localized: "1 voisin") : String(localized: "\(r.total) voisins"),
                compte(b, un: String(localized: "1 bon"), plusieurs: String(localized: "\(b) bons")),
                compte(m, un: String(localized: "1 moyen"), plusieurs: String(localized: "\(m) moyens")),
                compte(f, un: String(localized: "1 faible"), plusieurs: String(localized: "\(f) faibles")),
                compte(i, un: String(localized: "1 inconnu"), plusieurs: String(localized: "\(i) inconnus"))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Sans maillage de la sonde, ni enfants ni voisins radio connus.
    static var texteSansSonde: String { String(localized: "connu seulement avec la sonde") }

    /// Un noeud que le maillage de la sonde n'a pas (une autre partition, un reseau scinde) : ni enfants ni voisins
    /// connus.
    static var textePasVuParLaSonde: String { String(localized: "pas vu par la sonde") }

    /// Un enfant (appareil qui ne route pas) n'a pas de voisins radio.
    static var texteEnfantSeul: String { String(localized: "un enfant ne parle qu'à son parent") }

    /// Un routeur qui annonce TREL : ses liens avec les autres routeurs TREL ne sont pas montres.
    static var texteTrel: String {
        String(localized: "liens par le réseau local (TREL) non montrés : la carte est radio seulement")
    }

    /// Le noeud est couronne : un chef de la scene du meme rendu (`EntreeScene.chefs`), routeur de
    /// bordure ou noeud que la sonde seule connait ; la fiche couronne les memes noeuds que la scene.
    static func couronne(_ id: IdNoeud, entree: EntreeScene?) -> Bool {
        entree?.chefs.contains(id) == true
    }

    /// Courbes de l'historique sous les colonnes, pour tout noeud, des que l'historique de la
    /// sonde a un releve (jamais en demo) : la fiche garde sa hauteur d'un noeud a l'autre.
    static func courbesVisibles(dans surveillance: Surveillance) -> Bool {
        !surveillance.thread.historique.isEmpty
    }

    /// « Renommer… » : le surnom est indexe par l'instance d'un routeur de l'instantane ou
    /// par l'id d'un appareil connu. Un noeud que la sonde seule connait n'a qu'un RLOC16,
    /// volatil : rien ne lirait son surnom.
    static func renommable(_ id: String, dans surveillance: Surveillance) -> Bool {
        surveillance.thread.instantane?.routeur(id) != nil || surveillance.thread.appareil(id) != nil
    }

    // MARK: Appareil

    @ViewBuilder
    private func identiteAppareil(_ a: Appareil) -> some View {
        let disparu = surveillance.thread.suivi.disparus[a.id] != nil
        // Trouve par la sonde alors qu'il n'annonce plus d'adresse : joignable.
        let verifie = surveillance.thread.verification(a.id, a: instant)
        let maison = surveillance.thread.accessoire(a)
        Text(surveillance.thread.nom(a)).font(.title3.weight(.semibold))
        let description = Self.ligneDescription(maison: maison, modeleHomeKit: a.hap?.modele)
        if !description.isEmpty {
            Text(description).foregroundStyle(.secondary)
        }
        if surveillance.thread.associeALaMain(a) {
            Text("associé à la main").font(.caption).foregroundStyle(.tertiary)
        }
        if Self.couronne(IdNoeud(.thread, a.id), entree: entree) {
            PastilleChef()
        }
        HStack(spacing: 6) {
            PointEtat(couleur: verifie != nil ? .green : couleur(a, disparu: disparu),
                      pulse: verifie != nil || (!disparu && a.etat == .joignable))
            Text(Self.texteEtat(a.etat, disparu: disparu, verifie: verifie != nil))
            if let verifie {
                Text("· \(Self.texteVerification(verifie, instant))").foregroundStyle(.secondary)
            } else if let vu = vuLe(a, disparu: disparu) {
                Text("· vu \(Self.relatif(vu, instant))").foregroundStyle(.secondary)
            }
        }
        if let b = maison?.batterie {
            HStack(spacing: 6) {
                Image(systemName: Self.symboleBatterie(b))
                    .foregroundStyle(b.faible ? orange : b.charge == .enCharge ? Color.green : Color.primary)
                Text(Self.ligneBatterie(b)).foregroundStyle(b.faible ? orange : Color.primary)
                if let releve = surveillance.thread.noms.maison?.date {
                    Text("· relevé \(Self.relatif(releve, instant))").foregroundStyle(.secondary)
                }
            }
        }
        ForEach(a.adresses.prefix(2), id: \.self) { ad in
            Text(ad.description).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Text(a.id).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
    }

    /// Piece, fabricant (sinon modele HomeKit), modele, et firmware quand Maison le donne.
    static func ligneDescription(maison: AccessoireMaison?, modeleHomeKit: String?) -> String {
        let firmware = maison?.firmware.flatMap { $0.isEmpty ? nil : String(localized: "firmware \($0)") }
        return [maison?.piece, maison?.fabricant ?? modeleHomeKit, maison?.modele, firmware]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Niveau, puis l'etat de charge ; faible, « batterie faible » (et « en
    /// charge » seulement) ; sans niveau, l'alerte : « batterie OK » seulement
    /// si l'accessoire le dit.
    static func ligneBatterie(_ b: BatterieMaison) -> String {
        var parties: [String] = []
        if let n = b.niveau {
            parties.append(String(localized: "\(n)\u{202F}%"))
            if b.faible { parties.append(String(localized: "batterie faible")) }
        } else if b.faible {
            parties.append(String(localized: "batterie faible"))
        } else if b.alerte == false {
            parties.append(String(localized: "batterie OK"))
        }
        switch b.charge {
        case .enCharge: parties.append(String(localized: "en charge"))
        case .horsCharge where !b.faible: parties.append(String(localized: "sur batterie"))
        case .nonRechargeable where !b.faible: parties.append(String(localized: "non rechargeable"))
        default: break
        }
        return parties.joined(separator: " · ")
    }

    /// Triangle si faible, eclair en charge, sinon le niveau par quart.
    static func symboleBatterie(_ b: BatterieMaison) -> String {
        if b.faible { return "exclamationmark.triangle.fill" }
        if b.charge == .enCharge { return "battery.100percent.bolt" }
        switch b.niveau ?? 100 {
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Orange de la batterie faible, assez fonce en mode clair pour se lire sur le verre pale.
    private var orange: Color { apparence == .dark ? .orange : Color(red: 0.72, green: 0.36, blue: 0) }

    /// Etat d'un appareil dans la fiche ; `verifie` : il n'annonce plus d'adresse (sans adresse, ou disparu), et la
    /// sonde l'a trouve (`SurveillanceThread.verification`).
    static func texteEtat(_ etat: EtatAppareil, disparu: Bool, verifie: Bool) -> String {
        if verifie { return String(localized: "joignable, adresse plus annoncée") }
        if disparu { return String(localized: "disparu") }
        switch etat {
        case .joignable: return String(localized: "joignable")
        case .partitionCoupee: return String(localized: "isolé (partition coupée)")
        case .sansAdresse: return String(localized: "adresse non annoncée")
        case .inconnu: return String(localized: "partition inconnue")
        }
    }

    /// « verifie par la sonde il y a 12 minutes » : l'age de la resolution qui a trouve l'appareil.
    static func texteVerification(_ d: Date, _ instant: Date) -> String {
        String(localized: "vérifié par la sonde \(relatif(d, instant))")
    }

    private func couleur(_ a: Appareil, disparu: Bool) -> Color {
        if disparu { return .red }
        switch a.etat {
        case .joignable: return .green
        case .partitionCoupee: return .orange
        case .sansAdresse: return .red
        case .inconnu: return .gray
        }
    }

    /// "il y a 12 secondes", "maintenant".
    static func relatif(_ d: Date, _ reference: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .full
        // L'heure de la fiche est un debut de minute (TimelineView de la fenetre) : une date plus
        // recente, d'un releve fait depuis, se lirait « dans 20 secondes ». Jamais dans le futur :
        // « maintenant » jusqu'a la minute suivante (la spec admet une minute de retard).
        return f.localizedString(for: d, relativeTo: max(d, reference))
    }

    /// Present : l'instantane integre (un releve vide ne compte pas) ; disparu : sa premiere absence.
    private func vuLe(_ a: Appareil, disparu: Bool) -> Date? {
        if disparu { return surveillance.evenements(de: IdNoeud(.thread, a.id)).first { $0.type == .appareilDisparu }?.date }
        return surveillance.thread.instantane?.date
    }

    private func genre(_ a: Appareil) -> String {
        var morceaux: [String] = []
        if !a.instances.isEmpty { morceaux.append("Matter") }
        if a.hap != nil { morceaux.append("HomeKit") }
        if a.endormi {
            if let sii = a.proprietes?.sii {
                morceaux.append(String(localized: "endormi (réveil \(sii / 1000) s)"))
            } else {
                morceaux.append(String(localized: "endormi"))
            }
        }
        return morceaux.joined(separator: " · ")
    }

    // MARK: Sonde

    /// Maillage de la sonde pour le reseau affiche : celui de la scene.
    private var sonde: MaillageAffiche? { entree?.maillage }

    /// Ce que la sonde sait du noeud : son RLOC16, son parent et la qualite du lien avec sa source et son age (enfant),
    /// ou ses nombres de voisins et d'enfants (routeur) (spec de la sonde tout-en-un, section 2.4).
    @ViewBuilder
    private var ligneSonde: some View {
        if let m = sonde, let n = m.noeud(cle) {
            Text(Self.ligneSonde(n, maillage: m, nom: nomThread, instant: instant)).foregroundStyle(.secondary)
        }
    }

    /// Noeud que seule la sonde connait (routeur de bordure muet sans identite, avec ses candidats ; enfant inconnu).
    @ViewBuilder
    private func identiteSonde(_ n: NoeudSonde) -> some View {
        Text(LibellesNoeuds.inconnu(n, noms: nomsRouteurs)).font(.title3.weight(.semibold))
        if Self.couronne(IdNoeud(.thread, n.id), entree: entree) {
            PastilleChef()
        }
        if !n.candidats.isEmpty {
            // Chaque candidat ouvre la fiche de son annonce, pas dessinee a part.
            HStack(spacing: 8) {
                Text("Candidats :")
                ForEach(n.candidats, id: \.self) { c in
                    let choix = Self.selection(candidat: c, dans: surveillance)
                    Button(nomsRouteurs[c] ?? c) {
                        if let choix { choisir(IdNoeud(.thread, choix)) }
                    }
                    .buttonStyle(.link)
                    .disabled(choix == nil)
                }
            }
        }
    }

    /// Noeud a choisir pour un candidat : son annonce, si l'instantane la connait encore (sa
    /// fiche : role, adresses, journal, « Renommer… ») ; nil sinon.
    static func selection(candidat: String, dans surveillance: Surveillance) -> String? {
        surveillance.thread.instantane?.routeur(candidat) != nil ? candidat : nil
    }

    /// Ce que la sonde sait d'un noeud qu'elle seule connait.
    static func explication(_ n: NoeudSonde) -> String {
        switch n.genre {
        case .routeur where !n.candidats.isEmpty:
            String(localized: "Vu par la sonde sans son identité : sans doute l'une de ces annonces du réseau local, qu'aucun nœud ne reprend.")
        case .routeur:
            String(localized: "Vu par la sonde, sans annonce reconnue sur le réseau local.")
        case .enfant:
            String(localized: "Vu par la sonde : son ExtMac ne correspond à aucun appareil annoncé.")
        }
    }

    /// Fiche d'un routeur de bordure reconnu par elimination (`NoeudSonde.deduit`).
    static var texteElimination: String {
        String(localized: "Reconnu par élimination : seul routeur de bordure sans identité, seule annonce restante.")
    }

    /// Nom affiche de chaque routeur de bordure du reseau affiche, par instance (candidats d'un
    /// routeur de bordure non identifie).
    private var nomsRouteurs: [String: String] {
        surveillance.thread.reseau.map(surveillance.thread.nomsRouteurs) ?? [:]
    }

    /// Nom d'un noeud du graphe : routeur de bordure, appareil, ou noeud de la sonde.
    private func nomNoeud(_ id: IdNoeud) -> String { nomThread(id.cle) }

    /// Nom d'un noeud par sa cle Thread (les liens du maillage de la sonde parlent en cles) ; a defaut, la cle.
    private func nomThread(_ cle: String) -> String {
        surveillance.thread.nomNoeud(cle, maillage: sonde) ?? cle
    }

    /// « RLOC16 5004 · parent HomePod bureau, qualite 3 · diagnostic » ; un enfant resolu sous un routeur Apple, dont le
    /// RLOC16 est invente (`EnfantMaillage.bitInvente`), sans lui : « parent HomePod bureau, qualite inconnue · resolu
    /// il y a 12 minutes · acces au canal refuses : 0,7 % » ; « RLOC16 5000 · voisins : 4 · enfants : 2 ».
    static func ligneSonde(_ n: NoeudSonde, maillage m: MaillageAffiche, nom: (String) -> String,
                           instant: Date = .now) -> String {
        let rloc = String(format: "%04X", n.rloc16)
        switch n.genre {
        case .enfant:
            guard let p = m.parent(de: n.id) else {
                // Le RLOC16 invente d'un enfant resolu n'est jamais affiche.
                return n.rloc16 & EnfantMaillage.bitInvente == 0
                    ? String(localized: "RLOC16 \(rloc)") : String(localized: "Non identifié")
            }
            let lien = m.liens.first { $0.genre == .parent && $0.de == n.id }
            let q = lien?.qualite
            let ligne = n.rloc16 & EnfantMaillage.bitInvente == 0
                ? String(localized: "RLOC16 \(rloc) · parent \(nom(p)), \(texteQualite(q))")
                : String(localized: "parent \(nom(p)), \(texteQualite(q))")
            return ([ligne] + (lien?.origine.map { [texteOrigine($0, instant)] } ?? [])).joined(separator: " · ")
        case .routeur:
            let voisins = m.liens.filter { $0.genre == .radio && ($0.de == n.id || $0.vers == n.id) }.count
            let enfants = m.liens.filter { $0.genre == .parent && $0.vers == n.id }.count
            return String(localized: "RLOC16 \(rloc) · voisins : \(voisins) · enfants : \(enfants)")
        }
    }

    /// « qualite 3 » ; « qualite inconnue » sous un routeur muet.
    static func texteQualite(_ q: Int?) -> String {
        q.map { String(localized: "qualité \($0)") } ?? String(localized: "qualité inconnue")
    }

    /// La qualite, la source et l'age du lien radio entre `id` et son voisin `voisin` : « qualite 3 · entendu il y a 3
    /// minutes » ; la qualite seule pour un lien sans source (maillage de demo) ; nil sans lien.
    static func origineVoisin(_ voisin: String, de id: String, maillage m: MaillageAffiche, instant: Date) -> String? {
        guard let l = m.liens.first(where: { $0.genre == .radio && Set([$0.de, $0.vers]) == [id, voisin] }) else {
            return nil
        }
        return ([texteQualite(l.qualite)] + (l.origine.map { [texteOrigine($0, instant)] } ?? [])).joined(separator: " · ")
    }

    /// Source et age d'un lien : « diagnostic », « entendu il y a 3 minutes », « resolu il y a 12 minutes »,
    /// « acces au canal refuses : 0,7 % », « donne par la sonde » ; plusieurs, separes par « · ».
    static func texteOrigine(_ o: OrigineLien, _ instant: Date) -> String {
        var parties: [String] = []
        if o.sonde { parties.append(String(localized: "donné par la sonde")) }
        if o.diagnostic { parties.append(String(localized: "diagnostic")) }
        if let d = o.entendu { parties.append(String(localized: "entendu \(relatif(d, instant))")) }
        if let d = o.resolu { parties.append(String(localized: "résolu \(relatif(d, instant))")) }
        if let e = o.echecs { parties.append(texteAccesCanal(e)) }
        return parties.joined(separator: " · ")
    }

    /// « acces au canal refuses : 0,7 % » : les acces au canal refuses a l'enfant rapportes a ses envois, au dixieme de
    /// pour cent, a titre d'information (`AccesCanal` : ce n'est pas la qualite de son lien).
    static func texteAccesCanal(_ taux: Double) -> String {
        String(localized: "accès au canal refusés : \(taux.formatted(.percent.precision(.fractionLength(1))))")
    }

    /// Un routeur muet que la sonde n'entend pas (`MaillageAffiche.jamaisEntendu`).
    static var texteJamaisEntendu: String {
        String(localized: "jamais entendu par la sonde ; liens vus seulement par ses voisins")
    }

    // MARK: Routeur

    @ViewBuilder
    private func identiteRouteur(_ r: RouteurBordure) -> some View {
        Text(surveillance.thread.nom(r)).font(.title3.weight(.semibold))
        let description = [r.fabricant, r.modele, r.versionThread.map { "Thread \($0)" }].compactMap { $0 }
            .joined(separator: " · ")
        if !description.isEmpty {
            Text(description).foregroundStyle(.secondary)
        }
        if Self.couronne(IdNoeud(.thread, r.instance), entree: entree) {
            PastilleChef()
        }
        HStack(spacing: 6) {
            Circle().fill(.blue).frame(width: 8, height: 8)
            Text(role(r))
            if let bbr = bbr(r) { Text("· \(bbr)").foregroundStyle(.secondary) }
        }
        ForEach(r.adressesLien, id: \.self) { ad in
            Text(ad.description).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func roleRouteur(_ r: RouteurBordure) -> some View {
        Text("Routeur de bordure").foregroundStyle(.secondary)
        ligneSonde
        if sonde?.noeud(r.instance)?.deduit == true {
            Text(Self.texteElimination).font(.caption).foregroundStyle(.secondary)
        }
        if let nn = r.nomReseau { Text("Réseau \(nn)").foregroundStyle(.secondary) }
    }

    private func role(_ r: RouteurBordure) -> String {
        guard let role = r.role else { return String(localized: "rôle inconnu (Thread \(r.versionThread ?? "?"))") }
        return TexteEvenement.role(role.rawValue)
    }

    private func bbr(_ r: RouteurBordure) -> String? {
        guard let e = r.etat, e.bbrActif else { return nil }
        return e.bbrPrimaire ? String(localized: "BBR primaire") : String(localized: "BBR actif")
    }

    // MARK: Partition et journal du noeud

    /// `incertaine` : partition d'un appareil tiree d'un prefixe partage (voir `Instantane.partitionIncertaine`).
    @ViewBuilder
    private func lignesPartition(partition: String?, prefixe: PrefixeIPv6?, incertaine: Bool = false) -> some View {
        if let partition {
            if incertaine {
                Text("Partition \(partition) (incertaine : préfixe partagé)").foregroundStyle(.secondary)
            } else {
                Text("Partition \(partition)").foregroundStyle(.secondary)
            }
        }
        if let prefixe {
            Text(prefixe.description).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    /// Le journal du noeud, sous un titre « Journal » : ses dernieres lignes, ses changements de parent d'une meme heure
    /// regroupes (`Surveillance.lignesJournal`).
    @ViewBuilder
    private var journal: some View {
        let lignes = surveillance.lignesJournal(de: id)
        if !lignes.isEmpty {
            TitreColonne(titre: "Journal")
                .padding(.top, 6)
            ForEach(lignes) { ligne in ligneJournal(ligne) }
        }
    }

    /// Une ligne du journal du noeud : un evenement isole sur une ligne ; les changements de parent d'une meme heure en
    /// une seule, repliee (plage horaire, nombre de changements, relais), a deplier.
    @ViewBuilder
    private func ligneJournal(_ ligne: LigneJournal) -> some View {
        switch ligne {
        case .parents(let groupe), .chemins(let groupe):
            LigneChangements(groupe: groupe) {
                Text("\(TexteEvenement.plage(groupe)) · \(TexteEvenement.changements(ligne))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .evenement, .pertes:
            ForEach(ligne.evenements) { e in
                Text("\(TexteEvenement.quand(e)) · \(TexteEvenement.titre(e))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    /// Bouton de verre de la fiche ; dans une capture, qui ne rend pas le verre, celui des capsules.
    func boutonDeFiche() -> some View {
        modifier(BoutonDeFiche())
    }
}

private struct BoutonDeFiche: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content.buttonStyle(StyleBoutonCapsule())
        } else {
            content.buttonStyle(.glass)
        }
    }
}

/// Fond de la fiche : du verre aux coins de 22 pt (le Liquid Glass de macOS). Une capture, qui ne rend pas
/// le verre, dessine a sa place un fond proche de celui de la maquette de la fiche (rgba(40, 48, 72, 0,40),
/// filet de 0,5 pt blanc a 0,22, ombre noire a 0,4), avec deux ecarts : l'ombre est posee sur ce fond
/// translucide, donc multipliee par son opacite (0,4) ; et l'ombre interne de la maquette (un lisere clair
/// d'un point en haut) n'y est pas. Ce dessin ne sert qu'aux captures.
private struct FondDeFiche: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content
                .background(RoundedRectangle(cornerRadius: 22).fill(fondVerreCapture.opacity(0.4))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 8))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}

/// « 👑 Chef du reseau Thread, elu automatiquement », sous le nom d'un noeud couronne (polissage B,
/// section 3 ; maquette de la fiche, `.chef`) : 10,5 pt, marges de 2 x 8 pt, en capsule, sur une ligne : une colonne
/// de la fiche plus etroite que la pastille (233 pt a la largeur par defaut de la fenetre) ne la fait pas passer a la
/// ligne, son texte se reduit pour y tenir, jusqu'a 70 % (la plus etroite des quatre colonnes fait 190 pt ; fiche en
/// quatre colonnes, 09/10).
struct PastilleChef: View {
    var body: some View {
        Text("👑 Chef du réseau Thread, élu automatiquement")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.texteChef)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.jauneChef.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Palette.jauneChef.opacity(0.5), lineWidth: 0.5))
    }
}

/// Point d'etat de la fiche. Joignable, il pulse doucement : un halo s'elargit
/// et s'efface toutes les 2 s, sauf si « Reduire les animations » est active.
private struct PointEtat: View {
    let couleur: Color
    let pulse: Bool
    @Environment(\.accessibilityReduceMotion) private var reduire

    var body: some View {
        Circle().fill(couleur).frame(width: 8, height: 8)
            .background {
                if pulse && !reduire {
                    Circle().fill(couleur)
                        .phaseAnimator([false, true]) { halo, etendu in
                            halo.scaleEffect(etendu ? 2.6 : 1).opacity(etendu ? 0 : 0.55)
                        } animation: { etendu in
                            etendu ? .easeOut(duration: 2) : nil
                        }
                }
            }
    }
}
