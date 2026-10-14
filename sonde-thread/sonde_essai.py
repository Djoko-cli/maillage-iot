#!/usr/bin/env python3
"""Essai de la sonde de maillage : commandes par l'USB ou par le reseau, capture et decodage.

  python3 sonde_essai.py <port> <capture.jsonl> <commande> [<commande> ...]
  python3 sonde_essai.py udp:<hote> <capture.jsonl> <commande> [<commande> ...]

Commandes : bonjour, etat, voisins, routeurs, "diag <cible> <t,t,...> <id>",
annonces et "resoudre <ipv6> <id>" (firmware 1.1.0), cle, "cle efface",
"cle nouvelle", ecoute:<s> (lit <s> secondes sans rien envoyer). Chaque ligne
machine est ajoutee a la capture avec l'heure ; les reponses diag, routeurs,
annonces (avec les liens de chaque Route64) et resoudre sont mises en forme a
l'ecran. La cle n'est jamais affichee ni capturee.

USB (<port> : celui que Djoko designe) : ouverture sure du C6 (comme benq
tools/halo_udp.py) : DTR = RTS = 0 en un seul appel, jamais RTS=1 DTR=0 qui
le redemarre. "cle nouvelle" : l'outil tire l'alea (32 octets) et l'id ; la
sonde rend la cle une fois, rangee dans le fichier SONDE_CLE (obligatoire ;
0600, ecriture atomique) ; seules son empreinte et le nom d'hote s'affichent.
La cle de l'app (trousseau) devient alors perimee : la recreer depuis l'app
pour y revenir.

Reseau (udp:<hote>) : UDP sur IPv6 vers le port 5480 (SONDE_PORT pour un
autre), enveloppe H1 du pont Halo (poignee de main SALUT/DEFI, messages
scelles). <hote> : le nom d'hote de bonjour (avec ou sans .local), ou une
adresse IPv6. Chaque commande part en "<rid> <commande>", renvoyee avec le
meme rid a 2 s puis 4 s tant que la reponse n'est pas complete. Cle : le
fichier SONDE_CLE, sinon le trousseau (service fr.djoko.maillage.iot.sonde-thread,
compte = nom d'hote : la cle rangee par l'app). Commande du reseau seulement :
refus (5 datagrammes sans enveloppe vers le port : DELAI attendu, avec ou sans
cle ; REFUS voudrait dire qu'un ICMPv6 « port injoignable » est revenu).
Prerequis Mac : route IPv6 vers le prefixe OMR (section Route vers le reseau Thread de README.fr.md).
"""
import fcntl, hashlib, hmac, ipaddress, json, os, re, select, socket, struct, subprocess, sys, termios, time

PORT_RESEAU = int(os.environ.get("SONDE_PORT") or 5480)
SERVICE_TROUSSEAU = "fr.djoko.maillage.iot.sonde-thread"


def ouvrir(chemin):
    fd = os.open(chemin, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    fcntl.ioctl(fd, termios.TIOCEXCL)
    fcntl.ioctl(fd, termios.TIOCMSET, struct.pack("I", 0))
    i, o, c, l, _, _, cc = termios.tcgetattr(fd)
    i &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK | termios.ISTRIP | termios.INLCR | termios.IGNCR
           | termios.ICRNL | termios.IXON)
    o &= ~termios.OPOST
    l &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG | termios.IEXTEN)
    c &= ~(termios.CSIZE | termios.PARENB | termios.HUPCL)
    c |= termios.CS8 | termios.CLOCAL | termios.CREAD
    termios.tcsetattr(fd, termios.TCSANOW, [i, o, c, l, termios.B115200, termios.B115200, cc])
    return fd


MASQUE = "********"
HEXA_16 = re.compile(r"[0-9A-Fa-f]{16,}")
CHAMP_CLE = re.compile(r'("cle"\s*:\s*")[0-9A-Fa-f]+')
TYPES_DONNEES = frozenset({"bonjour", "etat", "voisins", "routeurs", "diag", "erreur", "oubli", "annonces", "resoudre"})


