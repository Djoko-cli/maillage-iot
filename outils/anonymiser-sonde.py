#!/usr/bin/env python3
"""Anonymise une capture de la sonde (JSON Lines) avant d'en faire des donnees de test.

  python3 outils/anonymiser-sonde.py <capture brute.jsonl> <capture anonyme.jsonl>

Remplace, de facon coherente d'une ligne a l'autre et jusque dans les TLV de
diagnostic :
- les ExtMac (TLV 0, `ext` de `etat`, de son parent, des voisins et des
  routeurs), les adresses lien-local qui en derivent, et le nom d'hote SRP de
  la sonde (`hote`, 16 hexa : Matter le tire de son ExtMac) ;
- les prefixes IPv6 (/48 : reseau maille, OMR, NAT64...) et les identifiants
  d'interface, sauf ceux des RLOC et ALOC (0000:00ff:fe00:xxxx), gardes ;
- le `xp`, la MAC de la sonde, son nom (SONDE-01, SONDE-02...) et
  l'empreinte de sa cle ;
- les adresses des Network Data (prefixes, donnees de serveur).
Retire le code d'appairage et le QR code (null), et la cle (deja masquee par
sonde_essai.py). Garde les RLOC16, partitions, qualites, signaux, delais,
compteurs et versions de pile. Aucune valeur reelle n'est ecrite dans ce
script : il les repere dans la capture. A la fin, il verifie qu'aucune ne
reste dans la sortie (a la minuscule, separateurs retires : une ExtMac ecrite par groupes serait vue).

Une capture deja anonymisee ressort telle quelle : une valeur deja factice
(ExtMac E000..., identifiant 0A00..., /48 fd00:1111:2222..., MAC A0000000...,
xp A0A1A2A3A4A5A6A7, nom SONDE-NN, empreinte C1E0...) reste elle-meme, et une
valeur reelle recoit une factice qui n'a pas encore servi. Une valeur reelle
de cette forme passerait telle quelle : tiree au hasard, elle n'a presque
aucune chance d'exister. (Une capture qui melerait valeurs reelles et
factices pourrait confondre deux noeuds, jamais laisser passer une valeur
reelle.)

Garde : l'outil ne connait que les messages de la sonde 1.0.3 (bonjour, etat,
voisins, routeurs, diag, cle, oubli, erreur) et ceux de la capture du 29/09
(firmware d'essai), leurs champs et la forme de chacun (CHAMPS_COMMUNS,
CHAMPS_CONNUS, OBJETS), et les TLV de diagnostic que la tournee demande
(TLV_CONNUS). Il echoue AVANT toute ecriture, avec la liste de ce qu'il ne
connait pas (des noms, jamais une valeur), devant :
- une ligne qui n'est pas un objet, un type de message ou un champ inconnu ;
- une valeur qui n'a pas la forme de son champ : un objet ou une liste la ou
  l'outil n'en descend pas ; un texte libre qui n'est pas sur (texte_sur() :
  64 caracteres au plus, lettres, chiffres, espace, point, tiret, souligne,
  « : » seul entre deux espaces, jamais 8 hexa de suite une fois retires les
  espaces, tirets, points, soulignes et « : » : DEAD BEEF 0000 0004, DE-AD-BE-EF-00-01,
  DEAD.BEEF.0000.0004) ; un nombre qui
  n'est pas un entier de 32 bits (une ExtMac en demande 64) ; un RLOC16, une
  partition ou une heure mal formes ; autre chose que du texte dans un champ
  que l'outil remplace ;
- un TLV inconnu, a longueur etendue ou tronque, ou de longueur inattendue :
  8 octets pour le TLV 0 (ExtMac), 2 pour le 1 (Address16), 1 pour le 2
  (Mode), 9 plus un par routeur pour le 5 (Route64), 8 pour le 6 (Leader
  Data), des adresses entieres pour le 8, des entrees de 3 octets pour le 16
  (Child Table), 2 pour le 24 (Version), et au plus 32, 32, 16 et 64 pour les
  textes des TLV 25 a 28 ;
- un texte des TLV 25 a 28 (fabricant, modele, version logicielle, pile) qui
  n'est pas de l'ASCII lisible, ou qui porte 12 hexa de suite, une MAC, une
  adresse IPv6 (cherchee dans tout le texte, meme collee a `=`, `:` ou un
  point), un « :: », un « : » hors d'un horaire (07:09:25), 3 groupes de 2 a
  4 hexa avec un meme separateur (`: . _ -` ou espace), ou 6 paires d'hexa et
  plus avec un meme separateur : texte_tlv_sur() ;
- dans la Network Data (TLV 7), autre chose que des Prefix de 16 bits au plus
  ou de 41 a 96 bits, des Service et une Commissioning Data qui ne porte qu'une
  Commissioner Session ID (16 bits, quelle que soit sa valeur), ou une donnee
  de service de plus de 2 octets : donnees_reseau() ne remplace que les 6
  premiers octets des Prefix, a partir de 41 bits, et l'adresse des Server d'un
  Service ;
- dans un Prefix, autre chose que des Has Route (entrees de 3 octets), des
  Border Router (entrees de 4) et un 6LoWPAN Context (2 octets) ; dans un
  Service, autre chose que des Server, ou un Server qui n'est ni un RLOC16 seul
  (2 octets), ni un RLOC16 suivi d'une adresse et d'un port (20 octets,
  l'adresse remplacee), ni, pour le routeur de dorsale (donnee 01), un RLOC16
  et ses 7 octets de reglages.
Une valeur illisible dans un champ remplace (un hexa abime, une adresse, une
cible qui n'est ni un RLOC16 ni une adresse) le fait sortir avec le seul
numero de ligne, jamais la valeur (la trace d'une exception la citerait). Pour
ajouter un champ : verifier qu'il ne porte rien d'identifiant, sinon le
traiter dans message() ; puis l'inscrire dans la table, avec sa forme.
"""
import ipaddress
import json
import re
import sys

