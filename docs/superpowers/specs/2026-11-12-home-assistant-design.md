# Maillage IoT et Home Assistant : conception

**Date :** 12/11/2026. **Pour :** Djoko. **Statut :** à valider.
**Spec principale :** `2026-10-13-maillage-iot-design.md` (architecture, `IdNoeud`, trousseau). Cette conception y
ajoute les phases 12 à 14 (section « Feuille de route », en fin de document).

## 1. Pourquoi

Djoko a fait de Home Assistant (HA) le centre de sa maison, à la place de l'app Maison. Il a donné à HA les identifiants
du réseau Thread d'Apple : il ajoute maintenant des appareils Thread par HA, sans passer par Maison. Trois manques en
découlent.

1. **Un appareil ajouté par HA n'apparaît pas.** Cas réel : une carte ESP32-H2 sous ESPHome, sur Thread. Elle n'est ni
   Matter ni HomeKit : elle ne s'annonce qu'en `_esphomelib._tcp`, que l'app n'écoute pas.
2. **Le contrôleur Matter de HA apparaît comme un appareil inconnu**, dans la liste « Appareils IP », sous un
   identifiant de 16 chiffres hexadécimaux. Djoko l'a pris pour le nouvel appareil.
3. **Les noms, les pièces et les étages ne viennent que de Maison**, par Passeur Noms. Ceux que Djoko tient maintenant
   dans HA ne servent pas.

But : HA devient une seconde source de noms, de pièces et d'étages, au choix de l'utilisateur, et les appareils Thread
que HA ajoute apparaissent sur la carte.

## 2. Objectifs, non-objectifs, anti-objectifs

**Objectifs**
- Les appareils ESPHome sur Thread apparaissent sur la carte, nommés par leur annonce.
- Le contrôleur Matter de HA est nommé comme tel dans « Appareils IP ».
- L'app se connecte à HA par la page de connexion de HA, avec un jeton collé en secours.
- Deux réglages indépendants : « Noms » (Maison ou Home Assistant) et « Pièces et étages » (Maison ou Home Assistant).

**Non-objectifs** (hors de ce projet)
- L'accès à HA hors du réseau local (Nabu Casa, `external_url`).
- Plusieurs instances de HA.
- « Identifier » par HA, les piles lues dans HA, les associations à la main avec un appareil de HA. Ces trois
  capacités restent à Maison (Passeur Noms) et au pont Hue (§ 7.3).
- Les appareils ESPHome en Wi-Fi ou en Ethernet.
- Une clé HomeKit (HAP) pour le rapprochement : aucun appareil HomeKit sur Thread n'est annoncé chez Djoko (§ 4). Elle
  s'ajoutera quand un cas existera.
- HTTPS avec un certificat auto-signé.

**Anti-objectifs** (un échec, même si tout le reste marche)
- HA devient nécessaire : sans HA, l'app se comporte exactement comme aujourd'hui.
- Un secret sort du trousseau : journal, préférences, fichier, capture, rapport de plantage, URL, message d'erreur.
- L'app écrit dans HA. Seule exception : la révocation de son propre jeton, à la déconnexion.
- Un nœud que la source choisie ne connaît pas prend le nom ou la pièce de l'autre source.
- Les noms passent d'une source à l'autre pendant une reconnexion.
- L'app relance sans fin un jeton refusé : HA compte les échecs d'authentification, et peut bannir l'adresse qui les
  répète, selon ses réglages.
- L'app écoute un port local pour la connexion (voie C, écartée).

## 3. Ce qui existe

Constaté dans le code au commit `46cdd7f`.

- **Recensement Bonjour** (`MaillageIoT/Thread/Recenseur/`) : `_meshcop._udp`, `_matter._tcp`, `_hap._udp`,
  `_trel._udp`, `_airplay._tcp`. Le relevé (`Annonces`) garde, par type, les instances résolues. Celles d'AirPlay n'y
  gardent que `model` (minimisation). Une capture ancienne se relit, et une capture sans AirPlay garde ses octets.
- **Instantané** (`ProtocoleThread/Instantane/`) : les instances regroupées par hôte font un `Appareil` (id = hôte sans
  `.local`). Son genre vient de ses adresses :
  - `thread` : une adresse dans un préfixe OMR ;
  - `ip` : des adresses du réseau local seulement ;
  - `sansAdresse` : aucune adresse.

  Les appareils `ip` forment `appareilsIP`, la liste « Appareils IP ».
- **Noms**
  - `ResolveurNoms` (Thread) : surnom > accessoire de Maison > nom HomeKit > identifiant. L'accessoire de Maison se
    trouve par le nœud de l'appareil sur la fabrique d'Apple, que l'app déduit par recouvrement, puis par une
    association faite à la main.
  - `FusionNoms` (Zigbee) : le pont Hue donne les appareils. Maison donne le nom et la pièce de ceux qu'il retrouve, par
    une suite d'appariements par nom (mémoire, nom exact, nom souple, pièce et modèle). Les autres gardent les noms de
    l'app Hue (`origine`).
