import Foundation
import Network
import Testing
import dnssd
@testable import MaillageIoT

// Banc de l'etape 3a, anomalie A : le refus NoAuth (-65555) de mDNSResponder (type Bonjour non declare pour macOS, liste
// NSBonjourServices perimee) se voit, distinct du refus du reseau local (PolicyDenied).

@MainActor
@Suite("Bonjour : type non declare pour macOS")
struct BonjourNonDeclareTests {
    @Test func noAuthEstUnCasPropre() {
        #expect(NavigateurBonjour.etat(.dns(DNSServiceErrorType(kDNSServiceErr_NoAuth))) == .nonDeclare)
    }

    @Test func policyDeniedResteLeRefusDuReseauLocal() {
        #expect(NavigateurBonjour.etat(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))) == .refuse)
    }

    /// La decouverte du pont transmet les deux drapeaux, l'un sans l'autre.
    @Test func decouverteTransmetLeNonDeclare() {
        let ecoute = BonjourFactice(type: DecouvertePont.type)
        let d = DecouvertePont(navigateur: ecoute)
        var refus: [Bool] = []
        var nonDeclare: [Bool] = []
        d.surRefus = { refus.append($0) }
        d.surNonDeclare = { nonDeclare.append($0) }
        d.demarrer()
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        #expect(nonDeclare.last == true && refus.last == false)
        ecoute.etat = .refuse
        ecoute.surChangement?()
        #expect(nonDeclare.last == false && refus.last == true)
        ecoute.etat = .pret
        ecoute.surChangement?()
        #expect(nonDeclare.last == false && refus.last == false)
        d.arreter()
    }

    /// Du navigateur factice jusqu'a `NomsPont` : le drapeau est expose, a cote de `reseauLocalRefuse`.
    @Test func nomsPontExposeLeDrapeau() async throws {
        let b = try BancActivation(zigbee: false)
        defer { b.nettoyer() }
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        let pont = ArretNomsPontTests.banc()
        let ecoute = BonjourFactice(type: DecouvertePont.type)
        let decouverte = DecouvertePont(navigateur: ecoute)
        ModulesApp.relierZigbee(b.s, sonde: z.sonde, nomsPont: pont.pont, decouverte: decouverte)
        decouverte.demarrer()
        #expect(!pont.pont.bonjourNonDeclare && !pont.pont.reseauLocalRefuse)
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        #expect(pont.pont.bonjourNonDeclare && !pont.pont.reseauLocalRefuse)
        ecoute.etat = .refuse
        ecoute.surChangement?()
        #expect(!pont.pont.bonjourNonDeclare && pont.pont.reseauLocalRefuse)
        ecoute.etat = .pret
        ecoute.surChangement?()
        #expect(!pont.pont.bonjourNonDeclare && !pont.pont.reseauLocalRefuse)
        decouverte.arreter()
    }

    /// A l'arret de la decouverte, les deux drapeaux retombent : un Zigbee eteint ne garde pas le message rouge.
    @Test func arretRemetLesDrapeauxAZero() async throws {
        let ecoute = BonjourFactice(type: DecouvertePont.type)
        let d = DecouvertePont(navigateur: ecoute)
        var refus: [Bool] = []
        var nonDeclare: [Bool] = []
        d.surRefus = { refus.append($0) }
        d.surNonDeclare = { nonDeclare.append($0) }
        d.demarrer()
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        #expect(nonDeclare.last == true)
        d.arreter()
        #expect(nonDeclare.last == false && refus.last == false)
        d.demarrer()
        ecoute.etat = .refuse
        ecoute.surChangement?()
        #expect(refus.last == true)
        d.arreter()
        #expect(nonDeclare.last == false && refus.last == false)

        // Jusqu'a `NomsPont` : un Zigbee eteint ne garde pas le message.
        let b = try BancActivation(zigbee: false)
        defer { b.nettoyer() }
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        let pont = ArretNomsPontTests.banc()
        let decouverte = DecouvertePont(navigateur: ecoute)
        ModulesApp.relierZigbee(b.s, sonde: z.sonde, nomsPont: pont.pont, decouverte: decouverte)
        decouverte.demarrer()
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        #expect(pont.pont.bonjourNonDeclare)
        decouverte.arreter()
        #expect(!pont.pont.bonjourNonDeclare && !pont.pont.reseauLocalRefuse)
    }

    /// Le texte des Reglages dit le remede, sans parler du reseau local. Les trois extraits suivent la langue du lancement des
    /// tests (`-testLanguage fr`, puis `en`) : en francais, ceux d'aujourd'hui, mot pour mot.
    @Test func texteEnClair() throws {
        let francais = ThreadRouteTests.langue == "fr"
        guard francais || ThreadRouteTests.langue == "en" else {
            throw ThreadRouteTests.ErreurLangue(langue: ThreadRouteTests.langue)
        }
        let t = ReglagesPont.texteNonDeclare
        #expect(t.contains(francais ? "macOS refuse la recherche du pont Hue" : "macOS refuses the app's search for the Hue bridge"))
        #expect(t.contains(francais ? "redémarrez le Mac" : "restart the Mac"))
        #expect(!t.contains(francais ? "Réseau local" : "Local Network"))
    }

    /// La sonde Zigbee en Wi-Fi (`_maillage-zigbee._tcp`) : meme drapeau, remis a zero a l'arret.
    @Test func sondeZigbeeExposeLeDrapeau() async throws {
        let z = try ArretSondeZigbeeTests.banc()
        defer { z.nettoyer() }
        z.sonde.demarrer()
        let ecoute = try #require(z.bonjour.crees.first)
        #expect(ecoute.type == "_maillage-zigbee._tcp" && !z.sonde.bonjourNonDeclare)
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        #expect(z.sonde.bonjourNonDeclare)
        ecoute.etat = .pret
        ecoute.surChangement?()
        #expect(!z.sonde.bonjourNonDeclare)
        ecoute.etat = .nonDeclare
        ecoute.surChangement?()
        z.sonde.arreter()
        #expect(!z.sonde.bonjourNonDeclare)
    }

    /// Le recenseur de Thread ne perd pas ce refus : il le montre comme une erreur.
    @Test func recenseurLeMontreCommeUneErreur() {
        let fab = FabriqueBonjour()
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100))
        r.demarrer()
        fab.crees[0].etat = .nonDeclare
        fab.crees[0].surChangement?()
        if case .erreur = r.etat {} else { Issue.record("etat du recenseur : \(r.etat)") }
        r.arreter()
    }
}
