"""Tests du hook outils/pre-push : de vrais push vers un depot nu, dans des depots temporaires, avec des
identifiants inventes et deux controles d'anonymisation remplaces par un bouchon (le hook est teste, pas les
controles prives).

  python3 -m unittest discover -s outils/tests -q
"""
import os
import shutil
import subprocess
import tempfile
import unittest

OUTILS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NOREPLY = "12185352+Djoko-cli@users.noreply.github.com"
SECRET = "ZORGLUB4271"  # identifiant invente : la liste de la garde le contient
LISTE = "# Identifiants inventes pour les tests\n" + SECRET + "\n"

# Bouchon des deux controles prives : meme interface (fichiers --table T FICHIER...), la table donne la liste ;
# echoue si un identifiant de la liste parait dans un fichier, sans tenir compte de la casse.
BOUCHON = r'''import json, sys
table = json.load(open(sys.argv[3], encoding="utf-8"))
ids = [l.strip().upper() for l in open(table["liste"], encoding="utf-8") if l.strip() and not l.startswith("#")]
defauts = [f for f in sys.argv[4:] if any(i in open(f, "rb").read().decode("utf-8", "replace").upper() for i in ids)]
print(f"{len(sys.argv) - 4} fichier(s) controle(s), {len(defauts)} fichier(s) en defaut")
sys.exit(1 if defauts else 0)
'''


def git(depot, *args, ok=True, env=None):
    r = subprocess.run(["git", "-C", depot, *args], capture_output=True, text=True, env=env)
    if ok and r.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} : {r.stderr}")
    return r


