// Acces reseau de la sonde : repris du pont Halo (depot benq au commit
// bd2268c, src/net_udp.cpp), memes noms internes ; les ecarts sont dits dans
// reseau.h et la ou ils sont.
#include "reseau.h"

#include <Arduino.h>
#include <Preferences.h>
#include <esp_openthread.h>
#include <esp_random.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <openthread/ip6.h>
#include <openthread/message.h>
#include <openthread/srp_client.h>
#include <openthread/udp.h>
#include <string.h>

#include "h1_proto.h"

static_assert(kPlacesReseau == h1::kSlots, "une place par session H1 etablie");

// Cle a cote du nom et de l'interrupteur de la sonde (Halo : halo1/cle).
static const char *const kNvsNs = "sonde";
static const char *const kNvsKey = "cle";

// Au-dela, le datagramme n'est pas pour nous (compte, jete).
static constexpr size_t kRxMax = kChargeRecueMax;
static constexpr uint8_t kRxN = 4;
// En-tete H1 et charge "<rid> <ligne JSON>" : 56 + 1100 octets.
static constexpr size_t kTxMax = h1::kHeaderMax + kChargeMax;
static constexpr uint8_t kTxN = 6;
static constexpr uint32_t kTxStaleMs = 4000;   // pas parti dans ce delai : perdu
static constexpr uint8_t kTxPerTurn = 2;       // datagrammes remis a OpenThread par tour de loop()
// Debit moyen plafonne (Halo) : 3000 octets/s, ~10 % du canal ; credit de
// 2400 octets (deux datagrammes pleins d'affilee).
static constexpr uint32_t kTxBytesPerS = 3000;
static constexpr uint32_t kTxBurst = 2400;
// Tampons OpenThread (128 octets, 65 en tout, partages avec Matter) laisses
// libres apres un envoi : un datagramme plein en prend ~12 jusqu'a son depart.
static constexpr uint16_t kBufReserve = 24;
static constexpr uint32_t kHostReadMs = 5000;  // nom SRP relu au plus toutes les 5 s
static constexpr uint32_t kExpireMs = 1000;
static constexpr uint32_t kOpenRetryMs = 1000;

struct RxItem {
  uint16_t len;
  uint16_t port;
  uint8_t peer[16];
  uint8_t local[16];
  uint8_t data[kRxMax];
};

struct TxItem {
  uint32_t at;
  bool errCounted;  // tx_erreurs compte une fois par datagramme
  uint8_t slot;     // session qui l'a scelle, kRawSlot : DEFI (sans session)
  uint16_t len;
  uint16_t port;
  uint8_t peer[16];
  uint8_t local[16];
  uint8_t data[kTxMax];
};

static constexpr uint8_t kRawSlot = 0xFF;

static QueueHandle_t sRxQ = nullptr;
static RxItem sRxOt;    // tampon du rappel (tache OT seulement)
static RxItem sRxLoop;  // tampon de la tache loop
static TxItem sTx[kTxN];
static uint8_t sTxHead = 0, sTxN = 0;

static h1::Table sTable;
static otUdpSocket sSock;
static bool sOpen = false;
static uint32_t sOpenTryAt = 0, sExpireAt = 0;
static uint32_t sTxCredit = kTxBurst, sTxCreditAt = 0;
// Cle chargee : lu par le rappel de reception (tache OT), ecrit par la tache loop.
static volatile bool sKeyLoaded = false;
static uint32_t sGeneration[h1::kSlots] = {};

static struct {
  volatile uint32_t rxTooBig, rxQueueFull, rxNoKey;  // ecrits par la tache OT
  uint32_t rxDropped;                               // en file quand la cle a change
  uint32_t rx, rejected, defis, tx, txLost, txErr;
  uint16_t bufMin;
} sSt = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFFFF};

static struct {
  bool known;
  uint32_t at;
  bool hostKnown;
  char host[64];
} sHost = {};

// ===========================================================================
//  Reception (tache OT, verrou OT tenu)
// ===========================================================================

// Jamais de verrou CHIP ni de Serial ici : copie dans la file, rien d'autre.
// Sans cle : rien n'est lu ni mis en file (silence total).
static void onRx(void *, otMessage *m, const otMessageInfo *info) {
  if (!sKeyLoaded) {
    sSt.rxNoKey = sSt.rxNoKey + 1;
    return;
  }
  const uint16_t off = otMessageGetOffset(m), total = otMessageGetLength(m);
  if (total < off || (size_t)(total - off) > kRxMax) {
    sSt.rxTooBig = sSt.rxTooBig + 1;
    return;
  }
  sRxOt.len = otMessageRead(m, off, sRxOt.data, (uint16_t)(total - off));
  sRxOt.port = info->mPeerPort;
  memcpy(sRxOt.peer, info->mPeerAddr.mFields.m8, 16);
  memcpy(sRxOt.local, info->mSockAddr.mFields.m8, 16);
  if (!sRxQ || xQueueSend(sRxQ, &sRxOt, 0) != pdTRUE) sSt.rxQueueFull = sSt.rxQueueFull + 1;
}

