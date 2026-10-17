#!/bin/sh
# Genere le projet puis lance les tests : tous, ou ceux passes en arguments
#   outils/tester.sh ProtocoleThreadTests/AdressesTests MaillageIoTTests
# Affiche les erreurs, les tests en echec et le bilan ; journal complet dans
# $TMPDIR/maillage-iot-tests.log. Produits de compilation hors du depot (DD).
# Chaque cible donnee doit lancer au moins un test, sinon echec : un nom faux ne lance rien, et
# xcodebuild repond pourtant TEST SUCCEEDED. Un test de Swift Testing se nomme avec ses
# parentheses (ProtocoleThreadTests/GrapheReseauTests/stable()).
# Avant de compiler, lance la garde des deux sondes (outils/verifier-sondes.sh) : etat de sonde ecrit hors de son pilote, port
# ouvert hors du fichier +USB ; un defaut arrete la porte (code 1) avant toute compilation.
set -u
cd "$(dirname "$0")/.."
bash outils/verifier-sondes.sh || exit 1
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
JOURNAL=${TMPDIR:-/tmp}/maillage-iot-tests.log
xcodegen generate --quiet || exit 1
# La porte complete compile l'app : elle verifie toujours son catalogue (la variable du coeur seul, posee par
# tester-coeur.sh, ne doit pas la faire sauter).
unset TEST_RUNNER_MAILLAGE_COEUR_SEUL
FILTRES=""
for t in "$@"; do FILTRES="$FILTRES -only-testing:$t"; done
# shellcheck disable=SC2086
xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -destination 'platform=macOS' \
  -derivedDataPath "$DD" test $FILTRES > "$JOURNAL" 2>&1
CODE=$?
grep -E "(error|warning): |✘|Test run with|\*\* TEST" "$JOURNAL" | grep -v -e appintentsmetadataprocessor -e "\[Connection\]"
if [ "$CODE" -eq 0 ] && [ $# -gt 0 ]; then
  # Ce qui a tourne : les noeuds du resultat (paquet, suite, test), sous leur chemin de cible.
  RESULTATS=$(sed -n '/^Test session results/{n;s/^[[:space:]]*//;p;}' "$JOURNAL" | tail -n 1)
  if [ -z "$RESULTATS" ]; then
    echo "echec : chemin du resultat des tests absent du journal ; cibles non verifiees"
    CODE=1
  elif ! ARBRE=$(xcrun xcresulttool get test-results tests --path "$RESULTATS" 2>&1); then
    echo "echec : resultat des tests illisible ($RESULTATS) ; cibles non verifiees :"
    printf '%s\n' "$ARBRE" | head -n 5
    CODE=1
  else
    LANCES=$(printf '%s\n' "$ARBRE" | sed -n 's|.*"nodeIdentifierURL" : "test://[^/]*/[^/]*/\([^"]*\)".*|\1|p')
    # Une cible au nom faux ne lance rien : l'arbre ne porte alors que le plan de tests, sans noeud
    # de test ; c'est un arbre sans aucun noeud (ou sans identifiant) qui trahit un format change.
    NOEUDS=$(printf '%s\n' "$ARBRE" | grep '"nodeType"')
    if [ -z "$LANCES" ] && { [ -z "$NOEUDS" ] || printf '%s\n' "$NOEUDS" | grep -qv 'Test Plan'; }; then
      echo "echec : aucun noeud de test lu dans $RESULTATS (format de xcresulttool change ?) ; cibles non verifiees"
      CODE=1
    else
      for t in "$@"; do
        if ! printf '%s\n' "$LANCES" | grep -qxF -- "$t"; then
          echo "echec : la cible $t ne lance aucun test (nom faux, ou test sans ses parentheses ?)"
          CODE=1
        fi
      done
    fi
  fi
fi
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
