import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import Testing
@testable import MaillageIoT

/// Etape 3a, tache 13 : un seul journal pour les deux protocoles. Chaque evenement porte son protocole et garde sa gravite, ses
/// textes (journal, menu, notification) sont ceux de son module, une veille du Mac n'est ecrite qu'une fois, et un protocole
/// eteint n'ecrit ni ne signale rien.
@MainActor
@Suite("Journal unique : Thread et Zigbee")
struct JournalDeuxProtocolesTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)

    static func evenement(_ type: TypeEvenement, _ nom: String, minutes: Double = 0, protocole: Protocole? = nil,
                          avant: String? = nil, apres: String? = nil) -> Evenement {
        Evenement(date: t.addingTimeInterval(minutes * 60), type: type, sujet: Sujet(id: "ID-\(nom)", nom: nom),
                  avant: avant, apres: apres, protocole: protocole)
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
    }

    /// Un evenement de Zigbee et un de Thread du meme type gardent chacun leur protocole et la gravite de ce protocole dans le
    /// journal ecrit puis relu ; les deux se distinguent (identifiant), et un type propre a un protocole se relit avec lui.
    @Test func memeTypeChaqueProtocoleDansLeJournalRelu() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        let thread = Self.evenement(.routeurDisparu, "Routeur 1")
        let zigbee = Self.evenement(.routeurDisparu, "Routeur 1")
        s.ajouter([thread], de: .thread)
        s.ajouter([zigbee, Self.evenement(.cheminChange, "Routeur 2", minutes: 1, avant: "A", apres: "B")], de: .zigbee)
        s.ajouter([Self.evenement(.parentChange, "Appareil 1", minutes: 2, avant: "A", apres: "B")], de: .thread)
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.chargerJournal()
        #expect(relu.evenements.count == 4)
        let disparus = relu.evenements.filter { $0.type == .routeurDisparu }
        #expect(disparus.map(\.protocole) == [.thread, .zigbee])
        #expect(disparus.allSatisfy { $0.gravite == .alerte }, "la gravite de leur protocole")
        #expect(Set(disparus.map(\.id)).count == 2, "meme date, meme type, meme sujet : deux identifiants")
        #expect(relu.evenements.first { $0.type == .cheminChange }?.protocole == .zigbee)
        #expect(relu.evenements.first { $0.type == .parentChange }?.protocole == .thread)
        #expect(relu.lignesJournal.count == 4, "quatre lignes, une par evenement")
        // Les evenements de la session sont les memes que ceux relus.
        #expect(s.evenements == relu.evenements)
    }

    /// Une ligne d'avant l'etape 3 (sans `protocole`) se relit comme une ligne de Thread, avec le texte de Thread.
    @Test func ligneSansProtocoleEstDeThread() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let journal = dossier.appendingPathComponent("Journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let ligne = #"{"constate":false,"date":"2026-09-27T00:14:00.000Z","details":{},"gravite":"alerte","sujet":{"id":"ID-R","nom":"Routeur 1"},"type":"routeurDisparu"}"#
        try Data((ligne + "\n").utf8).write(to: journal.appendingPathComponent("journal-2026-09.jsonl"))
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.chargerJournal()
        let e = try #require(s.evenements.first)
        #expect(e.protocole == nil)
        #expect(TexteEvenement.titre(e) == TexteEvenementThread.titre(e))
        #expect(TexteEvenement.protocole(e) == .thread)
    }

    /// Les evenements de Zigbee ont les textes de Zigbee : dans le journal, dans les lignes regroupees, dans les
    /// notifications. Ceux de Thread (et ceux sans protocole) gardent ceux de Thread. (Avant : le texte de Thread, qui
    /// retombait sur le nom brut du type pour tout type de Zigbee.)
    @Test func textesParProtocole() {
        let chemin = Self.evenement(.cheminChange, "Lampe", protocole: .zigbee, avant: "Prise", apres: "Pont Hue")
        #expect(TexteEvenement.titre(chemin) == TexteEvenementZigbee.titre(chemin))
        #expect(TexteEvenement.titre(chemin) != chemin.type.rawValue, "pas le nom brut du type")
        #expect(TexteEvenement.titre(chemin) == String(localized: "\("Lampe") a changé de chemin vers le pont : \("Prise") → \("Pont Hue")"))
        // Un meme type, deux textes : celui du protocole de l'evenement.
        let routeurZ = Self.evenement(.routeurApparu, "Prise", protocole: .zigbee)
        let routeurT = Self.evenement(.routeurApparu, "Prise", protocole: .thread)
        let routeurN = Self.evenement(.routeurApparu, "Prise")
        #expect(TexteEvenement.titre(routeurZ) == String(localized: "Routeur apparu : \("Prise")"))
        #expect(TexteEvenement.titre(routeurT) == String(localized: "\("Prise") est apparu"))
        #expect(TexteEvenement.titre(routeurN) == TexteEvenement.titre(routeurT), "sans protocole : Thread")
        // Un type de Thread garde son texte.
        let scinde = Evenement(date: Self.t, type: .reseauScinde, sujet: Sujet(id: "XP", nom: "Reseau 1"), apres: "2",
                               protocole: .thread)
        #expect(TexteEvenement.titre(scinde) == TexteEvenementThread.titre(scinde))
        // Les lignes regroupees : celles de Zigbee disent « chemin vers le pont », avec le nom du dernier changement.
        let chemins = LigneJournal.chemins([chemin, Self.evenement(.cheminChange, "Lampe", minutes: 5, protocole: .zigbee)])
        #expect(TexteEvenement.titre(chemins) == TexteEvenementZigbee.titre(chemins))
        #expect(TexteEvenement.titre(chemins) == String(localized: "\("Lampe") a changé \(2) fois de chemin vers le pont en 1 h"))
        let parentsZ = LigneJournal.parents([Self.evenement(.parentChange, "Lampe", protocole: .zigbee),
                                             Self.evenement(.parentChange, "Lampe", minutes: 5, protocole: .zigbee)])
        #expect(TexteEvenement.titre(parentsZ) == TexteEvenementZigbee.titre(parentsZ))
        #expect(TexteEvenement.quand(chemins) == TexteEvenementZigbee.quand(chemins))
        #expect(TexteEvenement.changement(chemin) == TexteEvenementZigbee.changement(chemin))
    }

    /// Les notifications : le titre et le texte de chaque protocole (« Routeur disparu » pour Zigbee, « Routeur de bordure
    /// disparu » pour Thread ; « N appareils perdus » et « N appareils Thread perdus »). Les categories restent celles d'avant.
    @Test func notificationsParProtocole() {
        let disparuZ = Self.evenement(.routeurDisparu, "Prise", protocole: .zigbee)
        let disparuT = Self.evenement(.routeurDisparu, "HomePod", protocole: .thread)
        let z = AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: disparuZ.id, evenements: [disparuZ])
        let t = AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: disparuT.id, evenements: [disparuT])
        #expect(TexteEvenement.notification(z).titre == String(localized: "Routeur disparu"))
        #expect(TexteEvenement.notification(t).titre == String(localized: "Routeur de bordure disparu"))
        #expect(TexteEvenement.notification(z) == TexteEvenementZigbee.notification(z))
        #expect(TexteEvenement.notification(t) == TexteEvenementThread.notification(t))
        let pertesZ = (0..<3).map { Self.evenement(.appareilDisparu, "Lampe \($0)", minutes: Double($0), protocole: .zigbee) }
        let pertesT = pertesZ.map { e in var e = e; e.protocole = .thread; return e }
        let nZ = TexteEvenement.notification(AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: pertesZ))
        let nT = TexteEvenement.notification(AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: pertesT))
        #expect(nZ.titre == String(localized: "\(3) appareils perdus") && nT.titre == String(localized: "\(3) appareils Thread perdus"))
        // Une information de Zigbee : son titre, pas le nom brut du type.
        let info = Self.evenement(.cheminChange, "Lampe", protocole: .zigbee, avant: "A", apres: "B")
        #expect(TexteEvenement.notification(AlerteAEnvoyer(categorie: .informations, identifiant: info.id, evenements: [info])).titre
                == TexteEvenementZigbee.titre(info))
        // La politique du journal reste celle d'avant : memes categories pour les memes evenements.
        #expect(Surveillance.politiqueJournal.categorie(disparuZ) == .routeurDisparu)
        #expect(Surveillance.politiqueJournal.categorie(disparuT) == .routeurDisparu)
        #expect(Surveillance.politiqueJournal.categorie(info) == .informations)
    }

    /// Une veille du Mac s'ecrit une fois, pas une fois par modele : une seule ligne avec les deux protocoles actifs. Elle
    /// reste ecrite si un seul protocole est actif, et n'est pas ecrite si aucun ne l'est.
    @Test func uneSeuleLigneDeVeille() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let debut = Self.t, fin = Self.t.addingTimeInterval(1800)
        func veilles() -> [Evenement] { s.evenements.filter { $0.type == .veille } }
        s.noterVeille(debut: debut, fin: fin)
        #expect(veilles().count == 1, "une ligne pour deux protocoles actifs")
        #expect(veilles().first?.periode == DateInterval(start: debut, end: fin))
        s.thread.actif = false
        s.noterVeille(debut: debut, fin: fin.addingTimeInterval(3600))
        #expect(veilles().count == 2, "Thread eteint : une ligne, celle de Zigbee")
        #expect(veilles().last?.protocole == .zigbee)
        s.zigbee.actif = false
        s.noterVeille(debut: debut, fin: fin.addingTimeInterval(7200))
        #expect(veilles().count == 2, "aucun protocole actif : aucune ligne")
        s.thread.actif = true
        s.noterVeille(debut: debut, fin: fin.addingTimeInterval(10_800))
        #expect(veilles().count == 3 && veilles().last?.protocole == .thread, "Zigbee eteint : celle de Thread")
    }

    /// Un protocole eteint n'ecrit rien au journal et ne fait pas d'alerte ; l'alerte d'un protocole est la sienne.
    @Test func protocoleEteintSansAlerte() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let maintenant = Date()
        #expect(!s.alerte && !s.alerte(de: .zigbee) && !s.alerte(de: .thread))
        s.ajouter([Evenement(date: maintenant, type: .routeurDisparu, sujet: Sujet(id: "ID-1", nom: "Prise"))], de: .zigbee)
        #expect(s.alerte && s.alerte(de: .zigbee) && !s.alerte(de: .thread), "l'alerte de Zigbee n'est pas celle de Thread")
        s.zigbee.actif = false
        #expect(!s.alerte && !s.alerte(de: .zigbee), "Zigbee eteint : plus d'alerte")
        let avant = s.evenements.count
        s.ajouter([Evenement(date: maintenant, type: .routeurDisparu, sujet: Sujet(id: "ID-2", nom: "Prise 2"))], de: .zigbee)
        #expect(s.evenements.count == avant, "un protocole eteint n'ecrit rien")
        s.zigbee.actif = true
        #expect(s.alerte(de: .zigbee), "rallume : l'alerte de l'heure revient")
        s.ajouter([Evenement(date: maintenant, type: .routeurDisparu, sujet: Sujet(id: "ID-3", nom: "HomePod"))], de: .thread)
        #expect(s.alerte(de: .thread))
        s.thread.actif = false
        #expect(!s.alerte(de: .thread) && s.alerte, "Thread eteint, Zigbee alerte : l'alerte est celle de Zigbee")
    }

    /// Les familles du journal portent les types des deux protocoles : la famille « Surveillance » de Zigbee, les types de
    /// chemin dans « Maillage », et les types de Thread inchanges.
    @Test func famillesDesDeuxProtocoles() {
        #expect(FamilleEvenement.surveillance.contient(.surveillanceDemarree) && FamilleEvenement.surveillance.contient(.veille))
        #expect(FamilleEvenement.maillage.contient(.cheminChange))
        #expect(FamilleEvenement.reseau.contient(.reseauScinde) && FamilleEvenement.prefixes.contient(.prefixeNouveau))
        // Tout type d'un protocole a sa famille (hors « Tous ») : le filtre ne perd aucun type.
        for t in Surveillance.politiqueJournal.types {
            #expect(FamilleEvenement.allCases.contains { $0 != .toutes && $0.contient(t) }, "\(t.rawValue)")
        }
    }

    /// La recherche du journal lit le titre du protocole de la ligne : un titre de Zigbee se trouve, et le nom brut d'un type de
    /// Zigbee n'est plus ce qui est cherche. Le mot cherche est un extrait du titre dans la langue du test : « chemin vers le
    /// pont » est une cle du catalogue (la legende), et son texte est aussi celui du titre (« path to the bridge » en anglais).
    @Test func rechercheDansLeTitreDuProtocole() {
        let chemin = Self.evenement(.cheminChange, "Lampe", protocole: .zigbee, avant: "Prise", apres: "Pont Hue")
        let lignes = [LigneJournal.evenement(chemin)]
        #expect(FiltreJournal(recherche: String(localized: "chemin vers le pont")).appliquer(lignes).count == 1)
        #expect(FiltreJournal(recherche: "cheminChange").appliquer(lignes).isEmpty)
    }

    /// Deux evenements identiques a un protocole pres sont deux lignes du journal, jamais une seule (identite de la liste).
    @Test func deuxLignesDeMemeDateEtDeMemeType() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.ajouter([Self.evenement(.appareilRevenu, "Lampe")], de: .thread)
        s.ajouter([Self.evenement(.appareilRevenu, "Lampe")], de: .zigbee)
        #expect(s.lignesJournal.count == 2)
        #expect(Set(s.lignesJournal.map(\.id)).count == 2)
    }

    /// Les pertes de deux protocoles ne se regroupent pas dans le journal : une ligne de pertes par protocole.
    @Test func pertesParProtocoleDansLeJournal() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.ajouter([Self.evenement(.appareilDisparu, "A1"), Self.evenement(.appareilDisparu, "A2", minutes: 2)], de: .thread)
        s.ajouter([Self.evenement(.appareilDisparu, "B1", minutes: 1), Self.evenement(.appareilDisparu, "B2", minutes: 3)],
                  de: .zigbee)
        let lignes = s.lignesJournal
        #expect(lignes.count == 2)
        #expect(lignes.allSatisfy { l in
            if case .pertes(let g) = l { Set(g.map(\.protocole)).count == 1 } else { false }
        }, "chaque ligne de pertes n'a qu'un protocole")
    }
}
