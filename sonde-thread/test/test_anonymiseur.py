#!/usr/bin/env python3
"""Tests de outils/anonymiser-sonde.py : sa garde, ses remplacements, l'outil lance comme on le lance.

  python3 sonde/test/test_anonymiseur.py
  python3 -m unittest discover -s sonde/test        (tous les tests Python, depuis la racine du depot)

La garde : l'anonymiseur ne connait que les messages de la sonde 1.0.3 et ceux de la capture du 29/09/2026,
avec la forme de chaque champ. Tout autre type de message, champ, forme ou TLV le fait echouer avant toute
ecriture, avec un message clair qui ne cite que des noms, jamais une valeur. Une capture deja anonymisee
ressort telle quelle.

Donnees inventees : les valeurs "reelles" des captures brutes ci-dessous n'ont jamais existe (ExtMac
DEADBEEF..., prefixes de documentation 2001:db8). La capture anonymisee du depot sert de reference.
"""
import importlib.util
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ICI = os.path.dirname(os.path.abspath(__file__))
DEPOT = os.path.normpath(os.path.join(ICI, "..", ".."))
SCRIPT = os.path.join(DEPOT, "outils", "anonymiser-sonde.py")
CAPTURE_ANONYME = os.path.join(DEPOT, "docs", "releves", "2026-09-29", "capture-sonde.jsonl")

# Le nom du script a un tiret : on le charge par son chemin.
_spec = importlib.util.spec_from_file_location("anonymiser_sonde", SCRIPT)
anon = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(anon)

# Valeurs "reelles" inventees des captures brutes.
EXT_PARENT = "DEADBEEF00000001"
EXT_ROUTEUR = "DEADBEEF00000002"
EXT_INCONNU = "DEADBEEF00000003"  # celle d'un champ que l'anonymiseur ne connait pas
EXT_SONDE = "DEADBEEF00000004"  # celle de la sonde, dont Matter tire le nom d'hote SRP
XP = "FEEDFACECAFEBEEF"
MAC = "DEADBEEF0001"
CODE, QR = "99988877766", "MT:FAUX0000000000000000"
PREFIXE_MAILLE, PREFIXE_OMR = "2001:db8:a1b2", "2001:db8:c3d4"
IID_OMR = "aabb:ccdd:eeff:1122"
NOM, EMPREINTE = "Sonde-du-salon", "FEEDF00D"
CLE = "0123456789ABCDEF" * 4
# Tout ce qui ne doit plus se lire dans une sortie (minuscules, sans deux-points).
REEL = [EXT_PARENT, EXT_ROUTEUR, EXT_INCONNU, EXT_SONDE, XP, MAC, CODE, "FAUX0000000000000000", "20010db8a1b2",
        "20010db8c3d4", "aabbccddeeff1122", NOM, EMPREINTE, CLE,
        "dcadbeef00000002"]  # dernier : l'IID lien-local de EXT_ROUTEUR (bit U/L inverse)


def tlv(t, valeur):
    return bytes([t, len(valeur)]) + valeur


def ipv6(texte):
    return ipaddress.IPv6Address(texte).packed


def reseau_inventee():
    """Network Data inventee : un Prefix (avec un routeur de bordure), un Service 5d dont le Server a une adresse."""
    omr = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
    return (tlv(0x03, bytes([0, 64]) + ipv6(PREFIXE_OMR + "::")[:8] + tlv(0x05, bytes.fromhex("50000100")))
            + tlv(0x0B, bytes([0x81, 1, 0x5D]) + tlv(0x0D, bytes.fromhex("5000") + omr + bytes.fromhex("1680"))))


def prefixe_tlv(bits):
    """Un Prefix de la Network Data (bit stable a 1, domaine 0, sans sous-TLV) de `bits` de long, dont les octets
    sont ceux d'une adresse inventee : le prefixe de documentation, puis l'identifiant d'interface."""
    adresse = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
    return tlv(0x03, bytes([0, bits]) + (adresse + bytes(16))[:(bits + 7) // 8])


def service_tlv(donnee, entreprise=False):
    """Un Service de la Network Data : bit T a 1 (numero d'entreprise implicite), ou a 0 avec un numero d'entreprise ;
    puis la donnee de service et un Server (RLOC16 seul)."""
    entete = b"\x01" + bytes.fromhex("0000ABCD") if entreprise else b"\x81"
    return tlv(0x0B, entete + bytes([len(donnee)]) + donnee + tlv(0x0D, bytes.fromhex("5000")))


def charges_valides():
    """Une charge valide par TLV connu : 8 octets pour l'ExtMac, des adresses entieres, une Network Data lisible."""
    return {0: bytes.fromhex(EXT_ROUTEUR), 1: bytes.fromhex("5000"), 2: b"\x0b",
            5: bytes.fromhex("01" + "8000000000000000" + "22"), 6: bytes.fromhex("1A2B3C4D40010218"),
            7: reseau_inventee(), 8: ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR)), 16: bytes.fromhex("08010b"),
            24: bytes.fromhex("0004"), 25: b"Fabricant", 26: b"Modele", 27: b"1.0", 28: b"Pile 1.0"}


def charge_diag():
    """Charge TLV d'un diag de routeur : ExtMac, Address16, Network Data, adresses, version (2 octets)."""
    ext = bytes.fromhex(EXT_ROUTEUR)
    lien_local = ipv6("fe80::")[:8] + bytes([ext[0] ^ 0x02]) + ext[1:]
    omr = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
    rloc = ipv6("%s:0:0:ff:fe00:5000" % PREFIXE_MAILLE)
    return (tlv(0, ext) + tlv(1, bytes.fromhex("5000")) + tlv(7, reseau_inventee()) + tlv(8, lien_local + omr + rloc)
            + tlv(24, b"\x00\x04")).hex().upper()


def tlv_de_premier_niveau(hexa):
    """Les types des TLV d'une charge (sans les decoder plus bas)."""
    o, i, types = bytes.fromhex(hexa), 0, []
    while i + 2 <= len(o):
        types.append(o[i])
        i += 2 + o[i + 1]
    return types


def capture_inventee():
    """Une capture brute inventee, de la forme que sonde_essai.py ecrit : bonjour, etat, diag."""
    return [
        {"heure": "2026-09-28T23:44:56", "t": "bonjour", "v": 1, "produit": "sonde-maillage", "version": "0.1.0-essai",
         "mac": MAC, "appairee": False, "code": CODE, "qr": QR},
        {"heure": "2026-09-28T23:44:59", "t": "etat", "v": 1, "role": "child", "rloc16": "5005", "mode": "rn",
         "parent": {"rloc16": "5000", "ext": EXT_PARENT, "lqIn": 3, "lqOut": 3, "rssi": -60, "rssiDernier": -61,
                    "age": 4},
         "partition": "1A2B3C4D", "chef": 24, "canal": 15, "prefixeMaille": "20010DB8A1B20000", "xp": XP,
         "suspendue": False},
        {"heure": "2026-09-28T23:46:34", "t": "diag", "v": 1, "id": 101, "cible": "5000", "ms": 2782, "ok": True,
         "code": "2.04", "tlv": charge_diag()},
        {"heure": "2026-09-28T23:58:47", "t": "diag", "v": 1, "id": 301, "cible": "%s:0:%s" % (PREFIXE_OMR, IID_OMR),
         "ms": 30000, "ok": False, "erreur": "delai"},
    ]


def capture_1_0_3():
    """Une capture brute inventee de la sonde 1.0.3, de la forme que sonde_essai.py ecrit : chaque type de message,
    les reponses « occupee », la cle deja masquee."""
    compteurs = {"port": 5480, "ouvert": True, "sessions": 1, "provisoire": False, "rx": 120, "rejets": 0,
                 "rx_perdus": 0, "defis": 1, "tx": 118, "tx_perdus": 0, "tx_erreurs": 0, "tampons_min": 22,
                 "lignes_perdues": 0, "refus_cadence": 2}
    return [
        {"heure": "2026-10-01T10:00:00", "t": "bonjour", "v": 1, "produit": "sonde-maillage", "version": "1.0.3",
         "nom": NOM, "mac": MAC, "appairee": True, "code": CODE, "qr": QR, "hote": EXT_SONDE},
        {"heure": "2026-10-01T10:00:01", "t": "etat", "v": 1, "role": "child", "rloc16": "5005", "ext": EXT_SONDE,
         "mode": "rn", "eligible": False,
         "parent": {"rloc16": "5000", "ext": EXT_PARENT, "lqIn": 3, "lqOut": 3, "rssi": -60},
         "partition": "1A2B3C4D", "chef": 24, "canal": 15, "prefixeMaille": "20010DB8A1B20000", "xp": XP,
         "suspendue": False},
        {"heure": "2026-10-01T10:00:02", "t": "etat", "v": 1, "erreur": "occupee"},
        {"heure": "2026-10-01T10:00:03", "t": "routeurs", "v": 1,
         "liste": [{"id": 20, "rloc16": "5000", "ext": EXT_PARENT, "lqIn": 3, "lqOut": 3, "age": 4, "lien": True},
                   {"id": 24, "rloc16": "6000", "ext": None, "lqIn": 0, "lqOut": 0, "age": 30, "lien": False}],
         "suite": False},
        {"heure": "2026-10-01T10:00:04", "t": "voisins", "v": 1,
         "liste": [{"rloc16": "5000", "ext": EXT_PARENT, "rssi": -60, "lqi": 3, "routeur": True},
                   {"rloc16": "6000", "ext": EXT_ROUTEUR, "rssi": -82, "lqi": 1, "routeur": True}]},
        {"heure": "2026-10-01T10:00:05", "t": "voisins", "v": 1, "erreur": "occupee"},
        {"heure": "2026-10-01T10:00:06", "t": "diag", "v": 1, "id": 101, "cible": "5000", "ms": 64, "ok": True,
         "code": "2.04", "tlv": charge_diag(), "tronquee": True},
        {"heure": "2026-10-01T10:00:07", "t": "cle", "v": 1, "empreinte": EMPREINTE, "effacement_en_echec": False,
         "hote": EXT_SONDE, "udp": compteurs, "tas": {"libre": 181234, "min": 160112}},
        {"heure": "2026-10-01T10:00:08", "t": "cle", "v": 1, "id": 7, "cle": "(masquee)", "empreinte": EMPREINTE,
         "hote": EXT_SONDE, "msg": "cle non chargee : active au redemarrage"},
        {"heure": "2026-10-01T10:00:09", "t": "erreur", "v": 1, "erreur": "commande inconnue"},
        {"heure": "2026-10-01T10:00:10", "t": "oubli", "v": 1, "cle_effacee": True},
    ]


def controle(*messages):
    """La garde sur ces messages, numerotes a partir de 1."""
    return anon.controler(list(enumerate(messages, 1)))


