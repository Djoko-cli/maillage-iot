import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Historique du maillage : releves et fichiers mensuels")
struct HistoriqueTests {
    static func date(_ texte: String) -> Date {
        try! Date(texte, strategy: .iso8601)
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("historique-\(UUID().uuidString)")
    }

    /// Petit maillage (valeurs inventees) : le chef 0 et le routeur 1, muet, sans ExtMac ; la sonde
    /// 0001 sous 0 ; un enfant resolu sous 1 ; un enfant de table sans ExtMac ; deux signaux.
    static func maillage(_ date: Date) -> Maillage {
        var c = ConstructionMaillage(date: date, partition: "0000000A")
        c.routeurs(Route64(sequence: 1, routes: [RouteRouteur(idRouteur: 0, qualiteSortante: 3, qualiteEntrante: 2, cout: 1),
                                                 RouteRouteur(idRouteur: 1, qualiteSortante: 0, qualiteEntrante: 0, cout: 1)]),
                   chef: 0)
        c.identite("E0000000000000A0", routeur: 0)
        c.muet(1)
        c.lien(0, 1, sortante: 3, entrante: 2)
        c.enfant(EnfantMaillage(rloc16: 0x0001, extMac: "E0000000000000B1", qualite: 3, source: .sonde))
        c.enfant(EnfantMaillage(rloc16: 0x0402, extMac: "E0000000000000B2", source: .resolution))
        c.enfant(EnfantMaillage(rloc16: 0x0003, qualite: 2, source: .tableEnfants))
        c.signal(SignalSonde(routeur: 0, rssi: -60))
        c.signal(SignalSonde(routeur: 1, rssi: -75))
        return c.maillage()
    }

