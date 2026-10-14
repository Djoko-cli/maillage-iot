# Maillage IoT, étape 2 : Zigbee branché — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brancher Zigbee sur le cœur neutre : adopter au cœur ce que Zigbee a de générique, créer le framework `ProtocoleZigbee` et ses tests, recopier les outils et le firmware de la sonde Zigbee, et faire tourner le code d'app de Zigbee dans une cible d'app temporaire, « Maillage IoT Zigbee », dont la scène de démo est égale, octet pour octet, à la référence de Zigbee 1.1.1 — sans rien changer à ce que montre Thread.

**Architecture:** Trois temps. (1) Le cœur s'élargit de façon additive (enums unifiés, scène, courbes, journal, échelle de signal, enveloppe H1), Thread restant identique : le rejeu de la démo Thread reste exact à chaque tâche. (2) `ProtocoleZigbee` reçoit le code Zigbee du cœur de `maillage-zigbee`, renommé là où il entre en collision avec `ProtocoleThread` ou avec le cœur ; ses tests suivent. (3) Le code d'app de Zigbee entre dans la cible temporaire `MaillageIoTZigbee` (spec 6.5), avec ses tests et le rejeu de la démo Zigbee ; banc côte à côte avec Zigbee 1.1.1.

**Tech Stack:** Swift 6 strict, XcodeGen 2.46, xcodebuild, Swift Testing, Python 3 (unittest), PlatformIO (firmware recopié sans compilation), bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — sections 1, 2, 3.4, 6.1 (étape 2) et **6.5 (ajustements du 14/10, qui priment)**.

**Inventaires** (locaux, hors git, lus par les exécutants) : `.superpowers/fusion/inventaire-zigbee-coeur.md` (cœur Zigbee : classement des 49 fichiers, crochets, enums, collisions, tests), `.superpowers/fusion/inventaire-zigbee-app.md` (app Zigbee, identité, cible temporaire), `.superpowers/fusion/inventaire-zigbee-outils.md` (outils, firmware). Les numéros de ligne `Z:` renvoient à `maillage-zigbee` à `be6fadf`, `I:` à `maillage-iot` au début de l'étape. Registre et points reportés de l'étape 1 : `.superpowers/fusion/registre-etape-1.md`.

## Global Constraints

