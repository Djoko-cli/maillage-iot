import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

/// Piece proposee a un routeur de bordure Thread (HomePod, Apple TV) d'apres son nom AirPlay : rattachement par nom d'hote,
/// piece de Maison contenue dans le nom. Noms, hotes et pieces inventes.
@MainActor
@Suite("AirPlay : piece proposee pour les routeurs de bordure")
struct PieceAirPlayTests {
    typealias Bordure = (id: IdNoeud, hote: String)
    static let pieces = ["Salon", "Cuisine", "Chambre", "Salle de jeux", "Séjour"]

    /// TXT brut : chaque chaine precedee de sa longueur.
    static func txt(_ chaines: String...) -> Data {
        Data(chaines.flatMap { [UInt8($0.utf8.count)] + Array($0.utf8) })
    }
    static func id(_ instance: String) -> IdNoeud { IdNoeud(.thread, instance) }
    static func service(_ nom: String, hote: String, modele: String? = nil) -> ServiceAirPlay {
        ServiceAirPlay(nom: nom, hote: hote, modele: modele)
    }
    static func propositions(_ airplay: [ServiceAirPlay], _ bordures: [Bordure], pieces: [String] = pieces,
                             connues: [IdNoeud: String] = [:]) -> [IdNoeud: Proposition] {
        PieceAirPlay.propositions(airplay: airplay, bordures: bordures, piecesMaison: pieces, piecesConnues: connues)
    }

    // MARK: Rattachement par nom d'hote

    @Test func rattacheParLeNomDHote() {
        let p = Self.propositions([Self.service("HomePod Salon", hote: "Test-Hote-1.local")],
                                  [(Self.id("Routeur A"), "Test-Hote-1.local")])
        #expect(p == [Self.id("Routeur A"): Proposition(piece: "Salon", nomAirPlay: "HomePod Salon")])
    }

    @Test func hoteSansCasseNiPointFinal() {
        let airplay = [Self.service("HomePod Salon", hote: "TEST-HOTE-1.LOCAL.")]
        #expect(Self.propositions(airplay, [(Self.id("A"), "test-hote-1.local")]).keys.contains(Self.id("A")))
        let autre = [Self.service("HomePod Salon", hote: "test-hote-1.local")]
        #expect(Self.propositions(autre, [(Self.id("A"), "Test-Hote-1.local.")]).keys.contains(Self.id("A")))
    }

    @Test func sansHoteCommunAucuneProposition() {
        // Meme nom que l'instance du routeur, mais aucun hote commun : jamais de rattachement par le nom affiche.
        let p = Self.propositions([Self.service("HomePod Salon", hote: "Test-Hote-2.local")],
                                  [(Self.id("HomePod Salon"), "Test-Hote-1.local")])
        #expect(p.isEmpty)
        #expect(Self.propositions([], [(Self.id("A"), "Test-Hote-1.local")]).isEmpty)
        #expect(Self.propositions([Self.service("Salon", hote: "Test-Hote-1.local")], []).isEmpty)
    }

    @Test func deuxRouteursChacunSonService() {
        let airplay = [Self.service("Salon", hote: "hote-1.local"), Self.service("Cuisine", hote: "hote-2.local")]
        let p = Self.propositions(airplay, [(Self.id("A"), "hote-1.local"), (Self.id("B"), "hote-2.local")])
        #expect(p[Self.id("A")]?.piece == "Salon" && p[Self.id("B")]?.piece == "Cuisine")
    }

    // MARK: Piece contenue dans le nom

    @Test func motEntierSeulement() {
        func piece(_ nom: String) -> String? {
            Self.propositions([Self.service(nom, hote: "h.local")], [(Self.id("A"), "h.local")])[Self.id("A")]?.piece
        }
        #expect(piece("Salon") == "Salon")
        #expect(piece("Apple TV du salon") == "Salon")
        #expect(piece("Salonnière") == nil, "Salon n'est pas un mot de Salonnière")
        #expect(piece("Mon Salons") == nil)
        #expect(piece("HomePod") == nil, "aucune piece dans le nom : aucune proposition")
        #expect(piece("") == nil)
    }

