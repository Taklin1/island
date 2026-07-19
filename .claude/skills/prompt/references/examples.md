# Exemples de référence (calibration)

Deux prompts réels, à utiliser comme étalon de ton/densité/longueur. Un bon prompt **oriente
et pointe** ; il ne recopie pas l'issue.

Les exemples ci-dessous sont illustratifs (numéros/chemins fictifs) : cale-toi sur leur
**densité** et leur **structure**, pas sur leurs identifiants exacts.

---

## Exemple A - tranche de code AFK standard (PAS de bloc CADRAGE)

Issue #14 : durcissement du suivi de session, règle nette, dépend d'une slice précédente. Cas
le plus courant. Noter : pas de CADRAGE (tranche testable classique) ; PRÉREQUIS insiste sur la
dépendance non-mergée ; les « lis » ciblent l'ADR + le store livré par la slice-mère + la glue
d'ingestion des hooks + les tests à étendre + la slice sœur ; une piste de deepening (prédicat
pur) est suggérée dans le Périmètre.

```
Nouvelle session, projet island. Tâche : implémenter l'issue GitHub #14 (Taklin1/island) - « Suivi de session : un hook Stop reçu après un SessionEnd ne doit pas ré-ouvrir la carte d'une session terminée ».

PRÉREQUIS ABSOLU : #12 (dérivation de l'état Session depuis les hooks, PR #13) mergée sur develop - #14 s'appuie directement sur la machine à états rendue terminale par #12. Vérifie que #12 est bien sur develop AVANT de brancher ; sinon STOPPE et préviens-moi.

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (implémentation test-first rouge-vert-refactor), /agentic-tests (FP de la sous-issue avant PR).

Avant TOUT code, lis : (1) l'issue #14 en entier, (2) `CONTEXT.md` (vocabulaire Session / hook / état terminal) + `docs/adr/0002-session-lifecycle.md` si présent (un SessionEnd fige la session), (3) le store livré par #12 `Sources/island/SessionStore.swift` (transitions d'état + réception des événements), (4) la glue d'ingestion `Sources/island/HookEventHandler.swift` (mapping hook JSON → transition), (5) les tests `Tests/islandTests/SessionStoreTests.swift`, (6) la slice sœur #12 (PR #13) pour les invariants déjà posés.

Séquence : /git-flow (branche depuis develop, #12 incluse) → AUDIT PRÉALABLE (impact + cascade : ordre de réception des événements, un état terminal doit absorber Stop sans rouvrir, ne pas régresser le cas Stop→SessionEnd normal) → plan montré → /tdd → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #14 : POST des fixtures JSON hooks dans l'ordre Stop-après-SessionEnd, asserter que la Session publiée reste terminale) → `swift build` + `swift test` verts sur le diff → commit/push + PR vers develop. Arrête-toi à la PR.

Périmètre : dans la transition d'état de `SessionStore`, une session déjà en état terminal (SessionEnd reçu) ignore un hook Stop tardif - la carte ne se ré-ouvre pas et l'état publié ne change pas. Cas préservés inchangés : Stop reçu avant SessionEnd → transition normale vers terminal ; Stop sur session active jamais terminée → comportement actuel. Piste de deepening à évaluer dans le plan : extraire un prédicat PUR testable `isTerminal(state:)` / `canApply(event:to:)` plutôt que d'empiler des `if` dans le handler. Mettre à jour `docs/adr/0002-session-lifecycle.md` si l'invariant s'y trouve. Français pour les docs/issues, anglais pour le code et les identifiants.
```

---

## Exemple B - issue ops / outillage (AVEC bloc CADRAGE)

Issue #20 : runbook + script de génération de fixtures. Le CADRAGE est nécessaire : il dit
franchement que les skills s'appliquent au **code produit** (script testable), pas au geste
manuel (la capture des transcripts hooks réels depuis `~/.claude`, faite par Loic), et il cadre
le livrable (runbook + un seul script neuf). Les « lis » incluent les patterns d'outillage
existants et le format des fixtures. Le Périmètre sépare explicitement le doc (runbook) du code
(script + logique pure + FP), et fige les décisions (pas de flag, pas de dépendance réseau).