- Source Zigbee unique : `~/Dev/maillage-zigbee` à la révision **`be6fadf`**, lue par `git archive` (jamais la copie de travail, jamais `.superpowers/`). Le dépôt `maillage-zigbee` n'est jamais modifié.
- **Thread ne change pas** : le rejeu exact `MaillageIoTTests/ReferenceRejeuTests` (référence `docs/rejeu/thread-demo.json`, jamais régénérée) passe à chaque tâche. À partir de la tâche 11, le rejeu exact de Zigbee (`docs/rejeu/zigbee-demo.json`, jamais régénéré) aussi.
- Identité Zigbee : framework `ProtocoleZigbee` = `fr.djoko.maillage.iot.zigbee` ; tests `fr.djoko.maillage.iot.zigbee.tests` ; app temporaire « Maillage IoT Zigbee », module `MaillageIoTZigbee`, identifiant `fr.djoko.maillage.iot.banc-zigbee` (jamais publiée, sans Sparkle) ; services de trousseau `fr.djoko.maillage.iot.pont-hue` (compte = identifiant du pont) et `fr.djoko.maillage.iot.sonde-zigbee` (compte = IEEE de la sonde) ; sous-système des journaux `fr.djoko.maillage.iot` ; clés UserDefaults Zigbee préfixées `zigbee.` ; fichiers propres à Zigbee sous `Application Support/<dossier>/Zigbee/` (spec 2.2).
- **Contrats avec la sonde déjà flashée, inchangés** : service Bonjour `_maillage-zigbee._tcp`, port 5481, enveloppe H1, liste blanche des commandes.
- **À ne jamais changer** : `Passeur`, `Masqueur`, `PasseurTests`, `MaillageCoeur/Noms/NomsMaison.swift`, `MaillageCoeur/Noms/ProtocolePasseur.swift`, `MaillageCoeur/Annonces/CodageJSON.swift` (compilés aussi par le démon : ils restent autonomes), les `rawValue` des types d'événements déjà écrits dans des journaux.
- Le cœur ne dépend d'aucun module de protocole ; `ProtocoleZigbee` ne dépend que du cœur (jamais de `ProtocoleThread`).
- **Aucun nom public de premier niveau commun** à `ProtocoleThread` et `ProtocoleZigbee` (vérifié par `outils/verifier-noms-publics.sh`, tâche 7).
- Aucun test d'un fichier destiné à une cible de tests ne référence un symbole défini dans une **suite** d'une autre cible ; les aides partagées vivent dans des fichiers sans `@Test`.
- DerivedData `~/Library/Developer/Xcode/DerivedData/maillage-iot`. Swift 6 strict, avertissements = erreurs ; cœur et frameworks de protocole en `-O` même en Debug.
- Commentaires sans accents, textes d'interface avec accents ; commits en français sans accents, terminés par une ligne `Co-Authored-By:` du modèle auteur. L'utilisateur s'appelle **Djoko** ; aucun prénom réel ni chemin `/Users/<nom>` dans un fichier commité.
- Ne jamais lire ni afficher `garde.local.txt` ni rien sous `.superpowers/anonymisation/`. Avant chaque commit : `bash outils/controler-index.sh` → 0 défaut.
- Blocs de commandes écrits pour **bash** : les lancer sous bash, jamais zsh. Aucun push, aucun `git checkout` d'un autre commit, aucun `git stash`.
- **Porte de chaque tâche** : `outils/tester.sh` sans argument passe en entier. Un test ne change d'attente que si la tâche le dit. Les nombres de `@Test` par cible sont notés avant et après chaque tâche qui déplace ou scinde des tests : aucune assertion perdue.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Un crochet du cœur qui décale Thread** (rang et rayon, valeurs par défaut, filtre de liens, types d'événements déplacés, échelle) : on attend le rejeu Thread exact après chaque tâche. → toutes les tâches, `ReferenceRejeuTests`.
2. **L'inversion de sens `NomsMaison` / `AccessoireMaison`** : au cœur, le relevé de Maison ; chez Zigbee, les appareils du pont. Un renommage raté compile quand même. On attend que `FusionNoms` reçoive le relevé de Maison du cœur et les appareils du pont renommés. → tâche 7, test `fusionAvecLeReleveDuCoeur`.
3. **Un nom public commun aux deux modules de protocole** : ambiguïté qui n'éclaterait qu'à l'étape 3, dans l'app qui importe les deux. On attend un refus mécanique. → tâche 7, `outils/verifier-noms-publics.sh`.
4. **Un `pieces-routeurs.json` écrit par Zigbee (sans `maisons`)** : on attend qu'il se relise. → tâche 5, test `fichierSansMaisonsLisible`.
5. **Un ancien journal Zigbee relu** (types écrits par l'enum fermé de Zigbee 1.1.1, avec ou sans `gravite`) : on attend les mêmes gravités qu'avant. → tâche 8, test `journalZigbeeRelu`.

---

### Task 1: Dette de l'étape 1

Points reportés par la relecture finale de l'étape 1 (`.superpowers/fusion/registre-etape-1.md`, lignes `minor (deferred)`), traités en un lot.

**Files:**
- Modify: `MaillageCoeur/Systeme/FichiersGardes.swift`, `MaillageIoTTests/MisesAJourTests.swift`, `outils/passeur.sh`, `MaillageCoeur/Suivi/Alertes.swift`, `ProtocoleThreadTests/EvenementsThreadTests.swift`, `outils/tests/test_garde.py`
- Create: `outils/tester-coeur.sh`

- [x] **Step 1: Visibilités** — `FichiersGardes.Etat`, `examiner`, `mettreDeCote` redeviennent `internal` s'ils n'ont aucun utilisateur hors du module `MaillageCoeur` (les tests passent par `@testable`). Vérifier par compilation.
- [x] **Step 2: Sparkle** — dans `MisesAJourTests`, ajouter `#expect(info["CFBundleVersion"] as? String == "1")` (une compilation locale porte toujours le numéro 1).
- [x] **Step 3: passeur.sh** — l'usage cite `--comparer-versions` ; l'en-tête énonce la règle « toute modification de `Passeur/` monte `MARKETING_VERSION` » ; la comparaison départage deux `CFBundleShortVersionString` égaux par `CFBundleVersion` (test ajouté à `outils/tests/test_passeur_version.py` si le mode de comparaison change de signature).
- [x] **Step 4: Cœur seul** — `outils/tester-coeur.sh` : lance le schéma `MaillageCoeur` en test avec `ENABLE_TESTABILITY=YES` et le DerivedData du dépôt, journal dans `${TMPDIR:-/tmp}/maillage-iot-coeur.log`, code de sortie de xcodebuild.
- [x] **Step 5: Tests** — dans `EvenementsThreadTests`, une ligne Thread `appareilDisparu` **sans** `gravite`, relue avec la politique Thread, vaut `.attention` ; dans `test_garde.py`, `FF:1A:2B:CC` trouvé (identifiant court entre deux séparateurs) et un identifiant court impair trouvé isolé.
- [x] **Step 6: Commentaire** — `Alertes.swift`, commentaire « sans politique » remplacé par « avec la politique neutre ».
- [x] **Step 7: Vérifier et commiter** — `outils/tester.sh` (code 0), `bash outils/tester-coeur.sh` (code 0), `python3 -m unittest discover -s outils/tests -q` (OK), `controler-index` 0 ; commit « Dette de l'etape 1 : visibilites, Sparkle, passeur.sh, coeur seul, tests ».

---

### Task 2: Cœur — enums unifiés et graphe (repris de Zigbee)

D'après `inventaire-zigbee-coeur.md` §1.2 (GrapheReseau) et §2.1-2.2. Additif : Thread n'émet jamais les nouveaux cas.

**Files:**
- Modify: `MaillageCoeur/Scene/GrapheReseau.swift`, app Thread : `MaillageIoT/Vues/Pieces/{Palette,FicheNoeud,LegendePieces,SigneLegende}.swift` (switch exhaustifs)
- Test: `MaillageCoeurTests/GrapheManuelTests.swift`

**Interfaces:**
- Produces: `EtatAffiche.injoignable` (ordre : joignable, partitionCoupee, sansAdresse, injoignable, disparu, inconnu) ; `GrapheReseau.Lien.Genre.chemin` ; `Lien.suppose: Bool` (défaut `false` dans l'init) ; `GrapheReseau.init(noeuds:liens: = [])` qui **écarte les liens dont un bout manque** ; `func chemin(de id: String) -> String?` (premier lien `.chemin` partant de `id`) ; `AppareilAffiche.init(…, partition: String? = nil, …)`.

- [x] **Step 1: RED** — dans `GrapheManuelTests`, reprendre `noeudsDejaFaits` de `Z:MaillageCoeurTests/GrapheReseauTests.swift:84` (liens à bout manquant écartés), plus un test `cheminDUnNoeud` et un test `lienSuppose`. Lancer `outils/tester.sh MaillageCoeurTests/GrapheManuelTests` : échec de compilation attendu.
- [x] **Step 2: GREEN** — implémenter les interfaces ci-dessus dans le cœur, d'après `Z:Scene/GrapheReseau.swift` (lignes citées par l'inventaire). Dans l'app Thread, chaque `switch` exhaustif gagne le nouveau cas, avec le rendu de Zigbee pour `injoignable` (`Z:MaillageZigbee/Vues/Pieces/Palette.swift:44-48`) et pour `.chemin` (`Z:…/LegendePieces.swift:249-252`) ; Thread ne les produit jamais.
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, rejeu Thread compris) ; `bash outils/tester-coeur.sh` (code 0).
- [x] **Step 4: Commit** — « Coeur : etat injoignable, lien chemin et suppose, graphe tolerant aux liens orphelins ».

