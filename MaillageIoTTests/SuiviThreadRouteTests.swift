import AppKit
import Foundation
import Testing
@testable import MaillageIoT

/// Le suivi de l'etat de Thread Route (page Diagnostic des Reglages) : relu au retour de l'app au premier
/// plan, sans fenetre ni etat reel du Mac. Les tests ont leur centre de notifications et leur lecture.
@Suite("Thread Route : son suivi", .serialized)
@MainActor
struct SuiviThreadRouteTests {
    /// Une lecture simulee : rend l'etat courant, et compte les lectures.
    final class Lecture {
        var etat: EtatThreadRoute
        private(set) var lectures = 0

        init(_ etat: EtatThreadRoute) { self.etat = etat }

        func lire() -> EtatThreadRoute {
            lectures += 1
            return etat
        }
    }

    /// Une page affichee (ou non), changeable en cours de test.
    final class Page {
        var affichee: Bool
        init(_ affichee: Bool) { self.affichee = affichee }
    }

    static func suivi(_ lecture: Lecture, _ page: Page, _ centre: NotificationCenter) -> SuiviThreadRoute {
        SuiviThreadRoute(lecture: lecture.lire, affiche: { page.affichee }, centre: centre)
    }

    /// Attend une condition, au plus 5 s : les notifications sont rendues sur la file principale.
    static func attendre(_ condition: () -> Bool) async -> Bool {
        let fin = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < fin {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Laisse passer les notifications deja postees : elles sont rendues sur la file principale, dans l'ordre.
    static func laisserPasser() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func etatLuUneFoisALaCreation() {
        let lecture = Lecture(.aApprouver)
        let suivi = Self.suivi(lecture, Page(true), NotificationCenter())
        #expect(suivi.etat == .aApprouver)
        #expect(lecture.lectures == 1)
    }

    /// Le parcours de l'approbation : l'onglet montre « a approuver », on revient de Reglages Systeme,
    /// l'etat change ; chaque retour relit, pas seulement le premier.
    @Test func chaqueRetourAuPremierPlanRelitLEtat() async {
        let centre = NotificationCenter()
        let lecture = Lecture(.absent)
        let suivi = Self.suivi(lecture, Page(true), centre)
        #expect(suivi.etat == .absent)
        lecture.etat = .aApprouver
        centre.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(await Self.attendre { suivi.etat == .aApprouver }, "premier retour")
        lecture.etat = .actif
        centre.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(await Self.attendre { suivi.etat == .actif }, "second retour : la fenetre est gardee")
        #expect(lecture.lectures == 3, "une lecture a la creation, une par retour")
    }

    /// Hors de la page Diagnostic, un retour ne lit rien ; des qu'elle est l'onglet retenu, il relit.
    @Test func horsDeLaPageDiagnosticUnRetourNeLitRien() async {
        let centre = NotificationCenter()
        let lecture = Lecture(.absent)
        let page = Page(false)
        let suivi = Self.suivi(lecture, page, centre)
        lecture.etat = .actif
        centre.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Self.laisserPasser()
        #expect(lecture.lectures == 1, "page non affichee : aucune lecture")
        #expect(suivi.etat == .absent)
        page.affichee = true
        centre.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(await Self.attendre { suivi.etat == .actif })
        #expect(lecture.lectures == 2)
    }

    /// Seul le retour au premier plan declenche la relecture, pas une autre notification.
    @Test func uneAutreNotificationNeRelitPas() async {
        let centre = NotificationCenter()
        let lecture = Lecture(.absent)
        let suivi = Self.suivi(lecture, Page(true), centre)
        lecture.etat = .actif
        centre.post(name: NSApplication.didResignActiveNotification, object: nil)
        await Self.laisserPasser()
        #expect(lecture.lectures == 1)
        #expect(suivi.etat == .absent)
    }

    /// `relire` (l'onglet qui s'affiche) lit toujours, et `relireSiAffiche` (la fenetre qui se rouvre) suit la page.
    @Test func relireEtRelireSiAffiche() {
        let lecture = Lecture(.absent)
        let page = Page(false)
        let suivi = Self.suivi(lecture, page, NotificationCenter())
        lecture.etat = .ancien
        suivi.relireSiAffiche()
        #expect(suivi.etat == .absent, "page non affichee")
        #expect(lecture.lectures == 1)
        suivi.relire()
        #expect(suivi.etat == .ancien)
        lecture.etat = .actif
        page.affichee = true
        suivi.relireSiAffiche()
        #expect(suivi.etat == .actif)
        #expect(lecture.lectures == 3)
    }

    /// Un suivi disparu ne relit plus : le centre n'appelle rien sur un objet libere.
    @Test func unSuiviLiberaNeRelitPlus() async {
        let centre = NotificationCenter()
        let lecture = Lecture(.absent)
        var suivi: SuiviThreadRoute? = Self.suivi(lecture, Page(true), centre)
        #expect(suivi?.etat == .absent)
        suivi = nil
        centre.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Self.laisserPasser()
        #expect(lecture.lectures == 1)
    }

    /// L'onglet retenu de la fenetre, sans fenetre : l'identifiant du choix courant, ou nil.
    @Test func ongletCourantSuitLeChoix() {
        let onglets = OngletsReglages()
        #expect(onglets.ongletCourant == nil, "aucun onglet")
        for o in OngletReglages.allCases {
            let item = NSTabViewItem(viewController: NSViewController())
            item.identifier = o.rawValue
            onglets.addTabViewItem(item)
        }
        for (i, o) in OngletReglages.allCases.enumerated() {
            onglets.selectedTabViewItemIndex = i
            #expect(onglets.ongletCourant == o)
        }
    }
}
