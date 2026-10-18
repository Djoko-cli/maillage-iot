"""Tests de outils/publier.sh (le cliquet, le clone superficiel, la garde de la repetition, l'icone, les arguments
de publication.py) et de outils/anonymisation_double.py (les deux controles d'anonymisation prives).

Environnement neutre : des depots git temporaires, un faux publication.py qui note son appel, de faux outils sur le
PATH qui echouent s'ils sont lances, de faux controles prives (CONTROLE_THREAD, CONTROLE_ZIGBEE...). Ni reseau, ni
trousseau, ni compilation, ni controle prive reel, ni publication.

  /usr/bin/python3 -m unittest discover -s outils/tests
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

OUTILS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
RACINE = os.path.dirname(OUTILS)

# Un project.yml minimal : la cible a publier a un identifiant publiable ; la repetition (avant elle, pour que
# l'extraction ne prenne pas le premier identifiant du fichier) et une scene hors des cibles en ont un de repetition.
PROJECT = """name: Essai
targets:
  MaillageIoTRepetition:
    type: application
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.exemple.essai.repetition
  MaillageIoT:
    type: application
    # PRODUCT_BUNDLE_IDENTIFIER: fr.exemple.commentaire.repetition
    settings:
      base:
        PRODUCT_NAME: Essai
        PRODUCT_BUNDLE_IDENTIFIER: "fr.exemple.essai"   # l'identifiant publiable
  MaillageIoTTests:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.exemple.essai.tests
schemes:
  MaillageIoT:
    build:
      PRODUCT_BUNDLE_IDENTIFIER: fr.exemple.hors.cible.repetition
"""

ENREGISTREUR = r'''import json, os, sys
with open(os.environ["ENREGISTREUR"], "w") as f:
    json.dump({"argv": sys.argv[1:], "env": {k: os.environ.get(k) for k in (
        "DD", "CONTROLE_ANONYMISATION", "TABLE_ANONYMISATION", "NOTARISER", "PROFIL_NOTARISATION", "SPARKLE_BIN",
        "CONTROLE_THREAD", "TABLE_THREAD", "CONTROLE_ZIGBEE", "TABLE_ZIGBEE", "PUBLIER_PYTHON_ESSAI", "PUBLIER_ESSAI", "PYTHON",
        "ANONYMISATION_PRIVE")}}, f)
'''

FAUX_OUTIL = '#!/bin/sh\necho "$0 $*" >> "$ALERTE"\nexit 99\n'

# Un faux controle prive : meme interface (fichiers --table T F...), note son appel, imprime une ligne de comptes
# precedee d'une ligne qui ressemble a un contenu de fichier (jamais a relayer), rend le code voulu.
FAUX_CONTROLE = r'''import json, os, sys
with open(os.environ["JOURNAL_CONTROLES"], "a") as f:
    f.write(json.dumps({"nom": %(nom)r, "argv": sys.argv[1:]}) + "\n")
print("contenu-secret-du-fichier-" + %(nom)r)
print("ligne-fichier-secrete-en-erreur", file=sys.stderr)
print("%(comptes)s")
sys.exit(%(code)d)
'''

# Un faux controle qui resume sur la sortie d'erreur (comme pre-push le lit : 2>&1, derniere ligne).
FAUX_CONTROLE_STDERR = r'''import sys
print("contenu-secret-du-fichier-stdout")
print("%(comptes)s", file=sys.stderr)
sys.exit(%(code)d)
'''

# Un faux controle qui plante : ligne de contenu, puis trace Python dont le message porte du contenu de fichier.
FAUX_CONTROLE_PLANTE = r'''print("contenu-secret-du-fichier-avant-la-trace")
raise KeyError("valeur-secrete-12345")
'''


def git(depot, *args, ok=True):
    env = dict(os.environ, GIT_AUTHOR_NAME="Essai", GIT_AUTHOR_EMAIL="essai@example.invalid",
               GIT_COMMITTER_NAME="Essai", GIT_COMMITTER_EMAIL="essai@example.invalid",
               GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
    r = subprocess.run(["git", "-C", depot, *args], capture_output=True, text=True, env=env)
    if ok and r.returncode != 0:
        raise AssertionError("git %s : %s" % (" ".join(args), r.stderr))
    return r


def ecrire(chemin, texte, mode=None):
    os.makedirs(os.path.dirname(chemin), exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as f:
        f.write(texte)
    if mode:
        os.chmod(chemin, mode)


class Banc:
    """Un depot temporaire qui contient publier.sh, la garde, l'enveloppe, un faux publication.py et un project.yml."""

    def __init__(self, test, project=PROJECT, icone=True, superficiel=False):
        self.dossier = tempfile.mkdtemp(prefix="publier-")
        test.addCleanup(shutil.rmtree, self.dossier, True)
        source = os.path.join(self.dossier, "source")
        self.depot = os.path.join(self.dossier, "depot")
        self.maison = os.path.join(self.dossier, "maison")
        self.alerte = os.path.join(self.dossier, "alerte.txt")
        self.appel = os.path.join(self.dossier, "appel.json")
        os.makedirs(self.maison)
        os.makedirs(os.path.join(self.dossier, "bin"))
        for outil in ("xcodebuild", "codesign", "xcrun", "gh", "sign_update", "generate_keys", "security", "xcodegen"):
            ecrire(os.path.join(self.dossier, "bin", outil), FAUX_OUTIL, 0o755)
        os.makedirs(source)
        git(source, "init", "-q", "-b", "main")
        for nom in ("publier.sh", "refuser_repetition.py", "anonymisation_double.py"):
            chemin = os.path.join(OUTILS, nom)
            if os.path.exists(chemin):
                os.makedirs(os.path.join(source, "outils"), exist_ok=True)
                shutil.copy2(chemin, os.path.join(source, "outils", nom))
        ecrire(os.path.join(source, "outils", "publication.py"), ENREGISTREUR)
        ecrire(os.path.join(source, "project.yml"), project)
        if icone == "dossier-vide":
            os.makedirs(os.path.join(source, "MaillageIoT", "Ressources", "AppIcon.icon"))
            ecrire(os.path.join(source, "MaillageIoT", "Ressources", "AppIcon.icon", "Assets", "x.png"), "x\n")
        elif icone == "icon-json-vide":
            ecrire(os.path.join(source, "MaillageIoT", "Ressources", "AppIcon.icon", "icon.json"), "")
        elif icone:
            ecrire(os.path.join(source, "MaillageIoT", "Ressources", "AppIcon.icon", "icon.json"), "{}\n")
        git(source, "add", "-A")
        git(source, "commit", "-q", "-m", "un")
        ecrire(os.path.join(source, "suite.txt"), "deux\n")
        git(source, "add", "-A")
        git(source, "commit", "-q", "-m", "deux")
        if superficiel:
            git(self.dossier, "clone", "-q", "--depth", "1", "file://" + source, self.depot)
        else:
            os.rename(source, self.depot)

    def lancer(self, *args, env=None):
        e = {"PATH": os.path.join(self.dossier, "bin") + ":/usr/bin:/bin", "HOME": self.maison,
             "ALERTE": self.alerte, "ENREGISTREUR": self.appel}
        e.update(env or {})
        return subprocess.run(["bash", os.path.join(self.depot, "outils", "publier.sh"), *args], capture_output=True,
                              text=True, env=e, cwd=self.dossier)

    def appele(self):
        return os.path.exists(self.appel)

    def appel_json(self):
        with open(self.appel) as f:
            return json.load(f)

    def outil_lance(self):
        return os.path.exists(self.alerte)


