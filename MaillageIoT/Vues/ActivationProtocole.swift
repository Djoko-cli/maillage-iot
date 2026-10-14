import MaillageCoeur
import SwiftUI

/// « Activer ce protocole », en tete de l'onglet Thread ou Zigbee des Reglages (spec 3.3) : decoche, le protocole est
/// vraiment arrete (sonde et port, Bonjour ou pont, tournees, notifications : `ModeleProtocole.actif`) et ses noeuds
/// quittent la scene ; coche, il repart comme au lancement. Actif mais sans rien a montrer, l'onglet le dit simplement,
/// sans alerte ni notification. Rien en demo (les modules n'y sont pas branches). Le grisage des vues est a l'etape 3b.
struct ActivationProtocole: View {
    @Environment(Surveillance.self) private var surveillance
    let protocole: Protocole

    var body: some View {
        if surveillance.mode == .direct, let m = surveillance.modele(pour: protocole) {
            Section {
                Toggle("Activer ce protocole", isOn: Binding(get: { m.actif }, set: { m.actif = $0 }))
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
