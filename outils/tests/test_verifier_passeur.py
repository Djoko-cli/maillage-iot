"""Tests de l'outil de banc du passeur : trames et resumes, sans reseau."""
import contextlib
import importlib.util
import io
import json
import pathlib
import types
import unittest
from unittest import mock

CHEMIN = pathlib.Path(__file__).resolve().parent.parent / "verifier-passeur.py"
spec = importlib.util.spec_from_file_location("verifier_passeur", CHEMIN)
vp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vp)


def trame(objet):
    j = json.dumps(objet).encode()
    return str(len(j)).encode() + b"\n" + j


class FauxSocket:
    """Enregistre ce qui serait envoye au demon."""

    def __init__(self):
        self.envoye = b""

    def sendall(self, donnees):
        self.envoye += donnees


class Ouvrir(unittest.TestCase):
    JETON = "a" * 64

    def lancer(self, tourne, codes_open):
        """Appelle ouvrir() avec un faux pgrep (`tourne`) et les codes de retour successifs des `open`."""
        appels = []
        codes = iter(codes_open)

        def faux_run(cmd, **_):
            appels.append(cmd)
            if cmd[0] == "pgrep":
                return types.SimpleNamespace(returncode=0 if tourne() else 1)
            return types.SimpleNamespace(returncode=next(codes))

        with mock.patch.object(vp.subprocess, "run", side_effect=faux_run), \
                mock.patch.object(vp.time, "sleep"):
            vp.ouvrir("releve", 1234, self.JETON)
        return [c for c in appels if c[0] == "open"]

    def test_deja_lance_ouvre_seulement_l_url(self):
        ouvertures = self.lancer(lambda: True, [0])
        self.assertEqual(len(ouvertures), 1)
        self.assertTrue(ouvertures[0][-1].startswith("maillage-passeur://releve?port=1234"))

    def test_pas_lance_ouvre_l_app_puis_l_url(self):
        etat = {"n": 0}

        def tourne():
            etat["n"] += 1
            return etat["n"] > 1  # absent au premier controle, present ensuite

        ouvertures = self.lancer(tourne, [0, 0])
        self.assertEqual(len(ouvertures), 2)
        self.assertEqual(ouvertures[0], ["open", "-g", "-b", "fr.djoko.maillage.passeur"])
        self.assertTrue(ouvertures[1][-1].startswith("maillage-passeur://"))

    def test_ouverture_de_l_app_en_echec_sans_jeton(self):
        with self.assertRaises(SystemExit) as cm:
            self.lancer(lambda: False, [1])
        self.assertIn("open a echoue (code 1)", str(cm.exception))
        self.assertNotIn(self.JETON, str(cm.exception))

    def test_echec_de_l_url_sans_jeton(self):
        with self.assertRaises(SystemExit) as cm:
            self.lancer(lambda: True, [1])
        self.assertIn("open a echoue (code 1)", str(cm.exception))
        self.assertNotIn(self.JETON, str(cm.exception))


class Traiter(unittest.TestCase):
    def test_trames_suivant_le_jeton_sont_traitees(self):
        noms = {"version": 2, "statut": "ok", "accessoires": [{"nom": "Secret", "id": "X"}]}
        tampon = trame({"t": "etat", "v": 1, "version": "2.0", "acces": "autorise"}) \
            + trame({"t": "releve", "v": 1, "noms": noms}) + b"12\n{"
        faux, sortie = FauxSocket(), io.StringIO()
        with contextlib.redirect_stdout(sortie):
            reste, relu = vp.traiter(faux, tampon, False)
        texte = sortie.getvalue()
        self.assertIn("etat : version 2.0", texte)
        self.assertIn("releve : version 2", texte)
        self.assertIn("relire envoye", texte)
        self.assertNotIn("Secret", texte)
        self.assertIn(b'"relire"', faux.envoye)
        self.assertEqual(reste, b"12\n{")
        self.assertTrue(relu)

    def test_sans_relire_rien_n_est_envoye(self):
        faux, sortie = FauxSocket(), io.StringIO()
        with contextlib.redirect_stdout(sortie):
            reste, relu = vp.traiter(faux, trame({"t": "releve", "v": 1, "noms": {}}), True)
        self.assertEqual(faux.envoye, b"")
        self.assertEqual(reste, b"")
        self.assertTrue(relu)


class Trames(unittest.TestCase):
    def test_plusieurs_et_reste(self):
        a, b = trame({"t": "relire", "v": 1}), trame({"t": "etat", "v": 1})
        trames, reste = vp.lire_trames(a + b + b"12\n{")
        self.assertEqual([json.loads(t)["t"] for t in trames], ["relire", "etat"])
        self.assertEqual(reste, b"12\n{")

    def test_longueur_fausse(self):
        with self.assertRaises(ValueError):
            vp.lire_trames(b"x\n{}")
        with self.assertRaises(ValueError):
            vp.lire_trames(b"0\n")


class Resumes(unittest.TestCase):
    def test_releve_sans_noms(self):
        noms = {"version": 2, "statut": "ok", "accessoires": [{"nom": "Secret", "id": "X"}, {"nom": "Autre"}],
                "zones": [{"nom": "Etage", "pieces": ["Chambre"]}]}
        texte = vp.resumer({"t": "releve", "v": 1, "noms": noms})
        self.assertIn("2 accessoires", texte)
        self.assertIn("1 avec id", texte)
        self.assertNotIn("Secret", texte)
        self.assertNotIn("Chambre", texte)

    def test_etat(self):
        texte = vp.resumer({"t": "etat", "v": 1, "version": "2.0", "acces": "autorise",
                            "ouvertureSession": "inactive", "profilExpire": None})
        self.assertIn("2.0", texte)
        self.assertIn("autorise", texte)

    def test_identifie_sans_texte_d_erreur(self):
        texte = vp.resumer({"t": "identifie", "v": 1, "demande": "Identifier", "ok": False,
                            "erreur": "Texte HomeKit secret"})
        self.assertIn("erreur oui", texte)
        self.assertNotIn("Texte HomeKit", texte)
        self.assertIn("erreur non", vp.resumer({"t": "identifie", "v": 1, "demande": "Identifier", "ok": True,
                                                "erreur": None}))

    def test_inconnu(self):
        self.assertIn("allumer", vp.resumer({"t": "allumer", "v": 1}))


if __name__ == "__main__":
    unittest.main()
