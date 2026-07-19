---
name: git-flow
description: Git flow du projet island (branches, PR, validation de position avant dev). Use when starting or finishing a dev, branching, opening a PR, merging, or to know from which branch to work.
---

# Git flow - island

Git flow vanilla simplifie. On documente l'usage *projet*, pas git lui-meme.
Suivi du travail (GitHub Issues) : voir `docs/agents/issue-tracker.md`
(source de verite).

## Branches

- `main` : releases. Mise a jour UNIQUEMENT via une PR `develop -> main` (hotfix
  excepte), mergee par Loic. Aucun commit direct, aucun merge par l'agent. Pas de
  deploiement (app macOS native, pas de CI/CD pour l'instant).
- `develop` : integration, **branche par defaut GitHub**. Tout dev en part, tout y
  revient. Pas de CI configuree pour l'instant - a documenter quand elle existera.
- `epic/<issue-gh>-<slug>` : branche d'integration d'un gros chantier (une issue
  assez large pour meriter un PRD), depuis `develop` a jour. Creee au grilling
  (`/grill`), nommee d'apres l'**issue** qui la declenche (PAS le n° du PRD genere
  ensuite par `/to-prd`). La seance y ecrit la sortie de grilling (`CONTEXT.md`,
  ADRs) ; l'epic accumule ensuite les sous-issues. Les sous-issues `ready-for-agent`
  s'y **auto-mergent** apres verif locale verte ; `epic -> develop` reste une
  decision humaine.
- `feature/<issue-gh>-<slug>` : un dev = une branche, depuis `develop` a jour - ou
  depuis l'`epic/*` quand le dev implemente une sous-issue d'un chantier grille.
- `hotfix/<slug>` : depuis `main`, sur demande expresse, PR + validation manuelle,
  puis report sur `develop`.
- Pas de branche `release`.

> **Protection par convention.** La protection de branche GitHub n'est pas
> forcement disponible (repo prive/plan gratuit). `main`/`develop` sont donc
> protegees par convention - l'agent ne pousse jamais en direct et ne merge jamais
> vers `main`/`develop`.

## Epic ou feature directe ? (qui decide)

C'est une decision HUMAINE, prise quand tu saisis une issue - aucun skill ne
tranche tout seul. Heuristique :

- **Feature directe** (pas d'epic) : un seul changement clair, une seule tranche
  verticale, peu d'incertitude. -> `feature/<issue>-<slug>` depuis `develop`, tu
  codes (eventuellement `/to-issues` si c'est 2-3 tranches reliees).
- **Epic** : gros chantier = plusieurs tranches, OU des decisions de design/ADR,
  OU de l'incertitude a lever, OU un livrable transverse. -> `/grill`
  (cree la branche `epic/*` + ecrit CONTEXT.md/ADR) -> `/to-prd` (le PRD) ->
  `/to-issues` (les sous-issues).

Role des skills dans cette decision :

- `grill` ne decide pas, mais c'est LE moment ou l'epic se materialise (il cree la
  branche `epic/*`). Si tu grilles, tu as acte que c'est epic-scale.
- `to-prd` : produire un PRD = declarer un epic.
- `to-issues` : neutre - il decoupe un PRD (epic) en sous-issues, OU un petit plan
  en 2-3 issues sans epic.

En cas de doute : commence en feature ; si ca deborde (plusieurs tranches,
decisions structurantes), promeus en epic (grill -> PRD -> issues).

## Workflow

On parle de PR (GitHub). Cote git :

- **Nouveau dev** : depuis `develop` a jour -> `feature/<issue-gh>-<slug>` ; ou,
  pour une sous-issue d'un chantier grille, depuis l'`epic/*` -> `feature/...`.
  Rattache la branche a une/des issue(s) GitHub ; si aucune n'est connue, demande.
- **Gros chantier (epic)** : `/grill` cree `epic/<issue-gh>-<slug>` depuis
  `develop` a jour et y ecrit la sortie de grilling. `/to-prd` cree le PRD (issue,
  label `ready-for-agent`), puis `/to-issues` cree les sous-issues basees sur l'epic.
  **Juste apres `/to-issues`, `/prompt` arme les issues creees** : il genere le prompt
  de lancement pret-a-coller de chaque issue (structure figee /git-flow + /tdd +
  /agentic-tests) + une carte de parallelisation (quoi lancer en //, quoi sequencer).
  Les sous-issues `ready-for-agent` PR -> epic et s'**auto-mergent** une fois la
  **verif locale verte** : `swift build` + `swift test` + le **FP** vert via
  `/agentic-tests` (sans observation bloquante). Garde l'epic synchronisee avec
  `develop`.
- **Fin de dev** : PR vers la base d'ou part la branche (`--base develop`, ou
  `--base <epic>` pour une sous-issue) ; commente le lien PR sur l'issue. (Repo solo :
  pas de reviewer assigne.) **L'agent ne merge jamais vers `develop`/`main`** : Loic
  valide et merge. *Seule exception* : l'auto-merge d'une sous-issue `ready-for-agent`
  dans son `epic/*` (verif locale verte).
- **`epic/*` -> `develop`** : decision humaine. Avant la PR, l'agent **deroule la
  suite HP** (`/agentic-tests HP`) et **colle le resultat** dans la PR (passe/echec
  + observations). La PR **liste les issues incluses** pour une revue en lot. L'agent
  ouvre la PR et donne le lien ; jamais de merge par l'agent.
- **`develop` -> `main`** : decision humaine. Sur demande, l'agent ouvre la PR
  (liste des changements depuis le dernier release) et donne le lien ; le merge par
  Loic. Jamais de merge par l'agent.

> **Board GitHub Project : pas encore configure - a documenter quand il existera.**
> Pour l'instant le suivi passe par les labels et les liens PR commentes sur les
> issues (cf `docs/agents/issue-tracker.md`). Restent **manuels** : le tri (labels),
> commenter le lien PR sur l'issue, et tout merge (jamais l'agent).

## Avant de coder - valide ta position

Au 1er acte de dev (code destine a etre commite) :

```bash
git rev-parse --abbrev-ref HEAD   # ou suis-je ?
git branch --merged develop       # branche deja mergee = stale
git status -sb                    # upstream 'gone' = stale ; arbre propre ?
```

Sur `main`, sur une branche **stale**, ou sur une `feature/*` etrangere au dev
demande : n'empile pas. Explique le placement le plus propre (retour `develop` a
jour + nouvelle branche) et **pourquoi**, puis demande l'accord avant d'agir
(surtout s'il y a des changements non commites).
