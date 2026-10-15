#!/bin/bash
# Lance les tests du coeur seul (schema MaillageCoeur), sans les protocoles ni l'app :
#   bash outils/tester-coeur.sh
# ENABLE_TESTABILITY=YES : le coeur se compile en -O meme en Debug, sans lui @testable ne le voit pas.
# TEST_RUNNER_MAILLAGE_COEUR_SEUL=1 : xcodebuild le passe aux tests (sans le prefixe) ; CataloguesTests saute alors la
# comparaison du catalogue de l'app, meme si de vieux .stringsdata d'un ancien DerivedData trainent (l'app n'est pas
# compilee ici ; la porte complete outils/tester.sh la verifie toujours).
# Journal complet dans ${TMPDIR:-/tmp}/maillage-iot-coeur.log ; code de sortie = celui de xcodebuild.
set -u
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
JOURNAL=${TMPDIR:-/tmp}/maillage-iot-coeur.log
xcodegen generate --quiet || exit 1
TEST_RUNNER_MAILLAGE_COEUR_SEUL=1 xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageCoeur -destination 'platform=macOS' \
  -derivedDataPath "$DD" test ENABLE_TESTABILITY=YES > "$JOURNAL" 2>&1
CODE=$?
grep -E "Test run with|\*\* TEST" "$JOURNAL" | tail -n 5
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
