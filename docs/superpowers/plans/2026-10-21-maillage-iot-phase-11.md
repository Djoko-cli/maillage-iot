# Maillage IoT, phase 11 : un seul mouvement quand une pièce change de plateau — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quand une pièce passe d'un plateau à un autre, la vue joue un seul mouvement fluide : la pièce glisse, le plateau qui part s'efface, celui qui arrive apparaît, et après un choix fait dans la vue les plateaux non concernés ne bougent pas.

**Architecture:** Après un choix du menu du clic droit, le calcul suivant de `DispositionPieces` fixe les pièces des plateaux inchangés à leur position calculée ; le moteur garde les plateaux partis pendant la transition, pour la pose des pièces et le dessin, avec une opacité sur la rampe du glissement.

**Tech Stack:** Swift 6 strict, SwiftUI, Swift Testing, XcodeGen.

**Conception (banc et décisions de Djoko du 21/10) :**
- Constat de banc (phase 10) : une pièce rangée dans une autre zone saute d'un coup. Le plateau quitté disparaît, ou celui d'arrivée apparaît vide, avant le glissement, puis toutes les pièces se réarrangent, celles des étages non concernés comprises.
- Diagnostic (prouvé par une trace, rapport local `.superpowers/a-faire/transition-zones-diagnostic.md`) :
  1. une seule scène, un seul calcul, une seule transition ; mais la géométrie visée ne connaît que les plateaux de la nouvelle scène, et `PosesScene.centre` ignore une ancre sur un plateau absent : le plateau qui part disparaît à la première image, la pièce saute à sa place d'arrivée, et le plateau qui arrive est posé plein dès le départ ;
  2. `DispositionPieces` est global (coût de toute la maison, tours et budget partagés) : changer les pièces d'un plateau change le résultat des autres ;
  3. en 2D, les plateaux glissent en `CameraScene.dureeCases` (0,4 s) et les pièces en 0,9 s : deux temps.
- **Décision de Djoko (option B)** : les plateaux inchangés gardent leur place **après un choix fait dans la vue** : « Ranger dans la zone… » et les choix de niveau du menu d'un plateau (« Monter / Descendre d'un étage », « Au même niveau que », « Hors de la maison », « Sur son propre niveau »). Au lancement, et après un changement venu de Maison, Thread ou Zigbee, la disposition reste calculée librement, comme aujourd'hui. « Replacer les pièces automatiquement » recalcule tout, sans rien fixer. Rien de nouveau dans le fichier des places.
- Hors sujet : rendre la disposition de chaque plateau indépendante ; garder la disposition au relancement.

## Global Constraints

