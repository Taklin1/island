---
name: agentic-tests
description: Lance les tests agentiques d'Akutia - par defaut le parcours de feature (FP) de la sous-issue courante, ou la suite des parcours nominaux (HP) si "HP"/"all" est demande ou sur une branche d'integration avec PR en cours. Use when running agentic tests, validating a sub-issue before auto-merge, or running the HP suite before an epic->develop PR.
---

# /agentic-tests - runner (Akutia)

Execute la couche **test agentique** (sommet de la pyramide) : un subagent pilote
l'app **reelle qui tourne** et valide un parcours, verif **UI d'abord**. Ce skill
ne fait qu'**executer** ; le format et l'inventaire des HP vivent dans
`docs/test-scenarios/` (cree paresseusement).

## 0. Stack Akutia

- App Next.js : `yarn dev` (port 3000). Bridge (analyse profonde) :
  `cd bridge && yarn dev` (port 3001). Lance ce dont le parcours a besoin.
- Driver : navigateur via le skill `webapp-testing` (Playwright).
- **Avant tout rebuild/restart, verifier qu'aucune analyse profonde ne tourne**
  (cf CLAUDE.md). Ne casse jamais la **recherche rapide** ni la compat Vane.

## 1. Choisir le mode

| Condition | Mode |
|---|---|
| argument `HP` / `all` | **HP** - toute la suite |
| sinon, sur `epic/*` avec une PR epic->develop ouverte | **HP** |
| sinon (sur `feature/*`) | **FP** - la sous-issue courante |

En cas d'ambiguite (sur `develop`/`main`, sans argument), demande quel mode lancer.

## 2. Pre-requis

- L'app (et le bridge si besoin) **tourne en local**. Pas de stack = pas d'execution.
- Tu sais piloter l'app (Playwright via `webapp-testing`).

### Demarrer la stack en local (gotchas #164, FP d'une route API)

