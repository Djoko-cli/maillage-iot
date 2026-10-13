import HomeKit

/// Maison par HomeKit, pour le demon (`SourceMaison`, spec section 3.2) : le releve (noms, pieces, zones, fabricants,
/// noeuds Matter, batteries, identifiants), les changements (delegues des maisons et des accessoires ; pas la
/// joignabilite), et `identify()`. HomeKit ne dit pas sur quel fil il appelle ses delegues : tout passe par l'acteur
/// principal.
@MainActor
final class MaisonHomeKit: NSObject, SourceMaison, HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate {
    var surChangement: (@MainActor () -> Void)?
    private let gestionnaire = HMHomeManager()
    /// Maison a donne ses domiciles : avant `homeManagerDidUpdateHomes`, la liste est vide (HMHomeManager.h).
    private var maisonChargee = false
    /// Lectures des batteries : Maison repond depuis son cache (0,2 s pour 78 valeurs le 28/09) ; au-dela, le releve
    /// part avec les valeurs deja connues.
    static let delaiLectures: Duration = .seconds(5)

    override init() {
        super.init()
        gestionnaire.delegate = self
    }

    var acces: EtatPasseur.Acces {
        let s = gestionnaire.authorizationStatus
        if s.contains(.authorized) { return .autorise }
        if s.contains(.determined) { return .refuse }
        return .attente
    }

    func releve(batteries: Bool) async -> NomsMaison? {
        let s = gestionnaire.authorizationStatus
        guard s.contains(.authorized) else {
            return s.contains(.determined)
                ? NomsMaison(date: .now, statut: .refuse,
                             message: "Accès à Maison refusé : Réglages Système › Confidentialité et sécurité › Maison.")
                : nil
        }
        guard maisonChargee else { return nil }
        // Jamais un « ok » vide : il effacerait les noms gardes par l'app.
        guard !gestionnaire.homes.isEmpty else {
            return NomsMaison(date: .now, statut: .erreur, message: "Aucun domicile dans Maison")
        }
        if batteries { await lireBatteries() }
        // Les domiciles ont pu disparaitre pendant l'attente des lectures.
        guard !gestionnaire.homes.isEmpty else {
            return NomsMaison(date: .now, statut: .erreur, message: "Aucun domicile dans Maison")
        }
        return releveCourant()
    }

    func identifier(_ id: UUID) async -> IssueIdentifier {
        guard let a = gestionnaire.homes.flatMap(\.accessories).first(where: { $0.uniqueIdentifier == id }) else {
            return .inconnu
        }
        guard a.supportsIdentify else { return .nonIdentifiable }
        return await withCheckedContinuation { suite in
            a.identify { erreur in
                suite.resume(returning: erreur.map { .erreur($0.localizedDescription) } ?? .ok)
            }
        }
    }

    // MARK: Releve

    private func releveCourant() -> NomsMaison {
        let accessoires = gestionnaire.homes.flatMap(\.accessories).map { a in
            let b = Self.batterie(a)
            // Une tuile de Maison = un service interactif, hors informations d'accessoire et batterie.
            let tuiles = a.services.filter {
                $0.isUserInteractive && $0.serviceType != HMServiceTypeAccessoryInformation
                    && $0.serviceType != HMServiceTypeBattery
            }.map(\.name)
            return AccessoireMaison(nom: NomAccessoire.affiche(accessoire: a.name, tuiles: tuiles),
                                    piece: a.room?.name, fabricant: a.manufacturer, modele: a.model,
                                    firmware: a.firmwareVersion, categorie: a.category.localizedDescription,
                                    noeudMatter: AccessoireMaison.noeud(a.matterNodeID),
                                    pont: a.category.categoryType == HMAccessoryCategoryTypeBridge ? true : nil,
                                    batterie: b.flatMap {
                                        BatterieMaison.depuisHomeKit(niveau: $0.niveau?.value, charge: $0.charge?.value,
                                                                     alerte: $0.alerte?.value)
                                    },
                                    id: a.uniqueIdentifier.uuidString)
        }
        // Zones et pieces dans l'ordre de Maison.
        let zones = gestionnaire.homes.flatMap(\.zones).map { ZoneMaison(nom: $0.name, pieces: $0.rooms.map(\.name)) }
        let domicile = gestionnaire.homes.map(\.name).joined(separator: " + ")
        return NomsMaison(date: .now, statut: .ok, domicile: domicile.isEmpty ? nil : domicile,
                          accessoires: DemonPasseur.ordonner(accessoires), zones: zones)
    }