    /// Une ligne par tournee, en tableaux : routeurs, liens, enfants identifies (pas celui sans
    /// ExtMac) avec leur source, signaux, parent de la sonde. Relue a l'identique.
    @Test func ligneDUnReleve() throws {
        let r = ReleveMaillage(Self.maillage(Self.date("2026-09-30T10:00:00Z")))
        let json = String(decoding: try CodageJSON.encodeur().encode(r), as: UTF8.self)
        #expect(json == #"{"date":"2026-09-30T10:00:00.000Z","enfants":[["E0000000000000B1",0,3,"s"],["E0000000000000B2",1,null,"r"]],"liens":[[0,1,3,2]],"parentSonde":0,"partition":"0000000A","routeurs":[[0,"E0000000000000A0"],[1,null]],"signaux":[[0,-60],[1,-75]]}"#)
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(json.utf8)) == r)
        #expect(r.cle(routeur: 0) == "E0000000000000A0")
        #expect(r.cle(routeur: 1) == "rloc:0400", "sans ExtMac : son RLOC16")
    }

    /// Un enfant vu deux fois (il a change de parent) : la sonde passe avant une table, une table
    /// avant la resolution sous un routeur muet (qui peut dater de 30 minutes), quel que soit l'ordre
    /// des RLOC16 (donc des insertions). La sonde compte : son ancien parent la garde dans sa
    /// table jusqu'a l'echeance de l'enfant, et peut avoir le plus petit identifiant.
    @Test(arguments: [
        // (source de l'entree au plus petit RLOC16, parent ; source de l'autre, parent ; parent attendu)
        (SourceEnfant.resolution, 1, SourceEnfant.tableEnfants, 2, 2),
        (.tableEnfants, 2, .resolution, 1, 2),
        (.tableEnfants, 1, .sonde, 2, 2),
        (.sonde, 1, .tableEnfants, 2, 1),
        (.resolution, 1, .sonde, 2, 2),
        (.sonde, 1, .resolution, 2, 1),
    ])
    func enfantVuDeuxFois(premiere: SourceEnfant, parentPremiere: Int, seconde: SourceEnfant, parentSeconde: Int,
                          attendu: Int) {
        var c = ConstructionMaillage(date: Self.date("2026-09-30T10:00:00Z"), partition: "0000000A")
        c.enfant(EnfantMaillage(rloc16: UInt16(parentPremiere << 10) | 2, extMac: "E0000000000000B2", qualite: 3,
                                source: premiere))
        c.enfant(EnfantMaillage(rloc16: UInt16(parentSeconde << 10) | 5, extMac: "E0000000000000B2", qualite: 2,
                                source: seconde))
        let m = c.maillage()
        #expect(m.enfantsIdentifies["E0000000000000B2"]?.parent == attendu)
        #expect(ReleveMaillage(m).enfants.map(\.parent) == [attendu])
    }

    /// Un enfant devenu routeur garde jusqu'a 30 minutes son entree de la resolution sous un routeur muet :
    /// elle est ecartee, son ExtMac etant celle d'un routeur du maillage. L'historique n'a pas d'enfant de
    /// trop ; un autre enfant de la meme resolution reste.
    @Test func enfantDevenuRouteur() {
        var c = ConstructionMaillage(date: Self.date("2026-09-30T10:00:00Z"), partition: "0000000A")
        c.routeurs(Route64(sequence: 1, routes: [0, 1, 2].map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 0)
        c.identite("E0000000000000B2", routeur: 2)
        c.muet(1)
        c.enfant(EnfantMaillage(rloc16: 0x0402, extMac: "E0000000000000B2", source: .resolution))
        c.enfant(EnfantMaillage(rloc16: 0x0403, extMac: "E0000000000000B3", source: .resolution))
        let m = c.maillage()
        #expect(m.enfantsIdentifies["E0000000000000B2"] == nil, "devenu routeur")
        #expect(m.enfantsIdentifies["E0000000000000B3"]?.rloc16 == 0x0403)
        #expect(ReleveMaillage(m).enfants.map(\.extMac) == ["E0000000000000B3"])
    }

    /// Seule l'entree de la resolution est ecartee : une entree de la table d'un routeur ou de la sonde, que
    /// l'on vient de lire, garde son enfant, meme si son ExtMac est celle d'un routeur du maillage.
    @Test func entreeFraicheDunRouteurGardee() {
        var c = ConstructionMaillage(date: Self.date("2026-09-30T10:00:00Z"), partition: "0000000A")
        c.routeurs(Route64(sequence: 1, routes: [0, 1, 2].map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 3, qualiteEntrante: 3, cout: 1)
        }), chef: 0)
        c.identite("E0000000000000B2", routeur: 2)
        c.identite("E0000000000000B4", routeur: 1)
        c.enfant(EnfantMaillage(rloc16: 0x0402, extMac: "E0000000000000B2", source: .tableEnfants))
        c.enfant(EnfantMaillage(rloc16: 0x0404, extMac: "E0000000000000B4", source: .sonde))
        let m = c.maillage()
        #expect(m.enfantsIdentifies["E0000000000000B2"]?.rloc16 == 0x0402, "table d'un routeur")
        #expect(m.enfantsIdentifies["E0000000000000B4"]?.rloc16 == 0x0404, "sonde")
    }

    /// Un releve qui cite le routeur 63 (hors de 0...62 : des donnees non conformes) s'ecrit sans lui :
    /// ni ce routeur, ni ses liens, ni ses enfants, ni son signal, ni la sonde sous lui. Le reste de la
    /// ligne se relit, au lieu d'etre perdu avec elle.
    @Test func routeurHorsPlageNonEcrit() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let date = Self.date("2026-09-30T10:00:00Z")
        typealias R = ReleveMaillage
        try h.ajouter(R(date: date, partition: "0000000A",
                        routeurs: [R.Routeur(id: 0, extMac: "E0000000000000A0"), R.Routeur(id: 63, extMac: "E0000000000000A3")],
                        liens: [LienRadio(a: 0, b: 1, qualiteAB: 3, qualiteBA: 2), LienRadio(a: 0, b: 63, qualiteAB: 1, qualiteBA: 1)],
                        enfants: [R.Enfant(extMac: "E0000000000000B1", parent: 0, qualite: 3),
                                  R.Enfant(extMac: "E0000000000000B3", parent: 63, qualite: 2)],
                        signaux: [SignalSonde(routeur: 0, rssi: -60), SignalSonde(routeur: 63, rssi: -70)],
                        parentSonde: 63))
        let reste = R(date: date, partition: "0000000A", routeurs: [R.Routeur(id: 0, extMac: "E0000000000000A0")],
                      liens: [LienRadio(a: 0, b: 1, qualiteAB: 3, qualiteBA: 2)],
                      enfants: [R.Enfant(extMac: "E0000000000000B1", parent: 0, qualite: 3)],
                      signaux: [SignalSonde(routeur: 0, rssi: -60)], parentSonde: nil)
        #expect(try h.lire(depuis: .distantPast) == [reste])
    }

    /// Un octet non UTF-8 (0xC3 isole : un caractere accentue coupe) abime sa ligne seulement : les
    /// autres lignes du fichier sont lues, pour l'historique comme pour le journal.
    @Test func octetNonUTF8() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let avant = ReleveMaillage(Self.maillage(Self.date("2026-09-20T10:00:00Z")))
        let apres = ReleveMaillage(Self.maillage(Self.date("2026-09-21T10:00:00Z")))
        try h.ajouter(avant)
        let f = try FileHandle(forWritingTo: d.appendingPathComponent("maillage-2026-09.jsonl"))
        try f.seekToEnd()
        try f.write(contentsOf: Data(#"{"date":"2026-09-20T11:00:00.000Z","partition":"0000000A","x":""#.utf8) + Data([0xC3]))
        try f.write(contentsOf: Data("\"}\n".utf8))
        try f.close()
        try h.ajouter(apres)
        #expect(try h.lire(depuis: .distantPast) == [avant, apres])

        let j = JournalFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let e1 = Evenement(date: Self.date("2026-09-10T00:00:00Z"), type: .veille)
        let e2 = Evenement(date: Self.date("2026-09-11T00:00:00Z"), type: .veille)
        try j.ajouter([e1])
        let g = try FileHandle(forWritingTo: d.appendingPathComponent("journal-2026-09.jsonl"))
        try g.seekToEnd()
        try g.write(contentsOf: Data([0x7B, 0xC3, 0x0A]))
        try g.close()
        try j.ajouter([e2])
        #expect(try j.lire() == [e1, e2])
    }

    /// Un identifiant de routeur hors de 0...62 (un RLOC16 ne porte que 6 bits de routeur) rend la
    /// ligne illisible, donc ignoree : ni plantage, ni repli sur un autre routeur (64 donnerait 0).
    /// Les lignes voisines restent lues.
    @Test(arguments: [
        #""routeurs":[[70000,null]]"#,
        #""routeurs":[[-1,null]]"#,
        #""routeurs":[[64,null]]"#,
        #""routeurs":[[0,null]],"liens":[[0,70000,3,2]]"#,
        #""routeurs":[[0,null]],"liens":[[-1,0,3,2]]"#,
        #""routeurs":[[0,null]],"enfants":[["E0000000000000B1",64,3]]"#,
        #""routeurs":[[0,null]],"signaux":[[70000,-60]]"#,
        #""routeurs":[[0,null]],"parentSonde":64"#,
    ])
    func identifiantHorsPlageIgnore(champs: String) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let bon = ReleveMaillage(Self.maillage(Self.date("2026-09-20T10:00:00Z")))
        try h.ajouter(bon)
        let ligne = "{" + #""date":"2026-09-30T10:00:00.000Z","partition":"0000000A","# + Self.complete(champs) + "}"
        let f = try FileHandle(forWritingTo: d.appendingPathComponent("maillage-2026-09.jsonl"))
        try f.seekToEnd()
        try f.write(contentsOf: Data((ligne + "\n").utf8))
        try f.close()
        #expect(try h.lire(depuis: .distantPast) == [bon], "seule la ligne valide est lue : \(ligne)")
    }

    /// Les champs du cas, avec les tableaux vides pour ceux qu'il ne donne pas.
    private static func complete(_ champs: String) -> String {
        var texte = champs
        for cle in ["routeurs", "liens", "enfants", "signaux"] where !texte.contains("\"\(cle)\"") {
            texte += ",\"\(cle)\":[]"
        }
        return texte
    }

    /// `cle(routeur:)` est totale : un identifiant hors plage rend "rloc:?" au lieu d'arreter le
    /// programme (`UInt16(70000)`) ou de replier sur un autre routeur (`64 << 10` donne 0).
    @Test func cleDUnRouteurHorsPlage() {
        let r = ReleveMaillage(Self.maillage(Self.date("2026-09-30T10:00:00Z")))
        for id in [70000, -1, 63, 64, 1 << 40] { #expect(r.cle(routeur: id) == "rloc:?", "\(id)") }
        #expect(r.cle(routeur: 62) == "rloc:F800")
    }

    /// Tournee de la capture, avec des voisins : 7 routeurs, leurs liens avec leurs sources et 3 enfants
    /// identifies tiennent en moins de 700 octets ; avec 20 enfants (30 octets chacun), en moins de 1 Ko.
    @Test func tailleDUneLigne() async throws {
        let voisins = [VoisinSonde(rloc16: "E400", ext: "E0000000000000E4", rssi: -72, lqi: 3, routeur: true),
                       VoisinSonde(rloc16: "CC00", ext: "E0000000000000CC", rssi: -80, lqi: 3, routeur: true)]
        let (m, _) = try #require(try await Tournee.complete(try SondeRejouee.capture(voisins: voisins),
                                                               memoire: MemoireTournee(), maintenant: Self.date("2026-09-30T10:00:00Z")))
        let r = ReleveMaillage(m)
        #expect(r.routeurs.count == 7 && r.liens.count == 7)
        #expect(r.enfants.count == 3, "les enfants des tables qui ont donne leur identite")
        let octets = try CodageJSON.encodeur().encode(r).count
        #expect(octets < 700, "\(octets) octets")
        var vingt = r.enfants
        for n in 0..<17 {
            vingt.append(ReleveMaillage.Enfant(extMac: String(format: "E0000000000001%02X", n), parent: 24, qualite: 3,
                                               source: .tableEnfants))
        }
        let grand = ReleveMaillage(date: r.date, partition: r.partition, routeurs: r.routeurs, liens: r.liens, enfants: vingt,
                                   signaux: r.signaux, parentSonde: r.parentSonde)
        #expect(try CodageJSON.encodeur().encode(grand).count < 1024)
    }

    /// Fichiers `maillage-AAAA-MM.jsonl` du dossier de l'app : un releve par ligne, au mois de sa
    /// date (calendrier local) ; relus depuis une date, du plus ancien au plus recent, sans ligne
    /// illisible ; purges 90 jours apres la fin de leur mois ; les autres fichiers du dossier (un
    /// journal, ici dans le meme dossier ; dans l'app, il a son sous-dossier `Journal` ; et les
    /// identites) ne sont ni lus ni purges.
    @Test func fichiersMensuels() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        #expect(try h.lire(depuis: .distantPast).isEmpty, "dossier absent")
        let septembre = ReleveMaillage(Self.maillage(Self.date("2026-09-20T10:00:00Z")))
        let fin = ReleveMaillage(Self.maillage(Self.date("2026-09-30T21:00:00Z")))
        let octobre = ReleveMaillage(Self.maillage(Self.date("2026-10-02T10:00:00Z")))
        for r in [fin, septembre, octobre] { try h.ajouter(r) }
        let f = try FileHandle(forWritingTo: d.appendingPathComponent("maillage-2026-09.jsonl"))
        try f.seekToEnd()
        try f.write(contentsOf: Data("{pas du json\n".utf8))
        try f.close()
        try JournalFichiers(dossier: d, calendrier: JournalTests.calendrier)
            .ajouter([Evenement(date: Self.date("2026-09-10T00:00:00Z"), type: .veille)])
        try Data("{}".utf8).write(to: d.appendingPathComponent("identites-routeurs.json"))
        // 30/09 21:00 UTC = 01/10 01:00 a Asia/Tbilisi : fichier d'octobre.
        #expect(h.nomFichier(fin.date) == "maillage-2026-10.jsonl")
        #expect(try h.lire(depuis: .distantPast) == [septembre, fin, octobre])
        #expect(try h.lire(depuis: Self.date("2026-09-25T00:00:00Z")) == [fin, octobre])
        let supprimes = try h.purger(maintenant: Self.date("2027-01-05T12:00:00Z"))
        #expect(supprimes == ["maillage-2026-09.jsonl"], "septembre fini depuis 96 jours ; le journal reste")
        #expect(try h.lire(depuis: .distantPast) == [fin, octobre])
        let restants = try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
        #expect(restants == ["identites-routeurs.json", "journal-2026-09.jsonl", "maillage-2026-10.jsonl"])
    }

    /// Champs facultatifs de la sonde tout-en-un (spec, section 2.5) : la source de chaque sens d'un lien
    /// (`d` diagnostic, `e` ecoute), la source d'un enfant (`t` table, `r` resolution, `s` sonde) et le taux d'acces
    /// au canal refuses que donnent ses compteurs MAC, arrondi a 1/10 000, a titre d'information : il ne donne pas de
    /// qualite (un enfant resolu sous un routeur Apple reste en qualite inconnue). Pas les dates des mesures. Relue a
    /// l'identique.
    @Test func champsFacultatifs() throws {
        let t0 = Self.date("2026-10-07T10:00:00Z")
        var c = ConstructionMaillage(date: t0, partition: "0000000A")
        c.routeurs(Route64(sequence: 1, routes: [0, 1, 2].map {
            RouteRouteur(idRouteur: $0, qualiteSortante: 0, qualiteEntrante: 0, cout: 1)
        }), chef: 0)
        c.lien(0, 1, sortante: 3, entrante: 2, source: .diagnostic, date: t0)
        c.ecoute(Route64(sequence: 1, routes: [RouteRouteur(idRouteur: 1, qualiteSortante: 1, qualiteEntrante: 2, cout: 1)]),
                 routeur: 2, date: t0 - 120)
        c.enfant(EnfantMaillage(rloc16: 0x0A00, extMac: "E0000000000000C1", source: .resolution, resolu: t0,
                                echecs: 0.0071428))
        c.enfant(EnfantMaillage(rloc16: 0x0A01, extMac: "E0000000000000C2", source: .resolution, resolu: t0))
        let r = ReleveMaillage(c.maillage())
        let json = String(decoding: try CodageJSON.encodeur().encode(r), as: UTF8.self)
        #expect(json == #"{"date":"2026-10-07T10:00:00.000Z","enfants":[["E0000000000000C1",2,null,"r",0.0071],["E0000000000000C2",2,null,"r"]],"liens":[[0,1,3,2,"d","d"],[1,2,2,1,"e","e"]],"partition":"0000000A","routeurs":[[0,null],[1,null],[2,null]],"signaux":[]}"#)
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(json.utf8)) == r)
        #expect(r.liens.allSatisfy { $0.dateAB == nil && $0.dateBA == nil })
        #expect(r.enfants.first?.echecs == 0.0071 && r.enfants.first?.source == .resolution)
    }

    /// Lecture de l'ancien historique (avant la sonde tout-en-un) : les lignes sans les champs facultatifs se lisent
    /// comme avant, sources et taux inconnus ; une source inconnue (version plus recente) aussi.
    @Test func ancienHistorique() throws {
        let ancienne = #"{"date":"2026-09-30T10:00:00.000Z","enfants":[["E0000000000000B1",0,3],["E0000000000000B2",1,null]],"liens":[[0,1,3,2]],"parentSonde":0,"partition":"0000000A","routeurs":[[0,"E0000000000000A0"],[1,null]],"signaux":[[0,-60],[1,-75]]}"#
        let r = try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(ancienne.utf8))
        #expect(r.liens == [LienRadio(a: 0, b: 1, qualiteAB: 3, qualiteBA: 2)])
        #expect(r.enfants.map(\.source) == [nil, nil] && r.enfants.map(\.echecs) == [nil, nil])
        #expect(r.enfants.map(\.qualite) == [3, nil] && r.parentSonde == 0)
        let future = #"{"date":"2026-09-30T10:00:00.000Z","enfants":[["E0000000000000B1",0,3,"x",0.5]],"liens":[[0,1,3,2,"z",null]],"partition":"0000000A","routeurs":[],"signaux":[]}"#
        let f = try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(future.utf8))
        #expect(f.liens.first?.sourceAB == nil && f.enfants.first?.source == nil && f.enfants.first?.echecs == 0.5)
    }
}
