"""Les deux controles d'anonymisation prives de Maillage IoT, en un seul appel (celui de publication.py).

  python3 outils/anonymisation_double.py fichiers --table IGNOREE F...

Meme interface que le controle prive que publication.controler lance (`fichiers --table TABLE F...`) : l'argument
--table est lu mais ignore, chaque controle prend sa table. Lance, l'un apres l'autre et tous les deux quoi qu'il
arrive :
  <PRIVE>/thread/outils/controles.py  avec <PRIVE>/thread/table.json   (le controle de Maillage Thread)
  <PRIVE>/zigbee/controles.py         avec <PRIVE>/zigbee/table.json   (le controle de Maillage Zigbee)
(les memes chemins que outils/pre-push). Code 0 si les deux rendent 0 ; code 1 si l'un echoue, manque (script ou
table absents) ou si le dossier prive est introuvable : jamais un succes vide.

PRIVE : la variable ANONYMISATION_PRIVE, sinon `.superpowers/anonymisation` du depot PRINCIPAL (trouve par
`git rev-parse --git-common-dir`, pour qu'un worktree le trouve aussi). Un clone de repetition, lui, pose la variable.
Surcharges pour les tests seulement : CONTROLE_THREAD, TABLE_THREAD, CONTROLE_ZIGBEE, TABLE_ZIGBEE (le chemin du script
ou de la table de chaque controle). Elles ne servent qu'aux tests de ce script, avec de faux controles.

Sortie : seulement les comptes de chaque controle (les entiers de la derniere ligne qu'il imprime) et son code, jamais
une ligne de fichier controle ni la sortie d'erreur d'un controle.
"""
import os
import re
import subprocess
import sys

USAGE = "usage : anonymisation_double.py fichiers --table IGNOREE FICHIER..."


def dossier_prive():
    """Le dossier prive des controles (variable ANONYMISATION_PRIVE, sinon celui du depot principal) ; None si
    on ne le trouve pas."""
    variable = os.environ.get("ANONYMISATION_PRIVE")
    if variable:
        return variable
    ici = os.path.dirname(os.path.abspath(__file__))
    r = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True, cwd=ici)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    commun = os.path.abspath(os.path.join(ici, r.stdout.strip()))
    return os.path.join(os.path.dirname(commun), ".superpowers", "anonymisation")


def controles():
    """[(nom, script, table)] des deux controles prives."""
    prive = dossier_prive()
    base = prive if prive else os.path.join("introuvable", "anonymisation")
    e = os.environ
    return [
        ("thread", e.get("CONTROLE_THREAD") or os.path.join(base, "thread", "outils", "controles.py"),
         e.get("TABLE_THREAD") or os.path.join(base, "thread", "table.json")),
        ("zigbee", e.get("CONTROLE_ZIGBEE") or os.path.join(base, "zigbee", "controles.py"),
         e.get("TABLE_ZIGBEE") or os.path.join(base, "zigbee", "table.json")),
    ]


def comptes(sortie):
    """Les entiers de la derniere ligne non vide de la sortie d'un controle : rien d'autre n'est relaye."""
    lignes = [l for l in sortie.splitlines() if l.strip()]
    return re.findall(r"\d+", lignes[-1]) if lignes else []


def lancer(nom, script, table, fichiers):
    """Rend True si le controle `nom` reussit ; imprime ses comptes."""
    if not os.path.isfile(script) or not os.path.isfile(table):
        print("controle %s : absent (script ou table introuvable) : echec" % nom)
        return False
    r = subprocess.run([sys.executable, script, "fichiers", "--table", table] + fichiers,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace")
    print("controle %s : code %d, comptes %s" % (nom, r.returncode, " ".join(comptes(r.stdout)) or "aucun"))
    return r.returncode == 0


def main(argv):
    if len(argv) < 3 or argv[0] != "fichiers" or argv[1] != "--table":
        print(USAGE, file=sys.stderr)
        return 1
    fichiers = argv[3:]
    if dossier_prive() is None and not (os.environ.get("CONTROLE_THREAD") and os.environ.get("CONTROLE_ZIGBEE")):
        print("controle d'anonymisation : dossier prive introuvable (ANONYMISATION_PRIVE) : echec")
        return 1
    # Les deux controles tournent toujours : le rapport donne les comptes de chacun.
    resultats = [lancer(nom, script, table, fichiers) for nom, script, table in controles()]
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
