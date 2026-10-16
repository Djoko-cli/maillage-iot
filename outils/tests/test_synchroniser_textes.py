"""Tests de outils/synchroniser-textes.sh : le catalogue garde son saut de ligne final (xcstringstool l'enleve).

Un faux `xcrun` (qui retire le saut de ligne final, comme le vrai) est mis en tete du PATH, et le catalogue est une copie
dans un dossier temporaire (variable CATALOGUE) : ni le vrai catalogue ni le vrai xcstringstool ne servent.
"""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "synchroniser-textes.sh"

FAUX_XCRUN = """#!/bin/sh
# xcrun xcstringstool sync <catalogue> --stringsdata ... : reecrit le catalogue sans son saut de ligne final.
[ "$1" = xcstringstool ] && [ "$2" = sync ] || exit 2
python3 - "$3" <<'PY'
import sys
p = sys.argv[1]
d = open(p, "rb").read().rstrip(b"\\n")
open(p, "wb").write(d)
PY
"""


class SauterLigneFinale(unittest.TestCase):
    def lancer(self, contenu):
        with tempfile.TemporaryDirectory() as t:
            t = pathlib.Path(t)
            (t / "bin").mkdir()
            xcrun = t / "bin" / "xcrun"
            xcrun.write_text(FAUX_XCRUN)
            xcrun.chmod(0o755)
            objets = t / "dd/Build/Intermediates.noindex/MaillageIoT.build/Debug/MaillageIoT.build/Objects-normal/arm64"
            objets.mkdir(parents=True)
            source = t / "Source.swift"
            source.write_text("// source\n")
            (objets / "Source.stringsdata").write_text(json.dumps({"source": str(source), "tables": {}}))
            catalogue = t / "Localizable.xcstrings"
            catalogue.write_bytes(contenu)
            env = dict(os.environ, PATH=f"{t / 'bin'}:{os.environ['PATH']}", DD=str(t / "dd"), CATALOGUE=str(catalogue))
            r = subprocess.run(["sh", str(SCRIPT)], env=env, capture_output=True, text=True)
            return r, catalogue.read_bytes()

    def test_le_saut_de_ligne_final_revient(self):
        r, apres = self.lancer(b'{\n  "version" : "1.0"\n}\n')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(apres.endswith(b"}\n"), apres[-10:])
        self.assertFalse(apres.endswith(b"\n\n"))

    def test_un_catalogue_deja_termine_par_un_saut_de_ligne_n_en_gagne_pas_deux(self):
        # Le faux xcrun le retire toujours : le script ne doit en remettre qu'un.
        _, apres = self.lancer(b'{\n  "version" : "1.0"\n}')
        self.assertEqual(apres.count(b"\n\n"), 0)
        self.assertTrue(apres.endswith(b"}\n"))


if __name__ == "__main__":
    unittest.main()
