# Firmware du Totem

Firmware du **Totem** (voir `CONTEXT.md` § Totem) : un Waveshare ESP32-C6-Touch-AMOLED-2.16 qui affiche l'**Instantané** poussé par le **Relais** de l'app island sur le réseau local. Afficheur pur : un serveur HTTP entrant, aucune requête sortante, aucun canal vers l'app (ADR-0013, ADR-0014). Le firmware vit dans ce repo pour que le contrat évolue dans une seule PR des deux côtés (ADR-0015).

Cette version affiche du texte brut : Connecté / Déconnecté, état agrégé, compteurs, adresse IP et `island-totem.local`. La mascotte et le Halo arrivent avec #159.

## Organisation

| Chemin | Rôle |
| --- | --- |
| `platformio.ini` | env `totem_c6` (la carte) et env `native` (tests sur le Mac) |
| `lib/totem_core/` | logique pure, sans `Arduino.h` : décodage de l'Instantané, token, fraîcheur (Déconnecté), `config.json`, ordre de validation de `POST /snapshot` |
| `src/` | code carte : alimentation et écran, LVGL, Wi-Fi + mDNS, serveur HTTP, écran texte |
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
  --data-binary @contract/snapshot-nominal.json      # 204, écran CONNECTED / done
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

## Si le Totem reste Déconnecté

- `curl` depuis le Mac échoue : même réseau 2,4 GHz ? isolation client ou réseau invité ? IP changée (relire l'écran) ?
- `curl` depuis le Mac marche mais l'app ne met pas le Totem à jour : suspecter la permission **Réseau local** de l'app island (Réglages Système > Confidentialité et sécurité > Réseau local, macOS 15+), pas le firmware.

## Matériel

SoC RISC-V mono-cœur, 512 Ko de SRAM, **aucune PSRAM**, 16 Mo de flash, Wi-Fi 2,4 GHz. Écran AMOLED 480×480 CO5300 en QSPI, PMU AXP2101 (I2C 0x34) qui alimente l'écran. LVGL rend en mode partiel dans deux petits buffers en RAM interne, jamais dans un framebuffer complet. Le code carte est écrit à partir des faits matériels (broches, registres, ordre d'init) relevés sur cette carte lors du grilling de #158 ; aucun code tiers n'est copié.
