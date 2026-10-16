import AppKit
import Foundation
import MaillageCoeur
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Notifications par protocole, menu et icone de la barre (etape 3b, tache 8 ; spec 3.5 et 6.7, decision 4).
@MainActor
@Suite("Notifications par protocole")
struct NotificationsParProtocoleTests {
    private static func prefs() throws -> PreferencesMemoire {
        try #require(PreferencesMemoire(domaine: "notif-\(UUID())"))
    }

    private static func alerte(_ categorie: CategorieAlerte, de protocole: Protocole?) -> AlerteAEnvoyer {
        let e = Evenement(date: Date(timeIntervalSince1970: 1_700_000_000), type: .routeurDisparu,
                          sujet: Sujet(id: "ID-1", nom: "Appareil 1"), protocole: protocole)
        return AlerteAEnvoyer(categorie: categorie, identifiant: "a-\(categorie.rawValue)", evenements: [e])
    }

    // MARK: Reprise des cles communes

    /// Les cles de 3a (`notification.<categorie>`) passent aux cles par protocole a la premiere lecture : une categorie
    /// coupee en 3a reste coupee pour les deux protocoles, une categorie allumee reste allumee, et une categorie jamais
    /// touchee garde son defaut. Zigbee n'a pas de scission : pas de cle pour lui.
    @Test func reprisesDesClesCommunes() throws {
        let p = try Self.prefs()
        p.set(false, forKey: "notification.pertes")
        p.set(false, forKey: "notification.scission")
        p.set(true, forKey: "notification.informations")
        // Avant meme la reprise, la lecture suit la cle commune : rien n'est perdu.
        for protocole in Protocole.allCases {
            #expect(!Notifications.active(.pertes, de: protocole, preferences: p), "coupee en 3a : \(protocole)")
            #expect(Notifications.active(.informations, de: protocole, preferences: p), "allumee en 3a : \(protocole)")
            #expect(Notifications.active(.routeurDisparu, de: protocole, preferences: p), "defaut : \(protocole)")
        }
        Notifications.reprendreClesCommunes(preferences: p)
        for protocole in Protocole.allCases {
            #expect(p.object(forKey: "notification.\(protocole.rawValue).pertes") as? Bool == false)
            #expect(p.object(forKey: "notification.\(protocole.rawValue).informations") as? Bool == true)
            #expect(p.object(forKey: "notification.\(protocole.rawValue).routeurDisparu") == nil, "jamais touchee : rien d'ecrit")
        }
        #expect(p.object(forKey: "notification.thread.scission") as? Bool == false, "la scission est de Thread")
        #expect(p.object(forKey: "notification.zigbee.scission") == nil, "Zigbee n'a pas de scission")
        // Les cles communes restent (une version precedente de l'app les relit).
        #expect(p.object(forKey: "notification.pertes") as? Bool == false)
        // Chaque protocole est ensuite maitre de la sienne ; une seconde reprise n'ecrase rien.
        p.set(true, forKey: Notifications.cle(.pertes, de: .thread))
        Notifications.reprendreClesCommunes(preferences: p)
        #expect(Notifications.active(.pertes, de: .thread, preferences: p))
        #expect(!Notifications.active(.pertes, de: .zigbee, preferences: p), "l'autre protocole garde la sienne")
    }

    /// Sans aucune preference, les defauts sont ceux d'avant et les memes pour les deux protocoles.
    @Test func defautsIdentiques() throws {
        let p = try Self.prefs()
        Notifications.reprendreClesCommunes(preferences: p)
        for protocole in Protocole.allCases {
            for c in Notifications.categories(de: protocole) {
                #expect(Notifications.active(c, de: protocole, preferences: p) == c.parDefaut, "\(protocole) \(c)")
            }
        }
        #expect(Notifications.categories(de: .thread) == [.scission, .routeurDisparu, .pertes, .informations])
        #expect(Notifications.categories(de: .zigbee) == [.routeurDisparu, .pertes, .informations])
        // Zigbee n'a pas de routeur de « bordure » ; les autres libelles sont communs.
        #expect(Notifications.titre(.routeurDisparu, de: .zigbee) == String(localized: "Routeur disparu"))
        #expect(Notifications.titre(.routeurDisparu, de: .thread) == String(localized: "Routeur de bordure disparu"))
        #expect(Notifications.titre(.pertes, de: .zigbee) == Notifications.titre(.pertes, de: .thread))
        #expect(Notifications.cle(.scission, de: .thread) == "notification.thread.scission")
        #expect(Notifications.cle(.pertes, de: .zigbee) == "notification.zigbee.pertes")
    }

    // MARK: Chaque protocole a son interrupteur

