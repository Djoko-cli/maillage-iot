# Maillage IoT, phase 3c : découpe des deux `SondeMaillage` — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Couper chacun des deux pilotes de sonde, `SondeMaillageThread` (1 034 lignes) et `SondeMaillageZigbee` (1 066 lignes), en quelques fichiers d'un rôle chacun, sans aucun changement de comportement.

**Architecture:** Déplacement de code pur. La classe garde son fichier principal (état observé, initialisation, cycle de vie `demarrer` / `arreter` / `actif`) ; chaque rôle part dans une extension de la classe, dans son propre fichier `SondeMaillageThread+<Rôle>.swift` (et de même pour Zigbee). Les membres `private` qu'une extension d'un autre fichier doit lire passent au plus petit accès qui compile (`fileprivate` est impossible entre fichiers : `internal`, ou `private(set)` pour un état observé), et cela seulement. Aucune logique n'est réécrite.

**Tech Stack:** Swift 6 strict, XcodeGen 2.46, xcodebuild, Swift Testing, bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — §6.1 (ancienne « étape 2 bis » : mêmes tests, mêmes rejeux, aucun changement de comportement) et §6.6 (la découpe vient après l'étape 3).

## Global Constraints

- **Aucun changement de comportement.** Le diff ne contient que des déplacements, des changements d'accès rendus nécessaires par le passage en extension, des `import` et des commentaires d'en-tête de fichier. Toute autre modification est un constat à remonter, pas à faire.
- **Mêmes tests, aucune attente modifiée** : aucun fichier de test ne change, sauf si un test lit un membre par un chemin que la découpe déplace (le dire, ligne par ligne). Les nombres de `@Test` ne bougent pas.
- **Les trois références de rejeu restent exactes** : `docs/rejeu/thread-demo.json`, `zigbee-demo.json`, `maillage-iot-demo.json`, jamais régénérées.
- Rôles visés (adapter aux coutures réelles du fichier, et les nommer au rapport) : **USB** (liste des ports, carte retenue, ouverture gardée par `ouvrable`, liaison série), **Réseau** (session réseau, clé du trousseau, reprise de l'ancienne clé), **Chemin** (réglage et choix Automatique / USB / Réseau, bascules et hystérésis), **Tournées** (lancement, entretien, relances, budget), **Affichage** (textes et états montrés aux Réglages et au menu), **Cycle de vie** (`demarrer`, `arreter`, `tachesPlanifiees` ; rôle ajouté par la tâche 1, repris par la tâche 2). Fichier principal : moins de 300 lignes ; aucun fichier de plus de 400 lignes.
- Les gardes de sûreté ne se dispersent pas : `ouvrable` et tout appel à `ouvrirCanal` restent dans le fichier **USB** ; les générations (`essai`, `epoque`) et l'annulation des tâches restent dans le fichier principal ou le fichier qui les possède, jamais coupées en deux.
- `project.yml` prend les fichiers par dossier : lancer `xcodegen generate -q` après la découpe.
- Swift 6 strict, avertissements = erreurs ; aucun `nonisolated(unsafe)` ni `@unchecked Sendable` ajouté.
- Commentaires sans accents ; commits en français sans accents, terminés par une ligne `Co-Authored-By:` du modèle auteur. Aucune valeur réelle.
- Ne jamais lire ni afficher `garde.local.txt`, `.superpowers/anonymisation/`, `*.local*`. Avant chaque commit : `bash outils/controler-index.sh` → 0 défaut.
- Blocs de commandes pour **bash**. Aucun push, aucun `git checkout` d'un autre commit, aucun `git stash`.
- **Porte de chaque tâche** : `outils/tester.sh` passe en entier, `bash outils/verifier-noms-publics.sh` et `bash outils/tester-coeur.sh` aussi ; les suites de la sonde concernée lancées trois fois.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Une ligne de logique changée en route** : on attend que la concaténation des nouveaux fichiers redonne, au tri des déclarations près, le fichier d'origine (comparaison outillée au rapport : `git diff --color-moved=dimmed-zebra`, ou un script qui compare les corps des fonctions).
2. **Une garde de port dispersée ou contournée** : `ouvrable` et `ouvrirCanal` réunis dans le fichier USB, aucun nouveau chemin d'ouverture.
3. **Un accès trop ouvert** : chaque `private` relâché est justifié par un lecteur dans un autre fichier ; aucun membre ne devient `public`.

---

### Task 1: Découpe de `SondeMaillageThread`

**Files:**
- Modify: `MaillageIoT/Thread/Sonde/SondeMaillageThread.swift` (fichier principal)
- Create: `MaillageIoT/Thread/Sonde/SondeMaillageThread+USB.swift`, `+Reseau.swift`, `+Chemin.swift`, `+Tournees.swift`, `+Affichage.swift` (selon les coutures réelles)

- [x] **Step 1: Repères** — noter les nombres de `@Test` par cible et lancer les suites de la sonde Thread (vertes).
- [x] **Step 2: Découper** — déplacer chaque rôle dans son extension ; relâcher seulement les accès nécessaires ; `xcodegen generate -q`.
- [x] **Step 3: Vérifier** — porte de la tâche ; comparaison outillée « déplacement pur » au rapport ; tailles des fichiers.
- [x] **Step 4: Commit** — « Sonde Thread : decoupe du pilote par role, sans changement de comportement ».

---

### Task 2: Découpe de `SondeMaillageZigbee`

**Files:**
- Modify: `MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee.swift` (fichier principal)
- Create: `MaillageIoT/Zigbee/Sonde/SondeMaillageZigbee+USB.swift`, `+Reseau.swift`, `+Chemin.swift`, `+Tournees.swift`, `+Affichage.swift` (selon les coutures réelles ; la machine d'états de la spec 3.4 reste lisible d'un seul fichier, `+Chemin` ou le principal)

- [x] **Step 1: Repères** — comme la tâche 1, pour la sonde Zigbee.
- [x] **Step 2: Découper** — même méthode, mêmes noms de rôles que Thread quand le rôle existe des deux côtés.
- [x] **Step 3: Vérifier** — porte de la tâche ; comparaison outillée ; tailles des fichiers.
- [x] **Step 4: Commit** — « Sonde Zigbee : decoupe du pilote par role, sans changement de comportement ».

---

### Task 3: Relecture finale et feuille de route

- [x] **Step 1: Relecture finale** — par Opus, sur toute la branche (déplacement pur, gardes réunies, accès).
- [x] **Step 2: Feuille de route** — après le banc : cocher « Phase 3 » dans la §6.1 de la spec.

---

### Task 4: Banc avec Djoko

- [x] **Step 1: Préparer** — compiler `MaillageIoT` (Debug) et relancer l'app.
- [x] **Step 2: Vérifier** — les deux sondes en USB, puis la sonde Thread en Automatique (débrancher, rebrancher) et la sonde Zigbee en Wi-Fi : tout se comporte comme avant la découpe.
- [x] **Step 3: Verdict** — noté au registre ; plan coché ; fusion dans `main` et push avec l'accord de Djoko.
