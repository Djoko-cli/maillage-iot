# Maillage IoT, étape 3b : la vue A et l'interface commune — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à l'app unique son interface à deux protocoles : silhouettes (hexagone violet de Zigbee), interrupteurs de vue, bandes de qualité communes, légende, nom de la maison en haut à gauche, logos d'onglets, icône sans badge, journal et notifications par protocole, démo combinée avec sa référence, mesures contre l'étape 1, puis la liaison « Automatique » de la sonde Thread.

**Architecture:** L'étape ne touche pas le cœur de calcul de la scène : elle change le dessin (`Apparence`, `DessinNoeud`), la barre du haut, les Réglages, le journal, les notifications et la démo. Les deux rejeux d'un protocole seul restent exacts ; la démo combinée reçoit sa propre référence. La liaison Automatique de Thread, plus risquée, vient en dernier.

**Tech Stack:** Swift 6 strict, SwiftUI et AppKit, XcodeGen 2.46, xcodebuild, Swift Testing, bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — sections 3, 6.1 (critère de l'étape 3) et **6.7 (ajustements du 15/10 pour l'étape 3b, qui priment ; décisions 1 à 6)**.

**Inventaire** (local, hors git, lu par les exécutants) : `.superpowers/fusion/inventaire-etape3b.md` (§0 à §15, numéros de ligne de `main` à `cfb8db2`). Registre et constats du banc de l'étape 3a : `.superpowers/fusion/registre-etape-3a.md`. Décisions brutes de Djoko : `.superpowers/fusion/decisions-etape-3b.md`.

## Global Constraints

- **Les deux rejeux d'un protocole seul restent exacts à chaque tâche** : `docs/rejeu/thread-demo.json` et `docs/rejeu/zigbee-demo.json`, **jamais régénérés** ; ils sont calculés par `-demo-thread` et `-demo-zigbee` (démos seules, inchangées). À partir de la tâche 10, la référence combinée `docs/rejeu/maillage-iot-demo.json` aussi, écrite une seule fois.
- **À ne jamais changer** : `Passeur`, `Masqueur`, `PasseurTests`, `MaillageCoeur/Noms/NomsMaison.swift`, `MaillageCoeur/Noms/ProtocolePasseur.swift`, `MaillageCoeur/Annonces/CodageJSON.swift`, les `rawValue` des types d'événements écrits, les contrats des sondes flashées.
- Le cœur ne dépend d'aucun module de protocole ; `outils/verifier-noms-publics.sh` passe.
- Identité de l'app : `MaillageIoT`, `fr.djoko.maillage.iot`, « Maillage IoT », Sparkle conservé. Clés UserDefaults communes sans préfixe (vue : `vue.thread`, `vue.zigbee` ; journal : `journal.thread`, `journal.zigbee`), clés propres à un module préfixées `thread.` ou `zigbee.`.
- **Aucun port USB inconnu n'est ouvert** ; une carte retenue par un module n'est jamais ouverte par l'autre (registre `CartesRetenues`, tâche 12 de 3a).
- Tout texte nouveau passe par le catalogue (`outils/synchroniser-textes.sh`, traduction anglaise) ; `CataloguesTests` passe.
- Les tests n'utilisent jamais le vrai trousseau ni le vrai réseau.
- DerivedData `~/Library/Developer/Xcode/DerivedData/maillage-iot`. Avertissements = erreurs ; cœur et frameworks en `-O` même en Debug.
- Commentaires sans accents, textes d'interface avec accents ; commits en français sans accents, terminés par une ligne `Co-Authored-By:` du modèle auteur. L'utilisateur s'appelle **Djoko** ; aucun prénom réel ni chemin `/Users/<nom>` dans un fichier commité ; seulement des valeurs inventées dans les tests, la démo et les images.
- Ne jamais lire ni afficher `garde.local.txt` ni rien sous `.superpowers/anonymisation/` ni un fichier `*.local*`. Avant chaque commit : `bash outils/controler-index.sh` → 0 défaut.
- Blocs de commandes pour **bash**. Aucun push, aucun `git checkout` d'un autre commit dans la copie de travail, aucun `git stash` (la mesure de référence se fait dans une copie de travail à part, tâche 1).
- **Porte de chaque tâche** : `outils/tester.sh` passe en entier, `bash outils/verifier-noms-publics.sh` et `bash outils/tester-coeur.sh` aussi. Les nombres de `@Test` par cible sont notés avant et après ; aucune assertion perdue sans justification écrite au rapport. Les constantes de hauteur de la légende et de la fenêtre (`FenetrePiecesTests`, `sceneMinimale`) sont réécrites dans la tâche qui les déplace, jamais en fin d'étape.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Un rejeu décalé par le dessin ou la démo** : forme, couleur, filtre de vue ou horloge qui entrent dans la scène calculée ; `-demo` changé sans que `-demo-thread` garde la démo Thread seule. On attend les deux rejeux exacts et la référence combinée stable. → tâches 3, 5, 10.
2. **Un protocole masqué qui laisse une trace** : fiche, focus, isolement ou ligne de tournée d'un protocole masqué ; disposition qui bouge (le masquage doit être stable) ; protocole éteint dont l'interrupteur de vue reste actif. → tâche 5.
3. **Une préférence perdue** : notifications réglées en 3a (clés communes) qui reviennent au défaut après le passage aux clés par protocole ; choix de liaison Thread existant écrasé par « Automatique ». → tâches 8, 12.
4. **L'horloge de l'autre protocole** : dans la démo combinée, un nœud Thread jugé périmé par l'horloge de Zigbee (fiche, alerte, fenêtre). → tâche 10.
5. **La sonde Thread en Automatique qui ouvre la mauvaise carte ou bascule sans fin** : USB et réseau qui se disputent, carte de Zigbee ouverte, relances qui s'emballent. → tâche 12.

