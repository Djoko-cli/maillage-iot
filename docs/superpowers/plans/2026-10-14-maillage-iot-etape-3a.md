# Maillage IoT, étape 3a : une seule app — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fondre les deux cibles d'app en une seule, `MaillageIoT`, qui porte Thread et Zigbee en même temps : identifiants de nœud typés par protocole, fichiers communs, une `Surveillance` à deux modèles, les deux graphes réunis dans la scène avec le dessin actuel, Réglages à six onglets, « Activer ce protocole », deux sondes en même temps, un seul journal. La cible temporaire « Maillage IoT Zigbee » disparaît. Les deux rejeux de démo restent exacts.

**Architecture:** Quatre temps, rejeux verts à chaque tâche. (1) Le cœur reçoit `Protocole` et `IdNoeud`, puis la scène est retypée (un oubli ne compile pas) ; les modules emballent leurs clés à la sortie de leur graphe. (2) Les fichiers communs et le journal portent le protocole ; l'app Thread se prépare (client du démon commun, rangement sous `Thread/`, coque de `Surveillance`). (3) Le code d'app de Zigbee entre dans `MaillageIoT/Zigbee/`, la scène réunit les deux graphes, puis les tests de l'app temporaire rejoignent `MaillageIoTTests` et la cible temporaire est supprimée. (4) Réglages à six onglets, activation par protocole, deux sondes, journal unique ; banc.

**Tech Stack:** Swift 6 strict, XcodeGen 2.46, xcodebuild, Swift Testing, bash.

