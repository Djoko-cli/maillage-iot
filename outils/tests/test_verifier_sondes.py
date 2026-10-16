"""Tests de outils/verifier_sondes.py : des arbres de sources Swift inventes, deux sondes.

  python3 -m unittest discover -s outils/tests
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import verifier_sondes  # noqa: E402

_TEMPORAIRES = []


def tearDownModule():
    for d in _TEMPORAIRES:
        shutil.rmtree(d, ignore_errors=True)


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
    @ObservationIgnored var boucle: Task<Void, Never>?
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
    _TEMPORAIRES.append(d)
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
        self._poignees = {s: list(v) for s, v in getattr(verifier_sondes, "POIGNEES", {}).items()}
        verifier_sondes.POIGNEES = {"Thread": ["boucle"], "Zigbee": ["boucle"]}

    def tearDown(self):
        verifier_sondes.POIGNEES = self._poignees
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
        _TEMPORAIRES.append(d)
        os.makedirs(os.path.join(d, "MaillageIoT"))
        self.assertEqual(len(verifier_sondes.controler(d)), 2)

    def _un_defaut(self, supplements, ligne=None):
        defauts = verifier_sondes.controler(arbre(supplements))
        self.assertEqual(len(defauts), 1, defauts)
        if ligne:
            self.assertIn(ligne, defauts[0])

    def test_sonde_obtenue_par_une_fabrique_refusee(self):
        for fabrique, appel in (
                ("func faire() -> SondeMaillageThread { fab() }", "let s = faire()"),
                ("func faire() -> SondeMaillageThread { fab() }", "let s = try faire()"),
                ("func faire(a: Int) async throws -> SondeMaillageZigbee { fab() }", "let s = try await faire(a: 1)"),
                ("static func faire() -> SondeMaillageZigbee { fab() }", "let s = try? await Self.faire()"),
                ("static func faire() -> SondeMaillageZigbee { fab() }", "var s = SondeReseauTests.faire()"),
                ("func faire() -> SondeMaillageThread? { nil }", "if let s = faire() {\n        s.etat = .absente\n    }"),
                ("func faire() -> SondeMaillageThread { fab() }", "guard let s = Self.faire() else { return }"),
                ("let relancee: @MainActor () -> SondeMaillageZigbee", "let s = relancee()"),
                ("func faire(_ f: @MainActor () -> SondeMaillageThread) { }", "let s = f()"),
                ("func faire() -> SondeMaillageThread { fab() }", "let s =\n        faire()")):
            suite = "" if "etat" in appel else "\n    s.etat = .absente"
            texte = "struct T {\n    %s\n    func f() {\n    %s%s\n    }\n}\n" % (fabrique, appel, suite)
            defauts = verifier_sondes.controler(arbre({"MaillageIoTTests/Faux.swift": texte}))
            self.assertEqual(len(defauts), 1, (appel, defauts))

    def test_fabrique_declaree_dans_un_autre_fichier(self):
        self._un_defaut({
            "MaillageIoTTests/Outils.swift": "enum Outils { static func faire() -> SondeMaillageZigbee { fab() } }\n",
            "MaillageIoTTests/Faux.swift": "func f() {\n    let s = Outils.faire()\n    s.acces = nil\n}\n"},
            "MaillageIoTTests/Faux.swift:3")

    def test_sonde_obtenue_par_un_tuple_refusee(self):
        base = "func faire() -> (SondeMaillageZigbee, Canal) { fab() }\nfunc g() async throws {\n    %s\n    %s\n}\n"
        for lie, ecrit in (("let (s, _) = faire()", "s.etat = .absente"),
                           ("let (s, c) = try await faire()", "s.etat = .absente"),
                           ("var (s, c) = try! faire()", "s.acces = nil")):
            self._un_defaut({"MaillageIoTTests/Faux.swift": base % (lie, ecrit)}, "Faux.swift:4")
        etiquete = "func faire() -> (canal: Canal, sonde: SondeMaillageThread) { fab() }\nfunc g() {\n    let (c, p) = faire()\n    p.etat = .absente\n}\n"
        self._un_defaut({"MaillageIoTTests/Faux.swift": etiquete}, "Faux.swift:4")
        # le membre qui n'est pas une sonde reste libre
        sans = "func faire() -> (SondeMaillageZigbee, Canal) { fab() }\nfunc g() {\n    let (s, c) = faire()\n    c.etat = .absente\n    let (p, domaine) = try Reglages.preferences()\n    p.etat = 1\n}\n"
        self.assertEqual(verifier_sondes.controler(arbre({"MaillageIoTTests/Bon.swift": sans})), [])

    def test_alias_et_conversion_de_type(self):
        self._un_defaut({"MaillageIoTTests/Faux.swift": "func f() {\n    let s = self.sonde\n    s.etat = .absente\n}\n"},
                        "Faux.swift:3")
        self._un_defaut({"MaillageIoTTests/Faux.swift": "func f(x: Any) {\n    let s = x as! SondeMaillageThread\n    s.etat = .absente\n}\n"},
                        "Faux.swift:3")

    def test_fabriques_et_recepteurs_sans_rapport_acceptes(self):
        d = arbre({"MaillageIoTTests/Bon.swift": """
