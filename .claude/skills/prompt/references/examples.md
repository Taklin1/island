# Exemples de référence (calibration)

Deux prompts réels, à utiliser comme étalon de ton/densité/longueur. Un bon prompt **oriente
et pointe** ; il ne recopie pas l'issue.

---

## Exemple A - tranche de code AFK standard (PAS de bloc CADRAGE)

Issue #289 : durcissement d'une route, règle nette, dépend d'une slice précédente. Cas le
plus courant. Noter : pas de CADRAGE (tranche testable classique) ; PRÉREQUIS insiste sur la
dépendance non-mergée ; les « lis » ciblent ADR + route livrée par la slice-mère + glue +
`quota.ts` (couplage non-évident) + mémoires des slices sœurs + tests à étendre ; une piste
de deepening (prédicat pur) est suggérée dans le Périmètre.

```
Nouvelle session, projet Akutia. Tâche : implémenter l'issue GitHub #289 (Taklin1/briefy) - « Base de connaissances : durcissement - un membre parti ne peut plus muter le flag confidentiel d'une étude de son ancienne équipe ».

PRÉREQUIS ABSOLU : #225 (cas limites, PR #288) mergée sur develop - #289 s'appuie directement sur la route `/confidential` rendue équipe-aware par #225. Vérifie que #225 est bien sur develop AVANT de brancher ; sinon STOPPE et préviens-moi.

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (implémentation test-first rouge-vert-refactor), /agentic-tests (FP de la sous-issue avant PR).

Avant TOUT code, lis : (1) l'issue #289 en entier, (2) `docs/adr/0004-team-knowledge-base.md` (le savoir est un actif conservé de l'équipe ; membre retiré = « ancien membre »), (3) la route livrée par #225 `src/app/api/analysis/[id]/confidential/route.ts` (déjà : garde archived 403 + ownership + stamp chaîne), (4) `src/lib/team/knowledgeBase.ts` (`resolveTeamMembership`), (5) `src/lib/quota.ts` (comprendre que `analyses.team_id` pilote AUSSI le pool - ta garde ne touche QUE la route toggle, mais mesure l'impact), (6) les mémoires [[team-kb-225-edge-cases]] et [[team-kb-223-confidential]], (7) les tests `scripts/test/confidential-toggle-wiring.test.ts` + le réplica toggle de `scripts/test/knowledge-base-endpoint.test.ts`.

Séquence : /git-flow (branche depuis develop, #225 incluse) → carte « In progress » → AUDIT PRÉALABLE (impact + cascade : ordre des vérifs, réutiliser la membership déjà résolue pour l'archived afin d'éviter une 2e requête, lire `analyses.team_id` de la target) → plan montré → /tdd → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #289) → `npx prettier --write` sur le diff → commit/push + PR vers develop (« In review »). Arrête-toi à la PR.

Périmètre : dans `PATCH /api/analysis/[id]/confidential`, refuser 403 quand l'appelant n'est pas membre COURANT de l'équipe de l'étude - c.-à-d. `analyses.team_id` (figé, lu sur la target) est non-null ET ≠ équipe courante de l'appelant (`users.team_id`, via `resolveTeamMembership`, serveur-dérivée). Cas préservés inchangés : auteur toujours membre → autorisé ; étude solo (`team_id` null) → autorisé (no-op, byte-identique #223) ; équipe archivée → toujours 403 (garde #225, prioritaire). Ordre : flag 404 → auth 401 → id 400 → body 400 → archived 403 → appartenance 403 (NOUVEAU) → ownership 404 → update. Piste de deepening à évaluer dans le plan : extraire un prédicat PUR testable `canMutateStudyVisibility({callerTeamId, studyTeamId, archived})`. Mettre à jour `docs/adr/0004-team-knowledge-base.md`. Derrière `TEAM_KNOWLEDGE_BASE_ENABLED` (off = 404). Vouvoiement + accents, zéro em-dash.
```

---

## Exemple B - issue ops / outillage (AVEC bloc CADRAGE)

Issue #290 : runbook + script d'import. Le CADRAGE est nécessaire : il dit franchement que
les skills s'appliquent au **code produit** (script testable), pas à la mutation prod
(manuelle, via relais VPS), et il cadre le livrable (runbook + un seul script neuf). Les
« lis » incluent les patterns d'outillage existants (`team.ts`, `backfill-*.ts`) et les règles
crons/DB. Le Périmètre sépare explicitement le doc (runbook) du code (script + logique pure +
FP), et fige les décisions (pré-période only, pas de flag, pas de migration).

