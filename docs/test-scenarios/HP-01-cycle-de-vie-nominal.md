# HP-01 — Cycle de vie nominal (constat ⇒ « terminée »)

**But** : vérifier le parcours de base d'une Session — démarrage, prompt, outil,
fin de tour sur un **constat** SANS Sous-agent — se résout en `ended` (vert,
« terminée »). C'est le socle de l'état fiable (#31 : un tour fini est vert, et
rien ne le ressuscite).

**Couvre** : #31 (état fiable de fin de tour).

## Pré-requis

- App buildée (`swift build`) et lancée : `.build/debug/Island`, Serveur local à
  l'écoute sur `http://127.0.0.1:41414`.
- Flag anti-installeur posé avant lancement (`defaults write Island
  hooksInstallAttempted -bool true`) + backup de `~/.claude/settings.json`.
- Token : `TOKEN=$(cat ~/.claude/island-token)`.
- Helper POST (auth par en-tête `X-Island-Token`, JAMAIS `Bearer`) :
  ```bash
  post() { curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    http://127.0.0.1:41414/hooks/claude-code \
    -H "X-Island-Token: $TOKEN" -H "Content-Type: application/json" -d "$1"; }
  ```
- Assertion : lire la **trace stdout** de l'app (`island: [ts] sessions: …`), qui
  publie `<projet>[<id>]=<state>` à chaque refresh. État d'abord (ADR : pas de
  pixels ici, l'état publié suffit).

## Étapes

Session de test namespacée `hp-lifecycle-1`, cwd `island`.

1. **SessionStart** (`source: startup`) ⇒ Session créée, état `idle`.
   ```json
   {"session_id":"hp-lifecycle-1","transcript_path":"/tmp/hp-lifecycle-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"SessionStart","source":"startup"}
   ```
   Attendu trace : `island[hp-lifecycle-1]=idle`.

2. **UserPromptSubmit** (`prompt: "Corrige le bug"`) ⇒ `running`, `lastPrompt` posé.
   ```json
   {"session_id":"hp-lifecycle-1","transcript_path":"/tmp/hp-lifecycle-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"UserPromptSubmit","prompt":"Corrige le bug"}
   ```
   Attendu : `island[hp-lifecycle-1]=running`.

3. **PreToolUse** (`tool_name: Bash`) ⇒ `running(Bash)`.
   ```json
   {"session_id":"hp-lifecycle-1","transcript_path":"/tmp/hp-lifecycle-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}
   ```
   Attendu : `island[hp-lifecycle-1]=running(Bash)`.

4. **PostToolUse** (`tool_name: Bash`) ⇒ l'outil retombe, `running` nu.
   ```json
   {"session_id":"hp-lifecycle-1","transcript_path":"/tmp/hp-lifecycle-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":"done"}
   ```
   Attendu : `island[hp-lifecycle-1]=running` (plus de `(Bash)`).

5. **Stop** — constat, `background_tasks` **vide** ⇒ `ended` (vert).
   ```json
   {"session_id":"hp-lifecycle-1","transcript_path":"/tmp/hp-lifecycle-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Terminé — le bug est corrigé.","background_tasks":[]}
   ```
   Attendu : `island[hp-lifecycle-1]=ended+summary`.

6. **Non-régression #31** — une notification idle (~60 s) NE ressuscite PAS le
   tour terminé en « ? ». Poster ensuite :
   ```json
   {"session_id":"hp-lifecycle-1","cwd":"/Users/loic/Documents/island","hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}
   ```
   Attendu : reste `island[hp-lifecycle-1]=ended` (surtout PAS `waiting`).

## Critères de réussite

- Chaque POST renvoie `200`.
- La trace suit la séquence `idle → running → running(Bash) → running → ended`.
- Après l'idle, l'état reste `ended` (jamais `waiting`) — #31 tient.
