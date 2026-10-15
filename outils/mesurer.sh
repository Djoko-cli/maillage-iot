#!/bin/sh
# Mesures de la vue par pieces.
#   outils/mesurer.sh              le coeur, en Release (spec de la vue par pieces, section 10) : la disposition d'une
#                                  grande maison inventee (sous 1 s) et le placement de 150 noms (sous 2 ms dans une
#                                  fenetre ordinaire, sous 4 ms tres serres). En Debug (outils/tester.sh), ces trois
#                                  tests sont sautes. Schema MaillageCoeur : le coeur et ses tests seuls.
#   outils/mesurer.sh vue [FICHIER]  l'app, en Release, hors ecran (MaillageIoTTests/MesuresVueTests) : l'ouverture de la
#                                  scene de demo (Thread seule, puis combinee) et le cout d'une suite de zooms (medianes, en ms). Jamais une assertion
#                                  de duree ; saute dans la porte (outils/tester.sh). Avec FICHIER, ecrit aussi les
#                                  resultats en JSON (date, commit, suivi de -dirty si l'arbre a des
#                                  changements, configuration, machine generique), par exemple
#                                  docs/mesures/etape-1.json.
# Journal complet dans $TMPDIR/maillage-iot-mesures.log. Produits de compilation hors du depot (DD).
set -u
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
JOURNAL=${TMPDIR:-/tmp}/maillage-iot-mesures.log
xcodegen generate --quiet || exit 1

mesures_vue() {
  SORTIE=${1:-}
  # `TEST_RUNNER_` : xcodebuild passe ces variables au processus de test, sans le prefixe. Runtime renforce eteint : signee
  # ad hoc, l'app en Release refuse de charger ses cadres (validation des bibliotheques) ; les versions publiees sont
  # signees par l'equipe. Sans effet sur la vitesse.
  TEST_RUNNER_MESURES_VUE=1 xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -destination 'platform=macOS' \
    -derivedDataPath "$DD" -configuration Release ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES ENABLE_HARDENED_RUNTIME=NO test \
    -only-testing:MaillageIoTTests/MesuresVueTests > "$JOURNAL" 2>&1
  CODE=$?
  grep -E "(error|warning): |✘|Test run with|\*\* TEST" "$JOURNAL" | grep -v -e appintentsmetadataprocessor -e "\[Connection\]"
  # Un test saute (variable non transmise) passe sans rien mesurer : il faut sa ligne de resultats.
  if [ "$CODE" -eq 0 ] && [ "$(grep -c "^mesure vue json : " "$JOURNAL")" -ne 1 ]; then
    echo "echec : pas de ligne « mesure vue json » dans le journal (test saute ?)"
    CODE=1
  fi
  if [ "$CODE" -eq 0 ]; then
    COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo inconnu)
    # Un arbre qui a des changements (suivis ou non) : la mesure n'est pas celle du commit seul.
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then COMMIT="$COMMIT-dirty"; fi
    ARCH=$(uname -m)
    SYSTEME=$(sw_vers -productVersion 2>/dev/null || echo inconnu)
    python3 - "$JOURNAL" "$SORTIE" "$COMMIT" "$ARCH" "$SYSTEME" <<'PY' || CODE=1
import datetime, json, sys
journal, sortie, commit, arch, systeme = sys.argv[1:6]
ligne = next(l for l in open(journal, errors="replace") if l.startswith("mesure vue json : "))
m = json.loads(ligne[len("mesure vue json : "):])
# Thread seule : les memes cles qu'a l'etape 1 (docs/mesures/etape-1.json), pour se comparer ; la demo combinee : un bloc a part.
seule = m.pop("thread_seule")
combinee = m.pop("combinee")
r = {
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "commit": commit,
    "configuration": m.pop("compilation"),
    "machine": "Mac (Apple Silicon)" if arch == "arm64" else "Mac (Intel)",
    "systeme": "macOS " + systeme,
    "scene": "demo de Thread seule (-demo-thread), hors ecran, 1200 x 800 ; la demo combinee (-demo) dans demo_combinee",
    "unite": "ms (medianes)",
    "methode": "MaillageIoTTests/MesuresVueTests.swift, lancee par outils/mesurer.sh vue",
}
arrondi = lambda d: {k: round(v, 3) if isinstance(v, float) else v for k, v in d.items()}
r.update(arrondi(seule))
r["demo_combinee"] = arrondi(combinee)
for titre, c in (("demo de Thread seule", r), ("demo combinee", r["demo_combinee"])):
    lignes = [
        ("ouverture, froide (1er passage)", c["ouverture_froide_ms"]),
        ("ouverture, mediane", c["ouverture_ms"]),
        ("  dont surveillance + scene", c["ouverture_scene_ms"]),
        ("  dont disposition", c["ouverture_disposition_ms"]),
        ("  dont premiere image", c["ouverture_premiere_image_ms"]),
        ("zoom, suite de %d pas, mediane" % c["pas_de_zoom"], c["zoom_suite_ms"]),
        ("zoom, image mediane", c["zoom_image_ms"]),
        ("zoom, image au 95e centile", c["zoom_image_p95_ms"]),
        ("zoom, pire image", c["zoom_pire_image_ms"]),
    ]
    print("mesures de la vue, %s (%s, %s, %d passages, %d noeuds, %d pieces) :" % (titre, r["commit"], r["configuration"], c["passages"], c["noeuds"], c["pieces"]))
    for nom, v in lignes:
        print("  %-36s %9.2f ms" % (nom, v))
if sortie:
    with open(sortie, "w") as f:
        json.dump(r, f, indent=2, ensure_ascii=False, sort_keys=False)
        f.write("\n")
    print("ecrit : " + sortie)
PY
  fi
  echo "journal complet : $JOURNAL (code $CODE)"
  exit $CODE
}

case "${1:-}" in
  vue) mesures_vue "${2:-}" ;;
  "") ;;
  *) echo "usage : outils/mesurer.sh [vue [FICHIER.json]]"; exit 2 ;;
esac

xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageCoeur -destination 'platform=macOS' \
  -derivedDataPath "$DD" -configuration Release ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES test \
  -only-testing:MaillageCoeurTests/DispositionPiecesTests -only-testing:MaillageCoeurTests/PlacementNomsTests \
  > "$JOURNAL" 2>&1
CODE=$?
grep -E "(error|warning): |✘|mesure : |Test run with|\*\* TEST" "$JOURNAL" | grep -v -e appintentsmetadataprocessor -e "\[Connection\]"
# Un test de temps saute (compilation non optimisee) passe sans rien mesurer : il faut ses trois lignes.
MESURES=$(grep -c "mesure : " "$JOURNAL")
if [ "$CODE" -eq 0 ] && [ "$MESURES" -ne 3 ]; then
  echo "echec : $MESURES ligne(s) « mesure : » au lieu de 3 (un test de temps a ete saute)"
  CODE=1
fi
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
