#pragma once
// ===========================================================================
//  LED de la carte (WS2812 de la SuperMini, sur IO8 ; sonde 1.0.3, tronc
//  commun en 1.1.1)
//
//  Le tronc commun du pont Halo, de la carte Amaran, de la sonde de Maillage
//  Zigbee et de cette sonde (decide le 12/10) : 24/255 au plus par canal ;
//  bleu (0,0,24), vert (0,24,0), orange (24,6,0), lueur blanche 8/255. Du plus
//  prioritaire au moins prioritaire :
//  1. identification (cluster Identify de Matter, « Identifier » dans Maison) :
//     arc-en-ciel, un tour de roue en 2 s par pas de 40 ms, pendant toute
//     l'identification et au moins un tour complet ;
//  2. geste de l'interrupteur « Sonde maillage » : allume, deux eclairs verts
//     (100 ms, pause 100 ms) ; eteint, un eclair orange de 500 ms ;
//  3. bleu : pas mis en service, clignotant 250 ms / 250 ms ; mis en service
//     mais pas attachee au reseau Thread (au demarrage, ou parent perdu),
//     pulsation lente en triangle 0 -> 24 -> 0 sur 2 s ;
//  4. adhesion : deux eclairs verts au passage a « attachee » (le premier
//     attachement apres le demarrage compris) ;
//  5. suspendue (interrupteur eteint) : un bref eclair orange de 100 ms toutes
//     les 5 s, le premier tout de suite (aussi apres un redemarrage) ;
//  6. tout va bien (attachee, pas suspendue) : eteinte, breve lueur blanche
//     toutes les 10 s (0 -> 8 -> 0 sur 600 ms), la premiere juste apres les
//     eclairs d'adhesion ;
//  7. sinon, eteinte.
//  L'orange lent « mis en service sans reseau IP » du tronc commun ne
//  s'applique pas ici : le reseau IP de la sonde est Thread, couvert par le
//  bleu lent.
//
//  main.cpp la pilote dans loop(), jamais sous le verrou OpenThread ni depuis
//  un rappel Matter (qui ne fait que poser un etat). Instants de millis() :
//  des ecarts non signes ; chaque echeance (sequence finie, tour minimal de
//  l'arc-en-ciel, eclair de la suspension) est traitee a chaque appel, quel
//  que soit le motif montre, si bien que le retour a zero de millis() ne
//  ranime rien et qu'un motif masque longtemps ne derange pas les autres.
//
//  Pur et sans Arduino, tout dans cet en-tete : teste sur l'hote par
//  sonde/test/test_distant.cpp ; lancer : sh sonde/test/lancer.sh.
// ===========================================================================
#include <stdint.h>

class Voyant {
 public:
  // Ce que la LED montre, pour les tests : kBlanche et kBleue seulement quand
  // leur intensite n'est pas nulle (sinon kNoire) ; kArcEnCiel quelle que
  // soit la teinte.
  enum Couleur : uint8_t { kNoire, kVerte, kOrange, kBlanche, kBleue, kArcEnCiel };
  // Etat du reseau vu par main.cpp.
  enum Reseau : uint8_t { kNonMiseEnService, kDetachee, kAttachee };

  struct Rvb {
    uint8_t r = 0, g = 0, b = 0;
    bool operator==(const Rvb &o) const { return r == o.r && g == o.g && b == o.b; }
    bool operator!=(const Rvb &o) const { return !(*this == o); }
  };
  struct Image {
    Couleur couleur;
    Rvb rvb;
  };

  static constexpr uint8_t kMax = 24;             // plafond par canal (tronc commun)
  static constexpr uint32_t kVertMs = 100;        // chaque eclair vert, et la pause entre eux
  static constexpr uint32_t kExtinctionMs = 500;  // eclair orange quand l'interrupteur s'eteint
  static constexpr uint32_t kBrefMs = 100;        // bref eclair orange de la suspension...
  static constexpr uint32_t kPeriodeMs = 5000;    // ... toutes les 5 s (choix de Djoko, 30/09)
  static constexpr uint8_t kLueurMax = 8;              // sommet de la lueur blanche (pont Halo)
  static constexpr uint32_t kLueurPeriodeMs = 10000;   // une lueur toutes les 10 s...
  static constexpr uint32_t kLueurMs = 600;            // ... de 600 ms (montee puis descente)
  static constexpr uint32_t kClignoteMs = 250;         // bleu, pas mis en service : demi-periode (Halo)
  static constexpr uint32_t kPulsationMs = 2000;       // bleu, detachee : un triangle (sonde Zigbee)
  static constexpr uint32_t kArcEnCielMs = 2000;       // un tour de roue (pont Halo)...
  static constexpr uint32_t kPasMs = 40;               // ... par pas de 40 ms (25 images/s)

  // Demarrage, avec l'etat de l'interrupteur relu de la NVS et l'etat du
  // reseau : aucun eclair de changement ; suspendue, un bref eclair tout de
  // suite ; deja attachee, les eclairs d'adhesion.
  void demarrer(bool suspendue, Reseau reseau, uint32_t maintenant) {
    geste_ = kAucune;
    suspendue_ = suspendue;
    prochain_ = maintenant;
    reseau_ = kNonMiseEnService;
    debutReseau_ = maintenant;
    adhesion_ = false;
    changerReseau(reseau, maintenant);
  }

