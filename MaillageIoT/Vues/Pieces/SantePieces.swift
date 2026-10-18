import Foundation
import MaillageCoeur

/// Le modele du panneau de sante de la vue par pieces (spec du panneau de sante, section 2) : tout ce que le panneau montre,
/// sans rien dessiner. Il lit la scene (`EntreeScene` : noeuds, pieces, etages, appareils, apparences), le focus (`Isolement`)
/// et ce que le journal sait des disparitions, et rend une `Lecture` : la capsule repliee (les comptes de toute la maison, par
/// protocole), la portee regardee et ses sections, la ligne « Ailleurs ». Des valeurs, jamais des textes : la vue (francais et
/// anglais) met les causes en mots.
///
/// Tous les noeuds, sans distinction de nature (spec 2.1) : appareils finaux, routeurs de Thread, routeurs de bordure, routeurs
/// de Zigbee, coordinateur (le pont). Deux familles, d'apres l'etat du noeud :
/// - **Perdu** : disparu (Thread et Zigbee), injoignable (le pont le dit tel) ; le coordinateur injoignable est « pont
///   injoignable », un routeur disparu « routeur disparu ».
/// - **A surveiller** : pile faible, joignable mais adresse plus annoncee (anneau verifie), adresse non annoncee, autre partition
///   (un appareil en partition coupee, un routeur de bordure d'une partition qui n'est pas la principale).
/// Un noeud n'est dans le panneau qu'une fois : dans Perdu s'il y est, sinon avec la premiere cause a surveiller du tableau. Un
/// etat inconnu, un noeud joignable, un noeud que la sonde seule connait n'y sont pas.
///
/// D'ou viennent les etats. Ceux des appareils, de `EntreeScene.appareils` : le pont de Zigbee, ses routeurs (lampes, prises) et
/// les appareils de Thread qui routent y sont aussi, car Maison ou le pont les donne comme appareils. Celui d'un routeur de
/// bordure d'une autre partition, de son apparence dans la scene (`DessinNoeud.Couleur.routeur(principale: false)`, ce que la
/// legende appelle « routeur de bordure d'une autre partition »). Celui d'un routeur disparu qui a quitte la scene (un routeur
/// de bordure qui n'est plus annonce, un routeur de Zigbee que le pont ne connait pas et que le maillage ne voit plus), du
/// journal (`routeursDisparus(journal:releves:)`) : la scene ne le porte plus. La date d'une disparition vient du journal aussi
/// (`Disparition`).
enum SantePieces {
    /// La famille d'un noeud fautif (spec 2.1) : perdu (rouge), a surveiller (orange). L'ordre des cas est l'ordre de tri.
    enum Famille: Equatable, Comparable, Sendable {
        case perdu, aSurveiller
    }

    /// Pourquoi un noeud est dans le panneau (spec 2.1, colonne « cause ») ; la vue en fait un texte. `depuis` : le debut de la
    /// disparition en cours d'apres le journal, nil quand il ne la donne pas (« disparu » seul). `niveau` : celui de la pile,
    /// nil quand on ne l'a pas (« pile faible »).
    enum Cause: Equatable, Sendable {
        case disparu(depuis: Date?)
        case routeurDisparu(depuis: Date?)
        case injoignable
        case pontInjoignable
        case pile(niveau: Int?)
        case adressePlusAnnoncee
        case adresseNonAnnoncee
        case autrePartition

        var famille: Famille {
            switch self {
            case .disparu, .routeurDisparu, .injoignable, .pontInjoignable: .perdu
            case .pile, .adressePlusAnnoncee, .adresseNonAnnoncee, .autrePartition: .aSurveiller
            }
        }
    }

    /// Combien de noeuds perdus et a surveiller.
    struct Comptes: Equatable, Sendable {
        var perdus = 0
        var aSurveiller = 0

        init(perdus: Int = 0, aSurveiller: Int = 0) {
            self.perdus = perdus
            self.aSurveiller = aSurveiller
        }

        init(_ lignes: [Ligne]) {
            self.init(perdus: lignes.filter { $0.famille == .perdu }.count,
                      aSurveiller: lignes.filter { $0.famille == .aSurveiller }.count)
        }

        var estVide: Bool { perdus == 0 && aSurveiller == 0 }
        var total: Int { perdus + aSurveiller }

        static func + (a: Comptes, b: Comptes) -> Comptes {
            Comptes(perdus: a.perdus + b.perdus, aSurveiller: a.aSurveiller + b.aSurveiller)
        }
    }

