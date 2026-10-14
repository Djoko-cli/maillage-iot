import Foundation
import Network
import dnssd
import Testing
@testable import MaillageIoT

@MainActor
@Suite("Recenseur : refus du reseau local")
struct RecenseurTests {
    @Test func refusDuReseauLocal() {
        #expect(NavigateurBonjour.etat(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))) == .refuse)
        if case .erreur = NavigateurBonjour.etat(.dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))) {} else {
            Issue.record("une autre erreur DNS n'est pas un refus")
        }
        if case .erreur = NavigateurBonjour.etat(.posix(.ENETDOWN)) {} else {
            Issue.record("reseau coupe : erreur, pas refus")
        }
    }
}
