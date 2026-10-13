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
