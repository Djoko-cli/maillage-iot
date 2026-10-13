// Tests hote de sonde/src/distant.{h,cpp} (rid, liste blanche, reponses
// gardees, cadence ; depuis la 1.0.3, entiers des commandes et reprises CoAP
// d'un diag ; depuis la 1.1.0, annonces et resoudre dans la liste blanche) et
// de sonde/src/voyant.h (LED de la carte, 1.0.3 ; tronc commun en 1.1.1 :
// identification, bleus, adhesion, lueur).
// Lancer : sh sonde/test/lancer.sh
#include <stdio.h>
#include <string.h>

#include <string>
#include <vector>

#include "distant.h"
#include "voyant.h"

using namespace distant;

static int gChecks = 0, gFails = 0;
#define CHECK(cond, ...)                              \
  do {                                                \
    gChecks++;                                        \
    if (!(cond)) {                                    \
      gFails++;                                       \
      printf("ECHEC %s:%d : ", __FILE__, __LINE__);   \
      printf(__VA_ARGS__);                            \
      printf("\n");                                   \
    }                                                 \
  } while (0)

static bool rid(const char *texte, uint32_t *r, std::string *cmd) {
  std::vector<char> b(texte, texte + strlen(texte) + 1);
  char *c = nullptr;
  const bool ok = lireRid(b.data(), r, &c);
  if (ok) *cmd = c;
  return ok;
}

static std::vector<std::string> gRendu;
static void rendu(void *, const uint8_t *l, size_t n) { gRendu.emplace_back((const char *)l, n); }

static std::vector<std::string> rendre(Gardees &g, uint32_t r, bool *trouve = nullptr) {
  gRendu.clear();
  const bool t = g.rendre(r, rendu, nullptr);
  if (trouve) *trouve = t;
  return gRendu;
}

static void ajoute(Gardees &g, const std::string &s) { g.ajouter((const uint8_t *)s.data(), s.size()); }

static bool entier(const char *texte, uint32_t attendu) {
  uint32_t v = 12345;
  return lireEntier(texte, &v) && v == attendu;
}

static bool pasEntier(const char *texte) {
  uint32_t v = 12345;
  return !lireEntier(texte, &v) && v == 12345;  // refuse, et v intact
}

// Attente totale d'un diag avant l'echec « delai » : accuse x (2^(r+1) - 1).
static uint64_t attente(Reprises r) { return (uint64_t)r.accuseMs * ((1u << (r.reprises + 1)) - 1); }

// Couleurs de la LED sur [de, a), lues a chaque milliseconde (loop() les lit
// toutes les 5 ms environ) ; a peut suivre le retour a zero. true si toutes
// valent c.
static bool couleurs(Voyant &v, uint32_t de, uint32_t a, Voyant::Couleur c) {
  bool ok = true;
  for (uint32_t t = de; t != a; t++) ok = v.couleur(t) == c && ok;
  return ok;
}

// true si aucune des couleurs de [de, a) ne vaut c.
static bool jamais(Voyant &v, uint32_t de, uint32_t a, Voyant::Couleur c) {
  bool ok = true;
  for (uint32_t t = de; t != a; t++) ok = v.couleur(t) != c && ok;
  return ok;
}

