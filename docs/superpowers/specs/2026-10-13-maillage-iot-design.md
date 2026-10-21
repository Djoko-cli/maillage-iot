# Maillage IoT : fusion de Maillage Thread et Maillage Zigbee

Spec du 13/10/2026. Djoko a validé la conception le même jour, en chat, section par section. Elle s'appuie sur les
états des lieux de la session Thread et de la session Zigbee, puis sur leurs relectures de cette spec (13/10),
intégrées le 14/10. Ces documents sont gardés hors git (voir section 6.1, étape 0).

## 0. Contexte et décisions

**Aujourd'hui, deux apps de barre des menus voisines :**

- **Maillage Thread 1.3.0** (build 544, `fr.djoko.maillage`) : routeurs de bordure et appareils vus par Bonjour,
  vrai maillage par la sonde Thread (ESP32-C6, USB ou réseau via Thread Route), noms par le démon Passeur Noms.
- **Maillage Zigbee 1.1.1** (build 103, `fr.djoko.maillage.zigbee`) : maillage par la sonde Zigbee (USB ou Wi-Fi,
  enveloppe H1), noms et pièces par l'API du pont Hue et par le démon Passeur Noms.
- Zigbee est né d'une copie du cœur de Thread (début octobre). Les deux `MaillageCoeur` ont divergé depuis, surtout
  à cause du protocole : IEEE et LQI contre RLOC16, IPv6 et dBm. `GrapheReseau` est déjà presque générique : Zigbee
  y a gardé `partition`, `bordure` et `extMac` « pour la scène ».
- Le démon Passeur Noms est déjà commun : contrat `ProtocolePasseur.swift`, identique à l'octet dans les deux dépôts.

**Décisions de Djoko (13 et 14/10) :**

| Sujet | Décision |
|---|---|
| But | Les deux à la fois : **une vue unifiée** de la maison (Thread et Zigbee sur le même plan) **et un seul produit** à maintenir (un cœur, une publication, un flux). L'ouverture à d'autres protocoles va au backlog. |
| Utilisateurs existants | **Annonce et reprise manuelle** : une dernière version de chaque ancienne app annonce Maillage IoT et exporte ses données ; la nouvelle app les importe. Pas de migration Sparkle automatique. |
| Vue | **A : superposés, filtrables.** Deux interrupteurs Thread et Zigbee, mémorisés, tous deux allumés par défaut. |
| Dépôt et identité | **Tout neuf** : nouveau dépôt `maillage-iot`, nouvel identifiant `fr.djoko.maillage.iot`. |
| Reprise | **Réglages, noms et historique** (courbes et journal, 90 jours au plus). |
| Périmètre du dépôt | **Tout le système** : app, démon Passeur et Masqueur, les deux firmwares de sonde (séparés), copie de Thread Route, outils. |
| Approche | **1 : cœur neutre extrait de Thread**, Thread branché à l'identique, puis Zigbee, puis l'interface à deux protocoles, puis la reprise et la publication. |
| Prénom réel (14/10) | **Masqué partout.** Dans tout fichier commité et tout message de commit, l'utilisateur s'appelle **Djoko** ; la garde refuse le prénom réel. |

**Hors périmètre** (voir section 8) : autres protocoles, vue de santé par pièce, fusion des firmwares, migration
Sparkle automatique.

## 1. Architecture

### 1.1 Cibles

Comme aujourd'hui : XcodeGen (`project.yml` fait foi), Swift 6 strict, avertissements traités comme des erreurs,
macOS 26 au minimum, Sparkle 2.10.0 (SPM).

| Cible | Rôle | Identifiant |
|---|---|---|
| `MaillageCoeur` (framework) | Cœur **neutre** : scène 2D/3D, pièces et étages, fiche, focus, courbes, journal, suivi générique, noms (relevé Maison, Passeur, surnoms), fichiers gardés, enveloppe H1, interface « réseau maillé ». **Il ne connaît aucun protocole.** | `fr.djoko.maillage.iot.coeur` |
| `ProtocoleThread` (framework) | Bonjour et décodage (HAP, Matter, routeur de bordure), instantané, adresses, sonde Thread (USB et UDP), diagnostic TLV, tournées, résolution d'adresse, rapprochement, identités gardées, crochets de fiche et de focus. | `fr.djoko.maillage.iot.thread` |
| `ProtocoleZigbee` (framework) | Trames, Mgmt_Lqi et tables de routage, adresses IEEE et NWK, sonde Zigbee (USB et TCP), API du pont Hue (HTTPS vérifié), `FusionNoms`, `MemoireAppariements`, suivi des connexions. | `fr.djoko.maillage.iot.zigbee` |
| `MaillageIoT` (app) | App de barre des menus (`LSUIElement`), SwiftUI avec les Réglages en AppKit. Elle assemble les modules. | `fr.djoko.maillage.iot` |
| `Passeur`, `Masqueur` | Le démon Passeur Noms, **tel quel** (voir 5.3). | `fr.djoko.maillage.passeur`, `….passeur.masqueur` |
| Tests | Une cible de tests par framework, une pour l'app, une pour le démon. | `….tests`, `….coeur.tests`, etc. |

**Dépendances** : `ProtocoleThread` → `MaillageCoeur` ; `ProtocoleZigbee` → `MaillageCoeur` ; `MaillageIoT` → les
trois. `MaillageCoeur` ne dépend d'aucun module de protocole : les cibles l'interdisent à la compilation, et c'est
la garantie structurelle contre un cœur rempli de `if zigbee`.

**Optimisation** : le cœur et les deux modules sont compilés en `-O` même en Debug, comme le cœur de Thread
aujourd'hui (disposition des pièces).

### 1.2 L'interface « réseau maillé »

Le cœur définit l'interface ; chaque module l'implémente. Esquisse (le plan de l'étape 1 la fixe en lisant le code,
noms et signatures compris) :

```swift
public enum Protocole: String, Codable, Sendable, CaseIterable { case thread, zigbee }

/// Identifiant d'un noeud, stable entre les lancements ; forme texte "thread:<cle>" ou "zigbee:<cle>".
/// La cle est l'identifiant actuel du noeud dans son protocole, inchange (section 2.1).
public struct IdNoeud: Hashable, Codable, Sendable {
    public let protocole: Protocole
    public let cle: String
}

/// Qualite d'un lien ou d'un signal, en bandes communes aux protocoles.
public enum BandeQualite: Sendable { case bonne, moyenne, faible, inconnue }

/// Ce que chaque protocole fournit au coeur.
@MainActor public protocol ProtocoleMaille: AnyObject {
    var protocole: Protocole { get }
    var actif: Bool { get set }
    var graphe: GrapheReseau { get }          // noeuds et liens de ce protocole, sans geometrie
    var appareils: [AppareilAffiche] { get }  // noms deja choisis, etats, batteries
    var echelle: EchelleSignal { get }        // unite, pas, bornes, bandes, etiquette
    // evenements du journal, points de courbe, crochets de fiche et de focus, Identifier
}
```

**Règles :**

- **`GrapheReseau` reste le modèle d'affichage**, par protocole. La scène réunit les graphes des protocoles actifs.
  Les identifiants de nœud et de partition sont préfixés, donc rien n'entre en collision. Thread garde ses
  partitions ; Zigbee a une partition unique.
- **Pas de lien entre protocoles** : un lien relie toujours deux nœuds du même protocole.
- **Les enums partagés sont unifiés** dans le cœur. `EtatAffiche` réunit `joignable`, `partitionCoupee`,
  `sansAdresse` (Thread), `injoignable` (Zigbee), `disparu` et `inconnu`. `GenreLien` réunit les cas des deux côtés,
  dont `.chemin` de Zigbee. Chaque module n'utilise que les siens.
- **L'échelle de signal devient un crochet** (`EchelleSignal` par protocole) : unité (dBm ou LQI), pas, bornes et
  étiquette ; elle range une valeur en `BandeQualite`.
- **Tout ce qui dépend du protocole passe par un crochet** : construction du graphe, historique, suivi et événements,
  fiche, focus, rang et rayon des nœuds dans la scène, sous-système du Logger, types d'événements.

### 1.3 Ce qui va où

Les états des lieux classent les fichiers de `MaillageCoeur`. On part du code de Thread, en avance sur le graphe, la
fiche en quatre colonnes, le focus et les noms. On prend chez Zigbee ce qui y est en avance.

