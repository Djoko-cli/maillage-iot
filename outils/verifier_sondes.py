"""Garde des deux sondes (SondeMaillageThread, SondeMaillageZigbee), pour outils/verifier-sondes.sh.

Chaque sonde est decoupee en fichiers par role (MaillageIoT/<P>/Sonde/SondeMaillage<P>*.swift). Swift n'a pas d'acces
« ce fichier et ses extensions » d'un fichier a l'autre : les proprietes d'etat observe que les extensions ecrivent ont
perdu leur `private(set)`. Ce controle tient la regle a la place du compilateur. Trois controles :

1. aucune de ces proprietes n'est affectee hors des fichiers de la sonde (code de l'app et tests) : `sonde.etat = ...`,
   `sondeThread.serie = ...`, `sondeZigbee.acces = ...`, y compris `+=` et les ajouts a une collection ;
2. `ouvrirCanal(` et `ouvrable(` n'apparaissent que dans le fichier +USB de chaque sonde : une seule porte d'ouverture
   des ports, gardee par `ouvrable` ;
3. la liste ci-dessous suit le source : chaque propriete listee est declaree `var` (non privee) dans le fichier principal
   de sa sonde, et toute autre `var` observee du fichier principal est listee ou exemptee.

  python3 -I outils/verifier_sondes.py [racine]

Une ligne par defaut ; code 1 s'il y en a, 0 sinon. Lecture simple du source (pas de compilateur) : les commentaires et
les chaines sont ignores ; l'ecriture par un recepteur d'un autre nom que ceux ci-dessous (`RECEPTEURS`, plus les noms
declares avec le type de la sonde dans le meme fichier) echappe au controle 1.
"""
import os
import re
import sys

# Proprietes d'etat observe passees de `private(set)` a internes par la decoupe (le principal les declare ; les
# extensions les ecrivent). Tache 1 (Thread : les 21 du rapport, plus `portsVus`) et tache 2 (Zigbee : 22, plus `portsVus`) de la phase 3c ;
# `portsVus` etait `private var` observee, que les extensions ecrivent aussi.
PROPRIETES = {
    "Thread": [
        "etat", "serie", "choixRefuse", "nom", "serieEtat", "etatSonde", "derniereTournee", "erreurTournee", "couverture",
        "tourneeEnCours", "avancement", "debutTournee", "reglage", "liaison", "annonces", "hote", "empreinteAcces",
        "autorisationEnCours", "erreurAcces", "dernierePerte", "actif", "portsVus",
    ],
    "Zigbee": [
        "etat", "serie", "choixRefuse", "nom", "serieEtat", "etatSonde", "derniereTournee", "tourneeEnCours", "avancement",
        "debutTournee", "bilan", "passeComplementaire", "acces", "ieee", "nomWifi", "annoncee", "bonjourNonDeclare",
        "empreinteAcces", "tourneeDifferee", "dureeTournee", "erreurTournee", "actif", "portsVus",
    ],
}
# `var` observees du fichier principal qui restent ecrites de l'exterieur, par conception (reglage choisi aux Reglages).
EXEMPTEES = {"Thread": set(), "Zigbee": {"reglageChemin"}}
# Noms sous lesquels une sonde se trouve dans l'app et les tests ; s'y ajoutent les noms declares avec son type.
RECEPTEURS = {"sonde", "sondeThread", "sondeZigbee", "laSonde", "pilote"}
SONDES = ("Thread", "Zigbee")
DOSSIERS = ("MaillageIoT", "MaillageIoTTests")
FICHIER_SONDE = re.compile(r"^MaillageIoT/(Thread|Zigbee)/Sonde/SondeMaillage\1(\+\w+)?\.swift$")
FICHIER_USB = re.compile(r"^MaillageIoT/(Thread|Zigbee)/Sonde/SondeMaillage\1\+USB\.swift$")

_NETTOYAGE = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*[\s\S]*?\*/')
_OPERATEUR = r"(?:=(?!=)|[-+*/%&|^]=|<<=|>>=)"
_MUTATIONS = ("insert|remove|removeAll|append|formUnion|formIntersection|formSymmetricDifference|subtract|removeValue|"
              "removeFirst|removeLast|popFirst|popLast|sort|swapAt|reverse")
_TYPE_SONDE = re.compile(r"\b(\w+)\s*:\s*SondeMaillage(?:Thread|Zigbee)\b|"
                         r"\b(?:let|var)\s+(\w+)\s*=\s*SondeMaillage(?:Thread|Zigbee)\s*\(")


