#!/bin/bash
# Recopie les exports d'exemple que les anciennes apps ecrivent elles-memes (phase 4, tache 9), a l'octet, depuis leurs
# depots, et verifie leurs empreintes :
#   bash outils/recopier-exports-anciennes-apps.sh              recopie puis verifie (ecrit ORIGINE.md)
#   bash outils/recopier-exports-anciennes-apps.sh --verifier   ne modifie rien : les copies de ce depot sont-elles celles
#                                                               des depots d'origine, et leurs empreintes sont-elles bonnes ?
# Sources (lecture seule, jamais modifiees) : <depot>/docs/export-exemple/
#   Maillage Thread 1.4.0   DEPOT_THREAD  (defaut : ../maillage-thread)   -> exports/thread-1.4.0-export
#   Maillage Zigbee 1.2.0   DEPOT_ZIGBEE  (defaut : ../maillage-zigbee)   -> exports/zigbee-1.2.0-export
# Sortie : MaillageIoTTests/Ressources/exports (SORTIE=/dossier pour un autre emplacement). Ils s'ajoutent aux exports
# provisoires de outils/generer-exports-exemple.sh (thread-1.3.0, zigbee-1.1.1), qui restent.
# Chaque export source est controle avant d'etre copie : manifeste lisible, app et version attendues, chaque fichier du manifeste
# present avec sa taille et son SHA-256, rien en dehors du manifeste (sauf .DS_Store et fichiers AppleDouble ._*), aucun chemin
# qui sorte du dossier, aucun lien symbolique ; et le dossier source ne porte aucune modification non commitee. ORIGINE.md dit
# de quel depot et de quel commit viennent les copies. Code 0 : tout est bon ; 1 : un defaut (affiche).
set -u
cd "$(dirname "$0")/.." || exit 1
RACINE=$(pwd)
PARENT=$(dirname "$RACINE")
SORTIE=${SORTIE:-$RACINE/MaillageIoTTests/Ressources/exports}
MODE=recopier
case "${1:-}" in
  "") ;;
  --verifier) MODE=verifier ;;
  *) echo "usage : bash outils/recopier-exports-anciennes-apps.sh [--verifier]"; exit 1 ;;
esac
# nom:depot:dossier de destination:app attendue:version attendue
SOURCES="thread:${DEPOT_THREAD:-$PARENT/maillage-thread}:thread-1.4.0-export:thread:1.4.0 zigbee:${DEPOT_ZIGBEE:-$PARENT/maillage-zigbee}:zigbee-1.2.0-export:zigbee:1.2.0"

# Controle d'un dossier d'export (arg 1), app et version attendues (arg 2, 3). Affiche le defaut, code 1 s'il y en a un.
controler() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import hashlib, json, os, sys
dossier, app, version = sys.argv[1:4]
defauts = []
def defaut(texte): defauts.append(texte)
try:
    with open(os.path.join(dossier, "manifeste.json"), "rb") as f:
        manifeste = json.load(f)
except Exception as e:
    print("manifeste illisible : %s" % type(e).__name__); sys.exit(1)
if manifeste.get("format") != 1: defaut("format %r au lieu de 1" % manifeste.get("format"))
if manifeste.get("app") != app: defaut("app %r au lieu de %r" % (manifeste.get("app"), app))
if manifeste.get("versionApp") != version: defaut("version %r au lieu de %r" % (manifeste.get("versionApp"), version))
declares = set()
for entree in manifeste.get("fichiers", []):
    chemin = entree.get("chemin", "")
    parties = chemin.split("/")
    if chemin.startswith("/") or any(p in ("", ".", "..") for p in parties):
        defaut("chemin qui sort du dossier : %r" % chemin); continue
    if chemin in declares: defaut("chemin en double : %s" % chemin)
    declares.add(chemin)
    complet = os.path.join(dossier, chemin)
    if os.path.islink(complet) or not os.path.isfile(complet): defaut("fichier absent ou lien : %s" % chemin); continue
    with open(complet, "rb") as f: octets = f.read()
    if len(octets) != entree.get("taille"): defaut("taille fausse : %s" % chemin)
    if hashlib.sha256(octets).hexdigest() != entree.get("sha256"): defaut("empreinte fausse : %s" % chemin)
presents = set()
for base, dossiers, fichiers in os.walk(dossier):
    for nom in dossiers + fichiers:
        complet = os.path.join(base, nom)
        if os.path.islink(complet): defaut("lien symbolique : %s" % os.path.relpath(complet, dossier))
    for nom in fichiers:
        relatif = os.path.relpath(os.path.join(base, nom), dossier)
        if nom == ".DS_Store" or nom.startswith("._"): continue
        presents.add(relatif)
