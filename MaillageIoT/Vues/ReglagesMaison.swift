import MaillageCoeur
import ProtocoleZigbee
import SwiftUI

/// Reglages › Maison : la page du demon Passeur Noms, commune aux deux protocoles (un seul client, un seul releve de
/// Maison, qui sert Thread et Zigbee). Le demon (etat, ouverture de session, profil, aide quand il manque), puis le dernier
/// releve de Maison qu'il a servi (etat, date, accessoires et zones), combien d'appareils du pont Hue Maison nomme,
/// « Rafraichir depuis Maison » et le probleme du dernier releve.
struct ReglagesMaison: View {
    @Environment(NomsPasseur.self) private var passeur
    @Environment(Surveillance.self) private var surveillance

    var body: some View {
        Section("Passeur Noms") {
            if surveillance.mode == .demo {
                Text("Mode démo : le relevé de Maison de la démo, pas de Passeur.").foregroundStyle(.secondary)
            }
            LabeledContent("État", value: NomsPasseur.texteDemon(connecte: passeur.connecte, etat: passeur.etat))
            Toggle("Ouvrir Passeur Noms à l'ouverture de session", isOn: Binding(
                get: { passeur.etat?.ouvertureSession == .active },
                set: { passeur.reglerOuvertureSession($0) }))
                .disabled(!NomsPasseur.interrupteurActif(connecte: passeur.connecte, etat: passeur.etat))
            if passeur.connecte, passeur.etat?.ouvertureSession == .aApprouver {
                Text("Accepte Passeur Noms dans Réglages Système › Général › Ouverture.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let fin = passeur.etat?.profilExpire, NomsPasseur.profilBientotExpire(passeur.etat, maintenant: .now) {
                Text("Le profil de Passeur Noms expire le \(fin.formatted(date: .abbreviated, time: .omitted)) : relance outils/passeur.sh.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if passeur.passeurAbsent {
                Text("Passeur Noms s'installe par outils/passeur.sh : voir le README.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Noms de Maison") {
            LabeledContent("État", value: Self.texteEtat(releve: passeur.releve, enCours: passeur.releveEnCours))
            if let r = passeur.releve {
                LabeledContent("Dernier relevé", value: Self.texteReleve(r))
                // Rien pour un releve d'avant les zones.
                if let zones = r.zones {
                    LabeledContent("Zones", value: FenetreReglages.texteZones(zones))
                }
            }
            LabeledContent("Appareils du pont", value: Self.texteBilan(surveillance.zigbee.bilanFusion))
            if let p = passeur.probleme {
                Text(p).font(.caption).foregroundStyle(.red)
            }
            HStack {
                // Grise pendant une relecture : le demon y repond, sinon la garde la libere apres 2 minutes.
                Button("Rafraîchir depuis Maison") { passeur.relire() }
                    .disabled(surveillance.mode == .demo || passeur.inerte || passeur.releveEnCours)
                if passeur.releveEnCours {
                    ProgressView().controlSize(.small)
                }
            }
            Text("Les noms, les pièces et les étages (zones) viennent de l'app Maison, lus par Passeur Noms, qui les envoie dès qu'ils changent ; le pont Hue donne les adresses, l'état de connexion et les piles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// L'etat en quelques mots.
    static func texteEtat(releve: NomsMaison?, enCours: Bool) -> String {
        if enCours { return String(localized: "relevé en cours…") }
        return releve == nil ? String(localized: "aucun relevé : noms de l'app Hue") : String(localized: "relevé reçu")
    }

    /// « 42 accessoires · 8 oct. 2026 à 14:32 ».
    static func texteReleve(_ r: NomsMaison) -> String {
        String(localized: "\(r.accessoires.count) accessoires · \(r.date.formatted(date: .abbreviated, time: .shortened))")
    }

    /// « 20 nommés par Maison · 1 avec le nom de l'app Hue » ; sans pont lu ou sans releve, ce qui manque.
    static func texteBilan(_ b: FusionNoms.Bilan?) -> String {
        guard let b else { return String(localized: "noms de l'app Hue seulement") }
        return String(localized: "\(b.apparies) nommés par Maison · \(b.nonApparies) avec le nom de l'app Hue")
    }
}
