// Tests hote de sonde/src/mle.{h,cpp} (ecoute des messages MLE, firmware 1.1.0) : derivation de la cle MLE,
// AES-CCM, en-tete 802.15.4 (2006 et 2015, IE, PAN), IPHC, UDP, en-tete de securite MLE, dechiffrement et refus,
// TLV, cles gardees, table des routeurs entendus ; et la robustesse devant des trames tronquees ou abimees (ASan,
// UBSan). Vecteurs : sonde/test/vecteurs_mle.h, produits par sonde/test/vecteurs_mle.py (cle et adresses inventees).
// Lancer : sh sonde/test/lancer.sh
//
// La crypto de la plateforme vient ici de CommonCrypto (macOS), qui n'a pas d'AES-CCM : il est bati ci-dessous sur
// son AES-ECB, d'apres la RFC 3610 (L = 2, M = 4). Sur la carte, mbedTLS (src/mle_crypto.cpp).
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <stdio.h>
#include <string.h>

#include "mle.h"
#include "vecteurs_mle.h"

using namespace mle;

// Echec de la plateforme simule (tas epuise sur la carte) : testFournisseur.
static bool gHmacEchoue = false;

namespace mle {

bool hmacSha256(const uint8_t *cle, size_t nCle, const uint8_t *message, size_t n, uint8_t sortie[32]) {
  if (gHmacEchoue) return false;
  CCHmac(kCCHmacAlgSHA256, cle, nCle, message, n, sortie);
  return true;
}

static void aes(const uint8_t cle[kCle], const uint8_t entree[16], uint8_t sortie[16]) {
  uint8_t bloc[16];
  size_t ecrits = 0;
  CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionECBMode, cle, kCle, nullptr, entree, 16, bloc, 16, &ecrits);
  memcpy(sortie, bloc, 16);
}

bool aesCcmDechiffrer(const uint8_t cle[kCle], const uint8_t nonce[kNonce], const uint8_t *aad, size_t nAad,
                      const uint8_t *chiffre, size_t n, const uint8_t mic[kMic], uint8_t *clair) {
  // Compteur : A_i = drapeaux (L - 1), nonce, i sur 2 octets ; S_0 masque le MIC, S_1... le texte.
  uint8_t a[16] = {0x01}, s[16], x[16], b[16];
  memcpy(a + 1, nonce, kNonce);
  for (size_t k = 0; k < n; k += 16) {
    const uint16_t i = (uint16_t)(1 + k / 16);
    a[14] = (uint8_t)(i >> 8);
    a[15] = (uint8_t)i;
    aes(cle, a, s);
    for (size_t j = 0; j < 16 && k + j < n; j++) clair[k + j] = chiffre[k + j] ^ s[j];
  }
  // CBC-MAC : B_0 (Adata, M, L), la longueur des donnees associees sur 2 octets puis elles, puis le clair.
  b[0] = (uint8_t)((nAad ? 0x40 : 0) | ((kMic - 2) / 2) << 3 | (2 - 1));
  memcpy(b + 1, nonce, kNonce);
  b[14] = (uint8_t)(n >> 8);
  b[15] = (uint8_t)n;
  aes(cle, b, x);
  uint8_t bloc[16];
  size_t remplis = 0;
  auto ajouter = [&](uint8_t o) {
    bloc[remplis++] = o;
    if (remplis == 16) {
      for (int j = 0; j < 16; j++) x[j] ^= bloc[j];
      aes(cle, x, x);
      remplis = 0;
    }
  };
  auto completer = [&]() {
    if (!remplis) return;
    while (remplis < 16) bloc[remplis++] = 0;
    for (int j = 0; j < 16; j++) x[j] ^= bloc[j];
    aes(cle, x, x);
    remplis = 0;
  };
  if (nAad) {
    ajouter((uint8_t)(nAad >> 8));
    ajouter((uint8_t)nAad);
    for (size_t k = 0; k < nAad; k++) ajouter(aad[k]);
    completer();
  }
  for (size_t k = 0; k < n; k++) ajouter(clair[k]);
  completer();
  a[14] = a[15] = 0;
  aes(cle, a, s);
  uint8_t difference = 0;
  for (size_t j = 0; j < kMic; j++) difference |= (uint8_t)((x[j] ^ s[j]) ^ mic[j]);
  if (difference) {
    effacer(clair, n);
    return false;
  }
  return true;
}

}  // namespace mle

