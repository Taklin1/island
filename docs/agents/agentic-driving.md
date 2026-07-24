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

## Vérif HITL sur l'app packagée : relancer le binaire du bundle, pas le Finder

- **Découverte** : `island.app` lancée via le Finder (ou `open`) n'a AUCUNE trace
  lisible — l'app trace par `print` sur stdout (pas os_log), donc
  `log show --predicate 'process == "island"'` revient vide et le stdout part
  dans le vide. Impossible de croiser les observations HITL (clics, états)
  avec les traces.
- **Bonne méthode** : relancer le **binaire du bundle** avec redirection — même
  exécutable, donc l'octroi Accessibilité (par binaire) et le contexte bundle
  sont préservés :
  ```bash
  pkill -f "Applications/island.app" && sleep 1
  nohup ~/Applications/island.app/Contents/MacOS/island > /tmp/island-hitl.log 2>&1 &
  tail -f /tmp/island-hitl.log
  ```
  À la fin de la campagne, quitter par la mascotte menu-bar et relancer
  normalement (Finder ou login item au prochain redémarrage).
- **Preuve** (vérif HITL 0.1.23, 2026-07-20) : lancée Finder → `log show` vide,
  aucun observable ; relancée binaire+redirection → `accessibility permission
  granted`, `card activated: <id> → focus terminal ghostty`, `waiting+msg`…
  toutes les traces qui ont tranché #77 et confirmé le périmètre de #36.
- **Pourquoi** : justesse — sans traces, une vérif HITL ne départage pas « le
  clic n'atteint pas le handler » de « l'action aval échoue en silence » ; la
  seule trace `card activated` scinde cet arbre en deux dès le premier clic.
