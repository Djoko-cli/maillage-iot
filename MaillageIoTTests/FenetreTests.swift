import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Fenetre : barre d'outils et ligne de la tournee")
struct FenetreTests {
    /// Le bouton rafraichir de la barre lance aussi le passeur des noms de Maison, en mode direct
    /// seulement : plus de dossier des noms a choisir.
    @Test func rafraichirLanceLePasseurEnModeDirect() {
        #expect(BarreOutils.lancePasseur(mode: .direct))
        #expect(!BarreOutils.lancePasseur(mode: .demo))
    }

    /// L'aide du bouton rafraichir dit ce qu'il lancera vraiment : le reseau toujours, une
    /// tournee si la sonde est connectee et libre, les noms de Maison si le passeur sera lance.
    @Test func aideDuBoutonRafraichir() {
        #expect(BarreOutils.aideRafraichir(tournee: true, passeur: true)
                == String(localized: "Rafraîchir : réseau, tournée de la sonde et noms de Maison"))
        #expect(BarreOutils.aideRafraichir(tournee: true, passeur: false)
                == String(localized: "Rafraîchir : réseau et tournée de la sonde"))
        #expect(BarreOutils.aideRafraichir(tournee: false, passeur: true)
                == String(localized: "Rafraîchir : réseau et noms de Maison"))
        #expect(BarreOutils.aideRafraichir(tournee: false, passeur: false) == String(localized: "Rafraîchir : réseau"))
    }

    /// La capsule de la tournee garde la meme largeur a chaque etape (celle de la plus longue,
    /// compteur et duree compris) : elle ne change pas de taille a chaque pas.
    @Test func capsuleDeLargeurFixe() {
        let debut = Date(timeIntervalSinceNow: -42)
        let avancements = AvancementTournee.Etape.allCases.flatMap { e in
            [AvancementTournee(etape: e, fait: 0, total: 0), AvancementTournee(etape: e, fait: 3, total: 7),
             AvancementTournee(etape: e, fait: 24, total: 48), AvancementTournee(etape: e, fait: 160, total: 160)]
        }
        let largeurs = avancements.map {
            NSHostingView(rootView: IndicateurTournee(avancement: $0, debut: debut)).fittingSize.width
        }
        #expect(Set(largeurs).count == 1, "\(largeurs)")
    }

    /// La place de la tournee (ronde finale du 02/10) : la ligne montree pendant une tournee ; hors tournee, une sonde
    /// retenue, cachee, mais sa place comptee dans la marge du haut (la scene ne bouge pas au debut ni a la fin d'une
    /// tournee) ; rien sans sonde. Le gabarit que compte la marge a la taille de la ligne montree.
    @Test func placeDeLaTournee() {
        let a = AvancementTournee(etape: .resolution, fait: 24, total: 48)
        let debut = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(LigneTournee.place(serie: "A0:00:00:00:00:01", debut: debut) == .montree)
        #expect(LigneTournee.place(serie: "A0:00:00:00:00:01", debut: nil) == .comptee)
        #expect(LigneTournee.place(serie: nil, debut: nil) == .aucune)
        let tournee = NSHostingView(rootView: IndicateurTournee(avancement: a, debut: debut)).fittingSize
        let place = NSHostingView(rootView: LigneTournee.gabarit).fittingSize
        #expect(place == tournee)
    }

    /// Pendant une tournee, la capsule du reseau garde sa largeur : le bouton rafraichir ne bouge
    /// pas sous le pointeur. L'indicateur est sur sa propre ligne, qui ne prend aucune place
    /// sans sonde retenue (pas meme l'espacement de la pile).
    @Test(.timeLimit(.minutes(1))) func barreImmobilePendantUneTournee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let noms = NomsInternes(cache: nil, lanceur: NomsInternes.lanceurInterdit)
        let journal = JournalCanaux()
        let sonde = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in SondeMaillageTests.canalRetenu(journal) })
        func taille(_ vue: some View) -> CGSize {
            NSHostingView(rootView: vue.environment(surveillance).environment(sonde).environment(noms)).fittingSize
        }
        func pile() -> CGSize {
            taille(VStack(spacing: 10) {
                Color.clear.frame(width: 10, height: 10)
                LigneTournee()
                Color.clear.frame(width: 10, height: 10)
            })
        }
        let barre = taille(BarreOutils())
        #expect(pile().height == 30, "hors tournee : rien")
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        await journal.attendre(SondeMaillageTests.listeRetenue)
        await SondeMaillageTests.attendre { sonde.avancement != nil }
        #expect(taille(BarreOutils()) == barre)
        #expect(pile().height > 30, "pendant la tournee : la ligne de l'indicateur")
        await sonde.oublier()
    }
}

