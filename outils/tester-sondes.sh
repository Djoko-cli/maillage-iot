#!/bin/bash
# Tous les tests sans carte des sondes, depuis la racine du depot :
#   bash outils/tester-sondes.sh
# 1. tests hote du firmware de la sonde Thread (sonde-thread/test/lancer.sh) ;
# 2. tests hote du firmware de la sonde Zigbee (sonde-zigbee/test/lancer.sh) ;
# 3. tests Python des outils (outils/tests) ;
# 4. tests Python de la sonde Thread (sonde-thread/test) ;
# 5. garde des vrais identifiants (outils/garde.py).
# Aucun port serie n'est ouvert, rien n'est flashe. Chaque partie est rapportee ;
# le code de sortie est non nul si l'une d'elles echoue. L'app se teste par outils/tester.sh.
set -u
ICI=$(cd "$(dirname "$0")" && pwd)
DEPOT=$(cd "$ICI/.." && pwd)
cd "$DEPOT" || exit 1

ECHECS=0
partie() {
  local nom=$1
  shift
  echo "== $nom"
  if "$@"; then
    echo "-- OK : $nom"
  else
    echo "-- ECHEC : $nom"
    ECHECS=$((ECHECS + 1))
  fi
}

partie "firmware sonde-thread (tests hote)" sh "$DEPOT/sonde-thread/test/lancer.sh"
partie "firmware sonde-zigbee (tests hote)" sh "$DEPOT/sonde-zigbee/test/lancer.sh"
partie "tests Python des outils (outils/tests)" python3 -m unittest discover -s "$ICI/tests" -q
partie "tests Python de la sonde Thread (sonde-thread/test)" python3 -m unittest discover -s "$DEPOT/sonde-thread/test" -q
partie "garde des identifiants (outils/garde.py)" python3 "$ICI/garde.py"

if [ "$ECHECS" -ne 0 ]; then
  echo "BILAN : $ECHECS partie(s) en echec"
  exit 1
fi
echo "BILAN : toutes les parties passent"
