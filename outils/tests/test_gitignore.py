"""Tests du .gitignore : les secrets et donnees reelles des anciens depots (Maillage Thread, Maillage Zigbee) ne
peuvent pas etre suivis par megarde quand on recopie leurs fichiers (spec, section 5.1).

  python3 -m unittest discover -s outils/tests -q
"""
import os
import shutil
import subprocess
import tempfile
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

IGNORES = [
    "garde.local.txt",
    ".superpowers/fusion/etat-thread.md",
    "Local.xcconfig",
    "outils/cle_reseau.local",
    "outils/sonde.local.json",
    "sonde-zigbee/cle_hue.local.h",
    "docs/releves/2026-09-29/capture-sonde-essai.jsonl",
    "noms.json",
    "releve-maison.json",
    "noms-pont.json",
    "appariements-maison.json",
    "essais/capture.jsonl",
    ".pytest_cache/v/cache",
    ".vscode/settings.json",
]
SUIVIS = [
    "README.md",
    "outils/garde.py",
    "docs/releves/2026-09-29/capture-sonde.jsonl",
    "sonde-zigbee/cle_hue.exemple.h",
]


class GitignoreTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="gitignore-")
        subprocess.run(["git", "init", "-q", self.d], check=True)
        shutil.copy(os.path.join(RACINE, ".gitignore"), os.path.join(self.d, ".gitignore"))

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def ignore(self, chemin):
        return subprocess.run(["git", "-C", self.d, "check-ignore", "-q", "--no-index", chemin]).returncode == 0

    def test_secrets_et_donnees_reelles_ignores(self):
        manquants = [c for c in IGNORES if not self.ignore(c)]
        self.assertEqual(manquants, [])

    def test_fichiers_du_depot_suivis(self):
        ignores = [c for c in SUIVIS if self.ignore(c)]
        self.assertEqual(ignores, [])


if __name__ == "__main__":
    unittest.main()
