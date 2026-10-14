#pragma once
// ===========================================================================
//  Ecoute des messages MLE : briques pures (firmware 1.1.0, spec de la sonde
//  tout-en-un, section 1)
//
//  Une trame 802.15.4 recue (PSDU, FCS compris), dans l'ordre :
//  - l'en-tete MAC, aux formats 2003/2006 et 2015 : numero de sequence
//    supprime (2015), PAN selon le tableau 7-2 (2015), IE d'en-tete jusqu'a
//    HT1 ou HT2 (2015 ; apres HT1, les IE de charge jusqu'a leur fin) ;
//    seules les trames de donnees sans securite MAC sont lues ;
//  - 6LoWPAN IPHC sans contexte (adresses en ligne, ou tirees des adresses
//    MAC), puis UDP, compresse (NHC) ou non ;
//  - vers le port MLE 19788, depuis une adresse lien-local : l'en-tete de
//    securite MLE (suite 0, controle 0x15 : niveau 5, cle en mode 2), le
//    compteur de trame petit-boutiste, la sequence de cle gros-boutiste dans
//    la source de cle ;
//  - le dechiffrement AES-CCM (MIC de 4 octets) par la cle MLE de cette
//    sequence : les 128 premiers bits de HMAC-SHA256(cle reseau, sequence ||
//    « Thread »). Nonce : ExtMac de l'emetteur (identifiant d'interface de son
//    adresse lien-local, bit U/L inverse), compteur gros-boutiste, niveau 5.
//    Donnees associees : adresses IPv6 source et destination, puis les 10
//    octets de l'en-tete de securite (controle, compteur, source et index de
//    cle) ;
//  - les TLV du message : Source Address (0), Route64 (9), Leader Data (11).
//
//  Aussi : la table des routeurs entendus (TableEntendus), les deux cles MLE
//  gardees (ClesMle) et leur source (SourceCles), qui ne lit la cle reseau
//  qu'une fois par sequence de la pile. La cle reseau n'est jamais gardee ici :
//  ClesMle::preparer la recoit le temps d'une derivation, puis elle est effacee.
//
//  Pur et sans Arduino : teste sur l'hote par sonde/test/test_mle.cpp, sur des
//  vecteurs produits par sonde/test/vecteurs_mle.py (cle et adresses
//  inventees) ; lancer : sh sonde/test/lancer.sh. La crypto vient de la
//  plateforme : mbedTLS sur la carte (mle_crypto.cpp), CommonCrypto dans les
//  tests (AES-CCM bati sur son AES-ECB).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

