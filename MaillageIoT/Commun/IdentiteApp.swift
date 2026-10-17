import Foundation

/// L'identite de l'app qui tourne : l'app publiee (`fr.djoko.maillage.iot`) ou l'app de repetition (« Maillage IoT
/// Repetition », `fr.djoko.maillage.iot.repetition`, cible a part de project.yml, jamais publiee). La repetition de la reprise
/// (phase 4, tache 8) se fait dans cette seconde app, a cote de la vraie : son conteneur (donc ses fichiers et ses
/// preferences, qui suivent l'identifiant du bundle), ses notifications et son ouverture de session sont les siens ; reste
/// le trousseau du Mac, partage entre toutes les apps, ou elle range ses elements sous des services suffixes.
///
/// Tout ce que l'app ECRIT dans le trousseau passe par cette identite, jamais par un identifiant ecrit en dur : les
/// services viennent de l'identifiant du bundle (sans le suffixe de la repetition) et du suffixe (`MaillageSuffixeServices`
/// dans l'Info.plist, vide pour l'app publiee). Les services des ANCIENNES apps (`TrousseauReprisThread.serviceAncien`,
/// `TrousseauRepris.servicePontAncien` et `.serviceSondeAncien`) n'en dependent pas : la repetition doit justement tester
/// leur reprise, et ne les lit que (jamais modifies ni effaces).
struct IdentiteApp: Equatable, Sendable {
    /// La cle de l'Info.plist qui porte le suffixe des services de trousseau (absente ou vide : l'app publiee).
    static let cleSuffixe = "MaillageSuffixeServices"
    /// Le seul identifiant de l'app publiee ecrit dans le code : le repli d'un bundle sans identifiant (jamais en pratique,
    /// un bundle d'app en a toujours un). Aucun chemin d'ecriture ne le lit tant que le bundle a le sien.
    static let identifiantPublie = "fr.djoko.maillage.iot"

    /// L'identifiant du bundle.
    let identifiant: String
    /// Ajoute a chaque service de trousseau ecrit par l'app ; vide pour l'app publiee, `.repetition` pour la repetition.
    let suffixeServices: String
    /// Le nom de l'app (libelle des elements du trousseau).
    let nom: String

    init(identifiant: String, suffixeServices: String, nom: String) {
        self.identifiant = identifiant
        self.suffixeServices = suffixeServices
        self.nom = nom
    }

    init(bundle: Bundle) {
        let affiche = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let suffixe = bundle.object(forInfoDictionaryKey: Self.cleSuffixe) as? String
        self.init(identifiant: bundle.bundleIdentifier ?? Self.identifiantPublie, suffixeServices: suffixe ?? "",
                  nom: affiche ?? "Maillage IoT")
    }

    /// Celle de l'app qui tourne.
    static let courante = IdentiteApp(bundle: .main)

    var estRepetition: Bool { !suffixeServices.isEmpty }

    /// L'identifiant sans le suffixe : la racine commune de l'app publiee et de sa repetition.
    private var racine: String {
        !suffixeServices.isEmpty && identifiant.hasSuffix(suffixeServices) ? String(identifiant.dropLast(suffixeServices.count))
            : identifiant
    }

    private func service(_ role: String) -> String { "\(racine).\(role)\(suffixeServices)" }

    /// Les cles des sondes Thread (compte = nom d'hote de la sonde), des sondes Zigbee (compte = adresse longue) et des ponts
    /// Hue (compte = identifiant du pont), que l'app ecrit.
    var serviceSondeThread: String { service("sonde-thread") }
    var serviceSondeZigbee: String { service("sonde-zigbee") }
    var servicePontHue: String { service("pont-hue") }

    // MARK: Les trousseaux de l'app

    /// La sonde Thread : ses cles sous le service de l'app, reprises une fois de celui de Maillage Thread.
    func trousseauThread() -> TrousseauReprisThread {
        TrousseauReprisThread(actuel: TrousseauSystemeThread(service: serviceSondeThread, nomApp: nom),
                              ancien: TrousseauSystemeThread(service: TrousseauReprisThread.serviceAncien, nomApp: nom),
                              reprises: .preferences(cle: MemoireReprises.cleSondeThread))
    }

    /// La sonde Zigbee, reprise de Maillage Zigbee.
    func trousseauSondeZigbee() -> TrousseauRepris {
        TrousseauRepris(actuel: CheminSonde.trousseau(identite: self),
                        ancien: TrousseauSystemeZigbee(service: TrousseauRepris.serviceSondeAncien),
                        reprises: .preferences(cle: MemoireReprises.cleSondeZigbee))
    }

    /// Le pont Hue, repris de Maillage Zigbee.
    func trousseauPontHue() -> TrousseauRepris {
        TrousseauRepris(actuel: TrousseauSystemeZigbee.pont(identite: self),
                        ancien: TrousseauSystemeZigbee(service: TrousseauRepris.servicePontAncien),
                        reprises: .preferences(cle: MemoireReprises.clePontZigbee))
    }
}
