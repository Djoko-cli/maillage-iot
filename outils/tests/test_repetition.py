"""Tests de l'identite de repetition (phase 4, tache 8) : la garde de publication (outils/refuser_repetition.py) et la
declaration de la cible dans project.yml (sans Sparkle, identifiant et suffixe a part).

  python3 -m unittest discover -s outils/tests
"""
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(RACINE, "outils"))
import refuser_repetition  # noqa: E402

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None


def app(info):
    """Une .app minimale (Contents/Info.plist) dans un dossier temporaire."""
    d = tempfile.mkdtemp()
    chemin = os.path.join(d, "X.app", "Contents")
    os.makedirs(chemin)
    with open(os.path.join(chemin, "Info.plist"), "wb") as f:
        plistlib.dump(info, f)
    return os.path.join(d, "X.app")


def lancer(*args):
    return subprocess.run([sys.executable, "-I", os.path.join(RACINE, "outils", "refuser_repetition.py"), *args],
                          capture_output=True, text=True)


class GardeDePublication(unittest.TestCase):
    def test_l_app_publiee_passe(self):
        r = lancer(app({"CFBundleIdentifier": "fr.djoko.maillage.iot", "CFBundleName": "Maillage IoT"}))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_un_identifiant_de_repetition_est_refuse(self):
        r = lancer(app({"CFBundleIdentifier": "fr.djoko.maillage.iot.repetition"}))
        self.assertEqual(r.returncode, 1)
        self.assertIn("jamais publiee", r.stderr)

    def test_le_suffixe_des_services_suffit(self):
        r = lancer(app({"CFBundleIdentifier": "fr.djoko.maillage.iot", "MaillageSuffixeServices": ".repetition"}))
        self.assertEqual(r.returncode, 1)

    def test_le_nom_suffit(self):
        for cle, valeur in (("CFBundleName", "Maillage IoT Repetition"), ("CFBundleDisplayName", "Maillage IoT Répétition")):
            r = lancer(app({"CFBundleIdentifier": "fr.djoko.maillage.iot", cle: valeur}))
            self.assertEqual(r.returncode, 1, cle)

    def test_un_identifiant_seul_ou_un_plist(self):
        self.assertEqual(lancer("fr.djoko.maillage.iot").returncode, 0)
        self.assertEqual(lancer("fr.djoko.maillage.iot.repetition").returncode, 1)
        plist = os.path.join(tempfile.mkdtemp(), "Info.plist")
        with open(plist, "wb") as f:
            plistlib.dump({"CFBundleIdentifier": "fr.djoko.maillage.iot.repetition"}, f)
        self.assertEqual(lancer(plist).returncode, 1)

    def test_une_app_sans_info_plist_n_est_pas_publiable_en_silence(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "Vide.app"))
        self.assertEqual(lancer(os.path.join(d, "Vide.app")).returncode, 2)

    def test_le_controle_inverse_de_repetition_sh(self):
        self.assertEqual(lancer("--verifier-est-repetition", "fr.djoko.maillage.iot.repetition").returncode, 0)
        self.assertEqual(lancer("--verifier-est-repetition", "fr.djoko.maillage.iot").returncode, 1)


@unittest.skipIf(yaml is None, "PyYAML absent")
class CibleDeRepetition(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(RACINE, "project.yml")) as f:
            cls.projet = yaml.safe_load(f)
        cls.cible = cls.projet["targets"]["MaillageIoTRepetition"]
        cls.reelle = cls.projet["targets"]["MaillageIoT"]

    def test_identite_a_part(self):
        base = self.cible["settings"]["base"]
        self.assertEqual(base["PRODUCT_BUNDLE_IDENTIFIER"], "fr.djoko.maillage.iot.repetition")
        self.assertNotEqual(base["PRODUCT_BUNDLE_IDENTIFIER"], self.reelle["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"])
        self.assertEqual(self.cible["info"]["properties"][refuser_repetition.CLE_SUFFIXE], ".repetition")
        self.assertIn("Répétition", self.cible["info"]["properties"]["CFBundleDisplayName"])
        self.assertIn("REPETITION", base["SWIFT_ACTIVE_COMPILATION_CONDITIONS"])

    def test_sans_sparkle(self):
        self.assertNotIn({"package": "Sparkle"}, self.cible["dependencies"])
        self.assertFalse([d for d in self.cible["dependencies"] if "package" in d])
        self.assertFalse([k for k in self.cible["info"]["properties"] if k.startswith("SU")], "aucune cle de Sparkle")
        # Les droits : ni l'exception mach-lookup des services de Sparkle, ni ceux de l'app.
        droits = self.cible["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"]
        self.assertNotEqual(droits, self.reelle["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"])
        with open(os.path.join(RACINE, droits), "rb") as f:
            self.assertNotIn("com.apple.security.temporary-exception.mach-lookup.global-name", plistlib.load(f))

    def test_son_icone_n_est_pas_celle_de_l_app(self):
        self.assertEqual(self.cible["settings"]["base"]["ASSETCATALOG_COMPILER_APPICON_NAME"], "AppIconRepetition")
        self.assertIn("Ressources/AppIcon.icon", self.cible["sources"][0]["excludes"])
        self.assertTrue(os.path.isfile(os.path.join(
            RACINE, "MaillageIoTRepetition/Ressources/AppIconRepetition.icon/Assets/constellation.png")))

    def test_memes_sources_que_l_app(self):
        self.assertEqual(self.cible["sources"][0]["path"], "MaillageIoT")

    def test_declaree_dans_aucun_scheme_de_test_ni_de_publication(self):
        # La repetition a son schema ; celui de l'app (tests, archive) ne la construit pas.
        build = self.projet["schemes"]["MaillageIoT"]["build"]["targets"]
        self.assertNotIn("MaillageIoTRepetition", build)
        self.assertIn("MaillageIoTRepetition", self.projet["schemes"])


if __name__ == "__main__":
    unittest.main()