def masquer_strict(texte):
    """Texte recu affiche tel quel (ligne abimee, fragment, journal de la carte) : le champ "cle" meme sans
    guillemet fermant, et toute suite de 16 hexa ou plus, masques (comme masquerCleStricte de benq). Une
    cle coupee par un journal n'y laisse rien de long. Jamais sur un message decode : un ExtMac ou un nom
    d'hote SRP fait 16 hexa. Masquer d'abord, couper ensuite."""
    if isinstance(texte, (bytes, bytearray)):
        texte = texte.decode("ascii", "replace")
    return HEXA_16.sub(MASQUE, CHAMP_CLE.sub(lambda x: x.group(1) + MASQUE, texte))


def _sans_hexa_long(v, limite):
    """Valeur JSON, noms de champ compris, sans suite de plus de `limite` hexa."""
    motif = re.compile(r"[0-9A-Fa-f]{%d,}" % (limite + 1))

    def nettoyer(x):
        if isinstance(x, str):
            return motif.sub(MASQUE, x)
        if isinstance(x, list):
            return [nettoyer(y) for y in x]
        if isinstance(x, dict):
            return {nettoyer(k): nettoyer(y) for k, y in x.items()}
        return x

    return nettoyer(v)


def sans_cle(m):
    """Le message decode sans rien de la cle, pour l'ecran et la capture : champ cle masque. Reponse de cle
    (t "cle") ou type inconnu (ligne abimee mais lisible) : en plus, aucune suite de plus de 16 hexa, dans
    les valeurs comme dans les noms de champ (un nom de champ abime peut porter la cle ; le nom d'hote SRP
    fait 16 hexa, l'empreinte 8). Les messages de donnees (ExtMac, TLV) restent entiers."""
    if "cle" in m:
        m = dict(m, cle="(masquee)")
    t = m.get("t")
    return m if isinstance(t, str) and t in TYPES_DONNEES else _sans_hexa_long(m, 16)


def texte_affiche(m):
    return json.dumps(sans_cle(m), ensure_ascii=False)


def capturer(capture, m):
    with open(capture, "a") as f:
        f.write(json.dumps({"heure": time.strftime("%Y-%m-%dT%H:%M:%S"), **sans_cle(m)}) + "\n")


class Lecteur:
    def __init__(self, fd, capture):
        self.fd, self.capture, self.tampon = fd, capture, b""

    def lignes(self, jusqua, silencieux=False):
        """Lignes machine decodees jusqu'a l'echeance. La ligne machine commence au dernier RS (comme benq et
        l'app) ; ce qui le precede, et toute ligne sans RS ou illisible, s'affiche masque (masquer_strict),
        ou pas du tout si silencieux (cle nouvelle). Rien d'autre que les messages decodes n'est capture."""
        while time.time() < jusqua:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                try:
                    self.tampon += os.read(self.fd, 4096)
                except BlockingIOError:
                    pass
            while b"\n" in self.tampon:
                brut, self.tampon = self.tampon.split(b"\n", 1)
                brut = brut.rstrip(b"\r")
                i = brut.rfind(b"\x1e")
                avant = brut if i < 0 else brut[:i]
                if avant.strip() and not silencieux:
                    print("   |", masquer_strict(avant)[:160])
                if i < 0:
                    continue
                try:
                    m = json.loads(brut[i + 1:].decode("ascii"))
                except (ValueError, UnicodeDecodeError):
                    m = None
                if not isinstance(m, dict):
                    if not silencieux:
                        print("?? ligne machine illisible :", masquer_strict(brut[i + 1:])[:120])
                    continue
                capturer(self.capture, m)
                yield m


def nom_tlv(t):
    return {0: "ExtMac", 1: "Address16", 2: "Mode", 3: "Timeout", 4: "Connectivity", 5: "Route64", 6: "LeaderData",
            7: "NetworkData", 8: "IPv6", 9: "MacCounters", 14: "Batterie", 15: "Tension", 16: "ChildTable",
            17: "ChannelPages", 19: "MaxChildTimeout", 24: "Version", 25: "VendorName", 26: "VendorModel",
            27: "VendorSwVersion", 28: "ThreadStackVersion", 29: "Child", 30: "ChildIpv6", 31: "RouterNeighbor",
            34: "MleCounters", 35: "VendorAppUrl"}.get(t, f"TLV{t}")


