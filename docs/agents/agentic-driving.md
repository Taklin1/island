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

## Injection de frappe : JAMAIS sur l'instance Ghostty vivante

- **Découverte** : pour tester la faisabilité de l'Injection (epic #22), piloter
  au clavier l'instance Ghostty **réelle** — `CGEvent` clavier, `Cmd+N`/`Cmd+W`,
  `AXRaise` + frappe postée — a **fermé TOUTES les fenêtres Ghostty de Loïc**
  (comptage `AXWindows` passé de 8 à 0), même avec une garde par titre de fenêtre.
  Les raccourcis synthétiques et l'activation cross-instance ne visent pas la
  fenêtre attendue : la frappe part dans la mauvaise cible, `Cmd+W` ferme la
  mauvaise fenêtre.
- **Bonne méthode** : ne **jamais** poster d'événement clavier/fenêtre synthétique
  vers l'instance qui héberge les vraies Sessions. La faisabilité se dérisque en
  deux temps, sans jamais rien poster sur l'instance vivante :
  1. **Lecture seule** (sûr, aucune permission d'écriture) : `AXIsProcessTrusted()`,
     puis énumérer `AXWindows` de **toutes** les instances du bundle et lire
     `AXDocument` (= `file://<cwd>/`) par fenêtre pour le ciblage + la gate
     d'unicité. Aucun `CGEvent`, aucun `AXRaise`, aucun `activate`.
  2. **Injection réelle** : seulement sur `island.app` packagé, contre une cible
     **jetable dédiée**, jamais l'instance de travail. `open -n Ghostty.app` ne
     fournit **pas** une cible isolée fiable (Ghostty est mono-instance :
     `-n` déclenche la restauration de fenêtres et l'activation cross-instance
     ne fronte pas la fenêtre → la frappe fuit ailleurs).
- **Preuve** (spike #25, 2026-07-19) : `inject_selftest 3488` (activate + `Cmd+N`
  + frappe + `Cmd+W`) → `ax_target list` : `windows=0` ; Loïc : « toutes les pages
  Ghostty ont sauté ». À l'inverse, la lecture seule `AXDocument` par fenêtre
  (gate d'unicité : island=1 → certain, akutia=4/hedgencia=3 → dégrade) a
  parfaitement fonctionné **sans rien poster**.
- **Pourquoi** : sécurité — l'instance Ghostty porte le travail réel de Loïc ;
  un événement clavier/fenêtre mal ciblé détruit ses Sessions sans retour arrière.
  C'est plus grave que le curseur intrusif de la section précédente : ici on
  ferme des fenêtres. Règle absolue tant que l'Injection n'est pas exercée par
  `island.app` sur sa propre cible.

## Fichiers de config réels : backup + restauration byte-exacte

- **Découverte** : un FP qui exerce l'installeur (#6) ou le tee statusline (#9)
  écrit dans les VRAIS `~/.claude/settings.json` / `statusline-command.sh` de
  Loïc. Restaurer aveuglément sur la baseline de début de campagne écrase toute
  modification que Loïc fait EN parallèle (la campagne HP a vu son `"model"`
  passer de `fable` à `opus` en plein run).
- **Bonne méthode** : backup horodaté + `shasum -a 256` AVANT toute écriture ;
  à la fin, restaurer sur le **dernier état pré-intervention** (re-lu juste avant
  ta modif), pas sur la baseline ; vérifier par `cmp -s`. Poser
  `defaults write Island hooksInstallAttempted -bool true` avant de lancer l'app
  empêche l'auto-installation de toucher `settings.json` quand tu ne testes pas
  l'installeur lui-même (`defaults delete Island` en fin de campagne).
- **Preuve** (HP 2026-07-19) : diff détecté sur `settings.json`, changement de
  Loïc préservé, `cmp` final vert ; smoke post-sprites lancé sous ce flag →
  `settings.json` byte-identique au backup.
- **Pourquoi** : sécurité — c'est la config vivante de Loïc, une restauration
  naïve détruit son travail sans trace.

## Port 41414 : sérialiser les FP d'une même vague

- **Découverte** : le Serveur local bind un port FIXE (41414). Plusieurs FP
  d'agents parallèles qui lancent chacun l'app entrent en collision sur ce port.
- **Bonne méthode** : un seul FP tient le port à la fois — `pkill -f
  ".build/debug/Island"` avant de lancer le tien, ou `lsof -nP -iTCP:41414
  -sTCP:LISTEN` pour voir qui l'occupe et attendre. En orchestration, la flotte
  se sérialise d'elle-même (un agent libère le port pour le suivant).
- **Preuve** (vague 3, 2026-07-19) : FP #9 « sérialisé derrière le FP d'une
  autre sous-issue qui tenait le port », puis vert une fois le port libre.
- **Pourquoi** : fiabilité — un FP qui échoue à bind conclut à tort « l'app ne
  démarre pas » alors que c'est juste une collision de port.

## Login item : SMAppService exige un bundle .app

- **Découverte** : `SMAppService.register()` renvoie `Invalid argument` depuis
  le binaire SwiftPM nu (`.build/debug/Island`) — normal, pas un bug.
- **Bonne méthode** : ne pas conclure à l'échec ; le login item ne se teste que
  depuis un vrai bundle `.app`. En FP, tracer le comportement et le marquer
  comme observation non bloquante.
- **Preuve** (FP #6 + HP, 2026-07-19) : trace `registration unavailable:
  Invalid argument` sur le binaire nu, code par ailleurs correct.
- **Pourquoi** : justesse — sans cette note, chaque campagne re-signale un faux
  échec du login item.
