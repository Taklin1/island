# Le gate Sous-agents lit `background_tasks` au Stop ; la fin se résout à chaque Stop (plus de timeout)

> ## Amendement 2026-07-20 — le gate compte TOUTE entrée de `background_tasks` (décision #79, implémentation à venir)
>
> Le filtre `type == "subagent"` de l'amendement ci-dessous est **trop étroit** :
> un workflow (outil `Workflow`) vivant au Stop apparaît dans `background_tasks`
> avec `type: "workflow"` → exclu par le filtre → la Session passe à tort en
> `done` (bug #79). Ground truth par lecture du schéma Zod dans le **binaire**
> Claude Code 2.1.215 (voir `docs/agents/agentic-driving.md`, « Schéma des
> payloads de hooks ») : `type` est un label **ouvert** — « e.g. 'shell',
> 'subagent', 'monitor', 'workflow'. Falls back to the raw discriminant for
> unknown types » — et l'intention documentée du champ est précisément de
> distinguer « session is done » de « session is paused waiting for background
> work to wake it ».
>
> **Décision (Loïc, 2026-07-20)** : le gate compte **toute** entrée de
> `background_tasks` avec `id` non vide, quel que soit son `type` — pas
> d'allow-list. Raison : fidèle à l'intention du champ, robuste aux types
> inconnus/futurs ; toute tâche de fond réveille la session à sa complétion
> (nouveau tour ⇒ nouveau Stop qui ré-évalue), donc jamais de Session coincée.
> **Inchangé** : `session_crons` est un champ séparé (schéma distinct
> `{ id, schedule, recurring, prompt }`), toujours hors du compte.
> `liveSubagentCount` devient un misnomer — à renommer (p.ex.
> `liveBackgroundTaskCount`) lors de l'implémentation de #79, qui porte aussi le
> test de régression (un Stop avec une entrée `type: "workflow"` doit maintenir
> `.running`).

> ## Amendement 2026-07-19 — pivot `background_tasks` (implémentation #48)
>
> La capture ciblée exigée par le « 1er pas » (log `island-hook-capture-48.jsonl`,
> 2 scénarios réels validés par Loïc) a **révélé un signal que le grill ignorait** :
> **chaque hook `Stop` porte un champ `background_tasks`** listant les tâches de
> fond **encore vivantes au moment du Stop**. Ground truth :
>
> - Sous-agent vivant → `background_tasks` contient une entrée
>   `{ id = <agent_id>; type = subagent; status = running; agent_type = …; description = … }`.
>   Le `id` **est** l'`agent_id` porté par les hooks Pre/PostToolUse du Sous-agent.
> - Sous-agent fini → `background_tasks` **vide**.
> - `session_crons` est un **champ séparé** (crons `/schedule`, sans `type`) — **ne
>   compte pas** comme Sous-agent. On filtre sur **`type = subagent` ET `id` non vide**.
> - **Format du fil = tableau JSON** (décodable Codable). Le rendu « plist Obj-C »
>   (`( { id = …; } )`) observé dans le log n'est qu'un **artefact de
>   l'instrumentation** (`"\(nsArray)"` sur le tableau déjà parsé) — vérifié au
>   smoke test (un tableau JSON POSTé produit ce même rendu). On décode donc en
>   JSON, **pas** en parsing de description plist.
> - **Comportement du repli** : `background_tasks` est décodé dans une **enveloppe
>   Codable séparée** de `HookPayload`, en `try?` → **0** si le champ est absent,
>   d'un type inattendu ou illisible. Un format surprenant **ne casse donc jamais
>   le `Stop`** (la Session résout comme avant le gate). Ce repli n'est **pas** un
>   masque muet : un count mal décodé se voit **bruyamment** au FP réel (la carte
>   virerait au vert pendant qu'un Sous-agent tourne) et via la **trace de
>   production** du count décodé (`sessions: … =running ×Nsub` sur stdout, distincte
>   de toute instrumentation de capture — elle prouve que `count=1` a bien été lu).
>
> **Ce qui change vs le corps ci-dessous (raisonnement initial, superseded sur la
> fin) :**
>
> 1. **Le gate se décide au `Stop` lui-même**, sur `background_tasks` du payload —
>    la liste réelle des Sous-agents vivants à l'instant du Stop. **Race-free** :
>    plus besoin d'attendre le 1er hook du Sous-agent (la capture a montré que le
>    `Stop` du principal peut précéder d'~1 s le 1er hook du Sous-agent → l'approche
>    « ensemble d'`agent_id` » ci-dessous laissait un **flash vert** d'~1 s ; le
>    champ `background_tasks` supprime cette course).
> 2. **Plus de timeout d'inactivité ni de tic d'horloge.** La capture prouve que la
>    complétion d'un Sous-agent injecte dans la session **principale** un
>    `UserPromptSubmit` (`<task-notification>` avec `<task-id>=agent_id`,
>    `<status>completed</status>`) ⇒ un **nouveau tour** ⇒ un **nouveau `Stop`** qui
>    ré-évalue `background_tasks`. Toute résolution retombe donc **sur un Stop** :
>    island n'a **jamais** à ré-évaluer sans Événement → la « nouveauté
>    architecturale » (tic d'horloge) du corps ci-dessous **disparaît**. Le filet
>    « jamais coincée » reste assuré par l'**expiration d'orphelin** existante
>    (30 min sans Événement) du `SessionStore`.
> 3. **La garde `agent_id` de l'Adaptateur reste inchangée** (on continue de
>    **jeter** les hooks outil du Sous-agent) : le comptage ne vient plus d'eux mais
>    de `background_tasks` au Stop. Les événements `.subagentStarted/.subagentStopped`
>    (issue #31, hooks `SubagentStart/Stop` **non installés**, jamais émis) sont
>    **supprimés** comme code mort ; `mainTurnFinished`/`mainTurnAwaitsReply`
>    (complétion différée) disparaissent avec eux.
> 4. **`.turnEnded` porte désormais `liveSubagentCount`** (nombre d'entrées
>    `type = subagent` au Stop). Résolution : `awaitsReply ⇒ .waiting` **immédiat**
>    (Q5, question l'emporte, même avec Sous-agent vivant) ; sinon
>    `liveSubagentCount > 0 ⇒ .running` (gate) ; sinon `.ended`.
> 5. **Inchangé** : Q1 (Sous-agent = attribut de Session), Q2 (appartenance par
>    `agent_id`/`id`, indépendant du nom d'outil de spawn), Q6 (compte discret sur
>    la carte Étendue). `HookInstaller` **non touché**.

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
