#!/usr/bin/env python3
"""Tests de sonde/sonde_essai.py : masquage des secrets, decodage du TLV 7, annonces et resolutions (1.1.0).

  python3 sonde/test/test_sonde_essai.py
  python3 -m unittest discover -s sonde/test        (tous les tests Python, depuis la racine du depot)

Aucun port serie, aucun reseau : le module est importe, jamais lance ; ouvrir() est remplace par une
erreur ; le Lecteur lit une paire de sockets locale ; le temps est simule (aucune attente, aucune
dependance a la charge de la machine). Donnees inventees : la cle est un condensat d'un texte, elle ne
sert a aucune sonde ; le TLV 7 vient de la capture anonymisee du depot.

Le masquage tient une regle : la cle d'une sonde ne s'affiche jamais, ni a l'ecran ni dans la capture,
meme quand la ligne qui la porte arrive abimee (journal de la carte au milieu, octets perdus, JSON coupe).
On la cherche par morceaux : aucune suite de 16 hexa de la cle ne doit rester (une cle coupee par un
journal n'y laisse rien de long).
"""
import ast
import contextlib
import hashlib
import io
import json
import os
import select
import socket
import stat
import sys
import tempfile
import time
import unittest
from unittest import mock

ICI = os.path.dirname(os.path.abspath(__file__))
SONDE = os.path.normpath(os.path.join(ICI, ".."))
DEPOT = os.path.normpath(os.path.join(SONDE, ".."))
CAPTURE_ANONYME = os.path.join(DEPOT, "docs", "releves", "2026-09-29", "capture-sonde.jsonl")

sys.path.insert(0, SONDE)
os.environ.pop("SONDE_PORT", None)  # sonde_essai lit un entier au chargement : pas celui du poste
import sonde_essai as s  # noqa: E402

CLE = hashlib.sha256(b"cle inventee pour les tests de sonde_essai").digest()  # 32 octets, aucune sonde
CLE_HEXA = CLE.hex().upper()
EMPREINTE = s.empreinte(CLE)
MSG = "cle non chargee : active au redemarrage"
RS = b"\x1e"
ALEA = bytes(range(32))  # ce que os.urandom(32) rend dans cle_nouvelle_usb, sous test
IDENT = 1 + int.from_bytes(bytes(range(3)), "big") % 999999  # idem pour os.urandom(3) : 259


# ---------------------------------------------------------------------------
#  Outils des tests
# ---------------------------------------------------------------------------


class TempsSimule:
    """Remplace `time` dans sonde_essai : chaque lecture de l'heure avance de 50 ms."""

    def __init__(self):
        self.t = 1000.0

    def time(self):
        self.t += 0.05
        return self.t

    def __getattr__(self, nom):  # strftime, sleep... : le vrai module
        return getattr(time, nom)


class SelectSansAttente:
    """Remplace `select` dans sonde_essai : ne bloque jamais."""

    def select(self, lus, ecrits, autres, delai=None):
        return select.select(lus, ecrits, autres, 0)

    def __getattr__(self, nom):
        return getattr(select, nom)


@contextlib.contextmanager
def sans_attente():
    """Avec ceci, Lecteur.lignes parcourt ses 5 s de cle nouvelle en quelques millisecondes."""
    with mock.patch.object(s, "time", TempsSimule()), mock.patch.object(s, "select", SelectSansAttente()):
        yield


def morceaux(cle_hexa, taille=16):
    return [cle_hexa[i:i + taille] for i in range(len(cle_hexa) - taille + 1)]


def json_cle(ident=IDENT, **remplace):
    """La reponse de la sonde a `cle nouvelle`, telle qu'elle l'ecrit (sans espaces)."""
    m = {"v": 1, "t": "cle", "id": ident, "cle": CLE_HEXA, "empreinte": EMPREINTE, "hote": "sonde-ab12", "msg": MSG}
    m.update(remplace)
    return json.dumps(m, separators=(",", ":")).encode("ascii")


def dans_la_cle(j, n):
    """Indice, dans le JSON j, n hexa apres le debut de la valeur de cle."""
    return j.index(b'"cle":"') + len(b'"cle":"') + n


