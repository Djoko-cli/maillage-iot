#pragma once
// ===========================================================================
//  Acces a la sonde par le reseau Thread : UDP sur IPv6, enveloppe H1
//
//  Repris du pont Halo (depot benq, src/net_udp.{h,cpp} ; protocole : benq
//  docs/PROTOCOLE-JSON.md, section 10) : meme socket OpenThread, memes
//  files, meme debit, meme enveloppe (h1_proto.h, copie telle quelle), memes
//  sessions (2 etablies + 1 provisoire). Ecarts :
//  - le port est tenu par OpenThread des que la pile Thread existe, cle ou
//    non : sans cle, un datagramme est jete dans le rappel, sans reponse et
//    sans ICMPv6 « port injoignable » (un port tenu par OpenThread n'est
//    jamais remis a lwIP) ;
//  - charges : "<rid> <commande>" vers la carte, "<rid> <ligne JSON>" vers
//    l'app, 1100 octets au plus (liste blanche et reponses gardees :
//    main.cpp, distant.h) ;
//  - cle en NVS dans l'espace de la sonde (sonde/cle) ;
//  - seul le nom d'hote SRP est releve (pas de bloc d'adresses).
//
//  Taches et verrous (comme Halo) :
//  - reception : rappel d'OpenThread (tache OT, verrou OT tenu) ; il ne fait
//    que copier le datagramme dans une file FreeRTOS (4 places), jamais de
//    verrou CHIP, jamais de Serial ;
//  - tout le reste dans la tache loop : poignee de main, verification,
//    commandes (reseauRecu, main.cpp), formatage des lignes, HMAC ;
//  - emission : datagrammes scelles (en-tete H1 + charge) dans une file de 6
//    places, remis a OpenThread sous verrou pris SANS attente ; verrou
//    occupe : au tour suivant. Sous ce verrou, seulement des appels
//    OpenThread ;
//  - debit plafonne (3000 octets/s, priorite basse), et un datagramme ne part
//    que s'il reste assez de tampons OpenThread (65, partages avec Matter)
//    apres lui ; le DEFI d'une poignee de main passe devant, hors plafond.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

// Port UDP fixe, sous la plage ephemere d'OpenThread (49152..65535) : celui du pont Halo.
constexpr uint16_t kPortReseau = 5480;
// Charge d'un datagramme de la carte ("<rid> <ligne JSON>") : 1100 octets au
// plus ; avec l'en-tete H1 (56 au plus), 1156 < 1232 : pas de fragmentation IPv6.
constexpr size_t kChargeMax = 1100;
// Commande recue ("<rid> <commande>") : ce qui tient dans un datagramme recu
// (256 octets au plus, en-tete compris).
constexpr size_t kChargeRecueMax = 256;
// Sessions etablies (h1::kSlots).
constexpr uint8_t kPlacesReseau = 2;

// --- Fournis par main.cpp ----------------------------------------------------

// Verrou OpenThread pris SANS attente ; false : pile absente ou verrou pris.
bool reseauVerrouEssai();
void reseauVerrouLibere();
// Charge d'un message au MAC juste de la session etablie place : C, ASCII
// imprimable (tout autre octet devient '?'), kChargeRecueMax octets au plus.
void reseauRecu(uint8_t place, char *charge);
// La session place est partie (oubliee, remplacee, cle changee ou effacee) :
// ce qui lui etait garde tombe.
void reseauSessionPartie(uint8_t place);

// --- Cycle de vie (tache loop) -------------------------------------------------

// setup(), apres Matter.begin() : file de reception, cle lue en NVS.
void reseauDebut();
// loop() : socket, datagrammes recus (poignees de main, commandes), oubli des
// sessions, emission, nom d'hote SRP.
void reseauTour();

// --- Sessions ------------------------------------------------------------------

// Generation de la place : change a chaque session qui part ou arrive.
uint32_t reseauGeneration(uint8_t place);
// La session de cette generation occupe toujours la place.
bool reseauSessionActive(uint8_t place, uint32_t generation);
// Datagramme "<prefixe><json>" pour la session place (enveloppe H1, file
// d'emission). false : pas de session, charge trop longue ou file pleine.
bool reseauEnvoyer(uint8_t place, const char *prefixe, size_t nPrefixe, const uint8_t *json, size_t nJson);
// Places libres dans la file d'emission (partagee par les sessions).
uint8_t reseauPlacesLibres();

// Nom d'hote SRP (celui que Matter enregistre, sans .local), relu au plus
// toutes les 5 s ; false : pas encore connu.
bool reseauHote(char hote[64]);

// --- Cle (commande cle, USB seulement) -------------------------------------------

enum class ResultatCle : uint8_t {
  Ok,
  Crypto,      // cle non calculee : rien ne change
  Nvs,         // cle non ecrite : rien ne change
  Chargement,  // cle ecrite en NVS mais pas chargee : acces coupe jusqu'au redemarrage
};
// cle = HMAC-SHA256(cle = alea de l'app, message = alea de la carte), ecrite
// en NVS, rendue en hexa (cleHex, 64 + 1) avec son empreinte (8 + 1) ; toutes
// les sessions tombent.
ResultatCle reseauCleNouvelle(const uint8_t aleaApp[32], char cleHex[65], char empreinte[9]);
// Efface la cle (NVS et memoire) : plus d'acces reseau, toutes les sessions
// tombent. false : NVS en echec (la cle est quand meme retiree de la memoire).
bool reseauCleEfface();
bool reseauEmpreinte(char empreinte[9]);  // false : aucune cle

// Compteurs, comme le bloc reseau.ip.udp du pont Halo.
struct CompteursReseau {
  bool ouvert;
  uint8_t sessions;
  bool provisoire;
  uint32_t rx, rejets, rxPerdus, defis, tx, txPerdus, txErreurs;
  bool tamponsMinConnu;
  uint16_t tamponsMin;
};
void reseauCompteurs(CompteursReseau *c);