def mode_texte(m):
    return ("r" if m & 0x08 else "-") + ("d" if m & 0x02 else "-") + ("n" if m & 0x01 else "-")


def network_data(o):
    """Network Data (TLV 7) : prefixes, routeurs de bordure, routes et services, par RLOC16."""
    res, i = [], 0
    while i + 2 <= len(o):
        t, n = o[i] >> 1, o[i + 1]
        v = o[i + 2:i + 2 + n]
        i += 2 + n
        if t == 1 and len(v) >= 2:  # Prefix
            bits = v[1]
            pre = v[2:2 + (bits + 7) // 8]
            pre16 = (pre + bytes(16))[:16]  # un prefixe de plus de 128 bits (TLV abime) ne plante pas
            texte = f"{ipaddress.IPv6Address(pre16)}/{bits}"
            j = 2 + (bits + 7) // 8
            while j + 2 <= len(v):
                st, sn = v[j] >> 1, v[j + 1]
                sv = v[j + 2:j + 2 + sn]
                j += 2 + sn
                if st == 2:
                    res.append(f"prefixe {texte} : routeurs de bordure " + " ".join(f"{int.from_bytes(sv[k:k+2],'big'):04X}" for k in range(0, len(sv) - 3, 4)))
                elif st == 0:
                    res.append(f"prefixe {texte} : route par " + " ".join(f"{int.from_bytes(sv[k:k+2],'big'):04X}" for k in range(0, len(sv) - 2, 3)))
        elif t == 5 and len(v) >= 1:  # Service
            j = 1 if v[0] & 0x80 else 5
            if j >= len(v):
                continue
            dl = v[j]
            donnees = v[j + 1:j + 1 + dl]
            j += 1 + dl
            serveurs = []
            while j + 2 <= len(v):
                st, sn = v[j] >> 1, v[j + 1]
                if st == 6 and sn >= 2:
                    serveurs.append(f"{int.from_bytes(v[j+2:j+4],'big'):04X}")
                j += 2 + sn
            res.append(f"service {donnees.hex()} : serveurs " + " ".join(serveurs))
    return res


def decoder(hexa):
    o, i, res = bytes.fromhex(hexa), 0, []
    while i + 2 <= len(o):
        t, n = o[i], o[i + 1]
        v = o[i + 2:i + 2 + n]
        i += 2 + n
        if t == 0:
            d = v.hex().upper()
        elif t == 1:
            d = f"{int.from_bytes(v, 'big'):04X}"
        elif t == 2:
            d = mode_texte(v[0]) if v else "?"
        elif t == 5 and len(v) >= 9:
            masque = int.from_bytes(v[1:9], "big")
            ids = [r for r in range(64) if masque & (1 << (63 - r))]
            routes = []
            for r, b in zip(ids, v[9:]):
                routes.append(f"{r}(out{b >> 6} in{(b >> 4) & 3} cout{b & 15})")
            d = f"seq {v[0]} ; " + " ".join(routes)
        elif t == 6 and len(v) >= 8:
            d = f"partition {v[0:4].hex().upper()} poids {v[4]} version {v[5]}/{v[6]} chef {v[7]}"
        elif t == 7:
            entrees = network_data(v)
            if entrees:  # une ligne par prefixe ou par service
                res.extend(f"{nom_tlv(t)}: {e}" for e in entrees)
                continue
            d = v.hex().upper()
        elif t == 8:
            d = ", ".join(str(ipaddress.IPv6Address(v[k:k + 16])) for k in range(0, len(v) - 15, 16))
        elif t == 16:
            e = []
            for k in range(0, len(v) - 2, 3):
                x = int.from_bytes(v[k:k + 2], "big")
                e.append(f"id{x & 0x1FF}(lq{(x >> 9) & 3} delai2^{(x >> 11) - 4}s {mode_texte(v[k + 2])})")
            d = f"{len(e)} enfant(s) : " + " ".join(e)
        elif t == 24:
            d = str(int.from_bytes(v, "big"))
        elif t in (25, 26, 27, 28, 35):
            d = repr(v.decode("utf-8", "replace"))
        else:
            d = v.hex().upper()
        res.append(f"{nom_tlv(t)}: {d}")
    return res


def liens_route64(hexa):
    """Liens d'une Route64 brute (annonces, 1.1.0) : (identifiant, qualite sortante, entrante), voisins seulement."""
    try:
        v = bytes.fromhex(hexa)
    except (TypeError, ValueError):
        return []
    if len(v) < 9:
        return []
    masque = int.from_bytes(v[1:9], "big")
    ids = [r for r in range(64) if masque & (1 << (63 - r))]
    return [(r, b >> 6, (b >> 4) & 3) for r, b in zip(ids, v[9:]) if b >> 4]


def reponse_echo(m):
    """Firmware 1.1.1 : « repondu » dit si l'appareil lui-meme a repondu a l'echo ; absent avant (1.1.0)."""
    if "repondu" not in m:
        return "reponse d'echo inconnue"
    return "a repondu a l'echo" if m["repondu"] else "sans reponse d'echo"


def afficher(m):
    m = sans_cle(m)
    if m.get("t") == "annonces" and m.get("vide"):
        print("<< annonces : aucun routeur entendu")
    elif m.get("t") == "annonces" and "rloc16" in m:
        print(f"<< annonces {m['rloc16']} ext {m.get('ext')} partition {m.get('partition') or '-'} rssi {m.get('rssi')}"
              f" ({m.get('rssi_min')}..{m.get('rssi_max')}) {m.get('nb')} msg il y a {m.get('age_s')} s")
        liens = liens_route64(m.get("route64") or "")
        print("      liens : " + (", ".join(f"{r << 10:04X} {so}/{en}" for r, so, en in liens) or "-"))
    elif m.get("t") == "resoudre" and m.get("ok"):
        rloc = int(m["rloc16"], 16)
        mleid = str(ipaddress.IPv6Address(bytes.fromhex(m["mleid"]))) if m.get("mleid") else "inconnu"
        print(f"<< resoudre {m['cible']} : {m['rloc16']} (parent {rloc & 0xFC00:04X}), {m.get('ms')} ms, "
              f"{reponse_echo(m)}, ML-EID {mleid}")
    elif m.get("t") == "resoudre":
        print(f"<< resoudre {m.get('cible')} : {m.get('erreur')}")
    elif m.get("t") == "diag" and m.get("ok") and "tlv" in m:
        print(f"<< diag {m['cible']} : {m['ms']} ms, code {m.get('code')}, {len(m['tlv']) // 2} octets")
        for ligne in decoder(m["tlv"]):
            print("     ", ligne)
    elif m.get("t") == "routeurs" and "liste" in m:
        print(f"<< routeurs : {len(m['liste'])} entree(s){', suite' if m.get('suite') else ''}")
        for r in m["liste"]:
            print(f"      id {r['id']:2} {r['rloc16']} ext {r['ext'] or '-':16} lq {r['lqIn']}/{r['lqOut']}"
                  f" age {r['age']:3} {'lien' if r['lien'] else '-'}")
    else:
        print("<<", texte_affiche(m))


def attente(c):
    """Type de la ligne qui termine la reponse a c, et l'id d'un diag ou d'une resolution."""
    mots = c.split()
    attendu = mots[0] if mots else ""
    ident = None
    if attendu == "diag" and len(mots) >= 4 and mots[3].isdigit():
        ident = int(mots[3])
    if attendu == "resoudre" and len(mots) >= 3 and mots[2].isdigit():
        ident = int(mots[2])
    return attendu, ident


def delai_reponse(c):
    """Attente de la reponse a c, en secondes : un diag, son delai (45 s par defaut) plus 5 s ; une resolution, ses
    15 s plus 5 s ; le reste, 6 s."""
    mots = c.split()
    if mots[:1] == ["diag"]:
        return (int(mots[4]) / 1000 if len(mots) >= 5 and mots[4].isdigit() else 45) + 5
    if mots[:1] == ["resoudre"]:
        return 15 + 5
    return 6


def fin_de_reponse(m, attendu, ident):
    # routeurs, annonces : "suite":true sur chaque ligne sauf la derniere.
    if m.get("t") == "erreur":
        return True
    return (m.get("t") == attendu and not m.get("suite")
            and (attendu not in ("diag", "resoudre") or m.get("id") == ident))


# ---------------------------------------------------------------------------
#  Cle
# ---------------------------------------------------------------------------


def empreinte(cle):
    return hashlib.sha256(cle).hexdigest().upper()[:8]


def chemin_cle():
    c = os.environ.get("SONDE_CLE")
    return os.path.abspath(os.path.expanduser(c)) if c else None


def ranger_cle(chemin, cle_hex):
    """Ecriture atomique, 0600, sans suivre de lien symbolique (comme benq tools/halo_udp.py)."""
    import tempfile
    d = os.path.dirname(chemin)
    os.makedirs(d, mode=0o700, exist_ok=True)
    fdk, tmp = tempfile.mkstemp(prefix=".cle.", dir=d)  # 0600, nom unique, jamais un lien
    try:
        os.fchmod(fdk, 0o600)
        os.write(fdk, (cle_hex + "\n").encode())
        os.fsync(fdk)
    finally:
        os.close(fdk)
    try:
        os.replace(tmp, chemin)
    except OSError:
        os.unlink(tmp)
        raise


def lire_cle_fichier(chemin):
    try:
        with open(chemin) as f:
            cle = bytes.fromhex(f.read().strip())
    except OSError:
        raise SystemExit(f"{chemin} : illisible")
    except ValueError:
        raise SystemExit(f"{chemin} : cle illisible (64 hexa attendus)")
    if len(cle) != 32:
        raise SystemExit(f"{chemin} : cle illisible (64 hexa attendus)")
    return cle


def cle_du_trousseau(nom):
    """Cle rangee par l'app (security ; macOS demande une fois d'autoriser l'acces)."""
    try:
        r = subprocess.run(["security", "find-generic-password", "-s", SERVICE_TROUSSEAU, "-a", nom, "-w"],
                           capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    try:
        cle = bytes.fromhex(r.stdout.strip())
    except ValueError:
        return None
    return cle if len(cle) == 32 else None


def charger_cle(hote):
    """SONDE_CLE (fichier), sinon le trousseau (compte = nom d'hote sans .local)."""
    chemin = chemin_cle()
    if chemin:
        return lire_cle_fichier(chemin)
    nom = hote[:-len(".local")] if hote.endswith(".local") else hote
    if ":" in nom:
        raise SystemExit("adresse IPv6 : donner la cle par SONDE_CLE=<fichier>, ou viser le nom d'hote")
    cle = cle_du_trousseau(nom)
    if not cle:
        raise SystemExit(f"pas de cle pour {nom} dans le trousseau ({SERVICE_TROUSSEAU}) : la creer depuis l'app "
                         "(Reglages > Sonde, sonde branchee), ou SONDE_CLE=<fichier> et 'cle nouvelle' par l'USB")
    return cle


def cle_nouvelle_usb(fd, lecteur):
    chemin = chemin_cle()
    if not chemin:
        raise SystemExit("cle nouvelle : SONDE_CLE=<fichier> obligatoire (la cle y est rangee, jamais affichee)")
    alea = os.urandom(32).hex().upper()
    ident = 1 + int.from_bytes(os.urandom(3), "big") % 999999
    print(f">> cle nouvelle <alea de 32 octets> {ident}")
    os.write(fd, f"cle nouvelle {alea} {ident}\n".encode("ascii"))
    # Lecture silencieuse : ici, rien de recu ne s'affiche tel quel (une ligne abimee porterait la cle) ;
    # seuls le code d'erreur, l'empreinte verifiee et un nom d'hote bien forme sont imprimes.
    for m in lecteur.lignes(time.time() + 5, silencieux=True):
        if m.get("t") == "erreur":
            code = m.get("erreur")
            code = code if isinstance(code, str) and re.fullmatch(r"[a-z_ ]{1,32}", code) else "?"
            raise SystemExit(f"cle nouvelle refusee : {code} (rien n'a change)")
        if m.get("t") == "cle" and m.get("id") == ident:
            try:
                cle = bytes.fromhex(m.get("cle") or "")
            except (TypeError, ValueError):
                cle = b""
            if len(cle) != 32 or empreinte(cle) != m.get("empreinte"):
                raise SystemExit("reponse incoherente (cle illisible ou empreinte fausse) : cle non rangee")
            ranger_cle(chemin, cle.hex().upper())
            hote = m.get("hote")
            hote = hote if isinstance(hote, str) and re.fullmatch(r"[A-Za-z0-9-]{1,63}", hote) else None
            msg = m.get("msg")
            print(f"cle rangee dans {chemin} (empreinte {m['empreinte']}, hote {hote})")
            if isinstance(msg, str) and re.fullmatch(r"[a-z :'_,.-]{1,64}", msg):
                print(f"   ({msg})")
            return
    raise SystemExit("aucune reponse en 5 s. Si la sonde a quand meme change de cle, 'cle' montre une autre "
                     "empreinte : relancer 'cle nouvelle'.")


# ---------------------------------------------------------------------------
#  USB
# ---------------------------------------------------------------------------


def essai_usb(port, capture, commandes):
    fd = ouvrir(port)
    lecteur = Lecteur(fd, capture)
    try:
        for c in commandes:
            if c.startswith("ecoute:"):
                for m in lecteur.lignes(time.time() + float(c.split(":")[1])):
                    afficher(m)
                continue
            if c.split() == ["cle", "nouvelle"]:
                cle_nouvelle_usb(fd, lecteur)
                continue
            if c.split()[:2] == ["cle", "nouvelle"]:
                print("cle nouvelle : sans argument, l'outil tire l'alea et range la cle (SONDE_CLE)")
                continue
            if c == "refus":
                print("refus : par le reseau seulement (udp:<hote>)")
                continue
            print(f">> {c}")
            os.write(fd, (c + "\n").encode("ascii"))
            attendu, diag_id = attente(c)
            for m in lecteur.lignes(time.time() + delai_reponse(c)):
                afficher(m)
                if fin_de_reponse(m, attendu, diag_id):
                    break
    finally:
        os.close(fd)


# ---------------------------------------------------------------------------
#  Reseau : enveloppe H1 (benq docs/PROTOCOLE-JSON.md, 10.4)
# ---------------------------------------------------------------------------


def mac16(cle, texte):
    return hmac.new(cle, texte.encode() if isinstance(texte, str) else texte, hashlib.sha256).digest()[:16]


def decimal_canonique(b):
    """Entier decimal sans zero de tete (b : octets) ; None sinon."""
    if not b or not b.isdigit() or (len(b) > 1 and b[:1] == b"0") or len(b) > 10:
        return None
    v = int(b)
    return v if v <= 0xFFFFFFFF else None


class Fenetre:
    """Fenetre de 32 contre le rejeu (comme la carte)."""

    def __init__(self):
        self.haut, self.bits = 0, 0

    def accepter(self, ctr):
        if ctr == 0:
            return False
        if ctr > self.haut:
            decalage = ctr - self.haut
            self.bits = 0 if decalage >= 32 else (self.bits << decalage) & 0xFFFFFFFF
            self.bits |= 1
            self.haut = ctr
            return True
        recul = self.haut - ctr
        if recul >= 32 or self.bits & (1 << recul):
            return False
        self.bits |= 1 << recul
        return True


class SessionH1:
    def __init__(self, s, cle):
        self.s, self.cle, self.kid = s, cle, empreinte(cle)
        self.sid, self.ks, self.ctr, self.fenetre = None, None, 0, Fenetre()
        self.rejetes = 0

    def poignee(self):
        """SALUT signe, na neuf a chaque essai ; seul un DEFI au MAC juste pour ce na est pris."""
        for _ in range(3):
            na = os.urandom(16).hex().upper()
            mac = mac16(self.cle, f"H1|SALUT|{self.kid}|{na}").hex().upper()
            try:
                self.s.send(f"H1 SALUT {self.kid} {na} {mac}".encode())
            except OSError as e:
                print(f"!! envoi impossible : {e.strerror} (route IPv6 vers le reseau Thread ?)")
                time.sleep(1)
                continue
            jusqua = time.time() + 2.0
            while time.time() < jusqua:
                self.s.settimeout(max(0.05, jusqua - time.time()))
                try:
                    d = self.s.recv(2048)
                except socket.timeout:
                    break
                except ConnectionRefusedError:
                    raise SystemExit("REFUS (ICMPv6 port injoignable) : ce n'est pas le comportement de la 1.0.2")
                except OSError as e:
                    print(f"!! reception : {e.strerror}")
                    break
                p = d.split(b" ")
                if len(p) != 5 or p[0] != b"H1" or p[1] != b"DEFI":
                    continue  # une ligne d'une session precedente : ignoree
                sid, nc = p[2].decode("ascii", "replace"), p[3].decode("ascii", "replace")
                attendu = mac16(self.cle, f"H1|DEFI|{self.kid}|{na}|{nc}|{sid}").hex().upper().encode()
                if not hmac.compare_digest(attendu, p[4]):
                    continue  # DEFI d'un essai precedent, ou faux : ignore
                self.sid = sid
                self.ks = hmac.new(self.cle, f"H1|SESSION|{na}|{nc}|{sid}".encode(), hashlib.sha256).digest()
                self.ctr, self.fenetre = 0, Fenetre()
                return True
        return False

    def envoyer(self, charge):
        self.ctr += 1
        mac = mac16(self.ks, f"A|{self.sid}|{self.ctr}|".encode() + charge).hex().upper()
        self.s.send(f"H1 {self.sid} {self.ctr} {mac} ".encode() + charge)

    def recevoir(self, delai):
        """Charge du prochain message de la carte au MAC juste ; None au bout du delai."""
        jusqua = time.time() + delai
        while True:
            reste = jusqua - time.time()
            if reste <= 0:
                return None
            self.s.settimeout(reste)
            try:
                d = self.s.recv(2048)
            except socket.timeout:
                return None
            except ConnectionRefusedError:
                print("!! REFUS (ICMPv6 port injoignable) : ce n'est pas le comportement de la 1.0.2")
                continue
            p = d.split(b" ", 4)
            ctr = decimal_canonique(p[2]) if len(p) == 5 else None
            if len(p) != 5 or p[0] != b"H1" or p[1] != self.sid.encode() or ctr is None:
                self.rejetes += 1
                continue
            attendu = mac16(self.ks, b"C|" + p[1] + b"|" + p[2] + b"|" + p[4]).hex().upper().encode()
            if not hmac.compare_digest(attendu, p[3]) or not self.fenetre.accepter(ctr):
                self.rejetes += 1
                print(f"!! datagramme rejete (MAC ou rejeu), ctr {ctr}")
                continue
            return p[4]


def resoudre(hote):
    try:
        ipaddress.IPv6Address(hote)
        nom = hote
    except ValueError:
        # Le nom d'hote de bonjour vient sans .local.
        nom = hote if "." in hote or hote == "localhost" else hote + ".local"
    try:
        ai = socket.getaddrinfo(nom, PORT_RESEAU, socket.AF_INET6, socket.SOCK_DGRAM)
    except socket.gaierror as e:
        raise SystemExit(f"{nom} : {e} (nom d'hote de bonjour ? autorisation Reseau local ?)")
    return nom, ai[0][4]


def refus(adresse, essais=5):
    res = {}
    for _ in range(essais):
        s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        s.settimeout(3)
        try:
            s.connect(adresse)
            s.send(b"x")
            s.recv(64)
            r = "REPONSE (inattendu)"
        except ConnectionRefusedError:
            r = "REFUS : ICMPv6 port injoignable"
        except socket.timeout:
            r = "DELAI : rien (attendu : le port est tenu par la sonde, qui ignore ce datagramme)"
        except OSError as e:
            r = f"ERREUR {e.errno} {e.strerror} (route ?)"
        finally:
            s.close()
        res[r] = res.get(r, 0) + 1
        time.sleep(0.5)
    for r, n in res.items():
        print(f"   {n}/{essais}  {r}")


def essai_reseau(hote, capture, commandes):
    nom, adresse = resoudre(hote)
    print(f"sonde {adresse[0]} port {adresse[1]} ({nom})")
    s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    try:
        s.connect(adresse)
    except OSError as e:
        raise SystemExit(f"{adresse[0]} : {e.strerror} (route IPv6 vers le reseau Thread ?)")
    session, rid = None, 0
    try:
        for c in commandes:
            if c == "refus":
                print(f">> refus ({adresse[0]} port {adresse[1]})")
                refus(adresse)
                continue
            if c.split()[:2] == ["cle", "nouvelle"] and len(c.split()) > 2:
                print("cle nouvelle : par l'USB seulement ; un alea ne part jamais sur le reseau")
                continue
            if session is None:
                session = SessionH1(s, charger_cle(nom))
                if not session.poignee():
                    session = None
                    raise SystemExit("aucun DEFI en 6 s (sonde sans cle ? autre cle ? route IPv6 ? 'refus' pour "
                                     "tester le chemin)")
                print(f"session {session.sid} ouverte (cle {session.kid})")
            if c.startswith("ecoute:"):
                jusqua = time.time() + float(c.split(":")[1])
                while time.time() < jusqua:
                    charge = session.recevoir(jusqua - time.time())
                    if charge is not None:
                        print("   (hors requete)", masquer_strict(charge)[:160])
                continue
            rid += 1
            attendu, diag_id = attente(c)
            limite = delai_reponse(c)
            print(f">> {rid} {c}")
            session.envoyer(f"{rid} {c}".encode("ascii"))
            debut, renvois, vues, complete = time.time(), 0, set(), False
            while not complete and time.time() - debut < limite:
                # Reponse pas encore complete a 2 s puis 4 s : meme rid, la sonde ne relance rien.
                if renvois < 2 and time.time() >= debut + 2 * (renvois + 1):
                    renvois += 1
                    print(f">> (renvoi) {rid} {c}")
                    session.envoyer(f"{rid} {c}".encode("ascii"))
                prochain = debut + 2 * (renvois + 1) if renvois < 2 else debut + limite
                charge = session.recevoir(max(0.05, min(prochain, debut + limite) - time.time()))
                if charge is None:
                    continue
                r, _, ligne = charge.partition(b" ")
                if decimal_canonique(r) != rid:
                    continue  # une reponse en retard d'une requete precedente
                if ligne in vues:
                    continue  # doublon d'un renvoi
                vues.add(ligne)
                try:
                    m = json.loads(ligne.decode("ascii"))
                except (ValueError, UnicodeDecodeError):
                    m = None
                if not isinstance(m, dict):
                    print("?? ligne illisible :", masquer_strict(ligne)[:120])
                    continue
                capturer(capture, m)
                afficher(m)
                complete = fin_de_reponse(m, attendu, diag_id)
            if not complete:
                print(f"!! {rid} {c} : reponse incomplete ou absente en {limite:.0f} s")
                if not vues:
                    session = None  # sonde muette : nouvelle poignee de main a la commande suivante
    finally:
        s.close()


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    port, capture, commandes = sys.argv[1], sys.argv[2], sys.argv[3:]
    if port.startswith("udp:"):
        essai_reseau(port[len("udp:"):], capture, commandes)
    else:
        essai_usb(port, capture, commandes)


if __name__ == "__main__":
    main()
