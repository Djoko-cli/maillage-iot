# Maillage IoT, étape 0 : préparation et squelette du dépôt — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser le dépôt `maillage-iot`, anonyme dès son premier commit (spec et plan compris), avec une garde pre-push éprouvée, et commiter dans `maillage-thread` le résultat de référence que l'étape 1 rejouera.

**Architecture:** Le dossier local `~/Dev/maillage-merge` devient la copie de travail du dépôt `maillage-iot`. La garde reprend la garde de Zigbee (`garde.py` et sa liste `garde.local.txt`, qui contient aussi le prénom réel) et lance les **deux** contrôles d'anonymisation privés existants, celui de Thread et celui de Zigbee, plutôt que de fusionner leurs tables. Le résultat de référence est un test de `maillage-thread` qui écrit, en JSON trié, la scène que construit `EntreeScene` en mode démo.

**Tech Stack:** git, bash (le `/bin/bash` 3.2 de macOS pour le hook), Python 3, XcodeGen 2.46, Swift Testing, `xcodebuild` (via `outils/tester.sh` de Thread).

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` (sections 5.1 et 6.1, étape 0).

## Global Constraints

- Identité git de `maillage-iot` : `user.name` = `Djoko-cli`, `user.email` = `12185352+Djoko-cli@users.noreply.github.com`, réglée **avant** le premier commit.
- **Ne jamais afficher** le contenu de `garde.local.txt`, d'une `table.json` ni d'aucune vraie valeur : seulement des comptes. Pas de `cat`, `head`, `tail` ni `grep` sans `-c` ou `-q` sur ces fichiers.
- Fichiers privés créés avec `umask 077`, uniquement sous `.superpowers/` ou dans `garde.local.txt` (tous deux ignorés par git).
- Aucun prénom réel, aucun chemin `/Users/<nom>` dans un fichier commité ni dans un message de commit ; l'utilisateur s'appelle **Djoko**. Les chemins s'écrivent `~/Dev/…`.
- Commentaires du code et des scripts sans accents ; documents Markdown en français avec accents ; README en anglais d'abord, puis en français.
- Chaque message de commit se termine par la ligne `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Jamais `--no-verify`, jamais de push forcé. Aucun push vers GitHub avant la tâche 6 et l'accord de Djoko.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Le premier commit (racine) échappe aux contrôles** : `git diff-tree` ne liste rien pour un commit racine sans `--root`. On attend que le hook contrôle les fichiers du premier commit. → `--root` dans le hook (tâche 3), vérifié en tâche 5, étape 2.
2. **`garde.local.txt` absent** (nouvelle machine, fichier déplacé) : `garde.py` dit « rien a verifier » et passe. On attend un refus. → test en tâche 5, étape 7.
3. **Une vraie valeur dans un message de commit seulement** : on attend un refus. → tâche 5, étape 6.
4. **Une vraie valeur écrite dans une autre casse, avec d'autres séparateurs** (minuscules et deux-points) : on attend un refus. → tâche 5, étape 3.
5. **Les références du dépôt d'essai masquent des commits aux contrôles suivants** : le hook prend les commits « absents de tout remote » (`--not --remotes`). Si le remote d'essai reste, un premier push vers GitHub sauterait les commits déjà poussés à l'essai. On attend qu'il ne reste aucun remote d'essai. → tâche 5, étape 8.

---

### Task 1: Résultat de référence du rejeu dans `maillage-thread` (session Thread)

À faire par la session Thread, dans `~/Dev/maillage-thread`, en parallèle des tâches 2 à 5.

**Files:**
- Create: `MaillageThreadTests/ReferenceRejeuTests.swift`
- Create (écrit par le test) : `docs/rejeu/thread-demo.json`

**Interfaces:**
- Consumes: `Surveillance(mode: .demo, dossier: nil)`, `demarrer()`, `reseau`, `EntreeScene(surveillance:reseau:places:)`, `PlacesGardees()`, `GrapheReseau.noeuds` et `.liens`, `ScenePieces.noeuds`, `.pieces` et `.etages`.
- Produces: `docs/rejeu/thread-demo.json`, JSON trié (`noeuds`, `liens`, `scene`, `pieces`, `etages`), que l'étape 1 de Maillage IoT compare au sien, préfixes `thread:` retirés.

- [ ] **Step 1: Vérifier la signification des indices**

Lire dans `MaillageCoeur/Scene/ScenePieces.swift` la doc de `Noeud.piece` et de `Piece.etage` : ce doivent être des indices dans `pieces` et dans `etages`. Lire aussi les dates de `ScenarioPanne` et de `MaillageDemo` : elles doivent être relatives à `maintenant`, pas des dates fixes. Si l'un des deux points est faux, s'arrêter et le signaler à la session de fusion avant d'écrire le test.

