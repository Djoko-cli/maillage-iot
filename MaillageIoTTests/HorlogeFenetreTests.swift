import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MaillageIoT

/// L'etat reel des ecrans du Mac, lu par le trait `.enabled(if:)` des essais d'occlusion reelle : ecrans en veille, Mac
/// verrouille ou session ailleurs, AppKit juge cachee (`occlusionState`) la fenetre hors ecran des tests (constat du
/// 25/10 : `cachee: true` pendant 40 s la nuit), et ces essais n'ont plus rien a mesurer. Ils sautent alors, et le disent.
enum EtatDesEcrans {
    /// Les ecrans sont allumes, la session est a l'ecran et deverrouillee : une fenetre posee a l'ecran est vue par AppKit.
    static var occlusionReelleMesurable: Bool {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return false }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if (session?["CGSSessionScreenIsLocked"] as? Bool) == true { return false }
        if (session?["kCGSSessionOnConsoleKey"] as? Bool) == false { return false }
        return true
    }

    static let motif: Comment = "ecrans en veille, Mac verrouille ou session ailleurs : AppKit juge cachee la fenetre des tests"
}

/// Les centres de notifications propres a un essai d'occlusion reelle : les annonces de veille, de verrou et de session
/// y sont envoyees, jamais sur ceux du processus (celui de `NSWorkspace` est partage avec les suites voisines, dont les
/// vues s'arreteraient pendant l'essai).
struct CentresPrives {
    let espace = NotificationCenter()
    let verrou = NotificationCenter()

    var source: SourceVisibilite { .reelle(espace: espace, verrou: verrou) }
}