namespace mle {

constexpr uint16_t kPortMle = 19788;
// PSDU d'une trame 802.15.4, FCS compris.
constexpr size_t kPsduMax = 127;
// Valeur d'une TLV Route64 : sequence, masque de 8 octets, un octet par routeur (63 au plus).
constexpr size_t kRoute64Max = 72;
constexpr size_t kCle = 16;
constexpr size_t kNonce = 13;
constexpr size_t kMic = 4;
// En-tete de securite MLE sans la suite : controle, compteur (4), source de cle (4), index.
constexpr size_t kEnTeteSecurite = 10;
// Donnees associees : adresses source et destination, puis l'en-tete de securite.
constexpr size_t kDonneesAssociees = 16 + 16 + kEnTeteSecurite;
// Suite de securite d'un message MLE chiffre, et d'un message sans securite (Discovery).
constexpr uint8_t kSuiteChiffree = 0;
constexpr uint8_t kSuiteSansSecurite = 255;
// Niveau 5 (chiffrement, MIC de 32 bits), cle designee par sa source (mode 2).
constexpr uint8_t kControle = 0x15;
constexpr uint8_t kNiveau = 5;

// --- Crypto de la plateforme -------------------------------------------------

// HMAC-SHA256(cle, message). false : echec de la plateforme (sortie indefinie).
bool hmacSha256(const uint8_t *cle, size_t nCle, const uint8_t *message, size_t n, uint8_t sortie[32]);
// AES-128-CCM, nonce de 13 octets, MIC de 4 octets : dechiffre `n` octets et
// verifie le MIC. false : MIC faux ou echec ; `clair` est alors efface.
bool aesCcmDechiffrer(const uint8_t cle[kCle], const uint8_t nonce[kNonce], const uint8_t *aad, size_t nAad,
                      const uint8_t *chiffre, size_t n, const uint8_t mic[kMic], uint8_t *clair);

// --- Outils ------------------------------------------------------------------

// Mise a zero que l'optimiseur ne retire pas (cles et clairs sur la pile).
void effacer(void *p, size_t n);

// --- 802.15.4 ------------------------------------------------------------------

struct EnTeteMac {
  uint8_t version = 0;  // 0 : 2003, 1 : 2006, 2 : 2015
  uint8_t modeDst = 0;  // 0 : absente, 2 : courte, 3 : longue
  uint8_t modeSrc = 0;
  uint8_t dst[8] = {};  // dans l'ordre de la trame (petit-boutiste)
  uint8_t src[8] = {};
  size_t charge = 0;    // debut de la charge MAC, apres les IE
  size_t fin = 0;       // fin de la charge MAC : le FCS commence la
};

// En-tete d'une trame de donnees sans securite MAC. false : autre type de
// trame, securite MAC, version ou mode d'adresse inconnu, trame trop courte ou
// trop longue, IE mal formes.
bool lireMac(const uint8_t *psdu, size_t n, EnTeteMac *m);

// --- IPv6 (IPHC) et UDP ----------------------------------------------------------

struct Datagramme {
  uint8_t src[16] = {};
  uint8_t dst[16] = {};
  uint16_t portSrc = 0;
  uint16_t portDst = 0;
  size_t charge = 0;  // debut de la charge UDP dans la trame
};

enum class Refus : uint8_t {
  Aucun,
  PasIphc,     // fragment, en-tete maille, autre dispatch
  Contexte,    // IPHC avec contexte : pas une adresse lien-local
  PasUdp,      // autre en-tete suivant
  Tronquee,    // la trame finit avant l'en-tete
};

// IPHC sans contexte, puis UDP (NHC ou en ligne), a partir de la charge MAC.
Refus lireDatagramme(const uint8_t *psdu, const EnTeteMac &m, Datagramme *d);

// fe80::/64.
bool lienLocal(const uint8_t adresse[16]);

// --- Securite MLE ------------------------------------------------------------

struct SecuriteMle {
  uint32_t compteur = 0;   // compteur de trame
  uint32_t sequence = 0;   // sequence de cle (source de cle)
  uint8_t index = 0;       // index de cle
  const uint8_t *entete = nullptr;  // les kEnTeteSecurite octets, apres la suite
  const uint8_t *chiffre = nullptr;
  size_t n = 0;            // octets chiffres (commande et TLV)
  const uint8_t *mic = nullptr;
};

// Charge UDP d'un message MLE chiffre : suite 0, controle 0x15, puis au moins
// un octet chiffre et le MIC. false sinon.
bool lireSecuriteMle(const uint8_t *charge, size_t n, SecuriteMle *s);

// ExtMac (ordre naturel) d'un identifiant d'interface : le bit U/L inverse.
void extDepuisIid(const uint8_t iid[8], uint8_t ext[8]);
// Nonce : ExtMac, compteur gros-boutiste, niveau 5.
void nonceMle(const uint8_t ext[8], uint32_t compteur, uint8_t nonce[kNonce]);
// Donnees associees : source, destination, en-tete de securite.
void donneesAssociees(const uint8_t src[16], const uint8_t dst[16], const uint8_t entete[kEnTeteSecurite],
                      uint8_t aad[kDonneesAssociees]);
// Cle MLE d'une sequence : les 128 premiers bits de HMAC-SHA256(cle reseau,
// sequence gros-boutiste || « Thread »). false : echec de la plateforme.
bool deriverCleMle(const uint8_t cleReseau[kCle], uint32_t sequence, uint8_t cleMle[kCle]);

// --- Message dechiffre --------------------------------------------------------

struct Message {
  uint8_t ext[8] = {};      // emetteur, ordre naturel
  uint8_t commande = 0;
  bool aSource = false;     // TLV Source Address
  uint16_t rloc16 = 0;
  bool aPartition = false;  // TLV Leader Data
  uint32_t partition = 0;
  uint8_t nRoute64 = 0;     // valeur de la TLV Route64 (0 : absente ou mal formee)
  uint8_t route64[kRoute64Max] = {};
};

// Commande et TLV d'un message dechiffre. Une TLV qui deborde arrete la
// lecture ; ce qui a ete lu avant reste. Une Route64 de moins de 9 octets ou de
// plus de kRoute64Max est ignoree.
void lireTlv(const uint8_t *clair, size_t n, Message *m);

enum class Issue : uint8_t {
  Ignoree,     // pas un message MLE chiffre : autre trame, autre port, MLE sans securite
  Dechiffree,  // MIC verifie : le message est lu
  Echec,       // message MLE chiffre non dechiffre : en-tete illisible, cle indisponible, MIC faux
};

// Cle MLE d'une sequence ; false si elle n'est pas disponible.
typedef bool (*FournisseurCle)(void *contexte, uint32_t sequence, uint8_t cleMle[kCle]);

// Une trame entiere. Les cles et le clair passent par la pile et en sont
// effaces avant le retour.
Issue decoder(const uint8_t *psdu, size_t n, FournisseurCle cle, void *contexte, Message *m);

// --- Cles MLE gardees ---------------------------------------------------------

// Deux cles MLE derivees : la sequence courante de la pile et la suivante (une
// rotation de cle les fait servir l'une apres l'autre). Jamais la cle reseau.
class ClesMle {
 public:
  // Derive les cles de `courante` et de `courante + 1` ; l'appelant efface
  // ensuite `cleReseau`. false : echec de la plateforme ; rien de la nouvelle
  // derivation n'est garde, et les cles d'avant restent.
  bool preparer(uint32_t courante, const uint8_t cleReseau[kCle]);
  // Cle gardee de cette sequence.
  bool trouver(uint32_t sequence, uint8_t cle[kCle]) const;
  bool preparees() const { return prepare_; }
  uint32_t courante() const { return courante_; }
  void effacer();