static int gChecks = 0, gFails = 0;
#define CHECK(cond, ...)                              \
  do {                                                \
    gChecks++;                                        \
    if (!(cond)) {                                    \
      if (++gFails <= 40) {                           \
        printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
        printf(__VA_ARGS__);                          \
        printf("\n");                                 \
      }                                               \
    }                                                 \
  } while (0)

// Les cles de la pile des tests : la sequence courante (kSequence) et la suivante.
static bool fournir(void *contexte, uint32_t sequence, uint8_t cle[kCle]) {
  return static_cast<const ClesMle *>(contexte)->trouver(sequence, cle);
}

static bool nul(const uint8_t *p, size_t n) {
  for (size_t i = 0; i < n; i++)
    if (p[i]) return false;
  return true;
}

static void testDerivation() {
  for (const VecteurDerivation &v : kDerivations) {
    uint8_t cle[kCle] = {};
    CHECK(deriverCleMle(kCleReseau, v.sequence, cle) && !memcmp(cle, v.cle, kCle), "cle MLE de la sequence %u",
          v.sequence);
  }
  // Deux cles gardees : la courante et la suivante ; rien d'autre.
  ClesMle cles;
  uint8_t cle[kCle];
  CHECK(!cles.preparees() && !cles.trouver(kSequence, cle), "rien avant preparer");
  CHECK(cles.preparer(kSequence, kCleReseau) && cles.preparees() && cles.courante() == kSequence, "preparees");
  CHECK(cles.trouver(kSequence, cle) && !memcmp(cle, kDerivations[1].cle, kCle), "la courante");
  CHECK(cles.trouver(kSequence + 1, cle) && !memcmp(cle, kDerivations[2].cle, kCle), "la suivante");
  CHECK(!cles.trouver(kSequence - 1, cle) && !cles.trouver(kSequence + 2, cle), "ni la precedente, ni d'autres");
  // La suivante de 0xFFFFFFFF est 0.
  CHECK(cles.preparer(0xFFFFFFFFu, kCleReseau), "preparees au bout");
  CHECK(cles.trouver(0xFFFFFFFFu, cle) && !memcmp(cle, kDerivations[3].cle, kCle), "0xFFFFFFFF");
  CHECK(cles.trouver(0, cle) && !memcmp(cle, kDerivations[0].cle, kCle), "puis 0");
  CHECK(!cles.trouver(kSequence, cle), "les anciennes ne restent pas");
  cles.effacer();
  CHECK(!cles.preparees() && !cles.trouver(0, cle), "effacees");
}

// La pile des tests de SourceCles : sa sequence, son verrou (refuse ou non), et le nombre de lectures.
static uint32_t gSequencePile = 0;
static bool gVerrouSequence = true, gVerrouCle = true;
static int gLecturesSequence = 0, gLecturesCle = 0;

static bool lireSequencePile(uint32_t *courante) {
  gLecturesSequence++;
  if (!gVerrouSequence) return false;
  *courante = gSequencePile;
  return true;
}

static bool lireClePile(uint8_t cle[kCle]) {
  gLecturesCle++;
  if (!gVerrouCle) return false;
  memcpy(cle, kCleReseau, kCle);
  return true;
}

