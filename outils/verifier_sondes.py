"""Garde des deux sondes (SondeMaillageThread, SondeMaillageZigbee), pour outils/verifier-sondes.sh.

Chaque sonde est decoupee en fichiers par role (MaillageIoT/<P>/Sonde/SondeMaillage<P>*.swift). Swift n'a pas d'acces
« ce fichier et ses extensions » d'un fichier a l'autre : les proprietes d'etat observe que les extensions ecrivent ont
perdu leur `private(set)`. Ce controle tient la regle a la place du compilateur. Cinq controles :

1. aucune de ces proprietes n'est affectee hors des fichiers de la sonde (code de l'app et tests) : `sonde.etat = ...`,
   `sondeThread.serie = ...`, `sondeZigbee.acces = ...`, y compris `+=` et les ajouts a une collection ; il en va de
   meme des poignees de taches et drapeaux de connexion internes (`POIGNEES` : `boucle`, `entretien`, `reessaiReseau`,
   `nouvelEssai`, `reprise`...), jamais affectes hors des fichiers de la sonde ;
2. `ouvrirCanal(` et `ouvrable(` n'apparaissent que dans le fichier +USB de chaque sonde : une seule porte d'ouverture
   des ports, gardee par `ouvrable` ;
3. la liste ci-dessous suit le source : chaque propriete listee est declaree `var` (non privee) dans le fichier principal
   de sa sonde, et toute autre `var` observee du fichier principal est listee ou exemptee ; chaque poignee listee y est
   declaree aussi ;
4. aucune `extension SondeMaillage<P>` (non suivie d'un `.`) hors des fichiers de cette sonde : une extension ailleurs
   ecrirait l'etat sans recepteur, donc sans que le controle 1 la voie ;
5. (dans le controle 1) un recepteur est reconnu par son nom (`RECEPTEURS`) ou parce qu'il est lie a une sonde dans le
   fichier : declare avec le type (`x: SondeMaillageThread`), construit (`let x = SondeMaillageThread(`), obtenu par une
   fabrique (`let x = faire(...)`, avec `try`, `await`, `Self.`/`Type.`, `if let`, `guard let`, `var`), par un tuple
   (`let (x, _) = faire(...)`, a la position de la sonde dans le type rendu), par une conversion (`as! SondeMaillageX`)
   ou par un alias d'un recepteur (`let x = self.sonde`). Une fabrique est toute fonction du source, ou variable de type
   fonction, dont le type rendu est `SondeMaillage<P>` (optionnel ou non) ou un tuple qui en contient un.

  python3 -I outils/verifier_sondes.py [racine]

Une ligne par defaut ; code 1 s'il y en a, 0 sinon. Lecture simple du source (pas de compilateur) : les commentaires et
les chaines (hors chaines brutes `#"..."#` et guillemets imbriques dans une interpolation) sont ignores. Restent hors
d'atteinte d'une lecture textuelle, donc non detectes : une sonde lue dans une collection ou un tuple non destructure
(`liste[0].etat = ...`, `r.0.etat = ...`, `for s in sondes`), tiree d'une fermeture anonyme sans nom
(`let f = { SondeMaillageThread(...) }`), d'un generique ou d'un `typealias`, ou liee en dehors d'un `let`/`var`/`if let`/
`guard let` ; une fabrique dont le type rendu est ecrit par un `typealias` ; un recepteur lie dans un autre fichier que
celui qui l'ecrit (seules les fabriques sont suivies d'un fichier a l'autre). Ces cas n'existent pas dans l'arbre.
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
# Poignees de taches et drapeaux de connexion `@ObservationIgnored`, internes depuis la decoupe : ecrits par les fichiers
# de la sonde seulement (un `sonde.boucle = nil` ailleurs laisserait tourner une tache non annulee). Pas de controle de
# synchronisation avec toutes les `var` du principal : on verifie seulement que chacun y est declare.
POIGNEES = {
    "Thread": ["boucle", "reprise", "nouvelEssai", "retourUSB", "surveillantPorts", "sonde", "enConnexion",
               "cheminConnecte", "canalReseau", "lectureCle"],
    "Zigbee": ["boucle", "entretien", "reessaiReseau", "nouvelEssai", "surveillantPorts", "sonde", "enConnexion",
               "cheminConnecte", "tentativeReseau", "miseEnServiceEnCours", "navigateur"],
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
_SONDE = r"SondeMaillage(?:Thread|Zigbee)"
_TYPE_SONDE = re.compile(r"\b(\w+)\s*:\s*(?:@\w+\s+)*%s\b(?!\s*\.)|"
                         r"\b(?:let|var)\s+(\w+)\s*=\s*%s\s*\(|"
                         r"\b(?:let|var)\s+(\w+)\s*=\s*[^\n=]*?\bas[?!]?\s+%s\b(?!\s*\.)" % (_SONDE, _SONDE, _SONDE))
_EXTENSION = re.compile(r"\bextension\s+(?:\w+\s*\.\s*)*SondeMaillage(Thread|Zigbee)\b(?!\s*\.)")
_ESSAI = r"(?:try[?!]?\s+)?(?:await\s+)?"
_CHAINE = r"(?:\w+\s*[?!]?\s*\.\s*)*"
# `func nom(...) -> Type` et `nom: [@attribut] (...) [async] [throws] -> Type` (variable ou parametre de type fonction)
_FUNC = re.compile(r"\bfunc\s+(\w+)\s*(?:<[^>\n]*>)?\s*\(")
_VAR_FONCTION = re.compile(r"\b(\w+)\s*:\s*(?:@\w+(?:\([^)\n]*\))?\s+)*\([^()\n]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*")


def _equilibre(texte, debut):
    """Le texte entre la parenthese ouvrante a `debut` et sa fermante, et l'indice qui suit ; (None, debut) si absente."""
    prof = 0
    for i in range(debut, len(texte)):
        c = texte[i]
        if c == "(":
            prof += 1
        elif c == ")":
            prof -= 1
            if prof == 0:
                return texte[debut + 1:i], i + 1
    return None, debut


