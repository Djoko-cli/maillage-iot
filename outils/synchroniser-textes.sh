#!/bin/sh
# Met le catalogue de l'app a jour avec les textes extraits par le compilateur
# (a lancer apres une compilation, par exemple outils/tester.sh) : ajoute les
# nouvelles cles, marque "stale" celles qui ont disparu du code.
#   outils/synchroniser-textes.sh
# Ensuite :
#   python3 outils/traduire.py MaillageIoT/Ressources/Localizable.xcstrings outils/traductions/<fichier>.json
set -eu
cd "$(dirname "$0")/.."
[ $# -eq 0 ] || { echo "usage : $0 (sans argument : une seule app, MaillageIoT)" >&2; exit 2; }
APP=MaillageIoT
CATALOGUE=${CATALOGUE:-$APP/Ressources/Localizable.xcstrings}
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
# Le premier MaillageIoT.build est celui du projet, le second celui de la cible.
I="$DD/Build/Intermediates.noindex/MaillageIoT.build/Debug/$APP.build/Objects-normal"
# Seuls les .stringsdata dont la source existe encore comptent : ceux d'un fichier supprime ou renomme restent dans le
# dossier de compilation et remettraient ses cles dans le catalogue.
LISTE=$(mktemp)
trap 'rm -f "$LISTE"' EXIT
python3 - "$I" > "$LISTE" <<'PY'
import glob, json, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*", "*.stringsdata"))):
    with open(f) as h:
        source = json.load(h).get("source", "")
    if source and os.path.exists(source):
        print(f)
PY
[ -s "$LISTE" ] || { echo "aucun .stringsdata a source existante dans $I : compiler d'abord (outils/tester.sh)" >&2; exit 1; }
set --
while IFS= read -r f; do set -- "$@" --stringsdata "$f"; done < "$LISTE"
xcrun xcstringstool sync "$CATALOGUE" "$@"
# xcstringstool retire le saut de ligne final du catalogue : on le remet, pour ne laisser aucun diff parasite.
if [ -s "$CATALOGUE" ] && [ "$(tail -c 1 "$CATALOGUE" | od -An -c | tr -d ' ')" != '\n' ]; then
  printf '\n' >> "$CATALOGUE"
fi