class Banc:
    """Un depot de travail avec le hook installe, la garde, la liste et les bouchons ; un depot nu `essai`."""

    def __init__(self):
        self.racine = tempfile.mkdtemp(prefix="pre-push-")
        self.depot = os.path.join(self.racine, "depot")
        self.nu = os.path.join(self.racine, "essai.git")
        subprocess.run(["git", "init", "-q", "--bare", self.nu], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", self.depot], check=True)
        self.identite(self.depot)
        os.makedirs(os.path.join(self.depot, "outils"))
        shutil.copy(os.path.join(OUTILS, "garde.py"), os.path.join(self.depot, "outils", "garde.py"))
        with open(os.path.join(self.depot, "garde.local.txt"), "w") as f:
            f.write(LISTE)
        with open(os.path.join(self.depot, ".gitignore"), "w") as f:
            f.write("garde.local.txt\n.superpowers/\n")
        anon = os.path.join(self.depot, ".superpowers", "anonymisation")
        for script in ("thread/outils/controles.py", "zigbee/controles.py"):
            chemin = os.path.join(anon, script)
            os.makedirs(os.path.dirname(chemin), exist_ok=True)
            with open(chemin, "w") as f:
                f.write(BOUCHON)
        for table in ("thread/table.json", "zigbee/table.json"):
            with open(os.path.join(anon, table), "w") as f:
                f.write('{"liste": "%s"}' % os.path.join(self.depot, "garde.local.txt"))
        crochet = os.path.join(self.depot, ".git", "hooks", "pre-push")
        shutil.copy(os.path.join(OUTILS, "pre-push"), crochet)
        os.chmod(crochet, 0o755)
        self.ecrire("README.md", "propre\n")
        git(self.depot, "add", "-A")
        git(self.depot, "commit", "-q", "-m", "Racine propre")
        git(self.depot, "remote", "add", "essai", self.nu)

    @staticmethod
    def identite(depot, nom="Djoko-cli", adresse=NOREPLY):
        git(depot, "config", "user.name", nom)
        git(depot, "config", "user.email", adresse)

    def ecrire(self, nom, texte):
        with open(os.path.join(self.depot, nom), "w") as f:
            f.write(texte)

    def commit(self, message, **fichiers):
        for nom, texte in fichiers.items():
            self.ecrire(nom, texte)
        git(self.depot, "add", "-A")
        git(self.depot, "commit", "-q", "--allow-empty", "-m", message)

    def pousser(self, *args):
        """Code de sortie de `git push essai ARGS...` (le hook decide)."""
        return git(self.depot, "push", "essai", *args, ok=False).returncode

    def fermer(self):
        shutil.rmtree(self.racine, ignore_errors=True)


class PrePushTests(unittest.TestCase):
    def setUp(self):
        self.b = Banc()

    def tearDown(self):
        self.b.fermer()

    def test_push_propre_accepte(self):
        self.assertEqual(self.b.pousser("main"), 0)

    def test_valeur_ajoutee_puis_retiree_dans_le_meme_push_refusee(self):
        self.b.commit("Ajout", **{"notes.txt": "fuite " + SECRET + "\n"})
        self.b.commit("Retrait", **{"notes.txt": "propre\n"})
        self.assertNotEqual(self.b.pousser("main"), 0)

    def test_branche_non_extraite_refusee(self):
        git(self.b.depot, "checkout", "-q", "-b", "s2")
        self.b.commit("Fuite", **{"notes.txt": SECRET + "\n"})
        git(self.b.depot, "checkout", "-q", "main")
        self.assertNotEqual(self.b.pousser("s2"), 0)

    def test_prenom_dans_un_message_seul_refuse(self):
        self.b.commit("Essai " + SECRET)
        self.assertNotEqual(self.b.pousser("main"), 0)

    def test_liste_absente_refusee(self):
        os.remove(os.path.join(self.b.depot, "garde.local.txt"))
        self.assertNotEqual(self.b.pousser("main"), 0)

    def test_auteur_hors_noreply_refuse(self):
        Banc.identite(self.b.depot, adresse="quelquun@example.com")
        self.b.commit("Autre adresse")
        self.assertNotEqual(self.b.pousser("main"), 0)

    def test_nom_d_auteur_avec_une_vraie_valeur_refuse(self):
        Banc.identite(self.b.depot, nom=SECRET)
        self.b.commit("Nom d'auteur")
        self.assertNotEqual(self.b.pousser("main"), 0)

    def test_tag_annote_avec_une_vraie_valeur_refuse(self):
        self.assertEqual(self.b.pousser("main"), 0)
        git(self.b.depot, "tag", "-a", "v0", "-m", "Version " + SECRET)
        self.assertNotEqual(self.b.pousser("v0"), 0)

    def test_push_force_par_dessus_un_commit_distant_inconnu_refuse(self):
        self.assertEqual(self.b.pousser("main"), 0)
        autre = os.path.join(self.b.racine, "autre")
        subprocess.run(["git", "clone", "-q", self.b.nu, autre], check=True)
        Banc.identite(autre)
        git(autre, "commit", "-q", "--allow-empty", "-m", "Commit d'un autre poste")
        git(autre, "push", "-q", "--no-verify", "origin", "main")
        self.b.commit("Commit local propre")  # jamais de push force, meme propre (spec, section 5.1)
        self.assertNotEqual(self.b.pousser("--force", "main"), 0)

    def test_push_force_qui_reecrit_l_historique_refuse(self):
        self.b.commit("Second")
        self.assertEqual(self.b.pousser("main"), 0)
        git(self.b.depot, "reset", "-q", "--hard", "HEAD~1")
        self.b.commit("Second bis")
        self.assertNotEqual(self.b.pousser("--force", "main"), 0)

    def test_commits_connus_d_un_remote_tiers_controles(self):
        tiers = os.path.join(self.b.racine, "tiers")
        subprocess.run(["git", "init", "-q", "-b", "main", tiers], check=True)
        Banc.identite(tiers)
        with open(os.path.join(tiers, "notes.txt"), "w") as f:
            f.write(SECRET + "\n")
        git(tiers, "add", "-A")
        git(tiers, "commit", "-q", "-m", "Depot tiers")
        git(self.b.depot, "remote", "add", "tiers", tiers)
        git(self.b.depot, "fetch", "-q", "tiers")
        self.assertNotEqual(self.b.pousser("tiers/main:refs/heads/importe"), 0)

    def test_merge_qui_ajoute_une_valeur_refuse(self):
        git(self.b.depot, "checkout", "-q", "-b", "cote")
        self.b.commit("Cote", **{"cote.txt": "propre\n"})
        git(self.b.depot, "checkout", "-q", "main")
        self.b.commit("Principal", **{"principal.txt": "propre\n"})
        git(self.b.depot, "merge", "-q", "--no-ff", "--no-commit", "cote")
        self.b.ecrire("fusion.txt", SECRET + "\n")
        git(self.b.depot, "add", "-A")
        git(self.b.depot, "commit", "-q", "-m", "Fusion")
        git(self.b.depot, "rm", "-q", "fusion.txt")
        git(self.b.depot, "commit", "-q", "-m", "Retrait")
        self.assertNotEqual(self.b.pousser("main"), 0)


if __name__ == "__main__":
    unittest.main()