def _positions(type_rendu):
    """Un type rendu -> None (n'est pas une sonde), 'seule' (une sonde) ou l'ensemble des positions d'un tuple qui en
    contient."""
    t = type_rendu.strip()
    if t.startswith("("):
        interieur, fin = _equilibre(t, 0)
        if interieur is None or t[fin:].strip():
            return None
        morceaux, prof, cour = [], 0, ""
        for c in interieur:
            if c in "([<":
                prof += 1
            elif c in ")]>":
                prof -= 1
            if c == "," and prof == 0:
                morceaux.append(cour)
                cour = ""
            else:
                cour += c
        morceaux.append(cour)
        if len(morceaux) == 1:
            return _positions(morceaux[0])
        pos = {i for i, m in enumerate(morceaux) if re.match(r"^(?:\w+\s*:\s*)?%s[?!]?$" % _SONDE, m.strip())}
        return pos or None
    return "seule" if re.match(r"^%s[?!]?$" % _SONDE, t) else None


def _type_apres(texte, debut):
    """Le type ecrit a partir de `debut` : un tuple entre parentheses, ou un mot suivi de ses `?`/`!`/`.Membre`."""
    m = re.compile(r"\s*").match(texte, debut)
    i = m.end()
    if texte[i:i + 1] == "(":
        interieur, fin = _equilibre(texte, i)
        return texte[i:fin] if interieur is not None else ""
    m = re.compile(r"[\w]+(?:\s*\.\s*\w+)*[?!]*").match(texte, i)
    return m.group(0) if m else ""


def fabriques(texte):
    """Les fonctions et variables de type fonction du source qui rendent une sonde : {nom: ensemble de positions d'un
    tuple, ou 'seule' pour une sonde}. Un nom peut avoir plusieurs formes (surcharges)."""
    trouvees = {}

    def noter(nom, type_rendu):
        pos = _positions(type_rendu)
        if pos is not None:
            trouvees.setdefault(nom, []).append(pos)

    for m in _FUNC.finditer(texte):
        _, fin = _equilibre(texte, m.end() - 1)
        if fin == m.end() - 1:
            continue
        reste = re.split(r"\{|\n\s*(?:@\w+\s+)*(?:static\s|private\s|public\s|internal\s|final\s|override\s|"
                         r"nonisolated\s|func\s|var\s|let\s|init\b|subscript\b|\})", texte[fin:fin + 400], maxsplit=1)[0]
        fleche = reste.find("->")
        if fleche >= 0:
            noter(m.group(1), _type_apres(reste, fleche + 2))
    for m in _VAR_FONCTION.finditer(texte):
        noter(m.group(1), _type_apres(texte, m.end()))
    return trouvees


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