# ---------------------------------------------------------------------------
#  La garde, sans lancer l'outil
# ---------------------------------------------------------------------------


class Garde(unittest.TestCase):
    def test_la_capture_actuelle_passe(self):
        numerotes = anon.lire(CAPTURE_ANONYME)
        self.assertEqual({m["t"] for _, m in numerotes}, {"bonjour", "etat", "diag"}, "les trois types y sont")
        self.assertEqual(anon.controler(numerotes), {})

    def test_une_capture_brute_inventee_passe(self):
        self.assertEqual(controle(*capture_inventee()), {})

    def test_une_capture_de_la_sonde_1_0_3_passe(self):
        """Tous les messages de la 1.0.3 : etat.ext et eligible, bonjour.nom et hote, voisins, routeurs, cle (et
        refus_cadence), oubli, erreur, diag.tronquee, et les reponses « occupee »."""
        self.assertEqual(controle(*capture_1_0_3()), {})

    def test_champ_inconnu_fait_echouer(self):
        de_base = {m["t"]: m for m in capture_1_0_3()}
        for t, champ in (("etat", "adresse"), ("etat", "liste"), ("diag", "cle"), ("bonjour", "adresse"),
                         ("voisins", "suite"), ("routeurs", "hote"), ("cle", "nom"), ("oubli", "cle"),
                         ("erreur", "msg")):
            with self.subTest(champ="%s.%s" % (t, champ)):
                self.assertEqual(controle(dict(de_base[t], **{champ: EXT_INCONNU})),
                                 {"champ inconnu : %s.%s" % (t, champ): [1]})

    def test_champ_inconnu_d_un_voisin_d_un_routeur_ou_des_compteurs(self):
        capture = capture_1_0_3()
        routeurs, voisins, cle = capture[3], capture[4], capture[7]
        for message, chemin in ((dict(voisins, liste=[dict(voisins["liste"][0], bssid=EXT_INCONNU)]), "voisins.liste"),
                                (dict(routeurs, liste=[dict(routeurs["liste"][1], nom=EXT_INCONNU)]), "routeurs.liste"),
                                (dict(cle, udp=dict(cle["udp"], adresse=EXT_INCONNU)), "cle.udp"),
                                (dict(cle, tas=dict(cle["tas"], total=5)), "cle.tas")):
            with self.subTest(chemin=chemin):
                (raison,) = controle(message)
                self.assertTrue(raison.startswith("champ inconnu : %s." % chemin), raison)

    def test_listes_et_objets_de_forme_inconnue(self):
        capture = capture_1_0_3()
        routeurs, voisins, cle = capture[3], capture[4], capture[7]
        for liste in ({}, "x", [1], [[]], [EXT_INCONNU], None):
            with self.subTest(liste=liste):
                self.assertEqual(controle(dict(voisins, liste=liste)), {"forme inconnue : voisins.liste": [1]})
        for udp in ([], "x", 5, None):
            with self.subTest(udp=udp):
                self.assertEqual(controle(dict(cle, udp=udp)), {"forme inconnue : cle.udp": [1]})
        sans_ext = dict(voisins["liste"][0], ext=None)  # un voisin a toujours une ExtMac ; un routeur, pas toujours
        self.assertEqual(controle(dict(voisins, liste=[sans_ext])), {"forme inconnue : voisins.liste.ext": [1]})
        self.assertEqual(controle(dict(routeurs, liste=[dict(routeurs["liste"][0], ext=None)])), {})
        self.assertEqual(controle(dict(voisins, liste=[])), {})

    def test_champ_inconnu_du_parent(self):
        etat = capture_inventee()[1]
        etat["parent"] = dict(etat["parent"], hote="sonde-ab12")
        self.assertEqual(controle(etat), {"champ inconnu : etat.parent.hote": [1]})

    def test_parent_de_forme_inconnue(self):
        etat = capture_inventee()[1]
        for parent in ([EXT_INCONNU], EXT_INCONNU, 5, True):
            with self.subTest(parent=parent):
                self.assertEqual(controle(dict(etat, parent=parent)), {"forme inconnue : etat.parent": [1]})
        self.assertEqual(controle(dict(etat, parent=None)), {})  # sonde sans parent : connu

    def test_valeur_non_scalaire_fait_echouer(self):
        """Un champ connu qui porte un objet ou une liste cacherait ce que l'anonymiseur ne lit pas."""
        de_base = {m["t"]: m for m in capture_inventee()}
        for t, champ in (("etat", "role"), ("etat", "xp"), ("etat", "prefixeMaille"), ("etat", "heure"),
                         ("bonjour", "mac"), ("bonjour", "qr"), ("bonjour", "v"), ("diag", "cible"),
                         ("diag", "erreur"), ("diag", "tlv")):
            for valeur in ({"ext": EXT_INCONNU}, [EXT_INCONNU], {}, []):
                with self.subTest(champ="%s.%s" % (t, champ), valeur=valeur):
                    self.assertEqual(controle(dict(de_base[t], **{champ: valeur})),
                                     {"forme inconnue : %s.%s" % (t, champ): [1]})

    def test_texte_exige_pour_les_champs_lus_comme_hexa_ou_adresse(self):
        """mac, xp, prefixeMaille et cible sont lus comme un hexa ou une adresse : un nombre, un booleen ou null passait
        la forme, puis secrets() levait AttributeError."""
        de_base = {m["t"]: m for m in capture_inventee()}
        for t, champ in (("bonjour", "mac"), ("etat", "xp"), ("etat", "prefixeMaille"), ("diag", "cible")):
            for valeur in (12345, -1, 1.5, True, False, None, {"a": 1}, [EXT_INCONNU]):
                with self.subTest(champ="%s.%s" % (t, champ), valeur=valeur):
                    self.assertEqual(controle(dict(de_base[t], **{champ: valeur})),
                                     {"forme inconnue : %s.%s" % (t, champ): [1]})
            for valeur in ("", "x", "pas de l'hexa"):  # n'importe quel texte : la garde ne lit que la forme
                with self.subTest(champ="%s.%s" % (t, champ), texte=valeur):
                    self.assertEqual(controle(dict(de_base[t], **{champ: valeur})), {})

    def test_texte_exige_pour_le_ext_du_parent(self):
        etat = capture_inventee()[1]
        for valeur in (12345, True, None, {}, [EXT_PARENT]):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(etat, parent=dict(etat["parent"], ext=valeur))),
                                 {"forme inconnue : etat.parent.ext": [1]})
        self.assertEqual(controle(dict(etat, parent=dict(etat["parent"], ext="x"))), {})

    def test_valeur_non_scalaire_dans_le_parent(self):
        etat = capture_inventee()[1]
        for valeur in ({"a": 1}, [EXT_PARENT]):
            with self.subTest(valeur=valeur):
                parent = dict(etat["parent"], ext=valeur)
                self.assertEqual(controle(dict(etat, parent=parent)), {"forme inconnue : etat.parent.ext": [1]})

    def test_texte_libre_sur(self):
        """role, mode, produit, version, erreur, msg, code d'un diag : gardes tels quels, donc sans rien qui
        identifie. 64 caracteres au plus ; jamais 8 hexa de suite, ni une adresse ou une MAC."""
        etat = capture_inventee()[1]
        for valeur in ("child", "leader", "", "x", "rdn", "cle non chargee : active au redemarrage", "envoi NoBufs",
                       "trop_long", "0.1.0-essai", "2.04", "x" * 64, "ResponseTimeout"):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(etat, role=valeur)), {})
        for valeur in (0, -5, 1.5, True, None, "x" * 65, "DEADBEEF", "x" + MAC, "2001:db8::1", "fe80::1", "a:b",
                       "de:ad:be:ef:00:01", "r\u00f4le", "deux\nlignes", "a/b", "nom@exemple"):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(etat, role=valeur)), {"forme inconnue : etat.role": [1]})

    EXTMAC_GROUPEES = ("DEAD BEEF 0000 0004", "DE-AD-BE-EF-00-01", "DEAD.BEEF.0000.0004", "DE AD BE EF 00 00 00 04",
                       "DEAD_BEEF_0000_0004", "DE AD-BE.EF_00:00 00 04", "dead beef", "DEAD-BEEF", "x DEAD.BEEF y",
                       "DE_AD_BE_EF_00_01", "DE:AD:BE:EF:00:01", "DEADBEEF0001", "D E A D B E E F")

    def test_texte_libre_refuse_les_identifiants_ecrits_avec_des_separateurs(self):
        """Une ExtMac ou une MAC ecrite par groupes (espace, tiret, point, souligne, deux-points) : 8 hexa de suite une
        fois les separateurs retires."""
        etat = capture_inventee()[1]
        for valeur in self.EXTMAC_GROUPEES:
            with self.subTest(valeur=valeur):
                self.assertFalse(anon.texte_sur(valeur))
                self.assertEqual(controle(dict(etat, role=valeur)), {"forme inconnue : etat.role": [1]})

    def test_texte_libre_garde_les_formes_legitimes_malgre_les_separateurs(self):
        """Retirer les separateurs ne doit pas refuser les textes que la sonde ecrit vraiment."""
        for valeur in ("cle non chargee : active au redemarrage", "envoi NoBufs", "commande inconnue", "0.1.0-essai",
                       "1.0.3", "2.04", "trop_long", "ResponseTimeout", "sonde-maillage", "delai", "a b c d e f",
                       "DE AD BE", "DEAD BEE", "de-ad-be-e"):  # jusqu'a 7 hexa une fois colles : passe
            with self.subTest(valeur=valeur):
                self.assertTrue(anon.texte_sur(valeur))

    def champs_texte(self):
        """(type, chemin, message construit avec `valeur`) pour chaque champ de forme texte, dans CHAMPS_CONNUS et
        dans OBJETS (objets et listes compris)."""
        res = []
        for t, champs in anon.CHAMPS_CONNUS.items():
            for champ, forme in champs.items():
                genre, _, nom = forme.rstrip("?").partition(" ")
                if genre == "texte":
                    res.append(("%s.%s" % (t, champ), lambda v, t=t, champ=champ: {"t": t, champ: v}))
                elif genre in ("objet", "liste"):
                    for sous, sforme in anon.OBJETS[nom].items():
                        if sforme.rstrip("?") == "texte":
                            def fabrique(v, t=t, champ=champ, sous=sous, genre=genre):
                                o = {sous: v}
                                return {"t": t, champ: o if genre == "objet" else [o]}
                            res.append(("%s.%s.%s" % (t, champ, sous), fabrique))
        return res

    def test_tous_les_champs_texte_refusent_une_extmac_groupee(self):
        """Tous les champs de forme texte de CHAMPS_CONNUS et d'OBJETS, pas seulement etat.role."""
        champs = self.champs_texte()
        chemins = {chemin for chemin, _ in champs}
        for attendu in ("bonjour.produit", "bonjour.version", "etat.role", "etat.mode", "etat.erreur", "diag.code",
                        "diag.erreur", "cle.msg", "erreur.erreur", "voisins.erreur", "routeurs.erreur"):
            self.assertIn(attendu, chemins)
        # Aucun champ texte des tables n'est oublie : on recompte a part, objets et listes compris.
        a_part = sum(f.rstrip("?") == "texte" for champs_t in anon.CHAMPS_CONNUS.values() for f in champs_t.values())
        for champs_t in anon.CHAMPS_CONNUS.values():
            for f in champs_t.values():
                genre, _, nom = f.rstrip("?").partition(" ")
                if genre in ("objet", "liste"):
                    a_part += sum(g.rstrip("?") == "texte" for g in anon.OBJETS[nom].values())
        self.assertEqual(len(champs), a_part)
        for chemin, fabrique in champs:
            with self.subTest(champ=chemin, controle="un texte sur passe"):
                self.assertEqual(controle(fabrique("x")), {})
            for valeur in ("DEAD BEEF 0000 0004", "DE-AD-BE-EF-00-01", "DEAD.BEEF.0000.0004", "DEADBEEF00000004"):
                with self.subTest(champ=chemin, valeur=valeur):
                    self.assertEqual(controle(fabrique(valeur)), {"forme inconnue : %s" % chemin: [1]})
        for champ in anon.CHAMPS_COMMUNS:
            if anon.CHAMPS_COMMUNS[champ] == "texte":  # t : un type groupe n'est pas un type connu
                self.assertEqual(controle({champ: "DEAD BEEF 0000 0004"}), {"type de message inconnu : (illisible)": [1]})

    def test_nombres_entiers_de_32_bits(self):
        """Une ExtMac tient dans un entier de 64 bits : un nombre n'en porte pas plus de 32."""
        etat = capture_inventee()[1]
        for valeur in (-60, 0, 127, (1 << 32) - 1, -(1 << 31)):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(etat, parent=dict(etat["parent"], rssi=valeur))), {})
        for valeur in (1 << 32, -(1 << 31) - 1, int(EXT_INCONNU, 16), 1.5, True, "5", None):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(etat, parent=dict(etat["parent"], rssi=valeur))),
                                 {"forme inconnue : etat.parent.rssi": [1]})

    def test_rloc16_partition_et_heure(self):
        etat = capture_inventee()[1]
        for champ, bonnes, mauvaises in (
                ("rloc16", ("5005", "FFFE", "abcd"), ("5", "50050", "ZZZZ", 5005, None)),
                ("partition", ("1A2B3C4D", None), ("1A2B3C4", "1A2B3C4D5", 12)),
                ("heure", ("2026-09-28T23:44:56",), ("2026-09-28 23:44:56", "hier", "2026-09-28T23:44:56Z", 0))):
            for valeur in bonnes:
                with self.subTest(champ=champ, valeur=valeur):
                    self.assertEqual(controle(dict(etat, **{champ: valeur})), {})
            for valeur in mauvaises:
                with self.subTest(champ=champ, valeur=valeur):
                    self.assertEqual(controle(dict(etat, **{champ: valeur})), {"forme inconnue : etat.%s" % champ: [1]})

    def test_champs_effaces_acceptent_tout_scalaire(self):
        """Code d'appairage, QR code, cle : jamais recopies, leur valeur ne compte pas ; un objet ou une liste, si."""
        bonjour, cle = capture_1_0_3()[0], capture_1_0_3()[8]
        for valeur in (CODE, "", 5, True, None):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(bonjour, code=valeur)), {})
        for valeur in ({"a": 1}, [CODE]):
            with self.subTest(valeur=valeur):
                self.assertEqual(controle(dict(bonjour, code=valeur)), {"forme inconnue : bonjour.code": [1]})
        self.assertEqual(controle(dict(cle, cle=CLE)), {})

    def test_une_raison_repetee_sur_une_meme_ligne_compte_une_fois(self):
        double = self.diag_avec(tlv(31, b"\x00") + tlv(1, b"\x00\x00") + tlv(31, b"\x00") + tlv(29, b"\x00")
                                + tlv(29, b"\x00"))
        inconnu = anon.controler([(3, double), (7, double)])
        self.assertEqual(inconnu, {"TLV inconnu : 31 (diag.tlv)": [3, 7], "TLV inconnu : 29 (diag.tlv)": [3, 7]})
        self.assertIn("  TLV inconnu : 31 (diag.tlv) (2 ligne(s), la premiere : 3)", anon.texte_refus(inconnu))
        self.assertEqual(controle(self.diag_avec(tlv(7, bytes([0x0D, 0]) + bytes([0x0D, 0])))),
                         {"sous-TLV inconnu de la Network Data : 6 (diag.tlv)": [1]})

    def test_type_de_message_inconnu_fait_echouer(self):
        """Un type que la sonde 1.0.3 n'ecrit pas, et tout ce qui n'est pas un nom de type lisible."""
        for t in ("journal", "inconnu", "ETAT", "Bonjour", "voisin", ""):
            with self.subTest(t=t):
                attendu = "type de message inconnu : %s" % (t or "(illisible)")
                self.assertEqual(controle({"t": t, "v": 1, "liste": []}), {attendu: [1]})
        for t in (None, 3, True, ["etat"], {"a": 1}):
            with self.subTest(t=t):
                self.assertEqual(controle({"t": t, "v": 1}), {"type de message inconnu : (illisible)": [1]})
        self.assertEqual(controle({"v": 1}), {"type de message inconnu : (illisible)": [1]})

    def test_type_inconnu_ne_dit_rien_de_ses_champs(self):
        self.assertEqual(controle({"t": "journal", "v": 1, "liste": [{"ext": EXT_INCONNU}]}),
                         {"type de message inconnu : journal": [1]})

    def test_ligne_qui_n_est_pas_un_objet(self):
        for ligne in ([1, 2], "texte", 5, None, True):
            with self.subTest(ligne=ligne):
                self.assertEqual(controle(ligne), {"ligne qui n'est pas un objet JSON": [1]})

    def test_raisons_regroupees_avec_les_numeros_de_ligne(self):
        etat = dict(capture_inventee()[1], adresse=EXT_INCONNU)
        ok = capture_inventee()[0]
        inconnu = anon.controler([(2, etat), (5, ok), (9, etat), (12, {"t": "journal"})])
        self.assertEqual(inconnu, {"champ inconnu : etat.adresse": [2, 9], "type de message inconnu : journal": [12]})
        self.assertEqual(list(inconnu), ["champ inconnu : etat.adresse", "type de message inconnu : journal"])

    # --- TLV du diag ---

    def diag_avec(self, charge):
        return dict(capture_inventee()[2], tlv=charge.hex().upper() if isinstance(charge, bytes) else charge)

    def test_tlv_inconnu_fait_echouer(self):
        """29 Child, 30 ChildIpv6 et 31 RouterNeighbor portent des ExtMac ou des adresses : la garde les refuse."""
        for t in (29, 30, 31, 9, 34, 35, 255):
            with self.subTest(tlv=t):
                self.assertEqual(controle(self.diag_avec(tlv(1, b"\x50\x00") + tlv(t, bytes.fromhex(EXT_INCONNU)))),
                                 {"TLV inconnu : %d (diag.tlv)" % t: [1]})

    def test_plusieurs_tlv_inconnus_sont_tous_dits(self):
        inconnu = controle(self.diag_avec(tlv(31, b"\x00") + tlv(1, b"\x00\x00") + tlv(29, b"\x00")))
        self.assertEqual(list(inconnu), ["TLV inconnu : 31 (diag.tlv)", "TLV inconnu : 29 (diag.tlv)"])

    def test_tlv_connus_passent(self):
        """Un TLV de chaque type connu, avec une charge valide."""
        charges = charges_valides()
        self.assertEqual(set(charges), anon.TLV_CONNUS, "un TLV connu sans charge d'exemple")
        self.assertEqual(controle(self.diag_avec(b"".join(tlv(t, charges[t]) for t in sorted(charges)))), {})

    def test_tlv_0_qui_n_a_pas_8_octets_fait_echouer(self):
        """L'ExtMac fait 8 octets : Anonymiseur.tlv() ne remplace que celui-la."""
        for n in (0, 1, 7, 9, 16):
            with self.subTest(octets=n):
                self.assertEqual(controle(self.diag_avec(tlv(0, bytes(n)))),
                                 {"TLV 0 de longueur inattendue (diag.tlv)": [1]})
        self.assertEqual(controle(self.diag_avec(tlv(0, bytes(8)))), {})

    def test_tlv_8_qui_n_est_pas_fait_d_adresses_entieres_fait_echouer(self):
        """Une adresse fait 16 octets : un reste d'octets ne serait pas remplace."""
        for n in (1, 8, 15, 17, 24, 40):
            with self.subTest(octets=n):
                self.assertEqual(controle(self.diag_avec(tlv(8, bytes(n)))),
                                 {"TLV 8 de longueur inattendue (diag.tlv)": [1]})
        for n in (0, 16, 32, 48):
            with self.subTest(octets=n):
                self.assertEqual(controle(self.diag_avec(tlv(8, bytes(n)))), {})

    def test_tlv_de_longueur_fixe(self):
        """Address16 (1) : 2 octets ; Mode (2) : 1 ; Leader Data (6) : 8 ; Version (24) : 2. Un octet de plus porterait
        un morceau de valeur que l'anonymiseur ne lit pas."""
        for t, n in ((1, 2), (2, 1), (6, 8), (24, 2)):
            self.assertEqual(controle(self.diag_avec(tlv(t, bytes(n)))), {}, t)
            for autre in sorted({0, n - 1, n + 1, 16} - {n}):
                with self.subTest(tlv=t, octets=autre):
                    self.assertEqual(controle(self.diag_avec(tlv(t, bytes(autre)))),
                                     {"TLV %d de longueur inattendue (diag.tlv)" % t: [1]})

    def test_route64_un_octet_par_routeur(self):
        """Route64 (5) : numero de sequence, masque des routeurs (8 octets), puis un octet par routeur du masque."""
        masque = (1 << 63 | 1 << 40 | 1 << 2).to_bytes(8, "big")  # 3 routeurs
        self.assertEqual(controle(self.diag_avec(tlv(5, b"\x01" + masque + bytes(3)))), {})
        self.assertEqual(controle(self.diag_avec(tlv(5, b"\x01" + bytes(8)))), {}, "aucun routeur")
        for nom, charge in (("un octet de trop", b"\x01" + masque + bytes(4)),
                            ("un octet de moins", b"\x01" + masque + bytes(2)),
                            ("masque coupe", b"\x01" + masque[:5]), ("vide", b"")):
            with self.subTest(charge=nom):
                self.assertEqual(controle(self.diag_avec(tlv(5, charge))),
                                 {"TLV 5 de longueur inattendue (diag.tlv)": [1]})

    def test_table_des_enfants_par_entrees_de_3_octets(self):
        for n in (0, 3, 6, 12, 60):
            self.assertEqual(controle(self.diag_avec(tlv(16, bytes(n)))), {}, n)
        for n in (1, 2, 4, 8, 16):
            with self.subTest(octets=n):
                self.assertEqual(controle(self.diag_avec(tlv(16, bytes(n)))),
                                 {"TLV 16 de longueur inattendue (diag.tlv)": [1]})

    def test_texte_des_tlv_25_a_28(self):
        """Fabricant, modele, version logicielle, pile : du texte lisible, sans identifiant. Les versions de pile de la
        capture passent (une date, une heure, un condensat de commit de 9 hexa)."""
        for t, texte in ((25, b""), (25, b"Fabricant"), (26, b"Modele 2"), (27, b"1.4.2"),
                         (28, b"OPENTHREAD/1.0.0; EFR32; May 15 2026 07:09:25"),
                         (28, b"SL-OPENTHREAD/2.5.1.0_GitHub-1fceb225b; EFR32; Sep 18 2024 19:39")):
            with self.subTest(tlv=t, texte=texte):
                self.assertEqual(controle(self.diag_avec(tlv(t, texte))), {})
        for t, texte in ((25, b"Fabricant " + EXT_INCONNU.encode()), (26, b"Modele " + MAC.encode()),
                         (27, b"v" + MAC.encode()), (26, b"de:ad:be:ef:00:01"), (28, b"pile 2001:db8::1 ok"),
                         (28, b"pile fe80::1%wpan0"),
                         (25, b"Fabricant\x00"), (26, "Mod\u00e8le".encode()), (28, b"\xff\xfe")):
            with self.subTest(tlv=t, texte=texte):
                self.assertEqual(controle(self.diag_avec(tlv(t, texte))),
                                 {"texte inconnu dans le TLV %d (diag.tlv)" % t: [1]})

    def test_texte_des_tlv_25_a_28_de_longueur_maximale(self):
        for t, n in ((25, 32), (26, 32), (27, 16), (28, 64)):
            self.assertEqual(controle(self.diag_avec(tlv(t, b"x" * n))), {}, t)
            with self.subTest(tlv=t):
                self.assertEqual(controle(self.diag_avec(tlv(t, b"x" * (n + 1)))),
                                 {"TLV %d de longueur inattendue (diag.tlv)" % t: [1]})

    TEXTES_FORGES = ("addr=fd11:2233:4455::1", "ip:fd00::1", "fd00::1.", "fd11:2233:4455::/48", "fd11:2233:4455",
                     "0011:2233:4455:6677", "aabb.ccdd.eeff", "00 11 22 33 44 55 66 77", "00_11_22_33_44_55")

    def test_texte_des_tlv_25_a_28_refuse_les_adresses_et_les_suites_d_hexa_forgees(self):
        """Une adresse collee a `=`, `:` ou un point, un prefixe, une MAC ecrite avec un autre separateur : le controle
        porte sur tout le texte, plus seulement sur les mots que l'espace, `;`, `,`, les parentheses et les crochets
        separent. Le refus ne cite que le champ, jamais la valeur."""
        for t in (25, 26, 27, 28):
            for texte in self.TEXTES_FORGES:
                if len(texte) > anon.TLV_TEXTE_MAX[t]:
                    continue  # refuse pour sa longueur, une autre raison
                with self.subTest(tlv=t, texte=texte):
                    inconnu = controle(self.diag_avec(tlv(t, texte.encode())))
                    self.assertEqual(inconnu, {"texte inconnu dans le TLV %d (diag.tlv)" % t: [1]})
                    self.assertNotIn(texte, "".join(inconnu))
        for texte in self.TEXTES_FORGES:  # le 28 (64 caracteres) les prend tous, seuls ou noyes dans un texte normal
            for ecrit in (texte, "OPENTHREAD/1.0.0; " + texte + "; EFR32", "x" + texte + "x"):
                with self.subTest(texte=ecrit):
                    self.assertEqual(controle(self.diag_avec(tlv(28, ecrit.encode()))),
                                     {"texte inconnu dans le TLV 28 (diag.tlv)": [1]})

    def test_texte_des_tlv_25_a_28_refuse_tout_deux_points_hors_horaire_et_tout_double_deux_points(self):
        for texte in (b"::", b"a::b", b"pile :: x", b"x:y", b"x: y", b"a:1", b"1:2:3", b"07:09:25:1", b"07:09:2",
                      b"07:09:251", b"107:09", b"a07:09", b"07:09a", b"12:34:56:78", b"ip:07:09", b":07:09", b"07:09:"):
            with self.subTest(texte=texte):
                self.assertEqual(controle(self.diag_avec(tlv(28, texte))),
                                 {"texte inconnu dans le TLV 28 (diag.tlv)": [1]})

    def test_texte_des_tlv_25_a_28_refuse_les_groupes_et_les_paires_d_hexa_separes(self):
        """Au moins 3 groupes de 2 a 4 hexa avec un meme separateur (: . _ - espace), ou de 6 a 8 paires avec un meme
        separateur quelconque."""
        for texte in (b"aabb.ccdd.eeff", b"aabb-ccdd-eeff", b"aabb_ccdd_eeff", b"aabb ccdd eeff", b"aabb  ccdd  eeff",
                      b"00 11 22", b"0011 2233 4455 6677", b"a1.b2.c3", b"x 0011 2233 4455 y",
                      b"00/11/22/33/44/55", b"00;11;22;33;44;55", b"00,11,22,33,44,55,66", b"00|11|22|33|44|55|66|77",
                      b"00 11 22 33 44 55", b"00-11-22-33-44-55-66-77", b"00_11_22_33_44_55", b"00.11.22.33.44.55",
                      b"x00 11 22 33 44 55 66 77 88 99"):
            with self.subTest(texte=texte):
                self.assertEqual(controle(self.diag_avec(tlv(28, texte))),
                                 {"texte inconnu dans le TLV 28 (diag.tlv)": [1]})

    def test_texte_des_tlv_25_a_28_garde_les_formes_de_la_capture(self):
        """Ces formes sont celles des champs des TLV 25 a 28 de la capture du depot : une version, une pile OpenThread
        avec une date et un horaire, un condensat de commit de 9 hexa."""
        lus = set()
        for _, m in anon.lire(CAPTURE_ANONYME):
            o, i = bytes.fromhex(m.get("tlv") or ""), 0
            while i + 2 <= len(o):
                if o[i] in anon.TLV_TEXTE_MAX:
                    lus.add((o[i], o[i + 2:i + 2 + o[i + 1]]))
                i += 2 + o[i + 1]
        self.assertIn((28, b"OPENTHREAD/1.0.0; EFR32; May 15 2026 07:09:25"), lus)
        for t, texte in sorted(lus) + [(27, b"1.0.3"), (28, b"OPENTHREAD/1.3.0; 07:09:25"), (28, b"07:09"),
                                       (28, b"7:09:25"), (28, b"commit 1fceb225b"), (28, b"a 07:09:25 b 19:39"),
                                       (28, b"OPENTHREAD/1.0.3 Sep 18 2024 19:39"), (25, b"Fabricant 2"),
                                       (26, b"Modele-2_b"), (28, b"SL-OPENTHREAD/2.5.1.0_GitHub-1fceb225b")]:
            with self.subTest(tlv=t, texte=texte):
                self.assertEqual(controle(self.diag_avec(tlv(t, texte))), {})

    # --- Network Data (TLV 7) ---

    def diag_reseau(self, *tlvs):
        return self.diag_avec(tlv(1, b"\x50\x00") + tlv(7, b"".join(tlvs)))

    def test_network_data_de_la_capture_passe(self):
        """Commissioning Data (la Commissioner Session ID), trois Service, trois Prefix : la Network Data de la
        capture. Son TLV 4 est la raison de DONNEES_RESEAU_CONNUES : sans lui, la capture serait refusee."""
        trouvees = 0
        for _, m in anon.lire(CAPTURE_ANONYME):
            if 7 in tlv_de_premier_niveau(m.get("tlv") or ""):
                trouvees += 1
                self.assertEqual(controle(m), {})
                o = bytes.fromhex(m["tlv"])
                reseau = o[o.index(7) + 2:]
                self.assertEqual(reseau[0] >> 1, 4, "la Network Data de la capture commence par la Commissioning Data")
        self.assertGreater(trouvees, 0)

    def test_sous_tlv_inconnu_de_la_network_data_fait_echouer(self):
        """Hors Prefix (1), Commissioning Data (4) et Service (5), au premier niveau : Has Route, Border Router,
        6LoWPAN ID, Server, ou un type que personne ne connait."""
        for t in (0, 2, 3, 6, 7, 64, 127):
            with self.subTest(sous_tlv=t):
                inconnu = bytes([t << 1 | 1, 2]) + b"\x50\x00"
                self.assertEqual(controle(self.diag_reseau(reseau_inventee(), inconnu)),
                                 {"sous-TLV inconnu de la Network Data : %d (diag.tlv)" % t: [1]})

    def test_commissioning_data_seulement_avec_la_session_id(self):
        self.assertEqual(controle(self.diag_reseau(tlv(0x08, bytes.fromhex("0B02D2FF")))), {})
        for nom, contenu in (("Steering Data en plus", "0B02D2FF0802FFFF"), ("Border Agent Locator", "0902B400"),
                             ("vide", ""), ("Session ID de 3 octets", "0B03D2FF00"),
                             ("autre type MeshCoP", "0C02D2FF"), ("deux Session ID", "0B02D2FF0B02A1B2")):
            with self.subTest(contenu=nom):
                self.assertEqual(controle(self.diag_reseau(tlv(0x08, bytes.fromhex(contenu)))),
                                 {"Commissioning Data inconnue dans la Network Data (diag.tlv)": [1]})

    def test_commissioning_data_accepte_toute_valeur_de_session(self):
        """Un identifiant de session sur 16 bits n'est pas une donnee personnelle : la valeur est libre (la capture
        n'a que D2FF), seuls le type 11, la longueur 2 et l'unicite du sous-TLV comptent."""
        for session in ("D2FF", "A1B2", "0000", "FFFF", "1234"):
            for type_tlv in (0x08, 0x09):  # bit stable a 0 ou a 1
                with self.subTest(session=session, stable=type_tlv & 1):
                    self.assertEqual(controle(self.diag_reseau(tlv(type_tlv, bytes.fromhex("0B02" + session)))), {})

    # --- Prefix de plus de 96 bits ---

    def test_prefixe_de_plus_de_96_bits_fait_echouer(self):
        """Au-dela de 96 bits, l'identifiant d'interface resterait en clair : donnees_reseau() ne remplace que les 6
        premiers octets. Un /128 invente en est le cas."""
        for bits in (97, 104, 120, 128, 129, 255):
            with self.subTest(bits=bits):
                self.assertEqual(controle(self.diag_reseau(prefixe_tlv(bits))),
                                 {"prefixe de plus de 96 bits dans la Network Data (diag.tlv)": [1]})

    def test_prefixe_de_17_a_40_bits_fait_echouer(self):
        """donnees_reseau() ne remplace un Prefix qu'a partir de 41 bits (6 octets) : de 17 a 40 bits, le prefixe (un
        /40 de documentation invente) passerait en clair, et le controle final resterait muet."""
        for bits in (17, 24, 32, 40):
            with self.subTest(bits=bits):
                self.assertEqual(controle(self.diag_reseau(prefixe_tlv(bits))),
                                 {"prefixe de 17 a 40 bits dans la Network Data (diag.tlv)": [1]})

    def test_les_prefixes_de_16_bits_ou_moins_et_de_41_a_96_bits_passent(self):
        """Pas tous les prefixes courts : la capture a un /7. Elle a aussi un /64 et le /96 NAT64."""
        for bits in (0, 1, 7, 8, 16, 41, 48, 64, 95, 96):
            with self.subTest(bits=bits):
                self.assertEqual(controle(self.diag_reseau(prefixe_tlv(bits))), {})

    def test_donnee_de_service_de_plus_de_2_octets_fait_echouer(self):
        """Une donnee de service de plus de 2 octets pourrait porter une adresse, que donnees_reseau() ne remplace
        pas."""
        adresse = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
        for nom, donnee in (("3 octets", b"\x5d\x00\x01"), ("une adresse", adresse), ("40 octets", bytes(40))):
            for entreprise in (False, True):
                with self.subTest(donnee=nom, entreprise=entreprise):
                    self.assertEqual(controle(self.diag_reseau(service_tlv(donnee, entreprise))),
                                     {"donnee de service de plus de 2 octets dans la Network Data (diag.tlv)": [1]})

    def test_donnee_de_service_de_0_a_2_octets_passe(self):
        for donnee in (b"", b"\x5d", b"\x5c\xc5"):  # la capture : 01, 5d, 5cc5
            for entreprise in (False, True):
                with self.subTest(donnee=donnee.hex(), entreprise=entreprise):
                    self.assertEqual(controle(self.diag_reseau(service_tlv(donnee, entreprise))), {})

    def test_network_data_tronquee_fait_echouer(self):
        for nom, reseau in (("longueur trop grande", bytes([0x03, 20, 0, 64])),
                            ("octet seul", reseau_inventee() + b"\x03")):
            with self.subTest(reseau=nom):
                self.assertEqual(controle(self.diag_avec(tlv(7, reseau))), {"Network Data tronquee (diag.tlv)": [1]})

    def test_sous_tlv_d_un_prefix(self):
        """Has Route (entrees de 3 octets), Border Router (4), 6LoWPAN Context (2) : ceux de la capture. Un autre type,
        ou une autre longueur, pourrait porter une adresse que donnees_reseau() ne remplace pas."""
        def prefixe(*sous):
            return tlv(0x03, bytes([0, 64]) + ipv6(PREFIXE_OMR + "::")[:8] + b"".join(sous))

        for sous in ((), (tlv(0x01, bytes(3)),), (tlv(0x01, bytes(15)),), (tlv(0x00, b""),), (tlv(0x05, bytes(8)),),
                     (tlv(0x05, bytes(4)), tlv(0x07, bytes(2)))):
            with self.subTest(sous=b"".join(sous).hex()):
                self.assertEqual(controle(self.diag_reseau(prefixe(*sous))), {})
        adresse = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
        for t in (1, 4, 5, 6, 7, 64, 127):
            with self.subTest(sous_tlv=t):
                self.assertEqual(controle(self.diag_reseau(prefixe(tlv(t << 1 | 1, adresse)))),
                                 {"sous-TLV inconnu d'un Prefix : %d (diag.tlv)" % t: [1]})
        for t, n in ((0, 4), (0, 16), (2, 3), (2, 18), (3, 1), (3, 3), (3, 16)):
            with self.subTest(sous_tlv=t, octets=n):
                self.assertEqual(controle(self.diag_reseau(prefixe(tlv(t << 1 | 1, bytes(n))))),
                                 {"sous-TLV %d de longueur inattendue dans un Prefix (diag.tlv)" % t: [1]})

    def test_server_d_un_service(self):
        """Un RLOC16 seul (2 octets), le serveur SRP (RLOC16, adresse, port : 20 octets, l'adresse remplacee), le
        routeur de dorsale (donnee 01 : 9 octets). Un Server de 12 octets porterait une ExtMac en clair."""
        def service(donnee, *serveurs):
            return tlv(0x0B, b"\x81" + bytes([len(donnee)]) + donnee + b"".join(tlv(0x0D, s) for s in serveurs))

        adresse = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
        for nom, reseau in (("RLOC16 seuls", service(b"\x5c\xc5", bytes(2), bytes(2))),
                            ("serveur SRP", service(b"\x5d", b"\x50\x00" + adresse + b"\x16\x80")),
                            ("routeur de dorsale", service(b"\x01", bytes(9))), ("sans Server", service(b"\x5d"))):
            with self.subTest(service=nom):
                self.assertEqual(controle(self.diag_reseau(reseau)), {})
        for nom, reseau in (("ExtMac", service(b"\x5d", b"\x50\x00" + bytes.fromhex(EXT_INCONNU) + b"\x16\x80")),
                            ("9 octets hors dorsale", service(b"\x5d", bytes(9))),
                            ("adresse sans port", service(b"\x5d", b"\x50\x00" + adresse)),
                            ("vide", service(b"\x5d", b""))):
            with self.subTest(service=nom):
                self.assertEqual(controle(self.diag_reseau(reseau)),
                                 {"Server de longueur inattendue dans la Network Data (diag.tlv)": [1]})
        for t in (0, 1, 2, 3, 5, 7, 64):
            with self.subTest(sous_tlv=t):
                reseau = tlv(0x0B, b"\x81\x01\x5d" + tlv(t << 1 | 1, b"\x50\x00"))
                self.assertEqual(controle(self.diag_reseau(reseau)),
                                 {"sous-TLV inconnu d'un Service : %d (diag.tlv)" % t: [1]})

    def test_prefix_ou_service_tronque(self):
        for nom, reseau in (("sous-TLV du Prefix", tlv(0x03, bytes([0, 64]) + bytes(8) + bytes([0x01, 9, 0]))),
                            ("Server", tlv(0x0B, b"\x81\x01\x5d" + bytes([0x0D, 20]) + b"\x50\x00")),
                            ("octets du prefixe", tlv(0x03, bytes([0, 64]) + bytes(4))),
                            ("Prefix vide", tlv(0x03, b"")),
                            ("donnee de service", tlv(0x0B, b"\x81\x02\x5d")), ("Service vide", tlv(0x0B, b""))):
            with self.subTest(reseau=nom):
                self.assertEqual(controle(self.diag_reseau(reseau)), {"Network Data tronquee (diag.tlv)": [1]})

    CAS_DE_BORD_TRONQUES = (
        ("Prefix d'un seul octet", tlv(0x03, b"\x00")),
        ("Service d'un seul octet avec le bit T a 1", tlv(0x0B, b"\x81")),
        ("octet seul en queue de sous-TLV d'un Prefix", tlv(0x03, bytes([0, 64]) + bytes(8) + b"\x01")),
        ("octet seul en queue de sous-TLV d'un Service", tlv(0x0B, b"\x81\x01\x5d" + b"\x0d")),
        ("Prefix coupe d'exactement un octet", tlv(0x03, bytes([0, 64]) + bytes(7))),
        ("octet seul en queue de la Network Data", prefixe_tlv(64) + b"\x03"))

    def test_cas_de_bord_de_la_network_data_refuses_proprement(self):
        for nom, reseau in self.CAS_DE_BORD_TRONQUES:
            with self.subTest(reseau=nom):
                self.assertEqual(controle(self.diag_avec(tlv(7, reseau))), {"Network Data tronquee (diag.tlv)": [1]})

    def test_les_raisons_de_la_network_data_s_ajoutent_a_celles_du_diag(self):
        inconnu = controle(self.diag_avec(tlv(31, b"\x00") + tlv(7, bytes([0x0D, 0]))))
        self.assertEqual(list(inconnu),
                         ["TLV inconnu : 31 (diag.tlv)", "sous-TLV inconnu de la Network Data : 6 (diag.tlv)"])

    def test_l_anonymiseur_laisserait_ces_donnees_en_clair(self):
        """Ce que la garde retient : donnees_reseau() ne remplace ni la donnee de service, ni un TLV qu'il ne connait
        pas, ni la fin d'un Prefix de plus de 96 bits, ni un Prefix de 17 a 40 bits. Si l'anonymiseur apprend a le
        faire, la garde correspondante peut etre levee."""
        adresse = ipv6("%s:0:%s" % (PREFIXE_OMR, IID_OMR))
        self.assertIn(adresse, anon.Anonymiseur().donnees_reseau(service_tlv(adresse)))
        self.assertIn(adresse, anon.Anonymiseur().donnees_reseau(tlv(0x0D, adresse)))
        self.assertIn(adresse[8:], anon.Anonymiseur().donnees_reseau(prefixe_tlv(128)))  # l'identifiant d'un /128
        self.assertIn(adresse[:5], anon.Anonymiseur().donnees_reseau(prefixe_tlv(40)))  # les 5 octets d'un /40
        ext = bytes.fromhex(EXT_INCONNU)  # une ExtMac dans un Server de 12 octets
        serveur = tlv(0x0B, b"\x81\x01\x5d" + tlv(0x0D, b"\x50\x00" + ext + b"\x16\x80"))
        self.assertIn(ext, anon.Anonymiseur().donnees_reseau(serveur))

    def test_les_tlv_connus_sont_ceux_de_la_capture_actuelle(self):
        vus = set()
        for _, m in anon.lire(CAPTURE_ANONYME):
            o, i = bytes.fromhex(m.get("tlv") or ""), 0
            while i + 2 <= len(o):
                vus.add(o[i])
                i += 2 + o[i + 1]
        inconnus = sorted(vus - anon.TLV_CONNUS)
        self.assertEqual(inconnus, [], "TLV de la capture que la garde ne connait pas")

    def test_tlv_a_longueur_etendue_fait_echouer(self):
        """Longueur 0xFF : la vraie longueur suit sur deux octets. L'anonymiseur ne sait pas la lire."""
        etendu = bytes([16, 0xFF, 0x01, 0x00]) + bytes(256)
        self.assertEqual(controle(self.diag_avec(tlv(1, b"\x50\x00") + etendu)),
                         {"TLV a longueur etendue (diag.tlv)": [1]})

    def test_tlv_tronque_fait_echouer(self):
        for nom, charge in (("valeur coupee", tlv(1, b"\x50\x00") + bytes([16, 9, 1, 2])),
                            ("octet seul", tlv(1, b"\x50\x00") + b"\x01"),
                            ("en-tete seul", bytes([16, 9]))):
            with self.subTest(charge=nom):
                self.assertEqual(controle(self.diag_avec(charge)), {"TLV tronque (diag.tlv)": [1]})

    def test_tlv_illisible_fait_echouer(self):
        for charge in ("ZZ", "123", "0 1", 12, True):
            with self.subTest(tlv=charge):
                self.assertEqual(controle(self.diag_avec(charge)), {"tlv illisible (diag.tlv)": [1]})
        for charge in (["00"], {"a": 1}):  # un objet ou une liste : la forme suffit, dite une fois
            with self.subTest(tlv=charge):
                self.assertEqual(controle(self.diag_avec(charge)), {"forme inconnue : diag.tlv": [1]})

    def test_tlv_vide_ou_absent_passe(self):
        self.assertEqual(controle(self.diag_avec("")), {})
        self.assertEqual(controle(self.diag_avec(None)), {})
        sans_tlv = capture_inventee()[3]
        self.assertNotIn("tlv", sans_tlv)
        self.assertEqual(controle(sans_tlv), {})

    # --- Ce que le refus dit ---

    def test_nom_sur_ne_rend_que_des_noms_courts(self):
        for nom in ("ext", "prefixeMaille", "a_b2", "x" * 32, "deadbee"):  # 7 hexa de suite : lisible
            self.assertEqual(anon.nom_sur(nom), nom)
        for nom in ("", "x" * 33, EXT_INCONNU, "cle" + EXT_INCONNU.lower(), "a b", "\u00e9t\u00e9", None, 5, ["ext"]):
            self.assertEqual(anon.nom_sur(nom), "(illisible)", repr(nom))

    def test_nom_sur_cache_une_mac_un_48_un_code_d_appairage(self):
        """8 hexa de suite suffisent : une MAC (12), un /48 (12), un code d'appairage (11 chiffres)."""
        for nom in (MAC, "x" + MAC.lower(), "20010db8a1b2", "x20010db8a1b2", CODE, "a" + CODE, "deadbeef", "DEADBEEF_"):
            self.assertEqual(anon.nom_sur(nom), "(illisible)", repr(nom))

    def test_aucun_nom_des_tables_n_est_masque_par_nom_sur(self):
        """Les noms connus (types, champs, objets) restent lisibles dans le refus."""
        noms = set(anon.CHAMPS_COMMUNS) | set(anon.CHAMPS_CONNUS) | set(anon.OBJETS)
        for champs in list(anon.CHAMPS_CONNUS.values()) + list(anon.OBJETS.values()):
            noms |= set(champs)
        self.assertIn("refus_cadence", noms)
        for nom in sorted(noms):
            self.assertEqual(anon.nom_sur(nom), nom)

    def test_le_texte_de_refus_ne_cite_que_des_noms(self):
        """Ni valeur de champ, ni nom abime qui porterait une ExtMac."""
        etat = dict(capture_inventee()[1], adresse=EXT_INCONNU)
        etat[EXT_INCONNU] = EXT_ROUTEUR
        texte = anon.texte_refus(anon.controler([(3, etat), (8, {"t": "journal", "liste": [{"ext": EXT_INCONNU}]})]))
        for valeur in (EXT_INCONNU, EXT_ROUTEUR, XP, MAC):
            self.assertNotIn(valeur.lower(), texte.lower())
        self.assertEqual(texte.splitlines()[0], "refus : la capture contient ce que l'anonymiseur ne connait pas ; "
                                                "rien n'a ete ecrit.")
        self.assertIn("  champ inconnu : etat.adresse (1 ligne(s), la premiere : 3)", texte)
        self.assertIn("  champ inconnu : etat.(illisible) (1 ligne(s), la premiere : 3)", texte)
        self.assertIn("  type de message inconnu : journal (1 ligne(s), la premiere : 8)", texte)
        self.assertIn("CHAMPS_CONNUS", texte.splitlines()[-1])


