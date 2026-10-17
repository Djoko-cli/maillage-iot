import Foundation

/// Un module de l'app que la reprise de donnees arrete (phase 4, tache 7) : `ModulesApp.arreterTout` les arrete tous.
@MainActor
protocol ModuleArretable: AnyObject {
    func arreter()
}

extension Surveillance: ModuleArretable {}
extension NomsPont: ModuleArretable {}
extension DecouvertePont: ModuleArretable {}
extension NomsPasseur: ModuleArretable {}
// Les deux sondes se declarent dans leurs fichiers `+Cycle.swift` (la garde des sondes refuse toute extension ailleurs).