# Les formes de reponse, intacte ou abimee, a `cle nouvelle` (les 12 du banc de la 1.0.2, plus celle des
# morceaux de moins de 16 hexa) et ce que l'outil en fait : (octets que la carte envoie, issue).
# Issue : "rangee" (cle rangee), "incoherente" (ligne decodee mais cle illisible ou fausse),
# "aucune reponse" (rien de lisible en 5 s).
def _formes():
    j = json_cle()
    c1, c2 = dans_la_cle(j, 20), dans_la_cle(j, 44)
    journal = b"I (812) wifi: station deconnectee"
    return {
        "intacte": (RS + j + b"\n", "rangee"),
        "octets avant le RS": (b"\x00\x07ab" + RS + j + b"\n", "rangee"),
        "journal avec LF au milieu de la cle": (RS + j[:c1] + b"\r\n" + journal + b"\r\n" + j[c1:] + b"\n",
                                                "aucune reponse"),
        "nom de champ abime": (RS + j.replace(b'"cle":', b'"cl":') + b"\n", "incoherente"),
        "nom abime et cle collee a une lettre": (RS + j.replace(b'"cle":"', b'"cl":"z') + b"\n", "incoherente"),
        "octets perdus": (RS + j[:c1] + j[c1 + 6:] + b"\n", "incoherente"),
        "journal sans LF dans la cle": (RS + j[:c1] + journal + j[c1:] + b"\n", "incoherente"),
        "type abime": (RS + j.replace(b'"t":"cle"', b'"t":"cl"') + b"\n", "aucune reponse"),
        "JSON non ferme": (RS + j[:-1] + b"\n", "aucune reponse"),
        "cle en trois morceaux": (RS + j[:c1] + b"\n" + j[c1:c2] + b"\n" + j[c2:] + b"\n", "aucune reponse"),
        "cle dans un journal": (b"I (812) cle nouvelle : " + CLE_HEXA.encode() + b"\n", "aucune reponse"),
        "cle en minuscules coupee": (RS + j[:c2].lower() + b"\n", "aucune reponse"),
        # Des morceaux de moins de 16 hexa : masquer_strict ne peut rien y faire, seul le silence les retient.
        "cle en morceaux de moins de 16 hexa": (
            RS + j[:dans_la_cle(j, 0)] + b"\n"
            + b"".join(CLE_HEXA.encode()[i:i + 10] + b"\n" for i in range(0, len(CLE_HEXA), 10)), "aucune reponse"),
    }


FORMES = _formes()


class AvecCle(unittest.TestCase):
    def assertSansMorceauDeCle(self, texte, taille=16):
        bas = texte.lower()
        for m in morceaux(CLE_HEXA.lower(), taille):
            self.assertNotIn(m, bas, "un morceau de %d hexa de la cle est reste" % taille)


class BaseTest(AvecCle):
    def setUp(self):
        # Aucun test n'ouvre de port serie : ouvrir() leve au lieu d'ouvrir.
        p = mock.patch.object(s, "ouvrir", side_effect=AssertionError("port serie interdit en test"))
        p.start()
        self.addCleanup(p.stop)
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.dossier = d.name
        self.capture = os.path.join(self.dossier, "capture.jsonl")
        self.fichier_cle = os.path.join(self.dossier, "cle.txt")

    def contenu_capture(self):
        try:
            with open(self.capture, encoding="utf-8") as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def paire(self):
        carte, poste = socket.socketpair()
        carte.settimeout(2.0)
        self.addCleanup(carte.close)
        self.addCleanup(poste.close)
        return carte, poste

    def lire(self, octets, silencieux):
        """Fait lire `octets` a un Lecteur, comme essai_usb (affiche chaque message) ou cle nouvelle
        (silencieux). Rend (messages, ecran)."""
        carte, poste = self.paire()
        carte.sendall(octets)
        ecran, messages = io.StringIO(), []
        with sans_attente(), contextlib.redirect_stdout(ecran):
            lecteur = s.Lecteur(poste.fileno(), self.capture)
            for m in lecteur.lignes(s.time.time() + 0.3, silencieux=silencieux):
                messages.append(m)
                if not silencieux:
                    s.afficher(m)
        return messages, ecran.getvalue()

    def cle_nouvelle(self, octets):
        """Lance cle_nouvelle_usb, la carte ayant deja repondu `octets`. Rend (ecran, message de sortie)."""
        carte, poste = self.paire()
        carte.sendall(octets)
        ecran, sortie = io.StringIO(), None
        with mock.patch.dict(os.environ, {"SONDE_CLE": self.fichier_cle}), \
                mock.patch.object(os, "urandom", lambda n: bytes(range(n))), \
                sans_attente(), contextlib.redirect_stdout(ecran):
            try:
                s.cle_nouvelle_usb(poste.fileno(), s.Lecteur(poste.fileno(), self.capture))
            except SystemExit as e:
                sortie = str(e)
        self.commande_envoyee = carte.recv(4096)
        return ecran.getvalue(), sortie


