# HP-02 — Un tour finissant sur une question « attend » (orange)

**But** : un `Stop` dont le dernier message assistant finit sur `?` se résout en
`waiting` (orange, « attend »), pas `ended`. Détection locale, structurelle
(dernier texte rogné-à-droite finit par `?`), sans scan de mots ni appel LLM.

**Couvre** : #39 / ADR-0006.

## Pré-requis

Identiques à HP-01 (app lancée sur 41414, `TOKEN`, helper `post`, lecture de la
trace stdout). Session namespacée `hp-question-*`.

## Étapes

### A. Question ⇒ attend (orange)

1. **UserPromptSubmit** ⇒ `running`.
   ```json
   {"session_id":"hp-question-1","transcript_path":"/tmp/hp-question-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"UserPromptSubmit","prompt":"Quelle base viser ?"}
   ```
2. **Stop** finissant sur `?` (via `last_assistant_message`, le champ autoritaire —
   robuste même si le transcript lag, cf. #39) ⇒ `waiting`.
   ```json
   {"session_id":"hp-question-1","transcript_path":"/tmp/hp-question-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Je peux cibler Postgres ou SQLite. Lequel veux-tu ?"}
   ```
   Attendu trace : `island[hp-question-1]=waiting+summary`.
   - Le Liseré s'allume (orange) ; la question est conservée dans `lastSummary`
     pour le Peek (« projet · attend : "…?" »).

### B. Contraste — constat ⇒ terminée (vert)

3. Même séquence, autre Session, dernier message **sans** `?` :
   ```json
   {"session_id":"hp-question-2","transcript_path":"/tmp/hp-question-2.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"C'est fait — la release est taguée."}
   ```
   Attendu : `island[hp-question-2]=ended`. Prouve que le classement discrimine
   bien question vs constat (et n'est pas un orange systématique).

### C. Robustesse — ponctuation après le `?` tolérée (retry « autre donnée »)

4. Autre Session, message finissant par une question suivie d'espaces/guillemet :
   ```json
   {"session_id":"hp-question-3","transcript_path":"/tmp/hp-question-3.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"On part là-dessus ?  "}
   ```
   Attendu : `island[hp-question-3]=waiting` (rognage à droite avant test du `?`).

## Critères de réussite

- A : la Session finissant sur `?` est `waiting` (jamais `ended`).
- B : la Session finissant sur un constat est `ended` (jamais `waiting`).
- C : un `?` suivi d'espaces reste détecté `waiting` (détection structurelle).
