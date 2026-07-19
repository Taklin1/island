---
name: prompt
description: >-
  Génère un prompt de lancement prêt-à-coller pour implémenter une issue GitHub Akutia
  dans une session dédiée : structure figée du projet (Tâche + PRÉREQUIS + skills
  /git-flow /tdd /agentic-tests + « Avant TOUT code, lis » ciblé + Séquence
  audit-avant→plan→TDD→audit-après→FP→PR + Périmètre + vouvoiement/accents/zéro em-dash).
  Pour un LOT d'issues, ajoute une carte de parallélisation (quoi lancer en parallèle, quoi
  séquencer) d'après les blocked-by et les fichiers partagés. Déclenche dès que l'utilisateur
  veut « le prompt » ou « les prompts » d'une ou plusieurs issues, préparer des sessions
  AFK/dédiées, « par quoi je lance #X », « prépare-moi les sessions », savoir quelles issues
  paralléliser, ou JUSTE APRÈS /to-issues pour armer les issues créées - même sans le mot
  « prompt ». NE PAS se déclencher quand l'utilisateur veut IMPLÉMENTER/corriger l'issue
  lui-même maintenant (→ /git-flow + /tdd directement), rédiger un prompt LLM/système ou de
  cadrage PRD d'un agent (≠ un prompt de session), éditer la description d'un autre skill
  (→ skill-creator), découper un PRD en issues (→ /to-issues), ou juste consulter une
  branche/dépendance sans vouloir de prompt.
---

# /prompt - générateur de prompts de lancement d'issues (Akutia)

Ce skill transforme une (ou plusieurs) issue(s) GitHub en **prompt(s) de lancement prêt(s)
à coller** dans des sessions dédiées. Chaque prompt reprend le standard de travail Akutia
(audit avant/après, TDD, FP, PR vers develop) et pointe l'agent vers **le bon contexte à
lire** avant de coder - pour qu'une session neuve démarre exactement comme une session
experte, sans redécouvrir l'architecture.

Pour un lot (typiquement la sortie de `/to-issues`), il ajoute une **carte de
parallélisation** : ce qui peut être lancé en parallèle tout de suite, ce qui doit attendre.

## Quand ce skill se déclenche

- « donne-moi le prompt pour #289 », « par quoi je lance cette issue ? »
- « prépare les prompts des issues #271 #289 #290 »
- juste après `/to-issues` : « fais-moi les prompts des issues qu'on vient de créer »
- « quelles issues je peux paralléliser ? »
- toute demande de préparer des sessions dédiées / AFK à partir d'issues existantes.

## Entrées acceptées

- un ou plusieurs **numéros** d'issue (`#289`, `289`) ou **URLs** GitHub ;
- « les issues que /to-issues vient de créer » → prends les numéros retournés dans le contexte ;
- un **epic** (`#219`) → génère un prompt pour chacune de ses sous-issues OUVERTES
  (`gh issue view <epic> --json` / la liste de sous-issues), plus la carte de parallélisation.

Si aucune référence n'est fournissable, demande laquelle avant de générer.

---

## Étape 1 - récupérer chaque issue

```bash
gh issue view <N> --repo Taklin1/briefy
```

Lis : **titre exact**, corps (What to build / Contexte / Notes), **Acceptance criteria**,
section **Blocked by**, l'**epic parent**, et les labels (`ready-for-agent` vs
`ready-for-human` orientent le CADRAGE). Ne devine pas le titre : recopie-le tel quel.

## Étape 2 - remplir le gabarit

