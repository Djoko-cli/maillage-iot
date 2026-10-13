#!/usr/bin/env python3
"""Vecteurs de test de l'ecoute MLE de la sonde (sonde/src/mle.h), ecrits dans sonde/test/vecteurs_mle.h.

Des trames 802.15.4 inventees, qui portent des messages MLE chiffres comme les routeurs Thread les envoient : en-tete
MAC aux formats 2006 et 2015 (sequence supprimee, PAN selon le tableau 7-2, IE d'en-tete et de charge), 6LoWPAN IPHC
sans contexte (adresses en ligne ou tirees des adresses MAC, multicast compresse), UDP compresse ou non, en-tete de
securite MLE, AES-CCM a MIC de 4 octets. La cle reseau, les ExtMac, la partition et les routeurs sont inventes ; rien
ne vient d'un vrai reseau. Le calcul est independant du firmware : HMAC-SHA256 de la bibliotheque standard, AES-CCM de
la bibliotheque cryptography (presente dans le Python de PlatformIO, ~/.platformio/penv/bin/python).

  ~/.platformio/penv/bin/python sonde/test/vecteurs_mle.py             # ecrit sonde/test/vecteurs_mle.h
  ~/.platformio/penv/bin/python sonde/test/vecteurs_mle.py --verifier  # compare au fichier commite
"""
import hashlib
import hmac
import os
import struct
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESCCM

ICI = os.path.dirname(os.path.abspath(__file__))
SORTIE = os.path.join(ICI, 'vecteurs_mle.h')

CLE_RESEAU = bytes.fromhex('00112233445566778899AABBCCDDEEFF')
SEQUENCE = 5          # sequence courante de la pile, dans les tests ; la suivante (6) se dechiffre aussi
PAN = 0xFACE
PARTITION = 0x1234ABCD
PORT_MLE = 19788
PORT_TMF = 61631

EXT_A = bytes.fromhex('E000000000000A01')   # routeur 20 (5000)
EXT_B = bytes.fromhex('E000000000000B02')   # routeur 1 (0400)
EXT_C = bytes.fromhex('E000000000000C03')   # routeur 43 (AC00)
EXT_E = bytes.fromhex('E000000000000E05')   # un enfant (5004)
EXT_SONDE = bytes.fromhex('E00000000000F0F0')

IGNOREE, DECHIFFREE, ECHEC = 0, 1, 2
AUCUN, PAS_IPHC, CONTEXTE, PAS_UDP, TRONQUEE = 0, 1, 2, 3, 4


def cle_mle(sequence):
    """Les 128 premiers bits de HMAC-SHA256(cle reseau, sequence gros-boutiste || « Thread »)."""
    return hmac.new(CLE_RESEAU, struct.pack('>I', sequence) + b'Thread', hashlib.sha256).digest()[:16]


def fcs(octets):
    """FCS de 802.15.4 : CRC-16 de l'UIT-T, bits de poids faible d'abord, en petit-boutiste."""
    crc = 0
    for o in octets:
        crc ^= o
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return struct.pack('<H', crc)


def iid_ext(ext):
    """Identifiant d'interface d'une ExtMac : le bit U/L inverse."""
    return bytes([ext[0] ^ 0x02]) + ext[1:]


def iid_court(court):
    return bytes([0, 0, 0, 0xFF, 0xFE, 0, court >> 8, court & 0xFF])


def lien_local(iid):
    return bytes.fromhex('FE80000000000000') + iid


def multicast(texte):
    """ff02::1 etc., en 16 octets."""
    groupes = texte.split('::')
    tete = [int(x, 16) for x in groupes[0].split(':') if x]
    queue = [int(x, 16) for x in groupes[1].split(':') if x] if len(groupes) > 1 else []
    mots = tete + [0] * (8 - len(tete) - len(queue)) + queue
    return b''.join(struct.pack('>H', m) for m in mots)


