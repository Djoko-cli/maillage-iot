import ServiceManagement
import Testing

/// Correspondance des etats de SMAppService (spec, section 2.3). Aucun test n'appelle SMAppService.
@Suite("Ouverture a la session du demon")
struct OuvertureSessionDemonTests {
    @Test func correspondance() {
        #expect(EtatPasseur.Ouverture(.enabled) == .active)
        #expect(EtatPasseur.Ouverture(.notRegistered) == .inactive)
        #expect(EtatPasseur.Ouverture(.requiresApproval) == .aApprouver)
        #expect(EtatPasseur.Ouverture(.notFound) == .indisponible)
    }

    @Test func reponsesDIdentification() {
        #expect(IssueIdentifier.ok.reponse(3) == ReponseIdentifier(demande: 3, ok: true))
        #expect(IssueIdentifier.inconnu.reponse(4) == ReponseIdentifier(demande: 4, ok: false, erreur: ReponseIdentifier.inconnu))
        #expect(IssueIdentifier.nonIdentifiable.reponse(5)
                == ReponseIdentifier(demande: 5, ok: false, erreur: ReponseIdentifier.nonIdentifiable))
        #expect(IssueIdentifier.erreur("hors de portée").reponse(6)
                == ReponseIdentifier(demande: 6, ok: false, erreur: "hors de portée"))
    }
}