def nettoyer(texte):
    """Le source sans commentaires ni chaines (memes lignes : les retours a la ligne sont gardes)."""
    return _NETTOYAGE.sub(lambda m: "\n" * m.group(0).count("\n"), texte)


def fichiers_swift(racine):
    for dossier in DOSSIERS:
        for chemin, _, noms in os.walk(os.path.join(racine, dossier)):
            for nom in sorted(noms):
                if nom.endswith(".swift"):
                    yield os.path.relpath(os.path.join(chemin, nom), racine).replace(os.sep, "/")


def lire(racine, rel):
    with open(os.path.join(racine, rel), encoding="utf-8") as f:
        return f.read()


def ecritures(texte, noms):
    """Les affectations d'une propriete de `noms` par un recepteur de sonde : (numero de ligne, texte de la ligne)."""
    recepteurs = set(RECEPTEURS)
    for m in _TYPE_SONDE.finditer(texte):
        recepteurs.add(m.group(1) or m.group(2))
    r = "|".join(sorted(map(re.escape, recepteurs)))
    p = "|".join(sorted(map(re.escape, noms)))
    motif = re.compile(r"(?<![\w])(?:%s)[?!]?\.(?:%s)\b(?:\[[^\]\n]*\])?\s*%s|"
                       r"(?<![\w])(?:%s)[?!]?\.(?:%s)\.(?:%s)\(" % (r, p, _OPERATEUR, r, p, _MUTATIONS))
    lignes = texte.split("\n")
    return [(i + 1, lignes[i].strip()) for i in range(len(lignes)) if motif.search(lignes[i])]


def appels_ouverture(texte):
    motif = re.compile(r"\b(?:ouvrirCanal|ouvrable)\s*\(")
    lignes = texte.split("\n")
    return [(i + 1, lignes[i].strip()) for i in range(len(lignes)) if motif.search(lignes[i])]


def vars_observees(texte):
    """Noms des `var` stockees du fichier principal qui sont de l'etat observe : membres de la classe (indentation 4),
    ni privees, ni @ObservationIgnored, ni calculees (un corps `{` sans valeur `=` avant lui)."""
    noms = []
    for ligne in texte.split("\n"):
        m = re.match(r"^    var (\w+)\b(.*)$", ligne)
        if not m:
            continue
        avant_accolade = m.group(2).split("{")[0]
        if "{" in m.group(2) and "=" not in avant_accolade:
            continue
        noms.append(m.group(1))
    return noms


def controler(racine):
    defauts = []
    noms = {n for s in SONDES for n in PROPRIETES[s]}
    # 3. la liste suit le source
    for s in SONDES:
        rel = "MaillageIoT/%s/Sonde/SondeMaillage%s.swift" % (s, s)
        if not os.path.exists(os.path.join(racine, rel)):
            defauts.append("%s : fichier principal de la sonde %s absent" % (rel, s))
            continue
        declarees = vars_observees(nettoyer(lire(racine, rel)))
        for n in PROPRIETES[s]:
            if n not in declarees:
                defauts.append("%s : %s est dans la liste de outils/verifier_sondes.py mais n'y est plus declaree `var` "
                               "stockee non privee (liste a mettre a jour)" % (rel, n))
        for n in declarees:
            if n not in PROPRIETES[s] and n not in EXEMPTEES[s]:
                defauts.append("%s : `var %s` observee, ni listee ni exemptee dans outils/verifier_sondes.py "
                               "(une extension qui l'ecrit lui a-t-elle fait perdre son private(set) ?)" % (rel, n))
    # 1 et 2
    for rel in fichiers_swift(racine):
        texte = nettoyer(lire(racine, rel))
        if not FICHIER_SONDE.match(rel):
            for i, l in ecritures(texte, noms):
                defauts.append("%s:%d : etat de sonde ecrit hors de son pilote : %s" % (rel, i, l))
        if not FICHIER_USB.match(rel):
            for i, l in appels_ouverture(texte):
                defauts.append("%s:%d : ouverture de port hors du fichier +USB de sa sonde : %s" % (rel, i, l))
    return defauts


def main(argv):
    racine = argv[1] if len(argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    defauts = controler(racine)
    for d in defauts:
        print(d)
    if not defauts:
        print("verifier-sondes : etat des sondes ecrit par leur pilote seulement, ports ouverts par leur fichier +USB seulement")
    return 1 if defauts else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
