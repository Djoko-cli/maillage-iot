[English](README.md) · **Français**

# Maillage IoT

Maillage IoT montre les maillages radio d'une maison sur ses pièces, en 2D et en 3D : Thread et Zigbee
ensemble, depuis la barre des menus du Mac. Elle réunit deux apps plus anciennes,
[Maillage Thread](https://github.com/Djoko-cli/maillage-thread) et
[Maillage Zigbee](https://github.com/Djoko-cli/maillage-zigbee), qu'elle remplace.

## Ce qu'elle fait

- Les nœuds Thread et Zigbee sur la même vue par pièces : ronds pour Thread, hexagonaux pour Zigbee, la
  couleur des liens pour la qualité, et deux interrupteurs pour montrer ou masquer chaque réseau.
- Les deux sondes en même temps (un ESP32-C6 pour Thread, un autre pour Zigbee), par USB ou par le réseau.
- Les noms, les pièces et les étages de l'app Maison, par l'assistant facultatif Passeur Noms.
- Un seul journal, une seule série de notifications.
- Les réglages, les noms et l'historique repris de Maillage Thread et de Maillage Zigbee (voir plus bas).

## Installer

1. Télécharger le `.dmg` de la [dernière version](https://github.com/Djoko-cli/maillage-iot/releases/latest), puis
   glisser Maillage IoT dans Applications. macOS 26 ou plus récent est nécessaire.
2. L'app est signée avec un Developer ID d'Apple et notarisée par Apple : elle s'ouvre sans passer par Réglages
   Système, Confidentialité et sécurité.
3. Au premier lancement, macOS demande l'accès au réseau local et aux notifications. Autoriser les deux.

Les mises à jour sont automatiques : Maillage IoT cherche une nouvelle version au lancement puis toutes les
24 heures, la télécharge et l'installe.

## Venir de Maillage Thread ou de Maillage Zigbee

1. Mettre l'ancienne app à sa dernière version (Maillage Thread 1.4.0 ou Maillage Zigbee 1.2.0), puis choisir
   « Exporter pour Maillage IoT… ». Elle écrit un dossier, et l'ancienne app continue de marcher comme avant.
2. Dans Maillage IoT, l'assistant du premier lancement propose de le reprendre. La même entrée reste dans
   Réglages › Général, sous « Reprendre des données… », pour la seconde app.
3. Les surnoms, les pièces, l'historique (90 jours au plus), le journal et les réglages sont repris. Rien n'est
   repris tant que l'export n'est pas vérifié, et si quelque chose échoue, rien ne change.
4. macOS peut demander l'accès au trousseau, pour copier les clés des anciennes apps (les anciens éléments ne sont
   pas modifiés), et l'Automatisation, seulement pour quitter l'ancienne app avant la reprise. Refuser le trousseau
   oblige à appairer de nouveau le pont Hue et à brancher chaque sonde en USB.

## Passeur Noms (facultatif)

Passeur Noms est un assistant en arrière-plan qui lit les noms, les pièces et les étages de l'app Maison. Il ne
figure pas dans le téléchargement : il se compile sur le Mac, avec une équipe du programme Apple Developer, en
lançant `outils/passeur.sh` depuis un clone de ce dépôt. Maillage IoT marche sans lui.

## Conception

La conception est dans [docs/superpowers/specs/2026-10-13-maillage-iot-design.md](docs/superpowers/specs/2026-10-13-maillage-iot-design.md),
et le travail est planifié étape par étape dans [docs/superpowers/plans](docs/superpowers/plans).

## Crédits et marques

Thread est une marque du Thread Group, et Zigbee est une marque de la Connectivity Standards Alliance. Elles
appartiennent à leurs titulaires. Les glyphes de Thread et de Zigbee des onglets des Réglages sont des redessins
simplifiés, faits pour cette app, et ne servent qu'à identifier ces deux réseaux. Ils ne signifient pas que Maillage IoT
est fait, soutenu ou approuvé par le Thread Group ou par la Connectivity Standards Alliance. L'icône de l'app est
générée par [outils/icone/generer.swift](outils/icone/generer.swift).
