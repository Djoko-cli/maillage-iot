# Maillage IoT, phase 10 : une pièce dans plusieurs zones de Maison — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une pièce que Maison range dans plusieurs zones va dans sa zone la plus précise, et un clic droit sur la pièce permet de choisir sa zone, choix gardé.

**Architecture:** `ScenePieces.init` choisit la zone de chaque pièce (choix gardé, sinon la zone qui a le moins de pièces, sinon l'ordre de Maison) au lieu de la première ; `PlacesGardees` garde les choix par maison ; le menu du clic droit de la vue par pièces gagne une cible « pièce ».

**Tech Stack:** Swift 6 strict, SwiftUI, Swift Testing, XcodeGen.

**Conception (décisions de Djoko du 20/10, voie courte) :**
- Constat : `MaillageCoeur/Scene/ScenePieces.swift` (boucle `for z in fusionnees`, ~l.171) range une pièce de plusieurs zones dans la **première** zone (ordre de Maison). Une zone dont toutes les pièces sont prises par une zone précédente n'a plus de plateau (`guard !dedans.isEmpty`), et avec lui disparaît son menu « Hors de la maison ». Cas réel : une pièce extérieure, seule pièce d'une zone « Extérieur », ajoutée aussi à une zone d'étage.
- **Règle 1** : une pièce de plusieurs zones va dans sa zone la plus précise, celle qui a **le moins de pièces** dans Maison (pièces distinctes de la zone après la fusion des zones de même nom, montrées ou non). À égalité, la première dans l'ordre de Maison.
- **Règle 2** : clic droit sur une pièce → « Ranger dans la zone… », un sous-menu de ses zones. Le choix est gardé et l'emporte sur la règle 1. Un premier article, « Automatiquement », oublie le choix et revient à la règle 1.
- Le choix de place d'une zone (à côté, hors de la maison) est déjà gardé par sa clé : il revient quand la zone retrouve une pièce. Rien à faire pour lui, sauf le vérifier par un test.
- Hors sujet : changer les zones de Maison ; ranger une pièce dans une zone qui ne la contient pas.

## Global Constraints

- Une pièce présente dans une seule zone, ou dans aucune (« Autres pièces »), est rangée comme avant : les maisons sans pièce partagée ne voient aucun changement.
- Un choix gardé qui ne désigne plus une zone de la pièce (zone renommée, pièce retirée de la zone) est ignoré : la règle 1 s'applique. Le choix reste dans le fichier, comme les places.
- `PlacesGardees` : nouveau champ facultatif par maison, lu sans perte depuis un fichier d'avant et non écrit quand il est vide, comme `aCote` ; `versionActuelle` ne change pas.
- Textes en français et en anglais (catalogue) : « Ranger dans la zone… » / « Move to Zone… », « Automatiquement » / « Automatically ».
- Swift 6 strict, avertissements = erreurs ; aucune valeur réelle (zones et pièces de test inventées : « Zone 1 », « Pièce 1 », ou celles de la démo).
- Les références de rejeu `docs/rejeu/*.json` restent identiques à l'octet. Si la démo a une pièce dans plusieurs zones et que sa référence change, s'arrêter et le dire.
- Les tests n'utilisent jamais `UserDefaults.standard` ni le vrai fichier des places.
- Porte de chaque tâche : `bash outils/tester-coeur.sh` (tâche 1), `bash outils/tester.sh` (tâche 2 ; **aucune app Maillage IoT ne tourne**, sinon `NomsPasseurTests` fait avorter la suite), `bash outils/controler-index.sh` → 0, et la passe anglaise (`-testLanguage en -testRegion US`).
- Commentaires sans accents ; commits en français sans accents, terminés par `Co-Authored-By:` du modèle ; jamais de push ni de `--no-verify`. Cases du plan cochées et commitées avec le travail.

## Review Focus

1. **Une maison sans pièce partagée qui change** : même scène, mêmes étages, même ordre qu'avant (Task 1, test de non-régression sur la démo et sur une maison à zones simples).
2. **Une zone qui disparaît encore** : la zone « Extérieur » d'une seule pièce garde son plateau quand la pièce est aussi dans une zone d'étage plus grande (Task 1).
3. **Un choix gardé périmé** qui place une pièce dans une zone qui ne la contient plus (Task 1).
4. **Un fichier de places d'avant** lu avec perte, ou un fichier sans choix réécrit avec un champ vide (Task 1).
5. **Le clic droit qui vise la mauvaise pièce**, ou un menu qui agit après le remplacement de la scène pendant qu'il est ouvert : la cible est désignée par la clé de la pièce, jamais par un indice (Task 2).

---

### Task 1: La règle et le choix gardé (cœur)

**Files:**
- Modify: `MaillageCoeur/Scene/ScenePieces.swift` (choix de la zone de chaque pièce), `MaillageCoeur/Scene/PlacesGardees.swift` (champ des choix par maison)
- Test: `MaillageCoeurTests/ScenePiecesTests.swift`, `MaillageCoeurTests/PlacesGardeesTests.swift`

**Interfaces:**
- Produces :
  - `ScenePieces.init(…, zonesChoisies: [String: String] = [:], …)` : nom de pièce → nom de zone choisi. Paramètre ajouté avec une valeur par défaut, à côté de `aCote`.
  - `PlacesGardees.Maison.zones: [String: String]`, champ facultatif (clé de codage `zones`).
  - `PlacesGardees.choisirZone(_ zone: String?, piece: String, domicile: String)` : `nil` oublie le choix.
  - `PlacesGardees.zonesChoisies(_ domicile: String) -> [String: String]`.
  - `ScenePieces.zonesDe(_ piece: String) -> [String]` : les zones de Maison qui contiennent la pièce (ordre de Maison, après fusion), pour le menu ; vide si la scène n'a pas de zones. Le constructeur choisit où le garder (propriété calculée à la construction).
  - `ScenePieces.zoneChoisie(_ piece: String) -> String?` : le choix gardé qui s'applique (`nil` si aucun, ou périmé), pour la coche du menu.

- [x] **Step 1: Tests RED**
  - Une pièce dans « Zone A » (3 pièces) et « Zone B » (1 pièce) va dans B, quel que soit l'ordre de Maison ; « Zone B » garde son plateau.
  - À égalité de taille, la première dans l'ordre de Maison.
  - Avec `zonesChoisies` = A, elle va dans A ; avec un choix périmé (zone qui ne la contient pas, ou inconnue), la règle 1.
  - Une zone dont aucune pièce n'est rangée chez elle n'a pas de plateau (comportement inchangé).
  - Non-régression : une maison sans pièce partagée donne la même scène qu'avant (étages, pièces, ordre), et la scène de la démo combinée aussi.
  - `zonesDe` et `zoneChoisie` pour une pièce partagée, une pièce simple et une pièce sans zone.
  - `PlacesGardees` : aller-retour avec des choix ; un fichier d'avant (sans `zones`) se lit sans perte ; sans choix, le JSON écrit n'a pas de clé `zones` ; `choisirZone(nil, …)` oublie le choix ; `zones` mal formé est ignoré sans perdre l'ordre ni les places.
  - Le choix « à côté / hors de la maison » d'une zone revient quand la zone retrouve une pièce (un test qui le montre de bout en bout dans `ScenePieces`).
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — `bash outils/tester-coeur.sh`, `bash outils/controler-index.sh` → 0, références de rejeu inchangées (`git diff --exit-code docs/rejeu`).
- [x] **Step 4: Commit** — « Zones : une piece de plusieurs zones va dans la plus precise, choix garde ».

---

### Task 2: « Ranger dans la zone… » au clic droit (app)

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/MoteurPieces.swift` (`CibleMenu`), `MoteurPieces+Gestes.swift` (`cible(en:)`), `FenetrePieces.swift` (`MenuPieces`), `EntreeScene.swift` ou l'endroit qui passe `aCote` à `ScenePieces` (passer aussi `zonesChoisies`), un nouveau `moteur.rangerPiece(_:dans:)` à côté de `basculerDehors`, catalogue `Localizable.xcstrings`
- Test: `MaillageIoTTests/MenuZonesPieceTests.swift` (nouveau), et les tests du menu existants s'il faut

**Interfaces:**
- Consumes : Task 1 (`zonesChoisies`, `PlacesGardees.choisirZone`, `zonesDe`, `zoneChoisie`).
- Produces : `CibleMenu.piece(String)` (clé de la pièce) ; `MoteurPieces.rangerPiece(_ piece: String, dans zone: String?)` : garde le choix (fichier des places, comme les autres choix du menu), puis recalcule la scène.

- [ ] **Step 1: Tests RED**
  - Un clic droit sur une pièce donne `.piece(cle)` (avant : `.aucune`) ; sur un appareil, toujours `.aucune` ; le nom d'un étage, un disque et le fond ne changent pas.
  - Le menu d'une pièce : son nom en tête, grisé ; « Ranger dans la zone… » avec « Automatiquement » (coché sans choix gardé), un séparateur, puis ses zones (cochée : celle où elle est rangée quand un choix s'applique) ; sous-menu grisé pour une pièce d'une seule zone ou sans zone.
  - `rangerPiece` : la pièce passe dans la zone choisie, le choix est écrit dans les places (fichier de test isolé), il survit à une nouvelle scène ; « Automatiquement » l'oublie et la règle 1 revient.
  - La cible garde la clé : une scène remplacée pendant que le menu est ouvert ne fait pas viser une autre pièce.
  - Textes fr et en.
- [ ] **Step 2: GREEN** — implémenter (menu natif, comme le menu d'un plateau).
- [ ] **Step 3: Vérifier** — `bash outils/tester.sh` (app quittée), `bash outils/controler-index.sh` → 0, passe anglaise.
- [ ] **Step 4: Commit** — « Zones : ranger une piece dans une de ses zones au clic droit ».

---

### Task 3: Relecture et banc

- [ ] **Step 1: Relecture** — Sonnet par tâche, Opus sur la branche.
- [ ] **Step 2: Banc** — avec Djoko, sur sa maison réelle : la pièce extérieure retrouve sa zone et son menu « Hors de la maison » ; le clic droit range une pièce ailleurs et le choix tient après un relancement.
- [ ] **Step 3: Verdict** — cocher « Phase 10 » dans la §6.1 de la spec ; fusion et push avec l'accord de Djoko.
