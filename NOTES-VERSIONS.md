# Release notes · Notes de version

Maillage IoT: one section per published version, in English then in French. `outils/publier.sh` takes from it the
notes of the GitHub release and those of the update window.

Maillage IoT : une section par version publiée, en anglais puis en français. `outils/publier.sh` en tire les notes
de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

## 1.1.0

**English**

- **Health panel in the room view**: a glass panel lists what needs attention, such as a device that disappeared, a
  router that dropped or a split Thread network, and shows where it is.
- **Room suggested by AirPlay**: a border router that announces itself over AirPlay gets a room suggestion in its
  card, to place it or ignore it.
- **A room in several Home zones** goes to the most precise one, the zone with the fewest rooms. Right-click a room,
  then "Move to Zone…", to choose another one; the choice is kept, and "Automatically" goes back to the rule.
- **One smooth movement when a room changes floor**: the room glides, the floor it leaves fades out and the floor it
  joins fades in. After a choice made in the view, the other floors keep their place.
- **The log, notifications and menu name the device's room.**
- **Clearer room view**: each pair of nodes is drawn once, links to another room light up like the parent link they
  replace, and the 3D house bubble fills the free space.
- **More reliable Thread splits**: a split network is followed for its whole duration and ends after three
  consistent readings.
- **No more false "disappeared" Thread devices**: a Matter device over Wi-Fi or Ethernet that had no address yet at
  launch waits for it, and stays out of Thread.
- **Much lighter on the processor**: nothing is drawn while the room view is hidden, closed or minimized (about 1 %
  instead of 44 %), and the slow rotation runs at 30 frames per second, full speed as soon as you move the house.
- **Settings**: a crossfade between tabs, pages kept at the top.

**Français**

- **Panneau de santé dans la vue par pièces** : un panneau en verre liste ce qui demande attention, comme un appareil
  disparu, un routeur tombé ou un réseau Thread scindé, et montre où il se trouve.
- **Pièce proposée par AirPlay** : un routeur de bordure qui s'annonce en AirPlay reçoit une pièce proposée dans sa
  fiche, pour le placer ou l'ignorer.
- **Une pièce de plusieurs zones de Maison** va dans la plus précise, celle qui compte le moins de pièces. Clic droit
  sur la pièce, puis « Ranger dans la zone… », pour en choisir une autre ; le choix est gardé, et
  « Automatiquement » revient à la règle.
- **Un seul mouvement fluide quand une pièce change d'étage** : la pièce glisse, l'étage qu'elle quitte s'efface et
  celui qu'elle rejoint apparaît. Après un choix fait dans la vue, les autres étages gardent leur place.
- **Le journal, les notifications et le menu nomment la pièce de l'appareil.**
- **Vue par pièces plus lisible** : chaque paire de nœuds n'est dessinée qu'une fois, les liens vers une autre pièce
  s'éclairent comme le lien parent qu'ils remplacent, et la bulle de la maison en 3D remplit l'espace libre.
- **Scissions de Thread plus fiables** : un réseau scindé est suivi pendant toute la scission, qui se termine après
  trois relevés concordants.
- **Plus de faux appareils Thread « disparus »** : un appareil Matter en Wi-Fi ou en Ethernet encore sans adresse au
  lancement attend la sienne, et reste hors de Thread.
- **Beaucoup plus léger pour le processeur** : rien n'est dessiné quand la vue par pièces est cachée, fermée ou
  réduite (environ 1 % au lieu de 44 %), et la rotation lente tourne à 30 images par seconde, à pleine cadence dès
  qu'on fait bouger la maison.
- **Réglages** : un fondu enchaîné entre les onglets, pages collées en haut.

## 1.0.0

**English**

- **One app for Thread and Zigbee.** Maillage IoT replaces Maillage Thread and Maillage Zigbee. Both networks share
  one room view (round nodes for Thread, hexagonal nodes for Zigbee, two switches to show or hide each network), one
  log, one set of notifications and one menu bar icon.
- **Two probes at once**: an ESP32-C6 for Thread and another for Zigbee, over USB or the network. Each network can be
  switched off in Settings, with "Enable this protocol".
