import MaillageCoeur
import ProtocoleThread
import SwiftUI

/// Ce que la vue par pieces montre d'un reseau, tire de la surveillance (spec de la vue par pieces,
/// section 2) : la scene, le libelle et l'apparence de chaque noeud, et la maison de ses places
/// gardees ; avec ce dont la scene est faite, construit une fois avec elle a chaque rendu (le graphe,
/// le maillage rapproche, les chefs, les appareils), que la fiche et « Placer dans une piece… » lisent
/// ici, sans rien reconstruire : ils voient les memes noeuds, les memes cles et les memes chefs que la
/// scene.
struct EntreeScene: Equatable {
    var scene: ScenePieces
    var libelles: [IdNoeud: LibellesNoeuds.Libelle]
    var apparences: [IdNoeud: DessinNoeud.Apparence]
    /// Domicile de Maison ("" sans nom) : la cle de ses places gardees.
    var domicile: String
    /// Noeuds et liens du reseau.
    var graphe: GrapheReseau
    /// Maillage de la sonde rapproche du reseau ; nil sans sonde, ou s'il est perime.
    var maillage: MaillageAffiche?
    /// Noeuds couronnes (le chef de chaque partition, celui du maillage de la sonde) : ceux des
    /// libelles ; la couronne suit ceux-ci partout ou elle parait.
    var chefs: Set<IdNoeud>
    /// Appareils affiches, par id.
    var appareils: [IdNoeud: AppareilAffiche]
    /// Le modele du protocole de cette scene (Thread) : son classement des noeuds et sa mise en avant.
    let modele: any ModeleProtocole

    /// `places` : les places gardees, dont l'ordre des etages de la maison et ses choix de niveau ; `choix` :
    /// les pieces choisies pour les noeuds que Maison ne place pas, routeurs de bordure (sous leur instance)
    /// et autres noeuds (sous leur ExtMac, precision 27).
    @MainActor
    init(surveillance: Surveillance, reseau r: Reseau, places: PlacesGardees, choix: PiecesRouteurs = PiecesRouteurs()) {
        let affiches = surveillance.thread.appareilsAffiches(pour: r)
        let maillage = surveillance.thread.maillageAffiche(pour: r)
        let graphe = GrapheReseau(reseau: r, appareils: affiches, maillage: maillage)
        let parId = Dictionary(affiches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let chefs = LibellesNoeuds.chefs(reseau: r, maillage: surveillance.thread.maillage, affiche: maillage)
        let libelles = LibellesNoeuds.libelles(graphe: graphe, appareils: parId,
                                               nomsRouteurs: surveillance.thread.nomsRouteurs(pour: r), maillage: maillage,
                                               chefs: chefs)
        let maison = surveillance.thread.noms.maison
        let domicile = maison?.domicile ?? ""
        let pieces = LibellesNoeuds.pieces(reseau: r, appareils: affiches, maison: maison,
                                           nomsRouteurs: surveillance.thread.nomsRouteurs(pour: r), choix: choix,
                                           graphe: graphe, maillage: maillage)
        // La scene voit les noms sans leurs badges : un badge qui change ne la change pas (polissage D, section 2).
        let scene = ScenePieces(graphe: graphe, libelles: libelles.mapValues(\.nom), piecesNoeuds: pieces,
                                zones: maison?.zones, chefs: chefs,
                                piecesMaison: maison?.accessoires.contains { $0.piece?.isEmpty == false } == true,
                                ordreEtages: places.maison(domicile).ordreEtages, aCote: places.maison(domicile).aCote,
                                piles: Set(parId.filter { $0.value.batterie != nil }.keys),
                                classement: surveillance.thread.classement)
        let principale = r.partitions.first(where: \.estPrincipale)?.id
        self.scene = scene
        self.libelles = libelles
        self.domicile = domicile
        self.graphe = graphe
        self.maillage = maillage
        self.chefs = chefs
        modele = surveillance.thread
        appareils = parId
        apparences = Dictionary(scene.noeuds.map { n in
            (n.id, DessinNoeud.apparence(n, etat: parId[n.id]?.etat,
                                         principale: n.id.protocole == .thread && n.partition == principale,
                                         sonde: n.id.protocole == .thread && n.id.cle == maillage?.sonde, verifie: parId[n.id]?.verifie == true))
        }, uniquingKeysWith: { a, _ in a })
    }

    /// Egalite de ce que la vue dessine : la scene, les libelles, les apparences et le domicile. Ce dont
    /// la scene est faite n'y entre pas : un maillage recu plus tard, qui ne change rien a la scene, ne
    /// la fait pas reposer par le moteur (`MoteurPieces.recevoir`).
    static func == (a: EntreeScene, b: EntreeScene) -> Bool {
        a.scene == b.scene && a.libelles == b.libelles && a.apparences == b.apparences && a.domicile == b.domicile
    }

    /// Mode focus du graphe : ce qui reste net a la selection du noeud `id`, calcule par le modele du protocole
    /// (`ModeleProtocole.miseEnAvant`, pour Thread `FocusThread`) sur le graphe de cette scene et ses chefs. Le moteur,
    /// generique, ne fait que l'appeler (`MoteurPieces.majMiseEnAvant`).
    @MainActor
    func miseEnAvant(de id: IdNoeud) -> MiseEnAvant? {
        modele.miseEnAvant(de: id, graphe: graphe, chefs: chefs, voisins: true)
    }

    /// Ce qui oblige a recalculer la disposition : celle de la scene, sans les badges des noms (polissage D, section 2).
    typealias CleDisposition = ScenePieces.CleDisposition

    var cleDisposition: CleDisposition { scene.cleDisposition }
}