    @Test func accentsEtCasse() {
        func piece(_ nom: String, _ pieces: [String]) -> String? {
            Self.propositions([Self.service(nom, hote: "h.local")], [(Self.id("A"), "h.local")],
                              pieces: pieces)[Self.id("A")]?.piece
        }
        #expect(piece("HOMEPOD SEJOUR", ["Séjour"]) == "Séjour", "la piece rendue est celle de Maison, avec son accent")
        #expect(piece("HomePod Séjour", ["Sejour"]) == "Sejour")
        #expect(piece("homepod cuisine", ["Cuisine"]) == "Cuisine")
    }

    @Test func laPlusLongueDeDeuxPieces() {
        let un = Self.propositions([Self.service("Apple TV Salle de jeux", hote: "h.local")], [(Self.id("A"), "h.local")],
                                   pieces: ["Salle", "Salle de jeux"])
        #expect(un[Self.id("A")]?.piece == "Salle de jeux")
        let deux = Self.propositions([Self.service("Salon Cuisine", hote: "h.local")], [(Self.id("A"), "h.local")])
        #expect(deux[Self.id("A")]?.piece == "Cuisine", "Cuisine (7 lettres) l'emporte sur Salon (5)")
    }

    @Test func egaliteDeLongueurSansProposition() {
        // « Salon » et « Bains » : 5 lettres chacun, tous deux dans le nom : douteux.
        let p = Self.propositions([Self.service("Bains Salon", hote: "h.local")], [(Self.id("A"), "h.local")],
                                  pieces: ["Salon", "Bains"])
        #expect(p.isEmpty)
    }

    @Test func sansPieceDeMaisonAucuneProposition() {
        let p = Self.propositions([Self.service("HomePod Salon", hote: "h.local")], [(Self.id("A"), "h.local")], pieces: [])
        #expect(p.isEmpty)
    }

    // MARK: Noeud deja place

    @Test func noeudDejaPlaceSansProposition() {
        let airplay = [Self.service("HomePod Salon", hote: "h1.local"), Self.service("HomePod Cuisine", hote: "h2.local")]
        let bordures = [(Self.id("A"), "h1.local"), (Self.id("B"), "h2.local")]
        let p = Self.propositions(airplay, bordures, connues: [Self.id("A"): "Chambre"])
        #expect(p[Self.id("A")] == nil, "A a deja une piece (Maison ou choix) : rien, meme differente")
        #expect(p[Self.id("B")]?.piece == "Cuisine")
        let vide = Self.propositions(airplay, bordures, connues: [Self.id("A"): ""])
        #expect(vide[Self.id("A")]?.piece == "Salon", "une piece vide n'est pas une piece")
    }

    // MARK: Hote partage

    @Test func hotePartageParDeuxServices() {
        let bordures = [(Self.id("A"), "h.local")]
        let accord = Self.propositions([Self.service("HomePod Salon", hote: "h.local"), Self.service("Salon TV", hote: "H.local.")],
                                       bordures)
        #expect(accord[Self.id("A")]?.piece == "Salon", "deux services, meme piece")
        let desaccord = Self.propositions([Self.service("HomePod Salon", hote: "h.local"), Self.service("Cuisine", hote: "h.local")],
                                          bordures)
        #expect(desaccord.isEmpty, "deux services de pieces differentes sur un hote : douteux, aucune proposition")
        let unSeul = Self.propositions([Self.service("HomePod Salon", hote: "h.local"), Self.service("Apple TV", hote: "h.local")],
                                       bordures)
        #expect(unSeul[Self.id("A")]?.piece == "Salon", "l'autre nom ne dit rien : la piece reste")
    }

    @Test func hotePartageParDeuxRouteurs() {
        let p = Self.propositions([Self.service("HomePod Salon", hote: "h.local")],
                                  [(Self.id("A"), "h.local"), (Self.id("B"), "H.LOCAL.")])
        #expect(p.isEmpty, "un hote pour deux routeurs : on ne sait pas lequel, aucune proposition")
    }

    // MARK: Du recenseur au modele