// ===========================================================================
//  File d'emission (tache loop)
// ===========================================================================

static TxItem *txTail() { return sTxN < kTxN ? &sTx[(sTxHead + sTxN) % kTxN] : nullptr; }

static void txPop() {
  if (!sTxN) return;
  sTxHead = (uint8_t)((sTxHead + 1) % kTxN);
  sTxN--;
}

static void txClear() {
  sSt.txLost += sTxN;
  sTxHead = sTxN = 0;
}

// Session partie (remplacee, oubliee) : ses datagrammes deja scelles ne
// prennent plus le debit de la suivante. Les autres gardent leur ordre.
static void txDropSlot(uint8_t slot) {
  uint8_t kept = 0;
  for (uint8_t i = 0; i < sTxN; i++) {
    const uint8_t from = (uint8_t)((sTxHead + i) % kTxN);
    if (sTx[from].slot == slot) {
      sSt.txLost++;
      continue;
    }
    const uint8_t to = (uint8_t)((sTxHead + kept) % kTxN);
    if (to != from) sTx[to] = sTx[from];
    kept++;
  }
  sTxN = kept;
}

// Datagramme sans session (DEFI) vers l'expediteur du SALUT : en tete de file,
// hors plafond de debit (82 octets, 2 par seconde au plus), pour qu'une
// poignee de main n'attende pas derriere les reponses d'une autre session.
static void queueRaw(const h1::Peer &to, const uint8_t *d, size_t n, uint32_t now) {
  if (sTxN >= kTxN || n > kTxMax) {
    sSt.txLost++;
    return;
  }
  sTxHead = (uint8_t)((sTxHead + kTxN - 1) % kTxN);
  sTxN++;
  TxItem *t = &sTx[sTxHead];
  t->at = now;
  t->errCounted = false;
  t->slot = kRawSlot;
  t->len = (uint16_t)n;
  t->port = to.port;
  memcpy(t->peer, to.ip, 16);
  memcpy(t->local, to.local, 16);
  memcpy(t->data, d, n);
}

bool reseauEnvoyer(uint8_t place, const char *prefixe, size_t nPrefixe, const uint8_t *json, size_t nJson) {
  const size_t n = nPrefixe + nJson;
  if (place >= h1::kSlots || n > kChargeMax) return false;
  const h1::Session &s = sTable.slot(place);
  TxItem *t = txTail();
  if (!s.used || !t) return false;
  // La charge est posee apres la place de l'en-tete le plus long, scellee la,
  // puis ramenee contre l'en-tete (les deux zones se chevauchent : memmove).
  uint8_t *payload = t->data + h1::kHeaderMax;
  memcpy(payload, prefixe, nPrefixe);
  memcpy(payload + nPrefixe, json, nJson);
  char hdr[h1::kHeaderMax + 1];
  const size_t hn = sTable.seal(place, payload, n, hdr);
  if (!hn) return false;
  memmove(t->data + hn, payload, n);
  memcpy(t->data, hdr, hn);
  t->at = millis();
  t->errCounted = false;
  t->slot = place;
  t->len = (uint16_t)(hn + n);
  t->port = s.peer.port;
  memcpy(t->peer, s.peer.ip, 16);
  memcpy(t->local, s.peer.local, 16);
  sTxN++;
  return true;
}

uint8_t reseauPlacesLibres() { return sOpen ? (uint8_t)(kTxN - sTxN) : 0; }

