// ===========================================================================
//  Sonde de maillage Thread, firmware 1.1.1 (spec de la sonde, sections 2 et
//  3 ; contrat de la 1.0.2 : FED, routeurs, acces reseau comme le pont Halo ;
//  1.0.3 : LED, retour allume apres oubli, refus de la cadence comptes ;
//  1.1.0 : ecoute des messages MLE et resolution d'adresse, spec de la sonde
//  tout-en-un, section 1 ; 1.1.1 : voyant du tronc commun, avec le pont
//  Halo, la carte Amaran et la sonde de Maillage Zigbee)
//
//  Noeud Matter sur Thread, en FED non eligible routeur (Full End Device) :
//  il recoit en permanence mais ne relaie rien, ne devient jamais routeur ni
//  chef, et ne devient jamais le parent de personne. En FED, OpenThread tient
//  la table des routeurs de la partition et apprend l'ExtMac de ceux qu'il
//  entend (commande routeurs). Maison lui donne les identifiants du reseau a
//  l'appairage par Bluetooth.
//
//  La pile OpenThread precompilee d'Arduino n'a pas de client de diagnostic :
//  la sonde fabrique elle-meme la requete DIAG_GET (CoAP POST d/dg, TLV
//  Type List) et l'envoie au port TMF 61631 du noeud vise. La reponse revient
//  sur le port CoAP de la sonde ; ses TLV partent en hexa, sans decodage :
//  c'est l'app qui decode. Jusqu'a 8 requetes en vol, reperees par leur id.
//
//  Depuis la 1.1.0, la sonde ecoute aussi les messages MLE de ses voisins a un
//  saut (ecoute.h) : elle les dechiffre avec la cle MLE, derivee de la cle
//  reseau, et garde, par routeur entendu, sa derniere Route64 brute (c'est
//  l'app qui la decode), son signal et l'age du dernier message. La cle reseau
//  ne sort jamais de la carte et n'est lue que le temps d'une derivation.
//
//  USB : une commande par ligne ; chaque reponse est une ligne machine,
//  RS (0x1E) + JSON compact en ASCII + LF, 4096 octets au plus.
//    bonjour                          produit, version, nom, MAC, appairage,
//                                     code d'appairage et charge du QR code
//                                     (toujours, meme dans Maison), nom
//                                     d'hote SRP (hote, null tant qu'inconnu)
//    nom <texte>                      change le nom et le garde : 1 a 32
//                                     caracteres (lettres ASCII, chiffres,
//                                     - _ .) ; repond par un bonjour a jour,
//                                     sinon erreur « syntaxe » (nom refuse)
//                                     ou « ecriture » (NVS qui refuse)
//    etat                             role, RLOC16, ExtMac, mode, eligible,
//                                     parent, partition...
//    voisins                          routeurs voisins a lien etabli (le
//                                     parent n'y est pas : voir etat)
//    routeurs                         table des routeurs d'OpenThread
//                                     (otThreadGetRouterInfo), entrees
//                                     allouees ; plusieurs lignes si besoin
//                                     ("suite":true sur toutes sauf la
//                                     derniere)
//    diag <cible> <t,t,...> <id> [ms] DIAG_GET vers <cible> : RLOC16 en 4 hexa
//                                     (adresse RLOC formee sur le prefixe du
//                                     reseau maille) ou adresse IPv6 (hexa,
//                                     ':' et '.' seulement) ; id et delai en
//                                     decimal, sinon « syntaxe » ; delai de
//                                     3 a 60 s, 45 s par defaut
//    annonces                         routeurs entendus (1.1.0) : une ligne
//                                     par routeur ("suite":true sauf sur la
//                                     derniere), ou une ligne "vide":true
//    resoudre <ipv6> <id>             resolution d'adresse (1.1.0) : demande
//                                     d'echo ICMPv6, puis le cache d'adresses
//                                     toutes les 250 ms, 15 s au plus ;
//                                     rloc16, repondu (l'appareil a repondu
//                                     a l'echo) et mleid, ou « introuvable »
//    cle                              empreinte de la cle d'acces reseau
//                                     (null sans cle), effacement_en_echec,
//                                     hote, compteurs udp (lignes_perdues et
//                                     refus_cadence compris), tas libre et
//                                     minimum
//    cle efface                       efface la cle : plus d'acces reseau
//    cle nouvelle <64 HEXA> <id>      nouvelle cle (alea de l'app), rendue
//                                     UNE fois, dans la reponse ; sans id :
//                                     erreur « syntaxe », jamais de cle
//    oubli                            efface la cle (cle_effacee dans la
//                                     reponse), desappaire la sonde et
//                                     redemarre ; elle revient allumee
//
//  Reseau (reseau.h) : UDP sur IPv6, port 5480, enveloppe H1 du pont Halo,
//  cle creee par l'USB. Charge d'un message : "<rid> <commande>" ; reponse :
//  "<rid> <ligne JSON>" (la ligne de l'USB sans RS ni LF), 1100 octets au
//  plus. Permis : bonjour (sans code ni QR code), etat, voisins, routeurs,
//  diag, annonces, resoudre ; le reste : erreur « refuse ». Un rid repete ne relance rien (les 8
//  dernieres reponses, dans la limite de 4096 octets par session) ; 20
//  commandes par seconde et par session au plus (au-dela, rien, et le refus
//  est compte : udp.refus_cadence de cle). Sans cle : silence total.
//
//  Dans Maison : un interrupteur « Sonde maillage », allume par defaut.
//  Eteint, la sonde refuse les requetes (erreur « suspendue »). Son etat est
//  garde d'un demarrage a l'autre, comme le nom de la sonde (« SONDE-T1 » par
//  defaut) : il suit la carte d'un Mac a l'autre. Apres un oubli, la sonde
//  revient allumee, comme a sa premiere mise en service.
//
//  LED de la carte (WS2812 sur IO8), a faible intensite (24/255 au plus), le
//  tronc commun de la 1.1.1 (voyant.h), du plus prioritaire au moins
//  prioritaire : arc-en-ciel pendant une identification (« Identifier » dans
//  Maison, au moins un tour de 2 s) ; deux eclairs verts rapides quand
//  l'interrupteur s'allume, un eclair orange d'une demi-seconde quand il
//  s'eteint ; bleu clignotant tant que la sonde n'est pas mise en service,
//  bleu lent (pulsation de 2 s) quand elle l'est mais n'est pas attachee au
//  reseau Thread ; deux eclairs verts a l'attachement ; un bref eclair orange
//  toutes les 5 s tant qu'elle est suspendue, aussi apres un redemarrage ;
//  sinon, attachee, une breve lueur blanche toutes les 10 s.
// ===========================================================================

#include <Arduino.h>
#include <Matter.h>
#include <Preferences.h>
#include <app/server/Server.h>
#include <esp_mac.h>
#include <esp_openthread.h>
#include <esp_openthread_lock.h>
#include <esp_system.h>
#include <openthread/coap.h>
#include <openthread/icmp6.h>
#include <openthread/ip6.h>
#include <openthread/link.h>
#include <openthread/message.h>
#include <openthread/thread.h>
#include <openthread/thread_ftd.h>
#include <stdarg.h>

#include <atomic>

#include "distant.h"
#include "ecoute.h"
#include "h1_proto.h"
#include "reseau.h"
#include "voyant.h"

static const char *const kVersion = "1.1.1";

// ---------------------------------------------------------------------------
//  FED des la creation de la pile Thread, jamais eligible routeur (repris de
//  l'essai FED du 29/09 (spec, section 8))
//
//  esp_matter::start : _InitThreadStack (esp_openthread_init cree l'instance
//  et relit sa NVS, puis CHIP relance Thread si le reseau est connu), puis
//  _SetThreadDeviceType(Router), puis _StartThreadTask. Avant cette tache,
//  OpenThread ne traite ni message MLE ni minuteur.
//
//  Trois enveloppes, -Wl,--wrap=<symbole> dans platformio.ini (une enveloppe
//  sans son drapeau, ou l'inverse, ne lie pas) :
//  1. esp_openthread_init : des la creation de l'instance, avant que Thread
//     soit relance, la sonde passe en FED (imposerFed).
//  2. _SetThreadDeviceType : toute demande devient FullEndDevice. CHIP appelle
//     alors otThreadSetRouterEligible(false) avant otThreadSetLinkMode(r+d)
//     (objdump). Puis le FED est impose de nouveau, avec n.
//  3. otThreadSetRouterEligible : toujours false, quel que soit l'appelant
//     (CHIP, CLI OpenThread, ce fichier). Dans les bibliotheques, seuls
//     _SetThreadDeviceType et la CLI y font reference, et OpenThread ne rend
//     jamais l'eligibilite de lui-meme (nm, objdump).
//  Non eligible, OpenThread refuse de devenir routeur ou chef, ne repond pas
//  aux Parent Request, refuse les Child ID Request et n'emet ni balise ni
//  annonce MLE.
// ---------------------------------------------------------------------------

extern "C" otError __real_otThreadSetRouterEligible(otInstance *instance, bool eligible);

extern "C" otError __wrap_otThreadSetRouterEligible(otInstance *instance, bool eligible) {
  (void)eligible;
  return __real_otThreadSetRouterEligible(instance, false);
}

// Non eligible d'abord (jamais FTD et eligible a la fois), puis mode rdn :
// reception permanente, appareil complet, donnees reseau completes. Verrou
// OT sans limite, comme CHIP a ces deux endroits : il est recursif, et la
// tache OpenThread n'existe pas encore. Aucun appel CHIP dessous.
static void imposerFed(otInstance *ot) {
  esp_openthread_lock_acquire(portMAX_DELAY);
  otThreadSetRouterEligible(ot, false);
  otLinkModeConfig mode = otThreadGetLinkMode(ot);
  if (!mode.mRxOnWhenIdle || !mode.mDeviceType || !mode.mNetworkData) {
    mode.mRxOnWhenIdle = true;
    mode.mDeviceType = true;
    mode.mNetworkData = true;
    otThreadSetLinkMode(ot, mode);
  }
  esp_openthread_lock_release();
}

extern "C" esp_err_t __real_esp_openthread_init(const esp_openthread_platform_config_t *config);

