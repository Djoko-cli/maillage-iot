import Foundation
@testable import MaillageCoeur
import ProtocoleThread
import SwiftUI
import Testing
@testable import MaillageIoT

/// « Associer a un accessoire de Maison… » (12/10), cote app : un appareil que Maison ne nomme pas prend le nom et la
/// piece de l'accessoire choisi, garde dans `associations.json` ; l'association se defait ; rien sur disque en demo ni
/// sans dossier. Valeurs inventees, dossiers jetables, jamais `demarrer()`.
@MainActor
@Suite("Associer a un accessoire de Maison (app)")
struct AssociationMaisonTests {
    /// Les appareils de `AdresseVerifieeAppTests` : le Matter (noeud 1) que Maison nomme, le HomeKit (noeud 2) et le
    /// temoin (noeud 3) qu'il ne nomme pas.
    static let nomme = AdresseVerifieeAppTests.matter
    static let muet = AdresseVerifieeAppTests.hap
    static let autre = AdresseVerifieeAppTests.temoin

    static func maison() -> NomsMaison {
        NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Detecteur 1", piece: "Piece 1", noeudMatter: "0000000000000001"),
            AccessoireMaison(nom: "Detecteur 2", piece: "Piece 2", modele: "Modele 1", noeudMatter: "00000000000000AA"),
            AccessoireMaison(nom: "Detecteur 3", piece: "Piece 1", noeudMatter: "00000000000000BB"),
            AccessoireMaison(nom: "Detecteur 4", piece: "Piece 3"),
        ])
    }

    static func surveillance(dossier: URL?) -> Surveillance {
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.noms.maison = maison()
        s.thread.integrer(AdresseVerifieeAppTests.annonces(Date()))
        return s
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
    }

    @Test func associerDonneLeNomEtLaPiece() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Self.surveillance(dossier: dossier)
        let r = try #require(s.thread.reseau)
        let muet = try #require(s.thread.appareil(Self.muet))
        #expect(s.thread.nom(try #require(s.thread.appareil(Self.nomme))) == "Detecteur 1", "par son noeud")
        #expect(s.thread.nom(muet) == Self.muet)
        #expect(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.muet) }?.piece == nil)
        #expect(MenuAssocier.propose(muet, dans: s))
        #expect(!MenuAssocier.propose(try #require(s.thread.appareil(Self.nomme)), dans: s), "Maison le nomme deja")
        #expect(s.thread.accessoiresOrphelins.map(\.nom) == ["Detecteur 2", "Detecteur 3"])
        #expect(!s.thread.associeALaMain(muet))

        let choisi = try #require(s.thread.accessoiresOrphelins.first)
        s.thread.associer(Self.muet, a: choisi)
        #expect(s.thread.nom(muet) == "Detecteur 2")
        #expect(s.thread.accessoire(muet)?.piece == "Piece 2")
        let affiche = try #require(s.thread.appareilsAffiches(pour: r).first { $0.id == idt(Self.muet) })
        #expect(affiche.nom == "Detecteur 2" && affiche.piece == "Piece 2", "partout, la carte comprise")
        let entree = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        #expect(entree.libelles[idt(Self.muet)]?.nom == "Detecteur 2")
        #expect(entree.appareils[idt(Self.muet)]?.piece == "Piece 2")
        #expect(s.thread.associeALaMain(muet))
        #expect(!MenuAssocier.propose(muet, dans: s))
        #expect(s.thread.accessoiresOrphelins.map(\.nom) == ["Detecteur 3"], "plus propose")
        #expect(s.thread.nom(try #require(s.thread.appareil(Self.autre))) == Self.autre, "les autres ne bougent pas")

        // Dans le fichier, relu au lancement suivant.
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("associations.json")
        #expect(Associations.lire(fichier) == [Self.muet: "00000000000000AA"])
        let relu = Self.surveillance(dossier: dossier)
        #expect(relu.thread.noms.associations == [Self.muet: "00000000000000AA"])
        #expect(relu.thread.nom(try #require(relu.thread.appareil(Self.muet))) == "Detecteur 2")

        // Dissocier.
        s.thread.dissocier(Self.muet)
        #expect(s.thread.nom(muet) == Self.muet)
        #expect(!s.thread.associeALaMain(muet))
        #expect(s.thread.accessoiresOrphelins.map(\.nom) == ["Detecteur 2", "Detecteur 3"])
        #expect(Associations.lire(fichier) == [:])
        #expect(Self.surveillance(dossier: dossier).thread.noms.associations.isEmpty)
        s.thread.dissocier(Self.muet)
        // Un accessoire sans noeud n'associe rien.
        s.thread.associer(Self.muet, a: AccessoireMaison(nom: "Detecteur 4"))
        #expect(s.thread.noms.associations.isEmpty)
    }

    /// Le journal et les notifications utilisent le nom resolu : un appareil associe qui disparait est nomme par
    /// l'accessoire, sans nouvel evenement pour l'association.
    @Test func journalAvecLeNomResolu() throws {
        let t = Date()
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.noms.maison = Self.maison()
        s.thread.integrer(AdresseVerifieeAppTests.annonces(t - 900))
        s.thread.associer(Self.muet, a: Self.maison().accessoires[1])
        let avant = s.evenements
        s.thread.integrer(AdresseVerifieeAppTests.annonces(t - 840, partis: [Self.muet]))
        s.thread.integrer(AdresseVerifieeAppTests.annonces(t - 700, partis: [Self.muet]))
        let perdu = s.evenements.dropFirst(avant.count).filter { $0.type == .appareilDisparu }
        #expect(perdu.map { $0.sujet?.nom } == ["Detecteur 2"])
        #expect(s.evenements.dropFirst(avant.count).allSatisfy { $0.sujet?.id == Self.muet || $0.sujet == nil },
                "l'association elle-meme n'est pas un evenement")
    }

    /// Rien sur disque en demo ni sans dossier : le fichier n'est ecrit nulle part.
    @Test func rienEnDemoNiSansDossier() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let accessoire = Self.maison().accessoires[1]
        let demo = Surveillance(mode: .demo, dossier: dossier)
        demo.thread.associer("56B1E064401F74EF", a: accessoire)
        demo.thread.dissocier("56B1E064401F74EF")
        let sans = Self.surveillance(dossier: nil)
        sans.thread.associer(Self.muet, a: accessoire)
        #expect(sans.thread.nom(try #require(sans.thread.appareil(Self.muet))) == "Detecteur 2", "en memoire, comme un surnom")
        sans.thread.dissocier(Self.muet)
        #expect(!FileManager.default.fileExists(atPath: dossier.path), "ni dossier ni fichier")
        // Un fichier illisible est ignore au lancement (puis mis de cote a la premiere ecriture).
        try FileManager.default.createDirectory(at: Surveillance.dossierThread(dossier), withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: Surveillance.dossierThread(dossier).appendingPathComponent("associations.json"))
        let illisible = Self.surveillance(dossier: dossier)
        #expect(illisible.thread.noms.associations.isEmpty)
        illisible.thread.associer(Self.muet, a: accessoire)
        #expect(Self.surveillance(dossier: dossier).thread.noms.associations == [Self.muet: "00000000000000AA"])
        let fichiers = try FileManager.default.contentsOfDirectory(atPath: Surveillance.dossierThread(dossier).path)
        #expect(fichiers.contains { $0.hasPrefix("associations.illisible-") })
    }

    /// La fiche : le bouton, puis « associe a la main » et « Dissocier » ; chaque etat se rend autrement.
    @Test func ficheSelonLEtat() throws {
        let s = Self.surveillance(dossier: nil)
        let instant = Date()
        func rendu() -> Data? {
            let fiche = FicheNoeud(id: idt(Self.muet), entree: nil, instant: instant, aRenommer: .constant(nil), fermer: {})
                .environment(s)
                .environment(PiecesChoisies(fichier: nil))
                .frame(width: 1000)
            return ImageRenderer(content: fiche).nsImage?.tiffRepresentation
        }
        let avant = try #require(rendu())
        s.thread.associer(Self.muet, a: Self.maison().accessoires[1])
        let apres = try #require(rendu())
        #expect(apres != avant)
        s.thread.dissocier(Self.muet)
        #expect(rendu() != apres, "dissocie, la fiche change de nouveau")
        #expect(MenuAssocier.ligne(Self.maison().accessoires[1]) == "Detecteur 2 · Piece 2 · Modele 1")
        #expect(MenuAssocier.ligne(Self.maison().accessoires[3]) == "Detecteur 4 · Piece 3")
        #expect(MenuAssocier.ligne(AccessoireMaison(nom: "Detecteur 5")) == "Detecteur 5")
        // Sans lecture de Maison, ou pour un appareil du reseau local : pas de bouton.
        let sansMaison = Surveillance(mode: .direct, dossier: nil)
        sansMaison.thread.integrer(AdresseVerifieeAppTests.annonces(Date()))
        #expect(!MenuAssocier.propose(try #require(sansMaison.thread.appareil(Self.muet)), dans: sansMaison))
    }

    /// Les textes dans la langue du lancement des tests (`-testLanguage fr`, puis `en`).
    @Test func textesFrancaisEtAnglais() throws {
        let francais = ThreadRouteTests.langue == "fr"
        guard francais || ThreadRouteTests.langue == "en" else {
            throw ThreadRouteTests.ErreurLangue(langue: ThreadRouteTests.langue)
        }
        #expect(String(localized: "Associer à un accessoire de Maison…")
                == (francais ? "Associer à un accessoire de Maison…" : "Link to a Home accessory…"))
        #expect(String(localized: "Aucun accessoire de Maison à associer")
                == (francais ? "Aucun accessoire de Maison à associer" : "No Home accessory to link"))
        #expect(String(localized: "Dissocier") == (francais ? "Dissocier" : "Unlink"))
        #expect(String(localized: "associé à la main") == (francais ? "associé à la main" : "linked by hand"))
    }
}
