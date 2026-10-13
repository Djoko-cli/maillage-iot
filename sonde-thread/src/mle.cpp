#include "mle.h"

#include <string.h>

namespace mle {

void effacer(void *p, size_t n) {
  volatile uint8_t *v = static_cast<volatile uint8_t *>(p);
  while (n--) *v++ = 0;
}

// ===========================================================================
//  802.15.4
// ===========================================================================

namespace {

constexpr uint8_t kTypeDonnees = 1;
constexpr uint8_t kVersion2015 = 2;
constexpr uint8_t kModeCourte = 2, kModeLongue = 3;
constexpr uint8_t kHt1 = 0x7E, kHt2 = 0x7F;   // fin des IE d'en-tete : IE de charge ensuite, ou la charge
constexpr uint8_t kFinIeCharge = 0x0F;         // groupe qui termine les IE de charge

size_t longueurAdresse(uint8_t mode) { return mode == kModeLongue ? 8 : mode == kModeCourte ? 2 : 0; }

}  // namespace

bool lireMac(const uint8_t *p, size_t n, EnTeteMac *m) {
  // Controle (2), sequence (1), au moins une adresse courte, FCS (2).
  if (n < 2 + 2 || n > kPsduMax) return false;
  *m = EnTeteMac();
  m->fin = n - 2;
  const uint16_t fcf = (uint16_t)(p[0] | p[1] << 8);
  if ((fcf & 0x07) != kTypeDonnees || (fcf & 0x08)) return false;  // donnees, sans securite MAC
  m->version = (uint8_t)((fcf >> 12) & 3);
  m->modeDst = (uint8_t)((fcf >> 10) & 3);
  m->modeSrc = (uint8_t)((fcf >> 14) & 3);
  if (m->version > kVersion2015 || m->modeDst == 1 || m->modeSrc == 1) return false;
  const bool v2015 = m->version == kVersion2015;
  const bool compression = fcf & 0x40;
  size_t i = 2;
  if (!(v2015 && (fcf & 0x0100))) i++;  // numero de sequence, sauf supprime (2015)
  const bool dst = m->modeDst != 0, src = m->modeSrc != 0;
  bool panDst, panSrc;
  if (!v2015) {
    // 2003 et 2006 : PAN de la destination, et celui de la source sans compression.
    panDst = dst;
    panSrc = src && !compression;
  } else if (!dst && !src) {
    // 2015, tableau 7-2.
    panDst = compression;
    panSrc = false;
  } else if (dst && !src) {
    panDst = !compression;
    panSrc = false;
  } else if (!dst) {
    panDst = false;
    panSrc = !compression;
  } else if (m->modeDst == kModeLongue && m->modeSrc == kModeLongue) {
    panDst = !compression;
    panSrc = false;
  } else {
    panDst = true;
    panSrc = !compression;
  }
  const size_t lDst = longueurAdresse(m->modeDst), lSrc = longueurAdresse(m->modeSrc);
  const size_t entete = (panDst ? 2 : 0) + lDst + (panSrc ? 2 : 0) + lSrc;
  if (i + entete > m->fin) return false;
  if (panDst) i += 2;
  memcpy(m->dst, p + i, lDst);
  i += lDst;
  if (panSrc) i += 2;
  memcpy(m->src, p + i, lSrc);
  i += lSrc;
  if (v2015 && (fcf & 0x0200)) {
    // IE d'en-tete : longueur (7 bits), identifiant (8 bits), type 0.
    bool fini = false;
    bool charges = false;
    while (!fini) {
      if (i + 2 > m->fin) return false;
      const uint16_t d = (uint16_t)(p[i] | p[i + 1] << 8);
      if (d & 0x8000) return false;
      const size_t l = d & 0x7F;
      const uint8_t id = (uint8_t)((d >> 7) & 0xFF);
      i += 2;
      if (i + l > m->fin) return false;
      i += l;
      if (id == kHt1) charges = fini = true;
      if (id == kHt2) fini = true;
    }
    // IE de charge (apres HT1) : longueur (11 bits), groupe (4 bits), type 1 ; jusqu'au groupe 0x0F.
    while (charges) {
      if (i + 2 > m->fin) return false;
      const uint16_t d = (uint16_t)(p[i] | p[i + 1] << 8);
      if (!(d & 0x8000)) return false;
      const size_t l = d & 0x07FF;
      const uint8_t groupe = (uint8_t)((d >> 11) & 0x0F);
      i += 2;
      if (i + l > m->fin) return false;
      i += l;
      if (groupe == kFinIeCharge) charges = false;
    }
  }
  m->charge = i;
  return true;
}

// ===========================================================================
//  IPHC et UDP
// ===========================================================================

namespace {

// Identifiant d'interface tire d'une adresse MAC (dans l'ordre de la trame) :
// longue, l'adresse dans l'ordre naturel, bit U/L inverse ; courte,
// 0000:00ff:fe00:XXXX.
bool iidDepuisMac(const uint8_t *mac, uint8_t mode, uint8_t iid[8]) {
  if (mode == kModeLongue) {
    for (int k = 0; k < 8; k++) iid[k] = mac[7 - k];
    iid[0] ^= 0x02;
    return true;
  }
  if (mode == kModeCourte) {
    memset(iid, 0, 8);
    iid[3] = 0xFF;
    iid[4] = 0xFE;
    iid[6] = mac[1];
    iid[7] = mac[0];
    return true;
  }
  return false;
}

// Adresse unicast sans contexte (SAC ou DAC a 0) : fe80::/64 et l'identifiant,
// en ligne (128, 64 ou 16 bits) ou tire de l'adresse MAC.
bool unicast(const uint8_t *p, size_t fin, size_t *i, uint8_t mode, const uint8_t *mac, uint8_t modeMac,
             uint8_t adresse[16]) {
  static const size_t kLongueurs[] = {16, 8, 2, 0};
  if (*i + kLongueurs[mode] > fin) return false;
  memset(adresse, 0, 16);
  adresse[0] = 0xFE;
  adresse[1] = 0x80;
  switch (mode) {
    case 0: memcpy(adresse, p + *i, 16); break;
    case 1: memcpy(adresse + 8, p + *i, 8); break;
    case 2:
      adresse[11] = 0xFF;
      adresse[12] = 0xFE;
      adresse[14] = p[*i];
      adresse[15] = p[*i + 1];
      break;
    default:
      if (!iidDepuisMac(mac, modeMac, adresse + 8)) return false;
      break;
  }
  *i += kLongueurs[mode];
  return true;
}

// Destination multicast sans contexte (M a 1, DAC a 0) : 128 bits, ffXX::00XX:XXXX:XXXX,
// ffXX::00XX:XXXX ou ff02::00XX.
bool multicast(const uint8_t *p, size_t fin, size_t *i, uint8_t mode, uint8_t adresse[16]) {
  static const size_t kLongueurs[] = {16, 6, 4, 1};
  if (*i + kLongueurs[mode] > fin) return false;
  memset(adresse, 0, 16);
  const uint8_t *e = p + *i;
  switch (mode) {
    case 0: memcpy(adresse, e, 16); break;
    case 1:
      adresse[0] = 0xFF;
      adresse[1] = e[0];
      memcpy(adresse + 11, e + 1, 5);
      break;
    case 2:
      adresse[0] = 0xFF;
      adresse[1] = e[0];
      memcpy(adresse + 13, e + 1, 3);
      break;
    default:
      adresse[0] = 0xFF;
      adresse[1] = 0x02;
      adresse[15] = e[0];
      break;
  }
  *i += kLongueurs[mode];
  return true;
}

constexpr uint8_t kProtocoleUdp = 17;

}  // namespace

bool lienLocal(const uint8_t a[16]) {
  static const uint8_t kPrefixe[8] = {0xFE, 0x80, 0, 0, 0, 0, 0, 0};
  return !memcmp(a, kPrefixe, sizeof(kPrefixe));
}

Refus lireDatagramme(const uint8_t *p, const EnTeteMac &m, Datagramme *d) {
  *d = Datagramme();
  const size_t fin = m.fin;
  size_t i = m.charge;
  if (i + 2 > fin) return Refus::Tronquee;
  if ((p[i] & 0xE0) != 0x60) return Refus::PasIphc;
  const uint8_t a = p[i], b = p[i + 1];
  i += 2;
  const uint8_t tf = (a >> 3) & 3, hlim = a & 3;
  const bool nh = a & 0x04;
  const bool cid = b & 0x80, sac = b & 0x40, mcast = b & 0x08, dac = b & 0x04;
  const uint8_t sam = (b >> 4) & 3, dam = b & 3;
  if (cid || sac || dac) return Refus::Contexte;
  static const size_t kTf[] = {4, 3, 1, 0};
  i += kTf[tf];
  uint8_t suivant = 0;
  if (!nh) {
    if (i + 1 > fin) return Refus::Tronquee;
    suivant = p[i++];
  }
  if (hlim == 0) i++;
  if (i > fin) return Refus::Tronquee;
  if (!unicast(p, fin, &i, sam, m.src, m.modeSrc, d->src)) return Refus::Tronquee;
  const bool dstLue = mcast ? multicast(p, fin, &i, dam, d->dst) : unicast(p, fin, &i, dam, m.dst, m.modeDst, d->dst);
  if (!dstLue) return Refus::Tronquee;
  if (nh) {
    // NHC UDP : 11110CPP.
    if (i + 1 > fin) return Refus::Tronquee;
    const uint8_t u = p[i++];
    if ((u & 0xF8) != 0xF0) return Refus::PasUdp;
    static const size_t kPorts[] = {4, 3, 3, 1};
    const uint8_t ports = u & 3;
    const size_t somme = (u & 0x04) ? 0 : 2;
    if (i + kPorts[ports] + somme > fin) return Refus::Tronquee;
    const uint8_t *e = p + i;
    switch (ports) {
      case 0:
        d->portSrc = (uint16_t)(e[0] << 8 | e[1]);
        d->portDst = (uint16_t)(e[2] << 8 | e[3]);
        break;
      case 1:
        d->portSrc = (uint16_t)(e[0] << 8 | e[1]);
        d->portDst = (uint16_t)(0xF000 | e[2]);
        break;
      case 2:
        d->portSrc = (uint16_t)(0xF000 | e[0]);
        d->portDst = (uint16_t)(e[1] << 8 | e[2]);
        break;
      default:
        d->portSrc = (uint16_t)(0xF0B0 | e[0] >> 4);
        d->portDst = (uint16_t)(0xF0B0 | (e[0] & 0x0F));
        break;
    }
    i += kPorts[ports] + somme;
  } else {
    if (suivant != kProtocoleUdp) return Refus::PasUdp;
    if (i + 8 > fin) return Refus::Tronquee;
    d->portSrc = (uint16_t)(p[i] << 8 | p[i + 1]);
    d->portDst = (uint16_t)(p[i + 2] << 8 | p[i + 3]);
    i += 8;
  }
  d->charge = i;
  return Refus::Aucun;
}

// ===========================================================================
//  Securite MLE
// ===========================================================================

bool lireSecuriteMle(const uint8_t *c, size_t n, SecuriteMle *s) {
  *s = SecuriteMle();
  if (n < 1 + kEnTeteSecurite + 1 + kMic || c[0] != kSuiteChiffree || c[1] != kControle) return false;
  s->entete = c + 1;
  s->compteur = (uint32_t)c[2] | (uint32_t)c[3] << 8 | (uint32_t)c[4] << 16 | (uint32_t)c[5] << 24;
  s->sequence = (uint32_t)c[6] << 24 | (uint32_t)c[7] << 16 | (uint32_t)c[8] << 8 | (uint32_t)c[9];
  s->index = c[10];
  s->chiffre = c + 1 + kEnTeteSecurite;
  s->n = n - 1 - kEnTeteSecurite - kMic;
  s->mic = c + n - kMic;
  return true;
}

void extDepuisIid(const uint8_t iid[8], uint8_t ext[8]) {
  memcpy(ext, iid, 8);
  ext[0] ^= 0x02;
}

void nonceMle(const uint8_t ext[8], uint32_t compteur, uint8_t nonce[kNonce]) {
  memcpy(nonce, ext, 8);
  nonce[8] = (uint8_t)(compteur >> 24);
  nonce[9] = (uint8_t)(compteur >> 16);
  nonce[10] = (uint8_t)(compteur >> 8);
  nonce[11] = (uint8_t)compteur;
  nonce[12] = kNiveau;
}

void donneesAssociees(const uint8_t src[16], const uint8_t dst[16], const uint8_t entete[kEnTeteSecurite],
                      uint8_t aad[kDonneesAssociees]) {
  memcpy(aad, src, 16);
  memcpy(aad + 16, dst, 16);
  memcpy(aad + 32, entete, kEnTeteSecurite);
}

bool deriverCleMle(const uint8_t cleReseau[kCle], uint32_t sequence, uint8_t cleMle[kCle]) {
  const uint8_t entree[4 + 6] = {(uint8_t)(sequence >> 24), (uint8_t)(sequence >> 16), (uint8_t)(sequence >> 8),
                                 (uint8_t)sequence, 'T', 'h', 'r', 'e', 'a', 'd'};
  uint8_t hash[32];
  const bool ok = hmacSha256(cleReseau, kCle, entree, sizeof(entree), hash);
  if (ok) memcpy(cleMle, hash, kCle);  // les 128 premiers bits : la cle MLE
  effacer(hash, sizeof(hash));
  return ok;
}

// ===========================================================================
//  Message
// ===========================================================================

namespace {

constexpr uint8_t kTlvSource = 0, kTlvRoute64 = 9, kTlvChef = 11;

}  // namespace

void lireTlv(const uint8_t *c, size_t n, Message *m) {
  if (n < 1) return;
  m->commande = c[0];
  for (size_t i = 1; i + 2 <= n;) {
    const uint8_t type = c[i];
    const size_t l = c[i + 1];
    if (i + 2 + l > n) break;
    const uint8_t *v = c + i + 2;
    if (type == kTlvSource && l == 2) {
      m->aSource = true;
      m->rloc16 = (uint16_t)(v[0] << 8 | v[1]);
    } else if (type == kTlvChef && l == 8) {
      m->aPartition = true;
      m->partition = (uint32_t)v[0] << 24 | (uint32_t)v[1] << 16 | (uint32_t)v[2] << 8 | (uint32_t)v[3];
    } else if (type == kTlvRoute64 && l >= 9 && l <= kRoute64Max) {
      m->nRoute64 = (uint8_t)l;
      memcpy(m->route64, v, l);
    }
    i += 2 + l;
  }
}

Issue decoder(const uint8_t *psdu, size_t n, FournisseurCle fournir, void *contexte, Message *m) {
  EnTeteMac mac;
  Datagramme d;
  if (!lireMac(psdu, n, &mac) || lireDatagramme(psdu, mac, &d) != Refus::Aucun) return Issue::Ignoree;
  if (d.portDst != kPortMle || !lienLocal(d.src)) return Issue::Ignoree;
  const uint8_t *c = psdu + d.charge;
  const size_t nc = mac.fin - d.charge;
  if (nc >= 1 && c[0] == kSuiteSansSecurite) return Issue::Ignoree;
  SecuriteMle s;
  if (!lireSecuriteMle(c, nc, &s)) return Issue::Echec;
  uint8_t cle[kCle];
  if (!fournir(contexte, s.sequence, cle)) {
    effacer(cle, sizeof(cle));
    return Issue::Echec;
  }
  uint8_t ext[8], nonce[kNonce], aad[kDonneesAssociees], clair[kPsduMax];
  extDepuisIid(d.src + 8, ext);
  nonceMle(ext, s.compteur, nonce);
  donneesAssociees(d.src, d.dst, s.entete, aad);
  const bool ok = aesCcmDechiffrer(cle, nonce, aad, sizeof(aad), s.chiffre, s.n, s.mic, clair);
  effacer(cle, sizeof(cle));
  if (!ok) {
    effacer(clair, sizeof(clair));
    return Issue::Echec;
  }
  *m = Message();
  memcpy(m->ext, ext, 8);
  lireTlv(clair, s.n, m);
  effacer(clair, sizeof(clair));
  return Issue::Dechiffree;
}

// ===========================================================================
//  Cles MLE gardees
// ===========================================================================

bool ClesMle::preparer(uint32_t courante, const uint8_t cleReseau[kCle]) {
  Place p[2];
  p[0].sequence = courante;
  p[1].sequence = courante + 1;  // la suivante, a la rotation (le retour a 0 compris)
  const bool ok = deriverCleMle(cleReseau, p[0].sequence, p[0].cle) && deriverCleMle(cleReseau, p[1].sequence, p[1].cle);
  if (ok) {
    effacer();
    memcpy(places_, p, sizeof(places_));
    prepare_ = true;
    courante_ = courante;
  }
  mle::effacer(p, sizeof(p));
  return ok;
}

bool ClesMle::trouver(uint32_t sequence, uint8_t cle[kCle]) const {
  if (!prepare_) return false;
  for (const Place &p : places_)
    if (p.sequence == sequence) {
      memcpy(cle, p.cle, kCle);
      return true;
    }
  return false;
}

void ClesMle::effacer() {
  mle::effacer(places_, sizeof(places_));
  prepare_ = false;
  courante_ = 0;
}

bool SourceCles::fournir(uint32_t sequence, uint8_t cle[kCle]) {
  if (cles_.trouver(sequence, cle)) return true;
  if (consultee_) return false;
  consultee_ = true;
  uint32_t courante = 0;
  if (acces_.sequence == nullptr || !acces_.sequence(&courante)) return false;
  if (tentee_ && courante == sequenceTentee_) return false;
  uint8_t reseau[kCle];
  if (acces_.cleReseau == nullptr || !acces_.cleReseau(reseau)) {
    mle::effacer(reseau, sizeof(reseau));
    return false;
  }
  tentee_ = true;
  sequenceTentee_ = courante;
  const bool preparees = cles_.preparer(courante, reseau);
  mle::effacer(reseau, sizeof(reseau));
  return preparees && cles_.trouver(sequence, cle);
}

bool SourceCles::rappel(void *contexte, uint32_t sequence, uint8_t cle[kCle]) {
  return static_cast<SourceCles *>(contexte)->fournir(sequence, cle);
}

// ===========================================================================
//  Routeurs entendus
// ===========================================================================

bool TableEntendus::noter(const Message &m, int8_t rssi, uint32_t maintenant) {
  if (!m.aSource || (m.rloc16 & 0x03FF)) return false;
  Entendu *e = nullptr, *libre = nullptr, *ancien = nullptr;
  for (Entendu &p : places_) {
    if (p.utilise && !memcmp(p.ext, m.ext, 8)) {
      e = &p;
      break;
    }
    if (!p.utilise) {
      if (!libre) libre = &p;
    } else if (!ancien || maintenant - p.dernier > maintenant - ancien->dernier) {
      ancien = &p;
    }
  }
  if (!e) {
    e = libre ? libre : ancien;
    *e = Entendu();
    e->utilise = true;
    memcpy(e->ext, m.ext, 8);
    e->rssiMin = e->rssiMax = rssi;
  }
  e->rloc16 = m.rloc16;
  if (m.aPartition) {
    e->aPartition = true;
    e->partition = m.partition;
  }
  if (m.nRoute64) {
    e->nRoute64 = m.nRoute64;
    memcpy(e->route64, m.route64, m.nRoute64);
  }
  e->rssi = rssi;
  if (rssi < e->rssiMin) e->rssiMin = rssi;
  if (rssi > e->rssiMax) e->rssiMax = rssi;
  e->nb++;
  e->dernier = maintenant;
  return true;
}

void TableEntendus::oublier(uint32_t maintenant) {
  for (Entendu &p : places_)
    if (p.utilise && maintenant - p.dernier >= kOubliMs) p = Entendu();
}

size_t TableEntendus::nombre() const {
  size_t k = 0;
  for (const Entendu &p : places_) k += p.utilise;
  return k;
}

}  // namespace mle