---

### Task 1: Mesure de référence de l'étape 1

D'après `inventaire-etape3b.md` §14. Le critère de l'étape 3 (spec 6.1) compare l'ouverture de la vue et la fluidité du zoom à Thread seul de l'étape 1.

**Files:**
- Create: `MaillageIoTTests/MesuresVueTests.swift` (temps d'ouverture de la scène de démo et coût d'une suite de zooms, mesurés hors écran ; écrits dans un fichier de résultats, jamais une assertion de durée) ; `docs/mesures/etape-1.json` (référence).
- Modify: `outils/mesurer.sh` (seconde ligne : les mesures de la vue).

- [x] **Step 1: Outil** — écrire `MesuresVueTests` (désactivé par défaut dans la porte, lancé par `outils/mesurer.sh vue`) et sa ligne dans `mesurer.sh`.
- [x] **Step 2: Référence** — dans une copie de travail à part (`git worktree add --detach /private/tmp/claude-501/mesure-e32f3a5 e32f3a5`, DerivedData à part), y copier l'outil adapté si besoin, mesurer Thread seul, écrire `docs/mesures/etape-1.json` dans le dépôt principal, puis `git worktree remove`.
- [x] **Step 3: Vérifier** — porte de la tâche ; `outils/mesurer.sh vue` sur `main` donne des valeurs du même ordre (noté au rapport).
- [x] **Step 4: Commit** — « Mesures de la vue : outil et reference de l'etape 1 ».

---

### Task 2: Bandes de qualité communes

D'après `inventaire-etape3b.md` §5 ; spec 6.7, décision 2.

**Files:**
- Modify: `MaillageCoeur` (`NiveauQualite` devient `BandeQualite`, avec un alias de transition si utile ; `EchelleSignal.bande(_:)`), `MaillageIoT/Vues/Pieces/Palette.swift` (`NiveauLien` supprimé), la fiche (`CourbesFiche`, `ComposantsFiche`).
- Test: tests du cœur sur `EchelleSignal` (dBm et LQI), `qualiteDUnLienSelonLeProtocole` (le 0 de Thread reste gris).

