import Foundation
import MaillageCoeur
import Testing
@testable import MaillageIoT

/// Ce que montrent les Reglages et la fiche selon l'etat du demon (spec, section 4.1).
@Suite("Reglages du demon et bouton Identifier")
struct ReglagesDemonTests {
    static let maintenant = Date(timeIntervalSince1970: 1_800_000_000)

    static func etat(_ ouverture: EtatPasseur.Ouverture = .inactive, acces: EtatPasseur.Acces = .autorise,
                     profil: Date? = nil) -> EtatPasseur {
        EtatPasseur(version: "2.0", acces: acces, ouvertureSession: ouverture, profilExpire: profil)
    }

    @Test func texteDuDemon() {
        #expect(NomsPasseur.texteDemon(connecte: false, etat: Self.etat()) == String(localized: "non connecté"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: nil) == String(localized: "non connecté"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: Self.etat())
                == String(localized: "connecté · version \("2.0") · \(String(localized: "accès à Maison autorisé"))"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: Self.etat(acces: .refuse)).contains(String(localized: "accès à Maison refusé")))
    }

    /// Avertissement 30 jours avant l'expiration du profil, et apres.
    @Test func profil() {
        let jour: TimeInterval = 86_400
        #expect(!NomsPasseur.profilBientotExpire(nil, maintenant: Self.maintenant))
        #expect(!NomsPasseur.profilBientotExpire(Self.etat(), maintenant: Self.maintenant), "profil illisible")
        #expect(!NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant + 31 * jour), maintenant: Self.maintenant))
        #expect(NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant + 30 * jour), maintenant: Self.maintenant))
        #expect(NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant - jour), maintenant: Self.maintenant))
    }

    /// L'interrupteur : grise sans demon connecte ; actif meme `indisponible` (demon jamais inscrit).
    @Test func interrupteur() {
        #expect(!NomsPasseur.interrupteurActif(connecte: false, etat: Self.etat()))
        #expect(!NomsPasseur.interrupteurActif(connecte: true, etat: nil))
        #expect(NomsPasseur.interrupteurActif(connecte: true, etat: Self.etat(.indisponible)))
        #expect(NomsPasseur.interrupteurActif(connecte: true, etat: Self.etat(.aApprouver)))
    }

    /// « Identifier » : grise sans demon connecte, ou pour un accessoire sans `id`.
    @Test func boutonIdentifier() {
        let avec = AccessoireMaison(nom: "Capteur", id: "8D3C2A10-0000-4000-8000-000000000001")
        let sans = AccessoireMaison(nom: "Capteur")
        #expect(BoutonIdentifier.actif(connecte: true, accessoire: avec))
        #expect(!BoutonIdentifier.actif(connecte: false, accessoire: avec))
        #expect(!BoutonIdentifier.actif(connecte: true, accessoire: sans))
    }

    @Test func textesDIdentification() {
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: true)) == String(localized: "Identification demandée"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false, erreur: ReponseIdentifier.inconnu))
                == String(localized: "Accessoire introuvable dans Maison"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false, erreur: "hors de portée"))
                == String(localized: "Identification impossible : \("hors de portée")"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false)) == String(localized: "Identification impossible"))
    }
}