  // L'interrupteur vient de changer : eclairs verts ou eclair orange, puis,
  // suspendue, le premier bref eclair une periode plus tard.
  void changer(bool suspendue, uint32_t maintenant) {
    geste_ = suspendue ? kOrangeLong : kDeuxVerts;
    debutGeste_ = maintenant;
    suspendue_ = suspendue;
    prochain_ = maintenant + kPeriodeMs;
  }

  // Etat du reseau, relu par main.cpp : le motif bleu repart de zero a chaque
  // changement ; le passage a kAttachee lance les eclairs d'adhesion, puis la
  // grille des lueurs.
  void changerReseau(Reseau reseau, uint32_t maintenant) {
    if (reseau == reseau_) return;
    if (reseau == kAttachee) {
      adhesion_ = true;
      debutAdhesion_ = maintenant;
      // Vert, pause, vert, pause, puis la premiere lueur : la grille est
      // calee pour qu'une periode commence la (avant : la fin de la periode
      // d'avant, sans lueur), sans ecart negatif a surveiller.
      debutLueur_ = maintenant + 4 * kVertMs - kLueurPeriodeMs;
    }
    reseau_ = reseau;
    debutReseau_ = maintenant;
  }

  // Identification en cours (session Identify ou effet TriggerEffect, vu par
  // main.cpp) : l'arc-en-ciel part du debut de l'identification, et fait au
  // moins un tour complet meme si elle ne dure qu'un instant. Une nouvelle
  // identification pendant ce tour minimal le prolonge sans repartir.
  void identifier(bool actif, uint32_t maintenant) {
    // Un tour minimal echu mais pas encore oublie par image() ne compte plus.
    const bool tour = tourMinimal_ && maintenant - debutIdent_ < kArcEnCielMs;
    if (actif && !identification_ && !tour) {
      debutIdent_ = maintenant;
      tourMinimal_ = true;
    }
    identification_ = actif;
  }

  // Roue des couleurs a l'intensite kMax : teinte 0..767 (rouge, vert, bleu),
  // celle du pont Halo (statusled::wheel).
  static Rvb roue(uint16_t teinte) {
    teinte %= 768;
    const uint8_t monte = (uint8_t)((teinte % 256) * kMax / 255), descend = (uint8_t)(kMax - monte);
    switch (teinte / 256) {
      case 0: return Rvb{descend, monte, 0};
      case 1: return Rvb{0, descend, monte};
      default: return Rvb{monte, 0, descend};
    }
  }

  // Ce qu'il faut montrer maintenant ; a appeler a chaque tour de loop().
  Image image(uint32_t maintenant) {
    // Echeances d'abord, quel que soit le motif montre.
    const uint32_t tGeste = maintenant - debutGeste_;
    if ((geste_ == kDeuxVerts && tGeste >= 3 * kVertMs) || (geste_ == kOrangeLong && tGeste >= kExtinctionMs))
      geste_ = kAucune;
    const uint32_t tAdhesion = maintenant - debutAdhesion_;
    if (adhesion_ && tAdhesion >= 3 * kVertMs) adhesion_ = false;
    const uint32_t tIdent = maintenant - debutIdent_;
    if (tourMinimal_ && tIdent >= kArcEnCielMs) tourMinimal_ = false;
    const bool eclairSuspendue = suspendue_ && eclairSuspension(maintenant);

    // 1. Identification.
    if (identification_ || tourMinimal_) {
      // Par pas de kPasMs : la couleur ne change que 25 fois par seconde.
      const uint32_t phase = tIdent / kPasMs * kPasMs % kArcEnCielMs;
      return Image{kArcEnCiel, roue((uint16_t)(phase * 768 / kArcEnCielMs))};
    }
    // 2. Geste de l'interrupteur.
    if (geste_ == kDeuxVerts) return deuxVerts(tGeste);
    if (geste_ == kOrangeLong) return Image{kOrange, kOrangeRvb};
    // 3. Bleu.
    const uint32_t tReseau = maintenant - debutReseau_;
    if (reseau_ == kNonMiseEnService)
      return (tReseau / kClignoteMs) % 2 == 0 ? Image{kBleue, Rvb{0, 0, kMax}} : Image{kNoire, Rvb{}};
    if (reseau_ == kDetachee) {
      const uint8_t v = triangle(tReseau % kPulsationMs, kPulsationMs, kMax);
      return v ? Image{kBleue, Rvb{0, 0, v}} : Image{kNoire, Rvb{}};
    }
    // 4. Adhesion (attachee).
    if (adhesion_) return deuxVerts(tAdhesion);
    // 5. Suspendue.
    if (suspendue_) return eclairSuspendue ? Image{kOrange, kOrangeRvb} : Image{kNoire, Rvb{}};
    // 6. Lueur : un triangle en tete de chaque periode de 10 s.
    const uint8_t v = triangle((maintenant - debutLueur_) % kLueurPeriodeMs, kLueurMs, kLueurMax);
    return v ? Image{kBlanche, Rvb{v, v, v}} : Image{kNoire, Rvb{}};
  }