MAILLE_RLOC = bytes.fromhex("000000fffe00")
XP_FACTICE = "A0A1A2A3A4A5A6A7"  # le meme pour tout xp, comme dans la capture du 29/09
MASQUEE = "(masquee)"  # la cle, comme sonde_essai.py la capture

# Ce que l'outil connait (voir la garde dans la docstring) : chaque champ avec sa forme. "?" en fin : null permis.
#   texte    : un texte sur (texte_sur()), garde tel quel ;
#   remplace : du texte, remplace par une valeur factice (hexa, adresse, nom) dans message() ;
#   efface   : un scalaire, jamais recopie (code d'appairage, QR code, cle) ;
#   nombre   : un entier de 32 bits, signe ou non ; booleen ;
#   rloc16   : 4 hexa ; partition : 8 hexa ; heure : AAAA-MM-JJTHH:MM:SS, ajoutee par sonde_essai.py ;
#   tlv      : la charge d'un diag, en hexa (controler_tlv()) ;
#   objet X, liste X : un objet des champs OBJETS[X], une liste de tels objets.
CHAMPS_COMMUNS = {"t": "texte", "v": "nombre", "heure": "heure"}
CHAMPS_CONNUS = {
    "bonjour": {"produit": "texte", "version": "texte", "nom": "remplace", "mac": "remplace", "appairee": "booleen",
                "code": "efface?", "qr": "efface?", "hote": "remplace?"},
    "etat": {"erreur": "texte", "role": "texte", "rloc16": "rloc16", "ext": "remplace", "mode": "texte",
             "eligible": "booleen", "parent": "objet parent?", "partition": "partition?", "chef": "nombre?",
             "canal": "nombre", "prefixeMaille": "remplace", "xp": "remplace", "suspendue": "booleen"},
    "voisins": {"erreur": "texte", "liste": "liste voisin"},
    "routeurs": {"erreur": "texte", "liste": "liste routeur", "suite": "booleen"},
    "diag": {"id": "nombre", "cible": "remplace", "ms": "nombre", "ok": "booleen", "code": "texte",
             "erreur": "texte", "tlv": "tlv?", "tronquee": "booleen"},
    "cle": {"id": "nombre", "cle": "efface", "empreinte": "remplace?", "effacement_en_echec": "booleen",
            "hote": "remplace?", "udp": "objet udp", "tas": "objet tas", "msg": "texte"},
    "oubli": {"cle_effacee": "booleen"},
    "erreur": {"erreur": "texte"},
}
OBJETS = {
    "parent": {"rloc16": "rloc16", "ext": "remplace", "lqIn": "nombre", "lqOut": "nombre", "rssi": "nombre",
               "rssiDernier": "nombre", "age": "nombre"},
    "voisin": {"rloc16": "rloc16", "ext": "remplace", "rssi": "nombre", "lqi": "nombre", "routeur": "booleen"},
    "routeur": {"id": "nombre", "rloc16": "rloc16", "ext": "remplace?", "lqIn": "nombre", "lqOut": "nombre",
                "age": "nombre", "lien": "booleen"},
    # Compteurs du transport (ceux du pont Halo), plus les lignes perdues et les commandes refusees par la cadence.
    "udp": {"port": "nombre", "ouvert": "booleen", "sessions": "nombre", "provisoire": "booleen", "rx": "nombre",
            "rejets": "nombre", "rx_perdus": "nombre", "defis": "nombre", "tx": "nombre", "tx_perdus": "nombre",
            "tx_erreurs": "nombre", "tampons_min": "nombre?", "lignes_perdues": "nombre", "refus_cadence": "nombre"},
    "tas": {"libre": "nombre", "min": "nombre"},
}
TEXTE_SUR = re.compile(r"[A-Za-z0-9_. :-]{0,64}")
HEXA_8 = re.compile(r"[0-9A-Fa-f]{8}")
# Les separateurs qu'on glisse entre les groupes d'une ExtMac ou d'une MAC (DEAD BEEF, DE-AD-BE-EF, DEAD.BEEF, DE_AD,
# DE:AD) : retires avant de chercher 8 hexa de suite.
SEPARATEURS = re.compile(r"[ \-._:]")
# TLV de diagnostic : 0, 7 et 8 sont traites ; les autres n'ont ni ExtMac ni adresse.
TLV_CONNUS = frozenset({0, 1, 2, 5, 6, 7, 8, 16, 24, 25, 26, 27, 28})
# Longueur exacte : ExtMac (0), Address16 (1), Mode (2), Leader Data (6), Version (24). Un octet de plus porterait un
# morceau de valeur que l'anonymiseur ne lit pas.
TLV_LONGUEUR = {0: 8, 1: 2, 2: 1, 6: 8, 24: 2}
# Faits d'entrees de cette taille : les adresses (8), la Child Table (16). Route64 (5) se lit a part : 9 octets, puis
# un par routeur du masque.
TLV_ENTREES = {8: 16, 16: 3}
# Textes du fabricant (25), du modele (26), de la version logicielle (27) et de la pile (28) : longueur maximale.
TLV_TEXTE_MAX = {25: 32, 26: 32, 27: 16, 28: 64}
# Dans ces textes : 12 hexa de suite (une MAC, une ExtMac), ou une MAC ecrite avec des separateurs. Une version de pile
# porte une date, une heure, parfois un condensat de commit (9 hexa dans la capture) : la limite est a 12.
HEXA_12 = re.compile(r"[0-9A-Fa-f]{12}")
MAC_TEXTE = re.compile(r"[0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5}")
# Un horaire (07:09:25, 19:39) : le seul « : » admis. Il ne touche ni une lettre ni un chiffre de part et d'autre, sinon
# « fd00:12 » ou « 07:09:251 » en passeraient pour un.
HORAIRE = re.compile(r"(?<![0-9A-Za-z])\d{1,2}:\d{2}(?::\d{2})?(?![0-9A-Za-z])")
# Au moins 3 groupes de 2 a 4 hexa avec un meme separateur (une adresse IPv6 ou une MAC ecrite autrement, un prefixe) ;
# de 6 a 8 paires (ou plus) avec un meme separateur quelconque (une MAC, une ExtMac). Sans garde de bord : un groupe de
# 5 hexa ou un hexa colle a la suite n'y echappe pas.
GROUPES_HEXA = re.compile(r"[0-9A-Fa-f]{2,4}([:._ -]+)[0-9A-Fa-f]{2,4}(?:\1[0-9A-Fa-f]{2,4})+")
PAIRES_HEXA = re.compile(r"[0-9A-Fa-f]{2}([^0-9A-Za-z]+)(?:[0-9A-Fa-f]{2}\1){4,}[0-9A-Fa-f]{2}")
# Un candidat d'adresse IPv6 : toute suite de chiffres hexa, de « : », de points et de « % » qui porte un « : ». Elle est
# cherchee dans tout le texte, collee ou non a un « = », un « : » ou un point.
CANDIDAT_IPV6 = re.compile(r"[0-9A-Fa-f:.%]*:[0-9A-Fa-f:.%]*")
# Network Data (TLV 7), premier niveau : les Prefix (1) et les Service (5) sont traites par donnees_reseau() ; la
# Commissioning Data (4) n'est acceptee que si elle ne porte qu'un sous-TLV Commissioner Session ID (MeshCoP 11,
# longueur 2), quelle que soit sa valeur : un identifiant de session sur 16 bits n'est pas une donnee personnelle.
DONNEES_RESEAU_CONNUES = frozenset({1, 4, 5})
# Une donnee de service de plus de 2 octets (la capture : 01, 5d, 5cc5) pourrait porter une adresse.
DONNEE_SERVICE_MAX = 2
# donnees_reseau() ne remplace que les 6 premiers octets d'un Prefix : au-dela de 96 bits (le /96 NAT64 de la capture
# passe), l'identifiant d'interface resterait en clair.
PREFIXE_MAX_BITS = 96
# donnees_reseau() ne remplace un Prefix qu'a partir de 6 octets, soit 41 bits : de 17 a 40 bits il passerait en clair.
# Jusqu'a 16 bits (le /7 de la capture), un prefixe n'identifie personne.
PREFIXE_COURT_MAX_BITS = 16
PREFIXE_REMPLACE_MIN_BITS = 41