def mac(version, dst, src, compression, sequence=0x42, supprimer_sequence=False, ies=b'', ie_present=False,
        securite=False):
    """En-tete MAC d'une trame de donnees. dst, src : (mode, adresse dans l'ordre naturel) ; mode 0, 2 ou 3."""
    mode_dst, a_dst = dst
    mode_src, a_src = src
    fcf = 0x0001 | (0x0008 if securite else 0) | (0x0040 if compression else 0)
    fcf |= (0x0100 if supprimer_sequence else 0) | (0x0200 if ie_present else 0)
    fcf |= mode_dst << 10 | version << 12 | mode_src << 14
    if version < 2:
        pan_dst, pan_src = mode_dst != 0, mode_src != 0 and not compression
    else:
        # 802.15.4-2015, tableau 7-2.
        if not mode_dst and not mode_src:
            pan_dst, pan_src = compression, False
        elif mode_dst and not mode_src:
            pan_dst, pan_src = not compression, False
        elif not mode_dst:
            pan_dst, pan_src = False, not compression
        elif mode_dst == 3 and mode_src == 3:
            pan_dst, pan_src = not compression, False
        else:
            pan_dst, pan_src = True, not compression
    h = struct.pack('<H', fcf)
    if not supprimer_sequence:
        h += bytes([sequence])
    if pan_dst:
        h += struct.pack('<H', PAN)
    h += a_dst[::-1]
    if pan_src:
        h += struct.pack('<H', PAN)
    h += a_src[::-1]
    return h + ies


def ie_entete(identifiant, valeur):
    return struct.pack('<H', len(valeur) | identifiant << 7) + valeur


def ie_charge(groupe, valeur):
    return struct.pack('<H', len(valeur) | groupe << 11 | 0x8000) + valeur


