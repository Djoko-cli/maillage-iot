#pragma once
// ===========================================================================
//  Commandes de la sonde : briques pures (contrat de la 1.0.2, complete en
//  1.0.3 et en 1.1.0)
//
//  Commandes recues par le reseau. Charge d'un message H1 de l'app :
//  "<rid> <commande>". rid : entier decimal choisi par l'app
//  (0..4294967295, sans zero de tete), commande : le meme texte que sur
//  l'USB. Charge d'une reponse : "<rid> <ligne JSON>".
//
//  - Liste blanche : bonjour, etat, voisins, routeurs, diag ; depuis la
//    1.1.0, annonces et resoudre. Tout le reste (cle..., nom, oubli, commande
//    inconnue) : refuse a distance.
//  - Reponses gardees : un rid repete dans la meme session ne relance rien,
//    la reponse gardee repart : les 8 dernieres reponses, dans la limite de
//    4096 octets par session, lignes comprises (comme le cache des 8
//    dernieres reponses d'une session reseau du pont Halo, benq
//    src/json_out.h, ReplyCache). Au-dela (routeurs d'une quarantaine de
//    routeurs), un rid repete relance la commande : une lecture, sans effet.
//    Annonces (1.1.0) n'est jamais gardee : sa reponse part au fil des places
//    libres de la file d'emission (main.cpp), un rid repete apres la fin
//    relance la lecture (sans effet).
//  - Lignes : 1100 octets de charge au plus. routeurs se coupe en lignes
//    "suite" ; une ligne perdue en route donne une table partielle, ou
//    aucune si la derniere (suite:false) se perd ; l'app en tient compte.
//    voisins au-dela de 1100 octets repond « ligne trop longue » a
//    distance (entier sur l'USB) ; un diag trop long, trop_long.
//  - Cadence : 20 commandes par seconde glissante et par session au plus
//    (Cadence, copie de celle du pont Halo) ; au-dela, rien (l'app renvoie).
//    main.cpp compte ces refus (1.0.3 : cle, udp.refus_cadence).
//
//  Aussi (1.0.3), pour les commandes de l'USB comme du reseau : les entiers
//  de leurs arguments (lireEntier : id et delai de diag, id de cle nouvelle)
//  et les reprises CoAP d'un diag (reprisesDiag).
//
//  Pur et sans Arduino : teste sur l'hote par sonde/test/test_distant.cpp ;
//  lancer : sh sonde/test/lancer.sh (clang, ASan et UBSan, avec le test H1).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

namespace distant {

// Chiffres d'un rid : 4294967295 au plus.
constexpr size_t kRidMax = 10;

// "<rid> <commande>" (C, termine par 0). true : *rid lu et *commande pointe
// apres l'espace qui suit le rid (commande vide si la charge s'arrete au rid).
// false : pas de rid canonique (vide, zero de tete, trop grand, autre chose
// qu'un chiffre avant l'espace) ; la charge est ignoree, sans reponse.
bool lireRid(char *charge, uint32_t *rid, char **commande);

// Texte canonique du rid (decimal, sans zero de tete), 0 final compris dans
// out ; rend le nombre de chiffres.
size_t texteRid(uint32_t rid, char out[kRidMax + 1]);

// Commande permise a distance (espaces de tete sautes, comme l'aiguillage) :
// "bonjour", "etat", "voisins", "routeurs", "annonces" exactement, ou "diag "
// ou "resoudre " suivi des arguments.
bool permise(const char *commande);

// Reponses gardees d'une session reseau : les kReponses dernieres (par rid),
// toutes leurs lignes (JSON sans RS ni LF, sans le rid), dans kOctets.
// Une reponse qui ne tient pas dans kOctets n'est pas gardee du tout (jamais
// une partie) : un rid repete la relance alors (lectures seulement).
class Gardees {
 public:
  static constexpr size_t kReponses = 8;
  static constexpr size_t kOctets = 4096;

  void vider();
  // Reponse de rid : les lignes qui suivent (ajouter) sont les siennes. Une
  // reponse deja gardee sous ce rid est oubliee.
  void commencer(uint32_t rid);
  // Ligne de la reponse commencee, gardee a la suite des precedentes ; sans
  // reponse commencee (ou apres terminer), ignoree.
  void ajouter(const uint8_t *ligne, size_t n);
  void terminer();
  // Oublie la reponse rid (une erreur qu'un rid repete ne doit pas rejouer) ;
  // si elle est la reponse commencee, ses lignes suivantes sont ignorees.
  void oublier(uint32_t rid);
  // Lignes gardees sous rid, dans l'ordre, passees a f. false : rien de garde.
  typedef void (*Rendu)(void *contexte, const uint8_t *ligne, size_t n);
  bool rendre(uint32_t rid, Rendu f, void *contexte) const;
  // Pour les tests : reponses et octets gardes.
  size_t reponses() const;
  size_t octets() const { return n_; }

 private:
  // Enregistrement : rid (4 octets), longueur (2), ligne. Les lignes d'une
  // reponse se suivent ; les reponses, dans l'ordre de leur premiere ligne.
  static constexpr size_t kEntete = 6;
  uint32_t ridA(size_t i) const;
  size_t longueurA(size_t i) const;
  void retirer(size_t debut, size_t fin);
  void retirerPremiere();
  void retirerRid(uint32_t rid);
  bool gardee(uint32_t rid) const;

  uint8_t o_[kOctets] = {};
  size_t n_ = 0;
  uint32_t rid_ = 0;
  bool ouverte_ = false;     // une reponse est commencee
  bool abandonnee_ = false;  // trop grande : rien n'en est garde
};

// Au plus kLines lignes acceptees par kWindowMs glissantes : copie de la
// classe Cadence du pont Halo (benq src/json_out.h et json_out.cpp, section
// 6.5 de son protocole), jugee ici par session reseau.
class Cadence {
 public:
  static constexpr uint8_t kLines = 20;
  static constexpr uint32_t kWindowMs = 1000;
  bool allow(uint32_t now);  // true : ligne acceptee et comptee

 private:
  uint32_t at_[kLines] = {};
  uint8_t idx_ = 0, n_ = 0;
};

// Entier decimal de 1 a 10 chiffres (zeros de tete permis), 4294967295 au
// plus : id et delai de diag, id de cle nouvelle. false (et *v intact) pour
// tout le reste : vide, signe, espace, autre caractere, trop grand.
bool lireEntier(const char *s, uint32_t *v);

// Reponse d'echo ICMPv6 (1.1.1) : type 129 (Echo Reply) et identifiant d'echo
// egal a id (16 bits, en gros-boutiste dans les deux premiers octets des
// donnees de l'en-tete ICMPv6, comme otIcmp6Header.mData.m8). L'adresse source
// se compare a part (main.cpp).
bool reponseEcho(uint8_t type, const uint8_t donnees[4], uint32_t id);

// Reprises CoAP d'un diag, pour que l'echec tombe au bout du delai demande
// (3 a 60 s) : attente totale = accuse x (2^(reprises+1) - 1) avec un facteur
// aleatoire de 1, et l'accuse ne descend pas sous 1 s (plancher d'OpenThread).
// Une reprise sous 15 s (accuse = delai / 3), trois au-dela (delai / 15).
struct Reprises {
  uint32_t accuseMs;
  uint8_t reprises;
};
Reprises reprisesDiag(uint32_t delaiMs);

}  // namespace distant