- [x] **Step 1: RED** — `bandeSelonLEchelle` (des valeurs dBm et LQI rangées dans les bonnes bandes) ; un lien Thread de qualité 0 reste gris dans la scène et « faible » nulle part ailleurs qu'aujourd'hui.
- [x] **Step 2: GREEN** — implémenter, sans changer une couleur affichée.
- [x] **Step 3: Vérifier** — porte de la tâche (deux rejeux exacts).
- [x] **Step 4: Commit** — « Bandes de qualite communes aux deux protocoles ».

---

### Task 3: Silhouettes — hexagone violet de Zigbee et légende

D'après `inventaire-etape3b.md` §1, §2, §6 ; spec 3.1, 6.7.

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/DessinNoeud.swift` (`Apparence` gagne la forme du protocole, valeur par défaut ronde), `Palette.swift` (couleur `routeurZigbee` violette, pont compris), `RenduCanvas.swift` (2D et 3D), `LegendePieces.swift` / `SigneLegende.swift` (ligne « ● Thread ⬢ Zigbee » seulement quand les deux protocoles sont dans la scène ; entrées communes rondes).
- Test: les ~30 assertions sur `Apparence` réécrites dans cette tâche ; `ondesDessinees` (`MaillageIoTTests/…/LegendePiecesZigbeeTests.swift`) étendu à l'hexagone (ondes, pile, anneau pointillé et sélection n'empiètent sur aucun sommet) ; constantes de hauteur de la légende.

- [x] **Step 1: RED** — `hexagoneZigbee` (routeur facetté, pastille et anneau hexagonaux pour un appareil et un disparu, pointe en haut, sommets sur le rayon) ; `routeurZigbeeViolet` (pont compris) ; `routeurDeBordureBleu` inchangé ; test de pixels étendu ; légende : la ligne de protocole présente avec deux protocoles, absente avec un seul.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte de la tâche (deux rejeux exacts : aucune forme ni couleur dans les références).
- [x] **Step 4: Commit** — « Silhouettes : hexagone violet pour Zigbee, ligne de protocole dans la legende ».

---

### Task 4: Icônes et logos

D'après `inventaire-etape3b.md` §11 ; spec 6.7.

**Files:**
- Create: `outils/icone/` (outil qui dessine la constellation sans badge, nœuds ronds et hexagonaux, à toutes les tailles de l'icône de l'app ; ses tests si l'outil est en Python) ; les logos de Thread et de Zigbee en vectoriel monochrome (PDF ou SVG d'images modèles) dans les ressources.
- Modify: `MaillageIoT/Ressources` (icône de l'app, logos), `IconeBarre` (barre des menus : le seul symbole du maillage, sans `MarqueThread`), onglets Thread et Zigbee des Réglages (logos en images modèles), README (crédits des marques, anglais puis français) ; supprimer `MarqueThread` s'il n'a plus d'usage.
- Test: `MenuTests.icone` réécrit (aucun badge) ; un test que les onglets chargent leurs logos (images modèles).

- [x] **Step 1: RED** — tests ci-dessus.
- [x] **Step 2: GREEN** — générer l'icône par l'outil (commande au rapport), brancher logos et icône. Les images ne contiennent aucun texte ni donnée réelle.
- [x] **Step 3: Vérifier** — porte de la tâche ; images jointes au rapport (chemins), pour le banc.
- [x] **Step 4: Commit** — « Icones : constellation sans badge generee, logos de Thread et de Zigbee ».

---

### Task 5: Barre du haut — nom de la maison et interrupteurs de vue

D'après `inventaire-etape3b.md` §3, §4 ; spec 3.1, 3.3, 6.7.

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/` (`ContenuHaut`, `BandeauPieces`, `HautPieces` : capsule de gauche = nom de la maison (Maison), menu des réseaux par protocole — Thread : réseaux, partitions, choix du réseau affiché ; Zigbee : le pont —, puis « ● Thread ⬢ Zigbee » ; « Appareils IP · N » seulement si Thread est montré ; ligne de tournée d'un protocole masqué cachée), `EntreeScene` (paramètre des protocoles montrés, combiné à `actif` ; masquage **stable** : la disposition est calculée sur les protocoles actifs, le masquage n'agit qu'au dessin), `FenetrePieces` (fiche, focus et isolement d'un nœud masqué fermés ; écran quand tout est masqué), préférences `vue.thread` / `vue.zigbee` (vrai par défaut).
- Test: `masquageStable` (positions des pièces et des nœuds visibles identiques, protocole montré ou masqué) ; `ficheFermeeAuMasquage` ; `interrupteurGriseProtocoleEteint` ; `appareilsIPSelonThread` ; constantes de largeur et de hauteur de la barre.

