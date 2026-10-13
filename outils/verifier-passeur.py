#!/usr/bin/env python3
"""Banc du demon Passeur Noms : joue le role d'une app sur la boucle locale (127.0.0.1).

  python3 outils/verifier-passeur.py releve
  python3 outils/verifier-passeur.py abonner [--duree 120] [--relire]

releve  : demande un releve ponctuel (URL maillage-passeur://releve) et le resume.
abonner : s'abonne (URL maillage-passeur://abonner) et resume chaque message recu pendant --duree secondes ;
          --relire envoie `relire` apres le premier releve.
N'affiche que des nombres et des etats : jamais un nom de Maison, une piece, ni un identifiant d'accessoire, ni le
jeton. Ouvre l'URL avec `open -g` (le demon ne passe pas au premier plan).
"""
import argparse
import json
import secrets
import socket
import subprocess
import sys
import time

TAILLE_MAX = 8 * 1024 * 1024


def lire_trames(tampon):
    """Trames completes `<longueur>\\n<JSON>` du tampon ; rend (trames, reste). ValueError si une longueur est fausse."""
    trames = []
    while True:
        fin = tampon.find(b"\n")
        if fin < 0:
            if len(tampon) > 16:
                raise ValueError("ligne de longueur trop longue")
            return trames, tampon
        ligne = tampon[:fin]
        if not ligne.isdigit():
            raise ValueError("longueur illisible")
        n = int(ligne)
        if n <= 0 or n > TAILLE_MAX:
            raise ValueError("longueur hors bornes")
        if len(tampon) < fin + 1 + n:
            return trames, tampon
        trames.append(tampon[fin + 1:fin + 1 + n])
        tampon = tampon[fin + 1 + n:]


def resumer_noms(noms):
    accessoires = noms.get("accessoires", [])
    avec_id = sum(1 for a in accessoires if a.get("id"))
    return (f"version {noms.get('version')}, statut {noms.get('statut')}, {len(accessoires)} accessoires, "
            f"{avec_id} avec id, {len(noms.get('zones') or [])} zones")


def resumer(message):
    t = message.get("t")
    if t == "etat":
        return (f"etat : version {message.get('version')}, acces {message.get('acces')}, ouverture "
                f"{message.get('ouvertureSession')}, profil {message.get('profilExpire')}")
    if t == "releve":
        return "releve : " + resumer_noms(message.get("noms") or {})
    if t == "identifie":
        # Le texte de l'erreur peut reprendre du texte HomeKit : seulement oui ou non.
        return (f"identifie : demande {message.get('demande')}, ok {message.get('ok')}, erreur "
                f"{'oui' if message.get('erreur') else 'non'}")
    return f"message de type {t}"


def ecouter():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    return s, s.getsockname()[1]


ID_PASSEUR = "fr.djoko.maillage.passeur"
ATTENTE_DEMARRAGE = 1.5


def passeur_tourne():
    r = subprocess.run(["pgrep", "-f", "Passeur Noms.app/Contents/MacOS"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0


def lancer_sans_url():
    # HomeKit refuse un demon lance a froid PAR une URL (homed coupe la connexion au premier sync, les maisons
    # n'arrivent jamais : banc du 13/10). On le lance donc d'abord sans URL, puis on attend qu'il soit stable.
    if passeur_tourne():
        return
    r = subprocess.run(["open", "-g", "-b", ID_PASSEUR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        raise SystemExit(f"open a echoue (code {r.returncode}) : Passeur Noms installe ? (outils/passeur.sh)")
    for _ in range(100):
        if passeur_tourne():
            break
        time.sleep(0.1)
    else:
        raise SystemExit("Passeur Noms ne demarre pas (10 s)")
    time.sleep(ATTENTE_DEMARRAGE)


def ouvrir(demande, port, jeton):
    lancer_sans_url()
    # Sortie de `open` masquee : elle pourrait reprendre l'URL, donc le jeton. Pas de check=True : son exception
    # afficherait l'URL complete.
    r = subprocess.run(["open", "-g", f"maillage-passeur://{demande}?port={port}&jeton={jeton}"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        raise SystemExit(f"open a echoue (code {r.returncode}) : Passeur Noms installe ? (outils/passeur.sh)")


def accepter(s, jeton, delai=120):
    s.settimeout(delai)
    c, _ = s.accept()
    s.close()
    c.settimeout(delai)
    tampon = b""
    while b"\n" not in tampon:
        morceau = c.recv(65536)
        if not morceau:
            raise SystemExit("connexion fermee avant le jeton")
        tampon += morceau
    ligne, _, reste = tampon.partition(b"\n")
    if not secrets.compare_digest(ligne, jeton.encode()):
        raise SystemExit("jeton faux")
    print("jeton : ok")
    return c, reste


def releve():
    jeton = secrets.token_hex(32)
    s, port = ecouter()
    ouvrir("releve", port, jeton)
    c, tampon = accepter(s, jeton)
    while True:
        morceau = c.recv(65536)
        if not morceau:
            break
        tampon += morceau
    c.close()
    longueur, _, json_brut = tampon.partition(b"\n")
    if not longueur.isdigit() or len(json_brut) < int(longueur):
        raise SystemExit("trame du releve incomplete")
    print("releve ponctuel : " + resumer_noms(json.loads(json_brut[:int(longueur)])))


def traiter(c, tampon, relu):
    """Traite les trames completes du tampon ; rend (reste, relu). Envoie `relire` au premier releve si demande
    (relu est False)."""
    trames, reste = lire_trames(tampon)
    for t in trames:
        message = json.loads(t)
        print(f"{time.strftime('%H:%M:%S')} {resumer(message)}")
        if not relu and message.get("t") == "releve":
            j = json.dumps({"t": "relire", "v": 1}).encode()
            c.sendall(str(len(j)).encode() + b"\n" + j)
            print("relire envoye")
            relu = True
    return reste, relu


def abonner(duree, relire):
    jeton = secrets.token_hex(32)
    s, port = ecouter()
    ouvrir("abonner", port, jeton)
    c, tampon = accepter(s, jeton)
    c.settimeout(1)
    debut = time.monotonic()
    relu = not relire
    # Les trames arrivees avec le jeton sont traitees tout de suite, sans attendre le prochain recv.
    tampon, relu = traiter(c, tampon, relu)
    while time.monotonic() - debut < duree:
        try:
            morceau = c.recv(65536)
        except socket.timeout:
            continue
        if not morceau:
            print("le demon a ferme la connexion")
            break
        tampon, relu = traiter(c, tampon + morceau, relu)
    c.close()


def main():
    # Sortie ligne par ligne meme dans un tube (`| tee`) : sinon rien ne s'affiche avant la fin.
    sys.stdout.reconfigure(line_buffering=True)
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("demande", choices=["releve", "abonner"])
    p.add_argument("--duree", type=int, default=120)
    p.add_argument("--relire", action="store_true")
    a = p.parse_args()
    if a.demande == "releve":
        releve()
    else:
        abonner(a.duree, a.relire)


if __name__ == "__main__":
    sys.exit(main())
