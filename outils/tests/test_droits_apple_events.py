"""Garde du droit « Apple events » (banc de la repetition) : l'assistant de reprise quitte l'ancienne app par l'evenement Apple
« quit ». Le bac a sable n'autorise que les identifiants de l'exception `com.apple.security.temporary-exception.apple-events` :
exactement les deux anciennes apps, dans l'app ET dans la repetition, jamais une autre, avec la raison de l'Automatisation dite
en francais et en anglais.

  python3 -I -m unittest discover -s outils/tests
"""
import json
import os
import plistlib
import re
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
EXCEPTION = "com.apple.security.temporary-exception.apple-events"
AUTOMATISATION = "com.apple.security.automation.apple-events"
DROITS = ("MaillageIoT/Droits.entitlements", "MaillageIoTRepetition/Droits.entitlements")


def identifiants_des_anciennes_apps():
    """Les identifiants de bundle de `ContratExport.AppSource.identifiantBundle` (la source de verite des anciennes apps)."""
    with open(os.path.join(RACINE, "MaillageCoeur", "Reprise", "ContratExport.swift"), encoding="utf-8") as f:
        source = f.read()
    corps = source[source.index("public var identifiantBundle: String {"):]
    corps = corps[:corps.index("\n        }\n")]
    return sorted(re.findall(r'case \.\w+: "([^"]+)"', corps))


def droits(chemin):
    with open(os.path.join(RACINE, chemin), "rb") as f:
        return plistlib.load(f)


class DroitsAppleEvents(unittest.TestCase):
    def test_les_anciennes_apps_sont_les_deux_attendues(self):
        self.assertEqual(identifiants_des_anciennes_apps(), ["fr.djoko.maillage", "fr.djoko.maillage.zigbee"])

    def test_l_exception_ne_vise_que_les_deux_anciennes_apps_dans_l_app_et_dans_la_repetition(self):
        for chemin in DROITS:
            self.assertEqual(sorted(droits(chemin).get(EXCEPTION, [])), identifiants_des_anciennes_apps(), chemin)

    def test_le_runtime_durci_laisse_envoyer_des_evenements(self):
        # Sans ce droit macOS refuse l'evenement sans rien demander ; la portee reste celle de l'exception du bac a sable.
        for chemin in DROITS:
            self.assertIs(droits(chemin).get(AUTOMATISATION), True, chemin)

    def test_la_raison_de_l_automatisation_est_dite_dans_les_deux_langues(self):
        with open(os.path.join(RACINE, "MaillageIoT", "Ressources", "InfoPlist.xcstrings"), encoding="utf-8") as f:
            cle = json.load(f)["strings"]["NSAppleEventsUsageDescription"]["localizations"]
        for langue in ("fr", "en"):
            texte = cle[langue]["stringUnit"]["value"]
            self.assertIn("Maillage Thread", texte, langue)
            self.assertIn("Maillage Zigbee", texte, langue)
        self.assertNotEqual(cle["fr"]["stringUnit"]["value"], cle["en"]["stringUnit"]["value"])
        with open(os.path.join(RACINE, "project.yml"), encoding="utf-8") as f:
            projet = f.read()
        # Une raison dans l'Info.plist de chaque cible (l'app et la repetition).
        self.assertEqual(len(re.findall(r"^\s+NSAppleEventsUsageDescription: ", projet, re.M)), 2)


if __name__ == "__main__":
    unittest.main()
