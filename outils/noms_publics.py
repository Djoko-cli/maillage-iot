"""Membres publics des extensions de types du coeur, pour outils/verifier-noms-publics.sh.

L'app de l'etape 3 importe ProtocoleThread et ProtocoleZigbee ensemble. Un membre public d'extension (init, methode,
propriete) declare par les deux modules sur un meme type, sous les memes etiquettes, y serait ambigu ; un init
d'extension dont les etiquettes sont un sous-ensemble ordonne de celles d'un init du coeur capterait en silence un
appel de l'autre protocole qui omet les etiquettes en trop. Deux controles :

  python3 -I outils/noms_publics.py communs ProtocoleThread ProtocoleZigbee
  python3 -I outils/noms_publics.py captes MaillageCoeur ProtocoleThread ProtocoleZigbee

Chacun affiche une ligne par defaut et rend 1 s'il en trouve, 0 sinon. Lecture simple du source (pas de compilateur) :
les commentaires et les chaines sont ignores, les accolades et les parentheses se suivent.
"""
import os
import re
import sys

ACCES = {"public", "open", "internal", "fileprivate", "private", "package"}
MODIFICATEURS = ACCES | {
    "static", "final", "mutating", "nonmutating", "nonisolated", "convenience", "required", "override", "indirect",
    "lazy", "dynamic", "class", "weak", "unowned", "prefix", "postfix", "infix", "isolated", "distributed",
}
TYPES = ("struct", "enum", "class", "actor", "protocol", "extension")
MEMBRES = ("init", "func", "var", "let", "subscript", "typealias")

_MOTIF_NETTOYAGE = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*[\s\S]*?\*/')
_ATTRIBUT = re.compile(r"@\w+(\([^)]*\))?\s*")
_MOT = re.compile(r"(\w+)(\([^)]*\))?\s*")
_SEULEMENT_ATTRIBUTS = re.compile(r"(\s*@\w+(\([^)]*\))?)+\s*")


def nettoyer(texte):
    """Le source sans commentaires ni contenu de chaines (les sauts de ligne des blocs sont gardes)."""
    def remplacer(m):
        s = m.group(0)
        if s.startswith("/*"):
            return "\n" * s.count("\n")
        if s.startswith("//"):
            return ""
        return '""'
    return _MOTIF_NETTOYAGE.sub(remplacer, texte)


def fermante(t, i):
    """Indice de l'accolade fermante qui correspond a l'ouvrante `t[i]` (fin du texte si elle manque)."""
    profondeur = 0
    for j in range(i, len(t)):
        if t[j] == "{":
            profondeur += 1
        elif t[j] == "}":
            profondeur -= 1
            if profondeur == 0:
                return j
    return len(t) - 1


def decouper(t, a, b):
    """Les declarations du niveau `t[a:b]` : (tete, debut du corps, fin du corps), le corps valant None sans accolades."""
    res = []
    debut = a
    parentheses = 0
    i = a
    while i < b:
        c = t[i]
        if c in "([":
            parentheses += 1
        elif c in ")]":
            parentheses -= 1
        elif c == "{":
            j = fermante(t, i)
            if parentheses > 0:
                i = j + 1
                continue
            res.append((t[debut:i], i + 1, j))
            i = j + 1
            debut = i
            continue
        elif (c == "\n" and parentheses == 0) or c == ";":
            tete = t[debut:i]
            suite = t[i + 1:b].lstrip()
            if not tete.strip():
                debut = i + 1
            elif _SEULEMENT_ATTRIBUTS.fullmatch(tete):
                pass  # attribut seul sur sa ligne : la declaration suit
            elif tete.rstrip().endswith((",", "=", ":", "->", "&&", "||")) or suite.startswith(("where ", "->")):
                pass  # la declaration continue sur la ligne suivante
            else:
                res.append((tete, None, None))
                debut = i + 1
        i += 1
    return res


def generiques(s, i):
    """Indice juste apres un bloc `<...>` qui commence en `s[i]` (i inchange s'il n'y en a pas)."""
    if i >= len(s) or s[i] != "<":
        return i
    profondeur = 0
    for j in range(i, len(s)):
        if s[j] == "<":
            profondeur += 1
        elif s[j] == ">" and s[j - 1] != "-":
            profondeur -= 1
            if profondeur == 0:
                return j + 1
    return i


def parametres(s, i):
    """Les etiquettes de la liste de parametres qui commence en `s[i] == "("` : `["id", "_", ...]`."""
    if i >= len(s) or s[i] != "(":
        return None
    profondeur = 0
    morceaux = []
    courant = ""
    j = i + 1
    while j < len(s):
        c = s[j]
        if c in "([{":
            profondeur += 1
        elif c in ")]}":
            if profondeur == 0 and c == ")":
                break
            profondeur -= 1
        elif c == "<":
            profondeur += 1
        elif c == ">" and s[j - 1] != "-":
            profondeur -= 1
        if c == "," and profondeur == 0:
            morceaux.append(courant)
            courant = ""
        else:
            courant += c
        j += 1
    if courant.strip():
        morceaux.append(courant)
    etiquettes = []
    for m in morceaux:
        avant = m.split(":", 1)[0].split()
        etiquettes.append(avant[0] if avant else "_")
    return etiquettes