    /// Une ligne du panneau : un noeud perdu ou a surveiller. `piece` : la piece PLACEE dans la scene, celle que l'on y voit (la
    /// carte « Sans piece » en est une), nil pour un noeud qui n'a pas de place dans la scene. `cliquable` : le noeud est dans la
    /// scene, un clic peut y mener ; sinon la ligne est attenuee.
    struct Ligne: Equatable, Sendable, Identifiable {
        var id: IdNoeud
        var nom: String
        var piece: String?
        var cause: Cause
        var cliquable: Bool

        var famille: Famille { cause.famille }
    }

    /// Une section du panneau ouvert : un protocole montre, avec ses lignes de la portee (perdus d'abord, puis a surveiller ; par
    /// piece, puis par nom). Sans ligne : « Rien a signaler ». `enAttente` : il n'a encore aucun releve et rien a signaler (« … »).
    struct SectionProtocole: Equatable, Sendable, Identifiable {
        var protocole: Protocole
        var lignes: [Ligne]
        var enAttente: Bool

        /// Les comptes de la portee : ceux des lignes.
        var comptes: Comptes { Comptes(lignes) }
        var id: Protocole { protocole }
    }

    /// Le panneau replie : un protocole montre apres l'autre (dans l'ordre des protocoles), avec les comptes de toute la maison.
    struct Resume: Equatable, Sendable {
        struct Entree: Equatable, Sendable {
            var protocole: Protocole
            /// nil : ce protocole n'a encore aucun releve et rien a signaler (« … »), jamais « tout va bien ».
            var comptes: Comptes?
        }

        var entrees: [Entree]

        /// Au moins un protocole montre, chacun releve, et aucun noeud perdu ni a surveiller : « Tout va bien ».
        var toutVaBien: Bool {
            !entrees.isEmpty && entrees.allSatisfy { $0.comptes?.estVide == true }
        }
    }

    /// Ce que regarde le panneau ouvert, d'apres le focus : la maison, un niveau isole ou une piece isolee, par leur nom, qui est
    /// le titre (« Sante · Maison »).
    enum Portee: Equatable, Sendable {
        case maison
        case etage(String)
        case piece(String)
    }

    /// Le debut de la disparition en cours d'un noeud, d'apres son journal : sa date, et si c'etait un routeur (le type de
    /// l'evenement : un routeur de Zigbee sorti du maillage n'a plus de route, mais le journal garde sa nature).
    struct Disparition: Equatable, Sendable {
        var depuis: Date
        var routeur: Bool

        /// La plus recente des disparitions (appareil ou routeur) d'une liste d'evenements d'un noeud, dans n'importe quel ordre ;
        /// nil s'il n'y en a pas (le noeud est disparu avant le lancement, ou l'evenement est trop ancien).
        static func plusRecente(parmi evenements: [Evenement]) -> Disparition? {
            evenements.filter { $0.type == .appareilDisparu || $0.type == .routeurDisparu }
                .max { $0.date < $1.date }
                .map { Disparition(depuis: $0.date, routeur: $0.type == .routeurDisparu) }
        }
    }

    /// Un routeur que le journal dit disparu, avec le nom que le journal lui donnait.
    struct RouteurDisparu: Equatable, Sendable {
        var id: IdNoeud
        var nom: String
        var depuis: Date
    }

    /// Tout ce que le panneau affiche, replie (`capsule`) et ouvert (`portee`, `sections`, `ailleurs`).
    struct Lecture: Equatable, Sendable {
        /// Les comptes de toute la maison, par protocole montre, quel que soit le focus.
        var capsule: Resume
        var portee: Portee
        /// Une section par protocole montre, dans l'ordre des protocoles.
        var sections: [SectionProtocole]
        /// Les noeuds perdus ou a surveiller hors de la portee ; nil a la vue d'ensemble, ou s'il n'y en a pas.
        var ailleurs: Comptes?

        /// Aucun protocole a montrer : le panneau n'a rien a dire, la vue ne le montre pas.
        var estVide: Bool { capsule.entrees.isEmpty }
    }

    // MARK: - La lecture

    /// Un noeud fautif et sa place : l'indice de sa piece dans la scene, nil sans place.
    private struct Evalue {
        var ligne: Ligne
        var piece: Int?
    }

    /// Ce que le focus regarde, dans la scene : la maison, un etage (son indice), une piece (son indice).
    private enum Cadre {
        case maison
        case etage(Int)
        case piece(Int)
    }