def recepteurs_lies(texte, fabs):
    """Les noms sous lesquels une sonde est liee dans ce fichier, en plus de `RECEPTEURS` : declares avec son type,
    construits, convertis, obtenus par une fabrique (seule ou en tuple) ou alias d'un recepteur deja connu."""
    noms = set(RECEPTEURS)
    for m in _TYPE_SONDE.finditer(texte):
        noms.add(m.group(1) or m.group(2) or m.group(3))
    if fabs:
        alt = "|".join(sorted(map(re.escape, fabs)))
        appel = re.compile(r"(?:\b(?:let|var)\s+|(?<![\w.]))(\w+)\s*(?::[^=\n]*)?=(?!=)\s*%s%s(%s)\s*[(<]" % (_ESSAI, _CHAINE, alt))
        tuple_ = re.compile(r"\b(?:let|var)\s*\(([^()\n]*)\)\s*=\s*%s%s(%s)\s*[(<]" % (_ESSAI, _CHAINE, alt))
        for m in appel.finditer(texte):
            if "seule" in fabs[m.group(2)]:
                noms.add(m.group(1))
        for m in tuple_.finditer(texte):
            positions = set()
            for f in fabs[m.group(2)]:
                if isinstance(f, set):
                    positions |= f
            for i, nom in enumerate(x.strip() for x in m.group(1).split(",")):
                if i in positions and re.fullmatch(r"\w+", nom) and nom != "_":
                    noms.add(nom)
    while True:  # alias : `let s = self.sonde`
        alt = "|".join(sorted(map(re.escape, noms)))
        alias = re.compile(r"\b(?:let|var)\s+(\w+)\s*=\s*(?:try[?!]?\s+)?%s(?:%s)(?:[!?](?![.\w(]))?(?![\w(.?!])" % (_CHAINE, alt))
        avant = len(noms)
        noms |= {m.group(1) for m in alias.finditer(texte)}
        if len(noms) == avant:
            return noms


def ecritures(texte, noms, fabs=None):
    """Les affectations d'une propriete de `noms` par un recepteur de sonde : (numero de ligne, texte de la ligne)."""
    recepteurs = recepteurs_lies(texte, fabs or {})
    r = "|".join(sorted(map(re.escape, recepteurs)))
    p = "|".join(sorted(map(re.escape, noms)))
    motif = re.compile(r"(?<![\w])(?:%s)[?!]?\.(?:%s)\b(?:\[[^\]\n]*\])?\s*%s|"
                       r"(?<![\w])(?:%s)[?!]?\.(?:%s)\.(?:%s)\(" % (r, p, _OPERATEUR, r, p, _MUTATIONS))
    lignes = texte.split("\n")
    return [(i + 1, lignes[i].strip()) for i in range(len(lignes)) if motif.search(lignes[i])]


def extensions_hors_fichiers(texte, rel):
    """Les `extension SondeMaillage<P>` (non suivies d'un `.`) hors des fichiers de la sonde P."""
    lignes = texte.split("\n")
    trouvees = []
    m_fichier = FICHIER_SONDE.match(rel)
    for m in _EXTENSION.finditer(texte):
        if m_fichier and m_fichier.group(1) == m.group(1):
            continue
        i = texte.count("\n", 0, m.start())
        trouvees.append((i + 1, lignes[i].strip()))
    return trouvees


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
    noms = {n for s in SONDES for n in PROPRIETES[s]} | {n for s in SONDES for n in POIGNEES[s]}
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
        declarees_toutes = {m for m in re.findall(r"^    (?:@ObservationIgnored )?(?:private\(set\) )?var (\w+)\b",
                                                  nettoyer(lire(racine, rel)), re.M)}
        for n in POIGNEES[s]:
            if n not in declarees_toutes:
                defauts.append("%s : %s est dans POIGNEES de outils/verifier_sondes.py mais n'y est plus declaree `var` "
                               "non privee (liste a mettre a jour)" % (rel, n))
        for n in declarees:
            if n not in PROPRIETES[s] and n not in EXEMPTEES[s]:
                defauts.append("%s : `var %s` observee, ni listee ni exemptee dans outils/verifier_sondes.py "
                               "(une extension qui l'ecrit lui a-t-elle fait perdre son private(set) ?)" % (rel, n))
    # 1, 2 et 4
    textes = {rel: nettoyer(lire(racine, rel)) for rel in fichiers_swift(racine)}
    fabs = {}
    for texte in textes.values():
        for nom, formes in fabriques(texte).items():
            fabs.setdefault(nom, []).extend(formes)
    for rel, texte in textes.items():
        if not FICHIER_SONDE.match(rel):
            for i, l in ecritures(texte, noms, fabs):
                defauts.append("%s:%d : etat de sonde ecrit hors de son pilote : %s" % (rel, i, l))
        for i, l in extensions_hors_fichiers(texte, rel):
            defauts.append("%s:%d : extension de la sonde hors de ses fichiers MaillageIoT/<P>/Sonde/SondeMaillage<P>*.swift "
                           "(elle ecrirait l'etat sans recepteur) : %s" % (rel, i, l))
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
