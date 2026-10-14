import Foundation
import MaillageCoeur

/// Nom affiche d'un noeud, par priorite : surnom (donne dans l'app) > nom de l'appareil sur le pont > l'adresse longue.
/// Un noeud se nomme par son adresse longue (IEEE), qui ne change pas : les surnoms sont gardes sous elle.
public struct ResolveurNomsZigbee: Hashable, Sendable {
    /// Adresse longue -> surnom.
    public var surnoms: [String: String]
    public var maison: NomsZigbee?

    public init(surnoms: [String: String] = [:], maison: NomsZigbee? = nil) {
        self.surnoms = surnoms
        self.maison = maison
    }

    /// L'appareil du pont d'adresse longue `ieee` ; nil si le pont ne le connait pas.
    public func accessoire(ieee: String) -> AppareilPont? {
        maison?.accessoire(ieee: ieee)
    }

    /// Le surnom, sinon le nom sur le pont ; nil s'il n'a ni l'un ni l'autre.
    public func nomConnu(ieee: String) -> String? {
        if let s = surnoms[ieee], !s.isEmpty { return s }
        if let m = accessoire(ieee: ieee)?.nom, !m.isEmpty { return m }
        return nil
    }

    /// Le surnom, sinon le nom sur le pont, sinon l'adresse longue.
    public func nom(ieee: String) -> String { nomConnu(ieee: ieee) ?? ieee }
}
