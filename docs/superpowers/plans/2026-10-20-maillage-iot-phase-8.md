# Maillage IoT, phase 8 : clés `rloc:` de Thread qualifiées en cas de collision — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deux routeurs Thread de partitions différentes qui ont le même RLOC16 ne se confondent plus (historique, pièce, surnom, scène).

**Architecture:** Décision de Djoko (20/10) : la clé reste `rloc:XXXX` tant qu'une seule partition a ce RLOC16 ; pendant une collision seulement, les autres routeurs de ce numéro prennent `rloc:<partition>:XXXX`. Départage déterministe : garde la clé simple le routeur de la partition qui l'avait au relevé précédent ; à défaut la plus grande partition ; puis le plus petit identifiant de partition. Aucune conversion de fichier ; références de rejeu inchangées.

**Tech Stack:** Swift 6 strict, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` (§2.1 `IdNoeud`, §8 backlog « Clés `rloc:` de Thread qualifiées par leur partition »).

## Global Constraints

- Clé simple `rloc:XXXX` inchangée hors collision (aucune conversion de `pieces-noeuds.json`, `surnoms.json`, historiques, journal) ; références de rejeu `docs/rejeu/*.json` inchangées à l'octet.
- Pendant une collision : `rloc:<partition en hexadécimal, comme l'app l'affiche>:XXXX` pour les routeurs qui ne gardent pas la clé simple ; départage comme ci-dessus, déterministe.
- Tous les endroits qui fabriquent ou lisent une clé `rloc:` (ProtocoleThread/Maillage : Maillage, SuiviMaillage, HistoriqueMaillage, ClesHistorique, Rapprochement, DonneesReseau ; MaillageCoeur/Scene/GrapheReseau, CourbesNoeud ; SurveillanceThread ; LegendePieces) passent par une seule fonction.
- Swift 6 strict ; aucune valeur réelle ; porte : `bash outils/tester.sh` (l'app réelle tourne : règle connue de NomsPasseurTests), `bash outils/tester-sondes.sh`, `bash outils/controler-index.sh` → 0, passe anglaise.

## Review Focus

1. **Une collision qui mélange encore** : un même instantané avec deux partitions et le même RLOC16 (scène, journal, historique, suivi des disparitions).
2. **Une clé qui change hors collision** : un relevé normal produit exactement les clés d'avant (rejeu).
3. **Un départage qui oscille** d'un relevé à l'autre pendant une collision stable.
4. **La fin d'une collision** : le routeur qualifié retrouve-t-il la clé simple, ou un autre la prend-il (continuité).

---

### Task 1: Clés qualifiées en cas de collision

- [ ] **Step 1: Repérer** — toutes les fabriques et lectures de clés `rloc:` ; le dire au rapport.
- [ ] **Step 2: Tests RED** — collision dans un instantané (deux partitions, même RLOC16) : deux nœuds distincts dans la scène, l'historique, le suivi ; départage (relevé précédent, puis taille, puis identifiant) ; collision stable sur trois relevés : mêmes clés ; fin de collision ; relevé sans collision : clés identiques à avant ; rejeu exact.
- [ ] **Step 3: GREEN** — une seule fonction de clé, utilisée partout.
- [ ] **Step 4: Vérifier** — porte, passe anglaise, rejeu.
- [ ] **Step 5: Commit** — « Thread : cles rloc qualifiees par la partition en cas de collision ».

---

### Task 2: Relecture et verdict

- [ ] **Step 1: Relecture** — Sonnet (tâche), puis Opus (branche) : identité des nœuds.
- [ ] **Step 2: Verdict** — cocher « Phase 8 » dans la §6.1 de la spec ; retirer le point du backlog ; fusion et push avec l'accord de Djoko.
