# Maillage IoT, phase 5 : publication — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publier Maillage IoT 1.0.0 (signée Developer ID, notarisée, mise à jour par Sparkle), puis Maillage Thread 1.4.0 et Maillage Zigbee 1.2.0 qui l'annoncent, puis les bandeaux des anciens README et, avec l'accord de Djoko, l'archivage des anciens dépôts.

**Architecture:** L'outil de publication de Thread (`publication.py` et ses tests) est recopié à l'octet ; seul `outils/publier.sh` est propre à Maillage IoT et ajoute ce que `publication.py` ne sait pas faire ici (deux contrôles d'anonymisation, refus de l'identité de répétition, contrôle de l'icône). Une répétition N-1 → N dans un clone à part, avec une identité et une paire de clés d'essai, précède la vraie publication. Les anciennes apps sont publiées par leurs sessions, avec leurs propres outils, une fois la 1.0.0 en ligne.

**Tech Stack:** bash, Python 3 (`unittest`), XcodeGen 2.46, xcodebuild, codesign, notarytool, stapler, hdiutil, Sparkle 2.10.0 (`sign_update`, `generate_keys`, `sparkle-cli`), gh.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — §5 (dépôt, publication, annonce), §6.1 (phase 5), §6.2 (tests), §6.8 et §7. Méthode de signature : fiche de passation d'Amaran (`~/Dev/amaran/.superpowers/notarisation/passation-developer-id.md`, locale, jamais recopiée).

## Global Constraints

- `outils/publication.py` et `outils/tests/test_publication.py` sont **identiques à l'octet** à ceux de `~/Dev/maillage-thread/outils/` (contrôle par `cmp` dans les tests). Ils ne sont jamais modifiés ici ; toute adaptation passe par `publier.sh` ou par l'environnement (`CONTROLE_ANONYMISATION`, `TABLE_ANONYMISATION`, `SPARKLE_BIN`, `DD`).
- Signature « Developer ID Application » (identité choisie par ce préfixe), notarisation avec le profil `djoko-notarisation`, et rien d'autre : jamais de nouveau profil ni de nouveau certificat. Le nom légal et l'équipe n'apparaissent que dans la signature des produits : masqués (`<titulaire>`, `<equipe>`) dans toute sortie montrée, jamais dans un fichier, un commit, une note, un flux ou un journal affiché.
- Numéro de compilation = `git rev-list --count HEAD` sur `main` (posé par `publication.py`) ; les compilations de travail gardent `CURRENT_PROJECT_VERSION "1"`, où Sparkle ne démarre pas (`MisesAJour.doitDemarrer`).
- Flux : `appcast.xml` à la racine de `main` de `Djoko-cli/maillage-iot`, signé avec la paire EdDSA commune (clé publique `CLE_MISES_A_JOUR` de `project.yml`, clé privée dans le trousseau, jamais lue ni affichée).
- Étiquettes git des versions : `v` + numéro (`v1.0.0`).
- Notes de version (`NOTES-VERSIONS.md`, version GitHub, fenêtre de mise à jour) : section `## X.Y.Z`, bloc **English** puis bloc **Français**, même contenu. README : anglais (`README.md`) et français (`README.fr.md`), liens croisés en tête.
- Ordre public (spec 5.4) : 1.0.0 en ligne (version GitHub et flux) → Thread 1.4.0 et Zigbee 1.2.0 → bandeaux des README → archivage. **Chaque geste public demande l'accord explicite de Djoko** (« publie 1.0.0 », « publie Thread 1.4.0 », « archive… ») ; un accord ne vaut que pour son geste.
- Anonymat : aucune valeur réelle ; ne jamais lire ni afficher `garde.local.txt`, `.superpowers/anonymisation/`, `*.local*` ; garde `pre-push` jamais contournée (`--no-verify` et push forcé interdits).
- Commentaires sans accents ; commits en français sans accents, terminés par la ligne `Co-Authored-By:` du modèle auteur.
- Porte de chaque tâche de code : `bash outils/tester.sh` (vert, sauf instabilité nommée au rapport et relancée trois fois), `bash outils/tester-sondes.sh`, `bash outils/controler-index.sh` → 0 défaut.
- Toute publication ou répétition longue se suit dans un onglet du Terminal (`tail -F` du journal), avec un guetteur en arrière-plan qui prévient à la fin.

## Review Focus

1. **Une publication qui part d'un état faux** (arbre sale, `main` en retard sur `origin`, numéro de flux non croissant, clé publique qui n'est pas celle du trousseau) : refus avant tout geste public — couvert par `publication.py` ; `publier.sh` ne doit court-circuiter aucun de ses contrôles (Task 2, test « les arguments passés sont exactement ceux attendus »).
2. **L'identité de répétition publiée par erreur** : `publier.sh` refuse avant toute compilation si l'identifiant de la cible publiée finit par `.repetition` (Task 2, test avec un `project.yml` modifié dans un dossier temporaire).
3. **Une donnée réelle dans le .dmg, les notes ou le flux** : les DEUX contrôles d'anonymisation passent, et un seul en défaut fait échouer (Task 2, test de l'enveloppe avec deux faux contrôles, l'un en défaut).
4. **Une mise à jour qui casse l'app** : N s'installe sur N-1 par Sparkle, trousseau et réglages gardés, et le type Bonjour ajouté par N fonctionne après la mise à jour (Task 5, attendus de la répétition).
5. **Une batterie instable qui bloque la publication au mauvais moment** : le test de durée de la légende (`recadrageDeLaLegendeApresUnClic`) ne dépend plus de la charge (Task 3, suite lancée cinq fois sous charge).