// Remet a OpenThread les datagrammes en tete, sous verrou pris sans attente.
// Sous ce verrou : seulement des appels OpenThread.
static void txFlush() {
  // Heure lue ici, apres la mise en file : un datagramme date d'une
  // milliseconde plus tard que l'heure du debut de reseauTour() ne doit pas
  // paraitre vieux de 49 jours (comparaison signee).
  const uint32_t now = millis();
  while (sTxN && (int32_t)(now - sTx[sTxHead].at) > (int32_t)kTxStaleMs) {
    txPop();
    sSt.txLost++;
  }
  // Credit de debit (au plus 10 s rattrapees : pas de debordement du produit).
  const uint32_t elapsed = now - sTxCreditAt;
  sTxCreditAt = now;
  const uint32_t add = (elapsed > 10000 ? 10000 : elapsed) * kTxBytesPerS / 1000;
  sTxCredit = sTxCredit + add > kTxBurst ? kTxBurst : sTxCredit + add;
  if (!sTxN) return;
  if (!sOpen) {
    txClear();
    return;
  }
  auto paced = [](const TxItem &t) { return t.slot != kRawSlot && sTxCredit < t.len; };
  if (paced(sTx[sTxHead])) return;
  if (!reseauVerrouEssai()) return;
  otInstance *ot = esp_openthread_get_instance();
  for (uint8_t sent = 0; sTxN && sent < kTxPerTurn && !paced(sTx[sTxHead]); sent++) {
    TxItem &t = sTx[sTxHead];
    otBufferInfo bi;
    otMessageGetBufferInfo(ot, &bi);
    if (bi.mFreeBuffers != 0xFFFF) {
      if (bi.mFreeBuffers < sSt.bufMin) sSt.bufMin = bi.mFreeBuffers;
      // Premier tampon 76 octets utiles, les suivants 124 (benq, firmware.elf) :
      // len / 100 + 2 couvre toujours 1 + (len - 20) / 124 arrondi.
      const uint16_t need = (uint16_t)(t.len / 100 + 2);
      if (bi.mFreeBuffers < need + kBufReserve) break;  // au tour suivant
    }
    // Priorite basse : devant un manque de tampons, OpenThread evince nos
    // messages avant ceux de Matter, jamais l'inverse.
    otMessageSettings ms;
    ms.mLinkSecurityEnabled = true;
    ms.mPriority = OT_MESSAGE_PRIORITY_LOW;
    otMessage *m = otUdpNewMessage(ot, &ms);
    if (!m || otMessageAppend(m, t.data, t.len) != OT_ERROR_NONE) {
      if (m) otMessageFree(m);
      if (!t.errCounted) sSt.txErr++;  // nouvel essai au tour suivant, jusqu'a kTxStaleMs
      t.errCounted = true;
      break;
    }
    otMessageInfo mi;
    memset(&mi, 0, sizeof(mi));
    memcpy(mi.mPeerAddr.mFields.m8, t.peer, 16);
    mi.mPeerPort = t.port;
    // Reponse depuis l'adresse que l'app a visee (une socket UDP connectee ne
    // garde que celle-la), si elle est encore a nous ; sinon OpenThread choisit.
    otIp6Address local;
    memcpy(local.mFields.m8, t.local, 16);
    if (!otIp6IsAddressUnspecified(&local) && otIp6HasUnicastAddress(ot, &local)) mi.mSockAddr = local;
    mi.mSockPort = kPortReseau;
    if (otUdpSend(ot, &sSock, m, &mi) != OT_ERROR_NONE) {
      otMessageFree(m);  // refuse : il nous reste ; datagramme perdu
      if (!t.errCounted) sSt.txErr++;
      sSt.txLost++;
    } else {
      sSt.tx++;
      if (t.slot != kRawSlot) sTxCredit -= t.len;
    }
    txPop();
  }
  reseauVerrouLibere();
}

// ===========================================================================
//  Socket, nom d'hote (tache loop, verrou OT sans attente)
// ===========================================================================

static void rxClear() {
  if (!sRxQ) return;
  sSt.rxDropped += (uint32_t)uxQueueMessagesWaiting(sRxQ);  // lus nulle part : comptes
  xQueueReset(sRxQ);
}

// Ecart a Halo : ouvert des que la pile Thread existe, cle ou non, et jamais
// ferme. Halo ne l'ouvre qu'avec une cle ; sans, le port revient a lwIP, qui
// peut repondre « port injoignable ». Ici, un port tenu par OpenThread n'est
// jamais remis a lwIP (Udp::IsPortInUse, filtre de reception d'ESP-IDF) et
// OpenThread ne repond rien a un datagramme qu'il ignore : sans cle, silence.
static void openSocket(uint32_t now) {
  if (sOpen) return;
  if (sOpenTryAt && now - sOpenTryAt < kOpenRetryMs) return;
  sOpenTryAt = now ? now : 1;
  if (!reseauVerrouEssai()) return;
  otInstance *ot = esp_openthread_get_instance();
  memset(&sSock, 0, sizeof(sSock));
  if (otUdpOpen(ot, &sSock, onRx, nullptr) == OT_ERROR_NONE) {
    otSockAddr a;
    memset(&a, 0, sizeof(a));
    a.mPort = kPortReseau;
    // Sans UDP de plateforme dans ce build, l'interface ne change rien ;
    // interne si un jour il l'etait (pas de socket lwIP en double).
    if (otUdpBind(ot, &sSock, &a, OT_NETIF_THREAD_INTERNAL) == OT_ERROR_NONE) sOpen = true;
    else otUdpClose(ot, &sSock);
  }
  reseauVerrouLibere();
}

