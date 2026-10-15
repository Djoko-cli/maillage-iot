import CoreGraphics
import Foundation
import Testing
@testable import MaillageCoeur

/// Scene d'identifiants types (etape 3a, conception B) : deux noeuds de meme cle mais de protocoles differents restent
/// deux noeuds, et rien de ce que la scene calcule (teinte, tri, libelle de repli, cle de lien) ne depend du protocole.
@Suite("Scene : identifiants types par protocole")
struct SceneNeutreTests {
    static func noeud(_ id: IdNoeud, genre: GrapheReseau.Genre = .appareil, partition: String = "p",
                      routeur: Bool = false) -> GrapheReseau.Noeud {
        .init(id: id, genre: genre, partition: partition, routeur: routeur, bordure: false, inconnu: false)
    }

    static func scene(_ noeuds: [GrapheReseau.Noeud], liens: [GrapheReseau.Lien] = [],
                      libelles: [IdNoeud: String] = [:], pieces: [IdNoeud: String] = [:],
                      piecesMaison: Bool = true) -> ScenePieces {
        ScenePieces(graphe: GrapheReseau(noeuds: noeuds, liens: liens), libelles: libelles, piecesNoeuds: pieces,
                    zones: nil, chefs: [], piecesMaison: piecesMaison, classement: FixturesScene.classement)
    }

