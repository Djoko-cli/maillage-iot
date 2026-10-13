#!/bin/bash
# Controle avant commit (plan de l'etape 1) : la garde sur les fichiers suivis, puis les deux controles
# d'anonymisation prives sur les fichiers indexes. N'affiche que des bilans. Code 0 : propre.
set -u
racine=$(git rev-parse --show-toplevel)
cd "$racine" || exit 1
anon=.superpowers/anonymisation
fautes=0
python3 outils/garde.py || fautes=$((fautes + 1))
liste=()
while IFS= read -r f; do [ -f "$f" ] && liste+=("$f"); done < <(git diff --cached --name-only --diff-filter=d)
if [ ${#liste[@]} -gt 0 ]; then
  python3 "$anon/thread/outils/controles.py" fichiers --table "$anon/thread/table.json" "${liste[@]}" \
    > "$anon/sortie-index-thread.txt" 2>&1 || { echo "controle thread : defaut" >&2; fautes=$((fautes + 1)); }
  python3 "$anon/zigbee/controles.py" fichiers --table "$anon/zigbee/table.json" "${liste[@]}" \
    > "$anon/sortie-index-zigbee.txt" 2>&1 || { echo "controle zigbee : defaut" >&2; fautes=$((fautes + 1)); }
  tail -1 "$anon/sortie-index-zigbee.txt"
fi
echo "controler-index : ${#liste[@]} fichier(s) indexe(s), $fautes defaut(s)"
[ "$fautes" -eq 0 ]
