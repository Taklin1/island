# Firmware du Totem

Firmware du **Totem** (voir `CONTEXT.md` § Totem) : un Waveshare ESP32-C6-Touch-AMOLED-2.16 qui affiche l'**Instantané** poussé par le **Relais** de l'app island sur le réseau local. Afficheur pur : un serveur HTTP entrant, aucune requête sortante, aucun canal vers l'app (ADR-0013, ADR-0014). Le firmware vit dans ce repo pour que le contrat évolue dans une seule PR des deux côtés (ADR-0015).

Cette version affiche deux pages entourées du **Halo** : la **page état** (#159 : la mascotte pixel-art animée selon l'état agrégé, les compteurs par état, Connecté / Déconnecté, l'adresse IP et `island-totem.local`) et la **page Quotas** (#160 : jauges 5 h et 7 d, compte à rebours du reset 5 h). Le toucher bascule d'une page à l'autre et règle la luminosité, rien d'autre.

## Organisation

| Chemin | Rôle |
| --- | --- |
| `platformio.ini` | env `totem_c6` (la carte) et env `native` (tests sur le Mac) |
| `lib/totem_core/` | logique pure, sans `Arduino.h` : décodage de l'Instantané, token, fraîcheur (Déconnecté), `config.json`, ordre de validation de `POST /snapshot`, modèle de vue de la page état, Halo, palette grise, vue des Quotas et compte à rebours, gestes, niveaux de luminosité |
| `src/` | code carte : alimentation et écran, tactile, luminosité (NVS), LVGL, Wi-Fi + mDNS, serveur HTTP, pages état et Quotas et leur bascule (`src/ui/`) |
| `src/generated/totem_sprites.h` | Sprites exportés par `scripts/export_totem_sprites.py` (généré, versionné, ne pas éditer à la main) |
| `test/` | tests natifs de `lib/totem_core/` |
| `contract/` | fixtures du contrat, partagées avec `swift test` (lecture seule, #156) |
| `data/` | système de fichiers LittleFS envoyé sur la carte (`config.json`, non versionné) |

## Installation

PlatformIO 6.2.0 s'installe avec `uv`, sur Python 3.13 :

```sh
uv tool install platformio==6.2.0 --python 3.13   # pio dans ~/.local/bin/pio
```

Pas de `brew install platformio` : sur macOS 26.2, le Python 3.14 de Homebrew qu'il embarque ne charge plus `pyexpat`, et la plateforme pioarduino échoue en créant son environnement Python `~/.platformio/penv` (`ensurepip`).

N'alternez pas avec un autre `pio` (Homebrew, venv…) : s'il tourne sur une autre version de Python, il recrée `~/.platformio/penv` et peut le casser. Vérifiez `which pio` en cas de doute.

Le premier `pio run -e totem_c6` télécharge la plateforme pioarduino épinglée, le core Arduino et la toolchain RISC-V (1 à 2 Go dans `~/.platformio`). S'il est interrompu, relancez-le : les téléchargements sont en cache.

## Configuration : Wi-Fi et token

La config est un fichier `data/config.json` écrit sur la flash (LittleFS). Il n'est pas versionné. Le changer ne demande pas de recompiler, et il survit au reflash du firmware.

```sh
cp data/config.example.json data/config.json
openssl rand -hex 24   # un token long et aléatoire
```

Renseignez dans `data/config.json` :

- `ssid` : un réseau **2,4 GHz** (l'ESP32-C6 ne voit pas le 5 GHz), **sans isolation client** et hors réseau invité, sinon le Mac ne joint pas le Totem ;
- `password` : le mot de passe Wi-Fi (vide pour un réseau ouvert) ;
- `token` : le token partagé, le même que celui saisi dans le menu island (#157). **Un token vide est refusé** : le Totem affiche `CONFIG ERROR` (`token empty`) et ne démarre pas le serveur.

Envoyez la config sur la carte (branchée en USB) :

```sh
pio run -e totem_c6 -t uploadfs
```

Config absente, illisible, sans `ssid` ou avec un token vide : l'écran le dit, et le serveur n'est pas démarré.

## Flasher

La carte se flashe par son USB natif (USB-Serial-JTAG), sans manipulation de boot. Elle apparaît en `/dev/cu.usbmodem*`.

```sh
pio run -e totem_c6 -t upload
pio device monitor -e totem_c6   # journaux série (115200 bauds)
```

Si plusieurs ports existent : `pio run -e totem_c6 -t upload --upload-port /dev/cu.usbmodemXXXX`.

## Vérification locale

Un dev qui touche `firmware/` est vert quand ces deux commandes réussissent (CLAUDE.md règle 4, ADR-0015), en plus de `swift build` / `swift test` :

```sh
pio run -e totem_c6
pio test -e native
```

Vérifiez le code de sortie. Toujours `-e native` : `pio test` seul ne lance aucun test (les tests sont ignorés sur l'env carte pour ne jamais tenter de téléverser). Les tests natifs décodent les fixtures de `contract/` sur place (chemin injecté par `TOTEM_CONTRACT_DIR`). La CI de release ne builde ni ne teste le firmware (ADR-0010).

## Adresse et essai à la main

Au démarrage, l'écran affiche l'IP obtenue (`IP 192.168.x.y`) et `island-totem.local` (mDNS). Il n'y a pas de découverte : saisissez l'une des deux dans le menu island.

```sh
TOKEN=...   # le token de data/config.json
curl -i -X POST http://island-totem.local/snapshot \
  -H "X-Island-Token: $TOKEN" -H "Content-Type: application/json" \
  --data-binary @contract/snapshot-nominal.json      # 204, CONNECTED, mascotte finished, Halo vert
curl -i -X POST http://island-totem.local/snapshot \
  --data-binary @contract/snapshot-nominal.json      # 401, écran inchangé
```

| Requête | Réponse |
| --- | --- |
| `POST /snapshot` sans token ou mauvais token | `401` (vérifié en premier, état et fraîcheur inchangés) |
| corps de plus de 2 048 octets | `413` |
| JSON invalide, sans `v`, `v` différent de 1, champ obligatoire manquant | `400` |
| Instantané accepté | `204` |
| autre méthode sur `/snapshot` | `405` |
| autre chemin | `404` |

**Déconnecté** : au démarrage jusqu'au premier Instantané accepté, après 30 s sans Instantané accepté, et immédiatement sur un Instantané `shutdown: true` (fermeture de l'app). Le prochain Instantané normal repasse Connecté. Une requête refusée ne rafraîchit jamais. En Déconnecté, l'écran n'affiche ni état ni compteurs périmés.

Les libellés à l'écran sont en anglais, avec le lexique d'état d'ADR-0012 (`waiting`, `done`, `working`, `idle`) : `CONNECTED` / `DISCONNECTED`, `CONFIG ERROR`, `Wi-Fi: connecting...`. Ils restent en ASCII, seul jeu couvert par les polices Montserrat intégrées à LVGL.

## Page état

De haut en bas, dans une colonne centrée qui reste à l'intérieur du Halo : `CONNECTED` / `DISCONNECTED`, la mascotte (240×240), les compteurs (`waiting N   done N` / `working N   idle N`), `IP x.x.x.x` et `island-totem.local`. Chaque élément a une taille fixe : un texte qui change ne déplace jamais la mascotte.

**Mascotte.** Ce sont les Sprites de l'app (`bot.png`), exportés en C : état agrégé `idle` → `sleeping`, `working` → `working`, `done` → `finished`, `waiting` → `question` (comme `SpriteAnimation.animation(for:)`). Chaque pixel 16×16 est dessiné en carré plein de 15×15 (rendu maison, sans mise à l'échelle d'image ni antialiasing) ; seule la zone de la mascotte est invalidée quand la frame change. Frames et fps sont ceux de `SpriteSheet.bot` (`Sources/IslandUI/Sprites.swift`), épinglés par `test_sprites`.

**Compteurs.** Ce sont les compteurs **bruts** envoyés par le Mac : un `waiting 1` avec le Halo éteint est normal (Session en attente déjà acquittée sur le Mac). En Déconnecté, ils sont masqués (jamais de compteurs périmés).

**Halo.** Orange si l'état agrégé est `waiting`, vert si `done`, éteint sinon et en Déconnecté. Il suit ce que le Mac envoie, quel que soit le réglage « Edge outline » du Mac, et ne s'éteint que par l'Acquittement fait sur le Mac. Couleurs : celles du Liseré (SwiftUI `Color.orange` / `Color.green` de `GlowWindow.swift`, apparence sombre : `#FF9F0A` / `#30D158`), pas les teintes des Sprites qui restent sur la mascotte. Il est dessiné sur `lv_layer_top()` (au-dessus de toute page) en lueur intérieure : 4 bordures imbriquées de 6 px, d'opacité décroissante (230, 140, 80, 35), coins arrondis de 24 px. Pas d'ombre plein écran (son cache ne tient pas en SRAM).

**Respiration.** Pour ménager l'AMOLED, l'intensité du Halo oscille lentement entre 60 % et 100 % sur une période de 8,192 s (courbe adoucie), sur sa propre horloge (timer LVGL de 100 ms) : les Instantanés ne la pilotent pas. Elle ne repeint que quatre bandes le long des bords, jamais la mascotte ni les compteurs. Période, profondeur, épaisseur, arrondi et couleurs sont des constantes à régler sur matériel (`lib/totem_core/halo.h`, `src/ui/halo_layer.h`).

**Pas de clignotement.** La page garde le dernier modèle de vue appliqué et ne touche LVGL que sur une vraie différence (`PagePresenter`) : un Instantané identique ou un battement ne redessine rien, et l'index de frame de la mascotte ne repart jamais tant que l'animation ne change pas (y compris au passage Connecté → Déconnecté en dormant).

**Déconnecté.** Mascotte endormie en gris (échange de palette en luminance, Rec. 601), Halo éteint, compteurs masqués.

Le toucher n'acquitte rien (ADR-0013) : il ne sert qu'à la navigation locale (voir « Toucher et luminosité »).

### Régénérer les Sprites

Après un changement de `bot.png` ou de `SpriteSheet.bot` côté app :

```sh
python3 scripts/export_totem_sprites.py          # réécrit src/generated/totem_sprites.h
python3 scripts/export_totem_sprites.py --check  # échoue si le header n'est pas à jour
```

Le script lit `bot.png` et `Sprites.swift` sans rien réécrire côté app (ne relancez pas `scripts/generate_sprites.py` pour ça). Sa sortie est déterministe. La ligne `error` n'est pas exportée.

### Checklist visuelle (carte branchée)

Avec l'app island qui pousse vers le Totem :

1. Au démarrage : `DISCONNECTED`, mascotte endormie grise, pas de Halo, pas de compteurs.
2. Une Session qui travaille : mascotte `working` (lignes de code qui défilent), Halo éteint, `working 1`.
3. Une Session qui attend une réponse : mascotte `question`, Halo orange au même instant que le Liseré du Mac (même avec « Edge outline » désactivé sur le Mac).
4. Une Session terminée non acquittée : mascotte `finished` (coche), Halo vert.
5. Acquittement sur le Mac : le Halo s'éteint dès le push suivant ; le compteur `waiting`/`done` reste (compteur brut).
6. Les quatre animations sont nettes (pixels carrés, sans flou) et à la bonne cadence.
7. Aucun clignotement pendant plusieurs battements (une minute sans changement d'état) : ni mascotte qui repart à sa première frame, ni texte qui scintille.
8. Respiration du Halo lente et discrète, sans à-coups ; épaisseur, arrondi des coins et couleurs acceptables sur la dalle.
9. App quittée (ou 30 s sans Instantané) : `DISCONNECTED`, mascotte grise, Halo éteint.
10. `config.json` invalide : écran `CONFIG ERROR` inchangé, sans mascotte ni Halo.

## Page Quotas

De haut en bas : `QUOTAS` (`QUOTAS - DISCONNECTED` en Déconnecté), la jauge `5 h` avec son pourcentage, le compte à rebours du reset 5 h, puis la jauge `7 d`. Les règles sont celles de l'Étendu (`Sources/IslandUI/QuotaGauges.swift`, recopiées dans `lib/totem_core/quota_view.h` avec la mention « MUST mirror ») :

- **Pourcentage** : l'entier envoyé par le Mac (même arrondi que les jauges du Mac), affiché tel quel (`24%`, `105%`).
- **Remplissage** borné à 0…100 %.
- **Couleur** : vert sous 40 %, jaune sous 75 %, rouge au-delà (SwiftUI `Color.green` / `.yellow` / `.red`, apparence sombre : `#30D158` / `#FFD60A` / `#FF453A`). Le Mac seuille son pourcentage non arrondi : pile à une frontière (39,6 % affiché `40%`), le Totem, qui ne reçoit que l'entier, peut avoir un cran de couleur d'écart.
- **Fenêtre absente** : pas de jauge. **Aucune fenêtre** (le cas le plus fréquent, le tee statusline est désactivé par défaut) : `no quotas`, jamais `0%`.

**Compte à rebours** (cyan `#64D2FF`, icône « rafraîchir » de la police LVGL, le `↺` du Mac n'y existant pas) : le Totem n'a ni heure, ni NTP, ni fuseau. À chaque Instantané accepté, il part de `resetsAt - sentAt`, puis décompte avec `millis()`, sans jamais passer sous 0. Minutes arrondies au supérieur, pour se lire comme l'heure de reset du Mac moins l'heure affichée : `13m`, `2h 05m`, `now` à 0 (`1d 03h` au-delà de 24 h). Pas de compte à rebours si le Mac n'envoie pas de `resetsAt` pour la fenêtre 5 h.

**Déconnecté** : les dernières jauges et le compte à rebours reçus en Connecté restent affichés, estompés et figés, y compris après l'Instantané de fermeture de l'app (qui ne porte pas de Quotas). Au démarrage, `no quotas` estompé. Pas de % de contexte (hors contrat v1) ni d'atténuation nocturne (le Totem n'a pas l'heure).

## Toucher et luminosité

Tactile CST9220/CST9217 en I2C `0x5A` (SDA 8, SCL 7, INT 5, RST 11), via SensorLib `TouchDrvCST92xx` à version épinglée. Axes réglés pour le MADCTL `0x30` de l'écran : X/Y inversés et X en miroir (constat sur cette carte, relevé au grilling de #160) ; à recalibrer si l'orientation change. Les deux pages sont créées au démarrage et basculées par `LV_OBJ_FLAG_HIDDEN`, jamais créées ni détruites au toucher ; le Halo reste au-dessus des deux.

| Geste | Effet |
| --- | --- |
| **tap** (moins de 600 ms) | bascule page état ↔ page Quotas, au relâcher |
| **appui long** (600 ms) | un cran de luminosité, pendant l'appui, une seule fois par appui |
| aucun toucher pendant 30 s sur la page Quotas | retour automatique à la page état (chaque toucher réarme le délai) |

Un relâcher de moins de 60 ms (rapport perdu par le contrôleur) ne coupe pas l'appui en deux. Réglages : `lib/totem_core/gesture.h`.

**Luminosité** : 4 niveaux cycliques du registre `0x51` du CO5300 (`48`, `112`, `176`, `240` ; plancher non nul pour ne jamais simuler un objet éteint ; le plus lumineux par défaut), le plus lumineux repassant au plus faible. Le niveau est gardé en NVS (`Preferences`, espace `totem`, clé `brightness`), écrit à chaque appui long et relu au démarrage. Réglages : `lib/totem_core/brightness_levels.h`. Le bouton PWR n'est jamais utilisé (un appui de 6-8 s éteint l'AXP2101).

**Aucun autre effet** : pas d'acquittement, aucune requête sortante, rien vers l'app. Sans contrôleur tactile détecté (`[touch] CST92xx not found` au moniteur série), le Totem reste sur la page état ; avec un `config.json` en erreur, le tactile n'est pas démarré et l'écran `CONFIG ERROR` reste affiché.

### Checklist visuelle et tactile (carte branchée)

Avec l'app island qui pousse vers le Totem, l'Étendu ouvert sur le Mac à côté :

1. Tap au centre : page Quotas ; nouveau tap : page état. Dix taps d'affilée : dix bascules, aucune ratée ni doublée.
2. Axes : toucher les quatre coins, moniteur série ouvert (`pio device monitor -e totem_c6`). `[touch] down at x,y` donne ≈ `0,0` en haut à gauche, ≈ `479,0` en haut à droite, ≈ `0,479` en bas à gauche, ≈ `479,479` en bas à droite (écran tenu comme l'affichage).
3. Page Quotas, tee statusline activé : pourcentages et couleurs identiques aux jauges de l'Étendu au même instant ; `5 h` et `7 d`.
4. Compte à rebours cohérent avec le `↺ HH:MM` de l'Étendu (heure de reset moins l'heure du Mac, à la minute près), qui diminue d'une minute par minute.
5. Tee statusline désactivé (défaut) : `no quotas`, jamais `0%`.
6. Halo visible sur la page Quotas (orange / vert selon l'état), avec la même respiration.
7. Rester sur la page Quotas sans toucher : retour à la page état après ~30 s. Toucher à 20 s : le délai repart.
8. Appui long : un seul cran de luminosité par appui, même doigt posé plusieurs secondes ; quatre appuis longs font le tour ; le plus faible reste lisible.
9. Débrancher/rebrancher (ou redémarrer) : la luminosité choisie est conservée.
10. App quittée : page Quotas `QUOTAS - DISCONNECTED`, jauges et compte à rebours estompés et figés ; page état comme avant (mascotte grise, Halo éteint).
11. Aucun effet côté Mac pendant les gestes (Sessions, Acquittement, Liseré inchangés).

## Si le Totem reste Déconnecté

- `curl` depuis le Mac échoue : même réseau 2,4 GHz ? isolation client ou réseau invité ? IP changée (relire l'écran) ?
- `curl` depuis le Mac marche mais l'app ne met pas le Totem à jour : suspecter la permission **Réseau local** de l'app island (Réglages Système > Confidentialité et sécurité > Réseau local, macOS 15+), pas le firmware.

## Matériel

SoC RISC-V mono-cœur, 512 Ko de SRAM, **aucune PSRAM**, 16 Mo de flash, Wi-Fi 2,4 GHz. Écran AMOLED 480×480 CO5300 en QSPI, tactile CST9220/CST9217 (I2C 0x5A), PMU AXP2101 (I2C 0x34) qui alimente l'écran. LVGL rend en mode partiel dans deux petits buffers en RAM interne, jamais dans un framebuffer complet. Le code carte est écrit à partir des faits matériels (broches, registres, ordre d'init) relevés sur cette carte lors du grilling de #158 ; aucun code tiers n'est copié.