- [ ] **Step 2: Écrire le test**

```swift
import Foundation
import MaillageCoeur
import Testing
@testable import MaillageThread

/// Resultat de reference du rejeu (spec de Maillage IoT, section 6.1, etape 0) : la scene de la vue par pieces en
/// mode demo, telle que `EntreeScene` la construit, ecrite en JSON trie dans `docs/rejeu/thread-demo.json`. Maillage
/// IoT rejoue la meme demo et compare, prefixes `thread:` retires. Fichier absent : le test l'ecrit et echoue une
/// fois ; le controler (controle d'anonymisation), puis relancer.
@MainActor
@Suite("Reference du rejeu : la scene de la demo")
struct ReferenceRejeuTests {
    static let fichier = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageThreadTests
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/rejeu/thread-demo.json")

    struct Reference: Codable, Equatable {
        struct Noeud: Codable, Equatable {
            var id, genre, partition: String
            var routeur, bordure, inconnu: Bool
            var extMac: String?
        }
        struct Lien: Codable, Equatable {
            var de, vers, genre: String
            var qualite: Int?
        }
        struct NoeudScene: Codable, Equatable {
            var id, libelle, piece: String
            var chef, pile: Bool
            var rang: Int
            var rayon: Double
        }
        struct Piece: Codable, Equatable {
            var cle, etage: String
            var noeuds: [String]
        }
        struct Etage: Codable, Equatable {
            var cle: String
            var niveau: Int
            var principal, dehors: Bool
        }
        var noeuds: [Noeud]
        var liens: [Lien]
        var scene: [NoeudScene]
        var pieces: [Piece]
        var etages: [Etage]
    }

    static func reference() throws -> Reference {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let r = try #require(s.reseau)
        let e = EntreeScene(surveillance: s, reseau: r, places: PlacesGardees())
        let sc = e.scene
        let pieces = sc.pieces.map(\.nom.cle)
        let etages = sc.etages.map(\.nom.cle)
        return Reference(
            noeuds: e.graphe.noeuds.map {
                .init(id: $0.id, genre: $0.genre.rawValue, partition: $0.partition, routeur: $0.routeur,
                      bordure: $0.bordure, inconnu: $0.inconnu, extMac: $0.extMac)
            }.sorted { $0.id < $1.id },
            liens: e.graphe.liens.map {
                .init(de: $0.de, vers: $0.vers, genre: $0.genre.rawValue, qualite: $0.qualite)
            }.sorted { ($0.de, $0.vers, $0.genre) < ($1.de, $1.vers, $1.genre) },
            scene: sc.noeuds.map {
                .init(id: $0.id, libelle: $0.libelle,
                      piece: pieces.indices.contains($0.piece) ? pieces[$0.piece] : "",
                      chef: $0.chef, pile: $0.pile, rang: $0.rang, rayon: ($0.rayon * 10_000).rounded() / 10_000)
            }.sorted { $0.id < $1.id },
            pieces: sc.pieces.map {
                .init(cle: $0.nom.cle, etage: etages.indices.contains($0.etage) ? etages[$0.etage] : "",
                      noeuds: $0.noeuds.sorted())
            }.sorted { $0.cle < $1.cle },
            etages: sc.etages.map {
                .init(cle: $0.nom.cle, niveau: $0.niveau, principal: $0.principal, dehors: $0.dehors)
            }.sorted { $0.cle < $1.cle })
    }

    static func json(_ r: Reference) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(r) + Data("\n".utf8)
    }

    /// Deux constructions de suite donnent le meme JSON : la reference ne depend ni de l'heure ni d'un ordre de hasard.
    @Test func stable() throws {
        #expect(try Self.json(Self.reference()) == Self.json(Self.reference()))
    }

    @Test func egaleALaReference() throws {
        let calcule = try Self.json(Self.reference())
        guard let garde = try? Data(contentsOf: Self.fichier) else {
            try FileManager.default.createDirectory(at: Self.fichier.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try calcule.write(to: Self.fichier)
            Issue.record("reference absente : ecrite dans docs/rejeu/thread-demo.json ; la controler, puis relancer")
            return
        }
        #expect(calcule == garde, "la scene de la demo a change : comparer avec docs/rejeu/thread-demo.json")
    }
}
```

- [ ] **Step 3: Premier lancement : le test écrit la référence et échoue**

