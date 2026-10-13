# Maillage IoT, étape 1 : cœur neutre et Thread à l'identique — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faire de `maillage-iot` une copie fidèle de Maillage Thread 1.3.0 sous l'identité Maillage IoT, puis en extraire un cœur neutre (`MaillageCoeur`) et un framework `ProtocoleThread`, sans changer ce que l'app montre : la scène de la démo reste égale, octet pour octet, au résultat de référence.

**Architecture:** Trois temps. (1) Recopie depuis `maillage-thread` à la révision gelée `15a499a`, renommage des cibles et de l'identité, démon, outils, firmware et copie de Thread Route : tous les tests de Thread passent. (2) Préparation dans le même framework : fixtures de test neutres, journal neutre (`TypeEvenement` ouvert + politique injectée), coupes des quatre fichiers mixtes. (3) Création de `ProtocoleThread` et déplacement des 30 fichiers Thread et de leurs tests ; le code de l'app propre à Thread est rangé sous `MaillageIoT/Thread/`. Le test de rejeu tourne à chaque tâche.

**Tech Stack:** Swift 6 (concurrence stricte, avertissements = erreurs), XcodeGen 2.46, Xcode/xcodebuild, Swift Testing, Python 3 (unittest), PlatformIO (firmware, recopié sans compilation), bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — sections 1, 2.3, 5.3, 6.1 (étape 1) et **6.4 (ajustements du 14/10, qui priment)**.

**Inventaires** (locaux, hors git, lus par les exécutants) : `.superpowers/fusion/inventaire-coeur.md` (découpage de `MaillageCoeur`, fichier:ligne), `.superpowers/fusion/inventaire-app.md` (identité, app, tests), `.superpowers/fusion/inventaire-outils.md` (outils, démon, firmware). Les numéros de ligne y renvoient à `maillage-thread` à `15a499a`.

## Global Constraints

- Source unique : `~/Dev/maillage-thread` à la révision **`15a499a`**, lue par `git archive` (jamais la copie de travail, jamais `.superpowers/`). Le dépôt `maillage-thread` n'est jamais modifié.
- Identité : app `fr.djoko.maillage.iot`, produit « Maillage IoT », module `MaillageIoT`, cœur `fr.djoko.maillage.iot.coeur`, framework `fr.djoko.maillage.iot.thread`, dossier de données `Application Support/Maillage IoT/`, service de trousseau `fr.djoko.maillage.iot.sonde-thread`, sous-système des journaux système `fr.djoko.maillage.iot`, flux `https://raw.githubusercontent.com/Djoko-cli/maillage-iot/main/appcast.xml`, `MARKETING_VERSION` `1.0.0`, `CURRENT_PROJECT_VERSION` `"1"` (inchangé : il protège les compilations locales de Sparkle).
- **À ne jamais changer** : cibles `Passeur`, `Masqueur`, `PasseurTests` (identifiants `fr.djoko.maillage.passeur*`, schémas `maillage-passeur` et `maillage-passeur-1`, clé `MaillagePasseurProtocole`), les fichiers `MaillageCoeur/Noms/NomsMaison.swift`, `MaillageCoeur/Noms/ProtocolePasseur.swift`, `MaillageCoeur/Annonces/CodageJSON.swift` (compilés aussi par le démon : ils restent à ces chemins, sans nouvelle dépendance), les étiquettes `fr.djoko.thread.route` et `fr.djoko.halo.routes` (Thread Route, partagé avec le dépôt du pont Halo), la clé publique Sparkle `CLE_MISES_A_JOUR`.
- DerivedData propres à ce dépôt : `~/Library/Developer/Xcode/DerivedData/maillage-iot` (tests, textes, mesures) et `maillage-iot-passeur` (démon) ; jamais ceux de `maillage-thread`.
- Swift 6 strict, avertissements = erreurs ; le cœur et `ProtocoleThread` compilés en `-O` même en Debug.
- Commentaires de code sans accents ; textes de l'interface avec accents ; messages de commit en français sans accents, terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. L'utilisateur s'appelle **Djoko** ; aucun prénom réel, aucun chemin `/Users/<nom>` dans un fichier commité.
- **Ne jamais lire ni afficher** `garde.local.txt` ni rien sous `.superpowers/anonymisation/`. Avant chaque commit : `bash outils/controler-index.sh` (tâche 1) doit sortir `0`.
- Aucun push : l'orchestrateur pousse après la relecture finale. Jamais `--no-verify`.
- Les blocs de commandes de ce plan sont écrits pour **bash** : les lancer sous bash (`bash -c '…'` ou un script), jamais sous zsh, qui ne découpe pas les variables non citées.
- **Porte de chaque tâche** : `outils/tester.sh` sans argument passe en entier, `ReferenceRejeuTests` compris (rejeu exact de la démo contre `docs/rejeu/thread-demo.json`, jamais régénéré). Un test Swift ne se « corrige » jamais en changeant son attente pour la faire coller au code, sauf quand la tâche dit explicitement que l'attente change (identité).
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Un ancien journal relu** : une ligne `journal-*.jsonl` écrite par Thread 1.3.0, avec ou sans champ `gravite`, et une ligne au type inconnu (écrite plus tard par Zigbee). On attend la même lecture qu'avant, la gravité d'origine retrouvée, et le type inconnu conservé sans faire échouer le fichier. → tâche 5, tests `TypeEvenementTests`.
2. **Le cœur seul** : `MaillageCoeur` et `MaillageCoeurTests` compilent et passent sans `ProtocoleThread` (schéma `MaillageCoeur`, `outils/mesurer.sh`). → tâche 7, étapes 6 et 7.
3. **La nouvelle identité ne touche pas à l'ancienne** : dossier de données « Maillage IoT », service de trousseau neuf, domaine de préférences neuf ; rien n'est lu chez Maillage Thread. → tâche 2, tests `CleReseauTests` et `DossierDonneesTests`.
4. **Une compilation locale remplacée par Sparkle** : on attend que `CURRENT_PROJECT_VERSION` reste `"1"` et que le flux pointe vers `maillage-iot`. → tâche 1, `MisesAJourTests`.
5. **`passeur.sh` qui remplace un démon plus récent** (lancé depuis un dépôt en retard) : on attend un refus, sans rien arrêter ni remplacer. → tâche 3, `test_passeur_version.py`.

---

### Task 1: Recopie fidèle et nouvelle identité structurelle

**Files:**
- Create (recopiés de `15a499a`) : `MaillageCoeur/`, `MaillageCoeurTests/`, `MaillageIoT/` (ex-`MaillageThread/`), `MaillageIoTTests/` (ex-`MaillageThreadTests/`), `Passeur/`, `PasseurTests/`, `Masqueur/`, `Signature.xcconfig`, `outils/tester.sh`, `outils/mesurer.sh`, `outils/synchroniser-textes.sh`, `outils/traduire.py`, `outils/traductions/`, `docs/rejeu/thread-demo.json`, `docs/releves/2026-09-28/capture-1228.json`, `docs/releves/2026-09-29/capture-sonde.jsonl`, `docs/releves/2026-09-29/README.md`
- Replace: `project.yml` (celui de Thread, adapté)
- Create: `outils/controler-index.sh`
- Modify: `.gitignore`, `MaillageIoT/MaillageThreadApp.swift` → `MaillageIoT/MaillageIoTApp.swift`, les 40 fichiers de `MaillageIoTTests/`, `MaillageCoeurTests/CataloguesTests.swift`, `outils/tester.sh`, `outils/mesurer.sh`, `outils/synchroniser-textes.sh`

