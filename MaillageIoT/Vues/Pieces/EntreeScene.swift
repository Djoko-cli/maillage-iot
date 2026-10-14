import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI

/// Ce que la vue par pieces montre des reseaux, tire de la surveillance (spec de la vue par pieces, section 2) : la scene,
/// le libelle et l'apparence de chaque noeud, et la maison de ses places gardees ; avec ce dont la scene est faite, construit
/// une fois avec elle a chaque rendu (le graphe, les maillages rapproches, les chefs, les appareils), que la fiche et
/// « Placer dans une piece… » lisent ici, sans rien reconstruire : ils voient les memes noeuds, les memes cles et les memes
/// chefs que la scene.
///
/// C'est le point de jonction des protocoles : le graphe de la scene est l'union de ceux des protocoles qui ont un reseau a
/// montrer (jamais un lien d'un protocole a l'autre : un lien relie deux noeuds du meme), et chaque protocole fournit ses
/// crochets sur son sous-graphe : libelles, pieces, chefs, apparence, classement, mise en avant. Aucun crochet ne se replie
/// sur celui d'un autre protocole : le protocole d'un noeud (`IdNoeud.protocole`) choisit, par un `switch` sans defaut.
struct EntreeScene: Equatable {
    var scene: ScenePieces
    var libelles: [IdNoeud: LibellesNoeuds.Libelle]
    var apparences: [IdNoeud: DessinNoeud.Apparence]
    /// Domicile de la maison ("" sans nom) : la cle de ses places gardees. Celui de Maison quand Thread a un reseau a
    /// montrer, sinon celui du pont (Zigbee).
    var domicile: String
    /// Noeuds et liens des reseaux : l'union des graphes de Thread et de Zigbee.
    var graphe: GrapheReseau
    /// Maillage de la sonde de Thread rapproche du reseau ; nil sans sonde, ou s'il est perime, ou sans reseau Thread.
    var maillageThread: MaillageAffiche?
    /// Maillage de la sonde de Zigbee ; nil sans sonde, ou s'il est perime.
    var maillageZigbee: MaillageZigbee?
    /// Noeuds couronnes : le chef de chaque partition Thread (celui du maillage de la sonde), le coordinateur de Zigbee ;
    /// ceux des libelles ; la couronne suit ceux-ci partout ou elle parait.
    var chefs: Set<IdNoeud>
    /// Appareils affiches, par id.
    var appareils: [IdNoeud: AppareilAffiche]
    /// Les modeles de protocole de la coque : leur mise en avant et le choix de leurs voisins, par protocole du noeud.
    let modeles: [any ModeleProtocole]

    /// `reseau` : le reseau de Thread a montrer (nil : Thread n'en a pas) ; `places` : les places gardees, dont l'ordre des
    /// etages de la maison et ses choix de niveau ; `choix` : les pieces choisies pour les noeuds que Maison ne place pas,
    /// routeurs de bordure (sous leur instance) et autres noeuds (sous leur ExtMac, precision 27 ; sous leur adresse
    /// longue pour Zigbee). Zigbee est de la scene quand il a un maillage ou des appareils du pont.
    @MainActor
    init(surveillance: Surveillance, reseau r: Reseau?, places: PlacesGardees, choix: PiecesRouteurs = PiecesRouteurs()) {
        let thread = surveillance.thread, zigbee = surveillance.zigbee
        // Thread : son sous-graphe, ses chefs, ses libelles et ses pieces.
        var appareils: [IdNoeud: AppareilAffiche] = [:]
        var libelles: [IdNoeud: LibellesNoeuds.Libelle] = [:]
        var pieces: [IdNoeud: String] = [:]
        var chefs: Set<IdNoeud> = []
        var noeuds: [GrapheReseau.Noeud] = []
        var liens: [GrapheReseau.Lien] = []
        var affiches: [AppareilAffiche] = []
        var maison: NomsMaison?
        let maillageThread = r.flatMap { thread.maillageAffiche(pour: $0) }
        if let r {
            let a = thread.appareilsAffiches(pour: r)
            let g = GrapheReseau(reseau: r, appareils: a, maillage: maillageThread)
            let parId = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
            let c = LibellesNoeuds.chefs(reseau: r, maillage: thread.maillage, affiche: maillageThread)
            let nomsRouteurs = thread.nomsRouteurs(pour: r)
            maison = thread.noms.maison
            libelles.merge(LibellesNoeuds.libelles(graphe: g, appareils: parId, nomsRouteurs: nomsRouteurs,
                                                   maillage: maillageThread, chefs: c)) { x, _ in x }
            pieces.merge(LibellesNoeuds.pieces(reseau: r, appareils: a, maison: maison, nomsRouteurs: nomsRouteurs,
                                               choix: choix, graphe: g, maillage: maillageThread)) { x, _ in x }
            appareils.merge(parId) { x, _ in x }
            chefs.formUnion(c)
            noeuds += g.noeuds
            liens += g.liens
            affiches += a
        }
        // Zigbee : de meme, a ses etiquettes pres (`LibellesNoeudsZigbee`).
        let maillageZigbee = zigbee.maillageAffiche
        var maisonZigbee: NomsZigbee?
        if zigbee.aUnReseau {
            let a = zigbee.appareilsAffiches
            let g = GrapheReseau(maillage: maillageZigbee, appareils: a)
            let parId = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
            let c = LibellesNoeuds.chefs(g)
            maisonZigbee = zigbee.noms.maison
            libelles.merge(LibellesNoeuds.libelles(graphe: g, appareils: parId, nom: zigbee.nom, chefs: c)) { x, _ in x }
            pieces.merge(LibellesNoeuds.pieces(appareils: a, maison: maisonZigbee, choix: choix, graphe: g)) { x, _ in x }
            appareils.merge(parId) { x, _ in x }
            chefs.formUnion(c)
            noeuds += g.noeuds
            liens += g.liens
            affiches += a
        }
        let graphe = GrapheReseau(noeuds: noeuds, liens: liens)
        // La maison : celle de Maison (Thread) d'abord, sinon celle du pont (Zigbee). Le releve de Maison est le meme pour les
        // deux modeles (le pont n'en ajoute que ses appareils) : une scene qui a les deux montre celle de Maison.
        let domicile = maison?.domicile ?? maisonZigbee?.domicile ?? ""
        let zones = maison?.zones ?? maisonZigbee?.zones
        let piecesMaison = maison?.accessoires.contains { $0.piece?.isEmpty == false } == true
            || maisonZigbee?.accessoires.contains { $0.piece?.isEmpty == false } == true
        let gardees = places.maison(domicile)
        // La scene voit les noms sans leurs badges : un badge qui change ne la change pas (polissage D, section 2).
        let scene = ScenePieces(graphe: graphe, libelles: libelles.mapValues(\.nom), piecesNoeuds: pieces,
                                zones: zones, chefs: chefs, piecesMaison: piecesMaison,
                                ordreEtages: gardees.ordreEtages, aCote: gardees.aCote,
                                piles: Set(affiches.filter { $0.batterie != nil }.map(\.id)),
                                classement: Self.classement(thread: thread.classement, zigbee: zigbee.classement))
        let principale = r?.partitions.first(where: \.estPrincipale)?.id
        self.scene = scene
        self.libelles = libelles
        self.domicile = domicile
        self.graphe = graphe
        self.maillageThread = maillageThread
        self.maillageZigbee = maillageZigbee
        self.chefs = chefs
        modeles = surveillance.modeles
        self.appareils = appareils
        apparences = Dictionary(scene.noeuds.map { n in
            let a = appareils[n.id]
            let apparence: DessinNoeud.Apparence = switch n.id.protocole {
            case .thread:
                DessinNoeud.apparence(n, etat: a?.etat, principale: n.partition == principale,
                                      sonde: n.id.cle == maillageThread?.sonde, verifie: a?.verifie == true)
            case .zigbee:
                // Zigbee n'a qu'une partition : un noeud est toujours de la couleur principale, sans anneau verifie.
                DessinNoeud.apparence(n, etat: a?.etat, principale: true, sonde: n.id.cle == maillageZigbee?.sonde,
                                      verifie: false)
            }
            return (n.id, apparence)
        }, uniquingKeysWith: { x, _ in x })
    }

