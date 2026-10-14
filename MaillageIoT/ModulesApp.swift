import Foundation
import MaillageCoeur

/// Les objets de l'app et leur branchement : une `Surveillance` a deux modeles de protocole, un seul client du demon
/// Passeur Noms (son releve sert Thread et Zigbee), un seul navigateur Bonjour du pont Hue (`DecouvertePont`) et un seul
/// client du pont (`NomsPont`), et une sonde par protocole, chacune avec ses cles `thread.` / `zigbee.`, son trousseau et
/// son rythme. Construit par `MaillageIoTApp.init`, et par `DemarrageTests` : tout y est inerte en demo et sous les tests
/// (aucun port, aucun Bonjour, aucun fichier de l'app, aucun trousseau du Mac, aucun reseau).
@MainActor
struct ModulesApp {
    let surveillance: Surveillance
    let ouverture: OuvertureSession
    /// Le client du demon Passeur Noms : un seul abonnement, son releve va aux deux protocoles.
    let nomsMaison: NomsPasseur
    /// Le client du pont Hue (Zigbee) ; `decouverte` lui donne le pont que Bonjour trouve.
    let nomsPont: NomsPont
    let decouverte: DecouvertePont
    let sondeThread: SondeMaillageThread
    let sondeZigbee: SondeMaillageZigbee
    /// Le protocole dont la demo est rejouee (`-demo`) ; nil hors demo.
    let demo: Protocole?
    let sousTests: Bool

    /// `demo` : le protocole dont la demo est rejouee ; nil hors demo. `sousTests` : lance par les tests, qui ne touchent
    /// jamais aux fichiers de l'app, au trousseau ni au reseau.
    init(demo: Protocole?, sousTests: Bool = Surveillance.sousTests) {
        self.demo = demo
        self.sousTests = sousTests
        let inerte = demo != nil || sousTests
        // Ni fichier en demo (rien sur disque) ni sous les tests (jamais ceux de l'app).
        let dossier: URL? = inerte ? nil : Surveillance.dossierParDefaut
        surveillance = Surveillance(mode: demo != nil ? .demo : .direct, dossier: dossier, demo: demo ?? .thread)
        ouverture = OuvertureSession()
        // Les noms de Maison : le releve invente de la demo de Zigbee ; inerte sinon en demo et sous les tests (aucun
        // releve lu, ecrit ni demande au demon Passeur Noms) ; sinon le demon, son dernier releve garde dans
        // `releve-maison.json`, a la racine du dossier de l'app.
        nomsMaison = demo == .zigbee ? NomsPasseur(demo: NomsDemo.releveMaison)
            : inerte ? NomsPasseur()
            : NomsPasseur(cache: NomsPasseur.fichierCache(dossier: Surveillance.dossierParDefaut),
                          lanceur: NomsPasseur.lancerPasseurDuMac)
        // Les noms du pont : ceux de la demo de Zigbee ; inertes sinon en demo et sous les tests (ni reseau, ni trousseau,
        // ni fichier) ; sinon le client du pont, son dernier releve garde dans `Zigbee/noms-pont.json`.
        nomsPont = demo == .zigbee ? NomsPont(noms: NomsDemo.maisonPont)
            : inerte ? NomsPont()
            : NomsPont(dependances: .systeme(cache: Surveillance.dossierZigbee(Surveillance.dossierParDefaut)
                .appendingPathComponent("noms-pont.json")))
        decouverte = DecouvertePont()
        // Inertes en demo et sous tests : aucun port ouvert, ni trousseau du Mac lu, aucune identite de routeur lue ni
        // ecrite ; ils gardent un trousseau en memoire. Hors demo, la cle de l'acces reseau de chaque sonde vit dans le
        // trousseau du Mac (Zigbee reprend les cles de l'ancienne app, `TrousseauRepris`).
        sondeThread = SondeMaillageThread(
            actif: !inerte, trousseau: inerte ? TrousseauMemoireThread() : TrousseauSystemeThread(),
            fichierIdentites: SondeMaillageThread.fichierIdentites(demo: demo != nil, sousTests: sousTests))
        sondeZigbee = SondeMaillageZigbee(
            actif: !inerte,
            trousseau: inerte ? TrousseauMemoireZigbee()
                : TrousseauRepris(actuel: CheminSonde.trousseau(),
                                  ancien: TrousseauSystemeZigbee(service: TrousseauRepris.serviceSondeAncien),
                                  reprises: .preferences(cle: "zigbee.repriseTrousseauSonde")))
    }

    /// Branche les modules entre eux et les lance (ni en demo, ni sous les tests) : le releve de Maison aux deux
    /// protocoles ; Bonjour et le pont a Zigbee ; chaque sonde a son modele.
    func brancher() {
        let s = surveillance
        // Un seul releve de Maison, donne aux deux modeles ; le demon donne d'abord le releve garde, puis ses releves
        // arrivent des qu'ils changent.
        nomsMaison.surReleve = { [weak s] r in s?.recevoirReleveMaison(r) }
        nomsMaison.demarrer()
        // Les noms du pont et le releve de Maison vont au modele de Zigbee, qui les reunit (`FusionNoms`).
        nomsPont.surNoms = { [weak s] n in s?.zigbee.nomsPont = n }
        nomsPont.surLecture = { [weak s] n in s?.zigbee.lecturePont(n) }
        let b = decouverte
        b.surPont = { [weak nomsPont] p in nomsPont?.pontDecouvert(p) }
        b.surRefus = { [weak nomsPont] refus in nomsPont?.reseauLocalRefuse = refus }
        nomsPont.surEchecReseau = { [weak b] in b?.relancer() }
        nomsPont.demarrer()
        b.demarrer()
        // Thread : la sonde donne ses maillages au modele, qui lui rend les appareils a resoudre.
        let st = sondeThread
        st.surMaillage = { [weak s] m, recu in s?.thread.recevoir(m, a: recu) }
        st.surTournee = { [weak s] enCours in s?.thread.tourneeEnCours = enCours }
        st.surOubli = { [weak s] in s?.thread.oublierMaillage() }
        st.appareilsAResoudre = { [weak s] in s?.thread.appareilsAResoudre() ?? [] }
        st.reseauConnu = { [weak s] in s?.thread.instantane != nil }
        st.demarrer()
        // Zigbee. Incomplet : la tournee qui vient de finir a reporte des routes (son bilan est pose avant le maillage).
        let sz = sondeZigbee
        sz.surMaillage = { [weak s, weak sz] m, recu in
            s?.zigbee.recevoir(m, a: recu, incomplet: (sz?.bilan?.routesReportees ?? 0) > 0)
        }
        sz.surTournee = { [weak s] enCours in s?.zigbee.tourneeEnCours = enCours }
        sz.surOubli = { [weak s] in s?.zigbee.oublierMaillage() }
        sz.demarrer()
    }
}
