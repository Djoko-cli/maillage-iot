import CoreGraphics
import Foundation
import Testing
@testable import MaillageCoeur
@testable import ProtocoleZigbee

/// Etape 5 : le mode focus du graphe de Zigbee (la fonction de Zigbee ; la partie generique est testee au coeur), le
/// contenu des colonnes de la fiche, et le choix des courbes de l'historique. Sur la demo (valeurs inventees).
@Suite("Mode focus Zigbee, fiche en colonnes et choix des courbes")
struct FocusEtFicheZigbeeTests {
    typealias I = NomsDemo.Ieee

    static let graphe = GrapheReseau(maillage: MaillageDemoZigbee.maillage, appareils: [])

    static func paire(_ a: String, _ b: String) -> String { MiseEnAvant.cle(a, b) }

    // MARK: Zigbee

    /// La lampe de la chambre : son chemin complet jusqu'au pont (par la lampe du bureau, puis le lampadaire du salon),
    /// ses dependants (deux routeurs qui passent par elle, ses deux appareils, dont la telecommande au parent d'avant),
    /// et ses voisins entendus selon le bouton ; rien d'autre.
    @Test func focusDUnRouteur() throws {
        let g = Self.graphe
        let avec = try #require(FocusZigbee.miseEnAvant(de: I.lampeChambre, graphe: g, voisins: true))
        let chemin: Set<String> = [I.lampeChambre, I.lampeBureau, I.lampadaireSalon, I.pont]
        let dependants: Set<String> = [I.lampeChambreAmis, I.lampeSalleDeBain, I.interrupteurSalon, I.telecommandeChambre]
        #expect(avec.noeuds == chemin.union(dependants))
        #expect(avec.liens == [Self.paire(I.lampeChambre, I.lampeBureau), Self.paire(I.lampeBureau, I.lampadaireSalon),
                               Self.paire(I.lampadaireSalon, I.pont), Self.paire(I.lampeChambreAmis, I.lampeChambre),
                               Self.paire(I.lampeSalleDeBain, I.lampeChambre), Self.paire(I.interrupteurSalon, I.lampeChambre),
                               Self.paire(I.telecommandeChambre, I.lampeChambre)],
                "ses voisins entendus sont aussi ses dependants ou son prochain saut")
        // Les dependants du focus sont ceux de `dependants` (une seule source), voisins ou non.
        let sansVoisins = try #require(FocusZigbee.miseEnAvant(de: I.lampeChambre, graphe: g, voisins: false))
        let siens = FocusZigbee.dependants(de: I.lampeChambre, graphe: g)
        #expect(siens.count == 4 && siens.allSatisfy { sansVoisins.contient(lien: $0) && avec.contient(lien: $0) })
        // Sans les voisins : le meme ici ; pour la lampe du bureau, son voisin le pont s'efface.
        #expect(sansVoisins == avec)
        let bureau = try #require(FocusZigbee.miseEnAvant(de: I.lampeBureau, graphe: g, voisins: true))
        let bureauSans = try #require(FocusZigbee.miseEnAvant(de: I.lampeBureau, graphe: g, voisins: false))
        #expect(bureau.liens.contains(Self.paire(I.lampeBureau, I.pont)) && bureau.noeuds.contains(I.sonde))
        #expect(!bureauSans.liens.contains(Self.paire(I.lampeBureau, I.pont)))
        #expect(bureauSans.noeuds.contains(I.pont), "le pont reste : il est au bout de son chemin")
        #expect(bureau.liens.subtracting(bureauSans.liens) == [Self.paire(I.lampeBureau, I.pont)])
    }

    /// Un appareil final : son parent, puis le chemin du parent ; sans dependant ni voisin. Le pont : ses dependants
    /// directs (les routeurs dont le prochain saut est lui, l'appareil dont il est le parent), ses voisins selon le
    /// bouton. Un noeud absent : pas de focus. Une boucle de chemins s'arrete.
    @Test func focusDUnAppareilEtDuPont() throws {
        let g = Self.graphe
        let interrupteur = try #require(FocusZigbee.miseEnAvant(de: I.interrupteurSalon, graphe: g, voisins: true))
        #expect(interrupteur.noeuds == [I.interrupteurSalon, I.lampeChambre, I.lampeBureau, I.lampadaireSalon, I.pont])
        #expect(interrupteur.liens.count == 4)
        let pont = try #require(FocusZigbee.miseEnAvant(de: I.pont, graphe: g, voisins: false))
        #expect(pont.noeuds == [I.pont, I.plafonnierSalon, I.lampadaireSalon, I.suspensionCuisine, I.detecteurEntree])
        let pontVoisins = try #require(FocusZigbee.miseEnAvant(de: I.pont, graphe: g, voisins: true))
        #expect(pontVoisins.noeuds.subtracting(pont.noeuds) == [I.lampeBureau])
        #expect(FocusZigbee.miseEnAvant(de: "A0000000000000EE", graphe: g, voisins: true) == nil)
        let boucle = GrapheReseau(noeuds: [.init(zigbee: "P", genre: .centre, routeur: true, inconnu: false),
                                           .init(zigbee: "A", genre: .routeur, routeur: true, inconnu: false),
                                           .init(zigbee: "B", genre: .routeur, routeur: true, inconnu: false)],
                                  liens: [.init(de: "A", vers: "B", genre: .chemin), .init(de: "B", vers: "A", genre: .chemin)])
        #expect(FocusZigbee.miseEnAvant(de: "A", graphe: boucle, voisins: true)?.noeuds == ["A", "B"])
    }

    // MARK: Fiche

    /// Les voisins entendus de la lampe de la chambre, leur resume par qualite (comme la legende : 0 compte en faible)
    /// et leur tri, de la meilleure qualite a la plus faible ; ses dependants, les routeurs d'abord ; les routeurs qui
    /// parlent directement au pont ; la date des qualites.
    @Test func contenuDesColonnes() {
        let m = MaillageDemoZigbee.maillage
        let nom: (String) -> String = { NomsDemo.maisonPont.accessoire(ieee: $0)?.nom ?? $0 }
        let v = FicheZigbee.voisins(de: I.lampeChambre, maillage: m)
        #expect(Set(v.map(\.id)) == [I.lampeBureau, I.lampeChambreAmis, I.lampeSalleDeBain])
        let r = ResumeVoisins(v)
        #expect(r.total == 3 && r.nombre(.bonne) == 2 && r.nombre(.moyenne) == 0 && r.nombre(.faible) == 1)
        #expect(r.parts.map(\.niveau) == [.bonne, .faible])
        #expect(ResumeVoisins.trier(v, nom: nom).map(\.id) == [I.lampeBureau, I.lampeChambreAmis, I.lampeSalleDeBain],
                "190/185, puis 178/172, puis 104/97 (faible : 97)")
        let melange = [VoisinFiche(id: "x", qualite: nil), VoisinFiche(id: "b", qualite: 0, lqiIci: 40),
                       VoisinFiche(id: "a", qualite: 3, lqiIci: 200, lqiLa: 180), VoisinFiche(id: "c", qualite: 3, lqiIci: 210),
                       VoisinFiche(id: "d", qualite: 3, lqiIci: 210)]
        #expect(ResumeVoisins.trier(melange, nom: { $0 }).map(\.id) == ["c", "d", "a", "b", "x"])
        #expect(ResumeVoisins(melange).nombre(.faible) == 1 && ResumeVoisins(melange).nombre(.inconnue) == 1)
        let d = DependantFiche.trier(FicheZigbee.dependants(de: I.lampeChambre, maillage: m), nom: nom)
        #expect(d.map(\.id) == [I.lampeChambreAmis, I.lampeSalleDeBain, I.interrupteurSalon, I.telecommandeChambre])
        #expect(d.map(\.routeur) == [true, true, false, false])
        #expect(d.first?.qualite == 3 && d.last?.qualite == nil, "le parent d'avant n'a pas de qualite")
        #expect(FicheZigbee.dependants(de: I.interrupteurSalon, maillage: m).isEmpty)
        #expect(FicheZigbee.routeursDirects(m) == 3)
        #expect(FicheZigbee.routeursDirects(MaillageZigbee(date: m.date)) == 0)
        #expect(FicheZigbee.dateQualites(m) == m.date)
    }

    // MARK: Courbes

    /// Sur l'historique invente de la demo : la lampe du bureau change onze fois de prochain saut (dix changements
    /// proches l'un de l'autre, puis un autre il y a 10 h : des reperes, `ReperesCourbeTests`) ; ses
    /// courbes prioritaires sont le lien vers son prochain saut (le plus recent d'abord), puis ses dependants (la lampe
    /// de la chambre, la sonde), du plus faible au meilleur ; le pont, sans chemin, montre ses dependants ; un appareil
    /// final n'a qu'une courbe, vers son parent, avec ses changements de parent.
    @Test func courbesEtChoix() throws {
        let h = MaillageDemoZigbee.historique
        #expect(h.count == 93, "97 releves moins une heure sans releve")
        let fin = MaillageDemoZigbee.fin
        let bureau = CourbesNoeud(zigbee: I.lampeBureau, releves: h, periode: .jour, fin: fin)
        #expect(bureau.chemins.map(\.parent) == Array(repeating: [I.lampadaireSalon, I.pont], count: 5).flatMap { $0 } + [I.lampadaireSalon])
        #expect(bureau.prioritaires.prefix(2) == [I.lampadaireSalon, I.pont], "le prochain saut, le plus recent d'abord")
        #expect(Set(bureau.prioritaires.dropFirst(2)) == [I.lampeChambre, I.sonde])
        #expect(bureau.liens.first { $0.id == I.lampeChambre }?.points.allSatisfy { $0.lqi != nil } == true)
        #expect(bureau.liens.first { $0.id == I.lampeChambre }?.points.map(\.troncon).max() == 1, "le trou d'une heure")
        let pont = CourbesNoeud(zigbee: I.pont, releves: h, periode: .jour, fin: fin)
        let cles = pont.liens.map(\.id)
        #expect(pont.chemins.isEmpty && pont.parents.isEmpty)
        let montrees = ChoixCourbes.montrees(cles: cles, prioritaires: pont.prioritaires, tous: false)
        #expect(montrees == Array(pont.prioritaires.prefix(6)) && montrees.count <= ChoixCourbes.maximum)
        #expect(Set(pont.prioritaires).isSuperset(of: [I.plafonnierSalon, I.lampadaireSalon, I.suspensionCuisine]))
        let abri = CourbesNoeud(zigbee: I.detecteurAbri, releves: h, periode: .jour, fin: fin)
        #expect(abri.liens.map(\.id) == [CourbesNoeud.cleParent] && abri.prioritaires == [CourbesNoeud.cleParent])
        #expect(abri.parents.map(\.parent) == [I.priseTerrasse] && abri.chemins.isEmpty)
    }
}