// Echec : ni instance ni verrou surs, on n'y touche pas.
extern "C" esp_err_t __wrap_esp_openthread_init(const esp_openthread_platform_config_t *config) {
  const esp_err_t e = __real_esp_openthread_init(config);
  if (e == ESP_OK) imposerFed(esp_openthread_get_instance());
  return e;
}

using ThreadDeviceType = chip::DeviceLayer::ConnectivityManager::ThreadDeviceType;

extern "C" CHIP_ERROR
__real__ZN4chip11DeviceLayer8Internal40GenericThreadStackManagerImpl_OpenThreadINS0_22ThreadStackManagerImplEE20_SetThreadDeviceTypeENS0_19ConnectivityManager16ThreadDeviceTypeE(
    void *self, ThreadDeviceType type);

extern "C" CHIP_ERROR
__wrap__ZN4chip11DeviceLayer8Internal40GenericThreadStackManagerImpl_OpenThreadINS0_22ThreadStackManagerImplEE20_SetThreadDeviceTypeENS0_19ConnectivityManager16ThreadDeviceTypeE(
    void *self, ThreadDeviceType type) {
  (void)type;
  const CHIP_ERROR e =
      __real__ZN4chip11DeviceLayer8Internal40GenericThreadStackManagerImpl_OpenThreadINS0_22ThreadStackManagerImplEE20_SetThreadDeviceTypeENS0_19ConnectivityManager16ThreadDeviceTypeE(
          self, chip::DeviceLayer::ConnectivityManager::kThreadDeviceType_FullEndDevice);
  // Echec (pas d'instance OpenThread) : rien a imposer.
  if (e == CHIP_NO_ERROR) imposerFed(esp_openthread_get_instance());
  return e;
}

// ---------------------------------------------------------------------------
//  Etat partage
// ---------------------------------------------------------------------------

static MatterOnOffPlugin sInterrupteur;  // « Sonde maillage »
// Etat de l'interrupteur, garde dans la NVS comme dans l'exemple
// MatterOnOffPlugin d'Arduino-ESP32 : relu au demarrage, allume par defaut.
static Preferences sPreferences;
static const char *const kCleInterrupteur = "interrupteur";
// Pose par demarrerMatter(), puis par le rappel de l'interrupteur
// (surInterrupteur) : dans la tache CHIP quand Maison le change, dans celle
// de loop() pour updateAccessory() au demarrage et pour setOnOff() d'oubli.
// Lu par loop(), qui en tire aussi la LED.
static std::atomic<bool> sSuspendue{false};
// Identification de l'interrupteur (1.1.1), posee par surIdentification dans
// la tache CHIP, lue par loop() (voyantTour) : session Identify (IdentifyTime,
// finie par un STOP de la pile), ou fin datee d'un TriggerEffect (millis,
// 0 = aucun), que la pile ne termine jamais. Seule la tache CHIP pose une fin ;
// loop() ne fait qu'effacer une fin echue, par echange compare.
static std::atomic<bool> sIdentSession{false};
static std::atomic<uint32_t> sIdentFinEffet{0};
static bool sThreadPret = false;  // pile Thread creee par Matter.begin()
static otError enregistrerIcmp6(otInstance *ot);  // gestionnaire d'echo de resoudre (plus bas)
static char sMac[13] = "?";
// Nom de la sonde, garde dans la NVS a cote de l'interrupteur (commande `nom`).
static const char *const kCleNom = "nom";
static const char *const kNomDefaut = "SONDE-T1";
static constexpr size_t kNomMax = 32;
static char sNom[kNomMax + 1] = "SONDE-T1";

// 1 a 32 caracteres parmi les lettres ASCII, les chiffres, « - », « _ » et « . » :
// rien a echapper dans le JSON.
static bool nomValide(const char *s) {
  const size_t n = strlen(s);
  if (n == 0 || n > kNomMax) return false;
  for (size_t i = 0; i < n; i++) {
    const char c = s[i];
    const bool permis = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
                        c == '_' || c == '.';
    if (!permis) return false;
  }
  return true;
}

// Verrou OpenThread, delai total borne. REGLE (benq) : sous ce verrou, aucun
// appel Matter/CHIP ; la tache CHIP prend le verrou OT en tenant le sien.
static bool verrouOt(uint32_t ms) { return sThreadPret && esp_openthread_lock_acquire(pdMS_TO_TICKS(ms / 2)); }
static void libereOt() { esp_openthread_lock_release(); }

// Pour reseau.cpp : verrou pris SANS attente (emission, socket, nom d'hote).
bool reseauVerrouEssai() { return verrouOt(0); }
void reseauVerrouLibere() { libereOt(); }

// Pour ecoute.cpp (1.1.0) : la sequence de cle courante de la pile, et la cle
// reseau, le temps d'en deriver les cles MLE. La copie d'OpenThread est
// effacee ici ; l'appelant efface la sienne. Jamais imprimee, jamais rendue
// par une commande.
static bool lireSequenceCle(uint32_t *courante) {
  if (!verrouOt(50)) return false;
  *courante = otThreadGetKeySequenceCounter(esp_openthread_get_instance());
  libereOt();
  return true;
}

static bool lireCleReseau(uint8_t cle[mle::kCle]) {
  if (!verrouOt(50)) return false;
  otNetworkKey k;
  otThreadGetNetworkKey(esp_openthread_get_instance(), &k);
  libereOt();
  memcpy(cle, k.m8, mle::kCle);
  h1::wipe(&k, sizeof(k));
  return true;
}

// ---------------------------------------------------------------------------
//  Ligne machine : RS + JSON + LF, 4096 octets au plus sur l'USB
// ---------------------------------------------------------------------------

// Destination des lignes : l'USB, ou une session reseau (place, generation de
// la place, rid de la requete). Posee le temps d'une commande recue par le
// reseau, et pour la reponse d'un diag qui en venait.
struct Sortie {
  bool reseau = false;
  uint8_t place = 0;
  uint32_t generation = 0;
  uint32_t rid = 0;
};
static Sortie sSortie;

// Reponses gardees de chaque session reseau (un rid repete ne relance rien),
// et cadence de chaque session (20 commandes par seconde au plus).
static distant::Gardees sGardees[kPlacesReseau];
static distant::Cadence sCadences[kPlacesReseau];
// Lignes pour le reseau que la file d'emission n'a pas prises (pleine) :
// perdues en route, mais gardees pour un rid repete (Halo : json_perdus).
static uint32_t sLignesPerdues = 0;
// Commandes du reseau que la cadence a refusees (plus de 20 dans la seconde),
// toutes sessions confondues, depuis le demarrage : pour mesurer la cadence
// de l'app (18 par seconde).
static uint32_t sRefusCadence = 0;

static char sLigne[4096];
static size_t sLong = 0;
static bool sTropLong = false;
static size_t sLimite = sizeof(sLigne);

// Taille de sLigne permise pour la destination en cours (RS, LF et le 0
// final de vsnprintf compris) : 4096 sur l'USB ; sur le reseau, la charge
// "<rid> <ligne JSON>" tient en kChargeMax octets (JSON <= sLimite - 3).
static size_t limiteSortie() {
  if (!sSortie.reseau) return sizeof(sLigne);
  char rid[distant::kRidMax + 1];
  return kChargeMax - (distant::texteRid(sSortie.rid, rid) + 1) + 3;
}

static void ajoute(const char *fmt, ...) {
  if (sTropLong) return;
  va_list ap;
  va_start(ap, fmt);
  const size_t reste = sLimite - sLong - 2;  // place pour '}' et LF
  const int n = vsnprintf(sLigne + sLong, reste, fmt, ap);
  va_end(ap);
  if (n < 0 || (size_t)n >= reste) {
    sTropLong = true;
    return;
  }
  sLong += (size_t)n;
}

static void debut(const char *type) {
  sLong = 0;
  sTropLong = false;
  sLimite = limiteSortie();
  sLigne[sLong++] = 0x1E;
  ajoute("{\"v\":1,\"t\":\"%s\"", type);
}

// Ligne pour une session reseau : gardee (pour un rid repete), puis envoyee
// "<rid> <ligne JSON>", sans RS ni LF. Session partie entre-temps : rien.
// File d'emission pleine : perdue, mais gardee, l'app renverra le rid.
static void sortieReseau(const uint8_t *json, size_t n) {
  if (!reseauSessionActive(sSortie.place, sSortie.generation)) return;
  sGardees[sSortie.place].ajouter(json, n);
  char prefixe[distant::kRidMax + 2];
  size_t np = distant::texteRid(sSortie.rid, prefixe);
  prefixe[np++] = ' ';
  if (!reseauEnvoyer(sSortie.place, prefixe, np, json, n)) sLignesPerdues++;
}

static void fin() {
  if (sTropLong) {
    debut("erreur");
    ajoute(",\"erreur\":\"ligne trop longue\"");
  }
  sLigne[sLong++] = '}';
  sLigne[sLong++] = '\n';
  if (sSortie.reseau) sortieReseau((const uint8_t *)sLigne + 1, sLong - 2);
  else Serial.write((const uint8_t *)sLigne, sLong);
}

static void hexa(const char *cle, const uint8_t *o, size_t n) {
  ajoute(",\"%s\":\"", cle);
  for (size_t i = 0; i < n && !sTropLong; i++) ajoute("%02X", o[i]);
  ajoute("\"");
}

static void repondreErreur(const char *erreur) {
  debut("erreur");
  ajoute(",\"erreur\":\"%s\"", erreur);
  fin();
}

// Nom d'hote SRP, sans .local ; null tant qu'il n'est pas connu.
static void ajouteHote() {
  char hote[64];
  if (reseauHote(hote)) ajoute(",\"hote\":\"%s\"", hote);
  else ajoute(",\"hote\":null");
}

// ---------------------------------------------------------------------------
//  Matter
// ---------------------------------------------------------------------------

// Maison change l'interrupteur, updateAccessory() applique l'etat relu au
// demarrage, ou oubli le rallume (setOnOff) : l'etat est garde pour le
// prochain demarrage. Jamais la LED ici : loop() voit sSuspendue changer et
// la pilote (voyantTour).
static bool surInterrupteur(bool allume) {
  sSuspendue = !allume;
  sPreferences.putBool(kCleInterrupteur, allume);
  return true;
}

