import Foundation

/// Acces au canal refuses d'un enfant, tires de ses compteurs MAC (TLV 9) entre deux releves (spec de la sonde
/// tout-en-un, section 2.3) : Δ `ifOutErrors` / Δ `ifOutUcastPkts`. Dans OpenThread, `ifOutErrors` compte les echecs
/// d'acces au canal (CCA, a chaque tentative d'envoi), pas les accuses manquants ni les reprises : le taux dit
/// l'occupation du canal autour de l'enfant, pas la qualite de son lien avec son parent. La fiche le montre a titre
/// d'information ; il ne donne aucune qualite (decision de Djoko du 07/10) : sous un routeur Apple, la qualite de
/// l'enfant reste inconnue.
public enum AccesCanal {
    /// Trames envoyees entre deux releves, au moins : en deca, pas de taux.
    public static let tramesMin: UInt32 = 50

    /// Le taux entre deux releves ; nil si moins de `tramesMin` trames sont parties entre les deux, ou si un compteur a
    /// baisse (l'appareil a redemarre : le releve repart de zero).
    public static func taux(avant: CompteursMac, apres: CompteursMac) -> Double? {
        guard apres.unicastEmis >= avant.unicastEmis, apres.erreursEmises >= avant.erreursEmises else { return nil }
        let envois = apres.unicastEmis - avant.unicastEmis
        guard envois >= tramesMin else { return nil }
        return Double(apres.erreursEmises - avant.erreursEmises) / Double(envois)
    }
}
