#!/usr/bin/env python3
"""Tournee d'essai de la sonde (spec sonde, section 4), port deja designe.

  python3 tournee_essai.py <port> <capture.jsonl> [enfants_max]

1. etat : partition, chef, prefixe du reseau maille ;
2. au chef : Route64 (5) et Leader Data (6) : routeurs actifs ;
3. a chaque routeur (RLOC16 = id << 10) : 0,1,5,16,8,24 puis 25,26,27,28 ;
4. a quelques enfants lus dans les Child Table : 0,8,2 puis 25,26,27,28.
Tout est capture ; un resume s'affiche a la fin.
"""
import json, sys, time

import sonde_essai as s


class Sonde:
    def __init__(self, port, capture):
        self.fd = s.ouvrir(port)
        self.lecteur = s.Lecteur(self.fd, capture)
        self.id = 100

    def commande(self, texte, attendu, delai=5):
        s.os.write(self.fd, (texte + "\n").encode("ascii"))
        for m in self.lecteur.lignes(time.time() + delai):
            if m.get("t") == attendu or m.get("t") == "erreur":
                return m
        return None

    def diag(self, cible, tlv):
        self.id += 1
        t0 = time.time()
        m = self.commande(f"diag {cible} {','.join(map(str, tlv))} {self.id}", "diag", 55)
        return m, time.time() - t0


def tlv_brut(hexa):
    o, i, res = bytes.fromhex(hexa), 0, {}
    while i + 2 <= len(o):
        t, n = o[i], o[i + 1]
        res[t] = o[i + 2:i + 2 + n]
        i += 2 + n
    return res


def routeurs_de(route64):
    masque = int.from_bytes(route64[1:9], "big")
    return [r for r in range(64) if masque & (1 << (63 - r))]


def enfants_de(table, rloc_parent):
    res = []
    for k in range(0, len(table) - 2, 3):
        x = int.from_bytes(table[k:k + 2], "big")
        res.append({"rloc16": f"{rloc_parent | (x & 0x1FF):04X}", "endormi": not (table[k + 2] & 0x08)})
    return res


def afficher(titre, m, duree):
    if not m:
        print(f"   {titre} : pas de reponse ({duree:.1f} s)")
        return
    if not m.get("ok"):
        print(f"   {titre} : echec {m.get('erreur')} ({m.get('ms')} ms)")
        return
    print(f"   {titre} : {m['ms']} ms, {len(m['tlv']) // 2} octets, code {m.get('code')}")
    for ligne in s.decoder(m["tlv"]):
        print("      ", ligne[:220])


def main():
    port, capture = sys.argv[1], sys.argv[2]
    enfants_max = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    sonde = Sonde(port, capture)
    etat = sonde.commande("etat", "etat")
    print("etat :", json.dumps(etat, ensure_ascii=False))
    if not etat or etat.get("chef") is None:
        print("sonde non attachee : rien a faire")
        return
    chef = f"{etat['chef'] << 10:04X}"
    m, d = sonde.diag(chef, [5, 6])
    afficher(f"chef {chef} (Route64, LeaderData)", m, d)
    if not m or not m.get("ok"):
        return
    routeurs = routeurs_de(tlv_brut(m["tlv"]).get(5, b"\0" * 9))
    print(f"routeurs actifs : {routeurs}")
    enfants = []
    for r in routeurs:
        rloc = r << 10
        m, d = sonde.diag(f"{rloc:04X}", [0, 1, 5, 16, 8, 24])
        afficher(f"routeur {rloc:04X}", m, d)
        if m and m.get("ok"):
            enfants += enfants_de(tlv_brut(m["tlv"]).get(16, b""), rloc)
        m, d = sonde.diag(f"{rloc:04X}", [25, 26, 27, 28])
        afficher(f"routeur {rloc:04X} (fabricant)", m, d)
    print(f"enfants vus : {len(enfants)} dont {sum(e['endormi'] for e in enfants)} endormis")
    # Quelques eveilles et quelques endormis, pour les delais.
    choix = [e for e in enfants if not e["endormi"]][:enfants_max // 2] + [e for e in enfants if e["endormi"]][:enfants_max // 2]
    for e in choix:
        m, d = sonde.diag(e["rloc16"], [0, 8, 2, 25, 26, 27, 28])
        afficher(f"enfant {e['rloc16']} ({'endormi' if e['endormi'] else 'eveille'})", m, d)


if __name__ == "__main__":
    main()