// Nom d'hote que Matter/CHIP enregistre par SRP (Halo : srp.nom du bloc ip).
// Seulement lettres, chiffres et '-' (un label DNS ; rien a echapper en
// JSON) ; autre chose : inconnu.
static void readHost(uint32_t now) {
  if (sHost.known && now - sHost.at < kHostReadMs) return;
  if (!reseauVerrouEssai()) return;
  const otSrpClientHostInfo *h = otSrpClientGetHostInfo(esp_openthread_get_instance());
  char name[sizeof(sHost.host)];
  bool ok = h && h->mName && h->mName[0];
  size_t n = 0;
  for (; ok && h->mName[n]; n++) {
    const char c = h->mName[n];
    const bool allowed = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-';
    if (!allowed || n + 1 >= sizeof(name)) ok = false;
    else name[n] = c;
  }
  reseauVerrouLibere();
  sHost.hostKnown = ok;
  if (ok) {
    name[n] = 0;
    memcpy(sHost.host, name, n + 1);
  }
  sHost.known = true;
  sHost.at = now;
}

bool reseauHote(char hote[64]) {
  if (!sHost.known || !sHost.hostKnown) return false;
  memcpy(hote, sHost.host, sizeof(sHost.host));
  return true;
}

// ===========================================================================
//  Datagrammes recus (tache loop)
// ===========================================================================

// Aleatoire de la plateforme pour nc et sid (tire seulement pour un SALUT
// admis). IDF ne garantit un vrai aleatoire qu'avec une radio Wi-Fi ou BT ;
// ici l'IEEE 802.15.4 : au pire un pseudo-aleatoire, suffisant pour des nonces
// qui ne doivent pas se repeter (la cle, elle, melange l'alea de l'app).
static void fillRandom(void *p, size_t n) { esp_fill_random(p, n); }

// Chaque session partie (oubliee, remplacee, cle changee) : ses datagrammes et
// ce qui lui etait garde tombent, sa place change de generation.
static void sessionsLeft(uint8_t mask) {
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (mask & (1u << i)) {
      txDropSlot(i);
      sGeneration[i]++;
      reseauSessionPartie(i);
    }
}

uint32_t reseauGeneration(uint8_t place) { return place < h1::kSlots ? sGeneration[place] : 0; }

bool reseauSessionActive(uint8_t place, uint32_t generation) {
  return place < h1::kSlots && sTable.slot(place).used && sGeneration[place] == generation;
}

static void handle(const RxItem &it, uint32_t now) {
  const h1::Parsed p = h1::parse(it.data, it.len);
  h1::Peer from;
  memcpy(from.ip, it.peer, 16);
  from.port = it.port;
  memcpy(from.local, it.local, 16);

  if (p.kind == h1::Kind::Salut) {
    // Sans place pour le DEFI, la poignee de main en cours (celle d'un autre
    // client peut-etre) n'est pas remplacee.
    if (sTxN >= kTxN) {
      sSt.rejected++;  // pas encore authentifie : ne compte pas comme datagramme perdu
      return;
    }
    char defi[h1::kDefiLen + 1];
    if (sTable.onSalut(p, fillRandom, from, now, defi) != h1::Verdict::Ok) {
      sSt.rejected++;
      return;
    }
    sSt.defis++;
    queueRaw(from, (const uint8_t *)defi, h1::kDefiLen, now);
    return;
  }

  uint8_t slot = 0;
  bool fresh = false;
  if (sTable.onData(p, from, now, &slot, &fresh) != h1::Verdict::Ok) {
    sSt.rejected++;  // forme, sid inconnu, MAC faux, rejeu, sans cle : silence
    return;
  }
  sSt.rx++;
  if (fresh) sessionsLeft((uint8_t)(1u << slot));  // session neuve, ou a la place d'une autre
  // Charge "<rid> <commande>" en ASCII imprimable : tout autre octet devient
  // '?', comme chez Halo (et un octet nul ne coupe jamais la ligne).
  char line[kRxMax + 1];
  const size_t n = p.payloadLen < kRxMax ? p.payloadLen : kRxMax;
  for (size_t i = 0; i < n; i++) {
    const uint8_t c = p.payload[i];
    line[i] = c >= 0x20 && c <= 0x7E ? (char)c : '?';
  }
  line[n] = 0;
  reseauRecu(slot, line);
}