- [x] **Step 1: RED** — tests ci-dessus.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte de la tâche (deux rejeux exacts : le masquage n'entre pas dans la scène calculée).
- [x] **Step 4: Commit** — « Barre du haut : nom de la maison, interrupteurs de vue, masquage stable ».

---

### Task 6: Onglet d'un protocole éteint grisé

D'après `registre-etape-3a.md` (T12 m3, T11 M5) ; spec 6.7, décision 5.

**Files:**
- Modify: pages Thread et Zigbee des Réglages (tout grisé sauf « Activer ce protocole »).
- Test: `ongletGriseProtocoleEteint` pour chacun ; « Activer ce protocole » reste actif.

- [x] **Step 1: RED** — tests.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte de la tâche ; `ReglagesHauteurTests` vert.
- [x] **Step 4: Commit** — « Reglages : onglet d'un protocole eteint grise ».

---

### Task 7: Journal — filtres et marques par protocole

D'après `inventaire-etape3b.md` §7 ; spec 3.5, 6.7.

**Files:**
- Modify: `FenetreJournal` et ses familles (interrupteurs Thread / Zigbee propres au journal, mémorisés `journal.thread` / `journal.zigbee` ; marque ● ou ⬢ dans la couleur du protocole sur chaque ligne ; familles propres à un protocole filtré grisées).
- Test: `filtreDuJournalParProtocole`, `marqueDeLigne`, préférence gardée.

- [x] **Step 1: RED** — tests.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « Journal : filtres et marques par protocole ».

---

### Task 8: Notifications par protocole et menu de la barre

D'après `inventaire-etape3b.md` §8, §9 ; `registre-etape-3a.md` (Final m3 : deux blocs « Alerte dans l'heure » sans protocole) ; spec 3.5, 6.7, décision 4.

