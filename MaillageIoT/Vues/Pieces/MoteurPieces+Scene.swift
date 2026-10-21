import Foundation
import MaillageCoeur
import SwiftUI

/// La scene et sa disposition, le glissement d'une disposition a l'autre, les noms, les places gardees et le menu du
/// clic droit (polissage D, section 5 : le moteur en fichiers).
extension MoteurPieces {
    // MARK: Scene et disposition

    /// Nouvelle scene : appliquee tout de suite, ou a la fin du mouvement en cours (envol, vol, fondu)
    /// ou du glisser. Si ses etages, ses pieces, ses noeuds ou leurs noms changent, la disposition est
    /// recalculee hors du fil principal ; l'ancienne reste affichee pendant ce temps.
    func recevoir(_ e: EntreeScene) {
        // Un protocole masque ne laisse ni fiche ni focus : ils se ferment tout de suite, meme si la scene attend la fin d'un
        // mouvement (l'isolement d'une piece, lui, se ferme a la pose de la scene, `installer`).
        if let choisi = selection, !e.montre(choisi) { selection = nil }
        if let avant = sceneRecente, avant.montres != e.montres { protocolesBascules() }
        if occupe {
            attente = e
            return
        }
        appliquer(e)
    }

    func appliquer(_ e: EntreeScene) {
        attente = nil
        let cle = e.cleDisposition
        if cle == cleCalculee {
            // Aucun calcul n'est a faire : la marque d'un choix qui ne change pas la disposition ne doit pas trainer
            // jusqu'au prochain changement de Maison.
            fixerInchanges = false
            calculFixe = false
            calcul?.cancel()
            enCalcul = nil
            installer(e)
            return
        }
        // Meme structure que la disposition en calcul : elle vaudra pour cette scene. Le choix de la vue que cette scene
        // porte n'a rien change a la structure ; si ce calcul est parti sans la marque, elle ne lui servira plus.
        if enCalcul?.cleDisposition == cle {
            if !calculFixe { fixerInchanges = false }
            enCalcul = e
            return
        }
        calculer(e)
    }

    /// Les pieces des plateaux inchanges de `e`, a leur position affichee (indice de piece de la scene `e` -> position
    /// locale). Un plateau est inchange quand sa cle, ses pieces et leurs noeuds (`cleDisposition.pieces`) et sa place de
    /// niveau (`cleDisposition.niveaux`) sont ceux de la disposition affichee (`cleCalculee`) ; ses pieces y sont prises dans
    /// `placesCalculees`. Rien avant la premiere disposition, ni pour une cle de plateau en double.
    func fixeesInchangees(_ e: EntreeScene) -> [Int: SIMD2<Double>] {
        guard let avant = cleCalculee else { return [:] }
        let cle = e.cleDisposition, scene = e.scene
        let doubles = Dictionary(grouping: scene.etages, by: \.id).filter { $0.value.count > 1 }.keys
        var r: [Int: SIMD2<Double>] = [:]
        for et in scene.etages where !doubles.contains(et.id) {
            guard let pieces = cle.pieces[et.id], pieces == avant.pieces[et.id],
                  cle.niveaux[et.id] == avant.niveaux[et.id] else { continue }
            for i in et.pieces {
                if let place = placesCalculees[scene.pieces[i].nom], place.x.isFinite, place.y.isFinite { r[i] = place }
            }
        }
        return r
    }

    /// Les pieces fixees du calcul de `e` : les places gardees a la main, et, apres un choix fait dans la vue
    /// (`fixerInchanges`), les pieces des plateaux inchanges. Une place gardee a la main l'emporte. Note si la marque a servi
    /// (`calculFixe`).
    private func fixeesPour(_ e: EntreeScene) -> [Int: SIMD2<Double>] {
        let main = places.fixees(e.scene, domicile: e.domicile)
        calculFixe = fixerInchanges
        guard fixerInchanges else { return main }
        return fixeesInchangees(e).merging(main) { _, main in main }
    }