# ---------------------------------------------------------------------------
#  masquer_strict : texte recu affiche tel quel
# ---------------------------------------------------------------------------


class MasquerStrict(AvecCle):
    def test_champ_cle_masque_avec_ou_sans_guillemet_ferme(self):
        self.assertEqual(s.masquer_strict('{"t":"cle","cle":"0123abcd"}'), '{"t":"cle","cle":"********"}')
        self.assertEqual(s.masquer_strict('{"t":"cle","cle":"0123abcd'), '{"t":"cle","cle":"********')
        self.assertEqual(s.masquer_strict('{"cle"  :  "0F"'), '{"cle"  :  "********"')

    def test_suite_de_16_hexa_masquee_15_conservee(self):
        self.assertEqual(s.masquer_strict("a" * 15), "a" * 15)
        self.assertEqual(s.masquer_strict("a" * 16), "********")
        self.assertEqual(s.masquer_strict("cle=" + "B" * 40 + " et " + "c" * 16), "cle=******** et ********")

    def test_minuscules_et_majuscules(self):
        self.assertNotIn(CLE_HEXA[:16], s.masquer_strict("x" + CLE_HEXA + "x"))
        self.assertNotIn(CLE_HEXA.lower()[:16], s.masquer_strict("x" + CLE_HEXA.lower() + "x"))

    def test_octets_decodes_en_ascii(self):
        self.assertEqual(s.masquer_strict(b"cle " + CLE_HEXA.encode()), "cle ********")
        self.assertEqual(s.masquer_strict(bytearray(b"\xff\xfe " + CLE_HEXA.encode())), "\ufffd\ufffd ********")

    def test_texte_sans_hexa_long_inchange(self):
        texte = "I (812) wifi: station deconnectee, 12 voisins, rloc16 5000"
        self.assertEqual(s.masquer_strict(texte), texte)

    def test_masquer_avant_de_couper(self):
        """Comme le Lecteur : masque puis coupe. Couper d'abord laisserait un bout de la cle."""
        ligne = "x" * 150 + CLE_HEXA
        affiche = s.masquer_strict(ligne)[:160]
        self.assertSansMorceauDeCle(affiche, 8)


# ---------------------------------------------------------------------------
#  sans_cle et texte_affiche : messages decodes
# ---------------------------------------------------------------------------


class SansCle(AvecCle):
    def test_champ_cle_remplace_et_message_intact(self):
        m = {"v": 1, "t": "cle", "id": 7, "cle": CLE_HEXA, "empreinte": EMPREINTE}
        r = s.sans_cle(m)
        self.assertEqual(r["cle"], "(masquee)")
        self.assertEqual(r["empreinte"], EMPREINTE)
        self.assertEqual(m["cle"], CLE_HEXA, "le message d'origine n'est pas modifie")

    def test_champ_cle_remplace_meme_dans_un_message_de_donnees(self):
        for t in sorted(s.TYPES_DONNEES):
            with self.subTest(t=t):
                self.assertEqual(s.sans_cle({"t": t, "cle": CLE_HEXA})["cle"], "(masquee)")

    def test_messages_de_donnees_restent_entiers(self):
        """ExtMac (16 hexa), nom d'hote SRP (16), TLV : lisibles, c'est voulu (jamais sur une ligne de console)."""
        for t in sorted(s.TYPES_DONNEES):
            with self.subTest(t=t):
                m = {"t": t, "ext": "1122334455667788", "tlv": "00081122334455667788" * 4, "liste": [{"x": "AB" * 20}]}
                self.assertEqual(s.sans_cle(m), m)

    def test_reponse_de_cle_ou_type_abime_sans_hexa_long(self):
        for t in ("cle", "cl", "", None, 7, ["cle"], {"t": "cle"}):
            with self.subTest(t=t):
                m = {"v": 1, "t": t, "champ": CLE_HEXA, CLE_HEXA: 1, "liste": [CLE_HEXA], "dans": {CLE_HEXA: CLE_HEXA}}
                self.assertSansMorceauDeCle(json.dumps(s.sans_cle(m)))

    def test_nom_de_champ_abime_qui_porte_la_cle(self):
        r = s.sans_cle({"t": "cle", CLE_HEXA[:40]: 1, "x" + CLE_HEXA[40:]: 2})
        self.assertSansMorceauDeCle(json.dumps(r))

    def test_limite_16_gardes_17_masques(self):
        """Le nom d'hote SRP fait 16 hexa et l'empreinte 8 : lisibles ; 17 et plus : masques."""
        r = s.sans_cle({"t": "inconnu", "a": "E" * 16, "b": "E" * 17, "c": "E" * 8})
        self.assertEqual((r["a"], r["b"], r["c"]), ("E" * 16, "********", "E" * 8))

    def test_valeurs_non_textuelles_inchangees(self):
        m = {"t": "inconnu", "n": 12, "ok": True, "rien": None, "x": 1.5}
        self.assertEqual(s.sans_cle(m), m)

    def test_texte_affiche_sans_cle_et_en_unicode(self):
        m = {"t": "cle", "cle": CLE_HEXA, "nom": "Salon \u00e9t\u00e9"}
        texte = s.texte_affiche(m)
        self.assertSansMorceauDeCle(texte)
        self.assertIn("(masquee)", texte)
        self.assertIn("Salon \u00e9t\u00e9", texte, "ensure_ascii=False")


