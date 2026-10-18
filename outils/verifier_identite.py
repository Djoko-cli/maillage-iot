"""Garde d'identite (phase 4, tache 8), lancee par outils/tester.sh :

  python3 -I outils/verifier_identite.py [--racine DOSSIER]      code 1 si un litteral d'identite est en dur

Refuse tout litteral de chaine « fr.djoko.maillage... » dans le code de l'app (MaillageIoT, MaillageCoeur, ProtocoleThread,
ProtocoleZigbee) hors du fichier d'identite (MaillageIoT/Commun/IdentiteApp.swift) et des cas listes ci-dessous (fichier +
litteral exacts). Les services du trousseau, le domaine des preferences et les chemins viennent de IdentiteApp : l'app de
repetition (« Maillage IoT Repetition », identifiant et suffixe `.repetition`) ecrit ainsi dans SES services. Un service de
l'app reelle ecrit en dur (par exemple `TrousseauSystemeThread(service: "fr.djoko.maillage.iot.sonde-thread")`) ferait ecrire
la repetition dans le trousseau de l'app reelle, et aucun test de l'app n'en saurait rien : les tests tournent dans l'app reelle.

Les commentaires ne comptent pas ; les tests (MaillageIoTTests...) ne sont pas controles. Un cas liste dont le litteral a disparu
de son fichier est lui aussi refuse : la liste ne grossit pas en silence.
"""
import argparse
import os
import sys

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DOSSIERS = ("MaillageIoT", "MaillageCoeur", "ProtocoleThread", "ProtocoleZigbee")
FICHIER_IDENTITE = "MaillageIoT/Commun/IdentiteApp.swift"
MOTIF = "fr.djoko.maillage"

# Cas admis : fichier -> litteraux exacts. Aucun n'est un service de trousseau, un domaine de preferences ni un chemin de
# l'app reelle ecrit : noms en memoire du processus (files d'attente, etiquettes de liaison serie), sous-systeme d'un journal
# systeme (coeur : il ne voit pas IdentiteApp), ou noms d'ANCIENNES apps, que la reprise lit seulement.
ADMIS = {
    "MaillageIoT/Commun/Bonjour/ResolveurDNSSD.swift": ("fr.djoko.maillage.iot.dnssd",),
    "MaillageIoT/Zigbee/Sonde/CanalReseauTCP.swift": ("fr.djoko.maillage.iot.sonde-zigbee.tcp",),
    "MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee.swift": ("fr.djoko.maillage.iot.sonde-zigbee",),
    "MaillageIoT/Thread/Sonde/SondeMaillageThread.swift": ("fr.djoko.maillage.iot.sonde-thread",),
    "MaillageIoT/Thread/Sonde/Reseau/TransportUDP.swift": ("fr.djoko.maillage.iot.sonde-thread.udp",),
    "MaillageIoT/Reprise/AncienneAppEnCours.swift": ("fr.djoko.maillage.iot.quitter-ancienne-app",),
    "MaillageCoeur/Systeme/FichiersGardes.swift": ("fr.djoko.maillage.iot",),
    "MaillageIoT/Zigbee/Pont/TrousseauZigbee.swift": ("fr.djoko.maillage.zigbee.pont", "fr.djoko.maillage.zigbee.sonde"),
    "MaillageIoT/Thread/Sonde/Reseau/TrousseauReprisThread.swift": ("fr.djoko.maillage.sonde",),
    "MaillageIoT/Noms/NomsPasseur.swift": ("fr.djoko.maillage.passeur",),
    "MaillageCoeur/Reprise/ContratExport.swift": ("fr.djoko.maillage", "fr.djoko.maillage.zigbee"),
}


