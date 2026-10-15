import Foundation
import MaillageCoeur
import ProtocoleThread
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Surveillance (modele de l'app)")
struct SurveillanceTests {
    static func demo() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        return s
    }

    /// Les appareils que la sonde doit resoudre (spec de la sonde tout-en-un, section 2.2) : ceux de l'instantane qui
    /// ont une adresse sur le prefixe OMR de leur partition, puis les disparus et les sans adresse, a leur derniere
    /// adresse ; aucun sans instantane.
    @Test func appareilsAResoudre() throws {
        let s = Self.demo()
        let i = try #require(s.thread.instantane)
        #expect(s.thread.appareilsAResoudre() == AppareilAResoudre.depuis(s.thread.suivi))
        #expect(Set(AppareilAResoudre.depuis(i)).isStrictSubset(of: Set(s.thread.appareilsAResoudre())))
        #expect(s.thread.appareilsAResoudre().contains { $0.id == "46F77B36E071F8D0" }, "un disparu de la demo")
        #expect(Surveillance(mode: .demo, dossier: nil).thread.appareilsAResoudre().isEmpty, "pas encore d'instantane")
    }

    @Test func modeDemo() throws {
        let s = Self.demo()
        #expect(s.thread.etatEcoute == .demo)
        #expect(s.evenements.count == 10)
        guard case .pertes(let pertes) = s.lignesJournal.first else {
            Issue.record("les pertes regroupees en tete du journal")
            return
        }
        #expect(pertes.count == 5)
        let resume = try #require(s.thread.resume)
        #expect(resume == ResumeReseauThread(nom: "MyHome1482620090", partitions: 2, routeurs: 6, appareils: 24, injoignables: 5))
        #expect(s.alerte, "reseau scinde")
        let r = try #require(s.thread.reseau)
        let affiches = s.thread.appareilsAffiches(pour: r)
        #expect(affiches.filter { $0.etat == .disparu }.map(\.nom).sorted()
                == ["Ampoule entrée", "Prise bureau", "Prise salon", "Thermo chambre"])
        #expect(affiches.first { $0.id == idt("46F77B36E071F8D0") }?.partition == "73586B68", "disparu a sa derniere place")
        #expect(affiches.first { $0.id == idt("56B1E064401F74EF") }?.piece == "Bureau")
        #expect(affiches.first { $0.id == idt("86E7BD1A75F28E6D") }?.batterie
                == BatterieMaison(niveau: 52, charge: .horsCharge, alerte: false), "batterie de Maison")
        #expect(affiches.filter { $0.batterie?.faible == true }.map(\.nom).sorted() == ["Eve Motion", "Fenêtre chambre"])
        #expect(s.evenements(de: idt("46F77B36E071F8D0")).first?.type == .appareilDisparu)
        #expect(s.thread.derniereScission(r)?.date == ScenarioPanne.date(4, 14))
        #expect(s.thread.appareil("46F77B36E071F8D0") != nil, "un disparu reste consultable")
        #expect(s.thread.routesLisibles == true)
    }

    @Test func journalEtSurnomsSurDisque() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        for a in ScenarioPanne.releves.prefix(12) { s.thread.integrer(a) }
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .routeurNouvelleAdresseLien, .prefixeNouveau,
                                             .prefixeRetire])
        let journal = JournalFichiers(dossier: dossier.appendingPathComponent("Journal"), politique: Surveillance.politiqueJournal)
        #expect(try journal.lire().count == 4)

        s.renommer(idt("56B1E064401F74EF"), en: "  Pont du bureau ")
        let halo = try #require(s.thread.appareil("56B1E064401F74EF"))
        #expect(s.thread.nom(halo) == "Pont du bureau")
        let relu = Surveillance(mode: .direct, dossier: dossier)
        #expect(relu.thread.noms.surnoms == ["56B1E064401F74EF": "Pont du bureau"])
        s.renommer(idt("56B1E064401F74EF"), en: "")
        #expect(s.thread.nom(halo) == "56B1E064401F74EF")

        let capture = try #require(try s.captureJSON())
        let lue = try CodageJSON.decodeur().decode(Annonces.self, from: capture)
        #expect(lue.date == ScenarioPanne.releves[11].date)
    }

    /// Deux reseaux Thread : un appareil devenu sans adresse ne va qu'au reseau
    /// de sa derniere partition, pas aussi au premier.
    @Test func deuxReseaux() throws {
        let debut = Releve20260928.annonces.date
        func annonces(_ t: TimeInterval, adresse: Bool) -> Annonces {
            var a = Releve20260928.annonces
            a.date = debut.addingTimeInterval(t)
            // Second reseau : un chef (autre xp, partition BBBBBBBB) qui publie son prefixe OMR.
            a.routeurs.append(AnnonceService(instance: "Voisin", hote: "Voisin.local", port: 49153, txt: ChampsTXT([
                "nn": Data("Voisin".utf8), "xp": Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
                "tv": Data("1.4.0".utf8), "pt": Data([0xBB, 0xBB, 0xBB, 0xBB]), "sb": Data([0, 0, 0x07, 0xB1]),
                "omr": Data([0x40, 0xFD, 0x99, 0, 0, 0, 0, 0, 0x01]),
            ])))
            a.adresses["Voisin.local"] = ["fe80::99"]
            a.matter.append(AnnonceService(instance: "30FC8F95E0E1A385-00000000000000BB", hote: "BBBB000000000001.local"))
            a.adresses["BBBB000000000001.local"] = adresse ? ["fd99:0:0:1::5"] : []
            return a
        }
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.integrer(annonces(0, adresse: true))
        s.thread.integrer(annonces(60, adresse: false))
        s.thread.integrer(annonces(180, adresse: false))
        let i = try #require(s.thread.instantane)
        #expect(i.reseaux.map(\.nom) == ["MyHome1482620090", "Voisin"])
        #expect(i.appareil("BBBB000000000001")?.etat == .sansAdresse)
        let maison = try #require(i.reseaux.first)
        let voisin = try #require(i.reseaux.last)
        #expect(!s.thread.appareilsAffiches(pour: maison).contains { $0.id == idt("BBBB000000000001") }, "pas dans le premier reseau")
        #expect(s.thread.appareilsAffiches(pour: voisin).map(\.id) == [idt("BBBB000000000001")])
        #expect(s.thread.appareilsAffiches(pour: voisin).first?.partition == "BBBBBBBB")
        #expect(s.thread.resume?.appareils == 24, "le premier reseau ne compte pas l'appareil du voisin")
    }

    @Test func veilleDuMac() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.integrer(ScenarioPanne.releves[0])
        s.noterVeille(debut: ScenarioPanne.date(3, 56), fin: ScenarioPanne.date(3, 55))
        #expect(s.evenements.last?.type == .veille)
        #expect(s.evenements.last?.periode?.duration == 0, "fin avant le debut : ramenee au debut")
    }

    /// Le Mac n'entend plus rien : aucun evenement, l'instantane reste, et la
    /// date du premier releve vide est gardee jusqu'au prochain releve non vide.
    @Test func reseauLocalMuet() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.thread.integrer(Annonces(date: ScenarioPanne.debut))
        #expect(s.thread.rienVuDepuis == nil, "pas encore d'instantane")
        s.thread.integrer(ScenarioPanne.releves[0])
        let evenements = s.evenements
        let date = try #require(s.thread.instantane?.date)
        let muet = ScenarioPanne.releves[0].date.addingTimeInterval(300)
        s.thread.integrer(Annonces(date: muet))
        #expect(s.evenements == evenements, "aucun evenement")
        #expect(s.thread.rienVuDepuis == muet)
        #expect(s.thread.instantane?.date == date)
        #expect(s.thread.dernierReleve?.date == muet, "le dernier releve recu, pour le diagnostic")
        s.thread.integrer(Annonces(date: muet.addingTimeInterval(60)))
        #expect(s.thread.rienVuDepuis == muet, "date du premier releve vide")
        var retour = ScenarioPanne.releves[0]
        retour.date = muet.addingTimeInterval(120)
        s.thread.integrer(retour)
        #expect(s.thread.rienVuDepuis == nil)
    }

    /// Scissions deja notifiees, gardees d'un lancement a l'autre (mode direct, lues
    /// au demarrage) : la scission trouvee de nouveau au lancement suivant n'est pas
    /// notifiee, mais reste au journal ; une reunion l'oublie. La demo n'ecrit rien,
    /// ni une surveillance pas demarree. Preferences jetables, jamais celles de l'app.
    @Test func scissionsNotifieesGardees() throws {
        // Domaine jetable, vide avant et apres ; toujours le meme : le systeme garde
        // son fichier (vide) dans le conteneur de l'app, un seul donc. L'ecriture est
        // attendue : l'app de test s'arrete aussitot apres.
        let domaine = "maillage-tests-scissions"
        let preferences = try #require(UserDefaults(suiteName: domaine))
        preferences.removePersistentDomain(forName: domaine)
        defer {
            preferences.removePersistentDomain(forName: domaine)
            preferences.synchronize()
        }
        let cle = SurveillanceThread.cleScissionsNotifiees
        let scinde = Releve20260928.annonces  // l'Aqara seul dans E2E79FFC
        var envoyees: [CategorieAlerte] = []
        /// Un lancement : les scissions notifiees sont lues comme au demarrage, sans ecouter le reseau.
        func lancement() -> Surveillance {
            let s = Surveillance(mode: .direct, dossier: nil, preferences: preferences)
            s.surAlertes = { envoyees += $0.map(\.categorie) }
            s.thread.chargerScissionsNotifiees()
            return s
        }

        Surveillance(mode: .demo, dossier: nil, preferences: preferences).demarrer()
        #expect(preferences.object(forKey: cle) == nil, "la demo (une scission a 04:14) n'ecrit rien")

        let premier = lancement()  // la coque vit tant que son modele verse au journal
        premier.thread.integrer(scinde)
        #expect(envoyees == [.scission], "premier lancement : constatee et notifiee")
        #expect(preferences.stringArray(forKey: cle) == ["4B36A2B7FEFB200B|73586B68,E2E79FFC"])

        envoyees = []
        let second = lancement()
        second.thread.integrer(scinde)
        #expect(envoyees.isEmpty, "toujours scinde au lancement suivant : pas de seconde notification")
        #expect(second.evenements.contains { $0.type == .reseauScinde && $0.constate }, "le journal la note toujours")

        // L'Aqara rejoint la partition Apple : reunion, la signature est oubliee.
        var reuni = scinde
        reuni.date = scinde.date.addingTimeInterval(60)
        let aqara = try #require(reuni.routeurs.firstIndex { $0.instance == "Aqara HubM100 #DFEB" })
        var txt = reuni.routeurs[aqara].txt.valeurs
        txt["pt"] = Data([0x73, 0x58, 0x6B, 0x68])
        reuni.routeurs[aqara].txt = ChampsTXT(txt)
        second.thread.integrer(reuni)
        #expect(second.evenements.last?.type == .reseauReuni)
        #expect(preferences.stringArray(forKey: cle) == [])

        let coque = Surveillance(mode: .direct, dossier: nil, preferences: preferences)
        coque.thread.integrer(scinde)
        #expect(preferences.stringArray(forKey: cle) == [], "pas demarree (comme les autres tests) : rien n'est ecrit")
    }

    // MARK: - Dernier maillage garde (repris de Maillage Zigbee, 12/10)

    /// Un maillage de la demo, recu a `date` (une seconde ronde : les dates du fichier gardent les millisecondes).
    static func maillageGarde(_ date: Date) throws -> Maillage {
        try #require(MaillageDemo.maillage(Instantane(annonces: Releve20260928.annonces), date: date))
    }

    static func dossierJetable() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
    }

    /// Le maillage recu est garde sur disque ; le lancement suivant le relit (comme au demarrage, sans ecouter le
    /// reseau), avec sa date de reception : la pastille « ancien » s'applique. Le maillage suivant remplace le fichier.
    @Test func dernierMaillageGarde() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernier-maillage.json")
        let s = Surveillance(mode: .direct, dossier: dossier)
        #expect(!FileManager.default.fileExists(atPath: fichier.path))
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        let m = try Self.maillageGarde(recu.addingTimeInterval(-60))
        s.thread.recevoir(m, a: recu)
        #expect(!s.thread.maillageRelu, "recu pendant que l'app tourne")
        #expect(FileManager.default.fileExists(atPath: fichier.path))

        let relu = Surveillance(mode: .direct, dossier: dossier)
        #expect(relu.thread.maillage == nil, "rien avant le demarrage")
        relu.thread.chargerMaillageGarde()
        #expect(relu.thread.maillage == m)
        #expect(relu.thread.maillageRecu == recu)
        #expect(relu.thread.maillageRelu)
        #expect(relu.thread.fraicheurMaillage(a: recu.addingTimeInterval(10 * 60)) == .ancien,
                "la pastille « ancien » s'applique")

        let suivant = try Self.maillageGarde(recu.addingTimeInterval(840))
        s.thread.recevoir(suivant, a: recu.addingTimeInterval(900))
        let apres = Surveillance(mode: .direct, dossier: dossier)
        apres.thread.chargerMaillageGarde()
        #expect(apres.thread.maillage == suivant && apres.thread.maillageRecu == recu.addingTimeInterval(900))
    }

    /// Un maillage relu au lancement est montre quel que soit son age (apres une nuit, c'est le cas vise), avec la
    /// pastille « ancien », jusqu'a la premiere tournee qui le remplace ; la peremption de 15 min reprend ensuite pour
    /// les maillages recus pendant que l'app tourne.
    @Test func maillageReluMontreQuelQueSoitSonAge() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        // Recu il y a une nuit, a l'heure du Mac : `maillageAffiche` compte l'age depuis maintenant.
        let recu = Date().addingTimeInterval(-10 * 3600)
        let m = try Self.maillageGarde(recu)
        let coque = Surveillance(mode: .direct, dossier: dossier)
        coque.thread.recevoir(m, a: recu)
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.integrer(Releve20260928.annonces)
        s.thread.chargerMaillageGarde()
        let matin = recu.addingTimeInterval(10 * 3600)
        #expect(s.thread.fraicheurMaillage(a: matin) == .ancien, "jamais perime tant qu'il est relu")
        #expect(SurveillanceThread.fraicheur(recu, maintenant: matin, tourneeEnCours: false) == .perime,
                "la regle normale, elle, ne change pas")
        let r = try #require(s.thread.reseau)
        #expect(s.thread.maillageRelu && s.thread.maillageAffiche(pour: r) != nil && s.thread.maillageAncien)
        // Pendant la premiere tournee, il reste « ancien » : la tournee ne le rend pas frais.
        s.thread.tourneeEnCours = true
        #expect(s.thread.fraicheurMaillage(a: matin) == .ancien && s.thread.maillageAffiche(pour: r) != nil)
        s.thread.tourneeEnCours = false
        // La premiere tournee le remplace : la regle des 15 min reprend.
        s.thread.recevoir(m, a: Date().addingTimeInterval(-20 * 60))
        #expect(!s.thread.maillageRelu && s.thread.maillageAffiche(pour: r) == nil, "recu il y a 20 min : perime")
        s.thread.recevoir(m, a: Date())
        #expect(s.thread.maillageAffiche(pour: r) != nil && !s.thread.maillageAncien)
    }

    /// Un fichier du dernier maillage illisible est ignore, sans erreur : comme s'il n'y en avait pas. Le maillage
    /// suivant le remplace.
    @Test func dernierMaillageIllisible() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        try FileManager.default.createDirectory(at: Surveillance.dossierThread(dossier), withIntermediateDirectories: true)
        try Data("{ pas du json".utf8).write(to: Surveillance.dossierThread(dossier).appendingPathComponent("dernier-maillage.json"))
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.thread.chargerMaillageGarde()
        #expect(s.thread.maillage == nil && s.thread.maillageRecu == nil && !s.thread.maillageRelu)

        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        let m = try Self.maillageGarde(recu)
        s.thread.recevoir(m, a: recu)
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.thread.chargerMaillageGarde()
        #expect(relu.thread.maillage == m)
    }

    /// Un fichier trafique ou abime, mais du JSON valide, est ignore lui aussi, sans arreter l'app : un identifiant de
    /// routeur hors de 0...62, deux routeurs de meme identifiant, une adresse IPv6 invalide.
    @Test func dernierMaillageIncoherent() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernier-maillage.json")
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        let coque = Surveillance(mode: .direct, dossier: dossier)
        coque.thread.recevoir(try Self.maillageGarde(recu), a: recu)
        let original = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fichier)) as? [String: Any])
        /// Le fichier, une fois le maillage retouche par `retouche`, relu au lancement.
        func relu(_ retouche: (inout [String: Any]) -> Void) throws -> Maillage? {
            var garde = original
            var m = try #require(garde["maillage"] as? [String: Any])
            retouche(&m)
            garde["maillage"] = m
            try JSONSerialization.data(withJSONObject: garde).write(to: fichier)
            let s = Surveillance(mode: .direct, dossier: dossier)
            s.thread.chargerMaillageGarde()
            return s.thread.maillage
        }
        #expect(try relu { _ in } != nil, "le fichier intact est relu")
        #expect(try relu { m in
            var routeurs = m["routeurs"] as? [[String: Any]] ?? []
            routeurs[0]["id"] = 99
            m["routeurs"] = routeurs
        } == nil, "identifiant hors de 0...62")
        #expect(try relu { m in
            var routeurs = m["routeurs"] as? [[String: Any]] ?? []
            routeurs[1]["id"] = routeurs[0]["id"]
            m["routeurs"] = routeurs
        } == nil, "deux routeurs de meme identifiant")
        #expect(try relu { m in
            var enfants = m["enfants"] as? [[String: Any]] ?? []
            enfants[0]["adresses"] = ["pas une adresse"]
            m["enfants"] = enfants
        } == nil, "adresse invalide")
    }

    /// Une sonde oubliee emporte son maillage garde : le lancement suivant n'a rien a relire.
    @Test func sondeOublieeEffaceLeMaillageGarde() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = Surveillance.dossierThread(dossier).appendingPathComponent("dernier-maillage.json")
        let s = Surveillance(mode: .direct, dossier: dossier)
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        s.thread.recevoir(try Self.maillageGarde(recu), a: recu)
        #expect(FileManager.default.fileExists(atPath: fichier.path))
        s.thread.oublierMaillage()
        #expect(!FileManager.default.fileExists(atPath: fichier.path))
        #expect(s.thread.maillage == nil && !s.thread.maillageRelu)
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.thread.chargerMaillageGarde()
        #expect(relu.thread.maillage == nil)
    }

    /// La demo ne garde aucun maillage, meme avec un dossier.
    @Test func demoNeGardeAucunMaillage() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .demo, dossier: dossier)
        s.demarrer()
        #expect(s.thread.maillage != nil, "la demo a son maillage")
        #expect(!FileManager.default.fileExists(atPath: Surveillance.dossierThread(dossier).appendingPathComponent("dernier-maillage.json").path))
    }

    /// Etape 3a, tache 6 : la coque (journal, surnoms) se construit et marche sans que le modele de Thread n'ait rien
    /// demarre : ni ecoute, ni sonde, ni releve. Un evenement ajoute par un modele y prend le protocole du modele, va au
    /// journal sur disque et se relit ; un surnom se garde sous l'identifiant de noeud, de n'importe quel protocole.
    @Test func coqueSansProtocole() throws {
        let dossier = Self.dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        #expect(s.modeles.map(\.protocole) == [.thread, .zigbee], "un modele par protocole, Thread d'abord")
        #expect(s.evenements.isEmpty && s.lignesJournal.isEmpty && !s.alerte)
        #expect(s.thread.instantane == nil && s.thread.maillage == nil && s.thread.dernierReleve == nil)
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        s.ajouter([Evenement(date: t0, type: .parentChange, sujet: Sujet(id: "AAAA000000000001", nom: "Prise"),
                             avant: "A", apres: "B")], de: .thread)
        #expect(s.evenements.count == 1 && s.evenements[0].protocole == .thread)
        let relu = Surveillance(mode: .direct, dossier: dossier)
        relu.chargerJournal()
        #expect(relu.evenements == s.evenements, "le journal est celui de la coque")
        let thread = IdNoeud(.thread, "AAAA000000000001"), zigbee = IdNoeud(.zigbee, "AAAA000000000001")
        s.renommer(thread, en: " Lampe ")
        s.renommer(zigbee, en: "Autre")
        #expect(s.surnom(de: thread) == "Lampe" && s.surnom(de: zigbee) == "Autre")
        #expect(s.thread.noms.surnoms == ["AAAA000000000001": "Lampe"], "le modele de Thread ne voit que ses cles")
        #expect(s.zigbee.noms.surnoms == ["AAAA000000000001": "Autre"], "celui de Zigbee aussi")
        #expect(Surveillance(mode: .direct, dossier: dossier).surnom(de: zigbee) == "Autre", "relu du disque")
    }

    /// Le modele de Thread repond au protocole d'app que la scene et le menu liront : les memes graphe, appareils et
    /// resume que ceux de la fenetre, l'echelle en dBm, le classement de Thread, une mise en avant propre a Thread.
    @Test func modeleThreadRepondAuProtocole() throws {
        let s = Self.demo()
        let m: any ModeleProtocole = s.thread
        #expect(m.protocole == .thread)
        let r = try #require(s.thread.reseau)
        #expect(m.graphe == s.thread.graphe(pour: r))
        #expect(!m.graphe.noeuds.isEmpty && m.graphe.noeuds.allSatisfy { $0.id.protocole == .thread })
        #expect(m.appareils == s.thread.appareilsAffiches(pour: r))
        #expect(m.echelle.unite == "dBm")
        let noeud = try #require(m.graphe.noeuds.first)
        #expect(m.classement(noeud) == classementThread(noeud))
        let chefs = LibellesNoeuds.chefs(reseau: r, maillage: s.thread.maillage, affiche: s.thread.maillageAffiche(pour: r))
        #expect(m.miseEnAvant(de: noeud.id, graphe: m.graphe, chefs: chefs, voisins: true)
                == FocusThread.miseEnAvant(de: noeud.id, graphe: m.graphe, chefs: chefs, voisins: true))
        #expect(m.miseEnAvant(de: IdNoeud(.zigbee, noeud.id.cle), graphe: m.graphe, chefs: chefs, voisins: true) == nil)
        let resume = try #require(s.thread.resume)
        #expect(m.resumeMenu == ResumeMenu(routeurs: resume.routeurs, appareils: resume.appareils,
                                           injoignables: resume.injoignables))
        #expect(m.aHistorique == !s.thread.historique.isEmpty && m.alerteReseau == (s.thread.instantane?.reseaux.contains(where: \.estScinde) == true))
        #expect(m.fraicheurMaillage(a: s.maintenant) == s.thread.fraicheurMaillage(a: s.maintenant))
        #expect(s.modele(pour: .zigbee) === s.zigbee && s.modele(pour: .thread) === s.thread)
    }
}
