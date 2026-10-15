import Foundation
import MaillageCoeur
import ProtocoleThread
import ProtocoleZigbee
import AppKit
import simd
import SwiftUI
import Testing
@testable import MaillageIoT

/// Etape 3b, tache 5 : la barre du haut dit la maison et porte les interrupteurs de vue « Thread » / « Zigbee ». Masquer un
/// protocole n'agit qu'au dessin : la scene calculee, sa disposition et la place de chaque noeud restent ceux des protocoles
/// actifs (les deux rejeux exacts ne le voient pas), et rien du protocole masque ne reste (fiche, focus, isolement, ligne de
/// tournee, commandes).
@MainActor
@Suite("Interrupteurs de vue et masquage stable")
struct VueProtocolesTests {
    static let tous: Set<Protocole> = [.thread, .zigbee]

    /// Les deux reseaux, et la scene qu'en montre la vue pour chaque ensemble de protocoles montres.
    static func scene(_ s: Surveillance, montres: Set<Protocole> = VueProtocolesTests.tous) -> EntreeScene {
        EntreeScene(surveillance: s, places: PlacesGardees(), montres: montres)
    }

    // MARK: Masquage stable

    /// Masquer un protocole ne bouge rien : la scene, sa cle de disposition, les positions des pieces, celles des noeuds
    /// visibles et les ancres des pieces sont identiques, protocole montre ou masque ; seuls les disques du protocole masque
    /// disparaissent. Le moteur ne recalcule pas la disposition (meme cle), et la remise du protocole les rend a leur place.
    @Test func masquageStable() throws {
        let s = EntreeSceneTests.deuxReseaux()
        let tout = Self.scene(s), sansZigbee = Self.scene(s, montres: [.thread]), sansThread = Self.scene(s, montres: [.zigbee])
        #expect(tout.scene == sansZigbee.scene && tout.scene == sansThread.scene, "la scene calculee ne lit pas le masque")
        #expect(tout.cleDisposition == sansZigbee.cleDisposition && tout.cleDisposition == sansThread.cleDisposition)
        #expect(tout.graphe == sansZigbee.graphe && tout.libelles == sansZigbee.libelles)
        #expect(tout != sansZigbee, "mais la vue, elle, change : le moteur doit recevoir la scene")
        let m = MoteurPiecesTests.moteur(tout)
        let avant = Releve(m)
        try #require(!avant.disques.isEmpty)
        #expect(Set(avant.disques.map(\.protocole)) == Self.tous)
        for (masque, reste) in [(Protocole.zigbee, Protocole.thread), (.thread, .zigbee)] {
            m.recevoir(masque == .zigbee ? sansZigbee : sansThread)
            MoteurPiecesTests.dessiner(m)
            let apres = Releve(m)
            #expect(m.enCalcul == nil && m.cleCalculee == tout.cleDisposition, "aucune disposition recalculee")
            #expect(apres.positions == avant.positions && apres.rayons == avant.rayons, "les pieces ne bougent pas")
            #expect(apres.ancresPieces == avant.ancresPieces && apres.blocs == avant.blocs)
            #expect(apres.disques.allSatisfy { $0.protocole == reste }, "seul le protocole montre est dessine")
            #expect(Set(apres.disques) == Set(avant.disques.filter { $0.protocole == reste }),
                    "les noeuds visibles sont a la meme place")
            #expect(m.entree?.masques == [masque])
            let etiquettes = m.etiquettes.compactMap { l -> IdNoeud? in if case .noeud(let id) = l.genre { id } else { nil } }
            #expect(!etiquettes.isEmpty && etiquettes.allSatisfy { $0.protocole == reste }, "aucun nom du protocole masque")
            m.recevoir(tout)
            MoteurPiecesTests.dessiner(m)
            #expect(Releve(m) == avant, "le protocole remis revient a sa place, sans bouger")
        }
    }

    /// Les liens, les noms et la pastille du protocole masque ne se dessinent pas ; ceux de l'autre ne changent pas.
    @Test func lesLiensDuProtocoleMasqueNeSeDessinentPas() throws {
        let s = EntreeSceneTests.deuxReseaux()
        let m = MoteurPiecesTests.moteur(Self.scene(s, montres: [.thread]))
        let p = try #require(m.projetee)
        #expect((p.liensEnfants + p.liensRouteurs).allSatisfy { $0.protocole == .thread })
        #expect(!(p.liensEnfants + p.liensRouteurs).isEmpty)
        // Un noeud masque ne se survole ni ne se clique : la ou etait sa pastille, il n'y a plus de noeud de Zigbee.
        let place = try #require(Releve(MoteurPiecesTests.moteur(Self.scene(s))).centreEcran(of: .zigbee))
        #expect(m.noeudSous(place)?.protocole != .zigbee)
        // Les comptes des pieces sont ceux des noeuds visibles.
        let tout = MoteurPiecesTests.moteur(Self.scene(s))
        let visibles = m.textes.pieces.values.map(\.compte), entiers = tout.textes.pieces.values.map(\.compte)
        #expect(visibles != entiers)
    }

    /// Un instantane du dessin : positions des pieces, rayons, ancres, blocs, et les disques (noeud, centre, rayon).
    struct Releve: Equatable {
        struct Disque: Hashable {
            var noeud: IdNoeud
            var x: Double
            var y: Double
            var rayon: Double
            var protocole: Protocole { noeud.protocole }
        }

        var positions: [SIMD2<Double>]
        var rayons: [Double]
        var ancresPieces: [Int: CGRect]
        var blocs: Int
        var disques: [Disque]

        @MainActor
        init(_ m: MoteurPieces) {
            positions = m.positions
            rayons = m.geometrie.rayons
            let p = m.projetee
            ancresPieces = p?.ancresPieces ?? [:]
            blocs = p?.blocs.count ?? 0
            disques = (p?.disques ?? []).map { Disque(noeud: $0.noeud, x: Double($0.centre.x), y: Double($0.centre.y), rayon: $0.rayon) }
        }

        func centreEcran(of protocole: Protocole) -> CGPoint? {
            disques.first { $0.protocole == protocole }.map { CGPoint(x: $0.x, y: $0.y) }
        }
    }

    // MARK: Fiche, focus, isolement

    /// La fiche, le focus et l'isolement d'un noeud du protocole masque se ferment ; ceux de l'autre protocole restent.
    @Test func ficheFermeeAuMasquage() throws {
        let s = EntreeSceneTests.deuxReseaux()
        let tout = Self.scene(s), sansZigbee = Self.scene(s, montres: [.thread]), sansThread = Self.scene(s, montres: [.zigbee])
        let zigbee = try #require(tout.scene.noeuds.first { $0.id.protocole == .zigbee && $0.chef }?.id, "le pont")
        let thread = try #require(tout.scene.noeuds.first { $0.id.protocole == .thread && $0.chef }?.id, "le chef Thread")
        let m = MoteurPiecesTests.moteur(tout)
        // Un noeud de Zigbee choisi : Zigbee masque, fiche et focus se ferment.
        m.selection = zigbee
        #expect(m.miseEnAvant != nil)
        m.recevoir(sansZigbee)
        #expect(m.selection == nil && m.miseEnAvant == nil, "la fiche et le focus d'un noeud masque se ferment")
        // Un noeud de Thread reste choisi quand Zigbee est masque.
        m.recevoir(tout)
        m.selection = thread
        m.recevoir(sansZigbee)
        #expect(m.selection == thread && m.miseEnAvant != nil, "l'autre protocole garde sa fiche")
        // L'inverse : Thread masque.
        m.recevoir(sansThread)
        #expect(m.selection == nil && m.miseEnAvant == nil)
        // Une piece isolee dont tous les noeuds sont masques est quittee ; une piece qui garde des noeuds visibles reste isolee.
        m.recevoir(tout)
        let rien = Self.scene(s, montres: [])
        m.poserIsolement(try #require(tout.scene.pieces.firstIndex { !$0.noeuds.isEmpty }))
        #expect(m.estIsolee)
        m.recevoir(rien)
        #expect(!m.estIsolee && m.isolement == .maison, "la piece vide de noeuds visibles est quittee")
        m.recevoir(tout)
        let mixte = try #require(tout.scene.pieces.firstIndex { p in Set(p.noeuds.map(\.protocole)) == Self.tous },
                                 "une piece des deux protocoles")
        m.poserIsolement(mixte)
        m.recevoir(sansZigbee)
        #expect(m.estIsolee, "une piece qui garde des noeuds visibles reste isolee")
        m.recevoir(sansThread)
        #expect(m.estIsolee, "de meme, Thread masque")
    }

    // MARK: Interrupteurs

    /// Les preferences `vue.thread` et `vue.zigbee` sont communes (sans prefixe de module), vraies par defaut.
    @Test func preferencesDeVue() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        #expect(InterrupteursVue.cle(.thread) == "vue.thread" && InterrupteursVue.cle(.zigbee) == "vue.zigbee")
        #expect(InterrupteursVue.preferes(dans: p) == Self.tous, "vrai par defaut")
        p.set(false, forKey: "vue.zigbee")
        #expect(InterrupteursVue.preferes(dans: p) == [.thread])
        p.set("peut-etre", forKey: "vue.thread")
        #expect(InterrupteursVue.preferes(dans: p) == [.thread], "une valeur qui n'est pas un booleen : le defaut")
    }

    /// Un protocole eteint dans les Reglages (`actif` faux) a son interrupteur grise, et compte comme masque quelle que soit
    /// la preference ; l'autre n'en est pas touche.
    @Test func interrupteurGriseProtocoleEteint() {
        let s = EntreeSceneTests.deuxReseaux()
        #expect(s.protocolesActifs == Self.tous)
        s.zigbee.actif = false
        #expect(s.protocolesActifs == [.thread])
        let preferes = Self.tous
        let zigbee = InterrupteursVue.etat(.zigbee, preferes: preferes, actifs: s.protocolesActifs)
        let thread = InterrupteursVue.etat(.thread, preferes: preferes, actifs: s.protocolesActifs)
        #expect(zigbee == InterrupteursVue.Etat(allume: false, grise: true), "eteint : grise, et jamais allume")
        #expect(thread == InterrupteursVue.Etat(allume: true, grise: false))
        #expect(InterrupteursVue.etat(.thread, preferes: [.zigbee], actifs: Self.tous) == .init(allume: false, grise: false),
                "masque par Djoko : eteint mais pas grise")
        #expect(InterrupteursVue.montres(preferes: preferes, actifs: s.protocolesActifs) == [.thread])
        // La scene : un protocole eteint n'est pas de la scene, quel que soit le parametre des montres.
        let e = Self.scene(s)
        #expect(e.protocoles == [.thread] && e.montres == [.thread] && e.masques == [.zigbee])
        s.zigbee.actif = true
        s.thread.actif = false
        let z = Self.scene(s)
        #expect(z.protocoles == [.zigbee] && z.montres == [.zigbee] && z.masques == [.thread])
        #expect(InterrupteursVue.etat(.thread, preferes: preferes, actifs: s.protocolesActifs).grise)
    }

    /// « Appareils IP · N » n'est dans la barre que si Thread est montre ; la ligne de tournee d'un protocole masque et ses
    /// commandes (liens, voisins) non plus.
    @Test func appareilsIPSelonThread() {
        let tous = ContenuHaut(protocoles: Self.tous, montres: Self.tous)
        let sansThread = ContenuHaut(protocoles: Self.tous, montres: [.zigbee])
        let sansZigbee = ContenuHaut(protocoles: Self.tous, montres: [.thread])
        let rien = ContenuHaut(protocoles: Self.tous, montres: [])
        #expect(tous.appareilsIP && sansZigbee.appareilsIP && !sansThread.appareilsIP && !rien.appareilsIP)
        #expect(tous.tournees == [.thread, .zigbee], "Thread d'abord")
        #expect(sansThread.tournees == [.zigbee] && sansZigbee.tournees == [.thread] && rien.tournees.isEmpty,
                "la ligne de tournee d'un protocole masque est cachee")
        #expect(tous.liens && sansThread.liens && !sansZigbee.liens && !rien.liens, "les liens sont ceux de Zigbee")
        // Sans noeud (rien a montrer encore) : la ligne de Thread, comme avant ; masquee, elle ne l'est plus.
        #expect(ContenuHaut(protocoles: [], montres: Self.tous).tournees == [.thread])
        #expect(ContenuHaut(protocoles: [], montres: [.zigbee]).tournees.isEmpty)
    }

    /// La barre d'une scene de Thread seul, de Zigbee seul ou des deux est la meme : un seul morceau, sans variante pour Zigbee.
    @Test func uneSeuleBarre() {
        for p: Set<Protocole> in [[], [.thread], [.zigbee], Self.tous] {
            let c = ContenuHaut(protocoles: p, montres: p)
            #expect(c.sansPiecesZigbee == (p == [.zigbee]), "le bandeau d'une maison sans pieces suit la scene")
        }
        // Les commandes des liens se lisent sur la scene du moteur et les protocoles montres.
        let reunie = EntreeSceneTests.deuxReseaux()
        let m = MoteurPiecesTests.moteur(Self.scene(reunie))
        #expect(CommandesVue.montreLiens(scene: m.scene, montres: Self.tous))
        #expect(!CommandesVue.montreLiens(scene: m.scene, montres: [.thread]), "Zigbee masque : ni liens ni voisins")
        #expect(!CommandesVue.montreLiens(scene: nil, montres: Self.tous))
    }

    // MARK: Nom de la maison et menu des reseaux

    /// La capsule de gauche porte le nom de la maison, tel que Maison le donne (son releve, sinon celui du pont qui l'a
    /// recu) ; « Maison » quand il est inconnu ou vide.
    @Test func nomDeLaMaison() {
        let demo = EntreeSceneTests.deuxReseaux()
        #expect(MenuReseaux.nomDeLaMaison(demo) == NomsDemo.domicile, "le releve de la demo")
        let direct = Surveillance(mode: .direct, dossier: nil)
        #expect(MenuReseaux.nomDeLaMaison(direct) == String(localized: "Maison"), "inconnu : « Maison »")
        func releve(_ domicile: String?) -> NomsMaison { NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), domicile: domicile) }
        direct.thread.noms.maison = releve("Maison inventee")
        #expect(MenuReseaux.nomDeLaMaison(direct) == "Maison inventee")
        direct.thread.noms.maison = releve("  ")
        #expect(MenuReseaux.nomDeLaMaison(direct) == String(localized: "Maison"), "un nom vide ou blanc : « Maison »")
        // Zigbee seul recoit le releve de Maison : il le dit aussi.
        let zigbee = Surveillance(mode: .direct, dossier: nil)
        zigbee.zigbee.recevoirReleveMaison(releve("Maison du pont"))
        #expect(MenuReseaux.nomDeLaMaison(zigbee) == "Maison du pont")
        // Le nom du reseau Thread n'est plus le libelle : « Reseau demo » n'est pas la maison.
        #expect(MenuReseaux.nomDeLaMaison(demo) != demo.thread.reseau?.nom)
    }

    /// Thread et Zigbee eteints : le menu du nom de la maison n'a aucune section ; il le dit (une ligne grisee) au lieu de
    /// s'ouvrir vide. Un seul protocole allume suffit a le remplir.
    @Test func menuDesReseauxSansProtocole() {
        let s = EntreeSceneTests.deuxReseaux()
        #expect(!MenuReseaux.contenu(s, pont: nil).sansProtocole)
        s.zigbee.actif = false
        #expect(!MenuReseaux.contenu(s, pont: nil).sansProtocole, "Thread seul : une section")
        s.thread.actif = false
        #expect(MenuReseaux.contenu(s, pont: nil).sansProtocole, "aucun protocole actif")
        s.zigbee.actif = true
        #expect(!MenuReseaux.contenu(s, pont: nil).sansProtocole, "Zigbee seul : une section")
    }

    /// Le menu du nom de la maison liste les reseaux par protocole : Thread (ses reseaux, partitions comprises, et le choisi),
    /// puis Zigbee (le pont : son nom, son modele, son etat). Un protocole eteint n'a pas de section.
    @Test func contenuDuMenuDesReseaux() throws {
        let s = EntreeSceneTests.deuxReseaux()
        let pont = NomsPont(capture: CapturesPieces.pontDeCapture, noms: NomsDemo.maisonPont)
        let menu = MenuReseaux.contenu(s, pont: pont)
        let reseaux = try #require(s.thread.instantane?.reseaux)
        let thread = try #require(menu.thread)
        #expect(thread.map(\.id) == reseaux.map(\.id), "tous les reseaux Thread vus")
        #expect(thread.filter(\.choisi).map(\.id) == [try #require(s.thread.reseau?.id)], "le reseau affiche est coche")
        for (r, t) in zip(reseaux, thread) {
            #expect(t.titre.hasPrefix(r.nom))
            #expect(r.estScinde == t.titre.contains("\(r.partitions.count)"), "les partitions d'un reseau scinde sont dites")
        }
        let z = try #require(menu.zigbee)
        #expect(z.titre.contains(try #require(CapturesPieces.pontDeCapture.modele)), "le modele du pont")
        // La demo n'a pas de pont : l'etat le dit ; en mode direct, l'etat du pont.
        #expect(s.mode == .demo && z.etat == MenuReseaux.texteEtatPont(.lie, demo: true))
        let direct = Surveillance(mode: .direct, dossier: nil)
        #expect(MenuReseaux.contenu(direct, pont: pont).zigbee?.etat == MenuReseaux.texteEtatPont(.lie, demo: false))
        #expect(MenuReseaux.contenu(direct, pont: nil).zigbee?.etat == MenuReseaux.texteEtatPont(.introuvable, demo: false))
        #expect(MenuReseaux.contenu(direct, pont: nil).zigbee?.titre == String(localized: "Pont Hue"), "sans modele : le nom seul")
        // Un protocole eteint n'a pas de section.
        s.zigbee.actif = false
        #expect(MenuReseaux.contenu(s, pont: pont).zigbee == nil && MenuReseaux.contenu(s, pont: pont).thread != nil)
        s.zigbee.actif = true
        s.thread.actif = false
        #expect(MenuReseaux.contenu(s, pont: pont).thread == nil && MenuReseaux.contenu(s, pont: pont).zigbee != nil)
        // Thread sans reseau : une section vide, que le menu dit « Aucun reseau Thread ».
        let vide = Surveillance(mode: .direct, dossier: nil)
        #expect(MenuReseaux.contenu(vide, pont: nil).thread == [])
        // Les etats du pont, dits un a un (le mode demo les remplace).
        let etats: [NomsPont.Etat] = [.introuvable, .trouve(ip: "192.0.2.10", identifiant: "C0FFEEFFFE012345"), .aLier,
                                      .liaisonEnCours(reste: 30), .lie, .erreur("x")]
        let textes = etats.map { MenuReseaux.texteEtatPont($0, demo: false) }
        #expect(Set(textes).count >= 5 && textes.allSatisfy { !$0.isEmpty })
        #expect(MenuReseaux.texteEtatPont(.lie, demo: true) == MenuReseaux.texteEtatPont(.introuvable, demo: true))
    }

    // MARK: Tout masque

    /// Tout masque, la vue le dit en une ligne ; rien d'autre n'est a dire quand un protocole au moins est montre.
    @Test func ecranToutMasque() {
        let s = EntreeSceneTests.deuxReseaux()
        let rien = Self.scene(s, montres: []), thread = Self.scene(s, montres: [.thread])
        #expect(rien.toutMasque && !thread.toutMasque)
        #expect(rien.visibles.isEmpty && thread.visibles == [.thread])
        #expect(MessageMasque.texte(protocoles: rien.protocoles) == String(localized: "Thread et Zigbee sont masqués"))
        #expect(MessageMasque.texte(protocoles: [.thread]) == String(localized: "Thread est masqué"))
        #expect(MessageMasque.texte(protocoles: [.zigbee]) == String(localized: "Zigbee est masqué"))
        #expect(MessageMasque.texte(protocoles: []) == nil)
        // Zigbee eteint, Thread masque : la scene n'a que Thread, et c'est lui que le message nomme.
        s.zigbee.actif = false
        let seul = Self.scene(s, montres: [])
        #expect(seul.toutMasque && MessageMasque.texte(protocoles: seul.protocoles) == String(localized: "Thread est masqué"))
        // Sans noeud (aucun reseau) : pas de scene a masquer.
        let vide = EntreeScene(surveillance: Surveillance(mode: .direct, dossier: nil), reseau: nil, places: PlacesGardees(),
                               montres: [])
        #expect(!vide.toutMasque)
    }

    /// La legende decrit la scene calculee, pas le dessin : masquer un protocole ne change pas sa hauteur, donc pas la marge du
    /// bas ni le cadrage de la vue (le masquage est stable).
    @Test func laLegendeNeBougePasAuMasquage() {
        let s = EntreeSceneTests.deuxReseaux()
        func lecture(_ montres: Set<Protocole>) -> LegendePieces.Lecture {
            LegendePieces.Lecture(Self.scene(s, montres: montres), ailleurs: false)
        }
        let entrees = { (m: Set<Protocole>) in LegendePieces.rubriques(lecture(m)).map { [$0.groupe.titre] + $0.entrees.map { "\($0)" } } }
        #expect(entrees([.thread]) == entrees(Self.tous) && entrees([]) == entrees(Self.tous))
        #expect(LegendePieces.montreLesProtocoles(lecture([.thread])))
    }

    /// Les deux capsules du haut tiennent dans la plus petite fenetre (`FenetrePieces.tailleMinimale`) avec les deux protocoles,
    /// en 3D (« Rotation lente » s'ajoute a celle de droite), un nom de maison tres long, et un reseau Thread scinde : la bande
    /// entre elles garde de quoi deplacer la fenetre, et aucune capsule ne passe sur l'autre.
    @Test func capsulesDansLaPlusPetiteFenetre() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let s = EntreeSceneTests.deuxReseaux()
        s.thread.noms.maison?.domicile = String(repeating: "W", count: 60)
        let sonde = SondeMaillageThread(preferences: p, actif: false)
        let moteur = MoteurPiecesTests.moteur(Self.scene(s))
        moteur.poserBascule(1)
        func hote(_ vue: some View) -> NSHostingView<AnyView> {
            NSHostingView(rootView: AnyView(vue.environment(s).environment(sonde).environment(NomsPasseur())))
        }
        let gauche = hote(BarreOutils().capsuleDeVerre()).fittingSize.width
        let droite = hote(CommandesVue(moteur: moteur, troisD: .constant(true)).capsuleDeVerre()).fittingSize.width
        let largeur = FenetrePieces.tailleMinimale.width
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: largeur, height: 200),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                               defer: false)
        fenetre.isReleasedWhenClosed = false
        defer { fenetre.contentView = nil }
        let haut = hote(HautPieces(moteur: moteur, troisD: .constant(true), protocoles: Self.tous)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        fenetre.contentView = haut
        FenetrePiecesTests.sansBarreDeTitre(fenetre)
        haut.layoutSubtreeIfNeeded()
        fenetre.layoutIfNeeded()
        let bande = try #require(FenetrePiecesTests.sousVue(BandeFenetre.Vue.self, dans: haut), "la bande")
        let cadre = bande.convert(bande.bounds, to: haut)
        let cas = "fenetre de \(Int(largeur)) pt, capsules de \(gauche) et \(droite) pt"
        #expect(abs(cadre.minX - (CadreFeux.defaut.droite + HautPieces.ecartFeux + gauche)) < 1, "\(cas) : la bande suit la capsule de gauche")
        #expect(abs(cadre.maxX - (largeur - HautPieces.bordDroit - droite)) < 1, "\(cas) : la bande finit a la capsule de droite")
        #expect(cadre.width >= 24, "\(cas) : la bande garde de quoi deplacer la fenetre (\(cadre.width) pt)")
        // Le nom d'une maison tres longue est coupe : la capsule de gauche reste bornee.
        #expect(gauche <= 490, "la capsule de gauche : \(gauche) pt")
    }
}