def sans_separateurs(x):
    """`x` sans espace, tiret, point, souligne ni « : » : une ExtMac ecrite par groupes redevient une suite d'hexa."""
    return SEPARATEURS.sub("", x)


def texte_sur(x):
    """Un texte libre qui ne porte rien d'identifiant : 64 caracteres au plus, lettres, chiffres, espace, point,
    tiret, souligne, et « : » seul entre deux espaces (« cle non chargee : active au redemarrage ») ; jamais 8 hexa
    de suite une fois les separateurs retires (une MAC, un /48, une ExtMac, un code d'appairage en ont 8 ou plus,
    ecrits d'une traite ou par groupes : DEAD BEEF 0000 0004, DE-AD-BE-EF-00-01, DEAD.BEEF.0000.0004)."""
    return (isinstance(x, str) and TEXTE_SUR.fullmatch(x) is not None and HEXA_8.search(sans_separateurs(x)) is None
            and all(":" not in mot or mot == ":" for mot in x.split(" ")))


FORMES = {
    "texte": texte_sur,
    "remplace": lambda x: isinstance(x, str),
    "efface": lambda x: not isinstance(x, (dict, list)),
    "nombre": lambda x: isinstance(x, int) and not isinstance(x, bool) and -(1 << 31) <= x < 1 << 32,
    "booleen": lambda x: isinstance(x, bool),
    "rloc16": lambda x: isinstance(x, str) and re.fullmatch(r"[0-9A-Fa-f]{4}", x) is not None,
    "partition": lambda x: isinstance(x, str) and re.fullmatch(r"[0-9A-Fa-f]{8}", x) is not None,
    "heure": lambda x: isinstance(x, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d", x) is not None,
}


def p48_factice(n):
    """Le n-ieme /48 factice, a partir de 1 : fd00:1111:2222, fd00:3333:4444, fd00:5555:6666..."""
    return bytes.fromhex("FD00%04X%04X" % (0x1111 * (2 * n - 1) & 0xFFFF, 0x1111 * 2 * n & 0xFFFF))


P48_FACTICES = frozenset(p48_factice(n) for n in range(1, 4097))


def remplaces(table):
    """Les valeurs reelles d'une table (pas celles, deja factices, qui restent elles-memes)."""
    return [reel for reel, factice in table.items() if reel != factice]


class Anonymiseur:
    def __init__(self):
        self.exts = {}        # ExtMac reelle (8 octets) -> factice ; aussi le nom d'hote SRP
        self.iids = {}        # identifiant d'interface reel -> factice
        self.p48 = {}         # /48 reel (6 octets) -> factice
        self.xp = {}
        self.macs = {}
        self.noms = {}        # nom de la sonde
        self.empreintes = {}  # empreinte de sa cle
        self.cles = set()     # cle en clair (sonde_essai.py la masque deja) : a ne plus trouver

    # --- Tables de correspondance ------------------------------------------

    @staticmethod
    def factice(table, reel, nieme, deja_factice):
        """La valeur factice de `reel`, la meme d'une ligne a l'autre. Deja factice (capture deja anonymisee), elle
        reste elle-meme ; sinon, la premiere factice libre (`nieme(n)`, n a partir du nombre de valeurs vues + 1) :
        jamais une factice deja donnee."""
        if reel not in table:
            if deja_factice(reel):
                table[reel] = reel
            else:
                prises, n = set(table.values()), len(table) + 1
                while nieme(n) in prises:
                    n += 1
                table[reel] = nieme(n)
        return table[reel]

    def ext(self, e):
        return self.factice(self.exts, e, lambda n: bytes.fromhex("E0%014X" % n),
                            lambda x: len(x) == 8 and x[0] == 0xE0 and int.from_bytes(x[1:], "big") < 1 << 16)

    def iid(self, i):
        return self.factice(self.iids, i, lambda n: bytes.fromhex("0A00%012X" % n),
                            lambda x: len(x) == 8 and x[:2] == b"\x0a\x00" and int.from_bytes(x[2:], "big") < 1 << 16)

    def prefixe48(self, p):
        if len(p) != 6:
            raise ValueError("prefixe")  # un prefixe du reseau maille trop court : illisible
        return self.factice(self.p48, p, p48_factice, lambda x: x in P48_FACTICES)

    def hexa_ext(self, texte):
        """Une ExtMac en hexa (ou le nom d'hote SRP, qui en est tire) -> sa factice, en hexa."""
        return self.ext(bytes.fromhex(texte)).hex().upper()

    def mac(self, m):
        return self.factice(self.macs, m, lambda n: "A0000000%04X" % n,
                            lambda x: re.fullmatch(r"A0000000[0-9A-F]{4}", x) is not None)

    def nom(self, x):
        return self.factice(self.noms, x, lambda n: "SONDE-%02d" % n,
                            lambda v: re.fullmatch(r"SONDE-[0-9]{2,}", v) is not None)

    def empreinte(self, x):
        return self.factice(self.empreintes, x, lambda n: "C1E0%04X" % n,
                            lambda v: re.fullmatch(r"C1E0[0-9A-F]{4}", v) is not None)

    def adresse(self, a):
        """Adresse IPv6 de 16 octets."""
        if a[:8] == bytes.fromhex("FE80000000000000"):
            # Lien-local Thread : identifiant tire de l'ExtMac (bit U/L inverse).
            e = bytes([a[8] ^ 0x02]) + a[9:]
            f = self.ext(e)
            return a[:8] + bytes([f[0] ^ 0x02]) + f[1:]
        tete = self.prefixe48(a[:6]) + a[6:8]
        if a[8:14] == MAILLE_RLOC:
            return tete + a[8:]
        return tete + self.iid(a[8:])

    # --- TLV de diagnostic -------------------------------------------------

    def tlv(self, hexa):
        o, i, sortie = bytes.fromhex(hexa), 0, b""
        while i + 2 <= len(o):
            t, n = o[i], o[i + 1]
            v = o[i + 2:i + 2 + n]
            if t == 0 and n == 8:
                v = self.ext(v)
            elif t == 8:
                v = b"".join(self.adresse(v[k:k + 16]) for k in range(0, n - 15, 16))
            elif t == 7:
                v = self.donnees_reseau(v)
            sortie += bytes([t, n]) + v
            i += 2 + n
        return sortie.hex().upper()

    def donnees_reseau(self, o):
        """Network Data : prefixes des TLV Prefix, adresses des donnees de serveur."""
        i, sortie = 0, b""
        while i + 2 <= len(o):
            t, n = o[i] >> 1, o[i + 1]
            v = bytearray(o[i + 2:i + 2 + n])
            if t == 1 and len(v) >= 2:  # Prefix : domaine, longueur en bits, prefixe, sous-TLV
                octets = (v[1] + 7) // 8
                if octets >= 6:
                    v[2:8] = self.prefixe48(bytes(v[2:8]))
            elif t == 5 and len(v) >= 1:  # Service : donnees, puis sous-TLV Server
                j = 1 if v[0] & 0x80 else 5
                if j < len(v):
                    j += 1 + v[j]
                    while j + 2 <= len(v):
                        st, sn = v[j] >> 1, v[j + 1]
                        if st == 6 and sn >= 2 + 16:  # Server : RLOC16, puis une adresse
                            v[j + 4:j + 20] = self.adresse(bytes(v[j + 4:j + 20]))
                        j += 2 + sn
            sortie += bytes([o[i], n]) + bytes(v)
            i += 2 + n
        return sortie

    # --- Messages de la sonde ----------------------------------------------

    def message(self, m):
        m = dict(m)
        t = m.get("t")
        if t == "bonjour":
            if m.get("mac"):
                m["mac"] = self.mac(m["mac"])
            if m.get("nom"):
                m["nom"] = self.nom(m["nom"])
            if m.get("hote"):
                m["hote"] = self.hexa_ext(m["hote"])
            m["code"] = None
            m["qr"] = None
        elif t == "etat":
            if m.get("ext"):
                m["ext"] = self.hexa_ext(m["ext"])
            if m.get("xp"):
                m["xp"] = self.xp.setdefault(m["xp"], XP_FACTICE)
            if m.get("prefixeMaille"):
                p = bytes.fromhex(m["prefixeMaille"])
                m["prefixeMaille"] = (self.prefixe48(p[:6]) + p[6:8]).hex().upper()
            if m.get("parent") and m["parent"].get("ext"):
                m["parent"] = dict(m["parent"], ext=self.hexa_ext(m["parent"]["ext"]))
        elif t in ("voisins", "routeurs"):
            if m.get("liste"):
                m["liste"] = [dict(e, ext=self.hexa_ext(e["ext"])) if e.get("ext") else dict(e) for e in m["liste"]]
        elif t == "diag":
            cible = m.get("cible", "")
            if ":" in cible:
                m["cible"] = str(ipaddress.IPv6Address(self.adresse(ipaddress.IPv6Address(cible).packed)))
            elif cible and not re.fullmatch(r"[0-9A-Fa-f]{4}", cible):
                raise ValueError("cible")  # ni un RLOC16, ni une adresse : illisible
            if m.get("tlv"):
                m["tlv"] = self.tlv(m["tlv"])
        elif t == "cle":
            if "cle" in m:
                if m["cle"] != MASQUEE:
                    self.cles.add(str(m["cle"]))
                m["cle"] = MASQUEE
            if m.get("empreinte"):
                m["empreinte"] = self.empreinte(m["empreinte"])
            if m.get("hote"):
                m["hote"] = self.hexa_ext(m["hote"])
        return m

    def secrets(self):
        """Valeurs reelles, en texte, a ne plus trouver dans la sortie (pas celles qui etaient deja factices)."""
        s = set()
        for e in remplaces(self.exts):
            s.add(e.hex())
            if e:
                s.add((bytes([e[0] ^ 0x02]) + e[1:]).hex())  # l'identifiant lien-local qui en derive
        for i in remplaces(self.iids):
            s.add(i.hex())
        for p in remplaces(self.p48):
            s.add(p.hex())
            s.add(str(ipaddress.IPv6Address(p + bytes(10))).split("::")[0])
        for table in (self.macs, self.noms, self.empreintes):
            s.update(remplaces(table))
        s.update(x for x in self.xp if x != XP_FACTICE)
        s.update(self.cles)
        return {x.lower() for x in s if len(x) >= 8}


def nom_sur(x):
    """Nom de champ ou de type pour un message d'erreur : jamais une valeur. Un nom abime peut porter une ExtMac, une
    MAC, un /48 ou un code d'appairage : 8 hexa de suite, et il devient "(illisible)"."""
    ok = isinstance(x, str) and re.fullmatch(r"[A-Za-z0-9_]{1,32}", x) and not re.search(r"[0-9A-Fa-f]{8}", x)
    return x if ok else "(illisible)"


def controler_sous_tlv(o, admis):
    """Les sous-TLV d'un Prefix ou d'un Service : `admis(type, valeur)` rend la raison de refuser un sous-TLV, ou
    None s'il est connu. Le bit de poids faible du type est le drapeau "stable"."""
    raisons, i = [], 0
    while i < len(o):
        if i + 2 > len(o) or i + 2 + o[i + 1] > len(o):
            return raisons + ["Network Data tronquee (diag.tlv)"]
        raison = admis(o[i] >> 1, o[i + 2:i + 2 + o[i + 1]])
        if raison:
            raisons.append(raison)
        i += 2 + o[i + 1]
    return raisons


def sous_tlv_prefix(t, v):
    """Has Route (0) : entrees de 3 octets (RLOC16, drapeaux) ; Border Router (2) : entrees de 4 (RLOC16, drapeaux) ;
    6LoWPAN Context (3) : 2 octets (identifiant, longueur). Aucun ne porte d'adresse."""
    if t not in (0, 2, 3):
        return "sous-TLV inconnu d'un Prefix : %d (diag.tlv)" % t
    if (t == 0 and len(v) % 3) or (t == 2 and len(v) % 4) or (t == 3 and len(v) != 2):
        return "sous-TLV %d de longueur inattendue dans un Prefix (diag.tlv)" % t
    return None


def controler_prefixe(v):
    """Un Prefix : domaine, longueur du prefixe en bits, ses octets, puis ses sous-TLV."""
    if len(v) < 2:
        return ["Network Data tronquee (diag.tlv)"]
    if v[1] > PREFIXE_MAX_BITS:
        return ["prefixe de plus de %d bits dans la Network Data (diag.tlv)" % PREFIXE_MAX_BITS]
    if PREFIXE_COURT_MAX_BITS < v[1] < PREFIXE_REMPLACE_MIN_BITS:
        return ["prefixe de %d a %d bits dans la Network Data (diag.tlv)"
                % (PREFIXE_COURT_MAX_BITS + 1, PREFIXE_REMPLACE_MIN_BITS - 1)]
    debut = 2 + (v[1] + 7) // 8
    if debut > len(v):
        return ["Network Data tronquee (diag.tlv)"]
    return controler_sous_tlv(v[debut:], sous_tlv_prefix)


def controler_service(v):
    """Un Service : bit T et identifiant, numero d'entreprise (4 octets) si T est a 0, donnee de service, puis des
    Server seulement. Un Server est un RLOC16 seul (2 octets), un RLOC16 suivi d'une adresse et d'un port (20 octets :
    le serveur SRP, dont donnees_reseau() remplace l'adresse), ou, pour le routeur de dorsale (donnee 01), un RLOC16
    et ses 7 octets de reglages. Un Server de 12 octets porterait une ExtMac en clair."""
    j = 1 if v and v[0] & 0x80 else 5
    if j >= len(v):
        return ["Network Data tronquee (diag.tlv)"]
    if v[j] > DONNEE_SERVICE_MAX:
        return ["donnee de service de plus de %d octets dans la Network Data (diag.tlv)" % DONNEE_SERVICE_MAX]
    donnee = v[j + 1:j + 1 + v[j]]
    if len(donnee) < v[j]:
        return ["Network Data tronquee (diag.tlv)"]

    def admis(t, serveur):
        if t != 6:
            return "sous-TLV inconnu d'un Service : %d (diag.tlv)" % t
        if len(serveur) not in (2, 20) and not (len(serveur) == 9 and donnee == b"\x01"):
            return "Server de longueur inattendue dans la Network Data (diag.tlv)"
        return None

    return controler_sous_tlv(v[j + 1 + v[j]:], admis)


def controler_donnees_reseau(o):
    """Pourquoi la Network Data (TLV 7) n'est pas connue (liste vide si elle l'est) : donnees_reseau() ne remplace
    que le /48 des Prefix et l'adresse des Server d'un Service ; le reste passerait en clair."""
    raisons, i = [], 0
    while i < len(o):
        if i + 2 > len(o) or i + 2 + o[i + 1] > len(o):
            return raisons + ["Network Data tronquee (diag.tlv)"]
        t, n = o[i] >> 1, o[i + 1]  # le bit de poids faible est le drapeau "stable"
        v = o[i + 2:i + 2 + n]
        if t not in DONNEES_RESEAU_CONNUES:
            raisons.append("sous-TLV inconnu de la Network Data : %d (diag.tlv)" % t)
        elif t == 1:
            raisons += controler_prefixe(v)
        elif t == 4 and not (len(v) == 4 and v[0] == 11 and v[1] == 2):  # un seul sous-TLV, la valeur est libre
            raisons.append("Commissioning Data inconnue dans la Network Data (diag.tlv)")
        elif t == 5:
            raisons += controler_service(v)
        i += 2 + n
    return raisons


def longueur_tlv_attendue(t, v):
    """La longueur du TLV connu `t` (voir TLV_LONGUEUR, TLV_ENTREES, TLV_TEXTE_MAX ; la Network Data se lit a part)."""
    if t in TLV_LONGUEUR:
        return len(v) == TLV_LONGUEUR[t]
    if t in TLV_ENTREES:
        return len(v) % TLV_ENTREES[t] == 0
    if t in TLV_TEXTE_MAX:
        return len(v) <= TLV_TEXTE_MAX[t]
    if t == 5:  # numero de sequence, masque des routeurs (64 bits), un octet par routeur du masque
        return len(v) >= 9 and len(v) == 9 + bin(int.from_bytes(v[1:9], "big")).count("1")
    return True


def adresse_ipv6_dans(texte):
    """Une adresse IPv6 valide dans le texte, y compris collee a d'autres caracteres (`addr=fd00::1`, `ip:fd00::1`,
    `fd00::1.`) : on essaie chaque candidat, puis ses bouts (sans point ni « : » de tete ou de queue, sans zone)."""
    for candidat in CANDIDAT_IPV6.findall(texte):
        for c in {candidat, candidat.strip(".:"), candidat.split("%")[0], candidat.split("%")[0].strip(".:")}:
            try:
                ipaddress.IPv6Address(c)
                return True
            except ValueError:
                pass
    return False


def texte_tlv_sur(v):
    """Le texte d'un TLV 25 a 28 : de l'ASCII lisible qui ne peut porter ni adresse, ni MAC, ni ExtMac, ni prefixe.
    Refuse :
    - 12 hexa de suite, une MAC (`aa:bb:cc:dd:ee:ff`), une adresse IPv6 valide n'importe ou dans le texte ;
    - tout « :: » et tout « : » qui n'appartient pas a un horaire (HORAIRE : 07:09:25, 19:39) ;
    - 3 groupes de 2 a 4 hexa avec un meme separateur, apres retrait des horaires (« May 15 2026 07:09:25 » porte
      « 15 2026 » puis un horaire : deux groupes seulement), ou 6 paires et plus avec un meme separateur quelconque.
    Les versions (1.0.3), les dates et les condensats de commit de 9 hexa passent ; une date ISO (2026-09-30) ou un
    numero de version a 3 nombres de 2 a 4 chiffres (10.20.30) sont refuses : au moindre doute, on refuse."""
    if any(c < 0x20 or c > 0x7E for c in v):
        return False
    texte = v.decode("ascii")
    if HEXA_12.search(texte) or MAC_TEXTE.search(texte) or PAIRES_HEXA.search(texte) or adresse_ipv6_dans(texte):
        return False
    sans_horaires = HORAIRE.sub("T", texte)
    return ":" not in sans_horaires and GROUPES_HEXA.search(sans_horaires) is None


def controler_tlv(hexa):
    """Pourquoi la charge TLV d'un diag n'est pas connue (liste vide si elle l'est)."""
    try:
        o = bytes.fromhex(hexa)
    except (TypeError, ValueError):
        return ["tlv illisible (diag.tlv)"]
    raisons, i = [], 0
    while i < len(o):
        if i + 2 > len(o):
            return raisons + ["TLV tronque (diag.tlv)"]
        t, n = o[i], o[i + 1]
        if n == 0xFF:
            return raisons + ["TLV a longueur etendue (diag.tlv)"]
        if i + 2 + n > len(o):
            return raisons + ["TLV tronque (diag.tlv)"]
        v = o[i + 2:i + 2 + n]
        if t not in TLV_CONNUS:
            raisons.append("TLV inconnu : %d (diag.tlv)" % t)
        elif not longueur_tlv_attendue(t, v):
            raisons.append("TLV %d de longueur inattendue (diag.tlv)" % t)
        elif t == 7:
            raisons += controler_donnees_reseau(v)
        elif t in TLV_TEXTE_MAX and not texte_tlv_sur(v):
            raisons.append("texte inconnu dans le TLV %d (diag.tlv)" % t)
        i += 2 + n
    return raisons


def controler(numerotes):
    """La garde. `numerotes` : [(numero de ligne, message)]. Rend {raison: [numeros de ligne]}, vide si tout est
    connu. Ne cite jamais une valeur de la capture, seulement des noms de type et de champ (nom_sur). Une raison
    repetee sur une meme ligne ne compte qu'une fois."""
    inconnu = {}

    def noter(raison, numero):
        numeros = inconnu.setdefault(raison, [])
        if numero not in numeros:
            numeros.append(numero)

    def objet(chemin, champs, o, numero):
        for champ, valeur in o.items():
            if champ not in champs:
                noter("champ inconnu : %s.%s" % (chemin, nom_sur(champ)), numero)
            else:
                forme_de(chemin + "." + champ, champs[champ], valeur, numero)

    def forme_de(chemin, forme, valeur, numero):
        if valeur is None:
            if not forme.endswith("?"):
                noter("forme inconnue : %s" % chemin, numero)
            return
        genre, _, nom = forme.rstrip("?").partition(" ")
        if genre == "objet" and isinstance(valeur, dict):
            objet(chemin, OBJETS[nom], valeur, numero)
        elif genre == "liste" and isinstance(valeur, list) and all(isinstance(e, dict) for e in valeur):
            for e in valeur:
                objet(chemin, OBJETS[nom], e, numero)
        elif genre == "tlv" and not isinstance(valeur, (dict, list)):
            for raison in controler_tlv(valeur):
                noter(raison, numero)
        elif genre not in FORMES or not FORMES[genre](valeur):
            noter("forme inconnue : %s" % chemin, numero)

    for numero, m in numerotes:
        if not isinstance(m, dict):
            noter("ligne qui n'est pas un objet JSON", numero)
            continue
        t = m.get("t")
        if not isinstance(t, str) or t not in CHAMPS_CONNUS:
            noter("type de message inconnu : %s" % nom_sur(t), numero)
            continue
        objet(t, dict(CHAMPS_COMMUNS, **CHAMPS_CONNUS[t]), m, numero)
    return inconnu


def texte_refus(inconnu):
    lignes = ["refus : la capture contient ce que l'anonymiseur ne connait pas ; rien n'a ete ecrit."]
    for raison, numeros in inconnu.items():
        lignes.append("  %s (%d ligne(s), la premiere : %d)" % (raison, len(numeros), numeros[0]))
    lignes.append("Un champ ou un message inconnu peut porter une ExtMac, une adresse ou un nom : le traiter dans "
                  "l'anonymiseur (message(), puis les tables CHAMPS_CONNUS, OBJETS et TLV_CONNUS) avant de lui "
                  "confier cette capture.")
    return "\n".join(lignes)


def lire(chemin):
    """Les messages de la capture avec leur numero de ligne (les lignes vides sont sautees)."""
    res = []
    with open(chemin, encoding="utf-8") as f:
        for numero, ligne in enumerate(f, 1):
            if ligne.strip():
                try:
                    res.append((numero, json.loads(ligne)))
                except ValueError:
                    sys.exit("refus : la ligne %d n'est pas du JSON ; rien n'a ete ecrit." % numero)
    return res


def valeur_illisible(numero):
    """Sort avec le seul numero de ligne : la trace d'une exception (AddressValueError...) citerait la valeur."""
    raise SystemExit("refus : la ligne %d porte une valeur que l'anonymiseur ne sait pas lire ; rien n'a ete ecrit."
                     % numero) from None


def main():
    entree, sortie = sys.argv[1], sys.argv[2]
    a = Anonymiseur()
    numerotes = lire(entree)
    inconnu = controler(numerotes)
    if inconnu:
        sys.exit(texte_refus(inconnu))
    # Le prefixe du reseau maille (sonde attachee) d'abord : il recoit toujours
    # le premier /48 factice.
    for numero, m in numerotes:
        if m.get("t") == "etat" and m.get("prefixeMaille") and m.get("role") in ("child", "router", "leader"):
            try:
                a.prefixe48(bytes.fromhex(m["prefixeMaille"])[:6])
            except (ValueError, TypeError):
                valeur_illisible(numero)
            break
    lignes = []
    for numero, m in numerotes:
        try:
            lignes.append(json.dumps(a.message(m), ensure_ascii=False, sort_keys=True))
        except (ValueError, TypeError):
            valeur_illisible(numero)
    texte = "\n".join(lignes) + "\n"
    minuscule = texte.lower()
    brut = sans_separateurs(minuscule)  # une ExtMac reelle ecrite par groupes serait vue
    fuites = [s for s in a.secrets()
              if s in minuscule or (len(sans_separateurs(s)) >= 8 and sans_separateurs(s) in brut)]
    if fuites:
        sys.exit("fuite : %d valeur(s) reelle(s) encore presente(s)" % len(fuites))
    open(sortie, "w", encoding="utf-8").write(texte)
    print("%d lignes ; %d ExtMac, %d identifiants, %d prefixes /48 remplaces" %
          (len(lignes), len(remplaces(a.exts)), len(remplaces(a.iids)), len(remplaces(a.p48))))


if __name__ == "__main__":
    main()
