#!/bin/bash
# Refuse un nom public de premier niveau commun a ProtocoleThread et ProtocoleZigbee (spec, contraintes de l'etape 2) :
# l'app de l'etape 3 importe les deux modules. Code 0 : aucun nom commun.
set -u
cd "$(dirname "$0")/.." || exit 1
noms() {
  grep -rhoE '^public (final )?(struct|enum|class|actor|protocol|typealias) [A-Za-z_][A-Za-z0-9_]*' "$1" --include='*.swift' \
    | awk '{print $NF}' | sort -u
}
communs=$(comm -12 <(noms ProtocoleThread) <(noms ProtocoleZigbee))
if [ -n "$communs" ]; then
  echo "noms publics communs aux deux protocoles :"; echo "$communs"; exit 1
fi
echo "verifier-noms-publics : aucun nom public commun"