---

### Task 3: Cœur — scène (versions de Zigbee)

D'après `inventaire-zigbee-coeur.md` §1.2 (SceneProjetee, TransitionScene, DispositionPieces, ScenePieces) et §5 (tests à porter).

**Files:**
- Replace by Zigbee's version (adaptée au cœur IoT) : `MaillageCoeur/Scene/SceneProjetee.swift`, `MaillageCoeur/Scene/TransitionScene.swift`
- Modify: `MaillageCoeur/Scene/DispositionPieces.swift` (les liens `.chemin` n'entrent pas dans la disposition), `MaillageCoeur/Scene/ScenePieces.swift`
- Test: `MaillageCoeurTests/SceneProjeteeTests.swift`, `TransitionSceneTests.swift`, `ScenePiecesTests.swift`

**Interfaces:**
- Produces: `ModeLiens` (défaut `.tous`), `EtatAnime(…, liens: ModeLiens = .tous, voisins: Bool = true)`, `enum Trace`, `PosesScene.Lien.suppose`, `TransitionScene.graphe` ; `ScenePieces.init(…, classement: @Sendable (GrapheReseau.Noeud) -> (rang: Int, rayon: Double) = ScenePieces.classementParDefaut)` où `classementParDefaut` est la règle actuelle (Thread : bordure 1, routeur 2, sinon 3 ; rayons centre 15, bordure 13, routeur 8, sinon 7).

- [x] **Step 1: RED** — porter les tests de Zigbee : `liensSelonLeMode` et `voisinsMasquesEtParentDAvant` (`Z:MaillageCoeurTests/SceneProjeteeTests.swift:169-242`), le bloc focus estompé de `Z:TransitionSceneTests.swift:478-487`, un test `classementFourni` (une règle passée en paramètre donne ses rangs et rayons) et un test `liensCheminHorsDisposition`. Échec attendu.
- [x] **Step 2: GREEN** — reprendre `Z:Scene/SceneProjetee.swift` et `Z:Scene/TransitionScene.swift` (diff purement additif d'après l'inventaire), la règle `.chemin` de `Z:Scene/DispositionPieces.swift:230-231`, et le paramètre `classement` de `ScenePieces`. L'app Thread compile sans changement d'appel (valeurs par défaut).
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, rejeu Thread exact) ; `bash outils/tester-coeur.sh` ; `outils/mesurer.sh` (3 lignes « mesure : »).
- [x] **Step 4: Commit** — « Coeur : scene projetee et transitions de Zigbee (modes de liens, voisins, chemins), classement des noeuds parametre ».

---

### Task 4: Cœur — courbes, journal et types d'événements communs

D'après `inventaire-zigbee-coeur.md` §1.2 (CourbesNoeud, Regroupement), §2.4 (types communs) et §4.

**Files:**
- Modify: `MaillageCoeur/Maillage/CourbesNoeud.swift`, `MaillageCoeur/Suivi/Regroupement.swift`, `MaillageCoeur/Suivi/PolitiqueJournal.swift`, `ProtocoleThread/Suivi/EvenementsThread.swift`, app Thread : `MaillageIoT/Vues/Journal/FenetreJournal.swift`, `MaillageIoT/Vues/Pieces/FicheNoeud.swift`, `MaillageIoT/Thread/TexteEvenement.swift` (cas `.chemins`)
- Create: `MaillageCoeur/Suivi/TypeEvenement+Reseau.swift`
- Test: `MaillageCoeurTests/RegroupementParentsTests.swift`, `MaillageCoeurTests/PolitiqueEssai.swift`, `MaillageCoeurTests/CourbesNoeudTests.swift`

