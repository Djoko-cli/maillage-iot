import Foundation
import Network

/// Connexion d'abonnement du demon vers une app, sur 127.0.0.1 (spec, section 2.2) : le jeton sur une ligne, puis des
/// trames dans les deux sens. Une trame mal formee ou un message illisible de l'app ferme la connexion ; un type
/// inconnu est ignore. Tout sur la file principale.
@MainActor
final class ConnexionApp: LienApp {
    var surMessage: (@MainActor (MessagePasseur) -> Void)?
    var surFin: (@MainActor () -> Void)?
    private var connexion: NWConnection?
    private var lecture = EnvoiPasseur.LectureTrames()

    /// Se connecte et envoie le jeton (`send` met en file avant que la connexion soit prete, dans l'ordre).
    init(cible: EnvoiPasseur.Cible) {
        // `Cible` n'a jamais de port 0 (lecture stricte de l'URL).
        guard let port = NWEndpoint.Port(rawValue: cible.port) else { return }
        let c = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        connexion = c
        c.stateUpdateHandler = { [weak self] etat in
            MainActor.assumeIsolated {
                switch etat {
                case .waiting(let e), .failed(let e):
                    journal.error("connexion à l'app impossible : \(String(describing: e), privacy: .public)")
                    self?.terminer()
                case .cancelled:
                    self?.terminer()
                default:
                    break
                }
            }
        }
        c.start(queue: .main)
        c.send(content: EnvoiPasseur.ligneJeton(cible.jeton), completion: .idempotent)
        recevoir(c)
    }

    func envoyer(_ m: MessagePasseur) {
        connexion?.send(content: EnvoiPasseur.trame(m), completion: .contentProcessed { [weak self] erreur in
            guard erreur != nil else { return }
            MainActor.assumeIsolated { self?.terminer() }
        })
    }

    func fermer() {
        terminer()
    }

    private func recevoir(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] donnees, _, finie, erreur in
            MainActor.assumeIsolated {
                guard let self, self.connexion === c else { return }
                if let donnees, !donnees.isEmpty {
                    let issue = self.lecture.ajouter(donnees)
                    for json in issue.trames {
                        guard self.connexion === c else { return }
                        switch MessagePasseur.lire(json) {
                        case .message(let m):
                            self.surMessage?(m)
                        case .ignore(let type):
                            journal.notice("message ignoré : \(type, privacy: .public)")
                        case .illisible:
                            journal.error("message illisible de l'app : connexion fermée")
                            self.terminer()
                            return
                        }
                    }
                    if issue.erreur != nil {
                        journal.error("trame mal formée de l'app : connexion fermée")
                        self.terminer()
                        return
                    }
                }
                if finie || erreur != nil {
                    self.terminer()
                    return
                }
                self.recevoir(c)
            }
        }
    }

    /// Ferme la connexion et previent le demon, une seule fois.
    private func terminer() {
        guard let c = connexion else { return }
        connexion = nil
        c.cancel()
        let fin = surFin
        surFin = nil
        surMessage = nil
        fin?()
    }
}

/// Releve ponctuel (URL `releve`), comme l'ancien passeur : la trame `<jeton>\n<longueur>\n<JSON>`, son cote ferme,
/// puis l'attente de la fermeture par l'app (elle a tout lu). Au plus `delai`. `fini` est appele une fois, quoi qu'il
/// arrive.
@MainActor
enum LivraisonPonctuelle {
    static let delai: Duration = .seconds(10)

    static func livrer(_ cible: EnvoiPasseur.Cible, json: Data, fini: @escaping @MainActor () -> Void) {
        let fin = UneFois(fini)
        guard let port = NWEndpoint.Port(rawValue: cible.port) else {
            fin.appeler()
            return
        }
        let c = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        c.stateUpdateHandler = { etat in
            MainActor.assumeIsolated {
                switch etat {
                case .ready:
                    c.send(content: EnvoiPasseur.trame(jeton: cible.jeton, json: json), contentContext: .finalMessage,
                           isComplete: true, completion: .contentProcessed { erreur in
                        MainActor.assumeIsolated {
                            if let erreur {
                                journal.error("relevé ponctuel non envoyé : \(String(describing: erreur), privacy: .public)")
                                c.cancel()
                                fin.appeler()
                                return
                            }
                            c.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                                MainActor.assumeIsolated {
                                    c.cancel()
                                    fin.appeler()
                                }
                            }
                        }
                    })
                case .waiting(let e), .failed(let e):
                    // Apres une livraison reussie, l'annulation de la connexion fait remonter .waiting/.failed (POSIX 50) :
                    // ce n'est pas une erreur.
                    if !fin.fait {
                        journal.error("relevé ponctuel : connexion impossible : \(String(describing: e), privacy: .public)")
                    }
                    c.cancel()
                    fin.appeler()
                default:
                    break
                }
            }
        }
        c.start(queue: .main)
        Task { @MainActor in
            try? await Task.sleep(for: delai)
            c.cancel()
            fin.appeler()
        }
    }
}
