import Foundation
@testable import MaillageCoeur

/// Petit reseau Thread de test, construit a la main.
struct Banc {
    var date: Date
    var routeurs: [AnnonceService] = []
    var matter: [AnnonceService] = []
    var hap: [AnnonceService] = []
    var adresses: [String: [String]] = [:]
    var routes: [RouteIPv6] = []
    var locaux: [String] = ["fd4b:36a2:b7fe:200b::/64"]

    init(date: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        self.date = date
    }

    /// Routeur de bordure ; `role` nil : Thread 1.3 (role inconnu) ; `xa` : son ExtMac.
    mutating func routeur(_ nom: String, partition: String = "73586B68", role: RoleThread? = .routeur,
                          primaire: Bool = false, lien: String, omr: String? = nil,
                          xp: String = "4B36A2B7FEFB200B", nn: String = "MyHome1482620090", xa: String? = nil) {
        let bitsRole: UInt32 = switch role {
        case .detache?: 0
        case .enfant?: 1
        case .routeur?: 2
        case .chef?: 3
        case nil: 0
        }
        let sb: UInt32 = 0x01 | 0x10 | 0x20 | 0x80 | (primaire ? 0x100 : 0) | bitsRole << 9
        var txt: [String: Data] = [
            "nn": Data(nn.utf8), "xp": Data(hexa: xp)!, "tv": Data((role == nil ? "1.3.0" : "1.4.0").utf8),
            "pt": Data(hexa: partition)!, "sb": Data(withUnsafeBytes(of: sb.bigEndian) { Array($0) }),
            "at": Data([0x00, 0x00, 0x66, 0xCE, 0xC7, 0x00, 0x00, 0x00]),
        ]
        if let omr, let p = PrefixeIPv6(omr) { txt["omr"] = Data([64] + p.octets) }
        if let xa { txt["xa"] = Data(hexa: xa)! }
        let hote = nom.replacingOccurrences(of: " ", with: "-") + ".local"
        routeurs.append(AnnonceService(instance: nom, hote: hote, port: 49153, txt: ChampsTXT(txt)))
        adresses[hote] = [lien]
    }

    /// Appareil Matter present sur une ou plusieurs fabriques.
    mutating func appareil(_ id: String, noeud: Int = 1, fabriques: [String] = ["30FC8F95E0E1A385"],
                           adresses liste: [String], sii: Int? = nil) {
        let hote = id + ".local"
        for f in fabriques {
            var txt: [String: Data] = [:]
            if let sii { txt["SII"] = Data(String(sii).utf8) }
            matter.append(AnnonceService(instance: f + "-" + String(format: "%016X", noeud), hote: hote,
                                         port: 5540, txt: ChampsTXT(txt)))
        }
        adresses[hote] = liste
    }

    /// Retire un appareil (toutes ses instances et ses adresses).
    mutating func retirer(_ id: String) {
        matter.removeAll { $0.hote == id + ".local" }
        hap.removeAll { $0.hote == id + ".local" }
        adresses[id + ".local"] = nil
    }

    mutating func route(_ prefixe: String, via lien: String) {
        routes.append(RouteIPv6(prefixe: prefixe, passerelle: lien, interface: "en0"))
    }

    var annonces: Annonces {
        Annonces(date: date, routeurs: routeurs, matter: matter, hap: hap, adresses: adresses,
                 routes: routes, prefixesLocaux: locaux)
    }
}

/// Captures reelles enregistrees par l'app, lues dans le depot (`docs/releves/2026-09-28/`).
enum Captures {
    static let dossier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageCoeurTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/releves/2026-09-28")

    static func annonces(_ fichier: String) throws -> Annonces {
        try CodageJSON.decodeur().decode(Annonces.self, from: Data(contentsOf: dossier.appendingPathComponent(fichier)))
    }
}

/// Capture anonymisee de la sonde (`docs/releves/2026-09-29/capture-sonde.jsonl`) :
/// un message par ligne, tel que la sonde l'a envoye, avec l'heure de reception.
enum CaptureSonde {
    static let fichier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageCoeurTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/releves/2026-09-29/capture-sonde.jsonl")

    /// Les lignes JSON, dans l'ordre.
    static func lignes() throws -> [String] {
        try String(contentsOf: fichier, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    /// TLV (hexa) de la reponse `diag` d'identifiant `id`.
    static func tlv(_ id: Int) throws -> String {
        for l in try lignes() {
            guard let m = try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any] else { continue }
            if m["t"] as? String == "diag", m["id"] as? Int == id, let t = m["tlv"] as? String { return t }
        }
        throw ErreurCapture(id: id)
    }

    struct ErreurCapture: Error {
        let id: Int
    }
}
