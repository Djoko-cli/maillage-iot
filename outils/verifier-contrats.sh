#!/bin/bash
# Verifie que les fichiers de contrat partages sont identiques a l'octet (cmp) dans les trois depots :
#   bash outils/verifier-contrats.sh
# Fichiers compares, au meme chemin relatif dans chaque depot (la copie de reference est celle de ce depot) :
#   MaillageCoeur/Reprise/ContratExport.swift   contrat de l'export de reprise (spec 4.1, 6.8)
#   MaillageCoeurTests/ContratExportTests.swift ses tests, recopies avec lui
#   MaillageCoeur/Noms/ProtocolePasseur.swift   contrat du demon Passeur Noms
# Depots compares, par defaut les voisins de celui-ci (meme dossier parent) :
#   ../maillage-thread   (Maillage Thread)      ../maillage-zigbee   (Maillage Zigbee)
# Pour d'autres emplacements : DEPOT_THREAD=/chemin DEPOT_ZIGBEE=/chemin bash outils/verifier-contrats.sh
# (ou MAILLAGE_DEPOTS=/dossier-parent). Un depot ou un fichier absent n'est pas une erreur : "pas encore recopie"
# (le contrat d'export est recopie dans les anciennes apps apres ce depot). Une copie presente mais differente est un
# defaut. Code 0 : aucune difference ; code 1 : au moins une copie differente, ou fichier de reference absent.
# Mode avertissement : CONTRATS_AVERTIR_SEULEMENT=1 affiche les defauts comme des "avertissement(s)" et sort avec le
# code 0. outils/tester.sh l'appelle en mode bloquant par defaut (les deux anciennes apps ont recopie le contrat) ;
# CONTRATS_AVERTIR_SEULEMENT=1 outils/tester.sh le ramene a un avertissement.
# Ne modifie rien.
set -u
cd "$(dirname "$0")/.." || exit 1
RACINE=$(pwd)
PARENT=${MAILLAGE_DEPOTS:-$(dirname "$RACINE")}
FICHIERS="MaillageCoeur/Reprise/ContratExport.swift MaillageCoeurTests/ContratExportTests.swift MaillageCoeur/Noms/ProtocolePasseur.swift"
DEPOTS="thread:${DEPOT_THREAD:-$PARENT/maillage-thread} zigbee:${DEPOT_ZIGBEE:-$PARENT/maillage-zigbee}"
DEFAUTS=0
IDENTIQUES=0
ABSENTS=0
for f in $FICHIERS; do
  if [ ! -f "$RACINE/$f" ]; then
    echo "defaut : fichier de reference absent de ce depot : $f"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  for d in $DEPOTS; do
    nom=${d%%:*}
    dossier=${d#*:}
    copie="$dossier/$f"
    if [ ! -f "$copie" ]; then
      echo "pas encore recopie : $nom/$f"
      ABSENTS=$((ABSENTS + 1))
    elif cmp -s "$RACINE/$f" "$copie"; then
      echo "identique : $nom/$f"
      IDENTIQUES=$((IDENTIQUES + 1))
    else
      echo "DIFFERENT : $nom/$f"
      DEFAUTS=$((DEFAUTS + 1))
    fi
  done
done
echo "verifier-contrats : $IDENTIQUES identique(s), $ABSENTS pas encore recopie(s), $DEFAUTS defaut(s)"
if [ "$DEFAUTS" -gt 0 ] && [ "${CONTRATS_AVERTIR_SEULEMENT:-0}" = 1 ]; then
  echo "avertissement : $DEFAUTS copie(s) differente(s), a recopier dans l'autre depot (mode CONTRATS_AVERTIR_SEULEMENT=1, code 0)"
  exit 0
fi
[ "$DEFAUTS" -eq 0 ]
