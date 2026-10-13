#!/bin/sh
# Copie Thread Route depuis sa source, le depot du pont Halo, a l'identique : outils/thread-route/
# recoit les fichiers de tools/macos/thread-route a la revision donnee (main par defaut), et
# outils/thread-route.source note l'arbre git de cette source. outils/tests/test_thread_route.py
# verifie la copie. Ne rien modifier dans outils/thread-route : changer la source, puis copier.
#   outils/synchroniser-thread-route.sh [revision]
#   DEPOT_HALO : le depot du pont Halo (par defaut ~/Documents/Dev/esp32/benq)
set -eu
cd "$(dirname "$0")/.."
DEPOT=${DEPOT_HALO:-$HOME/Documents/Dev/esp32/benq}
REV=${1:-main}
CHEMIN=tools/macos/thread-route
ARBRE=$(git -C "$DEPOT" rev-parse --verify "$REV:$CHEMIN")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$DEPOT" archive "$REV" "$CHEMIN" | tar -x -C "$TMP"
rm -rf outils/thread-route
cp -R "$TMP/$CHEMIN" outils/thread-route
cat > outils/thread-route.source <<FIN
Copie de Thread Route, a l'identique : ne pas la modifier ici (outils/synchroniser-thread-route.sh).
depot : Djoko-cli/benq-screenbar-halo-matter
chemin : $CHEMIN
arbre : $ARBRE
FIN
echo "copie : $CHEMIN, arbre $ARBRE"
