"""La copie de Thread Route (outils/thread-route) est celle de sa source, le depot du pont Halo
(tools/macos/thread-route), a la revision notee dans outils/thread-route.source : l'arbre git de
la source. outils/synchroniser-thread-route.sh refait la copie et la note.

  /usr/bin/python3 -m unittest discover -s outils/tests

Le depot du pont Halo (DEPOT_HALO, par defaut ~/Documents/Dev/esp32/benq) n'est lu que s'il est la.
"""
import hashlib
import os
import re
import subprocess
import tempfile
import unittest

RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COPIE = os.path.join(RACINE, 'outils', 'thread-route')
SOURCE = os.path.join(RACINE, 'outils', 'thread-route.source')
DEPOT_HALO = os.environ.get('DEPOT_HALO', os.path.expanduser('~/Documents/Dev/esp32/benq'))
IGNORES = {'.DS_Store'}


def arbre_git(dossier):
    """Identifiant git (SHA-1) de l'arbre d'un dossier de fichiers, sans sous-dossier, tel que git le calcule :
    un blob par fichier (« blob <taille>\\0 » puis le contenu), le mode 100755 ou 100644 selon le droit
    d'execution, les entrees dans l'ordre des octets de leur nom."""
    entrees = []
    for nom in os.listdir(dossier):
        if nom in IGNORES:
            continue
        chemin = os.path.join(dossier, nom)
        if os.path.isdir(chemin):
            raise ValueError('sous-dossier inattendu : ' + nom)
        with open(chemin, 'rb') as f:
            contenu = f.read()
        blob = hashlib.sha1(b'blob %d\0' % len(contenu) + contenu).digest()
        mode = b'100755' if os.access(chemin, os.X_OK) else b'100644'
        entrees.append((nom.encode('utf-8'), mode, blob))
    corps = b''.join(mode + b' ' + nom + b'\0' + blob for nom, mode, blob in sorted(entrees))
    return hashlib.sha1(b'tree %d\0' % len(corps) + corps).hexdigest()


def source_notee():
    """Les champs de outils/thread-route.source : « cle : valeur » par ligne."""
    with open(SOURCE, encoding='utf-8') as f:
        return dict(re.findall(r'^(\w+) : (.+)$', f.read(), re.M))


class CopieThreadRouteTests(unittest.TestCase):
    def test_arbre_git_comme_git(self):
        """arbre_git rend l'identifiant que git donne au meme dossier (un fichier executable, un ordinaire)."""
        with tempfile.TemporaryDirectory() as d:
            sous = os.path.join(d, 'x')
            os.mkdir(sous)
            with open(os.path.join(sous, 'b.sh'), 'w') as f:
                f.write('#!/bin/sh\necho b\n')
            os.chmod(os.path.join(sous, 'b.sh'), 0o755)
            with open(os.path.join(sous, 'a.c'), 'w') as f:
                f.write('int a;\n')
            env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
            subprocess.run(['git', 'init', '-q', d], check=True, env=env)
            subprocess.run(['git', '-C', d, 'add', 'x'], check=True, env=env)
            arbre = subprocess.run(['git', '-C', d, 'write-tree', '--prefix=x/'], check=True, env=env,
                                   capture_output=True, text=True).stdout.strip()
            self.assertEqual(arbre_git(sous), arbre)

    def test_copie_conforme_a_la_revision_notee(self):
        notee = source_notee()
        self.assertEqual(notee.get('chemin'), 'tools/macos/thread-route')
        self.assertRegex(notee.get('arbre', ''), r'^[0-9a-f]{40}$')
        self.assertEqual(arbre_git(COPIE), notee['arbre'],
                         'la copie a change : outils/synchroniser-thread-route.sh la refait depuis sa source')

    def test_revision_notee_dans_la_source(self):
        """L'arbre note existe dans le depot du pont Halo, s'il est sur ce Mac : la copie vient bien de lui."""
        if not os.path.isdir(DEPOT_HALO):
            self.skipTest('depot du pont Halo absent : ' + DEPOT_HALO)
        r = subprocess.run(['git', '-C', DEPOT_HALO, 'cat-file', '-t', source_notee()['arbre']],
                           capture_output=True, text=True)
        self.assertEqual(r.stdout.strip(), 'tree', 'arbre note introuvable dans ' + DEPOT_HALO)


if __name__ == '__main__':
    unittest.main()