// SourceCles : des trames recues ne font pas relire la cle reseau en boucle : la sequence de la pile au plus une fois par tour,
// la cle reseau au plus une fois par sequence de la pile, que la derivation reussisse ou non ; un verrou refuse ne
// retient rien.
static void testFournisseur() {
  uint8_t cle[kCle];
  SourceCles f;
  f.nouveauTour();
  CHECK(!f.fournir(kSequence, cle) && gLecturesSequence == 0, "non branche : rien, sans lecture");
  f.brancher({lireSequencePile, lireClePile});
  gSequencePile = kSequence;
  // Premiere trame : la sequence et la cle lues, une fois.
  f.nouveauTour();
  CHECK(f.fournir(kSequence, cle) && !memcmp(cle, kDerivations[1].cle, kCle), "la courante");
  CHECK(gLecturesSequence == 1 && gLecturesCle == 1, "une lecture de chaque");
  CHECK(f.fournir(kSequence + 1, cle) && !memcmp(cle, kDerivations[2].cle, kCle), "la suivante, gardee");
  // Sequences etrangeres (trames forgees) : au plus une lecture de la sequence par tour, jamais la cle.
  for (int k = 0; k < 16; k++) CHECK(!f.fournir(kSequence + 9, cle), "etrangere");
  CHECK(gLecturesSequence == 1 && gLecturesCle == 1, "etrangeres, meme tour : la pile deja lue a ce tour");
  for (int tour = 0; tour < 5; tour++) {
    f.nouveauTour();
    for (int k = 0; k < 16; k++) f.fournir(kSequence - 1, cle);
  }
  CHECK(gLecturesSequence == 6 && gLecturesCle == 1, "cinq tours : cinq lectures de la sequence, aucune de la cle");
  // Rotation de cle : la sequence de la pile change, la cle est relue une fois.
  gSequencePile = kSequence + 1;
  f.nouveauTour();
  CHECK(f.fournir(kSequence + 2, cle) && gLecturesCle == 2, "rotation : la cle relue");
  CHECK(f.fournir(kSequence + 1, cle) && !memcmp(cle, kDerivations[2].cle, kCle), "la nouvelle courante");
  // Derivation en echec : la sequence est retenue, la cle n'est plus relue tant que la pile n'a pas change ; les cles
  // d'avant restent.
  gHmacEchoue = true;
  gSequencePile = kSequence + 7;
  f.nouveauTour();
  CHECK(!f.fournir(kSequence + 7, cle) && gLecturesCle == 3, "echec de derivation");
  CHECK(f.fournir(kSequence + 2, cle), "les cles d'avant restent");
  for (int tour = 0; tour < 5; tour++) {
    f.nouveauTour();
    for (int k = 0; k < 16; k++) CHECK(!f.fournir(kSequence + 7, cle), "toujours pas de cle");
  }
  CHECK(gLecturesCle == 3, "apres un echec de derivation, la cle n'est pas relue");
  gHmacEchoue = false;
  f.nouveauTour();
  CHECK(!f.fournir(kSequence + 7, cle) && gLecturesCle == 3, "ni quand la plateforme revient, meme sequence");
  gSequencePile = kSequence + 8;
  f.nouveauTour();
  CHECK(f.fournir(kSequence + 8, cle) && gLecturesCle == 4, "la sequence de la pile change : relue, derivee");
  // Verrou refuse a la lecture de la cle : rien n'est retenu ; une seule tentative par tour, puis au tour suivant.
  gVerrouCle = false;
  gSequencePile = kSequence + 20;
  f.nouveauTour();
  CHECK(!f.fournir(kSequence + 20, cle) && gLecturesCle == 5, "verrou refuse");
  CHECK(!f.fournir(kSequence + 20, cle) && gLecturesCle == 5, "pas d'autre tentative a ce tour");
  gVerrouCle = true;
  f.nouveauTour();
  CHECK(f.fournir(kSequence + 20, cle) && gLecturesCle == 6, "au tour suivant : lue, derivee");
  // Verrou refuse a la lecture de la sequence : une seule tentative par tour.
  gVerrouSequence = false;
  const int avant = gLecturesSequence;
  f.nouveauTour();
  CHECK(!f.fournir(kSequence + 30, cle) && !f.fournir(kSequence + 31, cle), "sequence illisible");
  CHECK(gLecturesSequence == avant + 1 && gLecturesCle == 6, "une tentative");
  gVerrouSequence = true;
}

