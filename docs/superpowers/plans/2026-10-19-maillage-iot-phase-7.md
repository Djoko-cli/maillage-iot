# Maillage IoT, phase 7 : pièce proposée aux HomePod et à l'Apple TV — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Proposer, dans la fiche d'un HomePod ou d'une Apple TV sans pièce, la pièce que contient son nom AirPlay, à confirmer d'un clic.

**Architecture:** Le recenseur Thread écoute aussi `_airplay._tcp` ; un modèle pur rattache chaque service AirPlay à un routeur de bordure par nom d'hôte et en tire une pièce connue de Maison ; la fiche montre la proposition et réutilise le placement manuel existant.

**Tech Stack:** Swift 6 strict, SwiftUI, Network/dnssd, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-piece-airplay-design.md` (binding).

## Global Constraints

- Rattachement par nom d'hôte mDNS seulement ; proposition seulement pour une pièce connue de Maison, mot entier, sans casse ni accents, la plus longue ; jamais pour un nœud qui a déjà une pièce ; jamais de placement automatique.
- « Placer ici » = le placement manuel existant (`PiecesChoisies`) ; « Ignorer » mémorisé, tant que le nom AirPlay ne change pas.
- `_airplay._tcp` dans `NSBonjourServices` (app et répétition) et dans `Recenseur.types`.
- Swift 6 strict, avertissements = erreurs ; aucune valeur réelle ; références de rejeu inchangées.
- Porte : `bash outils/tester.sh` (aucune app Maillage IoT ne tourne pendant la porte), `bash outils/tester-sondes.sh`, `bash outils/controler-index.sh` → 0, passe anglaise.
- Commits en français sans accents ; jamais de push.

## Review Focus

1. **Une proposition fausse** : un nom AirPlay qui contient un mot proche d'une pièce (« Salonnière »), deux pièces, une pièce avec accent ; un hôte partagé par deux services (Task 1).
2. **Une proposition qui écrase un choix** : un nœud déjà placé ne reçoit rien (Task 1, Task 2).
3. **Un rattachement inventé** : sans nom d'hôte commun, aucune proposition (Task 1).
4. **« Ignorer » qui revient** sans raison, ou qui ne revient pas après un changement de nom (Task 2).

---

### Task 1: Écoute AirPlay et modèle de proposition

**Files:**
- Modify: `MaillageIoT/Thread/Recenseur/Recenseur.swift` (types), `project.yml` (NSBonjourServices des deux cibles)
- Create: `MaillageIoT/Thread/Recenseur/PieceAirPlay.swift`
- Test: `MaillageIoTTests/PieceAirPlayTests.swift`

**Interfaces:**
- Produces : `PieceAirPlay.propositions(airplay: [ServiceAirPlay], bordures: [(id: IdNoeud, hote: String)], piecesMaison: [String], piecesConnues: [IdNoeud: String]) -> [IdNoeud: Proposition]` (indicatif : ajuster aux types réels et le dire au rapport), `Proposition(piece: String, nomAirPlay: String)`.

- [x] **Step 1: Tests RED** — rattachement par hôte (casse, point final) ; aucune proposition sans hôte commun ; mot entier (« Salon » oui, « Salonnière » non), accents et casse, la plus longue de deux pièces ; nœud déjà placé : rien ; le service AirPlay résolu par le recenseur (hôte, TXT `model`) avec un faux navigateur.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte.
- [x] **Step 4: Commit** — « AirPlay : ecoute et proposition de piece pour les routeurs de bordure ».

---

### Task 2: La proposition dans la fiche, et la démo

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/FicheNoeud.swift`, `PiecesChoisies.swift` (mémoire « ignorée »), catalogue ; démo (HomePod et Apple TV sans pièce, service AirPlay inventé)
- Test: `MaillageIoTTests/FichePieceAirPlayTests.swift`

- [ ] **Step 1: Tests RED** — la ligne paraît pour un routeur de bordure sans pièce avec proposition ; « Placer ici » place le nœud comme « Placer dans une pièce… » ; « Ignorer » cache et persiste ; un nom AirPlay changé fait revenir la proposition ; démo : la proposition paraît ; références de rejeu inchangées.
- [ ] **Step 2: GREEN** — implémenter (fr et en).
- [ ] **Step 3: Vérifier** — porte, passe anglaise.
- [ ] **Step 4: Commit** — « AirPlay : piece proposee dans la fiche, placer ou ignorer ».

---

### Task 3: Relecture et banc

- [ ] **Step 1: Relecture** — par Sonnet (tâches) puis Opus (branche).
- [ ] **Step 2: Banc** — avec Djoko, sur son réseau réel : les HomePod et l'Apple TV reçoivent-ils une proposition juste ; le rattachement par hôte tient-il.
- [ ] **Step 3: Verdict** — cocher « Phase 7 » dans la §6.1 de la spec ; fusion et push avec l'accord de Djoko.