```
Nouvelle session, projet Akutia. Tâche : implémenter l'issue GitHub #290 (Taklin1/briefy) - « Runbook onboarding équipe (EDF) : create/attach/admin (team.ts existant) + script d'import sélectif des analyses solo dans la base ».

CADRAGE : le livrable = un RUNBOOK (`docs/runbooks/`) qui enchaîne l'onboarding équipe de bout en bout, + un SEUL code neuf : un script d'import dry-run-first testable. Les étapes 1-3 (créer/nommer l'équipe, ajouter les membres, désigner l'admin) réutilisent le CLI super-admin EXISTANT `scripts/team.ts` - tu les DOCUMENTES, tu ne les recodes PAS. Le code à /tdd + /agentic-tests = uniquement le script d'import (étape 4). La mutation prod reste MANUELLE via le relais Claude VPS (jamais toi, jamais `:5434`).

PRÉREQUIS : aucun bloquant (autonome). `team.ts` existe déjà. #225 mergée sur develop - branche depuis develop.

Skills à utiliser à minima : /git-flow (positionnement branche), /tdd (logique pure de sélection + garde fenêtre-pool du script), /agentic-tests (FP DB-jetable non-5434 du script).

Avant TOUT code, lis : (1) l'issue #290 en entier, (2) `docs/adr/0001-team-quota-architecture.md` + `docs/adr/0004-team-knowledge-base.md`, (3) `scripts/team.ts` (sous-commandes create/attach/set-role - pour documenter les étapes 1-3), (4) `src/lib/quota.ts` (`countTeamPoolUsed` : couplage `team_id` + `created_at >= periodStart` ; `teamPeriodWindow`), (5) `src/lib/team/{knowledgeBase,knowledgeBaseDerivation}.ts`, (6) la route confidentiel pour le pattern stamping de chaîne (`id = root OR root_analysis_id = root`), (7) les patterns backfill/CLI `scripts/backfill-fiche-summaries.ts` + les invariants `.claude/rules/{scripts-crons,database}.md`, (8) les mémoires [[fp-throwaway-postgres-cluster]], [[local-5434-is-prod-vps-forward]], [[vps-claude-relay]], [[team-admin-163]].

Séquence : /git-flow (branche depuis develop) → carte « In progress » → AUDIT PRÉALABLE (impact + cascade : `team_id` pilote base ET pool ; attacher ≠ importer ; parité `teamPeriodWindow` dupliquée côté scripts ; stamping chaîne entière) → plan montré → /tdd (script d'import) → AUDIT APRÈS impitoyable et factuel → /agentic-tests (FP #290) → `npx prettier --write` sur le diff → commit/push + PR vers develop (« In review »). Arrête-toi à la PR.

Périmètre : (1) RUNBOOK `docs/runbooks/` chaînant `team.ts create` (nommer) → `team.ts attach --role admin|member` (membres + admin) → `team.ts set-role` → le script d'import, avec « attacher ≠ importer » explicité. (2) CODE NEUF `scripts/import-analyses-to-team.ts` : dry-run par défaut (études importables = solo + completed + non-drill-down + chaîne ENTIÈREMENT pré-période `max(created_at) < periodStart` → zéro impact pool ; période-courante listée séparément, jamais stampée en silence) ; `--apply --root <id>...` stampe TOUTE la chaîne (scopé `user_id`), uniquement les roots passés ; garde dure anti-`:5434` ; periodStart via jumeau pur de `teamPeriodWindow` (parité commentée) ; logique pure testée `selectImportableChains`/`isChainFullyPrePeriod`. FP DB-jetable non-5434 : pré-période importée (apparaît via `deriveFiches`), période-courante intacte, `countTeamPoolUsed` réplica inchangé. PAS de flag (outil ops). PAS de migration (le marqueur `pool_exempt` reste différé). Nouveau script + tests ajoutés au `files[]` de `scripts/tsconfig.json`. Aucune exécution prod par toi. Vouvoiement + accents, zéro em-dash.
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
- **Séquence intouchée** : c'est le standard non-négociable.
- **Non-négociables de fin** : flag off = byte-identique + vouvoiement/accents/zéro em-dash.
