#!/bin/sh
# Genere le projet puis lance les tests : tous, ou ceux passes en arguments
#   outils/tester.sh ProtocoleThreadTests/AdressesTests MaillageIoTTests
# Affiche les erreurs, les tests en echec et le bilan ; journal complet dans
# $TMPDIR/maillage-iot-tests.log. Produits de compilation hors du depot (DD).
# Chaque cible donnee doit lancer au moins un test, sinon echec : un nom faux ne lance rien, et
# xcodebuild repond pourtant TEST SUCCEEDED. Un test de Swift Testing se nomme avec ses
# parentheses (ProtocoleThreadTests/GrapheReseauTests/stable()).
# Apres les tests, etape informative : outils/verifier-contrats.sh compare les contrats partages (ContratExport.swift et
# ses tests, ProtocolePasseur.swift) avec les depots Thread et Zigbee. Tant que les anciennes apps n'ont pas recopie le
# contrat, il tourne en mode avertissement (CONTRATS_AVERTIR_SEULEMENT=1 par defaut : une copie differente est affichee
# mais ne change pas le code) ; CONTRATS_AVERTIR_SEULEMENT=0 outils/tester.sh le rend bloquant (copie differente = code 1).
# Avant de compiler, lance la garde des deux sondes (outils/verifier-sondes.sh) : etat de sonde ecrit hors de son pilote, port
# ouvert hors du fichier +USB ; un defaut arrete la porte (code 1) avant toute compilation.
# Puis la garde d'identite (outils/verifier_identite.py) : aucun litteral de service de trousseau ou d'identifiant de l'app
# reelle dans le code (hors IdentiteApp et des cas listes), sinon l'app de repetition ecrirait dans le trousseau de l'app reelle
# sans qu'aucun test le voie (ils tournent dans l'app reelle) ; meme arret (code 1) avant toute compilation.
# Porte complete (sans argument) : apres les tests, elle construit aussi l'app de repetition (outils/repetition.sh construire :
# schema MaillageIoTRepetition, produit controle, rien lance) ; l'autre classe MisesAJour (#else) doit suivre la vraie.
set -u
cd "$(dirname "$0")/.."
bash outils/verifier-sondes.sh || exit 1
python3 -I outils/verifier_identite.py || exit 1
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
# Porte complete : l'app de repetition se construit aussi (construction et controle du produit seulement, aucun lancement).
if [ $# -eq 0 ]; then
  echo "--- app de repetition (outils/repetition.sh construire) ---"
  bash outils/repetition.sh construire || CODE=1
fi
# Etape informative (apres le bilan des tests, pour rester lisible) ; seule une copie DIFFERENTE peut la faire echouer,
# et seulement hors du mode avertissement.
echo "--- contrats partages (outils/verifier-contrats.sh) ---"
CONTRATS_AVERTIR_SEULEMENT=${CONTRATS_AVERTIR_SEULEMENT-1} bash outils/verifier-contrats.sh || CODE=1
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