**Files:**
- Modify: `Notifications` / `Alertes` (catégories par protocole, clés `notification.<protocole>.<catégorie>` qui reprennent à la première lecture la valeur des clés communes actuelles), onglet Notifications (sections Thread et Zigbee, mêmes défauts), `MenuBarre` (chaque bloc d'alerte dit son protocole ; une ligne de résumé par protocole actif), `IconeBarre` (pire des deux réseaux actifs, déjà en place : test seulement).
- Test: `reprisesDesClesCommunes` (une catégorie coupée en 3a reste coupée pour les deux protocoles), `notificationSelonSonProtocole`, `menuAlerteAvecProtocole`.

- [x] **Step 1: RED** — tests.
- [x] **Step 2: GREEN** — implémenter.
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « Notifications par protocole, menu de la barre avec le protocole des alertes ».

---

### Task 9: « Identifier par Hue »

D'après `inventaire-etape3b.md` §13 ; spec 6.7, backlog.

**Files:**
- Modify: fiche Zigbee (`BoutonIdentifier` de Zigbee : « Identifier par Hue », « Identification… »), catalogue ; la spec 3.2 est déjà précisée (6.7).
- Test: libellé du bouton.

- [x] **Step 1: RED** — test du libellé.
- [x] **Step 2: GREEN** — renommer.
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « Fiche Zigbee : Identifier par Hue ».

---

### Task 10: Démo combinée et sa référence

D'après `inventaire-etape3b.md` §10 ; spec 3.6, 6.7, décision 3.

**Files:**
- Modify: `ModulesApp.protocoleDeLaDemo` (`-demo` = combinée, `-demo-thread`, `-demo-zigbee`), `Surveillance(demo:)` (combinée : les deux modèles), démo Zigbee recalée sur l'horloge de la démo Thread et homonymes renommés **dans la seule démo combinée** ; lectures d'horloge d'un nœud par l'horloge de son modèle (`FicheNoeud`, `FenetrePieces`, `Surveillance.alerte(de:)`) ; captures de la documentation (`docs/images`) refaites seulement si leur option change.
- Create: `MaillageIoTTests/ReferenceRejeuCombineeTests.swift` (identifiants préfixés), `docs/rejeu/maillage-iot-demo.json` (écrit une fois en bac à sable, relu, commité, jamais régénéré) ; un test « union » qui relit les deux références existantes.
- Test: les deux rejeux existants inchangés (par `-demo-thread` / `-demo-zigbee`) ; `horlogeDuModeleDuNoeud` (un nœud Thread de la démo combinée n'est pas périmé).

- [x] **Step 1: RED** — tests ci-dessus (la référence combinée est créée à l'étape 2, puis le test doit passer sans la régénérer).
- [x] **Step 2: GREEN** — implémenter ; écrire la référence une seule fois.
- [x] **Step 3: Vérifier** — porte de la tâche (trois références exactes).
- [x] **Step 4: Commit** — « Demo combinee : -demo, horloge par modele, reference de la scene combinee ».

---

### Task 11: Mesures finales

D'après la tâche 1 ; critère de l'étape 3 (spec 6.1).

- [ ] **Step 1: Mesurer** — `outils/mesurer.sh vue` sur la démo combinée et sur la démo Thread seule ; écrire `docs/mesures/etape-3b.json`.
- [ ] **Step 2: Comparer** — tableau au rapport contre `docs/mesures/etape-1.json` ; un écart de plus de 20 % sur l'ouverture ou le zoom de la démo Thread seule est un constat à remonter, pas à masquer.
- [ ] **Step 3: Commit** — « Mesures de la vue : etape 3b contre l'etape 1 ».

---

### Task 12: Liaison « Automatique » de la sonde Thread

D'après `inventaire-etape3b.md` §12 ; spec 6.7. Tâche la plus risquée : relecture par Opus.

**Files:**
- Modify: `MaillageIoT/Thread/Sonde/SondeMaillageThread.swift` (réglage séparé du chemin, comme `ReglageChemin` / `CheminSonde` de Zigbee : Automatique, USB, Réseau Thread ; Automatique = USB d'abord si la carte retenue est branchée, sinon le réseau Thread si la clé est connue et la sonde annoncée ; signal « annoncée » à créer côté Thread), la page Thread des Réglages (sélecteur toujours visible ; Réseau indisponible tant que la clé est inconnue, avec son explication), préférence (Automatique par défaut des nouvelles installations ; un choix existant gardé).
- Test: miroir des tests de chemin de Zigbee (`CheminSondeTests`) : choix du chemin selon branchée / clé connue / annoncée ; aucune carte de Zigbee ni carte inconnue ouverte ; pas de bascule sans fin (USB et réseau qui se disputent) ; choix existant gardé.

- [ ] **Step 1: RED** — tests.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche ; tests de la sonde Thread ×3.
- [ ] **Step 4: Commit** — « Sonde Thread : liaison Automatique, USB d'abord puis le reseau Thread ».

---

### Task 13: Banc avec Djoko

Fait par l'orchestrateur avec Djoko, après la relecture finale et ses correctifs.

- [ ] **Step 1: Préparer** — compiler `MaillageIoT` (Debug) ; images de l'icône et des logos ; tableau des mesures.
- [ ] **Step 2: Comparer** — les deux réseaux réels ensemble avec la vue A (hexagones violets, légende, interrupteurs, nom de la maison), masquage stable, journal et notifications par protocole, démo combinée (`-demo`), icône au Dock et dans la barre, logos des onglets ; la sonde Thread en Automatique (USB puis réseau) ; **places de la sonde Zigbee** (3 places TCP, 2 sessions H1) observées avec Zigbee 1.1.1 ouverte en même temps (critère 6.1).
- [ ] **Step 3: Verdict** — noté au registre ; plan coché ; fusion dans `main` et push avec l'accord de Djoko.
