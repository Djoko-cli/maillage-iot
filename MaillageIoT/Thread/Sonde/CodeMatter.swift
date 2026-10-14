import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Code Matter de la sonde (message `bonjour`) : code d'appairage manuel et QR code.
enum CodeMatter {
    /// Code d'appairage manuel mis en forme comme Matter l'affiche : 4-3-4 pour 11
    /// chiffres, 4-3-4-5-5 pour 21 ; tel quel sinon (deja mis en forme, autre longueur).
    static func formater(_ code: String) -> String {
        guard code.allSatisfy({ ("0"..."9").contains($0) }) else { return code }
        let tailles: [Int]
        switch code.count {
        case 11: tailles = [4, 3, 4]
        case 21: tailles = [4, 3, 4, 5, 5]
        default: return code
        }
        var reste = Substring(code)
        var morceaux: [Substring] = []
        for t in tailles {
            morceaux.append(reste.prefix(t))
            reste = reste.dropFirst(t)
        }
        return morceaux.joined(separator: "-")
    }

    /// QR code d'une charge « MT:... » : un pixel par module, noir sur blanc, a agrandir
    /// sans lissage ; nil si CoreImage ne le forme pas.
    static func imageQR(_ charge: String) -> CGImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(charge.utf8)
        filtre.correctionLevel = "M"
        guard let sortie = filtre.outputImage else { return nil }
        return CIContext().createCGImage(sortie, from: sortie.extent)
    }
}
