# Maillage IoT, phase 4 : reprise — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reprendre dans Maillage IoT les données de Maillage Thread 1.3.0 et de Maillage Zigbee 1.1.1 (réglages, noms, pièces, historique) à partir d'un export écrit par chaque ancienne app, sans rien perdre ni rien casser, et le prouver par une répétition sur une copie des vraies données.

**Architecture:** Un contrat commun aux trois dépôts (`ContratExport.swift`, dans le cœur, autonome). Les anciennes apps écrivent un dossier d'export (manifeste, copies des fichiers, réglages) ; ce travail est fait dans leurs dépôts par les sessions Thread et Zigbee (tâche 9). Maillage IoT valide l'export, le convertit dans un dossier d'attente, puis l'applique d'un coup et se relance. Les clés du trousseau sont déjà reprises directement de l'ancien trousseau (spec 4.3).

**Tech Stack:** Swift 6 strict, XcodeGen 2.46, xcodebuild, Swift Testing, Python 3 (outils), bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — §2.2, §2.3, **§4** (contrat, export, import, ce qui se refait), §6.1 (critère de la phase 4) et **§6.8 (décisions de la phase 4, qui priment)**.

**Inventaire** (local, hors git) : `.superpowers/fusion/inventaire-phase-4.md` — chaque fichier et chaque réglage des deux anciennes apps, son format et sa destination, les lecteurs déjà présents, les risques. Reports des étapes 3 : `.superpowers/fusion/registre-etape-3a.md`, `registre-etape-3b.md`, `registre-phase-3c.md`.

## Global Constraints

- **Aucune donnée réelle dans le dépôt** : les exports d'exemple, les tests et les captures n'ont que des valeurs inventées, clés comprises (garde `outils/garde.py`, `controler-index.sh`). La répétition (tâche 10) se fait sur une copie locale, hors du dépôt.
- **L'export ne modifie jamais l'ancienne app** ; **l'import ne modifie rien en cas d'échec** (dossier d'attente, application d'un coup) ; réimporter le même export ne fait rien de plus (`imports.json`).
- **Aucun secret du trousseau** dans un export ; le trousseau est repris par `TrousseauRepris` / `TrousseauReprisThread`, déjà en place.
- `ContratExport.swift` est **identique à l'octet** dans les trois dépôts ; il ne dépend que de Foundation et CryptoKit.
- **À ne jamais changer** : `Passeur`, `Masqueur`, `PasseurTests`, `MaillageCoeur/Noms/NomsMaison.swift`, `ProtocolePasseur.swift`, `CodageJSON.swift`, les `rawValue` des types d'événements écrits, les trois références de rejeu (jamais régénérées).
- Règles de conversion (spec 4.3 et 6.8) : clés préfixées seulement dans `surnoms.json` et `pieces-noeuds.json` ; fichiers d'un module rangés sous `Thread/` ou `Zigbee/` sans changement de clé ; journal de Zigbee 1.1.1 : `"protocole":"zigbee"` ajouté à chaque ligne ; lignes JSONL sinon inchangées ; historique de plus de 90 jours écarté par fichier mensuel ; `thread.sondeLiaison` recopiée telle quelle ; clés de notification écrites par protocole ; premier import l'emporte pour les fichiers communs, le second ajoute ce qui manque, un fichier déjà présent n'est jamais sauté.
- Identité de l'app publiée inchangée : `MaillageIoT`, `fr.djoko.maillage.iot`. L'identité de répétition (tâche 8) n'est jamais publiée.
- DerivedData `~/Library/Developer/Xcode/DerivedData/maillage-iot`. Swift 6 strict, avertissements = erreurs.
- Commentaires sans accents, textes d'interface avec accents (catalogue fr + en) ; commits en français sans accents, terminés par une ligne `Co-Authored-By:` du modèle auteur. L'utilisateur s'appelle **Djoko**.
- Ne jamais lire ni afficher `garde.local.txt`, `.superpowers/anonymisation/`, `*.local*`. Les vraies données ne s'affichent jamais (noms, pièces, identifiants) : comptes et structures seulement. Avant chaque commit : `bash outils/controler-index.sh` → 0 défaut.
- Blocs de commandes pour **bash**. Aucun push, aucun `git checkout` d'un autre commit, aucun `git stash`. Les dépôts `maillage-thread` et `maillage-zigbee` ne sont modifiés que par leurs sessions (tâche 9).
- **Porte de chaque tâche** : `outils/tester.sh`, `bash outils/tester-coeur.sh`, `bash outils/verifier-noms-publics.sh`, `python3 -m unittest discover -s outils/tests -q`.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Une donnée perdue en silence** : un fichier, une ligne de journal ou un réglage de l'ancienne app absent après l'import sans être cité au résumé comme « ignoré ». On attend un test par fichier et par réglage de l'inventaire.
2. **Un mauvais protocole** : une ligne de journal Zigbee lue comme Thread, un surnom ou une pièce Zigbee rangé sous `thread:`. On attend le protocole juste sur chaque fichier converti.
3. **Un import à moitié appliqué** : échec au milieu (disque plein, fichier verrouillé, app qui tourne) qui laisse un mélange. On attend « tout ou rien », vérifié par un test qui fait échouer l'application à chaque fichier.
4. **Un choix de Djoko écrasé** : un surnom, une pièce ou un réglage déjà faits dans Maillage IoT remplacés par l'import ; `sondeLiaison` ou une notification remise au défaut.
5. **Un export altéré accepté** : empreinte fausse, fichier en trop ou en moins, format inconnu, chemin qui sort du dossier (`../`).

