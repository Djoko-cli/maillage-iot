"""Tests du refus de passeur.sh : ne jamais remplacer un demon installe plus recent (spec, section 5.3).

  python3 -m unittest discover -s outils/tests -q
"""
import os
import subprocess
import unittest

SCRIPT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "passeur.sh"))


def comparer(installee, construite, numero_installee=None, numero_construit=None):
    """Les deux premiers arguments : CFBundleShortVersionString ; les deux derniers (facultatifs) : CFBundleVersion,
    qui departage deux versions egales."""
    args = [installee, construite]
    if numero_installee is not None:
        args += [numero_installee, numero_construit or ""]
    return subprocess.run(["bash", SCRIPT, "--comparer-versions"] + args, capture_output=True, text=True)


class VersionPasseurTests(unittest.TestCase):
    def test_meme_version_acceptee(self):
        self.assertEqual(comparer("2.0", "2.0").returncode, 0)

    def test_version_plus_recente_acceptee(self):
        self.assertEqual(comparer("2.0", "2.1").returncode, 0)

    def test_demon_installe_plus_recent_refuse(self):
        r = comparer("2.10", "2.9")
        self.assertEqual(r.returncode, 1)
        self.assertIn("plus recent", r.stderr)

    def test_aucun_demon_installe_accepte(self):
        self.assertEqual(comparer("", "2.0").returncode, 0)

    def test_meme_version_numero_plus_recent_accepte(self):
        self.assertEqual(comparer("2.0", "2.0", "1", "2").returncode, 0)

    def test_meme_version_numero_identique_accepte(self):
        self.assertEqual(comparer("2.0", "2.0", "3", "3").returncode, 0)

    def test_meme_version_demon_installe_de_numero_plus_recent_refuse(self):
        r = comparer("2.0", "2.0", "10", "9")
        self.assertEqual(r.returncode, 1)
        self.assertIn("plus recent", r.stderr)

    def test_numero_ne_depasse_pas_la_version(self):
        # Le numero ne sert qu'a departager : une version construite plus ancienne reste refusee, meme avec un grand numero.
        self.assertEqual(comparer("2.1", "2.0", "1", "99").returncode, 1)

    def test_numero_absent_d_un_cote_ignore(self):
        self.assertEqual(comparer("2.0", "2.0", "", "1").returncode, 0)
        self.assertEqual(comparer("2.0", "2.0", "5", "").returncode, 0)


if __name__ == "__main__":
    unittest.main()