    /// Lit la scene `entree` au focus `isolement` (fonction pure).
    /// - `montres` : les protocoles montres (interrupteur de la vue allume, protocole actif) ; un autre n'est nulle part dans la
    ///   lecture : ni capsule, ni section, ni « Ailleurs ».
    /// - `disparitions` : depuis quand chaque noeud disparu l'est (`disparitions(entree:evenements:)`).
    /// - `routeursDisparus` : ceux du journal (`routeursDisparus(journal:releves:)`) ; seuls comptent ceux qui ne sont plus dans
    ///   la scene.
    /// - `sansReleve` : les protocoles qui n'ont encore aucun releve ; sans noeud fautif, leur place montre « … ».
    static func lire(entree e: EntreeScene, isolement: Isolement, montres: Set<Protocole>,
                     disparitions: [IdNoeud: Disparition] = [:], routeursDisparus: [RouteurDisparu] = [],
                     sansReleve: Set<Protocole> = []) -> Lecture {
        let scene = e.scene
        let (evalues, protocolesDesNoeuds) = evaluer(e, montres: montres, disparitions: disparitions,
                                                     routeursDisparus: routeursDisparus)
        let cadre = cadre(isolement, scene: scene)
        func dedans(_ v: Evalue) -> Bool {
            switch cadre {
            case .maison: true
            case .etage(let i): v.piece.map { scene.pieces[$0].etage == i } ?? false
            case .piece(let i): v.piece == i
            }
        }
        let portee: Portee = switch cadre {
        case .maison: .maison
        case .etage(let i): .etage(LibellesNoeuds.nom(scene.etages[i].nom))
        case .piece(let i): .piece(LibellesNoeuds.nom(scene.pieces[i].nom, libelles: e.libelles))
        }

        // Les protocoles montres : ceux qui ont un noeud, un noeud fautif, ou un releve qui manque encore.
        let presents = protocolesDesNoeuds.union(evalues.map(\.ligne.id.protocole)).union(sansReleve)
        let affiches = Protocole.allCases.filter { montres.contains($0) && presents.contains($0) }
        var entrees: [Resume.Entree] = []
        var sections: [SectionProtocole] = []
        for p in affiches {
            let maison = Comptes(evalues.map(\.ligne).filter { $0.id.protocole == p })
            // « … » quand le protocole n'a pas de releve et rien a signaler : un noeud fautif n'est jamais cache.
            let enAttente = sansReleve.contains(p) && maison.estVide
            entrees.append(Resume.Entree(protocole: p, comptes: enAttente ? nil : maison))
            let lignes = evalues.filter { $0.ligne.id.protocole == p && dedans($0) }.map(\.ligne)
            sections.append(SectionProtocole(protocole: p, lignes: lignes, enAttente: enAttente))
        }
        let dehors: Comptes? = switch cadre {
        case .maison: nil
        default: Comptes(evalues.filter { affiches.contains($0.ligne.id.protocole) && !dedans($0) }.map(\.ligne))
        }
        return Lecture(capsule: Resume(entrees: entrees), portee: portee, sections: sections,
                       ailleurs: dehors.flatMap { $0.estVide ? nil : $0 })
    }

    /// Les noeuds fautifs, dans l'ordre des lignes (`avant`), et les protocoles qui ont un noeud montre : ceux de la scene et des
    /// appareils affiches, puis les routeurs que le journal dit disparus et qui n'y sont plus (sans place, sans clic).
    private static func evaluer(_ e: EntreeScene, montres: Set<Protocole>, disparitions: [IdNoeud: Disparition],
                                routeursDisparus: [RouteurDisparu]) -> ([Evalue], Set<Protocole>) {
        let scene = e.scene
        // Les noeuds a lire : les appareils affiches, et ceux de la scene (un routeur de bordure n'est pas un appareil).
        let ids = Set(e.appareils.keys).union(scene.noeuds.map(\.id)).filter { montres.contains($0.protocole) }
        var evalues: [Evalue] = []
        for id in ids {
            let a = e.appareils[id], n = scene.noeud(id)
            guard let raison = cause(de: id, appareil: a, noeud: n, apparence: e.apparences[id], disparition: disparitions[id]) else {
                continue
            }
            let piece = n.map { scene.pieces[$0.piece] }.map { LibellesNoeuds.nom($0.nom, libelles: e.libelles) }
            let nom = a?.nom ?? e.libelles[id]?.nom ?? n?.libelle ?? id.cle
            evalues.append(Evalue(ligne: Ligne(id: id, nom: nom, piece: piece, cause: raison, cliquable: n != nil), piece: n?.piece))
        }
        // Un routeur que le journal dit disparu et que la scene n'a plus (ni parmi les appareils). Deux fois dans la liste : sa
        // derniere disparition.
        var absents: [IdNoeud: RouteurDisparu] = [:]
        for r in routeursDisparus where montres.contains(r.id.protocole) && !ids.contains(r.id) {
            if let deja = absents[r.id], deja.depuis >= r.depuis { continue }
            absents[r.id] = r
        }
        for r in absents.values {
            let ligne = Ligne(id: r.id, nom: r.nom, piece: nil, cause: .routeurDisparu(depuis: r.depuis), cliquable: false)
            evalues.append(Evalue(ligne: ligne, piece: nil))
        }
        evalues.sort { avant($0.ligne, $1.ligne) }
        return (evalues, Set(ids.map(\.protocole)))
    }

