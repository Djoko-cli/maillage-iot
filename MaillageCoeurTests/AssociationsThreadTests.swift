import Foundation
import Testing
@testable import MaillageCoeur

/// « Associer a un accessoire de Maison » (12/10) : un appareil que Maison ne nomme pas par son noeud (il a perdu son
/// inscription a la fabrique d'Apple, son noeud exporte n'est annonce par personne) prend le nom et la piece de
/// l'accessoire que l'utilisateur lui associe. Valeurs inventees.
@Suite("Associations a un accessoire de Maison : resolution des noms (Thread)")
struct AssociationsThreadTests {
    static let fabrique = "30FC8F95E0E1A385"
    static let nomme = "AAAA000000000001"
    static let muet = "AAAA000000000002"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// Deux appareils annonces sur la fabrique d'Apple : le noeud 1, que Maison nomme, et le noeud 0x99, qu'il ne
    /// connait pas.
    static func instantane() -> Instantane {
        var b = Banc()
        b.appareil(nomme, noeud: 1, adresses: ["fd00:aaaa:bbbb::1"])
        b.appareil(muet, noeud: 0x99, adresses: ["fd00:aaaa:bbbb::2"])
        return Instantane(annonces: b.annonces)
    }

    /// Maison : « Detecteur 1 » (noeud 1, annonce), et des accessoires dont le noeud n'est annonce par personne, ou
    /// sans noeud utile.
    static func maison() -> NomsMaison {
        NomsMaison(date: date, accessoires: [
            AccessoireMaison(nom: "Detecteur 1", piece: "Piece 1", noeudMatter: "0000000000000001"),
            AccessoireMaison(nom: "Detecteur 2", piece: "Piece 2", modele: "Modele 1", noeudMatter: "00000000000000AA"),
            AccessoireMaison(nom: "Detecteur 3", piece: "Piece 1", noeudMatter: "00000000000000BB"),
            AccessoireMaison(nom: "Detecteur 4", piece: "Piece 3"),
            AccessoireMaison(nom: "Detecteur 5", piece: "Piece 3", noeudMatter: "0000000000000000"),
        ])
    }

    static func appareil(_ id: String) throws -> Appareil {
        try #require(instantane().appareil(id))
    }

