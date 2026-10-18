import AppKit
import MaillageCoeur
import SwiftUI

/// La fenetre de l'assistant de reprise (phase 4, tache 7), au style des Reglages : un formulaire groupe, sa barre de boutons en
/// bas. Aucune logique ici : tout est dans `AssistantReprise` (les etapes, l'ancienne app, la reprise, la relance) et dans les
/// textes de `ResumeFinalReprise` / `EtatSystemeReprise`.
struct FenetreReprise: View {
    let assistant: AssistantReprise
    /// Ferme la fenetre (`ControleurReprise`).
    var fermer: () -> Void = {}
    @Environment(\.locale) private var locale
    /// Hauteur du contenu du formulaire, lue sur sa vue defilante : la fenetre la suit, jusqu'a `hauteurMax`.
    @State private var hauteurFormulaire: CGFloat = 0

    static let largeur: CGFloat = 540
    /// Hauteur au-dela de laquelle le formulaire defile ; en deca, la fenetre prend la hauteur de son contenu.
    static let hauteurMax: CGFloat = 640
    /// Hauteur de la barre des boutons et de son separateur.
    static let hauteurBarre: CGFloat = 57

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let avis = assistant.avis {
                    Section {
                        Label(avis.texte(locale: locale), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                contenu
            }
            .formStyle(.grouped)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { _, h in hauteurFormulaire = h }
            .frame(height: hauteurFormulaire > 0 ? min(hauteurFormulaire, Self.hauteurMax - Self.hauteurBarre) : nil)
            Divider()
            HStack(spacing: 12) {
                boutons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: Self.largeur)
        .frame(maxHeight: Self.hauteurMax)
        // L'ancienne app qui tourne se reverifie ; le resume relit « À refaire » sur l'etat reel (les reponses de macOS aux
        // notifications et a la cle, l'issue de Bonjour arrivent apres coup), et de nouveau quand l'app ou la fenetre revient
        // au premier plan (l'utilisateur sort de Reglages Systeme).
        .task(id: assistant.etape) {
            await assistant.surveillerAncienneApp()
            await assistant.surveillerARefaire()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await assistant.relireARefaire() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await assistant.relireARefaire() }
        }
    }

    // MARK: Contenu de chaque etape

    @ViewBuilder
    private var contenu: some View {
        switch assistant.etape {
        case .accueil: accueil
        case .validation: attente("Vérification de l'export…")
        case .refuse(let cause): refus(cause)
        case .impossible(let erreur): impossible(erreur)
        case .confirmation(let resume): confirmation(resume)
        case .dejaRepris(let reprise, _): dejaRepris(reprise)
        case .enCours: attente("Reprise en cours… Ne pas quitter Maillage IoT.")
        case .echec(let erreur): echec(erreur)
        case .relance: attente("Reprise terminée. Maillage IoT se relance pour lire les données reprises…")
        case .termine(let final, let taches): termine(final, taches)
        }
    }

    private var accueil: some View {
        Section {
            if assistant.proposition {
                Text("Maillage IoT remplace Maillage Thread et Maillage Zigbee. Les surnoms, les pièces, l'historique et les réglages de l'ancienne app peuvent être repris.")
            } else {
                Text("Reprendre les surnoms, les pièces, l'historique et les réglages de Maillage Thread ou de Maillage Zigbee.")
            }
            Text("Dans l'ancienne app (version 1.4.0 de Thread, 1.2.0 de Zigbee ou plus récente), le menu « Exporter pour Maillage IoT… » écrit un dossier. Il suffit de le choisir ici : l'ancienne app n'est pas modifiée, et rien n'est repris tant que l'export n'est pas vérifié.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Reprendre des données")
        }
    }

