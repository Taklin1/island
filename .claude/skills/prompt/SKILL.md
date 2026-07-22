---
name: prompt
description: >-
  Génère un prompt de lancement prêt-à-coller pour implémenter une issue GitHub island
  dans une session dédiée : structure figée du projet (Tâche + PRÉREQUIS + skills
  /git-flow /tdd /agentic-tests + « Avant TOUT code, lis » ciblé + Séquence
  audit-avant→plan→TDD→audit-après→FP→PR + Périmètre + français docs / anglais code).
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

# /prompt - générateur de prompts de lancement d'issues (island)

Ce skill transforme une (ou plusieurs) issue(s) GitHub en **prompt(s) de lancement prêt(s)
à coller** dans des sessions dédiées. Chaque prompt reprend le standard de travail island
(audit avant/après, TDD, FP, PR vers develop) et pointe l'agent vers **le bon contexte à
lire** avant de coder - pour qu'une session neuve démarre exactement comme une session
experte, sans redécouvrir l'architecture.

Pour un lot (typiquement la sortie de `/to-issues`), il ajoute une **carte de
parallélisation** : ce qui peut être lancé en parallèle tout de suite, ce qui doit attendre.

## Quand ce skill se déclenche

- « donne-moi le prompt pour #12 », « par quoi je lance cette issue ? »
- « prépare les prompts des issues #12 #14 #15 »
- juste après `/to-issues` : « fais-moi les prompts des issues qu'on vient de créer »
- « quelles issues je peux paralléliser ? »
- toute demande de préparer des sessions dédiées / AFK à partir d'issues existantes.

## Entrées acceptées

- un ou plusieurs **numéros** d'issue (`#12`, `12`) ou **URLs** GitHub ;
- « les issues que /to-issues vient de créer » → prends les numéros retournés dans le contexte ;
- un **epic** (`#1`) → génère un prompt pour chacune de ses sous-issues OUVERTES
  (`gh issue view <epic> --json` / la liste de sous-issues), plus la carte de parallélisation.

Si aucune référence n'est fournissable, demande laquelle avant de générer.

---

## Étape 1 - récupérer chaque issue

```bash
gh issue view <N> --repo Taklin1/island
```

Lis : **titre exact**, corps (What to build / Contexte / Notes), **Acceptance criteria**,
section **Blocked by**, l'**epic parent**, et les labels (`ready-for-agent` vs
`ready-for-human` orientent le CADRAGE). Ne devine pas le titre : recopie-le tel quel.

## Étape 2 - remplir le gabarit

