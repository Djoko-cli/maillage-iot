# Capture de la sonde, nuit du 28 au 29/09/2026 (23:44-00:09, heure du Mac)

Essai préalable au plan 3a (spec de la sonde, sections 7 et 8) : la troisième
carte ESP32-C6, avec le firmware d'essai de `sonde/`, appairée à Maison, puis
interrogée par l'USB. Données des tests de `MaillageCoeur/Maillage`.

| Fichier | Contenu | Obtenu par |
|---|---|---|
| `capture-sonde.jsonl` | 64 messages de la sonde (2 `bonjour`, 9 `etat`, 53 `diag`), un par ligne, avec l'heure de réception : tournée d'essai (chef, 7 routeurs, 3 enfants), Network Data, essais vers les adresses OMR, balayage des enfants de `AC00` | `sonde/sonde_essai.py` et `sonde/tournee_essai.py`, puis `outils/anonymiser-sonde.py` |

**Anonymisée** (décision de Djoko, 29/09). Les valeurs d'origine sont
remplacées de façon cohérente d'une ligne à l'autre, jusque dans les TLV :
- les ExtMac, en `E0…`, et les adresses lien-local qui en dérivent ;
- les préfixes /48, en `fd00:…` :
  - `fd00:1111:2222` pour le réseau maillé ;
  - `fd00:5555:6666` pour l'OMR et le NAT64 ;
  - `fd00:3333:4444` pour le préfixe par défaut d'OpenThread, avant l'appairage ;
- les identifiants d'interface, sauf ceux des RLOC et ALOC ;
- le `xp`, en `A0A1A2A3A4A5A6A7`, et la MAC de la sonde, en `A0…`.

Le code d'appairage et le QR code sont retirés (`null`), non remplacés.
Les RLOC16, qualités de lien, délais et versions de pile sont gardés, et les
`id` des `diag` aussi : ils reprennent ceux des commandes envoyées
(`diag <cible> <TLV> <id>`), choisis à la main ou par
`sonde/tournee_essai.py`, qui numérote à partir de 101. Ce ne sont pas des
identifiants de la sonde. La capture brute n'est pas dans le dépôt.

**Réécriture du 05/10/2026.** L'anonymiseur gardait deux identifiants réels :
la partition et le 4e groupe du préfixe de maillage local, derrière
`fd00:1111:2222`. L'historique du dépôt a été réécrit (spec de
l'anonymisation, `docs/superpowers/specs/2026-10-05-anonymisation-design.md`) :
ils sont désormais inventés, jusque dans les TLV, et la capture ne garde plus
aucun identifiant réel. Le canal radio est gardé, comme dans le reste du dépôt.

Ce que la capture montre (spec de la sonde, section 8) :
- **Les 5 routeurs de bordure d'Apple ne répondent jamais** : `0400`, `AC00`,
  `B400`, `CC00` et `E400`.
- **Le chef `6000` et le routeur `5000`**, deux appareils Matter EFR32,
  répondent en 50 à 120 ms en général. La première requête prend 2,8 s, et
  celle de la Network Data 2,9 s.
- **Les enfants répondent à leur RLOC** en 0,2 à 5 s, mais **jamais à leur
  adresse OMR** (ids 301 à 309).
- **Le balayage sous `AC00`** : 6 enfants de `AC03` à `AC08` (ids 501 à 512).
- **La sonde change de parent** : `E400`, puis `AC00`.
