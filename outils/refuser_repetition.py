"""Garde de publication : l'identite de repetition (« Maillage IoT Repetition », phase 4, tache 8) n'est JAMAIS publiee.

  python3 -I outils/refuser_repetition.py CIBLE                      code 1 si CIBLE est la repetition
  python3 -I outils/refuser_repetition.py --verifier-est-repetition CIBLE   l'inverse (outils/repetition.sh controle son produit)

CIBLE : une app (.app), un Info.plist, ou un identifiant de bundle. La publication (outils/publier.sh, phase 5) l'appelle sur
l'app a publier, AVANT toute signature, notarisation ou ecriture du flux : une repetition qui y passerait installerait chez
les utilisateurs une app sans mise a jour, aux services de trousseau a part.

Une cible est la repetition si l'un de ces signes y est : identifiant de bundle qui se termine par `.repetition`, cle
`MaillageSuffixeServices` non vide dans l'Info.plist (IdentiteApp), « Repetition » (sans accent ni casse) dans son nom.
"""
import os
import plistlib
import sys

SUFFIXE = ".repetition"
CLE_SUFFIXE = "MaillageSuffixeServices"


def charger_info(cible):
    """L'Info.plist de CIBLE (dict) ; un identifiant seul donne un dict a cet identifiant."""
    if os.path.isdir(cible):
        chemin = os.path.join(cible, "Contents", "Info.plist")
        if not os.path.isfile(chemin):
            raise FileNotFoundError("pas d'Info.plist dans " + cible)
    elif os.path.isfile(cible):
        chemin = cible
    else:
        return {"CFBundleIdentifier": cible}
    with open(chemin, "rb") as f:
        return plistlib.load(f)


def signes_de_repetition(info):
    """Les signes qui font de cette app la repetition (liste vide : l'app publiable)."""
    signes = []
    identifiant = str(info.get("CFBundleIdentifier", ""))
    if identifiant.lower().endswith(SUFFIXE):
        signes.append("identifiant " + identifiant)
    if str(info.get(CLE_SUFFIXE, "")) != "":
        signes.append("cle " + CLE_SUFFIXE)
    for cle in ("CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"):
        valeur = str(info.get(cle, ""))
        if "repetition" in valeur.lower().replace("é", "e"):
            signes.append(cle + " " + valeur)
    return signes


def main(argv):
    inverse = False
    if argv and argv[0] == "--verifier-est-repetition":
        inverse, argv = True, argv[1:]
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        signes = signes_de_repetition(charger_info(argv[0]))
    except (OSError, plistlib.InvalidFileException) as e:
        print("refuser_repetition : %s illisible (%s)" % (argv[0], e), file=sys.stderr)
        return 2
    if inverse:
        return 0 if signes else 1
    if signes:
        print("refuse : l'identite de repetition n'est jamais publiee (%s)" % ", ".join(signes), file=sys.stderr)
        return 1
    print("refuser_repetition : %s est publiable (pas l'identite de repetition)" % argv[0])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
