import Foundation
import MaillageCoeur
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 7 : le modele de Zigbee (`SurveillanceZigbee`) dans la coque, a cote de celui de Thread. Les tests de
/// l'app temporaire (`MaillageIoTZigbeeTests/SurveillanceTests`) y rejoignent a la tache 9 ; ceux-ci posent ce que la
/// fusion change : la coque porte deux modeles, la demo n'en rejoue qu'un, les fichiers vont sous `Zigbee/`, le
/// journal d'un noeud garde le protocole.
@MainActor
@Suite("Surveillance : le modele de Zigbee dans la coque")
struct SurveillanceZigbeeTests {
    typealias I = NomsDemo.Ieee

    static func demoZigbee() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .zigbee)
        s.demarrer()
        return s
    }

    /// La demo de Zigbee, l'autre protocole eteint : le journal, l'alerte de l'heure a l'horloge fixe de la demo, le
    /// resume, les appareils. Thread est muet : ni reseau, ni evenement, ni horloge.
    @Test func demoDeZigbeeSeule() throws {
        let s = Self.demoZigbee()
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .routeurDisparu, .parentChange, .cheminChange])
        #expect(s.evenements.allSatisfy { $0.protocole == .zigbee }, "chaque evenement porte le protocole de son modele")
        #expect(s.alerte, "un routeur disparu dans l'heure de la demo : l'horloge de l'alerte est `maintenant`, pas `Date()`")
        #expect(s.maintenant == MaillageDemoZigbee.fin && s.maintenant(a: .distantFuture) == MaillageDemoZigbee.fin)
        #expect(s.zigbee.fraicheurMaillage(a: s.maintenant) == .frais && !s.zigbee.maillageAncien)
        #expect(s.zigbee.resume == ResumeReseauZigbee(routeurs: 14, appareils: 9, injoignables: 1))
        #expect(s.zigbee.appareilsAffiches.count == 21)
        #expect(s.evenements(de: IdNoeud(.zigbee, I.priseSalon)).first?.type == .routeurDisparu)
        #expect(s.zigbee.historique.isEmpty, "la demo ne garde pas d'historique")
        // Thread, muet.
        #expect(s.thread.instantane == nil && s.thread.maillage == nil && s.thread.dernierReleve == nil)
        #expect(s.thread.noms.maison == nil && s.thread.resume == nil)
        #expect(s.thread.maintenant(a: .distantFuture) == .distantPast, "un modele muet n'impose pas son horloge")
    }

    /// La demo de Thread (par defaut), l'autre protocole eteint : Zigbee n'a ni reseau, ni evenement, ni noms.
    @Test func demoDeThreadLaisseZigbeeMuet() {
        let s = SurveillanceTests.demo()
        #expect(s.evenements.allSatisfy { $0.protocole == .thread })
        #expect(s.zigbee.maillage == nil && s.zigbee.nomsPont == nil && s.zigbee.releveMaison == nil)
        #expect(s.zigbee.graphe.noeuds.isEmpty && s.zigbee.appareils.isEmpty && s.zigbee.resumeMenu == nil)
        #expect(s.zigbee.maintenant(a: .distantFuture) == .distantPast)
        #expect(s.maintenant == s.thread.maintenant(a: Date()), "l'horloge de la demo est celle de Thread")
    }

    /// Le modele de Zigbee repond au protocole d'app que la scene et le menu liront : graphe, appareils, echelle LQI,
    /// classement et mise en avant de Zigbee, resume du menu, fraicheur de 16 et 45 min, pas d'alerte de reseau.
    @Test func modeleZigbeeRepondAuProtocole() throws {
        let s = Self.demoZigbee()
        let m: any ModeleProtocole = s.zigbee
        #expect(m.protocole == .zigbee)
        #expect(!m.graphe.noeuds.isEmpty && m.graphe.noeuds.allSatisfy { $0.id.protocole == .zigbee })
        #expect(m.graphe == GrapheReseau(maillage: s.zigbee.maillageAffiche, appareils: s.zigbee.appareilsAffiches))
        #expect(m.appareils == s.zigbee.appareilsAffiches)
        #expect(m.echelle.unite == EchelleSignal.lqi.unite)
        let noeud = try #require(m.graphe.noeuds.first)
        #expect(m.classement(noeud) == ScenePieces.classementZigbee(noeud))
        #expect(m.miseEnAvant(de: noeud.id, graphe: m.graphe, chefs: [], voisins: false)
                == FocusZigbee.miseEnAvant(de: noeud.id, graphe: m.graphe, voisins: false))
        #expect(m.miseEnAvant(de: IdNoeud(.thread, noeud.id.cle), graphe: m.graphe, chefs: [], voisins: true) == nil,
                "un noeud d'un autre protocole n'est pas de ce modele")
        let r = try #require(s.zigbee.resume)
        #expect(m.resumeMenu == ResumeMenu(routeurs: r.routeurs, appareils: r.appareils, injoignables: r.injoignables))
        #expect(!m.aHistorique && !m.alerteReseau)
        #expect(s.modele(pour: .zigbee) === s.zigbee)
        // Fraicheur : frais jusqu'a 16 min (et pendant une tournee), ancien jusqu'a 45, perime au-dela ; Thread : 6 et 15.
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        func f(_ minutes: Double, tournee: Bool = false) -> Surveillance.Fraicheur {
            SurveillanceZigbee.fraicheur(recu, maintenant: recu.addingTimeInterval(minutes * 60), tourneeEnCours: tournee)
        }
        #expect(f(16) == .frais && f(17) == .ancien && f(17, tournee: true) == .frais)
        #expect(f(45) == .ancien && f(46) == .perime && f(46, tournee: true) == .perime)
        #expect(SurveillanceThread.fraicheur(recu, maintenant: recu.addingTimeInterval(7 * 60)) == .ancien,
                "Thread garde ses seuils de 6 et 15 minutes")
    }

    /// Le journal d'un noeud garde le protocole des deux cotes : le modele de Zigbee ne concerne que les noeuds Zigbee,
    /// et parmi les evenements ceux de Zigbee (sujet ou `details["ieee"]` = la cle), jamais ceux d'un noeud Thread de
    /// meme cle ; celui de Thread, l'inverse.
    @Test func concernantGardeLeProtocole() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let cle = "00124B0001020304"
        let z = Evenement(date: Date(timeIntervalSince1970: 1_790_000_000), type: .parentChange, sujet: Sujet(id: cle, nom: "Prise"),
                          avant: "A", apres: "B", protocole: .zigbee)
        let t = Evenement(date: Date(timeIntervalSince1970: 1_790_000_001), type: .parentChange, sujet: Sujet(id: cle, nom: "Prise"),
                          avant: "A", apres: "B", protocole: .thread)
        let sans = Evenement(date: Date(timeIntervalSince1970: 1_790_000_002), type: .parentChange, sujet: Sujet(id: cle, nom: "Prise"),
                             avant: "A", apres: "B")
        let parIeee = Evenement(date: Date(timeIntervalSince1970: 1_790_000_003), type: .cheminChange,
                                sujet: Sujet(id: "autre", nom: "Autre"), details: ["ieee": cle], protocole: .zigbee)
        let tous = [z, t, sans, parIeee]
        let idZ = IdNoeud(.zigbee, cle), idT = IdNoeud(.thread, cle)
        #expect(tous.filter(s.zigbee.concernant(idZ)) == [z, parIeee], "Zigbee : son sujet, ou son adresse longue ; pas Thread")
        #expect(tous.filter(s.zigbee.concernant(idT)).isEmpty, "le modele de Zigbee ne concerne aucun noeud Thread")
        #expect(tous.filter(s.thread.concernant(idZ)).isEmpty, "ni celui de Thread un noeud Zigbee")
        #expect(tous.filter(s.thread.concernant(idT)) == [t, sans], "Thread : son protocole, ou sans protocole")
        s.ajouter([z.sansProtocole, t.sansProtocole], de: .zigbee)
        #expect(s.evenements(de: idZ).count == 2 && s.evenements(de: idT).isEmpty,
                "la coque dirige vers le modele du protocole du noeud : Zigbee a pose son protocole sur les deux")
    }

    /// Les fichiers de Zigbee vont sous `Zigbee/` du dossier de l'app (jamais a la racine ni sous `Thread/`) : le
    /// maillage garde et l'historique de la sonde, relus au lancement suivant ; le journal et les surnoms restent a la
    /// racine, communs.
    @Test func fichiersSousZigbee() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fm = FileManager.default
        let s = Surveillance(mode: .direct, dossier: dossier)
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: recu, incomplet: true)
        s.renommer(IdNoeud(.zigbee, I.priseSalon), en: "Prise du salon")
        let zigbee = Surveillance.dossierZigbee(dossier)
        #expect(zigbee.lastPathComponent == "Zigbee" && zigbee.deletingLastPathComponent().path == dossier.path)
        #expect(fm.fileExists(atPath: zigbee.appendingPathComponent("dernier-maillage.json").path))
        let contenu = try fm.contentsOfDirectory(atPath: zigbee.path).sorted()
        #expect(contenu.contains { $0.hasPrefix("maillage-") && $0.hasSuffix(".jsonl") }, "l'historique : \(contenu)")
        let racine = try fm.contentsOfDirectory(atPath: dossier.path).sorted()
        #expect(racine.contains("Journal") && racine.contains("surnoms.json") && racine.contains("Zigbee"))
        #expect(!racine.contains("Thread"), "Thread n'a rien ecrit")
        #expect(!racine.contains("dernier-maillage.json"))

        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.zigbee.chargerMaillageGarde()
        await relu.zigbee.chargerHistorique(maintenant: recu.addingTimeInterval(60))
        #expect(relu.zigbee.maillage == MaillageDemoZigbee.maillage && relu.zigbee.maillageRecu == recu)
        #expect(relu.zigbee.maillageIncomplet && relu.zigbee.maillageRelu)
        #expect(relu.zigbee.historique.count == 1, "l'historique relu")
        #expect(relu.thread.maillage == nil, "le maillage garde de Zigbee n'est pas celui de Thread")
        #expect(relu.zigbee.noms.surnoms == [I.priseSalon: "Prise du salon"] && relu.thread.noms.surnoms.isEmpty,
                "le surnom, relu du fichier commun, ne va qu'au resolveur de Zigbee")
    }

    /// Le releve de Maison et les noms du pont se fusionnent dans le modele de Zigbee ; Thread garde le releve tel quel.
    @Test func releveMaisonFusionneAvecLePont() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.zigbee.nomsPont = NomsDemo.maisonPont
        s.recevoirReleveMaison(NomsDemo.releveMaison)
        #expect(s.zigbee.noms.maison != nil && s.zigbee.bilanFusion != nil, "les noms du pont, nommes par Maison")
        #expect(s.thread.noms.maison == NomsDemo.releveMaison)
        s.recevoirReleveMaison(nil)
        #expect(s.thread.noms.maison == nil && s.zigbee.releveMaison == nil)
    }
}

private extension Evenement {
    /// Le meme evenement sans protocole (comme un evenement tout juste produit par un module).
    var sansProtocole: Evenement {
        var e = self
        e.protocole = nil
        return e
    }
}
