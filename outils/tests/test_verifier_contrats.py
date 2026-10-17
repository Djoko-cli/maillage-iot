"""Tests de outils/verifier-contrats.sh : des depots voisins inventes, copies identiques, differentes ou absentes.

  python3 -m unittest discover -s outils/tests
"""
import os
import shutil
import subprocess
import tempfile
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCRIPT = os.path.join(RACINE, "outils", "verifier-contrats.sh")
FICHIERS = ["MaillageCoeur/Reprise/ContratExport.swift", "MaillageCoeurTests/ContratExportTests.swift",
            "MaillageCoeur/Noms/ProtocolePasseur.swift"]

_TEMPORAIRES = []


def tearDownModule():
    for d in _TEMPORAIRES:
        shutil.rmtree(d, ignore_errors=True)


def depot(fichiers=(), modifies=()):
    """Un depot invente : les copies exactes des `fichiers`, la copie alteree des `modifies`."""
    d = tempfile.mkdtemp()
    _TEMPORAIRES.append(d)
    for f in list(fichiers) + list(modifies):
        cible = os.path.join(d, f)
        os.makedirs(os.path.dirname(cible), exist_ok=True)
        shutil.copyfile(os.path.join(RACINE, f), cible)
    for f in modifies:
        with open(os.path.join(d, f), "ab") as sortie:
            sortie.write(b"// altere\n")
    return d


def lancer(thread, zigbee):
    env = dict(os.environ, DEPOT_THREAD=thread, DEPOT_ZIGBEE=zigbee)
    r = subprocess.run(["bash", SCRIPT], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout


class VerifierContratsTests(unittest.TestCase):
    def test_les_fichiers_existent_ici(self):
        for f in FICHIERS:
            self.assertTrue(os.path.isfile(os.path.join(RACINE, f)), f)

    def test_copies_identiques(self):
        code, sortie = lancer(depot(FICHIERS), depot(FICHIERS))
        self.assertEqual(code, 0, sortie)
        self.assertIn("6 identique(s), 0 pas encore recopie(s), 0 defaut(s)", sortie)

    def test_depots_absents_ne_sont_pas_un_defaut(self):
        absent = os.path.join(tempfile.gettempdir(), "contrats-absent-" + os.urandom(4).hex())
        code, sortie = lancer(absent, absent)
        self.assertEqual(code, 0, sortie)
        self.assertIn("pas encore recopie : thread/MaillageCoeur/Reprise/ContratExport.swift", sortie)
        self.assertIn("0 identique(s), 6 pas encore recopie(s), 0 defaut(s)", sortie)

    def test_contrat_d_export_pas_encore_recopie_mais_passeur_identique(self):
        code, sortie = lancer(depot(FICHIERS[2:]), depot(FICHIERS[2:]))
        self.assertEqual(code, 0, sortie)
        self.assertIn("2 identique(s), 4 pas encore recopie(s), 0 defaut(s)", sortie)
        self.assertIn("pas encore recopie : thread/MaillageCoeurTests/ContratExportTests.swift", sortie)

    def test_copie_differente_est_un_defaut(self):
        for i, f in enumerate(FICHIERS):
            autre = [g for g in FICHIERS if g != f]
            code, sortie = lancer(depot(autre, [f]), depot(FICHIERS))
            self.assertEqual(code, 1, sortie)
            self.assertIn("DIFFERENT : thread/" + f, sortie)
            self.assertIn("1 defaut(s)", sortie)
            code, sortie = lancer(depot(FICHIERS), depot(autre, [f]))
            self.assertEqual(code, 1, sortie)
            self.assertIn("DIFFERENT : zigbee/" + f, sortie)

    def test_une_difference_malgre_une_copie_absente(self):
        code, sortie = lancer(depot([], [FICHIERS[0]]), "/inexistant")
        self.assertEqual(code, 1, sortie)
        self.assertIn("DIFFERENT : thread/" + FICHIERS[0], sortie)
        self.assertIn("pas encore recopie : zigbee/" + FICHIERS[0], sortie)


if __name__ == "__main__":
    unittest.main()