 private:
  struct Place {
    uint32_t sequence = 0;
    uint8_t cle[kCle] = {};
  };
  Place places_[2];
  bool prepare_ = false;
  uint32_t courante_ = 0;
};

// Acces a la pile : sa sequence de cle courante, et la cle reseau (que
// l'appelant efface apres usage). Sur la carte, main.cpp, sous le verrou
// OpenThread. false : verrou non pris.
struct AccesPile {
  bool (*sequence)(uint32_t *courante);
  bool (*cleReseau)(uint8_t cle[kCle]);
};

// Les cles MLE du decodage (le FournisseurCle de decoder, avec `rappel`), tirees
// de la pile sans que des trames recues puissent faire relire la cle reseau en
// boucle ni prendre le verrou a chaque trame :
// - une sequence gardee (ClesMle) sert sans rien lire ;
// - sinon la pile est consultee au plus une fois par tour (nouveauTour) ;
// - la cle reseau est lue au plus une fois par sequence de la pile, que la
//   derivation reussisse ou non : elle n'est relue que quand cette sequence
//   change (rotation) ou au redemarrage ; un echec arrete l'ecoute jusqu'a
//   la rotation ou le redemarrage ; une sequence etrangere ne la fait jamais relire ;
// - une lecture refusee (verrou) ne retient rien : retentee au tour suivant.
// La cle reseau ne passe que par la pile de `fournir`, effacee avant le retour.
class SourceCles {
 public:
  void brancher(const AccesPile &acces) { acces_ = acces; }
  // Au debut de chaque tour de l'ecoute : la pile peut etre consultee une fois.
  void nouveauTour() { consultee_ = false; }
  bool fournir(uint32_t sequence, uint8_t cle[kCle]);
  // Pour decoder : `contexte` est la SourceCles.
  static bool rappel(void *contexte, uint32_t sequence, uint8_t cle[kCle]);

 private:
  AccesPile acces_ = {nullptr, nullptr};
  ClesMle cles_;
  bool consultee_ = false;   // la pile, a ce tour
  bool tentee_ = false;      // une cle reseau a ete lue pour sequenceTentee_
  uint32_t sequenceTentee_ = 0;
};

// --- Routeurs entendus --------------------------------------------------------

struct Entendu {
  bool utilise = false;
  uint8_t ext[8] = {};      // ordre naturel
  uint16_t rloc16 = 0;
  bool aPartition = false;
  uint32_t partition = 0;
  uint8_t nRoute64 = 0;     // derniere Route64 brute ; 0 : aucune encore
  uint8_t route64[kRoute64Max] = {};
  int8_t rssi = 0;          // derniere trame
  int8_t rssiMin = 0;       // depuis l'entree dans la table
  int8_t rssiMax = 0;
  uint32_t nb = 0;          // messages dechiffres
  uint32_t dernier = 0;     // millis() du dernier
};

// Routeurs entendus, par ExtMac : seuls les emetteurs dont le RLOC16 est celui
// d'un routeur (10 bits de poids faible nuls) y entrent. Un routeur muet depuis
// kOubliMs en sort. Table pleine : le plus ancien laisse sa place.
class TableEntendus {
 public:
  static constexpr size_t kPlaces = 32;
  static constexpr uint32_t kOubliMs = 600000;

  // Un message dechiffre ; false s'il n'est pas d'un routeur (sans TLV Source
  // Address, ou RLOC16 d'enfant).
  bool noter(const Message &m, int8_t rssi, uint32_t maintenant);
  // Retire les routeurs muets depuis kOubliMs.
  void oublier(uint32_t maintenant);
  const Entendu &place(size_t i) const { return places_[i]; }
  size_t nombre() const;

 private:
  Entendu places_[kPlaces];
};

}  // namespace mle