static void testCcm() {
  uint8_t clair[sizeof(kCcmClair)];
  CHECK(aesCcmDechiffrer(kCcmCle, kCcmNonce, kCcmAad, sizeof(kCcmAad), kCcmChiffre, sizeof(kCcmChiffre), kCcmMic,
                         clair) &&
            !memcmp(clair, kCcmClair, sizeof(clair)),
        "AES-CCM : le vecteur");
  uint8_t mic[kMic];
  memcpy(mic, kCcmMic, kMic);
  mic[3] ^= 0x80;
  memset(clair, 0xEE, sizeof(clair));
  CHECK(!aesCcmDechiffrer(kCcmCle, kCcmNonce, kCcmAad, sizeof(kCcmAad), kCcmChiffre, sizeof(kCcmChiffre), mic, clair) &&
            nul(clair, sizeof(clair)),
        "AES-CCM : MIC faux refuse, clair efface");
  uint8_t aad[sizeof(kCcmAad)];
  memcpy(aad, kCcmAad, sizeof(aad));
  aad[0] ^= 1;
  CHECK(!aesCcmDechiffrer(kCcmCle, kCcmNonce, aad, sizeof(aad), kCcmChiffre, sizeof(kCcmChiffre), kCcmMic, clair),
        "AES-CCM : donnees associees changees refusees");
}

static void testTrames() {
  ClesMle cles;
  cles.preparer(kSequence, kCleReseau);
  for (const VecteurTrame &v : kTrames) {
    EnTeteMac m;
    const bool lue = lireMac(v.psdu, v.n, &m);
    CHECK(lue == v.macLue, "%s : en-tete MAC %s", v.nom, v.macLue ? "lu" : "refuse");
    if (lue) {
      CHECK(m.version == v.version && m.modeDst == v.modeDst && m.modeSrc == v.modeSrc, "%s : version et modes",
            v.nom);
      CHECK(m.charge == v.charge && m.fin == v.n - 2, "%s : charge a %zu (attendue %zu)", v.nom, m.charge, v.charge);
      Datagramme d;
      const Refus r = lireDatagramme(v.psdu, m, &d);
      CHECK((int)r == v.refus, "%s : refus %d (attendu %d)", v.nom, (int)r, v.refus);
      if (r == Refus::Aucun) {
        CHECK(!memcmp(d.src, v.src, 16) && !memcmp(d.dst, v.dst, 16), "%s : adresses", v.nom);
        CHECK(d.portSrc == v.portSrc && d.portDst == v.portDst, "%s : ports %u et %u", v.nom, d.portSrc, d.portDst);
      }
    }
    Message msg;
    const Issue i = decoder(v.psdu, v.n, fournir, &cles, &msg);
    CHECK((int)i == v.issue, "%s : issue %d (attendue %d)", v.nom, (int)i, v.issue);
    if (i != Issue::Dechiffree) continue;
    CHECK(!memcmp(msg.ext, v.ext, 8), "%s : ExtMac de l'emetteur", v.nom);
    CHECK(msg.commande == v.commande && msg.aSource && msg.rloc16 == v.rloc16, "%s : commande et RLOC16", v.nom);
    CHECK(msg.aPartition == v.aPartition && msg.partition == v.partition, "%s : partition", v.nom);
    CHECK(msg.nRoute64 == v.nRoute64 && (!v.nRoute64 || !memcmp(msg.route64, v.route64, v.nRoute64)),
          "%s : Route64 (%u octets)", v.nom, msg.nRoute64);
  }
}

// Toute trame tronquee d'une trame dechiffrable : jamais dechiffree, jamais hors des bornes (ASan).
static void testTronquees() {
  ClesMle cles;
  cles.preparer(kSequence, kCleReseau);
  int dechiffrees = 0;
  for (const VecteurTrame &v : kTrames) {
    if (v.issue != 1) continue;
    for (size_t n = 0; n < v.n; n++) {
      uint8_t copie[kPsduMax];
      memcpy(copie, v.psdu, n);
      Message msg;
      if (decoder(copie, n, fournir, &cles, &msg) == Issue::Dechiffree) dechiffrees++;
    }
  }
  CHECK(dechiffrees == 0, "trames tronquees : %d dechiffrees", dechiffrees);
}