    /// Le focus dans la scene : l'etage ou la piece isoles, par leur cle ; la maison si la scene ne les connait plus (le moteur
    /// recale alors l'isolement a la maison).
    private static func cadre(_ isolement: Isolement, scene: ScenePieces) -> Cadre {
        switch isolement {
        case .maison:
            return .maison
        case .etage(let cle):
            return scene.etages.firstIndex { $0.id == cle }.map(Cadre.etage) ?? .maison
        case .piece(let cle, _):
            return scene.pieces.firstIndex { $0.id == cle }.map(Cadre.piece) ?? .maison
        }
    }

    /// La cause pour laquelle un noeud est dans le panneau ; nil s'il n'a rien a y faire. Le tableau de la spec (2.1), dans son
    /// ordre : perdu d'abord (l'etat du noeud), puis la premiere cause a surveiller.
    /// - `appareil` : l'appareil affiche (un routeur de bordure, un noeud que la sonde seule connait n'en ont pas) ;
    /// - `noeud` : le noeud de la scene (nil : sans place) ; `apparence` : sa couleur, qui dit un routeur de bordure d'une autre
    ///   partition ;
    /// - `disparition` : le journal de ce noeud. Un routeur est un noeud qui route, ou que le journal dit routeur.
    private static func cause(de id: IdNoeud, appareil a: AppareilAffiche?, noeud n: ScenePieces.Noeud?,
                              apparence: DessinNoeud.Apparence?, disparition: Disparition?) -> Cause? {
        if let a {
            switch a.etat {
            case .disparu:
                let depuis = disparition?.depuis
                return n?.routeur == true || disparition?.routeur == true ? .routeurDisparu(depuis: depuis) : .disparu(depuis: depuis)
            case .injoignable:
                // Le pont lui-meme : le coordinateur, le centre de Zigbee.
                return id.protocole == .zigbee && n?.genre == .centre ? .pontInjoignable : .injoignable
            case .joignable, .partitionCoupee, .sansAdresse, .inconnu:
                break
            }
            if let b = a.batterie, b.faible { return .pile(niveau: b.niveau) }
            if a.etat == .joignable && a.verifie { return .adressePlusAnnoncee }
            if a.etat == .sansAdresse { return .adresseNonAnnoncee }
            if a.etat == .partitionCoupee { return .autrePartition }
        }
        // Un routeur de bordure n'a pas d'etat : sa couleur dans la scene dit qu'il est d'une partition qui n'est pas la
        // principale (« routeur de bordure d'une autre partition », la legende).
        if apparence?.couleur == .routeur(principale: false) { return .autrePartition }
        return nil
    }

    /// L'ordre des lignes : perdus d'abord, puis a surveiller ; dans chaque famille, par piece puis par nom, dans l'ordre de la
    /// langue (« Lampe 2 » avant « Lampe 10 ») ; un noeud sans place apres les autres ; a nom egal, par identifiant.
    private static func avant(_ a: Ligne, _ b: Ligne) -> Bool {
        if a.famille != b.famille { return a.famille < b.famille }
        switch (a.piece, b.piece) {
        case (let p?, let q?):
            let c = p.localizedStandardCompare(q)
            if c != .orderedSame { return c == .orderedAscending }
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            break
        }
        let c = a.nom.localizedStandardCompare(b.nom)
        if c != .orderedSame { return c == .orderedAscending }
        return a.id < b.id
    }

    // MARK: - Ce que le journal sait