@MainActor
@Suite("Fiche d'un appareil")
struct FicheTests {
    /// Piece, fabricant (sinon modele HomeKit), modele, puis firmware quand Maison le donne.
    @Test func ligneDescription() {
        let maison = AccessoireMaison(nom: "Capteur", piece: "Salon", fabricant: "Acme", modele: "Capteur 2",
                                      firmware: "1.4.2")
        #expect(FicheNoeud.ligneDescription(maison: maison, modeleHomeKit: nil)
                == "Salon · Acme · Capteur 2 · firmware 1.4.2")
        var sansFirmware = maison
        sansFirmware.firmware = nil
        #expect(FicheNoeud.ligneDescription(maison: sansFirmware, modeleHomeKit: nil) == "Salon · Acme · Capteur 2")
        sansFirmware.firmware = ""
        #expect(FicheNoeud.ligneDescription(maison: sansFirmware, modeleHomeKit: nil) == "Salon · Acme · Capteur 2")
        #expect(FicheNoeud.ligneDescription(maison: nil, modeleHomeKit: "Eve Door") == "Eve Door")
        #expect(FicheNoeud.ligneDescription(maison: nil, modeleHomeKit: nil) == "")
    }

    /// Textes de l'app, dans la langue de l'hote des tests.
    static func pourcent(_ n: Int) -> String { String(localized: "\(n)\u{202F}%") }
    static let surBatterie = String(localized: "sur batterie")
    static let enCharge = String(localized: "en charge")
    static let nonRechargeable = String(localized: "non rechargeable")
    static let faible = String(localized: "batterie faible")
    static let ok = String(localized: "batterie OK")

    /// Niveau, puis l'etat de charge ; faible, « batterie faible » (et « en
    /// charge » seulement) ; sans niveau, l'alerte seule, et « batterie OK »
    /// seulement si l'accessoire le dit.
    @Test func ligneBatterie() {
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 52, charge: .horsCharge))
                == "\(Self.pourcent(52)) · \(Self.surBatterie)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 81, charge: .enCharge))
                == "\(Self.pourcent(81)) · \(Self.enCharge)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 97, charge: .nonRechargeable))
                == "\(Self.pourcent(97)) · \(Self.nonRechargeable)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 88)) == Self.pourcent(88))
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 12, charge: .horsCharge))
                == "\(Self.pourcent(12)) · \(Self.faible)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(niveau: 15, charge: .enCharge))
                == "\(Self.pourcent(15)) · \(Self.faible) · \(Self.enCharge)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(alerte: true)) == Self.faible)
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(alerte: false)) == Self.ok)
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(charge: .enCharge, alerte: false))
                == "\(Self.ok) · \(Self.enCharge)")
        #expect(FicheNoeud.ligneBatterie(BatterieMaison(charge: .enCharge)) == Self.enCharge, "alerte inconnue")
        #expect(Self.pourcent(52).contains("\u{202F}") || !Self.pourcent(52).contains(" "),
                "pas d'espace secable avant %")
    }

    /// Triangle si faible, eclair en charge, sinon le niveau par quart.
    @Test func symboleBatterie() {
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 12)) == "exclamationmark.triangle.fill")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(alerte: true)) == "exclamationmark.triangle.fill")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 81, charge: .enCharge)) == "battery.100percent.bolt")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 30)) == "battery.25percent")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 52)) == "battery.50percent")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 64)) == "battery.75percent")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(niveau: 100)) == "battery.100percent")
        #expect(FicheNoeud.symboleBatterie(BatterieMaison(alerte: false)) == "battery.100percent")
    }

    /// Pastille d'un nom : seulement pour une batterie faible ; le niveau, sinon « faible ».
    @Test func pastilleBatterie() {
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: 12)) == Self.pourcent(12))
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(alerte: true)) == String(localized: "faible"))
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: 90, alerte: true)) == Self.pourcent(90))
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: 52)) == nil)
        #expect(LibellesNoeuds.pastilleBatterie(nil) == nil)
    }
}