Run: `outils/tester.sh MaillageThreadTests/ReferenceRejeuTests`
Expected: `stable()` passe ; `egaleALaReference()` échoue avec « reference absente : ecrite dans docs/rejeu/thread-demo.json » ; le fichier existe.

- [ ] **Step 4: Contrôler la référence avant tout commit**

Run: `python3 .superpowers/anonymisation/outils/controles.py fichiers --table .superpowers/anonymisation/execution/table.json docs/rejeu/thread-demo.json MaillageThreadTests/ReferenceRejeuTests.swift; echo "code=$?"`
Expected: `code=0`, aucun fichier en défaut. Sinon, ne pas commiter et signaler les comptes à la session de fusion.

- [ ] **Step 5: Deuxième lancement : le test passe**

Run: `outils/tester.sh MaillageThreadTests/ReferenceRejeuTests`
Expected: les deux tests passent.

- [ ] **Step 6: Commit et push**

```bash
git add MaillageThreadTests/ReferenceRejeuTests.swift docs/rejeu/thread-demo.json
git commit -F - <<'EOF'
Rejeu : reference de la scene de la demo, pour l'etape 1 de Maillage IoT

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git push origin main
```
Expected: le pre-push accepte (auteur noreply). Répondre à la session de fusion en une ligne, avec l'empreinte du commit.

---

### Task 2: Dépôt local `maillage-iot` : identité, `.gitignore`, documents privés rangés

**Files:**
- Create: `~/Dev/maillage-merge/.gitignore`
- Move: `etat-thread.md`, `etat-zigbee.md`, `relecture-thread.md`, `relecture-zigbee.md` → `.superpowers/fusion/`

**Interfaces:**
- Produces: un dépôt git `main` sans commit, identité noreply, avec un `.gitignore` qui couvre `.superpowers/`, `garde.local.txt` et `*.local.*` (utilisés par les tâches 3 à 5).

- [x] **Step 1: Ranger les documents privés**

```bash
cd ~/Dev/maillage-merge
mkdir -p .superpowers/fusion
mv etat-thread.md etat-zigbee.md relecture-thread.md relecture-zigbee.md .superpowers/fusion/
ls .superpowers/fusion
```
Expected: les quatre fichiers listés ; plus aucun `.md` à la racine.

- [x] **Step 2: Créer le dépôt et régler l'identité**

```bash
git init -b main
git config user.name Djoko-cli
git config user.email 12185352+Djoko-cli@users.noreply.github.com
git config user.name; git config user.email
```
Expected: `Djoko-cli` puis `12185352+Djoko-cli@users.noreply.github.com`.

- [x] **Step 3: Écrire `.gitignore`**

```gitignore
# Projet genere par xcodegen (project.yml fait foi)
*.xcodeproj/
*.xcworkspace/
# Produits de compilation
build/
DerivedData/
.build/
*.xcresult
*.dmg
# Fichiers propres a l'utilisateur
xcuserdata/
*.xcuserstate
.swiftpm/
.DS_Store
__pycache__/
# Espace de travail prive : etats des lieux, anonymisation, essais, suivi d'execution, maquettes
.superpowers/
# Signature propre au poste, jamais commitee
Local.xcconfig
# Garde : les vrais identifiants des reseaux de Djoko et son prenom reel, jamais dans le depot
garde.local.txt
# Sondes : secrets et reglages locaux (cle_hue.local.h, sonde.local.json...)
*.local.*
.pio/
# Essais de banc, releves et captures reels
essais/
# Noms de Maison ecrits par le demon : jamais dans le depot
noms.json
passeur-demande.json
releve-maison.json
```

- [x] **Step 4: Vérifier ce que git verrait**

Run: `git status --short --untracked-files=all`
Expected: seulement `.gitignore`, `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` et `docs/superpowers/plans/2026-10-14-maillage-iot-etape-0.md`. Rien sous `.superpowers/`.

---

### Task 3: La garde : `garde.py`, sa liste, les deux contrôles privés et le hook pre-push

**Files:**
- Create: `outils/garde.py` (copie de `~/Dev/maillage-zigbee/outils/garde.py`, docstring adaptée)
- Create: `outils/tests/test_garde.py` (copie de `~/Dev/maillage-zigbee/outils/test/test_garde.py`)
- Create: `outils/pre-push` (version de référence du hook)
- Create (privé) : `garde.local.txt`, `.superpowers/anonymisation/thread/outils/…`, `.superpowers/anonymisation/thread/table.json`, `.superpowers/anonymisation/zigbee/controles.py`, `.superpowers/anonymisation/zigbee/table.json`
- Install: `.git/hooks/pre-push`