// Chaque octet d'une trame change a son tour : le message n'est jamais dechiffre avec une autre ExtMac, une autre
// commande ni d'autres TLV que celles de la trame (le MIC couvre tout ce qui compte), et rien ne deborde.
static void testAbimees() {
  ClesMle cles;
  cles.preparer(kSequence, kCleReseau);
  int faux = 0;
  for (const VecteurTrame &v : kTrames) {
    if (v.issue != 1) continue;
    for (size_t k = 0; k + 2 < v.n; k++) {
      static const uint8_t kMasques[] = {0x01, 0x80, 0xFF};
      for (uint8_t masque : kMasques) {
        uint8_t copie[kPsduMax];
        memcpy(copie, v.psdu, v.n);
        copie[k] ^= masque;
        Message msg;
        if (decoder(copie, v.n, fournir, &cles, &msg) != Issue::Dechiffree) continue;
        const bool pareil = !memcmp(msg.ext, v.ext, 8) && msg.commande == v.commande && msg.rloc16 == v.rloc16 &&
                            msg.nRoute64 == v.nRoute64 && msg.partition == v.partition;
        if (!pareil) faux++;
      }
    }
  }
  CHECK(faux == 0, "trames abimees : %d dechiffrees autrement", faux);
}

// Des trames au hasard (generateur fixe) : rien ne deborde, rien n'est dechiffre.
static void testHasard() {
  ClesMle cles;
  cles.preparer(kSequence, kCleReseau);
  uint32_t x = 0x9E3779B9u;
  auto suivant = [&x]() {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
  };
  int dechiffrees = 0;
  for (int k = 0; k < 200000; k++) {
    uint8_t t[kPsduMax];
    const size_t n = suivant() % (kPsduMax + 1);
    for (size_t i = 0; i < n; i++) t[i] = (uint8_t)suivant();
    // Une trame sur deux commence comme une trame de donnees (2003, PAN compresse, destination courte, source
    // longue), IPHC tire du MAC, UDP vers le port MLE, en-tete de securite de la sequence courante : le hasard va
    // jusqu'au dechiffrement.
    if (k % 2 && n > 40) {
      const uint8_t debut[] = {0x41, 0xC8};
      memcpy(t, debut, sizeof(debut));
      t[15] = 0x7F;
      t[16] = 0x33;
      t[17] = 0xF0;
      t[20] = (uint8_t)(kPortMle >> 8);
      t[21] = (uint8_t)kPortMle;
      t[24] = kSuiteChiffree;
      t[25] = kControle;
      t[30] = t[31] = t[32] = 0;
      t[33] = (uint8_t)kSequence;
    }
    Message msg;
    if (decoder(t, n, fournir, &cles, &msg) == Issue::Dechiffree) dechiffrees++;
    EnTeteMac m;
    if (lireMac(t, n, &m)) {
      CHECK(m.charge <= m.fin && m.fin + 2 == n, "hasard : bornes de la charge");
      Datagramme d;
      if (lireDatagramme(t, m, &d) == Refus::Aucun) CHECK(d.charge <= m.fin, "hasard : bornes de l'UDP");
    }
  }
  CHECK(dechiffrees == 0, "hasard : %d dechiffrees", dechiffrees);
}