for extra in sorted(presents - declares - {"manifeste.json"}): defaut("fichier hors manifeste : %s" % extra)
if "reglages.json" not in declares: defaut("reglages.json absent du manifeste")
for d in defauts: print(d)
sys.exit(1 if defauts else 0)
PY
}

DEFAUTS=0
for s in $SOURCES; do
  IFS=: read -r nom depot cible app version <<EOF
$s
EOF
  source="$depot/docs/export-exemple"
  copie="$SORTIE/$cible"
  if [ ! -d "$source" ]; then
    echo "defaut : $nom : export d'exemple absent ($source)"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  if ! sortie=$(controler "$source" "$app" "$version"); then
    printf '%s\n' "$sortie" | sed "s/^/defaut : $nom : source : /"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  # Le dossier source doit etre celui d'un commit (sinon ORIGINE.md mentirait).
  if [ -n "$(GIT_OPTIONAL_LOCKS=0 git -C "$depot" status --porcelain -- docs/export-exemple 2>/dev/null)" ]; then
    echo "defaut : $nom : docs/export-exemple porte des modifications non commitees"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  commit=$(git -C "$depot" log -1 --format=%h -- docs/export-exemple 2>/dev/null)
  if [ "$MODE" = recopier ]; then
    rm -rf "$copie"
    mkdir -p "$copie"
    # -X : ni attributs etendus ni fourche de ressources ; ni .DS_Store ni AppleDouble ne sont recopies.
    (cd "$source" && find . -type f ! -name .DS_Store ! -name '._*' -print0 | sort -z | while IFS= read -r -d '' f; do
      mkdir -p "$copie/$(dirname "$f")" && cp -X "$f" "$copie/$f"
    done)
    echo "recopie : $nom ($commit) -> $cible"
  fi
  if [ ! -d "$copie" ]; then
    echo "defaut : $nom : copie absente ($cible) : lancer sans --verifier"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  if ! sortie=$(controler "$copie" "$app" "$version"); then
    printf '%s\n' "$sortie" | sed "s/^/defaut : $nom : copie : /"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  # La copie est celle de la source, octet pour octet (diff -r ; les .DS_Store et AppleDouble exclus).
  if ! diff -r -x .DS_Store -x '._*' "$source" "$copie" > /dev/null; then
    echo "defaut : $nom : la copie differe de la source : lancer bash outils/recopier-exports-anciennes-apps.sh"
    DEFAUTS=$((DEFAUTS + 1))
    continue
  fi
  echo "ok : $nom $version ($commit) : copie identique, empreintes bonnes"
  eval "COMMIT_$nom=$commit"
done

if [ "$DEFAUTS" -eq 0 ] && [ "$MODE" = recopier ]; then
  cat > "$SORTIE/ORIGINE.md" <<EOF
# Origine des exports des anciennes apps

Copies **a l'octet** des exports d'exemple que les anciennes apps ecrivent elles-memes (valeurs inventees seulement). Ils
s'ajoutent aux exports provisoires de \`outils/generer-exports-exemple.sh\` (\`thread-1.3.0/\`, \`zigbee-1.1.1/\`), qui restent.
Mise a jour : \`bash outils/recopier-exports-anciennes-apps.sh\` (recopie et verifie les empreintes) ;
\`bash outils/recopier-exports-anciennes-apps.sh --verifier\` ne modifie rien.

| Dossier | Depot d'origine | Version | Commit d'origine | Chemin d'origine |
|---|---|---|---|---|
| \`thread-1.4.0-export/\` | maillage-thread | 1.4.0 | \`$COMMIT_thread\` | \`docs/export-exemple/\` |
| \`zigbee-1.2.0-export/\` | maillage-zigbee | 1.2.0 | \`$COMMIT_zigbee\` | \`docs/export-exemple/\` |

Le commit est le dernier de l'ancien depot qui touche \`docs/export-exemple/\`. Ces dossiers ne se modifient jamais a la main :
une difference avec l'ancien depot est un ecart a signaler a la session de cette app.
EOF
  echo "ORIGINE.md ecrit dans $SORTIE"
fi
[ "$DEFAUTS" -eq 0 ] || { echo "recopier-exports-anciennes-apps : $DEFAUTS defaut(s)"; exit 1; }
echo "recopier-exports-anciennes-apps : tout est bon"
