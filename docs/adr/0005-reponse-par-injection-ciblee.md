# Répondre à un agent bloqué par injection de frappes ciblée

Pour répondre à une Session « en attente » (question AskUserQuestion ou prompt de permission) depuis l'Island, on injecte la frappe correspondant à l'option choisie dans le terminal de la Session via l'API Accessibilité, **uniquement si la fenêtre/onglet Ghostty de cette Session est identifiée avec certitude** (titre/cwd). Sinon on dégrade en simple Click-to-focus. Un seul mécanisme couvre les deux cas, parce qu'un prompt de permission comme une question sont des menus numérotés au clavier dans Ghostty.

## Considered Options

- **Réponse HTTP bloquante du hook** (mécanisme d'agent-island : le hook PermissionRequest bloque sa réponse jusqu'au clic dans l'Island) : rejeté comme mécanisme principal — il ne couvre que les permissions, pas les questions, et Loïc tourne en `defaultMode: auto` où les permissions allow/deny sont rares (seul le classificateur en escalade quelques-unes). L'injection couvrant déjà les deux cas, ce second mécanisme n'apporte rien.
- **Injecter dans la fenêtre au premier plan** (sans ciblage) : rejeté — avec plusieurs Sessions ouvertes, la réponse peut partir dans le mauvais terminal ; c'est le risque le plus grave de la feature, d'où la garde « cible sûre ou rien ».

## Consequences

- Dépendance à la permission Accessibilité (onboarding à prévoir) ; Ghostty n'a pas d'API de scripting, d'où l'Accessibilité plutôt qu'AppleScript.
- Le ciblage de la fenêtre/onglet exact (au-delà de l'activation d'app de la v1, ADR hors périmètre jusqu'ici) devient nécessaire — c'est le point dur technique.
- Sans réponse de l'utilisateur, la Session reste « en attente » (Liseré orange persistant) ; l'Island ne décide jamais seule (le prompt du terminal reste le filet de sécurité). Cohérent avec la sémantique d'Acquittement de la v1.