static void testSecurite() {
  // Suite 0, controle 0x15, compteur 0x04030201 (petit-boutiste), sequence 0x00000005 (gros-boutiste), index 6,
  // une commande chiffree, le MIC.
  const uint8_t c[] = {0x00, 0x15, 0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x05, 0x06, 0xAA, 0x11, 0x22, 0x33, 0x44};
  SecuriteMle s;
  CHECK(lireSecuriteMle(c, sizeof(c), &s), "en-tete de securite lu");
  CHECK(s.compteur == 0x04030201u && s.sequence == 5 && s.index == 6, "compteur, sequence, index");
  CHECK(s.entete == c + 1 && s.chiffre == c + 11 && s.n == 1 && s.mic == c + 12, "places");
  CHECK(!lireSecuriteMle(c, sizeof(c) - 1, &s), "sans octet chiffre : refuse");
  uint8_t autre[sizeof(c)];
  memcpy(autre, c, sizeof(c));
  autre[1] = 0x0D;  // niveau 5, cle en mode 1
  CHECK(!lireSecuriteMle(autre, sizeof(autre), &s), "autre controle : refuse");
  memcpy(autre, c, sizeof(c));
  autre[0] = 0xFF;
  CHECK(!lireSecuriteMle(autre, sizeof(autre), &s), "sans securite : refuse");
  // Nonce et donnees associees.
  const uint8_t ext[8] = {0xE0, 0, 0, 0, 0, 0, 0x0A, 0x01};
  uint8_t nonce[kNonce];
  nonceMle(ext, 0x01020304u, nonce);
  const uint8_t attendu[kNonce] = {0xE0, 0, 0, 0, 0, 0, 0x0A, 0x01, 0x01, 0x02, 0x03, 0x04, 0x05};
  CHECK(!memcmp(nonce, attendu, kNonce), "nonce : ExtMac, compteur gros-boutiste, niveau 5");
  uint8_t iid[8] = {0xE2, 0, 0, 0, 0, 0, 0x0A, 0x01}, e[8];
  extDepuisIid(iid, e);
  CHECK(!memcmp(e, ext, 8), "ExtMac d'un identifiant d'interface : bit U/L inverse");
  uint8_t src[16], dst[16], aad[kDonneesAssociees];
  for (int k = 0; k < 16; k++) src[k] = (uint8_t)k, dst[k] = (uint8_t)(0x80 + k);
  donneesAssociees(src, dst, c + 1, aad);
  CHECK(!memcmp(aad, src, 16) && !memcmp(aad + 16, dst, 16) && !memcmp(aad + 32, c + 1, 10), "donnees associees");
  CHECK(lienLocal(src) == false && lienLocal(kTrames[0].src), "lien-local : fe80::/64");
}

static void testTlv() {
  // Commande, Source Address, une TLV inconnue, Leader Data, Route64.
  const uint8_t c[] = {0x04, 0x00, 0x02, 0x50, 0x00, 0x22, 0x01, 0xEE, 0x0B, 0x08, 0x12, 0x34, 0xAB, 0xCD,
                       0x40, 0x11, 0x22, 0x14, 0x09, 0x0A, 0x7A, 0x80, 0, 0, 0, 0, 0, 0, 0, 0xF1};
  Message m;
  lireTlv(c, sizeof(c), &m);
  CHECK(m.commande == 4 && m.aSource && m.rloc16 == 0x5000, "commande et Source Address");
  CHECK(m.aPartition && m.partition == 0x1234ABCDu, "Leader Data");
  CHECK(m.nRoute64 == 10 && m.route64[0] == 0x7A && m.route64[9] == 0xF1, "Route64");
  // La Route64 deborde : la lecture s'arrete, le reste lu avant est garde.
  Message t;
  lireTlv(c, sizeof(c) - 1, &t);
  CHECK(t.aSource && t.aPartition && t.nRoute64 == 0, "TLV tronquee : ignoree");
  // Route64 trop courte (8 octets) ou trop longue (73) : ignoree.
  uint8_t court[] = {0x04, 0x09, 0x08, 1, 2, 3, 4, 5, 6, 7, 8};
  Message u;
  lireTlv(court, sizeof(court), &u);
  CHECK(u.nRoute64 == 0, "Route64 de 8 octets ignoree");
  uint8_t long_[2 + 2 + 73] = {0x04, 0x09, 73};
  Message w;
  lireTlv(long_, 3 + 73, &w);
  CHECK(w.nRoute64 == 0, "Route64 de 73 octets ignoree");
  // Source Address de 3 octets : ignoree ; message vide : rien.
  const uint8_t mauvais[] = {0x04, 0x00, 0x03, 0x50, 0x00, 0x01};
  Message x;
  lireTlv(mauvais, sizeof(mauvais), &x);
  CHECK(!x.aSource, "Source Address de 3 octets ignoree");
  Message y;
  lireTlv(c, 0, &y);
  CHECK(y.commande == 0 && !y.aSource, "message vide");
}

static Message routeur(uint8_t n, uint16_t rloc16, bool route = true) {
  Message m;
  m.ext[0] = 0xE0;
  m.ext[7] = n;
  m.aSource = true;
  m.rloc16 = rloc16;
  m.aPartition = true;
  m.partition = 0x1234ABCD;
  if (route) {
    m.nRoute64 = 10;
    m.route64[0] = n;
  }
  return m;
}

