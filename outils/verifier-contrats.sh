#!/bin/bash
# Verifie que les fichiers de contrat partages sont identiques a l'octet (cmp) dans les trois depots :
#   bash outils/verifier-contrats.sh
# Fichiers compares, au meme chemin relatif dans chaque depot (la copie de reference est celle de ce depot) :
#   MaillageCoeur/Reprise/ContratExport.swift   contrat de l'export de reprise (spec 4.1, 6.8)
#   MaillageCoeur/Noms/ProtocolePasseur.swift   contrat du demon Passeur Noms
# Depots compares, par defaut les voisins de celui-ci (meme dossier parent) :
#   ../maillage-thread   (Maillage Thread)      ../maillage-zigbee   (Maillage Zigbee)
# Pour d'autres emplacements : DEPOT_THREAD=/chemin DEPOT_ZIGBEE=/chemin bash outils/verifier-contrats.sh
# (ou MAILLAGE_DEPOTS=/dossier-parent). Un depot ou un fichier absent n'est pas une erreur : "pas encore recopie"
# (le contrat d'export est recopie dans les anciennes apps apres ce depot). Une copie presente mais differente est un
# defaut. Code 0 : aucune difference ; code 1 : au moins une copie differente, ou fichier de reference absent.
# Ne modifie rien. Pas encore branche dans tester.sh.
set -u
cd "$(dirname "$0")/.." || exit 1
RACINE=$(pwd)
PARENT=${MAILLAGE_DEPOTS:-$(dirname "$RACINE")}
FICHIERS="MaillageCoeur/Reprise/ContratExport.swift MaillageCoeur/Noms/ProtocolePasseur.swift"
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
[ "$DEFAUTS" -eq 0 ]