```
Nouvelle session, projet island. Tâche : implémenter l'issue GitHub #20 (Taklin1/island) - « Runbook capture de transcripts hooks réels + script de conversion en fixtures JSON rejouables par l'API d'événements ».

CADRAGE : le livrable = un RUNBOOK (`docs/runbooks/`) qui décrit la capture de bout en bout, + un SEUL code neuf : un script de conversion testable. La capture des transcripts réels depuis `~/.claude` reste MANUELLE (Loic fournit les fichiers bruts) - tu la DOCUMENTES, tu ne la scriptes PAS (pas d'accès à un environnement tiers). Le code à /tdd + /agentic-tests = uniquement le convertisseur transcript→fixture (logique pure + FP par rejeu dans l'API locale d'événements).

PRÉREQUIS : aucun bloquant (autonome). L'API locale d'événements (ingestion des fixtures JSON hooks) existe déjà. Branche depuis develop.

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (logique pure de conversion + sélection des événements retenus), /agentic-tests (FP : rejeu du fixture produit dans l'API locale, assertion de l'état Session publié).

Avant TOUT code, lis : (1) l'issue #20 en entier, (2) `CONTEXT.md` (vocabulaire hook / événement / fixture / Session) + `docs/adr/*` de la zone ingestion si présent, (3) le format attendu par l'API locale `Sources/island/HookEventHandler.swift` (schéma JSON des événements acceptés), (4) un fixture existant `Tests/islandTests/Fixtures/*.json` (forme cible), (5) les patterns d'outillage/CLI Swift déjà présents dans le repo (`Sources/` ou `Scripts/`, à grepper), (6) la slice qui a posé l'API d'événements (PR de référence) pour l'ordre et la forme des hooks.

Séquence : /git-flow (branche depuis develop) → AUDIT PRÉALABLE (impact + cascade : un transcript réel contient plus d'événements que le fixture n'en retient ; ordre chronologique à préserver ; champs sensibles à ne pas embarquer) → plan montré → /tdd (convertisseur) → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #20) → `swift build` + `swift test` verts sur le diff → commit/push + PR vers develop. Arrête-toi à la PR.

Périmètre : (1) RUNBOOK `docs/runbooks/` décrivant : où Claude Code écrit les transcripts hooks, comment Loic les récupère, puis l'appel au script. (2) CODE NEUF `Scripts/transcript-to-fixture.swift` (ou l'emplacement d'outillage retenu) : lit un transcript brut, sélectionne les événements hooks pertinents (logique pure testée `selectHookEvents`/`toFixtureEvent`), émet un fixture JSON conforme au schéma de l'API locale, chronologie préservée, aucun champ sensible embarqué. Décisions figées : PAS de flag (outil ops) ; PAS de dépendance réseau (conversion locale de fichiers) ; le fixture produit doit être rejouable tel quel par `/agentic-tests`. Français pour les docs/issues, anglais pour le code et les identifiants.
```

---

## Ce qui distingue un bon prompt d'un mauvais

- **Titre recopié à l'identique** (pas paraphrasé).
- **PRÉREQUIS actionnable** : un « vérifie que X est mergé, sinon STOPPE » vaut mieux qu'un
  « dépend de X ».
- **« lis » ciblé** (4-6 pointeurs portants), pas un annuaire. Chaque pointeur gagne sa place
  parce qu'il cache un piège (couplage, invariant, cascade) qu'une session neuve ignorerait.
- **Périmètre = décisions figées + gardes**, pas une reformulation de l'AC. Il empêche la
  session de rouvrir un débat déjà tranché.
- **Séquence intouchée** : c'est le standard non-négociable (`swift build` + `swift test`
  verts avant la PR ; arrêt à la PR).
- **Non-négociable de fin** : français pour les docs/issues, anglais pour le code et les
  identifiants.