    /// Lance le calcul de la disposition d'une scene, hors du fil principal, avec les places gardees
    /// du moment ; un calcul en cours est abandonne.
    private func calculer(_ e: EntreeScene) {
        calcul?.cancel()
        enCalcul = e
        let cle = e.cleDisposition
        let cartes = cartesPour(e)
        let fixees = fixeesPour(e)
        let scene = e.scene
        calcul = Task { [weak self] in
            let d = await Task.detached(priority: .userInitiated) {
                DispositionPieces(scene: scene, cartes: cartes, fixees: fixees)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.retenir(d, scene: scene, cartes: cartes, cle: cle)
        }
    }

    /// La meme chose, sur le fil principal (captures, tests).
    func installerMaintenant(_ e: EntreeScene) {
        calcul?.cancel()
        let cartes = cartesPour(e)
        let d = DispositionPieces(scene: e.scene, cartes: cartes, fixees: fixeesPour(e))
        enCalcul = e
        retenir(d, scene: e.scene, cartes: cartes, cle: e.cleDisposition)
    }

    /// Cartes des pieces d'une scene, d'apres les noms mesures des noeuds, avec la place de tous leurs badges possibles
    /// (polissage D, section 2) : un badge qui change ne change pas la carte.
    private func cartesPour(_ e: EntreeScene) -> [CartesPieces.Carte] {
        var largeurs: [IdNoeud: Double] = [:]
        for n in e.scene.noeuds {
            largeurs[n.id] = mesure.reserve(n.libelle, routeur: n.route, pile: n.pile).width
        }
        return CartesPieces.cartes(e.scene, largeurs: largeurs)
    }

    /// Une disposition calculee pour `scene` : gardee par cles (piece, etage), d'apres cette scene, dont
    /// elle suit les indices (une scene plus recente de meme structure peut ranger ses etages, donc ses
    /// pieces, dans un autre ordre) ; puis posee avec la derniere scene de cette structure, si une scene
    /// d'une autre structure ne l'a pas depassee ; a la fin du mouvement ou du glisser en cours, s'il y
    /// en a un.
    private func retenir(_ d: DispositionPieces, scene: ScenePieces, cartes: [CartesPieces.Carte],
                         cle: EntreeScene.CleDisposition) {
        guard let e = enCalcul, e.cleDisposition == cle else { return }
        // Par `nom` et non par `id` : deux cartes de routeur de meme cle de deux protocoles (maison sans pieces) ont la meme
        // cle de piece `routeur:<cle>` (gardee brute), mais deux `NomPiece` : chacune garde sa place et sa carte.
        placesCalculees = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map {
            (scene.pieces[$0].nom, d.positions[$0])
        })
        rayonsCalcules = Dictionary(scene.etages.indices.map { (scene.etages[$0].id, d.rayons[$0]) },
                                    uniquingKeysWith: { a, _ in a })
        cartesCalculees = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map {
            (scene.pieces[$0].nom, cartes[$0])
        })
        cleCalculee = cle
        // La marque d'un choix de la vue a servi a ce calcul : elle ne vaut qu'une fois. Un calcul parti sans elle ne
        // l'efface pas (le choix est venu apres).
        if calculFixe { fixerInchanges = false }
        calculFixe = false
        enCalcul = nil
        if occupe {
            if attente == nil { attente = e }
            return
        }
        installer(e)
    }

    /// Pose une scene sur la disposition gardee : positions et rayons retrouves par cles, noms, piece isolee. Une
    /// nouvelle disposition glisse depuis la pose affichee (polissage D, section 1) ; des niveaux changes, ou des
    /// rayons changes sans eux (section 4), redemandent la grille.
    private func installer(_ e: EntreeScene) {
        let scene = e.scene
        let ancienFocus = focus.flatMap { $0 < clesPieces.count ? clesPieces[$0] : nil }
        // Des niveaux changes (le menu du clic droit) : les plateaux glissent vers leur nouvelle place (polissage C,
        // section 1.3) ; a la vue d'ensemble 2D, la grille se recalcule, sinon elle l'attend.
        let anciens = entree?.scene.etages.map(\.id) ?? []
        let niveauxChanges = pret && entree?.scene.niveaux != scene.niveaux
        let ensemble = aLaVueDEnsemble2D
        // Ce que la vue regarde, et ou, a l'image d'avant : sans glissement (« Reduire les animations »), elle le
        // suit d'un coup (plus bas). Une piece ou un etage qu'on quitte n'est plus regarde, meme s'il se relache
        // encore (relecture ciblee de la vague finale, Important 1).
        let regard = cleRegard(piece: ancienFocus)
        let ancre0 = pret ? ancreCamera() : nil
        // La pose affichee de la scene d'avant, et sa pose d'arrivee (polissage D, section 1).
        let avant = entree.map { PosesScene(scene: $0.scene, cartes: cartes, positions: positions) }
        let affichee = avant?.recouvertes(par: posesAffichees)
        let rayonsAvant = entree.map { Self.rayonsParCle($0.scene, geometrieVisee.rayons) }
        let ancienne = entree
        // La bascule d'un protocole (montre ou masque) se joue en un seul mouvement ; un changement du reseau garde
        // l'enchainement d'origine (`PlanTransition`).
        let cause: PlanTransition.Cause = ancienne.map { $0.montres != e.montres } == true ? .bascule : .reseau
        entree = e
        // Un autre ordre des plateaux : le disque et le nom d'etage survoles, des indices, en designeraient
        // d'autres ; le prochain mouvement du pointeur les reprend.
        if scene.etages.map(\.id) != anciens {
            survolEtage = nil
            survolNomEtage = nil
        }
        cartes = scene.pieces.map { cartesCalculees[$0.nom] ?? CartesPieces.carte([]) }
        positions = scene.pieces.map { placesCalculees[$0.nom] ?? .zero }
        // Une nouvelle disposition glisse (polissage D, section 1) : de la pose affichee a la nouvelle, en 0,9 s ; une
        // disposition qui ne change aucune pose laisse le glissement en cours aller a son terme, sans le relancer :
        // un releve qui ne change que la qualite d'un lien, par exemple. Ce qui change se juge comme dans
        // `TransitionScene` (les pieces, les noeuds, les liens presents). Avec « Reduire les animations », tout de
        // suite.
        let arrivee = PosesScene(scene: scene, cartes: cartes, positions: positions)
        // Les plateaux qui partaient a l'image : l'un d'eux peut revenir, de la ou il etait dessine (phase 11).
        let partisAffiches = posesAffichees.plateauxPartis
        // Une nouvelle transition accompagne ce changement : les plateaux glissent avec les pieces, sur sa duree (plus
        // bas).
        var nouvelleTransition = false
        if pret, let affichee, let avant,
           transition == nil || TransitionScene(de: avant, vers: arrivee, a: 0) != nil {
            transition = TransitionScene(de: affichee, vers: arrivee, a: Self.maintenant(), reduire: reduire,
                                         cause: cause)
            if transition != nil {
                // Un seul mouvement quand une piece change de plateau (phase 11) : le plateau qui part reste a sa place
                // de l'image et s'efface, la piece glisse depuis lui ; celui qui arrive apparait. La geometrie de l'image
                // est encore celle de la scene d'avant (`anciens`) : la nouvelle est visee plus bas.
                let (partis, arrivants) = plateauxEnTransition(depuis: anciens, vers: scene)
                transition?.plateauxPartis = partis
                transition?.plateauxArrivants = arrivants
            }
            if let tr = transition {
                nouvelleTransition = true
                posesAffichees = tr.poses(a: tr.debut)
                apparencesParties = (ancienne?.apparences ?? [:]).merging(apparencesParties) { a, _ in a }
                // Les noms de ceux qui partent : ceux d'avant (`textes` et `routeurs` sont encore ceux de la scene d'avant).
                nomsPartis = textes.noeuds.merging(nomsPartis) { a, _ in a }
                routeursPartis.formUnion(routeurs)
                // Le nom des plateaux qui partent, de meme (`textes.etages` suit les plateaux de la scene d'avant).
                var noms = nomsEtagesPartis
                for (j, c) in anciens.enumerated() where noms[c] == nil { noms[c] = textes.etages[j] }
                nomsEtagesPartis = noms.filter { c, _ in tr.plateauxPartis.contains { $0.cle == c } }
            } else {
                posesAffichees = PosesScene()
                apparencesParties = [:]
                nomsPartis = [:]
                routeursPartis = []
                nomsEtagesPartis = [:]
            }
        }
        // Les rayons changent sans les niveaux : la grille se redemande comme au redimensionnement, par la regle de la
        // politique : a la vue d'ensemble 2D, elle se rechoisit, avec l'hysteresis ; sinon elle attend (polissage D,
        // section 4).
        let rayonsChanges = pret && !niveauxChanges && Self.rayonsParCle(scene, rayons(scene)) != rayonsAvant
        if grille && (!pret || (niveauxChanges && ensemble)) {
            politique.choisir(rayons: rayons(scene), zone: zoneVisible, enPlace: false)
        } else if niveauxChanges {
            politique.attendre(PolitiqueGrille.niveaux)
        } else if rayonsChanges && grille {
            politique.demander(PolitiqueGrille.redimensionnement, ensemble2D: ensemble, rayons: rayons(scene),
                                   zone: zoneVisible)
        }
        // Des niveaux changes seuls : les plateaux glissent en 0,4 s en 2D. Accompagnes d'une nouvelle transition (une
        // piece qui change de plateau, phase 11), ils glissent avec les pieces, sur la duree du glissement : un seul
        // mouvement.
        let glisse = pret ? PlanTransition.pour(cause).glissement.duree : 0
        viser(geometriePour(scene), depuis: anciens, partis: partisAffiches,
              duree2D: niveauxChanges && !nouvelleTransition ? CameraScene.dureeCases : glisse,
              duree3D: niveauxChanges ? CameraScene.dureeNiveaux : glisse)
        // Les parts de l'isolement sont gardees par cle (triage A, n° 9) : un releve recu pendant un fondu ne remet pas
        // la piece a pleine taille. L'etage en vue suit ce que vise la vue (polissage C, section 5) : celui de la piece
        // isolee, qui a pu changer de zone. Une piece isolee qui disparait rend la maison, comme avant les etages :
        // l'etage est relache, comme a la bascule, et la vue d'ensemble se recadre (plus bas). Un etage isole qui
        // disparait rend aussi la maison.
        let clesPieces = Set(scene.pieces.map(\.id)), clesEtages = Set(scene.etages.map(\.id))
        fk = fk.filter { clesPieces.contains($0.key) }
        // La piece isolee rangee dans une autre zone emporte l'isolement de son etage : sans cela, son nouvel etage est
        // sous le voile des autres, et la piece tombe a 15 % avant de remonter (relecture finale de la phase 11, I2).
        if case .piece(let cle, _) = isolement, let ancien = etageEnVue,
           let i = scene.pieces.firstIndex(where: { $0.id == cle }) {
            let nouveau = scene.etages[scene.pieces[i].etage].id
            if nouveau != ancien { ek[nouveau] = max(ek[nouveau] ?? 0, ek[ancien] ?? 0) }
        }
        ek = ek.filter { clesEtages.contains($0.key) }
        isolement = isolement.recaler(pieces: clesPieces, etages: clesEtages)
        if let cle = ancienFocus, let i = scene.pieces.firstIndex(where: { $0.id == cle }) {
            focus = i
            if case .piece = isolement, scene.etages.count > 1 { viserEtage(scene.etages[scene.pieces[i].etage].id) }
        } else if focus != nil {
            focus = nil
            s = 0
            sCible = 0
            isolee = nil
            if isolement == .maison {
                etageEnVue = nil
                se = 0
                seCible = 0
                ek = [:]
            }
        }
        if let k = etageEnVue, !clesEtages.contains(k) {
            etageEnVue = nil
            se = 0
            seCible = 0
        }
        textes = Self.textes(e, focus: focus)
        routeurs = Set(scene.noeuds.filter(\.route).map(\.id))
        teintes = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map { ($0, scene.pieces[$0].teinte) })
        // Un noeud choisi dont le protocole est masque n'est plus choisi (sa fiche et son focus se ferment).
        if let choisi = selection, !e.montre(choisi) { selection = nil }
        construireEtiquettes()
        majFil()
        majMiseEnAvant()
        if !pret {
            pret = true
            orbite = CameraScene.canonique(geometrie, aspect: aspect, u: t)
        } else if !vueTouchee && sansIsolement {
            recadrer()
        } else if let ancre0, transition == nil, glissementPlateaux == nil, !aLaVueDEnsemble,
                  regard == cleRegard(piece: focus.map { scene.pieces[$0].id }) {
            // Rien ne glisse (« Reduire les animations ») : les pieces et les plateaux sont poses tout de suite
            // (polissage D, section 1 ; polissage C, section 1.3). La vue isolee ou zoomee suit ce qu'elle regarde,
            // d'un coup, depuis sa place a l'image d'avant, comme le glissement le lui fait suivre image apres image
            // (`suivre`), sans « Reduire » (relecture finale, Mineur 1). Si elle regarde autre chose (la piece isolee
            // disparue), elle ne bouge pas.
            suivre(depuis: ancre0)
        }
        reveiller()
    }

    /// Les rayons des plateaux de `scene`, par cle : une cle en double garde son premier rayon.
    private static func rayonsParCle(_ scene: ScenePieces, _ rayons: [Double]) -> [String: Double] {
        Dictionary(zip(scene.etages.map(\.id), rayons).map { ($0, $1) }, uniquingKeysWith: { a, _ in a })
    }

    /// Textes des noms : libelles, pieces (nom, compte), etages, maison, reperes « ailleurs ».
    static func textes(_ e: EntreeScene, focus: Int?) -> TextesScene {
        var t = TextesScene()
        t.noeuds = e.libelles
        for (i, p) in e.scene.pieces.enumerated() {
            t.pieces[i] = TextesScene.Piece(nom: LibellesNoeuds.nom(p.nom, libelles: e.libelles),
                                            compte: LibellesNoeuds.compte(p.noeuds.count))
        }
        for (i, et) in e.scene.etages.enumerated() { t.etages[i] = LibellesNoeuds.nom(et.nom) }
        t.maison = String(localized: "⌂ Maison")
        if let f = focus {
            for a in SceneProjetee.reperes(e.scene, focus: f) {
                t.ailleurs[a.enfant] = LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles)
            }
        }
        return t
    }

    /// Cle d'un nom, qui ne depend pas des indices de la scene.
    private func cle(_ g: Etiquette.Genre) -> String {
        switch g {
        case .noeud(let id): "n:" + id.texte
        case .piece(let i): "p:" + (i < clesPieces.count ? clesPieces[i] : "")
        case .etage(let i): "e:" + (i < clesEtages.count ? clesEtages[i]
            : i - clesEtages.count < clesEtagesPartis.count ? clesEtagesPartis[i - clesEtages.count] : "")
        case .maison: "m"
        case .ailleurs(let id): "a:" + id.texte
        }
    }

    /// Noms de la scene, dans l'ordre de la maquette (appareils, etages, pieces, maison, reperes) ;
    /// chacun garde son etat de placement d'une scene a l'autre.
    func construireEtiquettes() {
        guard let scene else { return }
        var anciennes: [String: Etiquette] = [:]
        for l in etiquettes { anciennes[cle(l.genre)] = l }
        clesPieces = scene.pieces.map(\.id)
        clesEtages = scene.etages.map(\.id)
        clesEtagesPartis = posesAffichees.plateauxPartis.map(\.cle)
        var l: [Etiquette] = []
        func ajouter(_ genre: Etiquette.Genre, _ taille: CGSize) {
            var e = Etiquette(genre, taille: taille)
            if let a = anciennes[cle(genre)] {
                e.place = a.place
                e.envie = a.envie
                e.vu = a.vu
                e.rect = a.rect
                e.rectAvant = a.rectAvant
            }
            l.append(e)
        }
        for n in scene.noeuds {
            let libelle = textes.noeuds[n.id] ?? LibellesNoeuds.Libelle(texte: n.id.cle)
            ajouter(.noeud(n.id), mesure.noeud(libelle, routeur: n.route))
        }
        for i in scene.etages.indices { ajouter(.etage(i), mesure.etage(textes.etages[i] ?? "")) }
        // Le nom d'un plateau qui part (phase 11), apres ceux de la scene : il garde sa place, et s'efface avec lui.
        for (k, c) in clesEtagesPartis.enumerated() {
            ajouter(.etage(scene.etages.count + k), mesure.etage(nomsEtagesPartis[c] ?? ""))
        }
        for i in scene.pieces.indices {
            let t = textes.pieces[i] ?? TextesScene.Piece(nom: "", compte: "")
            ajouter(.piece(i), mesure.piece(nom: t.nom, compte: t.compte))
        }
        ajouter(.maison, mesure.maison(textes.maison))
        for (id, texte) in textes.ailleurs.sorted(by: { $0.key < $1.key }) {
            ajouter(.ailleurs(id), mesure.ailleurs(texte))
        }
        // Le nom d'un noeud qui s'efface, vu a l'image d'avant, reste jusqu'a la fin de son fondu, au meme endroit : il
        // s'efface avec son noeud (il est ote de `etiquettes` quand celui-ci n'est plus dessine, `image`).
        for (_, nom) in anciennes.sorted(by: { $0.key < $1.key }) {
            guard case .noeud(let id) = nom.genre, scene.noeud(id) == nil, nom.vu, nomsPartis[id] != nil else { continue }
            l.append(nom)
        }
        etiquettes = l
    }

    // MARK: Places gardees et ordre des etages

    private func enregistrer() {
        // Arrete pour une reprise de donnees : le fichier est celui de l'import, jamais recrit depuis la memoire d'avant.
        guard coque?.arretee != true, let fichierPlaces else { return }
        do {
            try places.ecrire(dans: fichierPlaces)
        } catch {
            Self.journal.error("places des pieces non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Garde la place d'une piece qu'on vient de glisser : elle est desormais fixee. Un calcul en cours
    /// ne la connait pas : il est relance avec elle (sinon, a sa fin, la piece sauterait a la place
    /// qu'il lui donne). Une place non finie (camera degeneree) n'est pas gardee.
    func garder(_ id: String) {
        guard let e = entree, let i = e.scene.pieces.firstIndex(where: { $0.id == id }), i < positions.count,
              positions[i].x.isFinite, positions[i].y.isFinite else { return }
        let p = e.scene.pieces[i]
        places.garder(positions[i], piece: p.id, etage: e.scene.etages[p.etage].id, domicile: e.domicile)
        placesCalculees[p.nom] = positions[i]
        enregistrer()
        if let c = enCalcul { calculer(c) }
    }

    // MARK: Menu du clic droit (polissage C, section 1.3)

    /// La scene la plus recente : celle qui attend la fin d'un mouvement ou d'un geste, sinon celle du calcul en cours,
    /// sinon celle affichee. Apres un choix du menu, elle le porte avant la scene affichee.
    private var sceneRecente: EntreeScene? { attente ?? enCalcul ?? entree }

    /// Le menu du nom ou du disque du plateau `cle`, sur la scene la plus recente : ses coches et ses grises suivent le
    /// dernier choix, meme quand la scene de ce choix attend encore. Il lit la version de cette scene, observee : une
    /// vue qui le montre se refait quand elle change, meme si la cible du clic droit, elle, ne change pas.
    func menuEtage(_ cle: String) -> MenuEtage? {
        _ = versionScene
        guard let scene = sceneRecente?.scene, let niveau = scene.niveaux.niveau(cle) else { return nil }
        let n = scene.niveaux, estPrincipal = n.estPrincipal(cle)
        func nom(_ c: String) -> String {
            scene.etages.firstIndex { $0.id == c }.map { LibellesNoeuds.nom(scene.etages[$0].nom) } ?? c
        }
        let niveaux = n.liste.indices.filter { !(estPrincipal && $0 == niveau) }.map { i in
            MenuEtage.Niveau(principal: n.liste[i][0], nom: nom(n.liste[i][0]), coche: !estPrincipal && i == niveau)
        }
        return MenuEtage(nom: nom(cle), monter: estPrincipal && niveau < n.liste.count - 1,
                         descendre: estPrincipal && niveau > 0, niveaux: niveaux, aCote: !estPrincipal,
                         dehors: n.dehors(cle))
    }

    /// Le menu du clic droit sur la piece `cle`, sur la scene la plus recente (comme `menuEtage`, qui en explique la
    /// version lue) : son nom, et les zones de Maison qui la contiennent, celle du choix qui s'applique cochee. nil si la
    /// scene n'a plus cette piece. Une piece qui n'est pas de Maison (carte d'un routeur, « Sans piece ») n'a pas de zone.
    func menuPiece(_ cle: String) -> MenuPiece? {
        _ = versionScene
        guard let e = sceneRecente, let p = e.scene.pieces.first(where: { $0.id == cle }) else { return nil }
        let nom = LibellesNoeuds.nom(p.nom, libelles: e.libelles)
        guard case .maison(let piece) = p.nom else { return MenuPiece(nom: nom, automatique: true, zones: []) }
        let choisie = e.scene.zoneChoisie(piece)
        return MenuPiece(nom: nom, automatique: choisie == nil,
                         zones: e.scene.zonesDe(piece).map { MenuPiece.Zone(nom: $0, coche: $0 == choisie) })
    }

    /// « Ranger dans la zone… » : la piece `cle` (sa cle de piece, jamais un indice) va dans la zone `zone` de Maison, qui doit
    /// la contenir ; `nil`, « Automatiquement », oublie le choix. Le choix est calcule sur la scene la plus recente et garde
    /// dans les places, comme les choix de niveau (`ranger`) ; la scene suivante le prend (`EntreeScene`). Rien pour une
    /// piece inconnue, qui n'est pas de Maison, ou une zone qui ne la contient pas.
    func rangerPiece(_ cle: String, dans zone: String?) {
        guard let e = sceneRecente, let p = e.scene.pieces.first(where: { $0.id == cle }),
              case .maison(let piece) = p.nom, zone.map({ z in e.scene.zonesDe(piece).contains(z) }) ?? true else { return }
        // Un choix qui ne change rien (la zone deja cochee, « Automatiquement » deja coche) ne change pas la scene : aucun
        // calcul n'effacerait la marque, qui trainerait jusqu'au prochain changement de Maison (relecture finale, M1).
        guard places.zonesChoisies(e.domicile)[piece] != zone else { return }
        places.choisirZone(zone, piece: piece, domicile: e.domicile)
        enregistrer()
        fixerInchanges = true
    }

    /// Un choix du menu, calcule sur la scene la plus recente et sur les choix gardes : le nouvel ordre des plateaux et
    /// les nouveaux choix de niveau, gardes ; la scene suivante les prend (`EntreeScene`), et les plateaux glissent
    /// vers leur nouvelle place. Sur la scene affichee, un choix fait pendant que la scene du precedent attend (un vol,
    /// le calcul de sa disposition) defaisait le precedent.
    private func ranger(_ operation: (Niveaux, [String: PlacesGardees.ACote]) -> Rangement?) {
        guard let e = sceneRecente, let r = operation(e.scene.niveaux, places.maison(e.domicile).aCote) else { return }
        places.ranger(r, domicile: e.domicile)
        enregistrer()
        fixerInchanges = true
    }

    /// La cle du plateau `e` de la scene affichee, celle des noms et de la projection.
    func cleEtage(_ e: Int) -> String? {
        guard let scene, scene.etages.indices.contains(e) else { return nil }
        return scene.etages[e].id
    }

    /// La cle de la piece `i` de la scene affichee, celle de la cible du menu et de ses articles.
    func clePiece(_ i: Int) -> String? {
        guard let scene, scene.pieces.indices.contains(i) else { return nil }
        return scene.pieces[i].id
    }

    /// « Monter d'un etage » (+1) ou « Descendre d'un etage » (-1) : le niveau entier de l'etage `cle`, zones a cote
    /// comprises, change de place avec son voisin.
    func deplacerEtage(_ cle: String, de pas: Int) {
        ranger { $0.deplacer(cle, de: pas, choix: $1) }
    }

    /// La meme chose pour le plateau `e` de la scene affichee.
    func deplacerEtage(_ e: Int, de pas: Int) {
        if let cle = cleEtage(e) { deplacerEtage(cle, de: pas) }
    }

    func peutDeplacerEtage(_ e: Int, de pas: Int) -> Bool {
        cleEtage(e).flatMap(menuEtage).map { pas > 0 ? $0.monter : $0.descendre } ?? false
    }

    /// « Au meme niveau que » le niveau de l'etage principal `principal` (sa cle), dans la maison.
    func mettreAuNiveau(_ cle: String, de principal: String) {
        ranger { n, choix in n.niveau(principal).flatMap { n.rejoindre(cle, niveau: $0, choix: choix) } }
    }

    /// « Hors de la maison », coche ou non.
    func basculerDehors(_ cle: String) {
        ranger { $0.basculerDehors(cle, choix: $1) }
    }

    /// « Sur son propre niveau ».
    func mettreSurSonNiveau(_ cle: String) {
        ranger { $0.propreNiveau(cle, choix: $1) }
    }

    /// « Replacer les pieces automatiquement » : oublie les places gardees de la maison (pas l'ordre
    /// des etages) et recalcule la disposition de la scene la plus recente (celle qui attend la fin d'un
    /// mouvement ou d'un geste, sinon celle du calcul en cours, sinon celle affichee) ; l'ancienne reste
    /// affichee pendant ce temps.
    func replacerPieces() {
        guard let e = sceneRecente else { return }
        places.replacer(domicile: e.domicile)
        enregistrer()
        fixerInchanges = false
        calculFixe = false
        cleCalculee = nil
        enCalcul = nil
        appliquer(e)
    }
}