int main() {
  uint32_t r = 0;
  std::string c;
  // rid
  CHECK(rid("0 etat", &r, &c) && r == 0 && c == "etat", "0");
  CHECK(rid("7 diag 0400 0,1 5", &r, &c) && r == 7 && c == "diag 0400 0,1 5", "7 diag");
  CHECK(rid("4294967295 bonjour", &r, &c) && r == 4294967295u, "max");
  CHECK(rid("12", &r, &c) && r == 12 && c.empty(), "rid seul : commande vide");
  CHECK(rid("12 ", &r, &c) && r == 12 && c.empty(), "rid et espace : commande vide");
  CHECK(rid("12  etat", &r, &c) && c == " etat", "deux espaces : la commande garde le second");
  CHECK(!rid("4294967296 etat", &r, &c), "trop grand");
  CHECK(!rid("99999999999 etat", &r, &c), "11 chiffres");
  CHECK(!rid("012 etat", &r, &c), "zero de tete");
  CHECK(!rid("00 etat", &r, &c), "00");
  CHECK(!rid("", &r, &c), "vide");
  CHECK(!rid(" 1 etat", &r, &c), "espace de tete");
  CHECK(!rid("1x etat", &r, &c), "1x");
  CHECK(!rid("-1 etat", &r, &c), "-1");
  CHECK(!rid("+1 etat", &r, &c), "+1");
  CHECK(!rid("1?etat", &r, &c), "1?");
  // texteRid
  char t[kRidMax + 1];
  CHECK(texteRid(0, t) == 1 && !strcmp(t, "0"), "texte 0");
  CHECK(texteRid(4294967295u, t) == 10 && !strcmp(t, "4294967295"), "texte max");
  CHECK(texteRid(1000, t) == 4 && !strcmp(t, "1000"), "texte 1000");
  // liste blanche
  const char *oui[] = {"bonjour", "etat", "voisins", "routeurs", "diag 0400 0 1", "diag ", "  etat", " diag x",
                       "annonces", "resoudre fd00::1 7", "resoudre ", " annonces"};
  const char *non[] = {"", "cle", "cle nouvelle", "cle efface", "nom x", "oubli", "Bonjour", "etat ", "etatx",
                       "diag", "routeur", "voisins x", "bonjour\t", "diagx 1", "routeurs;oubli", "annonces x",
                       "annonce", "resoudre", "resoudrex 1", "Annonces"};
  for (const char *x : oui) CHECK(permise(x), "permise : %s", x);
  for (const char *x : non) CHECK(!permise(x), "refusee : %s", x);

  // Reponses gardees
  static Gardees g;
  bool trouve = true;
  CHECK(rendre(g, 1, &trouve).empty() && !trouve, "vide");
  g.commencer(1);
  ajoute(g, "{\"a\":1}");
  g.terminer();
  CHECK(rendre(g, 1) == std::vector<std::string>{"{\"a\":1}"}, "une ligne");
  ajoute(g, "hors reponse");
  CHECK(rendre(g, 1).size() == 1 && g.reponses() == 1, "ligne hors reponse ignoree");
  g.commencer(2);
  ajoute(g, "L1");
  ajoute(g, "L2");
  ajoute(g, "L3");
  g.terminer();
  CHECK((rendre(g, 2) == std::vector<std::string>{"L1", "L2", "L3"}), "trois lignes dans l'ordre");
  CHECK(g.reponses() == 2, "2 reponses");
  // Commencer sans ligne : rien de garde (un diag qui part).
  g.commencer(3);
  g.terminer();
  CHECK(!(rendre(g, 3, &trouve), trouve) && g.reponses() == 2, "reponse sans ligne : rien");
  // Meme rid recommence : l'ancienne reponse est oubliee.
  g.commencer(1);
  ajoute(g, "neuf");
  g.terminer();
  CHECK(rendre(g, 1) == std::vector<std::string>{"neuf"}, "rid recommence : remplace");
  CHECK((rendre(g, 2) == std::vector<std::string>{"L1", "L2", "L3"}), "les autres restent");
  // 8 reponses au plus : la plus ancienne part.
  g.vider();
  for (uint32_t i = 10; i < 19; i++) {
    g.commencer(i);
    ajoute(g, "r" + std::to_string(i));
    g.terminer();
  }
  CHECK(g.reponses() == 8, "8 au plus (%zu)", g.reponses());
  CHECK(!(rendre(g, 10, &trouve), trouve), "la plus ancienne partie");
  CHECK(rendre(g, 11) == std::vector<std::string>{"r11"} && rendre(g, 18) == std::vector<std::string>{"r18"},
        "les 8 dernieres");
  // Place : les plus anciennes partent, jamais une partie de la reponse en cours.
  g.vider();
  const std::string mille(1000, 'x');
  for (uint32_t i = 20; i < 24; i++) {
    g.commencer(i);
    ajoute(g, mille);
    g.terminer();
  }
  CHECK(g.reponses() == 4 && g.octets() == 4 * 1006, "4 x 1006 octets");
  g.commencer(24);
  ajoute(g, mille);
  g.terminer();
  CHECK(g.reponses() == 4 && !(rendre(g, 20, &trouve), trouve) && rendre(g, 24).size() == 1,
        "la plus ancienne chassee pour la place");
  // Reponse plus grande que kOctets : rien n'en est garde, les autres partent.
  g.commencer(30);
  for (int i = 0; i < 5; i++) ajoute(g, mille);
  g.terminer();
  CHECK(!(rendre(g, 30, &trouve), trouve), "reponse trop grande : pas gardee du tout");
  CHECK(g.octets() <= Gardees::kOctets, "octets bornes (%zu)", g.octets());
  // ... et apres l'abandon, les lignes suivantes de ce rid ne reviennent pas.
  g.commencer(31);
  ajoute(g, "a");
  g.terminer();
  CHECK(rendre(g, 31) == std::vector<std::string>{"a"}, "reponse suivante gardee");
  // Ligne seule plus grande que kOctets.
  g.commencer(32);
  ajoute(g, std::string(Gardees::kOctets, 'y'));
  g.terminer();
  CHECK(!(rendre(g, 32, &trouve), trouve) && rendre(g, 31).size() == 1, "ligne geante : ignoree");
  // Remplissage exact : 4096 octets tout juste.
  g.vider();
  g.commencer(40);
  ajoute(g, std::string(Gardees::kOctets - 6, 'z'));
  g.terminer();
  CHECK(g.octets() == Gardees::kOctets && rendre(g, 40).size() == 1, "remplissage exact");
  g.commencer(41);
  ajoute(g, "b");
  g.terminer();
  CHECK(!(rendre(g, 40, &trouve), trouve) && rendre(g, 41).size() == 1, "le suivant chasse le plein");
  // rid 0 et rid max
  g.vider();
  g.commencer(0);
  ajoute(g, "zero");
  g.commencer(4294967295u);
  ajoute(g, "max");
  g.terminer();
  CHECK(rendre(g, 0) == std::vector<std::string>{"zero"} && rendre(g, 4294967295u) == std::vector<std::string>{"max"},
        "rid 0 et max");
  // Lignes vides
  g.commencer(5);
  ajoute(g, "");
  g.terminer();
  CHECK(rendre(g, 5) == std::vector<std::string>{""}, "ligne vide gardee");
  // oublier(rid) : une reponse qu'on ne veut pas voir rejouee (l'erreur
  // « occupee » d'annonces, 1.1.0) ; les autres restent, et le rid peut revenir.
  g.vider();
  g.commencer(50);
  ajoute(g, "A1");
  ajoute(g, "A2");
  g.terminer();
  g.commencer(51);
  ajoute(g, "B1");
  g.terminer();
  g.commencer(52);
  ajoute(g, "C1");
  ajoute(g, "C2");
  g.terminer();
  g.oublier(51);
  CHECK(!(rendre(g, 51, &trouve), trouve) && g.reponses() == 2, "oublier : la reponse part");
  CHECK((rendre(g, 50) == std::vector<std::string>{"A1", "A2"}) &&
            (rendre(g, 52) == std::vector<std::string>{"C1", "C2"}),
        "oublier : les autres intactes, dans l'ordre");
  g.oublier(50);
  g.oublier(52);
  CHECK(g.reponses() == 0 && g.octets() == 0, "oublier : tout part (%zu octets)", g.octets());
  g.oublier(77);  // inconnue : rien
  CHECK(g.reponses() == 0, "oublier : rid inconnu sans effet");
  g.commencer(51);
  ajoute(g, "B2");
  g.terminer();
  CHECK(rendre(g, 51) == std::vector<std::string>{"B2"}, "oublier : le rid peut revenir");
  // Reponse en cours : oubliee, ses lignes suivantes sont ignorees.
  g.commencer(53);
  ajoute(g, "D1");
  g.oublier(53);
  ajoute(g, "D2");
  g.terminer();
  CHECK(!(rendre(g, 53, &trouve), trouve), "oublier une reponse en cours : rien ne revient");
  // Cadence (copie de Halo) : 20 lignes par seconde glissante.
  Cadence k;
  for (uint32_t i = 0; i < 20; i++) CHECK(k.allow(1000 + i), "ligne %u acceptee", (unsigned)i);
  CHECK(!k.allow(1100), "21e ligne dans la seconde : refusee");
  CHECK(!k.allow(1999), "encore refusee a 999 ms de la premiere");
  CHECK(k.allow(2000), "acceptee une seconde apres la premiere");
  CHECK(!k.allow(2000), "puis refusee (la deuxieme est a 1001)");
  CHECK(k.allow(2001), "acceptee une seconde apres la deuxieme");
  Cadence w;  // retour a zero de millis()
  for (uint32_t i = 0; i < 20; i++) w.allow(0xFFFFFF00u + i);
  CHECK(!w.allow(0xFFFFFFF0u), "retour a zero : refusee dans la seconde");
  CHECK(w.allow(0xFFFFFF00u + 1000u), "retour a zero : acceptee une seconde apres (millis repasse par 0)");

  // Entiers des commandes (1.0.3) : id et delai de diag, id de cle nouvelle.
  CHECK(entier("0", 0) && entier("7", 7) && entier("45000", 45000), "entiers simples");
  CHECK(entier("007", 7) && entier("0000000000", 0), "zeros de tete permis");
  CHECK(entier("4294967295", 4294967295u), "max");
  const char *pasEntiers[] = {"", "4294967296", "99999999999", "00000000001", "-1", "+1", " 1",
                              "1 ", "12x", "x", "0x10", "1.5", "6000ms"};
  for (const char *x : pasEntiers) CHECK(pasEntier(x), "pas un entier : '%s'", x);

  // Reprises CoAP d'un diag (1.0.3) : l'echec tombe au bout du delai demande.
  const Reprises r6 = reprisesDiag(6000), r8 = reprisesDiag(8000);
  CHECK(r6.reprises == 1 && r6.accuseMs == 2000 && r8.reprises == 1 && r8.accuseMs == 2666,
        "6 et 8 s (ceux de l'app) : inchanges");
  CHECK(attente(reprisesDiag(10000)) == 9999 && attente(reprisesDiag(12000)) == 12000,
        "10 a 15 s : plus arrondi a 15 s");
  CHECK(reprisesDiag(14999).reprises == 1 && attente(reprisesDiag(14999)) == 14997, "14999 ms : une reprise");
  CHECK(reprisesDiag(15000).reprises == 3 && reprisesDiag(15000).accuseMs == 1000, "15 s : trois reprises");
  CHECK(reprisesDiag(45000).accuseMs == 3000 && reprisesDiag(60000).accuseMs == 4000, "45 et 60 s");
  CHECK(reprisesDiag(3000).accuseMs == 1000 && attente(reprisesDiag(3000)) == 3000, "3 s : accuse de 1 s");
  CHECK(reprisesDiag(0).accuseMs == 1000 && reprisesDiag(2999).accuseMs == 1000,
        "sous 3 s (main.cpp borne avant) : accuse jamais sous 1 s");
  // Tout delai permis : accuse d'au moins 1 s, attente au plus le delai, a l'arrondi pres.
  uint32_t fautif = 0;
  for (uint32_t d = 3000; d <= 60000 && !fautif; d++) {
    const Reprises rd = reprisesDiag(d);
    const uint64_t a = attente(rd), facteur = (1u << (rd.reprises + 1)) - 1;
    if (rd.accuseMs < 1000 || a > d || d - a >= facteur) fautif = d;
  }
  CHECK(!fautif, "delai %u ms : attente hors du delai", (unsigned)fautif);

  // LED de la carte (1.0.3 ; tronc commun en 1.1.1). V : eclair vert, E :
  // eclair de l'extinction, B : bref eclair de la suspension, P : sa periode.
  using R = Voyant::Rvb;
  const uint32_t V = Voyant::kVertMs, E = Voyant::kExtinctionMs, B = Voyant::kBrefMs, P = Voyant::kPeriodeMs;
  CHECK(V == 100 && E == 500 && B == 100 && P == 5000, "durees : 100, 500, 100 ms et 5 s");
  CHECK(Voyant::kMax == 24 && Voyant::kLueurMax == 8 && Voyant::kLueurPeriodeMs == 10000 && Voyant::kLueurMs == 600,
        "tronc commun : 24/255, lueur 8/255 toutes les 10 s sur 600 ms");
  CHECK(Voyant::kClignoteMs == 250 && Voyant::kPulsationMs == 2000 && Voyant::kArcEnCielMs == 2000 &&
            Voyant::kPasMs == 40,
        "bleu 250 ms / 250 ms, pulsation de 2 s, arc-en-ciel de 2 s par pas de 40 ms");

  // Couleurs exactes du tronc commun.
  {
    Voyant c;
    c.demarrer(false, Voyant::kNonMiseEnService, 0);
    CHECK(c.rvb(0) == (R{0, 0, 24}), "bleu (0,0,24)");
    c.changer(false, 1000);
    CHECK(c.rvb(1000) == (R{0, 24, 0}), "vert (0,24,0)");
    c.changer(true, 2000);
    CHECK(c.rvb(2000) == (R{24, 6, 0}), "orange (24,6,0)");
    Voyant w;
    w.demarrer(false, Voyant::kAttachee, 0);
    CHECK(w.rvb(400 + 300) == (R{8, 8, 8}), "lueur blanche, sommet (8,8,8)");
  }

  // Bleu clignotant tant que la sonde n'est pas mise en service : 250 / 250.
  {
    Voyant b;
    b.demarrer(false, Voyant::kNonMiseEnService, 1000);
    bool ok = true;
    for (uint32_t t = 1000; t < 61000; t++) {
      const bool allume = ((t - 1000) / 250) % 2 == 0;
      ok = b.rvb(t) == (allume ? R{0, 0, 24} : R{}) && ok;
    }
    CHECK(ok, "pas mise en service : bleu 250 ms allume, 250 ms eteint, des le demarrage");
    // Suspendue et pas mise en service : le bleu passe devant l'orange.
    Voyant bs;
    bs.demarrer(true, Voyant::kNonMiseEnService, 0);
    CHECK(jamais(bs, 0, 60000, Voyant::kOrange), "pas mise en service : bleu devant la suspension");
  }

  // Bleu lent, mise en service mais detachee : triangle 0 -> 24 -> 0 sur 2 s.
  {
    Voyant d;
    d.demarrer(false, Voyant::kDetachee, 0);
    CHECK(d.couleur(0) == Voyant::kNoire && d.rvb(1) == R{}, "detachee : la pulsation part de zero");
    CHECK(d.rvb(500) == (R{0, 0, 12}), "detachee : moitie de la montee");
    CHECK(d.rvb(1000) == (R{0, 0, 24}) && d.couleur(1000) == Voyant::kBleue, "detachee : sommet a 1 s");
    CHECK(d.rvb(1500) == (R{0, 0, 12}), "detachee : moitie de la descente");
    CHECK(d.rvb(2000) == R{} && d.rvb(3000) == (R{0, 0, 24}), "detachee : 2 s par pulsation");
    bool ok = true;
    uint8_t avant = 0;
    for (uint32_t t = 4000; t <= 5000; t++) {
      const R c = d.rvb(t);
      ok = c.r == 0 && c.g == 0 && c.b >= avant && c.b <= 24 && ok;
      avant = c.b;
    }
    CHECK(ok, "detachee : bleu seul, montee reguliere, 24 au plus");
    CHECK(jamais(d, 5000, 60000, Voyant::kBlanche) && jamais(d, 5000, 60000, Voyant::kVerte),
          "detachee : ni lueur ni vert");
    // Suspendue et detachee : le bleu passe devant l'orange.
    Voyant ds;
    ds.demarrer(true, Voyant::kDetachee, 0);
    CHECK(jamais(ds, 0, 60000, Voyant::kOrange), "detachee : bleu devant la suspension");
  }

  // Adhesion : deux eclairs verts au passage a attachee, puis la lueur.
  {
    Voyant a;
    a.demarrer(false, Voyant::kDetachee, 0);
    a.changerReseau(Voyant::kAttachee, 10000);
    CHECK(couleurs(a, 10000, 10000 + V, Voyant::kVerte), "adhesion : premier eclair vert");
    CHECK(couleurs(a, 10000 + V, 10000 + 2 * V, Voyant::kNoire), "adhesion : pause");
    CHECK(couleurs(a, 10000 + 2 * V, 10000 + 3 * V, Voyant::kVerte), "adhesion : second eclair vert");
    CHECK(couleurs(a, 10000 + 3 * V, 10000 + 4 * V + 1, Voyant::kNoire), "adhesion : pause avant la lueur");
    CHECK(a.rvb(10400 + 150) == (R{4, 4, 4}), "lueur : moitie de la montee");
    CHECK(a.rvb(10400 + 300) == (R{8, 8, 8}) && a.couleur(10700) == Voyant::kBlanche, "lueur : sommet a 300 ms");
    CHECK(a.rvb(10400 + 450) == (R{4, 4, 4}), "lueur : moitie de la descente");
    CHECK(couleurs(a, 10400 + 600, 20400, Voyant::kNoire), "lueur finie : eteinte jusqu'a 10 s");
    CHECK(a.rvb(20700) == (R{8, 8, 8}), "lueur suivante 10 s plus tard");
    a.changerReseau(Voyant::kAttachee, 30800);
    CHECK(jamais(a, 30800, 31100, Voyant::kVerte) && a.rvb(40700) == (R{8, 8, 8}),
          "deja attachee : ni eclairs ni grille qui repart");
    // Perte du parent : bleu lent, plus de lueur ; rattachee : adhesion de nouveau.
    a.changerReseau(Voyant::kDetachee, 50000);
    CHECK(a.rvb(51000) == (R{0, 0, 24}), "parent perdu : bleu lent, depuis la perte");
    CHECK(jamais(a, 51000, 80000, Voyant::kBlanche), "detachee : plus de lueur");
    a.changerReseau(Voyant::kAttachee, 80000);
    CHECK(couleurs(a, 80000, 80000 + V, Voyant::kVerte) && a.rvb(80700) == (R{8, 8, 8}),
          "rattachee : adhesion puis lueur");
    // Oubli : plus mise en service, le clignotant repart de zero.
    a.changerReseau(Voyant::kNonMiseEnService, 90010);
    CHECK(couleurs(a, 90010, 90260, Voyant::kBleue) && couleurs(a, 90260, 90510, Voyant::kNoire),
          "plus mise en service : bleu clignotant depuis le changement");
    // Mise en service directement attachee : l'adhesion aussi.
    a.changerReseau(Voyant::kAttachee, 100000);
    CHECK(couleurs(a, 100000, 100000 + V, Voyant::kVerte), "mise en service, deja attachee : adhesion");
    // Attachee des le demarrage : l'adhesion aussi.
    Voyant a0;
    a0.demarrer(false, Voyant::kAttachee, 5000);
    CHECK(couleurs(a0, 5000, 5000 + V, Voyant::kVerte), "attachee au demarrage : adhesion");
  }

  // Geste de l'interrupteur, attachee : deux eclairs verts rapides, puis
  // l'orange d'une demi-seconde et les brefs eclairs de la suspension.
  {
    Voyant v;
    v.demarrer(false, Voyant::kAttachee, 0);
    v.changer(false, 40000);
    CHECK(couleurs(v, 40000, 40000 + V, Voyant::kVerte), "premier eclair vert");
    CHECK(couleurs(v, 40000 + V, 40000 + 2 * V, Voyant::kNoire), "pause entre les eclairs verts");
    CHECK(couleurs(v, 40000 + 2 * V, 40000 + 3 * V, Voyant::kVerte), "second eclair vert");
    CHECK(jamais(v, 40000 + 3 * V, 80000, Voyant::kVerte), "apres les eclairs verts : plus de vert");
    // Eteint : un eclair orange d'une demi-seconde, puis un bref toutes les 5 s, jamais de lueur.
    v.changer(true, 100000);
    CHECK(couleurs(v, 100000, 100000 + E, Voyant::kOrange), "extinction : orange 500 ms");
    CHECK(couleurs(v, 100000 + E, 100000 + P, Voyant::kNoire), "puis rien jusqu'a 5 s");
    CHECK(couleurs(v, 100000 + P, 100000 + P + B, Voyant::kOrange), "bref eclair orange a 5 s");
    CHECK(couleurs(v, 100000 + P + B, 100000 + 2 * P, Voyant::kNoire), "puis rien jusqu'a 10 s");
    CHECK(couleurs(v, 100000 + 2 * P, 100000 + 2 * P + B, Voyant::kOrange), "bref eclair orange a 10 s");
    CHECK(jamais(v, 100000, 124000, Voyant::kBlanche), "suspendue : jamais de lueur");
    // Rallume pendant la suspension : les eclairs verts, puis plus d'orange, la lueur revient.
    v.changer(false, 125000);
    CHECK(couleurs(v, 125000, 125000 + V, Voyant::kVerte), "rallumee : vert tout de suite");
    CHECK(jamais(v, 125000 + 3 * V, 200000, Voyant::kOrange), "rallumee : plus d'eclair orange");
    CHECK(v.rvb(200700) == (R{8, 8, 8}), "rallumee : la lueur sur sa grille");
    // Eteint pendant les eclairs verts : l'orange tout de suite.
    v.changer(false, 300000);
    CHECK(v.couleur(300000) == Voyant::kVerte, "eclairs verts en cours");
    v.changer(true, 300000 + V / 2);
    CHECK(couleurs(v, 300000 + V / 2, 300000 + V / 2 + E, Voyant::kOrange), "eteinte pendant le vert : orange");
    // Geste pendant la lueur : le geste passe devant.
    Voyant g;
    g.demarrer(false, Voyant::kAttachee, 0);
    CHECK(g.couleur(10600) == Voyant::kBlanche, "lueur en cours");
    g.changer(false, 10650);
    CHECK(g.couleur(10650) == Voyant::kVerte, "geste devant la lueur");
    // Geste pendant l'adhesion : le geste passe devant.
    Voyant ga;
    ga.demarrer(true, Voyant::kDetachee, 0);
    ga.changerReseau(Voyant::kAttachee, 1000);
    ga.changer(true, 1150);
    CHECK(couleurs(ga, 1150, 1150 + E, Voyant::kOrange), "geste devant l'adhesion");
  }

  // Geste devant le bleu ; la suspension reste sous le bleu.
  {
    Voyant n;
    n.demarrer(false, Voyant::kNonMiseEnService, 0);
    n.changer(false, 1000);
    CHECK(couleurs(n, 1000, 1000 + V, Voyant::kVerte) && couleurs(n, 1000 + V, 1000 + 2 * V, Voyant::kNoire) &&
              couleurs(n, 1000 + 2 * V, 1000 + 3 * V, Voyant::kVerte),
          "geste devant le bleu clignotant (sa pause comprise)");
    CHECK(n.couleur(1500) == Voyant::kBleue, "puis le bleu clignotant sur sa grille");
    n.changer(true, 3000);
    CHECK(couleurs(n, 3000, 3000 + E, Voyant::kOrange), "extinction devant le bleu");
    CHECK(jamais(n, 3000 + E, 30000, Voyant::kOrange), "suspendue sous le bleu : pas d'eclair orange");
    Voyant dl;
    dl.demarrer(false, Voyant::kDetachee, 0);
    dl.changer(false, 1000);
    CHECK(couleurs(dl, 1000, 1000 + V, Voyant::kVerte), "geste devant le bleu lent");
  }

  // Bleu devant l'adhesion : rattachee puis detachee pendant les eclairs.
  {
    Voyant ba;
    ba.demarrer(false, Voyant::kDetachee, 0);
    ba.changerReseau(Voyant::kAttachee, 5000);
    CHECK(ba.couleur(5000) == Voyant::kVerte, "adhesion en cours");
    ba.changerReseau(Voyant::kDetachee, 5050);
    CHECK(jamais(ba, 5050, 5300, Voyant::kVerte), "de nouveau detachee : le bleu devant l'adhesion");
  }

  // Adhesion devant la suspension ; la grille de 5 s avance sous le bleu, meme
  // masquee plus de 24,8 jours.
  {
    Voyant s;
    s.demarrer(true, Voyant::kDetachee, 0);
    const uint32_t A = 2200000000u;  // multiple de 5 s, au-dela de 2^31 ms
    for (uint32_t t = 0; t < A; t += 1000) s.couleur(t);
    s.changerReseau(Voyant::kAttachee, A);
    CHECK(couleurs(s, A, A + V, Voyant::kVerte), "adhesion devant la suspension");
    CHECK(couleurs(s, A + 3 * V, A + P, Voyant::kNoire), "suspendue, attachee : ni lueur ni eclair hors de l'heure");
    CHECK(couleurs(s, A + P, A + P + B, Voyant::kOrange), "bleu 25 jours : bref eclair toujours a l'heure");
  }

  // Identification : arc-en-ciel, un tour de 2 s par pas de 40 ms, devant tout.
  {
    CHECK(Voyant::roue(0) == (R{24, 0, 0}) && Voyant::roue(256) == (R{0, 24, 0}) &&
              Voyant::roue(512) == (R{0, 0, 24}) && Voyant::roue(128) == (R{12, 12, 0}),
          "roue du pont Halo : rouge, vert, bleu, 24 au plus");
    Voyant i;
    i.demarrer(false, Voyant::kAttachee, 0);
    i.identifier(true, 1000);
    CHECK(i.rvb(1000) == (R{24, 0, 0}) && i.rvb(1039) == (R{24, 0, 0}), "arc-en-ciel : part du rouge, pas de 40 ms");
    CHECK(i.rvb(1040) == Voyant::roue(40 * 768 / 2000), "arc-en-ciel : pas suivant a 40 ms");
    CHECK(i.rvb(1500) == Voyant::roue(480 * 768 / 2000) && i.rvb(2000) == Voyant::roue(384),
          "arc-en-ciel : 768 teintes en 2 s, par pas de 40 ms");
    CHECK(i.rvb(3000) == (R{24, 0, 0}) && i.rvb(3500) == Voyant::roue(480 * 768 / 2000),
          "arc-en-ciel : un tour toutes les 2 s");
    bool ok = true;
    for (uint32_t t = 3000; t < 9000; t++) {
      i.identifier(true, t);
      ok = i.couleur(t) == Voyant::kArcEnCiel && ok;
    }
    CHECK(ok, "arc-en-ciel pendant toute l'identification");
    i.identifier(false, 9000);
    CHECK(i.couleur(9000) != Voyant::kArcEnCiel, "identification finie apres un tour : arc-en-ciel fini");
    // Identification d'un instant : au moins un tour complet.
    i.identifier(true, 20000);
    i.identifier(false, 20005);
    ok = true;
    for (uint32_t t = 20005; t < 22000; t++) {
      i.identifier(false, t);
      ok = i.couleur(t) == Voyant::kArcEnCiel && ok;
    }
    CHECK(ok, "identification d'un instant : un tour complet de 2 s");
    CHECK(i.couleur(22000) != Voyant::kArcEnCiel, "puis fini");
    // Reprise pendant le tour minimal : il se prolonge sans repartir du rouge.
    i.identifier(true, 30000);
    i.identifier(false, 30100);
    i.identifier(true, 30500);
    CHECK(i.rvb(30500) == Voyant::roue(480 * 768 / 2000), "reprise pendant le tour : pas de saut de teinte");
    i.identifier(false, 31000);
    CHECK(i.couleur(31999) == Voyant::kArcEnCiel && i.couleur(32000) != Voyant::kArcEnCiel,
          "reprise puis fin : le tour minimal compte depuis le debut");
    // Nouvelle demande juste apres l'echeance d'un tour minimal, avant que
    // image() l'ait oublie : un nouveau tour part, depuis le rouge.
    Voyant e;
    e.demarrer(false, Voyant::kAttachee, 0);
    e.identifier(true, 1000);
    e.identifier(false, 1020);
    e.identifier(true, 3005);
    CHECK(e.rvb(3005) == Voyant::roue(0), "nouveau tour : depuis le rouge");
    e.identifier(false, 3045);
    CHECK(e.couleur(3045) == Voyant::kArcEnCiel && e.couleur(5004) == Voyant::kArcEnCiel,
          "demande juste apres un tour echu : un nouveau tour complet");
    // Devant tout : geste, bleu des deux sortes, adhesion, suspension.
    Voyant t1;
    t1.demarrer(false, Voyant::kNonMiseEnService, 0);
    t1.identifier(true, 0);
    CHECK(jamais(t1, 0, 3000, Voyant::kBleue), "identification devant le bleu clignotant");
    t1.changer(false, 3000);
    CHECK(couleurs(t1, 3000, 3300, Voyant::kArcEnCiel), "identification devant le geste");
    t1.changerReseau(Voyant::kDetachee, 4000);
    CHECK(jamais(t1, 4000, 6000, Voyant::kBleue), "identification devant le bleu lent");
    t1.changerReseau(Voyant::kAttachee, 6000);
    t1.changer(true, 6000);
    CHECK(couleurs(t1, 6000, 12000, Voyant::kArcEnCiel), "identification devant l'adhesion et la suspension");
    // Les echeances passent sous l'arc-en-ciel : ni geste ni adhesion ensuite.
    t1.identifier(false, 12000);
    CHECK(jamais(t1, 12000, 14000, Voyant::kVerte), "geste et adhesion echus sous l'arc-en-ciel");
    // Effets TriggerEffect (repris du pont Halo) : Blink et Okay 2 s, Breathe
    // 15 s, ChangementCanal 8 s, Stop tout de suite, Finish 1 s au plus.
    using namespace effetIdent;
    CHECK(finApres(0, kBlink, 1000) == 3000 && finApres(0, kOkay, 1000) == 3000, "Blink, Okay : 2 s");
    CHECK(finApres(0, kBreathe, 1000) == 16000 && finApres(0, kChangementCanal, 1000) == 9000,
          "Breathe 15 s, ChangementCanal 8 s");
    CHECK(finApres(16000, kStop, 2000) == 0, "Stop : fin immediate");
    CHECK(finApres(16000, kFinish, 2000) == 3000 && finApres(2500, kFinish, 2000) == 2500 &&
              finApres(0, kFinish, 2000) == 0,
          "Finish : 1 s au plus, rien sans effet en cours");
    CHECK(finApres(0, kBlink, 0xFFFFF830u) == 1, "fin a zero : 1 (0 veut dire aucun effet)");
    CHECK(enCours(3000, 2999) && !enCours(3000, 3000) && !enCours(0, 0) && enCours(100, 0xFFFFFF00u),
          "effet en cours : ecart signe, a travers le retour a zero");
  }

  // Suspendue, loop() retenue : l'eclair en cours se voit encore, les
  // echeances passees sont sautees. (Attachee : le premier eclair, sous
  // l'adhesion, ne se voit pas.)
  Voyant lent;
  lent.demarrer(true, Voyant::kAttachee, 0);
  CHECK(lent.couleur(0) == Voyant::kVerte, "adhesion devant le premier eclair");
  CHECK(lent.couleur(3 * P + B / 2) == Voyant::kOrange, "retenue 15 s : l'eclair en cours");
  CHECK(lent.couleur(3 * P + B) == Voyant::kNoire && lent.couleur(4 * P - 1) == Voyant::kNoire,
        "retenue : rien jusqu'au suivant");
  CHECK(lent.couleur(4 * P) == Voyant::kOrange, "retenue : le suivant a l'heure");
  CHECK(lent.couleur(7 * P + P / 2) == Voyant::kNoire && lent.couleur(8 * P) == Voyant::kOrange,
        "retenue entre deux eclairs : recalee sur la periode");
  // Retour a zero de millis() : les eclairs continuent ; une sequence finie ne revient pas.
  Voyant z;
  const uint32_t Z = 0xFFFFF000u;
  z.demarrer(true, Voyant::kAttachee, Z);
  CHECK(couleurs(z, Z + 4 * V, Z + P, Voyant::kNoire), "zero : rien en passant par 0");
  CHECK(couleurs(z, Z + P, Z + P + B, Voyant::kOrange), "zero : eclair a l'heure apres");
  Voyant y;
  y.demarrer(false, Voyant::kDetachee, 0xFFFF0000u);
  y.changer(false, 0xFFFFFFF0u);
  CHECK(couleurs(y, 0xFFFFFFF0u, 0xFFFFFFF0u + V, Voyant::kVerte), "zero : eclair vert a cheval");
  CHECK(jamais(y, 0xFFFFFFF0u + 3 * V, 1000, Voyant::kVerte), "zero : fin des eclairs verts");
  CHECK(jamais(y, 0xFFFFFFF0u, 0xFFFFFFF0u + 3 * V, Voyant::kVerte),
        "sequence finie : pas ranimee quand millis() repasse par les memes valeurs");
  // Suspendue plus de 49,7 jours, un tour toutes les 2,5 s : un eclair toutes les
  // 5 s de temps reel, avant, pendant et apres le retour a zero de millis()
  // (sauf le premier, sous l'adhesion).
  Voyant longue;
  longue.demarrer(true, Voyant::kAttachee, 0);
  uint64_t horsDeLHeure = 0, eclairs = 0;
  for (uint64_t reel = 0; reel < (1ull << 32) + 3 * P; reel += 2500) {
    const bool orange = longue.couleur((uint32_t)reel) == Voyant::kOrange;
    eclairs += orange;
    if (orange != (reel % P == 0 && reel != 0)) horsDeLHeure++;
  }
  CHECK(!horsDeLHeure && eclairs == ((1ull << 32) + 3 * P - 1) / P,
        "suspendue 50 jours : %llu tour(s) hors de l'heure, %llu eclairs", (unsigned long long)horsDeLHeure,
        (unsigned long long)eclairs);
  // Attachee plus de 49,7 jours : la lueur ne s'arrete pas.
  Voyant veille;
  veille.demarrer(false, Voyant::kAttachee, 0);
  uint64_t lueurs = 0;
  for (uint64_t reel = 0; reel < (1ull << 32) + 60000; reel += 100)
    lueurs += veille.couleur((uint32_t)reel) == Voyant::kBlanche;
  CHECK(lueurs >= ((1ull << 32) + 60000) / 10000 * 4, "attachee 50 jours : la lueur continue (%llu)",
        (unsigned long long)lueurs);

  // reponse d'echo ICMPv6 (1.1.1) : type 129 et identifiant sur 16 bits, gros-boutiste
  const uint8_t id7[4] = {0x00, 0x07, 0x00, 0x01};
  const uint8_t id1234[4] = {0x12, 0x34, 0x00, 0x09};
  CHECK(reponseEcho(129, id7, 7), "echo : reponse, id 7");
  CHECK(reponseEcho(129, id1234, 0x1234), "echo : id gros-boutiste");
  CHECK(reponseEcho(129, id1234, 0x51234u), "echo : id tronque sur 16 bits, comme l'envoi");
  CHECK(!reponseEcho(128, id7, 7), "echo : une demande n'est pas une reponse");
  CHECK(!reponseEcho(1, id7, 7), "echo : destination injoignable");
  CHECK(!reponseEcho(129, id7, 8), "echo : autre identifiant");
  CHECK(!reponseEcho(129, id1234, 0x3412), "echo : octets inverses");

  printf("test_distant : %d verification(s), %d echec(s)\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