# ---------------------------------------------------------------------------
#  capturer : la capture ne recoit jamais la cle
# ---------------------------------------------------------------------------


class Capturer(BaseTest):
    def test_ligne_avec_l_heure_sans_cle(self):
        s.capturer(self.capture, {"v": 1, "t": "cle", "id": 3, "cle": CLE_HEXA, "empreinte": EMPREINTE})
        brut = self.contenu_capture()
        self.assertSansMorceauDeCle(brut)
        ligne = json.loads(brut)
        self.assertRegex(ligne["heure"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$")
        self.assertEqual((ligne["t"], ligne["cle"], ligne["empreinte"]), ("cle", "(masquee)", EMPREINTE))

    def test_messages_de_donnees_captures_entiers(self):
        m = {"v": 1, "t": "diag", "id": 9, "cible": "5000", "ok": True, "tlv": "0008" + "1122334455667788"}
        s.capturer(self.capture, m)
        self.assertEqual({k: v for k, v in json.loads(self.contenu_capture()).items() if k != "heure"}, m)

    def test_chaque_appel_ajoute_une_ligne(self):
        s.capturer(self.capture, {"t": "etat"})
        s.capturer(self.capture, {"t": "bonjour"})
        self.assertEqual([json.loads(l)["t"] for l in self.contenu_capture().splitlines()], ["etat", "bonjour"])


# ---------------------------------------------------------------------------
#  Lecteur : les formes de ligne, en lecture silencieuse (cle nouvelle) et a l'ecran
# ---------------------------------------------------------------------------


class LecteurDeLignes(BaseTest):
    def test_message_intact_lu_affiche_masque_et_capture_masque(self):
        messages, ecran = self.lire(FORMES["intacte"][0], silencieux=False)
        self.assertEqual([m["t"] for m in messages], ["cle"])
        self.assertEqual(messages[0]["cle"], CLE_HEXA, "l'outil garde la vraie cle en memoire pour la ranger")
        self.assertIn("(masquee)", ecran)
        self.assertSansMorceauDeCle(ecran)
        self.assertSansMorceauDeCle(self.contenu_capture())

    def test_octets_avant_le_rs_affiches_masques_et_ligne_lue(self):
        avant = b"journal " + CLE_HEXA.encode() + b" "
        messages, ecran = self.lire(avant + RS + json_cle() + b"\n", silencieux=False)
        self.assertEqual([m["t"] for m in messages], ["cle"])
        self.assertIn("   | journal ********", ecran)
        self.assertSansMorceauDeCle(ecran)

    def test_silencieux_n_affiche_rien_du_tout(self):
        for nom, (octets, _) in FORMES.items():
            with self.subTest(forme=nom):
                _, ecran = self.lire(octets, silencieux=True)
                self.assertEqual(ecran, "")

    def test_aucune_forme_ne_laisse_un_morceau_de_cle_a_l_ecran_ni_dans_la_capture(self):
        for silencieux in (True, False):
            for nom, (octets, _) in FORMES.items():
                with self.subTest(forme=nom, silencieux=silencieux):
                    if os.path.exists(self.capture):
                        os.unlink(self.capture)
                    _, ecran = self.lire(octets, silencieux)
                    self.assertSansMorceauDeCle(ecran)
                    self.assertSansMorceauDeCle(self.contenu_capture())

    def test_ligne_illisible_affichee_masquee_et_non_capturee(self):
        """JSON coupe, ou JSON qui n'est pas un objet : dit a l'ecran (masque), rien n'est capture."""
        for nom, corps in (("coupe", json_cle()[:-1]), ("liste", b'["' + CLE_HEXA.encode() + b'"]'),
                           ("texte", b'"' + CLE_HEXA.encode() + b'"')):
            with self.subTest(corps=nom):
                messages, ecran = self.lire(RS + corps + b"\n", silencieux=False)
                self.assertEqual(messages, [])
                self.assertIn("?? ligne machine illisible :", ecran)
                self.assertSansMorceauDeCle(ecran)
                self.assertEqual(self.contenu_capture(), "")

    def test_ligne_sans_rs_affichee_masquee(self):
        _, ecran = self.lire(b"I (812) cle=" + CLE_HEXA.encode() + b" fin\n", silencieux=False)
        self.assertEqual(ecran, "   | I (812) cle=******** fin\n")

    def test_masquer_avant_de_couper_a_160_caracteres(self):
        _, ecran = self.lire(b"x" * 150 + CLE_HEXA.encode() + b"\n", silencieux=False)
        self.assertSansMorceauDeCle(ecran, 8)
        self.assertEqual(ecran, "   | " + "x" * 150 + "********\n")

    def test_le_rs_le_plus_a_droite_commence_la_ligne_machine(self):
        messages, _ = self.lire(RS + b"{pas du json" + RS + json_cle() + b"\n", silencieux=True)
        self.assertEqual([m["t"] for m in messages], ["cle"])

    def test_cr_final_ignore(self):
        messages, _ = self.lire(RS + json_cle() + b"\r\n", silencieux=True)
        self.assertEqual([m["t"] for m in messages], ["cle"])


# ---------------------------------------------------------------------------
#  cle_nouvelle_usb : ce que l'outil range, et ce qu'il dit
# ---------------------------------------------------------------------------


class CleNouvelleUsb(BaseTest):
    def lire_fichier_cle(self):
        with open(self.fichier_cle, encoding="ascii") as f:
            return f.read()

    def test_toutes_les_formes(self):
        """Cle rangee seulement pour la forme intacte et celle aux octets avant le RS ; a l'ecran, l'invitation
        et rien d'autre (la lecture est silencieuse) ; jamais un morceau de cle dans la sortie ni la capture."""
        invitation = ">> cle nouvelle <alea de 32 octets> %d\n" % IDENT
        for nom, (octets, issue) in FORMES.items():
            with self.subTest(forme=nom):
                for f in (self.fichier_cle, self.capture):
                    if os.path.exists(f):
                        os.unlink(f)
                ecran, sortie = self.cle_nouvelle(octets)
                self.assertSansMorceauDeCle(ecran + (sortie or ""))
                self.assertSansMorceauDeCle(self.contenu_capture())
                self.assertNotIn(ALEA.hex().upper(), ecran + (sortie or ""), "l'alea envoye n'est pas affiche")
                if issue == "rangee":
                    self.assertIsNone(sortie)
                    self.assertEqual(self.lire_fichier_cle(), CLE_HEXA + "\n")
                    self.assertEqual(ecran, invitation + "cle rangee dans %s (empreinte %s, hote sonde-ab12)\n   (%s)\n"
                                     % (self.fichier_cle, EMPREINTE, MSG))
                else:
                    self.assertEqual(ecran, invitation)
                    self.assertFalse(os.path.exists(self.fichier_cle), "aucune cle rangee")
                    self.assertIsNotNone(sortie)
                    dit = {"incoherente": "reponse incoherente", "aucune reponse": "aucune reponse en 5 s"}[issue]
                    self.assertIn(dit, sortie)

    def test_cle_rangee_seule_l_empreinte_et_l_hote_s_affichent(self):
        ecran, sortie = self.cle_nouvelle(FORMES["intacte"][0])
        self.assertIsNone(sortie)
        self.assertIn("cle rangee dans %s (empreinte %s, hote sonde-ab12)" % (self.fichier_cle, EMPREINTE), ecran)
        self.assertIn("   (%s)" % MSG, ecran)
        self.assertIn(">> cle nouvelle <alea de 32 octets> %d" % IDENT, ecran)
        self.assertEqual(stat.S_IMODE(os.stat(self.fichier_cle).st_mode), 0o600)

    def test_la_commande_envoyee_porte_l_alea_et_l_id(self):
        self.cle_nouvelle(FORMES["intacte"][0])
        self.assertEqual(self.commande_envoyee, ("cle nouvelle %s %d\n" % (ALEA.hex().upper(), IDENT)).encode())

    def test_hote_mal_forme_non_affiche(self):
        for hote in (CLE_HEXA, "a b", "x" * 64, "", None, 12):
            with self.subTest(hote=hote):
                ecran, sortie = self.cle_nouvelle(RS + json_cle(hote=hote) + b"\n")
                self.assertIsNone(sortie)
                self.assertIn("hote None)", ecran)
                self.assertSansMorceauDeCle(ecran)

    def test_msg_mal_forme_non_affiche(self):
        for msg in (CLE_HEXA, "MAJUSCULES", "x" * 65, "", None, ["a"]):
            with self.subTest(msg=msg):
                ecran, sortie = self.cle_nouvelle(RS + json_cle(msg=msg) + b"\n")
                self.assertIsNone(sortie)
                self.assertEqual(ecran.count("\n"), 2, "l'invitation et la ligne de la cle rangee, rien d'autre")
                self.assertSansMorceauDeCle(ecran)

    def test_empreinte_fausse_ou_absente_cle_non_rangee(self):
        variantes = ["00000000", None, ""]
        if EMPREINTE.lower() != EMPREINTE:
            variantes.append(EMPREINTE.lower())  # l'empreinte se compare en majuscules
        for empreinte in variantes:
            with self.subTest(empreinte=empreinte):
                _, sortie = self.cle_nouvelle(RS + json_cle(empreinte=empreinte) + b"\n")
                self.assertIn("reponse incoherente", sortie)
                self.assertFalse(os.path.exists(self.fichier_cle))

    def test_cle_de_mauvaise_longueur_ou_absente_non_rangee(self):
        for cle in (CLE_HEXA[:62], CLE_HEXA + "00", "", None, 5):
            with self.subTest(cle=cle):
                _, sortie = self.cle_nouvelle(RS + json_cle(cle=cle) + b"\n")
                self.assertIn("reponse incoherente", sortie)
                self.assertFalse(os.path.exists(self.fichier_cle))

    def test_reponse_d_un_autre_id_ignoree(self):
        _, sortie = self.cle_nouvelle(RS + json_cle(ident=IDENT + 1) + b"\n")
        self.assertIn("aucune reponse en 5 s", sortie)
        self.assertFalse(os.path.exists(self.fichier_cle))

    def test_erreur_de_la_sonde_code_verifie(self):
        for erreur, attendu in (("crypto", "crypto"), ("ecriture", "ecriture"), ("occupee", "occupee"),
                                (CLE_HEXA, "?"), ("MAJ", "?"), ("a" * 33, "?"), (None, "?")):
            with self.subTest(erreur=erreur):
                ligne = json.dumps({"v": 1, "t": "erreur", "erreur": erreur}, separators=(",", ":")).encode()
                ecran, sortie = self.cle_nouvelle(RS + ligne + b"\n")
                self.assertEqual(sortie, "cle nouvelle refusee : %s (rien n'a change)" % attendu)
                self.assertSansMorceauDeCle(ecran + sortie)

    def test_sans_fichier_sonde_cle_l_outil_refuse_avant_tout_envoi(self):
        carte, poste = self.paire()
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("SONDE_CLE", None)
            with self.assertRaises(SystemExit) as e:
                s.cle_nouvelle_usb(poste.fileno(), s.Lecteur(poste.fileno(), self.capture))
        self.assertIn("SONDE_CLE=<fichier> obligatoire", str(e.exception))
        carte.setblocking(False)
        with self.assertRaises(BlockingIOError):
            carte.recv(1)  # rien n'est parti vers la carte


# ---------------------------------------------------------------------------
#  Decodage du TLV 7 (Network Data)
# ---------------------------------------------------------------------------


def tlv_7_de_la_capture():
    """Le TLV 7 de la reponse 206 de la capture anonymisee (routeur 5000, Network Data). Cinq tests de DecodageTlv7
    en dependent, avec ENTREES_CAPTURE : une capture remplacee ou renumerotee demande de les revoir."""
    with open(CAPTURE_ANONYME, encoding="utf-8") as f:
        for ligne in f:
            m = json.loads(ligne)
            if m.get("id") == 206 and m.get("tlv"):
                return m["tlv"]
    raise AssertionError("reponse 206 absente de la capture anonymisee")


ENTREES_CAPTURE = [
    "service 01 : serveurs B400",
    "prefixe fc00::/7 : route par B400 CC00 0400 AC00 E400",
    "prefixe fd00:5555:6666:ffff::/96 : route par B400",
    "prefixe fd00:5555:6666::/64 : routeurs de bordure B400",
    "service 5cc5 : serveurs B400 CC00 0400 AC00 E400",
    "service 5d : serveurs B400",
]


def tlv(t, valeur):
    return bytes([t, len(valeur)]) + valeur


class DecodageTlv7(unittest.TestCase):
    def test_network_data_de_la_capture(self):
        octets = bytes.fromhex(tlv_7_de_la_capture())
        self.assertEqual(octets[0], 7)
        self.assertEqual(s.network_data(octets[2:2 + octets[1]]), ENTREES_CAPTURE)

    def test_decoder_a_une_branche_tlv_7_une_ligne_par_entree(self):
        self.assertEqual(s.decoder(tlv_7_de_la_capture()), ["NetworkData: " + e for e in ENTREES_CAPTURE])

    def test_decoder_continue_apres_le_tlv_7(self):
        nd = bytes.fromhex(tlv_7_de_la_capture())[2:]
        charge = tlv(1, b"\x50\x00") + tlv(7, nd) + tlv(24, b"\x04")
        self.assertEqual(s.decoder(charge.hex()),
                         ["Address16: 5000"] + ["NetworkData: " + e for e in ENTREES_CAPTURE] + ["Version: 4"])

    def test_afficher_un_diag_avec_network_data(self):
        """Ce que l'operateur lit : l'en-tete du diag, puis une ligne par prefixe ou service."""
        m = {"v": 1, "t": "diag", "id": 206, "cible": "5000", "ms": 2947, "ok": True, "code": "2.04",
             "tlv": tlv_7_de_la_capture()}
        ecran = io.StringIO()
        with contextlib.redirect_stdout(ecran):
            s.afficher(m)
        self.assertEqual(ecran.getvalue().splitlines(),
                         ["<< diag 5000 : 2947 ms, code 2.04, 142 octets"]
                         + ["      NetworkData: " + e for e in ENTREES_CAPTURE])

    def test_tlv_7_sans_entree_lisible_reste_en_hexa(self):
        self.assertEqual(s.network_data(b""), [])
        self.assertEqual(s.decoder("07020102"), ["NetworkData: 0102"])

    def test_prefixe_de_plus_de_128_bits_ne_plante_pas(self):
        """TLV abime : 255 bits annonces, 32 octets de prefixe, un routeur de bordure."""
        prefixe = bytes([0xFD, 0x00]) + bytes(30)
        nd = tlv(0x03, bytes([0, 255]) + prefixe + tlv(0x05, b"\x50\x00\x01\x00"))
        self.assertEqual(s.network_data(nd), ["prefixe fd00::/255 : routeurs de bordure 5000"])
        self.assertEqual(s.decoder(tlv(7, nd).hex()), ["NetworkData: prefixe fd00::/255 : routeurs de bordure 5000"])

    def test_charge_tronquee_ne_plante_pas(self):
        nd = bytes.fromhex(tlv_7_de_la_capture())[2:]
        for n in range(len(nd)):
            with self.subTest(coupe=n):
                s.network_data(nd[:n])


class AnnoncesEtResolution(unittest.TestCase):
    """Firmware 1.1.0 : annonces (une ligne par routeur entendu, "suite" sauf sur la derniere) et resoudre (une
    reponse par id, apres 15 s au plus). Valeurs inventees."""

    ANNONCE = {"v": 1, "t": "annonces", "rloc16": "5000", "ext": "E000000000000A01", "partition": "1234ABCD",
               "route64": "7A" + "4000080000100000" + "F10092", "seq": 122, "rssi": -61, "rssi_min": -70,
               "rssi_max": -55, "nb": 12, "age_s": 7, "suite": True}

    def test_attente_d_une_resolution_par_son_id(self):
        self.assertEqual(s.attente("resoudre fd00::1 17"), ("resoudre", 17))
        self.assertEqual(s.attente("annonces"), ("annonces", None))
        self.assertEqual(s.delai_reponse("resoudre fd00::1 17"), 20)
        self.assertEqual(s.delai_reponse("annonces"), 6)

    def test_fin_d_une_reponse(self):
        self.assertFalse(s.fin_de_reponse(self.ANNONCE, "annonces", None), "suite : d'autres lignes viennent")
        self.assertTrue(s.fin_de_reponse(dict(self.ANNONCE, suite=False), "annonces", None))
        self.assertTrue(s.fin_de_reponse({"v": 1, "t": "annonces", "vide": True}, "annonces", None))
        r = {"v": 1, "t": "resoudre", "id": 17, "cible": "fd00::1", "ok": False, "erreur": "introuvable"}
        self.assertTrue(s.fin_de_reponse(r, "resoudre", 17))
        self.assertFalse(s.fin_de_reponse(dict(r, id=16), "resoudre", 17), "une autre resolution")

    def test_liens_d_une_route64(self):
        # Routeurs 1, 20 et 43 : 1 et 43 voisins (qualites sortante et entrante), 20 l'emetteur lui-meme.
        self.assertEqual(s.liens_route64(self.ANNONCE["route64"]), [(1, 3, 3), (43, 2, 1)])
        self.assertEqual(s.liens_route64("7A00"), [], "trop courte")

    def test_affichage(self):
        ecran = io.StringIO()
        with contextlib.redirect_stdout(ecran):
            s.afficher(self.ANNONCE)
            s.afficher({"v": 1, "t": "annonces", "vide": True})
            s.afficher({"v": 1, "t": "resoudre", "id": 17, "cible": "fd00::1", "ok": True, "ms": 340,
                        "rloc16": "AC00", "repondu": True, "mleid": "FD00111122220C87" + "0000000000000017"})
            s.afficher({"v": 1, "t": "resoudre", "id": 18, "cible": "fd00::2", "ok": True, "ms": 90,
                        "rloc16": "B000", "repondu": False, "mleid": None})
            s.afficher({"v": 1, "t": "resoudre", "id": 19, "cible": "fd00::3", "ok": True, "ms": 90,
                        "rloc16": "B400", "mleid": None})
        texte = ecran.getvalue()
        self.assertIn("5000 ext E000000000000A01 partition 1234ABCD rssi -61 (-70..-55) 12 msg il y a 7 s", texte)
        self.assertIn("liens : 0400 3/3, AC00 2/1", texte)
        self.assertIn("aucun routeur entendu", texte)
        self.assertIn("fd00::1 : AC00 (parent AC00), 340 ms, a repondu a l'echo, ML-EID fd00:1111:2222:c87::17", texte)
        self.assertIn("fd00::2 : B000 (parent B000), 90 ms, sans reponse d'echo, ML-EID inconnu", texte)
        self.assertIn("fd00::3 : B400 (parent B400), 90 ms, reponse d'echo inconnue, ML-EID inconnu", texte)

    def test_donnees_entieres(self):
        """Une Route64 et un ML-EID ont plus de 16 hexa : ce sont des donnees, jamais masquees."""
        for t in ("annonces", "resoudre"):
            self.assertIn(t, s.TYPES_DONNEES)
        self.assertEqual(s.sans_cle(self.ANNONCE), self.ANNONCE)


class Structure(unittest.TestCase):
    def test_le_bloc_main_est_la_derniere_instruction_du_module(self):
        """Lance comme un script, le module execute main() des que le bloc __main__ est lu : une fonction definie
        plus bas (network_data l'etait) n'existe pas encore quand main() l'appelle."""
        with open(os.path.join(SONDE, "sonde_essai.py"), encoding="utf-8") as f:
            corps = ast.parse(f.read()).body
        dernier = corps[-1]
        self.assertIsInstance(dernier, ast.If)
        self.assertIn("__main__", [c.value for c in ast.walk(dernier.test) if isinstance(c, ast.Constant)])
        self.assertIn("network_data", [n.name for n in corps if isinstance(n, ast.FunctionDef)])

    def test_decoder_appelle_network_data(self):
        with open(os.path.join(SONDE, "sonde_essai.py"), encoding="utf-8") as f:
            arbre = ast.parse(f.read())
        decoder = next(n for n in arbre.body if isinstance(n, ast.FunctionDef) and n.name == "decoder")
        appels = {c.func.id for c in ast.walk(decoder) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}
        self.assertIn("network_data", appels)


if __name__ == "__main__":
    unittest.main()