  Couleur couleur(uint32_t maintenant) { return image(maintenant).couleur; }
  Rvb rvb(uint32_t maintenant) { return image(maintenant).rvb; }

 private:
  enum Geste : uint8_t { kAucune, kDeuxVerts, kOrangeLong };
  // Orange : le vert d'une WS2812 parait bien plus fort que son rouge.
  static constexpr Rvb kOrangeRvb{kMax, kMax / 4, 0};

  // Vert, pause, vert, d'une duree kVertMs chacun (t < 3 * kVertMs).
  static Image deuxVerts(uint32_t t) {
    return t / kVertMs == 1 ? Image{kNoire, Rvb{}} : Image{kVerte, Rvb{0, kMax, 0}};
  }

  // Triangle 0 -> sommet -> 0 sur `duree` ms, a la phase `ph` ; 0 au-dela.
  static uint8_t triangle(uint32_t ph, uint32_t duree, uint8_t sommet) {
    const uint32_t demi = duree / 2;
    if (ph >= duree) return 0;
    const uint32_t x = ph < demi ? ph : duree - ph;
    return (uint8_t)((sommet * x + demi / 2) / demi);
  }

  // Bref eclair de la suspension en cours ? Fait avancer la grille de 5 s a
  // chaque appel, meme quand un motif plus prioritaire la masque.
  bool eclairSuspension(uint32_t maintenant) {
    // Ecart depuis le prochain bref eclair : au-dela de 2^31 ms, il est encore
    // a venir (prochain_ n'est jamais a plus d'une periode en avance).
    const uint32_t e = maintenant - prochain_;
    if (e >= 0x80000000u) return false;
    if (e % kPeriodeMs < kBrefMs) return true;
    // Eclair fini (plusieurs si loop() a ete retenue) : le suivant, sur la
    // meme grille de 5 s.
    prochain_ += (e / kPeriodeMs + 1) * kPeriodeMs;
    return false;
  }

  Geste geste_ = kAucune;
  uint32_t debutGeste_ = 0;  // debut du geste de l'interrupteur
  bool suspendue_ = false;
  uint32_t prochain_ = 0;  // debut du prochain bref eclair, ou de celui en cours
  Reseau reseau_ = kNonMiseEnService;
  uint32_t debutReseau_ = 0;  // dernier changement de reseau : depart du motif bleu
  bool adhesion_ = false;
  uint32_t debutAdhesion_ = 0;
  uint32_t debutLueur_ = 0;  // la grille des lueurs part de la
  bool identification_ = false, tourMinimal_ = false;
  uint32_t debutIdent_ = 0;
};

// --- Identification par TriggerEffect (main.cpp) ---------------------------
// Repris du pont Halo (statusled::effectEnd). La pile n'envoie jamais de STOP
// apres un effet : sa fin est datee (millis), 0 = aucun effet. Identifiants de
// la spec Matter (EffectIdentifierEnum, MatterIdentifyRequest::EffectId). Pas
// « identification » : Matter.h rend esp_matter::identification global.
namespace effetIdent {
constexpr uint8_t kBlink = 0x00, kBreathe = 0x01, kOkay = 0x02, kChangementCanal = 0x0B, kFinish = 0xFE,
                  kStop = 0xFF;
constexpr uint32_t kFinishMs = 1000;  // Finish : le cycle en cours s'acheve (1 s au plus)

// Effet en cours a `maintenant` ? Ecart signe : juste a travers le retour a
// zero de millis(), tant qu'une fin echue est oubliee (remise a 0) avant 24,8
// jours.
inline bool enCours(uint32_t fin, uint32_t maintenant) { return fin && (int32_t)(fin - maintenant) > 0; }

// Fin d'effet quand l'effet `effet` arrive a `maintenant`, le precedent
// finissant a `fin`. Stop : fin immediate. Finish : l'effet en cours finit son
// cycle (kFinishMs au plus) et rien ne s'allume sans effet en cours. Les
// autres durent ce que dit la spec (Breathe 15 s, ChangementCanal 8 s), 2 s au
// moins (Blink et Okay y durent a peine une seconde). Jamais 0 pour un effet
// en cours.
inline uint32_t finApres(uint32_t fin, uint8_t effet, uint32_t maintenant) {
  uint32_t ms = 2000;  // Blink, Okay, et tout effet inconnu
  switch (effet) {
    case kStop: return 0;
    case kFinish: {
      if (!enCours(fin, maintenant)) return 0;
      const uint32_t bientot = maintenant + kFinishMs;
      return enCours(fin, bientot) ? (bientot ? bientot : 1) : fin;
    }
    case kBreathe: ms = 15000; break;
    case kChangementCanal: ms = 8000; break;
    default: break;
  }
  const uint32_t e = maintenant + ms;
  return e ? e : 1;  // 0 veut dire « aucun effet »
}
}  // namespace effetIdent
