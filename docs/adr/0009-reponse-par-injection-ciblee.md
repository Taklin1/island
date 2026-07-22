# Répondre à un agent bloqué par injection de frappes ciblée

Pour répondre à une Session « en attente » (question AskUserQuestion ou prompt de permission) depuis l'Island, on injecte la frappe correspondant à l'option choisie dans le terminal de la Session via l'API Accessibilité, **uniquement si la fenêtre/onglet Ghostty de cette Session est identifiée avec certitude** (cwd exposé par l'Accessibilité, correspondance unique — cf. spike #25). Sinon on dégrade en simple Click-to-focus. Un seul mécanisme couvre les deux cas, parce qu'un prompt de permission comme une question sont des menus numérotés au clavier dans Ghostty.

## Considered Options

- **Réponse HTTP bloquante du hook** (mécanisme d'agent-island : le hook PermissionRequest bloque sa réponse jusqu'au clic dans l'Island) : rejeté comme mécanisme principal — il ne couvre que les permissions, pas les questions, et Loïc tourne en `defaultMode: auto` où les permissions allow/deny sont rares (seul le classificateur en escalade quelques-unes). L'injection couvrant déjà les deux cas, ce second mécanisme n'apporte rien.
- **Injecter dans la fenêtre au premier plan** (sans ciblage) : rejeté — avec plusieurs Sessions ouvertes, la réponse peut partir dans le mauvais terminal ; c'est le risque le plus grave de la feature, d'où la garde « cible sûre ou rien ».

## Consequences

- Dépendance à la permission Accessibilité (onboarding à prévoir) ; Ghostty n'a pas d'API de scripting, d'où l'Accessibilité plutôt qu'AppleScript.
- Le ciblage de la fenêtre/onglet exact (au-delà de l'activation d'app de la v1, ADR hors périmètre jusqu'ici) devient nécessaire — c'est le point dur technique, **dérisqué par le spike #25** (ci-dessous).
- Sans réponse de l'utilisateur, la Session reste « en attente » (Liseré orange persistant) ; l'Island ne décide jamais seule (le prompt du terminal reste le filet de sécurité). Cohérent avec la sémantique d'Acquittement de la v1.

## Spike #25 — dérisquage (validé 2026-07-19)

Investigation détaillée : `docs/spikes/25-ciblage-ghostty-et-format-askuserquestion.md`.

- **Ciblage (comment on cible)** : chaque fenêtre Ghostty expose son cwd via l'attribut Accessibilité `AXDocument` (`file://<cwd>/`) — signal fiable, contrairement au titre que Claude Code écrase avec le texte de la tâche. **Cible certaine = exactement UNE fenêtre (toutes instances Ghostty confondues) dont l'`AXDocument` égale `Session.cwd`.** 0 ou ≥ 2 → cible incertaine → dégrade en Click-to-focus. Démontré sur un cas réel 8 fenêtres / 3 projets.
- **Format (quoi on lit)** : le tool-call `AskUserQuestion` est lisible tel quel dans le JSONL — `input.questions[]`, chaque question portant `question`, `header`, `multiSelect`, `options[]` **ordonnées** (`{label, description}`) ; l'ordre du tableau est le mapping option → touche. Pas d'options extractibles → dégrade en focus.
- **Permissions** : un prompt de permission escaladé n'apparaît **pas** comme `tool_use` dans le transcript → sa source d'options n'est pas le JSONL, à traiter en #29.
- **Contrainte de sûreté (test)** : la faisabilité d'injection réelle ne se prouve **jamais** en pilotant au clavier l'instance Ghostty vivante (un test l'a fait fermer toutes les fenêtres de Loïc) — uniquement sur `island.app` packagé contre une cible jetable. Cf. `docs/agents/agentic-driving.md`.

## Résolution #29 — prompts de permission escaladés (2026-07-20)

Le spike #25 avait **reporté à #29** la source des options d'un prompt de permission escaladé (auto-mode). L'implémentation de #29 tranche : **il n'existe pas de source sûre d'options de permission**, donc **aucune injection n'est livrée pour les permissions** ; on se limite à les **rendre lisibles** dans l'Island.

- **Pas dans le JSONL** : un prompt de permission n'apparaît pas comme `tool_use` dans le transcript (spike #25) — rien à extraire là.
- **Le type de notification ne distingue pas** permission et question : `notification_type == "permission_prompt"` couvre **aussi** l'affichage d'une `AskUserQuestion` (vérifié en test). On ne peut donc pas « gater » l'extraction sur le type.
- **Menu fixe reconstruit côté Island : rejeté.** Toute la sûreté de l'Injection repose sur l'**ordre verbatim** des options (l'index EST la touche), garanti par le transcript pour une question. Un menu de permission (allow / allow-always / deny) **varie** selon l'outil (nombre et ordre d'options) ; injecter un index **deviné** frapperait potentiellement la mauvaise option d'une **décision de sécurité persistante** (« allow-always ») — exactement ce qu'interdisent US7 et « aucune décision automatique ». La garde de ciblage (#27) ne protège que la **fenêtre**, jamais le **choix**.
- **Comportement sûr, émergent et piloté par le contenu** : une carte « en attente » affiche des boutons **si et seulement si** une `AskUserQuestion` vivante est extractible du transcript ; un vrai prompt de permission n'en a aucune → `question == nil` → **dégrade en Click-to-focus**, jamais de bouton bidon, jamais d'auto-sélection. La dégradation tient même transcript **lisible** (le `tool_use` en attente est l'outil gaté, pas une question), pas seulement sur échec de lecture.
- **Ce que #29 livre** : le `message` humain porté par la Notification (« Claude needs your permission to use Bash ») est **surfacé** sur la carte en attente **sans boutons** (champ `Session.waitingMessage`, affichage seul), afin que la permission ait une **présence** dans l'Island (US1/US6) sans quitter le terminal. Aucune frappe, aucune décision : le clic dégrade en Click-to-focus comme n'importe quelle carte. La moitié « réponse » (injection des options de permission) reste **reportée** faute de source sûre.

## Résolution #77 — la source de la question est le payload `PreToolUse`, pas le transcript (2026-07-20)

La vérification HITL de la v0.1.23 a montré qu'**aucun bouton ne s'affichait jamais** pour une vraie question : le constat « Format (quoi on lit) » du spike #25 était **incomplet sur la disponibilité temporelle**. Le tool-call `AskUserQuestion` est bien lisible dans le JSONL, mais Claude Code ne l'y écrit **qu'au moment où la question est répondue** (`tool_use` + `tool_result` sur des lignes adjacentes) : pendant toute l'attente, le transcript ne contient **aucun** `tool_use` en suspens. « Le dernier `AskUserQuestion` sans `tool_result` » est un état qui **n'existe jamais sur disque** — l'extraction de #26 renvoyait toujours `nil` (ses FP passaient sur des fixtures encodant cet état imaginaire, le piège documenté dans `docs/agents/agentic-driving.md`).

**Nouvelle source, prouvée par capture réelle** (`docs/spikes/77-capture-pretooluse-askuserquestion.md`, discipline capture-first) : le hook **`PreToolUse` de l'outil `AskUserQuestion`** porte dans son `tool_input` le tableau `questions[]` **verbatim et ordonné** (`question`, `header`, `multiSelect`, `options[]` `{label, description}`), **avant** l'affichage de la question. L'ordre du tableau reste le mapping option → touche : l'invariant de sûreté de cet ADR (jamais d'index deviné) est préservé à l'identique, seule la **source** change.

- **Fil observé** : `PreToolUse(AskUserQuestion)` (avec les options) → `Notification` `permission_prompt` (sans options — son type ne distingue toujours pas question et permission, cf. Résolution #29) → réponse de l'utilisateur → `PostToolUse` du même outil (mêmes `questions[]` + `answers`).
- **Mécanique** : l'adaptateur (toujours **sans état**) parse le `tool_input` du `PreToolUse` et pose la question sur l'événement générique ; le store la **stash** sur la Session (`Session.questionStash`, jamais affichée), la **promeut** en `pendingQuestion` à l'entrée « en attente » (l'invariant « boutons visibles ⟺ Session en attente » tient par construction : la promotion est le seul point d'affichage), et l'invalide partout où `pendingQuestion` l'est déjà, plus au `PostToolUse` du même outil (question résolue au terminal). La logique `waitingMessage` de #29 (message ssi `question == nil`) est inchangée.
- **Chemin transcript supprimé sans fallback** : il ne peut par construction rien récupérer pendant l'attente. Les gardes défensives (une seule question, options non vides, trim) ont **migré** sur le décodage du payload.
- **Nouvelle garde `multiSelect`** : `multiSelect == true` → **dégrade** (pas de boutons) — un sélecteur multiple n'est pas un menu à une touche, un index injecté n'y répondrait pas. `nil`/`false` → OK.
- **Périmètre inchangé** : les permissions restent affichage seul (Résolution #29) — leur `PreToolUse` est celui de l'outil gaté, sans `questions[]`, donc aucun stash et aucune promotion : la dégradation reste pilotée par le contenu.

## Résolution #81 — livraison vérifiée au pid, comportement onglets acté (2026-07-20)

Le gate HITL de #77 a montré que la frappe injectée **n'arrivait jamais** au terminal
alors que `inject` rendait `true` (« en cours » menteur). Deux causes actées, une
capture versionnée (`docs/spikes/81-capture-ax-fenetres-onglets-ghostty.md`).

- **Cause racine de la perte** : le post `.cghidEventTap` suit le **key focus
  global**, que le clic sur le panneau island (NSPanel non-activant) peut retenir
  sans activer l'app — la frappe mourait dans le panneau ; `app.activate()` n'est
  pas synchrone et **aucune API ne permet de vérifier** « le key focus est revenu
  au terminal ». Le routage global est donc remplacé, pas fiabilisé.
- **Mécanisme retenu** : après le verdict d'unicité (inchangé), `AXRaise` +
  `activate`, puis **vérification positive re-lue à l'instant du post** (attente
  bornée ~10 × 50 ms) : instance Ghostty **active**, sa fenêtre-clé (`AXFocusedWindow`,
  l'onglet visible) expose `AXDocument == Session.cwd`, et son titre n'est **pas un
  chemin nu**. Alors seulement, `CGEvent.postToPid(pid Ghostty)` — la frappe entre
  dans la file de la seule app vérifiée : **la fuite vers une autre app est impossible
  par construction** (l'inverse du `.cghidEventTap`, qui livrait « à qui a le focus »).
  `inject` ne rend `.injected` — et la carte ne passe « en cours » — **que si la
  frappe a été postée vers cette cible vérifiée** : le feedback est véridique
  (`.uncertainTarget` / `.deliveryUnverified` → dégrade en Click-to-focus, tracé).
- **Comportement onglets/Spaces (capture #81)** : `AXWindows` n'expose que le Space
  courant ; un onglet d'arrière-plan n'a **ni** `AXWindow` propre **ni** `AXTabGroup`
  — la fenêtre à onglets est UNE `AXWindow` dont `AXDocument`/`AXTitle` suivent
  l'onglet visible ; une fenêtre non-key peut être illisible. Le verdict « certain »
  signifie donc « **l'onglet visible est au cwd de la Session** », rien de plus. Deux
  gardes renforcent « cible certaine ou rien » : **≥ 2 Sessions vivantes au même cwd →
  dégrade** (l'Island sait ce que l'AX ne voit pas) ; **titre = chemin nu → dégrade**
  (signature d'un shell sans Session). Un tap pendant la fenêtre de vérification est
  ignoré (anti double-frappe). **Résiduel acté** : un terminal caché au même cwd
  qu'une unique Session (shell nu à titre non-chemin, vieille session silencieuse)
  reste indétectable — le prompt du terminal reste le filet de sécurité.
- **Répondre « depuis ailleurs »** : cible non visible → verdict incertain → aucune
  frappe, dégrade en focus **au niveau app** — qui peut fronter une autre fenêtre
  Ghostty que celle de la Session (constat HITL). Le focus de la bonne *fenêtre*
  est le périmètre de **#36**, qui réutilisera la même énumération.
- **Séquence TUI validée** (gate HITL, 2 livraisons réelles) : « N » + Return
  sélectionne et **soumet** l'option N d'une vraie `AskUserQuestion` ; aucun Return
  orphelin observé. Preuve : les clics hors-fenêtre tracent `uncertainTarget` sans
  aucune frappe nulle part ; les clics sur la fenêtre visible livrent — la réponse
  du mainteneur au point HITL est elle-même arrivée par la chaîne corrigée.
