import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

@MainActor
@Suite("Fenetre : barre d'outils et ligne de la tournee (Zigbee)")
struct FenetreZigbeeTests {
    /// L'aide du bouton rafraichir, dans la barre commune aux deux protocoles (etape 3b, tache 5 : celle de Zigbee seul n'est
    /// plus), dit ce qu'il lancera vraiment : une tournee si la sonde de Zigbee est connectee et libre, sans les noms de
    /// Maison hors du mode direct.
    @Test func aideDuBoutonRafraichir() {
        #expect(BarreOutils.aideRafraichir(tournee: true, passeur: false) == String(localized: "Rafraîchir : réseau et tournée de la sonde"))
        #expect(BarreOutils.aideRafraichir(tournee: false, passeur: false) == String(localized: "Rafraîchir : réseau"))
    }

    /// La capsule de la tournee garde la meme largeur a chaque etape (celle de la plus longue,
    /// compteur et duree compris) : elle ne change pas de taille a chaque pas.
    @Test func capsuleDeLargeurFixe() {
        let debut = Date(timeIntervalSinceNow: -42)
        let avancements = AvancementTourneeZigbee.Etape.allCases.flatMap { e in
            [AvancementTourneeZigbee(etape: e, fait: 0, total: 0), AvancementTourneeZigbee(etape: e, fait: 3, total: 7),
             AvancementTourneeZigbee(etape: e, fait: 24, total: 48), AvancementTourneeZigbee(etape: e, fait: 160, total: 160)]
        }
        let largeurs = avancements.map {
            NSHostingView(rootView: IndicateurTourneeZigbee(avancement: $0, debut: debut)).fittingSize.width
        }
        #expect(Set(largeurs).count == 1, "\(largeurs)")
    }

    /// La place de la tournee (ronde finale du 02/10) : la ligne montree pendant une tournee ; hors tournee, une sonde
    /// retenue, cachee, mais sa place comptee dans la marge du haut (la scene ne bouge pas au debut ni a la fin d'une
    /// tournee) ; rien sans sonde. Le gabarit que compte la marge a la taille de la ligne montree.
    @Test func placeDeLaTournee() {
        let a = AvancementTourneeZigbee(etape: .tables, fait: 24, total: 48)
        let debut = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(LigneTournee.place(serie: "A0:00:00:00:00:01", debut: debut) == .montree)
        #expect(LigneTournee.place(serie: "A0:00:00:00:00:01", debut: nil) == .comptee)
        #expect(LigneTournee.place(serie: nil, debut: nil) == .aucune)
        let tournee = NSHostingView(rootView: IndicateurTourneeZigbee(avancement: a, debut: debut)).fittingSize
        let place = NSHostingView(rootView: LigneTourneeZigbee.gabarit).fittingSize
        #expect(place == tournee)
    }

    /// Pendant une tournee, la capsule de gauche garde sa largeur : le bouton rafraichir ne bouge pas sous le pointeur.
    /// L'indicateur est sur sa propre ligne, qui ne prend aucune place hors tournee (pas meme l'espacement de la pile).
    /// La tournee est posee par ses points d'accroche (`debuterTournee`, `avancer`, `finirTournee`).
    @Test(.timeLimit(.minutes(1))) func barreImmobilePendantUneTournee() async throws {
        let (p, domaine) = try SondeMaillageZigbeeTests.preferences()
        defer { SondeMaillageZigbeeTests.nettoyer(p, domaine) }
        let surveillance = Surveillance(mode: .direct, dossier: nil)
        let noms = NomsPont()
        let sonde = SondeMaillageZigbee(preferences: p, actif: true, trousseau: TrousseauMemoireZigbee(),
                                  ouvrirCanal: { _ in CanalRejoueZigbee { CanalRejoueZigbee.sondeMinimale($0) } })
        func taille(_ vue: some View) -> CGSize {
            NSHostingView(rootView: vue.environment(surveillance).environment(sonde).environment(noms)
                .environment(SondeMaillageThread(preferences: p, actif: false)).environment(NomsPasseur())).fittingSize
        }
        func pile() -> CGSize {
            taille(VStack(spacing: 10) {
                Color.clear.frame(width: 10, height: 10)
                LigneTourneeZigbee()
                Color.clear.frame(width: 10, height: 10)
            })
        }
        let barre = taille(BarreOutils())
        #expect(pile().height == 30, "hors tournee : rien")
        await sonde.connecter(SondeMaillageZigbeeTests.port, choisi: true)
        sonde.debuterTournee()
        sonde.avancer(AvancementTourneeZigbee(etape: .tables, fait: 3, total: 12))
        #expect(sonde.tourneeEnCours && !sonde.tourneeAuRafraichir)
        #expect(taille(BarreOutils()) == barre)
        #expect(pile().height > 30, "pendant la tournee : la ligne de l'indicateur")
        sonde.finirTournee(nil)
        #expect(pile().height == 30 && sonde.avancement == nil && sonde.debutTournee == nil)
        await sonde.oublier()
    }
}

@MainActor
@Suite("Fiche d'un appareil (Zigbee)")
struct FicheZigbeeTests {
    /// Piece, fabricant, modele, puis firmware quand le pont le donne.
    @Test func ligneDescription() {
        let maison = AppareilPont(nom: "Capteur", piece: "Salon", fabricant: "Acme", modele: "Capteur 2",
                                      firmware: "1.4.2")
        #expect(FicheNoeudZigbee.ligneDescription(maison: maison) == "Salon · Acme · Capteur 2 · firmware 1.4.2")
        var sansFirmware = maison
        sansFirmware.firmware = nil
        #expect(FicheNoeudZigbee.ligneDescription(maison: sansFirmware) == "Salon · Acme · Capteur 2")
        sansFirmware.firmware = ""
        #expect(FicheNoeudZigbee.ligneDescription(maison: sansFirmware) == "Salon · Acme · Capteur 2")
        #expect(FicheNoeudZigbee.ligneDescription(maison: nil) == "")
    }

    /// Textes de l'app, dans la langue de l'hote des tests.
    static func pourcent(_ n: Int) -> String { String(localized: "\(n)\u{202F}%") }
    static let surBatterie = String(localized: "sur batterie")
    static let enCharge = String(localized: "en charge")
    static let nonRechargeable = String(localized: "non rechargeable")
    static let faible = String(localized: "batterie faible")
    static let ok = String(localized: "batterie OK")

}
