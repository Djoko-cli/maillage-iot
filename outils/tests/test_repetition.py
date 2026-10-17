"""Tests de l'identite de repetition (phase 4, tache 8) : la garde de publication (outils/refuser_repetition.py) et la
declaration de la cible dans project.yml (sans Sparkle, identifiant et suffixe a part).

  python3 -m unittest discover -s outils/tests
"""
import hashlib
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

    def test_un_chemin_qui_n_existe_pas_n_est_jamais_publiable(self):
        # La garde ne doit pas echouer ouvert : un chemin mal tape ou pas encore construit sort en code 2, avec sa cause.
        d = tempfile.mkdtemp()
        for cible in (os.path.join(d, "absent", "Maillage IoT Repetition.app"), os.path.join(d, "Absent.app"),
                      os.path.join(d, "Info.plist"), "Maillage IoT Repetition", "dossier/sans/app", "x.app"):
            r = lancer(cible)
            self.assertEqual(r.returncode, 2, cible)
            self.assertNotIn("publiable", r.stdout, cible)
            self.assertIn("illisible", r.stderr, cible)

    def test_une_app_illisible_ou_sans_identifiant_n_est_pas_publiable(self):
        # Info.plist qui n'est pas un plist, ou sans CFBundleIdentifier : code 2, jamais « publiable ».
        faux = app({})
        with open(os.path.join(faux, "Contents", "Info.plist"), "wb") as f:
            f.write(b"ceci n'est pas un plist")
        self.assertEqual(lancer(faux).returncode, 2)
        with open(os.path.join(faux, "Contents", "Info.plist"), "wb") as f:
            f.write(b'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key>')
        self.assertEqual(lancer(faux).returncode, 2)
        self.assertEqual(lancer(app({"CFBundleName": "Maillage IoT"})).returncode, 2)
        self.assertEqual(lancer(app({"CFBundleIdentifier": ""})).returncode, 2)
        plist = os.path.join(tempfile.mkdtemp(), "Info.plist")
        with open(plist, "wb") as f:
            plistlib.dump({"CFBundleName": "Maillage IoT"}, f)
        self.assertEqual(lancer(plist).returncode, 2)

    def test_seul_un_identifiant_nu_explicite_se_lit_comme_identifiant(self):
        self.assertEqual(lancer("fr.djoko.maillage.iot").returncode, 0)
        self.assertEqual(lancer("fr.djoko.maillage.iot.Repetition").returncode, 1)
        # Pas une forme d'identifiant : espace, « / », « .app », un seul segment.
        for cible in ("fr.djoko maillage", "a/b.c", "app", "fr.djoko.maillage.iot.app"):
            self.assertEqual(lancer(cible).returncode, 2, cible)

    def test_le_controle_inverse_de_repetition_sh(self):
        self.assertEqual(lancer("--verifier-est-repetition", "fr.djoko.maillage.iot.repetition").returncode, 0)
        self.assertEqual(lancer("--verifier-est-repetition", "fr.djoko.maillage.iot").returncode, 1)


class IconeDeRepetition(unittest.TestCase):
    """La construction ne salit jamais l'arbre : l'icone de repetition ne se regenere que si elle manque ou si sa source change."""
    SOURCES = ("MaillageIoT/Ressources/AppIcon.icon/icon.json", "MaillageIoT/Ressources/AppIcon.icon/Assets/constellation.png",
               "outils/icone/generer-repetition.swift")
    EMPREINTE = "outils/icone/repetition.empreinte"
    PNG = "MaillageIoTRepetition/Ressources/AppIconRepetition.icon/Assets/constellation.png"

    def test_l_empreinte_suit_les_sources_de_l_icone(self):
        # Une source changee sans icone regeneree (ou l'inverse) fait echouer la porte, au lieu d'une icone perimee.
        h = hashlib.sha256()
        for chemin in self.SOURCES:
            with open(os.path.join(RACINE, chemin), "rb") as f:
                h.update(f.read())
        with open(os.path.join(RACINE, self.EMPREINTE)) as f:
            self.assertEqual(f.read().strip(), h.hexdigest())

    def test_une_icone_a_jour_n_est_pas_reecrite(self):
        png = os.path.join(RACINE, self.PNG)
        avant = (os.stat(png).st_mtime_ns, os.path.getsize(png))
        r = subprocess.run(["bash", os.path.join(RACINE, "outils", "repetition.sh"), "icone"], capture_output=True, text=True, cwd=RACINE)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("a jour", r.stdout)
        self.assertEqual((os.stat(png).st_mtime_ns, os.path.getsize(png)), avant)


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

    def test_la_cible_reelle_garde_son_identite_et_sparkle(self):
        # Rien n'a change pour l'app publiee : identifiant, Sparkle (paquet, flux, cle, droits) et icone.
        base = self.reelle["settings"]["base"]
        self.assertEqual(base["PRODUCT_BUNDLE_IDENTIFIER"], "fr.djoko.maillage.iot")
        self.assertEqual(base["ASSETCATALOG_COMPILER_APPICON_NAME"], "AppIcon")
        self.assertIn({"package": "Sparkle"}, self.reelle["dependencies"])
        self.assertIn("Sparkle", self.projet["packages"])
        infos = self.reelle["info"]["properties"]
        for cle in ("SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks"):
            self.assertIn(cle, infos)
        self.assertNotIn(refuser_repetition.CLE_SUFFIXE, infos)
        self.assertNotIn("REPETITION", base.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", ""))
        with open(os.path.join(RACINE, base["CODE_SIGN_ENTITLEMENTS"]), "rb") as f:
            self.assertIn("com.apple.security.temporary-exception.mach-lookup.global-name", plistlib.load(f))

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
