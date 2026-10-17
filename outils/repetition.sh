#!/bin/bash
# L'app de repetition de la reprise (phase 4, tache 8) : « Maillage IoT Repetition », la meme app sous une autre identite
# (fr.djoko.maillage.iot.repetition : conteneur, preferences, notifications, ouverture de session et services de trousseau
# `.repetition` a part, sans Sparkle, jamais publiee). Elle se lance A COTE de l'app reelle, qu'elle ne touche pas.
#
#   bash outils/repetition.sh construire    icone (derivee de celle de l'app), projet, compilation Debug, controle du produit
#   bash outils/repetition.sh lancer [-demo]   construit si besoin, puis ouvre la repetition (l'app reelle reste ouverte) ;
#                                           `-demo` : la demo de l'app (rien lu ni ecrit : ni ouverture de session inscrite,
#                                           ni notification demandee, ni sonde cherchee), pour verifier le lancement sans
#                                           consommer le « premier lancement » du banc
#   bash outils/repetition.sh quitter       quitte la repetition, elle seule
#   bash outils/repetition.sh etat          ce qui tourne, et les conteneurs
#
# Ne lance JAMAIS d'import et n'ecrit rien dans le trousseau : elle ouvre l'app, rien de plus.
# La construction echoue si l'icone de repetition manque ou n'est pas dans le produit (on ne compile pas sans icone).
# Journal complet de la compilation dans ${TMPDIR:-/tmp}/maillage-iot-repetition.log. Produits hors du depot (DD).
set -u
cd "$(dirname "$0")/.." || exit 1
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot}
ID=fr.djoko.maillage.iot.repetition
ID_REEL=fr.djoko.maillage.iot
NOM="Maillage IoT Repetition"
APP="$DD/Build/Products/Debug/$NOM.app"
ICONE=MaillageIoTRepetition/Ressources/AppIconRepetition.icon
JOURNAL=${TMPDIR:-/tmp}/maillage-iot-repetition.log

echec() { echo "echec : $*" >&2; exit 1; }

icone() {
  [ -f outils/icone/generer-repetition.swift ] || echec "outils/icone/generer-repetition.swift manque"
  [ -f MaillageIoT/Ressources/AppIcon.icon/Assets/constellation.png ] || echec "l'icone de l'app manque (MaillageIoT/Ressources/AppIcon.icon)"
  swift outils/icone/generer-repetition.swift > /dev/null || echec "l'icone de repetition n'a pas pu etre derivee"
  [ -s "$ICONE/Assets/constellation.png" ] && [ -s "$ICONE/icon.json" ] || echec "l'icone de repetition manque ($ICONE)"
}

# Le produit est bien l'identite de repetition, sans Sparkle, avec son icone.
controler_produit() {
  local info="$APP/Contents/Info.plist"
  [ -f "$info" ] || echec "produit absent : $APP"
  lire() { /usr/libexec/PlistBuddy -c "Print :$1" "$info" 2>/dev/null; }
  [ "$(lire CFBundleIdentifier)" = "$ID" ] || echec "identifiant du produit : $(lire CFBundleIdentifier)"
  [ "$(lire MaillageSuffixeServices)" = ".repetition" ] || echec "suffixe des services du trousseau absent de l'Info.plist"
  [ "$(lire CFBundleIconName)" = "AppIconRepetition" ] || echec "icone du produit : $(lire CFBundleIconName)"
  [ -f "$APP/Contents/Resources/Assets.car" ] || echec "l'icone n'est pas dans le produit (Assets.car)"
  ls "$APP/Contents/Frameworks" | grep -qi sparkle && echec "un cadre Sparkle est lie"
  for cle in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    [ -z "$(lire $cle)" ] || echec "cle $cle dans l'Info.plist"
  done
  if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q mach-lookup; then echec "exception mach-lookup (Sparkle) dans les droits"; fi
  python3 -I outils/refuser_repetition.py --verifier-est-repetition "$APP" || echec "le produit ne se reconnait pas comme repetition"
  echo "produit controle : $APP"
}

construire() {
  icone
  xcodegen generate --quiet || echec "xcodegen"
  xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoTRepetition -destination 'platform=macOS' \
    -configuration Debug -derivedDataPath "$DD" build > "$JOURNAL" 2>&1
  local code=$?
  grep -E "(error|warning): |\*\* BUILD" "$JOURNAL" | grep -v -e appintentsmetadataprocessor | head -20
  [ "$code" -eq 0 ] || echec "compilation (journal : $JOURNAL)"
  controler_produit
}

# Le pid de la repetition, par le chemin EXACT de son executable (jamais celui de l'app reelle).
pid_repetition() { pgrep -f "$NOM.app/Contents/MacOS/$NOM" | head -1; }

lancer() {
  [ -d "$APP" ] || construire
  [ -d "$APP" ] || exit 1
  if [ -n "$(pid_repetition)" ]; then echo "la repetition tourne deja (pid $(pid_repetition))"; return 0; fi
  # open sans -n : une seule repetition (meme identifiant) ; l'app reelle, d'un autre identifiant, n'est pas concernee.
  if [ $# -gt 0 ]; then open "$APP" --args "$@" || echec "ouverture"; else open "$APP" || echec "ouverture"; fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -n "$(pid_repetition)" ] && break; sleep 1; done
  [ -n "$(pid_repetition)" ] || echec "la repetition ne tourne pas apres 10 s"
  echo "repetition lancee (pid $(pid_repetition))"
}

quitter() {
  local pid; pid=$(pid_repetition)
  [ -n "$pid" ] || { echo "la repetition ne tourne pas"; return 0; }
  # Par son identifiant : l'app reelle (autre identifiant) n'est jamais visee.
  osascript -e "tell application id \"$ID\" to quit" > /dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(pid_repetition)" ] && break; sleep 1; done
  if [ -n "$(pid_repetition)" ]; then kill -TERM "$(pid_repetition)"; sleep 2; fi
  [ -z "$(pid_repetition)" ] && echo "repetition quittee" || echec "la repetition tourne encore"
}

etat() {
  echo "repetition : ${APP}"
  echo "  pid repetition : $(pid_repetition)"
  echo "  pid app reelle : $(pgrep -f "/Maillage IoT.app/Contents/MacOS/Maillage IoT" | tr '\n' ' ')"
  for id in "$ID_REEL" "$ID"; do
    if [ -d "$HOME/Library/Containers/$id" ]; then echo "  conteneur : ~/Library/Containers/$id (present)"
    else echo "  conteneur : ~/Library/Containers/$id (absent)"; fi
  done
}

case "${1:-}" in
  construire) construire ;;
  lancer) shift; lancer "$@" ;;
  quitter) quitter ;;
  etat) etat ;;
  *) echo "usage : bash outils/repetition.sh construire|lancer|quitter|etat" >&2; exit 2 ;;
esac