def litteraux(source):
    """[(ligne, texte)] des chaines de la source Swift, hors commentaires (interpolations exclues du texte)."""
    trouves = []
    n = len(source)

    def _debut_brut(src, i):
        j = i
        while j < n and src[j] == "#":
            j += 1
        return j < n and src[j] == '"'

    def code(i, ligne, interpolation):
        """Parcourt du code depuis i ; rend (i, ligne) en fin de source, ou apres la `)` qui ferme une interpolation."""
        profondeur = 0
        while i < n:
            c = source[i]
            if source.startswith("//", i):
                while i < n and source[i] != "\n":
                    i += 1
            elif source.startswith("/*", i):
                niveau = 0
                while i < n:
                    if source.startswith("/*", i):
                        niveau, i = niveau + 1, i + 2
                    elif source.startswith("*/", i):
                        niveau, i = niveau - 1, i + 2
                        if niveau == 0:
                            break
                    else:
                        ligne += source[i] == "\n"
                        i += 1
            elif c == '"' or (c == "#" and _debut_brut(source, i)):
                i, ligne = chaine(i, ligne)
            else:
                if interpolation:
                    if c == "(":
                        profondeur += 1
                    elif c == ")":
                        if profondeur == 0:
                            return i + 1, ligne
                        profondeur -= 1
                ligne += c == "\n"
                i += 1
        return i, ligne

    def chaine(i, ligne):
        debut = ligne
        dieses = 0
        while source[i] == "#":
            dieses, i = dieses + 1, i + 1
        multi = source.startswith('"""', i)
        ouvrant = '"""' if multi else '"'
        i += len(ouvrant)
        fermant = ouvrant + "#" * dieses
        echappement = "\\" + "#" * dieses
        morceaux = []
        while i < n:
            if source.startswith(fermant, i):
                i += len(fermant)
                break
            if source.startswith(echappement, i):
                i += len(echappement)
                if i < n and source[i] == "(":
                    i, ligne = code(i + 1, ligne, True)
                else:
                    i += 1
                continue
            if not multi and source[i] == "\n":  # chaine non fermee : on s'arrete a la ligne
                break
            ligne += source[i] == "\n"
            morceaux.append(source[i])
            i += 1
        trouves.append((debut, "".join(morceaux)))
        return i, ligne

    code(0, 1, False)
    return trouves


def fichiers_swift(racine):
    for dossier in DOSSIERS:
        for chemin, _, noms in sorted(os.walk(os.path.join(racine, dossier))):
            for nom in sorted(noms):
                if nom.endswith(".swift"):
                    yield os.path.relpath(os.path.join(chemin, nom), racine)


def lire(racine, relatif):
    with open(os.path.join(racine, relatif), encoding="utf-8") as f:
        return f.read()


def controler(racine):
    """Les defauts (liste de textes « fichier:ligne : ... ») ; vide : propre."""
    defauts = []
    for relatif in fichiers_swift(racine):
        if relatif == FICHIER_IDENTITE:
            continue
        for ligne, texte in litteraux(lire(racine, relatif)):
            if MOTIF in texte and texte not in ADMIS.get(relatif, ()):
                defauts.append("%s:%d : litteral d'identite en dur \"%s\" (passer par IdentiteApp)" % (relatif, ligne, texte))
    return defauts


def restes(racine):
    """Les cas admis dont le litteral a disparu de son fichier (a retirer de ADMIS)."""
    restes = []
    for relatif, admis in ADMIS.items():
        presents = {t for _, t in litteraux(lire(racine, relatif))} if os.path.isfile(os.path.join(racine, relatif)) else set()
        restes += ["%s : cas admis \"%s\" absent du fichier (a retirer de ADMIS)" % (relatif, t) for t in admis if t not in presents]
    return restes


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--racine", default=RACINE)
    args = p.parse_args(argv)
    problemes = controler(args.racine) + (restes(args.racine) if args.racine == RACINE else [])
    for ligne in problemes:
        print("verifier-identite : " + ligne, file=sys.stderr)
    if problemes:
        return 1
    print("verifier-identite : aucun litteral d'identite en dur (services, preferences et chemins passent par IdentiteApp)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
