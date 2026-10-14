"""Tests du refus de passeur.sh : ne jamais remplacer un demon installe plus recent (spec, section 5.3).

  python3 -m unittest discover -s outils/tests -q
"""
import os
import subprocess
import unittest

SCRIPT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "passeur.sh"))


def comparer(installee, construite):
    return subprocess.run(["bash", SCRIPT, "--comparer-versions", installee, construite],
                          capture_output=True, text=True)


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


if __name__ == "__main__":
    unittest.main()
