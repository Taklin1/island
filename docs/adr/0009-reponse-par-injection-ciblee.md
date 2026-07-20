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