# ---------------------------------------------------------------------------
#  Les remplacements, sans lancer l'outil
# ---------------------------------------------------------------------------


class Remplacement(unittest.TestCase):
    def test_une_valeur_deja_factice_reste_elle_meme(self):
        """Dans le desordre aussi : la factice n'est pas renumerotee (elle le serait par ordre d'apparition)."""
        a = anon.Anonymiseur()
        for valeur in ("E000000000000002", "E000000000000001"):
            self.assertEqual(a.hexa_ext(valeur), valeur)
        self.assertEqual(a.iid(bytes.fromhex("0A00000000000003")), bytes.fromhex("0A00000000000003"))
        self.assertEqual(a.prefixe48(anon.p48_factice(3)), anon.p48_factice(3))
        self.assertEqual((a.mac("A00000000002"), a.nom("SONDE-04"), a.empreinte("C1E00002")),
                         ("A00000000002", "SONDE-04", "C1E00002"))
        self.assertEqual(a.message({"t": "etat", "xp": anon.XP_FACTICE})["xp"], anon.XP_FACTICE)
        self.assertEqual(a.secrets(), set(), "une valeur deja factice n'est pas une valeur reelle")

    def test_une_valeur_reelle_ne_recoit_pas_une_factice_deja_donnee(self):
        a = anon.Anonymiseur()
        a.hexa_ext("E000000000000002")
        self.assertEqual(a.hexa_ext(EXT_PARENT), "E000000000000003")
        a.nom("SONDE-02")
        self.assertEqual(a.nom(NOM), "SONDE-03")

    def assertReelle(self, remplacer, valeur, factice):
        """`valeur`, proche d'une forme factice mais reelle, est remplacee par la premiere factice libre (la meme
        a chaque fois) et non gardee. Rend l'anonymiseur, pour en lire les secrets."""
        a = anon.Anonymiseur()
        self.assertEqual(remplacer(a, valeur), factice)
        self.assertEqual(remplacer(a, valeur), factice)
        self.assertNotEqual(factice, valeur)
        return a

    def test_une_extmac_proche_d_une_factice_mais_reelle_est_remplacee(self):
        """Les bords de E0 + 14 chiffres, inferieurs a 2^16 : E1... et E0...010000 sont reelles."""
        for reelle in ("E100000000000001", "E000000000010000", "E0FFFFFFFFFFFFFF", "DF00000000000001",
                       "E001000000000001", "E000000100000001", "E000000000100000"):
            with self.subTest(ext=reelle):
                a = self.assertReelle(lambda a, v: a.hexa_ext(v), reelle, "E000000000000001")
                self.assertIn(reelle.lower(), a.secrets())
        for factice in ("E000000000000000", "E000000000000001", "E00000000000FFFF"):  # dedans : gardees
            with self.subTest(ext=factice):
                a = anon.Anonymiseur()
                self.assertEqual(a.hexa_ext(factice), factice)
                self.assertEqual(a.secrets(), set())

    def test_un_identifiant_d_interface_proche_d_une_factice_mais_reel_est_remplace(self):
        for reel in ("0A00000000010000", "0A00000000100000", "0A00FFFFFFFFFFFF", "0A01000000000001",
                     "0B00000000000001", "0900000000000001"):
            with self.subTest(iid=reel):
                a = self.assertReelle(lambda a, v: a.iid(bytes.fromhex(v)).hex().upper(), reel, "0A00000000000001")
                self.assertIn(reel.lower(), a.secrets())
        for factice in ("0A00000000000000", "0A0000000000FFFF"):
            with self.subTest(iid=factice):
                a = anon.Anonymiseur()
                self.assertEqual(a.iid(bytes.fromhex(factice)), bytes.fromhex(factice))

    def test_un_prefixe_48_proche_d_un_factice_mais_reel_est_remplace(self):
        """fd00:1111:2222 est le premier factice : fd00:1111:2223, fd00:1112:2222, fd01:1111:2222 sont reels."""
        for reel in ("fd00:1111:2223", "fd00:1112:2222", "fd01:1111:2222", "fd00:1111:2221", "fd00:2222:1111"):
            with self.subTest(prefixe=reel):
                p = ipaddress.IPv6Address(reel + "::").packed[:6]
                a = anon.Anonymiseur()
                self.assertEqual(a.prefixe48(p), anon.p48_factice(1))
                self.assertNotEqual(a.prefixe48(p), p)
                self.assertIn(p.hex(), a.secrets())
        a = anon.Anonymiseur()
        for n in (1, 2, 4096):
            self.assertEqual(a.prefixe48(anon.p48_factice(n)), anon.p48_factice(n))
        self.assertEqual(a.secrets(), set())
        self.assertNotIn(anon.p48_factice(4097), anon.P48_FACTICES)
        b = anon.Anonymiseur()
        self.assertNotEqual(b.prefixe48(anon.p48_factice(4097)), anon.p48_factice(4097))

    def test_une_mac_proche_d_une_factice_mais_reelle_est_remplacee(self):
        """A0000000 + 4 chiffres : un chiffre de trop, un de moins, une minuscule ou un espace ne sont pas factices."""
        for reelle in ("A000000000001", "A0000000000", "A000000000", "A0000000000001", "A0000000000G", "B00000000001",
                       "A0000000 0001", "a00000000001", "A00000010001", "A0000000000\n"):
            with self.subTest(mac=reelle):
                a = self.assertReelle(lambda a, v: a.mac(v), reelle, "A00000000001")
                if len(reelle) >= 8:  # secrets() ignore ce qui a moins de 8 caracteres
                    self.assertIn(reelle.lower(), a.secrets())
        self.assertEqual(anon.Anonymiseur().mac("A0000000FFFF"), "A0000000FFFF")

    def test_un_nom_proche_de_sonde_nn_mais_reel_est_remplace(self):
        """SONDE-NN (2 chiffres ou plus) est factice : SONDE- seul, un chiffre, une lettre, une suite ou un prefixe
        de trop ne le sont pas."""
        for reel in ("SONDE-", "SONDE-1", "SONDE-A1", "SONDE-01A", "SONDE-0A", "SONDE-01 ", "SONDE--01", "sonde-01",
                     "SONDE01", "SONDE-\u0660\u0661", "XSONDE-01", "SONDE-01\n", "SONDE-0 1"):
            with self.subTest(nom=reel):
                a = self.assertReelle(lambda a, v: a.nom(v), reel, "SONDE-01")
                if len(reel) >= 8:
                    self.assertIn(reel.lower(), a.secrets())
        for factice in ("SONDE-01", "SONDE-99", "SONDE-100"):
            self.assertEqual(anon.Anonymiseur().nom(factice), factice)

    def test_une_empreinte_proche_d_une_factice_mais_reelle_est_remplacee(self):
        """C1E0 + 4 hexa : C1E0ABCDE (un de trop), C1E0ABC (un de moins), une minuscule ne sont pas factices."""
        for reelle in ("C1E0ABCDE", "C1E0ABC", "C1E0", "C1E1ABCD", "c1e0abcd", "C1E0ABCG", "D1E0ABCD", "C1E0 ABC",
                       "C1E0ABCD\n"):
            with self.subTest(empreinte=reelle):
                a = self.assertReelle(lambda a, v: a.empreinte(v), reelle, "C1E00001")
                if len(reelle) >= 8:
                    self.assertIn(reelle.lower(), a.secrets())
        for factice in ("C1E00000", "C1E0ABCD", "C1E0FFFF"):
            self.assertEqual(anon.Anonymiseur().empreinte(factice), factice)

    def test_un_xp_proche_du_factice_mais_reel_est_remplace(self):
        a = anon.Anonymiseur()
        proche = "A0A1A2A3A4A5A6A8"
        self.assertEqual(a.message({"t": "etat", "xp": proche})["xp"], anon.XP_FACTICE)
        self.assertIn(proche.lower(), a.secrets())

    def test_le_nom_d_hote_suit_l_ext_de_la_sonde(self):
        """Matter tire le nom d'hote SRP de l'ExtMac : les deux ont la meme factice, dans l'ordre ou ils viennent."""
        a = anon.Anonymiseur()
        hote = a.message({"t": "bonjour", "hote": EXT_SONDE})["hote"]
        self.assertEqual(a.message({"t": "etat", "ext": EXT_SONDE})["ext"], hote)
        self.assertEqual(a.message({"t": "cle", "hote": EXT_SONDE.lower()})["hote"], hote)

    def test_la_cle_en_clair_est_masquee_et_cherchee_dans_la_sortie(self):
        a = anon.Anonymiseur()
        self.assertEqual(a.message({"t": "cle", "cle": CLE})["cle"], "(masquee)")
        self.assertEqual(a.message({"t": "cle", "cle": "(masquee)"})["cle"], "(masquee)")
        self.assertIn(CLE.lower(), a.secrets())


