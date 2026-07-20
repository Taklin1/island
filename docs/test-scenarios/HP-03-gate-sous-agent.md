# HP-03 — Gate Sous-agent (jamais « terminée » tant qu'un Sous-agent tourne)

**But** : le gate Sous-agent lu depuis `background_tasks` au `Stop`. Une Session
dont le `Stop` (constat) liste un Sous-agent vivant reste `running` — AUCUN flash
vert ; le `Stop` suivant avec `background_tasks` vide la passe `ended`. Contrôle
Q5 : une **question** l'emporte toujours (orange immédiat) même avec un Sous-agent
vivant — le gate ne concerne que le **vert**.

**Couvre** : #48 / ADR-0008 (dont Q5 corrigeant ADR-0006).

## Pré-requis

Identiques à HP-01. Sessions namespacées `hp-gate-*`. Forme de fixture vérifiée
(tableau JSON `background_tasks`, filtre `type == "subagent"` + `id` non vide ;
`session_crons` ne compte pas).

## Étapes

### A. Constat + Sous-agent vivant ⇒ reste running (pas de vert)

1. **UserPromptSubmit** ⇒ `running`.
   ```json
   {"session_id":"hp-gate-1","transcript_path":"/tmp/hp-gate-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"UserPromptSubmit","prompt":"Explore le repo en sous-agent"}
   ```
2. **Stop** constat, `background_tasks` listant un Sous-agent vivant ⇒ `running`
   avec compte, **jamais** `ended`.
   ```json
   {"session_id":"hp-gate-1","transcript_path":"/tmp/hp-gate-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"En cours d'exploration…","background_tasks":[{"id":"sub-1","type":"subagent","status":"running"}]}
   ```
   Attendu trace : `island[hp-gate-1]=running ×1sub+summary`.
   Le `×1sub` prouve que le count a été décodé et que le gate a tenu (pas de vert).

3. **Stop** suivant, `background_tasks` **vide** (le Sous-agent a fini) ⇒ `ended`.
   ```json
   {"session_id":"hp-gate-1","transcript_path":"/tmp/hp-gate-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Exploration terminée.","background_tasks":[]}
   ```
   Attendu : `island[hp-gate-1]=ended` (plus de `×sub`).

### B. Contrôle Q5 — question + Sous-agent vivant ⇒ orange IMMÉDIAT

4. Autre Session, **UserPromptSubmit** ⇒ `running`.
   ```json
   {"session_id":"hp-gate-2","transcript_path":"/tmp/hp-gate-2.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"UserPromptSubmit","prompt":"Prépare le merge"}
   ```
5. **Stop** finissant sur `?` AVEC un Sous-agent vivant ⇒ `waiting` immédiat
   (la question l'emporte ; le gate ne retient que le vert).
   ```json
   {"session_id":"hp-gate-2","transcript_path":"/tmp/hp-gate-2.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Prêt à merger — je lance ?","background_tasks":[{"id":"sub-2","type":"subagent","status":"running"}]}
   ```
   Attendu : `island[hp-gate-2]=waiting` (orange), Liseré allumé — PAS `running`.

### C. Robustesse repli — `background_tasks` de forme inattendue ne casse pas le Stop

6. Autre Session ; `background_tasks` d'un type inattendu (ex. non-tableau) ⇒
   repli silencieux à 0, le `Stop` (constat) se résout normalement `ended`.
   ```json
   {"session_id":"hp-gate-3","transcript_path":"/tmp/hp-gate-3.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Rien à signaler.","background_tasks":"garbage"}
   ```
   Attendu : `island[hp-gate-3]=ended` (le champ illisible ne bloque pas le Stop).

## Critères de réussite

- A : Sous-agent vivant + constat ⇒ `running ×1sub`, jamais de flash `ended` ;
  puis liste vide ⇒ `ended`.
- B : Sous-agent vivant + question ⇒ `waiting` immédiat (Q5).
- C : `background_tasks` mal formé ⇒ repli à 0, `Stop` résolu normalement.