**Spec:** `docs/superpowers/specs/2026-10-13-maillage-iot-design.md` — sections 1.2, 2, 3.3, 3.4, 3.5, 6.1 et **6.6 (ajustements du 14/10 pour l'étape 3, qui priment ; décisions 1 à 12)**.

**Inventaires** (locaux, hors git, lus par les exécutants) : `.superpowers/fusion/inventaire-etape3-idnoeud.md` (types, sites de clés, conception B, sites de préfixe manqué §6), `.superpowers/fusion/inventaire-etape3-fusion-apps.md` (carte des 58 fichiers de l'app temporaire, coques, collisions, ressources, tests), `.superpowers/fusion/inventaire-etape3-interface.md` (Réglages, deux sondes, journal, démo). Mineurs reportés : `.superpowers/fusion/registre-etape-2.md` (lignes `minor (deferred)`) et `.superpowers/fusion/relecture-finale-etape-2.md` (M2, M3). `I:` = `MaillageIoT/` et `Z:` = `MaillageIoTZigbee/` au début de l'étape (`main` à `d9e07b0` plus le commit de ce plan).

## Global Constraints

- **Les deux rejeux restent exacts à chaque tâche** : `docs/rejeu/thread-demo.json` et `docs/rejeu/zigbee-demo.json`, **jamais régénérés**. Chaque démo est calculée avec l'autre protocole éteint ; les identifiants y sont comparés par leur clé (`IdNoeud.cle`), sans préfixe. Jusqu'à la tâche 9, le rejeu Zigbee tourne dans `MaillageIoTZigbeeTests` ; ensuite dans `MaillageIoTTests`.
- **Restent bruts, jamais préfixés** (spec 6.6, 2) : `noeudMatter`, l'`id` HomeKit du relevé Maison, les clés d'historique (`CourbeLien.id`, `ChangementParent.parent`), les clés de pièce et d'étage (dont `routeur:<clé>`), les partitions (Zigbee garde `zigbee`, jamais `zigbee:zigbee`), `Sujet.id` du journal, les clés internes des modules (`Suivi`, `Rapprochement`, `HistoriqueMaillage`, `IdentitesGardees`, `FusionNoms`, `MemoireAppariements`, noms du pont, `associations.json`).
- `IdNoeud` n'est **pas** `CustomStringConvertible` : un identifiant ne s'affiche jamais par interpolation ; le libellé de repli est `cle`.
- **À ne jamais changer** : `Passeur`, `Masqueur`, `PasseurTests`, `MaillageCoeur/Noms/NomsMaison.swift`, `MaillageCoeur/Noms/ProtocolePasseur.swift`, `MaillageCoeur/Annonces/CodageJSON.swift`, les `rawValue` des types d'événements déjà écrits, les contrats des sondes flashées (services Bonjour, ports, H1, listes blanches).
- Le cœur ne dépend d'aucun module de protocole ; chaque module ne dépend que du cœur. `outils/verifier-noms-publics.sh` passe (étendu aux membres d'extension en tâche 1).
- Identité de l'app unique : `MaillageIoT`, `fr.djoko.maillage.iot`, titre « Maillage IoT », Sparkle conservé. Services de trousseau `fr.djoko.maillage.iot.sonde-thread` (et `.udp`), `fr.djoko.maillage.iot.pont-hue`, `fr.djoko.maillage.iot.sonde-zigbee`, avec la reprise des clés anciennes (`TrousseauRepris`, spec 4.3) pour Zigbee. Clés UserDefaults propres à un module préfixées `thread.` ou `zigbee.`. Fichiers propres à un module sous `Application Support/Maillage IoT/Thread/` ou `…/Zigbee/`.
- **Aucun port USB inconnu n'est ouvert** ; une carte retenue par un module n'est jamais proposée ni ouverte par l'autre (spec 3.4).
- Les tests n'utilisent jamais le vrai trousseau ni le vrai réseau ; `Surveillance.sousTests` garde ses effets (Dock compris).
- DerivedData `~/Library/Developer/Xcode/DerivedData/maillage-iot`. Avertissements = erreurs ; cœur et frameworks en `-O` même en Debug.
- Commentaires sans accents, textes d'interface avec accents ; commits en français sans accents, terminés par une ligne `Co-Authored-By:` du modèle auteur. L'utilisateur s'appelle **Djoko** ; aucun prénom réel ni chemin `/Users/<nom>` dans un fichier commité ; seulement des valeurs inventées dans les tests.
- Ne jamais lire ni afficher `garde.local.txt` ni rien sous `.superpowers/anonymisation/` ni un fichier `*.local*`. Avant chaque commit : `bash outils/controler-index.sh` → 0 défaut.
- Blocs de commandes pour **bash**. Aucun push, aucun `git checkout` d'un autre commit, aucun `git stash`.
- **Porte de chaque tâche** : `outils/tester.sh` passe en entier, `bash outils/verifier-noms-publics.sh` et `bash outils/tester-coeur.sh` aussi. Un test ne change d'attente que si la tâche le dit. Les nombres de `@Test` par cible sont notés avant et après chaque tâche qui déplace, fusionne ou supprime des tests : aucune assertion perdue sans justification écrite au rapport.
- Les cases de ce plan sont cochées dès qu'une étape est faite et vérifiée, et commitées avec le travail.

## Review Focus

1. **Un préfixe manqué ou en trop** : un id de scène comparé à une clé brute de module (fiche vide, sonde non reconnue, surnom perdu, `thread:` affiché à l'écran). On attend une erreur de compilation partout où la conception B le permet, et un test pour chacun des 11 sites de `inventaire-etape3-idnoeud.md` §6 qui restent du texte. → tâches 3, 4, 8.
2. **Le rejeu d'un protocole décalé par l'autre** : teinte, tri, libellé de repli ou mise en avant qui dépendent du texte préfixé, classement Zigbee appliqué à Thread (`ModeLiens.chemins` qui masque les liens radio Thread). On attend les deux rejeux exacts, chacun l'autre protocole éteint, et un test « scène réunie = union des deux scènes seules » sur les nœuds et les liens. → tâches 3, 8.
3. **Un protocole éteint qui tourne encore** : minuterie, tournée, navigateur Bonjour, port série ouvert, notification. On attend, après `actif = false`, aucun port ouvert, aucune minuterie armée, aucune notification, et un rallumage qui repart proprement. → tâche 11.
4. **Une carte ouverte par le mauvais module** : la sonde Thread choisie dans la liste de Zigbee, ou une carte inconnue ouverte. On attend qu'une série retenue par un module disparaisse des choix de l'autre, et que rien ne s'ouvre sans série retenue ni choix explicite. → tâche 12.
5. **Un ancien fichier mal relu** : `surnoms.json` au format plat de Thread 1.3, journal sans `protocole`, `pieces-routeurs.json` version 1 (les journaux de Zigbee 1.1.1 se relisent à l'import, étape 4). On attend la relecture à l'identique (clés de Thread préfixées `thread:` à la lecture, lignes sans protocole = Thread) et qu'un format inconnu ne soit jamais écrasé. → tâche 4.

---

### Task 1: Dette de l'étape 2

Points reportés (`registre-etape-2.md`, `relecture-finale-etape-2.md`), en un lot, avant que l'app importe les deux modules.

**Files:**
- Modify: `MaillageCoeur/Scene/ScenePieces.swift` (classement obligatoire), `ProtocoleThread/Scene/` (nouveau `classementThread`), sites `ScenePieces(` de l'app Thread et des tests, `outils/verifier-noms-publics.sh`, `ProtocoleZigbee` (renommage des membres d'extension en collision : `GrapheReseau.Noeud.init(id:genre:routeur:inconnu:extMac:)` et `CourbesNoeud.init(cle:releves:periode:fin:)`), `ProtocoleZigbee/Noms/MemoireAppariements.swift` (lire et écrire par `FichiersGardes`), `MaillageCoeurTests/CataloguesTests.swift`, `MaillageIoTZigbeeTests/MisesAJourTests.swift:30`, commentaires obsolètes (`Z:Vues/Pieces/FicheNoeud.swift:579`, `Z:Noms/NomsPasseur.swift:12,59,294`, `MaillageIoTZigbeeTests/FenetrePiecesTests.swift:738`, en-tête de `MaillageIoTZigbeeTests/ReferenceRejeuTests.swift`).
- Test: `MaillageCoeurTests/ScenePiecesTests.swift` (ou le fichier qui teste le classement), `ProtocoleZigbeeTests/MemoireAppariementsTests.swift`, `outils/tests/` si le script a des tests.

**Interfaces:**
- Produces: `ScenePieces.init(…, classement:)` **sans valeur par défaut** ; `public func classementThread(_:) ` dans `ProtocoleThread` (la règle par défaut actuelle, déplacée) ; noms Zigbee renommés (consigner la correspondance au rapport) ; `verifier-noms-publics.sh` qui compte aussi les membres publics des extensions de types du cœur (initialiseurs et méthodes, par signature d'étiquettes).

- [x] **Step 1: RED** — étendre `verifier-noms-publics.sh` aux membres d'extension ; le lancer : il doit signaler les deux collisions connues (code non nul). Écrire `MemoireAppariementsTests.formatInconnuJamaisEcrase` (fichier de version inconnue, `ecrire` ne l'écrase pas) : échec attendu. Dans `CataloguesTests`, le cas « une app a ses `.stringsdata`, l'autre non » doit échouer au lieu d'être sauté (test du sélecteur de cas, sans dépendre des produits réels).
- [x] **Step 2: GREEN** — renommer les deux membres Zigbee (étiquettes distinctes, par exemple `init(zigbee:…)`), et leurs appelants ; `MemoireAppariements` par `FichiersGardes` ; `classement` obligatoire, `classementThread` dans `ProtocoleThread`, chaque site passe la règle de son protocole ; `MisesAJourTests` échoue si l'entitlement est illisible au lieu de `?? []` ; commentaires corrigés.
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, deux rejeux exacts), `bash outils/verifier-noms-publics.sh` (code 0), `bash outils/tester-coeur.sh` (code 0). Expected : aucun changement de compte de `@Test` hors tests ajoutés.
- [x] **Step 4: Commit** — « Dette de l'etape 2 : classement obligatoire, noms publics des extensions, appariements gardes, catalogues stricts ».

---

### Task 2: Cœur — `Protocole` et `IdNoeud`

**Files:**
- Create: `MaillageCoeur/Scene/IdNoeud.swift`
- Test: `MaillageCoeurTests/IdNoeudTests.swift`

**Interfaces:**
- Produces (exact) :

```swift
/// Protocole d'un noeud (spec 1.2). L'ordre des cas est l'ordre de tri.
public enum Protocole: String, Codable, Sendable, CaseIterable, Comparable {
    case thread, zigbee

    public static func < (a: Protocole, b: Protocole) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Identifiant d'un noeud au-dessus des modules : le protocole et la cle du module, inchangee (spec 2.1).
/// Forme texte "<protocole>:<cle>", coupee au premier ":" seulement ("thread:instance:Salon" -> cle "instance:Salon").
/// Volontairement sans `CustomStringConvertible` : un identifiant ne s'affiche jamais ; le libelle de repli est `cle`.
public struct IdNoeud: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public let protocole: Protocole
    public let cle: String

    public init(_ protocole: Protocole, _ cle: String) {
        self.protocole = protocole
        self.cle = cle
    }

    /// nil si le protocole est inconnu ou la cle vide.
    public init?(texte: String) {
        guard let i = texte.firstIndex(of: ":"), let p = Protocole(rawValue: String(texte[..<i])) else { return nil }
        let cle = String(texte[texte.index(after: i)...])
        guard !cle.isEmpty else { return nil }
        self.init(p, cle)
    }

    public var texte: String { "\(protocole.rawValue):\(cle)" }

    public static func < (a: IdNoeud, b: IdNoeud) -> Bool {
        (a.protocole, a.cle) < (b.protocole, b.cle)
    }

    public init(from decoder: Decoder) throws {
        let t = try decoder.singleValueContainer().decode(String.self)
        guard let id = IdNoeud(texte: t) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Identifiant de noeud illisible"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(texte)
    }

    public var codingKey: CodingKey { CleTexte(stringValue: texte) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(texte: codingKey.stringValue)
    }

    private struct CleTexte: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
```

- [x] **Step 1: RED** — `IdNoeudTests` : aller-retour texte (`thread:0000000000000001`, `zigbee:00000000000000A1`) ; coupure au premier `:` (`thread:instance:Pièce 1` → cle `instance:Pièce 1`, `thread:rloc:0400`) ; refus de `zigbee:`, `wifi:x`, `sans-deux-points` ; même EUI-64 des deux côtés : deux `IdNoeud` distincts dans un `Set` ; ordre (`thread` avant `zigbee`, puis la clé) ; un `[IdNoeud: Int]` encodé en JSON donne un **objet** `{"thread:0000000000000001":1}` (et non un tableau), et se relit. Lancer `outils/tester.sh MaillageCoeurTests/IdNoeudTests` : échec de compilation attendu.
- [x] **Step 2: GREEN** — créer `IdNoeud.swift` avec le code ci-dessus.
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0), `bash outils/tester-coeur.sh`, `bash outils/verifier-noms-publics.sh`.
- [x] **Step 4: Commit** — « Coeur : Protocole et IdNoeud (forme texte, cle de dictionnaire JSON) ».

