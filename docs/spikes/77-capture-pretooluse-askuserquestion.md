# Capture #77 — le fil réel du hook `PreToolUse(AskUserQuestion)`

> Issue #77 · ADR-0009 (§ Résolution #77) · discipline `docs/agents/agentic-driving.md`
> § « capturer le fil réel avant de coder une détection ».
> Capture du 2026-07-20, build DEV instrumenté `TEMP-CAPTURE-77` (jamais l'Island vivante,
> mise en pause le temps de la capture), Claude Code v2.1.215. Vraie `AskUserQuestion`
> déclenchée par le mainteneur (point HITL n° 1) ; l'instrumentation a été retirée
> avant tout commit de fix (`grep TEMP-CAPTURE-77` = 0).

## Verdict

**La capture CONFIRME le contrat du brief** : le payload `PreToolUse` d'une
`AskUserQuestion` porte `tool_input.questions[]` **verbatim et ordonné** — l'ordre du
tableau `options[]` est l'ordre affiché par le TUI, donc l'index EST la touche (même
invariant de sûreté qu'ADR-0009). La bascule de source transcript → payload `PreToolUse`
est donc implémentable.

## Ordre du fil observé (session `a92c1263…`, cwd `~/Documents/island`)

1. `PreToolUse` `tool_name=AskUserQuestion` — **avant** l'affichage de la question,
   avec le `tool_input` complet (ci-dessous) ;
2. `Notification` `notification_type=permission_prompt`,
   `message="Claude needs your permission"` — c'est CE hook qui met la Session
   « en attente » ; il ne porte **pas** les options, et son type ne distingue pas
   question et permission (confirme ADR-0009 § Résolution #29) ;
3. *(l'utilisateur répond dans le terminal)* ;
4. `PostToolUse` `tool_name=AskUserQuestion` — même `tool_input`, plus `answers{}`.

Pendant toute l'attente (entre 1 et 4), le transcript JSONL ne contient **aucun**
bloc `tool_use` `AskUserQuestion` : le `tool_use` + `tool_result` n'apparaissent
qu'à la réponse (constat de l'issue #77 — la source transcript est morte-née).

## Payload `PreToolUse` capturé (extrait anonymisé, champs pertinents)

```json
{
  "session_id": "a92c1263…",
  "cwd": "~/Documents/island",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "La vraie AskUserQuestion a-t-elle été déclenchée puis répondue dans la session jetable ?",
        "header": "Capture #77",
        "options": [
          {
            "label": "Fait — question répondue",
            "description": "La question s'est affichée, j'ai attendu ~15 s puis répondu. Tu peux dépouiller la capture."
          },
          {
            "label": "Problème",
            "description": "Quelque chose n'a pas marché — je décris en note."
          }
        ],
        "multiSelect": false
      }
    ]
  }
}
```

L'ordre affiché dans le TUI au même instant (vérifié sur capture d'écran du
mainteneur) : `1. Fait — question répondue` puis `2. Problème` — identique à
l'ordre du tableau.

## Payload `PostToolUse` (résumé)

Même `tool_input.questions[]` que le `PreToolUse`, complété de
`answers{question → réponse}` (et `annotations{}`), dupliqué dans `tool_response`.
Le `PostToolUse` du même outil est donc le signal « question résolue » côté hooks.

## Note d'ironie utile

La question capturée est l'AskUserQuestion que l'agent d'implémentation de #77 a
posée au mainteneur pendant la capture elle-même : la session d'implémentation
tourne sous les mêmes hooks, le runbook « session jetable » n'a pas été nécessaire.
La capture d'écran du mainteneur montre en outre le bug #77 en conditions réelles :
carte « attend » avec le `waitingMessage` « Claude needs your permission » (#29) et
zéro bouton pendant qu'une question était bel et bien à l'écran.