- Un plateau est **inchangé** quand sa clé, ses pièces et leurs nœuds (`cleDisposition.pieces[cle]`) et sa place de niveau (`cleDisposition.niveaux[cle]`) sont les mêmes que ceux de la disposition affichée (`cleCalculee`). Ses pièces sont fixées à leur position de `placesCalculees`, ajoutées à `places.fixees` (une place gardée à la main l'emporte).
- La marque « choix fait dans la vue » vaut pour le prochain calcul seulement, puis s'efface ; un calcul abandonné (scène suivante de structure différente avant la fin) la garde pour le suivant.
- Avec « Réduire les animations », tout se pose d'un coup, sans plateau parti ni fondu (comportement actuel).
- Un plateau parti ne se clique pas, ne se survole pas, n'entre ni dans le menu du clic droit, ni dans le cadrage, la sphère ou la boîte de la vue.
- Swift 6 strict, avertissements = erreurs ; aucun `nonisolated(unsafe)` ni `@unchecked Sendable` ajouté ; aucune valeur réelle (scènes inventées : « Zone 1 », « Pièce 1 », ou la démo).
- Références de rejeu `docs/rejeu/*.json` identiques à l'octet ; captures inchangées sauf raison dite au rapport.
- Tests sans `UserDefaults.standard` ni vrai fichier des places.
- Porte : suites ciblées par `xcodebuild … -only-testing:` pendant les tâches (une app Maillage IoT tourne) ; `bash outils/tester-coeur.sh` ; `bash outils/controler-index.sh` → 0. La porte complète `bash outils/tester.sh` et la passe anglaise sont lancées par le contrôleur, l'app quittée.
- Commentaires sans accents ; commits en français sans accents, terminés par `Co-Authored-By:` du modèle ; jamais de push ni de `--no-verify`. Cases du plan cochées et commitées avec le travail.

## Review Focus

1. **Une disposition au lancement qui change** : sans choix dans la vue, le calcul est exactement celui d'avant (Task 1).
2. **Une marque qui traîne** : un changement de Maison arrivé après un choix, une fois ce choix posé, rearrange librement (Task 1).
3. **Un plateau parti qui reste** après la fin de la transition, ou qu'une transition interrompue (nouvelle scène, vol, envol, glisser) laisse affiché (Task 2).
4. **Une pièce qui saute encore** : un plateau qui part et un qui arrive dans le même mouvement ; un aller-retour rapide ; la 2D et la 3D ; pièce isolée ou étage isolé pendant le choix (Task 2).
5. **Les choix de niveau du menu d'un plateau** (qui passent par le même chemin) : un seul mouvement en 2D, plateaux et pièces à la même durée, sans régression des tests existants de ces choix (Task 2).

---

### Task 1: Les plateaux inchangés gardent leur place après un choix dans la vue

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/MoteurPieces+Scene.swift` (`rangerPiece`, `ranger`, `calculer`, `installerMaintenant`, `replacerPieces`), `MoteurPieces.swift` (la marque)
- Test: `MaillageIoTTests/PlateauxInchangesTests.swift` (nouveau)

**Interfaces:**
- Produces : `MoteurPieces.fixerInchanges` (marque, `Bool`, posée par `rangerPiece` et `ranger`, effacée par le calcul qui la prend et par `replacerPieces`) ; `MoteurPieces.fixeesInchangees(_ e: EntreeScene) -> [Int: SIMD2<Double>]` (indices de pièces de la scène `e` → position calculée, pour les plateaux inchangés).

- [x] **Step 1: Tests RED** — scène inventée : « Zone 1 » (plusieurs pièces), « Zone 2 » (une seule pièce P, aussi dans « Zone 1 », à côté et hors de la maison), « Zone 3 » et « Zone 4 » (autres pièces).
  - Après `rangerPiece(P, dans: "Zone 1")` puis la scène suivante, les positions locales des pièces des Zones 3 et 4 sont identiques au bit près ; même chose au retour (« Automatiquement »).
  - Même chose après `basculerDehors` et `mettreAuNiveau` sur un plateau.
  - Sans choix (scène suivante venue d'un changement de Maison), le calcul est libre : mêmes positions que `DispositionPieces` sans fixées supplémentaires.
  - La marque ne vaut qu'une fois ; un calcul abandonné la garde ; `replacerPieces` l'efface et recalcule tout.
  - Une place gardée à la main l'emporte sur une position fixée.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — suites ciblées (nouvelle suite, disposition, menus des plateaux, zones, démo), `bash outils/tester-coeur.sh`, `bash outils/controler-index.sh` → 0, `git diff --exit-code docs/rejeu`.
- [x] **Step 4: Commit** — « Pieces : apres un choix dans la vue, les plateaux inchanges gardent leur place ».

---

### Task 2: Le plateau qui part s'efface, la pièce glisse

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/MoteurPieces+Scene.swift` (`installer`), `MoteurPieces+Camera.swift`, `MoteurPieces+Image.swift` (fin de transition), `TransitionScene.swift` (`PosesScene.centre`), `SceneProjetee.swift` (plateaux partis, opacités), le dessin des plateaux et de leurs noms
- Test: `MaillageIoTTests/PlateauxPartisTests.swift` (nouveau)

**Interfaces:**
- Consumes : Task 1 (rien de plus que la scène de test).
- Produces : les plateaux partis, gardés par le moteur pendant la transition (centre, rayon, nom), à côté de `apparencesParties` et `nomsPartis` ; une opacité par plateau dans `SceneProjetee`.

- [ ] **Step 1: Tests RED** — même scène que la tâche 1, en 2D et en 3D.
  - Aller : à t = 0 de la transition, le centre de P est sa place d'avant, sur le plateau parti ; à mi-chemin, entre les deux ; à la fin, sa place d'arrivée.
  - Le plateau parti est dessiné à t = 0 avec une opacité de 1, entre 0 et 1 à mi-chemin, absent à la fin ; son nom aussi.
  - Retour : le plateau qui arrive a une opacité de 0 à t = 0, de 1 à la fin.
  - Le plateau parti n'est ni cliquable, ni survolable, ni dans le menu, ni dans le cadrage.
  - Une nouvelle scène, un vol, un envol ou un glisser pendant la transition ne laisse aucun plateau parti affiché.
  - Avec « Réduire les animations », tout est posé d'un coup.
  - En 2D, quand une transition de disposition accompagne un changement de niveaux, plateaux et pièces glissent sur la même durée (celle du glissement) ; les tests existants des choix de niveau du menu restent verts ou sont mis à jour pour cette seule durée.
- [ ] **Step 2: GREEN** — implémenter (voie du diagnostic : plateaux partis hors de `GeometrieMaison`, gardés par le moteur).
- [ ] **Step 3: Vérifier** — suites ciblées (nouvelle suite, transitions, disposition, isolement, menus, caméra, démo, captures), `bash outils/tester-coeur.sh`, `bash outils/controler-index.sh` → 0, `git diff --exit-code docs/rejeu`.
- [ ] **Step 4: Commit** — « Pieces : le plateau qui part s'efface et la piece glisse, en un seul mouvement ».

---

### Task 3: Relecture et banc

- [ ] **Step 1: Porte et relecture** — porte complète et passe anglaise (app quittée) ; relecture Opus de la branche.
- [ ] **Step 2: Banc** — avec Djoko, sur sa maison réelle, en 2D et en 3D : « Ranger dans la zone… » aller et retour, et un choix de niveau d'un plateau. Si le mouvement dure encore environ 2 s au lieu de 0,9 s, journaliser `installer` et `retenir` (heure, clé) et la durée des images pendant la transition, pour trancher entre une cadence faible et une pause avant la première image.
- [ ] **Step 3: Verdict** — cocher « Phase 11 » dans la §6.1 de la spec ; fusion et push avec l'accord de Djoko.