Le gabarit est **figé** (c'est sa valeur : chaque session démarre pareil). Tu ne changes que
le contenu des `{...}`. Le voici, avec la logique de remplissage juste après.

```
Nouvelle session, projet Akutia. Tâche : implémenter l'issue GitHub #{N} (Taklin1/briefy) - « {titre exact} ».

{CADRAGE - bloc optionnel de 2-4 lignes ; À INCLURE seulement si l'issue n'est PAS une tranche de code standard (voir plus bas). Sinon, supprimer complètement cette ligne.}

PRÉREQUIS : {dépendances} (vérifie avant de brancher, sinon STOPPE et préviens-moi).

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (implémentation test-first rouge-vert-refactor), /agentic-tests (FP de la sous-issue avant PR).

Avant TOUT code, lis : (1) l'issue #{N} en entier, (2) {ADR(s) de la zone}, (3) {fichiers/endpoints concernés}, (4) {invariants .claude/rules/*.md de la zone}, (5) {mémoires pertinentes [[...]] + slices sœurs}.

Séquence : /git-flow (branche depuis {base}) → carte « In progress » → AUDIT PRÉALABLE (impact + cascade) → plan montré → /tdd pour l'implémentation → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #{N}) → `npx prettier --write` sur le diff → commit/push + PR vers {base} (« In review »). Arrête-toi à la PR.

Périmètre : {scope précis}. {Derrière le flag {FLAG} : off = byte-identique, si applicable.} Vouvoiement + accents complets, zéro em-dash.
```

### Comment remplir chaque `{...}`

**`{N}` / `{titre exact}`** - de `gh issue view`. Titre recopié à l'identique.

**`{CADRAGE}` (optionnel)** - c'est le curseur d'honnêteté du prompt. L'inclure UNIQUEMENT
quand l'issue sort du cas « tranche de code testable » :
- **issue ops / outillage** (script, migration, runbook) : préciser que `/tdd` + `/agentic-tests`
  s'appliquent au **code produit** (logique pure + FP), pas à la mutation prod, qui reste un
  geste manuel (relais VPS, jamais `:5434`). Ex. #290.
- **UI pure réutilisant un endpoint déjà testé** : préciser que le FP est surtout du wiring +
  la réutilisation de la suite existante, pas un stand-up d'app complet.
- **décision HITL / design ouvert** : signaler la décision à faire trancher dans le plan.
Sinon → **pas de bloc CADRAGE** (une tranche AFK standard n'en a pas besoin).

**`{dépendances}` (PRÉREQUIS)** - de la section *Blocked by* :
- bloqueurs → « #X (et #Y) mergée(s) sur develop » ;
- si le bloqueur est encore en PR non mergée → insister : « vérifie que #X est bien sur
  develop AVANT de brancher ; sinon STOPPE » (une branche partant d'un develop sans le
  bloqueur repartira à zéro) ;
- aucun bloqueur → « aucun bloquant (autonome) ».

**`{base}` (branche de départ + cible PR)** - `develop` par défaut. Si l'issue est une
sous-issue d'un **epic grillé qui a une branche `epic/<n>-<slug>`**, alors `epic/<...>`
(cf `/git-flow`). Les slices de la base de connaissances (#220-#225) partaient de `develop` :
vérifie l'historique de l'epic (d'où sont parties les sœurs) plutôt que de supposer.

**`Avant TOUT code, lis` - LE cœur du skill.** Un bon prompt fait lire à la session neuve
exactement ce qu'un expert de la zone a en tête. Sélectionne, dans l'ordre :
1. **l'issue elle-même** (toujours (1)) ;
2. **l'ADR / la PRD de la zone** : `docs/adr/*.md` (mappe le domaine de l'issue → l'ADR ;
   ex. quota→0001, KB→0004, templates→0003, résilience→0002) ; + `PRD_*.md` si l'issue en relève ;
3. **le code concerné** : les fichiers/endpoints nommés dans le corps de l'issue, plus un
   `grep`/Explore rapide de la zone pour les voisins load-bearing (route + glue + dérivation
   pure + UI, selon la pile) ;
4. **les invariants `.claude/rules/*.md` de la zone** : utilise la **table d'index de
   `CLAUDE.md`** (section « Index des fichiers `.claude/rules/` ») qui mappe zone→fichier ;
   nomme ceux dont le `paths:` couvre les fichiers touchés (ex. UI streams→`frontend-streams.md`,
   route/auth→`security-auth.md`, DB→`database.md`, bridge→`bridge-analysis.md`) ;
5. **les mémoires `memory/*.md`** : via l'index `MEMORY.md` + les `[[liens]]` ; inclure la
   mémoire de la slice courante si elle existe et **les mémoires des slices sœurs** de l'epic
   (une session sur #225 gagne à lire #220/#223/#224). Cite-les en `[[slug]]`.
Ne liste pas 15 fichiers : vise **4-6 pointeurs vraiment portants**. Si tu ne trouves pas
l'ADR/rule/mémoire pertinents, **grep pour les trouver** - ne remplis pas au hasard.

**`{scope précis}` (Périmètre)** - distille *What to build* + *Acceptance criteria* +
décisions clés en **un paragraphe dense** : le comportement bout-en-bout, les gardes de
sécurité, les cas limites, les décisions déjà tranchées (pour ne pas les rouvrir). Reprends
le vocabulaire du domaine (CONTEXT.md / l'ADR). Ajoute, quand ça s'applique :
- le **feature flag** + « off = byte-identique » (quasi toutes les features Akutia sont
  gatées ; c'est un invariant projet) ;
- les **non-négociables de copie** : « Vouvoiement + accents complets, zéro em-dash »
  (voir `.claude/rules` + mémoires `ui-copy-vouvoiement-accents`, `em-dash-detection-locale`).

La **Séquence est identique pour toute issue** (c'est le standard de travail Akutia :
audit préalable → plan → TDD → audit après impitoyable et factuel → FP → PR, arrêt à la PR).
Ne la personnalise pas ; elle encode la discipline non-négociable du repo.

## Étape 3 - format de sortie

Pour **chaque** issue, un en-tête d'une ligne puis **un bloc ```` ``` ```` copiable** :

```
### Prompt #{N} - {titre court}
` ``
<le prompt rempli>
` ``
```

(Le bloc doit être un vrai fence de code pour un copier-coller propre.)

---

## Lot d'issues : la carte de parallélisation

Quand tu génères plusieurs prompts (souvent après `/to-issues`), termine par une carte qui
dit **quoi lancer en parallèle** et **quoi séquencer**. Deux signaux :

1. **Dépendances `Blocked by`** (dur) - construis le graphe et **stratifie en vagues** :
   - *Vague 1 (parallélisables maintenant)* = issues sans bloqueur non-mergé ;
   - *Vague 2* = issues débloquées une fois la Vague 1 mergée sur develop ; etc.
   Une issue bloquée par une PR non mergée reste en vague ultérieure (elle a besoin du code
   du bloqueur sur develop).

2. **Fichiers partagés** (mou, mais réel) - deux issues sans dépendance formelle mais qui
   **éditent le même module** (même route, même composant, même glue) vont **entrer en
   conflit au merge** même en parallèle. Déduis les fichiers touchés du corps des issues (+
   un `grep` de la zone si besoin) et **signale-les** : « #A et #B touchent toutes deux
   `X.tsx` → préférer les sérialiser (ou coordonner les diffs) ».

Format de la carte :

```
## Parallélisation
- Vague 1 (en //): #A, #B  - indépendantes.
- Vague 2 (après merge #A): #C  - bloquée par #A.
- Attention conflit: #B et #C touchent `src/lib/team/knowledgeBase.ts` → sérialiser de préférence.
```

Reste **factuel** : base les vagues sur les `Blocked by` réels, pas sur une intuition. Si une
dépendance est ambiguë, dis-le plutôt que de trancher au hasard.

---

## Calibration

Les prompts de référence (ton, densité, longueur) vivent dans `references/examples.md` :
un exemple **tranche de code AFK** (sans CADRAGE) et un exemple **ops/outillage** (avec
CADRAGE). Lis-les avant de générer si tu as un doute sur le niveau de détail attendu - un bon
prompt est **dense mais pas exhaustif** : il oriente et pointe, il ne réécrit pas l'issue.

## Position dans le flux

Ce skill se place **après `/to-issues`** (qui crée les issues) : `/to-issues` découpe le plan
en issues grabbables, `/prompt` les arme en prompts de session + carte de parallélisation. Il
est aussi utilisable seul, à tout moment, pour (re)générer le prompt d'une issue existante.