// « Identifier » dans Maison (cluster Identify de l'interrupteur), dans la
// tache CHIP : ne fait que poser l'etat, comme le pont Halo (onIdentify).
// La requete est remplie par la bibliotheque juste avant ce rappel.
static_assert(effetIdent::kBlink == MatterIdentifyRequest::BLINK &&
                  effetIdent::kBreathe == MatterIdentifyRequest::BREATHE &&
                  effetIdent::kOkay == MatterIdentifyRequest::OKAY &&
                  effetIdent::kChangementCanal == MatterIdentifyRequest::CHANNEL_CHANGE &&
                  effetIdent::kFinish == MatterIdentifyRequest::FINISH &&
                  effetIdent::kStop == MatterIdentifyRequest::STOP,
              "effets d'identification : les valeurs de la bibliotheque Matter");
static bool surIdentification(bool actif) {
  const MatterIdentifyRequest r = sInterrupteur.getIdentifyRequest();
  if (r.fromTriggerEffect)
    sIdentFinEffet.store(effetIdent::finApres(sIdentFinEffet.load(), r.effectId, millis()));
  else
    sIdentSession = actif;
  return true;
}

static void demarrerMatter() {
  uint8_t mac[8] = {};
  if (esp_read_mac(mac, ESP_MAC_BASE) == ESP_OK)
    snprintf(sMac, sizeof(sMac), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  // Avant le premier begin() d'accessoire : c'est lui qui cree le noeud.
  if (!Matter.selectNetwork(MATTER_NETWORK_THREAD)) Serial.println("!! selectNetwork(THREAD) refuse");
  // Etat garde de l'interrupteur (allume au premier demarrage) : la sonde reste
  // suspendue apres un redemarrage si « Sonde maillage » est eteint dans Maison.
  sPreferences.begin("sonde", false);
  // Nom garde (« SONDE-T1 » au premier demarrage, ou s'il etait illisible).
  const String nom = sPreferences.getString(kCleNom, kNomDefaut);
  if (nomValide(nom.c_str())) snprintf(sNom, sizeof(sNom), "%s", nom.c_str());
  const bool allume = sPreferences.getBool(kCleInterrupteur, true);
  sSuspendue = !allume;
  sInterrupteur.begin(allume);
  // onChange, et non onChangeOnOff : updateAccessory() n'appelle que ce rappel-la.
  sInterrupteur.onChange(surInterrupteur);
  sInterrupteur.onIdentify(surIdentification);
  char serie[20];
  snprintf(serie, sizeof(serie), "SONDE-%s", sMac);
  Matter.setVendorName("Maillage Thread");
  Matter.setProductName("Sonde maillage");
  Matter.setDeviceName("Sonde maillage");
  Matter.setSerialNumber(serie);
  Matter.begin();
  sThreadPret = chip::DeviceLayer::ThreadStackMgrImpl().OTInstance() != nullptr;
  if (!sThreadPret) Serial.println("!! pile Thread absente");
  // Ecoute des messages MLE (1.1.0) : le rappel des trames, des que la pile
  // existe. Verrou OT sans limite, comme imposerFed ; aucun appel CHIP dessous.
  if (sThreadPret) {
    esp_openthread_lock_acquire(portMAX_DELAY);
    ecoute::demarrer(esp_openthread_get_instance(), {lireSequenceCle, lireCleReseau});
    // Reponses d'echo de resoudre (1.1.1) : une fois, la pile creee.
    const otError eIcmp = enregistrerIcmp6(esp_openthread_get_instance());
    esp_openthread_lock_release();
    if (eIcmp != OT_ERROR_NONE) Serial.println("!! gestionnaire ICMPv6 refuse");
  }
  // Comme l'exemple officiel : l'etat relu passe par le rappel une fois Matter demarre.
  sInterrupteur.updateAccessory();
}

// ---------------------------------------------------------------------------
//  Commandes simples
// ---------------------------------------------------------------------------

// Chaine JSON, ou null si elle est vide (code que Matter n'a pas pu former).
static void chaineOuNull(const char *cle, const String &valeur) {
  if (valeur.length()) {
    ajoute(",\"%s\":\"%s\"", cle, valeur.c_str());
  } else {
    ajoute(",\"%s\":null", cle);
  }
}

// Code d'appairage et QR code toujours sur l'USB, appairee ou non : Maillage
// Thread les montre dans ses Reglages (Matter les forme une fois, au
// demarrage). A distance, jamais : null, comme le pont Halo (le trafic H1
// n'est pas chiffre ; qui les lirait pourrait ajouter la sonde a son propre
// controleur des que l'appairage est ouvert).
static void cmdBonjour() {
  const bool appairee = Matter.isDeviceCommissioned();
  String code, qr;
  if (!sSortie.reseau) {
    // L'URL du QR code porte la charge utile « MT:... » apres « data= ».
    const String url = Matter.getOnboardingQRCodeUrl();
    const int i = url.indexOf("data=");
    qr = i >= 0 ? url.substring(i + 5) : url;
    qr.replace("%3A", ":");
    code = Matter.getManualPairingCode();
  }
  debut("bonjour");
  ajoute(",\"produit\":\"sonde-maillage\",\"version\":\"%s\",\"nom\":\"%s\",\"mac\":\"%s\",\"appairee\":%s", kVersion,
         sNom, sMac, appairee ? "true" : "false");
  chaineOuNull("code", code);
  chaineOuNull("qr", qr);
  ajouteHote();
  fin();
}

// nom <texte> : change le nom et le garde ; repond par un bonjour a jour. Nom
// refuse : erreur « syntaxe » ; NVS qui refuse l'ecriture : « ecriture ».
// USB seulement (la liste blanche la refuse deja au reseau).
static void cmdNom(char *texte) {
  if (sSortie.reseau) return repondreErreur("refuse");
  while (*texte == ' ') texte++;
  size_t n = strlen(texte);
  while (n > 0 && texte[n - 1] == ' ') texte[--n] = 0;
  const char *erreur = nullptr;
  if (!nomValide(texte)) {
    erreur = "syntaxe";
  } else if (sPreferences.putString(kCleNom, texte) == 0) {
    erreur = "ecriture";
  }
  if (erreur) {
    debut("erreur");
    ajoute(",\"erreur\":\"%s\"", erreur);
    fin();
    return;
  }
  snprintf(sNom, sizeof(sNom), "%s", texte);
  cmdBonjour();
}

static void cmdEtat() {
  debut("etat");
  if (!verrouOt(200)) {
    ajoute(",\"erreur\":\"occupee\"");
    fin();
    return;
  }
  otInstance *ot = esp_openthread_get_instance();
  const otDeviceRole role = otThreadGetDeviceRole(ot);
  ajoute(",\"role\":\"%s\",\"rloc16\":\"%04X\"", otThreadDeviceRoleToString(role), otThreadGetRloc16(ot));
  const otExtAddress *ext = otLinkGetExtendedAddress(ot);
  if (ext) hexa("ext", ext->m8, sizeof(ext->m8));
  const otLinkModeConfig mode = otThreadGetLinkMode(ot);
  ajoute(",\"mode\":\"%s%s%s\"", mode.mRxOnWhenIdle ? "r" : "", mode.mDeviceType ? "d" : "", mode.mNetworkData ? "n" : "");
  // Routeur ou chef permis (FTD, eligible, politique de securite) : false attendu.
  ajoute(",\"eligible\":%s", otThreadIsRouterEligible(ot) ? "true" : "false");
  otRouterInfo parent;
  if (role == OT_DEVICE_ROLE_CHILD && otThreadGetParentInfo(ot, &parent) == OT_ERROR_NONE) {
    int8_t moyen = 0;
    otThreadGetParentAverageRssi(ot, &moyen);
    ajoute(",\"parent\":{\"rloc16\":\"%04X\"", parent.mRloc16);
    hexa("ext", parent.mExtAddress.m8, sizeof(parent.mExtAddress.m8));
    ajoute(",\"lqIn\":%u,\"lqOut\":%u,\"rssi\":%d}", parent.mLinkQualityIn, parent.mLinkQualityOut, moyen);
  } else {
    ajoute(",\"parent\":null");
  }
  const bool attachee = role == OT_DEVICE_ROLE_CHILD || role == OT_DEVICE_ROLE_ROUTER || role == OT_DEVICE_ROLE_LEADER;
  if (attachee) {
    ajoute(",\"partition\":\"%08lX\",\"chef\":%u", (unsigned long)otThreadGetPartitionId(ot),
           otThreadGetLeaderRouterId(ot));
  } else {
    ajoute(",\"partition\":null,\"chef\":null");
  }
  ajoute(",\"canal\":%u", otLinkGetChannel(ot));
  const otMeshLocalPrefix *ml = otThreadGetMeshLocalPrefix(ot);
  if (ml) hexa("prefixeMaille", ml->m8, sizeof(ml->m8));
  const otExtendedPanId *xp = otThreadGetExtendedPanId(ot);
  if (xp) hexa("xp", xp->m8, sizeof(xp->m8));
  libereOt();
  ajoute(",\"suspendue\":%s", sSuspendue ? "true" : "false");
  // Ecoute des messages MLE (1.1.0), depuis le demarrage.
  const ecoute::Compteurs c = ecoute::compteurs();
  ajoute(",\"ecoute\":{\"trames\":%lu,\"mle\":%lu,\"echecs\":%lu,\"file_pleine\":%lu}", (unsigned long)c.trames,
         (unsigned long)c.mle, (unsigned long)c.echecs, (unsigned long)c.filePleine);
  fin();
}

static void cmdVoisins() {
  debut("voisins");
  if (!verrouOt(200)) {
    ajoute(",\"erreur\":\"occupee\"");
    fin();
    return;
  }
  otInstance *ot = esp_openthread_get_instance();
  otNeighborInfoIterator it = OT_NEIGHBOR_INFO_ITERATOR_INIT;
  otNeighborInfo v;
  ajoute(",\"liste\":[");
  bool premier = true;
  while (otThreadGetNextNeighborInfo(ot, &it, &v) == OT_ERROR_NONE) {
    ajoute("%s{\"rloc16\":\"%04X\"", premier ? "" : ",", v.mRloc16);
    hexa("ext", v.mExtAddress.m8, sizeof(v.mExtAddress.m8));
    ajoute(",\"rssi\":%d,\"lqi\":%u,\"routeur\":%s}", v.mAverageRssi, v.mLinkQualityIn, v.mIsChild ? "false" : "true");
    premier = false;
  }
  ajoute("]");
  libereOt();
  fin();
}

// ---------------------------------------------------------------------------
//  routeurs : table des routeurs d'OpenThread (repris de l'essai FED)
// ---------------------------------------------------------------------------

// Une entree allouee d'otThreadGetRouterInfo, copiee sous le verrou OT pour
// ecrire les lignes hors verrou.
struct Routeur {
  uint8_t id;
  uint16_t rloc16;
  uint8_t ext[8];
  uint8_t lqIn, lqOut, age;
  bool lien;
};
static constexpr size_t kRouteursMax = 64;  // identifiants 0 a 62
static Routeur sRouteurs[kRouteursMax];

// Une entree de `liste`, precedee d'une virgule sauf en tete de liste.
// ExtMac nulle (OpenThread ne l'a pas relevee pour ce routeur) : null.
static int formaterRouteur(char *b, size_t taille, const Routeur &r, bool premier) {
  bool nulle = true;
  for (uint8_t o : r.ext) nulle = nulle && o == 0;
  char ext[19] = "null";
  if (!nulle)
    snprintf(ext, sizeof(ext), "\"%02X%02X%02X%02X%02X%02X%02X%02X\"", r.ext[0], r.ext[1], r.ext[2], r.ext[3],
             r.ext[4], r.ext[5], r.ext[6], r.ext[7]);
  return snprintf(b, taille, "%s{\"id\":%u,\"rloc16\":\"%04X\",\"ext\":%s,\"lqIn\":%u,\"lqOut\":%u,\"age\":%u,\"lien\":%s}",
                  premier ? "" : ",", (unsigned)r.id, (unsigned)r.rloc16, ext, (unsigned)r.lqIn, (unsigned)r.lqOut,
                  (unsigned)r.age, r.lien ? "true" : "false");
}

// Entrees allouees, de l'identifiant 0 a otThreadGetMaxRouterId(). Une ligne,
// ou plusieurs si elle depasserait la taille permise (4096 octets sur l'USB,
// une charge de 1100 octets sur le reseau) : "suite":true sur chaque ligne
// sauf la derniere ("suite":false), coupees entre deux entrees.
static void cmdRouteurs() {
  if (!verrouOt(200)) {
    debut("routeurs");
    ajoute(",\"erreur\":\"occupee\"");
    fin();
    return;
  }
  otInstance *ot = esp_openthread_get_instance();
  const uint8_t maxId = otThreadGetMaxRouterId(ot);
  size_t n = 0;
  for (uint16_t id = 0; id <= maxId && n < kRouteursMax; id++) {
    otRouterInfo info;
    if (otThreadGetRouterInfo(ot, id, &info) != OT_ERROR_NONE || !info.mAllocated) continue;
    Routeur &r = sRouteurs[n++];
    r.id = info.mRouterId;
    r.rloc16 = info.mRloc16;
    memcpy(r.ext, info.mExtAddress.m8, sizeof(r.ext));
    r.lqIn = info.mLinkQualityIn;
    r.lqOut = info.mLinkQualityOut;
    r.age = info.mAge;
    r.lien = info.mLinkEstablished;
  }
  libereOt();

  static const char kFinDerniere[] = "],\"suite\":false";  // la plus longue des deux fins
  debut("routeurs");
  ajoute(",\"liste\":[");
  bool premier = true;
  for (size_t i = 0; i < n; i++) {
    char entree[160];
    int l = formaterRouteur(entree, sizeof(entree), sRouteurs[i], premier);
    // ajoute() reussit si sLong + longueur + 3 <= sLimite (NUL, '}' et LF) :
    // l'entree puis la fin de ligne doivent encore tenir, sinon ligne suivante.
    if (!premier && sLong + (size_t)l + (sizeof(kFinDerniere) - 1) + 3 > sLimite) {
      ajoute("],\"suite\":true");
      fin();
      debut("routeurs");
      ajoute(",\"liste\":[");
      premier = true;
      l = formaterRouteur(entree, sizeof(entree), sRouteurs[i], premier);
    }
    ajoute("%s", entree);
    premier = false;
  }
  ajoute("%s", kFinDerniere);
  fin();
}

// ---------------------------------------------------------------------------
//  DIAG_GET par CoAP, 8 en vol
// ---------------------------------------------------------------------------

static constexpr uint16_t kPortTmf = 61631;
static constexpr uint8_t kTlvTypeList = 18;
static constexpr size_t kTlvMax = 32;
static constexpr size_t kEnVol = 8;
static constexpr uint32_t kDelaiDefaut = 45000, kDelaiMin = 3000, kDelaiMax = 60000;

static bool sCoapDemarre = false;

// Un emplacement par requete en vol. loop() le remplit (id, cible, sortie,
// debut), pose finie a faux puis enVol, sous le verrou OT, avant l'envoi. Le
// rappel CoAP (tache OpenThread) ecrit la reponse (fin, erreur, code, charge,
// longueur, tronquee), puis pose finie. loop() ne lit la reponse qu'apres
// avoir vu finie, puis libere l'emplacement (finie et enVol a faux). finie
// est atomique : son ecriture ne passe pas avant celles de la reponse, ce que
// volatile ne garantissait pas. enVol ne quitte pas la tache de loop().
struct Requete {
  std::atomic<bool> enVol;
  std::atomic<bool> finie;
  uint32_t id;
  char cible[48];
  uint32_t debutMs, finMs;
  otError erreur;
  uint8_t code;  // code CoAP de la reponse
  uint8_t charge[1024];
  uint16_t longueur;
  bool tronquee;
  Sortie sortie;  // qui attend la reponse : l'USB, ou une session reseau et son rid
};
static Requete sRequetes[kEnVol];

static void surReponse(void *contexte, otMessage *msg, const otMessageInfo *, otError erreur) {
  Requete &r = sRequetes[(uintptr_t)contexte];
  r.finMs = millis();
  r.erreur = erreur;
  r.longueur = 0;
  r.tronquee = false;
  if (erreur == OT_ERROR_NONE && msg) {
    r.code = (uint8_t)otCoapMessageGetCode(msg);
    const uint16_t debutCharge = otMessageGetOffset(msg);
    const uint16_t total = otMessageGetLength(msg) - debutCharge;
    const uint16_t n = total > sizeof(r.charge) ? sizeof(r.charge) : total;
    r.longueur = otMessageRead(msg, debutCharge, r.charge, n);
    r.tronquee = n < total;
  }
  r.finie = true;
}

// Reprises CoAP reglees pour que l'echec tombe au bout du delai demande
// (distant::reprisesDiag), facteur aleatoire de 1.
static otCoapTxParameters parametres(uint32_t delaiMs) {
  const distant::Reprises r = distant::reprisesDiag(delaiMs);
  otCoapTxParameters p = {r.accuseMs, 1, 1, r.reprises};
  return p;
}

static void repondreDiagErreur(uint32_t id, const char *cible, const char *erreur) {
  debut("diag");
  ajoute(",\"id\":%lu,\"cible\":\"%s\",\"ok\":false,\"erreur\":\"%s\"", (unsigned long)id, cible, erreur);
  fin();
}

// Cible : RLOC16 en 4 hexa, ou adresse IPv6 (hexa, ':', et '.' d'une IPv4
// incluse). Rien d'autre : la cible repart telle quelle dans la ligne JSON
// (sans echappement), qui doit rester valide, sur l'USB comme a distance.
static const char kCaracteresCible[] = "0123456789abcdefABCDEF:.";

// diag <cible> <t,t,...> <id> [<delai ms>]. id et delai en decimal
// (distant::lireEntier), sinon « syntaxe », avec l'id s'il a pu etre lu (0
// sinon).
static void cmdDiag(char *args) {
  char *cible = strtok(args, " ");
  char *liste = strtok(nullptr, " ");
  char *idTexte = strtok(nullptr, " ");
  char *delaiTexte = strtok(nullptr, " ");
  uint32_t id = 0, delai = kDelaiDefaut;
  const bool idLu = idTexte && distant::lireEntier(idTexte, &id);
  const bool delaiLu = !delaiTexte || distant::lireEntier(delaiTexte, &delai);
  if (!cible || !liste || !idLu || !delaiLu || strlen(cible) >= sizeof(sRequetes[0].cible) ||
      strspn(cible, kCaracteresCible) != strlen(cible)) {
    repondreDiagErreur(id, "", "syntaxe");
    return;
  }
  if (sSuspendue) return repondreDiagErreur(id, cible, "suspendue");
  if (delai < kDelaiMin) delai = kDelaiMin;
  if (delai > kDelaiMax) delai = kDelaiMax;

  size_t libre = kEnVol;
  for (size_t i = 0; i < kEnVol; i++)
    if (!sRequetes[i].enVol) {
      libre = i;
      break;
    }
  if (libre == kEnVol) return repondreDiagErreur(id, cible, "occupee");

  uint8_t types[kTlvMax];
  size_t nTypes = 0;
  for (char *t = strtok(liste, ","); t && nTypes < kTlvMax; t = strtok(nullptr, ",")) {
    const long v = strtol(t, nullptr, 10);
    if (v < 0 || v > 255) return repondreDiagErreur(id, cible, "syntaxe");
    types[nTypes++] = (uint8_t)v;
  }
  if (nTypes == 0) return repondreDiagErreur(id, cible, "syntaxe");

  if (!verrouOt(500)) return repondreDiagErreur(id, cible, "occupee");
  otInstance *ot = esp_openthread_get_instance();
  otIp6Address adresse;
  bool adresseOk = false;
  if (strlen(cible) == 4 && strspn(cible, "0123456789abcdefABCDEF") == 4) {
    // Adresse RLOC : prefixe du reseau maille + 0000:00ff:fe00:<rloc16>.
    const otMeshLocalPrefix *ml = otThreadGetMeshLocalPrefix(ot);
    if (ml) {
      const uint16_t rloc16 = (uint16_t)strtoul(cible, nullptr, 16);
      memset(&adresse, 0, sizeof(adresse));
      memcpy(adresse.mFields.m8, ml->m8, 8);
      adresse.mFields.m8[11] = 0xFF;
      adresse.mFields.m8[12] = 0xFE;
      adresse.mFields.m8[14] = (uint8_t)(rloc16 >> 8);
      adresse.mFields.m8[15] = (uint8_t)rloc16;
      adresseOk = true;
    }
  } else {
    adresseOk = otIp6AddressFromString(cible, &adresse) == OT_ERROR_NONE;
  }
  if (!adresseOk) {
    libereOt();
    return repondreDiagErreur(id, cible, "cible");
  }
  if (!sCoapDemarre) sCoapDemarre = otCoapStart(ot, OT_DEFAULT_COAP_PORT) == OT_ERROR_NONE;
  otMessage *msg = sCoapDemarre ? otCoapNewMessage(ot, nullptr) : nullptr;
  otError e = msg ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
  if (msg) {
    otCoapMessageInit(msg, OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_POST);
    otCoapMessageGenerateToken(msg, OT_COAP_DEFAULT_TOKEN_LENGTH);
    e = otCoapMessageAppendUriPathOptions(msg, "d/dg");
    if (e == OT_ERROR_NONE) e = otCoapMessageSetPayloadMarker(msg);
    const uint8_t entete[2] = {kTlvTypeList, (uint8_t)nTypes};
    if (e == OT_ERROR_NONE) e = otMessageAppend(msg, entete, sizeof(entete));
    if (e == OT_ERROR_NONE) e = otMessageAppend(msg, types, (uint16_t)nTypes);
  }
  if (e == OT_ERROR_NONE) {
    otMessageInfo info;
    memset(&info, 0, sizeof(info));
    info.mPeerAddr = adresse;
    info.mPeerPort = kPortTmf;
    const otCoapTxParameters p = parametres(delai);
    Requete &r = sRequetes[libre];
    r.id = id;
    snprintf(r.cible, sizeof(r.cible), "%s", cible);
    r.sortie = sSortie;
    r.debutMs = millis();
    r.finie = false;
    r.enVol = true;
    e = otCoapSendRequestWithParameters(ot, msg, &info, surReponse, (void *)(uintptr_t)libre, &p);
    if (e != OT_ERROR_NONE) r.enVol = false;
  }
  if (e != OT_ERROR_NONE && msg) otMessageFree(msg);
  libereOt();
  if (e != OT_ERROR_NONE) {
    char texte[24];
    snprintf(texte, sizeof(texte), "envoi %s", otThreadErrorToString(e));
    repondreDiagErreur(id, cible, texte);
  }
}

static void imprimerDiag(const Requete &r) {
  debut("diag");
  ajoute(",\"id\":%lu,\"cible\":\"%s\",\"ms\":%lu", (unsigned long)r.id, r.cible, (unsigned long)(r.finMs - r.debutMs));
  if (r.erreur == OT_ERROR_NONE) {
    ajoute(",\"ok\":true,\"code\":\"%u.%02u\"", r.code >> 5, r.code & 0x1F);
    hexa("tlv", r.charge, r.longueur);
    if (r.tronquee) ajoute(",\"tronquee\":true");
  } else {
    ajoute(",\"ok\":false,\"erreur\":\"%s\"",
           r.erreur == OT_ERROR_RESPONSE_TIMEOUT ? "delai" : otThreadErrorToString(r.erreur));
  }
  // A distance, une reponse qui ne tient pas dans un datagramme : trop_long.
  if (sTropLong && sSortie.reseau) {
    debut("diag");
    ajoute(",\"id\":%lu,\"cible\":\"%s\",\"ok\":false,\"erreur\":\"trop_long\"", (unsigned long)r.id, r.cible);
  }
  fin();
}

// Reponses arrivees. Pour une session reseau : partie entre-temps, la reponse
// tombe ; sinon elle attend une place dans la file d'emission (jamais perdue
// faute de place), puis elle est gardee pour un rid repete.
static void diagsFinis() {
  for (Requete &r : sRequetes) {
    if (!r.enVol || !r.finie) continue;
    if (r.sortie.reseau) {
      if (!reseauSessionActive(r.sortie.place, r.sortie.generation)) {
        r.finie = false;
        r.enVol = false;
        continue;
      }
      if (!reseauPlacesLibres()) continue;
      sGardees[r.sortie.place].commencer(r.sortie.rid);
    }
    sSortie = r.sortie;
    imprimerDiag(r);
    sSortie = Sortie();
    if (r.sortie.reseau) sGardees[r.sortie.place].terminer();
    r.finie = false;
    r.enVol = false;
  }
}

// ---------------------------------------------------------------------------
//  annonces : routeurs entendus (1.1.0, ecoute.h)
// ---------------------------------------------------------------------------

// Une ligne par routeur entendu, "suite":true sur toutes sauf la derniere
// ("suite":false) ; sans routeur, une seule ligne "vide":true. Champs : rloc16,
// ext, partition (Leader Data ; null sans elle), route64 (derniere Route64
// brute, en hexa ; null sans elle), seq (sa sequence), rssi (dernier message),
// rssi_min et rssi_max (depuis l'entree dans la table), nb (messages
// dechiffres), age_s (depuis le dernier). Une ligne fait moins de 400 octets :
// elle passe par le reseau (1100 au plus). Ni la cle reseau ni une cle
// derivee : seulement ce que les routeurs annoncent a leurs voisins.
static void ligneAnnonces(const mle::Entendu &e, uint32_t maintenant, bool suite) {
  debut("annonces");
  ajoute(",\"rloc16\":\"%04X\"", e.rloc16);
  hexa("ext", e.ext, sizeof(e.ext));
  if (e.aPartition) ajoute(",\"partition\":\"%08lX\"", (unsigned long)e.partition);
  else ajoute(",\"partition\":null");
  if (e.nRoute64) {
    hexa("route64", e.route64, e.nRoute64);
    ajoute(",\"seq\":%u", e.route64[0]);
  } else {
    ajoute(",\"route64\":null,\"seq\":null");
  }
  ajoute(",\"rssi\":%d,\"rssi_min\":%d,\"rssi_max\":%d,\"nb\":%lu,\"age_s\":%lu", e.rssi, e.rssiMin, e.rssiMax,
         (unsigned long)e.nb, (unsigned long)((maintenant - e.dernier) / 1000));
  ajoute(",\"suite\":%s", suite ? "true" : "false");
  fin();
}

static void ligneAnnoncesVide() {
  debut("annonces");
  ajoute(",\"vide\":true");
  fin();
}

// Par le reseau, les lignes ne peuvent pas partir toutes ensemble : la file
// d'emission n'a que 6 places (reseau.cpp) et ne se vide qu'en fin de tour,
// alors que la table peut garder 32 routeurs. La commande en fait donc un
// travail, repris a chaque tour de loop() (annoncesTour) : une ligne par place
// libre, dans l'ordre, la derniere avec "suite":false, comme une reponse de
// diag ou de resolution qui attend sa place, en laissant une place libre pour
// les reponses des autres commandes et les DEFI des nouvelles connexions. Un
// seul a la fois, sur une copie de la table prise a la commande (la table
// change entre deux tours : la reponse est un instantane, et sa fin ne peut
// pas disparaitre). Cette reponse n'est jamais gardee (Gardees) : un rid
// repete pendant l'envoi est ignore, apres la fin il relance la lecture, sans
// effet (rejouee d'un coup, une reponse de plus de 6 lignes buterait sur la
// file) ; l'app fusionne par ext ou rloc16.
struct AnnoncesEnVol {
  bool actif = false;
  Sortie sortie;         // session reseau et rid qui attendent la reponse
  uint32_t debutMs = 0;  // millis() de la commande : age_s de toutes les lignes
  uint8_t total = 0;     // lignes a envoyer (au moins une : "vide")
  uint8_t emises = 0;
  uint8_t routeurs = 0;  // entrees copiees dans sInstantane
};
// Places de la file d'emission laissees libres pendant l'envoi.
static constexpr uint8_t kPlacesReserveAnnonces = 1;
static AnnoncesEnVol sAnnonces;
static mle::Entendu sInstantane[mle::TableEntendus::kPlaces];

static void cmdAnnonces() {
  const mle::TableEntendus &t = ecoute::entendus();
  const uint32_t maintenant = millis();
  if (sSortie.reseau) {
    if (sAnnonces.actif) {
      repondreErreur("occupee");
      // Pas gardee : le rid repete apres la fin relance la commande.
      sGardees[sSortie.place].oublier(sSortie.rid);
      return;
    }
    AnnoncesEnVol a;
    a.actif = true;
    a.sortie = sSortie;
    a.debutMs = maintenant;
    for (size_t k = 0; k < mle::TableEntendus::kPlaces; k++)
      if (t.place(k).utilise) sInstantane[a.routeurs++] = t.place(k);
    a.total = a.routeurs ? a.routeurs : 1;
    sAnnonces = a;
    return;
  }
  size_t restants = t.nombre();
  if (restants == 0) return ligneAnnoncesVide();
  for (size_t k = 0; k < mle::TableEntendus::kPlaces; k++) {
    const mle::Entendu &e = t.place(k);
    if (!e.utilise) continue;
    restants--;
    ligneAnnonces(e, maintenant, restants != 0);
  }
}

// Tour de loop() : les lignes d'annonces que la file d'emission peut prendre
// (hors la place de reserve). Session partie entre-temps : le travail tombe.
// Rien n'est garde pour un rid repete (voir plus haut) : sortieReseau ne trouve
// aucune reponse ouverte, et ses lignes ne sont pas gardees.
static void annoncesTour() {
  AnnoncesEnVol &a = sAnnonces;
  if (!a.actif) return;
  if (!reseauSessionActive(a.sortie.place, a.sortie.generation)) {
    a = AnnoncesEnVol();
    return;
  }
  if (reseauPlacesLibres() <= kPlacesReserveAnnonces) return;
  sSortie = a.sortie;
  while (a.emises < a.total && reseauPlacesLibres() > kPlacesReserveAnnonces) {
    if (a.routeurs) ligneAnnonces(sInstantane[a.emises], a.debutMs, a.emises + 1 < a.total);
    else ligneAnnoncesVide();
    a.emises++;
  }
  sSortie = Sortie();
  if (a.emises >= a.total) a = AnnoncesEnVol();
}

// ---------------------------------------------------------------------------
//  resoudre : resolution d'adresse (1.1.0), 8 en vol
// ---------------------------------------------------------------------------

// Une demande d'echo ICMPv6 vers l'adresse fait resoudre celle-ci par
// OpenThread (Address Query) : un routeur repond pour lui-meme, ou le parent
// pour son enfant, endormi ou non. Le cache d'adresses donne ensuite le RLOC16
// trouve (celui du parent, ou de l'enfant, selon le routeur), et le ML-EID de
// la cible quand la reponse l'a porte. loop() lit le cache toutes les 250 ms,
// 15 s au plus.
//
// Une entree de cache peut dater d'une resolution anterieure (la sonde resout
// chaque appareil toutes les 30 min) : « trouvee » ne dit pas que l'appareil
// est la. La preuve (1.1.1, champ « repondu ») est une reponse d'echo ICMPv6
// (Echo Reply) venue de l'adresse avec l'identifiant de la demande, vue par un
// gestionnaire ICMPv6 d'OpenThread. Le mode d'echo (OT_ICMP6_ECHO_HANDLER_ALL
// par defaut) ne regle que les demandes d'echo auxquelles la sonde repond : les
// gestionnaires enregistres voient toutes les reponses (Icmp::HandleMessage).
// Une resolution est finie quand elle est trouvee ET repondue, ou apres 15 s
// (alors « repondu » dit si la reponse est venue entre-temps). Une reponse sans
// entree de cache reste « introuvable » : elle ne donne pas le RLOC16.
static constexpr uint32_t kResolutionMs = 15000, kPasCacheMs = 250;

// Attente de la reponse d'echo, un emplacement par resolution (meme indice que
// sResolutions). Le rappel ICMPv6 tourne dans la tache OpenThread, verrou OT
// tenu ; cmdResoudre et resolutionsTour ne touchent ces champs que sous ce meme
// verrou : il les serialise, sans atomique ni course. Rien de Matter/CHIP.
struct AttenteEcho {
  bool active = false;  // la resolution attend sa reponse
  bool repondu = false;
  uint16_t id = 0;      // identifiant d'echo envoye
  otIp6Address adresse = {};
};
static AttenteEcho sAttentes[kEnVol];

// Rappel du gestionnaire : note la reponse d'echo (type, identifiant et
// adresse source) de la resolution en vol qui l'attend, et rien d'autre. Un
// message qui ne s'accorde avec aucune attente est ignore.
static void surIcmp6(void *, otMessage *, const otMessageInfo *info, const otIcmp6Header *entete) {
  if (!info || !entete) return;
  for (AttenteEcho &a : sAttentes)
    if (a.active && !a.repondu && distant::reponseEcho(entete->mType, entete->mData.m8, a.id) &&
        !memcmp(&info->mPeerAddr, &a.adresse, sizeof(a.adresse)))
      a.repondu = true;
}
// Statique : OpenThread ne copie pas le gestionnaire.
static otIcmp6Handler sGestionnaireIcmp6 = {surIcmp6, nullptr, nullptr};
static otError enregistrerIcmp6(otInstance *ot) { return otIcmp6RegisterHandler(ot, &sGestionnaireIcmp6); }

// Un emplacement par resolution en vol, dans la tache loop seulement.
struct Resolution {
  bool enVol = false;
  bool finie = false;    // trouvee ou echue : la reponse attend son depart
  bool trouvee = false;
  bool repondu = false;  // l'appareil a repondu a l'echo (copie de l'attente, prise sous le verrou OT)
  uint32_t id = 0;
  char cible[48] = {};
  otIp6Address adresse = {};
  uint32_t debutMs = 0, prochainMs = 0, finMs = 0;
  uint16_t rloc16 = 0;
  bool mleidValide = false;
  otIp6Address mleid = {};
  Sortie sortie;  // qui attend la reponse : l'USB, ou une session reseau et son rid
};
static Resolution sResolutions[kEnVol];

static void repondreResolutionErreur(uint32_t id, const char *cible, const char *erreur) {
  debut("resoudre");
  ajoute(",\"id\":%lu,\"cible\":\"%s\",\"ok\":false,\"erreur\":\"%s\"", (unsigned long)id, cible, erreur);
  fin();
}

// resoudre <ipv6> <id>. id en decimal (distant::lireEntier) ; adresse mal
// formee (pas une IPv6, ou un autre caractere que l'hexa, ':' et '.') :
// « syntaxe », avec l'id s'il a pu etre lu (0 sinon). Puis « suspendue »,
// « occupee » (8 en vol, ou verrou OT refuse) ou « envoi ... ».
static void cmdResoudre(char *args) {
  char *cible = strtok(args, " ");
  char *idTexte = strtok(nullptr, " ");
  char *reste = strtok(nullptr, " ");
  uint32_t id = 0;
  const bool idLu = idTexte && distant::lireEntier(idTexte, &id);
  otIp6Address adresse;
  if (!cible || !idLu || reste || strlen(cible) >= sizeof(sResolutions[0].cible) ||
      strspn(cible, kCaracteresCible) != strlen(cible) || otIp6AddressFromString(cible, &adresse) != OT_ERROR_NONE)
    return repondreResolutionErreur(id, "", "syntaxe");
  if (sSuspendue) return repondreResolutionErreur(id, cible, "suspendue");
  size_t libre = kEnVol;
  for (size_t i = 0; i < kEnVol; i++)
    if (!sResolutions[i].enVol) {
      libre = i;
      break;
    }
  if (libre == kEnVol || !verrouOt(500)) return repondreResolutionErreur(id, cible, "occupee");
  otInstance *ot = esp_openthread_get_instance();
  // L'attente est posee avant l'envoi, sous le verrou : une reponse ne peut
  // pas arriver avant (le rappel attend le verrou).
  AttenteEcho &attente = sAttentes[libre];
  attente = AttenteEcho();
  attente.active = true;
  attente.id = (uint16_t)id;
  attente.adresse = adresse;
  otMessage *msg = otIp6NewMessage(ot, nullptr);
  otError e = msg ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
  if (msg) {
    otMessageInfo info;
    memset(&info, 0, sizeof(info));
    info.mPeerAddr = adresse;
    e = otIcmp6SendEchoRequest(ot, msg, &info, (uint16_t)id);
    if (e != OT_ERROR_NONE) otMessageFree(msg);  // refuse : il nous reste
  }
  if (e != OT_ERROR_NONE) attente = AttenteEcho();
  libereOt();
  if (e != OT_ERROR_NONE) {
    char texte[24];
    snprintf(texte, sizeof(texte), "envoi %s", otThreadErrorToString(e));
    return repondreResolutionErreur(id, cible, texte);
  }
  Resolution &r = sResolutions[libre];
  r = Resolution();
  r.id = id;
  snprintf(r.cible, sizeof(r.cible), "%s", cible);
  r.adresse = adresse;
  r.debutMs = millis();
  r.prochainMs = r.debutMs + kPasCacheMs;
  r.sortie = sSortie;
  r.enVol = true;
}

// Le cache d'adresses, toutes les 250 ms, pour les resolutions en vol : une
// entree resolue (ou vue passer) de leur adresse donne le RLOC16 et, s'il est
// connu, le ML-EID. Finie quand l'entree est trouvee ET que l'echo a recu sa
// reponse ; 15 s sans entree : introuvable. Verrou OT occupe : au tour suivant.
static void resolutionsTour(uint32_t maintenant) {
  bool due = false;
  for (const Resolution &r : sResolutions)
    due = due || (r.enVol && !r.finie && (int32_t)(maintenant - r.prochainMs) >= 0);
  if (!due || !verrouOt(50)) return;
  otInstance *ot = esp_openthread_get_instance();
  otCacheEntryIterator it;
  memset(&it, 0, sizeof(it));
  otCacheEntryInfo info;
  while (otThreadGetNextCacheEntry(ot, &info, &it) == OT_ERROR_NONE) {
    if (info.mState != OT_CACHE_ENTRY_STATE_CACHED && info.mState != OT_CACHE_ENTRY_STATE_SNOOPED) continue;
    for (Resolution &r : sResolutions) {
      if (!r.enVol || r.finie || r.trouvee || memcmp(&info.mTarget, &r.adresse, sizeof(r.adresse))) continue;
      r.trouvee = true;
      r.rloc16 = info.mRloc16;
      r.mleidValide = info.mValidLastTrans;
      if (r.mleidValide) r.mleid = info.mMeshLocalEid;
      r.finMs = maintenant;
    }
  }
  // Toujours sous le verrou : l'attente d'echo est celle du rappel ICMPv6.
  for (size_t i = 0; i < kEnVol; i++) {
    Resolution &r = sResolutions[i];
    if (!r.enVol || r.finie || (int32_t)(maintenant - r.prochainMs) < 0) continue;
    r.repondu = sAttentes[i].repondu;
    if ((r.trouvee && r.repondu) || maintenant - r.debutMs >= kResolutionMs) {
      r.finie = true;
      sAttentes[i] = AttenteEcho();  // le rappel n'a plus rien a noter
    } else {
      r.prochainMs = maintenant + kPasCacheMs;
    }
  }
  libereOt();
}

// {"v":1,"t":"resoudre","id":7,"cible":"<ipv6>","ok":true,"ms":340,"rloc16":"AC00","repondu":true,
// "mleid":"<32 HEXA>"|null}, ou "ok":false et "erreur":"introuvable". ms : le temps jusqu'a l'entree de cache ;
// repondu : l'appareil lui-meme a repondu a l'echo pendant cette resolution (faux s'il dort et ne s'est pas
// reveille en 15 s).
static void imprimerResolution(const Resolution &r) {
  debut("resoudre");
  ajoute(",\"id\":%lu,\"cible\":\"%s\"", (unsigned long)r.id, r.cible);
  if (r.trouvee) {
    ajoute(",\"ok\":true,\"ms\":%lu,\"rloc16\":\"%04X\",\"repondu\":%s", (unsigned long)(r.finMs - r.debutMs), r.rloc16,
           r.repondu ? "true" : "false");
    if (r.mleidValide) hexa("mleid", r.mleid.mFields.m8, sizeof(r.mleid.mFields.m8));
    else ajoute(",\"mleid\":null");
  } else {
    ajoute(",\"ok\":false,\"erreur\":\"introuvable\"");
  }
  fin();
}

// Reponses pretes, comme celles d'un diag : pour une session reseau partie
// entre-temps, la reponse tombe ; sinon elle attend une place dans la file
// d'emission, puis elle est gardee pour un rid repete.
static void resolutionsFinies() {
  for (Resolution &r : sResolutions) {
    if (!r.enVol || !r.finie) continue;
    if (r.sortie.reseau) {
      if (!reseauSessionActive(r.sortie.place, r.sortie.generation)) {
        r = Resolution();
        continue;
      }
      if (!reseauPlacesLibres()) continue;
      sGardees[r.sortie.place].commencer(r.sortie.rid);
    }
    sSortie = r.sortie;
    imprimerResolution(r);
    sSortie = Sortie();
    if (r.sortie.reseau) sGardees[r.sortie.place].terminer();
    r = Resolution();
  }
}

// ---------------------------------------------------------------------------
//  Cle d'acces reseau (USB seulement)
// ---------------------------------------------------------------------------

// Ligne de reponse a cle nouvelle, au plus : RS, {"v":1,"t":"cle","id":<10>,
// "cle":"<64>","empreinte":"<8>","hote":"<63>"}, LF : 204 octets. Avec le msg
// d'une cle non chargee (kMsgNonChargee, rare) : 252, sous les 256 du tampon.
// La place libre exigee couvre le cas le plus long : la reponse est la seule
// copie de la cle.
static constexpr int kLigneCleMax = 252;
static const char *const kMsgNonChargee = "cle non chargee : active au redemarrage";

// Effacement de la cle refuse par la NVS : la cle n'est plus en memoire (plus
// d'acces reseau), mais elle reviendrait au demarrage. Jamais tu : la reponse
// a cle le dit (effacement_en_echec), et un nouvel essai part a chaque tour
// de surveillerAppairage (500 ms) jusqu'a ce que la NVS accepte.
static bool sEffacementEnEchec = false;

// Deux essais, comme Halo (matterDecommissionNow). true : plus aucune cle en
// NVS (effacee, ou il n'y en avait pas).
static bool effacerCle() {
  const bool ok = reseauCleEfface() || reseauCleEfface();
  sEffacementEnEchec = !ok;
  return ok;
}

// {"v":1,"t":"cle","empreinte":"<8 hexa>"|null} ; aussi le nom d'hote, les
// compteurs du transport (bloc reseau.ip.udp du pont Halo, plus les lignes
// perdues faute de place dans la file d'emission et les commandes refusees
// par la cadence) et le tas (libre, minimum depuis le demarrage : la 1.0.2
// prend ~18 Ko de RAM de plus).
static void repondreCle() {
  char kid[h1::kKidHex + 1];
  CompteursReseau c;
  reseauCompteurs(&c);
  const uint32_t tasLibre = esp_get_free_heap_size(), tasMin = esp_get_minimum_free_heap_size();
  debut("cle");
  if (reseauEmpreinte(kid)) ajoute(",\"empreinte\":\"%s\"", kid);
  else ajoute(",\"empreinte\":null");
  // Cle sortie de la memoire mais pas de la NVS : elle reviendrait au demarrage.
  ajoute(",\"effacement_en_echec\":%s", sEffacementEnEchec ? "true" : "false");
  ajouteHote();
  ajoute(",\"udp\":{\"port\":%u,\"ouvert\":%s,\"sessions\":%u,\"provisoire\":%s,\"rx\":%lu,\"rejets\":%lu,"
         "\"rx_perdus\":%lu,\"defis\":%lu,\"tx\":%lu,\"tx_perdus\":%lu,\"tx_erreurs\":%lu",
         (unsigned)kPortReseau, c.ouvert ? "true" : "false", (unsigned)c.sessions, c.provisoire ? "true" : "false",
         (unsigned long)c.rx, (unsigned long)c.rejets, (unsigned long)c.rxPerdus, (unsigned long)c.defis,
         (unsigned long)c.tx, (unsigned long)c.txPerdus, (unsigned long)c.txErreurs);
  if (c.tamponsMinConnu) ajoute(",\"tampons_min\":%u", (unsigned)c.tamponsMin);
  else ajoute(",\"tampons_min\":null");
  ajoute(",\"lignes_perdues\":%lu,\"refus_cadence\":%lu}", (unsigned long)sLignesPerdues,
         (unsigned long)sRefusCadence);
  ajoute(",\"tas\":{\"libre\":%lu,\"min\":%lu}", (unsigned long)tasLibre, (unsigned long)tasMin);
  fin();
}

// cle nouvelle <64 HEXA> <id> : cle = HMAC-SHA256(cle = alea de l'app,
// message = alea de la carte), gardee en NVS et rendue une seule fois, dans
// cette reponse. La cle n'est jamais imprimee ailleurs ; sans id : syntaxe.
static void cleNouvelle(const char *hex, const char *idTexte) {
  uint8_t alea[32];
  uint32_t id = 0;
  // 64 hexa MAJUSCULES (h1::fromHex refuse les minuscules), comme Halo.
  const bool ok = strlen(hex) == 64 && h1::fromHex(hex, sizeof(alea), alea) && distant::lireEntier(idTexte, &id);
  if (!ok) {
    h1::wipe(alea, sizeof(alea));
    return repondreErreur("syntaxe");
  }
  // La reponse est la seule copie de la cle : pas de cle neuve si elle ne
  // peut pas partir tout de suite (tampon d'emission USB occupe).
  if (Serial.availableForWrite() < kLigneCleMax) {
    h1::wipe(alea, sizeof(alea));
    return repondreErreur("occupee");
  }
  char cleHex[65], kid[h1::kKidHex + 1];
  const ResultatCle res = reseauCleNouvelle(alea, cleHex, kid);
  h1::wipe(alea, sizeof(alea));
  if (res == ResultatCle::Crypto) return repondreErreur("crypto");
  if (res == ResultatCle::Nvs) return repondreErreur("ecriture");
  // La nouvelle cle a remplace l'ancienne en NVS : plus rien a effacer.
  sEffacementEnEchec = false;
  debut("cle");
  ajoute(",\"id\":%lu,\"cle\":\"%s\",\"empreinte\":\"%s\"", (unsigned long)id, cleHex, kid);
  ajouteHote();
  // Cle ecrite mais pas chargee : elle vaut au prochain demarrage, l'app doit
  // la connaitre ; la reponse le dit (msg, comme Halo).
  if (res == ResultatCle::Chargement) ajoute(",\"msg\":\"%s\"", kMsgNonChargee);
  fin();
  h1::wipe(cleHex, sizeof(cleHex));
  h1::wipe(sLigne, sizeof(sLigne));
}

// cle | cle efface | cle nouvelle <64 HEXA> <id> : USB seulement. La liste
// blanche les refuse deja au reseau ; refusees ici aussi (defense en
// profondeur : la reponse de nouvelle porte la cle).
static void cmdCle(char *args) {
  if (sSortie.reseau) return repondreErreur("refuse");
  char *mots[4];
  size_t n = 0;
  for (char *m = strtok(args, " "); m && n < 4; m = strtok(nullptr, " ")) mots[n++] = m;
  if (n == 0) return repondreCle();
  if (n == 1 && !strcmp(mots[0], "efface")) {
    if (!effacerCle()) return repondreErreur("ecriture");
    return repondreCle();
  }
  if (n == 3 && !strcmp(mots[0], "nouvelle")) return cleNouvelle(mots[1], mots[2]);
  repondreErreur("syntaxe");
}

// oubli : la cle part aussi (deux essais : un echec la laisserait revenir au
// demarrage), sinon l'ancien proprietaire garderait l'acces reseau apres un
// nouvel appairage (comme Halo, matterDecommissionNow). Matter n'efface que
// ses propres espaces NVS. La reponse dit si la cle est bien partie
// (cle_effacee false : la NVS a refuse, la cle reviendra au redemarrage ;
// cle efface ensuite). USB seulement.
// La sonde revient allumee, comme a sa premiere mise en service (1.0.3) :
// setOnOff(true) met l'attribut de Matter a allume (et, s'il change, passe
// par le rappel surInterrupteur), puis l'etat allume est ecrit dans la NVS
// de la sonde, que decommission() n'efface pas. Ecrit ici dans tous les
// cas : setOnOff rend sans appeler le rappel quand onOffState ou l'attribut
// valent deja allume, et la NVS pourrait alors dire eteint.
static void cmdOubli() {
  if (sSortie.reseau) return repondreErreur("refuse");
  const bool effacee = effacerCle();
  debut("oubli");
  ajoute(",\"cle_effacee\":%s", effacee ? "true" : "false");
  fin();
  Serial.flush();
  sInterrupteur.setOnOff(true);
  sPreferences.putBool(kCleInterrupteur, true);
  Matter.decommission();  // efface l'appairage et redemarre
}

// Plus aucun controleur (sonde retiree de Maison sans oubli) : Matter rouvre
// l'appairage ; la cle part aussi, sinon l'ancien proprietaire garderait
// l'acces reseau apres qu'un autre a ajoute la sonde (comme Halo, ownerPoll).
// Seul un passage observe de « appairee » a « plus appairee » compte (pas
// l'etat au demarrage). Un effacement refuse par la NVS (ici ou par cle
// efface) est retente a chaque tour, et dit par la reponse a cle.
static void surveillerAppairage(uint32_t maintenant) {
  static int8_t sVu = -1;  // -1 : pas encore lu
  static uint32_t sA = 0;
  if (sVu >= 0 && maintenant - sA < 500) return;
  sA = maintenant;
  const bool appairee = Matter.isDeviceCommissioned();
  char kid[h1::kKidHex + 1];
  if ((sVu == 1 && !appairee && reseauEmpreinte(kid)) || sEffacementEnEchec) effacerCle();
  sVu = appairee ? 1 : 0;
}

// ---------------------------------------------------------------------------
//  Commandes recues par le reseau (reseau.cpp)
// ---------------------------------------------------------------------------

void reseauSessionPartie(uint8_t place) {
  if (place >= kPlacesReseau) return;
  sGardees[place].vider();
  sCadences[place] = distant::Cadence();
  // Annonces en cours pour cette session : abandonnees (le loop() les aurait
  // vues tomber, mais une session neuve de la meme place ne doit pas attendre).
  if (sAnnonces.actif && sAnnonces.sortie.place == place) sAnnonces = AnnoncesEnVol();
}

// Une ligne gardee repart vers l'app, "<rid> <ligne JSON>".
struct Renvoi {
  uint8_t place;
  char prefixe[distant::kRidMax + 2];
  size_t n;
};

static void renvoyerLigne(void *contexte, const uint8_t *ligne, size_t n) {
  const Renvoi &r = *(const Renvoi *)contexte;
  if (!reseauEnvoyer(r.place, r.prefixe, r.n, ligne, n)) sLignesPerdues++;
}

static void executer(char *c);

// "<rid> <commande>" d'une session etablie. Sans rid lisible, aucune reponse
// possible : ignoree. Un rid deja servi ne relance rien : la reponse gardee
// repart, ou rien si un diag, une resolution ou des annonces de ce rid sont
// encore en vol (les annonces ne sont pas gardees : apres leur fin, le rid
// relance la lecture). Puis la cadence, comme Halo apres l'id (benq cli.cpp) : plus de 20 commandes dans la seconde,
// rien, sans reponse (l'app renvoie), mais le refus est compte
// (sRefusCadence). Hors liste blanche : erreur « refuse ».
void reseauRecu(uint8_t place, char *charge) {
  uint32_t rid = 0;
  char *commande = nullptr;
  if (place >= kPlacesReseau || !distant::lireRid(charge, &rid, &commande)) return;
  const uint32_t generation = reseauGeneration(place);
  for (const Requete &r : sRequetes)
    if (r.enVol && r.sortie.reseau && r.sortie.place == place && r.sortie.generation == generation &&
        r.sortie.rid == rid)
      return;
  for (const Resolution &r : sResolutions)
    if (r.enVol && r.sortie.reseau && r.sortie.place == place && r.sortie.generation == generation &&
        r.sortie.rid == rid)
      return;
  if (sAnnonces.actif && sAnnonces.sortie.place == place && sAnnonces.sortie.generation == generation &&
      sAnnonces.sortie.rid == rid)
    return;
  Renvoi renvoi;
  renvoi.place = place;
  renvoi.n = distant::texteRid(rid, renvoi.prefixe);
  renvoi.prefixe[renvoi.n++] = ' ';
  if (sGardees[place].rendre(rid, renvoyerLigne, &renvoi)) return;
  if (!sCadences[place].allow(millis())) {
    sRefusCadence++;
    return;
  }

  sSortie.reseau = true;
  sSortie.place = place;
  sSortie.generation = generation;
  sSortie.rid = rid;
  sGardees[place].commencer(rid);
  if (distant::permise(commande)) executer(commande);
  else repondreErreur("refuse");
  sGardees[place].terminer();
  sSortie = Sortie();
}

// ---------------------------------------------------------------------------
//  LED de la carte (1.0.3 ; tronc commun en 1.1.1)
// ---------------------------------------------------------------------------

// WS2812 de la SuperMini, sur IO8 : rien d'autre n'y touche dans ce firmware.
// Faible intensite, le tronc commun du pont Halo sur la meme carte (voyant.h) :
// 24/255 au plus par canal. Ordre GRB par defaut de rgbLedWrite.
static constexpr uint8_t kBrocheVoyant = 8;
static Voyant sVoyant;
static bool sVoyantSuspendue = false;    // etat de l'interrupteur que la LED montre
static Voyant::Rvb sVoyantEcrit;         // couleur ecrite...
static bool sVoyantEcritValide = false;  // ... si quelque chose l'a deja ete
static bool sVoyantAttachee = false;     // attachement au reseau Thread, dernier role lu
static uint32_t sVoyantReseau = 0;       // derniere lecture du reseau (millis)

// rgbLedWrite (Arduino-ESP32 3.x) : 24 bits par le RMT, environ 30 us ; le
// canal RMT est cree au premier appel, puis reutilise. Seulement si la
// couleur change : 16 ecritures par lueur, 25 par seconde pendant
// l'arc-en-ciel et la pulsation bleue, sinon une par changement.
static void ecrireVoyant(Voyant::Rvb c) {
  if (sVoyantEcritValide && c == sVoyantEcrit) return;
  sVoyantEcrit = c;
  sVoyantEcritValide = true;
  rgbLedWrite(kBrocheVoyant, c.r, c.g, c.b);
}

// Identification en cours (session ou effet). Toutes les fins echues sont
// oubliees a chaque appel, bien avant que le retour a zero de millis() les
// fasse paraitre futures ; une fin posee entre-temps par la tache CHIP reste.
static bool identificationEnCours(uint32_t maintenant) {
  bool enCours = sIdentSession;
  uint32_t fin = sIdentFinEffet.load();
  if (effetIdent::enCours(fin, maintenant)) enCours = true;
  else if (fin) sIdentFinEffet.compare_exchange_strong(fin, 0u);
  return enCours;
}

// Etat du reseau que la LED montre. Matter.isDeviceCommissioned() hors du
// verrou OpenThread (appel Matter) ; le role Thread sous ce verrou, pris sans
// attendre (occupe : l'attachement d'avant reste, relu a la seconde suivante).
static Voyant::Reseau voyantReseau() {
  if (verrouOt(0)) {
    const otDeviceRole role = otThreadGetDeviceRole(esp_openthread_get_instance());
    libereOt();
    sVoyantAttachee = role == OT_DEVICE_ROLE_CHILD || role == OT_DEVICE_ROLE_ROUTER || role == OT_DEVICE_ROLE_LEADER;
  }
  if (!Matter.isDeviceCommissioned()) return Voyant::kNonMiseEnService;
  return sVoyantAttachee ? Voyant::kAttachee : Voyant::kDetachee;
}

// Dans loop() seulement, hors de tout verrou : les rappels Matter ne font que
// poser sSuspendue et l'identification ; un changement de l'interrupteur vu
// ici lance son geste. Sans attente : les motifs se lisent sur millis(). Le
// reseau (mise en service, role Thread) se relit une fois par seconde.
static void voyantTour(uint32_t maintenant) {
  const bool suspendue = sSuspendue;
  if (suspendue != sVoyantSuspendue) {
    sVoyantSuspendue = suspendue;
    sVoyant.changer(suspendue, maintenant);
  }
  if (maintenant - sVoyantReseau >= 1000) {
    sVoyantReseau = maintenant;
    sVoyant.changerReseau(voyantReseau(), maintenant);
  }
  sVoyant.identifier(identificationEnCours(maintenant), maintenant);
  ecrireVoyant(sVoyant.rvb(maintenant));
}

// ---------------------------------------------------------------------------
//  Boucle
// ---------------------------------------------------------------------------

static char sCommande[200];
static size_t sCmdLong = 0;

static void executer(char *c) {
  while (*c == ' ') c++;
  if (!strcmp(c, "bonjour")) return cmdBonjour();
  // « nom » seul : nom vide, refuse (syntaxe).
  if (!strcmp(c, "nom") || !strncmp(c, "nom ", 4)) return cmdNom(c + 3);
  if (!strcmp(c, "etat")) return cmdEtat();
  if (!strcmp(c, "voisins")) return cmdVoisins();
  if (!strcmp(c, "routeurs")) return cmdRouteurs();
  if (!strncmp(c, "diag ", 5)) return cmdDiag(c + 5);
  if (!strcmp(c, "annonces")) return cmdAnnonces();
  if (!strncmp(c, "resoudre ", 9)) return cmdResoudre(c + 9);
  if (!strcmp(c, "cle") || !strncmp(c, "cle ", 4)) return cmdCle(c + 3);
  if (!strcmp(c, "oubli")) return cmdOubli();
  if (!*c) return;
  debut("erreur");
  ajoute(",\"erreur\":\"commande inconnue\"");
  fin();
}

void setup() {
  Serial.begin(115200);
  // LED au noir d'abord : une WS2812 garde sa couleur a travers un redemarrage
  // (son alimentation ne coupe pas). IO8, broche de strapping, est deja
  // echantillonnee a ce stade.
  ecrireVoyant(Voyant::Rvb{});
  demarrerMatter();
  reseauDebut();
  // Etat relu de la NVS : suspendue, un bref eclair orange des le premier tour
  // (sous le bleu tant que la sonde n'est pas attachee). Reseau lu tout de
  // suite : mise en service, bleu lent jusqu'a l'attachement, sans eclair de
  // bleu clignotant.
  sVoyantSuspendue = sSuspendue;
  sVoyantReseau = millis();
  sVoyant.demarrer(sVoyantSuspendue, voyantReseau(), sVoyantReseau);
  cmdBonjour();
}

void loop() {
  while (Serial.available()) {
    const int o = Serial.read();
    if (o == '\n' || o == '\r') {
      sCommande[sCmdLong] = 0;
      if (sCmdLong) {
        executer(sCommande);
        // Rien ne reste de la ligne (l'alea de cle nouvelle).
        h1::wipe(sCommande, sizeof(sCommande));
      }
      sCmdLong = 0;
    } else if (o >= 0x20 && o < 0x7F && sCmdLong < sizeof(sCommande) - 1) {
      sCommande[sCmdLong++] = (char)o;
    }
  }
  diagsFinis();
  ecoute::tour(millis());
  resolutionsTour(millis());
  resolutionsFinies();
  annoncesTour();
  reseauTour();
  surveillerAppairage(millis());
  voyantTour(millis());
  delay(5);
}