**Interfaces:**
- Consumes: le dépôt de la tâche 2.
- Produces: `python3 outils/garde.py` (code 0 ou 1) ; le hook, qui refuse un push en cas d'auteur hors noreply, de `garde.local.txt` absent, d'identifiant trouvé par la garde ou par l'un des deux contrôles privés.

- [x] **Step 1: Copier la garde et ses tests**

```bash
cd ~/Dev/maillage-merge
mkdir -p outils/tests
cp ~/Dev/maillage-zigbee/outils/garde.py outils/garde.py
cp ~/Dev/maillage-zigbee/outils/test/test_garde.py outils/tests/test_garde.py
```
Puis, dans la docstring de `outils/garde.py`, remplacer la première ligne par `"""Garde des vrais identifiants (spec de Maillage IoT, section 5.1).` et « les vrais identifiants du reseau de Djoko, un » par « les vrais identifiants des reseaux de Djoko et son prenom reel, un ». Ne rien changer d'autre.

- [x] **Step 2: Lancer les tests de la garde**

Run: `python3 -m unittest discover -s outils/tests -q`
Expected: `OK`.

- [x] **Step 3: Composer la liste privée, sans l'afficher**

```bash
umask 077
cp ~/Dev/maillage-zigbee/garde.local.txt garde.local.txt
chmod 600 garde.local.txt
echo "lignes utiles : $(grep -cv -e '^#' -e '^[[:space:]]*$' garde.local.txt)"
echo "prenom present : $(grep -c '^# Prenom reel' garde.local.txt)"
```
Expected: environ 70 lignes utiles ; `prenom present : 1`.

- [x] **Step 4: Copier les deux contrôles privés**

```bash
umask 077
mkdir -p .superpowers/anonymisation/thread .superpowers/anonymisation/zigbee
cp -R ~/Dev/maillage-thread/.superpowers/anonymisation/outils .superpowers/anonymisation/thread/outils
cp ~/Dev/maillage-thread/.superpowers/anonymisation/execution/table.json .superpowers/anonymisation/thread/table.json
cp ~/Dev/maillage-zigbee/.superpowers/anonymisation/outils/controles.py .superpowers/anonymisation/zigbee/controles.py
python3 -I - "$PWD" <<'EOF'
import json, os, sys
racine = sys.argv[1]
source = os.path.expanduser("~/Dev/maillage-zigbee/.superpowers/anonymisation/execution/table.json")
with open(source, encoding="utf-8") as f:
    t = json.load(f)
t["identifiants"] = [os.path.join(racine, "garde.local.txt")]
with open(os.path.join(racine, ".superpowers/anonymisation/zigbee/table.json"), "w", encoding="utf-8") as f:
    json.dump(t, f, ensure_ascii=False, indent=1)
print("table zigbee :", len(t["identifiants"]), "fichier d'identifiants,",
      len(t.get("supplementaires", [])), "valeur(s) supplementaire(s)")
EOF
```
Expected: `table zigbee : 1 fichier d'identifiants, 1 valeur(s) supplementaire(s)`.

- [x] **Step 5: Les deux contrôles passent sur les fichiers propres**

```bash
A=.superpowers/anonymisation
F="docs/superpowers/specs/2026-10-13-maillage-iot-design.md docs/superpowers/plans/2026-10-14-maillage-iot-etape-0.md .gitignore outils/garde.py outils/tests/test_garde.py"
python3 $A/thread/outils/controles.py fichiers --table $A/thread/table.json $F > $A/sortie-thread.txt 2>&1; echo "thread code=$?"; tail -1 $A/sortie-thread.txt
python3 $A/zigbee/controles.py fichiers --table $A/zigbee/table.json $F > $A/sortie-zigbee.txt 2>&1; echo "zigbee code=$?"; tail -1 $A/sortie-zigbee.txt
```
Expected: `thread code=0` et `zigbee code=0`, avec des bilans sans fichier en défaut. Si un contrôle signale un fichier propre (faux positif), **s'arrêter** et rapporter les comptes à Djoko : ne pas modifier les contrôles.

- [x] **Step 6: Écrire le hook de référence `outils/pre-push`**

