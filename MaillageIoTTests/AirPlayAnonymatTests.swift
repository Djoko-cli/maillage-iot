import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Du TXT AirPlay, seul `model` est gardé (la piece n'en a pas besoin d'autre) : le reste (`deviceid` = adresse MAC, cle
/// publique `pk`, etc.) n'entre ni dans le releve gardé ni dans la capture exportee. Valeurs inventees.
@MainActor
@Suite("AirPlay : seul le modele du TXT est garde")
struct AirPlayAnonymatTests {
    typealias Cible = ResolveurDNSSD.Cible
    typealias Listee = Recenseur.InstanceListee
    static let type = Recenseur.typeAirPlay

    static func txt(_ chaines: String...) -> Data {
        Data(chaines.flatMap { [UInt8($0.utf8.count)] + Array($0.utf8) })
    }

    /// Un TXT AirPlay complet, avec des valeurs factices reconnaissables.
    static let txtComplet = txt("model=Test1,1", "deviceid=AA:BB:CC:00:00:01", "pk=0123456789abcdef", "features=0x1,0x2",
                                "srcvers=000.0.0", "flags=0x4", "pi=00000000-0000-0000-0000-000000000001")

    @Test func seulLeModeleDuTXTDuNavigateurEstGarde() {
        let vues = [Listee(type: Self.type, instance: "HomePod Salon", txt: Self.txtComplet)]
        let cibles = [Recenseur.cle(Self.type, "HomePod Salon"): Cible(hote: "h1.local", port: 7000, txt: Data())]
        let a = Recenseur.assembler(vues: vues, cibles: cibles, adresses: [:], routes: [], prefixesLocaux: [], date: Date(timeIntervalSince1970: 0))
        let s = a.airplay.first
        #expect(s?.txt == ChampsTXT(["model": Data("Test1,1".utf8)]), "model et rien d'autre")
        #expect(s?.instance == "HomePod Salon" && s?.hote == "h1.local" && s?.port == 7000)
    }

    @Test func seulLeModeleDuTXTDeLaCibleEstGarde() {
        // Le navigateur n'a pas donne de TXT : celui de la cible, filtre de meme.
        let vues = [Listee(type: Self.type, instance: "HomePod Salon", txt: Data())]
        let cibles = [Recenseur.cle(Self.type, "HomePod Salon"): Cible(hote: "h1.local", port: 7000, txt: Self.txtComplet)]
        let a = Recenseur.assembler(vues: vues, cibles: cibles, adresses: [:], routes: [], prefixesLocaux: [], date: Date(timeIntervalSince1970: 0))
        #expect(a.airplay.first?.txt == ChampsTXT(["model": Data("Test1,1".utf8)]))
    }

    @Test func sansModeleLeTXTEstVide() {
        let vues = [Listee(type: Self.type, instance: "Appareil", txt: Self.txt("deviceid=AA:BB:CC:00:00:01"))]
        let cibles = [Recenseur.cle(Self.type, "Appareil"): Cible(hote: "h2.local", port: 7000, txt: Data())]
        let a = Recenseur.assembler(vues: vues, cibles: cibles, adresses: [:], routes: [], prefixesLocaux: [], date: Date(timeIntervalSince1970: 0))
        #expect(a.airplay.first?.txt.estVide == true)
    }

    @Test func lesAutresTypesGardentLeurTXT() {
        let txt = Self.txt("md=Eve Door", "id=AA:BB:CC:00:00:02")
        let vues = [Listee(type: "_hap._udp", instance: "Eve Door 4A3B", txt: txt)]
        let cibles = [Recenseur.cle("_hap._udp", "Eve Door 4A3B"): Cible(hote: "h3.local", port: 1, txt: Data())]
        let a = Recenseur.assembler(vues: vues, cibles: cibles, adresses: [:], routes: [], prefixesLocaux: [], date: Date(timeIntervalSince1970: 0))
        #expect(a.hap.first?.txt == ChampsTXT(brut: txt), "HAP : TXT inchange")
    }

    /// Un releve integre avec un TXT AirPlay complet (venu d'ailleurs que de l'assembleur) ne donne pas non plus sa capture
    /// exportee : le releve garde est reduit a l'entree.
    @Test func laCaptureExporteeNeGardeQueLeModele() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        let complet = AnnonceService(instance: "HomePod Salon", hote: "h1.local", port: 7000, txt: ChampsTXT(brut: Self.txtComplet))
        s.thread.integrer(Annonces(date: Date(timeIntervalSince1970: 1_790_000_000),
                                   routeurs: [AnnonceService(instance: "Routeur A", hote: "h1.local", port: 49153)],
                                   airplay: [complet]))
        let capture = try #require(try s.captureJSON())
        let texte = String(decoding: capture, as: UTF8.self)
        for interdit in ["deviceid", "AA:BB:CC:00:00:01", "0123456789abcdef", "features", "srcvers", "00000000-0000"] {
            #expect(!texte.contains(interdit), "la capture ne contient pas \(interdit)")
        }
        #expect(texte.contains("Test1,1"), "le modele reste")
        let lue = try CodageJSON.decodeur().decode(Annonces.self, from: capture)
        #expect(lue.airplay.first?.txt == ChampsTXT(["model": Data("Test1,1".utf8)]))
        #expect(lue.airplay.first?.instance == "HomePod Salon")
    }
}
