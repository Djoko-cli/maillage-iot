"""Garde de publication : l'identite de repetition (« Maillage IoT Repetition », phase 4, tache 8) n'est JAMAIS publiee.

  python3 -I outils/refuser_repetition.py CIBLE                      code 1 si CIBLE est la repetition
  python3 -I outils/refuser_repetition.py --verifier-est-repetition CIBLE   l'inverse (outils/repetition.sh controle son produit)

CIBLE : une app (.app), un Info.plist, ou un identifiant de bundle NU (forme d'identifiant : segments de lettres, chiffres
et tirets separes par des points, sans « / » ni espace, et ne finissant pas par « .app » ou « .plist »). La garde n'echoue
jamais ouvert : une cible qui n'existe pas, qu'on ne lit pas, ou dont l'Info.plist n'a pas d'identifiant sort en code 2, avec sa
cause (jamais « publiable »). La publication (outils/publier.sh, phase 5) l'appelle sur
l'app a publier, AVANT toute signature, notarisation ou ecriture du flux : une repetition qui y passerait installerait chez
les utilisateurs une app sans mise a jour, aux services de trousseau a part.

Une cible est la repetition si l'un de ces signes y est : identifiant de bundle qui se termine par `.repetition`, cle
`MaillageSuffixeServices` non vide dans l'Info.plist (IdentiteApp), « Repetition » (sans accent ni casse) dans son nom.
"""
import os
import plistlib
import re
import sys
from xml.parsers.expat import ExpatError

SUFFIXE = ".repetition"
CLE_SUFFIXE = "MaillageSuffixeServices"


IDENTIFIANT = re.compile(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$")


class CibleIllisible(Exception):
    """La cible n'est ni une app, ni un Info.plist, ni un identifiant nu : la garde refuse de conclure."""


def est_identifiant_nu(cible):
    return bool(IDENTIFIANT.match(cible)) and not cible.lower().endswith((".app", ".plist"))


def charger_info(cible):
    """L'Info.plist de CIBLE (dict) ; un identifiant nu explicite donne un dict a cet identifiant."""
    if os.path.isdir(cible):
        chemin = os.path.join(cible, "Contents", "Info.plist")
        if not os.path.isfile(chemin):
            raise CibleIllisible("pas d'Info.plist dans " + cible)
    elif os.path.isfile(cible):
        chemin = cible
    elif est_identifiant_nu(cible):
        return {"CFBundleIdentifier": cible}
    else:
        raise CibleIllisible("ni une app ni un Info.plist qui existe, ni un identifiant de bundle")
    with open(chemin, "rb") as f:
        info = plistlib.load(f)
    if not isinstance(info, dict):
        raise CibleIllisible("Info.plist qui n'est pas un dictionnaire")
    return info


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
        info = charger_info(argv[0])
        signes = signes_de_repetition(info)
        # Un signe de repetition suffit a refuser ; sans signe, une app sans identifiant n'est pas un « publiable » : on ne sait pas ce qu'elle est.
        if not signes and not str(info.get("CFBundleIdentifier", "")).strip():
            raise CibleIllisible("Info.plist sans CFBundleIdentifier")
    except (OSError, ValueError, ExpatError, plistlib.InvalidFileException, CibleIllisible) as e:
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
