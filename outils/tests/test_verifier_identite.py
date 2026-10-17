"""Tests de la garde d'identite (outils/verifier_identite.py, phase 4, tache 8) : aucun litteral de l'identite de l'app reelle
dans le code, hors du fichier d'identite et des cas listes.

  python3 -I -m unittest discover -s outils/tests -p 'test_verifier_identite.py'
"""
import os
import subprocess
import sys
import tempfile
import unittest

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(RACINE, "outils"))
import verifier_identite  # noqa: E402


def arbre(fichiers):
    """Un depot minimal : {chemin relatif: contenu}."""
    d = tempfile.mkdtemp()
    for chemin, contenu in fichiers.items():
        complet = os.path.join(d, chemin)
        os.makedirs(os.path.dirname(complet), exist_ok=True)
        with open(complet, "w") as f:
            f.write(contenu)
    return d


APPEL = "MaillageIoT/App/ModulesApp.swift"


def defauts(source, chemin=APPEL):
    return verifier_identite.controler(arbre({chemin: source}))


class GardeDIdentite(unittest.TestCase):
    def test_un_service_en_dur_est_refuse(self):
        d = defauts('let t = TrousseauSystemeThread(service: "fr.djoko.maillage.iot.sonde-thread")\n')
        self.assertEqual(len(d), 1)
        self.assertIn(APPEL + ":1", d[0])

    def test_l_identifiant_nu_de_l_app_reelle_est_refuse(self):
        self.assertEqual(len(defauts('let id = "fr.djoko.maillage.iot"\n')), 1)

    def test_un_service_de_l_app_reelle_sous_un_autre_dossier_est_refuse(self):
        for dossier in ("MaillageCoeur", "ProtocoleThread", "ProtocoleZigbee"):
            self.assertEqual(len(defauts('let s = "fr.djoko.maillage.iot.pont-hue"\n', dossier + "/X.swift")), 1, dossier)

    def test_un_commentaire_n_est_pas_un_litteral(self):
        src = ('// "fr.djoko.maillage.iot.sonde-thread"\n/// "fr.djoko.maillage.iot"\n'
               '/* "fr.djoko.maillage.iot" */ let x = 1 // "fr.djoko.maillage.iot"\n'
               '/* a /* "fr.djoko.maillage.iot" imbrique */ "fr.djoko.maillage.iot" encore */ let y = 2\n')
        self.assertEqual(defauts(src), [])

    def test_une_chaine_apres_un_commentaire_de_bloc_est_vue(self):
        self.assertEqual(len(defauts('/* x */ let s = "fr.djoko.maillage.iot.sonde-thread"\n')), 1)

    def test_chaines_a_plusieurs_lignes_et_guillemets_echappes(self):
        self.assertEqual(len(defauts('let s = """\n  a\n  fr.djoko.maillage.iot.pont-hue\n  """\n')), 1)
        self.assertEqual(defauts('let s = "a \\" // pas un commentaire"\nlet t = 1\n'), [])
        self.assertEqual(len(defauts('let s = "a \\" // pas un commentaire fr.djoko.maillage.iot"\n')), 1)

    def test_le_fichier_d_identite_est_exempte(self):
        self.assertEqual(defauts('static let identifiantPublie = "fr.djoko.maillage.iot"\n', "MaillageIoT/Commun/IdentiteApp.swift"), [])

    def test_un_cas_liste_n_est_admis_que_dans_son_fichier(self):
        liste = ('let file = DispatchQueue(label: "fr.djoko.maillage.iot.dnssd")\n', "MaillageIoT/Commun/Bonjour/ResolveurDNSSD.swift")
        self.assertEqual(defauts(*liste), [])
        self.assertEqual(len(defauts(liste[0], APPEL)), 1)
        # ...et un autre litteral, dans ce meme fichier, reste refuse.
        self.assertEqual(len(defauts(liste[0] + 'let s = "fr.djoko.maillage.iot.sonde-thread"\n', liste[1])), 1)

    def test_les_anciens_services_lus_sont_admis_dans_leur_fichier(self):
        self.assertEqual(defauts('static let serviceAncien = "fr.djoko.maillage.sonde"\n',
                                 "MaillageIoT/Thread/Sonde/Reseau/TrousseauReprisThread.swift"), [])
        self.assertEqual(len(defauts('static let serviceAncien = "fr.djoko.maillage.sonde"\n')), 1)

    def test_les_tests_ne_sont_pas_controles(self):
        self.assertEqual(defauts('let s = "fr.djoko.maillage.iot.sonde-thread"\n', "MaillageIoTTests/IdentiteAppTests.swift"), [])

    def test_le_depot_est_propre(self):
        self.assertEqual(verifier_identite.controler(RACINE), [])

    def test_la_liste_des_cas_admis_n_a_pas_de_restes(self):
        # Un cas liste qui n'existe plus dans son fichier est a retirer de la liste : elle ne doit pas grossir en silence.
        self.assertEqual(verifier_identite.restes(RACINE), [])

    def test_code_de_sortie(self):
        script = os.path.join(RACINE, "outils", "verifier_identite.py")
        propre = subprocess.run([sys.executable, "-I", script], capture_output=True, text=True, cwd=RACINE)
        self.assertEqual(propre.returncode, 0, propre.stdout + propre.stderr)
        sale = arbre({APPEL: 'let s = "fr.djoko.maillage.iot.sonde-thread"\n'})
        r = subprocess.run([sys.executable, "-I", script, "--racine", sale], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn(APPEL + ":1", r.stderr)


if __name__ == "__main__":
    unittest.main()
