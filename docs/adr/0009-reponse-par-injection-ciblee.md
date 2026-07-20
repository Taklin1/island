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
