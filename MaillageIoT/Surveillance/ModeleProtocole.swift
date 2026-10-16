import Foundation
import MaillageCoeur

/// Les trois chiffres que la barre des menus montre de chaque protocole (routeurs, appareils, injoignables). Thread en
/// dit plus dans son menu (nom du reseau, partitions : `ResumeReseauThread`) ; ce resume commun est ce que les deux protocoles
/// savent donner.
struct ResumeMenu: Equatable {
    var routeurs: Int
    var appareils: Int
    var injoignables: Int
}

/// Ce que chaque protocole fournit a l'app, au-dessus de la coque `Surveillance` : la forme de `ProtocoleMaille` (spec
/// 1.2), dans l'app et non dans le coeur (le coeur ne connait aucun modele). `SurveillanceThread` et `SurveillanceZigbee`
/// s'y conforment ; l'identifiant de chaque noeud rendu est un `IdNoeud` de leur protocole.
///
/// Ne porte que ce que les vues lisent sans connaitre le protocole : la scene reunie (`EntreeScene`) lit `graphe`,
/// `appareils`, `classement`, `miseEnAvant` et `suitModeLiens` de chaque modele. Les libelles, les pieces, les chefs et
/// l'apparence des noeuds, qui lisent les types propres a chaque protocole (reseau, maillage et noms de Maison pour
/// Thread ; maillage et noms du pont pour Zigbee), restent des fonctions de chaque protocole (`LibellesNoeuds`,
/// `LibellesNoeudsZigbee`) que `EntreeScene` appelle sur le sous-graphe du protocole.
@MainActor
protocol ModeleProtocole: AnyObject {
    var protocole: Protocole { get }

    /// « Activer ce protocole » : faux, le module est vraiment arrete (sonde et port, Bonjour ou pont, tournees,
    /// notifications) et le modele ne montre plus rien (ni noeud dans la scene, ni chiffre au menu, ni alerte) ni
    /// n'ecrit rien au journal ; vrai, il repart comme au lancement. Garde dans les preferences du protocole
    /// (`thread.actif`, `zigbee.actif`), vrai par defaut.
    var actif: Bool { get set }

    /// En demo, ce modele rejoue la demo de son protocole ; faux : un modele muet (`-demo-thread` et `-demo-zigbee`
    /// font tourner un seul reseau, l'autre protocole eteint ; `-demo`, la combinee, les deux). Toujours vrai hors demo.
    var rejoueLaDemo: Bool { get }

    // MARK: Scene

    /// Noeuds et liens du reseau affiche de ce protocole, sans geometrie ; vide sans reseau a montrer.
    var graphe: GrapheReseau { get }
    /// Appareils a dessiner pour le reseau affiche : noms deja choisis, etats, batteries.
    var appareils: [AppareilAffiche] { get }
    /// Unite, pas, bornes et bandes du signal de ce protocole (courbes de la fiche).
    var echelle: EchelleSignal { get }
    /// Rang et rayon d'un noeud de ce protocole dans la scene (`ScenePieces(classement:)`).
    var classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) { get }
    /// Le mode des liens montres (`ModeLiens` : chemins vers le pont, ou tous les liens radio) et le choix des voisins
    /// entendus valent pour les liens de ce protocole (Zigbee, dont la carte est celle des chemins vers le pont) ; faux :
    /// ses liens radio sont toujours montres, et sa mise en avant montre toujours ses voisins (Thread, sans chemin vers un pont).
    var suitModeLiens: Bool { get }
    /// Mode focus : ce qui reste net a la selection de `id`, sur le graphe `graphe` de la scene. `chefs` : les noeuds
    /// couronnes (Thread les lit, Zigbee non) ; `voisins` : montrer aussi les voisins entendus (Zigbee le lit, Thread
    /// le montre toujours aujourd'hui). nil si `id` n'est pas de ce protocole.
    func miseEnAvant(de id: IdNoeud, graphe: GrapheReseau, chefs: Set<IdNoeud>, voisins: Bool) -> MiseEnAvant?

    // MARK: Fiche

    /// L'historique de la sonde a au moins un releve (la fiche montre ses courbes).
    var aHistorique: Bool { get }
    /// Courbes d'un noeud du graphe (sa cle brute de module) sur une periode qui finit a `fin` ; nil sans cle d'historique.
    func courbes(noeud cle: String, periode: PeriodeCourbes, fin: Date) -> CourbesNoeud?
    /// Noms des noeuds de l'historique, par cle d'historique.
    func nomsHistorique(_ cles: Set<String>) -> [String: String]
    /// Quels evenements du journal concernent le noeud `id` (ses evenements : la coque les filtre et les regroupe).
    func concernant(_ id: IdNoeud) -> (Evenement) -> Bool
    /// Applique (ou retire, avec nil) un surnom au resolveur de noms du module ; `cle` : la cle brute du noeud.
    func appliquerSurnom(_ surnom: String?, cle: String)

    // MARK: Noms

    /// Le releve de Maison du demon Passeur Noms, le meme pour tous les protocoles : chaque modele le range dans son
    /// resolveur de noms (nil : plus de releve).
    func recevoirReleveMaison(_ releve: NomsMaison?)

    // MARK: Menu et icone

    var resumeMenu: ResumeMenu? { get }
    /// L'etat du reseau est lui-meme une alerte (Thread : un reseau scinde), en plus des evenements graves du journal.
    var alerteReseau: Bool { get }

    // MARK: Horloge et fraicheur

    /// Reference des durees a l'heure `horloge` : cette heure, ou la fin de la demo rejouee en demo.
    func maintenant(a horloge: Date) -> Date
    /// Fraicheur du maillage de la sonde de ce protocole a `maintenant` (ses propres seuils) ; nil sans maillage.
    func fraicheurMaillage(a maintenant: Date) -> Surveillance.Fraicheur?

    // MARK: Cycle de vie, appele par la coque

    func demarrer()
    func arreter()
    /// Le Mac se reveille (apres `noterVeille`).
    func auReveil()
    /// Evenements de la veille du Mac, a verser au journal.
    func noterVeille(_ intervalle: DateInterval) -> [Evenement]
    /// Purge l'historique sur disque de ce protocole (mois finis depuis plus de 90 jours), a `maintenant`.
    func purgerHistorique(maintenant: Date)
}

extension ModeleProtocole {
    /// Reference a l'heure du Mac.
    var maintenant: Date { maintenant(a: Date()) }

    /// Le maillage affiche a depasse son seuil de fraicheur (6 min pour Thread, 16 min pour Zigbee), et aucune tournee n'est en cours : la
    /// sonde ne repond plus.
    var maillageAncien: Bool { fraicheurMaillage(a: maintenant) == .ancien }
}
