import MaillageCoeur
import ProtocoleZigbee
import SwiftUI

/// Le contenu de la fiche d'un noeud Zigbee (la coque, `FicheNoeud`, donne le cadre, le bouton de fermeture et les courbes
/// de l'historique), en quatre colonnes cote a cote (`ColonnesFiche`, moins dans une fenetre etroite) :
/// 1. identite : le nom, la piece, la marque, le modele, le firmware, l'origine du nom, l'etat, le role (endormi d'apres
///    `ecoute`), la pile, les adresses (longue et courte, IEEE), et les boutons « Renommer… », « Identifier » (l'appareil
///    clignote, par le pont Hue : seulement pour un appareil que le pont connait) et « Placer dans une pièce… » ;
/// 2. chemin : vers le pont (direct, ou via son prochain saut, en sauts ; suppose ; l'age de la route), le parent d'un
///    appareil final (ou son parent d'avant), le nombre de routeurs qui parlent directement au pont ; puis le journal
///    du noeud (ses changements de parent ou de chemin d'une meme heure en une ligne, a deplier) ;
/// 3. dependants : en pastilles, les routeurs qui passent par lui et les appareils dont il est le parent ;
/// 4. voisins entendus, resumes (nombre par qualite, barre de repartition, date des qualites) ; un clic deplie leur
///    liste complete en grille, sous les colonnes.
/// Le contenu des colonnes est propre a Zigbee (qualite en LQI) ; les colonnes et leurs composants sont generiques
/// (`ComposantsFiche`). Reprise de la fiche de l'app de Maillage Zigbee ; ce que la fiche de Thread a en commun
/// (`ligneBatterie`, `symboleBatterie`, `relatif`, `couronne`) reste dans `FicheNoeud`.
struct FicheNoeudZigbee: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.colorScheme) private var apparence
    /// Une capture ne rend pas un bouton en lien : elle dessine son texte.
    @Environment(\.capturePieces) private var capture
    /// Pieces choisies pour les noeuds que le pont ne place pas : la vue par pieces seule les donne.
    @Environment(PiecesChoisies.self) private var piecesChoisies: PiecesChoisies?
    /// Le pont Hue : « Identifier » passe par lui. nil dans les vues de test sans pont.
    @Environment(NomsPont.self) private var nomsPont: NomsPont?
    /// Le demon Passeur Noms : « Identifier par Maison » passe par lui. nil dans les vues de test sans demon.
    @Environment(NomsPasseur.self) private var nomsPasseur: NomsPasseur?
    /// Le noeud choisi, au-dessus des modules ; ce qui interroge Zigbee (pont, sonde, journal, courbes) le lit par `cle`,
    /// son adresse longue. Un noeud d'un autre protocole n'a pas cette fiche (`FicheNoeud` choisit par `id.protocole`).
    let id: IdNoeud
    /// La scene du meme rendu (`EntreeScene`), avec ce dont elle est faite : la fiche y lit le maillage, et « Placer
    /// dans une piece… » le graphe, sans rien reconstruire ; nil sans reseau.
    let entree: EntreeScene?
    /// Heure de la fenetre du graphe (sa `TimelineView`, chaque minute ; la fin de la demo en demo) : les durees de
    /// la fiche (« releve il y a... ») suivent l'heure sans autre evenement.
    let instant: Date
    @Binding var aRenommer: NoeudChoisi?
    /// L'adresse longue du noeud : sa cle Zigbee.
    private var cle: String { id.cle }
    /// Choisit un autre noeud (un dependant, un voisin).
    var choisir: (IdNoeud) -> Void = { _ in }
    /// La liste des voisins entendus depliee d'office (captures) ; sinon, au clic.
    var listeDepliee = false
    /// Les lignes de changements regroupes du journal depliees d'office (captures) ; sinon, repliees, au clic.
    var changementsDeplies = false
    /// La liste des voisins entendus, depliee d'un clic ; repliee par defaut, et de nouveau a chaque autre noeud.
    @State private var voisinsDeplies = false

    private var deplies: Bool { listeDepliee || voisinsDeplies }

    /// Les couleurs des qualites, celles de la legende (la fenetre reste sombre).
    private static let palette = Palette(sombre: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let n = entree?.graphe.noeud(id) {
                ColonnesFiche {
                    colonneIdentite(n)
                    colonneChemin()
                    colonneDependants()
                    colonneVoisins()
                }
                // La place du bouton de fermeture, en haut a droite.
                .padding(.trailing, 30)
                if deplies, let m = entree?.maillageZigbee {
                    listeVoisins(m)
                }
            } else {
                Text("Ce nœud n'est plus visible.").foregroundStyle(.secondary)
            }
        }
        .onChange(of: id) { voisinsDeplies = false }
    }

    /// « Renommer… » : tout noeud du graphe, dont le surnom est garde sous son adresse longue ; pas un noeud sans
    /// adresse longue (cle provisoire).
    static func renommable(_ id: IdNoeud, entree: EntreeScene?) -> Bool {
        id.protocole == .zigbee && entree?.graphe.noeud(id) != nil && NoeudZigbee.cleConnue(id.cle)
    }

    // MARK: Colonne 1 : identite

    private func colonneIdentite(_ n: GrapheReseau.Noeud) -> some View {
        let a = entree?.appareils[id]
        let accessoire = surveillance.zigbee.accessoire(cle)
        let m = entree?.maillageZigbee
        let noeud = m?.noeud(cle)
        return VStack(alignment: .leading, spacing: 4) {
            Text(surveillance.zigbee.nom(cle)).font(.title3.weight(.semibold))
            let description = Self.ligneDescription(maison: accessoire)
            if !description.isEmpty {
                Text(description).foregroundStyle(.secondary)
            }
            if let origine = Self.ligneOrigine(accessoire) {
                Text(origine).font(.caption).foregroundStyle(.secondary)
            }
            if FicheNoeud.couronne(id, entree: entree) {
                PastilleChef(protocole: .zigbee)
            }
            HStack(spacing: 6) {
                let etat = Self.etat(a, inconnu: n.inconnu, sonde: cle == m?.sonde)
                PointEtat(couleur: Self.couleur(a?.etat, inconnu: n.inconnu), pulse: a?.etat == .joignable)
                Text(etat)
                Text(verbatim: "· " + Self.texteRole(noeud?.type, endormi: a?.endormi == true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let b = accessoire?.batterie {
                HStack(spacing: 6) {
                    Image(systemName: FicheNoeud.symboleBatterie(b))
                        .foregroundStyle(b.faible ? orange : b.charge == .enCharge ? Color.green : Color.primary)
                    Text(FicheNoeud.ligneBatterie(b)).foregroundStyle(b.faible ? orange : Color.primary)
                    if let releve = surveillance.zigbee.noms.maison?.date {
                        Text("· relevé \(FicheNoeud.relatif(releve, instant))").foregroundStyle(.secondary)
                    }
                }
            }
            // Les adresses, sur une ligne si elle tient.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { adresses(noeud?.court) }
                VStack(alignment: .leading, spacing: 4) { adresses(noeud?.court) }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if Self.renommable(id, entree: entree) {
                    Button("Renommer…") { aRenommer = NoeudChoisi(id: id) }
                        .boutonDeFiche()
                }
                if let nomsPont, nomsPont.peutIdentifier(ieee: cle) {
                    BoutonIdentifierHue(enCours: nomsPont.identification(ieee: cle) == .enCours) {
                        nomsPont.identifier(ieee: cle)
                    }
                }
                // Par Maison : toujours offert pour un appareil du pont, grise tant qu'il n'a pas ete retrouve dans Maison
                // (son `idMaison`) ou que le demon n'est pas connecte. Les deux boutons coexistent.
                if Self.proposeIdentifierParMaison(accessoire) {
                    BoutonIdentifierMaison(passeur: nomsPasseur, accessoire: accessoire?.idMaison)
                }
                if let piecesChoisies, let entree,
                   let placement = PiecesChoisies.placement(id, dans: surveillance, entree: entree) {
                    MenuPlacer(placement: placement, domicile: surveillance.zigbee.noms.maison?.domicile ?? "",
                               choisies: piecesChoisies)
                }
            }
            .padding(.top, 4)
            if let nomsPont, case .erreur(let message)? = nomsPont.identification(ieee: cle) {
                Text(message).font(.caption).foregroundStyle(orange).fixedSize(horizontal: false, vertical: true)
            }
            if let nomsPasseur, let texte = BoutonIdentifierMaison.texte(nomsPasseur.identification,
                                                                         accessoire: accessoire?.idMaison) {
                Text(texte).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colonneDuChef(FicheNoeud.couronne(id, entree: entree))
    }

    /// L'adresse longue, selectionnable, puis l'adresse courte.
    @ViewBuilder
    private func adresses(_ court: UInt16?) -> some View {
        Text(verbatim: cle).textSelection(.enabled).fixedSize()
        if let court {
            Text(Self.texteCourt(court)).fixedSize()
        }
    }

    // MARK: Colonne 2 : chemin

    private func colonneChemin() -> some View {
        let lignes = entree?.maillageZigbee.map { Self.lignesChemin(cle, maillage: $0, nom: surveillance.zigbee.nom, maintenant: instant) }
            ?? []
        let journal = surveillance.lignesJournal(de: id)
        return VStack(alignment: .leading, spacing: 4) {
            TitreColonne(titre: "Chemin")
            if lignes.isEmpty {
                Text("aucun chemin connu").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(lignes, id: \.self) { ligne in
                Text(ligne).font(.caption)
            }
            if !journal.isEmpty {
                TitreColonne(titre: "Journal").padding(.top, 8)
                ForEach(journal) { ligne in ligneJournal(ligne) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Une ligne du journal du noeud : un evenement isole sur une ligne ; les changements de parent ou de chemin d'une
    /// meme heure en une seule, repliee (plage horaire, nombre de changements, relais), a deplier.
    @ViewBuilder
    private func ligneJournal(_ ligne: LigneJournal) -> some View {
        switch ligne {
        case .parents(let groupe), .chemins(let groupe):
            LigneChangements(groupe: groupe, deplie: changementsDeplies) {
                Text("\(TexteEvenementZigbee.plage(groupe)) · \(TexteEvenementZigbee.changements(ligne))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .evenement, .pertes:
            ForEach(ligne.evenements) { e in
                Text("\(TexteEvenementZigbee.quand(e)) · \(TexteEvenementZigbee.titre(e))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Colonne 3 : dependants

    private func colonneDependants() -> some View {
        let dependants = entree?.maillageZigbee.map {
            DependantFiche.trier(FicheZigbee.dependants(de: id, maillage: $0), nom: { surveillance.zigbee.nom($0.cle) })
        } ?? []
        return VStack(alignment: .leading, spacing: 6) {
            TitreColonne(titre: "Dépendants")
            if dependants.isEmpty {
                texteAucun(vu: Self.vuParLaSonde(cle, maillage: entree?.maillageZigbee))
            } else {
                Text(Self.ligneDependants(dependants)).font(.caption).foregroundStyle(.secondary)
                RangeesFluides {
                    ForEach(dependants) { d in
                        PastilleNoeud(nom: surveillance.zigbee.nom(d.id.cle), couleur: Self.palette.lienSonde(d.qualite, protocole: .zigbee),
                                      valeur: Self.valeurPastille(qualite: d.qualite)) {
                            choisir(d.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Colonne 4 : voisins entendus

    private func colonneVoisins() -> some View {
        let m = entree?.maillageZigbee
        let voisins = m.map { FicheZigbee.voisins(de: id, maillage: $0) } ?? []
        let resume = ResumeVoisins(voisins)
        return VStack(alignment: .leading, spacing: 5) {
            TitreColonne(titre: "Voisins entendus")
            if voisins.isEmpty {
                texteAucun(vu: Self.vuParLaSonde(cle, maillage: m))
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
            if let m, m.noeud(cle) != nil, !voisins.isEmpty || m.noeud(cle)?.route == true {
                Text(Self.ligneQualites(FicheZigbee.dateQualites(m))).font(.caption).foregroundStyle(.secondary)
            }
            if let m {
                ForEach(Self.lignesTable(cle, maillage: m), id: \.self) { ligne in
                    Text(ligne).font(.caption).foregroundStyle(.secondary)
                }
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

    /// La liste complete des voisins entendus, depliee sous les colonnes, en grille sur plusieurs colonnes : de la
    /// meilleure qualite a la plus faible, chacun avec son point de couleur et « LQI 230 / 224 » (le noeud, puis le
    /// voisin) ; un clic le choisit.
    private func listeVoisins(_ m: MaillageZigbee) -> some View {
        let voisins = ResumeVoisins.trier(FicheZigbee.voisins(de: id, maillage: m), nom: { surveillance.zigbee.nom($0.cle) })
        return GrilleListe {
            ForEach(voisins) { v in
                Button {
                    choisir(v.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Self.palette.lienSonde(v.qualite, protocole: .zigbee)).frame(width: 7, height: 7)
                        Text(verbatim: surveillance.zigbee.nom(v.id.cle)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.texteLQIs(v)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Textes des colonnes

    /// La colonne du chemin : pour le pont, combien de routeurs lui parlent directement ; pour un appareil final, son
    /// parent (ou son parent d'avant, avec son age), puis son chemin vers le pont ; pour un routeur, son chemin vers le
    /// pont et l'age de sa route.
    static func lignesChemin(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String,
                             maintenant: Date) -> [String] {
        guard let n = m.noeud(id) else { return [] }
        if n.type == .coordinateur { return [ligneRouteursDirects(FicheZigbee.routeursDirects(m))] }
        var lignes: [String] = []
        if !n.route, let p = ligneParent(id, maillage: m, nom: nom, maintenant: maintenant) { lignes.append(p) }
        lignes += lignesVersPont(id, maillage: m, nom: nom)
        if let age = ligneAgeChemin(id, maillage: m, maintenant: maintenant) { lignes.append(age) }
        return lignes
    }

    /// « 20 routeurs lui parlent directement » (le pont).
    static func ligneRouteursDirects(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "aucun routeur ne lui parle directement")
        case 1: String(localized: "1 routeur lui parle directement")
        default: String(localized: "\(n) routeurs lui parlent directement")
        }
    }

    /// Le parent d'un appareil final, avec la qualite du lien et son LQI ; le parent d'avant (`LienParent.dAvant`,
    /// absent des dernieres tables) avec son age, a `maintenant` (par defaut la date du maillage) : « parent connu il
    /// y a 40 min : Lampe bureau ». Nil sans parent.
    static func ligneParent(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String,
                            maintenant: Date? = nil) -> String? {
        guard let p = m.parent(de: id) else { return nil }
        if p.dAvant, let d = p.date {
            let age = FicheNoeud.relatif(d, maintenant ?? m.date, unites: .short)
            return String(localized: "parent connu \(age) : \(nom(p.parent))")
        }
        return String(localized: "parent \(nom(p.parent)), \(texteQualite(p.qualite))\(texteLQI(p.lqi))")
    }

    /// Ce que la sonde dit de la table d'un routeur : muet a deux tournees, ou non lue a celle-ci.
    static func lignesTable(_ id: String, maillage m: MaillageZigbee) -> [String] {
        guard let n = m.noeud(id) else { return [] }
        if n.muet { return [String(localized: "muet : sans réponse à deux tournées de suite")] }
        if n.route && n.tableNonLue { return [String(localized: "table non lue : liens vus seulement par ses voisins")] }
        return []
    }

    /// « 3 routeurs · 2 appareils » : le compte des dependants.
    static func ligneDependants(_ d: [DependantFiche]) -> String {
        let routeurs = d.count(where: \.routeur), appareils = d.count - routeurs
        return [routeurs == 0 ? nil : routeurs == 1 ? String(localized: "1 routeur") : String(localized: "\(routeurs) routeurs"),
                appareils == 0 ? nil : appareils == 1 ? String(localized: "1 appareil")
                    : String(localized: "\(appareils) appareils")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// « 28 voisins · 6 bons · 9 moyens · 13 faibles » (« · 2 inconnus ») : les niveaux absents n'y sont pas.
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

    /// « LQI 230 / 224 » : le LQI que le noeud mesure, puis celui du voisin ; « ? » pour un sens inconnu.
    static func texteLQIs(_ v: VoisinFiche) -> String {
        String(localized: "LQI \(texteLQI(v.lqiIci, seul: true)) / \(texteLQI(v.lqiLa, seul: true))")
    }

    /// L'appareil n'a pas ete retrouve dans Maison (`FusionNoms`) : son nom et sa piece sont ceux de l'app Hue. Rien
    /// quand il l'a ete, ni sans releve de Maison.
    static func ligneOrigine(_ a: AppareilPont?) -> String? {
        a?.origine == .pont ? String(localized: "nom de l'app Hue (pas trouvé dans Maison)") : nil
    }

    /// Piece, fabricant, modele, et firmware quand le pont le donne.
    static func ligneDescription(maison: AppareilPont?) -> String {
        let firmware = maison?.firmware.flatMap { $0.isEmpty ? nil : String(localized: "firmware \($0)") }
        return [maison?.piece, maison?.fabricant, maison?.modele, firmware].compactMap { $0 }.joined(separator: " · ")
    }

    /// « Coordinateur (le pont) », « Routeur », « Appareil final » (« · endormi ») ; « Rôle inconnu » hors maillage.
    static func texteRole(_ t: TypeNoeud?, endormi: Bool = false) -> String {
        let role = switch t {
        case .coordinateur?: String(localized: "Coordinateur (le pont)")
        case .routeur?: String(localized: "Routeur")
        case .final?: String(localized: "Appareil final")
        case .inconnu?, nil: String(localized: "Rôle inconnu")
        }
        return endormi ? String(localized: "\(role) · endormi") : role
    }

    /// « adresse courte 1A2B ».
    static func texteCourt(_ court: UInt16) -> String {
        String(localized: "adresse courte \(String(format: "%04X", court))")
    }

    /// « qualite 3 » ; « qualite inconnue » sans mesure.
    static func texteQualite(_ q: Int?) -> String {
        q.map { String(localized: "qualité \($0)") } ?? String(localized: "qualité inconnue")
    }

    /// La sonde a vu le noeud : il est dans le maillage qu'elle a releve. Un appareil que seuls le pont ou Maison
    /// connaissent n'y est pas : ses dependants et ses voisins ne sont pas « aucun », la sonde ne les connait pas.
    static func vuParLaSonde(_ id: String, maillage: MaillageZigbee?) -> Bool { maillage?.noeud(id) != nil }

    /// Une colonne vide : « aucun » si la sonde a vu le noeud (il n'a ni dependant ni voisin), « pas vu par la sonde »
    /// sinon.
    @ViewBuilder
    private func texteAucun(vu: Bool) -> some View {
        if vu {
            Text("aucun").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("pas vu par la sonde").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Ce que le point de couleur d'une pastille de dependant dit a VoiceOver : « qualité du lien : bonne ».
    static func valeurPastille(qualite: Int?) -> String {
        String(localized: "qualité du lien : \(NiveauQualite(qualite).nom)")
    }

    /// Un LQI : « 182 » seul, « ? » inconnu ; sinon « (LQI 182) », rien d'inconnu.
    static func texteLQI(_ lqi: Int?, seul: Bool = false) -> String {
        if seul { return lqi.map(String.init) ?? "?" }
        return lqi.map { " (LQI \($0))" } ?? ""
    }

    /// Le chemin d'un noeud vers le pont : « vers le pont : direct » quand son prochain saut est le pont ; sinon
    /// « vers le pont : via Plafonnier salon · 3 sauts » (le prochain saut : le chemin d'un routeur, le parent d'un
    /// appareil final ; les sauts jusqu'au pont), ou « … · chemin incomplet » (une boucle, ou un saut sans chemin) ;
    /// puis « chemin supposé (aucune route active vers le pont) » le cas echeant. Rien pour le pont, ni sans chemin.
    static func lignesVersPont(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String) -> [String] {
        guard m.noeud(id)?.type != .coordinateur, let prochain = m.prochainSaut(de: id) else { return [] }
        var lignes: [String] = []
        if prochain == m.coordinateur?.ieee {
            lignes.append(String(localized: "vers le pont : direct"))
        } else if let n = m.sauts(de: id) {
            lignes.append(String(localized: "vers le pont : via \(nom(prochain)) · \(n) sauts"))
        } else {
            lignes.append(String(localized: "vers le pont : via \(nom(prochain)) · chemin incomplet"))
        }
        if m.chemin(de: id)?.suppose == true {
            lignes.append(String(localized: "chemin supposé (aucune route active vers le pont)"))
        }
        return lignes
    }

    /// L'age du chemin lu d'un routeur (sa route vers le pont, lue a une tournee qui peut etre d'avant : les routes des
    /// routeurs sont lues en plusieurs passes) : « chemin lu il y a 12 min » ; nil pour un chemin suppose ou sans date.
    static func ligneAgeChemin(_ id: String, maillage m: MaillageZigbee, maintenant: Date) -> String? {
        guard let c = m.chemin(de: id), !c.suppose, let d = c.date else { return nil }
        return String(localized: "chemin lu \(FicheNoeud.relatif(d, maintenant, unites: .short))")
    }

    /// La date des tables de voisins d'ou viennent les qualites : « qualités du 08/10 à 14:05 ».
    static func ligneQualites(_ d: Date) -> String {
        let jour = d.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
        let heure = d.formatted(date: .omitted, time: .shortened)
        return String(localized: "qualités du \(jour) à \(heure)")
    }

    /// Etat d'un noeud : celui de son appareil ; « inconnu du pont » pour un noeud que le pont ne connait pas ; « la
    /// sonde » pour elle.
    static func etat(_ a: AppareilAffiche?, inconnu: Bool, sonde: Bool) -> String {
        if sonde { return String(localized: "la sonde") }
        if inconnu { return String(localized: "inconnu du pont") }
        switch a?.etat {
        case .joignable?: return String(localized: "joignable")
        // Etats de Thread, que Zigbee ne donne jamais : comme injoignable.
        case .injoignable?, .partitionCoupee?, .sansAdresse?: return String(localized: "injoignable")
        case .disparu?: return String(localized: "disparu")
        case .inconnu?, nil: return String(localized: "état inconnu")
        }
    }

    static func couleur(_ e: EtatAffiche?, inconnu: Bool) -> Color {
        if inconnu { return .gray }
        switch e {
        case .joignable?: return .green
        // Etats de Thread, que Zigbee ne donne jamais : comme injoignable.
        case .injoignable?, .partitionCoupee?, .sansAdresse?, .disparu?: return .red
        case .inconnu?, nil: return .gray
        }
    }

    /// Orange de la batterie faible, assez fonce en mode clair pour se lire sur le verre pale.
    private var orange: Color { apparence == .dark ? .orange : Color(red: 0.72, green: 0.36, blue: 0) }
}

extension FicheNoeudZigbee {
    /// « Identifier par Maison » est offert (grise s'il n'y a pas d'`id` ou de demon) pour tout appareil que le pont
    /// connait, comme pour Thread ; pas pour un noeud que le pont ne connait pas.
    static func proposeIdentifierParMaison(_ a: AppareilPont?) -> Bool {
        a != nil
    }
}

/// « Identifier par Maison » : le demon Passeur Noms appelle `identify()` sur l'accessoire de Maison apparie a
/// l'appareil. Grise sans demon connecte (ou sans `NomsPasseur`, dans les vues de test), et sans `id` de Maison
/// (appareil non apparie, releve d'avant le demon). Le resultat s'affiche quelques secondes sous les boutons de la fiche.
struct BoutonIdentifierMaison: View {
    let passeur: NomsPasseur?
    /// L'`id` de l'accessoire de Maison ; nil si l'appareil n'a pas ete retrouve dans Maison.
    let accessoire: String?

    nonisolated static func actif(connecte: Bool, accessoire: String?) -> Bool {
        connecte && accessoire?.isEmpty == false
    }

    /// Le resultat de la derniere identification, s'il est pour cet accessoire.
    nonisolated static func texte(_ i: NomsPasseur.Identification?, accessoire: String?) -> String? {
        guard let i, i.accessoire == accessoire else { return nil }
        return i.texte
    }

    var body: some View {
        Button { if let accessoire { passeur?.identifier(accessoire: accessoire) } } label: {
            Label("Identifier par Maison", systemImage: "homekit")
        }
        .boutonDeFiche()
        .disabled(!Self.actif(connecte: passeur?.connecte == true, accessoire: accessoire))
        .help("Fait clignoter l'appareil, par Maison (Passeur Noms), pour le repérer")
    }
}

/// « Identifier » : fait clignoter l'appareil par le pont Hue. Grise pendant l'envoi des identifications.
struct BoutonIdentifierHue: View {
    let enCours: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if enCours {
                Label("Identification…", systemImage: "light.beacon.max")
            } else {
                Label("Identifier", systemImage: "light.beacon.max")
            }
        }
        .boutonDeFiche()
        .disabled(enCours)
        .help("Fait clignoter l'appareil, par le pont Hue, pour le repérer")
    }
}

extension View {
    /// Colonne de la fiche qui porte la pastille du coordinateur : elle passe avant les autres. La pastille garde
    /// sa ligne (`PastilleChef`), mais le `.frame(minWidth:)` de la colonne ne la fait pas plus large que la
    /// place que la fiche lui propose : quand les colonnes se serrent, la pastille deborderait sur la
    /// colonne voisine.
    func colonneDuChef(_ couronne: Bool) -> some View {
        layoutPriority(couronne ? 1 : 0)
    }
}