def analyser(tete):
    """(acces explicite, genre, nom, etiquettes) d'une declaration ; genre None si ce n'en est pas une."""
    h = tete.strip()
    while True:
        m = _ATTRIBUT.match(h)
        if not m:
            break
        h = h[m.end():]
    acces = None
    while True:
        m = _MOT.match(h)
        if not m or m.group(1) not in MODIFICATEURS:
            break
        mot = m.group(1)
        if mot == "class" and not re.match(r"class\s+(func|var|let)\b", h):
            break
        if mot in ACCES and acces is None and m.group(2) != "(set)":
            acces = mot
        h = h[m.end():]
    m = re.match(r"(init[?!]?|func|var|let|subscript|typealias|struct|enum|class|actor|protocol|extension)\b\s*", h)
    if not m:
        return acces, None, None, None
    genre = m.group(1)
    reste = h[m.end():]
    if genre.startswith("init"):
        return acces, "init", "init", parametres(reste, generiques(reste, 0))
    if genre == "subscript":
        return acces, genre, "subscript", parametres(reste, generiques(reste, 0))
    if genre == "extension":
        nom = re.split(r"\s*(?::|\bwhere\b)", reste, maxsplit=1)[0].strip()
        return acces, genre, nom, None
    nom = re.match(r"[^\s(<:=]+", reste)
    if not nom:
        return acces, None, None, None
    suite = generiques(reste, nom.end())
    etiquettes = parametres(reste, suite) if genre == "func" else None
    return acces, genre, nom.group(0), etiquettes


def signature(genre, nom, etiquettes):
    if etiquettes is None:
        return nom
    return "%s(%s)" % (nom, "".join(e + ":" for e in etiquettes))


def declarations(texte):
    """Les membres declares dans des types ou des extensions du fichier :
    (type qualifie, signature, genre, etiquettes, public, dans une extension)."""
    t = nettoyer(texte)
    sortie = []

    def parcourir(a, b, chaine, extension, acces_implicite):
        for tete, c, d in decouper(t, a, b):
            acces, genre, nom, etiquettes = analyser(tete)
            if genre is None:
                continue
            if genre in TYPES:
                if c is None:
                    continue
                if genre == "extension":
                    parcourir(c, d, [nom], True, "public" if acces in ("public", "open") else "internal")
                else:
                    sortie.append((".".join(chaine), nom, genre, None, acces in ("public", "open") or (
                        acces is None and acces_implicite == "public"), extension))
                    parcourir(c, d, chaine + [nom], extension, "internal")
            elif chaine:
                effectif = acces or acces_implicite
                sortie.append((".".join(chaine), signature(genre, nom, etiquettes), genre, etiquettes,
                               effectif in ("public", "open"), extension))

    parcourir(0, len(t), [], False, "internal")
    return sortie


def fichiers_swift(dossier):
    for racine, _, noms in os.walk(dossier):
        for n in sorted(noms):
            if n.endswith(".swift"):
                yield os.path.join(racine, n)


def membres_extension(dossier):
    """{"Type.signature"} des membres publics des extensions du dossier."""
    res = set()
    for f in fichiers_swift(dossier):
        with open(f, encoding="utf-8") as fh:
            for type_, sig, _, _, public, extension in declarations(fh.read()):
                if public and extension:
                    res.add("%s.%s" % (type_, sig))
    return res


def inits_publics(dossier):
    """{type qualifie: [liste d'etiquettes]} des inits publics (de types ou d'extensions) du dossier."""
    res = {}
    for f in fichiers_swift(dossier):
        with open(f, encoding="utf-8") as fh:
            for type_, _, genre, etiquettes, public, _ in declarations(fh.read()):
                if public and genre == "init" and etiquettes is not None:
                    res.setdefault(type_, []).append(etiquettes)
    return res


def sous_suite(courte, longue):
    """`courte` est une suite strictement plus courte, dans l'ordre, des elements de `longue`."""
    if len(courte) >= len(longue):
        return False
    it = iter(longue)
    return all(e in it for e in courte)


def communs(a, b):
    return sorted(membres_extension(a) & membres_extension(b))


def captes(coeur, module):
    """Les inits d'extension du module dont les etiquettes sont un sous-ensemble ordonne de celles d'un init du coeur."""
    pris = inits_publics(coeur)
    res = []
    for f in fichiers_swift(module):
        with open(f, encoding="utf-8") as fh:
            for type_, sig, genre, etiquettes, public, extension in declarations(fh.read()):
                if not (public and extension and genre == "init" and etiquettes is not None):
                    continue
                for complet in pris.get(type_, []):
                    if sous_suite(etiquettes, complet):
                        res.append("%s.%s (init du coeur : %s)" % (
                            type_, sig, "".join(e + ":" for e in complet)))
                        break
    return sorted(res)


def main(argv):
    if len(argv) == 4 and argv[1] == "communs":
        defauts = ["membre d'extension public commun aux deux protocoles : " + x for x in communs(argv[2], argv[3])]
    elif len(argv) == 5 and argv[1] == "captes":
        defauts = []
        for module in argv[3:]:
            defauts += ["init d'extension qui capte un appel du coeur (%s) : %s" % (module, x)
                        for x in captes(argv[2], module)]
    else:
        print(__doc__)
        return 2
    for d in defauts:
        print(d)
    return 1 if defauts else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