static void testTable() {
  TableEntendus t;
  CHECK(t.nombre() == 0, "vide");
  CHECK(!t.noter(routeur(1, 0x5004), -60, 1000), "un enfant n'entre pas");
  Message sansSource = routeur(1, 0x5000);
  sansSource.aSource = false;
  CHECK(!t.noter(sansSource, -60, 1000), "sans Source Address, rien");
  CHECK(!t.noter(routeur(1, 0x5200), -60, 1000), "bit 9 du RLOC16 : pas un routeur");
  CHECK(t.noter(routeur(1, 0x5000), -60, 1000) && t.nombre() == 1, "un routeur");
  const Entendu &e = t.place(0);
  CHECK(e.utilise && e.ext[7] == 1 && e.rloc16 == 0x5000 && e.aPartition && e.partition == 0x1234ABCDu, "son entree");
  CHECK(e.nRoute64 == 10 && e.route64[0] == 1 && e.nb == 1 && e.dernier == 1000, "sa Route64, un message");
  CHECK(e.rssi == -60 && e.rssiMin == -60 && e.rssiMax == -60, "signal");
  // Un message sans Route64 (demande de lien) garde la Route64 d'avant ; le signal suit.
  CHECK(t.noter(routeur(1, 0x5000, false), -75, 2000), "sans Route64");
  CHECK(e.nRoute64 == 10 && e.nb == 2 && e.dernier == 2000, "la Route64 d'avant reste");
  CHECK(t.noter(routeur(1, 0x5000), -50, 3000), "encore");
  CHECK(e.rssi == -50 && e.rssiMin == -75 && e.rssiMax == -50 && e.nb == 3, "minimum et maximum");
  // Nouvel identifiant (redemarrage) : la meme entree, le nouveau RLOC16.
  CHECK(t.noter(routeur(1, 0x0400), -50, 4000) && t.nombre() == 1 && e.rloc16 == 0x0400, "nouveau RLOC16");
  // Muet depuis 10 min : retire ; un autre, plus recent, reste.
  CHECK(t.noter(routeur(2, 0xAC00), -80, 300000), "un autre");
  t.oublier(4000 + TableEntendus::kOubliMs - 1);
  CHECK(t.nombre() == 2, "pas encore 10 min");
  t.oublier(4000 + TableEntendus::kOubliMs);
  CHECK(t.nombre() == 1 && !t.place(0).utilise && t.place(1).ext[7] == 2, "10 min : retire");
  // Pleine : le plus ancien laisse sa place.
  TableEntendus p;
  for (uint8_t k = 0; k < TableEntendus::kPlaces; k++) p.noter(routeur(k, (uint16_t)(k << 10)), -70, 10000u + k);
  CHECK(p.nombre() == TableEntendus::kPlaces, "pleine");
  p.noter(routeur(0, 0), -70, 20000);  // le routeur 0 revient : il n'est plus le plus ancien
  CHECK(p.noter(routeur(200, 0xFC00), -70, 30000), "un de plus");
  bool unPresent = false, zeroPresent = false, deuxCentsPresent = false;
  for (size_t k = 0; k < TableEntendus::kPlaces; k++) {
    unPresent |= p.place(k).ext[7] == 1;
    zeroPresent |= p.place(k).ext[7] == 0;
    deuxCentsPresent |= p.place(k).ext[7] == 200;
  }
  CHECK(!unPresent && zeroPresent && deuxCentsPresent, "le plus ancien (1) remplace");
  // Retour a zero de millis() : les ages restent justes.
  TableEntendus z;
  z.noter(routeur(9, 0x2400), -70, 0xFFFFFF00u);
  z.oublier(0x00000100u);
  CHECK(z.nombre() == 1, "zero : 512 ms plus tard, toujours la");
  z.oublier(0xFFFFFF00u + TableEntendus::kOubliMs);
  CHECK(z.nombre() == 0, "zero : 10 min plus tard, retire");
}

int main() {
  testDerivation();
  testFournisseur();
  testCcm();
  testSecurite();
  testTlv();
  testTrames();
  testTronquees();
  testAbimees();
  testHasard();
  testTable();
  printf("test_mle : %d verification(s), %d echec(s)\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
