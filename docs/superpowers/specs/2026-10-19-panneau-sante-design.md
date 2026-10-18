# Panneau de santé dans la vue par pièces — conception

Date : 19/10/2026. Demande de Djoko (backlog §8 de `2026-10-13-maillage-iot-design.md`, « Panneau de santé dans la vue
par pièces », qui absorbe l'ancienne « vue de santé par pièce »). Conception validée en conversation le 19/10.

## 1. Intention

Voir **d'un coup d'œil l'état actuel du réseau** : les nœuds **perdus** et ceux **à surveiller**, **par protocole**
(Thread, Zigbee), sans parcourir le journal ni la scène. Un réseau réel peut avoir beaucoup d'appareils fautifs à la fois :
la clarté passe avant tout.

- **Buts** : un résumé toujours visible (replié) ; une liste claire de ce qui ne va pas dans la portée regardée (ouvert) ;
  un clic qui mène à l'appareil.
- **Hors sujet** : l'historique et les changements récents (le journal reste à part) ; les notifications ; les appareils
  sains ; les nœuds dont l'état est inconnu (pas encore de maillage).
- **À éviter** : un panneau qui encombre la scène ou cache des nœuds ; une liste interminable sans repère ; un panneau qui
  dirait « tout va bien » alors qu'un protocole n'a pas encore été relevé.

## 2. Ce que montre le panneau

### 2.1 Les deux familles (décidé avec Djoko)

**Tous les nœuds, sans distinction de nature** (décidé avec Djoko le 19/10) : appareils finaux, routeurs Thread, routeurs
de bordure, routeurs Zigbee et coordinateur (le pont). Un routeur perdu est souvent la panne la plus grave : il compte
comme les autres. Les états des appareils viennent de `EntreeScene.appareils` ; ceux des routeurs et des routeurs de
bordure de la scène et de leurs suivis (routeur disparu, routeur de bordure d'une autre partition, pont injoignable) :
les mêmes familles s'appliquent, avec leur cause (« routeur disparu depuis… », « autre partition », « pont injoignable »).
Dans le tableau, « appareil » vaut pour « nœud ».

| Famille | Couleur | États (`AppareilAffiche`) | Cause affichée |
|---|---|---|---|
| **Perdu** | rouge | `etat == .disparu` (Thread et Zigbee) ; `etat == .injoignable` (Zigbee, pont qui le dit injoignable) | « disparu depuis 14:05 » (début de la disparition en cours : le plus récent `appareilDisparu` ou `routeurDisparu` du nœud ; sans date connue, « disparu » seul) ; « injoignable » |
| **À surveiller** | orange | pile faible (`batterie.faible`) ; `verifie == true` (joignable, adresse plus annoncée) ; `etat == .sansAdresse` (adresse non annoncée) ; `etat == .partitionCoupee` (Thread, partition coupée) | « pile 12 % » (ou « pile faible » sans niveau) ; « adresse plus annoncée » ; « adresse non annoncée » ; « autre partition » |

Un appareil qui relève des deux familles n'apparaît qu'une fois, dans **Perdu**, avec la cause de perte. Un appareil à
surveiller pour deux raisons montre la plus grave, dans l'ordre du tableau (*décision du constructeur possible : afficher
les deux causes séparées par « · »*).

### 2.2 Replié : la capsule (décidé : option C)

En haut à gauche de la vue par pièces, en verre comme la légende (qui reste en bas à gauche) :
« Santé » puis, pour chaque protocole montré, son signe (rond Thread, hexagone Zigbee, ceux de la légende) et deux
pastilles : rouge = nombre de perdus, orange = nombre à surveiller. Une pastille à zéro n'est pas montrée. Sans aucun
appareil perdu ni à surveiller : « Tout va bien ». **Les comptes de la capsule portent toujours sur toute la maison**,
quel que soit le focus. Un protocole dont aucun relevé n'est encore arrivé n'est pas compté comme « tout va bien » :
sa place montre « … » (*ma décision, voir §5*).

### 2.3 Ouvert : la liste (décidé : option B)

- Titre : « Santé · <portée> » : « Maison » (vue d'ensemble), le nom du niveau isolé, ou le nom de la pièce isolée.
- Une section par protocole montré, avec son signe, son nom et ses deux pastilles (comptes **de la portée**).
- Une ligne par appareil de la portée : point rouge ou orange, **nom**, **pièce**, **cause** (à droite).
- Ordre : perdus d'abord, puis à surveiller ; dans chaque famille, par pièce puis par nom (ordre alphabétique de la
  langue).
- **La liste suit le focus** (décidé) : vue d'ensemble = toute la maison ; niveau isolé = ce niveau ; pièce isolée = cette
  pièce. Un protocole sans rien dans la portée montre « Rien à signaler » sous son titre.
- **Ligne « Ailleurs »** (décidé) : hors de la vue d'ensemble, s'il y a des appareils perdus ou à surveiller hors de la
  portée, une dernière ligne discrète : « Ailleurs : 1 perdu, 2 à surveiller ». Un clic ramène à la vue d'ensemble.
- Liste longue : hauteur limitée, défilement à l'intérieur du panneau (*ma décision*) ; le panneau ne descend jamais
  plus bas que la moitié de la hauteur de la vue, pour laisser la scène lisible.

### 2.4 Comportements

- **Clic sur une ligne** : comme un clic sur le nœud, et il y mène. L'app isole la pièce de l'appareil si elle n'est pas
  déjà la pièce isolée (vol de caméra existant), puis sélectionne l'appareil : focus et fiche. Un appareil sans pièce
  placée est sélectionné sans changer de vue (*ma décision*).
- **Interrupteurs de protocole** (capsules Thread / Zigbee de la barre) et « Activer ce protocole » : un protocole masqué
  ou éteint disparaît du panneau, capsule comprise.
- **Repli** : le panneau se souvient s'il est replié ou ouvert (préférence à lui, distincte de celle de la légende) ;
  replié par défaut.
- **Animation** : la même que la légende (durée, transition, réduction des animations respectée), ancrée en haut à
  gauche.
- **Obstacle** : le panneau, ouvert ou replié, est un obstacle pour les noms des nœuds, comme la légende.
- **Démo** : le panneau montre les appareils de la démo, sans code à part ; l'heure de référence est celle de la démo.
- **Textes** : français et anglais (catalogue) ; heures relatives comme dans la fiche.
- **Captures** (`CapturesPieces`) : un cas avec le panneau replié et un cas ouvert, pour la démo combinée ; le verre a le
  repli de capture de la légende.

## 3. Contraintes

- Swift 6 strict, avertissements = erreurs ; SwiftUI ; le panneau lit `EntreeScene` (déjà filtrée sur les protocoles
  montrés) et l'état du moteur (`MoteurPieces.isolement`) ; aucun nouvel état réseau.
- Liquid Glass (`.glassEffect`), même rendu que `VerreDeLegende`.
- Aucun texte sans traduction ; aucune valeur réelle dans les tests, les captures ou les commentaires.
- Les références de rejeu ne changent pas.

## 4. Repères dans le code (relevés le 19/10)

- Légende : `MaillageIoT/Vues/Pieces/LegendePieces.swift` (`VerreDeLegende` ~l.476, clé `legendeRepliee`) ; placée par
  `LigneDuBas` dans `FenetrePieces.swift` (~l.561) ; obstacle `.obstacle("legende", moteur)`.
- Haut de la vue : `HautPieces` (barre, bandeau de partition, fil « Maison › … ») : le panneau se place **sous** ce bloc.
- Animation : `Apparition.swift` (`dureeLegende`, `transitionLegende`, `animationDuConteneurLegende`…).
- Appareils : `EntreeScene.appareils[IdNoeud]` (`AppareilAffiche` : `nom`, `piece`, `etat`, `batterie`, `verifie`,
  `endormi`) ; pièce placée et niveau par `scene.noeuds[...].piece`, `scene.pieces[i].etage`, `scene.etages[e].nom`.
- Date de disparition : `surveillance.evenements(de: id)` (type `.appareilDisparu`), heure de référence
  `surveillance.maintenant(de:a:)`, mise en forme `FicheNoeud.relatif`.
- Focus : `moteur.isolement` (`.maison`, `.etage`, `.piece`) ; aller à une pièce : `moteur.isoler(i)` ; vers la maison :
  `moteur.versMaison(enFondu:)` ; sélection : `moteur.selection = id`.
- Protocoles montrés : `EntreeScene.montres`, `cachees`, `entree.montre(id)`.
- Tests à imiter : `LegendePiecesTests`, `LegendePiecesZigbeeTests`, `DemoCombineeTests`, `IsolementTests`,
  `MoletteEtEchapTests`, `VueProtocolesTests` ; captures : `CapturesPieces.casCombinee` et les tests qui comptent les cas.

## 5. Laissé au constructeur, ou décidé par moi (à vérifier par Djoko)

Décisions prises après la relecture du constructeur (19/10) :
- **Date de disparition** : le début de la disparition en cours (le plus récent événement de disparition du nœud) ; si le
  journal ne la donne pas (disparu avant le lancement, événement trop ancien), « disparu » sans heure. Pas de nouvelle
  API de journal pour cela.
- **« … » pour un protocole** : seulement quand le protocole est actif et montré mais n'a encore aucun relevé (aucun
  instantané Thread, aucun maillage Zigbee affiché). Un relevé ancien n'est pas « … » (le bandeau « ancien » de la vue le
  dit déjà) ; un protocole relevé sans aucun nœud fautif est « Tout va bien ».
- **Pièce et portée** : la pièce **placée dans la scène** (celle que l'on voit, choix de Djoko compris), pas la pièce
  brute de Maison : elle donne la colonne « pièce », le tri et l'appartenance à un niveau ou à une pièce isolée. Un nœud
  sans pièce placée compte dans la portée « Maison » et, hors de la vue d'ensemble, dans « Ailleurs ».
- **Nœud absent de la scène** (sans position, ou masqué) : sa ligne reste visible mais n'est pas cliquable (atténuée).
- **Place dans la fenêtre** : au constructeur, sous le bloc `HautPieces` mesuré ; la limite « moitié de la hauteur » se
  compte sur la hauteur libre entre ce bloc et la ligne du bas (légende, fiche).

Décisions antérieures :

- Place exacte sous le haut de la vue, marges, largeur (proche de la légende) : au constructeur, au rendu de la légende.
- « … » pour un protocole sans relevé (plutôt que « Tout va bien ») : ma décision.
- Défilement dans une hauteur limitée à la moitié de la vue : ma décision.
- Appareil sans pièce placée : sélection sans changement de vue : ma décision.
- Libellés exacts des causes en anglais : au constructeur, dans le ton de la légende.
