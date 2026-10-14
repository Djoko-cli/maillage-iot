#!/bin/bash
# Lance les tests du coeur seul (schema MaillageCoeur), sans les protocoles ni l'app :
#   bash outils/tester-coeur.sh
# ENABLE_TESTABILITY=YES : le coeur se compile en -O meme en Debug, sans lui @testable ne le voit pas.
# Journal complet dans ${TMPDIR:-/tmp}/maillage-iot-coeur.log ; code de sortie = celui de xcodebuild.
set -u
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
JOURNAL=${TMPDIR:-/tmp}/maillage-iot-coeur.log
xcodegen generate --quiet || exit 1
xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageCoeur -destination 'platform=macOS' \
  -derivedDataPath "$DD" test ENABLE_TESTABILITY=YES > "$JOURNAL" 2>&1
CODE=$?
grep -E "Test run with|\*\* TEST" "$JOURNAL" | tail -n 5
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