def somme_udp(src, dst, port_src, port_dst, charge):
    longueur = 8 + len(charge)
    donnees = src + dst + struct.pack('>IxxxB', longueur, 17) + struct.pack('>HHHH', port_src, port_dst, longueur, 0)
    donnees += charge + (b'\0' if len(charge) % 2 else b'')
    s = sum(struct.unpack('>%dH' % (len(donnees) // 2), donnees))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s & 0xFFFF) or 0xFFFF


def iphc(src, dst, sam, m, dam, src_en_ligne, dst_en_ligne, tf=3, nh=True, hlim=3):
    """IPHC sans contexte ; les champs en ligne, dans l'ordre : TF, en-tete suivant, limite, source, destination."""
    a = 0x60 | tf << 3 | (0x04 if nh else 0) | hlim
    b = sam << 4 | (0x08 if m else 0) | dam
    tfs = {0: b'\x00\x0A\xBC\xDE', 1: b'\x0A\xBC\xDE', 2: b'\x00', 3: b''}
    h = bytes([a, b]) + tfs[tf]
    if not nh:
        h += bytes([17])
    if hlim == 0:
        h += bytes([255])
    return h + src_en_ligne + dst_en_ligne


def udp(src, dst, port_src, port_dst, charge, nhc=True, ports=0, somme=True):
    if not nhc:
        return struct.pack('>HHHH', port_src, port_dst, 8 + len(charge), somme_udp(src, dst, port_src, port_dst, charge))
    u = 0xF0 | (0 if somme else 0x04) | ports
    if ports == 0:
        p = struct.pack('>HH', port_src, port_dst)
    elif ports == 1:
        p = struct.pack('>HB', port_src, port_dst & 0xFF)
    elif ports == 2:
        p = struct.pack('>BH', port_src & 0xFF, port_dst)
    else:
        p = bytes([(port_src & 0x0F) << 4 | (port_dst & 0x0F)])
    return bytes([u]) + p + (struct.pack('>H', somme_udp(src, dst, port_src, port_dst, charge)) if somme else b'')


def mle_chiffre(src, dst, compteur, sequence, clair):
    """Suite 0, en-tete de securite (controle 0x15, compteur, source et index de cle), puis AES-CCM et le MIC."""
    entete = bytes([0x15]) + struct.pack('<I', compteur) + struct.pack('>I', sequence) + bytes([(sequence & 0x7F) + 1])
    ext = iid_ext(src[8:])  # l'ExtMac de l'identifiant d'interface, bit U/L inverse
    nonce = ext + struct.pack('>I', compteur) + bytes([5])
    chiffre = AESCCM(cle_mle(sequence), tag_length=4).encrypt(nonce, clair, src + dst + entete)
    return bytes([0]) + entete + chiffre


def tlv(t, v):
    return bytes([t, len(v)]) + v


def route64(sequence, routes):
    """routes : {identifiant : (sortante, entrante, cout)}."""
    masque = 0
    for r in routes:
        masque |= 1 << (63 - r)
    octets = bytes([(s << 6) | (e << 4) | c for _, (s, e, c) in sorted(routes.items())])
    return bytes([sequence]) + struct.pack('>Q', masque) + octets


def chef(partition=PARTITION, chef_id=20):
    return struct.pack('>IBBBB', partition, 64, 0x11, 0x22, chef_id)


R64_A = route64(0x7A, {1: (3, 3, 1), 20: (0, 0, 0), 43: (2, 1, 2)})
R64_B = route64(0x7A, {1: (0, 0, 0), 20: (3, 3, 1), 43: (1, 1, 3)})
R64_C = route64(0x7B, {1: (1, 1, 3), 20: (1, 2, 2), 43: (0, 0, 0)})
R64_MAX = route64(0x10, {i: (i % 4, (i + 1) % 4, i % 16) for i in range(63)})


def annonce(source, r64=None, partition=PARTITION, commande=4):
    """Commande, Source Address, Leader Data (sans elle si partition est None), Route64."""
    clair = bytes([commande]) + tlv(0, struct.pack('>H', source))
    if partition is not None:
        clair += tlv(11, chef(partition))
    if r64 is not None:
        clair += tlv(9, r64)
    return clair


class Trame:
    def __init__(self, nom, psdu, issue, version=1, mode_dst=0, mode_src=0, charge=0, refus=AUCUN, src=b'',
                 dst=b'', port_src=0, port_dst=0, mac_lue=True, message=None, ext=b''):
        self.nom, self.psdu, self.issue = nom, psdu, issue
        self.version, self.mode_dst, self.mode_src, self.charge = version, mode_dst, mode_src, charge
        self.refus, self.src, self.dst, self.port_src, self.port_dst = refus, src, dst, port_src, port_dst
        self.mac_lue, self.message, self.ext = mac_lue, message, ext


def trame(nom, h_mac, h_ip, src, dst, port_src, port_dst, charge_udp, issue, version, mode_dst, mode_src,
          udp_args=None, message=None, refus=AUCUN):
    corps = h_mac + h_ip + udp(src, dst, port_src, port_dst, charge_udp, **(udp_args or {})) + charge_udp
    psdu = corps + fcs(corps)
    assert len(psdu) <= 127, nom
    return Trame(nom, psdu, issue, version=version, mode_dst=mode_dst, mode_src=mode_src, charge=len(h_mac),
                 refus=refus, src=src, dst=dst, port_src=port_src, port_dst=port_dst, message=message,
                 ext=iid_ext(src[8:]) if message is not None else b'')


def trames():
    t = []
    ff02_1, ff02_2 = multicast('ff02::1'), multicast('ff02::2')
    court = (2, b'\xff\xff')

    # 1. Annonce de 2006 : diffusion, source longue, PAN compresse ; IPHC tout tire du MAC ; UDP compresse.
    src = lien_local(iid_ext(EXT_A))
    h = mac(1, court, (3, EXT_A), True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0x5000, R64_A)
    t.append(trame('annonce 2006', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x107, SEQUENCE, c), DECHIFFREE, 1, 2, 3,
                   message=(4, 0x5000, PARTITION, R64_A)))
    base = t[-1]

    # 2. 2015 : sequence supprimee, deux adresses longues et PAN compresse (aucun PAN), IE d'en-tete puis HT2 ;
    #    destination lien-local tiree du MAC ; UDP sans somme.
    src = lien_local(iid_ext(EXT_C))
    dst = lien_local(iid_ext(EXT_SONDE))
    ies = ie_entete(0x1A, b'\x10\x00\x20\x00') + ie_entete(0x7F, b'')
    h = mac(2, (3, EXT_SONDE), (3, EXT_C), True, supprimer_sequence=True, ies=ies, ie_present=True)
    ip = iphc(src, dst, 3, False, 3, b'', b'')
    c = annonce(0xAC00, R64_C, commande=1)
    t.append(trame('accept 2015, sans sequence ni PAN', h, ip, src, dst, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, dst, 0x2201, SEQUENCE, c), DECHIFFREE, 2, 3, 3, udp_args={'somme': False},
                   message=(1, 0xAC00, PARTITION, R64_C)))

    # 3. 2015 : destination courte, source longue, PAN compresse (PAN de la destination seulement) ; IE d'en-tete,
    #    HT1, puis des IE de charge jusqu'a leur fin.
    src = lien_local(iid_ext(EXT_B))
    ies = ie_entete(0x1A, b'\x01\x02\x03\x04') + ie_entete(0x7E, b'') + ie_charge(0x1, b'\xAA\xBB') + ie_charge(0xF, b'')
    h = mac(2, court, (3, EXT_B), True, ies=ies, ie_present=True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0x0400, R64_B)
    t.append(trame('annonce 2015, IE de charge', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x3301, SEQUENCE, c), DECHIFFREE, 2, 2, 3,
                   message=(4, 0x0400, PARTITION, R64_B)))

    # 4. 2006 sans compression de PAN (deux PAN) ; IPHC tout en ligne : TF de 4 octets, en-tete suivant, limite,
    #    adresses de 128 bits ; UDP non compresse.
    src = lien_local(iid_ext(EXT_B))
    dst = lien_local(iid_ext(EXT_SONDE))
    h = mac(1, (3, EXT_SONDE), (3, EXT_B), False)
    ip = iphc(src, dst, 0, False, 0, src, dst, tf=0, nh=False, hlim=0)
    c = annonce(0x0400, R64_B)
    t.append(trame('2006, tout en ligne', h, ip, src, dst, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, dst, 0x4401, SEQUENCE, c), DECHIFFREE, 1, 3, 3, udp_args={'nhc': False},
                   message=(4, 0x0400, PARTITION, R64_B)))

    # 5. Source en 16 bits en ligne (fe80::ff:fe00:0400), multicast sur 32 bits (ff02::2) ; TF de 3 octets.
    src = lien_local(iid_court(0x0400))
    h = mac(1, court, (2, b'\x04\x00'), True)
    ip = iphc(src, ff02_2, 2, True, 2, b'\x04\x00', b'\x02\x00\x00\x02', tf=1)
    c = annonce(0x0400, R64_B)
    t.append(trame('source 16 bits, multicast 32 bits', h, ip, src, ff02_2, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_2, 0x5501, SEQUENCE, c), DECHIFFREE, 1, 2, 2,
                   message=(4, 0x0400, PARTITION, R64_B)))

    # 6. Source tiree de l'adresse MAC courte, multicast sur 48 bits (ff02::1) ; TF d'un octet.
    src = lien_local(iid_court(0x5000))
    h = mac(1, court, (2, b'\x50\x00'), True)
    ip = iphc(src, ff02_1, 3, True, 1, b'', b'\x02\x00\x00\x00\x00\x01', tf=2)
    c = annonce(0x5000, R64_A)
    t.append(trame('source MAC courte, multicast 48 bits', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x6601, SEQUENCE, c), DECHIFFREE, 1, 2, 2,
                   message=(4, 0x5000, PARTITION, R64_A)))

    # 7. Source en 64 bits en ligne, multicast de 128 bits en ligne.
    src = lien_local(iid_ext(EXT_A))
    h = mac(1, court, (3, EXT_A), True)
    ip = iphc(src, ff02_1, 1, True, 0, iid_ext(EXT_A), ff02_1)
    c = annonce(0x5000, R64_A)
    t.append(trame('source 64 bits, multicast en ligne', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x7701, SEQUENCE, c), DECHIFFREE, 1, 2, 3,
                   message=(4, 0x5000, PARTITION, R64_A)))

    # 7 bis. Route64 pleine (63 routeurs, 72 octets), sans Leader Data : tout le reste au plus court.
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0x5000, R64_MAX, partition=None)
    t.append(trame('Route64 pleine, sans Leader Data', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x7702, SEQUENCE, c), DECHIFFREE, 1, 2, 3, udp_args={'somme': False},
                   message=(4, 0x5000, None, R64_MAX)))

    # 8. La sequence suivante (rotation de cle) : dechiffree aussi.
    src = lien_local(iid_ext(EXT_A))
    h = mac(1, court, (3, EXT_A), True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0x5000, R64_A)
    t.append(trame('sequence suivante', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x8801, SEQUENCE + 1, c), DECHIFFREE, 1, 2, 3,
                   message=(4, 0x5000, PARTITION, R64_A)))

    # 9. Un enfant (5004) : dechiffre, sans place dans la table des routeurs ; sans Route64.
    src = lien_local(iid_ext(EXT_E))
    h = mac(1, court, (3, EXT_E), True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0x5004, None, commande=13)
    t.append(trame('enfant', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0x9901, SEQUENCE, c), DECHIFFREE, 1, 2, 3,
                   message=(13, 0x5004, PARTITION, b'')))

    # 10. Une autre partition (Leader Data) : dechiffree, la partition lue.
    src = lien_local(iid_ext(EXT_C))
    h = mac(1, court, (3, EXT_C), True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    c = annonce(0xAC00, R64_C, partition=0x0BADCAFE)
    t.append(trame('autre partition', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0xAA01, SEQUENCE, c), DECHIFFREE, 1, 2, 3,
                   message=(4, 0xAC00, 0x0BADCAFE, R64_C)))

    # 11. MIC faux : la trame 1, dernier octet du MIC change (le FCS refait).
    corps = bytearray(base.psdu[:-2])
    corps[-1] ^= 0x01
    t.append(Trame('MIC faux', bytes(corps) + fcs(corps), ECHEC, version=1, mode_dst=2, mode_src=3, charge=base.charge,
                   src=base.src, dst=base.dst, port_src=PORT_MLE, port_dst=PORT_MLE))

    # 12. Sequence de cle inconnue (ni la courante ni la suivante).
    src = lien_local(iid_ext(EXT_A))
    h = mac(1, court, (3, EXT_A), True)
    ip = iphc(src, ff02_1, 3, True, 3, b'', b'\x01')
    t.append(trame('sequence inconnue', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   mle_chiffre(src, ff02_1, 0xBB01, SEQUENCE + 4, annonce(0x5000, R64_A)), ECHEC, 1, 2, 3))

    # 13. MLE sans securite (suite 255, Discovery Request) : ignoree.
    t.append(trame('MLE sans securite', h, ip, src, ff02_1, PORT_MLE, PORT_MLE,
                   bytes([255, 16]) + tlv(26, b'\x80\x00'), IGNOREE, 1, 2, 3))

    # 14. Un autre port (TMF, 61631), ports compresses sur 4 bits : ignoree.
    t.append(trame('TMF, ports sur 4 bits', h, ip, src, ff02_1, PORT_TMF, PORT_TMF, b'\x50\x02\xAB\xCD',
                   IGNOREE, 1, 2, 3, udp_args={'ports': 3}))

    # 15. Ports compresses : destination sur 8 bits (0xF0BF), puis source sur 8 bits.
    t.append(trame('port de destination sur 8 bits', h, ip, src, ff02_1, PORT_MLE, PORT_TMF, b'\x01\x02',
                   IGNOREE, 1, 2, 3, udp_args={'ports': 1}))
    t.append(trame('port de source sur 8 bits', h, ip, src, ff02_1, PORT_TMF, PORT_MLE, b'\x01\x02',
                   ECHEC, 1, 2, 3, udp_args={'ports': 2}))

    # 16. Securite MAC : la trame n'est pas lue.
    corps = mac(1, court, (3, EXT_A), True, securite=True) + b'\x00' * 20
    t.append(Trame('securite MAC', corps + fcs(corps), IGNOREE, mac_lue=False))

    # 17. Un fragment 6LoWPAN (dispatch 11000) : pas d'IPHC.
    corps = mac(1, court, (3, EXT_A), True) + b'\xC0\x50\x12\x34' + b'\x00' * 8
    t.append(Trame('fragment', corps + fcs(corps), IGNOREE, version=1, mode_dst=2, mode_src=3,
                   charge=len(mac(1, court, (3, EXT_A), True)), refus=PAS_IPHC))

    # 18. IPHC avec contexte (SAC a 1) : pas une adresse lien-local.
    corps = mac(1, court, (3, EXT_A), True) + bytes([0x7B, 0x7B]) + b'\x00' * 8
    t.append(Trame('contexte', corps + fcs(corps), IGNOREE, version=1, mode_dst=2, mode_src=3,
                   charge=len(mac(1, court, (3, EXT_A), True)), refus=CONTEXTE))

    # 19. En-tete suivant autre qu'UDP (ICMPv6, 58) en ligne.
    corps = mac(1, court, (3, EXT_A), True) + bytes([0x78, 0x3B, 58]) + b'\x80\x00\x12\x34'
    t.append(Trame('ICMPv6', corps + fcs(corps), IGNOREE, version=1, mode_dst=2, mode_src=3,
                   charge=len(mac(1, court, (3, EXT_A), True)), refus=PAS_UDP))

    # 20. Une trame d'acquittement (type 2) : pas une trame de donnees.
    corps = bytes([0x02, 0x10, 0x42])
    t.append(Trame('acquittement', corps + fcs(corps), IGNOREE, mac_lue=False))
    return t


