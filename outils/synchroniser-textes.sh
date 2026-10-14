#!/bin/sh
# Met le catalogue d'une app a jour avec les textes extraits par le compilateur
# (a lancer apres une compilation, par exemple outils/tester.sh) : ajoute les
# nouvelles cles, marque "stale" celles qui ont disparu du code.
#   outils/synchroniser-textes.sh [App]     App : MaillageIoT (par defaut) ou MaillageIoTZigbee
# Ensuite :
#   python3 outils/traduire.py <App>/Ressources/Localizable.xcstrings outils/traductions/<fichier>.json
set -eu
cd "$(dirname "$0")/.."
APP=${1:-MaillageIoT}
case "$APP" in
  MaillageIoT|MaillageIoTZigbee) ;;
  *) echo "usage : $0 [MaillageIoT|MaillageIoTZigbee]" >&2; exit 2 ;;
esac
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
# Le premier MaillageIoT.build est celui du projet, le second celui de la cible.
I="$DD/Build/Intermediates.noindex/MaillageIoT.build/Debug/$APP.build/Objects-normal"
xcrun xcstringstool sync "$APP/Ressources/Localizable.xcstrings" --stringsdata "$I"/*/*.stringsdata