**Interfaces:**
- Produces: `PointCourbe.lqi: Double?` (défaut `nil`) ; `CourbesNoeud.chemins: [ChangementParent]` (défaut `[]` dans l'init public) ; une surcharge publique de `CourbesNoeud.reduire` qui porte une valeur d'origine (`(Date, Double, Double?)`) ; `LigneJournal.chemins([Evenement])` ; dans `PolitiqueJournal`, `func estChemin(_ e: Evenement) -> Bool` avec **implémentation par défaut `false`** (extension du protocole) ; `Regroupement` : clé `"chemin|"` ou `"parent|"` + `cleParent`, ligne `.chemins` si `estChemin` ; les 7 types communs déclarés **une seule fois au cœur** dans `TypeEvenement+Reseau.swift` : `routeurApparu` (info), `routeurDisparu` (alerte), `appareilNouveau` (info), `appareilDisparu` (attention), `appareilRevenu` (info), `parentChange` (info), `sansParent` (attention) — mêmes `rawValue` et gravités ; `EvenementsThread.swift` retire ces 7 déclarations et garde `PolitiqueJournalThread.types` **dans le même ordre**.

- [x] **Step 1: RED** — tests : `PolitiqueEssai` gagne un type `essaiChemin` et `estChemin` ; `cheminsRegroupes` (générique, `PolitiqueEssai`) ; `politiqueSansCheminInchangee` (une politique qui ne définit pas `estChemin` regroupe comme avant) ; `pointAvecLqi` et `reduireGardeLaValeurDOrigine`. Échec attendu.
- [x] **Step 2: GREEN** — implémenter, d'après `Z:Maillage/CourbesNoeud.swift` et `Z:Suivi/Regroupement.swift` ; les `switch` de l'app Thread sur `LigneJournal` gagnent `.chemins` (Thread n'en produit jamais) ; vérifier que `EvenementsThreadTests` passe sans changement d'attente (mêmes 22 noms, mêmes gravités, même ordre).
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, rejeu Thread exact) ; `bash outils/tester-coeur.sh`.
- [x] **Step 4: Commit** — « Coeur : courbes a LQI, regroupement des chemins, types d'evenements communs declares une fois ».

---

### Task 5: Cœur — échelle de signal paramétrée et pièces des routeurs

D'après `inventaire-zigbee-coeur.md` §3 et §1.1 (PiecesRouteurs).

**Files:**
- Modify: `MaillageCoeur/Maillage/EchelleSignal.swift`, `MaillageCoeur/Scene/PiecesRouteurs.swift`, app Thread `MaillageIoT/Vues/Pieces/CourbesFiche.swift`
- Create: `ProtocoleThread/Maillage/EchelleSignal+Thread.swift`
- Test: `MaillageCoeurTests/EchelleSignalTests.swift`, `MaillageCoeurTests/PiecesRouteursTests.swift`

**Interfaces:**
- Produces:
```swift
/// Echelle d'un signal (axe des courbes, etiquettes, bandes de qualite) : une par protocole (dBm pour Thread, LQI pour
/// Zigbee). Les fonctions qui ne dependent pas de l'unite restent statiques.
public struct EchelleSignal: Sendable {
    public var unite: String
    public var uniteAvant: Bool          // "LQI 182" (vrai) ou "-67 dBm" (faux)
    public var pas: Double               // 10 (dBm) ou 50 (LQI)
    public var marge: Double             // 5 (dBm) ou 10 (LQI)
    public var bornes: ClosedRange<Double>?   // nil (dBm) ou 0...255 (LQI)
    public var domaineParDefaut: ClosedRange<Double>  // -100...-40 (dBm) ou 0...255 (LQI)
    public init(unite:uniteAvant:pas:marge:bornes:domaineParDefaut:)
    public func domaine(_ valeurs: [Double]) -> ClosedRange<Double>?
    public func graduations(_ d: ClosedRange<Double>) -> [Double]
    public func etiquette(_ p: PointCourbe, periode: PeriodeCourbes, locale: Locale, fuseau: TimeZone) -> String
    // statiques inchanges : portee, seuil(periode:), plusProche(_:de:periode:), heure(…), aGauche(…)
}
```
  `ProtocoleThread` : `public extension EchelleSignal { static let dbm = EchelleSignal(unite: "dBm", uniteAvant: false, pas: 10, marge: 5, bornes: nil, domaineParDefaut: -100 ... -40) }` ; le cœur n'a aucune instance nommée (les tests du cœur ont une instance d'essai) ; `PiecesRouteurs` lit un fichier **sans** `maisons` (`decodeIfPresent`, défaut vide).