    /// La scene de la surveillance : le reseau de Thread affiche (`SurveillanceThread.reseau`) et celui de Zigbee.
    @MainActor
    init(surveillance: Surveillance, places: PlacesGardees, choix: PiecesRouteurs = PiecesRouteurs()) {
        self.init(surveillance: surveillance, reseau: surveillance.thread.reseau, places: places, choix: choix)
    }

    /// Le classement des noeuds : la regle du protocole de chaque noeud, jamais celle d'un autre (le `switch` n'a pas de defaut :
    /// un troisieme protocole ne compile pas sans la sienne).
    static func classement(thread: @escaping @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double),
                           zigbee: @escaping @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double))
        -> @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) {
        { n in
            switch n.id.protocole {
            case .thread: thread(n)
            case .zigbee: zigbee(n)
            }
        }
    }

    /// Les protocoles qui ont au moins un noeud dans la scene.
    var protocoles: Set<Protocole> { Set(graphe.noeuds.map(\.id.protocole)) }

    /// Le modele du protocole `protocole` ; nil si la coque n'en porte pas.
    @MainActor
    func modele(pour protocole: Protocole) -> (any ModeleProtocole)? {
        modeles.first { $0.protocole == protocole }
    }

    /// Egalite de ce que la vue dessine : la scene, les libelles, les apparences et le domicile. Ce dont
    /// la scene est faite n'y entre pas : un maillage recu plus tard, qui ne change rien a la scene, ne
    /// la fait pas reposer par le moteur (`MoteurPieces.recevoir`).
    static func == (a: EntreeScene, b: EntreeScene) -> Bool {
        a.scene == b.scene && a.libelles == b.libelles && a.apparences == b.apparences && a.domicile == b.domicile
    }

    /// Mode focus du graphe : ce qui reste net a la selection du noeud `id`, calcule par le modele de son protocole
    /// (`ModeleProtocole.miseEnAvant` : `FocusThread`, `FocusZigbee`) sur le graphe de cette scene et ses chefs. Les voisins
    /// entendus ne sont un choix que pour un protocole qui suit le mode des liens (`ModeleProtocole.suitModeLiens`, Zigbee :
    /// montres en mode « tous », ou si `voisins` le veut en mode « chemins ») ; Thread montre toujours ses voisins radio. Le
    /// moteur, generique, ne fait que l'appeler (`MoteurPieces.majMiseEnAvant`). nil si la coque ne porte pas ce protocole.
    @MainActor
    func miseEnAvant(de id: IdNoeud, liens: ModeLiens, voisins: Bool) -> MiseEnAvant? {
        guard let m = modele(pour: id.protocole) else { return nil }
        return m.miseEnAvant(de: id, graphe: graphe, chefs: chefs, voisins: !m.suitModeLiens || liens == .tous || voisins)
    }

    /// Ce qui oblige a recalculer la disposition : celle de la scene, sans les badges des noms (polissage D, section 2).
    typealias CleDisposition = ScenePieces.CleDisposition

    var cleDisposition: CleDisposition { scene.cleDisposition }
}
