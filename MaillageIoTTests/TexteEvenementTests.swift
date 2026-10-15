import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Textes des evenements et des notifications")
struct TexteEvenementTests {
    static func demo() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        return s
    }

    @Test func textes() throws {
        let t = ScenarioPanne.date(4, 14)
        for type in [.surveillanceDemarree, .veille] + TypeEvenement.thread {
            let e = Evenement(date: t, type: type, sujet: Sujet(id: "x", nom: "Nuki Ultra"), avant: "chef", apres: "routeur",
                              periode: type == .veille ? DateInterval(start: t, end: t.addingTimeInterval(60)) : nil)
            #expect(!TexteEvenementThread.titre(e).isEmpty, "\(type)")
        }
        let s = Self.demo()
        guard case .pertes(let pertes)? = s.lignesJournal.first else {
            Issue.record("les pertes regroupees en tete du journal")
            return
        }
        let titre = TexteEvenementThread.titre(LigneJournal.pertes(pertes))
        #expect(titre.contains("5"))
        #expect(titre.contains(TexteEvenementThread.heure(ScenarioPanne.date(4, 20))))
        let scission = try #require(s.evenements.first { $0.type == .reseauScinde })
        #expect(TexteEvenementThread.isoles(scission) == "Aqara HubM100 #DFEB")
        let notification = TexteEvenementThread.notification(AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: pertes))
        #expect(notification.corps.contains("Prise bureau"))
        let vides = try #require(PreferencesMemoire(domaine: "vide-\(UUID())"))
        #expect(Notifications.active(.scission, preferences: vides))
        let videsAussi = try #require(PreferencesMemoire(domaine: "vide-\(UUID())"))
        #expect(!Notifications.active(.informations, preferences: videsAussi))
    }

    /// Evenements du maillage de la sonde : les attentes reprennent les cles du code
    /// (independantes de la langue de l'hote).
    @Test func maillage() {
        let t = ScenarioPanne.date(4, 14)
        let s = Sujet(id: "56B1E064401F74EF", nom: "Prise bureau")
        let change = Evenement(date: t, type: .parentChange, sujet: s, avant: "HomePod salon", apres: "Routeur · 5000")
        #expect(TexteEvenementThread.titre(change)
                == String(localized: "\("Prise bureau") a changé de parent : \("HomePod salon") → \("Routeur · 5000")"))
        #expect(TexteEvenementThread.titre(Evenement(date: t, type: .sansParent, sujet: s, avant: "HomePod salon"))
                == String(localized: "\("Prise bureau") n'a plus de parent"))
        #expect(TexteEvenementThread.titre(Evenement(date: t, type: .routeurThreadApparu, sujet: s))
                == String(localized: "Routeur Thread apparu : \("Prise bureau")"))
        #expect(TexteEvenementThread.titre(Evenement(date: t, type: .routeurThreadDisparu, sujet: s))
                == String(localized: "Routeur Thread disparu : \("Prise bureau")"))
    }

    /// Changements de parent regroupes : le noeud, et leur nombre dans l'heure.
    @Test func parentsRegroupes() {
        let change = Evenement(date: ScenarioPanne.date(4, 14), type: .parentChange,
                               sujet: Sujet(id: "56B1E064401F74EF", nom: "Prise bureau"), avant: "A", apres: "B")
        let n = 4
        #expect(TexteEvenementThread.titre(LigneJournal.parents(Array(repeating: change, count: n)))
                == String(localized: "\("Prise bureau") a changé \(n) fois de parent en 1 h"))
    }

    /// La ligne repliee d'un journal regroupe (repris de Maillage Zigbee, 09/10) : la plage horaire (le jour repete s'il
    /// passe minuit), ce qu'il fait, les relais (« A → B → C · finit sur C », « A ⇄ B · finit sur A »), et chaque
    /// changement deplie (« 14:00 → B »).
    @Test func journalRegroupe() {
        let t = ScenarioPanne.date(4, 14)
        func change(_ minutes: Double, _ avant: String, _ apres: String) -> Evenement {
            Evenement(date: t.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: "x", nom: "X"),
                      avant: avant, apres: apres)
        }
        let groupe = [change(0, "A", "B"), change(20, "B", "C")]
        #expect(TexteEvenementThread.plage(groupe)
                == "\(TexteEvenementThread.jour(t)) \(TexteEvenementThread.heure(t)) – \(TexteEvenementThread.heure(t.addingTimeInterval(1200)))")
        let nuit = [change(0, "A", "B"), change(24 * 60, "B", "A")]
        #expect(TexteEvenementThread.plage(nuit).components(separatedBy: " – ").last?.hasPrefix(TexteEvenementThread.jour(t.addingTimeInterval(86400))) == true)
        #expect(TexteEvenementThread.plage([]) == "")
        let n = 2
        #expect(TexteEvenementThread.changements(.parents(groupe)) == String(localized: "a changé \(n) fois de parent"))
        #expect(TexteEvenementThread.changements(.evenement(groupe[0])).isEmpty)
        #expect(TexteEvenementThread.resume(Regroupement.resumeRelais(groupe))
                == "A → B → C · " + String(localized: "finit sur \("C")"))
        #expect(TexteEvenementThread.resume(Regroupement.resumeRelais([change(0, "A", "B"), change(5, "B", "A")]))
                == "A ⇄ B · " + String(localized: "finit sur \("A")"))
        #expect(TexteEvenementThread.changement(groupe[1]) == "\(TexteEvenementThread.heure(t.addingTimeInterval(1200))) → C")
    }

    /// Une ligne de changements de parent regroupes porte l'heure et le nom du dernier changement
    /// (celui qui la classe dans le journal), pas ceux du premier.
    @Test func parentsRegroupesDuDernierChangement() {
        let avant = Evenement(date: ScenarioPanne.date(4, 14), type: .parentChange,
                              sujet: Sujet(id: "rloc:0401", nom: "Ancien nom"), avant: "A", apres: "B")
        let apres = Evenement(date: ScenarioPanne.date(4, 14).addingTimeInterval(52 * 60), type: .parentChange,
                              sujet: Sujet(id: "rloc:0801", nom: "Nouveau nom"), avant: "B", apres: "A")
        let ligne = LigneJournal.parents([avant, apres])
        #expect(TexteEvenementThread.quand(ligne) == TexteEvenementThread.quand(apres))
        #expect(TexteEvenementThread.quand(ligne) != TexteEvenementThread.quand(avant))
        let n = 2
        #expect(TexteEvenementThread.titre(ligne) == String(localized: "\("Nouveau nom") a changé \(n) fois de parent en 1 h"))
        let seul = Evenement(date: ScenarioPanne.date(4, 14), type: .appareilNouveau, sujet: Sujet(id: "x", nom: "X"))
        #expect(TexteEvenementThread.quand(LigneJournal.evenement(seul)) == TexteEvenementThread.quand(seul))
    }

    /// Point de depart d'un reseau vu apres le lancement : le reseau est nomme.
    @Test func departDUnReseau() {
        let t = ScenarioPanne.date(4, 14)
        let lancement = Evenement(date: t, type: .surveillanceDemarree, details: ["routeurs": "6", "appareils": "24"])
        let reseau = Evenement(date: t, type: .surveillanceDemarree, reseau: "1122334455667788",
                               sujet: Sujet(id: "1122334455667788", nom: "Voisin"),
                               details: ["routeurs": "2", "appareils": "1"])
        let titre = TexteEvenementThread.titre(reseau)
        #expect(titre.contains("Voisin"), "le reseau est nomme")
        #expect(titre.contains("2") && titre.contains("1"))
        #expect(!TexteEvenementThread.titre(lancement).contains("Voisin"))
        #expect(TexteEvenementThread.titre(lancement).contains("24"), "le texte du lancement ne change pas")
    }

    /// Scission constatee : un seul texte, qu'elle soit trouvee au lancement, a la
    /// decouverte ou au retour d'un reseau (francais ou anglais, selon le Mac).
    @Test func scissionTrouvee() {
        let t = ScenarioPanne.date(4, 14)
        var e = Evenement(date: t, type: .reseauScinde, reseau: "1122334455667788",
                          sujet: Sujet(id: "1122334455667788", nom: "Voisin"), avant: "1", apres: "2", constate: true)
        #expect(["Réseau Voisin trouvé scindé", "Network Voisin found split"].contains(TexteEvenementThread.titre(e)))
        e.constate = false
        #expect(["Réseau Voisin scindé en 2 partitions", "Network Voisin split into 2 partitions"]
                .contains(TexteEvenementThread.titre(e)), "observee : inchange")
    }
}
