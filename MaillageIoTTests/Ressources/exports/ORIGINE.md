# Origine des exports des anciennes apps

Copies **a l'octet** des exports d'exemple que les anciennes apps ecrivent elles-memes (valeurs inventees seulement). Ils
s'ajoutent aux exports provisoires de `outils/generer-exports-exemple.sh` (`thread-1.3.0/`, `zigbee-1.1.1/`), qui restent.
Mise a jour : `bash outils/recopier-exports-anciennes-apps.sh` (recopie et verifie les empreintes) ;
`bash outils/recopier-exports-anciennes-apps.sh --verifier` ne modifie rien.

| Dossier | Depot d'origine | Version | Commit d'origine | Chemin d'origine |
|---|---|---|---|---|
| `thread-1.4.0-export/` | maillage-thread | 1.4.0 | `80db469` | `docs/export-exemple/` |
| `zigbee-1.2.0-export/` | maillage-zigbee | 1.2.0 | `412de0b` | `docs/export-exemple/` |

Le commit est le dernier de l'ancien depot qui touche `docs/export-exemple/`. Ces dossiers ne se modifient jamais a la main :
une difference avec l'ancien depot est un ecart a signaler a la session de cette app.
