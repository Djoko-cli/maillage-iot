"""Tests de outils/noms_publics.py : des sources Swift inventes, deux modules et un coeur.

  python3 -m unittest discover -s outils/tests
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import noms_publics  # noqa: E402


def dossier(fichiers):
    d = tempfile.mkdtemp()
    for nom, texte in fichiers.items():
        with open(os.path.join(d, nom), "w") as f:
            f.write(texte)
    return d


COEUR = """
public struct Graphe {
    public struct Noeud {
        public var extMac: String?
        public init(id: String, genre: Int, partition: String, routeur: Bool,
                    extMac: String? = nil) {
            self.extMac = extMac
        }
    }
    public init(noeuds: [Noeud], liens: [Int] = []) {}
}
"""


class MembresDExtension(unittest.TestCase):
    def test_init_public_a_etiquettes_multiples(self):
        d = dossier({"a.swift": """
public extension Graphe.Noeud {
    /// commentaire { avec une accolade
    init(id: String, genre: Int, routeur: Bool, extMac: String? = nil) { self.init(id: id) }
    private func cache() {}
    func visible(_ x: Int, pour y: Int) -> Int { x }
    static let valeur = "a { b"
    @discardableResult
    func marque(avec: Int) -> Int { avec }
}
"""})
        self.assertEqual(noms_publics.membres_extension(d), {
            "Graphe.Noeud.init(id:genre:routeur:extMac:)", "Graphe.Noeud.visible(_:pour:)",
            "Graphe.Noeud.valeur", "Graphe.Noeud.marque(avec:)"})

    def test_extension_non_publique_membres_explicites(self):
        d = dossier({"a.swift": """
extension Demo {
    public static let a = 1
    static let b = 2
    func c() {}
    public func d(x: Int) {}
}
"""})
        self.assertEqual(noms_publics.membres_extension(d), {"Demo.a", "Demo.d(x:)"})

    def test_corps_de_methode_et_closure_ignores(self):
        d = dossier({"a.swift": """
public extension Demo {
    static let regle: @Sendable (Int) -> Int = { n in
        let interne = n
        return interne
    }
    func f<T: Hashable>(_ a: [T], defaut: (Int, Int) -> Int = { $0 + $1 }) -> Int {
        func local() {}
        return 0
    }
}
"""})
        self.assertEqual(noms_publics.membres_extension(d), {"Demo.regle", "Demo.f(_:defaut:)"})


class Communs(unittest.TestCase):
    def test_meme_signature_dans_les_deux(self):
        a = dossier({"a.swift": "public extension C { init(cle: String, releves: [Int]) {} func f() {} }"})
        b = dossier({"b.swift": "public extension C { init(cle: String, releves: [Bool]) {} func f(x: Int) {} }"})
        self.assertEqual(noms_publics.communs(a, b), ["C.init(cle:releves:)"])

    def test_etiquettes_distinctes_pas_de_collision(self):
        a = dossier({"a.swift": "public extension C { init(thread: String) {} }"})
        b = dossier({"b.swift": "public extension C { init(zigbee: String) {} }"})
        self.assertEqual(noms_publics.communs(a, b), [])


class Captes(unittest.TestCase):
    def test_init_raccourci_capte_un_appel_du_coeur(self):
        coeur = dossier({"c.swift": COEUR})
        module = dossier({"z.swift": """
public extension Graphe.Noeud {
    init(id: String, genre: Int, routeur: Bool, extMac: String? = nil) { fatalError() }
}
"""})
        res = noms_publics.captes(coeur, module)
        self.assertEqual(len(res), 1)
        self.assertIn("Graphe.Noeud.init(id:genre:routeur:extMac:)", res[0])

    def test_init_a_etiquette_propre_ne_capte_rien(self):
        coeur = dossier({"c.swift": COEUR})
        module = dossier({"z.swift": """
public extension Graphe.Noeud {
    init(zigbee id: String, genre: Int, routeur: Bool, extMac: String? = nil) { fatalError() }
}
public extension Graphe {
    init(maillage: Int, appareils: [Int]) {}
}
"""})
        self.assertEqual(noms_publics.captes(coeur, module), [])

    def test_init_interne_ou_hors_extension_ignore(self):
        coeur = dossier({"c.swift": COEUR})
        module = dossier({"z.swift": """
extension Graphe.Noeud {
    init(id: String, genre: Int) {}
}
"""})
        self.assertEqual(noms_publics.captes(coeur, module), [])


class DepotReel(unittest.TestCase):
    """Le depot lui-meme : ses deux protocoles ne se capturent pas (meme garde que verifier-noms-publics.sh)."""

    def test_aucun_defaut(self):
        racine = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
        t, z, c = (os.path.join(racine, n) for n in ("ProtocoleThread", "ProtocoleZigbee", "MaillageCoeur"))
        if not all(os.path.isdir(x) for x in (t, z, c)):
            self.skipTest("sources absentes")
        self.assertEqual(noms_publics.communs(t, z), [])
        self.assertEqual(noms_publics.captes(c, t) + noms_publics.captes(c, z), [])


if __name__ == "__main__":
    unittest.main()
