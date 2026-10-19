# Pièce proposée aux HomePod et à l'Apple TV — conception

Date : 19/10/2026. Backlog §8 de `2026-10-13-maillage-iot-design.md` (demande de Djoko, banc de l'étape 3b, 16/10).
Djoko a demandé de se lancer sans questions : les choix ci-dessous sont ceux de Claude, à valider au banc.

## 1. Intention

HomeKit ne donne pas à une app tierce la pièce des HomePod et de l'Apple TV : leur pièce n'est connue que par un choix
manuel (« Placer dans une pièce… »). Ils s'annoncent aussi par AirPlay (mDNS, `_airplay._tcp`) sous le nom qu'on leur
donne dans Maison, souvent celui de leur pièce. L'app **propose** cette pièce ; Djoko la **confirme** d'un clic. Rien
n'est jamais imposé : un nom sans pièce, ou un rattachement douteux, ne donne aucune proposition.

## 2. Comportement

- **Écoute** : `_airplay._tcp` s'ajoute aux types que le recenseur Thread écoute déjà (`Recenseur.types`) et à
  `NSBonjourServices` (app et répétition). Le nom d'instance et le TXT (`model`) sont lus ; l'hôte est résolu.
- **Rattachement** : un service AirPlay est rattaché à un routeur de bordure Thread (HomePod, Apple TV) quand **ils ont
  le même nom d'hôte** mDNS (résolution `_meshcop._udp` d'un côté, `_airplay._tcp` de l'autre), à la casse et au point
  final près. Pas d'autre heuristique (pas de rattachement par le seul nom affiché). À vérifier au banc sur le réseau
  réel ; si le nom d'hôte ne suffit pas, le dire avant d'en inventer un autre.
- **Pièce proposée** : seulement si le nom AirPlay contient **une pièce connue de Maison** (liste des pièces du relevé
  du démon), comparée sans casse ni accents, en mot entier ; s'il en contient plusieurs, la plus longue. Sinon, aucune
  proposition. Un nœud qui a déjà une pièce (Maison ou choix de Djoko) n'a pas de proposition.
- **Où** : dans la fiche du nœud (`FicheNoeud`), une ligne « Pièce proposée : <pièce> (d'après AirPlay) » avec un bouton
  « Placer ici » ; le bouton fait exactement ce que fait « Placer dans une pièce… » pour cette pièce (`PiecesChoisies`),
  donc l'annulation et la persistance existantes s'appliquent. Un second bouton « Ignorer » masque la proposition pour ce
  nœud (mémorisé à côté des choix de pièces) ; ignorée, elle ne revient pas tant que le nom AirPlay ne change pas.
- **Textes** : français et anglais.
- **Démo** : la démo reçoit un HomePod et une Apple TV sans pièce, avec un service AirPlay inventé dont le nom contient
  une pièce de la démo, pour montrer la proposition (sans changer les références de rejeu : ajout réservé à ce qui n'est
  pas comparé, sinon le dire).

## 3. Hors sujet

- Pas de placement automatique ; pas de proposition pour des appareils non Apple ; pas d'écoute de `_raop._tcp` ni de
  Companion Link ; pas de lecture de l'adresse MAC.

## 4. Contraintes

- Swift 6 strict ; aucune valeur réelle dans le dépôt (tests et démo inventés).
- Ajouter un type Bonjour par une mise à jour marche sans redémarrage (répétition du 18/10) ; la note de version le dira
  quand même (« autoriser le réseau local si macOS le redemande »).