---

### Task 1: `ContratExport` et son contrôle

**Files:**
- Create: `MaillageCoeur/Reprise/ContratExport.swift` (manifeste version 1 : identifiant d'export, app source et version, date, fichiers avec chemin relatif, taille, empreinte SHA-256 ; `reglages.json` : dictionnaire typé des réglages repris ; les noms des fichiers connus par app source), `outils/verifier-contrats.sh` (compare `ContratExport.swift` et `ProtocolePasseur.swift` aux autres dépôts s'ils sont présents, par `cmp`).
- Test: `MaillageCoeurTests/ContratExportTests.swift`.

- [x] **Step 1: RED** — aller-retour du manifeste ; refus d'une version inconnue ; refus d'un chemin absolu ou qui sort du dossier ; empreinte SHA-256 d'un fichier connu.
- [x] **Step 2: GREEN** — écrire le contrat (Foundation et CryptoKit seulement, autonome) et le script.
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « Reprise : contrat d'export commun aux trois depots ».

---

### Task 2: Exports d'exemple provisoires

D'après `inventaire-phase-4.md` §1-2. Ils seront remplacés à la tâche 9 par ceux que produisent les anciennes apps.

**Files:**
- Create: `MaillageIoTTests/Ressources/exports/thread-1.3.0/` et `zigbee-1.1.1/` (manifeste, fichiers aux formats réels de chaque app, `reglages.json`, valeurs inventées seulement ; un historique de plus de 90 jours et un journal Zigbee sans `protocole`), et l'outil qui les produit (`outils/` ou un test qui les écrit une fois).

- [ ] **Step 1: Écrire** les deux exports, chaque fichier de l'inventaire présent au moins une fois.
- [ ] **Step 2: Vérifier** — la garde d'anonymat passe sur ces fichiers ; les empreintes du manifeste sont justes.
- [ ] **Step 3: Commit** — « Reprise : exports d'exemple provisoires de Thread 1.3.0 et Zigbee 1.1.1 ».

---

### Task 3: Validation d'un export

**Files:**
- Create: `MaillageIoT/Reprise/ValidationExport.swift`.
- Test: `MaillageIoTTests/Reprise/ValidationExportTests.swift`.

- [ ] **Step 1: RED** — les deux exports d'exemple sont acceptés ; refusés avec une cause lisible : empreinte fausse, taille fausse, fichier manquant, fichier en trop non listé, version inconnue, app source inconnue, chemin qui sort du dossier, manifeste illisible.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Reprise : validation du manifeste et des empreintes ».