- [x] **Step 1: RED** — `EchelleSignalTests` : les tests dBm actuels passent sur une instance d'essai aux réglages dBm (mêmes attentes, mot pour mot) ; ajouter les cas à bornes et à pas 50 de `Z:MaillageCoeurTests/EchelleSignalTests.swift` sur une instance d'essai aux réglages LQI. `PiecesRouteursTests.fichierSansMaisonsLisible`. Échec attendu.
- [x] **Step 2: GREEN** — passer `EchelleSignal` en struct d'après le tableau §3 de l'inventaire (un seul algorithme couvre les deux) ; l'app Thread appelle `EchelleSignal.dbm` (y compris le domaine par défaut aujourd'hui codé en dur dans `CourbesFiche.swift`) ; `PiecesRouteurs` en `decodeIfPresent`.
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, rejeu Thread exact) ; `bash outils/tester-coeur.sh`.
- [x] **Step 4: Commit** — « Coeur : echelle de signal parametree (dBm pour Thread), pieces des routeurs lisibles sans maisons ».

---

### Task 6: Cœur — enveloppe H1

D'après `inventaire-zigbee-coeur.md` §1.4.

**Files:**
- Create: `MaillageCoeur/Reseau/EnveloppeH1.swift` (version de Zigbee, tout public, + `extension SessionH1: CustomReflectable` de Thread)
- Delete: `MaillageIoT/Thread/Sonde/Reseau/EnveloppeH1.swift` (copie de l'app)
- Test: `MaillageCoeurTests/EnveloppeH1Tests.swift` (fusion de `Z:MaillageCoeurTests/EnveloppeH1Tests.swift` et du test `sessionMasquee` de `MaillageIoTTests/EnveloppeH1Tests.swift`, avec leurs vecteurs) ; retirer `MaillageIoTTests/EnveloppeH1Tests.swift` une fois ses tests repris.

- [ ] **Step 1: Comparer** — `diff` entre la copie de l'app Thread et `Z:MaillageCoeur/Reseau/EnveloppeH1.swift` : noter dans le rapport chaque écart de comportement (il ne doit y en avoir aucun hors visibilité et masquage).
- [ ] **Step 2: Déplacer** — créer le fichier du cœur, supprimer la copie de l'app, l'app Thread utilise celui du cœur (`import MaillageCoeur` déjà présent).
- [ ] **Step 3: Tests** — fusion des tests dans `MaillageCoeurTests` ; nombre de `@Test` H1 avant (Thread + Zigbee) = après.
- [ ] **Step 4: Vérifier** — `outils/tester.sh` (code 0) ; `bash outils/tester-coeur.sh`.
- [ ] **Step 5: Commit** — « Coeur : enveloppe H1 commune aux deux sondes ».

---

### Task 7: Création de `ProtocoleZigbee`

D'après `inventaire-zigbee-coeur.md` §1.3, §2.4, §4 et §6.

**Files:**
- Create: `ProtocoleZigbee/` (fichiers « Z » de l'inventaire, recopiés de `be6fadf` puis renommés), cibles `ProtocoleZigbee` et `ProtocoleZigbeeTests` dans `project.yml`, `outils/verifier-noms-publics.sh`
- Create: `ProtocoleZigbee/Scene/GrapheReseau+Zigbee.swift`, `ProtocoleZigbee/Maillage/CourbesNoeud+Zigbee.swift`, `ProtocoleZigbee/Suivi/EvenementsZigbee.swift`, `ProtocoleZigbee/Maillage/EchelleSignal+Zigbee.swift`, `ProtocoleZigbee/Scene/ClassementZigbee.swift`

**Interfaces:**
- Consumes: tous les crochets des tâches 2 à 6.
- Produces: module `ProtocoleZigbee` (dépend de `MaillageCoeur` seulement), avec :
  - `GrapheReseau.init(maillage:appareils:)` et `GrapheReseau.partitionUnique` (`"zigbee"`) en extension ; `GrapheReseau.Noeud.init(id:genre:routeur:inconnu:extMac:)` en extension (partition `zigbee`, bordure faux) ;
  - `CourbesNoeud.init(cle:releves:periode:fin:)` en extension ;
  - `TypeEvenement.cheminChange` (info) ; `PolitiqueJournalZigbee` : `types` = 2 neutres + 7 communs + `cheminChange` ; `estPerte` = `appareilDisparu` ; ni scission ni réunion ; catégories `routeurDisparu` → `.routeurDisparu`, neutres → nil, le reste `.informations` ; `cleParent` = `details["ieee"] ?? sujet?.id` ; `estChemin` = `cheminChange` ;
  - `EchelleSignal.lqi` (unité LQI devant, pas 50, marge 10, bornes 0...255, domaine par défaut 0...255) ;
  - `ScenePieces.classementZigbee` (centre 1, routeur 2, sinon 3 ; rayons centre 15, routeur 8, sinon 7).
- **Renommages imposés** (inventaire §6), faits à la recopie, avant toute autre modification :
  - les appareils du pont : `NomsMaison` → `NomsZigbee`, `AccessoireMaison` → `AppareilPont` (Zigbee), puis `ReleveMaison` → `NomsMaison` du cœur et `AccessoireReleve` → `AccessoireMaison` du cœur (dans cet ordre) ;
  - suffixe `Zigbee` sur les 18 types publics en collision avec `ProtocoleThread` (liste de l'inventaire §6) et sur `ConstructionMaillage` ; fichiers de même nom de base suffixés (`HistoriqueMaillageZigbee.swift`…) ;
  - `NomsDemo` : les doublons `zones` et `domicile` sont retirés (ceux du cœur servent), `maison` → `maisonPont`, `places(etagee:dehors:)` → `placesEtagees(…)` ;
  - les 7 types communs ne sont **pas** redéclarés.

- [ ] **Step 1: Recopier** — `git -C ~/Dev/maillage-zigbee archive be6fadf <fichiers Z de l'inventaire §1.3>` dans `ProtocoleZigbee/`, en gardant les sous-dossiers (`Zigbee/`, `Sonde/`, `Pont/`, `Noms/`, `Maillage/`, `Suivi/`, `Demo/`) ; ne pas recopier les fichiers C= ni l'enveloppe H1.
- [ ] **Step 2: Renommer** — les renommages imposés, dans l'ordre ci-dessus.
- [ ] **Step 3: Crochets** — créer les extensions et la politique ; supprimer de la recopie ce que le cœur fournit désormais (enums, scène, courbes génériques, types communs).
- [ ] **Step 4: Cibles** — dans `project.yml`, sur le modèle exact de `ProtocoleThread` / `ProtocoleThreadTests` : `ProtocoleZigbee` (framework, `fr.djoko.maillage.iot.zigbee`, dépend de `MaillageCoeur`, `-O` en Debug) ; `ProtocoleZigbeeTests` (`fr.djoko.maillage.iot.zigbee.tests`, sources `ProtocoleZigbeeTests` + `MaillageCoeurTests/MaisonInventee.swift` + `MaillageCoeurTests/FixturesScene.swift`) ; ajoutés au schéma `MaillageIoT` (build et test). Le dossier `ProtocoleZigbeeTests/` reçoit pour l'instant un seul test, `fusionAvecLeReleveDuCoeur` (Review Focus 2) : `FusionNoms.fusionner(pont:maison:memoire:)` sur un `NomsZigbee` d'essai et un `NomsMaison` du cœur d'essai donne les noms attendus.
- [ ] **Step 5: Noms publics** — `outils/verifier-noms-publics.sh` :
```bash
#!/bin/bash
# Refuse un nom public de premier niveau commun a ProtocoleThread et ProtocoleZigbee (spec, contraintes de l'etape 2) :
# l'app de l'etape 3 importe les deux modules. Code 0 : aucun nom commun.
set -u
cd "$(dirname "$0")/.." || exit 1
noms() {
  grep -rhoE '^public (final )?(struct|enum|class|actor|protocol|typealias) [A-Za-z_][A-Za-z0-9_]*' "$1" --include='*.swift' \
    | awk '{print $NF}' | sort -u
}
communs=$(comm -12 <(noms ProtocoleThread) <(noms ProtocoleZigbee))
if [ -n "$communs" ]; then
  echo "noms publics communs aux deux protocoles :"; echo "$communs"; exit 1
fi
echo "verifier-noms-publics : aucun nom public commun"
```
  Puis `bash outils/verifier-noms-publics.sh` → code 0. Vérifier aussi qu'aucun `public static let` d'extension de `TypeEvenement` n'est déclaré dans les deux modules (`grep`).
- [ ] **Step 6: Vérifier** — `outils/tester.sh` (code 0, rejeu Thread exact) ; `grep -rlnE "^(@testable )?import ProtocoleThread" ProtocoleZigbee ProtocoleZigbeeTests | wc -l` → 0.
- [ ] **Step 7: Commit** — « ProtocoleZigbee : framework Zigbee sur le coeur neutre, noms sans collision ».

---

### Task 8: Tests de `ProtocoleZigbee`

D'après `inventaire-zigbee-coeur.md` §5 (table fichier par fichier).

**Files:**
- Create: `ProtocoleZigbeeTests/` (fichiers de `Z:MaillageCoeurTests` destinés à `ProtocoleZigbeeTests`, recopiés de `be6fadf`, adaptés aux renommages de la tâche 7), `ProtocoleZigbeeTests/AidesZigbeeTests.swift` (copies des aides de suites du cœur qu'ils utilisent : `calendrier`, `fichierPieces`…), `ProtocoleZigbeeTests/MaisonInventeeZigbeeTests.swift` (équivalence avec `MaisonInventee` du cœur, au champ `partition`/`bordure` près, sur le modèle de `FixturesThreadTests`)
- Modify (portages au cœur, ~250 lignes) : `MaillageCoeurTests/FichiersGardesTests.swift` (`appareilsMalFormes`), tests génériques de `FocusEtFicheTests`, `ChampsTXTCodageTests` (ex-`AnnoncesTests` de Zigbee), cas génériques de `RegroupementParentsTests` restants
- Test: `ProtocoleZigbeeTests/EvenementsZigbeeTests.swift`

- [ ] **Step 1: Effectifs** — noter le nombre de `@Test` de `Z:MaillageCoeurTests` (`git -C ~/Dev/maillage-zigbee show be6fadf:…` ou archive), et pour chaque fichier sa destination (jeté car identique au cœur IoT / porté au cœur / `ProtocoleZigbeeTests`) dans le rapport : aucune assertion perdue (une assertion « jetée » doit exister à l'identique dans `MaillageCoeurTests`).
- [ ] **Step 2: Recopier et adapter** — suites suffixées `Zigbee` quand le nom existe déjà dans une autre cible (`GrapheReseauZigbeeTests`, `HistoriqueZigbeeTests`, `TourneeZigbeeTests`…) ; aucune référence à une suite d'une autre cible.
- [ ] **Step 3: Journal Zigbee** — `EvenementsZigbeeTests` : chaque type de `PolitiqueJournalZigbee().types` se relit avec sa gravité ; `journalZigbeeRelu` (Review Focus 5) : des lignes écrites par Zigbee 1.1.1 (encodées par l'enum fermé de `be6fadf`, recopiées en littéral), avec et sans `gravite`, se relisent avec la politique Zigbee aux mêmes gravités.
- [ ] **Step 4: Vérifier** — `outils/tester.sh` (code 0) ; effectifs par cible notés ; `bash outils/tester-coeur.sh`.
- [ ] **Step 5: Commit** — « Tests de ProtocoleZigbee, portages generiques au coeur ».

---

### Task 9: Outils et firmware de la sonde Zigbee

D'après `inventaire-zigbee-outils.md` (§1-6).

**Files:**
- Create (recopiés de `be6fadf`) : `sonde-zigbee/` (ex-`sonde/`, 49 fichiers), `outils/ecoute/`, `outils/flasher.py`, `outils/sonde_usb.py`, `outils/sonde_reseau.py`, `outils/essai_sonde.py`, leurs tests dans `outils/tests/` (49 tests), `outils/tester-sondes.sh` (ex-`tester.sh` de Zigbee : tests des deux firmwares, des outils Python et de la garde)
- Modify: `flasher.py` (cible `sonde-zigbee/`), fichiers locaux renommés `sonde-zigbee.local.json` et `cle-zigbee.local` (code et tests), `outils/tests/test_gitignore.py`, renvois de `sonde-zigbee/` vers `docs/superpowers/…` de Zigbee (vers la spec de Maillage IoT)
- Ne pas recopier : `garde.py`, `mesurer.sh`, `synchroniser-textes.sh`, `tester-app.sh`, `traduire.py`, `publication.py`, `publier.sh`, `test_garde.py`, `test_publication.py`, `essais/`, fichiers locaux.

- [ ] **Step 1: Recopier** par `git archive be6fadf`, puis `mv sonde sonde-zigbee` ; ne jamais lire les fichiers `*.local*`.
- [ ] **Step 2: Adapter** les chemins et les fichiers locaux ; le service Bonjour et le port restent.
- [ ] **Step 3: Vérifier** — `python3 -m unittest discover -s outils/tests -q` (OK) ; `sh sonde-zigbee/test/lancer.sh` (code 0) ; `sh sonde-thread/test/lancer.sh` (code 0) ; `bash outils/tester-sondes.sh` (code 0).
- [ ] **Step 4: Commit** — « Sonde Zigbee : firmware sonde-zigbee, outils de flash et de banc, tests ».

---

### Task 10: App de transition « Maillage IoT Zigbee » — sources

Spec 6.5. D'après `inventaire-zigbee-app.md` (§1-4).

**Files:**
- Create: `MaillageIoTZigbee/` (recopie de `Z:MaillageZigbee/` à `be6fadf`, 58 fichiers + ressources), cible `MaillageIoTZigbee` dans `project.yml`, schéma `MaillageIoTZigbee`

**Interfaces:**
- Produces: une app qui compile sur `MaillageCoeur` + `ProtocoleZigbee` (jamais `ProtocoleThread`), produit « Maillage IoT Zigbee », module `MaillageIoTZigbee`, identifiant `fr.djoko.maillage.iot.banc-zigbee`, `CURRENT_PROJECT_VERSION` « 1 », **sans Sparkle** (ni paquet, ni clés `SU*`, mises à jour inactives), `NSBonjourServices` = `_hue._tcp`, `_maillage-zigbee._tcp`, droits de l'app Zigbee moins les exceptions de Sparkle.

- [ ] **Step 1: Recopier** `MaillageZigbee/` → `MaillageIoTZigbee/` par `git archive be6fadf` ; renommer `MaillageZigbeeApp` → `MaillageIoTZigbeeApp`.
- [ ] **Step 2: Brancher** — `import ProtocoleZigbee` là où le compilateur le demande ; appliquer les renommages de la tâche 7 (`NomsZigbee`, `AppareilPont`, `NomsMaison` du cœur, types suffixés `Zigbee`, `NomsDemo.maisonPont`…) ; `Alertes`, `JournalFichiers`, `Regroupement` reçoivent `PolitiqueJournalZigbee()` ; `EchelleSignal.lqi` ; `ScenePieces(…, classement: ScenePieces.classementZigbee)` ; l'enveloppe H1 du cœur.
- [ ] **Step 3: Identité définitive de Zigbee** — trousseau `fr.djoko.maillage.iot.pont-hue` et `fr.djoko.maillage.iot.sonde-zigbee` (comptes inchangés) ; sous-système `fr.djoko.maillage.iot` ; files `fr.djoko.maillage.iot.dnssd`, `.sonde-zigbee`, `.sonde-zigbee.tcp` ; clés UserDefaults préfixées `zigbee.` (liste de l'inventaire §3, y compris `liensMontres`, `voisinsALaSelection` et le budget de tournée) ; fichiers propres à Zigbee sous `Zigbee/` du dossier de données (`noms-pont.json`, `appariements-maison.json`, `dernier-maillage.json`, `maillage-AAAA-MM.jsonl`), le relevé de Maison en `releve-maison.json` ; dossier de données « Maillage IoT Zigbee » ; textes visibles « Maillage IoT Zigbee » (titre de fenêtre, menu, accessibilité, `NSLocalNetworkUsageDescription`) ; renvois à « outils/passeur.sh de Maillage Thread » → « outils/passeur.sh ».
- [ ] **Step 4: Cible** — dans `project.yml`, cible d'application `MaillageIoTZigbee` (sources `MaillageIoTZigbee`, dépendances `MaillageCoeur` et `ProtocoleZigbee`), schéma `MaillageIoTZigbee` ; le schéma `MaillageIoT` ne change pas pour cette tâche. Catalogue propre (`MaillageIoTZigbee/Ressources/`).
- [ ] **Step 5: Vérifier** — `xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoTZigbee -configuration Debug -derivedDataPath ~/Library/Developer/Xcode/DerivedData/maillage-iot build` (code 0, aucun avertissement) ; `outils/tester.sh` (code 0, Thread inchangé).
- [ ] **Step 6: Commit** — « App de transition Maillage IoT Zigbee : code d'app de Zigbee sur le coeur et ProtocoleZigbee ».

---

### Task 11: App de transition — tests et rejeu Zigbee

D'après `inventaire-zigbee-app.md` §5-6.

**Files:**
- Create: `MaillageIoTZigbeeTests/` (recopie de `Z:MaillageZigbeeTests/` à `be6fadf`, 35 fichiers), `docs/rejeu/zigbee-demo.json` (recopié de `be6fadf`, jamais régénéré), cible `MaillageIoTZigbeeTests` (hôte : `Maillage IoT Zigbee.app`)
- Modify: `project.yml` (la cible de tests ajoutée au schéma `MaillageIoT`, pour que `outils/tester.sh` lance tout), `MaillageCoeurTests/CataloguesTests.swift` (paramétré par app : `MaillageIoT` et `MaillageIoTZigbee`, catalogues et `.stringsdata` de chacune ; le test `rienDeThread` de Zigbee n'est pas repris), `outils/synchroniser-textes.sh` (paramètre d'app)

- [ ] **Step 1: Recopier et adapter** — `@testable import MaillageIoTZigbee`, `import ProtocoleZigbee` ; attentes d'identité changées pour la nouvelle (identifiant, services, titre, `NSBonjourServices`, mach-lookup absents sans Sparkle, `MisesAJourTests` adapté à l'absence de Sparkle) ; aucune autre attente ne change.
- [ ] **Step 2: Rejeu Zigbee** — `ReferenceRejeuTests` de Zigbee (recopié) compare la scène de la démo à `docs/rejeu/zigbee-demo.json` : il doit passer **sans régénérer** la référence.
- [ ] **Step 3: Catalogues** — `CataloguesTests` vérifie les deux apps ; `synchroniser-textes.sh <App>` ; les deux catalogues restent séparés jusqu'à l'étape 3 (les 7 traductions divergentes y seront arbitrées).
- [ ] **Step 4: Vérifier** — `outils/tester.sh` (code 0 ; effectifs par cible notés : cœur, ProtocoleThread, ProtocoleZigbee, app Thread, app Zigbee, démon ; rejeu Thread et rejeu Zigbee exacts) ; `bash outils/verifier-noms-publics.sh` ; `bash outils/tester-coeur.sh`.
- [ ] **Step 5: Commit** — « App de transition Zigbee : tests, rejeu exact de la demo Zigbee ».

---

### Task 12: Banc avec Djoko

Fait par l'orchestrateur avec Djoko, après la relecture finale et ses correctifs.

- [ ] **Step 1: Compiler et lancer** — `xcodebuild -scheme MaillageIoTZigbee -configuration Debug … build`, puis ouvrir « Maillage IoT Zigbee.app » à côté de Maillage Zigbee 1.1.1.
- [ ] **Step 2: Comparer** — vue par pièces 2D et 3D (nœuds, liens, chemins, voisins, pièces, étages) ; noms (le pont Hue se réappaire dans l'app de transition : appui sur le bouton du pont, nouveau service de trousseau) ; relevé de Maison par le démon commun ; journal. Sonde **en USB seulement**, débranchée de l'une avant de la brancher sur l'autre (une mise en service réseau changerait la clé de la sonde et couperait Zigbee 1.1.1 de sa sonde Wi-Fi).
- [ ] **Step 3: Verdict** — noté dans le registre ; ce plan coché ; fusion dans `main` et push avec l'accord de Djoko.