# --- ecriture du fichier C -------------------------------------------------------------------------------------

def octets_c(o, retrait='    '):
    lignes = []
    for i in range(0, len(o), 16):
        lignes.append(retrait + ', '.join('0x%02X' % x for x in o[i:i + 16]) + ',')
    return '\n'.join(lignes) if lignes else retrait


def generer():
    lignes = [
        '// Vecteurs de test de l\'ecoute MLE (sonde/src/mle.h), generes par sonde/test/vecteurs_mle.py : ne pas',
        '// modifier a la main. Cle reseau, ExtMac, partition et routeurs inventes.',
        '//   ~/.platformio/penv/bin/python sonde/test/vecteurs_mle.py',
        '#pragma once',
        '#include <stddef.h>',
        '#include <stdint.h>',
        '',
        'static const uint8_t kCleReseau[16] = {',
        octets_c(CLE_RESEAU),
        '};',
        'static const uint32_t kSequence = %d;' % SEQUENCE,
        '',
        '// Cle MLE de quelques sequences : HMAC-SHA256(cle reseau, sequence || "Thread"), 16 premiers octets.',
        'struct VecteurDerivation {',
        '  uint32_t sequence;',
        '  uint8_t cle[16];',
        '};',
        'static const VecteurDerivation kDerivations[] = {',
    ]
    for s in (0, SEQUENCE, SEQUENCE + 1, 0xFFFFFFFF):
        lignes.append('    {0x%08XU, {%s}},' % (s, ', '.join('0x%02X' % x for x in cle_mle(s))))
    lignes.append('};')
    lignes.append('')
    # Un vecteur AES-CCM seul, pour la crypto des tests : la charge MLE de la trame 1.
    cle = cle_mle(SEQUENCE)
    nonce = iid_ext(iid_ext(EXT_A)) + struct.pack('>I', 0x107) + bytes([5])
    aad = bytes(range(42))
    clair = annonce(0x5000, R64_A)
    chiffre = AESCCM(cle, tag_length=4).encrypt(nonce, clair, aad)
    lignes += [
        '// AES-128-CCM, MIC de 4 octets : un vecteur seul (la crypto des tests).',
        'static const uint8_t kCcmCle[16] = {', octets_c(cle), '};',
        'static const uint8_t kCcmNonce[13] = {', octets_c(nonce), '};',
        'static const uint8_t kCcmAad[42] = {', octets_c(aad), '};',
        'static const uint8_t kCcmClair[%d] = {' % len(clair), octets_c(clair), '};',
        'static const uint8_t kCcmChiffre[%d] = {' % len(chiffre[:-4]), octets_c(chiffre[:-4]), '};',
        'static const uint8_t kCcmMic[4] = {', octets_c(chiffre[-4:]), '};',
        '',
    ]
    liste = trames()
    for k, t in enumerate(liste):
        lignes += ['// %d. %s' % (k + 1, t.nom), 'static const uint8_t kTrame%d[%d] = {' % (k + 1, len(t.psdu)),
                   octets_c(t.psdu), '};']
        if t.message is not None and t.message[3]:
            lignes += ['static const uint8_t kRoute%d[%d] = {' % (k + 1, len(t.message[3])), octets_c(t.message[3]),
                       '};']
    lignes += [
        '',
        '// Issue attendue de decoder() : 0 ignoree, 1 dechiffree, 2 echec. Refus attendu de lireDatagramme() : 0 aucun,',
        '// 1 pas IPHC, 2 contexte, 3 pas UDP, 4 tronquee.',
        'struct VecteurTrame {',
        '  const char *nom;',
        '  const uint8_t *psdu;',
        '  size_t n;',
        '  int issue;',
        '  bool macLue;',
        '  uint8_t version, modeDst, modeSrc;',
        '  size_t charge;',
        '  int refus;',
        '  uint8_t src[16], dst[16];',
        '  uint16_t portSrc, portDst;',
        '  uint8_t ext[8];',
        '  uint8_t commande;',
        '  uint16_t rloc16;',
        '  bool aPartition;',
        '  uint32_t partition;',
        '  const uint8_t *route64;',
        '  size_t nRoute64;',
        '};',
        'static const VecteurTrame kTrames[] = {',
    ]

    def tableau(o, n):
        o = o or bytes(n)
        return '{%s}' % ', '.join('0x%02X' % x for x in o)

    for k, t in enumerate(liste):
        m = t.message
        route = ('kRoute%d, %d' % (k + 1, len(m[3]))) if m is not None and m[3] else 'nullptr, 0'
        lignes.append('    {"%s", kTrame%d, %d, %d, %s, %d, %d, %d, %d, %d,' % (
            t.nom, k + 1, len(t.psdu), t.issue, 'true' if t.mac_lue else 'false', t.version, t.mode_dst, t.mode_src,
            t.charge, t.refus))
        lignes.append('     %s,' % tableau(t.src, 16))
        lignes.append('     %s,' % tableau(t.dst, 16))
        partition = m[2] if m is not None else None
        lignes.append('     %d, %d, %s, %d, 0x%04X, %s, 0x%08XU, %s},' % (
            t.port_src, t.port_dst, tableau(t.ext, 8), m[0] if m else 0, m[1] if m else 0,
            'true' if partition is not None else 'false', partition or 0, route))
    lignes.append('};')
    return '\n'.join(lignes) + '\n'


def main():
    texte = generer()
    if '--verifier' in sys.argv[1:]:
        with open(SORTIE, encoding='utf-8') as f:
            if f.read() != texte:
                print('vecteurs_mle.h differe de ce que le script produit')
                return 1
        print('vecteurs_mle.h : conforme au script')
        return 0
    with open(SORTIE, 'w', encoding='utf-8') as f:
        f.write(texte)
    print('ecrit : %s (%d trames)' % (os.path.relpath(SORTIE), len(trames())))
    return 0


if __name__ == '__main__':
    sys.exit(main())