- **Pièces et étages**
  - `LibellesNoeuds.pieces` et `PiecesRouteurs` : les choix « Placer dans une pièce… », gardés par domicile dans
    `pieces-noeuds.json`.
  - `EntreeScene` : le domicile, les zones (les étages), et l'ordre des étages, choisi et gardé par domicile.
- **Relevé de Maison** : `NomsMaison` (`MaillageCoeur/Noms/NomsMaison.swift`).
  - Accessoires : nom, pièce, fabricant, modèle, firmware, catégorie, `noeudMatter`, pont, batterie, `id` HomeKit.
  - Zones : un nom et des pièces.
  - Passeur Noms l'envoie, et `NomsPasseur` le garde dans `releve-maison.json`.
- **Usages de ce relevé** : une trentaine de fichiers (Passeur et démo compris), pour trois usages : les noms ; les
  pièces et les étages ; des capacités propres à Maison (« Identifier », piles, associations, mémoire des appariements).
- **Réglages** : six onglets, Général, Notifications, Maison, Thread, Zigbee et Diagnostic. L'onglet Maison
  (`ReglagesMaison`) a deux sections, « Passeur Noms » et « Noms de Maison ».
- **Trousseau** (`TrousseauThread`) : mot de passe générique, non synchronisé.
  - Service : `fr.djoko.maillage.iot.<service>`.
  - Dans l'app de répétition, `.repetition` s'ajoute au service (`IdentiteApp`).
- **Droits**
  - Bac à sable, `network.client` et `network.server`.
  - `NSBonjourServices` ne liste ni `_esphomelib._tcp` ni `_home-assistant._tcp` : macOS refuserait ces types
    (NoAuth, -65555).
  - Pas de clé `NSAppTransportSecurity`.

## 4. Mesures chez Djoko (12/11/2026, HA 2026.10.4)

**Les sondes.** Trois sondes locales, non versionnées, car elles lisent des données réelles :
`.superpowers/home-assistant/sonde-controleur.py`, `sonde-esphome.py` et `sonde-ha.py`. Leurs sorties datées sont à
côté. Elles n'affichent que des comptes.

| Fait | Mesure |
|---|---|
| Hôtes `_matter._tcp` | 29 : 26 `thread`, aucun avec une IPv4 ; 3 `ip`, tous avec une IPv4 |
| Contrôleur Matter de HA | Genre `ip`. Seul sur sa fabrique. Son IPv4 est celle de HA. Aucune adresse OMR. |
| ESPHome | 1 instance, la H2 : `network=thread` ; genre `thread` d'après la règle de l'app ; aucune IPv4 |
| TXT de la H2 | `friendly_name`, `mac` (12 hexa minuscules), `network`, `version`, `platform`, `board`, `api_encryption`, `config_hash` |
| Matter dans HA | Les 26 hôtes Thread ont une instance sur la fabrique de HA. 26/26 sont rapprochés par `deviceid_<fabrique>-<nœud>-MatterNodeDevice`. |
| Autres identifiants Matter | 5 appareils pontés (suffixe entier) ; aucun identifiant d'une autre fabrique |
| Noms et pièces dans HA | 26/26 rapprochés ont une pièce ; 25 sont renommés dans HA ; tous les étages ont un niveau |
| Zigbee dans HA | 57/57 appareils du pont rapprochés par la connexion `zigbee` (11/11). Forme : deux-points, minuscules (57/57). |
| ESPHome dans HA | La H2 : 1 entrée, 1 appareil, une connexion `mac`, aucun identifiant. Rapprochée par la MAC de son annonce (11/11). |
| HomeKit | 2 appareils `homekit_controller` dans HA ; 0 annonce `_hap._udp` sur le réseau |
| Taille des listes | 185 ko pour les 213 appareils de HA ; quelques ko pour les pièces et les étages |
| Doublons dans HA | 87 appareils gardés par la minimisation (§ 7.2). Aucune clé n'y désigne deux appareils. Aucune pièce en double. 10 appareils Matter, tous renommés dans HA, se partagent 2 noms. |
| Doublons dans Maison | 6 noms en double parmi les accessoires du relevé gardé, dont 2 entre accessoires Matter |

Une mesure ne vaut que pour les formes mesurées. La MAC d'ESPHome, par exemple, n'a été vue que sur un appareil : les
deux côtés se normalisent donc.

## 5. Approches

### 5.1 Connexion à HA

