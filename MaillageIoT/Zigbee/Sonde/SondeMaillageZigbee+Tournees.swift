import Foundation
import MaillageCoeur
import ProtocoleZigbee

// Sonde Zigbee, role Tournees : boucle des tournees (premiere, 15 minutes, passe complementaire, relance apres `occupee`),
// budget de pages, entretien de la liaison reseau, memoire et releve.
extension SondeMaillageZigbee {
    /// Une tournee qui attend que le budget de pages de la sonde le permette.
    struct TourneeDifferee: Equatable {
        /// L'instant ou elle partira.
        var instant: Date
        /// Elle lira les tables de voisins : une tournee complete.
        var complete: Bool
    }

    /// La memoire d'une tournee qui commence : vide, sauf le journal des pages envoyees dans les 10 dernieres minutes
    /// (et les pages des dernieres tables), relu des preferences. Ni preferences lues ni ecrites par une sonde inerte
    /// (`vivante` faux : demo, tests).
    func nouvelleMemoire() -> MemoireTourneeZigbee {
        guard vivante else { return MemoireTourneeZigbee() }
        var m = MemoireTourneeZigbee()
        if let valeurs = preferences.object(forKey: Self.cleJournalPages) as? [Double] {
            m.budget = BudgetPages(enregistre: valeurs, a: horloge())
        }
        if let pages = preferences.object(forKey: Self.clePagesTables) as? Int, pages > 0 { m.pagesTables = pages }
        return m
    }

    /// Une requete de plus est revenue : le budget a jour va dans la memoire et dans les preferences, tout de suite (une
    /// app quittee en pleine tournee n'oublie pas ses pages).
    private func garderBudget(_ b: BudgetPages) {
        memoire.budget = b
        guard vivante else { return }
        preferences.set(b.enregistrable(a: horloge()), forKey: Self.cleJournalPages)
    }

    /// Le releve de la sonde (etat, derniere tournee, bilan, memoire des muets) : il est a une autre sonde, ou a
    /// aucune.
    func oublierReleve() {
        etatSonde = nil
        derniereTournee = nil
        erreurTournee = nil
        bilan = nil
        dureeTournee = nil
        passeComplementaire = nil
        tourneeDifferee = nil
        // Le journal des pages reste : c'est la sonde physique qui plafonne, pas le reseau lu.
        if vivante { preferences.removeObject(forKey: Self.clePagesTables) }
        memoire = nouvelleMemoire()
    }

    /// Bouton Rafraichir : une tournee tout de suite (sonde connectee, pas de tournee en cours), qui s'y substitue la
    /// passe complementaire programmee (elle lit d'abord les routes reportees) ; la suivante 15 min apres sa fin, ou une
    /// nouvelle passe complementaire si elle a encore reporte des routes.
    func rafraichir() {
        guard tourneeAuRafraichir, sonde != nil else { return }
        planifierTournee(dans: .zero)
    }

    /// Planifie la prochaine tournee de la sonde connectee dans `delai` (la boucle : chaque tournee planifie la
    /// suivante), ou, avec `passeA`, la passe complementaire a cette heure (`delai` en est l'attente). Un seul plan a la
    /// fois : le nouveau remplace l'ancien, passe programmee comprise. Un `deconnecter` l'annule, tournee en cours
    /// comprise.
    func planifierTournee(dans delai: Duration, passeA: Date? = nil) {
        boucle?.cancel()
        passeComplementaire = nil
        tourneeDifferee = nil
        guard let s = sonde else { return }
        let n = essai
        let complementaire = passeA != nil
        passeComplementaire = passeA
        boucle = Task { [weak self] in
            if delai > .zero { try? await self?.dormir(delai) }
            guard !Task.isCancelled, let self, n == self.essai, self.sonde === s else { return }
            self.passeComplementaire = nil
            // Une passe complementaire a son propre instant ; toute autre tournee attend que le budget le permette.
            if !complementaire, !(await self.attendreBudget(s, essai: n)) { return }
            // Pendant une mise en service, la tournee attend qu'elle finisse (`finirMiseEnService`).
            guard !self.miseEnServiceEnCours else {
                self.tourneeRetenue = true
                return
            }
            let suite = await self.tourner(s, complementaire: complementaire)
            guard !Task.isCancelled, n == self.essai, self.sonde === s else { return }
            self.planifierSuite(suite)
        }
    }

    /// Attend, si besoin, que le budget de pages couvre les tables de voisins (quand elles sont dues) et les routes du pont
    /// de la tournee qui va partir (`MemoireTourneeZigbee.instantProchaineTournee`), en le montrant (`tourneeDifferee`).
    /// L'instant est recalcule apres chaque attente. Rend faux si le plan a ete annule ou remplace entre-temps.
    private func attendreBudget(_ s: Sonde, essai n: Int) async -> Bool {
        while let instant = memoire.instantProchaineTournee(a: horloge()) {
            let maintenant = horloge()
            tourneeDifferee = TourneeDifferee(instant: instant, complete: memoire.tablesDues)
            try? await dormir(.seconds(max(0, instant.timeIntervalSince(maintenant))))
            guard !Task.isCancelled, n == essai, sonde === s else { return false }
        }
        tourneeDifferee = nil
        return true
    }

    /// Ce qui suit une tournee.
    private enum SuiteTournee {
        /// La tournee n'a pas eu lieu, ou une passe complementaire n'a lu aucune route (rien ne dit qu'une autre y
        /// arriverait : pas d'emballement) : le rythme normal.
        case rythme
        /// Une passe complementaire peut suivre : la tournee a eu lieu, et, pour une passe, elle a lu des routes.
        case passe
        /// La sonde a refuse (`occupee` : pile Zigbee pas encore lancee) : une autre tournee bientot.
        case bientot
    }

