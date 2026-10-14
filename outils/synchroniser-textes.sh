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
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
# Le premier MaillageIoT.build est celui du projet, le second celui de la cible.
I="$DD/Build/Intermediates.noindex/MaillageIoT.build/Debug/$APP.build/Objects-normal"
xcrun xcstringstool sync "$APP/Ressources/Localizable.xcstrings" --stringsdata "$I"/*/*.stringsdata