Le gabarit est **figé** (c'est sa valeur : chaque session démarre pareil). Tu ne changes que
le contenu des `{...}`. Le voici, avec la logique de remplissage juste après.

```
Nouvelle session, projet island. Tâche : implémenter l'issue GitHub #{N} (Taklin1/island) - « {titre exact} ».

{CADRAGE - bloc optionnel de 2-4 lignes ; À INCLURE seulement si l'issue n'est PAS une tranche de code standard (voir plus bas). Sinon, supprimer complètement cette ligne.}

PRÉREQUIS : {dépendances} (vérifie avant de brancher, sinon STOPPE et préviens-moi).

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (implémentation test-first rouge-vert-refactor), /agentic-tests (FP de la sous-issue avant PR).

Avant TOUT code, lis : (1) l'issue #{N} en entier, (2) {CONTEXT.md + ADR(s) de la zone}, (3) {fichiers Swift / API d'événements concernés}, (4) {invariants/règles de la zone, s'ils existent}, (5) {sessions sœurs de l'epic - autres slices déjà livrées}.

Séquence : /git-flow (branche depuis {base}) → AUDIT PRÉALABLE (impact + cascade) → plan montré → /tdd pour l'implémentation → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #{N}) → `swift build` + `swift test` verts sur le diff → commit/push + PR vers {base}. Arrête-toi à la PR.

Périmètre : {scope précis}. Français pour les docs/issues, anglais pour le code et les identifiants.
```

### Comment remplir chaque `{...}`

**`{N}` / `{titre exact}`** - de `gh issue view`. Titre recopié à l'identique.

**`{CADRAGE}` (optionnel)** - c'est le curseur d'honnêteté du prompt. L'inclure UNIQUEMENT
quand l'issue sort du cas « tranche de code testable » :
- **issue ops / outillage** (script, fixtures, runbook) : préciser que `/tdd` + `/agentic-tests`
  s'appliquent au **code produit** (logique pure + FP), pas au geste manuel qui reste à la main
  de Loic (ex. capture de transcripts hooks réels depuis `~/.claude`, release d'un binaire) ;
- **UI SwiftUI pure réutilisant un état déjà testé** : préciser que le FP est surtout du wiring
  + la vérification visuelle par screenshot (pas de XCUITest), pas un stand-up complet ;
- **décision HITL / design ouvert** : signaler la décision à faire trancher dans le plan.
Sinon → **pas de bloc CADRAGE** (une tranche AFK standard n'en a pas besoin).

**`{dépendances}` (PRÉREQUIS)** - de la section *Blocked by* :
- bloqueurs → « #X (et #Y) mergée(s) sur develop » ;
- si le bloqueur est encore en PR non mergée → insister : « vérifie que #X est bien sur
  develop AVANT de brancher ; sinon STOPPE » (une branche partant d'un develop sans le
  bloqueur repartira à zéro) ;
- aucun bloqueur → « aucun bloquant (autonome) ».

**`{base}` (branche de départ + cible PR)** - `develop` par défaut. Si l'issue est une
sous-issue d'un **epic qui a une branche `epic/<n>-<slug>`**, alors `epic/<...>` (cf
`/git-flow`) : les sous-issues d'un epic s'auto-mergent dans la branche epic après vérif
locale verte, et c'est l'epic qui part en PR vers develop. Vérifie l'historique de l'epic
(d'où sont parties les sœurs) plutôt que de supposer.

**`Avant TOUT code, lis` - LE cœur du skill.** Un bon prompt fait lire à la session neuve
exactement ce qu'un expert de la zone a en tête. Sélectionne, dans l'ordre :
1. **l'issue elle-même** (toujours (1)) ;
2. **le contexte de domaine** : `CONTEXT.md` (vocabulaire du projet) + l'ADR de la zone dans
   `docs/adr/*.md` quand elle existe (mappe le domaine de l'issue → l'ADR) ; + la PRD si
   l'issue en relève ;
3. **le code concerné** : les fichiers Swift / points de l'API locale d'événements nommés dans
   le corps de l'issue, plus un `grep`/Explore rapide de la zone pour les voisins load-bearing
   (ingestion des hooks + dérivation de l'état Session + vue SwiftUI, selon la couche) ;
4. **les invariants/règles de la zone** : un index `.claude/rules/` n'est pas encore configuré
   sur island - à documenter quand il existera ; en attendant, pointe le fichier de règle
   pertinent seulement s'il existe, sinon saute ce point ;
5. **les sessions sœurs de l'epic** : les autres slices déjà livrées de la même epic (une
   session sur une slice gagne à lire ce que ses sœurs ont posé). Un mécanisme de mémoire
   (`memory/*.md`) n'est pas encore configuré sur island - à documenter quand il existera ; en
   attendant, cite les PR/branches sœurs plutôt que des `[[liens]]`.
Ne liste pas 15 fichiers : vise **4-6 pointeurs vraiment portants**. Si tu ne trouves pas
l'ADR/règle/slice pertinents, **grep pour les trouver** - ne remplis pas au hasard.

**`{scope précis}` (Périmètre)** - distille *What to build* + *Acceptance criteria* +
décisions clés en **un paragraphe dense** : le comportement bout-en-bout, les gardes, les cas
limites, les décisions déjà tranchées (pour ne pas les rouvrir). Reprends le vocabulaire du
domaine (`CONTEXT.md` / l'ADR). Ajoute, quand ça s'applique :
- **si l'issue introduit un flag/réglage** : son comportement par défaut explicite ;
- le **non-négociable de langue** : « Français pour les docs/issues, anglais pour le code et
  les identifiants » (invariant projet).

La **Séquence est identique pour toute issue** (c'est le standard de travail island :
audit préalable → plan → TDD → audit après impitoyable et factuel → FP → `swift build` +
`swift test` verts → PR, arrêt à la PR). Ne la personnalise pas ; elle encode la discipline
non-négociable du repo.

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
   **éditent le même module** (même store, même vue, même glue d'ingestion) vont **entrer en
   conflit au merge** même en parallèle. Déduis les fichiers touchés du corps des issues (+
   un `grep` de la zone si besoin) et **signale-les** : « #A et #B touchent toutes deux
   `SessionStore.swift` → préférer les sérialiser (ou coordonner les diffs) ».

Format de la carte :

```
## Parallélisation
- Vague 1 (en //): #A, #B  - indépendantes.
- Vague 2 (après merge #A): #C  - bloquée par #A.
- Attention conflit: #B et #C touchent `Sources/island/SessionStore.swift` → sérialiser de préférence.
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
