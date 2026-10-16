#!/bin/bash
# Garde des deux sondes (Thread, Zigbee), lancee par outils/tester.sh :
#   bash outils/verifier-sondes.sh
# Refuse (code 1) : (a) l'affectation, hors des fichiers MaillageIoT/<P>/Sonde/SondeMaillage<P>*.swift (app et tests), d'une
# propriete d'etat observe de la sonde qui a perdu son `private(set)` a la decoupe par role (`sonde.etat = ...`,
# `sondeThread.serie = ...`, `sondeZigbee.acces = ...`) ; (b) un appel `ouvrirCanal(` ou `ouvrable(` hors du fichier +USB de
# sa sonde ; (c) une liste de proprietes qui ne suit plus le source. Details et limites : outils/verifier_sondes.py ;
# essai : python3 -m unittest discover -s outils/tests -p 'test_verifier_sondes.py'.
set -u
cd "$(dirname "$0")/.." || exit 1
exec python3 -I outils/verifier_sondes.py
