# Release notes · Notes de version

Maillage IoT: one section per published version, in English then in French. `outils/publier.sh` takes from it the
notes of the GitHub release and those of the update window.

Maillage IoT : une section par version publiée, en anglais puis en français. `outils/publier.sh` en tire les notes
de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

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
- **Automatic updates**: Maillage IoT checks for a new version at launch and every 24 hours, then downloads and
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
- **Mises à jour automatiques** : Maillage IoT cherche une nouvelle version au lancement puis toutes les 24 heures,
  la télécharge et l'installe.
- **Passeur Noms, l'assistant qui lit les noms, les pièces et les étages de l'app Maison, reste facultatif et ne
  figure pas dans le téléchargement.** Il se compile sur le Mac avec `outils/passeur.sh`, depuis le dépôt.
