import Foundation
import Testing
import MaillageCoeur
import ProtocoleZigbee

/// Les deux sens de « Maison » apres la fusion des coeurs : les appareils du pont Hue sont des `NomsZigbee` /
/// `AppareilPont` (ProtocoleZigbee), le releve de Maison par le Passeur est le `NomsMaison` / `AccessoireMaison` du
/// coeur. La fusion prend les appareils du pont et les nomme par le releve, jamais l'inverse.
@Suite("Fusion des noms : appareils du pont et releve du coeur")
struct FusionNomsCoeurTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let lampe = "0000000000000001"
    static let prise = "0000000000000002"

    @Test func fusionAvecLeReleveDuCoeur() throws {
        // Le pont : une lampe (nom de l'app Hue, a la casse pres de celui de Maison) et une prise que Maison n'a pas.
        let pont = NomsZigbee(date: Self.t0, domicile: "Pont 1", accessoires: [
            AppareilPont(nom: "lampe 1", piece: "Pièce 1", fabricant: "Signify", modele: "Hue White", categorie: "Lampe",
                         ieee: Self.lampe, connexion: .connecte, idHue: "hue-1"),
            AppareilPont(nom: "Prise 2", piece: "pièce 2", fabricant: "Signify", modele: "Hue Smart Plug",
                         categorie: "Prise", ieee: Self.prise),
        ])
        // Le releve du Passeur (type du coeur, avec ses champs propres : noeud Matter, pont, identifiant HomeKit).
        let releve: MaillageCoeur.NomsMaison = NomsMaison(
            date: Self.t0, statut: .ok, domicile: "Maison 1",
            accessoires: [
                AccessoireMaison(nom: "Lampe 1", piece: "Pièce 3", fabricant: "Signify Netherlands B.V.",
                                 modele: "Hue White", categorie: "Lampe", noeudMatter: "00000000000000AA",
                                 id: "00000000-0000-0000-0000-000000000001"),
                AccessoireMaison(nom: "Thermostat", piece: "Pièce 2", fabricant: "Fabricant inventé", modele: "T1",
                                 categorie: "Thermostat", id: "00000000-0000-0000-0000-000000000002"),
            ],
            zones: [ZoneMaison(nom: "Étage 1", pieces: ["Pièce 2", "Pièce 3"])])

        let r = FusionNoms.fusionner(pont: pont, maison: releve, memoire: MemoireAppariements())

        let noms = try #require(r.noms)
        #expect(noms.domicile == "Maison 1")
        #expect(noms.zones == [ZoneMaison(nom: "Étage 1", pieces: ["Pièce 2", "Pièce 3"])])
        // Les appareils restent ceux du pont (adresse longue, connexion, identifiant Hue), tries par nom.
        #expect(noms.accessoires.map(\.ieee) == [Self.lampe, Self.prise])
        let l = try #require(noms.accessoire(ieee: Self.lampe))
        #expect(l.nom == "Lampe 1")
        #expect(l.piece == "Pièce 3")
        #expect(l.origine == .maison)
        #expect(l.idMaison == "00000000-0000-0000-0000-000000000001")
        #expect(l.connexion == .connecte)
        #expect(l.idHue == "hue-1")
        // La prise, absente de Maison, garde le nom du pont ; sa piece prend l'ecriture de Maison.
        let p = try #require(noms.accessoire(ieee: Self.prise))
        #expect(p.nom == "Prise 2")
        #expect(p.piece == "Pièce 2")
        #expect(p.origine == .pont)
        #expect(p.idMaison == nil)
        #expect(r.bilan == FusionNoms.Bilan(apparies: 1, nonApparies: 1))
        #expect(r.memoire.ids == [Self.lampe: "00000000-0000-0000-0000-000000000001"])
    }
}