- **LIMITE (spike #87, 2026-07-21) : cette méthode ne mesure PAS la permission
  Accessibilité.** Lancée par `nohup` depuis un shell, island hérite du
  « responsible process » TCC du **terminal** (Ghostty, qui a l'Accessibilité) :
  `AXIsProcessTrusted()` répond `granted` même après `tccutil reset Accessibility
  com.taklin.island`. Pour toute mesure TCC (trace `accessibility permission`),
  lancer via un **LaunchAgent** — island devient son propre responsible process
  ET la trace reste capturée (`StandardOutPath`) :
  ```bash
  launchctl bootstrap "gui/$(id -u)" <plist>     # RunAtLoad, KeepAlive=false
  launchctl kickstart -k "gui/$(id -u)/<label>"  # relances
  launchctl bootout "gui/$(id -u)/<label>"       # fin de campagne
  ```
  Protocole complet : `docs/spikes/87-certificat-stable-accessibilite.md`.

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

## Schéma des payloads de hooks : lisible en clair dans le binaire Claude Code

- **Découverte** : pas besoin d'une capture live pour connaître la **forme** d'un
  payload de hook — le binaire Claude Code embarque les schémas Zod en clair,
  avec leurs docstrings `.describe()` (champs, types possibles, sémantique).
- **Bonne méthode** : `strings -a ~/.local/share/claude/versions/<version> |
  grep -oE '.{250}<champ>.{250}'` (le binaire est un Mach-O compilé par bun,
  `grep` direct ne marche pas — passer par `strings`). Résoudre `<version>` via
  le symlink `$(readlink $(which claude))`. Chercher le nom du champ JSON (p.ex.
  `background_tasks:`) puis remonter au schéma référencé (p.ex. `_8f=`).
- **Preuve** : triage #79 — le schéma complet d'une entrée `background_tasks`
  (`{ id, type, status, description, command?, agent_type?, server?, tool?,
  name? }`, `type` ∈ « 'shell', 'subagent', 'monitor', 'workflow' » + fallback
  types inconnus) extrait en 3 greps, là où #48 avait exigé une instrumentation
  + un runbook de capture live.
- **Pourquoi** : vitesse + complétude — le schéma donne **tous** les cas
  possibles (types rares ou futurs inclus), qu'une capture live n'échantillonne
  que partiellement. La capture live reste nécessaire pour le **comportement**
  (timing, valeurs effectives, courses — cf. section précédente) ; le binaire
  donne la **forme**. Les deux se complètent, binaire d'abord.

## Instance de test dédiée : ISLAND_PORT (le port fixe 41414 est pris par l'app réelle)

- **Découverte** (FP #36, 2026-07-21) : l'island.app réelle de Loïc tourne en
  permanence et détient le port fixe `41414` — impossible de lancer une
  instance de test (le serveur échoue → l'app se termine), et il est interdit
  de piloter l'app réelle (vieille version + sessions réelles).
- **Bonne méthode** : lancer le binaire debug avec la seam d'environnement
  `ISLAND_PORT` (ajoutée par #36), en tâche de fond suivie par le harness (un
  `nohup … &` dans un shell éphémère se fait moissonner à la fermeture du
  shell) :
  ```bash
  ISLAND_PORT=41436 .build/debug/Island 2>&1 | tee island-fp.log   # run_in_background
  curl -s -X POST http://127.0.0.1:41436/hooks/claude-code -H "X-Island-Token: $(cat ~/.claude/island-token)" -d "$FIXTURE"
  ```
  Le binaire debug a son propre domaine defaults `Island` (l'app packagée vit
  dans `com.taklin.island`) : pré-poser
  `defaults write Island answerFromIslandOnboardingPrompted -bool true` avant
  un parcours sans permission, sinon le premier clic ouvre Réglages Système sur
  l'écran du mainteneur.
- **Pourquoi** : isolation — les fixtures de test n'apparaissent jamais dans
  l'island réelle, et les hooks réels (branchés sur 41414) n'atteignent jamais
  l'instance de test.

## Cliquer une carte en synthétique : NON fiable — passer par un harnais de seam live

- **Découverte** (FP #36, 2026-07-21) : impossible de cliquer une carte/le Peek
  au CGEvent pendant que le mainteneur travaille. Causes empilées, toutes
  vérifiées : un curseur **warpé statique ne maintient pas `isHovering`** (le
  panneau recède ~1-2 s après la Révélation, même curseur posé dessus — même
  racine que le piège « screenshot de l'Étendu » ci-dessus) ; le clic pendant la
  transition Peek→Étendu tombe sur une vue en cours de fondu (non cliquable) ;
  un jiggle d'entretien du hover se fait interrompre par les mouvements réels
  de l'utilisateur ; `mouseEventClickState=1` est nécessaire mais pas
  suffisant ; un clic `System Events` traverse jusqu'à la fenêtre Ghostty
  derrière (le panneau non-activant est invisible au hit-test AX). En prime :
  viser la « plus grande fenêtre » du pid attrape l'overlay du Liseré
  (plein écran, layer 25) — le panneau est la fenêtre **layer 1000** (hôte
  720×450, contenu visible en haut-centre seulement).
- **Bonne méthode** : ne pas s'entêter sur le geste UI. Vérifier la chaîne en
  deux moitiés : (1) la jambe clic→`cardActivated` est couverte par les tests
  unitaires + le garde `FirstMouseTests` + les clics réels des FP précédents ;
  (2) la jambe OS s'exerce par un **harnais de seam live** — un exécutable de
  scratchpad qui linke les objets du package et appelle la seam `.live` de
  production directement, puis re-lit l'état AX en lecture seule :
  ```bash
  swiftc harness.swift -I .build/arm64-apple-macosx/debug/Modules \
    .build/arm64-apple-macosx/debug/IslandFocus.build/*.o \
    .build/arm64-apple-macosx/debug/IslandStore.build/*.o -framework AppKit
  ```
- **Preuve** (FP #36) : 6 stratégies de clic échouées en ~15 min (aucune trace
  `card activated`) ; le harnais a prouvé les deux verdicts en 2 runs —
  `click-to-focus app` (cwd sans fenêtre) et `click-to-focus exactWindow` +
  fenêtre-clé re-lue = cible (Ghostty désactivée avant le run : la bascule est
  réelle).
- **Pourquoi** : fiabilité + politesse — chaque tentative de clic vole le
  curseur du mainteneur ; le harnais de seam prouve le geste AX réel sans
  toucher ni au curseur ni à l'app réelle.

## Machine équipée : capturer l'instance de test sans révéler l'island réelle

- **Découverte** (captures vitrine, 2026-07-22) : depuis la release 0.1.28,
  l'island.app réelle tourne en permanence sur la machine (« machine
  équipée »). Quand une instance de test (`ISLAND_PORT`, section ci-dessus)
  tourne à côté, la **Révélation bord-haut déclenche LES DEUX** : la bande
  (~280 pt centrée au bord haut) est écoutée par chaque instance via son
  moniteur souris global, un hover synthétique qui pince le bord est
  indiscernable d'un vrai geste → le panneau de l'island réelle passe devant,
  capte le hover, et la capture montre les **données privées des Sessions
  réelles**, pas l'instance de test.
- **Bonne méthode** : ne jamais warper le curseur au bord haut-centre. Pour
  capturer l'Étendu de l'instance de test : déclencher un **Peek** (POST d'un
  événement marquant sur le port de test — événementiel et port-isolé, l'island
  réelle reste Masquée), puis promouvoir Peek→Étendu en survolant le panneau
  **par en dessous** (rester sous les ~2 px du bord haut ET hors de la bande
  centrale de 280 pt) : le hover tracking s'arme en remontant dans le panneau
  depuis le bas. Pour la barre des menus (auto-masquée) : parquer le curseur au
  bord haut-**DROITE**, hors bande — elle s'affiche sans révéler aucun island.
- **Preuve** (2026-07-22, captures de la vitrine) : reveal bord-haut → double
  island, panneau réel devant ; méthode Peek port-isolé + hover par en
  dessous → Étendu de la seule instance de test, captures propres.
- **Pourquoi** : sécurité + justesse — une capture destinée à un README/artefact
  public qui montre les Sessions réelles fuit des données privées ; et le
  panneau réel par-dessus fait conclure à tort que l'instance de test ne
  fonctionne pas.

## Captures du panneau : des jauges grises ≠ seuils cassés (vibrancy)

- **Découverte** (issue #116, 2026-07-22) : sur une capture du panneau révélé
  **sans interaction préalable**, les jauges de Quotas restent grises
  désaturées alors que les seuils devraient les colorer (constaté : remplissage
  gris neutre malgré 63 %, donc jaune attendu). Les couleurs n'apparaissent
  qu'après un clic dans le panneau. Cause suspectée (mécanisme macOS, pas nos
  seuils) : le panneau est une `nonactivatingPanel` jamais fenêtre key →
  `controlActiveState` inactif → la vibrancy du matériau désature le `tint`
  des contrôles système (`ProgressView`).
- **Bonne méthode** : en vérif visuelle (FP, captures), ne PAS conclure d'une
  jauge grise que la logique de seuil est cassée — cliquer dans le panneau (ou
  vérifier la valeur/le libellé) pour départager le rendu du calcul. Pour toute
  nouvelle UI du panneau, préférer des `Color` explicites (formes remplies)
  aux tints de contrôles système, insensibles à la vibrancy — c'est l'exigence
  de #116.
- **Preuve** : captures live #116 — grise avant clic, colorée après clic, même
  valeur ; les tests unitaires de seuil passent (le calcul est bon, c'est le
  rendu).
- **Pourquoi** : justesse — sans cette note, chaque campagne de captures
  re-diagnostique un faux bug de seuils, et une preuve visuelle « avant/après »
  peut être invalidée par un simple clic qui change le rendu.

## Moniteurs globaux sourds aux CGEvents synthétiques (harnais sandboxé) : piloter par le hover natif

- **Découverte** (FP #141, 2026-07-24) : depuis le harnais d'agent sandboxé,
  les `mouseMoved` synthétiques (CGEvent, taps `cghidEventTap` ET
  `cgSessionEventTap`, source `hidSystemState`, en rafale « glide » comme en
  événement isolé) **déplacent réellement le curseur** mais n'atteignent
  **aucun** moniteur global `NSEvent` — ni celui de l'instance de test, ni un
  observateur diagnostic dédié (`AXIsProcessTrusted=true`, moniteur installé,
  zéro événement reçu). La chorégraphie appui-en-bande du FP #130 est donc
  **non rejouable** depuis ce contexte : aucune Révélation bord-franc, sans
  aucune erreur visible.
- **Bonne méthode** : ne pas conclure « la Révélation est cassée » — piloter
  par le **hover natif**, qui ne dépend pas des moniteurs (les tracking areas
  sont nourries par la position réelle du curseur, qui bouge bel et bien) :
  POST d'un événement marquant (Peek port-isolé) → « glide » du curseur **par
  en dessous** jusque dans le panneau du Peek → promotion `révélation
  (survol)` → traces. Le chemin géométrique moniteur (`mouseMoved` →
  `shouldRecede`) se prouve alors par ses **tests unitaires** (qui appellent
  `mouseMoved` directement) + la trace de dérivation runtime, pas par le geste.
- **Preuve** : FP #141 — 2 chorégraphies bord-franc muettes (0 trace),
  observateur diagnostic muet ; puis Peek + glide par en dessous →
  `révélation (survol): 5 session card(s)`, `étendu: hauteur panneau 225 →
  bande de maintien 305`, repli unique au hover-off. Cursor rendu par
  `CGWarpMouseCursorPosition` (aucun événement).
- **Pourquoi** : justesse + vitesse — sans cette note, chaque campagne re-brûle
  du temps à marteler des CGEvents que personne ne recevra, et peut conclure à
  tort à un rouge sur le mécanisme de Révélation.

## FP souris (dwell/cooldown #130) : ré-armer LOIN des panneaux, et pré-armer chaque run

- **Découverte** (FP #130, 2026-07-23) : deux artefacts de chorégraphie CGEvent
  qui miment un faux rouge sur la re-Révélation :
  1. un `mouseMoved` posté **sous le bord haut mais au-dessus de la zone d'un
     panneau d'island déployé** (ex. `(midX, top-300)` pendant que la vraie
     island est ouverte) **n'atteint pas toujours le moniteur global** de
     l'instance de test → le ré-armement (« quitter le bord ») n'est jamais vu ;
  2. un run **hérite l'état désarmé** du run précédent : la restauration du
     curseur par `CGWarpMouseCursorPosition` n'émet **aucun** événement, donc
     après le repli final d'un run, aucun « quitter le bord » n'est observé
     avant le run suivant.
- **Bonne méthode** : dans toute chorégraphie qui exerce dwell/cooldown,
  (a) poster le point de ré-armement **loin de tout panneau** (ex.
  `(150, top-450)`) ; (b) commencer chaque run par ce même mouvement de
  **pré-armement** ; (c) un seul événement d'appui en bande suffit ensuite —
  le dwell est armé par l'événement et la Révélation vient de la task, inutile
  de marteler des moves identiques.
- **Preuve** : FP #130 — ré-armement à `(720,599)` jamais tracé (panneau réel
  déployé au-dessus) puis run suivant parti `armed=false` ; avec pré-armement à
  `(150,449)` : P1→P5 verts en un run (2 révélations, 1 repli, scrubbing muet).
- **Pourquoi** : justesse — sans ces deux gestes, on conclut à tort que le
  cooldown/ré-armement est cassé alors que c'est la chorégraphie qui n'a
  jamais montré « repartir du bord » au moniteur.
