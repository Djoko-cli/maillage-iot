# Exports d'exemple provisoires de la reprise (phase 4)

Deux dossiers d'export au contrat v1 (`MaillageCoeur/Reprise/ContratExport.swift`), aux formats que Maillage Thread 1.3.0 et
Maillage Zigbee 1.1.1 écrivent, avec des **valeurs inventées seulement** (identifiants comme `0000000000000001`,
`SONDE-T1`, « Pièce 1 », « Routeur 1 »). Ils servent aux tests de validation, de conversion et d'import. Les exports que produisent
les anciennes apps (tâche 9) s'**ajoutent** à côté, sans les remplacer (voir ci-dessous) : les attentes des tests ne changent pas.

| Dossier | App source | Version |
|---|---|---|
| `thread-1.3.0/` | Maillage Thread | 1.3.0 |
| `zigbee-1.1.1/` | Maillage Zigbee | 1.1.1 |
| `thread-1.4.0-export/` | Maillage Thread | 1.4.0 (écrit par l'app elle-même) |
| `zigbee-1.2.0-export/` | Maillage Zigbee | 1.2.0 (écrit par l'app elle-même) |

## Exports écrits par les anciennes apps (tâche 9)

`thread-1.4.0-export/` et `zigbee-1.2.0-export/` sont des **copies à l'octet** des exports d'exemple que Maillage Thread 1.4.0 et
Maillage Zigbee 1.2.0 produisent dans leurs propres tests (`docs/export-exemple/` de chaque dépôt, valeurs inventées). On ne les
modifie jamais ici : `ORIGINE.md` dit de quel dépôt et de quel commit ils viennent, et

```bash
bash outils/recopier-exports-anciennes-apps.sh              # recopie depuis les dépôts voisins, vérifie les empreintes
bash outils/recopier-exports-anciennes-apps.sh --verifier   # ne modifie rien : les copies sont-elles à jour ?
```

les met à jour (`DEPOT_THREAD=` / `DEPOT_ZIGBEE=` pour d'autres emplacements). Le test `ExportsAnciennesAppsTests` les fait passer par
toute la chaîne : contrat, validation, conversion, application, réimport. Les dates de ces exports sont aussi le 2026-10-17 12:00 UTC.

## Date de référence fixe

**2026-10-17 12:00:00 UTC** : la date du manifeste, et le « maintenant » des tests de la coupe à 90 jours
(`GenerateurExportsExemple.dateReference`). Un fichier mensuel dont le mois est fini depuis plus de 90 jours à cette date est
écarté à l'import. Un mois fini le 1er juillet ou avant l'est (juin 2026 : fini depuis 108 jours) ; juillet 2026 (fini le
1er août, il y a 77 jours) est gardé.

- Écartés : `maillage-2026-04.jsonl` et `Journal/journal-2026-04.jsonl` (les deux apps).
- Gardés : `maillage-2026-07.jsonl`, `maillage-2026-09.jsonl` et `maillage-2026-10.jsonl` (Thread), `maillage-2026-10.jsonl`
  (Zigbee), `Journal/journal-2026-10.jsonl` (les deux apps).

## Ce que contient chaque export

Chaque fichier de l'inventaire (`inventaire-phase-4.md`, sections 1 et 2) est présent au moins une fois, avec les clés brutes de
l'ancienne app (aucun préfixe `thread:` ou `zigbee:`). Les lignes du journal n'ont **pas** de clé `protocole` (Thread 1.3.0
comme Zigbee 1.1.1 les écrivent ainsi : l'import ajoute `"protocole":"zigbee"` aux lignes de Zigbee). `reglages.json` porte
tous les réglages de l'inventaire (`valeurs`) et cite en `nonRepris` ce que l'app laisse sans le reprendre : Sparkle (`SU*`), états
de fenêtre (`NSWindow Frame *`, `NSNav*`, `NSOSPLastRootDirectory`), `reglages.onglet`, `dossierNoms`. Le manifeste cite en
`fichiersNonRepris` des fichiers vus mais non copiés (`.DS_Store`, un fichier `*.illisible-*.json`, un fichier hors contrat).

Particularités reproduites des vraies données : le domicile de Zigbee dans `pieces-routeurs.json` et `positions-pieces.json`
est tantôt un nom de maison, tantôt l'identifiant du pont (16 chiffres hexadécimaux) ; `pieces-routeurs.json` de Zigbee n'a que
`appareils` ; `releve-maison.json` (Zigbee) et `noms.json` (Thread) sont deux relevés de Maison (v2) à des dates différentes ;
`pont.hue` est un `Data` (JSON du pont retenu, sans sa clé).

## Régénérer

```bash
bash outils/generer-exports-exemple.sh
```

Le script compile `outils/exports-exemple/Generateur.swift` avec le contrat, recrée les deux dossiers et relit chacun avec
`verifierDossier`. Le manifeste, les tailles, les empreintes SHA-256 et `reglages.json` viennent du contrat, jamais de la
main. Le test `ExportsExempleTests` relance le même générateur dans un dossier temporaire et compare chaque octet aux
dossiers commités : après toute modification du générateur, régénérer puis commiter les dossiers.

## Écarts connus avec les vrais fichiers

Voir le rapport de la tâche 2 (`.superpowers/sdd/2026-10-17-maillage-iot-phase-4/task-2-report.md`) : tailles bien plus petites,
aucun routeur ni appareil réel, JSON écrit par `JSONSerialization` aux mêmes options que les encodeurs des apps, `réglages
notification.*` présents alors que les vraies plists n'en ont aucun.