- **Signed with an Apple Developer ID and notarized by Apple**: a fresh download opens without going through System
  Settings, Privacy & Security, "Open Anyway". It needs macOS 26 or later.
- **Bringing over your data from Maillage Thread 1.4.0 or Maillage Zigbee 1.2.0.** In the old app, choose "Export for
  Maillage IoT…". In Maillage IoT, the first-launch assistant (or Settings › General, "Import data…") reads that
  folder. The nicknames, rooms, history (90 days at most), log and settings are brought over. The old app is not
  modified, nothing is imported until the export has been verified, and if anything fails nothing is changed.
- **Keychain prompt at the first connection**, to copy the keys of the old apps (Hue bridge, Thread probe, Zigbee
  probe) into Maillage IoT. The old items are never modified or deleted. If you refuse, pair the bridge again and
  plug each probe in over USB.
- **Automation prompt**, only to quit Maillage Thread or Maillage Zigbee before the import, because a USB probe can
  only have one owner. No other app is concerned.
- **Local network and notifications prompts**: the first one lets Maillage IoT find border routers, bridges and
  probes on the network, the second one lets it warn you when a router drops.
- **Automatic updates**: Maillage IoT checks for a new version every 24 hours, then downloads and
  installs it.
- **Passeur Noms, the helper that reads names, rooms and floors from the Home app, stays optional and is not in the
  download.** It is built on your Mac with `outils/passeur.sh` from the repository.

**Français**

- **Une seule app pour Thread et Zigbee.** Maillage IoT remplace Maillage Thread et Maillage Zigbee. Les deux
  réseaux se partagent une vue par pièces (nœuds ronds pour Thread, hexagonaux pour Zigbee, deux interrupteurs pour
  montrer ou masquer chaque réseau), un journal, une série de notifications et une icône dans la barre des menus.
- **Deux sondes en même temps** : un ESP32-C6 pour Thread et un autre pour Zigbee, par USB ou par le réseau. Chaque
  réseau peut être éteint dans les Réglages, avec « Activer ce protocole ».
- **Signée avec un Developer ID d'Apple et notarisée par Apple** : un téléchargement neuf s'ouvre sans passer par
  Réglages Système, Confidentialité et sécurité, « Ouvrir quand même ». macOS 26 ou plus récent est nécessaire.
- **Reprise des données de Maillage Thread 1.4.0 ou de Maillage Zigbee 1.2.0.** Dans l'ancienne app, choisir
  « Exporter pour Maillage IoT… ». Dans Maillage IoT, l'assistant du premier lancement (ou Réglages › Général,
  « Reprendre des données… ») lit ce dossier. Les surnoms, les pièces, l'historique (90 jours au plus), le journal et
  les réglages sont repris. L'ancienne app n'est pas modifiée, rien n'est repris tant que l'export n'est pas vérifié,
  et si quelque chose échoue, rien ne change.
- **Invite du trousseau à la première connexion**, pour copier les clés des anciennes apps (pont Hue, sonde Thread,
  sonde Zigbee) dans Maillage IoT. Les anciens éléments ne sont jamais modifiés ni effacés. En cas de refus, il faut
  appairer de nouveau le pont et brancher chaque sonde en USB.
- **Invite d'Automatisation**, seulement pour quitter Maillage Thread ou Maillage Zigbee avant la reprise, car une
  sonde USB ne peut avoir qu'un seul maître. Aucune autre app n'est concernée.
- **Invites du réseau local et des notifications** : la première laisse Maillage IoT trouver les routeurs de
  bordure, les ponts et les sondes sur le réseau, la seconde le laisse prévenir quand un routeur disparaît.
- **Mises à jour automatiques** : Maillage IoT cherche une nouvelle version toutes les 24 heures,
  la télécharge et l'installe.
- **Passeur Noms, l'assistant qui lit les noms, les pièces et les étages de l'app Maison, reste facultatif et ne
  figure pas dans le téléchargement.** Il se compile sur le Mac avec `outils/passeur.sh`, depuis le dépôt.