/// L'horloge de la vue par pieces et la fenetre qui la porte (performance, constat du 25/10) : la rotation lente tenait
/// l'horloge en marche (`doitContinuer`), et la `TimelineView` de SwiftUI calcule ses images meme dans une fenetre fermee,
/// reduite dans le Dock ou entierement cachee. La vue ne calcule plus aucune image tant que sa fenetre n'est pas vue, et
/// la rotation reprend la ou elle en etait, sans saut.
@MainActor
@Suite("Vue par pieces : l'horloge s'arrete quand la fenetre n'est pas vue", .serialized)
struct HorlogeFenetreTests {
    /// La fenetre est vue seulement ouverte, hors du Dock, pas entierement cachee, les ecrans allumes, la session a
    /// l'ecran et deverrouillee ; l'horloge ne tourne que pendant un mouvement, dans une fenetre vue.
    @Test func fenetreVue() {
        let vue = VisibiliteFenetre()
        #expect(vue.vue)
        let cas: [(String, VisibiliteFenetre)] = [
            ("fermee", VisibiliteFenetre(ouverte: false)), ("reduite", VisibiliteFenetre(reduite: true)),
            ("cachee", VisibiliteFenetre(cachee: true)), ("ecrans eteints", VisibiliteFenetre(ecransEteints: true)),
            ("verrouillee", VisibiliteFenetre(verrouillee: true)),
            ("session ailleurs", VisibiliteFenetre(sessionAilleurs: true)),
        ]
        for (nom, v) in cas {
            #expect(!v.vue, "\(nom)")
            #expect(!VisibiliteFenetre.horloge(anime: true, visibilite: v), "\(nom) : pas d'horloge")
        }
        #expect(VisibiliteFenetre.horloge(anime: true, visibilite: vue))
        #expect(!VisibiliteFenetre.horloge(anime: false, visibilite: vue), "au repos : pas d'horloge")
        // Une vue hors de toute fenetre, ou dans une fenetre jamais posee a l'ecran, n'est pas vue.
        #expect(!VisibiliteFenetre(fenetre: nil, mac: vue).vue)
        let jamaisMontree = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 200, height: 200), styleMask: [.titled],
                                     backing: .buffered, defer: true)
        jamaisMontree.isReleasedWhenClosed = false
        #expect(!VisibiliteFenetre(fenetre: jamaisMontree, mac: vue).vue)
    }

    /// Le moteur en 3D, rotation lente : fermee, reduite, cachee, ecrans eteints, verrouillee, session ailleurs, l'horloge
    /// s'arrete, le mouvement reste du ; de retour, elle repart, et sa premiere image a un temps nul : la rotation
    /// reprend la ou elle en etait, sans le temps passe hors de vue (ni meme le dixieme de seconde ou `avancer` borne
    /// le pas).
    @Test func moteurSelonLaFenetre() throws {
        let (_, _, e) = try NomsSceneTests.demo()
        let m = MoteurPieces(troisD: true)
        m.marges = (84, 50)
        m.poserTaille(MoteurPiecesTests.taille)
        m.installerMaintenant(e)
        MoteurPiecesTests.dessiner(m)
        MoteurPiecesTests.dessiner(m)
        #expect(m.anime && m.horlogeEnMarche, "fenetre vue, rotation lente : l'horloge tourne")
        let cas: [(String, VisibiliteFenetre)] = [
            ("fermee", VisibiliteFenetre(ouverte: false)), ("reduite", VisibiliteFenetre(ouverte: false, reduite: true)),
            ("cachee", VisibiliteFenetre(cachee: true)), ("ecrans eteints", VisibiliteFenetre(ecransEteints: true)),
            ("verrouillee", VisibiliteFenetre(cachee: true, verrouillee: true)),
            ("session ailleurs", VisibiliteFenetre(sessionAilleurs: true)),
        ]
        var heure = MoteurPieces.maintenant() + 1
        for (nom, v) in cas {
            m.avancer(heure)
            m.regler(visibilite: v)
            #expect(!m.horlogeEnMarche, "\(nom) : aucune image")
            #expect(m.anime, "\(nom) : le mouvement reste du, il reprendra")
            m.regler(visibilite: VisibiliteFenetre())
            #expect(m.horlogeEnMarche, "\(nom), puis de retour : l'horloge repart")
            let azimut = m.orbite.azimut
            heure += 30
            m.avancer(heure)
            #expect(m.dt == 0 && m.orbite.azimut == azimut, "\(nom), premiere image de retour : pas de saut")
            heure += 1.0 / 60
            m.avancer(heure)
            #expect(m.orbite.azimut < azimut, "\(nom) : puis la rotation reprend")
        }
    }

    /// La vraie fenetre de la vue par pieces, hors ecran, en 3D (rotation lente active), la disposition posee et la
    /// bascule vers la 3D finie ; reductible, pour l'essai du Dock. `source` : d'ou la vue tire ce que Djoko voit (toujours
    /// vue par defaut ; les essais d'occlusion reelle donnent la vraie sonde, sur leurs centres propres). A retirer par
    /// `FenetrePiecesTests.fermer`.
    static func fenetre3D(_ p: UserDefaults, source: SourceVisibilite = .toujoursVue) async throws -> (NSWindow, MoteurPieces) {
        p.set(true, forKey: FenetrePieces.cleMode)
        let demo = Surveillance(mode: .demo, dossier: nil)
        demo.demarrer()
        let (fenetre, moteur) = try FenetrePiecesTests.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p,
                                                               visibilite: source)
        fenetre.styleMask.insert(.miniaturizable)
        try await MoteurPiecesTests.attendre { moteur.pret && moteur.projetee != nil && moteur.t == 1 && !moteur.margesEnRoute }
        try await Task.sleep(for: .milliseconds(300))
        return (fenetre, moteur)
    }

    /// L'azimut de la camera avance pendant `duree` : des images sont calculees (la rotation lente tourne).
    static func avance(_ moteur: MoteurPieces, pendant duree: Duration = .milliseconds(500)) async throws -> Double {
        let a = moteur.orbite.azimut
        try await Task.sleep(for: duree)
        return a - moteur.orbite.azimut
    }

    /// Retiree de l'ecran, reduite dans le Dock, fermee par son bouton : plus aucune image (l'azimut ne bouge plus) ; de
    /// retour, la rotation reprend, d'un pas ordinaire : pas de saut du temps ecoule. Un temps de pose apres chaque
    /// changement : AppKit annonce la fenetre cachee (`occlusionState`) a la fin de son effacement, environ 0,3 s apres
    /// `orderOut` (essai du 25/10), la sortie du Dock a la fin de son animation. Occlusion reelle : saute quand les ecrans
    /// dorment ou que le Mac est verrouille (`EtatDesEcrans`).
    @Test(.timeLimit(.minutes(1)), .enabled(if: EtatDesEcrans.occlusionReelleMesurable, EtatDesEcrans.motif))
    func fermeeReduiteEtDeRetour() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (fenetre, moteur) = try await Self.fenetre3D(p, source: CentresPrives().source)
        defer { FenetrePiecesTests.fermer(fenetre) }
        let pas = try await Self.avance(moteur)
        #expect(pas > 0, "fenetre ouverte : la rotation lente tourne")

        fenetre.orderOut(nil)
        try await Task.sleep(for: .milliseconds(700))
        #expect(try await Self.avance(moteur) == 0, "fenetre fermee : aucune image")
        fenetre.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(300))
        let retour = try await Self.avance(moteur)
        #expect(retour > 0 && retour < 2 * pas, "de retour : la rotation reprend, sans saut (\(retour) pour \(pas))")

        fenetre.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(try await Self.avance(moteur) == 0, "fenetre reduite dans le Dock : aucune image")
        fenetre.deminiaturize(nil)
        try await Task.sleep(for: .milliseconds(1200))
        let sortie = try await Self.avance(moteur)
        #expect(sortie > 0 && sortie < 2 * pas, "sortie du Dock : la rotation reprend, sans saut (\(sortie) pour \(pas))")

        fenetre.close()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await Self.avance(moteur) == 0, "fenetre fermee par son bouton : aucune image")
    }

    /// Les ecrans eteints, puis rallumes, l'ecran verrouille, puis deverrouille, la session quittee, puis reprise (les
    /// annonces, envoyees sur les centres propres de cet essai) : plus aucune image, puis la rotation reprend. Occlusion
    /// reelle : saute quand les ecrans dorment ou que le Mac est verrouille (`EtatDesEcrans`).
    @Test(.timeLimit(.minutes(1)), .enabled(if: EtatDesEcrans.occlusionReelleMesurable, EtatDesEcrans.motif))
    func ecransEteints() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let centres = CentresPrives()
        let (fenetre, moteur) = try await Self.fenetre3D(p, source: centres.source)
        defer { FenetrePiecesTests.fermer(fenetre) }
        let verrouillee = Notification.Name("com.apple.screenIsLocked")
        let deverrouillee = Notification.Name("com.apple.screenIsUnlocked")
        let annonces: [(NotificationCenter, Notification.Name, Notification.Name)] = [
            (centres.espace, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            (centres.verrou, verrouillee, deverrouillee),
            (centres.espace, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
        ]
        for (centre, eteint, rallume) in annonces {
            #expect(try await Self.avance(moteur) > 0, "\(eteint.rawValue) : la rotation tourne avant")
            centre.post(name: eteint, object: NSWorkspace.shared)
            try await Task.sleep(for: .milliseconds(100))
            #expect(try await Self.avance(moteur) == 0, "\(eteint.rawValue) : aucune image")
            centre.post(name: rallume, object: NSWorkspace.shared)
            try await Task.sleep(for: .milliseconds(100))
            #expect(try await Self.avance(moteur) > 0, "\(rallume.rawValue) : la rotation reprend")
        }
    }

    // MARK: La porte tient ecrans en veille

    /// Ce que fait la veille des ecrans, sans mettre les ecrans en veille : la vue est rapportee « non vue » (ici par une
    /// source fixe, la valeur que rapporte la vraie sonde apres `screensDidSleep`). Elle n'a alors plus d'horloge ni
    /// d'image : c'est ce qui faisait echouer les attentes d'animation des suites de fenetre. Et la meme fenetre, avec
    /// l'injection par defaut des tests, reste vue et continue de tourner.
    @Test(.timeLimit(.minutes(1))) func laVeilleArreteLaVueSaufDansLesFenetresDeTest() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }

        let (veille, moteurEndormi) = try await Self.fenetre3D(p, source: .fixe(VisibiliteFenetre(ecransEteints: true)))
        defer { FenetrePiecesTests.fermer(veille) }
        #expect(!moteurEndormi.visibilite.vue && !moteurEndormi.horlogeEnMarche, "veille : la vue n'est pas vue")
        #expect(try await Self.avance(moteurEndormi) == 0, "veille : aucune image, comme dans une fenetre de test sans injection")

        let (fenetre, moteur) = try await Self.fenetre3D(p)
        defer { FenetrePiecesTests.fermer(fenetre) }
        #expect(moteur.visibilite.vue && moteur.horlogeEnMarche, "injection par defaut : toujours vue")
        #expect(try await Self.avance(moteur) > 0, "injection par defaut : la rotation tourne")
    }

    /// Les annonces de veille, de verrou et de session, envoyees sur des centres propres a cet essai, atteignent bien la
    /// vraie sonde qui les ecoute (elle rapporte « non vue ») sans toucher a la vue d'une fenetre de test voisine, qui
    /// reste vue et tourne. Aucune annonce ne part sur le centre de `NSWorkspace` du processus.
    @Test(.timeLimit(.minutes(1))) func lesAnnoncesDeVeilleRestentSurLeursCentres() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { p.removePersistentDomain(forName: domaine) }
        let (fenetre, moteur) = try await Self.fenetre3D(p)
        defer { FenetrePiecesTests.fermer(fenetre) }

        let centres = CentresPrives()
        let rapports = RapportsVisibilite()
        let sonde = SondeVisibilite.Sonde({ rapports.valeurs.append($0) }, source: centres.source)
        fenetre.contentView?.addSubview(sonde)
        defer { sonde.removeFromSuperview() }
        try await Task.sleep(for: .milliseconds(100))
        let verrouillee = Notification.Name("com.apple.screenIsLocked")
        for (centre, nom) in [(centres.espace, NSWorkspace.screensDidSleepNotification), (centres.verrou, verrouillee),
                              (centres.espace, NSWorkspace.sessionDidResignActiveNotification)] {
            centre.post(name: nom, object: NSWorkspace.shared)
        }
        try await Task.sleep(for: .milliseconds(200))
        let dernier = try #require(rapports.valeurs.last)
        #expect(dernier.ecransEteints && dernier.verrouillee && dernier.sessionAilleurs && !dernier.vue,
                "la vraie sonde a entendu la veille, le verrou et la session : \(dernier)")
        #expect(moteur.visibilite.vue && moteur.horlogeEnMarche, "la fenetre de test voisine reste vue")
        #expect(try await Self.avance(moteur) > 0, "et sa rotation continue")
    }
}

/// Les rapports d'une sonde de visibilite, dans l'ordre.
@MainActor
final class RapportsVisibilite {
    var valeurs: [VisibiliteFenetre] = []
}
