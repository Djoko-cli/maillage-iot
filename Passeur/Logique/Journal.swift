import os

/// Journal du demon, a lire avec
/// `/usr/bin/log show --last 1h --predicate 'subsystem == "fr.djoko.maillage.passeur"'` (en zsh, `log` seul est une
/// commande interne). Jamais un nom de Maison, ni un UUID d'accessoire, ni le jeton : des raisons, des nombres et des
/// erreurs. `privacy: .public` pour les textes, sinon le journal les masque.
let journal = Logger(subsystem: "fr.djoko.maillage.passeur", category: "demon")