| Voie | Principe | Coût | Choix |
|---|---|---|---|
| **A. Fenêtre de connexion** | La page de connexion de HA, dans la fenêtre de connexion de macOS (`ASWebAuthenticationSession`). Retour par un schéma propre à l'app. HA vérifie l'adresse de retour dans une petite fiche publique (IndieAuth). | Le plus de travail. Une fiche publique. HA doit joindre internet au moment de la connexion. | **Retenue** (Djoko, 12/11) |
| **B. Jeton collé** | Un jeton longue durée, créé dans le profil HA, collé dans les Réglages. | Le moins de travail. Un secret à manipuler à la main. | **Secours** de A |
| C. Navigateur et retour local | Connexion dans le navigateur, retour sur `127.0.0.1`. | Travail intermédiaire. Un onglet reste ouvert, et l'app écoute un port. | Écartée |

Écartées aussi :
- **Se présenter comme l'app officielle de HA**, dont le `client_id` est accepté sans fiche : c'est une identité
  usurpée, et la session apparaîtrait dans HA comme celle de l'app iOS.
- **Un retour en HTTPS par un domaine associé** : le fichier `apple-app-site-association` porte l'identifiant
  d'équipe, qui ne doit paraître nulle part ailleurs que dans la signature des versions publiées.
- **Une fiche servie par HA lui-même** (`/local/`) : il faudrait déposer un fichier à la main dans la configuration de
  HA.

### 5.2 Organisation interne (choix de l'assistant)