# ---------------------------------------------------------------------------
#  L'outil, lance comme on le lance
# ---------------------------------------------------------------------------


class Outil(unittest.TestCase):
    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.dossier = d.name
        self.entree = os.path.join(self.dossier, "brute.jsonl")
        self.sortie = os.path.join(self.dossier, "anonyme.jsonl")

    def ecrire(self, messages, brut=""):
        with open(self.entree, "w", encoding="utf-8") as f:
            f.write("".join(json.dumps(m) + "\n" for m in messages) + brut)

    def lancer(self, entree=None):
        return subprocess.run([sys.executable, SCRIPT, entree or self.entree, self.sortie], capture_output=True,
                              text=True, timeout=60)

    def assertRefus(self, r, *attendu):
        """Echec (code 1), message clair sur stderr, rien sur stdout, rien d'ecrit, aucune valeur citee."""
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(r.stdout, "")
        self.assertIn("refus : ", r.stderr)
        self.assertIn("rien n'a ete ecrit", r.stderr)
        self.assertNotIn("Traceback", r.stderr)
        for morceau in attendu:
            self.assertIn(morceau, r.stderr)
        self.assertFalse(os.path.exists(self.sortie), "la sortie ne doit pas etre creee")
        self.assertEqual(os.listdir(self.dossier), ["brute.jsonl"], "rien d'autre n'est ecrit")
        for valeur in REEL:
            self.assertNotIn(valeur.lower(), (r.stdout + r.stderr).lower().replace(":", ""))

    def test_champ_inconnu_echoue_sans_rien_ecrire(self):
        messages = capture_inventee()
        messages[1]["adresse"] = EXT_INCONNU
        self.ecrire(messages)
        self.assertRefus(self.lancer(), "champ inconnu : etat.adresse (1 ligne(s), la premiere : 2)")

    def test_type_de_message_inconnu_echoue_sans_rien_ecrire(self):
        messages = capture_inventee()
        messages.insert(2, {"heure": "2026-09-28T23:45:00", "t": "journal", "v": 1,
                            "liste": [{"rloc16": "5000", "ext": EXT_INCONNU, "rssi": -60, "lqi": 3, "routeur": True}]})
        self.ecrire(messages)
        self.assertRefus(self.lancer(), "type de message inconnu : journal (1 ligne(s), la premiere : 3)")

    def test_tlv_inconnu_echoue_sans_rien_ecrire(self):
        """Un TLV RouterNeighbor (31) porterait un ExtMac que l'anonymiseur laisserait passer."""
        messages = capture_inventee()
        messages[2]["tlv"] = (tlv(31, bytes.fromhex(EXT_INCONNU) + b"\x00") + bytes.fromhex(messages[2]["tlv"])).hex()
        self.ecrire(messages)
        self.assertRefus(self.lancer(), "TLV inconnu : 31 (diag.tlv) (1 ligne(s), la premiere : 3)")

    def test_cas_de_bord_de_la_network_data_echouent_sans_trace(self):
        """Un Prefix ou un Service coupe, un octet seul en queue : un message de refus, jamais une trace d'exception."""
        for nom, reseau in Garde.CAS_DE_BORD_TRONQUES:
            with self.subTest(reseau=nom):
                messages = capture_inventee()
                messages[2]["tlv"] = tlv(7, reseau).hex().upper()
                self.ecrire(messages)
                self.assertRefus(self.lancer(), "Network Data tronquee (diag.tlv) (1 ligne(s), la premiere : 3)")

    def test_texte_forge_d_un_tlv_echoue_sans_citer_la_valeur(self):
        for texte in Garde.TEXTES_FORGES:
            with self.subTest(texte=texte):
                messages = capture_inventee()
                messages[2]["tlv"] = tlv(28, texte.encode()).hex().upper()
                self.ecrire(messages)
                r = self.lancer()
                self.assertRefus(r, "texte inconnu dans le TLV 28 (diag.tlv) (1 ligne(s), la premiere : 3)")
                self.assertNotIn(texte, r.stderr)

    def test_valeur_illisible_sort_avec_le_seul_numero_de_ligne(self):
        """Une adresse que ipaddress refuse, un hexa abime : la trace d'une exception citerait la valeur. L'outil sort
        avec le seul numero de ligne. (Un champ qui n'est pas du texte est refuse plus tot, par la garde.)"""
        cas = (("diag", "cible", "2001:db8:zz::1", "zz::1"),  # AddressValueError cite l'adresse
               ("etat", "prefixeMaille", "ZZ20010DB8A1B20000", "ZZ2001"),  # le prefixe du reseau maille, lu d'abord
               ("etat", "parent.ext", "ZZ" + EXT_PARENT, "ZZDEAD"))
        for t, champ, valeur, fragment in cas:
            with self.subTest(champ="%s.%s" % (t, champ), valeur=repr(valeur)):
                messages = capture_inventee()
                numero = next(n for n, m in enumerate(messages, 1) if m["t"] == t and (t != "diag" or "cible" in m))
                if champ == "parent.ext":
                    messages[numero - 1]["parent"]["ext"] = valeur
                else:
                    messages[numero - 1][champ] = valeur
                self.ecrire(messages)
                r = self.lancer()
                self.assertRefus(r, "la ligne %d porte une valeur que l'anonymiseur ne sait pas lire" % numero)
                if fragment:
                    self.assertNotIn(fragment.lower(), r.stderr.lower())

    def test_valeur_illisible_de_la_sonde_1_0_3(self):
        """Un nom d'hote qui n'est pas de l'hexa, une ExtMac abimee, une cible ni RLOC16 ni adresse, un prefixe du
        reseau maille trop court : le seul numero de ligne."""
        abimee = "ZZ" + EXT_SONDE[2:]
        cas = ((1, lambda m: m.update(hote="sonde-" + EXT_SONDE[:6])), (2, lambda m: m.update(ext=abimee)),
               (2, lambda m: m.update(prefixeMaille="20010DB8")),
               (5, lambda m: m["liste"][1].update(ext=abimee)), (7, lambda m: m.update(cible="zz" + EXT_SONDE[:8])))
        for numero, abimer in cas:
            with self.subTest(ligne=numero):
                messages = capture_1_0_3()
                abimer(messages[numero - 1])
                self.ecrire(messages)
                r = self.lancer()
                self.assertRefus(r, "la ligne %d porte une valeur que l'anonymiseur ne sait pas lire" % numero)
                self.assertNotIn(EXT_SONDE[:6].lower(), r.stderr.lower())

    def test_une_exception_de_l_anonymisation_sort_avec_le_seul_numero_de_ligne(self):
        """La garde exige du texte pour les champs lus comme un hexa ou une adresse : TypeError ne vient plus d'eux.
        La sortie couvre quand meme ValueError et TypeError, et ne cite jamais le texte de l'exception."""
        self.ecrire(capture_inventee())
        for erreur in (ValueError, TypeError):
            # message() ; puis le prefixe du reseau maille, lu d'abord
            for methode, numero in (("message", 1), ("prefixe48", 2)):
                with self.subTest(erreur=erreur.__name__, methode=methode):
                    faux = mock.Mock(side_effect=erreur("valeur secrete 2001:db8:zz::1"))
                    with mock.patch.object(anon.Anonymiseur, methode, faux), \
                            mock.patch.object(sys, "argv", ["anonymiser-sonde.py", self.entree, self.sortie]):
                        with self.assertRaises(SystemExit) as e:
                            anon.main()
                    self.assertEqual(str(e.exception), "refus : la ligne %d porte une valeur que l'anonymiseur ne "
                                                       "sait pas lire ; rien n'a ete ecrit." % numero)
                    self.assertFalse(os.path.exists(self.sortie))

    def test_xp_ou_mac_non_textuel_echoue_sans_trace(self):
        """Sans la garde, secrets() levait AttributeError hors de tout try : une trace et un code 1, pas un refus."""
        for champ, indice, nom_du_champ, valeur in (("xp", 1, "etat.xp", 12345), ("xp", 1, "etat.xp", True),
                                                    ("mac", 0, "bonjour.mac", 12345), ("mac", 0, "bonjour.mac", True)):
            with self.subTest(champ=nom_du_champ, valeur=valeur):
                messages = capture_inventee()
                messages[indice][champ] = valeur
                self.ecrire(messages)
                self.assertRefus(self.lancer(), "forme inconnue : %s (1 ligne(s), la premiere : %d)"
                                 % (nom_du_champ, indice + 1))

    def test_prefixe_40_echoue_sans_rien_ecrire(self):
        """Un /40 de documentation : donnees_reseau() le laissait en clair et le controle final restait muet."""
        messages = capture_inventee()
        messages[2]["tlv"] = tlv(7, reseau_inventee() + prefixe_tlv(40)).hex().upper()
        self.ecrire(messages)
        self.assertRefus(self.lancer(),
                         "prefixe de 17 a 40 bits dans la Network Data (diag.tlv) (1 ligne(s), la premiere : 3)")

    def test_server_de_12_octets_echoue_sans_rien_ecrire(self):
        """Une ExtMac dans un Server : donnees_reseau() ne remplace que l'adresse d'un Server de 18 octets ou plus."""
        messages = capture_inventee()
        serveur = tlv(0x0B, b"\x81\x01\x5d" + tlv(0x0D, b"\x50\x00" + bytes.fromhex(EXT_INCONNU) + b"\x16\x80"))
        messages[2]["tlv"] = tlv(7, reseau_inventee() + serveur).hex().upper()
        self.ecrire(messages)
        self.assertRefus(self.lancer(), "Server de longueur inattendue dans la Network Data (diag.tlv) (1 ligne(s), "
                                        "la premiere : 3)")

    def test_prefixe_128_echoue_sans_rien_ecrire(self):
        """Un /128 (prefixe de documentation, identifiant d'interface invente) : l'identifiant resterait en clair."""
        messages = capture_inventee()
        messages[2]["tlv"] = tlv(7, reseau_inventee() + prefixe_tlv(128)).hex().upper()
        self.ecrire(messages)
        self.assertRefus(self.lancer(),
                         "prefixe de plus de 96 bits dans la Network Data (diag.tlv) (1 ligne(s), la premiere : 3)")

    def test_texte_libre_avec_une_extmac_groupee_echoue_sans_la_citer(self):
        for valeur in ("DEAD BEEF 0000 0004", "DE-AD-BE-EF-00-01", "DEAD.BEEF.0000.0004"):
            with self.subTest(valeur=valeur):
                messages = capture_1_0_3()
                messages[1]["role"] = valeur
                self.ecrire(messages)
                r = self.lancer()
                self.assertRefus(r, "forme inconnue : etat.role (1 ligne(s), la premiere : 2)")
                for morceau in ("dead", "beef", "0004", "de-ad"):
                    self.assertNotIn(morceau, r.stderr.lower())

    def fuite(self, groupee):
        """main() en-process, la garde neutralisee : une ExtMac reelle (celle du parent) reste dans un champ texte,
        ecrite `groupee`. Rend le SystemExit."""
        messages = capture_1_0_3()
        messages[1]["erreur"] = groupee
        self.ecrire(messages)
        with mock.patch.object(anon, "controler", return_value={}), \
                mock.patch.object(sys, "argv", ["anonymiser-sonde.py", self.entree, self.sortie]):
            with self.assertRaises(SystemExit) as e:
                anon.main()
        return e.exception

    def test_le_controle_final_refuse_une_fuite_sans_rien_ecrire(self):
        """Le cas « fuite » : la sortie garde une ExtMac reelle, ou le nom reel de la sonde (dont les tirets peuvent
        devenir des espaces), ecrits par groupes. Refus, rien d'ecrit, aucune valeur citee."""
        for groupee in (EXT_PARENT, EXT_PARENT.lower(), "DEAD:BEEF:0000:0001", "DEAD BEEF 0000 0001",
                        "DE-AD-BE-EF-00-00-00-01", "DEAD.BEEF.0000.0001", "DEAD_BEEF_0000_0001",
                        "DE AD.BE-EF_00:00 00.01", "le sonde du salon", "SONDE_DU_SALON", "sonde.du.salon"):
            with self.subTest(ext=groupee):
                sortie = self.fuite(groupee)
                self.assertEqual(str(sortie), "fuite : 1 valeur(s) reelle(s) encore presente(s)")
                for morceau in ("dead", "beef", "0001", "salon"):
                    self.assertNotIn(morceau, str(sortie).lower())
                self.assertFalse(os.path.exists(self.sortie), "la sortie ne doit pas etre creee")
                self.assertEqual(os.listdir(self.dossier), ["brute.jsonl"])

    def test_le_controle_final_ne_touche_pas_une_sortie_qui_existe(self):
        with open(self.sortie, "w", encoding="utf-8") as f:
            f.write("sortie d'une autre capture\n")
        self.fuite("DEAD BEEF 0000 0001")
        with open(self.sortie, encoding="utf-8") as f:
            self.assertEqual(f.read(), "sortie d'une autre capture\n")

    def test_capture_1_0_3_anonymisee_sans_valeur_reelle(self):
        messages = capture_1_0_3()
        messages[8]["cle"] = CLE  # en clair : une capture qui ne viendrait pas de sonde_essai.py
        self.ecrire(messages)
        r = self.lancer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("11 lignes ;"), r.stdout)
        with open(self.sortie, encoding="utf-8") as f:
            texte = f.read()
        s = [json.loads(l) for l in texte.splitlines()]
        bas = texte.lower().replace(":", "")
        for valeur in REEL:
            self.assertNotIn(valeur.lower(), bas)
        # Le nom et le nom d'hote de la sonde, l'ExtMac du parent : les memes factices d'un message a l'autre.
        self.assertEqual((s[0]["nom"], s[0]["code"], s[0]["qr"]), ("SONDE-01", None, None))
        self.assertEqual(s[0]["hote"], s[1]["ext"])
        self.assertEqual(s[7]["hote"], s[1]["ext"])
        self.assertEqual({s[1]["parent"]["ext"], s[3]["liste"][0]["ext"], s[4]["liste"][0]["ext"]},
                         {s[1]["parent"]["ext"]})
        self.assertNotEqual(s[4]["liste"][1]["ext"], s[4]["liste"][0]["ext"])
        self.assertIsNone(s[3]["liste"][1]["ext"])
        self.assertEqual((s[7]["empreinte"], s[8]["empreinte"], s[8]["cle"]), ("C1E00001", "C1E00001", "(masquee)"))
        # Gardes tels quels : compteurs, signaux, qualites, reponses « occupee », erreurs, oubli.
        self.assertEqual((s[7]["udp"], s[7]["tas"]), (messages[7]["udp"], messages[7]["tas"]))
        self.assertEqual([v["rssi"] for v in s[4]["liste"]], [-60, -82])
        for i in (2, 5, 9, 10):
            self.assertEqual(s[i], messages[i])
        self.assertTrue(s[6]["tronquee"])

    def test_la_capture_du_depot_ressort_telle_quelle(self):
        """Deja anonymisee : ses valeurs factices restent les memes, et le controle final ne les prend plus pour des
        valeurs reelles."""
        r = self.lancer(entree=CAPTURE_ANONYME)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "64 lignes ; 0 ExtMac, 0 identifiants, 0 prefixes /48 remplaces\n")
        with open(CAPTURE_ANONYME, "rb") as f, open(self.sortie, "rb") as g:
            self.assertEqual(g.read(), f.read())

    def test_deux_passages_donnent_la_meme_sortie(self):
        self.ecrire(capture_1_0_3() + capture_inventee())
        self.assertEqual(self.lancer().returncode, 0)
        une_fois = os.path.join(self.dossier, "une-fois.jsonl")
        shutil.move(self.sortie, une_fois)
        r = self.lancer(entree=une_fois)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(" 0 ExtMac, 0 identifiants, 0 prefixes /48 remplaces", r.stdout)
        with open(une_fois, encoding="utf-8") as f, open(self.sortie, encoding="utf-8") as g:
            self.assertEqual(g.read(), f.read())

    def test_ne_touche_pas_a_une_sortie_qui_existe(self):
        messages = capture_inventee()
        messages[1]["adresse"] = EXT_INCONNU
        self.ecrire(messages)
        with open(self.sortie, "w", encoding="utf-8") as f:
            f.write("sortie d'une autre capture\n")
        r = self.lancer()
        self.assertEqual(r.returncode, 1)
        with open(self.sortie, encoding="utf-8") as f:
            self.assertEqual(f.read(), "sortie d'une autre capture\n")

    def test_ligne_illisible_dit_son_numero_sans_la_citer(self):
        self.ecrire(capture_inventee()[:2], brut='{"t":"etat","ext":"%s"\n' % EXT_INCONNU)
        self.assertRefus(self.lancer(), "la ligne 3 n'est pas du JSON")

    def test_lignes_vides_sautees_mais_comptees(self):
        messages = capture_inventee()
        messages[1]["adresse"] = EXT_INCONNU
        with open(self.entree, "w", encoding="utf-8") as f:
            f.write(json.dumps(messages[0]) + "\n\n\n" + json.dumps(messages[1]) + "\n")
        self.assertRefus(self.lancer(), "la premiere : 4")

    def test_capture_inventee_anonymisee_sans_valeur_reelle(self):
        messages = capture_inventee()
        self.ecrire(messages)
        r = self.lancer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, "")
        self.assertTrue(r.stdout.startswith("4 lignes ;"), r.stdout)
        with open(self.sortie, encoding="utf-8") as f:
            texte = f.read()
        sorties = [json.loads(l) for l in texte.splitlines()]
        self.assertEqual(len(sorties), 4)
        bas = texte.lower().replace(":", "")
        for valeur in REEL:
            self.assertNotIn(valeur.lower(), bas)
        # Retire : le code d'appairage et le QR. Remplaces : la MAC, le xp, les ExtMac, les prefixes.
        self.assertEqual((sorties[0]["code"], sorties[0]["qr"]), (None, None))
        self.assertNotEqual(sorties[0]["mac"], MAC)
        self.assertNotEqual(sorties[1]["xp"], XP)
        self.assertNotEqual(sorties[1]["parent"]["ext"], EXT_PARENT)
        self.assertNotEqual(sorties[3]["cible"], messages[3]["cible"])
        # Gardes tels quels : RLOC16, partition, canal, delais, identifiants, erreurs.
        for avant, apres in zip(messages[1:], sorties[1:]):
            for champ in ("heure", "t", "v", "role", "rloc16", "mode", "partition", "chef", "canal", "suspendue", "id",
                          "ms", "ok", "code", "erreur"):
                if champ in avant:
                    self.assertEqual(apres[champ], avant[champ], champ)
        self.assertEqual(sorties[1]["parent"]["rloc16"], "5000")
        self.assertEqual(len(sorties[2]["tlv"]), len(messages[2]["tlv"]), "les TLV gardent leur longueur")



if __name__ == "__main__":
    unittest.main()
