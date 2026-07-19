# island

App macOS native (Swift/SwiftUI) : une « Dynamic Island » flottante qui suit les sessions Claude Code et rattrape l'attention quand un agent a fini ou attend une réponse. Voir `CONTEXT.md` (vocabulaire) et `docs/adr/` (décisions).

## Prérequis

- macOS 14+ (testé sur MacBook Air M1, sans encoche : l'Island est flottante).
- Swift 6+ (les Command Line Tools suffisent — DynamicNotchKit est vendoré patché dans `Vendor/`, voir plus bas).

## Lancement

```sh
swift run Island
```

Au premier lancement, l'app :

- génère le token d'authentification dans `~/.claude/island-token` (permissions 0600) ;
- démarre le Serveur local sur `http://127.0.0.1:41414` (loopback uniquement) ;
- affiche l'Island Compacte en haut-centre de l'écran (panneau non-activant : jamais de vol de focus).

Pour une version optimisée : `swift build -c release` puis `.build/release/Island`.

## Brancher Claude Code (hook manuel, tranche #4)

Dans cette tranche, le hook `Stop` se colle à la main dans `~/.claude/settings.json` (l'installation automatique viendra plus tard). Ajouter dans l'objet `"hooks"` :

```json
"Stop": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "curl -s --max-time 2 -X POST \"http://127.0.0.1:41414/hooks/claude-code?token=$(cat ~/.claude/island-token)\" -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true",
        "timeout": 5
      }
    ]
  }
]
```

Propriétés du hook :

- `curl --max-time 2` + `|| true` : échec silencieux, Claude Code n'est **jamais** bloqué ni ralenti si l'app ne tourne pas (US 18).
- Le payload du hook (stdin) est forwardé tel quel ; l'app ignore `SubagentStop` et tout payload illisible.
- Requête sans token valide → 401.

Démo : lancer l'app, finir un tour Claude Code dans le terminal → Peek « `<projet>` ✓ terminé » pendant ~2,5 s, puis retour au Compact.

## Tests

```sh
swift test
```

Les tests suivent les seams du PRD (#3) : on POSTe des fixtures JSON de hooks au Serveur local et on asserte l'état des Sessions publié — jamais l'implémentation interne. Le rendu SwiftUI se vérifie visuellement.

## Vendor/DynamicNotchKit

Copie vendorée de [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 1.1.0 (MIT, ADR-0003), avec un micro-patch : les macros SwiftUI (`@Entry`, `#Preview`) ne compilent pas avec les seuls Command Line Tools (plugins de macros absents sans Xcode). Le patch remplace les `@Entry` par des `EnvironmentKey` explicites et retire les `#Preview` — comportement identique à l'upstream. Dès qu'un Xcode complet est installé, on peut revenir à la dépendance URL dans `Package.swift`.