    /// Une alerte obeit a l'interrupteur de son protocole, et a lui seul : Zigbee coupe, une alerte de Zigbee ne part pas,
    /// celle de Thread part ; et inversement. Sans protocole, une alerte est de Thread.
    @Test func notificationSelonSonProtocole() throws {
        let p = try Self.prefs()
        p.set(false, forKey: Notifications.cle(.routeurDisparu, de: .zigbee))
        let deThread = Self.alerte(.routeurDisparu, de: .thread)
        let deZigbee = Self.alerte(.routeurDisparu, de: .zigbee)
        let sansProtocole = Self.alerte(.routeurDisparu, de: nil)
        #expect(deZigbee.protocole == .zigbee && deThread.protocole == .thread && sansProtocole.protocole == .thread)
        #expect(Notifications.aPresenter([deThread, deZigbee, sansProtocole], preferences: p) == [deThread, sansProtocole],
                "Zigbee coupe : l'alerte de Zigbee seule ne part pas")
        p.set(true, forKey: Notifications.cle(.routeurDisparu, de: .zigbee))
        p.set(false, forKey: Notifications.cle(.routeurDisparu, de: .thread))
        #expect(Notifications.aPresenter([deThread, deZigbee, sansProtocole], preferences: p) == [deZigbee],
                "Thread coupe : celle de Zigbee part, celles de Thread non")
        // Une categorie coupee pour un protocole ne coupe pas les autres categories de ce protocole.
        let pertesZigbee = Self.alerte(.pertes, de: .zigbee)
        #expect(Notifications.aPresenter([pertesZigbee], preferences: p) == [pertesZigbee])
    }

    // MARK: Menu et icone

    /// Chaque bloc d'alerte du menu dit son protocole : deux blocs « Alerte dans l'heure » sans nom ne disaient pas lequel
    /// des deux reseaux etait en cause (final m3 de 3a).
    @Test func menuAlerteAvecProtocole() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.zigbee.recevoir(MaillageDemoZigbee.maillage, a: Date())
        s.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-1", nom: "Prise"))], de: .zigbee)
        s.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-2", nom: "HomePod"))], de: .thread)
        let blocs = MenuBarre.blocs(s)
        let thread = blocs.first { $0.protocole == .thread }
        let zigbee = blocs.first { $0.protocole == .zigbee }
        #expect(zigbee?.etat == .alerte)
        #expect(zigbee?.titre == String(localized: "Alerte Zigbee dans l'heure"))
        #expect(zigbee?.titre.contains("Zigbee") == true && zigbee?.titre.contains("Thread") == false)
        // Thread : son titre d'alerte nomme Thread (sans releve, son bloc ecoute encore le reseau local).
        #expect(thread != nil)
        #expect(MenuBarre.titreAlerte(.thread) == String(localized: "Alerte Thread dans l'heure"))
        #expect(MenuBarre.titreAlerte(.thread).contains("Thread") && !MenuBarre.titreAlerte(.thread).contains("Zigbee"))
        #expect(MenuBarre.titreAlerte(.thread) != MenuBarre.titreAlerte(.zigbee))
        #expect(MenuBarre.titreZigbee(resume: s.zigbee.resume, alerte: true) == MenuBarre.titreAlerte(.zigbee))
    }

    /// L'icone prend le pire des protocoles ACTIFS : orange si l'un d'eux est en alerte ; un protocole eteint ne la colore
    /// jamais, meme avec une alerte ecrite avant son arret.
    @Test func iconeDuPireDesProtocolesActifs() {
        let s = Surveillance(mode: .direct, dossier: nil)
        #expect(!s.alerte && IconeBarre.image(alerte: s.alerte).isTemplate, "calme : image modele")
        s.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-1", nom: "Prise"))], de: .zigbee)
        #expect(s.alerte && !IconeBarre.image(alerte: s.alerte).isTemplate, "Zigbee en alerte : orange")
        s.ajouter([Evenement(date: Date(), type: .routeurDisparu, sujet: Sujet(id: "ID-2", nom: "HomePod"))], de: .thread)
        #expect(s.alerte, "les deux en alerte")
        s.zigbee.actif = false
        #expect(s.alerte, "Thread, actif, reste en alerte")
        s.thread.actif = false
        #expect(!s.alerte && IconeBarre.image(alerte: s.alerte).isTemplate, "les deux eteints : jamais orange")
        s.zigbee.actif = true
        #expect(s.alerte, "Zigbee rallume : son alerte de l'heure revient")
        s.thread.actif = true
        s.zigbee.actif = false
        #expect(s.alerte, "Thread seul actif et en alerte")
    }
}