Retenu : **un relevé commun.** Maison (par Passeur Noms) et HA (par la connexion de l'app) produisent un relevé de même
forme. Les deux réglages choisissent quel relevé sert aux noms, et lequel sert aux pièces. Les quatre combinaisons
passent par un seul code.

Écartés :
- un circuit parallèle pour HA, qui obligerait à tenir les quatre combinaisons à jour partout ;
- un passage par Passeur Noms, qui obligerait un utilisateur qui n'a que HA à l'installer.

## 6. Décisions de Djoko

1. HA devient une seconde source de noms, à côté de Maison (11/11).
2. Deux réglages indépendants, au choix de l'utilisateur : « Noms » et « Pièces et étages », chacun Maison ou Home
   Assistant (11/11).
3. Un nœud que la source choisie ne connaît pas prend le nom qu'il annonce sur le réseau : nom HomeKit, ou
   `friendly_name` d'ESPHome ; à défaut, son identifiant. Jamais le nom de l'autre source (11/11).
4. Connexion par la voie A, avec le jeton de la voie B en secours (12/11).
5. D'abord les appareils du réseau absents de l'app (11/11).

## 7. Conception

### 7.1 Phase 12 : appareils ESPHome sur Thread, contrôleur de HA nommé

Cette phase se passe de connexion à HA.

**Écoute.**
- Le recensement écoute aussi `_esphomelib._tcp` et `_home-assistant._tcp`.
- Les deux types entrent dans `NSBonjourServices` des deux apps, Maillage IoT et sa répétition.
- `NSLocalNetworkUsageDescription` nomme aussi Home Assistant et ESPHome.

**Relevé.** `Annonces` gagne deux listes. Comme `airplay`, elles sont facultatives à la lecture et ne s'écrivent pas
quand elles sont vides : une capture ancienne garde ses octets.
- `esphome` : seulement les instances `network=thread`. Leur TXT est réduit à `friendly_name`, `mac`, `network`,
  `version`, `platform` et `board`.
- `homeAssistant` : instance, hôte et port. Le TXT est réduit à `uuid` et `version`. Jamais `internal_url`,
  `external_url` ni `base_url`, qui peuvent porter un domaine public.

**Appareil.**
- Une instance ESPHome entre dans l'`Appareil` de son hôte, avec une facette ESPHome : nom annoncé, nom d'instance,
  MAC, version, plateforme et carte.
- La MAC y est normalisée en 12 hexa majuscules. Elle fait l'identité de l'appareil, pas son hôte, qui change quand on
  le renomme dans ESPHome (§ 7.4).
- La règle des adresses place déjà l'appareil sur Thread : son genre ne change pas.

**Nom.** Après le nom HomeKit, la chaîne de `ResolveurNoms` prend le `friendly_name`, puis le nom d'instance ESPHome.

**Fiche.** La fiche du nœud montre la facette ESPHome : version, plateforme et carte.

**Contrôleur de HA.**
- Un appareil `ip` qui partage une adresse avec un hôte de `_home-assistant._tcp` est le contrôleur Matter de cette
  instance de HA.
- « Appareils IP » le nomme « Home Assistant », avec « contrôleur Matter » en second. Un surnom l'emporte.
- Il reste dans la liste : c'est bien un nœud Matter, et la liste dit ce qu'est chaque hôte.

**Carte.** Le nœud ESPHome se rapproche du nœud de la sonde par ses adresses, comme un appareil Matter (supposé,
vérifié au banc).

**Fin de la phase.**
- La H2 est sur la carte, avec son nom et sa fiche ESPHome.
- Le contrôleur est nommé dans « Appareils IP ».
- Une capture ancienne se relit, puis se réécrit à l'octet près.

### 7.2 Phase 13 : connexion à HA et relevé de son registre

**Découverte.**
- Les instances de `_home-assistant._tcp` du relevé, présentées par leur `location_name` (le nom de l'instance) et
  leur version.
- L'app se connecte en `http://<IP>:<port>`. L'IP est celle qu'elle résout depuis la cible SRV au moment où
  l'utilisateur choisit l'instance, et le port celui de la SRV. Elle garde cette IP, jamais le nom `.local`, auquel
  n'importe quel hôte du réseau peut répondre.
- Une adresse saisie à la main reste possible. Elle est gardée telle quelle (IP ou nom, en HTTP ou en HTTPS) : c'est le
  choix de l'utilisateur.
- Une seule instance est connectée à la fois.

**Fiche publique (le client).**
- Une page HTML de quelques lignes, servie par GitHub Pages depuis une branche qui ne porte qu'elle : le dossier
  `docs/` n'est pas publié.
- Son adresse sert de `client_id` : `https://djoko-cli.github.io/maillage-iot/`. HA l'affiche sur sa page de connexion.
- Son `<head>` déclare les adresses de retour, dans les 10 premiers kio (HA ne lit que le début) :
  - `<link rel="redirect_uri" href="fr.djoko.maillage.iot://auth-callback">` pour l'app ;
  - `fr.djoko.maillage.iot.repetition://auth-callback` pour l'app de répétition, sur une ligne de même forme.
- La page ne contient rien de personnel : un titre, et deux phrases (en anglais, puis en français) qui disent ce
  qu'est l'app.
- Publier la page et activer Pages demandent l'accord de Djoko.

**Connexion (voie A).**
1. L'app tire un `state` (32 octets aléatoires) et un vérificateur PKCE (43 à 128 caractères), d'où elle calcule le
   défi S256.
2. Elle ouvre `ASWebAuthenticationSession` sur cette adresse :
   `<HA>/auth/authorize?response_type=code&client_id=…&redirect_uri=…&state=…&code_challenge=…&code_challenge_method=S256`.
   - Rappel : `.customScheme("fr.djoko.maillage.iot")`.
   - `prefersEphemeralWebBrowserSession = true`.
   - Fenêtre d'ancrage : celle des Réglages.
3. Au retour, l'app compare le `state` à celui qu'elle a tiré, et refuse s'il diffère. Elle envoie aussitôt le `code`
   à `POST <HA>/auth/token`, dans un corps de formulaire : `grant_type=authorization_code`, `code`, `client_id`,
   `code_verifier`.
4. La réponse donne un jeton d'accès, valable 30 min (`expires_in: 1800`), et un jeton de renouvellement.

Deux garde-fous :
- Le schéma n'est pas déclaré dans `CFBundleURLTypes` : la session reçoit le retour sans cela. Une page web ou une
  autre app ne peuvent donc pas ouvrir l'app par ce schéma (supposé, vérifié au premier essai).
- L'URL de retour porte le `code` : elle n'est jamais journalisée, ni recopiée dans une erreur.

**Secours (voie B).**
- Dans la section Home Assistant, « Se connecter avec un jeton… » ouvre un champ sécurisé (`SecureField`). On y colle
  un jeton longue durée, créé dans le profil HA (onglet Sécurité).
- Quand la fenêtre de connexion échoue, le texte d'aide propose cette voie : « Si Home Assistant n'a pas accès à
  internet, connecte-toi avec un jeton. »

**Jetons.**
- **Garde.** Le jeton de renouvellement (A) ou le jeton longue durée (B) va au trousseau.
  - Mot de passe générique, non synchronisé.
  - Service `fr.djoko.maillage.iot.home-assistant`, avec `.repetition` en plus dans l'app de répétition.
  - La nature du jeton va en commentaire.
  - Le jeton d'accès reste en mémoire.
- **Renouvellement** : `grant_type=refresh_token`, à chaque (re)connexion, si le jeton d'accès a plus de 25 min.
- **Jeton refusé** (`invalid_grant` au renouvellement, `auth_invalid` sur le WebSocket) :
  - un seul renouvellement est tenté ;
  - puis l'état passe à « Reconnexion nécessaire » ;
  - plus aucune tentative automatique avec ce jeton (anti-objectifs).
- **« Se déconnecter »** :
  - voie A : `POST <HA>/auth/revoke` avec le jeton de renouvellement ;
  - voie B : un jeton longue durée se révoque dans HA, et la section le rappelle ;
  - puis l'élément du trousseau et le relevé de HA gardé sont supprimés.
- **Conseil affiché** : un compte HA non administrateur suffit.
  - Les commandes employées ne demandent pas d'être administrateur (constaté dans le code de HA 2026.10.4).
  - Un jeton de HA donne tous les droits de son compte.

**WebSocket et relevé.**
- **Connexion** : `ws(s)://<HA>/api/websocket`. HA envoie `auth_required` ; l'app répond
  `{"type":"auth","access_token":…}` ; HA confirme par `auth_ok`.
- **Commandes**, toutes en lecture :
  - `get_config`, dont l'app ne garde que `location_name` et `version`. La réponse porte aussi les coordonnées du
    domicile, que l'app ne garde jamais.
  - `config/device_registry/list`, `config/area_registry/list` et `config/floor_registry/list` ;
  - `config_entries/get` avec `domain: esphome`, pour reconnaître les appareils ESPHome (voir la minimisation).
- **Abonnements** (`subscribe_events`) : `device_registry_updated`, `area_registry_updated` et
  `floor_registry_updated`. Un événement provoque une relecture des quatre listes ; les événements proches se regroupent
  (2 s).
- **Relevé gardé** : `releve-home-assistant.json`, à côté de `releve-maison.json`, au format du relevé commun (§ 7.3).
  Seul un relevé complet le remplace.
- **Minimisation** : le relevé garde toutes les pièces et tous les étages, et ces appareils de HA :
  - ceux qui ont un identifiant `matter` en `deviceid_…-MatterNodeDevice`, ou une connexion `zigbee` ;
  - ceux qui ont une connexion `mac` et une entrée de configuration ESPHome. Une connexion `mac` ne suffit pas seule :
    d'autres intégrations la portent aussi (Apple TV, enceintes, ESPHome en Wi-Fi…).
- **Reconnexion** : après une coupure, des attentes croissantes (2, 5, 15, 60 s, puis toutes les 60 s) ; au réveil du
  Mac, tout de suite.
- **Messages de HA** : ce sont des entrées non fiables.
  - Décodage tolérant aux champs inconnus.
  - Taille d'un message plafonnée à 16 Mio : la liste des appareils pèse 185 ko chez Djoko, et le plafond de 1 Mio de
    `URLSessionWebSocketTask` serait trop juste pour une grande maison.
  - Textes affichés tels quels (`Text(verbatim:)`).

**Adresse de HA.**
- L'app garde l'adresse que l'utilisateur a choisie (voir la découverte).
- Si l'instance découverte (même `uuid`) s'annonce à une autre IP, les Réglages proposent la nouvelle adresse (« Home
  Assistant a changé d'adresse… Utiliser… »). D'ici là, HA est « introuvable ». C'est le prix d'une adresse fixée, et
  HA a le plus souvent une adresse fixe.
- L'app ne l'adopte jamais seule : une annonce Bonjour se falsifie, et le jeton partirait vers elle.
- Une adresse saisie à la main n'a pas d'`uuid`, car `get_config` n'en donne pas (constaté dans le code de HA
  2026.10.4). Aucune proposition, donc : l'utilisateur corrige l'adresse lui-même.

**Transport.**
- HTTP sur le réseau local est accepté : c'est le cas chez Djoko, comme pour l'interface web de HA.
- HTTPS fonctionne avec un certificat que le système reconnaît. Un certificat auto-signé n'est pas pris en charge.
- Les requêtes en clair vers une adresse locale (IP ou `.local`) passent par `NSAllowsLocalNetworking`, ou par
  Network.framework, que l'ATS ne couvre pas. Le constructeur choisit, et le premier essai vérifie.

**Rapprochement** (cœur, sans interface) : relier chaque nœud de l'app à un appareil du relevé de HA.
- **Thread Matter** : l'instance de l'appareil sur la fabrique de HA (celle de ses identifiants `matter`) correspond à
  `deviceid_<fabrique>-<nœud>-MatterNodeDevice`.
- **Thread ESPHome** : la MAC de l'annonce correspond à la connexion `mac`. Les deux côtés passent en 12 hexa
  majuscules.
- **Zigbee** : l'IEEE du pont Hue correspond à la connexion `zigbee`. Les deux côtés passent en 16 hexa majuscules.
- **Appareils `ip`** (Matter en Wi-Fi) : comme les Thread Matter.
- **Jamais de rapprochement ambigu** (§ 7.4) : une clé qui désigne plusieurs appareils de HA, ou l'inverse, ne
  rapproche rien.
- **Bilan**, pour la section Home Assistant, par protocole :
  - les nœuds reconnus, et ceux que HA ne connaît pas ;
  - pour Matter et Zigbee, aussi les appareils de HA non vus sur le réseau ; pas pour ESPHome, car le registre ne dit
    pas si un appareil ESPHome est sur Thread ou en Wi-Fi ;
  - ces états restent distincts : « inconnu » n'est pas « aucun ».

**Réglages.** L'onglet « Maison » devient « Noms et pièces » (même symbole, `house`). Ses sections, dans cet ordre :
1. « Sources » (phase 14) ;
2. « Passeur Noms » et « Noms de Maison », inchangées ;
3. « Home Assistant » :
   - l'instance et son état (introuvable, connexion…, connecté, reconnexion nécessaire, erreur), et le compte ;
   - les boutons « Se connecter… », « Se déconnecter » et « Se connecter avec un jeton… » ;
   - le conseil du compte non administrateur ;
4. « Relevé de Home Assistant » : sa date, les comptes d'appareils, de pièces et d'étages, et le bilan du
   rapprochement.

**Fin de la phase.**
- Connexion par la voie A chez Djoko, puis par la voie B.
- Relevé reçu, gardé, et tenu à jour quand un nom change dans HA.
- Bilan de 26 Thread, 57 Zigbee et 1 ESPHome.
- Aucun nom n'a encore changé sur la carte.

### 7.3 Phase 14 : noms, pièces et étages au choix

**Relevé commun.** Le type `NomsMaison` devient le relevé commun aux deux sources ; le constructeur peut le renommer.
Il gagne des champs facultatifs, que le relevé de Maison laisse vides, sans changer sa version :
- `source` : `maison` ou `homeAssistant` ;
- par accessoire : `fabriqueMatter` (la fabrique de son `noeudMatter`), `ieee` et `mac` ; pour HA, `id` porte
  l'identifiant d'appareil de HA ;
- par zone : `niveau`, le niveau de l'étage de HA.

Le relevé de HA s'y écrit ainsi :
- accessoire : nom = `name_by_user`, sinon `name` ; pièce = nom de la pièce (`area_id`) ; fabricant, modèle et
  firmware ;
- zone : une par étage, avec ses pièces et son niveau ; une pièce sans étage reste hors des zones ;
- domicile : `location_name`.

**Trois usages, trois relevés.**
- Les noms lisent le relevé choisi par « Noms ».
- Les pièces, les étages et le domicile lisent le relevé choisi par « Pièces et étages ».
- Les capacités propres à Maison lisent toujours le relevé de Maison, quelle que soit la source : « Identifier », les
  piles, les associations à la main, la mémoire des appariements de `FusionNoms`. Un identifiant de HA ne part jamais
  vers Passeur Noms.

**Noms**, par ordre de priorité :
- **Thread** : surnom > accessoire de la source > nom HomeKit > nom ESPHome annoncé > identifiant.
  - Avec Maison, l'accessoire se trouve par le nœud sur la fabrique d'Apple, puis par l'association faite à la main.
  - Avec HA, il se trouve par le nœud sur la fabrique de HA, ou par la MAC.
- **Zigbee** : surnom > accessoire de la source > nom de l'app Hue > IEEE.
  - Avec Maison, l'accessoire se trouve par les appariements de `FusionNoms`.
  - Avec HA, il se trouve par l'IEEE seul.
  - Le nom de l'app Hue tient lieu d'annonce : pour Zigbee, c'est le pont qui annonce les appareils.
- Avec les noms de HA, « Associer… » est caché. Les associations restent dans leur fichier.

**Pièces.**
- Thread : pièce de la source > choix « Placer dans une pièce… » > règle du nom (routeurs de bordure) > sans pièce.
- Zigbee : pièce de la source > pièce de l'app Hue.
- Les choix restent gardés par domicile. Ceux faits sous Maison restent dans le fichier, inutilisés tant que HA est la
  source.
- Le menu « Placer dans une pièce… » propose les pièces de la source.

**Étages.**
- Avec HA, l'ordre des étages suit leur niveau, dans le sens où la vue range déjà ses étages.
- Un ordre choisi par l'utilisateur pour ce domicile l'emporte, comme aujourd'hui.

**Source sans relevé.**
- Le dernier relevé gardé sert, et sa date apparaît en légende.
- Sans aucun relevé, ce sont les noms annoncés. La section « Sources » le dit : « Home Assistant n'est pas connecté :
  noms annoncés sur le réseau. »

**Origine.** La fiche d'un nœud dit d'où viennent son nom et sa pièce : surnom, Maison, Home Assistant, annonce, ou app
Hue.

**Homonymes.** Plusieurs nœuds affichés sous le même nom se distinguent par leur pièce, quelle que soit la source
(§ 7.4).

**Réglages, section « Sources ».**
- Deux sélecteurs, « Noms » et « Pièces et étages », chacun « Maison » ou « Home Assistant ».
- Sous chacun, une ligne donne l'état de la source choisie.
- Par défaut, « Maison » pour les deux : une mise à jour ne change rien.

**Fin de la phase.**
- Les quatre combinaisons passent au banc chez Djoko.
- Avec Maison pour les deux, la scène et les noms sont identiques à avant : rejeu d'une capture et d'un relevé de
  Maison.

### 7.4 Doublons

Question de Djoko (12/11) : comment se prémunir des doublons ? Six formes, et leur garde.

1. **Un même appareil sur plusieurs fabriques** (Apple et HA) : l'app regroupe déjà les annonces par hôte, donc un seul
   nœud. Constaté : 84 annonces Matter pour 29 hôtes (§ 4).
2. **Une annonce et un nœud de la sonde** pour le même appareil : le rapprochement par adresses, qui existe déjà, les
   fond en un nœud. Pour ESPHome, c'est le risque 12, vérifié par un test et au banc de la phase 12.
3. **Un appareil ESPHome renommé** : son hôte change avec son nom, et l'app verrait un nouvel appareil, l'ancien restant
   « disparu ». Garde, en phase 12 : l'identité d'un appareil ESPHome est sa MAC, pas son hôte. Le surnom et la pièce
   choisie le suivent.
4. **Un rapprochement ambigu** : une clé qui désigne plusieurs appareils de HA, ou un appareil de HA qui désigne
   plusieurs nœuds. Constaté chez Djoko : aucun cas. Garde, en phase 13 : pas de rapprochement ambigu, comme dans
   `FusionNoms`. Le nœud garde son nom annoncé, et le bilan compte le cas comme « ambigu ».
5. **Des homonymes** : plusieurs nœuds affichés sous le même nom. Le cas existe chez Djoko : 10 appareils Matter
   renommés dans HA se partagent 2 noms, et Maison a aussi des noms en double (§ 4). Garde, en phase 14, quelle que
   soit la source :
   - le libellé d'un homonyme ajoute sa pièce (« Appareil 1 · Pièce 1 ») ;
   - dans la vue par pièces, où la pièce se voit déjà, seuls les homonymes d'une même pièce reçoivent un court
     suffixe ;
   - le journal nomme déjà la pièce de l'appareil (phase 9).
6. **Une instance de HA annoncée deux fois** (deux interfaces, IPv4 et IPv6) : la découverte dédoublonne par `uuid`.

Par construction, enfin :
- un nœud ne peut pas recevoir deux noms, puisque chaque usage lit un seul relevé, sans repli sur l'autre source
  (décision 3) ;
- l'identité d'un nœud ne vient jamais de son nom : changer de source ne crée ni nœud, ni événement, ni notification
  en double.

## 8. Risques

| # | Risque | Statut | Où il se mesure |
|---|---|---|---|
| 1 | HA 2026.10.4 accepte un retour à schéma propre, déclaré par `<link rel="redirect_uri">` à un `client_id` d'un autre domaine | Constaté dans le code de HA 2026.10.4 (`indieauth.py` : `verify_redirect_uri`, `fetch_redirect_uris`, `LinkTagParser`). De bout en bout : supposé. | Premier essai, phase 13 |
| 2 | HA joint la fiche publique au moment de la connexion | Supposé chez Djoko. Délai (5 s) et taille lue (10 kio) constatés dans le code. | Premier essai ; sinon, voie B |
| 3 | HA vérifie le défi PKCE S256 quand il en reçoit un | Constaté dans le code de HA 2026.10.4 (`auth/__init__.py`, `login_flow.py`). Que la page de connexion transmette le défi : supposé, car le code de l'interface n'a pas été lu. | Premier essai : un échange avec un mauvais vérificateur doit échouer. S'il réussit, la voie A reste (§ 11), et l'essai le consigne. |
| 4 | `ASWebAuthenticationSession` ouvre une adresse `http://` du réseau local (IP et `.local`), dans le bac à sable, avec un rappel par un schéma non déclaré et une session éphémère | Supposé | Premier essai, phase 13 |
| 5 | La page s'affiche dans une feuille de Safari, ou dans le navigateur par défaut (macOS 14.4 et suivants) | Supposé ; sans effet sur la conception | Premier essai |
| 6 | L'ATS laisse passer les requêtes HTTP et WebSocket en clair vers le réseau local | Supposé | Premier essai |
| 7 | Les listes des registres, `config_entries/get`, et l'abonnement aux événements des registres ne demandent pas d'être administrateur | Constaté dans le code de HA 2026.10.4 (`config/*_registry.py`, `config/config_entries.py`, `auth/permissions/events.py`) | Essai avec un compte non administrateur, phase 13 |
| 8 | Une connexion WebSocket reste ouverte au-delà des 30 min du jeton d'accès, et HA la ferme quand le jeton de renouvellement est révoqué | Les 30 min sont constatées (`ACCESS_TOKEN_EXPIRATION`). Le reste est supposé. | Mesure, phase 13 |
| 9 | Forme des clés de HA : `deviceid_<fabrique 16 hexa>-<nœud 16 hexa>-MatterNodeDevice` ; connexions `zigbee` et `mac` en minuscules à deux-points | Constaté dans le code (`matter/helpers.py`, `esphome/manager.py` : `format_mac`) et chez Djoko (§ 4). La MAC d'ESPHome n'a été vue que sur un appareil. | Tests, sur les deux formes de chaque côté |
| 10 | Le contrôleur Matter de HA partage une adresse avec l'hôte de `_home-assistant._tcp` | Constaté chez Djoko : le module Matter tourne sur l'hôte de HA. En général : supposé. Un serveur Matter sur une autre machine reste un appareil IP sans nom. | Banc, phase 12 |
| 11 | La règle des adresses place un appareil ESPHome sur Thread | Constaté chez Djoko par une sonde qui reprend la règle. Par le code de l'app : supposé. | Tests et banc, phase 12 |
| 12 | Le nœud ESPHome se rapproche du nœud de la sonde par ses adresses | Supposé | Banc, phase 12 |
| 13 | GitHub Pages sert la fiche durablement, à la même adresse | Supposé. Si l'adresse change, il faut se reconnecter. | — |

## 9. Laissé au constructeur

- Les noms de types et de fichiers, y compris un éventuel renommage de `NomsMaison`.
- URLSession ou Network.framework pour HTTP et WebSocket. Contrainte : `http://` local, en IP et en `.local`.
- Le partage des consommateurs du relevé entre les trois usages (§ 7.3), fichier par fichier.
- Le symbole et la mise en page des sections de réglages, à valider au banc.
- L'état « connexion… » et ses délais ; le regroupement des relectures.
- Les appareils de HA désactivés (`disabled_by`) : les garder dans le relevé, ou non.

## 10. Choix de l'assistant, à vérifier

1. Un relevé commun, sur la base de `NomsMaison` (§ 5.2 et 7.3).
2. Le contrôleur de HA nommé dans « Appareils IP », et non caché (§ 7.1).
3. ESPHome : seulement `network=thread`. Nom annoncé : `friendly_name`, sinon le nom d'instance.
4. Zigbee avec HA : rapprochement par l'IEEE seul. Repli sur le nom et la pièce de l'app Hue, l'équivalent de
   l'annonce pour Zigbee.
5. « Identifier », les piles et les associations restent à Maison et au pont Hue.
6. La fiche publique sur GitHub Pages, dans une branche dédiée. `client_id` :
   `https://djoko-cli.github.io/maillage-iot/`, que HA affiche sur sa page de connexion.
7. Schéma de retour : `fr.djoko.maillage.iot://auth-callback`, de même forme que celui de l'app officielle de HA.
8. Session éphémère, et schéma non déclaré.
9. Une nouvelle adresse de HA est proposée, jamais adoptée seule.
10. Le conseil d'un compte HA non administrateur.
11. L'onglet « Maison » devient « Noms et pièces ».
12. Par défaut, Maison pour les deux réglages.
13. Les phases s'inscrivent dans la feuille de route de la spec principale (12 à 14), comme le panneau de santé et la
    pièce AirPlay.

Après la relecture du constructeur (12/11) :

14. Pour une instance découverte, l'app garde l'IP résolue, plutôt que son nom `.local`.
15. Un PKCE non vérifié au premier essai ne fait pas abandonner la voie A.
16. Les appareils ESPHome sont reconnus par leur entrée de configuration (`config_entries/get`), sans ligne « non vus »
    pour eux dans le bilan.

Après la question de Djoko sur les doublons (12/11) :

17. L'identité d'un appareil ESPHome est sa MAC (§ 7.4, forme 3).
18. Pas de rapprochement ambigu ; un cas ambigu est compté comme tel au bilan (forme 4).
19. Les homonymes se distinguent par leur pièce, quelle que soit la source (forme 5).

## 11. Ordre des phases

- **Phase 12** ne dépend de rien. Elle fournit deux éléments dont la suite a besoin :
  - `_home-assistant._tcp`, que la phase 13 reprend pour la découverte ;
  - la MAC d'ESPHome, que le rapprochement emploie.
- **Phase 13** dépend de la phase 12.
  - Sa première tâche est l'essai témoin de la voie A chez Djoko (risques 1 à 6), après l'accord pour publier la fiche.
  - La voie A échoue si HA refuse l'adresse de retour, ou si la session ne s'ouvre pas ou ne revient pas. La voie B
    livre alors quand même la phase.
  - Un PKCE non vérifié n'est pas un échec. Le retour va à la session elle-même (risque 4) et le `state` est vérifié.
    Un code ne vaut que 10 min et ne sert qu'une fois (constaté dans le code de HA 2026.10.4). L'essai consigne le
    résultat.
- **Phase 14** dépend de la phase 13 (relevé et rapprochement).
- Aucune phase ne fournit quelque chose dont une phase antérieure a besoin.
- **Mode d'exécution proposé :**
  - plan complet pour la phase 13 (sécurité, nouveau sous-système) ;
  - plan complet pour la phase 14 (code partagé des noms, quatre combinaisons) ;
  - voie courte possible pour la phase 12, bien bornée (une dizaine de fichiers).

## Feuille de route

Les cases vivent dans la feuille de route de la spec principale (`2026-10-13-maillage-iot-design.md`), que suit
Jalons. Les plans s'appellent `…-maillage-iot-phase-N.md`.

- Phase 12 : appareils ESPHome sur Thread, contrôleur de Home Assistant nommé.
- Phase 13 : connexion à Home Assistant et relevé de son registre.
- Phase 14 : noms, pièces et étages au choix entre Maison et Home Assistant.
