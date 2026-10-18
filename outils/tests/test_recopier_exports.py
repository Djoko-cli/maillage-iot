"""Tests de outils/recopier-exports-anciennes-apps.sh : des depots voisins inventes (git), des exports valides, alteres, ou
modifies sans commit ; la sortie est un dossier temporaire, jamais le vrai.

  python3 -m unittest discover -s outils/tests -q
"""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCRIPT = os.path.join(RACINE, "outils", "recopier-exports-anciennes-apps.sh")

_TEMPORAIRES = []


def tearDownModule():
    for d in _TEMPORAIRES:
        shutil.rmtree(d, ignore_errors=True)


def temporaire():
    d = tempfile.mkdtemp()
    _TEMPORAIRES.append(d)
    return d


def git(depot, *args):
    subprocess.run(["git", "-C", depot, "-c", "user.name=essai", "-c", "user.email=essai@users.noreply.github.com",
                    "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)


def depot(app, version, fichiers=None, commit=True):
    """Un depot invente avec docs/export-exemple/ : un manifeste correct pour `fichiers` (chemin -> octets)."""
    d = temporaire()
    export = os.path.join(d, "docs", "export-exemple")
    fichiers = dict(fichiers or {"surnoms.json": b"{}\n", "Journal/journal-2026-10.jsonl": b"{}\n"})
    fichiers.setdefault("reglages.json", b'{"app":"%s","format":1,"nonRepris":{},"valeurs":{}}\n' % app.encode())
    entrees = []
    for chemin, octets in sorted(fichiers.items()):
        cible = os.path.join(export, chemin)
        os.makedirs(os.path.dirname(cible), exist_ok=True)
        with open(cible, "wb") as f:
            f.write(octets)
        entrees.append({"chemin": chemin, "sha256": hashlib.sha256(octets).hexdigest(), "taille": len(octets)})
    manifeste = {"app": app, "date": "2026-10-17T12:00:00Z", "fichiers": entrees, "fichiersNonRepris": [],
                 "format": 1, "identifiant": "00000000-0000-4000-8000-000000000001", "versionApp": version}
    with open(os.path.join(export, "manifeste.json"), "w") as f:
        json.dump(manifeste, f)
    subprocess.run(["git", "init", "-q", d], check=True)
    if commit:
        git(d, "add", "-A")
        git(d, "commit", "-q", "-m", "export")
    return d


def lancer(thread, zigbee, sortie, *args):
    env = dict(os.environ, DEPOT_THREAD=thread, DEPOT_ZIGBEE=zigbee, SORTIE=sortie)
    r = subprocess.run(["bash", SCRIPT, *args], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout


def lire(chemin):
    with open(chemin, "rb") as f:
        return f.read()


class RecopierExportsTests(unittest.TestCase):
    def test_recopie_a_l_octet_et_ecrit_l_origine(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 0, sortie)
        for dossier, depot_source in (("thread-1.4.0-export", t), ("zigbee-1.2.0-export", z)):
            source = os.path.join(depot_source, "docs", "export-exemple")
            for base, _, noms in os.walk(source):
                for nom in noms:
                    relatif = os.path.relpath(os.path.join(base, nom), source)
                    self.assertEqual(lire(os.path.join(base, nom)), lire(os.path.join(s, dossier, relatif)), relatif)
        origine = lire(os.path.join(s, "ORIGINE.md")).decode()
        commit_t = subprocess.run(["git", "-C", t, "log", "-1", "--format=%h"], capture_output=True, text=True).stdout.strip()
        self.assertIn(commit_t, origine)
        self.assertIn("maillage-thread", origine)
        self.assertIn("maillage-zigbee", origine)
        self.assertNotIn("/Users/", origine)
        self.assertNotIn(t, origine)

    def test_ne_recopie_ni_ds_store_ni_appledouble(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        for nom in (".DS_Store", "._surnoms.json"):
            with open(os.path.join(t, "docs", "export-exemple", nom), "wb") as f:
                f.write(b"x")
        git(t, "add", "-f", "-A")
        git(t, "commit", "-q", "-m", "x")
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 0, sortie)
        self.assertFalse(os.path.exists(os.path.join(s, "thread-1.4.0-export", ".DS_Store")))
        self.assertFalse(os.path.exists(os.path.join(s, "thread-1.4.0-export", "._surnoms.json")))

    def test_verifier_ne_modifie_rien_et_voit_une_copie_a_jour(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        self.assertEqual(lancer(t, z, s)[0], 0)
        avant = lire(os.path.join(s, "ORIGINE.md"))
        code, sortie = lancer(t, z, s, "--verifier")
        self.assertEqual(code, 0, sortie)
        self.assertEqual(lire(os.path.join(s, "ORIGINE.md")), avant)

    def test_verifier_voit_une_copie_alteree_ou_absente(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        code, sortie = lancer(t, z, s, "--verifier")
        self.assertEqual(code, 1, sortie)
        self.assertIn("copie absente", sortie)
        self.assertEqual(lancer(t, z, s)[0], 0)
        with open(os.path.join(s, "zigbee-1.2.0-export", "surnoms.json"), "ab") as f:
            f.write(b" ")
        code, sortie = lancer(t, z, s, "--verifier")
        self.assertEqual(code, 1, sortie)
        self.assertIn("zigbee : copie : ", sortie)
        self.assertIn("empreinte fausse", sortie)

    def test_verifier_voit_une_source_plus_recente(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        self.assertEqual(lancer(t, z, s)[0], 0)
        neuf = depot("thread", "1.4.0", {"surnoms.json": b'{"a":"b"}\n'})
        code, sortie = lancer(neuf, z, s, "--verifier")
        self.assertEqual(code, 1, sortie)
        self.assertIn("la copie differe de la source", sortie)

    def test_une_empreinte_fausse_a_la_source_est_refusee_et_rien_n_est_ecrit(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        with open(os.path.join(t, "docs", "export-exemple", "surnoms.json"), "ab") as f:
            f.write(b" ")
        git(t, "add", "-A")
        git(t, "commit", "-q", "-m", "casse")
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("defaut : thread : source : empreinte fausse : surnoms.json", sortie)
        self.assertFalse(os.path.exists(os.path.join(s, "ORIGINE.md")))
        self.assertFalse(os.path.exists(os.path.join(s, "thread-1.4.0-export")))

    def test_un_fichier_hors_manifeste_est_refuse(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        with open(os.path.join(z, "docs", "export-exemple", "en-trop.json"), "wb") as f:
            f.write(b"{}")
        git(z, "add", "-A")
        git(z, "commit", "-q", "-m", "trop")
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("fichier hors manifeste : en-trop.json", sortie)

    def test_une_mauvaise_app_ou_version_est_refusee(self):
        s = temporaire()
        code, sortie = lancer(depot("zigbee", "1.4.0"), depot("zigbee", "1.2.0"), s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("app 'zigbee' au lieu de 'thread'", sortie)
        code, sortie = lancer(depot("thread", "1.3.0"), depot("zigbee", "1.2.0"), s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("version '1.3.0' au lieu de '1.4.0'", sortie)

    def test_un_chemin_qui_sort_du_dossier_est_refuse(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        chemin = os.path.join(t, "docs", "export-exemple", "manifeste.json")
        manifeste = json.loads(lire(chemin))
        manifeste["fichiers"].append({"chemin": "../x.json", "sha256": "0" * 64, "taille": 0})
        with open(chemin, "w") as f:
            json.dump(manifeste, f)
        git(t, "add", "-A")
        git(t, "commit", "-q", "-m", "chemin")
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("chemin qui sort du dossier", sortie)

    def test_une_source_non_commitee_est_refusee(self):
        t, z, s = depot("thread", "1.4.0", commit=False), depot("zigbee", "1.2.0"), temporaire()
        code, sortie = lancer(t, z, s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("modifications non commitees", sortie)

    def test_un_depot_absent_est_un_defaut(self):
        s = temporaire()
        absent = os.path.join(temporaire(), "n-existe-pas")
        code, sortie = lancer(absent, depot("zigbee", "1.2.0"), s)
        self.assertEqual(code, 1, sortie)
        self.assertIn("export d'exemple absent", sortie)

    def test_les_sources_ne_sont_pas_modifiees(self):
        t, z, s = depot("thread", "1.4.0"), depot("zigbee", "1.2.0"), temporaire()
        avant = subprocess.run(["git", "-C", t, "status", "--porcelain"], capture_output=True, text=True).stdout
        lancer(t, z, s)
        lancer(t, z, s, "--verifier")
        apres = subprocess.run(["git", "-C", t, "status", "--porcelain"], capture_output=True, text=True).stdout
        self.assertEqual(avant, apres)


if __name__ == "__main__":
    unittest.main()