    @Test func serviceAirPlayDuReleve() {
        let txt = Self.txt("model=Test1,1", "pk=abc")
        let releve = Annonces(date: Date(timeIntervalSince1970: 1_790_000_000),
                              routeurs: [AnnonceService(instance: "Routeur A", hote: "h1.local", port: 49153),
                                         AnnonceService(instance: "Routeur sans hote")],
                              airplay: [AnnonceService(instance: "HomePod Salon", hote: "h1.local", port: 7000,
                                                       txt: ChampsTXT(brut: txt)),
                                        AnnonceService(instance: "Sans hote")])
        let services = PieceAirPlay.services(de: releve)
        #expect(services == [ServiceAirPlay(nom: "HomePod Salon", hote: "h1.local", modele: "Test1,1")],
                "un service sans hote ne compte pas ; le modele vient du TXT `model`")
        let bordures = PieceAirPlay.bordures(de: releve)
        #expect(bordures.map(\.id) == [Self.id("Routeur A")] && bordures.map(\.hote) == ["h1.local"])
        let p = PieceAirPlay.propositions(airplay: services, bordures: bordures, piecesMaison: Self.pieces, piecesConnues: [:])
        #expect(p[Self.id("Routeur A")] == Proposition(piece: "Salon", nomAirPlay: "HomePod Salon"))
    }

    @Test func modeleAbsentDuTXT() {
        let releve = Annonces(date: Date(timeIntervalSince1970: 0), airplay: [AnnonceService(instance: "X", hote: "h.local")])
        #expect(PieceAirPlay.services(de: releve) == [ServiceAirPlay(nom: "X", hote: "h.local", modele: nil)])
    }

    // MARK: Ecoute du recenseur

    @Test func lEcouteAirPlayEstDansLesTypes() {
        #expect(Recenseur.types.contains("_airplay._tcp"))
        let fab = FabriqueBonjour()
        let r = Recenseur(fabrique: fab.fabriquer, avance: .seconds(100))
        r.demarrer()
        #expect(fab.types.contains("_airplay._tcp"), "le recenseur demande une ecoute AirPlay")
        r.arreter()
    }

    @Test func serviceAirPlayAssemble() {
        typealias Listee = Recenseur.InstanceListee
        let type = "_airplay._tcp"
        let txt = Self.txt("model=Test1,1")
        let vues = [Listee(type: type, instance: "HomePod Salon", txt: txt),
                    Listee(type: type, instance: "Pas resolu", txt: Data()),
                    Listee(type: "_meshcop._udp", instance: "Routeur A", txt: Data())]
        let cibles = [Recenseur.cle(type, "HomePod Salon"): ResolveurDNSSD.Cible(hote: "h1.local", port: 7000, txt: Data()),
                      Recenseur.cle("_meshcop._udp", "Routeur A"): ResolveurDNSSD.Cible(hote: "h1.local", port: 49153, txt: Data())]
        let a = Recenseur.assembler(vues: vues, cibles: cibles, adresses: [:], routes: [], prefixesLocaux: [],
                                    date: Date(timeIntervalSince1970: 0))
        #expect(a.airplay == [AnnonceService(instance: "HomePod Salon", hote: "h1.local", port: 7000, txt: ChampsTXT(brut: txt))])
        #expect(a.routeurs.map(\.instance) == ["Routeur A"])
    }

    @Test func lesHotesAirPlayNeSontPasResolusEnAdresses() {
        let cibles = [Recenseur.cle("_airplay._tcp", "TV du salon"): ResolveurDNSSD.Cible(hote: "tele.local", port: 7000, txt: Data()),
                      Recenseur.cle("_airplay._tcp", "Salon"): ResolveurDNSSD.Cible(hote: "routeur.local", port: 7000, txt: Data()),
                      Recenseur.cle("_meshcop._udp", "Routeur"): ResolveurDNSSD.Cible(hote: "routeur.local", port: 49153, txt: Data())]
        #expect(Recenseur.hotesAResoudre(cibles) == ["routeur.local"],
                "les adresses ne sont cherchees que pour les hotes des autres types : aucune pour les appareils AirPlay seuls")
    }
}