```bash
#!/bin/bash
# Barriere avant tout push de Maillage IoT (depot public ; spec, section 5.1). Installation :
#   cp outils/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
#  1. auteur ET committer de chaque commit pousse = l'adresse noreply ;
#  2. garde.local.txt present et non vide, puis garde des vrais identifiants sur les fichiers suivis (outils/garde.py) ;
#  3. les deux controles d'anonymisation prives (celui de Maillage Thread, celui de Maillage Zigbee) sur les
#     fichiers changes, commit racine compris (--root), et sur les messages des commits pousses.
# Chaque controle est lance seul et son code de sortie teste : jamais de tube. Jamais de --no-verify.
set -u
attendu="12185352+Djoko-cli@users.noreply.github.com"
zero=0000000000000000000000000000000000000000
racine=$(git rev-parse --show-toplevel)
anon="$racine/.superpowers/anonymisation"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fautifs=0
: > "$tmp/fichiers"
n=0
while read -r ref_locale sha_local ref_distante sha_distant; do
  [ "$sha_local" = "$zero" ] && continue   # suppression d'une branche
  if [ "$sha_distant" = "$zero" ]; then plage=$(git rev-list "$sha_local" --not --remotes)
  else plage=$(git rev-list "$sha_distant..$sha_local"); fi
  for c in $plage; do
    ae=$(git log -1 --format=%ae "$c"); ce=$(git log -1 --format=%ce "$c")
    if [ "$ae" != "$attendu" ] || [ "$ce" != "$attendu" ]; then
      echo "pre-push : commit $(git log -1 --format=%h "$c") avec auteur ou committer hors noreply" >&2
      fautifs=$((fautifs + 1))
    fi
    n=$((n + 1))
    git log -1 --format=%B "$c" > "$tmp/message-$n.txt"
    git diff-tree --root --no-commit-id --name-only -r --diff-filter=d "$c" >> "$tmp/fichiers"
  done
done
if [ ! -s "$racine/garde.local.txt" ]; then
  echo "pre-push : garde.local.txt absent ou vide : push refuse" >&2
  fautifs=$((fautifs + 1))
elif ! python3 "$racine/outils/garde.py"; then
  echo "pre-push : la garde a trouve un identifiant reel" >&2
  fautifs=$((fautifs + 1))
fi
liste=()
while IFS= read -r f; do [ -f "$racine/$f" ] && liste+=("$racine/$f"); done < <(sort -u "$tmp/fichiers")
for m in "$tmp"/message-*.txt; do [ -f "$m" ] && liste+=("$m"); done
controler() {  # $1 : nom du controle, $2 : script, $3 : table
  if [ ! -f "$2" ] || [ ! -f "$3" ]; then
    echo "pre-push : controle d'anonymisation $1 introuvable : push refuse" >&2
    return 1
  fi
  [ ${#liste[@]} -eq 0 ] && return 0
  python3 "$2" fichiers --table "$3" "${liste[@]}" > "$tmp/sortie-$1" 2>&1
  code=$?
  tail -1 "$tmp/sortie-$1" >&2
  if [ $code -ne 0 ]; then
    echo "pre-push : le controle $1 a trouve un identifiant" >&2
    return 1
  fi
}
controler thread "$anon/thread/outils/controles.py" "$anon/thread/table.json" || fautifs=$((fautifs + 1))
controler zigbee "$anon/zigbee/controles.py" "$anon/zigbee/table.json" || fautifs=$((fautifs + 1))
[ "$fautifs" -eq 0 ] || { echo "pre-push : push refuse ($fautifs probleme(s))." >&2; exit 1; }
```

- [x] **Step 7: Installer le hook et vérifier sa syntaxe**

```bash
cp outils/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push outils/pre-push
/bin/bash -n .git/hooks/pre-push && echo "syntaxe ok"
cmp outils/pre-push .git/hooks/pre-push && echo "hook installe identique"
```
Expected: `syntaxe ok` puis `hook installe identique`.

---

### Task 4: README bilingues, `project.yml` minimal, premier commit

**Files:**
- Create: `README.md`, `README.fr.md`, `project.yml`
- Commit: tout ce qui précède, spec et plan compris.

**Interfaces:**
- Consumes: la garde de la tâche 3.
- Produces: le commit racine de `main`, sur lequel la tâche 5 essaie la garde.

- [x] **Step 1: Écrire `README.md`**

```markdown
**English** · [Français](README.fr.md)

# Maillage IoT

Maillage IoT shows the radio meshes of a home on its rooms, in 2D and 3D: Thread and Zigbee together, from the
Mac menu bar.

> **Status: under construction.** Maillage IoT merges two apps into one:
> [Maillage Thread](https://github.com/Djoko-cli/maillage-thread) and
> [Maillage Zigbee](https://github.com/Djoko-cli/maillage-zigbee). Until its first version is published, use
> them; each will point here once Maillage IoT 1.0 is out.

## What it will do

- Thread and Zigbee nodes on the same room view: round for Thread, hexagonal for Zigbee, link colors for the
  quality, and two switches to show or hide each network.
- Both probes at once (an ESP32-C6 for Thread, another for Zigbee), over USB or the network.
- Names, rooms and floors from the Home app, through the Passeur Noms helper.
- One log, one set of notifications, automatic updates.
- Settings, names and history carried over from Maillage Thread and Maillage Zigbee, from an export made by
  their last version.

## Design

The design is in [docs/superpowers/specs/2026-10-13-maillage-iot-design.md](docs/superpowers/specs/2026-10-13-maillage-iot-design.md)
(in French), and the work is planned step by step in [docs/superpowers/plans](docs/superpowers/plans).
```

