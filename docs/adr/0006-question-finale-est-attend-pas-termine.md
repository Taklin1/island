# Une session qui attend une réponse écrite est « attend » (orange), pas « terminée »

Un tour dont le **dernier message assistant finit sur une question** (`?`) est
classé `waiting` (Liseré orange, glyphe `?`, « attend ») — au même titre qu'une
`AskUserQuestion` ou une demande de permission — **jamais** `ended` (vert,
« terminé »). Le vert/`ended` est réservé aux tours finissant sur un **constat**.
« À toi » n'est donc **pas un état distinct** : c'est une porte d'entrée
supplémentaire dans `waiting`, détectée localement par l'Adaptateur au `Stop`
(dernier texte assistant rogné-à-droite finit par `?`), sans appel LLM
(ADR-0002), en réutilisant le `TranscriptReader` (#7). Défaut si le texte est
absent : `.turnEnded` (on ne crie pas au loup sans signal).

Issu du grill de #34 (Loïc, 2026-07-19).

## Considered Options

- **Un état « à toi » doux et vert, distinct de terminé** (annotation
  `endedKind: .done | .awaitingReply` sur `.ended`) : rejeté. « À toi » signifie
  que l'agent **attend quelque chose de toi** — sémantiquement c'est de
  l'attente, pas du terminé ; lui donner le vert du terminé sous-signale. Une
  question posée en prose et la même question via `AskUserQuestion` doivent se
  ressembler : les deux sont de l'attente.
- **Orange atténué / non-persistant pour la sous-catégorie « question »** (la
  distinguer visuellement de la permission) : **gardé en évolution possible**,
  non retenu en v1 — n'apporte pas de valeur à l'usage aujourd'hui et surcharge
  le vocabulaire visuel. Réversible si le besoin apparaît.
- **L'idle comme signal de classification** : rejeté. L'idle (`Notification`
  ~60 s) est un simple minuteur sur *ton* inactivité au prompt ; il est aveugle
  au « l'agent attend-il ? » et se déclenche à l'identique après un constat ou
  après une question. Il reste un **axe urgence orthogonal** (ravive l'attention
  d'une session déjà classée), jamais un classificateur — cohérent avec le fix
  idle de #31.

## Consequences

- **Mécanisme (détecter puis résoudre)** : l'Adaptateur *détecte* « le dernier
  texte finit sur `?` » au `Stop` et porte ce fait sur l'événement de fin de tour
  (p. ex. `.turnEnded(awaitsReply:)`) ; le **Store** le *résout* en `.waiting`
  (orange) ou `.ended` (vert). La décision vit dans le Store parce que c'est là
  qu'est le gate sous-agents de #31 : un `Stop` avec un sous-agent actif reste
  `running`, et la complétion différée (dernier `SubagentStop`) hérite du même
  choix « question ⇒ attend ». L'état résultant de « à toi » est le `.waiting`
  **existant** — aucun état vert distinct, aucune annotation persistante.
  Émettre `.waitingForUser` directement depuis l'Adaptateur contournerait le gate
  et afficherait orange pendant que les sous-agents tournent : à éviter.
- **Ne pas régresser #31** : la classification stricte des `Notification`
  (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) continue
  d'envoyer `AskUserQuestion` et les permissions en `waiting`/orange — ça marche
  déjà, #34 n'y touche pas.
- **Faux positif assumé** : un `?` rhétorique en fin de constat (« Pas mal,
  non ? ») produit un orange indu. Jugé rare et acceptable — un message finissant
  sur un vrai `?` est presque toujours une vraie question.
- **Bonus quasi-gratuit** : `lastSummary.text` (déjà stocké au `Stop`) porte la
  question, donc le Peek d'un `waiting`-par-question peut l'afficher (« projet ·
  attend : "…?" ») sans ouvrir le terminal.
