# Maillage IoT, phase 6 : panneau de santé — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un panneau de santé en verre, en haut à gauche de la vue par pièces : replié, les comptes de toute la maison par protocole ; ouvert, la liste des nœuds perdus ou à surveiller dans la portée du focus.

**Architecture:** Un modèle pur `SantePieces` (lecture de `EntreeScene`, de l'isolement du moteur et des dates de disparition du journal) donne tout ce que le panneau affiche ; une vue `PanneauSante` (SwiftUI, Liquid Glass) le dessine et agit sur le moteur (isoler, sélectionner, revenir à la maison). Aucun nouvel état réseau.

**Tech Stack:** Swift 6 strict, SwiftUI, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-panneau-sante-design.md` (la conception, binding) ; pour le reste de l'app, `docs/superpowers/specs/2026-10-13-maillage-iot-design.md`.

## Global Constraints

- Tous les nœuds, sans distinction de nature (appareils, routeurs Thread, routeurs de bordure, routeurs Zigbee, coordinateur) : mêmes familles **Perdu** (rouge) et **À surveiller** (orange), selon le tableau §2.1 de la conception.
- Les comptes de la capsule repliée portent toujours sur toute la maison ; la liste ouverte suit le focus (maison, niveau isolé, pièce isolée) ; la ligne « Ailleurs » résume le reste hors de la vue d'ensemble.
- La pièce est la pièce **placée dans la scène** ; un nœud sans pièce placée est dans la portée « Maison » et, sinon, dans « Ailleurs ».
- Préférence de repli propre au panneau (`santeRepliee`), **repliée par défaut** ; animation et verre identiques à la légende (`Apparition`, `VerreDeLegende` et son repli de capture).
- Textes en français et en anglais (catalogue), heures relatives comme la fiche (`FicheNoeud.relatif`, heure de référence `surveillance.maintenant(de:a:)`).
- Swift 6 strict, avertissements = erreurs ; aucun `nonisolated(unsafe)` ni `@unchecked Sendable` ajouté. Références de rejeu inchangées. Aucune valeur réelle.
- Porte de chaque tâche : `bash outils/tester.sh` vert, `bash outils/tester-sondes.sh`, `bash outils/controler-index.sh` → 0 ; la passe anglaise reste verte (`xcodebuild … -testLanguage en -testRegion US test`), car la publication la rejoue.
- Commentaires sans accents ; commits en français sans accents, terminés par `Co-Authored-By:` du modèle ; jamais de push ni de `--no-verify`. Cases du plan cochées et commitées avec le travail.

## Review Focus

1. **Un nœud fautif oublié** : un routeur disparu, un pont injoignable, un routeur de bordure d'une autre partition, un appareil en pile faible doivent tous paraître (tests par famille et par nature de nœud, Task 1).
2. **« Tout va bien » à tort** : un protocole actif sans relevé montre « … », jamais « Tout va bien » (Task 1).
3. **Portée fausse** : un nœud placé dans une autre pièce que sa pièce Maison est compté là où il est placé ; un nœud sans pièce placée va dans « Ailleurs » hors de la vue d'ensemble (Task 1).
4. **Un clic qui ne mène pas à l'appareil** : depuis la vue d'ensemble, depuis un autre niveau, depuis une autre pièce ; un nœud absent de la scène n'est pas cliquable (Task 2).
5. **Le panneau qui cache la scène** : obstacle pour les noms des nœuds, hauteur limitée à la moitié de l'espace libre, défilement (Task 2).

---

### Task 1: Le modèle `SantePieces`

**Files:**
- Create: `MaillageIoT/Vues/Pieces/SantePieces.swift`
- Test: `MaillageIoTTests/SantePiecesTests.swift`

**Interfaces:**
- Produces : `SantePieces.Lecture` (une valeur, `Equatable`) construite par `SantePieces.lire(entree: EntreeScene, isolement: Isolement, disparitions: [IdNoeud: Date], maintenant: (Protocole) -> Date, sansReleve: Set<Protocole>)` (signature indicative : le constructeur l'ajuste aux types réels et le dit au rapport) avec :
  - `capsule` : pour chaque protocole montré, `perdus`, `aSurveiller` (toute la maison), ou l'état « … » ; `toutVaBien`.
  - `portee` : `.maison`, `.etage(nom)`, `.piece(nom)` (le titre).
  - `sections` : par protocole montré, comptes de la portée et lignes `Ligne(id, nom, piece, famille, cause, cliquable)`, triées (perdus, puis à surveiller ; pièce ; nom).
  - `ailleurs` : comptes hors portée (nil à la vue d'ensemble ou si zéro).
- Consumes : `EntreeScene` (`appareils`, `scene.noeuds`, `scene.pieces`, `scene.etages`, `montres`), `Isolement`.

- [x] **Step 1: Tests RED** — un test par ligne du tableau §2.1 (perdu : disparu Thread et Zigbee, injoignable Zigbee ; à surveiller : pile faible, adresse plus annoncée, adresse non annoncée, partition coupée / autre partition) **pour un appareil et pour un routeur** (et le pont injoignable) ; un nœud des deux familles n'apparaît qu'une fois, en Perdu ; ordre de tri ; portée maison / niveau / pièce par la **pièce placée** (cas d'un nœud placé ailleurs que sa pièce Maison) ; nœud sans pièce placée dans « Ailleurs » ; comptes de la capsule toujours maison ; « … » pour un protocole sans relevé ; protocole masqué ou éteint absent ; date de disparition : la plus récente, et « disparu » sans heure quand elle manque ; démo combinée : la lecture n'est pas vide et ne contient que des nœuds de la démo.
- [x] **Step 2: GREEN** — implémenter, en lisant les états des routeurs là où la scène et les suivis les portent (le dire au rapport).
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « Sante : modele du panneau (familles, portee, ailleurs) ».

---

### Task 2: La vue `PanneauSante` et ses gestes

**Files:**
- Create: `MaillageIoT/Vues/Pieces/PanneauSante.swift`
- Modify: `MaillageIoT/Vues/Pieces/FenetrePieces.swift` (placement sous `HautPieces`, obstacle, hauteur), catalogues `Localizable.xcstrings`
- Test: `MaillageIoTTests/PanneauSanteTests.swift`

**Interfaces:**
- Consumes : `SantePieces.Lecture` (Task 1) ; `MoteurPieces.isoler(_:)`, `selection`, `versMaison(enFondu:)`, `isolement`.
- Produces : `PanneauSante(lecture:moteur:)` ; préférence `PanneauSante.cleRepliee = "santeRepliee"`.

- [x] **Step 1: Tests RED** — repli par défaut et mémorisé ; capsule : pastilles à zéro cachées, « Tout va bien », « … » ; ouvert : titre de portée, sections, ligne « Ailleurs » ; clic sur une ligne : depuis la maison, depuis un autre niveau, depuis une autre pièce → la pièce du nœud est isolée et le nœud sélectionné ; clic sur « Ailleurs » → vue d'ensemble ; ligne d'un nœud absent de la scène non cliquable ; hauteur bornée à la moitié de l'espace libre avec défilement ; obstacle enregistré pour les noms.
- [x] **Step 2: GREEN** — implémenter (verre et animation de la légende, ancrés en haut à gauche ; textes fr et en).
- [x] **Step 3: Vérifier** — porte de la tâche, passe anglaise comprise ; captures temporaires de la démo combinée (repliée et ouverte) au rapport.
- [x] **Step 4: Commit** — « Sante : panneau en verre dans la vue par pieces ».

---

### Task 3: Captures

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/CapturesPieces.swift` (cas de la démo combinée : panneau replié, ouvert à la maison, ouvert sur une pièce isolée), tests qui comptent les cas.

- [x] **Step 1: Ajouter les cas** et mettre à jour les tests qui comptent les cas.
- [x] **Step 2: Vérifier** — porte ; `-demo -captures <dossier>` produit les trois images (chemins au rapport).
- [x] **Step 3: Commit** — « Sante : captures du panneau ».

---

### Task 4: Relecture finale et banc

- [ ] **Step 1: Relecture finale** — par Opus, sur toute la branche.
- [ ] **Step 2: Banc** — avec Djoko, sur l'app réelle (compilation de travail) et la démo : coup d'œil, focus, clics, ailleurs.
- [ ] **Step 3: Verdict** — cocher « Phase 6 » dans la §6.1 de la spec ; fusion dans `main` et push avec l'accord de Djoko.