**Interfaces:**
- Produces: le projet `MaillageIoT.xcodeproj` (généré), schémas `MaillageIoT`, `MaillageCoeur`, `Passeur` ; module de l'app `MaillageIoT` (`@testable import MaillageIoT`) ; `struct MaillageIoTApp` ; `bash outils/controler-index.sh` (code 0 si l'index est propre).

- [x] **Step 1: Recopier les fichiers suivis de `15a499a`**

```bash
cd ~/Dev/maillage-merge
git -C ~/Dev/maillage-thread archive 15a499a \
  MaillageCoeur MaillageCoeurTests MaillageThread MaillageThreadTests Passeur PasseurTests Masqueur \
  Signature.xcconfig project.yml outils/tester.sh outils/mesurer.sh outils/synchroniser-textes.sh \
  outils/traduire.py outils/traductions docs/rejeu \
  docs/releves/2026-09-28/capture-1228.json docs/releves/2026-09-29/capture-sonde.jsonl \
  docs/releves/2026-09-29/README.md | tar -x
mv MaillageThread MaillageIoT && mv MaillageThreadTests MaillageIoTTests
mv MaillageIoT/MaillageThreadApp.swift MaillageIoT/MaillageIoTApp.swift
git status --short | head -20
```
Expected: les dossiers recopiés apparaissent non suivis ; `project.yml` apparaît modifié (celui de Thread a remplacé celui de l'étape 0).

- [x] **Step 2: Écrire `outils/controler-index.sh`**

```bash
#!/bin/bash
# Controle avant commit (plan de l'etape 1) : la garde sur les fichiers suivis, puis les deux controles
# d'anonymisation prives sur les fichiers indexes. N'affiche que des bilans. Code 0 : propre.
set -u
racine=$(git rev-parse --show-toplevel)
cd "$racine" || exit 1
anon=.superpowers/anonymisation
fautes=0
python3 outils/garde.py || fautes=$((fautes + 1))
liste=()
while IFS= read -r f; do [ -f "$f" ] && liste+=("$f"); done < <(git diff --cached --name-only --diff-filter=d)
if [ ${#liste[@]} -gt 0 ]; then
  python3 "$anon/thread/outils/controles.py" fichiers --table "$anon/thread/table.json" "${liste[@]}" \
    > "$anon/sortie-index-thread.txt" 2>&1 || { echo "controle thread : defaut" >&2; fautes=$((fautes + 1)); }
  python3 "$anon/zigbee/controles.py" fichiers --table "$anon/zigbee/table.json" "${liste[@]}" \
    > "$anon/sortie-index-zigbee.txt" 2>&1 || { echo "controle zigbee : defaut" >&2; fautes=$((fautes + 1)); }
  tail -1 "$anon/sortie-index-zigbee.txt"
fi
echo "controler-index : ${#liste[@]} fichier(s) indexe(s), $fautes defaut(s)"
[ "$fautes" -eq 0 ]
```
Puis `chmod +x outils/controler-index.sh`.

- [x] **Step 3: Adapter `project.yml`**

Sur la copie de Thread (numéros de ligne : `inventaire-app.md` §1 et §2), changer exactement :
- `name: MaillageThread` → `name: MaillageIoT` ; `bundleIdPrefix: fr.djoko.maillage` → `fr.djoko.maillage.iot` ;
- cible `MaillageCoeur` : `PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.maillage.iot.coeur` ;
- cible `MaillageThread` renommée `MaillageIoT` : `sources` et `info.path` sous `MaillageIoT/`, `CFBundleDisplayName: Maillage IoT`, `PRODUCT_NAME: Maillage IoT`, `PRODUCT_MODULE_NAME: MaillageIoT`, `PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.maillage.iot`, `MARKETING_VERSION: 1.0.0`, `CURRENT_PROJECT_VERSION: "1"` (inchangé), `FLUX_MISES_A_JOUR: https://raw.githubusercontent.com/Djoko-cli/maillage-iot/main/appcast.xml`, `CODE_SIGN_ENTITLEMENTS: MaillageIoT/Droits.entitlements` ; `CLE_MISES_A_JOUR` inchangée ; `NSLocalNetworkUsageDescription` inchangée ici (tâche 2) ;
- cible `MaillageCoeurTests` : `fr.djoko.maillage.iot.coeur.tests` ;
- cible `MaillageThreadTests` renommée `MaillageIoTTests` : `sources: MaillageIoTTests`, dépendance `MaillageIoT`, `fr.djoko.maillage.iot.tests`, `TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Maillage IoT.app/Contents/MacOS/Maillage IoT"` ;
- schéma `MaillageThread` renommé `MaillageIoT` (cibles de build et de test renommées de même) ;
- cibles `Passeur`, `Masqueur`, `PasseurTests`, schémas `Passeur` et `MaillageCoeur` : **aucun changement** ;
- en tête, remplacer le commentaire de Thread par : `# Maillage IoT, projet XcodeGen : ce fichier fait foi (le .xcodeproj est genere, jamais commite).`

- [x] **Step 4: Renommer le module et l'app dans le code et les tests**

```bash
grep -rl "@testable import MaillageThread" MaillageIoTTests | xargs sed -i '' 's/@testable import MaillageThread$/@testable import MaillageIoT/'
grep -rl "MaillageThreadApp" MaillageIoT MaillageIoTTests | xargs sed -i '' 's/MaillageThreadApp/MaillageIoTApp/g'
grep -rn "import MaillageThread\b\|MaillageThreadApp" MaillageIoT MaillageIoTTests MaillageCoeurTests | wc -l
```
Expected: `0`.

Puis, à la main :
- `MaillageCoeurTests/CataloguesTests.swift` (l. 12-13, 25-31) : `MaillageThread/Ressources` → `MaillageIoT/Ressources`, `MaillageThread.build` → `MaillageIoT.build` (les deux occurrences du chemin `Intermediates.noindex`) ;
- `MaillageIoTTests/DemarrageTests.swift:8` : identifiant attendu `fr.djoko.maillage.iot` ;
- `MaillageIoTTests/MisesAJourTests.swift` : version attendue `1.0.0` (l. 15), flux `https://raw.githubusercontent.com/Djoko-cli/maillage-iot/main/appcast.xml` (l. 16), services `["fr.djoko.maillage.iot-spks", "fr.djoko.maillage.iot-spki"]` (l. 32).

- [x] **Step 5: Adapter les scripts**

- `outils/tester.sh` : `DD` par défaut `$HOME/Library/Developer/Xcode/DerivedData/maillage-iot`, journal `${TMPDIR:-/tmp}/maillage-iot-tests.log`, `-project MaillageIoT.xcodeproj -scheme MaillageIoT`, exemple d'en-tête `MaillageIoTTests`.
- `outils/mesurer.sh` : `DD` par défaut `.../DerivedData/maillage-iot`, journal `maillage-iot-mesures.log`, `-project MaillageIoT.xcodeproj` (schéma `MaillageCoeur` inchangé).
- `outils/synchroniser-textes.sh` : `DD` par défaut `.../DerivedData/maillage-iot`, `MaillageIoT.build/Debug/MaillageIoT.build/Objects-normal`, `MaillageIoT/Ressources/Localizable.xcstrings`.

Puis : `grep -rn "MaillageThread\|DerivedData/maillage\"\|DerivedData/maillage$" outils/*.sh | wc -l` → `0`.

- [x] **Step 6: `.gitignore` des Info.plist générés**

Ajouter à `.gitignore`, sous le bloc XcodeGen :
```gitignore
# Info.plist generes par xcodegen (project.yml, info:)
MaillageIoT/Info.plist
Passeur/Info.plist
Masqueur/Info.plist
```

- [x] **Step 7: Lancer toute la suite**

Run: `outils/tester.sh > .superpowers/sdd/etape1-t1.log 2>&1; echo "code=$?"; tail -5 .superpowers/sdd/etape1-t1.log`
Expected: `code=0`, `** TEST SUCCEEDED **` ; environ 1 024 tests Swift (MaillageCoeurTests, MaillageIoTTests, PasseurTests), `ReferenceRejeuTests` compris.

- [x] **Step 8: Commit**

```bash
git add -A
git status --short | grep -c "Info.plist\|xcodeproj"   # attendu : 0
bash outils/controler-index.sh
git commit -q -F - <<'EOF'
Recopie de Maillage Thread 1.3.0 (15a499a) sous l'identite Maillage IoT

Cibles, module, identifiants, flux Sparkle et scripts renommes ; Passeur, Masqueur et leurs identifiants
inchanges. Tous les tests de Thread passent, rejeu de la demo compris.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```
Expected: `controler-index : … 0 defaut(s)`, puis le commit.

---

### Task 2: Identité visible, dossier de données, trousseau et préférences

**Files:**
- Modify: `MaillageIoT/Surveillance/Surveillance.swift` (l. 124, 127-128, 133-136), `MaillageIoT/Sonde/Reseau/Trousseau.swift` (l. 38-44, 82), `MaillageIoT/Sonde/SondeMaillage.swift` (l. 39-48), `MaillageIoT/Surveillance/Notifications.swift` (l. 10, 14), `MaillageIoT/Vues/Pieces/MoteurPieces.swift` (l. 125), `MaillageCoeur/Systeme/FichiersGardes.swift` (l. 26-27), `MaillageIoT/Sonde/LiaisonSerie.swift` (l. 25), `MaillageIoT/Sonde/Reseau/TransportUDP.swift` (l. 35), `MaillageIoT/Recenseur/ResolveurDNSSD.swift` (l. 76), `MaillageIoT/MaillageIoTApp.swift` (l. 99), `MaillageIoT/Vues/MenuBarre.swift` (l. 43, 93), `MaillageIoT/Vues/Pieces/MorceauxFenetre.swift` (l. 188), `MaillageIoT/Sonde/Reseau/ErreurReseau.swift` (l. 35), `project.yml` (`NSLocalNetworkUsageDescription`), `MaillageIoT/Ressources/Localizable.xcstrings`, `MaillageIoT/Ressources/InfoPlist.xcstrings`, `outils/traductions/interface.json`
- Modify (attentes) : `MaillageIoTTests/CleReseauTests.swift:114`, `MaillageIoTTests/FenetrePiecesTests.swift` (l. 754, 800, 816, 818), `MaillageIoTTests/CarteSimulee.swift:23`, `MaillageIoTTests/SondeTests.swift:685`, `MaillageIoTTests/SurveillanceTests.swift` (l. 150-160)
- Create: `MaillageIoTTests/DossierDonneesTests.swift`

**Interfaces:**
- Consumes: le projet de la tâche 1.
- Produces: `Surveillance.dossierParDefaut` se termine par `Maillage IoT` ; `Trousseau()` sert `fr.djoko.maillage.iot.sonde-thread` ; clés UserDefaults `thread.scissionsNotifiees`, `thread.sondeSerieUSB`, `thread.sondeNom`, `thread.sondeHote`, `thread.sondeLiaison`.

- [x] **Step 1: Écrire les attentes (RED)**

`MaillageIoTTests/DossierDonneesTests.swift` :
```swift
import Foundation
import Testing
@testable import MaillageIoT

/// Identite de Maillage IoT (spec, sections 2.2 et 2.3) : rien n'est lu ni ecrit chez Maillage Thread.
@MainActor
@Suite("Identite : dossier de donnees et preferences de Maillage IoT")
struct DossierDonneesTests {
    @Test func dossierDeDonnees() {
        #expect(Surveillance.dossierParDefaut.lastPathComponent == "Maillage IoT")
        #expect(Surveillance.dossierParDefaut.path.contains("Maillage Thread") == false)
    }

    @Test func clesDePreferencesThreadPrefixees() {
        #expect(SondeMaillage.cles.allSatisfy { $0.hasPrefix("thread.") })
        #expect(Surveillance.cleScissionsNotifiees == "thread.scissionsNotifiees")
    }
}
```
Si `SondeMaillage` n'expose pas encore ses clés en une liste `cles` ni `Surveillance` sa clé en `cleScissionsNotifiees`, les ajouter (constantes statiques internes, tirées des définitions actuelles : SondeMaillage.swift l. 42-48, Surveillance.swift l. 124) fait partie de l'étape 3.

Changer les attentes existantes : `CleReseauTests.swift:114` attend le service `fr.djoko.maillage.iot.sonde-thread` ; `FenetrePiecesTests.swift` l. 754, 800, 816, 818 attendent le titre « Maillage IoT » ; `CarteSimulee.swift:23` → `fr.djoko.maillage.iot.tests.connexion` ; `SondeTests.swift:685` → `fr.djoko.maillage.iot.tests.sonde.` ; `SurveillanceTests.swift` l. 150-160 lit la clé `thread.scissionsNotifiees`.

- [x] **Step 2: Vérifier l'échec**

Run: `outils/tester.sh MaillageIoTTests/DossierDonneesTests MaillageIoTTests/CleReseauTests MaillageIoTTests/FenetrePiecesTests > .superpowers/sdd/etape1-t2-red.log 2>&1; echo "code=$?"; grep -E "✘|error:" .superpowers/sdd/etape1-t2-red.log | head`
Expected: échecs (ou erreurs de compilation sur `cles` et `cleScissionsNotifiees`) : le dossier vaut encore « Maillage Thread », etc.

- [x] **Step 3: Changer l'identité dans le code**

- `Surveillance.swift:136` : `.appendingPathComponent("Maillage IoT")` (et le commentaire l. 133) ; l. 124 : clé `thread.scissionsNotifiees`, exposée en `static let cleScissionsNotifiees` ;
- `SondeMaillage.swift` l. 42-48 : clés `thread.sondeSerieUSB`, `thread.sondeNom`, `thread.sondeHote`, `thread.sondeLiaison`, exposées en `static let cles: [String]` ;
- `Trousseau.swift:44` : service par défaut `fr.djoko.maillage.iot.sonde-thread` (et sa doc l. 38) ; l. 82 : libellé `"Maillage IoT - sonde Thread \(nom)"` ;
- sous-système des `Logger` → `fr.djoko.maillage.iot` : FichiersGardes.swift l. 26, SondeMaillage.swift l. 39, Surveillance.swift l. 127, Notifications.swift l. 10 et 14, MoteurPieces.swift l. 125 ;
- files d'attente : LiaisonSerie.swift:25 `fr.djoko.maillage.iot.sonde-thread` ; TransportUDP.swift:35 `fr.djoko.maillage.iot.sonde-thread.udp` ; ResolveurDNSSD.swift:76 `fr.djoko.maillage.iot.dnssd` ;
- textes : `MaillageIoTApp.swift:99` `Window("Maillage IoT", id: "graphe")` ; `MenuBarre.swift:43` et `:93` (« Quitter Maillage IoT ») ; `MorceauxFenetre.swift:188` (« Autorisez Maillage IoT … ») ; `ErreurReseau.swift:35` (« … › Maillage IoT. ») ;
- `project.yml`, `NSLocalNetworkUsageDescription` : `Maillage IoT écoute les annonces du réseau local (routeurs de bordure Thread, appareils Matter et HomeKit) pour dessiner le réseau Thread, et se connecte à sa sonde par le réseau Thread si vous le choisissez.` ;
- la même phrase dans `MaillageIoT/Ressources/InfoPlist.xcstrings` (fr), et son anglais (en) avec « Maillage IoT » à la place de « Maillage Thread ».

Puis : `grep -rn "Maillage Thread" MaillageIoT MaillageCoeur project.yml | grep -v "^.*//" | wc -l` → `0` (les commentaires seuls peuvent rester).

- [x] **Step 4: Resynchroniser les textes**

```bash
outils/tester.sh MaillageIoTTests/DemarrageTests > /dev/null 2>&1   # compile, produit les .stringsdata
outils/synchroniser-textes.sh
```
Puis, dans `outils/traductions/interface.json`, remplacer les trois clés qui citent « Maillage Thread » (l. 58, 82, 191) par les nouvelles phrases françaises, avec leur anglais où « Maillage Thread » devient « Maillage IoT », et lancer :
```bash
python3 outils/traduire.py MaillageIoT/Ressources/Localizable.xcstrings outils/traductions/interface.json
python3 outils/traduire.py MaillageIoT/Ressources/Localizable.xcstrings outils/traductions/demon.json
```
Expected: aucune clé « stale » restante ; les quatre clés du catalogue qui contenaient le nom sont remplacées.

- [x] **Step 5: Lancer toute la suite**

Run: `outils/tester.sh > .superpowers/sdd/etape1-t2.log 2>&1; echo "code=$?"; tail -3 .superpowers/sdd/etape1-t2.log`
Expected: `code=0` ; `CataloguesTests` passe (catalogue et code alignés) ; `DossierDonneesTests` passe.

- [x] **Step 6: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
Identite visible de Maillage IoT : dossier de donnees, trousseau, preferences, textes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Démon, outils, firmware `sonde-thread/` et copie de Thread Route

**Files:**
- Create (recopiés de `15a499a`) : `outils/passeur.sh`, `outils/verifier-passeur.py`, `outils/anonymiser-sonde.py`, `outils/tests/test_verifier_passeur.py`, `outils/tests/test_thread_route.py`, `outils/thread-route/` (11 fichiers, bits d'exécution conservés), `outils/thread-route.source`, `outils/synchroniser-thread-route.sh`, `sonde-thread/` (ex-`sonde/`, 26 fichiers)
- Create: `outils/tests/test_passeur_version.py`
- Modify: `outils/passeur.sh` (DD, projet, refus d'un démon plus récent), `sonde-thread/sonde_essai.py` (l. 27, 36), `sonde-thread/README.md` (l. 23-24, 296), `sonde-thread/platformio.ini` (l. 2, 6)

**Interfaces:**
- Consumes: le projet de la tâche 1 (schéma `Passeur`).
- Produces: `outils/passeur.sh --comparer-versions INSTALLEE CONSTRUITE` (code 0 si `CONSTRUITE` ≥ `INSTALLEE`, code 1 et message sinon) ; l'installation refuse de remplacer un démon installé plus récent.

- [x] **Step 1: Recopier**

```bash
cd ~/Dev/maillage-merge
git -C ~/Dev/maillage-thread archive 15a499a outils/passeur.sh outils/verifier-passeur.py outils/anonymiser-sonde.py \
  outils/tests/test_verifier_passeur.py outils/tests/test_thread_route.py outils/thread-route \
  outils/thread-route.source outils/synchroniser-thread-route.sh sonde | tar -x
mv sonde sonde-thread
python3 -m unittest discover -s outils/tests -q 2>&1 | tail -2
```
Expected: `OK` (garde, pre-push, gitignore, vérificateur du démon, empreinte de Thread Route).

- [x] **Step 2: Écrire le test de version (RED)**

`outils/tests/test_passeur_version.py` :
```python
"""Tests du refus de passeur.sh : ne jamais remplacer un demon installe plus recent (spec, section 5.3).

  python3 -m unittest discover -s outils/tests -q
"""
import os
import subprocess
import unittest

SCRIPT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "passeur.sh"))


def comparer(installee, construite):
    return subprocess.run(["bash", SCRIPT, "--comparer-versions", installee, construite],
                          capture_output=True, text=True)


class VersionPasseurTests(unittest.TestCase):
    def test_meme_version_acceptee(self):
        self.assertEqual(comparer("2.0", "2.0").returncode, 0)

    def test_version_plus_recente_acceptee(self):
        self.assertEqual(comparer("2.0", "2.1").returncode, 0)

    def test_demon_installe_plus_recent_refuse(self):
        r = comparer("2.10", "2.9")
        self.assertEqual(r.returncode, 1)
        self.assertIn("plus recent", r.stderr)

    def test_aucun_demon_installe_accepte(self):
        self.assertEqual(comparer("", "2.0").returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest outils/tests/test_passeur_version.py 2>&1 | tail -3`
Expected: `FAILED` (l'option `--comparer-versions` n'existe pas encore).

- [x] **Step 3: Implémenter le refus dans `outils/passeur.sh`**

Ajouter, juste après le traitement des options existantes (avant toute compilation) :
```bash
# Refus de remplacer un demon plus recent (spec de Maillage IoT, section 5.3) : version installee contre
# version construite, comparees par `sort -V`. Sans demon installe : accepte.
plus_ancien_que_installe() {  # $1 : installee, $2 : construite ; code 0 si la construite est plus ancienne
  [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}
if [ "${1:-}" = "--comparer-versions" ]; then
  if plus_ancien_que_installe "${2:-}" "${3:-}"; then
    echo "passeur.sh : le demon installe ($2) est plus recent que celui-ci ($3) : rien n'est remplace" >&2
    exit 1
  fi
  exit 0
fi
```
Et, après la compilation, avant d'arrêter le démon en place : lire `CFBundleShortVersionString` de `$APP/Contents/Info.plist` (vide si absent) et du produit construit (`PlistBuddy -c 'Print :CFBundleShortVersionString'`), et sortir en code 1 avec le même message si `plus_ancien_que_installe` est vrai.

Adapter aussi : `DD` par défaut `$HOME/Library/Developer/Xcode/DerivedData/maillage-iot-passeur` (l. 32) ; `-project MaillageIoT.xcodeproj` (l. 81) ; le commentaire l. 2 renvoie à `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` (section 5.3).

- [x] **Step 4: Vérifier le passage**

Run: `python3 -m unittest discover -s outils/tests -q 2>&1 | tail -2`
Expected: `OK`.

- [x] **Step 5: Firmware et sonde**

- `sonde-thread/sonde_essai.py` l. 27 et 36, et `sonde-thread/README.md:296` : service de trousseau `fr.djoko.maillage.iot.sonde-thread`.
- `sonde-thread/README.md` l. 23-24 et `sonde-thread/platformio.ini` l. 2 et 6 : les renvois à `docs/superpowers/…` de Thread deviennent un renvoi à `docs/superpowers/specs/2026-10-13-maillage-iot-design.md`.
- Ne rien changer d'autre dans `sonde-thread/` (ni `src/`, ni le nom de fabricant Matter).

Run:
```bash
python3 -m unittest discover -s sonde-thread/test -q 2>&1 | tail -2
sh sonde-thread/test/lancer.sh > .superpowers/sdd/etape1-t3-cpp.log 2>&1; echo "c++ code=$?"
sh outils/thread-route/tests.sh > .superpowers/sdd/etape1-t3-route.log 2>&1; echo "route code=$?"
```
Expected: `OK` (146 tests), `c++ code=0`, `route code=0`. Si un test de `sonde_essai` attend l'ancien service, changer cette attente seulement.

- [x] **Step 6: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
Demon, outils, firmware sonde-thread et copie de Thread Route ; passeur.sh refuse un demon plus recent

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Graphe constructible à la main et fixtures neutres du cœur

**Files:**
- Modify: `MaillageCoeur/Scene/GrapheReseau.swift` (nouvel init public), `MaillageCoeurTests/MaisonInventee.swift`, `MaillageCoeurTests/ScenePiecesTests.swift` (fixture `graphe(sonde:)`, l. 11-40)
- Create: `MaillageCoeurTests/GrapheManuelTests.swift`, `MaillageCoeurTests/FixturesThreadTests.swift` (équivalences, partira dans `ProtocoleThreadTests` à la tâche 7), `MaillageCoeurTests/AidesThreadTests.swift` (copies de `PiecesRouteursTests.fichier()` et `JournalTests.calendrier` pour les tests Thread)
- Modify: `MaillageCoeurTests/PiecesAppareilsTests.swift` (l. 155, 197), `MaillageCoeurTests/HistoriqueTests.swift` (l. 109, 131, 143)

**Interfaces:**
- Produces: `public init(noeuds: [GrapheReseau.Noeud], liens: [GrapheReseau.Lien])` ; `MaisonInventee` et `ScenePiecesTests.graphe(sonde:)` construits sans aucun type Thread ; `AidesThread.fichierPieces()` et `AidesThread.calendrier` pour les tests Thread.

- [x] **Step 1: Test du graphe manuel (RED)**

`MaillageCoeurTests/GrapheManuelTests.swift` :
```swift
import Testing
@testable import MaillageCoeur

@Suite("Graphe construit a la main, sans protocole")
struct GrapheManuelTests {
    @Test func noeudsEtParent() {
        let g = GrapheReseau(
            noeuds: [.init(id: "c", genre: .centre, partition: "p", routeur: true, bordure: true, inconnu: false),
                     .init(id: "a", genre: .appareil, partition: "p", routeur: false, bordure: false, inconnu: false)],
            liens: [.init(de: "a", vers: "c", genre: .parent, qualite: 3)])
        #expect(g.noeuds.map(\.id) == ["c", "a"])
        #expect(g.noeud("a")?.genre == .appareil)
        #expect(g.parent(de: "a") == "c")
    }
}
```
Run: `outils/tester.sh MaillageCoeurTests/GrapheManuelTests > .superpowers/sdd/etape1-t4-red.log 2>&1; echo "code=$?"`
Expected: échec de compilation (`init(noeuds:liens:)` absent).

- [x] **Step 2: Ajouter l'init**

Dans `GrapheReseau` (le type reste au cœur) :
```swift
    /// Graphe donne tel quel : la construction propre a un protocole (ProtocoleThread : `init(reseau:appareils:maillage:)`)
    /// delegue ici, et les tests du coeur s'en servent sans aucun type de protocole.
    public init(noeuds: [Noeud], liens: [Lien]) {
        self.noeuds = noeuds
        self.liens = liens
    }
```
L'init Thread existant (l. 111) se termine désormais par un appel à cet init, sans autre changement.

- [x] **Step 3: Fixtures neutres et équivalences**

- Dans `FixturesThreadTests.swift`, déplacer **tel quel** le code actuel qui bâtit `MaisonInventee` et `ScenePiecesTests.graphe(sonde:)` avec `Banc`, `Instantane`, `ConstructionMaillage` et `MaillageAffiche`, en fonctions `MaisonInventeeThread…` et `grapheThread(sonde:)`.
- Récrire `MaisonInventee` et `ScenePiecesTests.graphe(sonde:)` avec `GrapheReseau(noeuds:liens:)` et des littéraux : mêmes nœuds, mêmes liens, même ordre. Pour les obtenir, afficher une fois le graphe produit par la version Thread (`dump`) et le recopier.
- Dans `FixturesThreadTests.swift`, un test par fixture : `#expect(versionManuelle == versionThread)` (les deux `GrapheReseau` sont `Hashable`).
- Copier `PiecesRouteursTests.fichier()` et `JournalTests.calendrier` dans `AidesThreadTests.swift` (`enum AidesThread`), et faire lire ces copies par `PiecesAppareilsTests` (l. 155, 197) et `HistoriqueTests` (l. 109, 131, 143).

- [x] **Step 4: Vérifier**

Run:
```bash
outils/tester.sh > .superpowers/sdd/etape1-t4.log 2>&1; echo "code=$?"
outils/mesurer.sh > .superpowers/sdd/etape1-t4-mesures.log 2>&1; echo "mesures code=$?"; grep -c "mesure :" .superpowers/sdd/etape1-t4-mesures.log
grep -ln "Banc\|Instantane\|ConstructionMaillage\|MaillageAffiche" MaillageCoeurTests/MaisonInventee.swift MaillageCoeurTests/ScenePiecesTests.swift | wc -l
```
Expected: `code=0`, `mesures code=0`, `3`, puis `0`.

- [x] **Step 5: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
Coeur : graphe constructible a la main, fixtures de scene neutres et equivalences avec Thread

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Journal neutre : `TypeEvenement` ouvert et politique injectée

**Files:**
- Modify: `MaillageCoeur/Suivi/Evenement.swift`, `MaillageCoeur/Suivi/Alertes.swift`, `MaillageCoeur/Suivi/Regroupement.swift`, `MaillageCoeur/Journal/JournalFichiers.swift`, les appelants de l'app (`Surveillance.swift`, `TexteEvenement.swift`, `FenetreJournal.swift:21`, `Notifications.swift`) et les tests qui utilisent les cas Thread
- Create: `MaillageCoeur/Suivi/PolitiqueJournal.swift`, `MaillageCoeur/Suivi/EvenementsThread.swift` (partira dans `ProtocoleThread` à la tâche 7), `MaillageCoeurTests/TypeEvenementTests.swift`, `MaillageCoeurTests/EvenementsThreadTests.swift` (partira dans `ProtocoleThreadTests`)

**Interfaces:**
- Produces:
  - `public struct TypeEvenement: RawRepresentable, Hashable, Codable, Sendable` : `rawValue: String`, `gravite: Gravite` (gravité par défaut, hors égalité et hors encodage), `init(_ rawValue: String, gravite: Gravite = .info)`, `init(rawValue:)` ; constantes du cœur `.surveillanceDemarree`, `.veille` ;
  - `public protocol PolitiqueJournal: Sendable` : `var types: [TypeEvenement]`, plus un membre par décision d'`Alertes` et de `Regroupement` qui nomme aujourd'hui un type Thread ;
  - `public struct PolitiqueJournalNeutre: PolitiqueJournal` ;
  - dans `EvenementsThread.swift` : les 18 constantes Thread (`extension TypeEvenement`), avec les gravités d'aujourd'hui, `TypeEvenement.thread: [TypeEvenement]`, et `public struct PolitiqueJournalThread: PolitiqueJournal` ;
  - `CodingUserInfoKey.typesEvenement` : le décodeur du journal retrouve un type connu, gravité comprise, par son nom.

- [x] **Step 1: Tests de compatibilité (RED)**

`MaillageCoeurTests/TypeEvenementTests.swift` :
```swift
import Foundation
import Testing
@testable import MaillageCoeur

@Suite("TypeEvenement ouvert : le journal reste lisible a l'identique")
struct TypeEvenementTests {
    static let typeEssai = TypeEvenement("essaiAttention", gravite: .attention)

    static func decodeur(_ types: [TypeEvenement]) -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.userInfo[.typesEvenement] = Dictionary(uniqueKeysWithValues: types.map { ($0.rawValue, $0) })
        return d
    }

    @Test func encodeCommeUneChaine() throws {
        let data = try JSONEncoder().encode(TypeEvenement.veille)
        #expect(String(decoding: data, as: UTF8.self) == "\"veille\"")
    }

    @Test func egaliteParLeNomSeul() {
        #expect(TypeEvenement("x", gravite: .alerte) == TypeEvenement(rawValue: "x"))
    }

    @Test func ligneSansGraviteRetrouveLaGraviteDuTypeConnu() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"essaiAttention"}"#
        let e = try Self.decodeur([Self.typeEssai]).decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.type == Self.typeEssai)
        #expect(e.gravite == .attention)
    }

    @Test func typeInconnuConserve() throws {
        let ligne = #"{"date":"2026-09-27T03:55:00Z","type":"parentPerduZigbee","gravite":"alerte"}"#
        let e = try Self.decodeur([]).decode(Evenement.self, from: Data(ligne.utf8))
        #expect(e.type.rawValue == "parentPerduZigbee")
        #expect(e.gravite == .alerte)
    }
}
```
Adapter la stratégie de date du décodeur à celle de `CodageJSON` si elle diffère (lire `MaillageCoeur/Annonces/CodageJSON.swift`).

`MaillageCoeurTests/EvenementsThreadTests.swift` : un test paramétré sur les 20 noms d'aujourd'hui, qui vérifie pour chacun que la constante a le même `rawValue` et la même gravité que la table de `Evenement.swift` l. 20-30 à `15a499a` (alerte : `reseauScinde`, `routeurDisparu` ; attention : `chefChange`, `jeuActifChange`, `routeurNouvelleAdresseLien`, `prefixeRetire`, `appareilDisparu`, `appareilSansAdresse`, `appareilChangePartition`, `sansParent`, `routeurThreadDisparu` ; info : les autres) ; et qu'une ligne de journal écrite par Thread 1.3.0 (un `Evenement` encodé par le code de `15a499a`, recopié en littéral dans le test) se relit en un événement égal.

Run: `outils/tester.sh MaillageCoeurTests/TypeEvenementTests MaillageCoeurTests/EvenementsThreadTests > .superpowers/sdd/etape1-t5-red.log 2>&1; echo "code=$?"`
Expected: échec de compilation (`TypeEvenement("…", gravite:)`, `.typesEvenement` absents).

- [x] **Step 2: Implémenter le type ouvert**

Dans `Evenement.swift`, remplacer l'`enum TypeEvenement` par :
```swift
/// Nature d'un evenement du journal : un nom stable (celui qu'ecrit le journal) et une gravite par defaut. Le coeur
/// ne declare que les types neutres ; chaque protocole declare les siens en extension (EvenementsThread.swift).
/// Deux types sont egaux si leurs noms le sont ; un type inconnu se relit et se garde tel quel.
public struct TypeEvenement: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    /// Gravite par defaut a la creation d'un evenement ; jamais ecrite dans le journal.
    public let gravite: Gravite

    public init(_ rawValue: String, gravite: Gravite = .info) {
        self.rawValue = rawValue
        self.gravite = gravite
    }

    /// Type relu sans le connaitre : gravite par defaut `info`.
    public init(rawValue: String) { self.init(rawValue) }

    public static func == (a: TypeEvenement, b: TypeEvenement) -> Bool { a.rawValue == b.rawValue }
    public func hash(into h: inout Hasher) { h.combine(rawValue) }

    /// Relu du journal : le type connu du decodeur (`CodingUserInfoKey.typesEvenement`), gravite comprise ; sinon
    /// un type inconnu, garde tel quel.
    public init(from decoder: Decoder) throws {
        let nom = try decoder.singleValueContainer().decode(String.self)
        let connus = decoder.userInfo[.typesEvenement] as? [String: TypeEvenement]
        self = connus?[nom] ?? TypeEvenement(rawValue: nom)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public static let surveillanceDemarree = TypeEvenement("surveillanceDemarree")
    public static let veille = TypeEvenement("veille")
}

public extension CodingUserInfoKey {
    /// Types d'evenements connus, par nom (`[String: TypeEvenement]`), pour relire le journal.
    static let typesEvenement = CodingUserInfoKey(rawValue: "typesEvenement")!
}
```
`Evenement.init(from:)` garde sa lecture tolérante : une `gravite` absente prend `type.gravite`, qui est désormais celle du type connu.

- [x] **Step 3: Déclarer les types Thread et la politique**

- `MaillageCoeur/Suivi/EvenementsThread.swift` : `public extension TypeEvenement` avec les 18 constantes (`static let reseauScinde = TypeEvenement("reseauScinde", gravite: .alerte)`, etc., mêmes noms et gravités qu'aujourd'hui) et `static let thread: [TypeEvenement]` (les 18 dans l'ordre de l'enum actuel) ; `public struct PolitiqueJournalThread: PolitiqueJournal` dont `types` vaut `[.surveillanceDemarree, .veille] + TypeEvenement.thread`.
- `MaillageCoeur/Suivi/PolitiqueJournal.swift` : le protocole et `PolitiqueJournalNeutre` (`types` = les deux types neutres ; aucune perte, aucune catégorie, aucun parent). Les membres du protocole sont tirés de la lecture d'`Alertes.swift` (l. 8, 68, 74, 78-79) et de `Regroupement.swift` (l. 52-53, 89) : un membre par décision qui nomme aujourd'hui un type Thread ou une clé de `details` propre à Thread (`coupee`, `extMac`).
- `Alertes` et `Regroupement` prennent la politique en paramètre (valeur par défaut : aucune) et n'en nomment plus aucun type Thread. `JournalFichiers` reçoit la politique et pose `userInfo[.typesEvenement]` sur son décodeur.
- App : `Surveillance` crée et passe `PolitiqueJournalThread()` ; `FenetreJournal.swift:21` remplace `TypeEvenement.allCases` par `[.surveillanceDemarree, .veille] + TypeEvenement.thread` ; les `switch` sur un type d'événement (`TexteEvenement.swift` et autres) gagnent un `default:` qui rend le texte générique actuel du cas le plus proche, ou le nom brut pour un type inconnu.

- [x] **Step 4: Vérifier**

Run:
```bash
outils/tester.sh > .superpowers/sdd/etape1-t5.log 2>&1; echo "code=$?"
for t in reseauScinde reseauReuni chefChange bbrPrimaireChange jeuActifChange routeurApparu routeurDisparu routeurRoleChange \
  routeurNouvelleAdresseLien prefixeNouveau prefixeRetire appareilNouveau appareilDisparu appareilRevenu appareilSansAdresse \
  appareilChangePartition parentChange sansParent routeurThreadApparu routeurThreadDisparu; do
  grep -rln "\.$t\b" MaillageCoeur --include=*.swift | grep -v EvenementsThread.swift; done | sort -u | wc -l
```
Expected: `code=0` ; le compte vaut `0` (aucun fichier du cœur, hors `EvenementsThread.swift`, ne nomme un type Thread).

- [x] **Step 5: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
Journal neutre : TypeEvenement ouvert, politique injectee, types Thread declares a part

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: Coupes des fichiers mixtes et visibilités

**Files:**
- Modify: `MaillageCoeur/Scene/GrapheReseau.swift` ; Create: `MaillageCoeur/Scene/GrapheReseau+Thread.swift`
- Modify: `MaillageCoeur/Maillage/CourbesNoeud.swift` ; Create: `MaillageCoeur/Maillage/CourbesNoeud+Thread.swift`
- Modify: `MaillageCoeur/Noms/ResolveurNoms.swift` → renommé `MaillageCoeur/Noms/SurnomsAssociations.swift` ; Create: `MaillageCoeur/Noms/ResolveurNomsThread.swift`
- Modify: `MaillageCoeur/Demo/NomsDemo.swift` ; Create: `MaillageCoeur/Demo/NomsDemoThread.swift`
- Modify: `MaillageCoeur/Systeme/FichiersGardes.swift` (public), `MaillageCoeur/Annonces/ChampsTXT.swift` (`Data(hexa:)` et `.hexa` publics)
- Split tests: `FichiersGardesTests`, `NomsTests`, `CourbesNoeudTests`, `AssociationsTests` → partie cœur (même nom) + partie Thread (`…ThreadTests.swift`)

**Interfaces:**
- Consumes: `GrapheReseau.init(noeuds:liens:)` (tâche 4).
- Produces: dans le cœur, plus aucun fichier hors `*+Thread.swift`, `*Thread.swift`, `EvenementsThread.swift` et les 30 fichiers Thread de l'inventaire ne référence un type Thread ; `public init(debut:fin:liens:parents:signal:parentsSonde:prioritaires:)` de `CourbesNoeud` ; `CourbesNoeud.reduire(_:pas:)` public ; `FichiersGardes` public (`lire`, `ecrire`, `mettreDeCote`, `examiner`, `Etat`).

- [x] **Step 1: Couper sans rien changer au comportement**

Suivre `inventaire-coeur.md` §3, ligne à ligne :
- `GrapheReseau+Thread.swift` : `public extension GrapheReseau` avec `init(reseau:appareils:maillage:)` (l. 111-160 actuelles, qui finit par `self.init(noeuds:liens:)`) et `static func extMac(hote:)` (l. 166-168) ;
- `CourbesNoeud+Thread.swift` : les deux `init(cle:releves:…)` (l. 107-175) en `public extension CourbesNoeud`, déléguant à l'init membre à membre public ;
- `ResolveurNomsThread.swift` : `struct ResolveurNoms` (l. 1-99) ; `SurnomsAssociations.swift` : `Surnoms` et `Associations` (l. 101-128) ;
- `NomsDemoThread.swift` : `public extension NomsDemo` avec `fabrique`, `table`, `batteries`, `routeurs`, `maison` (l. 11-94) ; `NomsDemo.swift` garde `zones`, `domicile`, `places(dehors:)`.
- Rendre publics `FichiersGardes` et ses membres, `CourbesNoeud.reduire`, `Data(hexa:)` et `.hexa`.

Ruling déjà pris : `ChampsTXT.swift` **reste au cœur** (spec 1.3 : identique dans les deux dépôts, analyse TXT de DNS-SD sans protocole radio).

- [x] **Step 2: Scinder les quatre tests mixtes**

D'après `inventaire-coeur.md` §4 : les assertions qui ne touchent que des types du cœur restent dans le fichier d'origine ; celles qui touchent `ResolveurNoms`, `Instantane`, `Releve20260928`, `NomsDemo.maison`, `CourbesNoeud(cle:releves:)`, `ClesHistorique`, `ReleveMaillage`, `IdentitesGardees` ou `Banc` partent dans `NomsThreadTests.swift`, `CourbesNoeudThreadTests.swift`, `AssociationsThreadTests.swift`, `FichiersGardesThreadTests.swift`. Aucun test n'est supprimé : le nombre total de `@Test` du dossier est le même avant et après.

```bash
grep -rc "@Test" MaillageCoeurTests | awk -F: '{s+=$2} END {print s}'
```
Expected: le même total qu'avant l'étape (le noter à l'étape 1).

- [x] **Step 3: Vérifier**

Run: `outils/tester.sh > .superpowers/sdd/etape1-t6.log 2>&1; echo "code=$?"`
Expected: `code=0`.

- [x] **Step 4: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
Coeur : coupes de GrapheReseau, CourbesNoeud, ResolveurNoms et NomsDemo ; visibilites publiques

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Création de `ProtocoleThread` et déplacement du code Thread

**Files:**
- Create: dossiers `ProtocoleThread/` et `ProtocoleThreadTests/` ; cibles `ProtocoleThread` (framework) et `ProtocoleThreadTests` dans `project.yml`
- Move (`git mv`) vers `ProtocoleThread/`, en gardant les sous-dossiers : les 30 fichiers « T » d'`inventaire-coeur.md` §1 **sauf `Annonces/ChampsTXT.swift`** (qui reste au cœur), `Demo/releve-2026-09-28.json`, et les fichiers de coupe `Scene/GrapheReseau+Thread.swift`, `Maillage/CourbesNoeud+Thread.swift`, `Noms/ResolveurNomsThread.swift`, `Demo/NomsDemoThread.swift`, `Suivi/EvenementsThread.swift`
- Move vers `ProtocoleThreadTests/` : les 22 fichiers de test « ProtocoleThreadTests » d'`inventaire-coeur.md` §4, `Banc.swift`, `FixturesThreadTests.swift`, `AidesThreadTests.swift`, `EvenementsThreadTests.swift` et les quatre `…ThreadTests.swift` de la tâche 6
- Modify: `project.yml` (cibles, dépendances de `MaillageIoT` et `MaillageIoTTests`, schémas `MaillageIoT` et `MaillageCoeur`), imports de l'app et des tests

**Interfaces:**
- Consumes: les coupes des tâches 4 à 6.
- Produces: module `ProtocoleThread` (`import ProtocoleThread`) ; `MaillageCoeur` sans aucune dépendance de protocole ; l'app dépend des deux frameworks.

- [x] **Step 1: Noter les effectifs**

```bash
for d in MaillageCoeurTests MaillageIoTTests PasseurTests; do printf '%s %s\n' "$d" "$(grep -rc '@Test' $d | awk -F: '{s+=$2} END {print s}')"; done
```
Noter les trois nombres dans le registre : la somme des `@Test` doit être la même après le déplacement (cœur + ProtocoleThread + app + démon).

- [x] **Step 2: Déplacer les fichiers**

Avec `git mv`, liste exacte ci-dessus (préserve l'historique). Vérifier : `ls ProtocoleThread/Demo/releve-2026-09-28.json` existe, et `MaillageCoeur/Noms/NomsMaison.swift`, `MaillageCoeur/Noms/ProtocolePasseur.swift`, `MaillageCoeur/Annonces/CodageJSON.swift` sont toujours en place.

- [x] **Step 3: Déclarer les cibles**

Dans `project.yml`, sur le modèle exact des cibles `MaillageCoeur` et `MaillageCoeurTests` :
```yaml
  ProtocoleThread:
    type: framework
    platform: macOS
    sources:
      - path: ProtocoleThread
    dependencies:
      - target: MaillageCoeur
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.maillage.iot.thread
        GENERATE_INFOPLIST_FILE: YES
        SKIP_INSTALL: YES
        DEFINES_MODULE: YES
      configs:
        Debug:
          SWIFT_OPTIMIZATION_LEVEL: -O
  ProtocoleThreadTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: ProtocoleThreadTests
    dependencies:
      - target: ProtocoleThread
      - target: MaillageCoeur
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.maillage.iot.thread.tests
        GENERATE_INFOPLIST_FILE: YES
```
Ajouter `- target: ProtocoleThread` aux dépendances de `MaillageIoT` et de `MaillageIoTTests` ; ajouter `ProtocoleThread` (build) et `ProtocoleThreadTests` (test) au schéma `MaillageIoT`. Le schéma `MaillageCoeur` ne change pas : il ne doit contenir que le cœur et ses tests.

- [x] **Step 4: Imports et visibilités**

- Fichiers de `ProtocoleThread/` : `import MaillageCoeur` en tête de chacun.
- Tests de `ProtocoleThreadTests/` : `@testable import ProtocoleThread` et `@testable import MaillageCoeur`.
- App et ses tests : ajouter `import ProtocoleThread` (ou `@testable import ProtocoleThread` dans les tests qui touchent un interne, par exemple `NomsSceneTests.swift:59` et `MaillageDemo.maillage(…sansIdentite:)`) partout où le compilateur le demande.
- Tout symbole interne du cœur que `ProtocoleThread` utilise devient `public` ; tout symbole interne de `ProtocoleThread` que l'app utilise devient `public`. Lister chaque symbole rendu public dans le registre (`Task 7: public : …`).

- [x] **Step 5: Lancer toute la suite**

Run: `outils/tester.sh > .superpowers/sdd/etape1-t7.log 2>&1; echo "code=$?"; tail -3 .superpowers/sdd/etape1-t7.log`
Expected: `code=0`, `ReferenceRejeuTests` compris.

- [x] **Step 6: Le cœur seul**

Run:
```bash
grep -rln "ProtocoleThread\|import ProtocoleThread" MaillageCoeur MaillageCoeurTests | wc -l
outils/mesurer.sh > .superpowers/sdd/etape1-t7-mesures.log 2>&1; echo "mesures code=$?"; grep -c "mesure :" .superpowers/sdd/etape1-t7-mesures.log
xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageCoeur -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/maillage-iot test > .superpowers/sdd/etape1-t7-coeur.log 2>&1; echo "coeur seul code=$?"
```
Expected: `0`, `mesures code=0`, `3`, `coeur seul code=0`.

- [x] **Step 7: Conservation des tests**

```bash
for d in MaillageCoeurTests ProtocoleThreadTests MaillageIoTTests PasseurTests; do printf '%s %s\n' "$d" "$(grep -rc '@Test' $d | awk -F: '{s+=$2} END {print s}')"; done
```
Expected: la somme est égale à celle de l'étape 1 de cette tâche.

- [x] **Step 8: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
ProtocoleThread : framework Thread extrait du coeur, qui compile et se teste seul

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Ranger le code de l'app propre à Thread sous `MaillageIoT/Thread/`

**Files:**
- Move (`git mv`) : `MaillageIoT/Recenseur/` → `MaillageIoT/Thread/Recenseur/` ; `MaillageIoT/Sonde/` → `MaillageIoT/Thread/Sonde/` ; `MaillageIoT/Surveillance/ThreadRoute.swift`, `MaillageIoT/Surveillance/TexteEvenement.swift` → `MaillageIoT/Thread/` ; `MaillageIoT/Vues/MarqueThread.swift` → `MaillageIoT/Thread/`
- Modify: commentaires et documents qui citent ces chemins (`grep -rn "Recenseur/\|Sonde/" --include=*.swift --include=*.sh --include=*.md`)

**Interfaces:**
- Produces: même cible, même module ; seul le rangement change. Les vues de la scène liées au modèle Thread (`FicheNoeud`, `LegendePieces`, `SigneLegende`, `DessinNoeud`, `LibellesNoeuds`, `PiecesChoisies`) restent où elles sont : elles seront séparées à l'étape 3, avec la scène à deux protocoles.

- [ ] **Step 1: Déplacer**

Les `git mv` de la liste ci-dessus, puis `xcodegen generate --quiet`.

- [ ] **Step 2: Vérifier**

Run: `outils/tester.sh > .superpowers/sdd/etape1-t8.log 2>&1; echo "code=$?"`
Expected: `code=0` ; `CataloguesTests` passe (même cible, mêmes `.stringsdata`).

- [ ] **Step 3: Commit**

```bash
git add -A && bash outils/controler-index.sh && git commit -q -F - <<'EOF'
App : code propre a Thread range sous MaillageIoT/Thread

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 9: Banc avec Djoko

Fait par l'orchestrateur avec Djoko, après la relecture finale et ses correctifs.

- [ ] **Step 1: Compiler et lancer Maillage IoT**

```bash
xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/maillage-iot build > .superpowers/sdd/etape1-banc.log 2>&1; echo "code=$?"
open ~/Library/Developer/Xcode/DerivedData/maillage-iot/Build/Products/Debug/"Maillage IoT.app"
```

- [ ] **Step 2: Comparer côte à côte**

Avec Djoko, Maillage Thread 1.3.0 et Maillage IoT ouverts ensemble :
- même vue par pièces (nœuds, liens, pièces, étages), en 2D et en 3D ;
- noms de Maison reçus par les deux apps, abonnées au même démon ;
- sonde **en USB seulement**, branchée sur l'une puis sur l'autre (pas de mise en service réseau : elle remplacerait la clé de la sonde et couperait Maillage Thread de sa sonde réseau, spec 4.4) ;
- journal et notifications de Maillage IoT : écrits dans `Application Support/Maillage IoT/`.

- [ ] **Step 3: Verdict**

Noter le verdict de Djoko dans le registre ; cocher ce plan ; l'orchestrateur pousse `main` (garde pre-push).
