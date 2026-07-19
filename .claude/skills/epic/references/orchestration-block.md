# Bloc ORCHESTRATION (verbatim, à insérer dans chaque prompt d'agent)

> Placeholders : `{PORT}` = port DB jetable dédié à l'agent (plage 56xx, incrémenté par
> agent de la vague) ; `{BASE}` = branche epic (`epic/<n>-<slug>`). Le reste s'insère tel
> quel, juste après la ligne « Tâche : ... » du gabarit /prompt. Chaque règle vient d'un
> incident réel du pilote #238 - ne pas en retirer sans une bonne raison documentée.

```
ORCHESTRATION (tu es un sous-agent d'une session orchestratrice ; adaptations NON-NÉGOCIABLES) :
(a) tu travailles dans un worktree git isolé : AVANT toute compilation/test, symlink les
node_modules du repo principal :
`ln -s /Users/loic/Documents/akutia/node_modules node_modules && ln -s /Users/loic/Documents/akutia/bridge/node_modules bridge/node_modules`
(ne JAMAIS les stager) ;
(b) ta branche part de {BASE} et ta PR cible {BASE} - jamais develop, jamais main ;
(c) INTERDIT de modifier `package.json` (version) et `CHANGELOG.md` : propose ta ligne de
changelog dans le body de la PR (section « Changelog proposé »), l'orchestrateur réconcilie
au merge ;
(d) PRÉ-SCAN EM-DASH avant CHAQUE push : la garde CI `check-no-emdash` scanne le CONTENU
ENTIER des fichiers touchés, pas ton diff - `perl -CSD -ne 'print "$ARGV:$.: $_" if /[\x{2013}\x{2014}]/' <chaque fichier touché>`
-> remplace toute occurrence pré-existante par « - » ; JAMAIS d'ajout à l'allowlist pour
notre code (elle est réservée au contenu tiers) ;
(e) PAS de `yarn build` / `next build` local : tsc + lint + FP suffisent pour une PR ;
(f) tout NOUVEAU test doit être enregistré dans le `files[]` de `scripts/tsconfig.json`
(sinon il n'est pas type-checké = faux vert possible) ;
(g) si une décision produit non tranchée ou un blocage survient : NE DEVINE PAS, arrête-toi
et termine ta réponse par un bloc « QUESTION: » (contexte, options, ta recommandation) -
la réponse du founder te sera renvoyée et tu reprendras avec ton contexte intact ;
(h) JAMAIS de `next dev`/`yarn dev`, JAMAIS rien contre 127.0.0.1:5434 (= Postgres PROD,
règle 11 CLAUDE.md) ; si un test a besoin d'une DB : cluster Postgres jetable sur TON port
dédié {PORT} ;
(i) board GitHub temps réel : carte « In progress » au démarrage, « In review » à la PR ;
(i-bis) tout NOUVEAU test `scripts/test/*.test.ts` commence par la ligne
`/* eslint-disable no-console */` (la règle `no-console` est `error`), et tu joues
`npx eslint` sur TES tests avant push - `yarn lint` seul ne suffit pas à le prouver ;
(j) termine ta réponse finale par : numéro de PR, branche, résumé en 3 lignes, ligne de
changelog proposée, résultats des tests (TDD/FP/tsc/lint/em-dash).
```

## Pourquoi chaque règle (traçabilité incidents, pilote #238 vague 1)

| Règle | Incident d'origine |
|---|---|
| (a) symlinks | worktree neuf sans node_modules -> tsc TS2307 (mémoire `worktree-node-modules-symlink`) |
| (c) fichiers réservés | 8 PR parallèles = conflits garantis sur version/CHANGELOG ; 0 conflit avec la règle |
| (d) pré-scan em-dash | 2 CI rouges (PR #309/#310) sur des em-dash legacy PRÉ-existants dans les fichiers touchés |
| (e) no-build | 3 agents ont brûlé 5-10 min de webpack chacun, sans valeur pour la PR |
| (f) allowlist tsconfig | 2 tests livrés non enregistrés = non type-checkés, attrapés seulement en revue |
| (g) protocole QUESTION | le sous-agent n'a AUCUN canal direct vers le founder ; deviner = reprise coûteuse |
| (h) ports dédiés | 8 FP simultanés sans collision ; :5434 = forward prod (incident #164) |
| (i-bis) header no-console | récidive x2 : vague 3 epic #273 (2 agents, 6 fichiers) puis vague 1 epic #449 (7 tests provenance) - réparation d'hygiène orchestrateur à chaque fois |