> **STOP - VERIFIE D'ABORD QUE TA DB EST VRAIMENT LOCALE.** Sur le Mac du founder, `DATABASE_URL=...@127.0.0.1:5434/...` (.env) est un **forward VS Code vers le Postgres PROD du VPS**, PAS une DB locale (cf CLAUDE.md regle 11 + `memory/local-5434-is-prod-vps-forward.md`). Lancer un `next dev` / un FP runtime dessus = charger la PROD (incident #164 : `max_connections` saturé, `FATAL 53300`, risque d'indispo). AVANT de booter quoi que ce soit : `lsof -nP -iTCP:5434` (si "Code Helper" -> c'est un forward, PAS local) + `docker ps` (aucun postgres local qui tourne -> distant). **Ne FP en local QUE contre une vraie DB locale jetable montee explicitement sur un AUTRE port** ; sinon, joue le FP **sur le VPS post-deploiement** (route live, via le relais VPS). Les gotchas ci-dessous ne valent QUE pour une DB authentiquement locale.

Pour un FP de route API (pas d'UI), curl + sondes psql suffisent (pas besoin de Playwright). 4 pieges decouverts en #164 quand on boote l'app local soi-meme (DB locale jetable) :

1. **`yarn dev` est wrappe Docker/SearxNG** (`docker start searxng || docker run ... && next dev`) : si Docker (OrbStack) est down, le `&&` casse et `next dev` ne demarre JAMAIS. SearxNG ne sert qu'a la recherche rapide -> pour tester une autre route, lance **`npx next dev --webpack -p <port>` directement** (bypass du wrapper).
2. **`DATA_DIR=/data` (prod) dans `.env`** : en local `/data` n'existe pas -> `ConfigManager` (`src/lib/config/index.ts`, `writeFileSync ${DATA_DIR}/data/config.json`) crashe au boot en `ENOENT`. **Override `DATA_DIR=<dossier temp local>`** (pre-creer `${DATA_DIR}/data` + `${DATA_DIR}/projects`) ; ConfigManager ecrit alors son `config.json` par defaut tout seul.
3. **`RESEND_API_KEY='' npx next dev`** coupe les emails (Next n'override PAS une env var deja posee -> `getResend()` renvoie null -> `log.warn skipping`). Verifier le marqueur de skip dans le log = preuve zero email sortant. Utiliser des adresses `@example.com` par securite.
4. **psql `-tAc` sur un `INSERT ... RETURNING id`** capture AUSSI le tag `INSERT 0 1` (2 lignes) -> un `TEAM_ID=$(psql -tAc ...)` malforme casse les inserts suivants (uuid invalide). Utiliser **`-qtAc`** (`-q` supprime le tag de commande).
5. **Next 16 dev refuse `127.0.0.1` comme dev origin** : le websocket HMR est rejete -> l'hydratation React ne s'execute jamais sous automation (pages inertes aux clics, faux negatifs Playwright alors que le SSR s'affiche). Toujours cibler **`http://localhost:<port>`** dans le driver, jamais `http://127.0.0.1:<port>` (constat suite HP epic #334).

**Nettoyage + connexions** : un `next dev` local ouvre un pool postgres-js qui s'EMPILE sur les instances deja lancees (`:3001` bridge, `:3002` app) et peut **saturer `max_connections`** (FATAL "emplacements reserves au superutilisateur") -> le cleanup en trap peut echouer SILENCIEUSEMENT. Toujours : data **namespacee** (`ZZZ_FP<issue>` / `@example.com`) + cleanup avec **retries espaces** (les connexions zombies se liberent en ~30-60s apres kill du dev server) + **verifier** ensuite le compte total restaure (pas de data de test laissee). Ne JAMAIS tuer/restart les instances `:3001`/`:3002` du founder ni postgres.

## 3. Mode FP (gate d'auto-merge sous-issue -> epic)

1. Deduis le n° d'issue du nom de branche `feature/<issue-gh>-<slug>` et recupere
   l'issue (`gh issue view <n>`).
2. Lis la section **"Acceptance criteria"**. Traduis-la en actions concretes au
   runtime (parcours comportemental).
3. Deroule le parcours contre l'app, verif UI d'abord (sonde DB/filesystem seulement
   si l'UI ne suffit pas).
4. Reporte : passe/echec par etape **+ observations**.

**Gate** (voir `git-flow`) : l'auto-merge n'a lieu que si le FP est **vert** *et*
qu'aucune **observation bloquante** n'est remontee - en plus de `yarn lint` +
`npx tsc -p tsconfig.json --noEmit` + `yarn build` + tests `scripts/test/*` verts.
Sur rouge ou observation bloquante : **ne merge pas**, reporte.

## 4. Mode HP (gate epic -> develop, decision humaine)

1. Lis tous les `docs/test-scenarios/HP-*.md`.
2. Deroule chaque parcours **independamment** contre l'app (un HP doit tourner seul).
3. Applique les **regles d'execution** (ci-dessous).
4. Produis un rapport par scenario + une rubrique **Observations** consolidee, prete
   a coller dans la PR epic->develop.

L'agent **ne merge jamais** vers `develop` : il deroule, reporte. HP rouge ->
l'humain tranche. Garde la suite HP courte et ciblee (les parcours nominaux qui
comptent vraiment), pas un catalogue exhaustif.

## 5. Regles d'execution (agent)

- **Retry sur une autre donnee avant de remonter une observation liee a la donnee.**
  Si une etape echoue sur une instance, reessaie avec une autre de meme nature ; une
  observation "donnee" ne se justifie que si toutes les instances raisonnables
  echouent, ou si le comportement est structurel.
- **Remonte toutes les observations**, bloquantes ou non (warning console,
  comportement surprenant, effet de bord, vraie cassure). Tu **qualifies la
  severite** ; une observation bloquante fait echouer le gate.
- **UI d'abord.** Une sonde du backing-store ne complete que ce que l'UI ne montre
  pas, et seulement si un store existe.
- **Selection des donnees par caracteristiques** (filtres, badges...), pas d'ID en
  dur (mode HP) : si aucune donnee ne satisfait les conditions, c'est un signal
  legitime, pas une excuse pour contourner l'UI.

## 6. Format du rapport

Pour chaque parcours : `✅ / ❌ <id ou issue> - <titre>`, les etapes en echec, puis :

```
## Observations
- [bloquante] ...
- [non bloquante] ...
```
