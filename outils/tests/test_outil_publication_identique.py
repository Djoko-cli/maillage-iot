"""Publication : l'outil de publication est recopie a l'octet de Maillage Thread. Ces trois fichiers doivent avoir
la meme empreinte SHA-256 que ceux du depot Thread (DEPOT_THREAD, par defaut ../maillage-thread) :

  outils/publication.py, outils/tests/test_publication.py, outils/Sparkle-LICENSE.txt

Sans depot Thread (clone isole), le test est saute avec un message clair : il n'est jamais vert en silence.

  /usr/bin/python3 -I -m unittest discover -s outils/tests -q
"""
import hashlib
import os
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEPOT_THREAD = os.environ.get("DEPOT_THREAD") or os.path.normpath(os.path.join(RACINE, "..", "maillage-thread"))

def empreinte(chemin):
    with open(chemin, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class OutilPublicationIdentique(unittest.TestCase):
    def verifier(self, relatif):
        if not os.path.isdir(DEPOT_THREAD):
            self.skipTest(
                f"depot Maillage Thread absent ({DEPOT_THREAD}) : "
                "definir DEPOT_THREAD pour verifier la recopie de publication.py"
            )
        source = os.path.join(DEPOT_THREAD, relatif)
        copie = os.path.join(RACINE, relatif)
        self.assertTrue(os.path.isfile(source), f"fichier absent du depot Thread : {source}")
        self.assertTrue(os.path.isfile(copie), f"copie absente : {relatif}")
        self.assertEqual(
            empreinte(copie), empreinte(source),
            f"{relatif} differe de Maillage Thread : recopier a l'octet (cp -p) depuis {DEPOT_THREAD}",
        )

    def test_publication_py(self):
        self.verifier("outils/publication.py")

    def test_test_publication_py(self):
        self.verifier("outils/tests/test_publication.py")

    def test_sparkle_license(self):
        self.verifier("outils/Sparkle-LICENSE.txt")


if __name__ == "__main__":
    unittest.main()
