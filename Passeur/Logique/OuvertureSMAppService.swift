import ServiceManagement

extension EtatPasseur.Ouverture {
    init(_ s: SMAppService.Status) {
        switch s {
        case .enabled: self = .active
        case .notRegistered: self = .inactive
        case .requiresApproval: self = .aApprouver
        case .notFound: self = .indisponible
        @unknown default: self = .indisponible
        }
    }
}

/// L'ouverture a la session du demon lui-meme (`SMAppService.mainApp`, disponible sous Mac Catalyst). A la premiere
/// inscription, macOS montre « Element d'arriere-plan ajoute ». Jamais appelee par les tests.
@MainActor
final class OuvertureSMAppService: OuvertureSessionDemon {
    var statut: EtatPasseur.Ouverture {
        EtatPasseur.Ouverture(SMAppService.mainApp.status)
    }

    func regler(actif: Bool) -> String? {
        do {
            if actif {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