    /// Depuis quand les noeuds disparus de la scene le sont : pour chacun, la plus recente disparition de son journal
    /// (`evenements`, ceux de ce noeud : `Surveillance.evenements(de:)`). Le journal n'est lu que pour les noeuds disparus ; sans
    /// evenement, le noeud n'a pas d'entree (« disparu » seul).
    static func disparitions(entree: EntreeScene, evenements: (IdNoeud) -> [Evenement]) -> [IdNoeud: Disparition] {
        var r: [IdNoeud: Disparition] = [:]
        for a in entree.appareils.values where a.etat == .disparu {
            r[a.id] = Disparition.plusRecente(parmi: evenements(a.id))
        }
        return r
    }

    /// Les routeurs que le journal dit disparus (`routeurDisparu`, d'un routeur de bordure de Thread ou d'un routeur de Zigbee) et
    /// que rien n'a suivi : ni son retour (`routeurApparu`), ni un nouveau depart de son protocole (`surveillanceDemarree`, le
    /// premier releve d'une session : comme un appareil disparu, un routeur disparu ne se garde pas d'un lancement a l'autre). Un
    /// depart d'un reseau vu pour la premiere fois (`reseau` donne) n'efface rien. Le journal est lu dans l'ordre ou l'app a
    /// appris les choses. Un evenement sans sujet est ignore ; une ligne sans protocole est de Thread. Triee par identifiant.
    /// `releves` : les protocoles dont cette session a deja un releve (`releveDeLaSession`) ; avant lui, le journal d'un protocole
    /// est celui d'une session passee, et ne dit rien de l'etat d'a present.
    static func routeursDisparus(journal: [Evenement], releves: Set<Protocole> = Set(Protocole.allCases)) -> [RouteurDisparu] {
        var disparus: [IdNoeud: RouteurDisparu] = [:]
        for e in journal {
            let protocole = e.protocole ?? .thread
            switch e.type {
            case .routeurDisparu:
                guard let s = e.sujet else { continue }
                let id = IdNoeud(protocole, s.id)
                disparus[id] = RouteurDisparu(id: id, nom: s.nom, depuis: e.date)
            case .routeurApparu:
                guard let s = e.sujet else { continue }
                disparus[IdNoeud(protocole, s.id)] = nil
            case .surveillanceDemarree where e.reseau == nil:
                disparus = disparus.filter { $0.key.protocole != protocole }
            default:
                break
            }
        }
        return disparus.values.filter { releves.contains($0.id.protocole) }.sorted { $0.id < $1.id }
    }

    // MARK: - D'apres la coque

    /// Les protocoles qui n'ont encore aucun releve : Thread tant qu'il n'a pas d'instantane, Zigbee tant qu'il n'a pas de maillage
    /// a montrer (spec 5 : un releve ancien n'est pas « … » ; le bandeau « ancien » de la vue le dit deja). Un protocole sans
    /// `switch` ici ne compile pas.
    @MainActor
    static func sansReleve(_ s: Surveillance) -> Set<Protocole> {
        Set(Protocole.allCases.filter { p in
            switch p {
            case .thread: s.thread.instantane == nil
            case .zigbee: s.zigbee.maillageAffiche == nil
            }
        })
    }

    /// Les protocoles dont CETTE session a deja un releve : Thread des son instantane, Zigbee des qu'une tournee a rendu un
    /// maillage (celui qu'il relit au lancement n'en est pas un). Le journal garde 90 jours : ce qu'il dit d'un routeur disparu ne
    /// vaut qu'apres le premier releve de la session.
    @MainActor
    static func releveDeLaSession(_ s: Surveillance) -> Set<Protocole> {
        Set(Protocole.allCases.filter { p in
            switch p {
            case .thread: s.thread.instantane != nil
            case .zigbee: s.zigbee.maillage != nil && !s.zigbee.maillageRelu
            }
        })
    }

    /// La lecture d'une fenetre : la scene `entree` au focus `isolement`, avec ce que sait la coque `s` (le journal, les releves).
    /// Les protocoles montres sont ceux de la scene que la coque montre : en demo, seulement ceux dont la demo est rejouee (l'autre,
    /// muet, n'attend rien).
    @MainActor
    static func lire(entree: EntreeScene, isolement: Isolement, surveillance s: Surveillance) -> Lecture {
        let montres = entree.montres.intersection(s.modelesMontres.map(\.protocole))
        let dates = disparitions(entree: entree) { s.evenements(de: $0) }
        let disparus = routeursDisparus(journal: s.evenements, releves: releveDeLaSession(s))
        return lire(entree: entree, isolement: isolement, montres: montres, disparitions: dates, routeursDisparus: disparus,
                    sansReleve: sansReleve(s))
    }
}
