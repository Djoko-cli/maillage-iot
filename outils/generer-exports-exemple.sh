#!/bin/bash
# Regenere les exports d'exemple PROVISOIRES de Maillage Thread 1.3.0 et de Maillage Zigbee 1.1.1 (phase 4, tache 2) :
#   bash outils/generer-exports-exemple.sh [dossier de sortie]
# Par defaut : MaillageIoTTests/Ressources/exports (les dossiers thread-1.3.0 et zigbee-1.1.1 y sont recrees ; rien
# d'autre n'y est touche). Le generateur (outils/exports-exemple/Generateur.swift) est compile avec le contrat d'export
# (MaillageCoeur/Reprise/ContratExport.swift) : le manifeste, les empreintes et reglages.json viennent du contrat. Aucune
# donnee reelle : valeurs inventees. Ces exports seront remplaces a la tache 9 par ceux des anciennes apps.
set -eu
cd "$(dirname "$0")/.."
SORTIE=${1:-MaillageIoTTests/Ressources/exports}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  MaillageCoeur/Reprise/ContratExport.swift outils/exports-exemple/Generateur.swift outils/exports-exemple/main.swift \
  -o "$TMP/generateur"
mkdir -p "$SORTIE"
"$TMP/generateur" "$SORTIE"
echo "exports d'exemple ecrits dans $SORTIE"
