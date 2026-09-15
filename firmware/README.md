# Firmware du Totem

Firmware du **Totem** (voir `CONTEXT.md` § Totem) : un Waveshare ESP32-C6-Touch-AMOLED-2.16 qui affiche l'**Instantané** poussé par le **Relais** de l'app island sur le réseau local. Afficheur pur : un serveur HTTP entrant, aucune requête sortante, aucun canal vers l'app (ADR-0013, ADR-0014). Le firmware vit dans ce repo pour que le contrat évolue dans une seule PR des deux côtés (ADR-0015).

Cette version affiche la **page état** (#159) : la mascotte pixel-art animée selon l'état agrégé, les compteurs par état, Connecté / Déconnecté, l'adresse IP et `island-totem.local`, entourés du **Halo**. La page Quotas et le tactile arrivent avec #160.

## Organisation

| Chemin | Rôle |
| --- | --- |
| `platformio.ini` | env `totem_c6` (la carte) et env `native` (tests sur le Mac) |
| `lib/totem_core/` | logique pure, sans `Arduino.h` : décodage de l'Instantané, token, fraîcheur (Déconnecté), `config.json`, ordre de validation de `POST /snapshot`, modèle de vue de la page état, Halo, palette grise |
| `src/` | code carte : alimentation et écran, LVGL, Wi-Fi + mDNS, serveur HTTP, page état (`src/ui/`) |
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

Le toucher n'acquitte rien (ADR-0013) ; cette version n'en fait rien du tout.

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

## Si le Totem reste Déconnecté

- `curl` depuis le Mac échoue : même réseau 2,4 GHz ? isolation client ou réseau invité ? IP changée (relire l'écran) ?
- `curl` depuis le Mac marche mais l'app ne met pas le Totem à jour : suspecter la permission **Réseau local** de l'app island (Réglages Système > Confidentialité et sécurité > Réseau local, macOS 15+), pas le firmware.

## Matériel

SoC RISC-V mono-cœur, 512 Ko de SRAM, **aucune PSRAM**, 16 Mo de flash, Wi-Fi 2,4 GHz. Écran AMOLED 480×480 CO5300 en QSPI, PMU AXP2101 (I2C 0x34) qui alimente l'écran. LVGL rend en mode partiel dans deux petits buffers en RAM interne, jamais dans un framebuffer complet. Le code carte est écrit à partir des faits matériels (broches, registres, ordre d'init) relevés sur cette carte lors du grilling de #158 ; aucun code tiers n'est copié.