class TestPublier(unittest.TestCase):
    def test_cliquet(self):
        """Hors --repetition, une autre identite ou NOTARISER different de 1 : code 1 avant tout appel."""
        b = Banc(self)
        for env in ({"IDENTITE_SIGNATURE": "Djoko-cli Code Signing"}, {"NOTARISER": "0"},
                    {"IDENTITE_SIGNATURE": "Developer ID Application: autre"}):
            with self.subTest(env=env):
                r = b.lancer("1.0.0", env=env)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("Developer ID", r.stderr)
                self.assertFalse(b.appele())
        self.assertFalse(b.outil_lance())

    def test_cliquet_ne_vaut_pas_en_repetition(self):
        b = Banc(self)
        r = b.lancer("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1",
                     env={"IDENTITE_SIGNATURE": "Autre identite", "NOTARISER": "0"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        a = b.appel_json()["argv"]
        self.assertEqual(a[a.index("--identite") + 1], "Autre identite")
        self.assertEqual(b.appel_json()["env"]["NOTARISER"], "0")

    def test_clone_superficiel(self):
        b = Banc(self, superficiel=True)
        r = b.lancer("1.0.0")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("superficiel", r.stderr)
        self.assertFalse(b.appele())

    def test_repetition_refusee(self):
        """L'identifiant de la cible MaillageIoT finit par .repetition : code 1 avant tout appel, meme en repetition."""
        projet = PROJECT.replace('"fr.exemple.essai"', "fr.exemple.essai.repetition")
        b = Banc(self, project=projet)
        for args in (("1.0.0",), ("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1")):
            with self.subTest(args=args):
                r = b.lancer(*args)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("repetition", r.stderr)
                self.assertFalse(b.appele())

    def test_identifiant_lu_dans_la_cible_seulement(self):
        """La repetition (avant la cible), un commentaire, un autre bloc et une scene portent .repetition : sans effet."""
        b = Banc(self)
        r = b.lancer("1.0.0")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(b.appele())

    def test_identifiant_introuvable_refuse(self):
        """Pas de cible MaillageIoT, ou pas d'identifiant dans son bloc : la garde ne conclut pas, code 1."""
        sans_cible = PROJECT.replace("  MaillageIoT:\n    type", "  AutreCible:\n    type")
        sans_cible = sans_cible.replace("\nschemes:\n  MaillageIoT:", "\nschemes:\n  AutreCible:")
        sans_identifiant = PROJECT.replace('        PRODUCT_BUNDLE_IDENTIFIER: "fr.exemple.essai"   # l\'identifiant publiable\n', "")
        variable = PROJECT.replace('"fr.exemple.essai"', "$(IDENTIFIANT)")
        for nom, projet in (("sans cible", sans_cible), ("sans identifiant", sans_identifiant), ("variable", variable)):
            with self.subTest(nom):
                b = Banc(self, project=projet)
                r = b.lancer("1.0.0")
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertRegex(r.stderr, "project.yml|illisible")
                self.assertFalse(b.appele())

    def test_project_yml_reel_publiable(self):
        """Le vrai project.yml : l'identifiant de la cible MaillageIoT passe la garde (aucun identifiant de repetition)."""
        with open(os.path.join(RACINE, "project.yml"), encoding="utf-8") as f:
            b = Banc(self, project=f.read())
        r = b.lancer("1.0.0")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_icone_absente(self):
        b = Banc(self, icone=False)
        r = b.lancer("1.0.0")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("AppIcon.icon", r.stderr)
        self.assertFalse(b.appele())

    def test_icone_dossier_sans_icon_json(self):
        """Le controle porte sur le contenu : un dossier AppIcon.icon vide (ou sans icon.json, ou icon.json vide) refuse."""
        for icone in ("dossier-vide", "icon-json-vide"):
            with self.subTest(icone=icone):
                b = Banc(self, icone=icone)
                r = b.lancer("1.0.0")
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("AppIcon.icon", r.stderr)
                self.assertFalse(b.appele())

    def test_arguments(self):
        b = Banc(self)
        r = b.lancer("1.0.0", "--sans-bureau", env={"SPARKLE_BIN": "/essai/sparkle"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        appel = b.appel_json()
        attendu = ["publier", "1.0.0", "--sans-bureau",
                   "--identite", "Developer ID Application", "--auteur", "Djoko-cli", "--etiquette", "v",
                   "--flux", "appcast.xml", "--licence", "outils/Sparkle-LICENSE.txt",
                   "--nom-app", "Maillage IoT", "--fichier", "Maillage-IoT",
                   "--depot-github", "Djoko-cli/maillage-iot",
                   "--projet", "MaillageIoT.xcodeproj", "--schema", "MaillageIoT", "--cible", "MaillageIoT",
                   "--test", "bash outils/tester.sh",
                   "--test", 'xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -destination '
                             'platform=macOS -derivedDataPath "$DD" -testLanguage en -testRegion US test',
                   "--test", "bash outils/tester-sondes.sh",
                   "--test", "sh outils/thread-route/tests.sh",
                   "--textes", "MaillageIoT/Ressources/Localizable.xcstrings",
                   "--textes", "MaillageIoT/Ressources/InfoPlist.xcstrings"]
        self.assertEqual(appel["argv"], attendu)
        env = appel["env"]
        self.assertEqual(env["DD"], os.path.join(b.maison, "Library", "Developer", "Xcode", "DerivedData",
                                                 "maillage-iot-publication"))
        self.assertEqual(env["CONTROLE_ANONYMISATION"], "outils/anonymisation_double.py")
        self.assertTrue(os.path.exists(os.path.join(b.depot, env["TABLE_ANONYMISATION"])))
        self.assertEqual(env["NOTARISER"], "1")
        self.assertEqual(env["PROFIL_NOTARISATION"], "djoko-notarisation")
        self.assertEqual(env["SPARKLE_BIN"], "/essai/sparkle")
        self.assertFalse(b.outil_lance())

    def test_controle_impose_malgre_l_environnement(self):
        """Un CONTROLE_ANONYMISATION de l'appelant ne remplace pas la double garde ; DD de l'appelant est respecte."""
        b = Banc(self)
        r = b.lancer("1.0.0", env={"CONTROLE_ANONYMISATION": "/bin/true", "TABLE_ANONYMISATION": "/dev/null",
                                   "DD": "/essai/dd"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        env = b.appel_json()["env"]
        self.assertEqual(env["CONTROLE_ANONYMISATION"], "outils/anonymisation_double.py")
        self.assertEqual(env["DD"], "/essai/dd")

    def test_interpreteur_substituable(self):
        """PUBLIER_PYTHON_ESSAI (avec le marqueur de test PUBLIER_ESSAI=1) remplace /usr/bin/python3 pour la garde et pour
        publication.py (les tests y mettent un enregistreur) ; ni l'une ni l'autre n'arrive dans l'environnement de
        publication.py."""
        b = Banc(self)
        enregistreur = os.path.join(b.dossier, "faux-python")
        ecrire(enregistreur, '#!/bin/sh\necho "$@" >> "$DOSSIER_APPELS"\nenv >> "$DOSSIER_ENV"\nexit 0\n', 0o755)
        appels = os.path.join(b.dossier, "appels.txt")
        environnement = os.path.join(b.dossier, "env.txt")
        r = b.lancer("1.0.0", env={"PUBLIER_PYTHON_ESSAI": enregistreur, "PUBLIER_ESSAI": "1", "DOSSIER_APPELS": appels,
                                   "DOSSIER_ENV": environnement})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(appels) as f:
            lignes = f.read().splitlines()
        self.assertEqual(len(lignes), 2, lignes)
        self.assertIn("refuser_repetition.py fr.exemple.essai", lignes[0])
        self.assertIn("outils/publication.py publier 1.0.0", lignes[1])
        with open(environnement) as f:
            appels_env = [x for x in f.read().split("_=/usr/bin/env\n") if x.strip()]
        self.assertEqual(len(appels_env), 2)
        self.assertNotIn("PUBLIER_PYTHON_ESSAI", appels_env[1])  # l'appel de publication.py
        self.assertNotIn("PUBLIER_ESSAI", appels_env[1])

    def test_interpreteur_ignore_sans_marqueur_de_test(self):
        """PUBLIER_PYTHON_ESSAI sans le marqueur PUBLIER_ESSAI=1 (ou avec une autre valeur) est ignoree : le vrai
        interpreteur lance la garde et publication.py ; le faux n'est jamais appele."""
        b = Banc(self)
        enregistreur = os.path.join(b.dossier, "faux-python")
        appels = os.path.join(b.dossier, "appels.txt")
        ecrire(enregistreur, '#!/bin/sh\necho "$@" >> "$DOSSIER_APPELS"\nexit 0\n', 0o755)
        for marqueur in ({}, {"PUBLIER_ESSAI": ""}, {"PUBLIER_ESSAI": "0"}, {"PUBLIER_ESSAI": "oui"}):
            with self.subTest(marqueur=marqueur):
                if os.path.exists(b.appel):
                    os.remove(b.appel)
                env = {"PUBLIER_PYTHON_ESSAI": enregistreur, "DOSSIER_APPELS": appels}
                env.update(marqueur)
                r = b.lancer("1.0.0", env=env)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertTrue(b.appele(), "publication.py doit tourner avec le vrai interpreteur")
                self.assertFalse(os.path.exists(appels), "le faux interpreteur ne doit jamais etre appele")
                e = b.appel_json()["env"]
                self.assertIsNone(e["PUBLIER_PYTHON_ESSAI"])
                self.assertIsNone(e["PUBLIER_ESSAI"])
        # l'aide ignore aussi la variable
        r = b.lancer("--aide", env={"PUBLIER_PYTHON_ESSAI": enregistreur, "DOSSIER_APPELS": appels})
        self.assertFalse(os.path.exists(appels), "le faux interpreteur ne doit jamais etre appele (aide)")

    def test_python_ambiant_sans_effet(self):
        """Un PYTHON de l'environnement (venv, pyenv...) ne change jamais l'interpreteur de la garde ni de publication.py."""
        b = Banc(self)
        r = b.lancer("1.0.0", env={"PYTHON": "/usr/bin/true"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(b.appele(), "publication.py doit tourner avec le vrai interpreteur, pas avec PYTHON")
        # et la garde de la repetition tourne pour de vrai : un identifiant de repetition est refuse malgre PYTHON=true
        projet = PROJECT.replace('"fr.exemple.essai"', "fr.exemple.essai.repetition")
        b = Banc(self, project=projet)
        r = b.lancer("1.0.0", env={"PYTHON": "/usr/bin/true"})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertFalse(b.appele())

    def test_surcharges_de_test_retirees(self):
        """Des surcharges de test dans l'environnement ambiant (controles, tables, interpreteur) n'arrivent jamais a
        publication.py : une valeur ambiante ne remplace pas un vrai controle."""
        b = Banc(self)
        ambiant = {"CONTROLE_THREAD": "/bin/true", "TABLE_THREAD": "/dev/null", "CONTROLE_ZIGBEE": "/bin/true",
                   "TABLE_ZIGBEE": "/dev/null"}
        ambiant["PUBLIER_ESSAI"] = "1"
        r = b.lancer("1.0.0", env=ambiant)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        env = b.appel_json()["env"]
        for nom in ambiant:
            self.assertIsNone(env[nom], nom)
        self.assertEqual(env["CONTROLE_ANONYMISATION"], "outils/anonymisation_double.py")

    # Les surcharges d'outils que lit publication.py (classe Outils) : hors repetition, une publication reelle les refuse.
    SURCHARGES_OUTILS = ("XCRUN", "SPCTL", "CODESIGN", "GH", "GIT", "SECURITY", "OPENSSL", "HDIUTIL", "DITTO",
                         "XCODEGEN", "XCODEBUILD")

    def test_surcharges_d_outils_refusees_hors_repetition(self):
        """Hors --repetition, une surcharge d'outil posee dans l'environnement (meme vide) est refusee, cause nommee, rien
        n'est lance : un faux XCRUN sauterait la notarisation sans bruit."""
        b = Banc(self)
        for nom in self.SURCHARGES_OUTILS:
            for valeur in ("/bin/true", ""):
                with self.subTest(nom=nom, valeur=valeur):
                    r = b.lancer("1.0.0", env={nom: valeur})
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn(nom, r.stderr)
                    self.assertFalse(b.appele())
        self.assertFalse(b.outil_lance())

    def test_liste_des_surcharges_celle_de_publication_py(self):
        """La liste de publier.sh et la constante du test sont les variables d'outils que lit la classe Outils de
        publication.py (hors SPARKLE_BIN, requis, et les deux controles, imposes par publier.sh)."""
        with open(os.path.join(OUTILS, "publication.py"), encoding="utf-8") as f:
            texte = f.read()
        classe = texte[texte.index("class Outils:"):texte.index("def lancer(")]
        lues = set(re.findall(r"e\.get\('([A-Z_]+)'", classe)) - {"SPARKLE_BIN", "CONTROLE_ANONYMISATION", "TABLE_ANONYMISATION"}
        with open(os.path.join(OUTILS, "publier.sh"), encoding="utf-8") as f:
            sh = re.search(r"for nom in ([A-Z ]+); do", f.read()).group(1).split()
        self.assertEqual(set(sh), lues)
        self.assertEqual(set(self.SURCHARGES_OUTILS), lues)

    def test_surcharges_d_outils_acceptees_en_repetition(self):
        """En repetition, rien ne change : les surcharges d'outils passent a publication.py (les tests de la repetition)."""
        b = Banc(self)
        for nom in self.SURCHARGES_OUTILS:
            with self.subTest(nom=nom):
                if b.appele():
                    os.remove(b.appel)
                r = b.lancer("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1", env={nom: "/bin/true"})
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertTrue(b.appele())

    def test_dossier_prive_retire_hors_repetition(self):
        """Hors --repetition, ANONYMISATION_PRIVE n'arrive pas a publication.py : seul le dossier prive du depot principal
        sert. En repetition, il est conserve."""
        b = Banc(self)
        r = b.lancer("1.0.0", env={"ANONYMISATION_PRIVE": "/essai/prive"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIsNone(b.appel_json()["env"]["ANONYMISATION_PRIVE"])
        os.remove(b.appel)
        r = b.lancer("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1",
                     env={"ANONYMISATION_PRIVE": "/essai/prive"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(b.appel_json()["env"]["ANONYMISATION_PRIVE"], "/essai/prive")

    def test_suffixe_des_services_dans_la_cible_refuse(self):
        """Une ligne MaillageSuffixeServices non vide dans le bloc de la cible MaillageIoT est une identite d'essai ou de
        repetition : code 1 avant tout appel, meme en repetition. Vide, en commentaire ou dans une autre cible : sans effet."""
        def avec(ligne):
            return PROJECT.replace("        PRODUCT_NAME: Essai\n", "        PRODUCT_NAME: Essai\n" + ligne)
        refuses = ("        MaillageSuffixeServices: .essai\n", "    MaillageSuffixeServices: '.repetition'  # x\n")
        for ligne in refuses:
            b = Banc(self, project=avec(ligne))
            for args in (("1.0.0",), ("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1")):
                with self.subTest(ligne=ligne, args=args):
                    r = b.lancer(*args)
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn("MaillageSuffixeServices", r.stderr)
                    self.assertFalse(b.appele())
        acceptes = ("        MaillageSuffixeServices:\n", '        MaillageSuffixeServices: ""\n',
                    "        # MaillageSuffixeServices: .essai\n")
        for ligne in acceptes:
            b = Banc(self, project=avec(ligne))
            with self.subTest(ligne=ligne):
                r = b.lancer("1.0.0")
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        b = Banc(self, project=PROJECT.replace("fr.exemple.essai.repetition\n  MaillageIoT:",
                                               "fr.exemple.essai.repetition\n        MaillageSuffixeServices: .repetition\n  MaillageIoT:"))
        r = b.lancer("1.0.0")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_repetition_valeur_vide_refusee(self):
        """Une valeur vide de --repetition (deux formes, ou valeur absente) ne saute jamais le cliquet : code 1 avec une
        cause, avant tout appel, meme avec le Developer ID et meme avec une autre identite."""
        b = Banc(self)
        for args in (("1.0.0", "--repetition", ""), ("1.0.0", "--repetition="), ("1.0.0", "--repetition"),
                     ("1.0.0", "--repetition", "  "), ("1.0.0", "--repetition=   "), ("1.0.0", "--repetition", "\t"),
                     ("1.0.0", "--repetition", "", "--url-base", "http://localhost:1")):
            for env in ({}, {"IDENTITE_SIGNATURE": "Djoko-cli Code Signing", "NOTARISER": "0"}):
                with self.subTest(args=args, env=env):
                    r = b.lancer(*args, env=env)
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn("--repetition", r.stderr)
                    self.assertFalse(b.appele())
        self.assertFalse(b.outil_lance())

    def test_repetition_valeur_non_vide_deux_formes(self):
        """Seule une valeur non vide saute le cliquet, sous les deux formes."""
        b = Banc(self)
        autre = {"IDENTITE_SIGNATURE": "Djoko-cli Code Signing", "NOTARISER": "0"}
        for args in (("1.0.0", "--repetition", "/tmp/x", "--url-base", "http://localhost:1"),
                     ("1.0.0", "--repetition=/tmp/x", "--url-base", "http://localhost:1")):
            with self.subTest(args=args):
                if os.path.exists(b.appel):
                    os.remove(b.appel)
                r = b.lancer(*args, env=autre)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertTrue(b.appele())
                self.assertEqual(b.appel_json()["env"]["NOTARISER"], "0")

    def test_abreviations_de_repetition_refusees(self):
        """argparse accepte toute abreviation de --repetition (--r, --rep, --repet=...) et garde la derniere occurrence :
        un argument en --r qui n'est ni exactement --repetition ni --repetition=VALEUR est refuse (code 1, avec une cause),
        seul, apres un vrai --repetition, ou avec une valeur vide, avant tout appel."""
        b = Banc(self)
        formes = ("--r", "--re", "--rep", "--repe", "--repet", "--repeti", "--repetit", "--repetiti", "--repetitio",
                  "--repetitionx", "--rx")
        suites = []
        for f in formes:
            suites += [(f, "/tmp/x"), (f + "=/tmp/x",), (f, ""), (f + "=",), (f,),
                       ("--repetition", "/tmp/x", f, ""), ("--repetition", "/tmp/x", f + "="),
                       ("--repetition=/tmp/x", f, ""), ("--repetition=/tmp/x", f + "=")]
        for env in ({}, {"IDENTITE_SIGNATURE": "Djoko-cli Code Signing", "NOTARISER": "0"}):
            for suite in suites:
                with self.subTest(suite=suite, env=env):
                    r = b.lancer("1.0.0", *suite, env=env)
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn("--repetition", r.stderr)
                    self.assertFalse(b.appele())
        self.assertFalse(b.outil_lance())

    def test_repetition_donnee_deux_fois_refusee(self):
        """--repetition present plus d'une fois (meme valeurs ou non, deux formes) : code 1 avec une cause, avant tout appel."""
        b = Banc(self)
        autre = {"IDENTITE_SIGNATURE": "Djoko-cli Code Signing", "NOTARISER": "0"}
        for args in (("--repetition", "/tmp/x", "--repetition", ""), ("--repetition", "/tmp/x", "--repetition", "/tmp/y"),
                     ("--repetition", "/tmp/x", "--repetition=/tmp/y"), ("--repetition=/tmp/x", "--repetition=/tmp/y"),
                     ("--repetition=/tmp/x", "--repetition="), ("--repetition=/tmp/x", "--repetition", ""),
                     ("--repetition=/tmp/x", "--repetition", "/tmp/y"), ("--repetition", "/tmp/x", "--repetition=")):
            for env in ({}, autre):
                with self.subTest(args=args, env=env):
                    r = b.lancer("1.0.0", *args, env=env)
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn("--repetition", r.stderr)
                    self.assertFalse(b.appele())

    def test_aucune_autre_option_de_publication_ne_commence_par_r(self):
        """La regle de publier.sh (tout argument en --r est --repetition ou refuse) suppose que --repetition est la seule
        option de publication.py qui commence par --r : sinon il faudrait l'autoriser nommement."""
        with open(os.path.join(OUTILS, "publication.py"), encoding="utf-8") as f:
            options = set(re.findall(r"""add_argument\(\s*['"](--[\w-]+)['"]""", f.read()))
        self.assertIn("--repetition", options)
        self.assertEqual(sorted(o for o in options if o.startswith("--r")), ["--repetition"])

    def test_aide_hors_premiere_position(self):
        """-h ailleurs qu'en premier passe par toutes les gardes puis par publication.py (jamais d'exemption)."""
        b = Banc(self)
        r = b.lancer("1.0.0", "-h")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("-h", b.appel_json()["argv"])
        os.remove(b.appel)
        r = b.lancer("1.0.0", "-h", env={"NOTARISER": "0"})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertFalse(b.appele())

    def test_identifiants_sans_decoupage_ni_globbing(self):
        """Un identifiant avec un joker ou une espace est transmis tel quel a la garde (un seul argument), sans
        expansion en noms de fichiers."""
        for valeur in ("*", "fr.exemple.* x", "fr.exemple.a b"):
            with self.subTest(valeur=valeur):
                b = Banc(self, project=PROJECT.replace('"fr.exemple.essai"', "'%s'" % valeur))
                enregistreur = os.path.join(b.dossier, "faux-python")
                ecrire(enregistreur, '#!/bin/sh\nprintf "[%s]" "$@" >> "$DOSSIER_APPELS"\necho >> "$DOSSIER_APPELS"\n'
                       'exit 1\n', 0o755)
                appels = os.path.join(b.dossier, "appels.txt")
                r = b.lancer("1.0.0", env={"PUBLIER_PYTHON_ESSAI": enregistreur, "PUBLIER_ESSAI": "1", "DOSSIER_APPELS": appels})
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                with open(appels) as f:
                    self.assertEqual(f.read(), "[-I][outils/refuser_repetition.py][%s]\n" % valeur)

    def test_aide(self):
        """--aide montre l'aide de publication.py sans rien verifier ni construire (meme sans icone)."""
        b = Banc(self, icone=False)
        ecrire(os.path.join(b.depot, "outils", "publication.py"), "import sys\nprint('aide', sys.argv[1:])\n")
        r = b.lancer("--aide")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("aide ['publier', '-h']", r.stdout)
        self.assertFalse(b.outil_lance())


def faux_controle(chemin, nom, code, comptes="3 fichiers, 0 defaut"):
    ecrire(chemin, FAUX_CONTROLE % {"nom": nom, "code": code, "comptes": comptes})


class TestAnonymisationDouble(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.mkdtemp(prefix="anonymisation-double-")
        self.addCleanup(shutil.rmtree, self.dossier, True)
        self.journal = os.path.join(self.dossier, "journal.jsonl")
        self.fichier = os.path.join(self.dossier, "a-controler.txt")
        ecrire(self.fichier, "rien\n")
        self.script = os.path.join(OUTILS, "anonymisation_double.py")

    def privee(self, thread=0, zigbee=0):
        """Un dossier prive factice a la disposition reelle (thread/outils/controles.py, zigbee/controles.py)."""
        prive = os.path.join(self.dossier, "prive")
        faux_controle(os.path.join(prive, "thread", "outils", "controles.py"), "thread", thread, "7 fichiers, 0 defaut")
        faux_controle(os.path.join(prive, "zigbee", "controles.py"), "zigbee", zigbee, "9 fichiers, 0 defaut")
        ecrire(os.path.join(prive, "thread", "table.json"), "{}\n")
        ecrire(os.path.join(prive, "zigbee", "table.json"), "{}\n")
        return prive

    def lancer(self, *args, env=None, script=None, cwd=None):
        e = {"PATH": "/usr/bin:/bin", "HOME": self.dossier, "JOURNAL_CONTROLES": self.journal}
        e.update(env or {})
        return subprocess.run(["/usr/bin/python3", script or self.script, *args], capture_output=True, text=True,
                              env=e, cwd=cwd or self.dossier)

    def appels(self):
        if not os.path.exists(self.journal):
            return []
        with open(self.journal) as f:
            return [json.loads(l) for l in f]

    def fichiers(self, *extra):
        return ["fichiers", "--table", "/ignoree.json", self.fichier, *extra]

    def test_deux_controles_reussis(self):
        prive = self.privee()
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        appels = self.appels()
        self.assertEqual([a["nom"] for a in appels], ["thread", "zigbee"])
        self.assertEqual(appels[0]["argv"], ["fichiers", "--table", os.path.join(prive, "thread", "table.json"),
                                             self.fichier])
        self.assertEqual(appels[1]["argv"], ["fichiers", "--table", os.path.join(prive, "zigbee", "table.json"),
                                             self.fichier])
        self.assertIn("thread", r.stdout)
        self.assertIn("zigbee", r.stdout)
        self.assertIn("7", r.stdout)
        self.assertIn("9", r.stdout)

    def test_un_echec_donne_1_et_les_deux_tournent(self):
        for thread, zigbee in ((1, 0), (0, 1), (1, 1), (2, 0)):
            with self.subTest(thread=thread, zigbee=zigbee):
                os.path.exists(self.journal) and os.remove(self.journal)
                prive = self.privee(thread, zigbee)
                r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertEqual([a["nom"] for a in self.appels()], ["thread", "zigbee"])

    def test_sortie_de_comptes_seulement(self):
        """Ni stdout ni stderr des controles ne sont relayes tels quels : des comptes, jamais des lignes de fichiers."""
        for thread in (0, 1):
            with self.subTest(thread=thread):
                r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": self.privee(thread=thread)})
                sortie = r.stdout + r.stderr
                self.assertNotIn("secret", sortie)
                self.assertNotIn("contenu-", sortie)
                self.assertNotIn("a-controler", sortie)

    def test_controle_absent_ou_table_absente(self):
        prive = self.privee()
        os.remove(os.path.join(prive, "thread", "outils", "controles.py"))
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("thread", r.stdout + r.stderr)
        prive = self.privee()
        os.remove(os.path.join(prive, "zigbee", "table.json"))
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("zigbee", r.stdout + r.stderr)

    def test_surcharges_de_test(self):
        """CONTROLE_THREAD, CONTROLE_ZIGBEE (et leurs tables) remplacent les chemins prives (tests seulement)."""
        faux_controle(os.path.join(self.dossier, "t.py"), "thread", 0)
        faux_controle(os.path.join(self.dossier, "z.py"), "zigbee", 0)
        ecrire(os.path.join(self.dossier, "t.json"), "{}\n")
        ecrire(os.path.join(self.dossier, "z.json"), "{}\n")
        env = {"CONTROLE_THREAD": os.path.join(self.dossier, "t.py"), "TABLE_THREAD": os.path.join(self.dossier, "t.json"),
               "CONTROLE_ZIGBEE": os.path.join(self.dossier, "z.py"), "TABLE_ZIGBEE": os.path.join(self.dossier, "z.json"),
               "ANONYMISATION_PRIVE": os.path.join(self.dossier, "introuvable")}
        r = self.lancer(*self.fichiers(), env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        faux_controle(os.path.join(self.dossier, "z.py"), "zigbee", 1)
        r = self.lancer(*self.fichiers(), env=env)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        env["CONTROLE_ZIGBEE"] = os.path.join(self.dossier, "manque.py")
        r = self.lancer(*self.fichiers(), env=env)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)

    def test_dossier_prive_introuvable(self):
        """ANONYMISATION_PRIVE absent et dossier du depot principal sans controles : code 1, jamais un succes vide."""
        depot = os.path.join(self.dossier, "depot")
        os.makedirs(os.path.join(depot, "outils"))
        git(depot, "init", "-q", "-b", "main")
        shutil.copy2(self.script, os.path.join(depot, "outils", "anonymisation_double.py"))
        r = self.lancer(*self.fichiers(), script=os.path.join(depot, "outils", "anonymisation_double.py"))
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(self.appels(), [])
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": os.path.join(self.dossier, "inexistant")})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)

    def test_dossier_prive_du_depot_principal_depuis_un_worktree(self):
        """Sans la variable, le dossier prive est celui du depot principal (git-common-dir), meme depuis un worktree."""
        depot = os.path.join(self.dossier, "depot")
        os.makedirs(os.path.join(depot, "outils"))
        git(depot, "init", "-q", "-b", "main")
        shutil.copy2(self.script, os.path.join(depot, "outils", "anonymisation_double.py"))
        git(depot, "add", "-A")
        git(depot, "commit", "-q", "-m", "un")
        prive = self.privee()
        os.makedirs(os.path.join(depot, ".superpowers"))
        shutil.move(prive, os.path.join(depot, ".superpowers", "anonymisation"))
        travail = os.path.join(self.dossier, "travail")
        git(depot, "worktree", "add", "-q", travail, "-b", "autre")
        for racine in (depot, travail):
            with self.subTest(racine=racine):
                os.path.exists(self.journal) and os.remove(self.journal)
                r = self.lancer(*self.fichiers(), script=os.path.join(racine, "outils", "anonymisation_double.py"))
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertEqual([a["nom"] for a in self.appels()], ["thread", "zigbee"])

    def test_resume_sur_la_sortie_d_erreur(self):
        """Comme pre-push (2>&1, derniere ligne) : un controle qui resume sur stderr donne ses comptes."""
        prive = self.privee()
        ecrire(os.path.join(prive, "thread", "outils", "controles.py"),
               FAUX_CONTROLE_STDERR % {"comptes": "7 fichiers, 0 defaut", "code": 0})
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r"controle thread : code 0, comptes 7 0")
        self.assertNotIn("aucun", r.stdout.split("controle zigbee")[0])
        self.assertNotIn("secret", r.stdout + r.stderr)

    def test_controle_qui_plante(self):
        """Un controle qui plante (trace sur stderr, code non nul) : code 1, la cause dite, jamais de contenu de fichier
        ni de message de la trace ; l'autre controle tourne quand meme."""
        prive = self.privee()
        ecrire(os.path.join(prive, "thread", "outils", "controles.py"), FAUX_CONTROLE_PLANTE)
        r = self.lancer(*self.fichiers(), env={"ANONYMISATION_PRIVE": prive})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r"controle thread : code 1, plante : echec")
        self.assertNotIn("KeyError", r.stdout + r.stderr)  # aucun mot de la sortie du controle, pas meme le nom
        self.assertNotIn("secret", r.stdout + r.stderr)
        self.assertNotIn("12345", r.stdout + r.stderr)
        self.assertEqual([a["nom"] for a in self.appels()], ["zigbee"])

    def test_controle_impossible_a_lancer(self):
        """Un OSError au lancement d'un controle (liste de fichiers trop longue...) : echec dit en une ligne, pas de trace."""
        import importlib.util
        from unittest import mock
        spec = importlib.util.spec_from_file_location("anonymisation_double_essai", self.script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        prive = self.privee()
        script = os.path.join(prive, "thread", "outils", "controles.py")
        table = os.path.join(prive, "thread", "table.json")
        with mock.patch.object(module.subprocess, "run", side_effect=OSError(7, "Argument list too long")):
            with mock.patch("builtins.print") as imprimer:
                self.assertFalse(module.lancer("thread", script, table, [self.fichier]))
        texte = " ".join(str(a) for appel in imprimer.call_args_list for a in appel.args)
        self.assertIn("thread", texte)
        self.assertIn("OSError", texte)
        self.assertNotIn(self.fichier, texte)

    def test_usage_incorrect(self):
        prive = self.privee()
        for args in ((), ("messages", "--table", "x", self.fichier), ("fichiers", self.fichier)):
            with self.subTest(args=args):
                r = self.lancer(*args, env={"ANONYMISATION_PRIVE": prive})
                self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.appels(), [])


if __name__ == "__main__":
    unittest.main()