    private func attente(_ texte: LocalizedStringKey) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(texte)
            }
        }
    }

    private func refus(_ cause: CauseRefus) -> some View {
        Section {
            Label(cause.texte(locale: locale), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            Text("Rien n'a été repris.").foregroundStyle(.secondary)
            if assistant.peutRepartirDUnJournalVide {
                Text("« Repartir d'un journal vide » renomme le journal des reprises en imports.json.abime, sans rien supprimer, puis vérifie de nouveau l'export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Export refusé")
        }
    }

    private func impossible(_ erreur: ErreurApplication) -> some View {
        Section {
            Label(TexteReprise.erreur(erreur, locale: locale), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        } header: {
            Text("L'export n'a pas pu être vérifié")
        }
    }

    private func dejaRepris(_ reprise: ImportRepris) -> some View {
        Section {
            Text("Cet export de \(reprise.app.nomApp) \(reprise.versionApp) a déjà été repris le \(TexteReprise.date(reprise.date, locale: locale)). Il n'y a rien à refaire.")
        } header: {
            Text("Déjà repris")
        }
    }

    private func confirmation(_ resume: ResumeExport) -> some View {
        Group {
            Section {
                LabeledContent("Ancienne app", value: "\(resume.app.nomApp) \(resume.versionApp)")
                LabeledContent("Export du", value: TexteReprise.date(resume.date, locale: locale))
                ForEach(GenreContenu.allCases.filter { resume.nombre($0) > 0 }, id: \.self) { genre in
                    Text(resume.ligne(genre, locale: locale))
                }
                Text(resume.texteReglagesRepris(locale: locale))
                if !resume.reglagesNonRepris.isEmpty {
                    Text(resume.texteReglagesLaissesDeCote(locale: locale)).foregroundStyle(.secondary)
                }
                if !resume.fichiersNonRepris.isEmpty {
                    Text(resume.texteFichiersNonRepris(locale: locale)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Contenu de l'export, vérifié")
            }
            ancienneApp(resume.app)
            Section {
                Text("Pendant la reprise, Maillage IoT cesse d'écouter. Une fois les données en place, il se relance seul et affiche ce qui a été repris, ce qui a été ignoré et ce qui reste à faire. Si quelque chose échoue, rien n'est modifié.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func ancienneApp(_ app: ContratExport.AppSource) -> some View {
        switch assistant.ancienneApp {
        case .absente:
            EmptyView()
        case .tourne:
            Section {
                Label("\(app.nomApp) tourne encore : une sonde USB ne peut avoir qu'un seul maître. La quitter avant la reprise.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .demandeEnvoyee:
            Section {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("En attente de la fermeture de \(app.nomApp)…")
                }
            }
        case .aQuitterSoiMeme:
            Section {
                Label(TexteReprise.ancienneAppAQuitterSoiMeme(app.nomApp, locale: locale), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func echec(_ erreur: ErreurApplication) -> some View {
        Section {
            Label(TexteReprise.erreur(erreur, locale: locale), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            if assistant.relanceEchouee {
                Text("Maillage IoT n'a pas pu se relancer seul : le quitter, puis le rouvrir.").foregroundStyle(.orange)
            } else {
                Text("Maillage IoT a cessé d'écouter pour la reprise : il doit se relancer.").foregroundStyle(.secondary)
            }
        } header: {
            Text("La reprise a échoué")
        }
    }

    private func termine(_ final: ResumeFinal, _ taches: [TacheARefaire]) -> some View {
        Group {
            Section {
                Text(final.origine(locale: locale))
                ForEach(final.lignesReprises(locale: locale), id: \.self) { Text($0) }
                if let recalcul = final.texteRecalcul(locale: locale) {
                    Text(recalcul).foregroundStyle(.secondary)
                }
                if let laisses = final.texteLaisses(locale: locale) {
                    Label(laisses, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } header: {
                Text("Repris")
            }
            if !final.ignores.isEmpty {
                Section {
                    ForEach(final.lignesIgnorees(locale: locale), id: \.self) { Text($0).foregroundStyle(.secondary) }
                } header: {
                    Text("Ignoré")
                }
            }
            Section {
                if taches.isEmpty {
                    Label(ListeARefaire.rienARefaire(locale: locale), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ForEach(taches, id: \.self) { tache in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tache.titre(locale: locale))
                            Text(tache.detail(locale: locale)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                // Le reseau local ne se lit pas a l'avance : la liste ne peut pas affirmer qu'il est en ordre.
                if !taches.contains(.autoriserReseauLocal) {
                    Text(ListeARefaire.noteReseauLocal(locale: locale)).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(ListeARefaire.titreSection(locale: locale))
            }
            if assistant.relanceEchouee {
                Section {
                    Label("Maillage IoT n'a pas pu se relancer seul : le quitter, puis le rouvrir, pour qu'il lise les données reprises.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Boutons

    @ViewBuilder
    private var boutons: some View {
        switch assistant.etape {
        case .accueil:
            Spacer()
            Button(assistant.proposition ? "Plus tard" : "Fermer") {
                assistant.plusTard()
                fermer()
            }
            .keyboardShortcut(.cancelAction)
            Button("Choisir le dossier d'export…") { Task { await assistant.choisirDossier() } }
                .keyboardShortcut(.defaultAction)
        case .validation, .enCours, .relance:
            Spacer()
        case .refuse, .impossible, .dejaRepris:
            Button("Fermer") { fermer() }.keyboardShortcut(.cancelAction)
            Spacer()
            if assistant.peutRepartirDUnJournalVide {
                Button("Repartir d'un journal vide") { Task { await assistant.repartirDUnJournalVide() } }
            }
            Button("Choisir un autre dossier…") { Task { await assistant.choisirDossier() } }
                .keyboardShortcut(.defaultAction)
        case .confirmation(let resume):
            Button("Annuler") { assistant.recommencer() }.keyboardShortcut(.cancelAction)
            Spacer()
            switch assistant.ancienneApp {
            case .tourne:
                Button("Quitter \(resume.app.nomApp)") { Task { await assistant.quitterAncienneApp() } }
            case .aQuitterSoiMeme:
                Button("Vérifier de nouveau") { assistant.verifierAncienneApp() }
            case .absente, .demandeEnvoyee:
                EmptyView()
            }
            Button("Reprendre") { Task { await assistant.lancer() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!assistant.peutLancer)
        case .echec:
            Spacer()
            if assistant.relanceEchouee {
                Button("Quitter Maillage IoT") { assistant.quitterMaillageIoT() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Relancer Maillage IoT") { Task { await assistant.relancerApresEchec() } }
                    .keyboardShortcut(.defaultAction)
            }
        case .termine:
            Spacer()
            if assistant.relanceEchouee {
                Button("Quitter Maillage IoT") { assistant.quitterMaillageIoT() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Terminé") {
                    assistant.terminer()
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