- [x] **Step 2: Écrire `README.fr.md`**

```markdown
[English](README.md) · **Français**

# Maillage IoT

Maillage IoT montre les maillages radio d'une maison sur ses pièces, en 2D et en 3D : Thread et Zigbee
ensemble, depuis la barre des menus du Mac.

> **État : en construction.** Maillage IoT réunit deux apps en une :
> [Maillage Thread](https://github.com/Djoko-cli/maillage-thread) et
> [Maillage Zigbee](https://github.com/Djoko-cli/maillage-zigbee). Jusqu'à la publication de sa première
> version, utilisez-les ; chacune renverra ici à la sortie de Maillage IoT 1.0.

## Ce qu'elle fera

- Les nœuds Thread et Zigbee sur la même vue par pièces : ronds pour Thread, hexagonaux pour Zigbee, la
  couleur des liens pour la qualité, et deux interrupteurs pour montrer ou masquer chaque réseau.
- Les deux sondes en même temps (un ESP32-C6 pour Thread, un autre pour Zigbee), par USB ou par le réseau.
- Les noms, les pièces et les étages de l'app Maison, par l'assistant Passeur Noms.
- Un seul journal, une seule série de notifications, des mises à jour automatiques.
- Les réglages, les noms et l'historique repris de Maillage Thread et de Maillage Zigbee, depuis un export fait
  par leur dernière version.

## Conception

La conception est dans [docs/superpowers/specs/2026-10-13-maillage-iot-design.md](docs/superpowers/specs/2026-10-13-maillage-iot-design.md),
et le travail est planifié étape par étape dans [docs/superpowers/plans](docs/superpowers/plans).
```

- [x] **Step 3: Écrire `project.yml`**

```yaml
# Maillage IoT, projet XcodeGen : ce fichier fait foi (le .xcodeproj est genere, jamais commite).
# Etape 0 : le projet est vide ; les cibles arrivent a l'etape 1 (spec, section 1.1).
name: MaillageIoT
options:
  bundleIdPrefix: fr.djoko.maillage.iot
  deploymentTarget:
    macOS: "26.0"
```

- [x] **Step 4: Vérifier que XcodeGen l'accepte**

Run: `xcodegen generate --quiet && ls -d MaillageIoT.xcodeproj && git status --short | grep -c xcodeproj`
Expected: `MaillageIoT.xcodeproj` existe, et le dernier compte vaut `0` (ignoré). Si XcodeGen refuse un projet sans cible, ajouter la ligne `targets: {}` à la fin de `project.yml` et relancer.

- [x] **Step 5: Cocher les cases faites de ce plan**

Cocher dans ce fichier les étapes des tâches 2, 3 et 4 déjà faites et vérifiées (la tâche 1 est cochée quand la session Thread a répondu).

- [ ] **Step 6: Contrôler ce qui va être commité**

```bash
git add .gitignore README.md README.fr.md project.yml outils/garde.py outils/tests/test_garde.py outils/pre-push docs/superpowers
git status --short
python3 outils/garde.py; echo "garde=$?"
A=.superpowers/anonymisation
F=$(git diff --cached --name-only | tr '\n' ' ')
python3 $A/thread/outils/controles.py fichiers --table $A/thread/table.json $F > $A/sortie-thread.txt 2>&1; echo "thread code=$?"
python3 $A/zigbee/controles.py fichiers --table $A/zigbee/table.json $F > $A/sortie-zigbee.txt 2>&1; echo "zigbee code=$?"
```
Expected: neuf fichiers indexés, rien sous `.superpowers/` ni `garde.local.txt` ; `garde=0`, `thread code=0`, `zigbee code=0`.

- [ ] **Step 7: Premier commit**

```bash
git commit -q -F - <<'EOF'
Maillage IoT : spec de la fusion, plan de l'etape 0 et squelette du depot

Spec validee par Djoko les 13 et 14/10 (fusion de Maillage Thread et Maillage Zigbee), plan de l'etape 0,
README bilingues, project.yml vide, garde des vrais identifiants et hook pre-push de reference.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git log --format='%h %ae %ce %s'
```
Expected: un seul commit, auteur et committer `12185352+Djoko-cli@users.noreply.github.com`.