func connectee(_ s: SondeMaillageThread) -> Bool { true }
func autre() -> SondeMaillageThread.Liaison { .usb }
func f() {
    let a = autre()
    a.etat = .absente
    let b = connectee(sonde)
    b.etat = true
    let c = sonde.etat
    c.acces = nil
}
"""})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_extension_de_la_sonde_hors_de_ses_fichiers_refusee(self):
        for rel, texte in (
                ("MaillageIoT/Thread/Vues/X.swift", "extension SondeMaillageThread {\n    func f() { etat = .absente }\n}\n"),
                ("MaillageIoT/Vues/X.swift", "extension SondeMaillageZigbee: Truc {\n}\n"),
                ("MaillageIoTTests/X.swift", "@MainActor extension SondeMaillageThread {\n}\n"),
                ("MaillageIoT/Thread/Sonde/Autre.swift", "extension  SondeMaillageThread {\n}\n"),
                ("MaillageIoT/Thread/Sonde/SondeMaillageThreadX.swift", "extension SondeMaillageThread {\n}\n"),
                ("MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee+Cycle.swift", "extension SondeMaillageThread {\n}\n")):
            defauts = verifier_sondes.controler(arbre({rel: texte}))
            self.assertEqual(len(defauts), 1, rel)
            self.assertIn(rel, defauts[0])
            self.assertIn("extension", defauts[0])

    def test_extensions_acceptees(self):
        d = arbre({
            "MaillageIoT/Thread/Sonde/SondeMaillageThread+Cycle.swift": "extension SondeMaillageThread {\n}\n",
            "MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee+Affichage.swift": "extension SondeMaillageZigbee {\n}\n",
            "MaillageIoT/Thread/Sonde/CheminLiaison.swift": "extension SondeMaillageThread.Liaison {\n}\n",
            "MaillageIoTTests/X.swift": "extension SondeMaillageThreadTests {\n}\n// extension SondeMaillageThread {\n"})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_poignees_de_taches_gardees(self):
        for ligne in ("sonde.boucle = nil", "sondeThread.boucle = Task { }", "s.laSonde?.boucle = nil"):
            self._un_defaut({"MaillageIoTTests/Faux.swift": "func f() {\n    %s\n}\n" % ligne}, "Faux.swift:2")
        self._un_defaut({"MaillageIoTTests/Faux.swift": "func f(p: SondeMaillageZigbee) {\n    p.boucle = nil\n}\n"}, "Faux.swift:2")
        d = arbre({"MaillageIoT/Thread/Sonde/SondeMaillageThread+Cycle.swift":
                   "extension SondeMaillageThread {\n    func f() { boucle = nil; sonde.boucle = nil }\n}\n"})
        self.assertEqual(verifier_sondes.controler(d), [])

    def test_poignee_perimee(self):
        verifier_sondes.POIGNEES["Thread"] = ["boucle", "disparue"]
        defauts = verifier_sondes.controler(arbre())
        self.assertEqual(len(defauts), 1)
        self.assertIn("disparue", defauts[0])


if __name__ == "__main__":
    unittest.main()
