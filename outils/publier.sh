#!/bin/sh
# Publie une version de Maillage IoT sur GitHub : verifications, numeros, compilation Release signee par le
# Developer ID de Djoko et notarisee, .dmg signe par Sparkle (cle du trousseau), controles d'anonymisation (les deux
# controles prives, outils/anonymisation_double.py), version publiee (etiquette vX.Y.Z, avec le .dmg), puis le flux
# des mises a jour (appcast.xml, qui garde toutes les versions) commite sur main et pousse aussitot, .dmg sur le Bureau.
# Le .dmg porte aussi la licence de Sparkle 2.10.0 (outils/Sparkle-LICENSE.txt, le fichier LICENSE de l'etiquette
# 2.10.0, entier) ; le commit du flux est signe Djoko-cli, a l'adresse noreply de GitHub.
# La logique est dans outils/publication.py (identique a l'octet a celle de Maillage Thread et d'Amaran Compagnon),
# ses tests dans outils/tests. Ce script n'y met que ce qui est propre a Maillage IoT.
#   outils/publier.sh X.Y.Z [--sans-bureau]
# La repetition, sans GitHub ni Bureau, avec la cle du trousseau, ou une paire d'essai :
#   outils/publier.sh X.Y.Z --repetition DOSSIER --url-base URL [--cle-privee FICHIER --cle-publique CLE]
#                           [--trousseau TROUSSEAU] [--sans-tests]
#   outils/publier.sh --aide        l'aide de publication.py, sans rien verifier ni construire
# SPARKLE_BIN : le dossier bin de l'archive de Sparkle 2.10.0 (sign_update, generate_keys), obligatoire hors repetition.
# Developer ID et notarisation des la 1.0.0 (decision de Djoko du 12/10/2026) : NOTARISER=1 et PROFIL_NOTARISATION=
# djoko-notarisation (le profil que notarytool store-credentials a range dans le trousseau) par defaut.
# Avant toute construction, trois gardes : jamais l'identite de repetition (outils/refuser_repetition.py, sur l'identifiant
# de la cible MaillageIoT lu dans project.yml), l'icone presente, un clone complet.
# PYTHON : l'interpreteur de la garde et de publication.py (/usr/bin/python3 par defaut ; les tests y mettent un
# enregistreur).
# CONTROLE_ANONYMISATION est toujours impose ici (une valeur de l'appelant ne remplace jamais la double garde) ; ses
# dossiers prives se reglent dans outils/anonymisation_double.py.
# Produits : build/publication/X.Y.Z/ ; compilation dans DD (par defaut DerivedData/maillage-iot-publication).
set -eu
cd "$(dirname "$0")/.."
PYTHON=${PYTHON:-/usr/bin/python3}
case ${1:-} in
  --aide|-h|--help) exec "$PYTHON" outils/publication.py publier -h;;
esac
# L'identite de signature de la version publiee, a ce seul endroit : le Developer ID de Djoko, trouve dans le
# trousseau par son prefixe (son nom complet porte le nom legal du titulaire : il n'est ecrit nulle part ici).
IDENTITE_SIGNATURE=${IDENTITE_SIGNATURE:-Developer ID Application}
NOTARISER=${NOTARISER:-1}
PROFIL_NOTARISATION=${PROFIL_NOTARISATION:-djoko-notarisation}
export NOTARISER PROFIL_NOTARISATION
# Le cliquet du Developer ID : une version publiee n'est jamais signee autrement (une signature autre ramenerait
# l'alerte « l'app differe » de macOS et le blocage de Gatekeeper). La repetition seule peut signer autrement.
repetition=0
for x in "$@"; do
  case $x in --repetition|--repetition=*) repetition=1;; esac
done
if [ $repetition = 0 ] && { [ "$IDENTITE_SIGNATURE" != "Developer ID Application" ] || [ "$NOTARISER" != 1 ]; }; then
  echo "publier.sh : une version publiee est signee par le Developer ID et notarisee (IDENTITE_SIGNATURE, NOTARISER)" >&2
  exit 1
fi
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-iot-publication}
# Le numero de compilation compte les commits : un clone superficiel donnerait 1, que l'app prend pour une
# compilation de travail (jamais de mise a jour). Il faut un clone complet.
if [ "$(git rev-parse --is-shallow-repository)" != false ]; then
  echo "publier.sh : clone superficiel (ou hors git) ; publier depuis un clone complet" >&2
  exit 1
fi
# Pas d'app sans icone.
if [ ! -e MaillageIoT/Ressources/AppIcon.icon ]; then
  echo "publier.sh : MaillageIoT/Ressources/AppIcon.icon absent ; pas de version sans icone" >&2
  exit 1
fi
# L'identifiant de bundle de la cible MaillageIoT, lu dans le seul bloc « targets: / MaillageIoT: » de project.yml
# (sans PyYAML : /usr/bin/python3 n'en a pas toujours). Rien de trouve : la garde ne conclut pas, code 1.
identifiants=$(awk '
  /^targets:[[:space:]]*(#.*)?$/ { cibles = 1; cible = 0; next }
  /^[^[:space:]#]/ { cibles = 0; cible = 0; next }
  cibles && /^  [^[:space:]#]/ { cible = ($0 ~ /^  MaillageIoT:[[:space:]]*(#.*)?$/); next }
  cible && /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER:/ {
    v = $0
    sub(/^[^:]*:[[:space:]]*/, "", v)
    sub(/[[:space:]]+#.*$/, "", v)
    sub(/[[:space:]]+$/, "", v)
    gsub(/^["\047]|["\047]$/, "", v)
    print v
  }' project.yml)
if [ -z "$identifiants" ]; then
  echo "publier.sh : identifiant de la cible MaillageIoT introuvable dans project.yml ; rien n'est publie" >&2
  exit 1
fi
# La repetition n'est jamais publiee : la garde passe sur chaque identifiant de la cible, avant tout le reste.
for identifiant in $identifiants; do
  "$PYTHON" -I outils/refuser_repetition.py "$identifiant" || exit 1
done
# Les deux controles prives (Thread, Zigbee) par une seule enveloppe ; la table n'y sert pas (elle existe pour que
# publication.py trouve le controle). Une valeur de l'appelant ne remplace pas la double garde.
export CONTROLE_ANONYMISATION=outils/anonymisation_double.py
export TABLE_ANONYMISATION=outils/anonymisation_double.py
export DD
exec "$PYTHON" outils/publication.py publier "$@" --identite "$IDENTITE_SIGNATURE" \
  --auteur Djoko-cli --etiquette v --flux appcast.xml --licence outils/Sparkle-LICENSE.txt \
  --nom-app "Maillage IoT" --fichier Maillage-IoT --depot-github Djoko-cli/maillage-iot \
  --projet MaillageIoT.xcodeproj --schema MaillageIoT --cible MaillageIoT \
  --test 'bash outils/tester.sh' \
  --test 'xcodebuild -project MaillageIoT.xcodeproj -scheme MaillageIoT -destination platform=macOS -derivedDataPath "$DD" -testLanguage en -testRegion US test' \
  --test 'bash outils/tester-sondes.sh' \
  --test 'sh outils/thread-route/tests.sh' \
  --textes MaillageIoT/Ressources/Localizable.xcstrings --textes MaillageIoT/Ressources/InfoPlist.xcstrings