    @Test func resolutionDuNomEtDeLaPiece() throws {
        let i = Self.instantane()
        let sans = ResolveurNoms(maison: Self.maison())
        let f = try #require(sans.fabriqueApple(appareils: i.appareils))
        #expect(f == Self.fabrique)
        let muet = try Self.appareil(Self.muet)
        #expect(sans.accessoire(de: muet, fabriqueApple: f) == nil)
        #expect(sans.nom(appareil: muet, fabriqueApple: f) == Self.muet, "Maison ne le nomme pas")
        #expect(!sans.associeALaMain(muet, fabriqueApple: f))

        let avec = ResolveurNoms(maison: Self.maison(), associations: [Self.muet: "00000000000000AA"])
        let a = try #require(avec.accessoire(de: muet, fabriqueApple: f))
        #expect(a.nom == "Detecteur 2" && a.piece == "Piece 2" && a.modele == "Modele 1")
        #expect(avec.nom(appareil: muet, fabriqueApple: f) == "Detecteur 2")
        #expect(avec.associeALaMain(muet, fabriqueApple: f))
        // Le noeud en minuscules du fichier se lit tout de meme.
        let minuscules = ResolveurNoms(maison: Self.maison(), associations: [Self.muet: "00000000000000aa"])
        #expect(minuscules.nom(appareil: muet, fabriqueApple: f) == "Detecteur 2")
        // Sans fabrique connue, l'association vaut aussi.
        #expect(avec.nom(appareil: muet, fabriqueApple: nil) == "Detecteur 2")
        // L'autre appareil garde son nom par son noeud.
        let nomme = try Self.appareil(Self.nomme)
        #expect(avec.nom(appareil: nomme, fabriqueApple: f) == "Detecteur 1")
        #expect(!avec.associeALaMain(nomme, fabriqueApple: f))
        // Une association vers un accessoire qui n'est plus dans Maison, ou sans Maison : rien.
        #expect(ResolveurNoms(maison: Self.maison(), associations: [Self.muet: "00000000000000CC"])
            .nom(appareil: muet, fabriqueApple: f) == Self.muet)
        #expect(ResolveurNoms(associations: [Self.muet: "00000000000000AA"])
            .nom(appareil: muet, fabriqueApple: f) == Self.muet)
        // Le noeud nul n'identifie personne, association comprise.
        #expect(ResolveurNoms(maison: Self.maison(), associations: [Self.muet: "0000000000000000"])
            .nom(appareil: muet, fabriqueApple: f) == Self.muet)
    }

    @Test func orphelins() throws {
        let i = Self.instantane()
        var n = ResolveurNoms(maison: Self.maison())
        let f = n.fabriqueApple(appareils: i.appareils)
        // Ni annonce (Detecteur 1), ni sans noeud (4), ni noeud nul (5).
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: f).map(\.nom) == ["Detecteur 2", "Detecteur 3"])
        n.associations[Self.muet] = "00000000000000AA"
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: f).map(\.nom) == ["Detecteur 3"], "deja associe")
        // Un accessoire qui partage le noeud d'un accessoire associe n'est plus propose non plus.
        n.maison?.accessoires.append(AccessoireMaison(nom: "Detecteur 6", noeudMatter: "00000000000000AA"))
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: f).map(\.nom) == ["Detecteur 3"])
        // Sans Maison : rien. Un disparu qui annonce le noeud le prend aussi : il n'est pas orphelin.
        #expect(ResolveurNoms().orphelins(appareils: i.appareils, fabriqueApple: f).isEmpty)
        var b = Banc()
        b.appareil("AAAA000000000003", noeud: 0xBB, adresses: ["fd00:aaaa:bbbb::3"])
        let disparu = try #require(Instantane(annonces: b.annonces).appareil("AAAA000000000003"))
        #expect(ResolveurNoms(maison: Self.maison()).orphelins(appareils: i.appareils + [disparu], fabriqueApple: f)
            .map(\.nom) == ["Detecteur 2"])
        // Tri par nom puis par piece.
        let tri = ResolveurNoms(maison: NomsMaison(date: Self.date, accessoires: [
            AccessoireMaison(nom: "B", piece: "Piece 2", noeudMatter: "0000000000000011"),
            AccessoireMaison(nom: "A", piece: "Piece 2", noeudMatter: "0000000000000012"),
            AccessoireMaison(nom: "A", piece: "Piece 1", noeudMatter: "0000000000000013"),
        ]))
        #expect(tri.orphelins(appareils: [], fabriqueApple: Self.fabrique).map { "\($0.nom)/\($0.piece ?? "")" }
                == ["A/Piece 1", "A/Piece 2", "B/Piece 2"])
    }

    /// Seules comptent les associations d'appareils presents ou disparus : celle d'un appareil que plus personne ne
    /// connait ne prend pas l'accessoire, qui redevient propose.
    @Test func orphelinsIgnoreLesAssociationsDAppareilsInconnus() throws {
        let i = Self.instantane()
        var n = ResolveurNoms(maison: Self.maison())
        let f = n.fabriqueApple(appareils: i.appareils)
        n.associations["AAAA0000000000FF"] = "00000000000000AA"
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: f).map(\.nom) == ["Detecteur 2", "Detecteur 3"],
                "l'appareil associe n'existe plus : Detecteur 2 est de nouveau propose")
        n.associations[Self.muet] = "00000000000000BB"
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: f).map(\.nom) == ["Detecteur 2"],
                "un appareil present prend son accessoire")
        // Un appareil disparu (passe en `appareils`) le prend aussi.
        var b = Banc()
        b.appareil("AAAA0000000000FF", noeud: 0xEE, adresses: ["fd00:aaaa:bbbb::ff"])
        let disparu = try #require(Instantane(annonces: b.annonces).appareil("AAAA0000000000FF"))
        #expect(n.orphelins(appareils: i.appareils + [disparu], fabriqueApple: f).map(\.nom) == [])
    }

    /// Un pont et un accessoire qu'il porte partagent un noeud : le menu n'en propose qu'un, celui dont l'appareil
    /// prendrait le nom (`accessoire(noeud:)` : le pont, sinon le premier par nom) ; ce qui est affiche est ce qu'on
    /// obtient en l'associant.
    @Test func orphelinsUnSeulParNoeud() throws {
        let i = Self.instantane()
        let muet = try Self.appareil(Self.muet)
        var n = ResolveurNoms(maison: NomsMaison(date: Self.date, accessoires: [
            AccessoireMaison(nom: "A prise", noeudMatter: "00000000000000AA"),
            AccessoireMaison(nom: "Z pont", noeudMatter: "00000000000000aa", pont: true),
            AccessoireMaison(nom: "Capteur 2", noeudMatter: "00000000000000BB"),
            AccessoireMaison(nom: "Capteur 1", noeudMatter: "00000000000000BB"),
        ]))
        let f = n.fabriqueApple(appareils: i.appareils)
        #expect(f == nil, "aucun noeud de Maison n'est annonce")
        let sur = n.orphelins(appareils: i.appareils, fabriqueApple: Self.fabrique)
        #expect(sur.map(\.nom) == ["Capteur 1", "Z pont"], "le pont l'emporte, sinon le premier par nom")
        for choisi in sur {
            n.associations[Self.muet] = choisi.noeudMatter ?? ""
            #expect(n.nom(appareil: muet, fabriqueApple: Self.fabrique) == choisi.nom, "le nom propose est obtenu")
        }
    }

    /// Sans fabrique d'Apple connue (Maison lue, aucun recoupement avec les noeuds annonces), aucun annonceur n'est
    /// connu : tous les accessoires sembleraient orphelins, on n'en propose aucun.
    @Test func orphelinsSansFabriqueConnue() throws {
        let i = Self.instantane()
        let n = ResolveurNoms(maison: Self.maison())
        #expect(n.orphelins(appareils: i.appareils, fabriqueApple: nil).isEmpty)
        #expect(n.orphelins(appareils: [], fabriqueApple: nil).isEmpty)
        #expect(!n.orphelins(appareils: i.appareils, fabriqueApple: Self.fabrique).isEmpty)
    }

    /// Priorite : le surnom passe avant l'association ; l'association passe avant le nom HomeKit et l'identifiant ; et
    /// si l'appareil retrouve son noeud (l'accessoire redevient annonce par lui), le noeud l'emporte.
    @Test func priorite() throws {
        let i = Self.instantane()
        let muet = try Self.appareil(Self.muet)
        var n = ResolveurNoms(maison: Self.maison(), associations: [Self.muet: "00000000000000AA"])
        let f = n.fabriqueApple(appareils: i.appareils)
        #expect(n.nom(appareil: muet, fabriqueApple: f) == "Detecteur 2")
        n.surnoms[Self.muet] = "Surnom 1"
        #expect(n.nom(appareil: muet, fabriqueApple: f) == "Surnom 1", "le surnom d'abord")
        n.surnoms[Self.muet] = nil
        // Maison exporte maintenant le noeud de l'appareil (0x99) : le noeud l'emporte.
        n.maison?.accessoires.append(AccessoireMaison(nom: "Detecteur 7", piece: "Piece 4",
                                                      noeudMatter: "0000000000000099"))
        #expect(n.nom(appareil: muet, fabriqueApple: f) == "Detecteur 7")
        #expect(n.accessoire(de: muet, fabriqueApple: f)?.piece == "Piece 4")
        #expect(!n.associeALaMain(muet, fabriqueApple: f), "l'association reste, sans effet")
        #expect(n.associations[Self.muet] == "00000000000000AA", "gardee : elle revient si le noeud se perd de nouveau")
        n.maison?.accessoires.removeLast()
        #expect(n.nom(appareil: muet, fabriqueApple: f) == "Detecteur 2")
    }
}