    /// Un appareil a deux radios : la meme cle des deux cotes. Deux noeuds, deux disques, deux libelles, deux poses.
    @Test func scenePasDeCollisionEntreProtocoles() throws {
        let t = idt("0000000000000001"), z = idt("0000000000000001", .zigbee)
        let s = Self.scene([Self.noeud(t), Self.noeud(z, partition: "zigbee")],
                           liens: [.init(de: z, vers: t, genre: .radio, qualite: 2)],
                           libelles: [t: "Radio Thread", z: "Radio Zigbee"], pieces: [t: "Salon", z: "Salon"])
        #expect(s.noeuds.count == 2)
        #expect(s.noeud(t)?.libelle == "Radio Thread" && s.noeud(z)?.libelle == "Radio Zigbee")
        #expect(try #require(s.indice(t)) != (try #require(s.indice(z))))
        #expect(s.pieces.count == 1 && Set(s.pieces[0].noeuds) == [t, z])
        let c = CartesPieces.cartes(s, largeurs: [t: 40, z: 90])
        let d = DispositionPieces(scene: s, cartes: c)
        let poses = PosesScene(scene: s, cartes: c, positions: d.positions)
        #expect(poses.noeuds.count == 2 && poses.noeuds[t] != nil && poses.noeuds[z] != nil)
        let g = GeometrieMaison(rayons: d.rayons)
        let p = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g,
                              etat: EtatAnime(t: 0, fk: Array(repeating: 0, count: s.pieces.count)),
                              orbite: CameraScene.canonique(g, aspect: 1.5, u: 0),
                              cadre: CGRect(x: 0, y: 0, width: 1200, height: 800))
        #expect(p.disques.count == 2 && Set(p.disques.map(\.noeud)) == [t, z] && p.ancresNoeuds.count == 2)
        // La largeur de chacun est la sienne : les deux cartes de noeud ne partagent pas une entree de dictionnaire.
        let seul = CartesPieces.cartes(s, largeurs: [t: 40, z: 40])
        #expect(c != seul, "la largeur du noeud Zigbee compte, distincte de celle du noeud Thread")
    }

    /// Le masquage d'un protocole (interrupteurs de vue, etape 3b) n'agit qu'au dessin : la disposition et les poses sont
    /// celles de la scene entiere, la projection ne dessine ni les pastilles, ni les liens, ni les fils « ailleurs » du
    /// protocole masque, et ne touche ni aux pieces ni aux noeuds des autres protocoles.
    @Test func masquageAuDessinSeulement() throws {
        let t = idt("0000000000000001"), t2 = idt("0000000000000002"), z = idt("0000000000000001", .zigbee)
        let z2 = idt("0000000000000002", .zigbee)
        let s = Self.scene([Self.noeud(t, genre: .routeur, routeur: true), Self.noeud(t2),
                            Self.noeud(z, genre: .routeur, partition: "zigbee", routeur: true),
                            Self.noeud(z2, partition: "zigbee")],
                           liens: [.init(de: t2, vers: t, genre: .parent), .init(de: z2, vers: z, genre: .parent),
                                   .init(de: z, vers: z2, genre: .radio, qualite: 2)],
                           libelles: [t: "A", t2: "B", z: "C", z2: "D"], pieces: [t: "Cuisine", t2: "Salon", z: "Cuisine", z2: "Salon"])
        let c = CartesPieces.cartes(s, largeurs: [:])
        let d = DispositionPieces(scene: s, cartes: c)
        let g = GeometrieMaison(rayons: d.rayons)
        func projeter(_ masques: Set<Protocole>, focus: Int? = nil) -> SceneProjetee {
            let e = EtatAnime(t: 0, s: focus == nil ? 0 : 1, fk: s.pieces.indices.map { $0 == focus ? 1 : 0 }, focus: focus,
                              masques: masques)
            return SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e,
                                 orbite: CameraScene.canonique(g, aspect: 1.5, u: 0),
                                 cadre: CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let tout = projeter([]), sansZigbee = projeter([.zigbee]), sansThread = projeter([.thread])
        #expect(tout.disques.count == 4 && Set(tout.disques.map(\.noeud)) == [t, t2, z, z2])
        #expect(Set(sansZigbee.disques.map(\.noeud)) == [t, t2] && Set(sansThread.disques.map(\.noeud)) == [z, z2])
        let liens = { (p: SceneProjetee) in Set((p.liensEnfants + p.liensRouteurs).map(\.protocole)) }
        #expect(liens(tout) == [.thread, .zigbee] && liens(sansZigbee) == [.thread] && liens(sansThread) == [.zigbee])
        // Les pieces et la place de ce qui reste ne bougent pas : memes blocs, memes ancres, memes pastilles.
        #expect(sansZigbee.blocs.count == tout.blocs.count && sansZigbee.ancresPieces == tout.ancresPieces)
        #expect(sansZigbee.plateaux.count == tout.plateaux.count && sansZigbee.ancresEtages == tout.ancresEtages)
        #expect(sansZigbee.centresNoeuds == tout.centresNoeuds, "les places sont celles de la scene entiere")
        for id in [t, t2] {
            #expect(sansZigbee.disques.first { $0.noeud == id }?.centre == tout.disques.first { $0.noeud == id }?.centre)
        }
        #expect(sansThread.disques.first { $0.noeud == z }?.centre == tout.disques.first { $0.noeud == z }?.centre)
        // Un fil « ailleurs » du protocole masque (la piece isolee) n'est pas dessine.
        let salon = try #require(s.pieces.firstIndex { $0.nom == .maison("Salon") })
        let ailleursTout = projeter([], focus: salon)
        let ailleursSans = projeter([.zigbee], focus: salon)
        #expect(ailleursTout.ailleurs.contains { $0.enfant.protocole == .zigbee })
        #expect(ailleursSans.ailleurs.allSatisfy { $0.enfant.protocole == .thread })
        #expect(ailleursTout.fils.count == 2 && ailleursSans.fils.count == 1)
        // La disposition est faite sur la scene, avant tout dessin : elle ne lit pas le masque (aucun parametre).
        #expect(DispositionPieces(scene: s, cartes: c) == d)
    }

    /// La teinte d'une carte de routeur vient de la cle du routeur : elle ne change pas si seul son protocole change.
    @Test func teinteNeutre() throws {
        for cle in ["Salon", "E1000000000000A1", "instance:Palier", "~4F2A", "rloc:0400"] {
            let t = Self.scene([Self.noeud(idt(cle), genre: .centre, routeur: true)], piecesMaison: false)
            let z = Self.scene([Self.noeud(idt(cle, .zigbee), genre: .centre, partition: "zigbee", routeur: true)],
                               piecesMaison: false)
            #expect(t.pieces.map(\.teinte) == z.pieces.map(\.teinte), "\(cle) : meme teinte")
            #expect(t.pieces.map(\.id) == z.pieces.map(\.id), "\(cle) : meme cle de piece, `routeur:<cle>`")
            #expect(t.pieces[0].id == "routeur:" + cle)
            #expect(t.pieces[0].teinte == Int(ScenePieces.fnv1a(cle) % 8))
        }
    }

    /// Un noeud sans libelle montre sa cle, jamais sa forme texte `thread:<cle>`.
    @Test func libelleDeRepliEstLaCle() {
        let z = idt("instance:Salon", .zigbee)
        let s = Self.scene([Self.noeud(idt("A1")), Self.noeud(z)], pieces: [idt("A1"): "Salon", z: "Salon"])
        #expect(s.noeud(idt("A1"))?.libelle == "A1" && s.noeud(z)?.libelle == "instance:Salon")
        #expect(s.noeuds.allSatisfy { !$0.libelle.contains("thread:") && !$0.libelle.contains("zigbee:") })
    }

    /// Le tri d'une carte (rang, libelle, id) ordonne les identifiants par (protocole, cle) : a rang et libelle egaux,
    /// Thread avant Zigbee, puis la cle ; a l'interieur d'un protocole, l'ordre d'avant.
    @Test func triParProtocoleEtCle() throws {
        let noeuds = [idt("B", .zigbee), idt("B"), idt("A", .zigbee), idt("C"), idt("A")]
        let s = Self.scene(noeuds.map { Self.noeud($0) },
                           libelles: Dictionary(uniqueKeysWithValues: noeuds.map { ($0, "Meme nom") }),
                           pieces: Dictionary(uniqueKeysWithValues: noeuds.map { ($0, "Salon") }))
        #expect(s.pieces[0].noeuds == [idt("A"), idt("B"), idt("C"), idt("A", .zigbee), idt("B", .zigbee)])
        #expect(idt("Z") < idt("A", .zigbee) && idt("A") < idt("B"))
    }

    /// Maison sans pieces : deux routeurs de meme cle de deux protocoles ont la meme cle de piece `routeur:<cle>` ; leur ordre
    /// ne depend ni de l'ordre d'entree ni de l'iteration d'un `Set` : Thread d'abord, puis Zigbee (dernier critere du tri).
    @Test func cartesDeRouteursDeMemeCleOrdreStable() {
        let cles = ["A", "B", "C", "D", "E", "F", "G", "H"]
        for tour in 0..<24 {
            var noeuds = cles.flatMap { [idt($0), idt($0, .zigbee)] }
            if tour % 2 == 1 { noeuds.reverse() }
            noeuds.rotate(by: tour)
            let s = Self.scene(noeuds.map { Self.noeud($0, genre: .centre, routeur: true) }, piecesMaison: false)
            let ordre: [IdNoeud] = s.pieces.compactMap { p in
                if case .routeur(let id) = p.nom { id } else { nil }
            }
            #expect(ordre == cles.flatMap { [idt($0), idt($0, .zigbee)] }, "tour \(tour)")
        }
    }

    /// La cle d'un lien dans le mode focus et dans les poses : sans ordre, mais propre a chaque protocole.
    @Test func clesDeLienParProtocole() {
        #expect(MiseEnAvant.cle(idt("A"), idt("B")) == MiseEnAvant.cle(idt("B"), idt("A")))
        #expect(MiseEnAvant.cle(idt("A"), idt("B")) != MiseEnAvant.cle(idt("A", .zigbee), idt("B", .zigbee)))
        // Deux bouts de protocoles differents : un seul ordre, celui de (protocole, cle).
        #expect(MiseEnAvant.cle(idt("A", .zigbee), idt("B")) == MiseEnAvant.cle(idt("B"), idt("A", .zigbee)))
        let l = GrapheReseau.Lien(de: idt("A"), vers: idt("B"), genre: .radio)
        let lz = GrapheReseau.Lien(de: idt("A", .zigbee), vers: idt("B", .zigbee), genre: .radio)
        #expect(PosesScene.cle(l) != PosesScene.cle(lz))
        var m = MiseEnAvant()
        m.ajouter(lien: idt("A"), idt("B"))
        #expect(m.contient(lien: l) && !m.contient(lien: lz) && m.noeuds == [idt("A"), idt("B")])
    }
}

private extension Array {
    mutating func rotate(by n: Int) {
        guard !isEmpty else { return }
        let k = n % count
        self = Array(self[k...] + self[..<k])
    }
}
