#include "distant.h"

#include <stdlib.h>
#include <string.h>

namespace distant {

// ===========================================================================
//  rid et liste blanche
// ===========================================================================

bool lireRid(char *charge, uint32_t *rid, char **commande) {
  uint64_t v = 0;
  size_t chiffres = 0;
  while (charge[chiffres] >= '0' && charge[chiffres] <= '9') {
    if (chiffres == kRidMax) return false;  // 11 chiffres ou plus
    v = v * 10 + (uint64_t)(charge[chiffres] - '0');
    chiffres++;
  }
  // Un seul texte par rid : pas de zero de tete (sauf "0").
  if (!chiffres || (chiffres > 1 && charge[0] == '0') || v > 0xFFFFFFFFull) return false;
  const char suite = charge[chiffres];
  if (suite != 0 && suite != ' ') return false;
  *rid = (uint32_t)v;
  *commande = charge + chiffres + (suite == ' ' ? 1 : 0);
  return true;
}

size_t texteRid(uint32_t rid, char out[kRidMax + 1]) {
  char t[kRidMax];
  size_t n = 0;
  do {
    t[n++] = (char)('0' + rid % 10);
    rid /= 10;
  } while (rid);
  for (size_t i = 0; i < n; i++) out[i] = t[n - 1 - i];
  out[n] = 0;
  return n;
}

bool permise(const char *commande) {
  while (*commande == ' ') commande++;
  return !strcmp(commande, "bonjour") || !strcmp(commande, "etat") || !strcmp(commande, "voisins") ||
         !strcmp(commande, "routeurs") || !strcmp(commande, "annonces") || !strncmp(commande, "diag ", 5) ||
         !strncmp(commande, "resoudre ", 9);
}

// ===========================================================================
//  Reponses gardees
// ===========================================================================

uint32_t Gardees::ridA(size_t i) const {
  return (uint32_t)o_[i] | (uint32_t)o_[i + 1] << 8 | (uint32_t)o_[i + 2] << 16 | (uint32_t)o_[i + 3] << 24;
}

size_t Gardees::longueurA(size_t i) const { return (size_t)o_[i + 4] | (size_t)o_[i + 5] << 8; }

void Gardees::vider() {
  n_ = 0;
  rid_ = 0;
  ouverte_ = false;
  abandonnee_ = false;
}

// Retire les octets [debut, fin) et ramene la suite.
void Gardees::retirer(size_t debut, size_t fin) {
  memmove(o_ + debut, o_ + fin, n_ - fin);
  n_ -= fin - debut;
}

// La plus ancienne reponse : ses lignes, jusqu'a la premiere d'un autre rid.
void Gardees::retirerPremiere() {
  if (!n_) return;
  const uint32_t r = ridA(0);
  size_t i = 0;
  while (i < n_ && ridA(i) == r) i += kEntete + longueurA(i);
  retirer(0, i);
}

void Gardees::retirerRid(uint32_t rid) {
  size_t i = 0;
  while (i < n_) {
    const size_t l = kEntete + longueurA(i);
    if (ridA(i) == rid) retirer(i, i + l);
    else i += l;
  }
}

bool Gardees::gardee(uint32_t rid) const {
  for (size_t i = 0; i < n_; i += kEntete + longueurA(i))
    if (ridA(i) == rid) return true;
  return false;
}

size_t Gardees::reponses() const {
  size_t k = 0;
  uint32_t avant = 0;
  for (size_t i = 0; i < n_; i += kEntete + longueurA(i)) {
    const uint32_t r = ridA(i);
    if (i == 0 || r != avant) k++;
    avant = r;
  }
  return k;
}

void Gardees::commencer(uint32_t rid) {
  retirerRid(rid);
  rid_ = rid;
  ouverte_ = true;
  abandonnee_ = false;
}

void Gardees::terminer() { ouverte_ = false; }

void Gardees::oublier(uint32_t rid) {
  retirerRid(rid);
  if (ouverte_ && rid_ == rid) abandonnee_ = true;
}

void Gardees::ajouter(const uint8_t *ligne, size_t n) {
  if (!ouverte_ || abandonnee_) return;
  const size_t besoin = kEntete + n;
  if (n > 0xFFFF || besoin > kOctets) {
    retirerRid(rid_);
    abandonnee_ = true;
    return;
  }
  // Premiere ligne de la reponse : elle prend l'une des kReponses places.
  if (!gardee(rid_))
    while (reponses() >= kReponses) retirerPremiere();
  // Place : les plus anciennes reponses partent. Les lignes de la reponse en
  // cours sont les dernieres ; si elles sont aussi les premieres, elle ne
  // tient pas : rien n'en est garde (jamais une reponse coupee).
  while (n_ + besoin > kOctets) {
    if (ridA(0) == rid_) {
      retirerRid(rid_);
      abandonnee_ = true;
      return;
    }
    retirerPremiere();
  }
  uint8_t *e = o_ + n_;
  e[0] = (uint8_t)rid_;
  e[1] = (uint8_t)(rid_ >> 8);
  e[2] = (uint8_t)(rid_ >> 16);
  e[3] = (uint8_t)(rid_ >> 24);
  e[4] = (uint8_t)n;
  e[5] = (uint8_t)(n >> 8);
  memcpy(e + kEntete, ligne, n);
  n_ += besoin;
}

bool Gardees::rendre(uint32_t rid, Rendu f, void *contexte) const {
  bool trouve = false;
  for (size_t i = 0; i < n_; i += kEntete + longueurA(i))
    if (ridA(i) == rid) {
      trouve = true;
      if (f) f(contexte, o_ + i + kEntete, longueurA(i));
    }
  return trouve;
}

// ===========================================================================
//  Cadence (copie de benq src/json_out.cpp, Cadence::allow)
// ===========================================================================

bool Cadence::allow(uint32_t now) {
  // at_[idx_] : la plus ancienne des kLines dernieres lignes acceptees.
  if (n_ >= kLines && now - at_[idx_] < kWindowMs) return false;
  at_[idx_] = now;
  idx_ = (uint8_t)((idx_ + 1) % kLines);
  if (n_ < kLines) n_++;
  return true;
}

// ===========================================================================
//  Entiers des commandes, reprises CoAP d'un diag
// ===========================================================================

bool lireEntier(const char *s, uint32_t *v) {
  const size_t n = strlen(s);
  if (n == 0 || n > 10 || strspn(s, "0123456789") != n) return false;
  const unsigned long long x = strtoull(s, nullptr, 10);
  if (x > 0xFFFFFFFFull) return false;
  *v = (uint32_t)x;
  return true;
}

Reprises reprisesDiag(uint32_t delaiMs) {
  Reprises r;
  // Sous 15 s, trois reprises feraient tomber l'accuse sous 1 s : le plancher
  // allongerait l'attente (jusqu'a 15 s pour un delai de 10 s).
  r.reprises = delaiMs < 15000 ? 1 : 3;
  const uint32_t facteur = (1u << (r.reprises + 1)) - 1;
  r.accuseMs = delaiMs / facteur;
  if (r.accuseMs < 1000) r.accuseMs = 1000;
  return r;
}

bool reponseEcho(uint8_t type, const uint8_t donnees[4], uint32_t id) {
  constexpr uint8_t kTypeEchoReply = 129;
  return type == kTypeEchoReply && (uint16_t)((donnees[0] << 8) | donnees[1]) == (uint16_t)id;
}

}  // namespace distant
