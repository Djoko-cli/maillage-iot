import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT
import ProtocoleZigbee

@MainActor
@Suite("Noms de Maison dans l'app : fusion avec le pont, etages, fiche")
struct NomsMaisonAppTests {
    typealias I = NomsDemo.Ieee

    /// La surveillance reunit les noms du pont et le releve de Maison, a chaque nouveau releve de l'un ou de l'autre ;
    /// sans releve de Maison, les noms du pont seuls ; sans pont, rien.
    @Test func fusionDansLaSurveillance() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.zigbee.releveMaison = NomsDemo.releveMaison
        #expect(s.zigbee.noms.maison == nil && s.zigbee.bilanFusion == nil, "Maison seule : aucune adresse longue")
        s.zigbee.nomsPont = NomsDemo.maisonPont
        #expect(s.zigbee.noms.maison == NomsDemo.maisonFusionnee)
        #expect(s.zigbee.bilanFusion == FusionNoms.Bilan(apparies: 20, nonApparies: 1))
        #expect(s.zigbee.nom(I.suspensionCuisine) == "Suspension de l'îlot")
        s.renommer(idz(I.suspensionCuisine), en: "Mon surnom")
        #expect(s.zigbee.nom(I.suspensionCuisine) == "Mon surnom", "le surnom l'emporte toujours")
        s.zigbee.releveMaison = nil
        #expect(s.zigbee.noms.maison == NomsDemo.maisonPont && s.zigbee.bilanFusion == nil, "sans Maison : les noms du pont")
        // IEEE, connexion et pile viennent toujours du pont.
        var pont = NomsDemo.maisonPont
        if let i = pont.accessoires.firstIndex(where: { $0.ieee == I.lampeBureau }) {
            pont.accessoires[i].connexion = .deconnecte
        }
        s.zigbee.releveMaison = NomsDemo.releveMaison
        s.zigbee.nomsPont = pont
        let a = try #require(s.zigbee.accessoire(I.lampeBureau))
        #expect(a.connexion == .deconnecte && a.origine == .maison)
        #expect(s.zigbee.accessoire(I.telecommandeChambre)?.batterie == NomsDemo.maisonPont.accessoire(ieee: I.telecommandeChambre)?.batterie)
    }

    /// La demo de l'app montre la fusion : noms de Maison, quatre etages, le bilan.
    @Test func demo() {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .zigbee)
        #expect(s.zigbee.noms.maison == NomsDemo.maisonFusionnee)
        #expect(s.zigbee.bilanFusion == FusionNoms.Bilan(apparies: 20, nonApparies: 1))
    }

    /// Les zones de Maison deviennent les etages de la vue par pieces, dans leur ordre ; l'appareil non apparie va a
    /// l'etage de sa piece ; une piece de l'app Hue sans equivalent dans Maison va dans « Autres pieces ».
    @Test func etagesDeMaison() throws {
        let s = Surveillance(mode: .demo, dossier: nil, demo: .zigbee)
        s.demarrer()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(e.scene.etages.map(\.nom) == NomsDemo.zones.map { .zone($0.nom) })
        #expect(e.domicile == NomsDemo.domicile)
        func etage(_ ieee: String) -> ScenePieces.NomEtage? {
            e.scene.pieces.first { $0.noeuds.contains(idz(ieee)) }.map { e.scene.etages[$0.etage].nom }
        }
        #expect(etage(I.fuiteBuanderie) == .zone("Rez-de-chaussée"), "non apparie, dans une piece de Maison")
        #expect(etage(I.suspensionCuisine) == .zone("Rez-de-chaussée"))
        #expect(etage(I.lampeGrenier) == .zone("Combles"))
        #expect(e.libelles[idz(I.suspensionCuisine)]?.nom == "Suspension de l'îlot")

        // Une piece de l'app Hue que Maison n'a pas : « Autres pieces ».
        var pont = NomsDemo.maisonPont
        if let i = pont.accessoires.firstIndex(where: { $0.ieee == I.fuiteBuanderie }) { pont.accessoires[i].piece = "Cave" }
        s.zigbee.nomsPont = pont
        let autre = EntreeScene(surveillance: s, places: PlacesGardees())
        let cave = try #require(autre.scene.pieces.first { $0.nom == .maison("Cave") })
        #expect(autre.scene.etages[cave.etage].nom == .autresPieces)
        #expect(cave.noeuds == [idz(I.fuiteBuanderie)])
    }

    /// La fiche signale un nom venu de l'app Hue (appareil pas trouve dans Maison) ; rien pour un appareil nomme par
    /// Maison, ni sans releve de Maison.
    @Test func ficheOrigine() {
        let n = NomsDemo.maisonFusionnee
        #expect(FicheNoeudZigbee.ligneOrigine(n.accessoire(ieee: I.fuiteBuanderie))
                == String(localized: "nom de l'app Hue (pas trouvé dans Maison)"))
        #expect(FicheNoeudZigbee.ligneOrigine(n.accessoire(ieee: I.lampeBureau)) == nil)
        #expect(FicheNoeudZigbee.ligneOrigine(NomsDemo.maisonPont.accessoire(ieee: I.fuiteBuanderie)) == nil)
        #expect(FicheNoeudZigbee.ligneOrigine(nil) == nil)
    }
}
