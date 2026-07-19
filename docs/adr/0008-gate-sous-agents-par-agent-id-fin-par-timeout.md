# Le gate Sous-agents suit les `agent_id` d'une Session ; la fin se détecte par timeout d'inactivité

Une Session reste **« en cours »** (jamais « terminée ») tant qu'au moins un
**Sous-agent** tourne. Un Sous-agent est un acteur secondaire sous le **même
`session_id`** que l'agent principal, distingué par un **`agent_id`** propre
(p. ex. l'outil `Agent`) — il ne crée ni Session ni carte (CONTEXT.md). Le gate
est alimenté par les hooks qu'island **reçoit déjà** :

- **Appartenance** : tout hook portant un `agent_id` révèle un Sous-agent actif
  → on tient un **ensemble d'`agent_id` actifs** par Session (indépendant du nom
  d'outil de spawn — on ne se lie pas à `Agent`/`Task`).
- **Fin** : **timeout d'inactivité** — un `agent_id` sort de l'ensemble après
  ~60-90 s sans hook le portant (cadence alignée sur l'idle). Auto-cicatrisant :
  la Session ne reste **jamais** coincée « en cours ».
- **Résolution** : tant que l'ensemble est non vide, un `Stop` finissant sur un
  **constat** garde la Session `running` ; le vert (« terminé ») n'est acté qu'au
  départ du dernier Sous-agent. Une **question l'emporte** (orange immédiat,
  corrige ADR-0006) : le gate ne vise que le **vert**.
- **Identité** : un **compte discret** des Sous-agents sur la carte Étendue ; pas
  de Sprite/carte/acquittement par Sous-agent.

Issu du grill de #48 (Loïc, 2026-07-19), sur vérité terrain (capture des hooks
réellement reçus par island).

## Considered Options

- **Gate via `SubagentStart`/`SubagentStop`** (plan initial de #31) : rejeté —
  ces hooks **ne sont pas installés** (`HookInstaller` n'en pose que 7) et le
  Sous-agent réel (`Agent`) ne les émet pas ; le compteur de #31 restait donc
  toujours 0, gate mort en prod (le bug exposé par le FP de #39).
- **Gate via `PreToolUse`/`PostToolUse(Task)`** : rejeté — l'outil réel est
  `Agent`, pas `Task` (fausse piste vérifiée) ; et le `PostToolUse` du spawn
  revient **immédiatement** (le Sous-agent est lancé en arrière-plan), donc ne
  marque pas la fin.
- **Fin par signal explicite seul (`TaskStop`)** : rejeté **seul** — se coince si
  un Sous-agent finit **sans** arrêt explicite. Aucun `Stop` reçu ne porte
  d'`agent_id` : un Sous-agent qui termine de lui-même n'émet aucun événement de
  fin exploitable. `TaskStop` reste envisagé en **voie rapide** complémentaire du
  timeout — à confirmer par une capture ciblée d'un Sous-agent finissant seul.
- **Sous-agent = Session/carte propre** : rejeté — un Sous-agent partage le
  `session_id` du parent (glossaire : Session = un `session_id`) ; ce n'est pas
  une Session. Plusieurs Sous-agents cohabitent sous un même `session_id`.

## Consequences

- **Nouveauté architecturale** : le timeout impose un **tic d'horloge** — island
  doit pouvoir ré-évaluer l'état d'une Session **sans nouvel Événement** (le
  modèle actuel est purement piloté par les Événements). C'est le principal coût.
- **Rançon du timeout** : un Sous-agent qui « réfléchit » longtemps sans tirer
  d'outil peut sortir de l'ensemble trop tôt et laisser la Session passer
  « terminée » prématurément ; jugé rare (les Sous-agents sont très bavards en
  outils) et rattrapé au hook suivant. Le réglage exact de N se cale sur une
  capture réelle.
- **La garde `agent_id` change de rôle** : aujourd'hui l'Adaptateur **jette**
  tout hook à `agent_id` (protégeant le parent du bruit du Sous-agent) ; elle doit
  devenir une **prise en compte volontaire** (compter le Sous-agent, alimenter le
  timeout) sans réintroduire de faux « ? » ni d'états parasites sur le parent —
  la non-régression de #39 (question du principal → orange) doit tenir.
- **Précédence figée** : question ⇒ orange immédiat ; le gate « pas terminée tant
  qu'un Sous-agent tourne » ne s'applique qu'au constat. (Corrige ADR-0006.)
- **Réversibilité** : le compte discret (identité minimale) et l'éventuel ajout
  de `TaskStop` sont des évolutions réversibles ; le choix « membership par
  `agent_id`, fin par timeout » est le socle dur.
