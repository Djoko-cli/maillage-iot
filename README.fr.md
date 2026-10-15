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

## Crédits et marques

Thread est une marque du Thread Group, et Zigbee est une marque de la Connectivity Standards Alliance. Elles
appartiennent à leurs titulaires. Les glyphes de Thread et de Zigbee des onglets des Réglages sont des redessins
simplifiés, faits pour cette app, et ne servent qu'à identifier ces deux réseaux. Ils ne signifient pas que Maillage IoT
est fait, soutenu ou approuvé par le Thread Group ou par la Connectivity Standards Alliance. L'icône de l'app est
générée par [outils/icone/generer.swift](outils/icone/generer.swift).
