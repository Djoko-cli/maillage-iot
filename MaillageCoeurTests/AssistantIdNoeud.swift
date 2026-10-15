@testable import MaillageCoeur

/// Assistants des tests (sans test ni suite, partages par toutes les cibles de test) : un identifiant de noeud d'apres
/// sa cle. `idt` : Thread, ou le protocole donne (`idt("a", .zigbee)`) ; `idz` : Zigbee.
func idt(_ cle: String, _ protocole: Protocole = .thread) -> IdNoeud { IdNoeud(protocole, cle) }
func idz(_ cle: String) -> IdNoeud { IdNoeud(.zigbee, cle) }