    /// Service Batterie d'un accessoire : niveau, etat de charge, alerte.
    private static func batterie(_ a: HMAccessory)
        -> (niveau: HMCharacteristic?, charge: HMCharacteristic?, alerte: HMCharacteristic?)? {
        guard let s = a.services.first(where: { $0.serviceType == HMServiceTypeBattery }) else { return nil }
        func c(_ type: String) -> HMCharacteristic? { s.characteristics.first { $0.characteristicType == type } }
        return (c(HMCharacteristicTypeBatteryLevel), c(HMCharacteristicTypeChargingState),
                c(HMCharacteristicTypeStatusLowBattery))
    }

    /// Relit les batteries ; rend la main a la derniere lecture, ou apres `delaiLectures`.
    private func lireBatteries() async {
        let caracteristiques = gestionnaire.homes.flatMap(\.accessories).compactMap(Self.batterie)
            .flatMap { [$0.niveau, $0.charge, $0.alerte].compactMap { $0 } }
        guard !caracteristiques.isEmpty else { return }
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let fin = UneFois { suite.resume() }
            let restantes = Compteur(caracteristiques.count)
            for c in caracteristiques {
                c.readValue { @Sendable _ in
                    Task { @MainActor in
                        if restantes.retirer() == 0 { fin.appeler() }
                    }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: Self.delaiLectures)
                fin.appeler()
            }
        }
    }

    // MARK: Changements

    /// Les maisons et les accessoires ont ce suivi pour delegue (les nouveaux aussi) ; puis le demon est prevenu.
    private func changer() {
        for h in gestionnaire.homes {
            h.delegate = self
            for a in h.accessories { a.delegate = self }
        }
        surChangement?()
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.maisonChargee = true
            self.changer()
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            journal.notice("autorisation de Maison : \(status.rawValue)")
            self.changer()
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { Task { @MainActor in self.changer() } }
    nonisolated func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { Task { @MainActor in self.changer() } }
    nonisolated func homeManagerDidUpdatePrimaryHome(_ manager: HMHomeManager) { Task { @MainActor in self.changer() } }

    nonisolated func homeDidUpdateName(_ home: HMHome) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didAdd accessory: HMAccessory) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didRemove accessory: HMAccessory) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) {
        Task { @MainActor in self.changer() }
    }
    nonisolated func home(_ home: HMHome, didAdd room: HMRoom) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didRemove room: HMRoom) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didUpdateNameFor room: HMRoom) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didAdd zone: HMZone) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didRemove zone: HMZone) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didUpdateNameFor zone: HMZone) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didAdd room: HMRoom, to zone: HMZone) { Task { @MainActor in self.changer() } }
    nonisolated func home(_ home: HMHome, didRemove room: HMRoom, from zone: HMZone) {
        Task { @MainActor in self.changer() }
    }

    nonisolated func accessoryDidUpdateName(_ accessory: HMAccessory) { Task { @MainActor in self.changer() } }
    nonisolated func accessoryDidUpdateServices(_ accessory: HMAccessory) { Task { @MainActor in self.changer() } }
    nonisolated func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService) {
        Task { @MainActor in self.changer() }
    }
}

/// Compte a rebours des lectures de batteries.
@MainActor
private final class Compteur {
    private var restant: Int

    init(_ n: Int) {
        restant = n
    }

    /// Une de moins ; rend ce qui reste.
    func retirer() -> Int {
        restant -= 1
        return restant
    }
}