---

### Task 3: Cœur — graphe et scène en `IdNoeud` (conception B)

D'après `inventaire-etape3-idnoeud.md` §1, §5 (conception B), §6. Le compilateur liste les sites ; chaque module emballe ses clés en sortant de son graphe.

**Files:**
- Modify (cœur) : `MaillageCoeur/Scene/GrapheReseau.swift` (`Noeud.id`, `Lien.de/vers`, `AppareilAffiche.id`, `chemin(de:)`), `ScenePieces`, `SceneProjetee`, `MiseEnAvant`, `PlacementNoms`, `TransitionScene`, `CartesPieces`, `DispositionPieces`, `ContenuFiche` (types d'identifiants de nœud seulement).
- Modify (modules) : `ProtocoleThread` (`GrapheReseau+Thread.swift`, 6 sites ; `FocusThread`, `FicheThread`, `classementThread`), `ProtocoleZigbee` (`GrapheReseau+Zigbee.swift`, 2 sites ; `FocusZigbee`, `FicheZigbee`, `classementZigbee`).
- Modify (apps) : les vues des deux apps qui lisent ces types (`EntreeScene`, `LibellesNoeuds`, `PiecesChoisies`, `FicheNoeud`, `MorceauxFenetre`, `FenetrePieces` : argument `-selection` en forme texte).
- Test: tests du cœur et des modules qui construisent des nœuds (assistant de test `IdNoeud` dans un fichier sans `@Test`, par cible), les deux `ReferenceRejeuTests`.

**Interfaces:**
- Consumes: `IdNoeud`, `Protocole` (tâche 2).
- Produces: `GrapheReseau.Noeud.id: IdNoeud`, `Lien.de/vers: IdNoeud`, `AppareilAffiche.id: IdNoeud`, `GrapheReseau.chemin(de: IdNoeud) -> Lien?` ; dictionnaires de scène indexés par `IdNoeud` ; **les quatre points de neutralité** : la teinte hache `cle` (pas `texte`), le tri `(rang, libelle, id)` ordonne par `(protocole, cle)`, le libellé de repli est `cle`, `MiseEnAvant.cle(a,b)` trie sur `IdNoeud`. Les partitions restent du texte brut.

- [x] **Step 1: RED** — dans `MaillageCoeurTests`, `scenePasDeCollisionEntreProtocoles` : deux nœuds de même clé, l'un `thread`, l'autre `zigbee`, gardent deux disques et deux libellés ; `teinteNeutre` : la teinte d'un nœud ne change pas si seul son protocole change. Échec de compilation attendu.
- [x] **Step 2: GREEN** — retyper le cœur ; les constructeurs de graphe emballent (`IdNoeud(.thread, …)`, `IdNoeud(.zigbee, …)`) ; les crochets de fiche et de focus des modules reçoivent un `IdNoeud` et lisent leurs états internes par `id.cle` après avoir vérifié `id.protocole` ; les vues des deux apps suivent. Les tests de rejeu comparent par `.cle` (le JSON de référence ne change pas).
- [x] **Step 3: Vérifier** — `outils/tester.sh` (code 0, **deux rejeux exacts**), `bash outils/tester-coeur.sh`, `bash outils/verifier-noms-publics.sh`. Expected : comptes de `@Test` inchangés hors tests ajoutés. Au rapport : la liste des sites de §6 de l'inventaire, chacun avec « ne compile plus sans protocole » ou le test qui le couvre.
- [x] **Step 4: Commit** — « Coeur et modules : identifiants de noeud types par protocole, scene neutre ».

---

### Task 4: Fichiers communs et journal par protocole

**Files:**
- Modify: `MaillageCoeur` : surnoms (type et fichier `surnoms.json`), `PiecesRouteurs` (devient le choix de pièce par `IdNoeud`, fichier `pieces-noeuds.json` version 2), `Suivi/Evenement.swift` (`protocole: Protocole?`), nouvelle `PolitiqueJournalComposee` (dans `MaillageCoeur/Suivi/`), `Regroupement` (clé de parent préfixée du protocole) ; `ProtocoleThread` : associations avec `version` ; app Thread : écrire ses événements avec `protocole = .thread`, lire `surnoms.json` et `pieces-noeuds.json`.
- Test: `MaillageCoeurTests/SurnomsTests.swift`, `PiecesRouteursTests.swift` (renommé si le type l'est), `EvenementTests` ou équivalent, `PolitiqueJournalComposeeTests.swift`, `RegroupementTests`, `ProtocoleThreadTests` (associations).

**Interfaces:**
- Consumes: `IdNoeud` (tâche 2).
- Produces: `surnoms.json` = `{"version": 1, "surnoms": {"thread:<cle>": "…"}}`, qui lit aussi l'ancien dictionnaire plat (clés brutes = `thread`) ; `pieces-noeuds.json` version 2 (clés `IdNoeud`), qui lit `pieces-routeurs.json` version 1 (clés brutes = `thread`) ; `Evenement.protocole: Protocole?` (absent au décodage = `nil`, lu comme `.thread`) ; `PolitiqueJournalComposee(_ politiques: [Protocole: any PolitiqueJournal])` qui délègue selon `e.protocole ?? .thread` ; clé de regroupement `<protocole>|parent|<cle>`.

- [x] **Step 1: RED** — tests : `ancienFormatPlatRelu` (dictionnaire plat → surnoms `thread:`), `formatInconnuJamaisEcrase` (surnoms et pièces), `piecesRouteursVersion1Relu`, `ligneSansProtocoleEstThread`, `memeTypeDeuxGravites` (un même type, écrit avec `protocole: zigbee` puis `thread`, prend la gravité de la politique de son protocole ; la relecture des journaux de Zigbee 1.1.1, sans `protocole`, se règle à l'import, étape 4) (un type présent dans les deux politiques prend la gravité de son protocole), `regroupementSepareLesProtocoles`. Échec attendu.
- [x] **Step 2: GREEN** — implémenter ; l'app Thread passe à `pieces-noeuds.json` et à la politique composée (avec Thread seul pour l'instant).
- [x] **Step 3: Vérifier** — porte de la tâche (deux rejeux exacts).
- [x] **Step 4: Commit** — « Fichiers communs versionnes par IdNoeud, journal et regroupement par protocole ».

---

### Task 5: App Thread — client du démon commun et rangement

D'après `inventaire-etape3-fusion-apps.md` §2.3, §7 (points 4, 5, 7).

**Files:**
- Modify: `MaillageIoT/Noms/` : `NomsInternes.swift` remplacé par `NomsPasseur.swift` de `Z:Noms/` (fichier `releve-maison.json`, sortie `surReleve`) ; `MaillageIoT/MaillageIoTApp.swift` ; `MaillageIoT/Surveillance/Surveillance.swift` (chemins sous `Thread/` : `associations.json`, `identites-routeurs.json`, `dernier-maillage.json`, `dernieres-adresses.json`, `maillage-AAAA-MM.jsonl`) ; déplacement vers `MaillageIoT/Commun/` des fichiers d'app partagés par les deux protocoles (`Thread/Recenseur/NavigateurBonjour.swift`, `ResolveurDNSSD.swift`, `Thread/Sonde/PortsUSB.swift`, `PortSerie.swift`, `LiaisonSerie.swift` : seulement ceux que `inventaire-etape3-fusion-apps.md` donne identiques ou à crochet ; la liste exacte au rapport).
- Test: tests de l'app Thread qui citent `NomsInternes`, `noms.json` ou les chemins.

**Interfaces:**
- Produces: `NomsPasseur` client unique du démon dans `MaillageIoT` ; dossier `Thread/` ; `MaillageIoT/Commun/`.

- [x] **Step 1: RED** — `DossierThreadTests.fichiersDeThreadSousThread` (l'historique et `dernier-maillage.json` s'écrivent sous `Thread/`) ; adapter les tests de `NomsInternes` à `NomsPasseur` (reprendre ceux de `MaillageIoTZigbeeTests` pour `NomsPasseur`). Échec attendu.
- [x] **Step 2: GREEN** — remplacer le client, ranger sous `Thread/`, déplacer les fichiers communs (`git mv`).
- [x] **Step 3: Vérifier** — porte de la tâche.
- [x] **Step 4: Commit** — « App Thread : client du demon commun, fichiers sous Thread/, code partage sous Commun/ ».

---

### Task 6: `Surveillance` : coque commune et `SurveillanceThread`

D'après `inventaire-etape3-fusion-apps.md` §2.2, §2.5 (point 1) ; spec 6.6, décision 6. Thread seul encore.

**Files:**
- Modify: `MaillageIoT/Surveillance/Surveillance.swift` (coque : `mode`, journal, `evenements`, `Alertes`, surnoms, veille, `maintenant`, `chargerJournal`, `purgerSiNouveauMois`, `captureJSON`, `ajouter`, modèles par protocole) ; Create: `MaillageIoT/Thread/SurveillanceThread.swift` (Bonjour, instantané, sonde, suivi, historique, fraîcheur 6 et 15 min, `EtatEcoute`, `thread.scissionsNotifiees`) ; les vues qui lisent l'état Thread passent par `surveillance.thread`.
- Test: `MaillageIoTTests` (89 appels `Surveillance(mode:dossier:)` gardent cette forme).

**Interfaces:**
- Produces: `Surveillance(mode:dossier:)` inchangé ; `surveillance.thread: SurveillanceThread` ; un point d'entrée par protocole pour la scène (`graphe(pour:) -> GrapheReseau`, `appareils`, `echelle`, crochets de fiche et de focus, résumé de menu), réunis dans un protocole d'app `ModeleProtocole` (forme de `ProtocoleMaille`, spec 1.2), dans l'app, pas dans le cœur.

- [x] **Step 1: RED** — `SurveillanceTests.coqueSansProtocole` (la coque se construit, journal et surnoms marchent, sans modèle actif) ; échec de compilation attendu.
- [x] **Step 2: GREEN** — scinder ; aucun comportement ne change.
- [x] **Step 3: Vérifier** — porte de la tâche ; comptes de `@Test` de `MaillageIoTTests` notés avant et après.
- [x] **Step 4: Commit** — « Surveillance : coque commune et modele Thread ».

---

### Task 7: Le code d'app de Zigbee entre dans `MaillageIoT`

D'après `inventaire-etape3-fusion-apps.md` §1 (carte des 58 fichiers), §3 (collisions), §4 (ressources). **La cible temporaire reste intacte jusqu'à la tâche 9** : ici on copie, on ne déplace pas.

**Files:**
- Create: `MaillageIoT/Zigbee/` : les fichiers (Z) et (≠) de la carte, renommés là où §3 le demande (16 renommages, préfixe `Zigbee` ou suffixe, consignés au rapport) ; `MaillageIoT/Zigbee/SurveillanceZigbee.swift` (d'après `Z:Surveillance/Surveillance.swift` : pont, sonde, `SuiviConnexions`, historique, fraîcheur 16 et 45 min) ; les fichiers (≈) deviennent communs avec le crochet nommé par la carte.
- Modify: `MaillageIoT/MaillageIoTApp.swift` (une `DecouvertePont`, un `NomsPont`, une seconde `SondeMaillage` pour Zigbee avec `TrousseauRepris`, `surveillance.zigbee`, toujours inertes en démo et sous tests) ; `MaillageIoT/Ressources/Localizable.xcstrings` (union, 7 clés divergentes : traduction de Thread) ; `MaillageIoT/Info.plist` (`NSBonjourServices` à six types, `NSLocalNetworkUsageDescription` neutre) ; `project.yml` (`MaillageIoT` dépend de `ProtocoleZigbee`).
- Test: ce qui ne compile plus dans `MaillageIoTTests` à cause des renommages.

**Interfaces:**
- Produces: `surveillance.zigbee: SurveillanceZigbee` (même protocole d'app que `SurveillanceThread`) ; les deux sondes instanciées, chacune avec ses clés `thread.`/`zigbee.`.

- [x] **Step 1: RED** — `DemarrageTests.deuxModelesSousTests` : sous tests, `surveillance.thread` et `surveillance.zigbee` existent, aucun port, aucun Bonjour, aucun trousseau réel. Échec attendu.
- [x] **Step 2: GREEN** — copier et renommer ; brancher. La scène ne montre encore que Thread (jonction à la tâche 8).
- [x] **Step 3: Vérifier** — porte de la tâche ; `CataloguesTests` (les deux apps), `verifier-noms-publics`.
- [x] **Step 4: Commit** — « App : le code de Zigbee entre dans Maillage IoT (pont, sonde, modele Zigbee) ».

---

### Task 8: Jonction des deux graphes dans la scène

D'après `inventaire-etape3-fusion-apps.md` §2.5 (points 2, 3), `inventaire-etape3-interface.md` §3.1-3.2, §3.6.

**Files:**
- Modify: `MaillageIoT/Vues/Pieces/EntreeScene.swift` (union des graphes des protocoles actifs ; classement, chefs, mise en avant, échelle et focus choisis par `id.protocole`) ; `FicheNoeud` et `CourbesFiche` (crochet par protocole : adresse IPv6 ou IEEE, dBm ou LQI, parent ou chemin vers le pont) ; `ModeLiens` propre à Zigbee (jamais appliqué aux liens Thread, `SceneProjetee.trace`) ; démo : la démo Thread et la démo Zigbee disponibles dans `MaillageIoT`, chacune seule (la démo combinée est à l'étape 3b).
- Create: `MaillageIoTTests/ReferenceRejeuZigbeeTests.swift` (d'après `MaillageIoTZigbeeTests/ReferenceRejeuTests.swift`, Zigbee seul, référence `docs/rejeu/zigbee-demo.json`).
- Test: `EntreeSceneTests` (ou équivalent) : `sceneReunieEstLUnionDesDeux`.

**Interfaces:**
- Consumes: `ModeleProtocole` (tâches 6, 7), `IdNoeud`.
- Produces: une scène qui réunit Thread et Zigbee avec le dessin actuel ; les deux rejeux exacts dans `MaillageIoTTests`.

- [ ] **Step 1: RED** — `sceneReunieEstLUnionDesDeux` (nœuds et liens de la scène réunie = union de ceux des deux scènes seules ; aucun lien entre protocoles ; liens radio Thread visibles quel que soit `ModeLiens`) ; `ReferenceRejeuZigbeeTests` dans `MaillageIoTTests`. Échec attendu.
- [ ] **Step 2: GREEN** — implémenter la jonction et les crochets.
- [ ] **Step 3: Vérifier** — porte de la tâche (les deux rejeux exacts dans `MaillageIoTTests`, et encore dans `MaillageIoTZigbeeTests`).
- [ ] **Step 4: Commit** — « Scene : les deux reseaux reunis, crochets par protocole, rejeu Zigbee dans l'app unique ».

---

### Task 9: Les tests de l'app temporaire rejoignent `MaillageIoTTests` ; la cible temporaire disparaît

D'après `inventaire-etape3-fusion-apps.md` §5 (25 homologues, 11 Zigbee seuls, 38 noms en collision, attentes d'identité), §6.

**Files:**
- Move: `MaillageIoTZigbeeTests/*` → `MaillageIoTTests/Zigbee/` (homologues fusionnés, collisions renommées, `@testable import MaillageIoT`) ; attentes d'identité ramenées à l'app unique (titre « Maillage IoT », identifiant `fr.djoko.maillage.iot`, domaine de préférences de test).
- Delete: `MaillageIoTZigbee/`, cibles `MaillageIoTZigbee` et `MaillageIoTZigbeeTests`, schéma `MaillageIoTZigbee` ; `CataloguesTests` et `outils/synchroniser-textes.sh` reviennent à une seule app.
- Modify: `project.yml`, `outils/tester.sh` si besoin ; `MaillageIoT/Noms/NomsPasseur.swift:347` : le message « …les noms viennent de l'app Hue » devient neutre (vrai pour Thread seul, Zigbee seul ou les deux), avec son test (relecture de la tâche 5).

- [ ] **Step 1: Compter** — `@Test` de `MaillageIoTTests` et de `MaillageIoTZigbeeTests` avant ; tableau fichier par fichier au rapport.
- [ ] **Step 2: Déplacer et fusionner** — chaque test Zigbee garde son assertion ; un test dédoublonné (même assertion des deux côtés) est justifié au rapport.
- [ ] **Step 3: Supprimer la cible temporaire** — et ses références (`grep -rn MaillageIoTZigbee` ne trouve plus que l'historique des plans et la spec).
- [ ] **Step 4: Vérifier** — porte de la tâche ; somme des `@Test` après = somme avant − dédoublonnés justifiés.
- [ ] **Step 5: Commit** — « Tests Zigbee dans MaillageIoTTests, cible temporaire supprimee ».

---

### Task 10: Réglages à six onglets

D'après `inventaire-etape3-interface.md` §3.3 ; spec 3.3, 6.6 (décision 10).

**Files:**
- Modify: `MaillageIoT/Vues/ControleurReglages.swift` (version de Zigbee, avec le correctif de hauteur du 11/10), `FenetreReglages.swift` : onglets **Général · Notifications · Maison · Thread · Zigbee · Diagnostic** ; Thread = sonde Thread (USB ou réseau) et Thread Route ; Zigbee = pont Hue et sonde Zigbee ; Général = langue, mises à jour, ouverture de session (« Reprendre des données… » est à l'étape 4).
- Test: `ReglagesHauteurTests` (fenêtre hors écran, les six onglets).

- [ ] **Step 1: RED** — `ReglagesHauteurTests` sur les six onglets ; `OngletReglages.allCases` = les six, dans l'ordre. Échec attendu.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Reglages : six onglets, Thread et Zigbee chacun le sien ».

---

### Task 11: « Activer ce protocole »

D'après `inventaire-etape3-interface.md` §3.3 (aucune `SondeMaillage` n'a d'`arreter()`, `actif` est un `let`) ; spec 3.3, 6.6 (décision 11).

**Files:**
- Modify: les deux `SondeMaillage` (`actif` devient modifiable ; `arreter()` ferme le port, annule tournées, entretien et relances ; `demarrer()` repart), `Recenseur`, `DecouvertePont`, `NomsPont` (`arreter()` réel), `SurveillanceThread`, `SurveillanceZigbee` (`actif`, persisté sous `thread.actif` / `zigbee.actif`, vrai par défaut), `Alertes` (aucune notification d'un protocole éteint), scène (les nœuds d'un protocole éteint disparaissent), onglets Thread et Zigbee (« Activer ce protocole » en tête ; un protocole actif qui ne trouve rien le dit sans alerte).
- Test: `ActivationTests` (app), tests des deux `SondeMaillage`.

**Interfaces:**
- Produces: `ModeleProtocole.actif: Bool { get set }`.

- [ ] **Step 1: RED** — pour chaque protocole : après `actif = false`, aucun port ouvert (port factice), aucune minuterie ni tâche de tournée vivante, aucun navigateur Bonjour, aucune alerte émise par un événement de ce protocole, nœuds absents de la scène ; `actif = true` repart ; la préférence survit à un redémarrage du modèle. Échec attendu.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Activer ce protocole : arret reel du module (sonde, Bonjour, pont, tournees, notifications) ».

---

### Task 12: Deux sondes en même temps

D'après `inventaire-etape3-interface.md` §3.4 ; spec 3.4.

**Files:**
- Create: `MaillageIoT/Commun/CartesRetenues.swift` (registre des numéros de série retenus par chaque module, observable).
- Modify: les deux `SondeMaillage` (`portsChanges` et `choisir` filtrent les cartes retenues par l'autre module ; rien ne s'ouvre sans série retenue ou choix explicite), les deux listes de ports des Réglages.
- Test: `CartesRetenuesTests`, tests des deux sondes.

- [ ] **Step 1: RED** — une série retenue par Thread disparaît des choix de Zigbee et n'est jamais ouverte par lui (et l'inverse) ; une carte Espressif inconnue n'est jamais ouverte ; « Oublier la sonde » la rend aux choix de l'autre. Échec attendu.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Deux sondes : registre des cartes retenues, aucune carte de l'autre module ouverte ».

---

### Task 13: Journal unique, notifications et menu à deux protocoles

Le minimum de l'étape 3a ; les filtres et marques du journal, les catégories par protocole et l'icône « pire des deux » sont à l'étape 3b.

**Files:**
- Modify: `Surveillance` (un journal, `PolitiqueJournalComposee` avec Thread et Zigbee, événements des deux modèles avec leur `protocole`) ; `Notifications`/`Alertes` (alertes des deux protocoles actifs, catégories et clés actuelles communes) ; `MenuBarre` (les lignes de résumé des deux protocoles actifs, l'une sous l'autre) ; `FenetreJournal` (les deux protocoles, textes d'événements de chaque module : `TexteEvenement` Thread et Zigbee renommés à la tâche 7).
- Test: `JournalDeuxProtocolesTests`, `MenuTests`.

- [ ] **Step 1: RED** — un événement Zigbee et un Thread du même type gardent chacun la gravité de leur protocole dans le journal relu ; le menu montre une ligne par protocole actif et aucune pour un protocole éteint. Échec attendu.
- [ ] **Step 2: GREEN** — implémenter.
- [ ] **Step 3: Vérifier** — porte de la tâche.
- [ ] **Step 4: Commit** — « Journal, alertes et menu : les deux protocoles ».

---

### Task 14: Banc avec Djoko

Fait par l'orchestrateur avec Djoko, après la relecture finale et ses correctifs.

- [ ] **Step 1: Préparer** — compiler `MaillageIoT` (Debug). Le conteneur de développement de `fr.djoko.maillage.iot` n'est pas migré (spec 6.6, décision 8) : avec l'accord de Djoko, mettre de côté son dossier `Application Support/Maillage IoT/` avant le lancement. Les clés du trousseau sont reprises de Thread 1.3.0 et de Zigbee 1.1.1 par les invites de macOS (Zigbee) ou par la remise en service (Thread, la reprise des clés de Thread est à l'étape 4).
- [ ] **Step 2: Comparer** — les deux réseaux réels ensemble dans la vue par pièces (dessin actuel), à côté de Thread 1.3.0 et de Zigbee 1.1.1 ; les deux sondes en USB en même temps (aucune carte de l'autre dans les listes) ; « Activer ce protocole » éteint puis rallumé pour chacun ; le journal et le menu.
- [ ] **Step 3: Verdict** — noté au registre ; plan coché ; fusion dans `main` et push avec l'accord de Djoko.