---

### Task 5: Essai de la garde sur un dépôt nu local

Critère de sortie de l'étape 0 (spec, section 6.1). Tout se passe en local : un dépôt nu sous `.superpowers/`, jamais GitHub.

**Files:**
- Create (privé) : `.superpowers/essai-garde/planter.py`, `.superpowers/essai-garde.git` (dépôt nu, supprimé à la fin)

**Interfaces:**
- Consumes: le hook de la tâche 3, le commit racine de la tâche 4.
- Produces: la preuve que le hook accepte un push propre et refuse chaque fuite plantée ; aucune trace d'essai à la fin (ni remote, ni branche, ni objet).

- [ ] **Step 1: Écrire le planteur**

`.superpowers/essai-garde/planter.py` :

```python
#!/usr/bin/env python3
"""Plante une vraie valeur dans un fichier, pour l'essai de la garde (plan de l'etape 0, tache 5).
N'affiche jamais la valeur : seulement sa sorte, le fichier et sa longueur.

    python3 -I planter.py hexa|prenom|nom-thread FICHIER
"""
import json
import os
import re
import sys

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GARDE = os.path.join(RACINE, "garde.local.txt")
TABLE_THREAD = os.path.join(RACINE, ".superpowers", "anonymisation", "thread", "table.json")


def lignes():
    with open(GARDE, encoding="utf-8") as f:
        return [l.strip() for l in f]


def hexa():
    """Un identifiant hexadecimal long, ecrit autrement : minuscules, deux-points tous les deux chiffres."""
    for l in lignes():
        brut = re.sub(r"0x|[:.\- ]", "", l, flags=re.IGNORECASE)
        if l and not l.startswith("#") and len(brut) >= 12 and re.fullmatch(r"[0-9A-Fa-f]+", brut):
            b = brut.lower()
            return ":".join(b[i:i + 2] for i in range(0, len(b), 2))
    sys.exit("aucun identifiant hexadecimal long dans garde.local.txt")


def prenom():
    ls = lignes()
    for i, l in enumerate(ls):
        if l.startswith("# Prenom reel"):
            for suite in ls[i + 1:]:
                if suite and not suite.startswith("#"):
                    return suite
    sys.exit("pas de ligne « # Prenom reel » suivie d'une valeur dans garde.local.txt")


def nom_thread():
    with open(TABLE_THREAD, encoding="utf-8") as f:
        noms = json.load(f).get("noms_reels") or []
    longs = [n for n in noms if isinstance(n, str) and len(n) >= 6]
    if not longs:
        sys.exit("aucun nom reel d'au moins 6 caracteres dans la table de Thread")
    return longs[0]


def main():
    sorte, fichier = sys.argv[1], sys.argv[2]
    valeur = {"hexa": hexa, "prenom": prenom, "nom-thread": nom_thread}[sorte]()
    with open(fichier, "w", encoding="utf-8") as f:
        f.write(f"Essai de la garde : {valeur}\n")
    print(f"plante : une valeur de sorte {sorte} dans {os.path.basename(fichier)} ({len(valeur)} caracteres)")


if __name__ == "__main__":
    main()
```

```bash
cd ~/Dev/maillage-merge
git init -q --bare .superpowers/essai-garde.git
git remote add essai "$PWD/.superpowers/essai-garde.git"
```

- [ ] **Step 2: Un push propre est accepté, commit racine contrôlé**

```bash
git push essai main; echo "code=$?"
git diff-tree --root --no-commit-id --name-only -r "$(git rev-list --max-parents=0 HEAD)" | wc -l
```
Expected: `code=0` ; les bilans des deux contrôles affichés par le hook (sur stderr) ; le compte vaut `9` (tous les fichiers du commit racine sont contrôlés).

- [ ] **Step 3: Un identifiant hexadécimal, autre casse et autres séparateurs, est refusé**

```bash
git checkout -q -b essai-hexa main
python3 -I .superpowers/essai-garde/planter.py hexa essai-plante.txt
git add essai-plante.txt && git commit -q -m "Essai de la garde"
git push essai essai-hexa; echo "code=$?"
git checkout -q main && git branch -q -D essai-hexa
```
Expected: `code=1`, avec « la garde a trouve un identifiant reel » et « push refuse ».

- [ ] **Step 4: Le prénom réel dans un fichier est refusé**

```bash
git checkout -q -b essai-prenom main
python3 -I .superpowers/essai-garde/planter.py prenom essai-plante.txt
git add essai-plante.txt && git commit -q -m "Essai de la garde"
git push essai essai-prenom; echo "code=$?"
git checkout -q main && git branch -q -D essai-prenom
```
Expected: `code=1`, avec « push refuse ».

