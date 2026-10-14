import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import SwiftUI
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 8 : la scene reunit les graphes des deux protocoles (`EntreeScene`), chacun avec ses crochets (classement,
/// chefs, mise en avant, libelles, pieces, apparence), et le mode des liens (`ModeLiens`) ne vaut que pour Zigbee. Les deux
/// rejeux (`ReferenceRejeuTests`, `ReferenceRejeuZigbeeTests`) tiennent chacun l'autre protocole eteint ; ces tests tiennent
/// les deux allumes.
@MainActor
@Suite("Scene reunie : Thread et Zigbee")
struct EntreeSceneTests {
    /// La demo de Thread, plus le maillage et les noms de la demo de Zigbee : une coque qui montre les deux reseaux (la demo
    /// combinee est a l'etape 3b ; ici le modele de Zigbee recoit ses donnees comme le ferait sa sonde).
    static func deuxReseaux() -> Surveillance {
        let s = SurveillanceTests.demo()
        s.zigbee.nomsPont = NomsDemo.maisonPont
        s.zigbee.recevoirReleveMaison(NomsDemo.releveMaison)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: MaillageDemoZigbee.fin)
        return s
    }

    /// Les liens, sans leur ordre.
    static func liens(_ e: EntreeScene) -> Set<GrapheReseau.Lien> { Set(e.scene.liens) }

    /// Noeuds et liens de la scene reunie : l'union de ceux des deux scenes seules, avec les attributs que chaque protocole
    /// leur donne ; aucun lien entre protocoles.
    @Test func sceneReunieEstLUnionDesDeux() throws {
        let seulThread = EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees())
        let seulZigbee = EntreeScene(surveillance: SurveillanceZigbeeTests.demoZigbee(), places: PlacesGardees())
        let reunie = EntreeScene(surveillance: Self.deuxReseaux(), places: PlacesGardees())
        let idsThread = Set(seulThread.scene.noeuds.map(\.id)), idsZigbee = Set(seulZigbee.scene.noeuds.map(\.id))
        #expect(!idsThread.isEmpty && !idsZigbee.isEmpty)
        #expect(idsThread.allSatisfy { $0.protocole == .thread } && idsZigbee.allSatisfy { $0.protocole == .zigbee })
        #expect(Set(reunie.scene.noeuds.map(\.id)) == idsThread.union(idsZigbee))
        #expect(reunie.scene.noeuds.count == seulThread.scene.noeuds.count + seulZigbee.scene.noeuds.count,
                "chaque noeud une fois")
        #expect(Self.liens(reunie) == Self.liens(seulThread).union(Self.liens(seulZigbee)))
        #expect(reunie.scene.liens.count == seulThread.scene.liens.count + seulZigbee.scene.liens.count)
        #expect(reunie.scene.liens.allSatisfy { $0.de.protocole == $0.vers.protocole }, "jamais un lien entre protocoles")
        #expect(Set(reunie.graphe.noeuds.map(\.id)) == idsThread.union(idsZigbee))
        #expect(Set(reunie.graphe.liens) == Set(seulThread.graphe.liens).union(seulZigbee.graphe.liens))
        // Chaque noeud garde ce que le crochet de son protocole lui donne : libelle, rang et rayon (classement), couronne, pile,
        // apparence, appareil.
        for seule in [seulThread, seulZigbee] {
            for n in seule.scene.noeuds {
                let m = try #require(reunie.scene.noeud(n.id), "\(n.id.cle)")
                #expect(m.libelle == n.libelle && m.genre == n.genre && m.partition == n.partition && m.routeur == n.routeur)
                #expect(m.rang == n.rang && m.rayon == n.rayon, "classement de son protocole : \(n.id.cle)")
                #expect(m.chef == n.chef && m.pile == n.pile && m.inconnu == n.inconnu && m.bordure == n.bordure)
                #expect(reunie.libelles[n.id] == seule.libelles[n.id])
                #expect(reunie.apparences[n.id] == seule.apparences[n.id], "apparence de son protocole : \(n.id.cle)")
                #expect(reunie.appareils[n.id] == seule.appareils[n.id])
            }
        }
        #expect(reunie.chefs == seulThread.chefs.union(seulZigbee.chefs))
        #expect(reunie.maillageThread == seulThread.maillageThread && reunie.maillageZigbee == seulZigbee.maillageZigbee)
        #expect(seulThread.maillageZigbee == nil && seulZigbee.maillageThread == nil)
    }

    /// Les liens radio de Thread sont toujours montres, quel que soit `ModeLiens` ; celui de Zigbee ne s'applique qu'a ses
    /// liens : en mode « chemins », ses chemins vers le pont et pas ses liens radio ; en mode « tous », ses liens radio et
    /// pas ses chemins.
    @Test func modeLiensNeVautQueZigbee() throws {
        let e = EntreeScene(surveillance: Self.deuxReseaux(), places: PlacesGardees())
        let m = MoteurPiecesTests.moteur(e)
        func projetes(_ mode: ModeLiens) throws -> [SceneProjetee.Lien] {
            m.liens = mode
            MoteurPiecesTests.dessiner(m)
            return try #require(m.projetee).liensRouteurs
        }
        let radiosThread = e.scene.liens.filter { $0.de.protocole == .thread && $0.genre == .radio }.count
        let radiosZigbee = e.scene.liens.filter { $0.de.protocole == .zigbee && $0.genre == .radio }.count
        let cheminsZigbee = e.scene.liens.filter { $0.de.protocole == .zigbee && $0.genre == .chemin }.count
        try #require(radiosThread > 0 && radiosZigbee > 0 && cheminsZigbee > 0)
        for mode in ModeLiens.allCases {
            let l = try projetes(mode)
            #expect(l.filter { $0.protocole == .thread && $0.genre == .radio && !$0.voisin }.count == radiosThread,
                    "les liens radio de Thread, en mode \(mode.rawValue)")
            #expect(l.filter { $0.protocole == .thread }.allSatisfy { !$0.voisin })
        }
        let chemins = try projetes(.chemins)
        #expect(chemins.filter { $0.protocole == .zigbee && $0.genre == .chemin }.count == cheminsZigbee)
        #expect(chemins.filter { $0.protocole == .zigbee && $0.genre == .radio }.isEmpty, "sans selection, pas de voisin entendu")
        let tous = try projetes(.tous)
        #expect(tous.filter { $0.protocole == .zigbee && $0.genre == .radio }.count == radiosZigbee)
        #expect(tous.filter { $0.protocole == .zigbee && $0.genre == .chemin }.isEmpty)
        // Le moteur dit quels protocoles ignorent le mode : ceux dont le modele ne le suit pas.
        #expect(m.protocolesSansMode == [.thread])
        #expect(MoteurPiecesTests.moteur(EntreeScene(surveillance: SurveillanceZigbeeTests.demoZigbee(),
                                                     places: PlacesGardees())).protocolesSansMode == [.thread])
    }

    /// La mise en avant d'un noeud est celle du protocole de ce noeud, sur le graphe reuni : Thread montre toujours ses
    /// voisins radio (le choix des voisins est celui de Zigbee), Zigbee suit le mode des liens et le choix des voisins.
    @Test func miseEnAvantParProtocole() throws {
        let s = Self.deuxReseaux()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let seulThread = EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees())
        let seulZigbee = EntreeScene(surveillance: SurveillanceZigbeeTests.demoZigbee(), places: PlacesGardees())
        let routeurThread = try #require(e.scene.noeuds.first { $0.id.protocole == .thread && $0.routeur && !$0.chef }).id
        let routeurZigbee = try #require(e.scene.noeuds.first { $0.id.protocole == .zigbee && $0.routeur && !$0.chef }).id
        for (liens, voisins) in [(ModeLiens.chemins, false), (.chemins, true), (.tous, false), (.tous, true)] {
            let t = try #require(e.miseEnAvant(de: routeurThread, liens: liens, voisins: voisins))
            #expect(t == seulThread.miseEnAvant(de: routeurThread, liens: liens, voisins: voisins))
            #expect(t == FocusThread.miseEnAvant(de: routeurThread, graphe: e.graphe, chefs: e.chefs, voisins: true),
                    "Thread montre ses voisins radio quels que soient le mode et le choix des voisins")
            #expect(t.noeuds.allSatisfy { $0.protocole == .thread })
            let z = try #require(e.miseEnAvant(de: routeurZigbee, liens: liens, voisins: voisins))
            #expect(z == seulZigbee.miseEnAvant(de: routeurZigbee, liens: liens, voisins: voisins))
            #expect(z == FocusZigbee.miseEnAvant(de: routeurZigbee, graphe: e.graphe, voisins: liens == .tous || voisins))
            #expect(z.noeuds.allSatisfy { $0.protocole == .zigbee })
        }
        // Les voisins de Zigbee suivent le mode ; ceux de Thread non.
        let sansVoisins = try #require(e.miseEnAvant(de: routeurZigbee, liens: .chemins, voisins: false))
        let avecVoisins = try #require(e.miseEnAvant(de: routeurZigbee, liens: .chemins, voisins: true))
        #expect(sansVoisins.liens.count < avecVoisins.liens.count)
        #expect(e.miseEnAvant(de: routeurThread, liens: .chemins, voisins: false)
                == e.miseEnAvant(de: routeurThread, liens: .tous, voisins: true))
        // Un noeud absent, ou d'un protocole que la scene ne porte pas : rien.
        #expect(e.miseEnAvant(de: IdNoeud(.zigbee, routeurThread.cle), liens: .tous, voisins: true) == nil)
        #expect(e.miseEnAvant(de: IdNoeud(.thread, routeurZigbee.cle), liens: .tous, voisins: true) == nil)
    }

    /// Une cle de Zigbee qui serait aussi une cle de Thread ne se lit pas dans l'etat de Thread : le noeud n'est ni connu, ni
    /// renommable, ni nomme par lui.
    @Test func fichePasLueDansLEtatDUnAutreProtocole() throws {
        let s = Self.deuxReseaux()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let r = try #require(s.thread.reseau)
        let routeur = try #require(r.routeurs.first)
        let thread = IdNoeud(.thread, routeur.instance), zigbee = IdNoeud(.zigbee, routeur.instance)
        #expect(FicheNoeud.connu(thread, dans: s, entree: e))
        #expect(!FicheNoeud.connu(zigbee, dans: s, entree: e), "cle de Thread, noeud de Zigbee : pas dans la scene")
        #expect(FicheNoeud.renommable(thread, dans: s, entree: e) && !FicheNoeud.renommable(zigbee, dans: s, entree: e))
        let ieee = try #require(e.graphe.noeuds.first { $0.id.protocole == .zigbee && $0.routeur }).id
        #expect(FicheNoeud.connu(ieee, dans: s, entree: e) && FicheNoeud.renommable(ieee, dans: s, entree: e))
        #expect(!FicheNoeud.connu(IdNoeud(.thread, ieee.cle), dans: s, entree: e), "cle de Zigbee, noeud de Thread")
        // Courbes : l'historique est celui du protocole du noeud.
        #expect(!FicheNoeud.courbesVisibles(de: zigbee, dans: s) && !FicheNoeud.courbesVisibles(de: thread, dans: s))
        s.zigbee.historiqueDeCapture(MaillageDemoZigbee.historique)
        #expect(FicheNoeud.courbesVisibles(de: zigbee, dans: s) && !FicheNoeud.courbesVisibles(de: thread, dans: s))
    }

    /// Les libelles d'un graphe qui porte les deux protocoles : Thread ne lit ses noms de routeurs et son maillage que pour
    /// ses noeuds ; un noeud de Zigbee de meme cle garde son repli (sa cle), sans le nom de Thread.
    @Test func libellesDeThreadIgnorentLesNoeudsDeZigbee() throws {
        let s = Self.deuxReseaux()
        let r = try #require(s.thread.reseau)
        let routeur = try #require(r.routeurs.first)
        s.renommer(IdNoeud(.thread, routeur.instance), en: "Enceinte inventee")
        let intrus = GrapheReseau.Noeud(id: IdNoeud(.zigbee, routeur.instance), genre: .routeur, partition: "zigbee",
                                        routeur: true, bordure: false, inconnu: false, extMac: nil)
        let graphe = GrapheReseau(noeuds: s.thread.graphe.noeuds + [intrus], liens: [])
        let nomsRouteurs = s.thread.nomsRouteurs(pour: r)
        let libelles = LibellesNoeuds.libelles(graphe: graphe, appareils: [:], nomsRouteurs: nomsRouteurs,
                                               maillage: s.thread.maillageAffiche(pour: r), chefs: [])
        #expect(nomsRouteurs[routeur.instance] == "Enceinte inventee", "le surnom donne a Thread distingue les deux noeuds")
        #expect(libelles[IdNoeud(.thread, routeur.instance)]?.nom == "Enceinte inventee")
        #expect(libelles[intrus.id]?.nom == CartesPieces.couper(routeur.instance), "le repli est la cle, jamais le nom de Thread")
    }

    /// Le contenu des fiches suit le protocole du noeud : l'echelle du signal (dBm, LQI) est celle du modele, le survol d'une
    /// courbe de Zigbee donne le LQI, la pastille du chef nomme le role de son protocole, et les modeles disent ce qui
    /// suit le mode des liens.
    @Test func contenuDesFichesParProtocole() throws {
        let s = SurveillanceTests.demo()
        for m in s.modeles {
            #expect(CourbesFiche.echelle(de: m.protocole).unite == m.echelle.unite, "\(m.protocole.rawValue)")
        }
        #expect(CourbesFiche.echelle(de: .thread).unite == "dBm" && CourbesFiche.echelle(de: .zigbee).unite == "LQI")
        #expect(s.thread.suitModeLiens == false && s.zigbee.suitModeLiens == true)
        #expect(PastilleChef.texte(.thread) != PastilleChef.texte(.zigbee))
        #expect(PastilleChef.texte(.zigbee).contains("Zigbee") && PastilleChef.texte(.thread).contains("Thread"))
        let heure = Date(timeIntervalSince1970: 1_700_000_000)
        let avecLQI = PointCourbe(date: heure, valeur: 2, troncon: 0, lqi: 182)
        #expect(GrapheQualite.ligneSurvol("Pont Hue", avecLQI) == String(localized: "\("Pont Hue") : LQI 182"))
        #expect(GrapheQualite.ligneSurvol("X", PointCourbe(date: heure, valeur: 2, troncon: 0))
                == String(localized: "\("X") : \(CourbesFiche.nomQualite(2))"), "sans LQI, la qualite")
        // L'identite du graphe de la fiche porte le protocole : meme cle, autre noeud.
        #expect(CourbesFiche.identiteGraphe(id: IdNoeud(.thread, "a"), tous: false, periode: .jour)
                != CourbesFiche.identiteGraphe(id: IdNoeud(.zigbee, "a"), tous: false, periode: .jour))
    }

    /// La barre et la ligne de tournee du haut ne sont celles de Zigbee que pour une scene qui n'a que Zigbee.
    @Test func protocolesDeLaScene() throws {
        #expect(EntreeScene(surveillance: SurveillanceTests.demo(), places: PlacesGardees()).protocoles == [.thread])
        #expect(EntreeScene(surveillance: SurveillanceZigbeeTests.demoZigbee(), places: PlacesGardees()).protocoles == [.zigbee])
        #expect(EntreeScene(surveillance: Self.deuxReseaux(), places: PlacesGardees()).protocoles == [.thread, .zigbee])
        let vide = Surveillance(mode: .demo, dossier: nil)
        #expect(EntreeScene(surveillance: vide, places: PlacesGardees()).protocoles.isEmpty, "rien demarre : aucun reseau")
    }

    /// Les images de la demo de Zigbee (`--args -demo-zigbee -captures`) : les 29 cas de l'app de Maillage Zigbee, sur sa
    /// maison etagee ; le cas du deplacement d'un appareil se prepare sur la scene de Zigbee seule (sans reseau Thread).
    @Test func capturesDeLaDemoDeZigbee() throws {
        let cas = CapturesPieces.casZigbee
        #expect(cas.count == 29 && Set(cas.map(\.nom)).count == 29)
        #expect(cas.filter { $0.deplacer != nil }.map(\.nom) == ["21-2d-appareil-en-route"])
        #expect(cas.filter(\.listeVoisins).map(\.nom) == ["27-2d-fiche-lampe-bureau"])
        #expect(cas.filter { $0.periode == .semaine }.map(\.nom) == ["28-2d-fiche-lampe-bureau-7j"])
        #expect(cas.filter(\.changementsDeplies).count == 2 && cas.filter(\.legendeRepliee).count == 1)
        let s = SurveillanceZigbeeTests.demoZigbee()
        s.zigbee.noms.maison = NomsDemo.maisonFusionnee
        s.zigbee.historiqueDeCapture(MaillageDemoZigbee.historique)
        let marges = (CGFloat(139), CGFloat(30))
        let enRoute = try #require(cas.first { $0.nom == "21-2d-appareil-en-route" })
        let (m, e) = CapturesPieces.preparer(enRoute, surveillance: s, reseau: nil, marges: marges)
        #expect(m.transition != nil && e.protocoles == [.zigbee])
        let fiche = try #require(cas.first { $0.nom == "13-2d-fiche-du-pont" })
        let (m2, e2) = CapturesPieces.preparer(fiche, surveillance: s, reseau: nil, marges: marges)
        #expect(m2.selection == IdNoeud(.zigbee, NomsDemo.Ieee.pont) && FicheNoeud.connu(IdNoeud(.zigbee, NomsDemo.Ieee.pont),
                                                                                         dans: s, entree: e2))
        #expect(FicheNoeud.courbesVisibles(de: IdNoeud(.zigbee, NomsDemo.Ieee.pont), dans: s), "l'historique invente des captures")
    }
}
