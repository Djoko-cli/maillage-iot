import Foundation
import Testing
@testable import MaillageCoeur

/// Appareils qui n'annoncent plus d'adresse, verifies par la sonde (12/10) : derniere adresse gardee par le suivi,
/// demandee a la sonde, appareils trouves portes par le maillage, rapprochement par la derniere adresse.
@Suite("Adresse non annoncee, verifiee par la sonde")
struct AdresseVerifieeTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let omr = "fd00:aaaa:bbbb:1::/64"
    static let partition = "0000AAAA"
    static let a1 = "0000000000000001"
    static let a2 = "0000000000000002"
    static let a3 = "0000000000000003"

    static func adresse(_ n: Int) -> String { "fd00:aaaa:bbbb:1::\(n)" }

    /// Un chef qui publie le prefixe OMR, trois appareils avec leur adresse, un appareil sans adresse des le depart.
    static func banc(_ date: Date, partition: String = partition) -> Banc {
        var b = Banc(date: date)
        b.routeur("Chef", partition: partition, role: .chef, primaire: true, lien: "fe80::1", omr: omr,
                  xa: "E1000000000000A1")
        b.appareil(a1, noeud: 1, adresses: [adresse(1), "fe80::11"])
        b.appareil(a2, noeud: 2, adresses: [adresse(2)])
        b.appareil(a3, noeud: 3, adresses: [adresse(3)])
        b.appareil("Jamais-Adresse", noeud: 4, adresses: [])
        return b
    }

    /// Le suivi apres le depart, puis `a1` sans adresse et `a2` disparu, au-dela du sursis de 2 min.
    static func suiviApresPerte() -> Suivi {
        var s = Suivi()
        _ = s.integrer(banc(t0).annonces)
        var b = banc(t0 + 60)
        b.adresses[a1 + ".local"] = []
        b.retirer(a2)
        _ = s.integrer(b.annonces)
        b.date = t0 + 200
        _ = s.integrer(b.annonces)
        return s
    }

    /// La derniere adresse sur le prefixe OMR de chaque appareil est gardee, et mise a jour a chaque instantane ou il
    /// en a une ; perdue par Bonjour, elle reste.
    @Test func derniereAdresseGardee() throws {
        var s = Suivi()
        _ = s.integrer(Self.banc(Self.t0).annonces)
        #expect(s.dernieresAdresses[Self.a1] == AdresseIPv6(Self.adresse(1)), "l'adresse OMR, pas la lien-local")
        #expect(s.dernieresAdresses["Jamais-Adresse"] == nil)
        var b = Self.banc(Self.t0 + 60)
        b.adresses[Self.a1 + ".local"] = [Self.adresse(0x21)]
        _ = s.integrer(b.annonces)
        #expect(s.dernieresAdresses[Self.a1] == AdresseIPv6(Self.adresse(0x21)), "mise a jour")
        let perdu = Self.suiviApresPerte()
        #expect(perdu.instantane?.appareil(Self.a1)?.etat == .sansAdresse)
        #expect(perdu.disparus[Self.a2] != nil)
        #expect(perdu.dernieresAdresses[Self.a1] == AdresseIPv6(Self.adresse(1)), "gardee sans adresse")
        #expect(perdu.dernieresAdresses[Self.a2] == AdresseIPv6(Self.adresse(2)), "gardee disparu")
    }

    /// Les appareils a resoudre : ceux qui annoncent leur adresse, puis l'appareil sans adresse et le disparu, avec
    /// leur derniere adresse et leur derniere partition ; pas un appareil qui n'a jamais eu d'adresse OMR.
    @Test func sansAdresseEtDisparuDemandes() throws {
        let s = Self.suiviApresPerte()
        let p = Self.partition
        let annonce1 = try #require(s.dernieresAnnonces[Self.a1])
        let annonce2 = try #require(s.dernieresAnnonces[Self.a2])
        #expect(AppareilAResoudre.depuis(s) == [
            AppareilAResoudre(id: Self.a1, partition: p, adresse: try #require(AdresseIPv6(Self.adresse(1))),
                              derniereAnnonce: annonce1),
            AppareilAResoudre(id: Self.a2, partition: p, adresse: try #require(AdresseIPv6(Self.adresse(2))),
                              derniereAnnonce: annonce2, disparu: true),
            AppareilAResoudre(id: Self.a3, partition: p, adresse: try #require(AdresseIPv6(Self.adresse(3)))),
        ])
        let i = try #require(s.instantane)
        #expect(AppareilAResoudre.depuis(i).map(\.id) == [Self.a3], "l'instantane seul : ceux qui l'annoncent")
        #expect(AppareilAResoudre.depuis(Suivi()).isEmpty, "aucun sans instantane")
    }

    /// La date de la derniere annonce de l'adresse OMR est gardee a cote de la derniere adresse : mise a jour a chaque
    /// releve ou l'appareil en a une, figee quand il passe sans adresse ou disparait, absente s'il n'en a jamais eu.
    @Test func derniereAnnonceGardee() throws {
        var s = Suivi()
        _ = s.integrer(Self.banc(Self.t0).annonces)
        #expect(s.dernieresAnnonces[Self.a1] == Self.t0 && s.dernieresAnnonces[Self.a2] == Self.t0)
        #expect(s.dernieresAnnonces["Jamais-Adresse"] == nil)
        let perdu = Self.suiviApresPerte()
        let a1 = try #require(perdu.dernieresAnnonces[Self.a1])
        let a2 = try #require(perdu.dernieresAnnonces[Self.a2])
        #expect(a1 >= Self.t0 && a1 <= Self.t0 + 60, "figee a la perte, avant le releve de t0 + 200")
        #expect(a2 >= Self.t0 && a2 <= Self.t0 + 60)
        #expect(perdu.dernieresAnnonces[Self.a3] == Self.t0 + 200, "il annonce encore : le dernier releve")
        #expect(perdu.dernieresAnnonces["Jamais-Adresse"] == nil)
    }

    // MARK: Redemande rapide apres la perte de l'annonce

    /// L'appareil `id` de la capture de `TourneeTests`, tel qu'il est demande une fois perdu : derniere annonce a
    /// `annonce`, disparu ou non.
    static func perdu(_ id: String, annonce: Date, disparu: Bool = false) throws -> AppareilAResoudre {
        let a = try #require(TourneeTests.appareils.first { $0.id == id })
        return AppareilAResoudre(id: a.id, partition: a.partition, adresse: a.adresse, derniereAnnonce: annonce,
                                 disparu: disparu)
    }

    /// Adresses demandees a la sonde (resolution) depuis `avant` requetes.
    static func demandees(_ sonde: SondeRejouee, depuis avant: Int) async -> [String] {
        await sonde.registre.requetes.dropFirst(avant).filter { $0.hasSuffix("|resoudre") }.sorted()
    }

    static func cle(_ n: Int) -> String { "\(TourneeTests.omr(n))|resoudre" }

    /// Une resolution faite avant la perte de l'annonce est refaite a la tournee suivante, meme si l'appareil a deja
    /// ete demande ; celle d'un appareil qui annonce, ou posterieure a la perte, ne l'est pas avant la resolution
    /// complete.
    @Test func perduRedemandeALaTourneeSuivante() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: TourneeTests.appareils))
        #expect(mem1.demandes.contains("E00000000000000A") && mem1.resolutions["E00000000000000A"]?.date == Self.t0)
        // A perd son annonce apres sa resolution ; B l'a perdue avant (sa resolution est posterieure) ; les autres
        // annoncent.
        var appareils = TourneeTests.appareils
        let iA = try #require(appareils.firstIndex { $0.id == "E00000000000000A" })
        let iB = try #require(appareils.firstIndex { $0.id == "E00000000000000B" })
        appareils[iA] = try Self.perdu("E00000000000000A", annonce: Self.t0 + 100)
        appareils[iB] = try Self.perdu("E00000000000000B", annonce: Self.t0 - 100)
        for instant in [Self.t0 + 300, Self.t0 + 600] {
            let avant = await sonde.registre.requetes.count
            let (_, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: instant,
                                                                    appareils: appareils))
            #expect(await Self.demandees(sonde, depuis: avant) == [Self.cle(0x0A)],
                    "A seul, bien qu'il soit deja dans les demandes")
            #expect(mem2.resolutions["E00000000000000A"]?.date == instant, "sa resolution est refaite")
            #expect(mem2.derniereResolution == Self.t0, "pas une resolution complete")
            // Resolu apres la perte : il n'est plus redemande a la tournee d'apres.
            let avant2 = await sonde.registre.requetes.count
            _ = try #require(try await Tournee.complete(sonde, memoire: mem2, maintenant: instant + 300,
                                                        appareils: appareils))
            #expect(await Self.demandees(sonde, depuis: avant2).isEmpty)
        }
    }

    /// Un appareil perdu que la sonde ne trouve pas (aucune resolution) est redemande a chaque tournee pendant les
    /// 30 min qui suivent sa derniere annonce, puis seulement a la resolution complete.
    @Test func perduIntrouvableRedemandePendantTrenteMinutes() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let c = "E00000000000000C"
        var recent = TourneeTests.appareils
        let iC = try #require(recent.firstIndex { $0.id == c })
        recent[iC] = try Self.perdu(c, annonce: Self.t0 - 100)
        let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: recent))
        #expect(mem1.demandes.contains(c) && mem1.resolutions[c] == nil, "demande, introuvable")
        var mem = mem1
        for instant in [Self.t0 + 300, Self.t0 + 600, Self.t0 + 1700] {
            let avant = await sonde.registre.requetes.count
            (_, mem) = try #require(try await Tournee.complete(sonde, memoire: mem, maintenant: instant,
                                                               appareils: recent))
            #expect(await Self.demandees(sonde, depuis: avant) == [Self.cle(0x0C)], "a chaque tournee")
        }
        // Perdu depuis plus de 30 min : plus qu'a la resolution complete (t0 + 1800).
        var ancien = recent
        ancien[iC] = try Self.perdu(c, annonce: Self.t0 - 2000)
        for instant in [Self.t0 + 300, Self.t0 + 1700] {
            let avant = await sonde.registre.requetes.count
            _ = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: instant, appareils: ancien))
            #expect(await Self.demandees(sonde, depuis: avant).isEmpty, "pas avant la resolution complete")
        }
        let avant = await sonde.registre.requetes.count
        _ = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 1800,
                                                    appareils: ancien))
        #expect(await Self.demandees(sonde, depuis: avant).contains(Self.cle(0x0C)), "a la resolution complete")
    }

    /// Un disparu dont la derniere annonce date de plus de 24 h n'est plus demande, meme a la resolution complete ; un
    /// disparu plus recent l'est, et un appareil sans adresse (Bonjour l'annonce encore) l'est toujours.
    @Test func disparuAncienPlusDemande() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let jour: TimeInterval = 24 * 3600
        let appareils = [
            try Self.perdu("E00000000000000A", annonce: Self.t0 - jour - 60, disparu: true),
            try Self.perdu("E00000000000000B", annonce: Self.t0 - jour + 60, disparu: true),
            try Self.perdu("E000000000000004", annonce: Self.t0 - jour - 60),
        ]
        let (_, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                              appareils: appareils))
        #expect(await Self.demandees(sonde, depuis: 0) == [Self.cle(0x04), Self.cle(0x0B)].sorted())
        #expect(mem.demandes == ["E00000000000000B", "E000000000000004"])
    }

    /// Apres une relance de l'app, la memoire de la tournee est vide : la premiere tournee est une resolution complete.
    /// Un appareil sans adresse dont la derniere annonce relue date de plusieurs heures y est demande, comme un
    /// disparu de moins de 24 h ; pas un disparu de plus de 24 h.
    @Test func derniereAnnonceReluePlusAncienneDemandeALaPremiereTournee() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let appareils = [
            try Self.perdu("E00000000000000A", annonce: Self.t0 - 5 * 3600),
            try Self.perdu("E00000000000000B", annonce: Self.t0 - 5 * 3600, disparu: true),
            try Self.perdu("E000000000000004", annonce: Self.t0 - 25 * 3600, disparu: true),
        ]
        let (_, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                              appareils: appareils))
        #expect(await Self.demandees(sonde, depuis: 0) == [Self.cle(0x0A), Self.cle(0x0B)].sorted())
        #expect(mem.resolutions["E00000000000000A"]?.date == Self.t0 && mem.derniereResolution == Self.t0)
    }

    /// Ce qu'un lancement precedent avait garde (`adressesGardees`) amorce le suivi : un appareil sans adresse au
    /// premier releve est demande avec sa derniere adresse et sa derniere annonce relues. Ce que le suivi a vu depuis
    /// l'emporte (adresse et annonce ensemble) ; la partition vue aussi.
    @Test func suiviAmorceParLesAdressesGardees() throws {
        let avant = Self.suiviApresPerte()
        let gardees = avant.adressesGardees
        #expect(gardees[Self.a1]?.adresse == AdresseIPv6(Self.adresse(1)))
        #expect(gardees[Self.a1]?.partition == Self.partition)
        #expect(gardees[Self.a1]?.annonce == avant.dernieresAnnonces[Self.a1])
        #expect(gardees["Jamais-Adresse"] == nil, "jamais d'adresse : rien a garder")
        let relu = try CodageJSON.decodeur().decode([String: Suivi.AdresseGardee].self,
                                                    from: CodageJSON.encodeur().encode(gardees))
        #expect(relu == gardees, "aller-retour JSON, dates a la milliseconde")

        // Un nouveau suivi : a1 est sans adresse des le premier releve (3 h plus tard).
        var s = Suivi()
        s.amorcer(relu)
        #expect(AppareilAResoudre.depuis(s).isEmpty, "pas d'instantane, rien a demander")
        var b = Self.banc(Self.t0 + 3 * 3600)
        b.adresses[Self.a1 + ".local"] = []
        _ = s.integrer(b.annonces)
        let a1 = try #require(AppareilAResoudre.depuis(s).first { $0.id == Self.a1 })
        #expect(a1.adresse == AdresseIPv6(Self.adresse(1)) && a1.partition == Self.partition)
        #expect(a1.derniereAnnonce == avant.dernieresAnnonces[Self.a1] && !a1.disparu)
        // a3 annonce : son adresse vient du releve, pas du fichier ; amorcer ne l'ecrase pas non plus.
        #expect(s.dernieresAnnonces[Self.a3] == Self.t0 + 3 * 3600)
        var autre = s
        autre.amorcer([Self.a3: .init(adresse: try #require(AdresseIPv6("fd00:aaaa:bbbb:1::99")),
                                     partition: "0000BBBB", annonce: Self.t0)])
        #expect(autre.dernieresAdresses[Self.a3] == AdresseIPv6(Self.adresse(3)))
        #expect(autre.dernieresAnnonces[Self.a3] == Self.t0 + 3 * 3600)
        #expect(autre.dernieresPartitions[Self.a3] == Self.partition)
    }

    /// Une resolution anterieure a la perte de l'annonce ne place plus l'appareil sous son parent, tant que la sonde ne
    /// l'a pas retrouve (ici introuvable apres la perte) ; posterieure a la perte, elle le place toujours.
    @Test func resolutionAnterieureNePlacePlus() async throws {
        let a = "E00000000000000A"
        let premiere = try TourneeTests.sondeResolue()
        let (m1, mem1) = try #require(try await Tournee.complete(premiere, memoire: MemoireTournee(),
                                                                 maintenant: Self.t0,
                                                                 appareils: TourneeTests.appareils))
        #expect(m1.enfants.contains { $0.extMac == a && $0.source == .resolution }, "place sous son parent muet")
        // Apres la perte, la sonde ne le trouve plus ; sa resolution de t0 reste dans la memoire.
        var introuvable = TourneeTests.resolutions
        introuvable["\(TourneeTests.omr(0x0A))"] = nil
        let sonde = try TourneeTests.sondeResolue(resolutions: introuvable)
        let i = try #require(TourneeTests.appareils.firstIndex { $0.id == a })
        for (annonce, place) in [(Self.t0 + 100, false), (Self.t0, false), (Self.t0 - 100, true)] {
            var appareils = TourneeTests.appareils
            appareils[i] = try Self.perdu(a, annonce: annonce)
            let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300,
                                                                     appareils: appareils))
            #expect(mem2.resolutions[a]?.date == Self.t0, "la resolution de t0 reste en memoire")
            #expect(m2.enfants.contains { $0.extMac == a && $0.source == .resolution } == place)
        }
    }

    /// Un appareil que l'app ne demande plus (son adresse est annoncee par un autre identifiant) n'est plus place sous
    /// son parent par sa resolution d'avant, gardee en memoire jusqu'a la resolution complete suivante.
    @Test func horsDeLaListeNePlacePlus() async throws {
        let a = "E00000000000000A"
        let sonde = try TourneeTests.sondeResolue()
        let (m1, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(),
                                                                 maintenant: Self.t0,
                                                                 appareils: TourneeTests.appareils))
        #expect(m1.enfants.contains { $0.extMac == a && $0.source == .resolution })
        let sansA = TourneeTests.appareils.filter { $0.id != a }
        let (m2, mem2) = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300,
                                                                 appareils: sansA))
        #expect(mem2.resolutions[a] != nil, "sa resolution reste en memoire")
        #expect(!m2.enfants.contains { $0.extMac == a }, "mais il n'est plus place")
        #expect(m2.enfants.contains { $0.source == .resolution }, "les autres le sont toujours")
    }

    /// Le maillage porte les appareils trouves par la resolution (la memoire de la tournee), quel que soit leur
    /// parent, avec leur date ; pas l'introuvable. Ils ne sont pas gardes sur disque : relu, le maillage n'en a aucun.
    @Test func resolusDansLeMaillage() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                               appareils: TourneeTests.appareils))
        #expect(m.resolus == mem.resolutions.mapValues(\.date))
        #expect(m.resolusRepondus == Set(m.resolus.keys), "capture du firmware 1.1.1 : repondu vrai")
        #expect(m.resolus["E000000000000004"] == Self.t0, "sous le 20, qui repond : trouve aussi")
        #expect(m.resolus["E00000000000000C"] == nil, "introuvable")
        let relu = try CodageJSON.decodeur().decode(Maillage.self, from: try CodageJSON.encodeur().encode(m))
        #expect(relu.resolus.isEmpty && relu.resolusRepondus.isEmpty && relu.enfants == m.enfants
                && relu.resolution == m.resolution)
    }

    /// Un enfant resolu qui n'a l'adresse annoncee d'aucun appareil est rapproche de l'appareil dont c'est la
    /// derniere adresse (un accessoire HomeKit, dont l'hote n'est pas l'ExtMac) ; sans elle, il reste inconnu.
    @Test func rapprocheParSaDerniereAdresse() async throws {
        let sonde = try TourneeTests.sondeResolue()
        let (m, _) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(), maintenant: Self.t0,
                                                             appareils: TourneeTests.appareils))
        var b = Banc()
        b.routeur("Apple TV", partition: "46CBEBCD", primaire: true, lien: "fe80::1", omr: "fd00:aaaa:bbbb:1::/64",
                  xa: "E0000000000000A1")
        b.appareil("Prise-HomeKit", noeud: 1, adresses: [])
        let i = Instantane(annonces: b.annonces)
        let r = try #require(i.reseaux.first)
        let sans = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils)
        #expect(sans.enfants[0xAE01]?.id == "rloc:AE01")
        let avec = MaillageAffiche(maillage: m, reseau: r, appareils: i.appareils,
                                   dernieresAdresses: ["Prise-HomeKit": TourneeTests.omr(0x50)])
        #expect(avec.enfants[0xAE01]?.id == "Prise-HomeKit")
        #expect(avec.parent(de: "Prise-HomeKit") == avec.routeurs[43]?.id)
    }

    // MARK: Preuve par la reponse de l'appareil (firmware 1.1.1)

    /// La capture rejouee de `TourneeTests`, chaque resolution portant `repondu` (nil : firmware ancien, sans champ).
    static func sondeRepondu(_ repondu: Bool?) throws -> SondeRejouee {
        let resolutions = TourneeTests.resolutions.mapValues {
            ResultatResolution(id: $0.id, cible: $0.cible, ok: $0.ok, ms: $0.ms, rloc16: $0.rloc16, mleid: $0.mleid,
                               erreur: $0.erreur, repondu: repondu)
        }
        return try TourneeTests.sondeResolue(resolutions: resolutions)
    }

    static func place(_ id: String, dans m: Maillage) -> Bool {
        m.enfants.contains { $0.extMac == id && $0.source == .resolution }
    }

    /// Un appareil qui n'annonce plus son adresse n'est place sous son parent, ni porte par `resolusRepondus`, que si
    /// la sonde dit qu'il a repondu (vrai) ; faux (cache seul) ou nil (firmware ancien) : ni l'un ni l'autre. Un
    /// appareil qui annonce son adresse est place comme avant, quel que soit `repondu`.
    @Test func repondu() async throws {
        let a = "E00000000000000A", b = "E00000000000000B"
        var appareils = TourneeTests.appareils
        let iA = try #require(appareils.firstIndex { $0.id == a })
        appareils[iA] = try Self.perdu(a, annonce: Self.t0 - 100)
        for repondu in [true, false, nil] as [Bool?] {
            let sonde = try Self.sondeRepondu(repondu)
            let (m, mem) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(),
                                                                   maintenant: Self.t0, appareils: appareils))
            let texte = "repondu \(String(describing: repondu))"
            #expect(mem.resolutions[a]?.repondu == repondu, "porte par la memoire : \(texte)")
            #expect(m.resolus[a] == Self.t0, "toujours resolu : \(texte)")
            #expect(Self.place(a, dans: m) == (repondu == true), "perdu : place seulement si repondu vrai, \(texte)")
            #expect(m.resolusRepondus.contains(a) == (repondu == true), Comment(rawValue: texte))
            #expect(Self.place(b, dans: m), "il annonce son adresse : place quel que soit repondu, \(texte)")
            #expect(m.resolusRepondus.contains(b) == (repondu == true), Comment(rawValue: texte))
        }
    }

    /// Un perdu dont la resolution posterieure n'a pas ete repondue (cache seul, ou firmware ancien) reste redemande a
    /// chaque tournee pendant 30 min, comme un introuvable ; repondu vrai, il ne l'est plus avant la resolution
    /// complete.
    @Test func perduNonRepondantRedemande() async throws {
        let a = "E00000000000000A"
        var appareils = TourneeTests.appareils
        let iA = try #require(appareils.firstIndex { $0.id == a })
        appareils[iA] = try Self.perdu(a, annonce: Self.t0 - 100)
        for repondu in [true, false, nil] as [Bool?] {
            let sonde = try Self.sondeRepondu(repondu)
            let (_, mem1) = try #require(try await Tournee.complete(sonde, memoire: MemoireTournee(),
                                                                    maintenant: Self.t0, appareils: appareils))
            let avant = await sonde.registre.requetes.count
            _ = try #require(try await Tournee.complete(sonde, memoire: mem1, maintenant: Self.t0 + 300,
                                                        appareils: appareils))
            let redemande = await Self.demandees(sonde, depuis: avant)
            #expect(redemande == (repondu == true ? [] : [Self.cle(0x0A)]), "repondu \(String(describing: repondu))")
        }
    }

    /// `ResolutionAppareil.prouve(apres:)` : repondu vrai ET posterieure a la derniere annonce.
    @Test func preuvePosterieureEtRepondue() throws {
        let ad = try #require(AdresseIPv6(Self.adresse(1)))
        func resolution(_ repondu: Bool?) -> ResolutionAppareil {
            ResolutionAppareil(rloc16: 0xAC00, mleid: nil, adresse: ad, date: Self.t0, repondu: repondu)
        }
        #expect(resolution(true).prouve(apres: Self.t0 - 1))
        #expect(!resolution(true).prouve(apres: Self.t0), "egale : pas posterieure")
        #expect(!resolution(true).prouve(apres: Self.t0 + 1))
        #expect(!resolution(false).prouve(apres: Self.t0 - 1))
        #expect(!resolution(nil).prouve(apres: Self.t0 - 1))
    }

    // MARK: Partition d'aujourd'hui

    /// Apres un changement de partition (perte du chef, fusion) avec le meme prefixe OMR, un appareil disparu (que
    /// l'instantane ne montre plus, donc dont la derniere partition vue ne change plus) est demande dans la partition
    /// qui porte aujourd'hui le prefixe de sa derniere adresse, et non dans l'ancienne. Sans partition qui porte ce
    /// prefixe, sa derniere partition connue sert de repli.
    @Test func perduDemandeDansLaPartitionDAujourdhui() throws {
        let b = "0000BBBB"
        var s = Suivi()
        _ = s.integrer(Self.banc(Self.t0).annonces)
        #expect(s.dernieresPartitions[Self.a2] == Self.partition)
        // a2 s'en va ; la partition change quand le sursis de 2 min s'acheve et le fait disparaitre.
        var parti = Self.banc(Self.t0 + 60)
        parti.retirer(Self.a2)
        _ = s.integrer(parti.annonces)
        var change = Self.banc(Self.t0 + 200, partition: b)
        change.retirer(Self.a2)
        _ = s.integrer(change.annonces)
        #expect(s.disparus[Self.a2] != nil)
        #expect(s.dernieresPartitions[Self.a2] == Self.partition, "la derniere partition vue reste l'ancienne")
        #expect(s.partitionActuelle(de: Self.a2) == b)
        let demande = try #require(AppareilAResoudre.depuis(s).first { $0.id == Self.a2 })
        #expect(demande.partition == b && demande.adresse == AdresseIPv6(Self.adresse(2)) && demande.disparu)
        // Celui qui annonce encore a la partition de l'instantane, comme avant.
        #expect(AppareilAResoudre.depuis(s).first { $0.id == Self.a3 }?.partition == b)

        // Aucune partition ne porte le prefixe (ici, pas encore d'instantane apres une relance) : repli sur la derniere
        // partition connue ; un appareil inconnu n'en a pas.
        var relance = Suivi()
        relance.amorcer([Self.a2: .init(adresse: try #require(AdresseIPv6(Self.adresse(2))), partition: Self.partition,
                                        annonce: Self.t0)])
        #expect(relance.partitionActuelle(de: Self.a2) == Self.partition)
        #expect(relance.partitionActuelle(de: "inconnu") == nil)
        let autre = Banc(date: Self.t0 + 3600)
        _ = relance.integrer(autre.annonces)
        #expect(relance.partitionActuelle(de: Self.a2) == Self.partition, "aucune partition ne porte le prefixe")
    }

    // MARK: Meme appareil sous un nouvel hote

    /// Un perdu dont la derniere adresse est annoncee aujourd'hui par un autre identifiant (le meme appareil sous un
    /// nouvel hote) n'est pas demande : pas de doublon joignable. Les autres perdus le sont toujours.
    @Test func perduRevenuSousUnAutreHote() throws {
        var s = Self.suiviApresPerte()
        #expect(AppareilAResoudre.depuis(s).map(\.id) == [Self.a1, Self.a2, Self.a3])
        #expect(!s.adresseAnnonceeParUnAutre(Self.a1))
        var b = Self.banc(Self.t0 + 300)
        b.adresses[Self.a1 + ".local"] = []
        b.retirer(Self.a2)
        b.appareil("0000000000000009", noeud: 9, adresses: [Self.adresse(1)])
        _ = s.integrer(b.annonces)
        #expect(s.adresseAnnonceeParUnAutre(Self.a1))
        #expect(!s.adresseAnnonceeParUnAutre(Self.a2))
        #expect(!s.adresseAnnonceeParUnAutre("0000000000000009"), "le nouvel hote ne s'exclut pas lui-meme")
        #expect(AppareilAResoudre.depuis(s).map(\.id) == [Self.a2, Self.a3, "0000000000000009"].sorted(),
                "a1 n'est plus demande, a2 (disparu) l'est toujours")
    }
}
