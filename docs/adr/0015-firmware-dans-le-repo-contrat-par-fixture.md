# Firmware du Totem dans ce repo (`firmware/`), contrat vérifié par fixture partagée

Le firmware (C++/PlatformIO/LVGL, non Swift) vit dans `firmware/` de ce repo, comme `web-app/`, pour que le schéma de l'Instantané évolue dans une seule PR des deux côtés. Le contrat est une fixture JSON versionnée dans `firmware/contract/` : côté app, `swift test` vérifie que le Relais l'encode à l'identique ; côté firmware, `pio run` et `pio test` (décodage de la même fixture) doivent être verts en local. La CI de release (ADR-0010) ne builde ni ne teste le firmware. Issu du grill de #154 (Loïc, 2026-09-07).

## Considered Options

- **Repo séparé `island-firmware`** : rejeté. Contrat dupliqué ou publié, deux repos à synchroniser à chaque champ ajouté ; usage perso non distribué, aucun bénéfice à la séparation.

## Consequences

- La règle « un dev est vert quand `swift build` et `swift test` passent » s'étend : une PR touchant `firmware/` est verte quand `pio run`/`pio test` passent aussi en local.
- Le versioning de l'app (0.x.y, CHANGELOG) couvre le firmware ; pas de version firmware séparée en v1.
