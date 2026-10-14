#!/bin/bash
# Refuse ce qui rendrait ambigu l'import des deux protocoles dans l'app de l'etape 3 (ProtocoleThread et
# ProtocoleZigbee). Code 0 : rien de commun ni de capte. Trois controles :
# 1. un nom public de premier niveau commun aux deux modules (spec, contraintes de l'etape 2) ;
# 2. un membre public d'extension (init, methode, propriete) declare par les deux modules sur un meme type, sous
#    les memes etiquettes (outils/noms_publics.py communs) ;
# 3. un init public d'extension d'un module dont les etiquettes sont un sous-ensemble ordonne de celles d'un init
#    du coeur : il capterait en silence un appel de l'autre protocole qui omet les etiquettes en trop
#    (outils/noms_publics.py captes). Sont a renommer, avec des etiquettes propres au protocole.
set -u
cd "$(dirname "$0")/.." || exit 1
CODE=0
noms() {
  grep -rhoE '^public (final )?(struct|enum|class|actor|protocol|typealias) [A-Za-z_][A-Za-z0-9_]*' "$1" --include='*.swift' \
    | awk '{print $NF}' | sort -u
}
communs=$(comm -12 <(noms ProtocoleThread) <(noms ProtocoleZigbee))
if [ -n "$communs" ]; then
  echo "noms publics communs aux deux protocoles :"; echo "$communs"; CODE=1
fi
python3 -I outils/noms_publics.py communs ProtocoleThread ProtocoleZigbee || CODE=1
python3 -I outils/noms_publics.py captes MaillageCoeur ProtocoleThread ProtocoleZigbee || CODE=1
if [ "$CODE" -eq 0 ]; then
  echo "verifier-noms-publics : aucun nom public commun, aucun membre d'extension commun ni capte"
fi
exit $CODE