// ===========================================================================
//  Cle (NVS sonde/cle)
// ===========================================================================

static void loadKey() {
  Preferences p;
  if (!p.begin(kNvsNs, true)) return;
  uint8_t k[h1::kKeyLen];
  // isKey() d'abord : interroger une cle absente logue une erreur NVS.
  const bool ok = p.isKey(kNvsKey) && p.getBytes(kNvsKey, k, sizeof(k)) == sizeof(k);
  p.end();
  if (ok) sTable.setKey(k);
  h1::wipe(k, sizeof(k));
  sKeyLoaded = sTable.hasKey();
}

// Toutes les sessions tombent (nouvelle cle, cle effacee) : leurs datagrammes aussi.
static void dropAll() {
  uint8_t mask = 0;
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (sTable.slot(i).used) mask |= (uint8_t)(1u << i);
  sessionsLeft(mask);
  txClear();
  rxClear();
}

ResultatCle reseauCleNouvelle(const uint8_t aleaApp[32], char cleHex[65], char empreinte[9]) {
  uint8_t card[32], key[h1::kKeyLen];
  esp_fill_random(card, sizeof(card));
  const h1::Part part = {card, sizeof(card)};
  char newKid[h1::kKidHex + 1];
  const bool made = h1::hmacSha256(aleaApp, 32, &part, 1, key) && h1::keyId(key, newKid);
  h1::wipe(card, sizeof(card));
  if (!made) {
    h1::wipe(key, sizeof(key));
    return ResultatCle::Crypto;
  }
  Preferences p;
  const bool written = p.begin(kNvsNs, false) && p.putBytes(kNvsKey, key, sizeof(key)) == sizeof(key);
  p.end();
  if (!written) {  // NVS : ecriture atomique par entree, l'ancienne cle reste
    h1::wipe(key, sizeof(key));
    return ResultatCle::Nvs;
  }
  dropAll();
  const bool loaded = sTable.setKey(key);
  sKeyLoaded = sTable.hasKey();
  h1::toHex(key, sizeof(key), cleHex);
  memcpy(empreinte, newKid, h1::kKidHex + 1);
  h1::wipe(key, sizeof(key));
  return loaded ? ResultatCle::Ok : ResultatCle::Chargement;
}

bool reseauCleEfface() {
  Preferences p;
  bool ok = p.begin(kNvsNs, false);
  if (ok && p.isKey(kNvsKey)) ok = p.remove(kNvsKey);
  p.end();
  // Meme si la NVS refuse : plus de cle en memoire, plus d'acces jusqu'au redemarrage.
  sKeyLoaded = false;
  dropAll();
  sTable.setKey(nullptr);
  return ok;
}

bool reseauEmpreinte(char empreinte[9]) {
  if (!sTable.hasKey()) return false;
  memcpy(empreinte, sTable.kid(), h1::kKidHex + 1);
  return true;
}

void reseauCompteurs(CompteursReseau *c) {
  c->ouvert = sOpen;
  c->sessions = sTable.established();
  c->provisoire = sTable.provisional().used;
  c->rx = sSt.rx;
  c->rejets = sSt.rejected;
  c->rxPerdus = sSt.rxTooBig + sSt.rxQueueFull + sSt.rxNoKey + sSt.rxDropped;
  c->defis = sSt.defis;
  c->tx = sSt.tx;
  c->txPerdus = sSt.txLost;
  c->txErreurs = sSt.txErr;
  c->tamponsMinConnu = sSt.bufMin != 0xFFFF;
  c->tamponsMin = sSt.bufMin;
}

// ===========================================================================
//  Cycle de vie
// ===========================================================================

void reseauDebut() {
  sRxQ = xQueueCreate(kRxN, sizeof(RxItem));
  loadKey();
}

void reseauTour() {
  const uint32_t now = millis();
  openSocket(now);
  // Au plus kRxN datagrammes par tour ; chaque commande tient en quelques ms
  // (un diag part et repond plus tard).
  for (uint8_t i = 0; i < kRxN && sRxQ && xQueueReceive(sRxQ, &sRxLoop, 0) == pdTRUE; i++) handle(sRxLoop, now);
  if (now - sExpireAt >= kExpireMs) {
    sExpireAt = now;
    sessionsLeft(sTable.expire(now));
  }
  txFlush();
  // Meme sans cle : l'app lit le nom d'hote par l'USB (bonjour) avant d'en regler une.
  readHost(now);
}