| Fichiers actuels | Destination |
|---|---|
| Identiques des deux côtés : `ProtocolePasseur`, `Annonces/ChampsTXT`, `Annonces/CodageJSON`, `Journal/*`, `CameraScene`, `Isolement`, `Niveaux`, `PlacementNoms`, `PlacesGardees`, `PolitiqueGrille` | Cœur, tels quels |
| `Reseau/EnveloppeH1` (cœur de Zigbee, et la même dans l'app Thread sous `MaillageThread/Sonde/Reseau/`) | Cœur, **une seule fois**, pour les deux sondes |
| Écarts de commentaires seulement : `ChoixCourbes`, `ReperesCourbe`, `ContenuFiche`, `ResumeRelais`, `MiseEnAvant`, `CartesPieces` | Cœur, version de Thread |
| `SceneProjetee` | Cœur, **version de Zigbee** (`ModeLiens`, voisins, traces des chemins), réalignée sur le moteur de Thread. Le réalignement garde `GenreLien.chemin` et le focus Zigbee (chemins vers le pont, dépendants). |
| `TransitionScene`, `FichiersGardes`, `EchelleSignal`, `DispositionPieces`, `ScenePieces`, `Evenement`, `Regroupement`, `Alertes`, `PiecesRouteurs` | Cœur, version de Thread, plus un **crochet** par écart (`suppose`, Logger paramétré, échelle, liens `.chemin`, rang et rayon, types d'événements, partie routeur de bordure) |
| `NomsMaison` (Thread) et `ReleveMaison` (Zigbee) | Cœur : le **relevé Maison commun** v1/v2. L'identifiant HomeKit garde la clé JSON **`id`**, qui fait partie du contrat du démon, quel que soit le nom Swift. Ce qui appartient à un protocole (accessoire Matter, appareil du pont) part dans son module. |
| `GrapheReseau`, `CourbesNoeud`, `HistoriqueMaillage`, `SuiviMaillage` | Types dans le cœur, construction dans chaque module |
| `ResolveurNoms`, `NomsDemo` | Par protocole |
| Propres à Thread : `Adresses/`, `Annonces/Annonces`, `Decodage/`, `Instantane/`, `Maillage/` (sonde, tournées, résolution, rapprochement, diagnostic, identités gardées, clés d'historique, accès au canal), `Suivi/Suivi` et `MemoireAnnonces`, `Systeme/InterfacesLocales` et `TableRoutage`, `FicheThread`, `FocusThread` | `ProtocoleThread` |
| Propres à Zigbee : `Zigbee/`, `Sonde/`, `Pont/` (`ApiHue`, `CertificatPont`, `RacinesSignify` : HTTPS vérifié contre les racines de Signify), `FusionNoms`, `MemoireAppariements`, `Suivi/SuiviConnexions` | `ProtocoleZigbee` |

**Le code des apps** (dossiers `MaillageThread/` et `MaillageZigbee/`) suit la même logique :
- avec Thread : le Recenseur (Bonjour), la sonde Thread (`SondeMaillage`, liaison USB ou UDP par Thread Route, clé
  d'accès réseau dans le trousseau), Thread Route ;
- avec Zigbee : le pont, la sonde Zigbee (`SondeMaillage`, machine d'états gardée telle quelle, voir 3.4) ;
- dans l'app commune : les vues, les Réglages, les notifications, les mises à jour, l'ouverture de session, et le
  **client du démon**, repris tel quel de Thread (`AbonnementPasseur`, `NomsInternes` : réabonnement 5, 10, 30 puis
  60 s, premier délai 2 min, garde de 2 min sur `relire`).

### 1.4 Hors Xcode

- `sonde-thread/` : firmware PlatformIO de la sonde Thread (1.1.1), avec ses tests.
- `sonde-zigbee/` : firmware PlatformIO de la sonde Zigbee (1.1.0), avec ses tests d'hôte C++ (`test/lancer.sh`,
  dont `test_demarrage`).
- Les deux firmwares restent **séparés, non fusionnés**. Ils sont recopiés tels quels, avec leurs outils de flash.
- `outils/thread-route/` : copie à l'identique du démon root qui garde la route IPv6 vers la sonde Thread (voir 5.3).
- `outils/` : publication, garde, anonymisation (dont `anonymiser-sonde.py`), traduction (`synchroniser-textes.sh`,
  `traduire.py`), tests (`tester.sh`), mesure (`mesurer.sh`, temps de la vue par pièces en Release), Passeur
  (`passeur.sh`, `verifier-passeur.py`), flash et clients de banc des deux sondes, écoute passive.

## 2. Identité des nœuds et données

### 2.1 `IdNoeud`

- **La clé d'un nœud est son identifiant actuel, inchangé, derrière le préfixe de son protocole** : forme texte
  `thread:<clé>` ou `zigbee:<clé>`. Le préfixe s'applique à l'étape 3, à la jonction des graphes dans la scène et dans
  les fichiers communs ; chaque module garde ses clés sans préfixe (ajustement du 14/10, section 6.4).
- **Zigbee** : la clé est l'adresse longue IEEE (16 chiffres hexadécimaux majuscules). Elle est stable.
- **Thread** : la clé est l'identifiant actuel du nœud dans le graphe, sous l'une de quatre formes :
  - l'**hôte Bonjour** d'un appareil, sans `.local` : souvent 16 chiffres hexadécimaux, mais pas toujours une ExtMac ;
  - `instance:<nom>` quand l'hôte est inconnu ;
  - l'**instance de service** d'un routeur de bordure, en texte libre ;
  - `rloc:<RLOC16>` pour un nœud que seule la sonde connaît.
- Surnoms, associations et pièces restent rangés par ces clés, comme aujourd'hui, désormais préfixées.
- **L'historique de la sonde Thread garde ses propres clés** (ExtMac ou `rloc:`), à l'intérieur du module :
  - `IdentitesGardees` garde la correspondance RLOC16 → ExtMac des routeurs (`identites-routeurs.json`), sans
    réécrire de fichier ;
  - `ClesHistorique` fond les clés à la lecture de l'historique ;
  - `Rapprochement` relie un nœud de la sonde à un routeur ou à un appareil du graphe.
  L'étape 1 garde ce fonctionnement à l'identique.
- **Les clés sont des données personnelles.** Une instance de routeur de bordure contient souvent un nom donné par
  l'utilisateur. Toute anonymisation (exports d'exemple, démo, relevés de test) traite **les clés autant que les
  valeurs**.
- **Un appareil n'est que sur une radio.** Il n'y a jamais de fusion de nœuds entre protocoles : le pont Hue
  (coordinateur Zigbee) et un routeur de bordure Thread restent des nœuds distincts, même s'ils sont dans la même
  pièce.
- **Les noms** viennent de Maison pour les deux protocoles, par **un seul relevé Passeur** partagé. Zigbee y ajoute
  les noms du pont et son appariement (`FusionNoms`).

### 2.2 Rangement

Dans le conteneur, sous `Application Support/Maillage IoT/` :

```
releve-maison.json        relevé du démon (un seul abonnement)
surnoms.json              surnoms, par IdNoeud
pieces-noeuds.json        pièces choisies pour les nœuds, par IdNoeud (remplace pieces-routeurs.json)
positions-pieces.json     disposition des pièces (les pièces viennent de Maison)
imports.json              exports déjà importés (identifiant de manifeste, date, source)
Journal/                  journal-AAAA-MM.jsonl, unique ; chaque événement porte son protocole
Thread/
  associations.json  identites-routeurs.json  dernier-maillage.json
  dernieres-adresses.json  maillage-AAAA-MM.jsonl
Zigbee/
  noms-pont.json  appariements-maison.json  dernier-maillage.json  maillage-AAAA-MM.jsonl
```

- **L'historique reste par protocole**, car les courbes en dépendent (dBm contre LQI). La **rétention est de
  90 jours** pour les deux.
- **La capture du relevé Bonjour** de Thread n'est pas rangée dans le conteneur : c'est un export que l'utilisateur
  enregistre par un panneau (Réglages > Diagnostic), comme aujourd'hui.
- **Chaque fichier JSON porte un champ `version`** ; chaque ligne JSONL porte le sien, ou en hérite d'une ligne
  d'en-tête (le plan choisit). Un format inconnu n'est jamais écrasé : il est laissé de côté et signalé au journal.

### 2.3 Trousseau et réglages

- **Trousseau**, services neufs : `fr.djoko.maillage.iot.sonde-thread` (et `.sonde-thread.udp`),
  `fr.djoko.maillage.iot.pont-hue`, `fr.djoko.maillage.iot.sonde-zigbee`. **La forme du compte de chaque élément
  est gardée** : l'IEEE de la sonde pour la clé de la sonde Zigbee, l'identifiant du pont pour la clé du pont, la
  forme actuelle pour la sonde Thread.
- **Les tests n'utilisent jamais le vrai trousseau** : le paramètre reste obligatoire, comme chez Zigbee.
- **UserDefaults** :
  - clés communes : interrupteurs de la vue, onglet des Réglages, repli de la légende, grille des étages, premier
    graphe ouvert, langue (`AppleLanguages`), notifications par catégorie ;
  - clés préfixées par module (`thread.`, `zigbee.`) pour le reste : sonde retenue (série, liaison, hôte), scissions
    notifiées, chemin et port de la sonde Zigbee, nom du Wi-Fi, budget de tournée (`sondeJournalPages`, pages des
    10 dernières minutes, et `sondePagesTables`, pages par table, gardés entre les lancements).
- **Le mot de passe Wi-Fi n'est jamais gardé**, et la clé de la sonde n'est jamais en clair hors de l'USB, comme
  aujourd'hui.

## 3. Interface

### 3.1 La vue par pièces

- **Les deux protocoles superposés.** La barre de la fenêtre porte deux interrupteurs, **Thread** et **Zigbee**. Ils
  sont mémorisés et tous deux allumés par défaut. Un protocole éteint dans la vue n'est que masqué : le module
  continue de tourner (voir 3.3 pour l'éteindre vraiment).
- **Le protocole se lit à la silhouette.** La grammaire actuelle de `DessinNoeud` est gardée : la forme dit le rôle
  (sphère brillante pour un routeur, pastille pour un appareil, anneau pour un appareil disparu), la couleur dit
  l'état, et les ornements sont inchangés (cercle bleu d'un routeur qui n'est pas de bordure, ondes de la sonde,
  anneau pointillé jaune, pastille de batterie).
  - Thread garde le **rond**.
  - Zigbee passe à l'**hexagone** : sphère facettée pour un routeur, pastille hexagonale pour un appareil, anneau
    hexagonal pour un appareil disparu.
  - Sur un hexagone, les ondes, la pastille de batterie et l'anneau pointillé se placent sur le **rayon
    circonscrit**, pour ne pas mordre sur les sommets. Un test de pixels le vérifie, comme celui des ondes
    aujourd'hui. Les traces des chemins et le focus partent du centre : rien ne change pour eux.
  - **Le pont Hue** devient hexagonal lui aussi, et garde son ornement de pont, pour qu'on ne le confonde pas avec un
    routeur de bordure Thread.
- **La couleur des liens donne la qualité**, en bandes communes (`BandeQualite`). Chaque protocole range ses valeurs
  avec son échelle.
- **La légende** gagne une ligne « ● Thread ⬢ Zigbee ». Le reste ne change pas, repli compris.
- **Disposition** : les nœuds des deux protocoles se partagent les pièces. Le rang et le rayon passent par le
  crochet de `ScenePieces`.

### 3.2 Fiche, focus, Identifier, Associer

- **La fiche en quatre colonnes** est commune. Son contenu propre au protocole passe par des crochets : courbes en
  dBm ou en LQI, adresse IPv6 ou IEEE, parent ou chemin vers le pont.
- **Le focus** passe par le module du nœud : chemins Zigbee vers le pont et dépendants, voisins entendus ; liens
  Thread et partition.
- **Identifier** passe par le module : la sonde ou Maison pour Thread, le pont ou Maison pour Zigbee.
- **Le menu « Associer »** (un appareil vers un accessoire de Maison) réunit les associations manuelles de Thread
  et l'appariement automatique de Zigbee (`FusionNoms` : mémoire → nom exact → nom souple → pièce et modèle), qui
  reste propre à Zigbee.

### 3.3 Les Réglages

- Fenêtre AppKit à onglets, animée comme aujourd'hui. Onglets : **Général · Notifications · Maison · Thread ·
  Zigbee · Diagnostic**.
- **Thread** : la sonde Thread (USB ou réseau), Thread Route, les pièces des routeurs.
- **Zigbee** : le pont Hue (appairage), la sonde Zigbee (Automatique, USB ou Wi-Fi, mise en service réseau par
  l'USB), le budget de tournée.
- **Chaque onglet de protocole commence par « Activer ce protocole ».** Éteint, le module ne fait plus rien : ni
  Bonjour, ni sonde, ni tournées, ni notifications. Ses nœuds disparaissent de la vue et son interrupteur de vue est
  grisé.
- **Un protocole actif qui ne trouve rien n'est pas une panne** (pas de pont, pas de routeur de bordure) : son
  onglet le dit, sans alerte ni notification.
- **Général** : langue, mises à jour, ouverture de session, « Reprendre des données… » (section 4).
- Le test de hauteur de la fenêtre (`ReglagesHauteurTests`, fenêtre hors écran) couvre les six onglets.

### 3.4 Les deux sondes

- Elles fonctionnent **en même temps**, chacune avec sa liaison et son service de trousseau. Elles ne partagent rien.
- **Aucun port USB inconnu n'est jamais ouvert.** D'autres cartes ESP32-C6 peuvent être branchées (les ponts d'autres
  projets). Ouvrir un port peut basculer DTR/RTS et réinitialiser une carte, et une réinitialisation USB après
  802.15.4 laisse le Wi-Fi d'une carte hors service (piège du 10/10). On garde donc la règle de Zigbee :
  - chaque module reconnaît sa sonde par son **numéro de série USB**, lu par `ioreg`, sans ouvrir le port ;
  - il n'ouvre que la carte retenue, ou celle que l'utilisateur choisit explicitement ;
  - une carte retenue par un module est retirée des choix de l'autre.
- **La machine d'états de la sonde Zigbee est gardée telle quelle** :
  - en mode Automatique, l'USB passe en premier ;
  - `injoignable` ; nouvel essai de l'USB espacé de 5 à 60 s ;
  - tournée relancée 30 s après `occupee` ; pas de mise en service pendant une tournée ;
  - liaison muette fermée après 6 ou 128 s ; entretien toutes les 180 s.
- La liste blanche des commandes réseau de la sonde Zigbee, l'enveloppe H1 et le budget de 550 pages par 10 minutes
  sont gardés tels quels.

### 3.5 Journal, notifications, menu de la barre

- **Le journal** est une seule fenêtre, avec les deux mêmes interrupteurs de filtre. Chaque ligne porte la marque de
  son protocole, et le regroupement des événements est commun.
- **Les notifications** : chaque protocole garde **ses catégories actuelles**. Zigbee a aujourd'hui celles de
  Thread (`routeurDisparu`, `pertes`, `informations`) ; Thread a en plus la scission. L'onglet Notifications les
  range par protocole, avec un interrupteur par catégorie comme aujourd'hui. De nouvelles catégories propres à
  Zigbee vont au backlog.
- **Le menu de la barre** : l'état de l'icône est le **pire des deux réseaux** actifs, avec une ligne de résumé par
  protocole actif.

### 3.6 Le mode démo

- Il combine les deux démos : le relevé de Thread et son scénario de panne, plus la démo de Zigbee.
- **Toutes les données de démo et de test repassent par l'anonymiseur**, clés comprises, avant leur premier commit
  dans `maillage-iot`.

## 4. La reprise

### 4.1 Le contrat d'export

- `ContratExport.swift` décrit le manifeste et les formats repris. Il est **identique à l'octet** dans
  `maillage-thread`, `maillage-zigbee` et `maillage-iot`, vérifié par `cmp`, comme `ProtocolePasseur.swift`.
- Chaque ancienne app produit dans ses tests un **export d'exemple anonymisé** (clés comprises), recopié dans les
  tests de Maillage IoT. Le format écrit et le format lu ne peuvent pas diverger sans qu'un test casse.

### 4.2 L'export (Thread 1.4.0 et Zigbee 1.2.0)

- **Un bandeau et une entrée de menu** : « Maillage Thread devient Maillage IoT » (ou Zigbee), avec le lien de
  téléchargement de Maillage IoT et « Exporter pour Maillage IoT… ».
- L'export écrit un **dossier**, à l'emplacement choisi dans un panneau d'enregistrement :
  - `manifeste.json` : format 1, identifiant unique d'export, app source et version, date, liste des fichiers avec
    taille et empreinte SHA-256 ;
  - une copie des fichiers de `Application Support/Maillage Thread/` (ou `Maillage Zigbee/`), historique compris,
    dont `noms.json` (le relevé Maison de Thread) ;
  - `reglages.json` : les UserDefaults utiles, sans les réglages de Sparkle. Pour Zigbee, il comprend le budget de
    tournée.
- **Aucun secret du trousseau** n'y figure.
- **L'export ne modifie rien** : l'ancienne app continue de marcher normalement.
- Une fois l'export réussi, l'ancienne app propose **« Ne plus ouvrir Maillage Thread à l'ouverture de session »**,
  pour que les deux apps ne se disputent pas la sonde USB au démarrage.
- **Le dépôt de Thread retire `outils/passeur.sh`** dans sa dernière version, et le remplace par un renvoi vers
  `maillage-iot` : relancé depuis l'ancien dépôt, il remplacerait le démon par une compilation plus ancienne.

### 4.3 L'import (Maillage IoT)

- **Au premier lancement**, un assistant propose « Reprendre depuis Maillage Thread ou Zigbee… ». La même entrée
  reste ensuite dans Réglages > Général, pour reprendre la seconde app.
- **Validation** : le manifeste est lu, le format reconnu et chaque empreinte vérifiée. Si une vérification échoue,
  rien n'est importé et la cause s'affiche.
- **Conversion** :
  - les fichiers communs et le journal reçoivent les **clés préfixées** (`thread:` ou `zigbee:`) ; les événements du
    journal reçoivent leur protocole ;
  - les fichiers propres à un module (historique de la sonde, identités, adresses, noms du pont, appariements) sont
    rangés dans `Thread/` ou `Zigbee/` sans changement de clé ;
  - `noms.json` de Thread devient `releve-maison.json`, sans préfixe (6.8, 3) ;
  - `pieces-routeurs.json` (des deux apps) devient `pieces-noeuds.json` ;
  - l'historique de plus de 90 jours est laissé de côté ;
  - les réglages repris sont rangés sous leurs nouvelles clés (2.3).
  - **`thread.sondeLiaison` est recopiée telle quelle, jamais remplacée par une valeur par défaut** : une préférence
    absente vaut Automatique (la sonde Thread la lit ainsi, et « Oublier » retire la clé) ; écrire `usb` ou un autre
    défaut à l'import figerait un choix que l'utilisateur n'a pas fait ;
  - **les clés de notification sont écrites par protocole** (`notification.<protocole>.<catégorie>`) : l'import les
    pose lui-même, ou passe avant `Notifications.reprendreClesCommunes` (qui recopie une clé commune sous la clé du
    protocole, sans jamais écraser une clé déjà écrite) ; sinon une catégorie coupée dans Thread 1.3.0 reviendrait au
    défaut ;
- **Atomicité** : l'import se fait dans un dossier d'attente, puis il est déplacé d'un coup. En cas d'échec, rien ne
  change.
- **Idempotence** : réimporter le même export ne fait rien de plus. Son identifiant de manifeste est gardé dans
  `imports.json`.
- **Clés du trousseau** (demande de Djoko, 14/10/2026, au banc de l'étape 2) : l'export n'en contient toujours
  aucune ; Maillage IoT les **lit directement dans l'ancien trousseau** (`TrousseauRepris`). Une clé absente du
  nouveau service est demandée **une seule fois** à l'ancien (Thread : `fr.djoko.maillage.sonde`, le transport UDP n'ayant pas de service propre ; Zigbee : `fr.djoko.maillage.zigbee.pont`,
  `fr.djoko.maillage.zigbee.sonde`) : macOS demande l'accord de l'utilisateur, l'élément appartenant à l'ancienne
  app. La clé est recopiée sous le nouveau service ; l'ancien élément n'est jamais modifié ni effacé, si bien que
  l'ancienne app garde son pont et son accès réseau à la sonde. Un refus, une clé absente ou « Oublier » ne
  redemandent plus rien, et l'appairage manuel (4.4) reste le secours. En place pour les deux protocoles : Zigbee
  depuis l'app de transition (étape 2, `TrousseauRepris`), Thread depuis le banc de l'étape 3a (15/10,
  `TrousseauReprisThread`). La liste des clés montre la clé de l'ancienne app sans la lire (attributs seuls), pour que le
  choix de la liaison par le réseau apparaisse ; la clé est reprise à la connexion.
- **Fichiers communs** (surnoms, positions des pièces, pièces des nœuds) : **le premier import l'emporte**. Un fichier
  déjà présent dans Maillage IoT (choix faits avant l'import) n'est jamais sauté : l'import y fusionne ce qui manque. Le second
  ne fait qu'ajouter ce qui manque, et le résumé dit ce qui a été ignoré. Les clés préfixées n'entrent jamais en
  collision.
- **Une ancienne app qui tourne encore** est signalée, et l'assistant propose de la quitter : une sonde USB ne peut
  avoir qu'un seul maître.
- **Le résumé final** dit ce qui a été repris et ce qui a été ignoré, puis donne la liste « À refaire » (4.4).

### 4.4 Ce qui se refait

- **Seulement si la reprise des clés (4.3) n'a pas abouti** (refus, clé absente, accès refusé par le bac à sable) :
  - appairer le pont Hue (appui sur son bouton) ;
  - brancher chaque sonde en USB pour sa mise en service réseau : une nouvelle clé est écrite dans la sonde et dans
    le nouveau trousseau. **L'ancienne clé est remplacée** : l'ancienne app perd l'accès réseau à la sonde (elle la
    voit « injoignable »). Le résumé le dit.
- Accepter les autorisations de macOS : réseau local et notifications.
- Ouverture de session : interrupteur de Maillage IoT.

## 5. Dépôt, publication et annonce

### 5.1 Anonymat dès le premier commit

**Avant tout commit :**
- l'identité git du dépôt sur l'adresse noreply de GitHub ;
- un `.gitignore` qui couvre `*.xcodeproj/`, `build/`, `DerivedData/`, `.superpowers/`, `.pio/`, `essais/`,
  `Local.xcconfig`, `garde.local.txt`, les fichiers `*.local.*` des sondes, les relevés et captures réels, et les
  fichiers de noms écrits par le démon ;
- la **garde `pre-push`**, installée tout de suite. C'est l'union des deux gardes actuelles : auteur noreply,
  `garde.py`, anonymisation du diff et des messages. Elle lit un `garde.local.txt` qui réunit les identifiants
  réels des deux réseaux **et le prénom réel de l'utilisateur**. Jamais de `--no-verify` ni de force push.

**Ensuite :**
- **Le code est recopié depuis les fichiers, jamais par fusion d'historique** : aucun commit, aucune date et aucun
  auteur des anciens dépôts n'entre dans `maillage-iot`.
- Chaque fichier recopié passe par la garde, commentaires compris. L'utilisateur s'y appelle **Djoko**.
- README bilingue : anglais d'abord, puis français, avec un lien vers chaque langue en tête. La description
  « About » du dépôt est en anglais. `NOTES-VERSIONS.md` contient, pour chaque version, un bloc **English** puis
  un bloc **Français**.
- Les commentaires du code restent sans accents ; les textes de l'interface ont leurs accents.

### 5.2 Publication

- **Maillage IoT 1.0.0** est signée Developer ID et notarisée avec le profil `djoko-notarisation`. L'identité est
  choisie par le préfixe « Developer ID Application ». Le titulaire et l'équipe sont masqués dans tout ce que les
  outils affichent. La méthode est celle de la fiche de passation d'Amaran, répétition de mise à jour comprise.
- `publication.py`, ses tests et la licence de Sparkle sont ceux de Thread, **identiques à l'octet** à ceux d'Amaran
  (un test le vérifie) ; `outils/publier.sh` est propre à Maillage IoT, avec le même cliquet de signature et les deux
  contrôles d'anonymisation (amendement du 18/10). (Le `publication.py` de Zigbee diffère sur trois lignes :
  il n'est pas repris.)
- **Le numéro de compilation** est le nombre de commits de `main`. L'identifiant est neuf, donc il n'y a aucun
  conflit avec les anciens flux. ~~Une compilation locale porte un numéro plus grand que la version publiée, sinon
  Sparkle la remplace (piège vu chez Zigbee).~~ (Remplacé le 18/10 : voir l'amendement à la fin de cette section.)
- **Sparkle** : nouvel `appcast.xml` à la racine de `main` de `maillage-iot`. Il est signé avec la **paire EdDSA
  commune** aux apps de Djoko (clé publique dans `project.yml`, clé privée dans le trousseau). Recherche au
  démarrage puis toutes les 24 h.
- **Droits de l'app** (bac à sable) : `network.client`, `network.server` (écoute sur 127.0.0.1, Bonjour),
  `device.serial` (sondes USB), `files.user-selected.read-write` (panneaux de capture, d'export et d'import), et les
  exceptions `mach-lookup` de l'installateur de Sparkle (`-spks`, `-spki`).
- **Info.plist** : `NSLocalNetworkUsageDescription`, sans quoi l'autorisation « réseau local » n'est jamais
  demandée ; `NSBonjourServices` : `_meshcop._udp`, `_matter._tcp`, `_hap._udp`, `_trel._udp` (Thread),
  `_hue._tcp` et `_maillage-zigbee._tcp` (Zigbee).
- **Les textes de l'interface** passent par **un seul mécanisme de traduction**. Thread utilise les catalogues
  `.xcstrings` ; chez Zigbee, `traductions/interface.json` est la source de `traduire.py`, et son `CataloguesTests`
  l'exige. Le plan de l'étape 1 compare les deux et en garde un, en migrant `CataloguesTests` en conséquence. Le
  test reste obligatoire : chaque texte en français et en anglais.

**Amendement du 18/10/2026 (phase 5, publication).** Il précise 5.2 et remplace la phrase barrée ci-dessus ainsi que la
ligne « Une compilation locale remplacée par Sparkle » de la section 7 :
- **Compilation de travail** : elle garde `CURRENT_PROJECT_VERSION "1"`, et Sparkle ne démarre pas à ce numéro
  (`MisesAJour.doitDemarrer`). Il n'y a plus de « numéro plus grand » à tenir pour une compilation locale : seule
  une version publiée porte le nombre de commits de `main`, posé par `publication.py`.
- **Étiquettes git** : `v` suivi du numéro de version (`v1.0.0`).
- **Enveloppe des contrôles d'anonymisation** : `outils/anonymisation_double.py` lance, l'un après l'autre et tous les
  deux, le contrôle privé de Maillage Thread et celui de Maillage Zigbee (mêmes chemins que `outils/pre-push`). Un seul
  en défaut, ou un contrôle ou une table introuvable, fait échouer la publication ; sa sortie ne montre que des comptes.
- **Répétition** : `outils/publier.sh` refuse, avant toute compilation, de publier l'identité de répétition (identifiant de
  la cible publiée terminé par `.repetition`). La signature Developer ID et la notarisation y sont imposées ; seule
  l'option `--repetition`, sans GitHub ni Bureau, peut signer autrement.
- **Droit d'Automatisation** : limité aux deux anciennes apps, par l'exception `apple-events` de `Droits.entitlements`
  (`fr.djoko.maillage` et `fr.djoko.maillage.zigbee`). Il ne sert qu'à les quitter avant la reprise (4.3) ; l'app ne
  peut piloter aucune autre app. `NSAppleEventsUsageDescription` le dit à l'utilisateur.

### 5.3 Le reste du système

- **Démon Passeur Noms et Masqueur** :
  - identifiant `fr.djoko.maillage.passeur`, contrat 1 et **ses deux schémas inchangés** : `maillage-passeur` et
    `maillage-passeur-1`, par lequel l'app le trouve. La clé `MaillagePasseurProtocole` de son Info.plist, lue par
    `passeur.sh`, est gardée. Les anciennes apps encore installées dépendent de tout cela ;
  - même App ID avec la capacité HomeKit, mêmes droits, même équipe et même profil d'un an : sinon HomeKit
    redemande l'accès, ou le refuse (« Entitlement not found ») ;
  - toujours signés en développement, jamais publiés en `.dmg` ni notarisés ;
  - installés par `outils/passeur.sh`, qui **refuse de remplacer un démon installé plus récent** que le sien ;
  - ils ne sont plus maintenus que dans `maillage-iot`.
- **Leçons du banc du 13/10 à garder** :
  - l'app lance le démon **sans URL** : elle vise le paquet trouvé par le schéma, vérifie s'il tourne en filtrant sur
    ce paquet, puis lui envoie l'URL ; elle affiche « ne démarre pas » après 10 s ;
  - elle le trouve par son schéma, jamais en lisant son paquet ;
  - nom affiché : le nom de la tuile de Maison pour un accessoire à une seule tuile ;
  - le démon se ferme si, l'accès à Maison étant accordé, aucun relevé `ok` n'est arrivé en 100 s.
- Le démon sert déjà plusieurs clients à la fois : la nouvelle app et les anciennes coexistent pendant la transition
  (à vérifier au banc, relances simultanées comprises).
- **Thread Route** : sa source fait foi dans le dépôt du pont Halo, et Halo Compagnon sait aussi l'installer.
  `maillage-iot` reprend le mécanisme actuel de copie à l'identique : `outils/thread-route.source`,
  `synchroniser-thread-route.sh` et l'empreinte de l'arbre. Il ne devient pas la source.

### 5.4 L'ordre de l'annonce

L'annonce doit pointer vers quelque chose qui existe :
1. Maillage IoT 1.0.0 est publiée : version GitHub et appcast.
2. Puis **Thread 1.4.0** et **Zigbee 1.2.0** sont publiées dans leurs propres flux, avec l'export et le bandeau qui
   renvoie vers la 1.0.0.
3. Les README des anciens dépôts reçoivent un bandeau « This project continues as Maillage IoT ».
4. **L'archivage des anciens dépôts sur GitHub** est demandé à Djoko à ce moment-là : c'est une action publique.
   Décision du 18/10 : les deux anciens dépôts restent en l'état, sans archivage.

## 6. Étapes, tests et rôles

### 6.1 Les étapes

Chaque étape se termine par un **banc avec Djoko**, puis une **relecture par Opus**. **Chaque étape a son propre
plan**, écrit au moment d'y entrer, avec ce que l'étape précédente a appris. Les cases des plans sont cochées au fil
de l'eau et commitées avec le travail.

| Étape | Contenu | Critère de sortie |
|---|---|---|
| **0. Préparation** | Les deux dépôts sont gelés : pas de nouvelle fonction. Zigbee a coché ses deux plans exécutés (fait le 13/10). Les états des lieux et les relectures vont dans `.superpowers/fusion/` (hors git). **Références de rejeu** : dans `maillage-thread`, un test (pas une fonction de l'app) construit le graphe affiché (nœuds, liens, pièces) à partir de la démo et des captures existantes, et l'écrit en JSON trié, commité comme résultat de référence. Squelette de `maillage-iot` : identité noreply, `.gitignore`, garde pre-push, `project.yml` vide, README bilingue. Cette spec est le premier commit. | La garde refuse un push qui contient un identifiant réel planté exprès (dont le prénom réel), puis l'accepte une fois l'identifiant retiré. Le résultat de référence de Thread est commité. |
| **1. Cœur neutre + Thread à l'identique** | Recopie de Thread sous l'identité Maillage IoT (cibles, identifiants, dossier de données, trousseau, textes), démon, outils, firmware `sonde-thread/` et copie de Thread Route ; extraction de `MaillageCoeur` neutre et de `ProtocoleThread` (journal neutre : `TypeEvenement` ouvert) ; le code de l'app propre à Thread reste dans la cible de l'app, sous `Thread/` (section 6.4). | Tous les tests de Thread passent. **Rejeu exact** : la scène de la démo est égale au résultat de référence `docs/rejeu/thread-demo.json`, à chaque tâche. Le cœur compile et se teste seul, sans `ProtocoleThread`. Au banc, Thread 1.3.0 et Maillage IoT ouverts côte à côte, abonnés au même démon, montrent la même vue. |
| **2. Zigbee branché** | Avant l'étape : dans `maillage-zigbee`, un test (pas une fonction de l'app) écrit en JSON trié la scène de la démo de Zigbee 1.1.1 (`docs/rejeu/zigbee-demo.json`), commité comme résultat de référence (ajustement du 14/10, section 6.5). Puis les enums unifiés (`injoignable`, lien `.chemin`, section 1.2) et `ProtocoleZigbee` sur l'interface : pont Hue, sonde Zigbee, `FusionNoms`, mémoire des appariements. **`SondeMaillage` n'est pas découpé** pendant cette étape. | Tous les tests de Zigbee passent. **Rejeu exact** : la scène de la démo de Zigbee dans Maillage IoT est égale à la référence, à chaque tâche. Au banc, Zigbee 1.1.1 et Maillage IoT (Zigbee seul) ouverts côte à côte montrent la même vue. |
| **2 bis. Découpe des deux `SondeMaillage`** | Les deux fichiers dépassent 700 lignes. Ils sont découpés dans un plan à part, sous les mêmes tests, une fois le banc de l'étape 2 passé. | Mêmes tests, mêmes rejeux, aucun changement de comportement. |
| **3. Interface à deux protocoles** | Préfixe des identifiants (`IdNoeud`) à la jonction des graphes et dans les fichiers communs ; vue A (silhouettes, interrupteurs, bandes de qualité, légende), Réglages à six onglets, « Activer ce protocole », deux sondes en même temps, journal et notifications communs, menu de la barre, démo combinée. | Au banc, les deux réseaux réels sont affichés ensemble. Le temps d'ouverture de la vue (`mesurer.sh`) et la fluidité du zoom sont mesurés, avec Thread seul de l'étape 1 comme référence. Les places de la sonde Zigbee (3 places TCP, 2 sessions H1) sont observées avec l'ancienne app ouverte en même temps. |
| **4. Reprise** | `ContratExport` dans les trois dépôts. Export dans Thread 1.4.0 et Zigbee 1.2.0 (dans leurs dépôts). Import dans Maillage IoT. | Tests d'import sur les deux exports d'exemple. **Répétition sur une copie** (identifiant et services de trousseau de test) avec les vraies données de Djoko, avant la vraie reprise. |
| **5. Publication** | Maillage IoT 1.0.0, puis Thread 1.4.0 (sans `passeur.sh`) et Zigbee 1.2.0, puis les bandeaux des README, puis l'archivage avec l'accord de Djoko. | La 1.0.0 s'installe et se met à jour par Sparkle (répétition de mise à jour). Les anciennes apps annoncent et exportent. |

L'export dans les anciennes apps (étape 4, côté anciens dépôts) peut avancer **en parallèle** des étapes 2 et 3.

**Feuille de route** (une phase par étape ; les plans s'appellent `…-phase-N.md`, avec un suffixe de lettre pour les
plans d'une même phase). L'ancienne « étape 2 bis », la découpe des deux `SondeMaillage`, se fait après l'étape 3b
(6.6) : elle devient le troisième plan de la phase 3, `phase-3c`.

- [x] Phase 0 : préparation
- [x] Phase 1 : cœur neutre et Thread à l'identique
- [x] Phase 2 : Zigbee branché
- [x] Phase 3 : interface à deux protocoles (3a une seule app, 3b la vue A et l'interface commune, 3c la découpe des deux `SondeMaillage`)
- [x] Phase 4 : reprise
- [x] Phase 5 : publication
- [x] Phase 6 : panneau de santé dans la vue par pièces (conception du 19/10 : `2026-10-19-panneau-sante-design.md`)
- [x] Phase 7 : pièce proposée aux HomePod et à l'Apple TV par leur annonce AirPlay (conception du 19/10 : `2026-10-19-piece-airplay-design.md`)
- [x] Phase 8 : clés `rloc:` de Thread qualifiées par la partition en cas de collision (décisions du 20/10 : seulement entre partitions actives en même temps, tenante stable pendant la scission, fin après trois relevés sans scission)
- [x] Phase 9 : le journal nomme la pièce de l'appareil en français naturel (décisions du 20/10)
- [x] Phase 10 : une pièce dans plusieurs zones de Maison va dans la plus précise, et se range au clic droit (décisions du 20/10)
- [ ] Phase 11 : une transition en un seul mouvement quand une pièce change de plateau, et les autres étages gardent leur place après un choix fait dans la vue (banc et décisions du 21/10)

### 6.2 Les tests

- **Tous les tests existants suivent leur code** :
  - Thread : environ 495 tests du cœur, 476 de l'app et 51 du démon, plus les tests Python (`outils/tests`), ceux du
    firmware (`sonde/test`) et ceux de Thread Route (`outils/thread-route/tests.sh`) ;
  - Zigbee : 341 tests du cœur et 448 de l'app, dont `TourneeSondeTests`, `SondeParReseauTests`,
    `AffichageSondeTests`, `IdentifierMaisonTests`, `ReglagesHauteurTests` et `FusionNomsTests`, plus les tests de la
    publication et de la garde (`outils/test`) et les tests d'hôte du firmware (`sonde/test/lancer.sh`).
- **La neutralité du cœur** est imposée par les dépendances des cibles (1.1).
- **Les tests de rejeu** (étapes 1 et 2) comparent le graphe de Maillage IoT aux résultats de référence des anciens
  cœurs. Les entrées réelles restent locales, hors git ; seule une version anonymisée, clés comprises, entre dans un
  dépôt.
- **L'import** est testé sur les exports d'exemple des deux anciennes apps : conversion des clés, fusion des fichiers
  communs, idempotence, refus d'un manifeste altéré.
- **`ContratExport.swift` et `ProtocolePasseur.swift`** sont vérifiés à l'octet entre les dépôts.
- **`CataloguesTests`** reste obligatoire, et `publier.sh` lance toute la batterie avant chaque publication.

### 6.3 Qui fait quoi

- **La session de fusion** (celle qui a écrit cette spec) orchestre : un plan par étape, la coordination avec les deux
  sessions, les relectures d'étape et le cochage des plans.
- **Le travail dans `maillage-iot`** est fait par des **sous-agents neufs**, tâche par tâche : Haiku pour les
  recopies à l'octet, Sonnet pour l'implémentation et la relecture de tâche, Opus pour la relecture finale de chaque
  étape.
- **Les sessions Thread et Zigbee** n'interviennent qu'à quelques moments, car leur contexte est lourd :
  - la relecture de cette spec (faite le 13/10) ;
  - les références de rejeu dans leur dépôt (étape 0 pour Thread, avant l'étape 2 pour Zigbee) ;
  - l'export et la dernière version dans leur dépôt (étapes 4 et 5).
  Pas de petites retouches entre-temps.
- **Le coût en jetons** de chaque étape est annoncé à Djoko avant son lancement. L'étape 1 est la plus lourde
  (environ 120 fichiers Swift déplacés ou découpés).

### 6.4 Ajustements du 14/10 pour l'étape 1

Validés par Djoko le 14/10, après l'inventaire du code de Thread :
1. **Le préfixe des identifiants (`IdNoeud`) passe à l'étape 3.** Dans Thread, les identifiants servent de clés partout
   (surnoms, pièces choisies, associations, noms des routeurs, recherches de la surveillance). Le préfixe n'a de sens
   qu'à la jonction de deux graphes ; le rejeu de l'étape 1 est donc exact, sans préfixe.
2. **Les enums unifiés** (`injoignable`, lien `.chemin`) arrivent à l'étape 2, avec Zigbee.
3. **Le code de l'app propre à Thread** (Recenseur, sonde série et UDP, Thread Route, textes des événements, marque
   Thread) reste dans la cible de l'app, rangé sous `MaillageIoT/Thread/` : il dépend d'AppKit et d'IOKit, et ses
   textes vivent dans le catalogue de l'app. `ProtocoleThread` reçoit la logique du cœur (30 fichiers et les coupes).
4. **Le journal devient neutre** : `TypeEvenement` passe d'un enum fermé à un type ouvert ; le cœur ne déclare que
   les types neutres, `ProtocoleThread` déclare les siens. Les fichiers `journal-*.jsonl` existants restent lisibles
   à l'identique.
5. **La publication** (`publier.sh`, `publication.py` et leurs tests) n'est recopiée qu'à l'étape 5.
6. **Le banc de l'étape 1 est visuel**, côte à côte, Thread 1.3.0 et Maillage IoT abonnés au même démon. L'équivalence
   du traitement est prouvée par le rejeu de la démo.
7. **Seules les données de `docs/` que lisent les tests sont recopiées** : `docs/rejeu/thread-demo.json`,
   `docs/releves/2026-09-28/capture-1228.json` et `docs/releves/2026-09-29/` (capture anonymisée de la sonde et son
   README).

### 6.5 Ajustement du 14/10 pour l'étape 2

Validé par Djoko le 14/10 : comme pour Thread (6.4, point 6), la référence de rejeu de Zigbee est la scène de sa démo,
et le banc est visuel, côte à côte. L'enregistrement d'une tournée réelle et des réponses brutes du pont n'est pas fait.

Validé par Djoko le 14/10, après l'inventaire de l'app Zigbee : le code d'app de Zigbee recouvre celui de Thread (30 fichiers
de même nom au contenu différent, 121 noms de types communs). Les fondre est le travail de l'étape 3. À l'étape 2, le code
d'app de Zigbee entre donc dans une **cible d'app temporaire**, « Maillage IoT Zigbee » (`MaillageIoTZigbee/`, identifiant
`fr.djoko.maillage.iot.banc-zigbee`, jamais publiée, sans Sparkle), qui compile par-dessus `MaillageCoeur` et
`ProtocoleZigbee`. Elle porte déjà l'identité définitive de Zigbee (services de trousseau, clés `zigbee.`, sous-dossier
`Zigbee/`), porte le rejeu de la démo Zigbee et sert au banc. Elle disparaît à l'étape 3, quand les deux apps se fondent.
L'étape 2 reste un seul plan.

### 6.6 Ajustements du 14/10 pour l'étape 3

Validés par Djoko le 14/10 :
- **L'étape 2 bis passe après l'étape 3** : l'étape 3 déplace les deux `SondeMaillage` sans les fondre ; la découpe se
  fait à leur place définitive, sous les tests de l'app unique.
- **L'étape 3 se fait en deux plans, chacun avec son banc et sa relecture par Opus** :
  - **3a, une seule app** : `IdNoeud`, fichiers communs, une `Surveillance` qui porte les deux protocoles, fusion des
    deux cibles d'app (la cible temporaire disparaît), jonction des graphes dans la scène avec le dessin actuel,
    Réglages à six onglets, « Activer ce protocole », deux sondes en même temps, journal unique. Sortie : tous les
    tests passent, les deux rejeux restent exacts (chaque démo calculée avec l'autre protocole éteint) ; au banc, les
    deux réseaux réels s'affichent ensemble et les deux sondes tournent en même temps.
  - **3b, la vue A et le reste de l'interface** : silhouettes (hexagone de Zigbee), interrupteurs de vue, bandes de
    qualité, légende, filtres et marques du journal, catégories de notification par protocole, menu de la barre
    (pire des deux réseaux), démo combinée et sa référence, icône sans badge, « Identifier par Hue ». Sortie : celle
    de l'étape 3 en 6.1 (mesures, places de la sonde Zigbee).

Décisions du plan 3a, d'après les inventaires `inventaire-etape3-*.md` (proposées par l'orchestrateur avec le plan) :
1. **`IdNoeud` est typé dès la sortie du graphe de chaque module** : `GrapheReseau.Noeud.id`, les bouts des liens,
   `AppareilAffiche.id` et les types de la scène du cœur. Un oubli ne compile pas. Les modules gardent leurs clés
   internes en texte brut. Forme texte `<protocole>:<clé>`, coupée au premier `:` seulement.
2. **Restent bruts** (précise 1.2 et 4.3) : `noeudMatter` et l'`id` HomeKit (`releve-maison.json` ne change que de
   nom), les clés d'historique, les clés de pièce et d'étage (dont `routeur:<clé>` dans `positions-pieces.json`), les
   partitions (le protocole est porté par le nœud ; Zigbee garde sa partition `zigbee`).
3. **Journal** : `Sujet.id` reste brut, chaque `Evenement` gagne `protocole` ; une ligne sans protocole est de Thread
   (journaux de Maillage IoT avant 3a, et de Maillage Thread). La politique du journal est composée par protocole.
4. **`associations.json`** reste au module Thread, clés brutes, avec un champ `version`.
5. **Fichiers communs versionnés** : `surnoms.json` version 1 (`{version, surnoms}` par `IdNoeud`), qui lit encore
   l'ancien format plat (clés de Thread) ; `pieces-noeuds.json` version 2. La version des JSONL est fixée à l'étape 4,
   avec le contrat d'export.
6. **Une seule `Surveillance`** : une coque commune (journal, surnoms, veille) et deux modèles de protocole,
   `SurveillanceThread` et `SurveillanceZigbee` (la forme de `ProtocoleMaille`), chacun avec ses seuils de fraîcheur.
7. **Le client du démon commun est celui de Zigbee** (`NomsPasseur`, fichier `releve-maison.json`).
8. **Rangement** : les fichiers de Thread passent sous `Thread/` (2.2). Le conteneur de développement n'est pas migré.
9. **Un seul catalogue de textes**, union des deux ; pour les 7 clés traduites différemment, la traduction de Thread
   (déjà publiée), revue au banc de 3b.
10. **Réglages** : six onglets, sans nouveau réglage (les pièces des routeurs et le budget de tournée restent sans
    réglage visible, comme aujourd'hui).
11. **« Activer ce protocole » arrête vraiment le module** : sonde, Bonjour ou pont, tournées, notifications. Le
    client du démon reste abonné, même avec les deux protocoles éteints.
12. **Reportés à 3b** : « Identifier par la sonde » pour Thread et « Associer » pour Zigbee n'existent pas
    aujourd'hui ; 3b dira s'ils sont créés ou laissés au backlog.

### 6.7 Ajustements du 15/10 pour l'étape 3b

Validés par Djoko le 15/10 (banc de l'étape 3a et questions du plan 3b) :
- **Routeurs Zigbee en violet**, en plus de l'hexagone ; le pont Hue aussi, avec sa couronne. Les routeurs de bordure
  Thread gardent le bleu.
- **Hexagone pointe en haut**, sommets sur le rayon du nœud (cercle circonscrit) ; ondes, pile, anneau pointillé et
  anneau de sélection restent ronds, au-delà du rayon.
- **Interrupteurs de vue dans la capsule de gauche**, après le nom de la maison : « ● Thread ⬢ Zigbee ». Masquer un
  protocole **recompose la vue** sans lui (choix de Djoko au banc de 3b, 16/10, à la place du masquage stable) : les
  pièces et les nœuds se replacent ; la fiche ou le focus d'un nœud masqué se ferment. Un protocole éteint dans les Réglages y est grisé.
- **En haut à gauche, le nom de la maison** (Maison) ; son menu liste les réseaux par protocole : Thread (réseaux,
  partitions, choix du réseau affiché), puis Zigbee (le pont).
- **Onglets Thread et Zigbee** : logos redessinés en vectoriel monochrome, en images modèles (teinte du système) ;
  crédits des marques dans le README bilingue.
- **Icône sans badge**, générée par un outil du dépôt : une constellation qui mêle nœuds ronds et hexagonaux, à toutes
  les tailles du Dock ; la barre des menus garde le seul symbole du maillage.
- **Journal** : interrupteurs Thread / Zigbee propres au journal (mémorisés), indépendants de la vue ; chaque ligne
  porte la marque de son protocole (● ou ⬢, dans sa couleur).
- **Démo** : `-demo` lance la démo combinée ; `-demo-thread` et `-demo-zigbee` gardent chacune la sienne seule (les deux
  rejeux exacts). Dans la seule démo combinée, la démo Zigbee est recalée sur l'horloge de celle de Thread et les
  homonymes sont renommés ; la scène combinée a sa propre référence, `docs/rejeu/maillage-iot-demo.json`, écrite une
  fois puis jamais régénérée.
- **Liaison « Automatique » pour la sonde Thread** (USB d'abord, sinon le réseau Thread), en miroir de Zigbee :
  dernière tâche de 3b, avec sa relecture Opus. Défaut des nouvelles installations ; un choix existant est gardé.
- **« Identifier par la sonde »** (Thread) est abandonné : impossible sans contrôleur Matter (précise 3.2). **« Associer »**
  pour Zigbee va au backlog.

Décisions du plan 3b (proposées par l'orchestrateur avec le plan) :
1. La légende montre la ligne « ● Thread ⬢ Zigbee » seulement quand les deux protocoles sont dans la scène ; ses entrées
   communes (joignable, disparu, sonde) restent rondes.
2. `NiveauQualite` du cœur devient la bande commune (`BandeQualite`) ; `EchelleSignal` range une valeur en bande ; le 0
   de Thread reste gris, comme aujourd'hui.
3. Toute lecture d'horloge d'un nœud passe par l'horloge de son modèle (démo combinée : deux horloges cohérentes).
4. Notifications : clés `notification.<protocole>.<catégorie>`, qui reprennent la valeur des clés communes actuelles ;
   l'onglet les range par protocole ; mêmes défauts qu'aujourd'hui.
5. L'onglet d'un protocole éteint est grisé, sauf « Activer ce protocole » (règle unique pour les deux sondes).
6. Mesures : avant de toucher la vue, la référence de l'étape 1 (Thread seul) est relevée sur `e32f3a5` dans une
   copie de travail à part ; l'outil mesure l'ouverture de la vue et le zoom ; la mesure finale la compare.

### 6.8 Ajustements du 17/10 pour la phase 4 (reprise)

D'après l'inventaire des formats (`.superpowers/fusion/inventaire-phase-4.md`), proposés avec le plan de la phase 4 :
1. **`ContratExport.swift` vit dans le cœur**, autonome comme `ProtocolePasseur.swift` (Foundation et CryptoKit seulement), recopié à
   l'octet dans les deux anciennes apps ; un script de contrôle le compare par `cmp` quand les autres dépôts sont là.
2. **Les lignes JSONL ne changent pas** (journal et historiques) : le manifeste porte la version du format ; seule
   exception, chaque ligne du journal de Zigbee 1.1.1 reçoit `"protocole":"zigbee"` (sans quoi elle serait lue comme
   Thread).
3. **`noms.json` de Thread devient `releve-maison.json` sans préfixe** (précise 4.3 : le relevé ne contient aucun
   identifiant de nœud du graphe). Le relevé est un cache du démon : le plus récent l'emporte (celui déjà présent
   ou celui de l'import).
4. **Fichiers communs** : `surnoms.json` (version 1) et `pieces-noeuds.json` (version 2) sont écrits par l'import
   avec leurs clés préfixées, jamais déposés tels quels ; `positions-pieces.json` se fusionne en profondeur (maison,
   étage, pièce) ; le premier import l'emporte, le second ajoute ce qui manque.
5. **L'historique de plus de 90 jours** est écarté par fichier mensuel entier (comme la purge) ; le journal importé
   est ajouté et trié à la lecture.
6. **Après un import réussi, l'app se relance d'elle-même** (ses modules lisent leurs fichiers au lancement).
7. **La répétition** se fait avec une identité de test (« Maillage IoT Répétition », identifiant, conteneur et
   services de trousseau à part, sans Sparkle, jamais publiée), sur une copie des vraies données.
8. Les réglages `liensMontres` et `voisinsALaSelection` restent propres à Zigbee (`zigbee.`), comme le code (précise 2.3).

## 7. Risques et parades

| Risque | Parade |
|---|---|
| Une erreur de clé casse l'historique et les noms gardés | Clés actuelles inchangées derrière un préfixe (2.1) ; historique de la sonde laissé dans son module ; tests de conversion à l'import ; rejeu aux étapes 1 et 2 |
| Un cœur rempli de `if zigbee` | Le cœur ne dépend d'aucun module (cibles) ; un crochet par écart (1.3) |
| Un diff impossible à relire | Une étape à la fois, chacune avec son plan, son banc et sa relecture ; Thread d'abord, à l'identique ; découpe des sondes à part (2 bis) |
| Le contrat du démon touché par mégarde | `ProtocolePasseur.swift` vérifié à l'octet ; démon recopié tel quel, deux schémas et clé d'Info.plist compris |
| Un ancien dépôt réinstalle un démon plus ancien | `passeur.sh` retiré de Thread 1.4.0 ; celui de `maillage-iot` refuse de remplacer un démon plus récent |
| HomeKit refuse le démon recompilé | Même App ID, mêmes droits, même équipe, même profil (5.3) |
| Une carte réinitialisée par l'ouverture d'un port USB | Reconnaissance par numéro de série sans ouvrir le port ; seule la carte retenue ou choisie est ouverte (3.4) |
| Les deux sondes ou les deux apps se disputent une sonde | Carte retenue retirée des choix de l'autre module ; ancienne app signalée à l'import ; ouverture de session coupée après l'export ; places TCP et H1 observées au banc |
| L'ancienne app perd sa sonde après la reprise | Le résumé de l'import le dit (4.4) |
| La vue surchargée avec deux maillages | Interrupteurs de vue ; silhouette par protocole ; mesure au banc (étape 3) |
| La vue ralentie | Cœur et modules en `-O` même en Debug ; mesure avec `mesurer.sh` contre la référence de l'étape 1 |
| Une compilation locale remplacée par Sparkle | Compilation de travail au numéro 1, où Sparkle ne démarre pas (amendement du 18/10, 5.2) |
| Une donnée réelle dans le dépôt | Garde dès le premier commit, prénom réel compris ; recopie fichier par fichier ; anonymisation des clés autant que des valeurs ; `garde.local.txt` commun |
| L'annonce qui pointe dans le vide | Ordre de publication de 5.4 |

## 8. Backlog

- Autres protocoles : Wi-Fi, Matter sur Wi-Fi, BLE. L'interface « réseau maillé » les accueillera.
- Catégories de notification propres à Zigbee (parent perdu, pont injoignable).
- « Identifier les candidats » dans le menu d'association (proposé chez Thread, gelé jusqu'à la fusion).
- Mineurs reportés de Zigbee : pertes de parent de la sonde non journalisées (la nuit de comparaison du plan Wi-Fi
  est restée partielle), messages neutres affichés en rouge.
- « Associer » pour Zigbee : associer à la main un appareil du pont à un accessoire de Maison (écriture dans
  `MemoireAppariements`), à côté de l'appariement automatique (étape 3b, 15/10).
- Fusion des deux firmwares de sonde, si un jour une carte porte les deux radios.
- **Contrôle de taille avant lecture dans le contrat d'export** (mineur m1 de la relecture finale de la phase 4,
  18/10) : `manifeste.json` et `reglages.json` sont lus en entier avant tout contrôle de taille, si bien qu'un export
  abîmé ou trafiqué de plusieurs Go ferait tomber l'app au lieu de donner une cause lisible (rien n'est écrit). À faire :
  comparer la taille du fichier à celle du manifeste avant lecture, et borner `manifeste.json`. À grouper avec le prochain
  changement du contrat, qui doit rester identique à l'octet dans les trois dépôts.
- **Repris du backlog de Maillage Zigbee** (transmis par sa session le 18/10, sans valeur réelle) :
  - **Chiffrement des échanges réseau des sondes** (Zigbee et Thread), aujourd'hui signés (enveloppe H1) mais non
    chiffrés : TCP chiffré par TLS-PSK à la place de H1, approche B retenue le 11/10, commune à Zigbee, Thread, au pont
    Halo et à Amaran (aussi transmis par la session Thread : hypothèse à étudier, rien de prévu).
  - **Dossiers temporaires « pont-… » laissés par les tests** dans le conteneur de l'app (l'app sert d'hôte de tests) :
    les nettoyer dans les tests.
  - **Bancs jamais faits** : reconnexion après une veille du Mac de plus de 10 min (session H1 oubliée par la carte) ;
    export vers un autre volume (clé USB) ; renommage de la sonde par la commande `nom` (l'annonce Bonjour doit suivre) ;
    « 5e client servi après environ 25 s », à remesurer.
  - **App, sonde Zigbee** : « Régénérer la clé » grisé sans raison visible quand la sonde est en Wi-Fi ; reconnexion sans
    délai si la sonde coupe juste après la poignée de main ; branche réseau de `reevaluer` sans la garde
    `!versUnAutrePort` ; adresse longue gardée si l'annonce Bonjour d'une autre sonde n'en a pas.
  - **Firmware de la sonde Zigbee** : le nom DHCP ne suit pas un renommage ; `suspendre` par l'USB pendant l'attente du
    Wi-Fi répond « occupee » alors que la suspension est enregistrée ; `CleSonde.cle` en clair dans un struct `Hashable`
    (la masquer dans `description`).
  - **Export (code des anciennes apps, si un jour il est repris dans Maillage IoT)** : « Quitter » reste actif pendant un
    export (dans un cas rare, l'ancien export reste caché dans le dossier temporaire) ; quand un ancien dossier n'est pas
    restauré, l'alerte donne le chemin sans bouton « Afficher dans le Finder ».
- **Repris de Maillage Thread** (transmis par sa session le 18/10) : vérifier de bout en bout le démarrage de Passeur Noms
  à l'ouverture de session, dernière case ouverte du plan du démon (banc 4) : interrupteur « Ouvrir Passeur Noms à
  l'ouverture de session », macOS montre « Élément d'arrière-plan ajouté », puis fermeture et réouverture de session : le
  démon doit tourner. Jamais fait jusqu'au bout (Réglages › Maison affichait « connecté »). À faire au prochain
  redémarrage du Mac, avec le démon 2.1 installé le 18/10.
- **L'app réelle gêne la suite de tests** (constat du 19/10) : `NomsPasseurTests.abonnementEtReleves` dépasse ses 60 s
  quand Maillage IoT tourne sur le Mac pendant `outils/tester.sh` (verte app fermée). Isoler le faux démon du test du vrai
  (port, schéma ou nom de service), ou faire refuser la porte tant que l'app tourne.
- **Charge du processeur de l'app réelle** (constat du 19/10) : Maillage IoT 1.0.0 à environ 70 % d'un cœur en continu,
  pendant des heures. Mesurer fenêtre de la vue par pièces ouverte et fermée (rendu 3D, rotation lente), puis corriger.
