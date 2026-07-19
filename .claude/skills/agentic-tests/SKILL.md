---
name: agentic-tests
description: Lance les tests agentiques d'island - par defaut le parcours de feature (FP) de la sous-issue courante, ou la suite des parcours nominaux (HP) si "HP"/"all" est demande ou sur une branche d'integration avec PR en cours. Use when running agentic tests, validating a sub-issue before auto-merge, or running the HP suite before an epic->develop PR.
---

# /agentic-tests - runner (island)

Execute la couche **test agentique** (sommet de la pyramide) : on injecte des
evenements dans l'app **reelle** via son API locale et on valide un parcours,
verif **etat des Sessions d'abord**. Ce skill ne fait qu'**executer** ; le format
et l'inventaire des HP vivent dans `docs/test-scenarios/` (cree paresseusement).

## 0. Stack island

- App macOS native Swift/SwiftUI (SwiftPM), "island" : Dynamic Island qui suit les
  sessions Claude Code.
- Driver : **POST de fixtures JSON de hooks** vers l'API locale d'evenements de
  l'app, puis assertion de l'**etat des Sessions publie**. Le rendu SwiftUI se
  verifie **visuellement** (screenshots) - pas de XCUITest.
- Lance ce dont le parcours a besoin : l'app buildee (`swift build`) et tournant en
  local, ecoutant sur son API d'evenements.

## 1. Choisir le mode

| Condition | Mode |
|---|---|
| argument `HP` / `all` | **HP** - toute la suite |
| sinon, sur `epic/*` avec une PR epic->develop ouverte | **HP** |
| sinon (sur `feature/*`) | **FP** - la sous-issue courante |

En cas d'ambiguite (sur `develop`/`main`, sans argument), demande quel mode lancer.

## 2. Pre-requis

- L'app **tourne en local** (`swift build` puis lancee), API d'evenements a l'ecoute.
  Pas d'app qui tourne = pas d'execution.
- Tu sais piloter l'app : POST des fixtures de hooks + lecture de l'etat des Sessions
  ; screenshots pour le rendu SwiftUI.

### Injecter les fixtures

Un FP/HP d'island se joue en POSTant des **fixtures JSON de hooks** (evenements
Claude Code : session start/stop, tool use, etc.) sur l'API locale de l'app, puis en
**asseyant l'etat des Sessions** que l'app publie en reponse. Regles :

1. **Fixtures namespacees** : prefixe/ID de test reconnaissable pour reperer et
   nettoyer facilement l'etat de test.
2. **Ne perturbe pas une instance reelle du dev** : joue contre une instance de test
   dediee, pas contre l'island qui suit les vraies sessions de Loic.
3. **Etat d'abord, pixels ensuite** : assois-toi sur l'etat des Sessions publie ; ne
   passe au screenshot que pour ce que seul le rendu SwiftUI peut confirmer.

## 3. Mode FP (gate d'auto-merge sous-issue -> epic)

1. Deduis le n° d'issue du nom de branche `feature/<issue-gh>-<slug>` et recupere
   l'issue (`gh issue view <n>`).
2. Lis la section **"Acceptance criteria"**. Traduis-la en actions concretes au
   runtime (parcours comportemental : quels evenements injecter, quel etat attendre).
3. Deroule le parcours contre l'app : POST des fixtures, assertion de l'etat des
   Sessions (screenshot seulement si l'etat publie ne suffit pas a trancher).
4. Reporte : passe/echec par etape **+ observations**.

**Gate** (voir `git-flow`) : l'auto-merge n'a lieu que si le FP est **vert** *et*
qu'aucune **observation bloquante** n'est remontee - en plus de `swift build` +
`swift test` verts. Sur rouge ou observation bloquante : **ne merge pas**, reporte.

## 4. Mode HP (gate epic -> develop, decision humaine)

1. Lis tous les `docs/test-scenarios/HP-*.md`.
2. Deroule chaque parcours **independamment** contre l'app (un HP doit tourner seul).
3. Applique les **regles d'execution** (ci-dessous).
4. Produis un rapport par scenario + une rubrique **Observations** consolidee, prete
   a coller dans la PR epic->develop.

L'agent **ne merge jamais** vers `develop` : il deroule, reporte. HP rouge ->
l'humain (Loic) tranche. Garde la suite HP courte et ciblee (les parcours nominaux
qui comptent vraiment), pas un catalogue exhaustif.

## 5. Regles d'execution (agent)

- **Retry sur une autre donnee avant de remonter une observation liee a la donnee.**
  Si une etape echoue sur une fixture, reessaie avec une autre de meme nature ; une
  observation "donnee" ne se justifie que si toutes les fixtures raisonnables
  echouent, ou si le comportement est structurel.
- **Remonte toutes les observations**, bloquantes ou non (log surprenant,
  comportement inattendu, effet de bord, vraie cassure). Tu **qualifies la
  severite** ; une observation bloquante fait echouer le gate.
- **Etat d'abord.** Un screenshot ne complete que ce que l'etat des Sessions publie
  ne montre pas.
- **Selection des fixtures par caracteristiques** (type d'evenement, phase de
  session...), pas d'ID en dur (mode HP) : si aucune fixture ne satisfait les
  conditions, c'est un signal legitime, pas une excuse pour contourner l'API.

## 6. Format du rapport

Pour chaque parcours : `✅ / ❌ <id ou issue> - <titre>`, les etapes en echec, puis :

```
## Observations
- [bloquante] ...
- [non bloquante] ...
```