---

### Task 4: Conversion de Thread 1.3.0

D'après `inventaire-phase-4.md` (Thread) ; spec 4.3, 6.8.

**Files:**
- Create: `MaillageIoT/Reprise/ConversionThread.swift` (export validé → dossier d'attente + réglages à écrire).
- Test: `MaillageIoTTests/Reprise/ConversionThreadTests.swift`.

- [ ] **Step 1: RED** — un test par fichier et par réglage de l'inventaire : `surnoms.json` v1 préfixé `thread:` ; `pieces-routeurs.json` → `pieces-noeuds.json` v2 préfixé ; `positions-pieces.json` fusionné en profondeur ; `associations.json`, `identites-routeurs.json`, `dernieres-adresses.json`, `dernier-maillage.json`, historiques mensuels → `Thread/` sans changement de clé ; historique de plus de 90 jours écarté ; journal ajouté tel quel (lignes sans `protocole` = Thread) ; `noms.json` → `releve-maison.json` sans préfixe, gardé seulement si aucun relevé n'est présent ou s'il est plus récent ; réglages : `sonde*` → `thread.*`, `sondeLiaison` tel quel, notifications par protocole, Sparkle et fenêtres non repris (cités au résumé).
- [ ] **Step 2: GREEN** — implémenter, en réutilisant les lecteurs d'anciens formats déjà présents (inventaire §5).
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Reprise : conversion des donnees de Thread 1.3.0 ».

---

### Task 5: Conversion de Zigbee 1.1.1

**Files:**
- Create: `MaillageIoT/Reprise/ConversionZigbee.swift`.
- Test: `MaillageIoTTests/Reprise/ConversionZigbeeTests.swift`.

- [ ] **Step 1: RED** — un test par fichier et par réglage de l'inventaire (Zigbee) : surnoms et pièces préfixés `zigbee:` (jamais lus par les lecteurs de secours, qui supposent Thread) ; `noms-pont.json`, `appariements-maison.json`, `dernier-maillage.json`, historiques → `Zigbee/` ; **chaque ligne du journal reçoit `"protocole":"zigbee"`** ; relevé de Maison selon la règle 6.8 ; réglages `sonde*` → `zigbee.*`, `pont.hue` repris (pour la reprise de la clé du pont), budget de tournée, `liensMontres` et `voisinsALaSelection` → `zigbee.` ; non repris cités au résumé.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Reprise : conversion des donnees de Zigbee 1.1.1 ».

---

### Task 6: Application de l'import, tout ou rien

**Files:**
- Create: `MaillageIoT/Reprise/ApplicationImport.swift` (fusion avec les fichiers présents selon les règles, écriture dans un dossier d'attente, remplacement d'un coup, `imports.json`, réglages écrits seulement après le remplacement réussi).
- Test: `MaillageIoTTests/Reprise/ApplicationImportTests.swift`.

- [ ] **Step 1: RED** — import de Thread puis de Zigbee : état final attendu ; ordre inverse : même état (clés préfixées sans collision) ; réimport du même export : rien ne change ; un choix déjà fait dans Maillage IoT (surnom, pièce, réglage) n'est jamais écrasé ; échec forcé à chaque fichier : le dossier de l'app reste identique (tout ou rien) ; un format inconnu déjà présent n'est jamais écrasé (`FichiersGardes`).
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Reprise : application de l'import en un seul coup, idempotente ».

---

### Task 7: L'assistant de reprise

D'après la spec 4.3, 4.4, 6.8 (relance).

**Files:**
- Create: `MaillageIoT/Vues/Reprise/` (fenêtre de l'assistant : choix du dossier d'export par un panneau d'ouverture, validation, ancienne app qui tourne signalée avec « Quitter Maillage Thread » ou Zigbee, résumé de ce qui a été repris et ignoré, liste « À refaire » selon l'état réel des clés du trousseau, des autorisations et de l'ouverture de session, relance de l'app) ; entrée « Reprendre des données… » dans Réglages › Général ; proposition au premier lancement.
- Test: `MaillageIoTTests/Reprise/AssistantRepriseTests.swift` (textes du résumé et de « À refaire » selon les cas, détection de l'ancienne app par son identifiant, aucun import sans validation).

- [ ] **Step 1: RED** — tests ci-dessus.
- [ ] **Step 2: GREEN** — implémenter (catalogue fr + en).
- [ ] **Step 3: Vérifier** — porte de la tâche ; captures de l'assistant (chemins au rapport).
- [ ] **Step 4: Commit** — « Reprise : assistant, resume et liste a refaire ».

---

### Task 8: Identité de répétition

**Files:**
- Modify: `project.yml` (configuration ou cible « Maillage IoT Répétition » : identifiant `fr.djoko.maillage.iot.repetition`, conteneur à part, services de trousseau suffixés `.repetition`, sans Sparkle) ; le code qui nomme les services de trousseau les lit depuis l'identité (jamais en dur pour la répétition) ; la publication (phase 5) refusera cette identité.
- Test: un test que les services de trousseau de la répétition diffèrent de ceux de l'app.

- [ ] **Step 1: RED** — test ci-dessus.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche ; l'app de répétition se compile et se lance à côté de l'app réelle.
- [ ] **Step 4: Commit** — « Reprise : identite de repetition, a cote de l'app reelle ».

---

### Task 9: L'export dans les anciennes apps (sessions Thread et Zigbee)

Fait dans leurs dépôts par les sessions Thread (`maillage-thread`, version 1.4.0, non publiée avant la phase 5) et Zigbee (`maillage-zigbee`, version 1.2.0), sur la spec 4.1-4.2 et le `ContratExport.swift` de la tâche 1, recopié à l'octet.

- [ ] **Step 1: Envoyer** — à chaque session : la spec 4.1-4.2, le contrat, l'inventaire de son app (sans valeur réelle), les règles d'anonymat ; chacune écrit l'export (menu et bandeau « … devient Maillage IoT », « Exporter pour Maillage IoT… », dossier choisi par un panneau, « Ne plus ouvrir à l'ouverture de session ») et produit dans ses tests un export d'exemple anonymisé.
- [ ] **Step 2: Intégrer** — remplacer les exports provisoires de la tâche 2 par les leurs ; les tests des tâches 3 à 6 passent sans changer d'attente (sinon : écart entre le format écrit et le format lu, à corriger côté export ou côté import).
- [ ] **Step 3: Contrôler** — `outils/verifier-contrats.sh` : `ContratExport.swift` identique dans les trois dépôts.
- [ ] **Step 4: Commit** — « Reprise : exports d'exemple des anciennes apps, contrat identique dans les trois depots ».

---

### Task 10: Répétition sur une copie des vraies données

Avec Djoko. Rien de réel n'entre dans le dépôt.

- [ ] **Step 1: Exporter** — avec les compilations de travail de Thread 1.4.0 et de Zigbee 1.2.0, exporter les vraies données dans un dossier local hors du dépôt.
- [ ] **Step 2: Importer** — dans « Maillage IoT Répétition » : Thread puis Zigbee ; vérifier le résumé, les comptes (fichiers, lignes de journal, relevés, surnoms, pièces) contre l'inventaire, la vue réunie, le journal (protocoles justes), les réglages repris, la reprise des clés (invites du trousseau).
- [ ] **Step 3: Réimporter** — le même export : rien ne change.
- [ ] **Step 4: Noter** — résultats au registre (comptes seulement).

---

### Task 11: Relecture finale et banc

- [ ] **Step 1: Relecture finale** — par Opus, sur toute la branche.
- [ ] **Step 2: Banc** — avec Djoko : l'assistant de reprise de bout en bout dans l'app de répétition, puis la décision de la vraie reprise (elle peut attendre la publication, phase 5).
- [ ] **Step 3: Verdict** — noté au registre ; cocher « Phase 4 » dans la §6.1 de la spec ; fusion dans `main` et push avec l'accord de Djoko.