- [ ] **Step 5: Un nom réel connu du seul contrôle de Thread est refusé**

```bash
git checkout -q -b essai-nom main
python3 -I .superpowers/essai-garde/planter.py nom-thread essai-plante.txt
git add essai-plante.txt && git commit -q -m "Essai de la garde"
git push essai essai-nom; echo "code=$?"
git checkout -q main && git branch -q -D essai-nom
```
Expected: `code=1`, avec « le controle thread a trouve un identifiant ». Si le push passe, s'arrêter et le signaler à Djoko : le contrôle de Thread ne couvre pas ce nom en mode `fichiers`.

- [ ] **Step 6: Le prénom réel dans un message de commit seulement est refusé**

```bash
git checkout -q -b essai-message main
python3 -I .superpowers/essai-garde/planter.py prenom .superpowers/essai-garde/message.txt
git commit -q --allow-empty -F .superpowers/essai-garde/message.txt
git push essai essai-message; echo "code=$?"
git checkout -q main && git branch -q -D essai-message
rm -f .superpowers/essai-garde/message.txt
```
Expected: `code=1`, avec « push refuse » (refus par un contrôle sur le message).

- [ ] **Step 7: `garde.local.txt` absent : refus**

```bash
git checkout -q -b essai-sans-liste main
git commit -q --allow-empty -m "Essai de la garde sans liste"
mv garde.local.txt .superpowers/essai-garde/garde.local.txt.ecarte
git push essai essai-sans-liste; echo "code=$?"
mv .superpowers/essai-garde/garde.local.txt.ecarte garde.local.txt
git checkout -q main && git branch -q -D essai-sans-liste
```
Expected: `code=1`, avec « garde.local.txt absent ou vide : push refuse » ; `garde.local.txt` de retour à la racine.

- [ ] **Step 8: Effacer toute trace de l'essai**

```bash
git remote remove essai
rm -rf .superpowers/essai-garde.git
git reflog expire --expire=now --all && git gc -q --prune=now
echo "remotes : $(git remote | wc -l | tr -d ' ') ; branches distantes : $(git branch -r | wc -l | tr -d ' ')"
echo "commits : $(git rev-list --all | wc -l | tr -d ' ') ; branches : $(git branch | tr -d ' *' | tr '\n' ' ')"
python3 outils/garde.py; echo "garde=$?"
```
Expected: `remotes : 0 ; branches distantes : 0` ; `commits : 1` (ou 2 si les cases ont déjà été commitées) ; `branches : main` ; `garde=0`.

- [ ] **Step 9: Cocher les cases et commiter**

Cocher les étapes faites des tâches 4 et 5 dans ce plan, puis :

```bash
git add docs/superpowers/plans/2026-10-14-maillage-iot-etape-0.md
git commit -q -F - <<'EOF'
Plan de l'etape 0 : garde essayee sur un depot nu local (refus et acceptation)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: Dépôt GitHub `maillage-iot` (avec l'accord de Djoko)

Ne commencer qu'après l'accord explicite de Djoko sur la visibilité (public ou privé) : c'est une action publique.

**Files:** aucun.

**Interfaces:**
- Consumes: `main` propre, hook installé, aucun remote d'essai (tâche 5).
- Produces: `origin` = `https://github.com/Djoko-cli/maillage-iot.git`, `main` poussé.

- [ ] **Step 1: Demander à Djoko : public ou privé**

Proposer la description « About », en anglais : « Maps the Thread and Zigbee radio meshes of a home on its rooms, in 2D and 3D, from the Mac menu bar (merging Maillage Thread and Maillage Zigbee). »

- [ ] **Step 2: Créer le dépôt et pousser, hook compris**

```bash
gh repo create Djoko-cli/maillage-iot --public --description "Maps the Thread and Zigbee radio meshes of a home on its rooms, in 2D and 3D, from the Mac menu bar (merging Maillage Thread and Maillage Zigbee)."
git remote add origin https://github.com/Djoko-cli/maillage-iot.git
git push -u origin main; echo "code=$?"
```
(`--private` à la place de `--public` si Djoko le choisit.)
Expected: `code=0`, les bilans des deux contrôles affichés par le hook, et `main` suivi par `origin/main`.

- [ ] **Step 3: Vérifier l'auteur publié**

Run: `gh api repos/Djoko-cli/maillage-iot/commits --jq '.[].commit.author.email' | sort -u`
Expected: une seule ligne, `12185352+Djoko-cli@users.noreply.github.com`.
