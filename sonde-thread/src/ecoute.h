#pragma once
// ===========================================================================
//  Ecoute des messages MLE sur la carte (firmware 1.1.0, spec de la sonde
//  tout-en-un, section 1.1)
//
//  En FED, la sonde recoit les messages MLE de ses voisins a un saut (les
//  annonces des routeurs portent leur Route64), sans mode promiscuite.
//  - Le rappel des trames (otLinkSetPcapCallback), dans la tache OpenThread,
//    ne fait qu'un tri (trames de donnees sans securite MAC) et une copie dans
//    une file FreeRTOS de 16 trames : une file pleine est comptee, jamais
//    bloquante. Jamais de verrou, jamais d'appel Matter ni CHIP, jamais de
//    Serial.
//  - Tout le reste dans la tache loop (tour) : le dechiffrement (mle.h), la
//    table des routeurs entendus, l'oubli de ceux qui se taisent depuis 10 min.
//  - La cle reseau n'est lue, sous le verrou OpenThread et par main.cpp, que
//    pour deriver les cles MLE quand la sequence de la pile change, une fois
//    par sequence meme si la derivation echoue (l'ecoute reste alors arretee
//    jusqu'a la rotation ou un redemarrage), puis effacee ; seules deux
//    cles MLE sont gardees (mle::ClesMle). Une trame ne fait consulter la pile
//    qu'une fois par tour au plus (mle::SourceCles). Aucune commande ne rend
//    ni la cle reseau ni une cle derivee.
// ===========================================================================
#include <openthread/instance.h>
#include <stdint.h>

#include "mle.h"

namespace ecoute {

// Fournis par main.cpp, sous le verrou OpenThread : la sequence de cle courante
// de la pile, et la cle reseau (que l'appelant efface apres usage). false :
// verrou non pris. La pile est consultee au plus une fois par tour, et la cle
// reseau au plus une fois par sequence de la pile (mle::SourceCles).
using Acces = mle::AccesPile;

// Pose le rappel des trames ; verrou OpenThread pris par l'appelant.
void demarrer(otInstance *ot, const Acces &acces);

// Tache loop : les trames de la file (16 au plus), puis l'oubli des routeurs
// muets depuis 10 min.
void tour(uint32_t maintenant);

// Depuis le demarrage (etat.ecoute).
struct Compteurs {
  uint32_t trames;      // trames recues par le rappel
  uint32_t mle;         // messages MLE dechiffres
  uint32_t echecs;      // messages MLE chiffres non dechiffres : en-tete illisible, cle indisponible, MIC faux
  uint32_t filePleine;  // trames perdues, file pleine
};
Compteurs compteurs();

// Routeurs entendus (commande annonces), lus dans la tache loop.
const mle::TableEntendus &entendus();

}  // namespace ecoute
