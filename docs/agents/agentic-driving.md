# Piloter l'app island en test agentique

Conventions vérifiées pour dérouler un FP/HP contre l'app réelle (voir le
skill `agentic-tests` pour le protocole ; ici : les pièges d'outillage).

## Auth de l'API locale : PAS de `Authorization: Bearer`

- **Découverte** : POSTer une fixture avec `Authorization: Bearer <token>`
  renvoie `401` — le réflexe standard échoue silencieusement.
- **Bonne méthode** : le Serveur local n'accepte que le paramètre `?token=`
  ou l'en-tête `X-Island-Token` :
  ```bash
  curl -s -X POST http://127.0.0.1:41414/hooks/claude-code \
    -H "X-Island-Token: $(cat ~/.claude/island-token)" -d "$FIXTURE_JSON"
  ```
- **Preuve** (FP #11, 2026-07-19) : même fixture, `Bearer` → `401`,
  `X-Island-Token` → `200` + Session publiée.
- **Pourquoi** : fiabilité — un 401 sur l'auth ressemble à un token périmé et
  fait perdre du temps de diagnostic à chaque session de test.

## Mode Étendu : hover synthétique via CGEvent

- **Découverte** : le mode Étendu ne s'ouvre qu'au survol réel de l'Island ;
  ni `osascript` (pas de position souris dans System Events) ni `cliclick`
  (non installé) ne permettent de le déclencher pour un screenshot.
- **Bonne méthode** : compiler un mini-outil Swift qui poste un `mouseMoved`
  CGEvent vers le haut-centre de l'écran (l'Island est top-center), attendre
  ~1,5 s, screenshoter, puis renvoyer le curseur ailleurs :
  ```swift
  // mouse_move.swift — usage : ./mouse_move <x> <y>
  import CoreGraphics
  import Foundation
  let args = CommandLine.arguments
  let point = CGPoint(x: Double(args[1])!, y: Double(args[2])!)
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
          mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
  ```
  ```bash
  swiftc -o mouse_move mouse_move.swift
  ./mouse_move 720 15 && sleep 1.5 && screencapture -x expanded.png
  ./mouse_move 720 600   # rendre la main
  ```
- **Preuve** (FP #11, 2026-07-19) : le déplacement déclenche la trace
  `island: expanded on hover: N session card(s)` et le screenshot montre les
  cartes Étendues ; aucune permission Accessibilité demandée pour un simple
  `mouseMoved`.
- **Pourquoi** : justesse — sans ce chemin, le rendu Étendu resterait
  invérifiable en agentique et les FP/HP concluraient « visuel non testé »
  alors qu'un screenshot suffit. Attention : déplacer la souris pendant que
  Loïc travaille est intrusif ; le faire vite et remettre le curseur ailleurs.
