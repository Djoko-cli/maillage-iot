#!/bin/sh
# Passeur Noms, demon de Maison (docs/superpowers/specs/2026-10-13-maillage-iot-design.md, section 5.3) : app Mac
# Catalyst sans fenetre ni Dock, qui lit Maison en arriere-plan et la sert a Maillage IoT par la boucle locale.
# HomeKit n'est pas offert aux apps Mac signees Developer ID (capacite reservee a l'App Store) : le demon reste une
# compilation de developpement pour ce Mac enregistre. Il exige une equipe payante (Apple Developer Program), profil
# d'un an ; une equipe gratuite ne peut pas le compiler (HomeKit refuse : « Entitlement com.apple.developer.homekit
# not found »). Relancer ce script pour renouveler le profil (les apps le rappellent 30 jours avant).
# Compile, arrete le demon qui tourne (par son PID), remplace l'app installee (seulement une installation faite par ce
# script : l'ancienne enveloppe, lien WrappedBundle, ou le demon, cle MaillagePasseurProtocole de son Info.plist),
# l'enregistre aupres de LaunchServices (et desinscrit les autres copies enregistrees, produits de compilation ou
# enveloppes, qui reclameraient aussi l'URL maillage-passeur://), puis la lance en arriere-plan : le premier
# lancement demande l'acces a Maison.
#
#   outils/passeur.sh [--sans-lancer]
#   outils/passeur.sh --comparer-versions INSTALLEE CONSTRUITE
#
#   --sans-lancer  compile et installe, sans lancer.
#   --comparer-versions  code 0 si CONSTRUITE est au moins aussi recente qu'INSTALLEE (ou si INSTALLEE est vide),
#                  code 1 et message sinon ; ne touche a rien. L'installation applique la meme regle : elle refuse
#                  de remplacer un demon installe plus recent que celui qui vient d'etre compile.
#   APP=...        paquet a installer, en .app (defaut : ~/Applications/Passeur Noms.app).
#   DD=...         produits de compilation (defaut : ~/Library/Developer/Xcode/DerivedData/maillage-iot-passeur).
#   EQUIPE=...     equipe de signature, 10 caracteres (defaut : celle du premier certificat « Apple Development »
#                  encore valide du trousseau, sinon celle du certificat « Developer ID Application », la meme
#                  equipe payante : Xcode cree alors le certificat Apple Development). Jamais affichee.
set -eu
USAGE="usage : outils/passeur.sh [--sans-lancer]"
# Refus de remplacer un demon plus recent (spec de Maillage IoT, section 5.3) : version installee contre
# version construite, comparees par `sort -V`. Sans demon installe : accepte.
plus_ancien_que_installe() {  # $1 : installee, $2 : construite ; code 0 si la construite est plus ancienne
  [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}
refuser_si_plus_recent() {  # $1 : installee, $2 : construite
  if plus_ancien_que_installe "$1" "$2"; then
    echo "passeur.sh : le demon installe ($1) est plus recent que celui-ci ($2) : rien n'est remplace" >&2
    exit 1
  fi
}
if [ "${1:-}" = "--comparer-versions" ]; then
  refuser_si_plus_recent "${2:-}" "${3:-}"
  exit 0
fi
LANCER=oui
for a in "$@"; do
  case "$a" in
    --sans-lancer) LANCER=non ;;
    *) echo "argument inconnu : $a" >&2; echo "$USAGE" >&2; exit 1 ;;
  esac
done
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot-passeur}
APP=${APP:-"$HOME/Applications/Passeur Noms.app"}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Gardes, avant de toucher au disque : l'app installee est effacee puis remplacee.
case "$APP" in
  *.app) ;;
  *) echo "APP : chemin d'un paquet .app (par exemple ~/Applications/Passeur Noms.app), pas « $APP »" >&2
     exit 1 ;;
esac
ENVELOPPE=non
if [ -e "$APP" ]; then
  if [ "$(readlink "$APP/WrappedBundle" 2>/dev/null)" = "Wrapper/Passeur Noms.app" ]; then
    ENVELOPPE=oui
  elif ! /usr/libexec/PlistBuddy -c "Print :MaillagePasseurProtocole" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "$APP existe mais n'est pas une installation faite par ce script : rien n'est effacé." >&2
    exit 1
  fi
fi
# Equipe : celle du premier certificat « Apple Development » encore valide (le trousseau peut garder des certificats
# expires).
equipe() {
  pem=""
  security find-certificate -a -c "Apple Development" -p 2>/dev/null | while IFS= read -r ligne; do
    pem="$pem$ligne
"
    case "$ligne" in
      *"END CERTIFICATE"*)
        if printf '%s' "$pem" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
          printf '%s' "$pem" | openssl x509 -noout -subject 2>/dev/null |
            sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p'
          break
        fi
        pem="" ;;
    esac
  done
}
# Repli : l'equipe du certificat « Developer ID Application » (une seule identite de ce nom dans le trousseau).
equipeDeveloperID() {
  security find-certificate -c "Developer ID Application" -p 2>/dev/null |
    openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p'
}
EQUIPE=${EQUIPE:-$(equipe | head -1)}
[ -n "$EQUIPE" ] || EQUIPE=$(equipeDeveloperID)
if [ -z "$EQUIPE" ]; then
  echo "Pas de certificat Apple Development ni Developer ID : ajouter un compte Apple dans Xcode (Réglages > Comptes), ou EQUIPE=XXXXXXXXXX" >&2
  exit 1
