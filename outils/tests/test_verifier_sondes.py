"""Tests de outils/verifier_sondes.py : des arbres de sources Swift inventes, deux sondes.

  python3 -m unittest discover -s outils/tests
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import verifier_sondes  # noqa: E402

PRINCIPAL = """
final class SondeMaillage%(P)s {
    private(set) var essai = 0
    var etat: Etat = .sansSonde
    var acces: Acces?
    var reglage: Reglage = .automatique {
        didSet { }
    }
    var ports: [Port] { portsVus }
    @ObservationIgnored var surMaillage: (() -> Void)?
    @ObservationIgnored let ouvrirCanal: (String) -> Canal
}
"""
USB = """
extension SondeMaillage%(P)s {
    func connecter(_ port: Port) {
        guard ouvrable(port) else { return }
        let c = ouvrirCanal(port.chemin)
        etat = .connexion
    }
    private func ouvrable(_ port: Port) -> Bool { true }
}
"""


def arbre(supplements=None, listes=None):
    d = tempfile.mkdtemp()
    fichiers = {}
    for p in ("Thread", "Zigbee"):
        base = "MaillageIoT/%s/Sonde/SondeMaillage%s" % (p, p)
        fichiers[base + ".swift"] = PRINCIPAL % {"P": p}
        fichiers[base + "+USB.swift"] = USB % {"P": p}
    fichiers.update(supplements or {})
    for rel, texte in fichiers.items():
        chemin = os.path.join(d, rel)
        os.makedirs(os.path.dirname(chemin), exist_ok=True)
        with open(chemin, "w") as f:
            f.write(texte)
    return d


class Garde(unittest.TestCase):
    def setUp(self):
        self._propres = {s: list(v) for s, v in verifier_sondes.PROPRIETES.items()}
        self._exemptees = {s: set(v) for s, v in verifier_sondes.EXEMPTEES.items()}
        verifier_sondes.PROPRIETES = {"Thread": ["etat", "acces", "reglage"], "Zigbee": ["etat", "acces", "reglage"]}
        verifier_sondes.EXEMPTEES = {"Thread": set(), "Zigbee": set()}

    def tearDown(self):
        verifier_sondes.PROPRIETES = self._propres
        verifier_sondes.EXEMPTEES = self._exemptees

    def test_arbre_propre(self):
        self.assertEqual(verifier_sondes.controler(arbre()), [])

    def test_affectation_par_un_recepteur_de_sonde_refusee(self):
        for ligne in ("sonde.etat = .absente", "sondeThread.acces = nil", "sondeZigbee.etat = .connexion",
                      "self.sonde.etat = .absente", "s.laSonde?.reglage = .usb", "sonde.acces == nil ? 1 : 2; sonde.etat += 1"):
            d = arbre({"MaillageIoTTests/Faux.swift": "func f() {\n    %s\n}\n" % ligne})
            defauts = verifier_sondes.controler(d)
            self.assertEqual(len(defauts), 1, ligne)
            self.assertIn("MaillageIoTTests/Faux.swift:2", defauts[0])

    def test_recepteur_declare_avec_le_type_de_la_sonde(self):
        d = arbre({"MaillageIoT/Vues/Faux.swift": "struct V { let mienne: SondeMaillageZigbee\n func f() { mienne.etat = .absente } }\n"})
        self.assertEqual(len(verifier_sondes.controler(d)), 1)
        d = arbre({"MaillageIoTTests/Faux.swift": "func f() { let x = SondeMaillageThread(actif: false)\n x.acces = nil }\n"})
        self.assertEqual(len(verifier_sondes.controler(d)), 1)

    def test_ajout_a_une_collection_refuse(self):
        verifier_sondes.PROPRIETES["Thread"].append("annonces")
        d = arbre({"MaillageIoTTests/Faux.swift": "func f() { sonde.annonces.insert(\"a\") }\n"})
        self.assertEqual(len(verifier_sondes.controler(d)), 2)  # liste / source (annonces non declaree) et ecriture

    def test_lectures_comparaisons_et_autres_recepteurs_acceptes(self):
        d = arbre({"MaillageIoTTests/Bon.swift": """
func f() {
    #expect(sonde.etat == .absente)
    let x = sonde.acces
    thread.etat = .absente
    s.thread.actif = true
    sonde.autre = 1
    // sonde.etat = .absente
    let t = "sonde.etat = 1"
}
"""})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_affectation_dans_les_fichiers_de_la_sonde_acceptee(self):
        d = arbre({"MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee+Tournees.swift":
                   "extension SondeMaillageZigbee {\n    func f() { sonde.etat = .absente }\n}\n"})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_ouverture_de_port_hors_du_fichier_usb_refusee(self):
        for appel in ("let c = ouvrirCanal(chemin)", "if ouvrable(port, choisi: true) { }"):
            d = arbre({"MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee+Chemin.swift":
                       "extension SondeMaillageZigbee {\n    func f() { %s }\n}\n" % appel})
            defauts = verifier_sondes.controler(d)
            self.assertEqual(len(defauts), 1, appel)
            self.assertIn("+Chemin.swift:2", defauts[0])
        d = arbre({"MaillageIoTTests/Faux.swift": "func f() { _ = ouvrirCanal(\"/dev/x\") }\n"})
        self.assertEqual(len(verifier_sondes.controler(d)), 1)

    def test_etiquette_et_declaration_ne_sont_pas_des_appels(self):
        d = arbre({"MaillageIoTTests/Bon.swift": "let s = SondeMaillageThread(actif: false, ouvrirCanal: { _ in c })\n"})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_liste_perimee_et_var_non_listee(self):
        verifier_sondes.PROPRIETES["Thread"] = ["etat", "acces", "reglage", "disparue"]
        defauts = verifier_sondes.controler(arbre())
        self.assertEqual(len(defauts), 1)
        self.assertIn("disparue", defauts[0])
        verifier_sondes.PROPRIETES["Thread"] = ["etat", "acces"]
        defauts = verifier_sondes.controler(arbre())
        self.assertEqual(len(defauts), 1)
        self.assertIn("var reglage", defauts[0])
        verifier_sondes.EXEMPTEES["Thread"] = {"reglage"}
        self.assertEqual(verifier_sondes.controler(arbre()), [])

    def test_principal_absent(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "MaillageIoT"))
        self.assertEqual(len(verifier_sondes.controler(d)), 2)


if __name__ == "__main__":
    unittest.main()
