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

## Mode Étendu : vérifier la Révélation par la TRACE, pas par un screenshot maintenu

- **Découverte** (épopée #41, ADR-0007 — PÉRIME l'ancienne méthode « hover
  synthétique → screenshot de l'Étendu ») : depuis le passage en `.floating`
  masqué, l'Étendu ne s'ouvre plus au survol d'une barre visible mais par un
  **moniteur souris global `NSEvent`** (Révélation bord-franc). Le panneau se
  déploie **autour** du curseur au bord haut ⇒ aucun `mouseEntered` natif ⇒
  `keepVisible` ne s'arme pas ⇒ l'Étendu **recede en ~300 ms**. Un `mouseMoved`
  CGEvent posté à un point statique NE maintient PAS `isHovering` assez
  longtemps pour un `screencapture` : la fenêtre est presque toujours ratée
  (l'écran capturé montre le bureau, pas le panneau). La trace a aussi été
  **renommée** : `révélation: N session card(s)` (plus `expanded on hover`).
- **Bonne méthode** : vérifier la Révélation par la **trace stdout**, pas par un
  screenshot de l'Étendu maintenu. Compiler un mini-outil Swift qui vise le
  haut-centre du bord (auto-centré sur `NSScreen.main`, y ≈ bord haut) pour
  déclencher, puis lire la trace :
  ```bash
  # reveal_move.swift : CGEvent mouseMoved vers (NSScreen.main.frame.midX, top)
  swiftc -o reveal_move reveal_move.swift && ./reveal_move
  grep "révélation: .* session card" island.log   # preuve que l'Étendu s'est déployé
  ```
  Le **contenu de carte** (titre #32, compte sous-agent #48/Q6) se confirme
  manuellement (vrai trackpad qui repose sur le panneau) ou se considère inchangé
  si l'épopée en cours ne touche pas au rendu des cartes. Le **Peek** (Sprite +
  texte), lui, se capture bien au `screencapture` car il est déclenché par un
  **événement** (POST d'un `Stop` marquant), pas par la souris — fenêtre ~2,5 s.
- **Preuve** (HP épopée #41, 2026-07-20) : `reveal_move` unique → aucune trace,
  screenshot vide (Étendu déjà receded) ; répété avec vrai mouvement → traces
  `révélation: 6 session card(s)` fiables mais screenshot toujours raté ; un
  `Stop` finissant sur `?` → Peek capturé net (pastille Sprite + texte).
- **Pourquoi** : justesse — s'entêter à screenshoter l'Étendu maintenu fait
  conclure à tort « la Révélation ne marche pas » alors que la trace prouve le
  contraire ; c'est la trace qui tranche le mécanisme, le screenshot ne tranche
  que le Peek. Déplacer la souris pendant que Loïc travaille reste intrusif —
  vite, puis rendre le curseur.

## Suite HP : l'orchestrateur la déroule lui-même (ne pas s'entêter sur un sous-agent mort)

- **Découverte** (gate final épopée #41, 2026-07-20) : un sous-agent délégué pour
  dérouler `/agentic-tests HP` s'est mis **idle immédiatement après spawn sans
  exécuter la moindre étape** (aucun process `Island`, port 41414 libre, flag
  `hooksInstallAttempted` jamais posé, repo intact, notifications idle vides).
- **Bonne méthode** : ne pas s'acharner à re-nudger un runner de test délégué qui
  part idle sans rien faire — l'orchestrateur **déroule la suite HP directement**
  (build + lancer `.build/debug/Island` + POST des fixtures + lire les traces).
  C'est plus fiable et le contexte reste maîtrisé.
- **Preuve** : deux relances du sous-agent → deux notifications idle vides ; HP
  entièrement déroulée par l'orchestrateur ensuite (HP-01→04 verts).
- **Pourquoi** : fiabilité — un runner délégué inerte bloque le gate ; l'orchestrateur
  a tout ce qu'il faut pour dérouler HP lui-même, la délégation n'est pas un dû.

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
- **Levée (packaging, 2026-07-19)** : depuis le vrai bundle `island.app`
  (`scripts/package_app.sh`, ad-hoc, installé dans `~/Applications`),
  `register()` réussit — trace `island: login item registered` et entrée BTM
  `com.taklin.island → ~/Applications/island.app` (`sfltool dumpbtm | grep -i
  island`). Tester le login item = lancer le `.app` empaqueté, jamais le binaire
  nu. Voir ADR-0005.

## Comportement des hooks : capturer le fil réel avant de coder une détection

- **Découverte** : une fixture synthétique encode facilement une *croyance*
  fausse sur ce qu'island reçoit vraiment — elle passe son propre test et échoue
  en réel. Deux fixes « à l'aveugle » sont morts ainsi sur la fiabilité d'état :
  le lag du transcript au `Stop` (#39, il faut lire `last_assistant_message`) puis
  le mauvais modèle de Sous-agent (#48 — aucun `Stop`/`SubagentStop` ne porte
  d'`agent_id`, c'est le champ `background_tasks` du `Stop` qui liste les
  Sous-agents vivants ; introuvable sans capture).
- **Bonne méthode** : avant de coder la détection d'une transition d'état pilotée
  par un hook que tu n'as **pas observée**, instrumente le build DEV (throwaway,
  gardé par une variable d'env p.ex. `ISLAND_CAPTURE_48=1`, marqué
  `TEMP-CAPTURE-*`, JAMAIS l'Island live sur 41414) pour logger chaque hook reçu
  + l'état résolu vers un `.jsonl`, fais **capturer le cas réel** (runbook à Loïc
  si le cas exige une vraie session — p.ex. un Sous-agent qui finit seul), puis
  code contre ce ground truth. Retire l'instrumentation avant le commit du fix
  (`grep -rE "TEMP-CAPTURE-*" = 0`). Attention : un log qui interpole un objet
  déjà parsé (`"\(nsArray)"`) peut **déguiser le format du fil** (un tableau JSON
  rendu en plist) — décode le champ brut, ne te fie pas au rendu du log.
- **Preuve** : `~/island-hook-capture-39.jsonl` et `~/island-hook-capture-48.jsonl`
  ont chacune tranché ce que 2 fixtures « raisonnables » avaient faux — dont la
  découverte de `background_tasks` au `Stop` (ADR-0008 amendé), impossible à
  deviner. Le FP réel a confirmé le parsing (trace `×1sub`), pas la fixture.
- **Pourquoi** : justesse — sur le comportement des hooks, une fixture prouve
  seulement que le code fait ce que la fixture affirme, pas ce que Claude Code
  envoie. Seule la capture du fil réel ferme l'écart ; la valider ensuite par un
  FP réel (pas un fixture) est ce qui empêche un repli silencieux de masquer un
  format mal deviné.