fi
JOURNAL=${TMPDIR:-/tmp}/maillage-passeur.log
xcodegen generate --quiet
if ! xcodebuild -project MaillageIoT.xcodeproj -scheme Passeur \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$EQUIPE" build > "$JOURNAL" 2>&1; then
  # Les erreurs, sans le nom du titulaire ni l'equipe.
  grep -E "error:" "$JOURNAL" | sed -E 's/(Apple Development|Developer ID Application): [^(]*\(([A-Z0-9]{10})\)/\1: <titulaire> (<equipe>)/g; s/[A-Z0-9]{10}/<id>/g' >&2 || true
  echo "échec de la compilation, journal complet : $JOURNAL" >&2
  exit 1
fi
PRODUIT="$DD/Build/Products/Debug-maccatalyst/Passeur Noms.app"
if [ ! -d "$PRODUIT/Contents/PlugIns/Masqueur.bundle" ]; then
  echo "Produit de compilation incomplet (Masqueur.bundle absent) : $PRODUIT ($APP n'est pas touché)" >&2
  exit 1
fi
# Refus avant d'arreter ou de remplacer quoi que ce soit : le demon installe est-il plus recent que le produit ?
VERSION_INSTALLEE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || true)
VERSION_CONSTRUITE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PRODUIT/Contents/Info.plist" 2>/dev/null || true)
refuser_si_plus_recent "$VERSION_INSTALLEE" "$VERSION_CONSTRUITE"
# Le passeur qui tourne (ancienne enveloppe ou demon) : arrete par son PID avant de remplacer son paquet.
arreter() {
  for pid in $(pgrep -f "$APP/" 2>/dev/null || true); do
    kill "$pid" 2>/dev/null || true
    # Attente de la fin, 5 s au plus (25 x 0,2 s) : sinon l'installation ne remplace rien.
    attente=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$attente" -ge 25 ]; then
        echo "Passeur Noms (PID $pid) ne s'arrete pas : arret de l'installation." >&2
        exit 1
      fi
      sleep 0.2
      attente=$((attente + 1))
    done
  done
}
arreter
# LaunchServices : l'ancienne installation et les copies de compilation (l'ancienne app iOS et la nouvelle) ne
# doivent plus reclamer l'URL maillage-passeur:// ni l'identifiant du passeur.
if [ -e "$APP" ]; then
  [ "$ENVELOPPE" = oui ] && "$LSREGISTER" -u "$APP/Wrapper/Passeur Noms.app" 2>/dev/null || true
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
fi
for copie in "$DD/Build/Products/Debug-iphoneos/Passeur Noms.app" "$PRODUIT"; do
  [ -e "$copie" ] && "$LSREGISTER" -u "$copie" 2>/dev/null || true
done
# Une app a pu relancer le passeur entre-temps (URL maillage-passeur://) : on l'arrete de nouveau juste avant de
# remplacer le paquet.
arreter
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
# Chemin absolu et reel (APP relatif, ou passant par un lien) : la copie installee est reconnue plus bas dans le dump
# de LaunchServices, qui donne des chemins absolus ; sinon elle serait desinscrite avec les autres.
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
ditto "$PRODUIT" "$APP"
"$LSREGISTER" -f "$APP"
# Xcode reenregistre ses produits (builds iOS de DerivedData, enveloppes temporaires, compilations de verification) :
# toute AUTRE copie enregistree du passeur est desinscrite (jamais effacee), sinon elle reclame l'URL et l'identifiant.
"$LSREGISTER" -dump 2>/dev/null |
  awk '/^path:/{sub(/^path: */,""); sub(/ \(0x[0-9a-f]+\)$/,""); p=$0} /fr\.djoko\.maillage\.passeur$/{print p}' |
  sort -u | grep "Passeur Noms.app$" | while IFS= read -r copie; do
  case "$copie" in "$APP" | "$APP"/) continue ;; esac
  "$LSREGISTER" -u "$copie" 2>/dev/null || true
  echo "copie desinscrite de LaunchServices : $(printf '%s' "$copie" | sed "s|^$HOME|~|")"
done || true
if [ "$LANCER" = non ]; then
  echo "Passeur Noms installé (non lancé) : $APP"
else
  open -g "$APP"
  echo "Passeur Noms installé et lancé en arrière-plan : $APP"
fi
