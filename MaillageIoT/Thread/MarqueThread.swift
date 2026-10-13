import AppKit

/// Le symbole de Thread (le « T » dont la tige s'enroule), le badge de l'icone de la barre des menus (demande de Djoko
/// du 08/10). Trace du logo de Thread Group (Wikimedia Commons, `Thread_Group_wordmark.svg`, domaine public ; Thread
/// est une marque du Thread Group), ramene a une hauteur de 1, y vers le bas : 0,79 de large.
enum MarqueThread {
    /// Largeur du symbole pour une hauteur de 1.
    static let proportion: CGFloat = 0.79

    /// Le trace, refait a chaque appel (un `CGPath` ne se partage pas entre fils d'execution).
    static var trace: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.5384, y: 1.0000))
        p.addLine(to: CGPoint(x: 0.4136, y: 1.0000))
        p.addLine(to: CGPoint(x: 0.4136, y: 0.3761))
        p.addLine(to: CGPoint(x: 0.2261, y: 0.3761))
        p.addCurve(to: CGPoint(x: 0.1249, y: 0.4773), control1: CGPoint(x: 0.1705, y: 0.3761), control2: CGPoint(x: 0.1249, y: 0.4215))
        p.addCurve(to: CGPoint(x: 0.2261, y: 0.5783), control1: CGPoint(x: 0.1249, y: 0.5329), control2: CGPoint(x: 0.1705, y: 0.5783))
        p.addLine(to: CGPoint(x: 0.2261, y: 0.7032))
        p.addCurve(to: CGPoint(x: 0.0000, y: 0.4773), control1: CGPoint(x: 0.1014, y: 0.7032), control2: CGPoint(x: 0.0000, y: 0.6019))
        p.addCurve(to: CGPoint(x: 0.2261, y: 0.2513), control1: CGPoint(x: 0.0000, y: 0.3526), control2: CGPoint(x: 0.1015, y: 0.2513))
        p.addLine(to: CGPoint(x: 0.4136, y: 0.2513))
        p.addLine(to: CGPoint(x: 0.4136, y: 0.1881))
        p.addCurve(to: CGPoint(x: 0.6017, y: 0.0000), control1: CGPoint(x: 0.4136, y: 0.0844), control2: CGPoint(x: 0.4979, y: 0.0000))
        p.addCurve(to: CGPoint(x: 0.7896, y: 0.1881), control1: CGPoint(x: 0.7053, y: 0.0000), control2: CGPoint(x: 0.7896, y: 0.0844))
        p.addCurve(to: CGPoint(x: 0.6017, y: 0.3761), control1: CGPoint(x: 0.7896, y: 0.2917), control2: CGPoint(x: 0.7053, y: 0.3761))
        p.addLine(to: CGPoint(x: 0.5384, y: 0.3761))
        p.addLine(to: CGPoint(x: 0.5384, y: 1.0000))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.5384, y: 0.2513))
        p.addLine(to: CGPoint(x: 0.6018, y: 0.2513))
        p.addCurve(to: CGPoint(x: 0.6648, y: 0.1881), control1: CGPoint(x: 0.6366, y: 0.2513), control2: CGPoint(x: 0.6648, y: 0.2229))
        p.addCurve(to: CGPoint(x: 0.6018, y: 0.1249), control1: CGPoint(x: 0.6648, y: 0.1532), control2: CGPoint(x: 0.6366, y: 0.1249))
        p.addCurve(to: CGPoint(x: 0.5384, y: 0.1881), control1: CGPoint(x: 0.5668, y: 0.1249), control2: CGPoint(x: 0.5384, y: 0.1532))
        p.closeSubpath()
        return p
    }

    /// Le symbole dans `r` (de la hauteur de `r`), dans un contexte y vers le haut, de la couleur `c` ; avec
    /// `detourage`, la silhouette elargie de ce nombre de points est d'abord effacee.
    static func dessiner(_ ctx: CGContext, dans r: CGRect, couleur c: NSColor, detourage: CGFloat = 0) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: r.height, y: -r.height)
        if detourage > 0 {
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(trace)
            ctx.setLineWidth(2 * detourage / r.height)
            ctx.setLineJoin(.round)
            ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
        }
        ctx.addPath(trace)
        ctx.setFillColor(c.cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }
}