    /// Ce qui suit une tournee finie : la passe complementaire si elle a reporte des routes (des que le budget le permet,
    /// au moins 30 s apres), une nouvelle tournee dans `delaiReessaiOccupee` si la sonde etait occupee, sinon la tournee
    /// suivante 15 minutes apres sa fin.
    private func planifierSuite(_ suite: SuiteTournee) {
        let fin = horloge()
        if suite == .bientot {
            planifierTournee(dans: delaiReessaiOccupee)
            return
        }
        guard suite == .passe, let instant = memoire.instantPasseComplementaire(apres: fin) else {
            planifierTournee(dans: periodeTournees)
            return
        }
        planifierTournee(dans: .seconds(max(0, instant.timeIntervalSince(fin))), passeA: instant)
    }

    /// Une tournee de la sonde `s` : son avancement, puis son maillage (s'il y en a un) a la surveillance, son bilan et
    /// l'etat lu de la sonde. Perimee (sonde deconnectee entre-temps), elle ne touche plus a rien.
    private func tourner(_ s: Sonde, complementaire: Bool) async -> SuiteTournee {
        debuterTournee()
        guard tourneeEnCours else { return .rythme }
        let debut = horloge()
        do {
            let r = try await TourneeZigbee.executer(s, memoire: memoire, complementaire: complementaire, horloge: horloge,
                                               attendre: attendre, avancement: { [weak self] a in self?.avancer(a) },
                                               surBudget: { [weak self] b in self?.garderBudget(b) })
            guard s === sonde else { return .rythme }
            guard !Task.isCancelled else {
                finirTournee(nil)
                return .rythme
            }
            memoire = r.memoire
            if vivante {
                if let pages = r.memoire.pagesTables {
                    preferences.set(pages, forKey: Self.clePagesTables)
                }
                preferences.set(r.memoire.budget.enregistrable(a: horloge()), forKey: Self.cleJournalPages)
            }
            etatSonde = r.etat
            bilan = r.bilan
            dureeTournee = horloge().timeIntervalSince(debut)
            erreurTournee = Self.texteEmpechement(r.empechement) ?? r.bilan.lacune.map(Self.texteLacune)
            finirTournee(r.maillage)
            return r.empechement == nil && (!complementaire || r.bilan.routesRouteursDemandees > 0) ? .passe : .rythme
        } catch {
            guard s === sonde else { return .rythme }
            if !(error is CancellationError) { erreurTournee = Self.texteErreur(error) }
            finirTournee(nil)
            return Self.sondeOccupee(error) ? .bientot : .rythme
        }
    }

    /// La sonde a refuse parce que sa pile Zigbee n'est pas (encore) lancee : elle attend son Wi-Fi au demarrage.
    private static func sondeOccupee(_ erreur: Error) -> Bool {
        if case Sonde.Erreur.occupee? = erreur as? Sonde.Erreur { return true }
        return false
    }

    /// Le message d'une erreur de la sonde connectee ; un refus `occupee` (etat transitoire, retente bientot) reste neutre.
    private static func texteErreur(_ erreur: Error) -> String {
        sondeOccupee(erreur)
            ? String(localized: "La sonde n'est pas encore prête : nouvel essai dans un instant.")
            : erreur.localizedDescription
    }

    /// Debut d'une tournee : son heure, et `surTournee`. Sans sonde connectee, ou pendant une tournee, rien.
    func debuterTournee() {
        guard case .connectee = etat, !tourneeEnCours else { return }
        tourneeEnCours = true
        debutTournee = horloge()
        surTournee?(true)
    }

    /// Avancement de la tournee en cours ; rien hors tournee.
    func avancer(_ a: AvancementTourneeZigbee) {
        guard tourneeEnCours else { return }
        avancement = a
    }

    /// Fin de la tournee en cours : son maillage, s'il y en a un, part a la surveillance avec l'heure de sa reception ;
    /// l'avancement et l'heure du debut sont remis a nil, puis `surTournee`. Hors tournee, rien.
    func finirTournee(_ m: MaillageZigbee?) {
        guard tourneeEnCours else { return }
        if let m {
            let recu = horloge()
            derniereTournee = recu
            surMaillage?(m, recu)
        }
        avancement = nil
        debutTournee = nil
        tourneeEnCours = false
        surTournee?(false)
    }

    /// Relit `etat` toutes les `periodeEntretien` hors tournee : la session H1 de la sonde reste vivante entre deux
    /// tournees (elle est oubliee apres 10 min sans message).
    func entretenir(_ s: Sonde) {
        entretien?.cancel()
        let periode = periodeEntretien
        entretien = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: periode)
                guard let self, !Task.isCancelled, s === self.sonde else { return }
                if !self.tourneeEnCours { await self.lireEtat(s) }
            }
        }
    }

    /// `etat` de la sonde connectee ; rien n'est retenu si la liaison n'est plus la sienne. Une liaison fermee est
    /// laissee a `liaisonFermee`.
    func lireEtat(_ s: Sonde) async {
        do {
            let e = try await s.etat()
            guard s === sonde else { return }
            etatSonde = e
            erreurTournee = nil
        } catch Sonde.Erreur.fermee {
            // La liaison est fermee : `liaisonFermee` s'en occupe.
        } catch {
            guard s === sonde else { return }
            erreurTournee = Self.texteErreur(error)
        }
    }
}
