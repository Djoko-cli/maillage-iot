# Maillage IoT, phase 9 : le journal nomme la pièce de l'appareil — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chaque ligne du journal, chaque notification et chaque entrée du menu de la barre nomme le nœud avec sa pièce, en français naturel (« La lampe du bureau a perdu son parent »).

**Architecture:** L'accord grammatical automatique d'Apple ne connaît pas le genre des noms courants (essai du 20/10) : un lexique propre à l'app (genre, élision, pluriel) pour les mots de la maison, et une fonction pure qui construit le groupe nominal du sujet à partir du nom du nœud et de sa pièce ; les textes des événements la reçoivent à la place du nom seul.

**Tech Stack:** Swift 6 strict, Swift Testing, String Catalogs.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` (§8, « Le journal nomme la pièce de l'appareil ») et décisions de Djoko du 20/10 ci-dessous.

## Global Constraints (décisions de Djoko, 20/10)

- **Nom qui contient la pièce, mots connus** : on retire la pièce du nom et on accorde : « La lampe du bureau a perdu son parent », « Le capteur de la cuisine… », « L'interrupteur de l'entrée… », « Les volets de la chambre… » (contractions de + le = du, de + les = des ; élision devant voyelle et h muet).
- **Nom sans la pièce, pièce connue** : « HomePod Avant, dans le salon, a perdu son parent » (dans le / la / l' / les).
- **Mot inconnu (appareil ou pièce)** : aucun article inventé : « Hue Go (droite) — Salle de jeux : a perdu son parent ».
- **Sans pièce** : le nom seul, comme aujourd'hui.
- **Anglais** : « Desk lamp (Office) lost its parent » (pas d'accord).
- Pièce = la pièce **placée dans la scène** (choix de Djoko compris), lue à l'affichage ; même règle dans la fenêtre du journal, les notifications et le menu de la barre.
- La recherche du journal trouve toujours une ligne par le nom brut du nœud et par sa pièce.
- Majuscule en début de phrase ; noms communs du lexique en minuscules dans la phrase ; un nom propre (mot hors lexique) garde sa casse.
- Swift 6 strict ; textes fr/en au catalogue ; références de rejeu inchangées ; aucune valeur réelle (tests avec des noms inventés).
- Porte : `bash outils/tester.sh` (l'app réelle tourne : règle connue de NomsPasseurTests), `bash outils/tester-sondes.sh`, `bash outils/controler-index.sh` → 0, passe anglaise, préférences isolées dans les tests.

## Review Focus

1. **Une faute d'accord** : un mot dont le genre est deviné au lieu d'être lu dans le lexique ; une élision oubliée (« de le entrée ») ; un pluriel (« combles », « toilettes ») (Task 1).
2. **Une pièce retirée à tort** du nom : « Salon de thé » dans la pièce « Salon » ; un nom qui ne contient la pièce qu'en partie (Task 1).
3. **Une phrase cassée** par un texte d'événement qui ne commence pas par le sujet (Task 2).
4. **La recherche du journal** qui ne trouve plus une ligne par le nom d'origine (Task 2).

---

### Task 1: Le lexique et la phrase du sujet

- [ ] **Step 1: Tests RED** — lexique (genre, élision, pluriel) ; chaque forme des décisions ci-dessus, avec des noms inventés ; retrait de la pièce en mots entiers, sans casse ni accents ; « Salon de thé » / « Salon » ; repli sans article pour un mot inconnu ; anglais.
- [ ] **Step 2: GREEN** — `MaillageCoeur` (ou là où vivent les textes d'événements) : le lexique et une fonction pure, signature au rapport.
- [ ] **Step 3: Vérifier** — porte.
- [ ] **Step 4: Commit** — « Journal : lexique et phrase du sujet avec la piece ».

---

### Task 2: Le journal, les notifications et le menu

- [ ] **Step 1: Tests RED** — chaque type d'événement du journal (Thread et Zigbee) donne une phrase juste avec la pièce ; notifications et menu de la barre identiques ; recherche par nom brut et par pièce ; démo ; anglais.
- [ ] **Step 2: GREEN** — brancher la fonction là où les textes d'événements sont produits.
- [ ] **Step 3: Vérifier** — porte, passe anglaise, rejeux.
- [ ] **Step 4: Commit** — « Journal : la piece de l'appareil dans le journal, les notifications et le menu ».

---

### Task 3: Relecture et banc

- [ ] **Step 1: Relecture** — Sonnet par tâche, Opus sur la branche.
- [ ] **Step 2: Banc** — avec Djoko, sur son journal réel.
- [ ] **Step 3: Verdict** — cocher « Phase 9 » ; retirer le point du backlog ; fusion et push avec l'accord de Djoko.