---

### Task 1: Recopie de l'outil de publication

**Files:**
- Create: `outils/publication.py`, `outils/tests/test_publication.py`, `outils/Sparkle-LICENSE.txt` (copies à l'octet de `~/Dev/maillage-thread/outils/`)
- Create: `outils/tests/test_outil_publication_identique.py`

**Interfaces:**
- Produces: `outils/publication.py publier …` (options de Thread, inchangées) ; variables d'environnement lues : `CONTROLE_ANONYMISATION`, `TABLE_ANONYMISATION`, `SPARKLE_BIN`, `IDENTITE_SIGNATURE`, `NOTARISER`, `PROFIL_NOTARISATION`.

- [x] **Step 1: Test RED** — `test_outil_publication_identique.py` : `publication.py` et `test_publication.py` ont la même empreinte SHA-256 que ceux de `DEPOT_THREAD` (défaut `../maillage-thread`) ; le test est sauté avec un message si `DEPOT_THREAD` est absent (clone isolé), jamais vert en silence. Lancer : `/usr/bin/python3 -I -m unittest outils.tests.test_outil_publication_identique` → échec (fichiers absents).
- [x] **Step 2: Recopier** (agent Haiku) les trois fichiers avec `cp -p`, puis `cmp` sur chacun.
- [x] **Step 3: Vérifier** — `NOTARISER=1 PROFIL_NOTARISATION=djoko-notarisation IDENTITE_SIGNATURE="Developer ID Application" /usr/bin/python3 -m unittest discover -s outils/tests` : les 105 tests de `test_publication.py` et tous les autres verts (l'environnement de publication ne doit pas fuir dans les tests).
- [x] **Step 4: Commit** — « Publication : outil de Maillage Thread recopie a l'octet ».

---

### Task 2: `publier.sh` de Maillage IoT

**Files:**
- Create: `outils/publier.sh`, `outils/anonymisation_double.py`
- Test: `outils/tests/test_publier.py`

**Interfaces:**
- Consumes: Task 1 (`publication.py publier`, ses options et ses variables d'environnement) ; `outils/refuser_repetition.py CIBLE` (code 0 publiable, 1 refusé, 2 illisible).
- Produces: `bash outils/publier.sh [options de publication.py]`, et `outils/anonymisation_double.py fichiers --table <ignoree> F…` (même interface que le contrôle privé appelé par `publication.controler`).

- [x] **Step 1: Tests RED** dans `test_publier.py`, en environnement neutre (faux `python3` et faux outils dans un `PATH` temporaire, aucun appel réseau) :
  - `test_cliquet` : hors `--repetition`, `IDENTITE_SIGNATURE` autre que « Developer ID Application » ou `NOTARISER` autre que 1 → code 1 avant tout appel à `publication.py`.
  - `test_clone_superficiel` : dépôt `--depth 1` → code 1.
  - `test_repetition_refusee` : copie temporaire de `project.yml` où l'identifiant de la cible `MaillageIoT` finit par `.repetition` → code 1 avant tout appel.
  - `test_icone_absente` : `MaillageIoT/Ressources/AppIcon.icon` absent → code 1.
  - `test_arguments` : l'appel final reçoit exactement `--identite`, `--auteur Djoko-cli`, `--etiquette v`, `--flux appcast.xml`, `--licence outils/Sparkle-LICENSE.txt`, `--nom-app "Maillage IoT"`, `--fichier Maillage-IoT`, `--depot-github Djoko-cli/maillage-iot`, `--projet MaillageIoT.xcodeproj`, `--schema MaillageIoT`, `--cible MaillageIoT`, les `--test` de la batterie (ci-dessous) et `--textes MaillageIoT/Ressources/Localizable.xcstrings --textes MaillageIoT/Ressources/InfoPlist.xcstrings`, plus les options de l'appelant ; `CONTROLE_ANONYMISATION` pointe sur `outils/anonymisation_double.py` ; `DD` vaut par défaut `~/Library/Developer/Xcode/DerivedData/maillage-iot-publication`.
  - `test_anonymisation_double` : avec deux faux contrôles (variables `CONTROLE_THREAD`, `CONTROLE_ZIGBEE` pour les tests), code 0 si les deux rendent 0, code 1 si l'un rend 1 ou manque ; la sortie ne contient que des comptes (jamais les lignes des fichiers contrôlés).
- [x] **Step 2: Écrire `publier.sh`** sur le squelette de `~/Dev/maillage-thread/outils/publier.sh` (même cliquet, même garde du clone superficiel), avec avant l'`exec` : `refuser_repetition.py` sur l'identifiant de la cible `MaillageIoT` lu dans `project.yml` ; contrôle de l'icône ; `export CONTROLE_ANONYMISATION=outils/anonymisation_double.py` et `TABLE_ANONYMISATION` sur un fichier existant (l'enveloppe l'ignore). Batterie `--test` : `bash outils/tester.sh` ; `xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -destination platform=macOS -derivedDataPath "$DD" -testLanguage en -testRegion US test` ; `bash outils/tester-sondes.sh` ; `sh outils/thread-route/tests.sh`. En-tête : Developer ID dès la 1.0.0, `SPARKLE_BIN` attendu hors répétition.
- [x] **Step 3: Écrire `anonymisation_double.py`** : lance `<PRIVE>/thread/outils/controles.py` avec `<PRIVE>/thread/table.json`, puis l'équivalent `zigbee/` (mêmes chemins que `outils/pre-push`), chacun en `fichiers --table <sa table> F…` ; `PRIVE` = variable `ANONYMISATION_PRIVE`, par défaut `.superpowers/anonymisation` du dépôt principal (trouvé par `git rev-parse --git-common-dir`, pour qu'un worktree ou un clone de répétition le trouve aussi quand la variable est posée) ; code 1 si l'un échoue ou manque ; n'imprime que les comptes de chaque contrôle. Test ajouté : `ANONYMISATION_PRIVE` absent et dossier introuvable → code 1, jamais un succès vide.
- [x] **Step 4: Vérifier** — tests verts ; porte de la tâche ; `bash outils/publier.sh --aide` (ou l'aide de `publication.py`) s'affiche sans rien construire.
- [x] **Step 5: Commit** — « Publication : publier.sh de Maillage IoT (deux controles d'anonymisation, refus de la repetition, icone) ».

---

### Task 3: Batterie fiable — le test de durée de la légende

**Files:**
- Modify: `MaillageIoTTests/FenetrePiecesZigbeeTests.swift` (test `recadrageDeLaLegendeApresUnClic`, ~l.552) et, s'il porte la même mesure, son jumeau Thread.

- [x] **Step 1: Reproduire** — lancer la suite cinq fois pendant que `bash outils/tester-coeur.sh` tourne en parallèle ; noter les échecs (il a échoué une fois le 18/10 sous `tester.sh` : `abs(repli - Apparition.dureeLegende) < 0.07`).
- [x] **Step 2: Corriger le test, pas le code** : mesurer la durée de l'animation déclarée (valeur et courbe passées à l'animation), ou une tolérance fondée sur l'horloge de l'animation, au lieu d'un chronométrage réel ; l'assertion doit toujours échouer si `dureeLegende` change.
- [x] **Step 3: Vérifier** — cinq passes sous charge vertes ; une mutation de `dureeLegende` fait échouer le test ; porte de la tâche.
- [x] **Step 4: Commit** — « Tests : duree de la legende verifiee sans chronometre, insensible a la charge ».

---

### Task 4: Notes, README et spec

**Files:**
- Create: `NOTES-VERSIONS.md` (en-tête bilingue au format de `~/Dev/maillage-thread/NOTES-VERSIONS.md`, puis `## 1.0.0`)
- Modify: `README.md`, `README.fr.md`, `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` (§5.2 et §8)

- [x] **Step 1: Notes 1.0.0** — **English** puis **Français**, même contenu : une seule app pour Thread et Zigbee (vue par pièces commune, deux sondes, journal commun) ; signée Developer ID et notarisée ; reprise des données de Maillage Thread 1.4.0 et Maillage Zigbee 1.2.0 par leur export ; les invites macOS attendues au premier lancement (trousseau pour reprendre les clés des anciennes apps, « Automatisation » pour quitter l'ancienne app, réseau local, notifications) ; mises à jour automatiques. Aucun nom de pièce, d'appareil ni de réseau réel.
- [x] **Step 2: README** (EN et FR) — remplacer « en construction » par : installer (.dmg de la dernière version), signature et notarisation, mises à jour, venir de Maillage Thread ou Maillage Zigbee (export puis « Reprendre des données… »), le démon Passeur Noms (facultatif, compilé localement).
- [x] **Step 3: Spec** — amendement daté du 18/10 au §5.2 : compilation de travail à `CURRENT_PROJECT_VERSION "1"`, Sparkle éteint à ce numéro (remplace « une compilation locale porte un numéro plus grand ») ; étiquettes `v` ; enveloppe des deux contrôles d'anonymisation ; refus de la répétition par `publier.sh` ; droit d'Automatisation limité aux deux anciennes apps. Backlog §8 : contrôle de taille avant lecture dans le contrat d'export (m1 de la relecture finale de la phase 4), à grouper avec le prochain changement du contrat.
- [x] **Step 4: Vérifier** — `publication.py` lit la section `## 1.0.0` (test : `/usr/bin/python3 -I -c` qui appelle sa fonction d'extraction des notes et vérifie la présence des deux blocs) ; garde d'anonymat ; `bash outils/controler-index.sh` → 0.
- [x] **Step 5: Commit** — « Publication : notes de la 1.0.0, README d'installation, spec amendee ».

---

### Task 5: Répétition N-1 → N (avec Djoko pour l'essai à la main)

Selon la fiche de passation d'Amaran (§5 et §6), dans un clone complet à part, hors du dépôt (`~/Dev/maillage-iot-repetition-maj/`, jamais poussé) ; script et journaux dans `.superpowers/publication/` (ignoré par git).

- [ ] **Step 1: Préparer** — clone ; identifiant `fr.djoko.maillage.iot.essai-maj` et `MaillageSuffixeServices` non vide (services de trousseau à part) dans le `project.yml` du clone ; `ANONYMISATION_PRIVE` pointe vers celui du dépôt principal ; `git tag -d` des étiquettes ; paire Ed25519 d'essai par `openssl` (rien dans le trousseau) ; `CLE_MISES_A_JOUR` du clone = sa clé publique ; flux servi en local (`127.0.0.1`).
- [ ] **Step 2: N-1** — `MARKETING_VERSION 1.0.0`, **sans** le type Bonjour `_hue._tcp` ; `publier.sh --repetition … --url-base http://127.0.0.1:<port>/ --cle-privee … --cle-publique …`, signée Developer ID et notarisée.
- [ ] **Step 3: N** — `1.0.1`, avec `_hue._tcp` ; même commande ; flux à deux entrées.
- [ ] **Step 4: Attendus automatiques** — `sparkle-cli` : sans nouveauté rien ; un .dmg mal signé refusé (erreur 4005) ; N s'installe sur N-1 ; `spctl` « Notarized Developer ID » sur le .dmg et l'app ; `stapler validate` ; contrôles d'anonymisation : aucun défaut ; droits de l'app signée = ceux de §5.2 plus l'exception Automatisation, sans `cs.*`.
- [ ] **Step 5: Essai à la main avec Djoko** — N-1 ouverte (lancée et fermée par PID), « Rechercher les mises à jour… », « Installer et relancer » ; une seule alerte macOS au plus ; trousseau d'essai et réglages relus sans demande ; Bonjour : le pont Hue est trouvé par `_hue._tcp` après la mise à jour sans redémarrage (sinon : le noter, et la note de version de toute future version qui ajoute un type Bonjour dira de redémarrer le Mac).
- [ ] **Step 6: Ranger** — processus par PID, serveur, éléments de trousseau d'essai, conteneur d'essai à la corbeille ; résultats au registre `.superpowers/fusion/registre-phase-5.md` (comptes et verdicts, aucune valeur d'identité).

---

### Task 6: Relecture finale et fusion de l'outillage

- [ ] **Step 1: Relecture finale** — par Opus, sur toute la branche `phase-5` (outil recopié à l'octet, `publier.sh`, enveloppe d'anonymisation, notes et README, résultats de la répétition).
- [ ] **Step 2: Fusion** — correctifs éventuels, puis fusion de `phase-5` dans `main` et push, avec l'accord de Djoko (la publication exige `main` = `origin/main`, arbre propre).

---

### Task 7: Publication de Maillage IoT 1.0.0 (accord « publie 1.0.0 »)

- [ ] **Step 1: Préparer** — worktree neuf de `main` à jour (`git worktree add`, hors du dépôt) : il partage la garde `pre-push` et `garde.local.txt` du dépôt principal, que le commit du flux traverse ; historique complet ; auteur Djoko-cli noreply ; `SPARKLE_BIN` ; `gh auth status`. Le worktree est retiré après la publication.
- [ ] **Step 2: Publier** — `bash outils/publier.sh` dans un onglet du Terminal, journal suivi, guetteur en arrière-plan ; aucune sortie montrée sans masque.
- [ ] **Step 3: Vérifier en ligne** — version GitHub `v1.0.0` avec le .dmg ; flux brut `appcast.xml` à jour ; .dmg en ligne identique à celui du Bureau (SHA-256) ; `stapler validate` ; `spctl` sur le .dmg et l'app (sortie `origin=` masquée).
- [ ] **Step 4: Banc avec Djoko** — installer depuis le .dmg dans `/Applications` ; retirer l'ouverture de session et les copies de travail qui pointent vers DerivedData (même identifiant) ; premier lancement : réglages et données déjà présents gardés ; « Rechercher les mises à jour… » : à jour ; la vraie reprise depuis les exports de Thread et Zigbee si Djoko la veut maintenant (sinon notée « à faire »).

---

### Task 8: Anciennes apps, bandeaux et archivage (sessions Thread et Zigbee)

- [ ] **Step 1: Thread 1.4.0** — message à la session Thread : 1.0.0 en ligne (lien de la version), publier la 1.4.0 avec son `publier.sh`, sur l'accord de Djoko donné dans sa session ; vérifier le flux de Thread (tête 1.4.0) et que son lien vers Maillage IoT ouvre la 1.0.0.
- [ ] **Step 2: Zigbee 1.2.0** — même chose pour la session Zigbee (sa 1.2.0 compilée APRÈS le contrat final `0ba3833` : `sondeJournalPages` y est transitoire).
- [ ] **Step 3: Bandeaux** — chaque session ajoute en tête de ses README (EN et FR) « This project continues as Maillage IoT » / « Ce projet continue sous le nom de Maillage IoT », avec le lien, et pousse avec l'accord de Djoko.
- [ ] **Step 4: Archivage** — demander à Djoko l'accord explicite pour archiver `Djoko-cli/maillage-thread` et `Djoko-cli/maillage-zigbee` (`gh repo archive`), après que leurs flux ont servi la dernière version ; noter que l'archivage garde les flux lisibles.
- [ ] **Step 5: Feuille de route** — registre ; cocher « Phase 5 » dans la §6.1 de la spec ; commit et push avec l'accord de Djoko.
