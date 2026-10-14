# Sonde de maillage Thread (firmware)

Un ESP32-C6 SuperMini (flash de 4 Mo), branché au Mac en USB, ou alimenté
seul et joint par le réseau Thread. La sonde entre dans le réseau Thread
comme **nœud Matter en FED non éligible routeur** (Full End Device) : elle
reçoit en permanence mais ne relaie rien, ne devient jamais routeur ni chef,
et ne devient jamais le parent de personne. Elle fabrique les requêtes de
diagnostic Thread (`DIAG_GET`, CoAP `POST d/dg` vers le port TMF 61631) que
Maillage Thread lui demande, et renvoie les réponses brutes. C'est l'app qui
les décode.

En FED (depuis la 1.0.2 ; MED jusqu'à la 1.0.1), OpenThread tient la table
des routeurs de la partition et apprend l'ExtMac de ceux qu'il entend :
commande `routeurs`.

Depuis la 1.1.0, la sonde **écoute aussi les messages MLE** de ses voisins à
un saut (voir « Écoute des messages MLE ») : les annonces des routeurs portent
leur Route64, leurs liens dans les deux sens, même pour les routeurs de
bordure d'Apple, qui ne répondent pas au diagnostic. Et elle **résout
l'adresse** d'un appareil (`resoudre`) : OpenThread demande au réseau qui la
porte, et le parent d'un enfant endormi répond à sa place.

Spec : `docs/superpowers/specs/2026-10-13-maillage-iot-design.md`.

## Compiler et flasher

Chaîne calée sur benq : pioarduino `55.03.312-1` (Arduino-ESP32 3.3.12,
ESP-IDF 5.5.5, Matter 1.5).

```sh
cd sonde
pio run                                         # compile
pio run -t erase --upload-port /dev/cu.usbmodemXXXX    # premier flash : effacement
pio run -t upload --upload-port /dev/cu.usbmodemXXXX
```

Pour passer une sonde déjà appairée à une nouvelle version, flasher **sans**
effacement (`-t upload` seul) : l'appairage Maison, le réseau Thread, le nom
et la clé d'accès réseau sont gardés. De la 1.0.1 à la 1.0.2, la sonde passe
de MED (`rn`) à FED (`rdn`) au démarrage et se rattache. De la 1.0.3 à la
1.1.1, rien ne change de ce qui est gardé ; place à la compilation (1.1.1) :
76,6 % de la flash et 54,1 % de la RAM.

**Toujours désigner le port de la sonde.** Le pont Halo de benq est lui
aussi un C6 : le flasher par erreur le remplacerait. Le numéro de série USB
d'un C6 est son adresse MAC (`ioreg -p IOUSB -l | grep "USB Serial Number"`).

## Appairer à Maison

Au démarrage, et à la commande `bonjour`, la sonde donne son code
d'appairage et la charge de son QR code (`MT:…`), même une fois dans Maison
(depuis la 1.0.1 ; la 1.0.0 ne les donnait qu'avant l'appairage). Maillage
Thread les montre dans Réglages › Sonde : le QR code, et le code mis en forme
4-3-4 (par exemple `1234-567-8901`).
1. Dans Maison sur l'iPhone : « + » › Ajouter un accessoire › Plus d'options.
2. Saisir le code, ou scanner le QR code.
3. Maison dit « accessoire non certifié » : ajouter quand même.

La sonde apparaît comme une prise « Sonde maillage », allumée par défaut.
Éteinte, elle refuse les requêtes de diagnostic (`suspendue`). Son état est
gardé d'un démarrage à l'autre : éteinte dans Maison, elle reste suspendue
après un redémarrage ou un débranchement. Sa LED le montre (voir « LED »).

`oubli` efface la clé d'accès réseau, désappaire la sonde et la redémarre
allumée, interrupteur compris, comme à sa première mise en service (depuis
la 1.0.3 ; avant, une sonde éteinte revenait éteinte, donc suspendue après
un nouvel appairage). Retirée de Maison sans `oubli`, elle efface aussi sa
clé (un nouveau propriétaire ne garde pas l'accès de l'ancien), mais garde
l'état de son interrupteur.

## LED

Depuis la 1.0.3, la LED couleur de la carte (WS2812, sur IO8) montre l'état de
la sonde, à faible intensité. Depuis la 1.1.1, elle suit le **tronc commun**
partagé avec le pont Halo, la carte Amaran et la sonde de Maillage Zigbee :
24/255 au plus par canal, bleu (0, 0, 24), vert (0, 24, 0), orange (24, 6, 0),
lueur blanche jusqu'à 8/255. Du plus prioritaire au moins prioritaire :

| LED | Signification |
|---|---|
| arc-en-ciel, un tour de roue en 2 s (par pas de 40 ms) | identification demandée par Maison (« Identifier ») : pendant toute l'identification, et au moins un tour complet même si elle ne dure qu'un instant |
| deux éclairs verts rapides (100 ms, 100 ms de pause) | l'interrupteur « Sonde maillage » vient de s'allumer dans Maison |
| un éclair orange d'une demi-seconde | l'interrupteur vient de s'éteindre |
| bleu clignotant (250 ms allumé, 250 ms éteint) | la sonde n'est pas mise en service (pas encore appairée, ou oubliée) |
| bleu lent, pulsation de 2 s (montée jusqu'à 24/255 puis descente) | mise en service mais pas attachée au réseau Thread : au démarrage, ou après la perte de son parent |
| deux éclairs verts rapides (100 ms, 100 ms de pause) | la sonde vient de s'attacher au réseau Thread (aussi au premier attachement après le démarrage) |
| un bref éclair orange (100 ms) toutes les 5 s | la sonde est suspendue (interrupteur éteint) ; dès l'attachement si elle l'était avant |
| éteinte, une brève lueur blanche toutes les 10 s (montée puis descente jusqu'à 8/255 sur 600 ms) | tout va bien : la sonde est allumée et attachée au réseau Thread ; la première lueur juste après les éclairs verts de l'attachement |

L'orange lent du tronc commun (« mis en service, sans réseau IP ») ne
s'applique pas à la sonde : son réseau IP est Thread lui-même, couvert par le
bleu lent. Suspendue et pas attachée, la sonde montre donc le bleu, pas
l'orange.

Seule la boucle principale écrit la LED, jamais sous le verrou d'OpenThread :
les rappels de Matter (interrupteur, identification) ne font que noter un
état. La mise en service et l'attachement (rôle Thread) se relisent une fois
par seconde, le rôle sous le verrou pris sans attendre. Une identification
par effet (`TriggerEffect`) dure 2 s (Blink, Okay), 8 s (changement de canal)
ou 15 s (Breathe), comme sur le pont Halo, puisque la pile Matter ne la
termine jamais.

## Nom

La sonde a un nom, « SONDE-T1 » par défaut, gardé dans sa mémoire (NVS, à
côté de l'état de l'interrupteur) : il suit la carte d'un Mac à l'autre.
Maillage Thread le montre à la place du port (« SONDE-T1 » plutôt que
« usbmodem11301 »). `nom <texte>` le change : 1 à 32 caractères parmi les
lettres ASCII, les chiffres, `-`, `_` et `.`. L'app n'a pas encore de quoi le
changer.

## Protocole USB

Une commande par ligne. En retour, des lignes machine : RS (0x1E), JSON
compact en ASCII, LF, 4096 octets au plus. Pour ouvrir le port sans redémarrer
le C6, il faut mettre DTR et RTS à 0 dans un seul appel (voir benq).

| Commande | Réponse |
|---|---|
| `bonjour` | produit (`sonde-maillage`), version, nom, MAC, appairée ou non, code d'appairage (`code`) et charge du QR code (`qr`, `MT:…`), toujours ; nom d'hôte SRP (`hote`, sans `.local`, `null` tant qu'il n'est pas connu) |
| `nom <texte>` | change le nom et le garde ; un `bonjour` à jour, ou l'erreur `syntaxe` (nom refusé) ou `ecriture` (mémoire qui refuse l'écriture) |
| `etat` | rôle, RLOC16, ExtMac, mode (`rdn`), `eligible` (`false`), parent (RLOC16, ExtMac, qualités, RSSI), partition, chef, canal, préfixe du réseau maillé, `xp`, suspendue |
| `voisins` | routeurs voisins à lien établi (le parent n'y est pas : voir `etat`) |
| `routeurs` | table des routeurs d'OpenThread : `{"v":1,"t":"routeurs","liste":[{"id":…,"rloc16":"XXXX","ext":"<16 hexa>"\|null,"lqIn":…,"lqOut":…,"age":…,"lien":…}],"suite":…}`, plusieurs lignes si besoin (`"suite":true` sur toutes sauf la dernière) |
| `diag <cible> <t,t,…> <id> [<délai ms>]` | TLV de la réponse en hexa, ou l'erreur : `delai`, `suspendue`, `occupee` (8 requêtes en vol, ou verrou d'OpenThread refusé), `envoi…` |
| `annonces` | (1.1.0) une ligne par routeur entendu : `{"v":1,"t":"annonces","rloc16":"XXXX","ext":"<16 hexa>","partition":"<8 hexa>"\|null,"route64":"<hexa>"\|null,"seq":…,"rssi":…,"rssi_min":…,"rssi_max":…,"nb":…,"age_s":…,"suite":…}` (`"suite":true` sur toutes sauf la dernière) ; sans routeur entendu, une seule ligne `{"v":1,"t":"annonces","vide":true}` ; par le réseau, les lignes partent au fil des places libres de la file d'émission (6 places), en quelques secondes pour 32 routeurs, et la réponse est un instantané de la table à la commande ; un autre `annonces` pendant ce temps répond `{"v":1,"t":"erreur","erreur":"occupee"}` ; cette réponse n'est pas gardée (un rid répété après la fin relance la lecture : l'app fusionne par `ext` ou `rloc16`) ; l'envoi laisse une place libre dans la file |
| `resoudre <ipv6> <id>` | (1.1.0) `{"v":1,"t":"resoudre","id":…,"cible":"<ipv6>","ok":true,"ms":…,"rloc16":"XXXX","repondu":true\|false,"mleid":"<32 hexa>"\|null}` (`repondu` : 1.1.1, l'appareil a répondu à l'écho pendant cette résolution), ou l'erreur : `introuvable` (rien en 15 s), `syntaxe` (adresse mal formée), `suspendue`, `occupee` (8 résolutions en vol, ou verrou d'OpenThread refusé), `envoi…` |
| `cle` | `{"v":1,"t":"cle","empreinte":"<8 hexa>"\|null,…}`, avec `effacement_en_echec`, le nom d'hôte, les compteurs du transport (`udp`, dont `lignes_perdues` et `refus_cadence`) et le tas (`tas`) |
| `cle efface` | efface la clé (plus d'accès réseau) ; la réponse de `cle`, ou l'erreur `ecriture` |
| `cle nouvelle <64 HEXA> <id>` | nouvelle clé (réservé à l'app) : `{"v":1,"t":"cle","id":<id>,"cle":"<64 HEXA>","empreinte":"<8 hexa>","hote":…}`, **une seule fois** ; sans `id` : erreur `syntaxe` ; clé écrite mais pas chargée : un `msg` en plus |
| `oubli` | efface la clé, désappaire et redémarre : `{"v":1,"t":"oubli","cle_effacee":true\|false}` |

`etat`, `voisins` et `routeurs` répondent `{"v":1,"t":"<commande>","erreur":"occupee"}`
si le verrou d'OpenThread n'a pas pu être pris (200 ms). Depuis la 1.1.0,
`etat` porte aussi `ecoute` : `{"trames":…,"mle":…,"echecs":…,"file_pleine":…}`,
les trames reçues, les messages MLE déchiffrés, ceux qui ne l'ont pas été
(en-tête illisible, clé indisponible, MIC faux) et les trames perdues file
pleine, depuis le démarrage.

`<cible>` est un RLOC16 en 4 hexa, ou une adresse IPv6 du réseau maillé :
chiffres hexa, `:` et `.` seulement, sinon `syntaxe`. `<id>` et
`<délai ms>` sont des entiers décimaux de 10 chiffres au plus (4294967295
au plus), sinon `syntaxe` (depuis la 1.0.3). Le délai va de 3 à 60 s, 45 s
par défaut ; l'échec `delai` tombe à son terme (depuis la 1.0.3 : un délai
de 10 à 15 s n'est plus arrondi à 15 s).

Si la mémoire (NVS) refuse d'effacer la clé (`cle efface`, retrait de Maison),
la clé quitte la mémoire vive (plus d'accès réseau) mais reviendrait au
démarrage : `cle` le dit (`effacement_en_echec`), et la sonde réessaie toutes
les 500 ms. `oubli` le dit par `cle_effacee` (`false` : la clé reviendra après
le redémarrage ; `cle efface` ensuite).

En FED, `routeurs` donne tous les routeurs de la partition (leur RLOC16),
l'ExtMac de ceux que la sonde entend : trois viennent en quelques secondes,
les autres au fil des minutes. L'entrée du parent n'a jamais d'ExtMac (voir
`etat`). `age` n'a de sens que pour un routeur entendu.

## Écoute des messages MLE (1.1.0)

- **Les trames.** Au démarrage de la pile Thread, la sonde pose
  `otLinkSetPcapCallback` : OpenThread lui donne chaque trame reçue, sans mode
  promiscuité. Le rappel, dans la tâche OpenThread, ne fait qu'un tri (trames
  de données sans sécurité MAC) et une copie dans une file de 16 trames ; une
  file pleine est comptée, jamais bloquante ; ni verrou, ni Matter, ni CHIP.
  Le reste se fait dans `loop()`.
- **Le décodage** (`src/mle.h`, sans Arduino, testé sur le Mac) : en-tête
  802.15.4 aux formats 2003/2006 et 2015 (numéro de séquence supprimé, PAN
  selon le tableau 7-2, IE d'en-tête jusqu'à HT1 ou HT2), 6LoWPAN IPHC sans
  contexte, UDP vers le port MLE 19788, source lien-local.
- **Le déchiffrement** : suite de sécurité 0, contrôle `0x15` (niveau 5, clé
  en mode 2), compteur de trame petit-boutiste, séquence de clé gros-boutiste.
  La clé MLE est les 128 premiers bits de HMAC-SHA256(clé réseau, séquence ‖
  « Thread ») ; AES-CCM, MIC de 4 octets ; nonce : l'ExtMac de l'émetteur
  (tirée de son adresse lien-local), le compteur, le niveau ; données
  associées : les adresses IPv6 source et destination, puis les 10 octets de
  l'en-tête de sécurité. mbedTLS sur la carte (`src/mle_crypto.cpp`).
- **La clé réseau** ne quitte jamais la carte : lue sous le verrou
  d'OpenThread seulement pour dériver les clés MLE, quand la séquence de la
  pile change, puis effacée. Deux clés MLE sont gardées : la séquence courante
  et la suivante (rotation). Aucune commande ne rend ni la clé réseau ni une
  clé dérivée ; une séquence étrangère ne fait jamais relire la clé réseau.
  Une trame à clé inconnue fait lire la séquence de la pile au plus une fois
  par tour de `loop()` ; la clé réseau n'est lue qu'une fois par séquence de
  la pile, même si la dérivation échoue (tas épuisé) : elle n'est relue qu'à
  la rotation suivante. Un échec de dérivation arrête donc l'écoute jusqu'à la
  rotation suivante de la clé (672 h par défaut, soit 4 semaines) ou jusqu'à un
  redémarrage de la sonde ; ce cas, très improbable, demande un tas épuisé au
  moment de la dérivation. Il se voit : `mle` ne progresse plus dans `ecoute`
  de `etat`, et la couverture reste à 0 dans l'app ; un redémarrage le règle.
  Seul un verrou refusé la fait retenter, au tour suivant.
- **La table des routeurs entendus**, par ExtMac, 32 entrées : RLOC16 (TLV
  Source Address), partition (TLV Leader Data), dernière Route64 brute (au
  plus 72 octets), signal (dernier, minimum et maximum depuis l'entrée),
  nombre de messages, âge du dernier. Seuls les émetteurs dont le RLOC16 est
  celui d'un routeur y entrent ; un routeur muet depuis 10 minutes en sort ;
  table pleine, le plus ancien laisse sa place. `annonces` la rend : c'est
  l'app qui décode les Route64.

## Résolution d'adresse (1.1.0)

`resoudre <ipv6> <id>` envoie une demande d'écho ICMPv6
(`otIcmp6SendEchoRequest`) : OpenThread résout l'adresse (Address Query). Un
routeur répond pour lui-même ; le parent d'un enfant, endormi ou non, répond à
sa place : les routeurs Apple avec leur propre RLOC16, les routeurs tiers avec
celui de l'enfant. La sonde lit ensuite son cache d'adresses
(`otThreadGetNextCacheEntry`) toutes les 250 ms, 15 s au plus : `rloc16`, et
`mleid` (le ML-EID de l'appareil) quand la réponse l'a porté. Au plus 8 en
vol, comme `diag`.

Depuis la 1.1.1, la réponse porte aussi `repondu` (juste après `rloc16`). Une
entrée du cache d'adresses peut dater d'une résolution précédente (la sonde
résout chaque appareil toutes les 30 min) : « trouvée » ne dit donc pas que
l'appareil est là. `repondu:true` veut dire que **l'appareil lui-même a répondu
à l'écho ICMPv6 pendant cette résolution** : la sonde enregistre un
gestionnaire ICMPv6 (`otIcmp6RegisterHandler`) et note une réponse d'écho
(Echo Reply) dont l'identifiant (celui de `<id>`, sur 16 bits) et l'adresse
source sont ceux de la résolution en vol. La résolution se termine dès que
l'entrée est trouvée **et** que la réponse est venue ; sinon elle attend jusqu'aux
15 s, puis rend `repondu:false` si la réponse n'est pas venue (`ms` reste le
temps jusqu'à l'entrée de cache). Limite : un appareil endormi qui ne se réveille
pas dans les 15 s rend `repondu:false` (le parent répond à la requête d'adresse,
pas à l'écho). Une réponse d'écho sans entrée de cache à la fin reste
`introuvable` : elle ne donne pas le RLOC16.

Le diagnostic (`diag`) n'est accepté que sur les adresses internes du réseau
(RLOC, ML-EID) : c'est au ML-EID que l'app demande la TLV 9 (compteurs MAC)
d'un enfant.

## Accès par le réseau Thread

Repris tel quel du pont Halo de benq (`src/net_udp.cpp`, `src/h1_proto.cpp`,
`docs/PROTOCOLE-JSON.md`, section 10) : la sonde peut être débranchée du Mac
et promenée dans la maison, l'app la joint par le réseau.

- **UDP sur IPv6, port 5480**, socket d'OpenThread, par l'adresse OMR de la
  sonde, à travers les routeurs de bordure. L'app vise `<hote>.local:5480`
  (`hote` : le nom d'hôte SRP que Matter enregistre, donné par `bonjour`). Le
  Mac a besoin d'une route vers le préfixe OMR : voir « Route vers le réseau
  Thread » dans le README du dépôt.
- **Clé** de 32 octets, créée par l'USB seulement (`cle nouvelle`) :
  `cle = HMAC-SHA256(clé = aléa de l'app, message = aléa de la carte)`,
  gardée en NVS, rendue une seule fois, jamais imprimée ailleurs. Une
  nouvelle clé ou son effacement fait tomber toutes les sessions.
- **Enveloppe H1** du pont Halo : poignée de main `SALUT`/`DEFI`, puis
  messages `H1 <sid> <ctr> <mac> <charge>` (HMAC-SHA256 tronqué, sens `A`/`C`,
  fenêtre de 32 contre le rejeu, 2 `DEFI` par seconde au plus, 2 sessions et
  une provisoire, comparaisons en temps constant). Intégrité et authenticité,
  **pas de confidentialité** : le trafic se lit sur le réseau local.
- **Charges** : vers la sonde `<rid> <commande>` (le même texte que sur
  l'USB) ; en retour `<rid> <ligne JSON>` (la ligne de l'USB sans RS ni LF),
  1100 octets au plus. `routeurs` se coupe plus tôt (`suite`) : une ligne
  perdue en route donne une table partielle, ou aucune si la dernière
  (`"suite":false`) se perd ; l'app en tient compte. Un
  `diag` trop long répond `{"v":1,"t":"diag","id":…,"cible":…,"ok":false,"erreur":"trop_long"}` ;
  `voisins` au-delà de 1100 octets répond
  `{"v":1,"t":"erreur","erreur":"ligne trop longue"}` (entier sur l'USB).
- **Permis à distance** : `bonjour` (sans code d'appairage ni QR code :
  `null`), `etat`, `voisins`, `routeurs`, `diag`, et depuis la 1.1.0
  `annonces` et `resoudre`. Tout le reste répond
  `{"v":1,"t":"erreur","erreur":"refuse"}`. Une ligne d'`annonces` fait moins
  de 400 octets.
- **Un rid répété** dans la même session ne relance rien : la sonde renvoie
  la réponse gardée (les 8 dernières réponses, dans la limite de 4096 octets
  par session ; au-delà, un rid répété relance la commande, une lecture), ou
  ne dit rien si un `diag`, un `resoudre` ou un `annonces` de ce rid est
  encore en vol. `annonces` n'est jamais gardée : après la fin de son envoi,
  un rid répété relance la lecture (sans effet).
  Prendre un rid neuf par requête.
- **Cadence** : 20 commandes par seconde glissante et par session au plus
  (comme Halo) ; au-delà, rien n'est exécuté ni répondu, l'app renvoie.
  L'app, elle, envoie au plus 18 nouvelles commandes par seconde glissante ;
  ses renvois ne comptent pas dans ces 18. La carte compte ses refus depuis
  le démarrage (`udp.refus_cadence` de `cle`, depuis la 1.0.3) : ce compteur
  dit si la marge suffit.
- **Sans clé : silence total**, ni réponse ni ICMPv6 « port injoignable »
  (le port reste tenu par OpenThread).
- Débit plafonné comme Halo (3000 octets/s, priorité basse, réserve de
  tampons OpenThread). Une réponse que la file d'émission ne prend pas est
  perdue en route (`udp.lignes_perdues` de `cle`) mais gardée : le renvoi
  du rid la rattrape.

## Outils d'essai

- `sonde_essai.py <port> <capture.jsonl> <commande>…` : envoie des commandes
  par l'USB, garde les réponses, décode les TLV et la table des routeurs ;
  depuis la 1.1.0, les annonces (les liens de chaque Route64) et les
  résolutions (`resoudre`, 20 s d'attente au plus).
  `"cle nouvelle"` : l'outil tire l'aléa et range la clé dans le fichier
  `SONDE_CLE` (0600) ; il ne lit alors rien à l'écran de ce qui arrive. La
  clé n'est jamais affichée ni capturée : toute ligne reçue affichée telle
  quelle (abîmée, journal de la carte) a ses suites de 16 hexa ou plus
  masquées.
- `sonde_essai.py udp:<hote> <capture.jsonl> <commande>…` : les mêmes
  commandes par le réseau (H1, renvoi du même rid à 2 s et 4 s). Clé :
  `SONDE_CLE`, sinon le trousseau (service `fr.djoko.maillage.iot.sonde-thread`, compte
  = nom d'hôte, la clé de l'app). `refus` vérifie le port (DELAI attendu,
  avec ou sans clé).
- `tournee_essai.py <port> <capture.jsonl>` : une tournée à la main par
  l'USB (chef, routeurs, quelques enfants).

Les captures brutes contiennent les adresses du réseau de la maison. À passer
par `outils/anonymiser-sonde.py` avant de les mettre dans le dépôt. Il
connaît les messages de la 1.0.3 (tous ceux du tableau, réponses « occupée »
comprises) et ceux de la capture du 29/09, la forme de chaque champ et les
TLV de diagnostic que la tournée demande, jusque dans la Network Data ; il
échoue devant tout le reste, sans rien écrire, et ne cite que des noms.
Une capture déjà anonymisée ressort telle quelle.

## Tests sur le Mac

`sh sonde/test/lancer.sh` : les tests hôte purs, sans carte (clang, ASan et
UBSan ; ce ne sont pas des tests `pio test`) : l'enveloppe H1
(`test_h1.cpp`, repris de benq) et les briques pures de `distant.cpp` et
de `voyant.h` (`test_distant.cpp` : rid, liste blanche, réponses gardées,
cadence ; depuis la 1.0.3, lecture des entiers, reprises CoAP d'un `diag` et
séquence de la LED ; depuis la 1.1.1, chaque motif du tronc commun, ses
durées et ses priorités, et la fin des effets d'identification) ; depuis
la 1.1.0, l'écoute (`test_mle.cpp` : dérivation
de la clé MLE, AES-CCM et refus d'un MIC faux, trames 802.15.4 de 2006 et de
2015, IE, PAN, IPHC, UDP compressé ou non, TLV, clés gardées et leur
lecture sur la pile (une fois par séquence, même après un échec), table des
routeurs entendus, trames tronquées, abîmées ou tirées au hasard). Ses
vecteurs (`test/vecteurs_mle.h`) viennent de `test/vecteurs_mle.py`, à clé et
adresses inventées, calculés à part (bibliothèque `cryptography`, présente
dans le Python de PlatformIO) :
`~/.platformio/penv/bin/python sonde/test/vecteurs_mle.py` les récrit,
`--verifier` les compare au fichier commité. Sur le Mac, CommonCrypto n'a pas
d'AES-CCM : le test le bâtit sur son AES-ECB.

`python3 -m unittest discover -s sonde/test` : les tests Python, sans carte ni
réseau : le masquage de la clé par `sonde_essai.py` (à l'écran et dans la
capture, y compris sur une ligne abîmée), le décodage du TLV 7 et
l'anonymiseur (sa garde, ses remplacements, la capture du dépôt qui ressort
telle quelle). `lancer.sh` ne les lance pas.
