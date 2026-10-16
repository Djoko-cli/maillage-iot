import AppKit
import Foundation
import MaillageCoeur
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Barre des menus : icone")
struct MenuTests {
    @Test func icone() throws {
        #expect(IconeBarre.image(alerte: false).isTemplate)
        #expect(!IconeBarre.image(alerte: true).isTemplate, "orange : pas une image modele")
        // Le seul symbole du maillage, sans badge : le canevas est celui du symbole du systeme.
        let maillage = try #require(NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                                           accessibilityDescription: nil))
        for alerte in [false, true] {
            let icone = IconeBarre.image(alerte: alerte)
            #expect(icone.size == maillage.size, "aucun badge : \(icone.size) pour \(maillage.size)")
            #expect(icone.accessibilityDescription == "Maillage IoT")
        }
    }

    /// « Ouvrir le graphe » et « Journal… » ferment le menu, comme « Reglages… » (01b0a42) : l'app inactive, le menu
    /// restait ouvert (reverification du 02/10). Les deux boutons passent par `MenuBarre.ouvrir` : la fenetre demandee
    /// s'ouvre, puis celle du menu, ici une fenetre hors ecran, se ferme. (Les boutons ne se pressent pas d'un test :
    /// SwiftUI n'y construit pas leur accessibilite.)
    @Test(arguments: ["graphe", "journal"]) func ouvrirUneFenetreFermeLeMenu(_ id: String) {
        let menu = NSPanel(contentRect: NSRect(x: -6000, y: -6000, width: 320, height: 200), styleMask: [.borderless],
                           backing: .buffered, defer: false)
        menu.isReleasedWhenClosed = false
        menu.orderFrontRegardless()
        defer { menu.orderOut(nil) }
        var ouvertes: [String] = []
        #expect(menu.isVisible)
        MenuBarre.ouvrir(id, par: { ouvertes.append($0) }, menu: menu)
        #expect(ouvertes == [id], "la fenetre demandee")
        #expect(!menu.isVisible, "le menu se ferme")
    }

    /// Un bloc par protocole actif, l'un sous l'autre, Thread d'abord : son titre (l'etat de son reseau) et ses chiffres. Un
    /// protocole eteint n'a pas de bloc, et son texte (« Ecoute du reseau local… » pour Thread) n'est dit nulle part.
    @Test func unBlocParProtocoleActif() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        let ecoute = String(localized: "Écoute du réseau local…")
        var blocs = MenuBarre.blocs(s)
        #expect(blocs.map(\.protocole) == [.thread, .zigbee])
        #expect(blocs[0].titre == ecoute && blocs[0].etat == .attente && blocs[0].lignes.isEmpty, "Thread n'a rien entendu")
        let r = s.zigbee.resume
        #expect(r != nil && blocs[1].etat == .normal)
        #expect(blocs[1].titre == String(localized: "Réseau Zigbee normal"))
        #expect(blocs[1].lignes == [String(localized: "Routeurs : \(r?.routeurs ?? 0) · appareils : \(r?.appareils ?? 0) · injoignables : \(r?.injoignables ?? 0)")])
        // Thread eteint : plus de bloc, et plus de « Ecoute du reseau local… ».
        s.thread.actif = false
        blocs = MenuBarre.blocs(s)
        #expect(blocs.map(\.protocole) == [.zigbee])
        #expect(!blocs.flatMap { [$0.titre] + $0.lignes }.contains(ecoute))
        // Zigbee eteint aussi : aucun bloc, le menu le dit une fois.
        s.zigbee.actif = false
        #expect(MenuBarre.blocs(s).isEmpty)
        #expect(MenuBarre.titreSansProtocole == String(localized: "Aucun protocole actif"))
        // Thread seul rallume : son bloc, pas celui de Zigbee.
        s.thread.actif = true
        #expect(MenuBarre.blocs(s).map(\.protocole) == [.thread])
        s.zigbee.actif = true
        #expect(MenuBarre.blocs(s).map(\.protocole) == [.thread, .zigbee])
    }

    /// Le bloc de Thread : le nom du reseau et ses partitions, puis les chiffres ; en demo, seul le protocole rejoue a un bloc
    /// (l'autre, muet, n'est pas « en attente »).
    @Test func blocDeThreadEnDemo() throws {
        let s = SurveillanceTests.demo()
        let blocs = MenuBarre.blocs(s)
        #expect(blocs.map(\.protocole) == [.thread], "la demo de Thread : Zigbee, muet, n'a pas de bloc")
        let r = try #require(s.thread.resume)
        #expect(blocs[0].lignes == [String(localized: "\(r.nom) · partitions : \(r.partitions)"),
                                    String(localized: "Routeurs : \(r.routeurs) · appareils : \(r.appareils) · injoignables : \(r.injoignables)")])
        #expect(blocs[0].titre == MenuBarre.titreThread(s.thread, alerte: s.alerte(de: .thread)))
        #expect(blocs[0].etat == (s.alerte(de: .thread) ? .alerte : .normal))
        #expect(MenuBarre.blocs(SurveillanceZigbeeTests.demoZigbee()).map(\.protocole) == [.zigbee])
    }

    /// Le bloc de Zigbee dit « en attente » tant que la sonde n'a rien donne, et l'alerte de l'heure est celle de Zigbee seul.
    @Test func blocDeZigbeeAlerteEtAttente() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.actif = false
        #expect(MenuBarre.blocs(s).first?.titre == String(localized: "En attente du maillage de la sonde…"))
        #expect(MenuBarre.blocs(s).first?.etat == .attente)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        s.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-1", nom: "Prise"))], de: .zigbee)
        #expect(MenuBarre.blocs(s).first?.titre == String(localized: "Alerte Zigbee dans l'heure"))
        #expect(MenuBarre.blocs(s).first?.etat == .alerte)
        // Une alerte de Thread ne fait pas celle de Zigbee.
        let t = Surveillance(mode: .direct, dossier: nil)
        t.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        t.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-2", nom: "HomePod"))], de: .thread)
        #expect(MenuBarre.blocs(t).last?.etat == .normal, "l'alerte de Thread n'est pas celle de Zigbee")
    }
}
