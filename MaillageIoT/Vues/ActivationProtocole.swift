import MaillageCoeur
import SwiftUI

/// Le contenu d'un onglet de protocole (Thread, Zigbee) : « Activer ce protocole » en tete, puis la page. Protocole eteint,
/// tout ce qui suit l'interrupteur est grise, et lui seul reste actif pour rallumer (spec 6.7, decision 5 : une seule regle
/// pour les deux protocoles). Le grisage est pose UNE fois, sur tout le contenu : un controle ajoute plus tard a la page
/// est grise sans qu'on y pense, et les `.disabled` propres a un controle (un bouton sans sonde) restent en plus. En demo,
/// aucun module n'est branche : rien n'est grise.
struct PageProtocole<Contenu: View>: View {
    @Environment(Surveillance.self) private var surveillance
    let protocole: Protocole
    @ViewBuilder let contenu: Contenu

    var body: some View {
        ActivationProtocole(protocole: protocole)
        Group { contenu }
            .disabled(!actif)
    }

    private var actif: Bool { surveillance.protocoleReglable(protocole) }
}

extension Surveillance {
    /// Les reglages d'un protocole sont-ils utilisables : son module est actif, et l'app n'est pas arretee pour une reprise de
    /// donnees (rien ne se relance avant la relance de l'app). Toujours vrai en demo (aucun module n'y est branche : rien n'est
    /// grise). Sert aux pages des protocoles et aux sections de l'onglet Notifications.
    func protocoleReglable(_ protocole: Protocole) -> Bool {
        guard mode == .direct, let m = modele(pour: protocole) else { return true }
        return m.actif && !arretee
    }
}

/// « Activer ce protocole », en tete de l'onglet Thread ou Zigbee des Reglages (spec 3.3) : decoche, le protocole est
/// vraiment arrete (sonde et port, Bonjour ou pont, tournees, notifications : `ModeleProtocole.actif`) et ses noeuds
/// quittent la scene ; coche, il repart comme au lancement. Actif mais sans rien a montrer, l'onglet le dit simplement,
/// sans alerte ni notification. Rien en demo (les modules n'y sont pas branches). Le grisage de l'onglet eteint est
/// `PageProtocole`.
struct ActivationProtocole: View {
    @Environment(Surveillance.self) private var surveillance
    let protocole: Protocole

    var body: some View {
        if surveillance.mode == .direct, let m = surveillance.modele(pour: protocole) {
            Section {
                Toggle("Activer ce protocole", isOn: Binding(get: { m.actif }, set: { m.actif = $0 }))
                    // Pendant une reprise de donnees, ou apres elle tant que l'app ne s'est pas relancee, rien ne se rallume.
                    .disabled(surveillance.arretee)
                if let texte = Self.texteRienTrouve(protocole, rienTrouve: rienTrouve) {
                    Text(texte).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rienTrouve: Bool {
        switch protocole {
        case .thread: surveillance.thread.rienTrouve
        case .zigbee: surveillance.zigbee.rienTrouve
        }
    }

    /// Ce que l'onglet dit d'un protocole actif qui ne trouve rien ; nil sinon. Une simple phrase : pas d'alerte, pas de
    /// notification.
    static func texteRienTrouve(_ protocole: Protocole, rienTrouve: Bool) -> String? {
        guard rienTrouve else { return nil }
        return switch protocole {
        case .thread: String(localized: "Aucun réseau Thread visible sur ce réseau local")
        case .zigbee: String(localized: "Aucun réseau Zigbee à montrer : ni maillage de la sonde, ni appareil du pont Hue.")
        }
    }
}
